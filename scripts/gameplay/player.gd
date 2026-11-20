extends CharacterBody2D
## M0 手感灰盒 · 玩家。
##
## 招式通过 configuration.gd 从 assets/data/battle.json 注入。
##
## 四条必须守住的规矩：
##   1. Hitstop 自己数帧，绝不用 Engine.time_scale（设计文档 §2.3）
##   2. 击退用 move_and_collide() 手动积分，不用 RigidBody2D（§2.1 / §9.4）
##   3. 输入采样在 hitstop 判定【之前】，否则顿帧期间按的键会丢
##   4. 出招期间【不锁移动】—— 锁住会立刻变成"站桩游戏"，手感全废
##
## 类型说明：preload 出来的类型在每个脚本里各是一份，所以不要把 MoveDefinition
## 当成跨脚本的接口类型用。跨脚本传招式资源统一用 Resource / 无类型 Array。

signal move_started(move: Resource, index: int)
## 挥刀音效提示：在判定帧前 swing_cue_lead_frames 帧发出（刀风音效的峰值在 0.05 秒，
## 提前 3 帧发声，耳朵听到的“唰”正好落在刀光出现的那一帧）
signal swing_cue(move: Resource, index: int)
signal hit_confirmed(target: Node2D, move: Resource, point: Vector2)
## 伤害窗口打开（一招里真的开始能打到人的那一帧，每招只发一次）。
## 11-03 重击：大范围重击的伤害只在判定段末尾，刀光要在"窗口打开"时铺开，而不是等打中了才画。
signal damage_window_opened(move: Resource)
signal landed()
signal jumped(is_double: bool)
## 打中返还了一次空中跳（stock = 现在存着几次返还的空中跳）
signal air_jump_refunded(stock: int)
signal charge_started()
signal charge_released(frames: int, charged: bool)
signal ranged_fired(projectile: Node)
## 被打死。只有 can_die = true 时才可能发出（PVE 里玩家不会死，见 can_die 的注释）。
## PVP 靠这个信号判回合胜负。
signal died()
## 自己撞墙吃了二次伤害。PVP 靠它做"撞墙"播报和震屏 ——
## 玩家的撞墙以前只有画面反馈、没有对外事件，PVP 的记分需要它。
signal wall_slam(impact_speed: float, damage: float, point: Vector2)
## 弹刀成功：把来招弹开了。attacker = 打我的人（它已经被后仰硬直）。
##
## 【为什么把 attacker 一起发出来】表现层要在"打我的那个人"身上落火花/音效，
## 而 take_hit 只把 attacker 交给了防守方 —— 不转发出去，外面永远拿不到。
signal parry_success(attacker: Node, point: Vector2)
signal block_success(attacker: Node, point: Vector2)
## 试玩版：S+J 下砸落地（表现层拿去放冲击尘土/震屏）
signal plunge_landed(point: Vector2)
## 大招「绝影 · 鸦羽止」（10-31 按整段预览 13 改，见 docs/大招-全程过场-规划.md）：发动（全场定住）→ 开场领域展开
## → 睁眼 + 挥刀视频 → 回到游戏地图斩（ult_arrive）→ 整条街沿线错开、影全部斩开（ult_strike）→ “咔”收刀（ult_reveal）→ 收（ult_finished）
signal ult_started()
## 大招期间每帧（关卡据此推进定格 / 斩开；不依赖关卡自己的 _physics_process）
signal ult_tick()
signal ult_strike(index: int, count: int)
signal ult_arrive()
## “咔”收剑的那一帧
signal ult_reveal()
signal ult_finished()
## 2 格残影池变化（current = 当前可用格数，maximum = 上限）
signal shadow_changed(current: int, maximum: int)
## 6 帧高速穿身短闪起手
signal short_dash_started(direction: int, origin: Vector2)
## 极限掠影闪避：擦着敌人出刀帧瞬步穿过，当场返还 1 格残影并赋予瞬发完美重击
signal perfect_dodge_triggered(attacker: Node2D, point: Vector2)
## 1A 半空智能索敌「追影冲刺」起手
signal shadow_pursuit_started(target: Node2D, destination: Vector2)
## 瞬发完美重击就绪态变化（弹刀成功 / 极限闪避后窗口）
signal flash_heavy_ready_changed(ready: bool)
## 紫电锋芒就绪态变化（穿敌绕背 / 极限闪避 / 精准弹刀 / 浮空影镖钉滞点亮；单点 J 直出真强普）
signal keen_edge_ready_changed(ready: bool)
## J + K 轻重派生终结技起手（stage: 1=升龙挑月, 2=穿云破阵, 3=断岳崩裂）
signal combo_finisher_triggered(move: Resource, stage: int)

const InputBuffer := preload("res://scripts/core/input_buffer.gd")
const Timeline := preload("res://scripts/core/animation_timeline.gd")
const ProjectileScene := preload("res://scenes/actors/projectile.tscn")

enum State { NEUTRAL, ATTACK, LAUNCHED, DOWN, DEAD }

## 方向终结（试玩版，docs/HANDOFF-试玩版.md §7）：空中出刀时方向键决定把敌人送去哪。
##   &"slam"  = 空中 S+J：直接出空中终结刀，自己急坠，把敌人砸向地面（落地反弹 + 冲击波连锁）
##   &"drive" = 空中第三刀时按住前：横斩，把敌人水平打飞（撞墙 / 撞人连锁）
##   &""      = 普通
## 敌人在 take_hit 里通过 attacker.combat_intent() 读取。
var finisher_intent: StringName = &""
## 下落攻击的速度（11-03 用户：“速度改成几乎瞬移”）：直接以恒定高速往下砸，不吃重力、不吃下落速度上限。
##
## 【为什么是 5200】每帧位移 ≈ 5200/60 ≈ 87 px，正好是角色碰撞胶囊高度（168）的一半，
## 再快 move_and_slide 就可能一帧穿过薄地板。这个速度从 355 px 的跳跃顶点砸到地面约 4 帧，看起来就是瞬移。
const PLUNGE_SPEED := 5200.0
## 见 _clamp_root_motion。试玩场景设为 &"shade"。
var root_motion_block_group: StringName = &""
## 见 _process_attack 的 recovery 分支。试玩场景设为 true。
var launcher_cancel: bool = false
const ROOT_MOTION_CONTACT := 40.0
## 判定盒向下多给一截（像素）。空中追打时敌人常常已经在脚底以下，原判定盒下沿正好卡在脚底，
## 于是「人明明跳起来压着它，却一刀不中」。34 px 约等于半个身子，够擦到，又不会打到脚下好几层。
const MELEE_VERTICAL_FORGIVENESS := 34.0
## 空中出刀再往下多给一截：空连时玩家一跳（355）常常直接高过被打飞的敌人，
## 原来的盒子全都长在脚底以上，于是「人在它上面砍，砍不到」。144 px 向下 =
## 玩家最多高出敌人 200 左右还能砍到；街道楼层间距 335，不会隔着楼板打到下一层。
const MELEE_AIR_DOWN_REACH := 110.0
## 判定盒往身后多盖一截（11-08 用户：“在空中很容易模型重合但是还是打不到人”）：
## 招式盒子都从身前十来像素才开始，敌人中心只要落到她身后一点点就打不中，空连飞过头时最常见。
## 现在盒子后沿盖到身后这么远；和她身体重合、身后不到一个身位的敌人都算打中（击退仍朝她面向）。
const MELEE_BACK_REACH := 40.0
## 刀光判定放大（11-08 用户：“刀光范围直接搞大点”“改主角刀光，判定包括自己”）：
## 每一招的盒子前沿离她中心的距离、上下高度都放大这么多倍（招式数据里的盒子不改）……
const MELEE_REACH_SCALE := 1.25
## ……并且一定把她自己整个身体（受击盒 50×156）包进去，四周再多这么多：
## 跟她模型重合、贴在头顶脚边、身后半个身位的敌人都砍得到。
const MELEE_BODY_MARGIN := 30.0

const TRACKED_ACTIONS: Array[StringName] = [
	&"jump", &"attack_light", &"attack_ranged", &"aim_up",
	&"move_left", &"move_right", &"parry", &"dash_modifier", &"move_down", &"ult",
]
const AXIS_ACTIONS: Array[StringName] = [&"move_left", &"move_right", &"aim_up", &"move_down"]
## J 连续按住多少帧才认定是"蓄力"而不是"点按"。
## 默认 10 帧约 167ms；这个门槛由修改器配置，点按立即出刀。
@export var hold_to_charge_frames: int = 10
@export var foot_offset: float = 84.0
@export var acceleration: float = 4800.0
## 刹车 / 反向时的减速度（地面）。比加速度大，松手就停、不打滑。
@export var deceleration: float = 4800.0
@export_range(0.0, 1.0) var charge_movement_scale: float = 0.85
## 蓄力斩出招（松手之后）前摇 + 判定时的移速倍率，后摇不减速。11-01 用户：“攻击的时候移速大幅降低”“后摇不要减速了”；蓄力姿态本身仍用上面那个。
@export_range(0.0, 1.0) var charge_attack_movement_scale: float = 0.3
@export_group("空中追击")
@export var uppercut_input_frames: int = 12
@export var hit_fall_slow_frames: int = 12
@export_range(0.0, 1.0) var hit_fall_speed_scale: float = 0.45
@export_range(0.0, 1.0) var hit_fall_gravity_scale: float = 0.35
## 最大下落速度
@export var max_fall_speed: float = 2400.0
## 松开跳跃键后上升段的重力倍率（小跳）。只对真实键盘/手柄生效，
## 机器人和测试注入的输入一律视为"按满"，不会被误判成松键。
@export var jump_cut_gravity_scale: float = 1.0
## 空中连段悬停结束后的下落重力、被打飞时的重力。
## 和普通跳跃的下落重力分开：跳跃改快以后，空连和被击飞仍保持原来的滞空。
@export var air_attack_gravity: float = 1476.0
@export var knock_gravity: float = 1476.0
## 落差超过这个高度（像素）算"重落地"（播完整落地动作 + 重落地音效）。下砸一律算重落地。
@export var heavy_landing_height: float = 260.0
## 重落地后的落地硬直（物理帧）：期间走路很慢，但跳跃/出招/弹刀随时可以取消。
@export var heavy_landing_lag_frames: int = 0

@export_group("阵营 / 输入（PVP 用；PVE 时全部保持默认值 = 零影响）")
## 按键表后缀。"" = P1（A/D/W/S/J/K）；"_p2" = P2（方向键 + 小键盘）。
##
## 【为什么用后缀而不是两套招式代码】本文件内部所有招式判定用的都是【不带后缀】
## 的动作名（&"attack_light" / &"jump" …），后缀只加在"采样真实键盘"那一步，
## 采完再剥掉。于是同一份状态机可以同时驱动键盘 P1、键盘 P2、机器人、将来的回放，
## 而 _resolve_attack_command 这类招式逻辑一行都不用改。
## 详情见 docs/关卡与PVP架构.md §4。
@export var action_suffix: String = ""
## 外部输入源：任何带 poll_frame(owner) -> InputBuffer.Frame 的对象。
## 有它就完全替代键盘（机器人 / 回放用）。见 scripts/logic/bot_input.gd。
var input_source: Object = null
## 阵营号。0 = 玩家方；1..n = 敌对（PVP 里 P2 是 1）。
## 【注意】近战"只打身前"的判定不看阵营，只看 hit_mask 命中谁 ——
## 阵营只用于记分和胜负，不参与命中过滤（这样代码里没有第二套过滤逻辑）。
@export var team: int = 0
## 近战判定盒的碰撞 mask。PVE = 4（只打怪）；PVP = 12（怪 + 对手受击盒）。
@export var hit_mask: int = 4
## 远程弹丸的 mask。PVE = 5（地形 + 怪）；PVP = 13（再加对手受击盒）。
@export var ranged_hit_mask: int = 5
## 自身受击盒所在层。P1 = 2，P2 = 8。层号是数据不是硬编码（架构文档 §6）。
@export var hurt_layer: int = 2
## 能不能被打死。
## 【默认 false 是刻意的】M0 的约定是"木桩不会还手，玩家不该死"，
## 打空血只倒地然后回 1 点血 —— 现有的 108+85 项手感测试依赖这个行为。
## PVP 必须分胜负，所以由 PvpRules 把这一项打开。
@export var can_die: bool = false
## 受击无敌帧（PVP 复活保护）。每帧自减。
@export var invuln_frames: int = 0
## 倒地（DOWN）会额外补这么多帧无敌 —— 即"倒地 + 起身"是连续的一段无敌窗口。
##
## 【为什么它是关卡数据，而不是写在 _enter_down 里的常量】PVE 里 can_die=false，
## 血打空只倒地、26 帧后回 1 点血，但【倒地期间并不免疫伤害】。于是被 2~3 只怪
## 围住时会形成死循环：倒地 → 26 帧内再吃一下 → 又倒地 → …… 玩家从头到尾
## 拿不到任何一次出招机会。固定种子的机器人试玩实测到 1/4 的种子出现
## "击杀 0 / 撞墙 0 / 连击 0、剩余血量恒为 1%" —— 就是被这个循环锁死的。
##
## 这是"围殴下的生存窗口"，属于难度设计：教学关该给得宽（30 帧），
## 挑战关要收窄（14 帧）。所以它由 .tres 的 tuning 决定：
##   "player.getup_invuln_frames": 30
## 默认 0 = 保持 M0 行为完全不变（既有的 108+85 项手感测试不受影响）。
@export var getup_invuln_frames: int = 0
## 自己【打出】的伤害倍率。写进 take_hit 的 damage_mul。
##
## 【为什么需要它而不是改招式数据】PVP 的"突然死亡"要求双方伤害一起放大，
## 而 MoveDefinition 是两个玩家共用的同一份资源 —— 改它会波及 PVE 和对手。
## 把倍率挂在攻击者身上，"谁打得更痛"就变成一个 per-角色 的运行时属性。
@export var attack_damage_mul: float = 1.0
## 蓄力速率倍率（charge_boost 道具写它）
@export var charge_rate_scale: float = 1.0

@export_group("身份色")
## 剪影上那块饱和色。PVP 里 P2 换成另一色，玩家才能一眼分出"哪个是我"。
## 默认值 = palette.gd 的 IDENTITY_P1，所以 PVE 表现完全不变。
@export var identity_color: Color = Color(0.184, 0.878, 0.816)
@export var identity_light: Color = Color(0.498, 0.961, 0.941)
@export var identity_dark: Color = Color(0.106, 0.612, 0.565)

@export_group("移动")
@export var speed: float = 450.0
@export var jump_height: float = 151.0
@export var jump_time_to_peak: float = 0.28
@export var jump_time_to_descent: float = 0.20
@export var air_control: float = 0.75
## 空中可再跳几次（1 = 二段跳）
@export var extra_air_jumps: int = 1
## 二段跳相对首跳的力度。略小一点，落地更干脆
@export var double_jump_scale: float = 0.92
## 地面招式（冲刺斩 / W+J）返还空中跳：每打中这么多下 → +1 段。
## 11-02 默认给地面冲刺斩关掉（0 = 不给）：空中已经「每中一下给一段」，地面再给就是双份。
## 想恢复就把这个数改回 2。
@export var air_jump_refund_hits: int = 0
## W+J 上挑打中返还空中跳（11-02 用户：“W+J 空中冲刺斩给”）：默认 1 = 挑中一下就给一段，
## 因为它就是把敌人挑上天的那一招，不给跳就得靠提前起跳才追得上。0 = 关。
@export var launcher_refund_hits: int = 1
## 空中打到人返还空中跳（11-02 用户：“空中打到人能多一段跳”）：空中三连 / 空中上挑 / 下砸 / 横扫
## 每打中这么多次 → +1 次空中跳。默认 1 = 空连每命中一下就给一段，空连才追得住被打飞的敌人。
@export var air_hit_refund_hits: int = 1
## 返还的空中跳最多同时存几次（另算在 extra_air_jumps 之外；落地清零）
@export var air_jump_refund_max: int = 3
## 出招期间的水平移速倍率。不是 0 —— 出招能走位是这个手感的关键
@export var attack_move_scale: float = 0.62
## 单向平台所在的物理层（试玩关卡的多层地形，见 scripts/night/terrain.gd）。
## 站在这种平台上按 S（或 S + 跳）= 往下穿过平台（不消耗跳跃次数）。0 = 场景里没有单向平台
@export var one_way_mask: int = 0

@export_group("容错（设计文档 §2.4）")
@export var coyote_frames: int = 6
@export var jump_buffer_frames: int = 6
## 连段输入窗口：后摇期间提前按键仍能接上下一段
@export var attack_buffer_frames: int = 8
## 打完一招后多久内再按 J 还算"同一条连段"。超过就从头起手
@export var combo_keep_frames: int = 36

@export_group("击退 / 受击")
@export var gravity_scale_launched: float = 1.35
@export var wall_restitution: float = 0.30
## 撞墙伤害全局缩放。设计文档的 0.5/0.8 是无量纲比例，
## 撞墙速度是 px/s，直接当伤害会秒杀，所以再乘这个配平值。
@export var wall_damage_scale: float = 0.15
@export var min_wall_impact_speed: float = 90.0
@export var max_hp: float = 100.0
## 轻击退阈值（第四轮，疯狂小人式“挨一下就能动”）。击退速度低于它的受击
## 落地后直接站稳（不倒地），并给 soft_recover_invuln 帧无敌。0 = 关（默认，旧行为不变）。
@export var soft_knock_threshold: float = 0.0
@export var soft_recover_invuln: int = 12
## 真正被打倒（重击 / 挑飞）后躺多少帧
@export var hard_down_frames: int = 26

@export_group("招式表")
## 无类型 Array：元素必须是 move_definition.gd 的实例（由 main.gd 从 .tres 注入）
@export var light_combo: Array = []
## 第三段点按 J 出的"强化普攻"（连段的终点 / 蓄力斩）
@export var charge_move: Resource
## K 键的远程弹丸数据
@export var ranged_move: Resource
@export var up_strike_move: Resource
@export var air_up_move: Resource
## L 键的招架（弹刀）。判定帧内被打到 → 弹开来招、自己不吃伤害。
## 窗口有多宽由 data/moves/parry_1.tres 的 active_frames 决定。
@export var parry_move: Resource
@export var air_combo: Array = []
@export var dash_move: Resource
@export var dash_left_move: Resource
## 空中冲刺斩的独立招式（11-03 用户：“空中冲刺斩我也希望当成单独动作”）。为空时退回用地面冲刺斩。
@export var air_dash_move: Resource
@export var air_dash_left_move: Resource
## 下落攻击的独立招式（11-03 用户：“下落攻击我希望有单独动作模组”）。为空时退回用空中第三刀（旧行为）。
@export var air_plunge_move: Resource
@export var guard_reactions: Array = []
@export var parry_reactions: Array = []

@export_group("远程")
## 弹丸飞行速度 px/s
@export var ranged_speed: float = 940.0
## 弹丸存活帧数上限
@export var ranged_life_frames: int = 90
## 发射点相对玩家的偏移
@export var ranged_offset: Vector2 = Vector2(40.0, -6.0)

@export_group("空中攻击")
## 每次离地默认只能空中 J 一次；K 或第三段命中后返还一次。
@export var air_light_uses: int = 1
## 一次腾空能放几次冲刺斩（11-01 用户：“冲刺斩希望能在天上用”），落地回满
@export var air_dash_uses: int = 1
## 空中冲刺斩无限用（11-03 用户：“空中冲刺斩在空中能无限使用应该”）：打开后不看 `air_dash_uses`，
## 只要人在空中就能一直放。想恢复次数限制，把这个开关关掉（或在 battle.json 里设 airDashUnlimited: false）。
@export var air_dash_unlimited: bool = true

@export_group("残影与短闪")
## 2 格残影池（A1）：冲刺斩与 6 帧穿身短闪各耗 1 格；精准弹刀直接回满，破壳 / 击杀各回 1 格，平时慢速自然充能。
@export var max_shadow_charges: int = 2
var shadow_charges: int = 2
@export var shadow_regen_seconds: float = 3.0
var _shadow_regen_timer: float = 0.0
@export var shadow_cost_enabled: bool = true
## 6 帧干脆穿身短闪（A1）：高速穿身，任意后续帧可自由出刀 / 跳跃 / 弹刀取消。
@export var short_dash_frames: int = 6
@export var short_dash_speed: float = 1650.0
var _short_dash_ticks: int = 0
var _short_dash_dir: int = 1
## 「瞬步穿锋 · 追影重斩」(1A) 战斗重设计开关：实战场景开启，M0 木桩训练场保持 false 以 100% 兼容旧测试契约
@export var combat_rework_enabled: bool = false
## 无限闪开关：开启后地面/空中瞬步、追影冲刺及冲刺派生完全零残影消耗、无限连闪
@export var unlimited_dash: bool = false
@export var step_dash_frames: int = 7
@export var step_dash_speed: float = 2150.0
@export var pursuit_range_x: float = 480.0
@export var pursuit_max_distance: float = 540.0
@export var pursuit_frames: int = 6
@export var heavy_full_charge_frames: int = 25
@export var heavy_tap_threshold_frames: int = 6
@export var flash_heavy_duration: float = 1.25
@export var keen_edge_duration: float = 1.8
@export var rework_ranged_cooldown_frames: int = 66
## 实战普攻连段续接窗口（帧）：被打断 / 瞬步 / 弹刀 / 走位 / 挥空后在此窗口内再按 J，接着下一刀继续砍
@export var rework_combo_keep_frames: int = 240
var flash_heavy_timer: float = 0.0
var keen_edge_timer: float = 0.0
var _keen_swing_active: bool = false
var _keen_cross_locks: Dictionary = {}
var ranged_cooldown: int = 0
var combo_k_launch_move: Resource = null
var combo_k_pierce_move: Resource = null
var combo_k_pierce_left_move: Resource = null
var combo_k_cleave_move: Resource = null
var _rework_next_light: int = 0
var _rework_combo_timer: int = 0
var _rework_next_air: int = 0
var _rework_air_combo_timer: int = 0
var _post_dash_window: int = 0
var _post_dash_was_pursuit: bool = false
var _pursuit_target: Node2D = null
var _pursuit_offset: Vector2 = Vector2.ZERO
var _dash_preserving_charge: bool = false
var _dash_passed_enemy: Node2D = null
var _perfect_dodge_locks: Dictionary = {}
var _charge_action: StringName = &"attack_light"
var _heavy_hold_frames: int = 0
var _air_normal_hit_chain: int = 0
var _air_a4_braked_this_flight: bool = false
var _hit_recoil_x: float = 0.0
var _hit_recoil_vel_x: float = 0.0

@export_group("大招（第四轮）")
## 能量满后 J、K 在 ult_chord_frames 帧内先后按下（或同时按）→ 大招。默认关（训练场 / PVP 不受影响）。
@export var ult_enabled: bool = false
@export var ult_max: float = 100.0
@export var ult_chord_frames: int = 6
## 「绝影 · 鸦羽止」（10-31，整段预览 18）。时间轴（60 帧 / 秒，和 UltFullPreview18 一致）：
##   0～ult_vanish_frame：开场领域展开（全场定住，镜头升起成墙角，墨铺满世界，黑屏），她原地居合架势
##   ult_vanish_frame～ult_calm_start：睁眼 + 挥刀视频，这段她不在场上（ult_hidden）
##   ult_calm_start：回到游戏地图斩，她还在原地（关卡给 ult_stand_pos），发 ult_arrive；斩线射出、时停
##   ult_cut_frames：断开——整条街沿斩线错开，屏幕里的影全部斩开（发 ult_strike(i, n)）
##   （11-01 预览 22c 进游戏：刀尖出画后的时停 16 → 6 帧，断开 188 → 178，“咔” 228 → 214，总长 282 → 270）
##   ult_final_frame：“咔”——收刀，世界合回去，发 ult_reveal；影子退潮，到 ult_total_frames 结束
@export var ult_total_frames: int = 276     ## 正常放完的总长；测试和无敌帧按它算（11-01 预览 26×2b：甩出慢放 2 倍，地图斩往后 4 帧）
@export var ult_vanish_frame: int = 66
@export var ult_cut_frames := PackedInt32Array([182])
@export var ult_calm_start: int = 162
@export var ult_final_frame: int = 222
@export var ult_freeze_frames: int = 0
@export var ult_damage: float = 50.0

@export_group("手感表现")
@export var squash_strength: float = 1.0

var state: State = State.NEUTRAL
var facing: int = 1
## Stable presentation interface; facing remains the combat/hitbox direction.
var input_direction: int = 0
var movement_direction: int = 0
var display_facing: int = 1
var locomotion_animation: String = ""
var locomotion_clock: float = 0.0
var locomotion_frame: int = 0
var locomotion_source_facing: int = 1
var air_combo_index: int = 0
var air_suspend_used: int = 0
var guard_animation: String = ""
var guard_clock: float = 0.0
var action_serial: int = 0
var ult_energy: float = 0.0
var ult_frame: int = -1          ## ≥0 = 正在放大招（第几帧）
## 大招期间角色显示哪段动画、第几帧（character_view 读；空 = 不管）
var ult_clip: String = ""
var ult_pose: int = -1
var ult_from_x: float = NAN      ## 起手时站在哪（表现层用）
var ult_cut_pos := PackedVector2Array()      ## 三刀出刀位置（关卡在 ult_started 里给；没给就在身前摆一个默认三角）
var ult_cut_face := PackedInt32Array()       ## 三刀出刀时朝哪边
var ult_stand_pos: Vector2 = Vector2.INF     ## 站定位置（敌群另一头的地面）
var ult_stand_face: int = 1
var ult_hidden := false          ## 大招里她“消失”的那几段（表现层据此隐藏角色）
## 大招里她用哪张定格图（表现层画；空 = 用平常的角色帧）：&"iai" 居合架势 / &"zanshin" 低位收势 / &"sheathed" 收剑
var ult_body: StringName = &""
var _ult_move: Resource = null
var _ult_used_seq: int = -1      ## 已经用掉的那对 J/K 按键（防止同一次按键放两次）
var _soft_knock := false   ## 这次被击退是轻击（落地直接站稳）
var action_idle_frames: int = 0
var _turn_target: int = 1
var _turn_clip: Dictionary = {}
var _turn_options: Dictionary = {}
var _guard_active: bool = false
var _guard_frames: int = 0
var _guard_parried: bool = false
var _guard_variant: int = 0
var _parry_variant: int = 0
var _dash_facing: int = 1
var _pending_dash_direction: int = 1
var _air_dash_left: int = 1
var _dash_in_air: bool = false      ## 这一发冲刺斩是空中起手的：冲刺段不吃重力（平着冲出去）
## 空中冲刺斩砍中的第一只敌人：穿到它另一侧就停（见 _try_dash_cross_stop）
var _dash_cross_target: Node2D = null
## 已经停在敌人另一侧了：这一招只剩落地
var _dash_stopped: bool = false
## 双击方向出冲刺斩（11-03 用户：“冲刺斩改成 aa 或 dd”）：两次按下相差多少帧内算双击
@export var double_tap_frames: int = 14
## 已经用掉的那一次双击（存第二下的 seq，避免同一次双击连着出好几发）
var _double_tap_seq: int = -1
var _reaction_guard_held: bool = false
var hp: float = 100.0
var hitstop_frames: int = 0
var hitstop_this_tick: bool = false
var parry_hitstop_frames: int = 3
var hitstop_multiplier: float = 1.0
var ground_frames: int = 0
var air_frames: int = 0
var down_frames: int = 0

var current_move: Resource = null
var move_frame: int = 0
## 这一招的挥刀音效提示发过没有（每招只发一次）
var _swing_cued: bool = false
## 挥刀音效比判定帧提前几帧发出
var swing_cue_lead_frames: int = 3
var combo_index: int = 0
## 当前正在用的招式是不是"上挑/向上打"。命中判定要靠它决定浮空方向
var current_is_up: bool = false
var link_open: bool = false
var link_open_count: int = 0
## 当前这一刀有没有打到东西。挥空 → 连段归零（见 _end_attack）
var last_swing_hit: bool = false
## 距离上一招结束过了多少帧，用来判断连段是否已经"断太久"
var frames_since_attack: int = 100
## 蓄力中攒了多少帧（<0 表示不在蓄力）
var charge_frames: int = -1
## 蓄力量化后的比例 0..1，命中时用来放大伤害/击退/顿帧
var _charge_t: float = 0.0
## 蓄力速率的浮点累加器（见 _process_charge 的注释）
var _charge_accum: float = 0.0
## The new grounded release has an authored hop; airborne release keeps its jump.
var _charge_authored_hop: bool = false
var _charge_hop_started: bool = false
var _charge_hop_origin_y: float = 0.0

var input_buffer: InputBuffer

var _jump_velocity: float = -560.0
var _jump_rising: bool = false
var _jump_cut: bool = false
var _keyboard_frame: bool = false
var _peak_y: float = 0.0
## 最近一次落地：落差（像素）和是不是重落地。landed 信号发出前写好，音效/画面直接读。
var last_fall_height: float = 0.0
var last_landing_heavy: bool = false
var _landing_lag: int = 0
var _gravity: float = 1600.0
var _fall_gravity: float = 1600.0
var _jump_buffer_counter: int = 0
var _air_jumps_left: int = 0
var _refund_hits: int = 0           ## 地面冲刺斩 / 上挑：离上一次返还空中跳又打中了几下
var _refund_hits_air: int = 0       ## 空中招式：同上（和地面分开记，互不凑数）
var bonus_air_jumps: int = 0        ## 打中返还、还没用掉的空中跳
var _ground_jump_used: bool = false
var _uppercut_jump_pending: bool = false
var _uppercut_used_light_seq: int = -1
var _last_jump_frame: int = -1000
var _last_jump_from_up: bool = false
var _last_jump_is_uppercut: bool = false
var _space_was_held: bool = false
var _air_hit_slow_frames: int = 0
var _air_slow_hit_tick: int = -1
var _jump_buffer_tick: int = -1
var _frame_counter: int = 0
var _hit_this_swing: Dictionary = {}
## 这一招的「伤害窗口打开」事件发过了没有（每招只发一次，见 damage_window_opened）
var _damage_announced: bool = false
## 本招已经打中几次（换招清零）；穿透招式只在第 1 次顿帧，表现层据此减弱后续命中的震屏
var swing_hit_count: int = 0
var _squash_timer: int = 0
## 已消费的按键边沿记账：action -> 该边沿的 Frame.seq
var _consumed_edge: Dictionary = {}
## 蓄力招式一共持续了多少帧（测试用）
var last_charge_frames: int = 0
## J 已经连续按住了几帧（0 = 没按）。用来区分"点按普攻"和"按住蓄力"。
var _attack_hold_frames: int = 0
var _air_light_left: int = 1

## 物理帧计数器（只增不减）。测试用它测"一次 await 之间玩家跑了几次
## _physics_process"，从而把注入帧和真实帧对齐。
var tick_count: int = 0
## 注入队列：给"每一帧都是不同输入"的用例准备，每帧从队首取一帧。
var _frame_queue: Array[InputBuffer.Frame] = []
## 测试/回放注入的"粘住"帧：在测试明确换帧或清除之前一直有效。
##
## 为什么必须有它：注入方无法预知一次 await 之间玩家跑了几次 _physics_process。
## 若只注入一帧，多出来的那几次会回落到真实 Input（无头环境恒为空），
## "按住"就变成"已松开" —— 蓄力当场断掉、跳跃读不到边沿。
##
## 为什么不用"往队列里塞 N 份同一个 Frame"来顶：那样会多剩几份留在队列里，
## 在后续断言帧上重放出旧边沿。实测后果是二段跳被自动消耗掉
## （按下一次跳，紧接着的两个物理帧各自又跳了一次）。同一个 Frame 对象
## 固然让 seq 唯一，但边沿存在性本身在每帧都是 true —— 必须靠"粘住"而不是"排队"。
var _sticky_frame: InputBuffer.Frame = null

@onready var _visual: Node2D = get_node_or_null("Visual")
@onready var _hurtbox: Area2D = get_node_or_null("Hurtbox")
@onready var _melee: Area2D = get_node_or_null("MeleeHitbox")
## 近战判定盒在"面朝右"时的前伸距离（_ready 里从场景节点读，默认 52）。
## 翻面时用它乘朝向 —— 见 _sync_melee_offset()。
var _melee_base_offset_x: float = 52.0


## 测试/回放用：把一帧输入压进队列，玩家按 _physics_process 的次数依次消费。
func queue_input(frame: InputBuffer.Frame, copies: int = 1) -> void:
	for i in maxi(copies, 1):
		_frame_queue.append(frame)


## 测试/回放用：注入一帧并让它"粘住"，直到下一次 set_injected_frame / 清除。
## 这是逐帧驱动的主入口（_step_input 用它）。
func set_injected_frame(frame: InputBuffer.Frame) -> void:
	_frame_queue.clear()
	_sticky_frame = frame


## 测试/回放用：清空注入状态，回到真实 Input 采样。
func clear_input_queue() -> void:
	_frame_queue.clear()
	_sticky_frame = null


func _ready() -> void:
	# Room for a heavy hitstop at the editor's maximum 3x feedback setting.
	input_buffer = InputBuffer.new(128)
	hp = max_hp
	shadow_charges = max_shadow_charges
	_shadow_regen_timer = 0.0
	_ensure_short_dash_action()
	_recalculate_jump()
	up_direction = Vector2.UP
	if _visual != null:
		_visual.scale = Vector2.ONE
	# 记下场景里作者摆的判定盒前伸距离（absf 取正），翻面时以它为基准
	if _melee != null:
		_melee_base_offset_x = absf(_melee.position.x)
	_sync_melee_offset()
	apply_combat_identity()


func _ensure_short_dash_action() -> void:
	if action_suffix != "":
		return
	if not InputMap.has_action(&"attack_heavy"):
		InputMap.add_action(&"attack_heavy")
	if InputMap.has_action(&"short_dash"):
		return
	InputMap.add_action(&"short_dash")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_C
	InputMap.action_add_event(&"short_dash", key)
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_LEFT_SHOULDER
	InputMap.action_add_event(&"short_dash", pad)


## 把 hit_mask / hurt_layer / identity_color 刷到节点上。
## 单独成方法，是为了让 PVP 控制器能在运行中改阵营（换边 / 换人）。
func apply_combat_identity() -> void:
	if _melee != null:
		_melee.collision_mask = hit_mask
	if _hurtbox != null:
		_hurtbox.collision_layer = hurt_layer
	_apply_identity_color()


## 把身份色刷到剪影上。
##
## 【为什么按节点名找而不在场景里挂 NodePath】要换色的色块有 9 个，
## 挂 9 个 NodePath 导出会把场景文件搞得很脆（美术一改名就全空）。
## 用 get_node_or_null 按名字找、找不到就跳过，改动成本最低。
func _apply_identity_color() -> void:
	if _visual == null:
		return
	var paint := {
		"ChestPlate": identity_color,
		"ChestPlateEdge": identity_light,
		"ChestPlateShade": identity_dark,
		"EyeCore": identity_color,
		"FacingMark": identity_light,
	}
	for key in paint.keys():
		var n := _visual.get_node_or_null(NodePath(key)) as ColorRect
		if n != null:
			n.color = paint[key]
	var blade := _visual.get_node_or_null(^"Blade")
	if blade != null:
		var body := blade.get_node_or_null(^"BladeBody") as ColorRect
		if body != null:
			body.color = identity_color
		var edge := blade.get_node_or_null(^"BladeEdge") as ColorRect
		if edge != null:
			edge.color = identity_light
		var shade := blade.get_node_or_null(^"BladeShade") as ColorRect
		if shade != null:
			shade.color = identity_dark
		var trail := blade.get_node_or_null(^"BladeTrail") as ColorRect
		if trail != null:
			trail.color = Color(identity_color.r, identity_color.g,
					identity_color.b, 0.22)
	# 【判定跟着素材走之后这里必须跟上】真精灵剪影的身份色走的是
	# silhouette 着色器的 uniform，上面那些 ColorRect 早已被 v3_hide 藏掉 ——
	# 只刷色块 = PVP 里 P2 身体还是 P1 的青色（§8.6 遗留，2026-09 修复）。
	var sprite := _visual.get_node_or_null(^"ActorSprite")
	if sprite != null and sprite.has_method(&"set_identity_color"):
		sprite.call(&"set_identity_color", identity_color)


## 读角色配置里的移动参数（夜战和训练场共用这一份，免得两边各写一遍）。
func apply_movement_config(c: Dictionary, settings: Dictionary) -> void:
	acceleration = float(c.get("acceleration", 4800))
	deceleration = float(c.get("deceleration", acceleration))
	charge_movement_scale = clampf(float(c.get("chargeMovementScale", 0.85)), 0.0, 1.0)
	charge_attack_movement_scale = clampf(float(c.get("chargeAttackMovementScale", 0.3)), 0.0, 1.0)
	var air_combat: Dictionary = c.get("airCombat", {})
	uppercut_input_frames = maxi(1, int(air_combat.get("uppercutInputFrames", 12)))
	hit_fall_slow_frames = maxi(0, int(air_combat.get("hitFallSlowFrames", 12)))
	hit_fall_speed_scale = clampf(float(air_combat.get("hitFallSpeedScale", 0.45)), 0.0, 1.0)
	hit_fall_gravity_scale = clampf(float(air_combat.get("hitFallGravityScale", 0.35)), 0.0, 1.0)
	# 打中返还空中跳（11-02：空中打到人每一下都给一段）
	air_jump_refund_hits = maxi(0, int(air_combat.get("airJumpRefundHits", air_jump_refund_hits)))   # 0 = 地面招式不返还
	air_hit_refund_hits = maxi(1, int(air_combat.get("airHitRefundHits", air_hit_refund_hits)))
	launcher_refund_hits = maxi(0, int(air_combat.get("launcherRefundHits", launcher_refund_hits)))
	air_jump_refund_max = maxi(1, int(air_combat.get("airJumpRefundMax", air_jump_refund_max)))
	# 空中冲刺斩次数：11-03 起默认无限；battle.json 里写 airDashUses / airDashUnlimited 可以改回来
	air_dash_uses = maxi(1, int(air_combat.get("airDashUses", air_dash_uses)))
	air_dash_unlimited = bool(air_combat.get("airDashUnlimited", air_dash_unlimited))
	speed = float(c.get("speed", 186)) * float(settings.get("characterSpeedMultiplier", 1))
	air_control = float(c.get("airControl", 0.8))
	jump_time_to_peak = float(c.get("jumpTimeToPeak", 0.28))
	jump_time_to_descent = float(c.get("jumpTimeToDescent", 0.20)) / sqrt(float(settings.get("jumpGravityMultiplier", 1)))
	jump_height = float(c.get("jumpSpeed", 600)) * jump_time_to_peak * 0.5 * float(settings.get("jumpSpeedMultiplier", 1))
	extra_air_jumps = maxi(0, int(c.get("maxJumps", 2)) - 1)
	max_fall_speed = float(c.get("maxFallSpeed", 2400))
	jump_cut_gravity_scale = maxf(float(c.get("jumpCutGravityScale", 1.0)), 1.0)
	air_attack_gravity = float(c.get("airAttackGravity", 1476))
	knock_gravity = float(c.get("knockGravity", 1476))
	heavy_landing_height = float(c.get("heavyLandingHeight", 260))
	heavy_landing_lag_frames = int(c.get("heavyLandingLagFrames", 0))
	if is_inside_tree():
		_recalculate_jump()


func _recalculate_jump() -> void:
	_jump_velocity = -2.0 * jump_height / jump_time_to_peak
	_gravity = 2.0 * jump_height / (jump_time_to_peak * jump_time_to_peak)
	_fall_gravity = 2.0 * jump_height / (jump_time_to_descent * jump_time_to_descent)


## 采样真实键盘。action_suffix 为空（P1）时就是原样的一行，零开销。
##
## 加了后缀之后必须把动作名【剥回内部名】：输入缓冲里存的动作名要和
## _resolve_attack_command 里写死的 &"attack_light" 一致，否则 P2 永远出不了招。
func _sample_keyboard() -> InputBuffer.Frame:
	if action_suffix == "":
		var sampled := InputBuffer.sample(TRACKED_ACTIONS, AXIS_ACTIONS)
		# Space needs an independent edge when W already holds the jump action.
		var space_held := _pure_jump_down()
		if space_held and not _space_was_held and not sampled.pressed_this_frame.has(&"jump"):
			sampled.pressed_this_frame.append(&"jump")
		_space_was_held = space_held
		for extra_act in [&"short_dash", &"attack_heavy"]:
			if InputMap.has_action(extra_act):
				if Input.is_action_pressed(extra_act) and not sampled.actions.has(extra_act):
					sampled.actions.append(extra_act)
				if Input.is_action_just_pressed(extra_act) and not sampled.pressed_this_frame.has(extra_act):
					sampled.pressed_this_frame.append(extra_act)
		return sampled
	var tracked: Array[StringName] = []
	for a in TRACKED_ACTIONS:
		tracked.append(StringName(String(a) + action_suffix))
	for extra_base in ["short_dash", "attack_heavy"]:
		var ex_act := StringName(extra_base + action_suffix)
		if InputMap.has_action(ex_act):
			tracked.append(ex_act)
	var axes: Array[StringName] = []
	for a in AXIS_ACTIONS:
		axes.append(StringName(String(a) + action_suffix))
	var f := InputBuffer.sample(tracked, axes)
	for i in f.actions.size():
		f.actions[i] = _unsuffix(f.actions[i])
	for i in f.pressed_this_frame.size():
		f.pressed_this_frame[i] = _unsuffix(f.pressed_this_frame[i])
	return f


## “只是跳”的键按着吗：空格 / 手柄 A（InputMap 的 jump_pure）。W 同时是跳和上方向，不算——
## 按着它说明玩家只想跳，不是要 W+J 上挑。没注册这个动作的场景（单元测试）一律当没按。
func _pure_jump_down() -> bool:
	return InputMap.has_action(&"jump_pure") and Input.is_action_pressed(&"jump_pure")


func _unsuffix(a: StringName) -> StringName:
	var s := String(a)
	if s.ends_with(action_suffix):
		s = s.substr(0, s.length() - action_suffix.length())
	return StringName(s)


func _physics_process(delta: float) -> void:
	var paused_last_tick := hitstop_this_tick
	hitstop_this_tick = false
	_frame_counter += 1
	tick_count += 1
	if invuln_frames > 0 and hitstop_frames <= 0:
		invuln_frames -= 1

	# ---- 1. 取这一帧的输入（必须在 hitstop 的 return 之前！）----
	# 优先级：注入队列 > 粘住帧 > 真实 Input 采样
	var frame: InputBuffer.Frame
	_keyboard_frame = false
	if not _frame_queue.is_empty():
		frame = _frame_queue.pop_front()
	elif _sticky_frame != null:
		frame = _sticky_frame
	elif input_source != null:
		# 外部输入源（机器人 / 回放）。它每帧返回一个【新的】Frame，
		# 并自己负责"同一次按住只在第一帧给边沿"—— 见 bot_input.gd 的说明。
		frame = input_source.poll_frame(self)
	else:
		frame = _sample_keyboard()
		_keyboard_frame = true
	if frame == null:
		frame = InputBuffer.Frame.new()
	# Resume at age zero so the first actionable tick can use the entire
	# input window; this also keeps the active/recovery boundary inclusive.
	input_buffer.push(frame, hitstop_frames <= 0 and not paused_last_tick)
	var guard_held := bool(_guard_config().get("enabled", false)) and frame.actions.has(&"parry")
	if guard_held:
		# Consume attacks before hitstop and the ultimate check: held L never
		# stores a delayed J/K/dash/ultimate to fire when defense ends.
		_take_edge(&"attack_light")
		_take_edge(&"attack_heavy")
		_take_edge(&"attack_ranged")
		_take_edge(&"dash_modifier")
		_take_edge(&"short_dash")
		_take_edge(&"ult")
		_consumed_edge[&"attack_light_press"] = frame.seq
		_consumed_edge[&"attack_heavy_press"] = frame.seq
		_ult_used_seq = maxi(_ult_used_seq, frame.seq)
		_attack_hold_frames = 0
		_heavy_hold_frames = 0
	# 大招可以取消任何出招 / 自己的顿帧，所以放在顿帧前面判
	if ult_frame < 0 and ult_enabled and not guard_held:
		_try_ult()
	if ult_frame >= 0 or state in [State.DEAD, State.LAUNCHED, State.DOWN]:
		# Damage reactions and the ultimate reject jumps rather than queueing them.
		_jump_buffer_counter = 0
		_consumed_edge[&"jump"] = frame.seq
	elif not guard_held and _try_uppercut_input(frame):
		_process_attack(delta, frame)
		return
	elif _try_action_jump_cancel(delta, frame):
		return

	# ---- 2. Hitstop：冻结自己，不影响别人 ----
	if hitstop_frames > 0:
		if combat_rework_enabled and not guard_held and state == State.ATTACK and is_on_floor() \
				and last_swing_hit and flash_heavy_timer <= 0.0 and _has_edge(&"attack_heavy") and _combo_k_stage() > 0:
			hitstop_frames = 0
		else:
			hitstop_this_tick = true
			hitstop_frames -= 1
			# 空中停住位置但保留速度，恢复后继续原跳跃/击飞轨迹。
			if state != State.LAUNCHED and not is_guarding() and is_on_floor():
				velocity = Vector2.ZERO
			elif combat_rework_enabled and state == State.ATTACK and not is_on_floor() and current_move != null \
					and StringName(current_move.get(&"id")) in [&"air_light_1", &"air_light_2", &"air_light_3"] \
					and _air_normal_hit_chain >= 4 and velocity.y >= 0.0:
				velocity.y = minf(velocity.y + _fall_gravity * 0.55 * delta, max_fall_speed)
			_sync_visual_pivot()
			return

	_air_hit_slow_frames = maxi(_air_hit_slow_frames - 1, 0)
	_squash_timer = maxi(_squash_timer - 1, 0)
	if absf(_hit_recoil_x) > 0.05 or absf(_hit_recoil_vel_x) > 1.0:
		var recoil_acc := -520.0 * _hit_recoil_x - 30.0 * _hit_recoil_vel_x
		_hit_recoil_vel_x += recoil_acc * delta
		_hit_recoil_x = clampf(_hit_recoil_x + _hit_recoil_vel_x * delta, -24.0, 22.0)
		if absf(_hit_recoil_x) <= 0.08 and absf(_hit_recoil_vel_x) <= 2.0:
			_hit_recoil_x = 0.0
			_hit_recoil_vel_x = 0.0
		_sync_visual_pivot()
	if _squash_timer == 0:
		_lerp_visual_scale(0.18)
	_update_drop_through()

	# ---- 3. 地面/空中计数放在最前面 ----
	# 出招期间也要更新，否则"出招中能不能跳"的判断会用到过期数据。
	# 但跳跃缓冲的计数只在允许自由行动时消耗（见 _try_buffered_jump）。
	_update_ground_air()
	_update_jump_cut(frame)
	input_direction = int(signf(frame.axis.x)) if absf(frame.axis.x) > 0.15 else 0
	movement_direction = int(signf(velocity.x)) if absf(velocity.x) > 1.0 else 0
	_advance_locomotion(delta)
	if is_combat_action_active():
		action_idle_frames = 0
	else:
		action_idle_frames += 1
	# J 的"按住了几帧"计时器也必须每帧更新（含顿帧期间的输入）
	_update_attack_hold(frame)
	if state != State.DEAD and ult_frame < 0:
		_tick_shadow_regen(delta)
		if combat_rework_enabled and _rework_combo_timer > 0:
			if state in [State.LAUNCHED, State.DOWN]:
				_rework_combo_timer = maxi(_rework_combo_timer, 120)
			elif not (state == State.ATTACK and light_combo.has(current_move)) \
					and _short_dash_ticks <= 0 and not _guard_active:
				_rework_combo_timer -= 1
				if _rework_combo_timer <= 0:
					_rework_next_light = 0
		if combat_rework_enabled and _rework_air_combo_timer > 0:
			if state in [State.LAUNCHED, State.DOWN]:
				_rework_air_combo_timer = maxi(_rework_air_combo_timer, 120)
			elif not (state == State.ATTACK and air_combo.has(current_move)) \
					and _short_dash_ticks <= 0 and not _guard_active:
				_rework_air_combo_timer -= 1
				if _rework_air_combo_timer <= 0:
					_rework_next_air = 0
		if _post_dash_window > 0 and _short_dash_ticks <= 0:
			_post_dash_window -= 1
			if _post_dash_window <= 0:
				_post_dash_was_pursuit = false
				_dash_passed_enemy = null
		if flash_heavy_timer > 0.0:
			flash_heavy_timer = maxf(flash_heavy_timer - delta, 0.0)
			if flash_heavy_timer <= 0.0:
				flash_heavy_ready_changed.emit(false)
		if keen_edge_timer > 0.0:
			keen_edge_timer = maxf(keen_edge_timer - delta, 0.0)
			if keen_edge_timer <= 0.0:
				keen_edge_ready_changed.emit(false)
		if ranged_cooldown > 0:
			ranged_cooldown -= 1

	if ult_frame >= 0:
		_process_ult(delta, frame)
		return

	if state not in [State.LAUNCHED, State.DOWN, State.DEAD]:
		if not guard_held and _short_dash_ticks <= 0 \
				and (_try_rework_dash_input(frame) if combat_rework_enabled else _try_short_dash_input(frame)):
			_process_short_dash(delta, frame, true)
			return
		if _short_dash_ticks > 0:
			_process_short_dash(delta, frame, false)
			return

	# 蓄力是"招式之外的一个前置阶段"，所以优先于状态机分流
	if charge_frames >= 0:
		_process_charge(delta, frame)
		return

	match state:
		State.NEUTRAL:
			_process_neutral(delta, frame)
		State.ATTACK:
			_process_attack(delta, frame)
		State.LAUNCHED:
			_process_launched(delta)
		State.DOWN:
			_process_down(delta)
		State.DEAD:
			pass


func _update_ground_air() -> void:
	if is_on_floor():
		ground_frames += 1
		air_frames = 0
		_air_jumps_left = extra_air_jumps
		_ground_jump_used = false
		_air_light_left = air_light_uses
		_air_dash_left = air_dash_uses
		_air_hit_slow_frames = 0
		_air_normal_hit_chain = 0
		_air_a4_braked_this_flight = false
		var landing_peak := _peak_y
		# 站在地上时最高点 = 脚下，离地之后再往上记
		_peak_y = global_position.y
		if ground_frames == 1:
			# 落地清零返还的空中跳（地面冲刺斩打中攒下的留到下一次落地）
			_refund_hits = 0
			_refund_hits_air = 0
			bonus_air_jumps = 0
			last_fall_height = maxf(global_position.y - landing_peak, 0.0)
			last_landing_heavy = finisher_intent == &"slam" or last_fall_height >= heavy_landing_height
			_landing_lag = heavy_landing_lag_frames if last_landing_heavy else 0
			_jump_rising = false
			_jump_cut = false
			if finisher_intent == &"slam":
				finisher_intent = &""
				plunge_landed.emit(global_position + Vector2(0, foot_offset))
			if not air_combo.is_empty():
				if current_move != null and air_combo.has(current_move):
					_end_attack()
				_reset_air_combo()
			landed.emit()
	else:
		_landing_lag = 0
		_peak_y = minf(_peak_y, global_position.y)
		air_frames += 1
		ground_frames = 0
	frames_since_attack += 1


## 小跳：真实按键在上升途中松开 → 这一跳剩下的上升段用更大的重力。
## 注入/机器人输入（_keyboard_frame=false）一律按"按满"处理。
func _update_jump_cut(frame: InputBuffer.Frame) -> void:
	if velocity.y >= 0.0:
		_jump_rising = false
		_jump_cut = false
		return
	if _jump_rising and _keyboard_frame and not frame.actions.has(&"jump"):
		_jump_cut = true


## 自由行动时的重力：上升用起跳重力（松键小跳加大），下落用下落重力。
func _air_gravity() -> float:
	if velocity.y > 0.0:
		if _air_hit_slow_frames > 0 and finisher_intent == &"" and state != State.LAUNCHED:
			return _fall_gravity * hit_fall_gravity_scale
		return _fall_gravity
	if _jump_cut:
		return _gravity * jump_cut_gravity_scale
	return _gravity


# ---------------------------------------------------------------- NEUTRAL

func _process_neutral(delta: float, frame: InputBuffer.Frame) -> void:
	var started_guard := false
	if not _guard_active and bool(_guard_config().get("enabled", false)) \
			and (_has_edge(&"parry") or frame.actions.has(&"parry")):
		var precise := _has_edge(&"parry")
		_take_edge(&"parry")
		_start_guard(precise)
		started_guard = true
	if _guard_active and _process_guard(delta, frame, started_guard):
		return
	# S 单按 = 从单向平台往下穿（11-01 用户：“下楼梯改成 S 就行”；S + 跳 仍然可以）。
	# 只认按下那一下：空中按住 S 下砸落到平台上，不会接着穿下去。
	if frame.pressed_this_frame.has(&"move_down") and _try_drop_through():
		return
	if not locomotion_animation.is_empty() and not _turn_can_cancel():
		_buffer_jump(frame)
		_move_horizontal(delta, frame, 1.0)
		_apply_gravity(delta, _air_gravity())
		move_and_slide()
		return
	# 【顺序很重要】先判跳跃，再判出招。
	# 反过来的话，缓冲里一条还没过期的攻击边沿会在每帧抢先起手，
	# 然后把跳跃输入一直压在缓冲里 —— 表现就是"按跳没反应"。
	# 而 W+J 的上挑不受影响：那条路径靠 aim_up（W 按住）+ attack_light 判定，
	# 只有在"攻击边沿存在"时才走，所以先判跳跃不会吃掉上挑。
	# W 同时是跳跃和上方向；W+J 必须优先判成地面上挑，不能先跳起来。
	var wants_up_attack := frame.actions.has(&"aim_up") and _has_edge(&"attack_light") \
			and not (_keyboard_frame and _pure_jump_down())
	if not wants_up_attack and _try_buffered_jump(frame):
		return

	var cmd := _resolve_attack_command(frame)
	if cmd != &"":
		_landing_lag = 0
		# 起手这一帧也照常移动，点按 J / K 不能吞掉一帧走路或跳跃轨迹。
		_move_horizontal(delta, frame, 1.0)
		_apply_gravity(delta, _air_gravity())
		move_and_slide()
		_begin_command(cmd, frame)
		return

	var land_scale := 1.0
	if _landing_lag > 0:
		_landing_lag -= 1
		land_scale = 0.25
	_move_horizontal(delta, frame, land_scale)
	_apply_gravity(delta, _air_gravity())
	move_and_slide()


# ---------------------------------------------------------------- 跳跃

## 记录跳跃缓冲；存活且有跳跃次数就可消费，大招期间直接拒绝。
##
## 【必须去边沿】一条按下边沿只能记一次跳跃。
## 早期版本这里只判 `pressed_this_frame` 就直接把缓冲拉满，而它在
## `_try_buffered_jump` 里是【先于】缓冲判定执行的 —— 于是第一跳之后的
## 下一个物理帧，同一条仍然存在于缓冲顶部的边沿又把缓冲拉满，
## 当场自动跳出第二跳（表现：按一次跳，二段跳被白白吃掉，且按键完全失灵）。
## 这和攻击边沿用 `_take_edge` 记账是同一个道理，所以这里也用 seq 记账。
func _buffer_jump(frame: InputBuffer.Frame) -> void:
	if _jump_buffer_tick == tick_count:
		return
	_jump_buffer_tick = tick_count
	if frame.pressed_this_frame.has(&"jump"):
		if frame.seq != _consumed_edge.get(&"jump", -1):
			_consumed_edge[&"jump"] = frame.seq
			_jump_buffer_counter = jump_buffer_frames
	elif _jump_buffer_counter > 0:
		_jump_buffer_counter -= 1


func _can_jump() -> bool:
	if ground_frames > 0:
		return true
	if not _ground_jump_used and air_frames > 0 and air_frames <= coyote_frames:
		return true
	return _air_jumps_left > 0 or bonus_air_jumps > 0


## Either order forms one rising uppercut; W-first reuses its existing jump.
func _try_uppercut_input(frame: InputBuffer.Frame) -> bool:
	if charge_frames >= 0 or up_strike_move == null or (_keyboard_frame and _pure_jump_down()):
		return false
	if frame.actions.has(&"dash_modifier"):
		return false
	var light_frame: InputBuffer.Frame = null
	for i in mini(uppercut_input_frames, input_buffer.frame_count()):
		var recent := input_buffer.frame_at(i)
		if recent.pressed_this_frame.has(&"attack_light"):
			light_frame = recent
			break
	if light_frame == null or light_frame.seq == _uppercut_used_light_seq:
		return false
	var fresh_light := frame.pressed_this_frame.has(&"attack_light")
	var fresh_up := frame.pressed_this_frame.has(&"aim_up") \
			or (frame.pressed_this_frame.has(&"jump") and frame.actions.has(&"aim_up"))
	var up_recent := frame.actions.has(&"aim_up") or input_buffer.held_within(&"aim_up", uppercut_input_frames)
	if not ((fresh_light and up_recent) or (fresh_up and light_combo.has(current_move))):
		return false
	var reuse_jump := _last_jump_from_up and not _last_jump_is_uppercut \
			and _frame_counter - _last_jump_frame < uppercut_input_frames and not is_on_floor()
	# Once airborne, held W is steering/aim input, not another jump command on every J.
	# Only a fresh W chord or the original W-first jump may request a new uppercut.
	if not is_on_floor() and not reuse_jump and not fresh_up:
		return false
	if is_on_floor():
		ground_frames = maxi(ground_frames, 1)
		air_frames = 0
	if not reuse_jump and not _can_jump():
		return false
	_uppercut_used_light_seq = light_frame.seq
	_consumed_edge[&"attack_light"] = light_frame.seq
	_consumed_edge[&"jump"] = frame.seq
	_jump_buffer_counter = 0
	_short_dash_ticks = 0
	charge_frames = -1
	_charge_accum = 0.0
	hitstop_frames = 0
	hitstop_this_tick = false
	_start_move(up_strike_move, true)
	if reuse_jump:
		_uppercut_jump_pending = false
		_last_jump_is_uppercut = true
		move_frame = up_strike_move.startup_frames
	else:
		# Keyboard order must not add a grounded windup delay. Take off this tick,
		# then enter the strike's active phase on the next physics tick.
		move_frame = maxi(up_strike_move.startup_frames - 1, 0)
	return true


## Jump cancels the actor's own actions/hitstop, but never damage reactions or
## the ultimate. Neutral jumps retain ordinary platform drop-through behavior.
func _try_action_jump_cancel(delta: float, frame: InputBuffer.Frame) -> bool:
	if state in [State.LAUNCHED, State.DOWN, State.DEAD] or ult_frame >= 0:
		return false
	# Charging is a persistent stance; _process_charge handles ordinary jumps and gravity.
	if charge_frames >= 0:
		return false
	var busy := state != State.NEUTRAL or charge_frames >= 0 or hitstop_frames > 0 \
			or _guard_active or not locomotion_animation.is_empty() or _short_dash_ticks > 0
	if not busy:
		return false
	var explicit_space := _keyboard_frame and _pure_jump_down()
	if frame.actions.has(&"aim_up") and _has_edge(&"attack_light") and not explicit_space:
		return false  # W also means jump; preserve W+J uppercuts.
	_buffer_jump(frame)
	if _jump_buffer_counter <= 0:
		return false
	if is_on_floor():
		if ground_frames == 0:
			# An immediate landing cancel still starts a fresh jump budget.
			_air_jumps_left = extra_air_jumps
		ground_frames = maxi(ground_frames, 1)
		air_frames = 0
	if not _can_jump():
		return false
	var keep_guard := is_guarding() and frame.actions.has(&"parry")
	if not keep_guard:
		_stop_guard()
	_cancel_locomotion()
	_reset_air_combo()
	_reaction_guard_held = false
	_short_dash_ticks = 0
	_pursuit_target = null
	_pursuit_offset = Vector2.ZERO
	_dash_preserving_charge = false
	_post_dash_window = 0
	_post_dash_was_pursuit = false
	_dash_passed_enemy = null
	charge_frames = -1
	_charge_accum = 0.0
	_charge_t = 0.0
	_keen_swing_active = false
	current_move = null
	current_is_up = false
	finisher_intent = &""
	_uppercut_jump_pending = false
	state = State.NEUTRAL
	link_open = false
	down_frames = 0
	_soft_knock = false
	_landing_lag = 0
	hitstop_frames = 0
	hitstop_this_tick = false
	_attack_hold_frames = 0
	_heavy_hold_frames = 0
	_take_edge(&"attack_light")
	_take_edge(&"attack_heavy")
	_take_edge(&"attack_ranged")
	_consumed_edge[&"attack_light_press"] = frame.seq
	_consumed_edge[&"attack_heavy_press"] = frame.seq
	if keep_guard and not _guard_active:
		_start_guard(false)
	input_direction = int(signf(frame.axis.x)) if absf(frame.axis.x) > 0.15 else 0
	_move_horizontal(delta, frame, 1.0)
	_try_buffered_jump(frame)
	return true


## 消费跳跃缓冲；真的跳了返回 true。
## 站在单向平台上按住 S 再按跳 = 往下穿（也返回 true：这一帧已经处理过移动）。
func _try_buffered_jump(frame: InputBuffer.Frame) -> bool:
	_buffer_jump(frame)
	if _jump_buffer_counter <= 0 or not _can_jump():
		return false
	if ground_frames > 0 and frame != null and frame.axis.y > 0.5 and _try_drop_through():
		return true
	_do_jump()
	return true


# ---------------------------------------------------------------- 单向平台下穿

var _drop_from_y: float = NAN       ## 正在往下穿的平台顶面（脚底 y）；NAN = 没在穿
var _drop_frames: int = 0
const DROP_CLEAR := 30.0            ## 脚底低于平台顶面这么多 = 已经穿过去，恢复平台碰撞

## 脚底正踩着单向平台吗（用一个贴着脚底的小矩形查重叠，只查单向平台那一层）
func standing_on_one_way() -> bool:
	if one_way_mask == 0 or not is_on_floor():
		return false
	var q := PhysicsShapeQueryParameters2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(28.0, 6.0)
	q.shape = rect
	q.transform = Transform2D(0.0, global_position + Vector2(0.0, foot_offset + 3.0))
	q.collision_mask = one_way_mask
	q.collide_with_areas = false
	q.collide_with_bodies = true
	return not get_world_2d().direct_space_state.intersect_shape(q, 1).is_empty()


func _try_drop_through() -> bool:
	if not is_nan(_drop_from_y) or not standing_on_one_way():
		return false
	_cancel_locomotion()
	_jump_buffer_counter = 0
	_drop_from_y = global_position.y + foot_offset
	_drop_frames = 0
	collision_mask &= ~one_way_mask
	ground_frames = 0
	# 穿下去算“已经离地”：之后再按跳就是二段跳（不白送一次首跳）
	air_frames = coyote_frames + 1
	_ground_jump_used = true
	velocity.y = 60.0
	_set_visual_scale(Vector2(1.1, 0.9))
	_squash_timer = 4
	move_and_slide()
	return true


## 每帧检查：穿过去了 / 又跳回平台上方了 / 落地了 / 超时 → 恢复单向平台碰撞
func _update_drop_through() -> void:
	if is_nan(_drop_from_y):
		return
	_drop_frames += 1
	var feet := global_position.y + foot_offset
	if feet > _drop_from_y + DROP_CLEAR or feet < _drop_from_y - 4.0 \
			or (is_on_floor() and _drop_frames > 2) or _drop_frames > 40:
		_drop_from_y = NAN
		collision_mask |= one_way_mask


func is_dropping_through() -> bool:
	return not is_nan(_drop_from_y)


func _do_jump() -> void:
	_air_hit_slow_frames = 0
	_air_normal_hit_chain = 0
	_air_a4_braked_this_flight = false
	if combat_rework_enabled and is_inside_tree():
		for n in get_tree().get_nodes_in_group(&"shade"):
			if n != null and is_instance_valid(n) and int(n.get(&"state")) == 6:
				if n.get(&"_air_light_juggle_streak") != null:
					n.set(&"_air_light_juggle_streak", 0)
				if n.get(&"_air_raw_a4_count") != null:
					n.set(&"_air_raw_a4_count", 0)
	_last_jump_frame = _frame_counter
	var jump_input := input_buffer.frame_at(0)
	_last_jump_from_up = jump_input != null and jump_input.actions.has(&"aim_up") \
			and not (_keyboard_frame and _pure_jump_down())
	_last_jump_is_uppercut = false
	if not locomotion_animation.is_empty():
		_set_facing(input_direction if input_direction != 0 else _turn_target)
	_cancel_locomotion()
	var is_double := ground_frames == 0 and (_ground_jump_used or not (air_frames > 0 and air_frames <= coyote_frames))
	_jump_buffer_counter = 0
	ground_frames = 0
	_ground_jump_used = true
	# 起跳前先把自己从几何体里"挤"出来。
	# 如果角色和地形有重叠（掉帧、被顶进平台、测试里瞬移），
	# move_and_slide 会优先解算重叠，把这一帧的起跳速度直接吃掉 ——
	# 实测表现是"按跳完全没反应"，而且 is_on_floor() 还是 false，
	# 光看地面判定根本查不出来。
	var horizontal_velocity := velocity.x
	_depenetrate()
	velocity.x = horizontal_velocity
	if is_double:
		if _air_jumps_left > 0:
			_air_jumps_left -= 1
		else:
			bonus_air_jumps = maxi(bonus_air_jumps - 1, 0)
		velocity.y = _jump_velocity * double_jump_scale
		_jump_rising = true
		_jump_cut = false
		# 二段跳更夸张的拉伸，和一段跳区分开
		_set_visual_scale(Vector2(0.74, 1.30))
		_squash_timer = 7
	else:
		# Coyote time rescues an unspent ground jump after walking off a ledge.
		# A successful launch spends it immediately; the next press is a double jump.
		air_frames = maxi(air_frames, 1)
		velocity.y = _jump_velocity
		_jump_rising = true
		_jump_cut = false
		_set_visual_scale(Vector2(0.82, 1.22))
		_squash_timer = 6
	jumped.emit(is_double)
	move_and_slide()


func _apply_gravity(delta: float, g: float) -> void:
	# 同 dummy.gd：不能用 is_on_floor() 提前 return。
	# 起跳的瞬间玩家还是"贴地"状态，提前 return 会把起跳速度当场吃掉。
	if is_on_floor() and velocity.y > 0.0:
		velocity.y = 0.0
		return
	velocity.y += g * delta
	velocity.y = minf(velocity.y, max_fall_speed)


## 把角色从地形重叠里挤出来（起跳前调用）。
##
## 为什么需要：move_and_slide 在检测到重叠时，会先做解算并把速度投影到碰撞面上。
## 如果此时给的是"向上"的起跳速度而角色恰好嵌在平台里，这一帧的速度会被
## 完全吃掉，看起来就是"按跳没反应"，而且 is_on_floor() 仍然是 false。
## 用零速度 move_and_slide 迭代几次即可脱离重叠，且不影响正常起跳
## （没有重叠时一次就返回，不会有任何位移）。
func _depenetrate() -> void:
	for i in 4:
		var was_on_floor := is_on_floor()
		velocity = Vector2.ZERO
		move_and_slide()
		if is_on_floor() and not was_on_floor:
			return


## 水平移动。scale 是出招时的减速倍率（不是 0，出招要走得动）。
func _move_horizontal(delta: float, frame: InputBuffer.Frame, move_scale: float) -> void:
	# A normal airborne swing uses the same steering as an empty jump.
	# Directional finishers and dash attacks retain their deliberate movement.
	if is_guarding():
		move_scale = clampf(float(_guard_config().get("movementScale", 0.85)), 0.0, 1.0)
	elif charge_frames >= 0:
		move_scale = charge_movement_scale
	elif state == State.ATTACK and (current_move == charge_move or current_move == combo_k_cleave_move) and current_move != null:
		# 11-01 用户：出招时大幅减速，“后摇不要减速了”
		move_scale = charge_attack_movement_scale if current_move.phase_at(move_frame) != &"recovery" else 1.0
	elif not is_on_floor() and state == State.ATTACK and finisher_intent == &"" \
			and current_move != dash_move and current_move != dash_left_move:
		move_scale = 1.0
	var axis := frame.axis
	var target := axis.x * speed * move_scale
	if state == State.NEUTRAL and is_on_floor() and locomotion_animation.is_empty() \
			and absf(velocity.x) > speed * 0.1 and absf(axis.x) > 0.15 and int(signf(axis.x)) != facing:
		_start_turn(int(signf(axis.x)))
	if not locomotion_animation.is_empty():
		target = 0.0 if facing != _turn_target else float(_turn_target) * absf(axis.x) * speed * move_scale
	var rate := acceleration
	if not is_on_floor():
		target = velocity.x + (target - velocity.x) * air_control
	elif absf(target) < absf(velocity.x) or signf(target) != signf(velocity.x):
		# 松手 / 反向：用更大的减速度，急停不打滑
		rate = deceleration
	velocity.x = move_toward(velocity.x, target, rate * delta)
	if absf(axis.x) > 0.15 and locomotion_animation.is_empty():
		_set_facing(1 if axis.x > 0.0 else -1)


# ---------------------------------------------------------------- 指令

## 读 InputBuffer 回溯，决定出哪一招。
##
## 优先级：空中向上打 > 远程 > 上挑 > 普攻。
## "向上"用 W（aim_up）判定 —— 注意是"攻击键按下时 W 也按着"，
## 因为横版里方向键一直按着，不能只靠"按住方向"。
##
## 【键位语义】
##   J = 点按普攻（三段连段），第三段点按 J 出强化普攻；
##       连段是可"存"的 —— J→K→J 时第三个 J 直接出强化普攻（见 _link_into）
##   K = 远程弹丸，随时可放，且【不影响连段指针】
func _resolve_attack_command(frame: InputBuffer.Frame) -> StringName:
	# 【弹刀最先判】L 是独立键，和 J/K 不冲突；放最前是为了"按下即起手"——
	# 排到后面的话，手里正好按着 W（aim_up）时会被判成上挑、晚一帧才开始，
	# 而弹刀的全部价值就在"来得及"。
	if _has_edge(&"parry"):
		return &"parry"
	var aim_up := frame.actions.has(&"aim_up") or _held_within(&"aim_up", attack_buffer_frames)
	var airborne := not is_on_floor() and air_frames > coyote_frames
	if not air_combo.is_empty():
		airborne = not is_on_floor()

	if combat_rework_enabled:
		if _has_edge(&"attack_heavy"):
			if airborne:
				return &"air_slam" if _rework_wants_slam(frame) else &"air_drive"
			if _short_dash_ticks > 0 or _post_dash_window > 0:
				return &"dash_heavy"
			if flash_heavy_timer > 0.0:
				return &"flash_heavy"
			if _combo_k_stage() > 0:
				return &"combo_k"
			return &"heavy_charge"
		if (_short_dash_ticks > 0 or _post_dash_window > 0) and _has_edge(&"attack_light"):
			if aim_up and is_on_floor():
				return &"up"
			if (_post_dash_was_pursuit or _pursuit_target != null) and airborne:
				if _wants_air_slam(frame):
					return &"air_slam"
				if not air_combo.is_empty():
					return &"air_combo"
			# 地面冲刺斩仅在瞬步冲刺进行中（含同帧 Shift+J / 双击+J）派生；若已穿敌点亮锋芒且松开闪避与方向键单点 J，则立即回身劈出锋芒强普
			var keen_turn_slash := keen_edge_timer > 0.0 and _dash_passed_enemy != null \
					and frame != null and not frame.actions.has(&"dash_modifier") \
					and not frame.actions.has(&"short_dash") and absf(frame.axis.x) <= 0.15
			if _short_dash_ticks > 0 and dash_move != null and not keen_turn_slash:
				_pending_dash_direction = _rework_followup_dir(frame)
				return &"dash_strike"
	else:
		# 双击 A / D = 冲刺斩（11-03 用户：“冲刺斩改成 aa 或 dd”），朝双击的那一边。
		# 和下面的 dash_modifier 是同一套出招逻辑，只是入口不同。
		var tap_dir := _double_tap_direction()
		if dash_move != null and tap_dir != 0:
			var tap_seq := _newest_press_seq(&"move_left" if tap_dir < 0 else &"move_right")
			if tap_seq >= 0:
				_double_tap_seq = tap_seq      # 记下这一次双击（残影不足也消费掉，避免回格后自动冲出）
				if _dash_allowed():
					_pending_dash_direction = tap_dir
					return &"dash"
		var dash_dir := _dash_edge_direction(_unconsumed_edge_frame(&"dash_modifier"))
		if dash_move != null and dash_dir != 0:
			if _dash_allowed():
				_pending_dash_direction = dash_dir
				return &"dash"
			# 空中次数用完：吃掉这一下，免得边沿留在缓冲里、落地后自己冲出去
			_take_edge(&"dash_modifier")

	if airborne and _has_edge(&"attack_light"):
		var finisher := _wants_air_finisher()
		if finisher == &"slam":
			return &"air_slam"
		if finisher == &"drive":
			return &"air_drive"
		match _air_light_hold_state():
			-1:
				return &""
			1:
				return &"charge"
		if not air_combo.is_empty():
			return &"air_combo"
		if _air_light_left > 0:
			return &"air_up"
		# 没次数时也消费这次按键，避免之后被 K 重置后自动补出一刀。
		_take_edge(&"attack_light")
		return &""
	if _has_edge(&"attack_ranged"):
		if combat_rework_enabled and ranged_cooldown > 0:
			_take_edge(&"attack_ranged")
		else:
			return &"ranged"
	if aim_up and _has_edge(&"attack_light"):
		return &"up"
	if _has_edge(&"attack_light"):
		return &"light"
	return &""


## 取走一个按键边沿：找到就记账并返回 true。
##
## 为什么必须记账：输入帧会在环形队列里留存 attack_buffer_frames 帧，
## 同一帧在接下来若干物理帧里都"在窗口内"，不记账就会被反复命中，
## 表现就是一次按键把连段一路推到底。
##
## 为什么用 frame.seq 而不是"帧龄 i"：帧龄会复用。第 1 招消费了 age=0 的边沿，
## 过几帧再按一次，新边沿同样落在 age=0 上，会被误判成"已消费"而丢掉 ——
## 实测表现就是"第二段接得上、第三段死活接不上"。
func _take_edge(action: StringName) -> bool:
	for i in input_buffer.frame_count():
		if input_buffer.logic_age_at(i) >= attack_buffer_frames:
			break
		var f := input_buffer.frame_at(i)
		if f == null or not f.pressed_this_frame.has(action):
			continue
		if f.seq == _consumed_edge.get(action, -1):
			return false
		_consumed_edge[action] = f.seq
		return true
	return false


func _has_edge(action: StringName) -> bool:
	return _unconsumed_edge_frame(action) != null


## Modifiers belong to the same sampled edge as the command, even across hitstop.
func _unconsumed_edge_frame(action: StringName) -> InputBuffer.Frame:
	for i in input_buffer.frame_count():
		if input_buffer.logic_age_at(i) >= attack_buffer_frames:
			break
		var f := input_buffer.frame_at(i)
		if f != null and f.pressed_this_frame.has(action):
			# 只看最新一条匹配边沿；若它已消费，就不能让更老的边沿复活。
			return f if f.seq != _consumed_edge.get(action, -1) else null
	return null


func _held_within(action: StringName, n: int) -> bool:
	return input_buffer.held_within(action, n)


# ---------------------------------------------------------------- 起手

func _begin_command(cmd: StringName, frame: InputBuffer.Frame) -> void:
	match cmd:
		&"dash":
			_take_edge(&"dash_modifier")
			if not consume_shadow(1):
				return
			var direction := _pending_dash_direction
			_dash_in_air = not is_on_floor() and air_frames > coyote_frames
			if _dash_in_air:
				_air_normal_hit_chain = 0
				_air_a4_braked_this_flight = false
			if _dash_in_air and not air_dash_unlimited:
				_air_dash_left = maxi(_air_dash_left - 1, 0)
			_cancel_locomotion()
			_set_facing(direction)
			_start_move(_dash_move_for(direction), false)
		&"dash_strike":
			_take_edge(&"attack_light")
			_take_edge(&"dash_modifier")
			_take_edge(&"short_dash")
			_post_dash_window = 0
			_post_dash_was_pursuit = false
			_dash_passed_enemy = null
			var ds_dir := _pending_dash_direction if _pending_dash_direction != 0 else facing
			_dash_in_air = not is_on_floor() and air_frames > coyote_frames
			if _dash_in_air:
				_air_normal_hit_chain = 0
				_air_a4_braked_this_flight = false
			if _dash_in_air and not air_dash_unlimited:
				_air_dash_left = maxi(_air_dash_left - 1, 0)
			_cancel_locomotion()
			_set_facing(ds_dir)
			_start_move(_dash_move_for(ds_dir), false)
		&"dash_heavy":
			_take_edge(&"attack_heavy")
			_post_dash_window = 0
			_post_dash_was_pursuit = false
			var dh_dir := _rework_followup_dir(frame)
			_dash_passed_enemy = null
			_set_facing(dh_dir)
			_start_instant_heavy(1.0 if _consume_flash_heavy() else 0.80, 10)
		&"flash_heavy":
			_take_edge(&"attack_heavy")
			_consume_flash_heavy()
			if frame != null and absf(frame.axis.x) > 0.15:
				_set_facing(1 if frame.axis.x > 0.0 else -1)
			_start_instant_heavy(1.0, 14)
		&"combo_k":
			var ck_stage := _combo_k_stage()
			if ck_stage > 0:
				_start_combo_k_finisher(ck_stage, frame)
			else:
				_start_heavy_charge(frame)
		&"heavy_charge":
			_start_heavy_charge(frame)
		&"air_combo":
			_take_edge(&"attack_light")
			_post_dash_window = 0
			_post_dash_was_pursuit = false
			_start_air_combo_move()
		&"charge":
			_start_charge()
		&"air_slam":
			_start_air_finisher(&"slam")
		&"air_drive":
			_start_air_finisher(&"drive")
		&"parry":
			_take_edge(&"parry")
			_begin_guard_or_parry()
		&"ranged":
			_take_edge(&"attack_ranged")
			_start_ranged()
		&"up", &"air_up":
			_take_edge(&"attack_light")
			if cmd == &"air_up":
				_air_light_left = maxi(_air_light_left - 1, 0)
			_start_move(up_strike_move if cmd == &"up" else air_up_move, true)
		_:
			_take_edge(&"attack_light")
			if light_combo.is_empty():
				return
			if not is_on_floor() and air_frames > coyote_frames:
				return
			if combat_rework_enabled and light_combo.size() >= 4 and _consume_keen_edge():
				combo_index = light_combo.size() - 1
				_rework_next_light = 0
				_rework_combo_timer = 0
				var kmv: Resource = light_combo[combo_index]
				_start_move(kmv, false, &"", true)
				move_frame = mini(3, maxi(int(kmv.startup_frames) - 2, 0))
				_check_swing_cue(kmv)
				return
			# 实战下被打断（瞬步 / 弹刀 / 挨打受击 / 走位 / 挥空）仍在窗口内继续下一段；训练场保持旧规则
			if combat_rework_enabled:
				combo_index = _rework_next_light if _rework_combo_timer > 0 else 0
			elif frames_since_attack > combo_keep_frames:
				combo_index = 0
			_start_move(light_combo[clampi(combo_index, 0, light_combo.size() - 1)], false)


func _start_move(mv: Resource, is_up: bool, intent_override: StringName = &"", keen: bool = false) -> void:
	if mv == null:
		return
	if not locomotion_animation.is_empty():
		_set_facing(input_direction if input_direction != 0 else _turn_target)
	_cancel_locomotion()
	_stop_guard()
	_reaction_guard_held = false
	_short_dash_ticks = 0
	action_serial += 1
	action_idle_frames = 0
	_dash_facing = facing
	current_move = mv
	_keen_swing_active = keen
	_charge_authored_hop = (mv == charge_move or mv == combo_k_cleave_move) and not mv.root_motion_y.is_empty() \
			and float(mv.root_motion_y.min()) < -0.1 and is_on_floor()
	_charge_hop_started = false
	_charge_hop_origin_y = global_position.y
	finisher_intent = intent_override
	_uppercut_jump_pending = is_up and (mv == up_strike_move or mv == air_up_move or mv == combo_k_launch_move) and _can_jump()
	if not combat_rework_enabled and finisher_intent == &"" and not air_combo.is_empty() and mv == air_combo[air_combo.size() - 1] and not is_on_floor():
		var intent_frame := input_buffer.frame_at(0)
		if intent_frame != null and intent_frame.axis.x * float(facing) > 0.4:
			finisher_intent = &"drive"
	if not mv.is_charge:
		_charge_t = 0.0
	current_is_up = is_up
	move_frame = 0
	# 空中冲刺斩的"空中版本"（11-03 用户：前后摇大幅度缩短）：直接跳过前面几帧起手，
	# 空中一秒都不能等；后摇由 air_frames().recovery 决定（见 _process_dash_attack）。
	if is_dash_move(mv) and _dash_in_air and mv.air_startup_frames >= 0:
		move_frame = maxi(mv.startup_frames - int(mv.air_frames().startup), 0)
	if _melee != null and mv.hitbox.size.x > 0:
		# 下沿往下多给一截：跳起来压着打、或者跳得比敌人高，也擦得到
		var extra_down := MELEE_VERTICAL_FORGIVENESS
		if not is_on_floor():
			extra_down += MELEE_AIR_DOWN_REACH
		var reach: Vector2 = mv.hitbox.size
		# 空中版本（11-03 用户：空中冲刺斩"上下范围加大两倍"）：以盒子中心为轴拉高，
		# 上下各多出一截，冲过头、冲在敌人下方都还能擦到。
		if _dash_in_air and mv.air_hitbox_height_scale > 1.0:
			reach.y *= mv.air_hitbox_height_scale
		# 以下都是朝右、相对她中心的坐标；_sync_melee_offset 再按面向翻
		var cx := absf(mv.hitbox.position.x)
		var cy: float = mv.hitbox.position.y + foot_offset
		var front := (cx + reach.x * 0.5) * MELEE_REACH_SCALE
		var back := minf(cx - reach.x * 0.5, -MELEE_BACK_REACH)
		var top := cy - reach.y * 0.5 * MELEE_REACH_SCALE
		var bottom := cy + reach.y * 0.5 * MELEE_REACH_SCALE + extra_down
		var body := _body_half_size()
		back = minf(back, -(body.x + MELEE_BODY_MARGIN))
		top = minf(top, -(body.y + MELEE_BODY_MARGIN))
		bottom = maxf(bottom, body.y + MELEE_BODY_MARGIN)
		_melee_base_offset_x = (front + back) * 0.5
		_melee.position.y = (top + bottom) * 0.5
		var shape: RectangleShape2D = _melee.get_node("CollisionShape2D").shape
		shape.size = Vector2(front - back, bottom - top)
		_sync_melee_offset()
	state = State.ATTACK
	link_open = false
	last_swing_hit = false
	_hit_this_swing.clear()
	_damage_announced = false
	_dash_stopped = false
	_dash_cross_target = null
	swing_hit_count = 0
	var lc_idx := light_combo.find(mv)
	if lc_idx >= 0:
		combo_index = lc_idx
		if combat_rework_enabled:
			if lc_idx >= light_combo.size() - 1:
				_rework_next_light = 0
				_rework_combo_timer = 0
			else:
				_rework_next_light = lc_idx + 1
				_rework_combo_timer = rework_combo_keep_frames
	var ac_idx := air_combo.find(mv)
	if ac_idx >= 0 and combat_rework_enabled and intent_override == &"":
		if ac_idx >= air_combo.size() - 1:
			_rework_next_air = 0
			_rework_air_combo_timer = 0
		else:
			_rework_next_air = ac_idx + 1
			_rework_air_combo_timer = rework_combo_keep_frames
	if _is_light_finisher(mv) and air_combo.is_empty():
		_air_light_left = maxi(_air_light_left, 1)
	# 前摇反向蓄力（设计文档 §8.4 Anticipation）
	var windup := Vector2(0.90, 1.12)
	if is_up:
		windup = Vector2(1.10, 0.90)
	_set_visual_scale(windup)
	_squash_timer = 4
	move_started.emit(mv, combo_index if lc_idx >= 0 else -1)
	_swing_cued = false
	_check_swing_cue(mv)


## 判定帧前 swing_cue_lead_frames 帧发 swing_cue（招架/远程这类不挥刀的招式由音效表决定不响）
func _check_swing_cue(mv: Resource) -> void:
	if _swing_cued or mv == null or current_move != mv:
		return
	if move_frame >= mv.startup_frames - swing_cue_lead_frames:
		_swing_cued = true
		swing_cue.emit(mv, combo_index if light_combo.has(mv) else -1)


func _start_charge() -> void:
	if charge_move == null:
		return
	_take_edge(&"attack_light")
	_charge_action = &"attack_light"
	_cancel_locomotion()
	_stop_guard()
	action_serial += 1
	action_idle_frames = 0
	charge_frames = 0
	_charge_accum = 0.0
	current_move = null
	state = State.NEUTRAL
	link_open = false
	charge_started.emit()


func _start_heavy_charge(frame: InputBuffer.Frame = null) -> void:
	if charge_move == null:
		return
	_take_edge(&"attack_heavy")
	_charge_action = &"attack_heavy"
	_post_dash_window = 0
	_post_dash_was_pursuit = false
	if _dash_passed_enemy != null and is_instance_valid(_dash_passed_enemy) and (frame == null or absf(frame.axis.x) <= 0.15):
		var bdx := _dash_passed_enemy.global_position.x - global_position.x
		if absf(bdx) > 4.0:
			_set_facing(1 if bdx > 0.0 else -1)
	elif frame != null and absf(frame.axis.x) > 0.15:
		_set_facing(1 if frame.axis.x > 0.0 else -1)
	_dash_passed_enemy = null
	_cancel_locomotion()
	_stop_guard()
	action_serial += 1
	action_idle_frames = 0
	charge_frames = 0
	_charge_accum = 0.0
	current_move = null
	state = State.NEUTRAL
	link_open = false
	charge_started.emit()


func _start_instant_heavy(power: float, skip_startup_cap: int = 12) -> void:
	if charge_move == null:
		return
	_charge_t = clampf(power, 0.0, 1.0)
	last_charge_frames = roundi(_charge_t * float(maxi(heavy_full_charge_frames, 1)))
	charge_frames = -1
	_charge_accum = 0.0
	_start_move(charge_move, false)
	move_frame = mini(skip_startup_cap, maxi(charge_move.startup_frames - 6, 0))
	_check_swing_cue(charge_move)
	charge_released.emit(last_charge_frames, _charge_t > 0.35)


## K：发射一发远程弹丸。
##
## 刻意【不】改 combo_index、也不走 _start_move —— 所以：
##   · 连段指针被"存"住，J→K→J 的第三个 J 仍然是强化普攻
##   · 远程不占连段帧，随时能放
func _start_ranged() -> void:
	if ranged_move == null:
		return
	if combat_rework_enabled:
		if ranged_cooldown > 0:
			return
		ranged_cooldown = rework_ranged_cooldown_frames
	action_serial += 1
	action_idle_frames = 0
	if air_combo.is_empty():
		_air_light_left = maxi(_air_light_left, 1)
	var p := ProjectileScene.instantiate()
	p.move = ranged_move
	p.facing = facing
	p.speed = ranged_speed
	p.life_frames = ranged_life_frames
	p.shooter = self
	# 远程命中不能冻结射手，否则空中 K 会在跳跃轨迹里突然停顿。
	p.shooter_hitstop = 0
	# 弹丸的命中层与颜色都跟着射手走 —— PVP 里 P2 的弹丸必须能打到 P1，
	# 而且颜色要和自己的身份色一致（否则分不清是谁打的）。
	p.hit_mask = ranged_hit_mask
	p.tint = identity_color
	var parent := get_parent()
	if parent == null:
		p.queue_free()
		return
	parent.add_child(p)
	var spawn_pos := global_position + Vector2(ranged_offset.x * float(facing), ranged_offset.y)
	p.global_position = spawn_pos
	if combat_rework_enabled and is_inside_tree() and p.get(&"velocity_y") != null:
		var aim_target: Node2D = null
		var best_score := INF
		for n in get_tree().get_nodes_in_group(&"shade"):
			if not (n is Node2D) or not is_instance_valid(n) or int(n.get(&"state")) == 9:
				continue
			var s2d := n as Node2D
			var dx := (s2d.global_position.x - spawn_pos.x) * float(facing)
			var dy := s2d.global_position.y - spawn_pos.y
			if dx < 16.0 or dx > 760.0 or absf(dy) > 320.0:
				continue
			var air_bonus := -220.0 if int(n.get(&"state")) == 6 else 0.0
			var sc := dx + absf(dy) * 0.6 + air_bonus
			if sc < best_score:
				best_score = sc
				aim_target = s2d
		if aim_target != null:
			var adx := maxf(absf(aim_target.global_position.x - spawn_pos.x), 36.0)
			var ady := aim_target.global_position.y - spawn_pos.y
			if absf(ady) > 22.0:
				var flight_t := adx / maxf(ranged_speed, 1.0)
				p.set(&"velocity_y", clampf(ady / maxf(flight_t, 0.03), -680.0, 480.0))
	if p.has_signal(&"hit_target"):
		p.hit_target.connect(_on_projectile_hit)
	# 连段保留窗口要放长：远程是"存连段"的中转，不能因为它把连段过期掉
	frames_since_attack = 0
	ranged_fired.emit(p)


func _on_projectile_hit(target: Node, point: Vector2) -> void:
	last_swing_hit = true
	if combat_rework_enabled and target != null and is_instance_valid(target) and int(target.get(&"_pin_frames")) > 0:
		_grant_keen_edge(keen_edge_duration)
	hit_confirmed.emit(target, ranged_move, point)


# ---------------------------------------------------------------- 蓄力

## 蓄力阶段只降低移速，跳跃和重力沿用正常移动。
func _process_charge(delta: float, frame: InputBuffer.Frame) -> void:
	if bool(_guard_config().get("enabled", false)) and frame.actions.has(&"parry"):
		charge_frames = -1
		_charge_accum = 0.0
		var precise := _has_edge(&"parry")
		_take_edge(&"parry")
		_start_guard(precise)
		_process_guard(delta, frame, true)
		return
	# 蓄力速率是倍率（charge_boost 道具写 charge_rate_scale）。
	# 【为什么要浮点累加器】直接用 int 递增会丢掉 1.6 这种非整数倍率的零头，
	# 于是"加速 60%"实际只快 50% —— 玩家能感觉到不对劲但说不清哪里不对。
	_charge_accum += maxf(charge_rate_scale, 0.05)
	while _charge_accum >= 1.0:
		_charge_accum -= 1.0
		charge_frames += 1
	var cm := charge_move
	var use_heavy_rework := combat_rework_enabled and _charge_action == &"attack_heavy"
	var cap: int = heavy_full_charge_frames if use_heavy_rework else cm.max_charge_frames
	var t := clampf(float(charge_frames) / float(maxi(cap, 1)), 0.0, 1.0)

	# 蓄力表现：越攒越"缩"，同时抖起来
	var sq := Vector2(1.0 + 0.18 * t, 1.0 - 0.18 * t)
	if charge_frames % 3 == 0:
		sq.x += 0.03 * t * (1.0 if charge_frames % 6 == 0 else -1.0)
	_set_visual_scale(sq)
	_squash_timer = 2

	_move_horizontal(delta, frame, charge_movement_scale)
	if not _try_buffered_jump(frame):
		_apply_gravity(delta, _air_gravity())
		move_and_slide()
	if _has_edge(&"attack_ranged"):
		_take_edge(&"attack_ranged")
		_start_ranged()

	# 蓄满只封顶伤害，继续按住仍保持；松开才释放。
	var released := not frame.actions.has(_charge_action)
	if use_heavy_rework:
		if released:
			_release_charge()
		return
	if released and charge_frames >= cm.min_charge_frames:
		_release_charge()
		return
	# 还没到最短蓄力就松手 → 当成一次普通轻击（不惩罚玩家）
	if released and charge_frames < cm.min_charge_frames:
		charge_frames = -1
		if not light_combo.is_empty():
			_start_move(light_combo[0], false)
		return


## 放出蓄力斩：把蓄力量化成 damage / knockback / hitstop 三个倍率。
func _release_charge() -> void:
	last_charge_frames = charge_frames
	var cm := charge_move
	var use_heavy_rework := combat_rework_enabled and _charge_action == &"attack_heavy"
	var cap: int = heavy_full_charge_frames if use_heavy_rework else cm.max_charge_frames
	var t := clampf(float(charge_frames) / float(maxi(cap, 1)), 0.0, 1.0)
	var is_quick_tap := use_heavy_rework and charge_frames <= heavy_tap_threshold_frames
	if is_quick_tap:
		t = maxf(0.45, t)
	# 存进"这一刀的实际数值"，命中时用
	_charge_t = t
	charge_frames = -1
	_charge_accum = 0.0
	_start_move(cm, false)
	if use_heavy_rework:
		var skip := 10 if is_quick_tap else 6
		move_frame = mini(skip, maxi(cm.startup_frames - 6, 0))
		_check_swing_cue(cm)
	charge_released.emit(last_charge_frames, t > 0.35)


# ---------------------------------------------------------------- 出招

func _process_attack(delta: float, frame: InputBuffer.Frame) -> void:
	var mv := current_move
	if mv == null:
		state = State.NEUTRAL
		return
	if guard_reactions.has(mv) or parry_reactions.has(mv):
		_process_guard_reaction(delta, frame, mv)
		return
	# 空中自由打断（11-03 用户：“空中冲刺斩应该能打断和被打断任何招式，空中攻击同理”）：
	# 人在天上时，只要「正在出的这一招」或「想出的下一招」有一边是空中招，
	# 就允许立刻切——不看前摇/判定/后摇，也不要求先开接招窗口。
	if _try_air_interrupt(mv, frame):
		return

	if _uppercut_jump_pending and move_frame >= maxi(mv.startup_frames - 1, 0):
		_uppercut_jump_pending = false
		if _can_jump():
			_do_jump()
			_last_jump_is_uppercut = true
			move_frame += 1
			return
	_check_swing_cue(mv)
	var phase: StringName = mv.phase_at(move_frame)
	if is_dash_move(mv) and _dash_in_air:
		phase = _air_dash_phase(mv, move_frame)
	if is_dash_move(mv):
		_process_dash_attack(delta, mv, phase, frame)
		return
	# 11-01 用户：“蓄力很容易按不出来，我需要轻松就能蓄力”。以前要等这一刀的接招点才看按没按住，
	# 按住时间不够长就又出一刀普攻；现在地面普攻里 J 按住满 hold_to_charge_frames 帧就当场转蓄力。
	if light_combo.has(mv) and is_on_floor() and _should_charge_on_hold():
		_take_edge(&"attack_light")
		_start_charge()
		if charge_frames >= 0:
			_process_charge(delta, frame)
		return

	if phase == &"startup":
		# 前摇：能走位，但不能取消
		_move_horizontal(delta, frame, mv.startup_movement_scale)

	elif phase == &"active":
		if combat_rework_enabled and is_on_floor() and last_swing_hit and _has_edge(&"attack_heavy") and flash_heavy_timer <= 0.0:
			var ck_hit := _combo_k_stage()
			if ck_hit > 0:
				_start_combo_k_finisher(ck_hit, frame)
				return
		# 弹刀【不做攻击判定】—— 它是防守动作，"谁在窗口里打我我就弹谁"
		# 这条判定在 take_hit 那一侧。让它顺手打一下的话，0 伤害 0 击退的一击
		# 仍然会把怪推进 LAUNCHED → 倒地 26 帧，等于白送一个击倒。
		# 伤害窗口（11-03 重击）：只有「挥到底」那一截结算，前面挥过去只有风没有判定。
		if not _is_parry_move(mv) and not guard_reactions.has(mv) and not parry_reactions.has(mv) \
				and mv.damages_at(move_frame):
			if not _damage_announced:
				_damage_announced = true
				damage_window_opened.emit(mv)
			_do_hit_check(mv)
			if hitstop_this_tick:
				return
			if combat_rework_enabled and is_on_floor() and last_swing_hit and _has_edge(&"attack_heavy") and flash_heavy_timer <= 0.0:
				var ck_now := _combo_k_stage()
				if ck_now > 0:
					_start_combo_k_finisher(ck_now, frame)
					return
		# 命中前冲：只在判定帧的头几帧推一次，做出"撞上去"的顿挫
		if is_on_floor() and mv != charge_move and mv != combo_k_cleave_move and move_frame == mv.startup_frames and mv.lunge > 0.0 and absf(frame.axis.x) < 0.15:
			velocity.x = float(facing) * mv.lunge
		_move_horizontal(delta, frame, mv.movement_scale)

	elif phase == &"recovery":
		# Uppercut takeoff already spent its jump. After the strike, J may start
		# normal air attacks without requiring another jump or waiting the long ground tail.
		if not is_on_floor() and (mv == up_strike_move or mv == air_up_move or mv == combo_k_launch_move) \
				and not air_combo.is_empty() and _resolve_light_press():
			if charge_frames >= 0:
				_process_charge(delta, frame)
				return
			_move_horizontal(delta, frame, 1.0)
			_apply_air_attack_gravity(delta, current_move)
			_move_with_root_motion(delta, current_move)
			return
		# 方向 1：J+K 轻重派生终结技 —— 地面 light_1..3 一进后摇即可按 K 零蓄力瞬发派生！
		if combat_rework_enabled and is_on_floor() and _has_edge(&"attack_heavy") and flash_heavy_timer <= 0.0:
			var ck_rec := _combo_k_stage()
			if ck_rec > 0:
				_start_combo_k_finisher(ck_rec, frame)
				return
		# 挑飞取消（试玩版，launcher_cancel=true 时）：地面招式的后摇一开始就能 W+J 接上挑，
		# 和"后摇按 W 跳起取消"同一时机。让"打满失衡 → 眩晕 → 立刻挑飞"这一步不被长后摇拖住。
		if launcher_cancel and not link_open and is_on_floor() and up_strike_move != null \
				and mv != up_strike_move and light_combo.has(mv):
			var lf := _unconsumed_edge_frame(&"attack_light")
			if lf != null and (lf.actions.has(&"aim_up") or frame.actions.has(&"aim_up")):
				_link_into(&"attack_light")
				return
		# 第二轮手感：招式后摇【随时】可以用 弹刀 / 冲刺 / 跳 取消（受击反馈另算，见下）。
		var reaction := guard_reactions.has(mv) or parry_reactions.has(mv)
		if not reaction and not _is_parry_move(mv):
			if _has_edge(&"parry"):
				_link_into(&"parry")
				if _guard_active:
					_process_guard(delta, frame, true)
				return
			if _try_dash_cancel():
				return
		# 取消窗口：后摇开始后第 cancel_frame 帧起。
		# 窗口一开就【立刻】尝试消费连段输入 —— 不然窗口期内每帧都会重新命中
		# 同一个边沿，把连段自动推到底。
		if not link_open and move_frame >= mv.startup_frames + mv.active_frames + mv.cancel_frame:
			link_open = true
			link_open_count += 1
		if link_open:
			# L 弹刀可以在后摇里抢出来 —— 招架的价值全在"来得及"，
			# 后摇里按不出来就等于这个键废掉一半。
			if _has_edge(&"parry"):
				_link_into(&"parry")
				if _guard_active:
					_process_guard(delta, frame, true)
				return
			if _try_dash_cancel():
				return
			# K 随时能补一发远程，且不影响连段指针（"存连段"的中转）
			if _has_edge(&"attack_ranged"):
				_link_into(&"attack_ranged")
				if air_combo.is_empty() or not air_combo.has(mv):
					return
			if combat_rework_enabled and _has_edge(&"attack_heavy"):
				if not is_on_floor():
					_start_air_finisher(&"slam" if _rework_wants_slam(frame) else &"drive")
					if current_move != null:
						_move_horizontal(delta, frame, 1.0)
						_apply_air_attack_gravity(delta, current_move)
						_move_with_root_motion(delta, current_move)
					return
				if flash_heavy_timer > 0.0:
					_take_edge(&"attack_heavy")
					_consume_flash_heavy()
					if absf(frame.axis.x) > 0.15:
						_set_facing(1 if frame.axis.x > 0.0 else -1)
					_start_instant_heavy(1.0, 14)
					return
				var ck_link := _combo_k_stage()
				if ck_link > 0:
					_start_combo_k_finisher(ck_link, frame)
					return
				_start_heavy_charge(frame)
				if charge_frames >= 0:
					_process_charge(delta, frame)
				return
			# J：按住 → 蓄力斩；点按 → 推进连段
			if _resolve_light_press():
				if charge_frames >= 0:
					_process_charge(delta, frame)
					return
				# A chain transition still consumes a physics tick. Keep moving on
				# that tick rather than leaving a one-frame gap in the jump arc.
				if not is_on_floor() and current_move != null:
					_move_horizontal(delta, frame, 1.0)
					_apply_air_attack_gravity(delta, current_move)
					_move_with_root_motion(delta, current_move)
				return
			link_open = false
		# 收招尾巴：接招点之后再过 move_cancel_delay 帧，按方向键直接收招跑开
		if _try_move_cancel(mv):
			_process_neutral(delta, frame)
			return
		# 后摇也能走位（走得慢一点），这是"取消不重置"之外的第二条流畅度来源
		_move_horizontal(delta, frame, mv.recovery_movement_scale)
		# 后摇里按 W 可以跳起来取消（地面常用）
		if _try_buffered_jump(frame):
			# 地面招式跳起取消 = 这一招真正结束：人在空中回到中立，
			# 马上能接空中连段（挑飞 → 起跳追击）。空中招式保持原行为。
			if not air_combo.has(mv):
				_end_attack()
			return

	if (mv == charge_move or mv == combo_k_cleave_move) and _try_buffered_jump(frame):
		move_frame += 1
		if move_frame >= mv.total_frames():
			_end_attack()
		return
	_apply_air_attack_gravity(delta, mv)
	_move_with_root_motion(delta, mv)
	if not air_combo.is_empty() and air_combo.has(mv) and is_on_floor():
		_end_attack()
		_reset_air_combo()
		return

	move_frame += 1
	if move_frame >= mv.total_frames():
		_end_attack()


## 现在该不该进蓄力斩？
##
## 【键位契约】
##   · J 点按  → 普攻；第三段点按 = **强化普攻**（light_3）
##   · J 按住  → **蓄力斩**（charge_1：高伤 / 打飞 / 26 帧僵直）
## 蓄力斩是第三下【按住不松】的版本，点按仍然是强化普攻。
##
## 【为什么不能靠 `_has_edge` 判"按住"】
## 走到第三段时，那条按下边沿已经被 `_take_edge` 消费掉了 ——
## 之后再想"按住同一个 J"就没有边沿可查了，蓄力永远起不来（踩过）。
## 所以这里改成**计时**：按下那一刻开始数，还按着就继续数，
## 数到 HOLD_TO_CHARGE_FRAMES 才认定是蓄力。松手就清零。
##
## 另外两个例外：
##   · 当前招式就是蓄力斩本身 → 否则它自己的后摇里会不停续上蓄力，死循环
## 空中也能蓄力（11-01 用户：“跳起来的时候也能蓄力”），见 _air_light_hold_state。
func _should_charge_on_hold() -> bool:
	if combat_rework_enabled:
		return false
	if charge_move == null or current_move == charge_move:
		return false
	return _attack_hold_frames >= hold_to_charge_frames


## 空中的 J 先不出招，看是点按还是按住（11-01 用户：“空中蓄力最好不是先普攻再蓄力”）：
## -1 = 还按着、不够 hold_to_charge_frames，再等等；0 = 已松手，出空中连段；1 = 按够了，进蓄力。
## 代价：空中点按 J 要到松手那一帧才出刀（晚了按键时长那几帧）。
## 提前按下、在上一刀里就松开的缓冲输入不受影响（松手了直接是 0）。
func _air_light_hold_state() -> int:
	if combat_rework_enabled or charge_move == null:
		return 0
	if _attack_hold_frames >= hold_to_charge_frames:
		return 1
	return -1 if _attack_hold_frames > 0 else 0


## 维护"J 按住了几帧"的计时器。每帧都必须调用一次。
##
## 【为什么要看 seq 才算"新按下"】注入/回放的帧对象可能被连续压入多帧
## （测试里的"粘住帧"、以后的回放系统都会这样），此时
## `pressed_this_frame` 会在连续几帧里重复为真。
## 只看它会把"同一次按下的重放"当成新按下，于是"按住"永远数不到 2 帧。
## 用 seq 记账就能识别出"这只是同一次按下的重放"。
func _update_attack_hold(frame: InputBuffer.Frame) -> void:
	var is_new_press: bool = frame.pressed_this_frame.has(&"attack_light") \
			and frame.seq != _consumed_edge.get(&"attack_light_press", -1)
	if is_new_press:
		_consumed_edge[&"attack_light_press"] = frame.seq
		_attack_hold_frames = 1
	elif frame.actions.has(&"attack_light"):
		_attack_hold_frames += 1
	else:
		_attack_hold_frames = 0
	var is_new_heavy: bool = frame.pressed_this_frame.has(&"attack_heavy") \
			and frame.seq != _consumed_edge.get(&"attack_heavy_press", -1)
	if is_new_heavy:
		_consumed_edge[&"attack_heavy_press"] = frame.seq
		_heavy_hold_frames = 1
	elif frame.actions.has(&"attack_heavy"):
		_heavy_hold_frames += 1
	else:
		_heavy_hold_frames = 0


## J 的"点按 / 按住"分流。**只在取消窗口里调用**。
##
## 【为什么必须在取消窗口里，而不能放在 NEUTRAL 顶部】
## 攻击边沿会在环形缓冲里留存 attack_buffer_frames 帧。如果在真正空闲的
## 每一帧都去消费它，就会在出招前摇/判定期间提前把边沿吃掉：
##   · 连段接不上（取消窗口还没开，边沿已经被消耗）
##   · 或者反复重新起手 light_1，而重起手的挥空又把连段指针清零
## 实测两种坏法都出现过。所以起手权仍然只属于取消窗口。
##
## 【点按 vs 按住】
## `_attack_hold_frames` 每帧数：新按下置 1，继续按着 +1，松开归 0。
## 达到 HOLD_TO_CHARGE_FRAMES 就是"按住" → 蓄力斩；否则按点按处理。
func _resolve_light_press() -> bool:
	if not air_combo.is_empty() and not is_on_floor():
		if not _has_edge(&"attack_light"):
			# 上一刀起手的那次按键一直没松：接招点到了也转蓄力
			if _should_charge_on_hold():
				_start_charge()
				return true
			return false
		var finisher := _wants_air_finisher()
		if finisher != &"":
			_start_air_finisher(finisher)
			return true
		match _air_light_hold_state():
			-1:
				return false
			1:
				_start_charge()
				return true
		_take_edge(&"attack_light")
		_start_air_combo_move()
		return true
	if _should_charge_on_hold():
		# 两种情况都算"按住"：
		#   a) 边沿还在（还没出过招）→ 直接消费边沿进蓄力
		#   b) 边沿已经被这一刀消费掉了（点按下去了，但手指没松）→ 也进蓄力
		# (b) 是"点按第三下之后继续按住"能转蓄力的关键：
		#     那时 `_has_edge` 已经是 false，只有靠按住的计时器才认得出来。
		_take_edge(&"attack_light")
		_start_charge()
		return true
	if not _has_edge(&"attack_light"):
		return false
	_link_into(&"attack_light")
	return true


## 后摇取消：把连段指针推进一位再接下一招。
##
## 三条分支：
##   · K（远程）—— 直接放，【不动连段指针】，所以连段被"存"下来
##   · 按住 J  —— 接强化普攻（第三段）或继续接下一段
##   · 点按 J  —— 推进一段
func _link_into(action: StringName) -> void:
	if action == &"attack_ranged":
		_take_edge(&"attack_ranged")
		_start_ranged()
		return
	if action == &"charge":
		_start_charge()
		return
	if action == &"parry":
		_take_edge(&"parry")
		_begin_guard_or_parry()
		return
	var edge_frame := _unconsumed_edge_frame(&"attack_light")
	_take_edge(&"attack_light")
	var frame_ctx := input_buffer.frame_at(0)
	# 方向以【按下 J 的那一帧】为准（或者现在还按着）：连段里缓冲的 W+J，
	# 等取消窗口打开时手早就松开 W 了，只看当前帧会被误判成普通第三刀。
	var aim_up := (frame_ctx != null and frame_ctx.actions.has(&"aim_up")) \
			or (edge_frame != null and edge_frame.actions.has(&"aim_up"))
	if aim_up and up_strike_move != null:
		_start_move(up_strike_move, true)
		return
	if light_combo.is_empty():
		return
	if combat_rework_enabled and light_combo.size() >= 4 and _consume_keen_edge():
		combo_index = light_combo.size() - 1
		_rework_next_light = 0
		_rework_combo_timer = 0
		var kmv: Resource = light_combo[combo_index]
		_start_move(kmv, false, &"", true)
		move_frame = mini(3, maxi(int(kmv.startup_frames) - 2, 0))
		_check_swing_cue(kmv)
		return
	# 终结段后面再按 J 回到第一段；实战下统一按 _rework_next_light 推进，被打断与正常连按共享同一续连指针
	if combat_rework_enabled:
		combo_index = _rework_next_light if _rework_combo_timer > 0 else 0
	elif current_move != null and _is_light_finisher(current_move):
		combo_index = 0
	else:
		combo_index = mini(combo_index + 1, light_combo.size() - 1)
	_start_move(light_combo[clampi(combo_index, 0, light_combo.size() - 1)], false)


func _end_attack() -> void:
	var guard_reaction := guard_reactions.has(current_move) or parry_reactions.has(current_move)
	var ended_finisher := current_move != null and _is_light_finisher(current_move)
	_reaction_guard_held = false
	_keen_swing_active = false
	current_move = null
	current_is_up = false
	state = State.NEUTRAL
	frames_since_attack = 0
	# 连段指针的规则：实战开启「被打断也继续」，窗口内无论挥空、取消还是穿插其他招式均保留下一段进度
	if combat_rework_enabled:
		combo_index = _rework_next_light if _rework_combo_timer > 0 else 0
	elif not last_swing_hit or ended_finisher:
		combo_index = 0   # 第三段打完（打中也一样）下一刀从第一段起
	link_open = false
	var last_input := input_buffer.frame_at(0)
	if guard_reaction and last_input != null and last_input.actions.has(&"parry"):
		_start_guard(false)


## 她自己身体的半宽半高（受击盒，中心在她原点；读不到时按 50×156）
func _body_half_size() -> Vector2:
	if _hurtbox != null:
		var cs := _hurtbox.get_node_or_null(^"CollisionShape2D") as CollisionShape2D
		if cs != null and cs.shape is RectangleShape2D:
			return (cs.shape as RectangleShape2D).size * 0.5
	return Vector2(25.0, 78.0)


func _do_hit_check(mv: Resource) -> void:
	if _melee == null:
		return
	for area in _melee.get_overlapping_areas():
		if area == null or area == _hurtbox:
			continue
		var owner_node := area.get_parent()
		if owner_node == null or owner_node == self:
			continue
		if _hit_this_swing.has(owner_node.get_instance_id()):
			continue
		if not owner_node.has_method(&"take_hit"):
			continue
		if owner_node.get("hp") != null and float(owner_node.get("hp")) <= 0.0 and not bool(owner_node.get("overkilled")):
			continue
		# 只打身前（朝向那一侧），避免背对敌人也能命中；但和她身体重合、身后不到一个身位的照样算
		# （判定盒后沿已经盖到身后 MELEE_BACK_REACH，这里只挡掉更远的背后目标）
		var dx: float = owner_node.global_position.x - global_position.x
		if dx * float(facing) < -(MELEE_BACK_REACH + 50.0):
			continue

		_hit_this_swing[owner_node.get_instance_id()] = true
		var point: Vector2 = (global_position + owner_node.global_position) * 0.5
		# 空中冲刺斩：记住砍中的敌人，冲过它以后再停（见 _try_dash_cross_stop）
		if not is_on_floor() and current_move != null \
				and is_dash_move(current_move) \
				and (_dash_cross_target == null or not is_instance_valid(_dash_cross_target)):
			_dash_cross_target = owner_node
		var hp_before: Variant = owner_node.get(&"hp")
		var shell_before: float = float(owner_node.get(&"shell_hp")) if owner_node.get(&"shell_hp") != null else 0.0
		var state_before: int = int(owner_node.get(&"state")) if owner_node.get(&"state") != null else -1
		var keen_mul := 1.75 if (combat_rework_enabled and _keen_swing_active) else 1.0
		var parried: bool = owner_node.take_hit(mv, facing, point, _charge_t, current_is_up, attack_damage_mul * keen_mul, self)
		if parried:
			continue
		var dealt_or_overkill := (hp_before != null and float(owner_node.get(&"hp")) < float(hp_before)) \
				or bool(owner_node.get(&"overkilled"))
		if dealt_or_overkill and (owner_node.is_in_group(&"shade") or owner_node.is_in_group(&"dummy")):
			_on_melee_mobility_hit(mv)
			_count_air_jump_refund(mv)
		last_swing_hit = true
		swing_hit_count += 1
		# Apply the attacker's pause on a real hit, not only when this actor receives damage.
		# 穿透招式只在第一次命中停，路上后面的敌人照样受击，但自己不再一顿一顿。
		if not mv.hitstop_first_only or swing_hit_count == 1:
			var charge_bonus := roundi(mv.charge_hitstop_bonus * _charge_t)
			hitstop_frames = maxi(hitstop_frames, mv.hitstop_frames + charge_bonus)
			hitstop_this_tick = hitstop_frames > 0
		_set_visual_scale(mv.squash)
		_squash_timer = 5 if combat_rework_enabled else 2
		if combat_rework_enabled and ult_frame < 0 and (not mv.hitstop_first_only or swing_hit_count == 1):
			var shell_after: float = float(owner_node.get(&"shell_hp")) if owner_node.get(&"shell_hp") != null else 0.0
			var state_after: int = int(owner_node.get(&"state")) if owner_node.get(&"state") != null else -1
			var mid_hit := StringName(mv.get(&"id"))
			if (shell_before > 0.0 and shell_after > 0.0) or (state_before == 10 and state_after == 10):
				_hit_recoil_x = -float(facing) * 18.0
				_hit_recoil_vel_x = float(facing) * 240.0
			elif _keen_swing_active or mid_hit in [&"light_4", &"air_light_4", &"combo_k_cleave", &"combo_k_launch", &"combo_k_pierce", &"combo_k_pierce_left", &"charge_1"] or finisher_intent != &"":
				_hit_recoil_x = -float(facing) * 16.5
				_hit_recoil_vel_x = float(facing) * 660.0
				_squash_timer = 6
			elif mid_hit in [&"light_3", &"air_light_3"]:
				_hit_recoil_x = -float(facing) * 12.5
				_hit_recoil_vel_x = float(facing) * 480.0
			else:
				_hit_recoil_x = -float(facing) * 9.0
				_hit_recoil_vel_x = float(facing) * 360.0
			_sync_visual_pivot()
		hit_confirmed.emit(owner_node, mv, point)


func _on_melee_mobility_hit(mv: Resource) -> void:
	if not is_on_floor() and not mv.is_ranged() and finisher_intent == &"":
		if combat_rework_enabled:
			var mid := StringName(mv.get(&"id")) if mv != null else &""
			if mid == &"air_light_4" or mv == air_up_move:
				if _air_slow_hit_tick != tick_count:
					_air_slow_hit_tick = tick_count
					# 强化空普命中：仅在本次腾空/追影首轮或锋芒触发时刹停下坠并给 5 帧缓冲；不按跳/追影直接复读第 2 次空 A4 时零刹车与减重
					if mv == air_up_move or _keen_swing_active or not _air_a4_braked_this_flight:
						_air_a4_braked_this_flight = true
						if velocity.y > 90.0:
							velocity.y = 90.0
						_air_hit_slow_frames = maxi(_air_hit_slow_frames, 5)
				return
			if mid in [&"air_light_1", &"air_light_2", &"air_light_3"]:
				if _air_slow_hit_tick != tick_count:
					_air_slow_hit_tick = tick_count
					_air_normal_hit_chain += 1
					# 削弱普通普攻滞空：单次起跳/追影内前 3 刀递减微缓冲（6→4→3 帧）刚好衔接第 4 刀强普，第 4 刀起不按跳/追影直接零减重坠地
					if hit_fall_slow_frames > 0 and _air_normal_hit_chain <= 3:
						var frames_lut := [6, 4, 3]
						var scale_lut := [0.55, 0.70, 0.80]
						_air_hit_slow_frames = maxi(_air_hit_slow_frames, int(frames_lut[_air_normal_hit_chain - 1]))
						if velocity.y > 0.0:
							velocity.y *= float(scale_lut[_air_normal_hit_chain - 1])
				return
		if hit_fall_slow_frames > 0 and _air_slow_hit_tick != tick_count:
			_air_slow_hit_tick = tick_count
			_air_hit_slow_frames = hit_fall_slow_frames
			if velocity.y > 0.0:
				velocity.y *= hit_fall_speed_scale


## 打中返还空中跳（11-12 重做：普通普攻命中绝不给跳，强化普攻命中才给跳）：
##   · 实战重做模式下：普通普攻（light_1..3 / air_light_1..3）一律不返还跳跃；
##     唯有强化普攻（地面第 4 段 light_4 / 空中第 4 段 air_light_4，含紫电锋芒直出强普）及专门追空招命中 → +1 段跳
##   · 训练场旧模式下保持原契约不变
func _count_air_jump_refund(mv: Resource) -> void:
	var mid := StringName(mv.get(&"id")) if mv != null else &""
	if combat_rework_enabled:
		if mid in [&"light_1", &"light_2", &"light_3", &"air_light_1", &"air_light_2", &"air_light_3"]:
			return
		if (light_combo.has(mv) and mid != &"light_4") or (air_combo.has(mv) and mid != &"air_light_4"):
			return
	var is_dash := is_dash_move(mv)
	var airborne_move := (mid == &"air_light_4" or mv == air_up_move) if combat_rework_enabled else (air_combo.has(mv) or mv == air_up_move)
	var air_like := true
	var need := 0
	if airborne_move:
		need = air_hit_refund_hits
	elif mv == up_strike_move or mv == combo_k_launch_move or mid == &"light_4":
		need = launcher_refund_hits
	elif is_dash:
		# 只认 _dash_in_air（出招那一帧定的），不去看当前 is_on_floor：
		# 冲刺到台边那一帧脚已经离地，那样会被当成空中冲刺斩白送一段跳
		if _dash_in_air:
			need = air_hit_refund_hits      # 空中冲刺斩：和空中招式同一套
		else:
			need = air_jump_refund_hits     # 地面冲刺斩：默认 0
			air_like = false
	else:
		return
	if need <= 0:
		return
	if air_like:
		_refund_hits_air += 1
		if _refund_hits_air < need:
			return
		_refund_hits_air = 0
	else:
		_refund_hits += 1
		if _refund_hits < need:
			return
		_refund_hits = 0
	if bonus_air_jumps >= air_jump_refund_max:
		return
	bonus_air_jumps += 1
	air_jump_refunded.emit(bonus_air_jumps)


func _is_light_move(mv: Resource) -> bool:
	return light_combo.has(mv)


func _is_light_finisher(mv: Resource) -> bool:
	return not light_combo.is_empty() and mv == light_combo[light_combo.size() - 1]


# ---------------------------------------------------------------- LAUNCHED

## 被击飞：自己积分位移，撞到东西立刻结算二次伤害（设计文档 §2.1）。
func _process_launched(delta: float) -> void:
	var speed_before := velocity.length()
	var col := move_and_collide(velocity * delta)

	if col != null:
		var normal := col.get_normal()
		var impact := speed_before
		var impact_pos: Vector2 = global_position + col.get_travel()
		# 同 dummy.gd：贴地时引擎会报一个法线朝上的碰撞，即便正在向上飞。
		# 速度与法线同向 = 正在离开该表面 → 跳过碰撞响应，否则起跳/上挑会被吃掉。
		if velocity.dot(normal) <= 0.0:
			if impact >= min_wall_impact_speed:
				var wall_damage := _wall_damage_for(impact)
				hp -= wall_damage
				hitstop_frames = maxi(hitstop_frames, roundi(12 * hitstop_multiplier))
				_squash_timer = 8
				_set_visual_scale(Vector2(0.72, 1.32))
				if current_move != null:
					hit_confirmed.emit(self, current_move, impact_pos)
				# 撞墙的对外事件。以前这里只有画面反馈，PVP 的记分/播报需要信号。
				wall_slam.emit(impact, wall_damage, impact_pos)
				if hp <= 0.0:
					if can_die:
						_die()
					else:
						_enter_down()
					return
			# 水平撞墙 → 弹回；地面 → 停住
			if absf(normal.x) > 0.7:
				velocity.x = velocity.x * -wall_restitution
				velocity.y *= 0.86
			elif normal.y < -0.7:
				# 落地：弹跳一次（设计文档 §2.1 第 5 步，restitution ≈ 0.3）
				if absf(velocity.y) > 220.0:
					velocity.y = -absf(velocity.y) * wall_restitution
				else:
					velocity.y = 0.0
					_enter_down()
					return
			else:
				velocity = velocity.bounce(normal) * wall_restitution

	velocity.y += knock_gravity * gravity_scale_launched * delta
	velocity.x = move_toward(velocity.x, 0.0, 260.0 * delta)

	if absf(velocity.x) < 12.0 and is_on_floor():
		_enter_down()


## 撞墙二次伤害 = 撞墙速度 × 招式系数 × 全局缩放。
func _wall_damage_for(impact_speed: float) -> float:
	var factor := 0.5
	if current_move != null:
		factor = current_move.wall_damage_factor
	return impact_speed * factor * wall_damage_scale


## 真正的死亡。只有 can_die = true 时才走到这里（PVP）。
## DEAD 状态下 _physics_process 什么都不做 —— 尸体不会滑动、不会被打。
func _die() -> void:
	_interrupt_action_flow()
	state = State.DEAD
	hp = 0.0
	velocity = Vector2.ZERO
	hitstop_frames = 0
	charge_frames = -1
	_charge_accum = 0.0
	var death_frames: Array = get_meta("character", {}).get("sprite", {}).get("animations", {}).get("death", {}).get("frames", [])
	_set_visual_scale(Vector2.ONE if not death_frames.is_empty() else Vector2(1.40, 0.45))
	died.emit()


func _enter_down() -> void:
	_interrupt_action_flow()
	if _soft_knock and hp > 0.0 and state == State.LAUNCHED:
		# 轻击：落地就站稳，马上能动（短无敌防止被连着打到起不来）
		_soft_knock = false
		state = State.NEUTRAL
		combo_index = (_rework_next_light if _rework_combo_timer > 0 else 0) if combat_rework_enabled else 0
		velocity.x *= 0.3
		_set_visual_scale(Vector2(1.12, 0.9))
		_squash_timer = 4
		invuln_frames = maxi(invuln_frames, soft_recover_invuln)
		return
	_soft_knock = false
	state = State.DOWN
	down_frames = hard_down_frames
	velocity = Vector2.ZERO
	_set_visual_scale(Vector2(1.25, 0.72))
	_squash_timer = 0
	# 【一次性预支整段无敌窗口】而不是在 _process_down 里逐帧续期。
	# take_hit 只看 invuln_frames 这一个数，预支出去之后这段窗口就是连续、
	# 不可被打断的；逐帧续则会在"起身那一帧"露出一个空档，又被打回倒地。
	if getup_invuln_frames > 0:
		invuln_frames = maxi(invuln_frames, down_frames + getup_invuln_frames)


func _process_down(delta: float) -> void:
	_apply_gravity(delta, knock_gravity)
	velocity.x = move_toward(velocity.x, 0.0, 900.0 * delta)
	move_and_slide()
	down_frames -= 1
	if down_frames <= 0:
		state = State.NEUTRAL
		combo_index = (_rework_next_light if _rework_combo_timer > 0 else 0) if combat_rework_enabled else 0
		_set_visual_scale(Vector2.ONE)
		hp = maxf(hp, 1.0)


# ---------------------------------------------------------------- 对外接口

## 被击中。由攻击方调用。
##
## attacker 是**弹刀唯一的判定依据**：处于招架判定帧 + 知道是谁打的
## → 把这一下弹回去（自己不吃伤害，攻击者后仰硬直）。
##
## 【为什么允许 attacker 为 null】撞墙/环境伤害没有攻击者。那种情况一律
## **不能**被招架 —— 否则贴着墙一直按 L 就无敌了。
## 【为什么返回 bool】调用点要靠它区分"打中了"和"被弹开了"：
## 命中音/火花是"我砍中你了"的语义，被弹开时一个字都不能播。
## 返回 true = 被弹开了（没有造成伤害）。
##
## 【签名必须和 dummy.gd / enemy.gd 完全一致】三个类共用同一批调用点
## （player._do_hit_check / enemy._resolve_attack / projectile._resolve_hit）。
## 少一个参数，报错只有一行 "Invalid call to function 'take_hit' ... Expected
## N argument(s)"，表现却是"玩家永远打不死怪"。
func take_hit(mv: Resource, from_facing: int, _point: Vector2, _charge: float = 0.0,
		_from_up: bool = false, damage_mul: float = 1.0, attacker: Node = null) -> bool:
	if state == State.DEAD or invuln_frames > 0:
		return false
	# ---- 弹刀 ----
	# 【为什么还要求 has_method(&"on_parried")】attacker 只是个 Node（也可能是
	# 弹丸、是别的东西）。弹不动的东西就【不消耗】判定窗口，按普通受击处理 ——
	# 否则"打到一个弹不动的东西"反而让自己白吃一顿打，玩家读不出来为什么。
	if attacker != null and attacker.has_method(&"on_parried") and is_parrying() \
			and (not _guard_active or from_facing == -facing):
		_do_parry(attacker, _point)
		return true
	if is_guarding() and from_facing == -facing:
		hp -= mv.damage * damage_mul * clampf(float(_guard_config().get("damageMultiplier", 0.0)), 0.0, 1.0)
		if hp <= 0.0:
			if can_die:
				_die()
			else:
				_enter_down()
		else:
			_do_block(attacker, _point)
		return true
	if has_super_armor():
		# 霸体：照样掉血，但不打断、不击飞（只给一下受击形变）
		hp -= mv.damage * damage_mul
		_set_visual_scale(Vector2(1.08, 0.94))
		_squash_timer = 2
		if hp <= 0.0:
			charge_frames = -1
			_charge_accum = 0.0
			if can_die:
				_die()
			else:
				_enter_down()
		return false
	_interrupt_action_flow()
	hitstop_frames = maxi(hitstop_frames, mv.victim_hitstop_frames)
	# damage_mul 让"怪物原型倍率 / PVP 全局伤害缩放 / 突然死亡"三者能在
	# 不改招式数据的前提下叠乘。默认 1.0 → 既有 PVE 调用完全不受影响。
	hp -= mv.damage * damage_mul
	_set_visual_scale(Vector2(mv.squash.x, mv.squash.y))
	_squash_timer = 2
	if hp <= 0.0:
		if can_die:
			_die()
		else:
			_enter_down()
		return false
	current_move = mv
	state = State.LAUNCHED
	velocity = mv.knockback_velocity(from_facing)
	_soft_knock = soft_knock_threshold > 0.0 and not mv.forces_launch and velocity.length() < soft_knock_threshold
	# 被击退时朝向攻击者
	_set_facing(-from_facing)
	return false


## 霸体（11-01 用户）：蓄力中、以及蓄力斩整招（前摇到收招）里挨打只掉血，不被打断。
func has_super_armor() -> bool:
	if state == State.DEAD:
		return false
	if charge_frames >= 0:
		return true
	return state == State.ATTACK and (
		(charge_move != null and current_move == charge_move)
		or (combo_k_cleave_move != null and current_move == combo_k_cleave_move)
	)


## 现在处于"招架判定帧"吗 —— 弹刀唯一的**时间**条件。
##
## 【为什么每次去问招式数据】窗口长度就是 .tres 里的 active_frames。
## 在工坊里把它从 4 改成 6，判定当场变宽，代码一行不用动。
## 走的又是 MoveDefinition.is_parry_move()，所以"哪种招式算招架"
## 全项目只有一个来源（加"上段弹刀"不用改这里）。
func is_parrying() -> bool:
	if _guard_active:
		return not _guard_parried and _guard_frames < maxi(int(_guard_config().get("parryWindowFrames", 0)), 0)
	if guard_reactions.has(current_move) or parry_reactions.has(current_move):
		return false
	if state != State.ATTACK or current_move == null:
		return false
	if not _is_parry_move(current_move):
		return false
	return current_move.phase_at(move_frame) == &"active"


## 现在在不在【整个弹刀招】里（前摇 + 判定 + 后摇）—— 表现层绑精灵表用的是这个。
##
## 【为什么表现层不该用 is_parrying()】那是 4 帧的窗口。拿它去换精灵表，前摇与
## 后摇就会掉回连段表（弹刀不在 light_combo 里，combo_index 恒为 0）→ 播成 attack_1。
## 于是整招看起来是"挥一刀 → 换个人 → 再挥一刀"（实测逐帧：
## attack_1 ×3 → parry ×4 → attack_1 ×12）。而 is_parrying() 仍然只回答
## "判定窗口开没开"，两件事各归各的接口。
func is_in_parry() -> bool:
	if _guard_active:
		return true
	if state != State.ATTACK or current_move == null:
		return false
	return _is_parry_move(current_move)


## 这是不是一个弹刀招式（跨脚本拿到的招式静态类型是 Resource，所以先问 has_method）。
func _is_parry_move(mv: Resource) -> bool:
	if mv == null:
		return false
	if mv.has_method(&"is_parry_move"):
		return bool(mv.call(&"is_parry_move"))
	return false


## 招架成功。**不结算任何伤害**，只把"该弹谁"转交出去 + 给自己一点表现。
##
## 【为什么要给自己顿帧】没有这一下，弹开的"实感"全靠音效撑；
## 而且顿帧期间玩家也动不了 —— 挡住的那一瞬间本就该有一拍静止。
func _do_parry(attacker: Node, point: Vector2) -> void:
	if _guard_active:
		_guard_parried = true
		_play_guard_reaction(parry_reactions, true)
	hitstop_frames = maxi(hitstop_frames, parry_hitstop_frames)
	hitstop_this_tick = hitstop_frames > 0
	if not _reaction_guard_held:
		set(&"velocity", Vector2(velocity.x * 0.2, velocity.y))
	_set_visual_scale(Vector2(1.16, 0.88))
	_squash_timer = 5
	# 弹开算"有效动作"：连段指针不该因为这一下被当成挥空而归零
	last_swing_hit = true
	refund_shadow(max_shadow_charges)
	if combat_rework_enabled:
		_grant_flash_heavy(flash_heavy_duration)
		_grant_keen_edge(keen_edge_duration)
	attacker.call(&"on_parried", self)
	parry_success.emit(attacker, point)


## 被别人弹开（PVP：我打过去、对面按了 L）。
##
## 【为什么复用 LAUNCHED 而不是给玩家新开一个"硬直"状态】player.gd 没有
## STUNNED，而"被弹开后仰"必须是一段**不能出招**的时间。LAUNCHED 是现成的、
## 已经被 108 项手感测试覆盖过的路径，复用它比自己新造一个状态安全得多。
## PVE 里敌人不会招架，所以这条路径只在 PVP 生效。
func on_parried(cause: Node = null) -> void:
	if state == State.DEAD:
		return
	_interrupt_action_flow()
	# 蓄力中被打断时【必须清掉】charge_frames：_physics_process 里蓄力分支
	# 排在状态机之前，不清的话人会一边被弹飞一边继续蓄力。
	charge_frames = -1
	_charge_accum = 0.0
	var dir := -float(facing)
	# 【必须判 cause is Node2D】形参类型是 Node（attacker 通道共用），
	# 而"能被打的东西"未必有世界坐标。
	if cause != null and is_instance_valid(cause) and cause is Node2D:
		var d: float = global_position.x - (cause as Node2D).global_position.x
		if absf(d) > 0.5:
			dir = signf(d)
	hitstop_frames = maxi(hitstop_frames, roundi(14 * hitstop_multiplier))
	_set_visual_scale(Vector2(0.88, 1.16))
	_squash_timer = 6
	# current_move 置空：不然 _process_launched 里的撞墙结算会拿"上一个招式"
	# 的墙伤系数来算，还会朝外面发一条语义不对的 hit_confirmed。
	current_move = null
	current_is_up = false
	state = State.LAUNCHED
	velocity = Vector2(dir * 240.0, -150.0)
	_set_facing(-int(dir))


func reset_state(pos: Vector2) -> void:
	_interrupt_action_flow()
	ult_frame = -1
	ult_energy = 0.0
	ult_clip = ""
	ult_pose = -1
	_reset_ult_flow()
	action_idle_frames = 0
	global_position = pos
	velocity = Vector2.ZERO
	hp = max_hp
	shadow_charges = max_shadow_charges
	_shadow_regen_timer = 0.0
	_short_dash_ticks = 0
	if flash_heavy_timer > 0.0:
		flash_heavy_timer = 0.0
		flash_heavy_ready_changed.emit(false)
	if keen_edge_timer > 0.0:
		keen_edge_timer = 0.0
		keen_edge_ready_changed.emit(false)
	_keen_swing_active = false
	_keen_cross_locks.clear()
	ranged_cooldown = 0
	_post_dash_window = 0
	_post_dash_was_pursuit = false
	_pursuit_target = null
	_pursuit_offset = Vector2.ZERO
	_dash_preserving_charge = false
	_dash_passed_enemy = null
	_perfect_dodge_locks.clear()
	_charge_action = &"attack_light"
	_heavy_hold_frames = 0
	_air_normal_hit_chain = 0
	_air_a4_braked_this_flight = false
	shadow_changed.emit(shadow_charges, max_shadow_charges)
	state = State.NEUTRAL
	current_move = null
	current_is_up = false
	move_frame = 0
	combo_index = 0
	_rework_next_light = 0
	_rework_combo_timer = 0
	_rework_next_air = 0
	_rework_air_combo_timer = 0
	link_open = false
	last_swing_hit = false
	frames_since_attack = 100
	charge_frames = -1
	_charge_t = 0.0
	_charge_accum = 0.0
	last_charge_frames = 0
	invuln_frames = 0
	_consumed_edge.clear()
	_frame_queue.clear()
	_sticky_frame = null
	hitstop_frames = 0
	hitstop_this_tick = false
	_attack_hold_frames = 0
	_squash_timer = 0
	_hit_recoil_x = 0.0
	_hit_recoil_vel_x = 0.0
	down_frames = 0
	ground_frames = 0
	air_frames = 0
	_air_jumps_left = extra_air_jumps
	_refund_hits = 0
	_refund_hits_air = 0
	bonus_air_jumps = 0
	_ground_jump_used = false
	_air_light_left = air_light_uses
	_air_dash_left = air_dash_uses
	_jump_buffer_counter = 0
	_uppercut_jump_pending = false
	_uppercut_used_light_seq = -1
	_last_jump_frame = -1000
	_last_jump_from_up = false
	_last_jump_is_uppercut = false
	_space_was_held = _pure_jump_down()
	_air_hit_slow_frames = 0
	_air_slow_hit_tick = -1
	_jump_buffer_tick = -1
	if not is_nan(_drop_from_y):
		_drop_from_y = NAN
		collision_mask |= one_way_mask
	input_buffer.clear()
	_sync_melee_offset()      # 复活/换边后判定盒要重新贴回当前朝向
	if _visual != null:
		_visual.scale = Vector2(float(facing), 1.0)
		_sync_visual_pivot()


func combat_intent() -> StringName:
	return finisher_intent if state == State.ATTACK else &""


func _wants_air_slam(frame: InputBuffer.Frame) -> bool:
	return frame != null and frame.axis.y > 0.5 and not air_combo.is_empty() \
			and not is_on_floor()


## 空中已经出过至少一刀后，按住前方 + J：直接出横扫终结（把敌人水平打飞去撞墙/撞人）
## 实战模式（1A）下主动横轰由独立重击键 K 负责，确保按着方向键追怪点 J 能打满四连直出空中强普
func _wants_air_drive(frame: InputBuffer.Frame) -> bool:
	if combat_rework_enabled:
		return false
	return frame != null and frame.axis.x * float(facing) > 0.5 and absf(frame.axis.y) < 0.5 \
			and not air_combo.is_empty() and air_combo_index >= 1 \
			and not is_on_floor()


func _wants_air_finisher() -> StringName:
	var edge := _unconsumed_edge_frame(&"attack_light")
	var now := input_buffer.frame_at(0)
	if _wants_air_slam(now) or _wants_air_slam(edge):
		return &"slam"
	if _wants_air_drive(edge) or (edge == null and _wants_air_drive(now)):
		return &"drive"
	return &""


func _start_air_slam() -> void:
	_start_air_finisher(&"slam")


func _start_air_finisher(intent: StringName) -> void:
	_air_hit_slow_frames = 0
	_take_edge(&"attack_light")
	if combat_rework_enabled:
		_take_edge(&"attack_heavy")
		_post_dash_window = 0
		_post_dash_was_pursuit = false
		_dash_passed_enemy = null
		var latest := input_buffer.frame_at(0)
		if latest != null and absf(latest.axis.x) > 0.15:
			_set_facing(1 if latest.axis.x > 0.0 else -1)
	air_combo_index = air_combo.size()
	# 11-03 用户：“下落攻击我希望有单独动作模组”——下砸用自己的招式资源（air_plunge），
	# 不再借用空中第三刀；没配才退回旧行为。空中 K 横轰（drive）保持借用 air_combo[2] 横斩模组。
	var move: Resource = null
	if intent == &"slam" and air_plunge_move != null:
		move = air_plunge_move
	if move == null and not air_combo.is_empty():
		if combat_rework_enabled and intent == &"drive" and air_combo.size() >= 3:
			move = air_combo[2]
		else:
			move = air_combo[air_combo.size() - 1]
	_start_move(move, false, intent)
	finisher_intent = intent
	if intent == &"slam":
		velocity.y = maxf(velocity.y, PLUNGE_SPEED)


func is_busy() -> bool:
	return state != State.NEUTRAL or _short_dash_ticks > 0

func is_in_hitstop() -> bool:
	return hitstop_frames > 0 or hitstop_this_tick


func debug_state_name() -> String:
	if charge_frames >= 0:
		return "CHARGING(%d)" % charge_frames
	if is_parrying():
		return "PARRY"
	match state:
		State.NEUTRAL: return "NEUTRAL"
		State.ATTACK: return "ATTACK"
		State.LAUNCHED: return "LAUNCHED"
		State.DOWN: return "DOWN"
		State.DEAD: return "DEAD"
	return "?"


func is_charging() -> bool:
	return charge_frames >= 0


# ---------------------------------------------------------------- 表现

func _set_facing(dir: int) -> void:
	if dir == 0:
		return
	display_facing = dir
	if dir == facing:
		# 【为什么"方向没变"也要贴一次判定盒】facing 是个公开 var，
		# 任何一处裸写（`player.facing = 1`）都会绕开这个函数 ——
		# 于是出现"人朝右、判定盒在左"的失配，而且再也修不回来：
		# 之后每次 _set_facing(1) 都会在这里提前 return。
		# 症状和 §_sync_melee_offset 注释里那次完全一样（近战全挥空），
		# 只是这次的触发路径是"外部直接写字段"。
		# 实测：M0 集成套件因此稳定红 10 条（上挑不飞 / 蓄力 0 伤害 / 连段被挥空重置）。
		# 这一行在正常流程里是幂等的（本来就已经贴好了），所以不动手感。
		_sync_melee_offset()
		return
	facing = dir
	_sync_melee_offset()
	if _visual != null:
		_visual.scale.x = absf(_visual.scale.x) * float(facing)


## 近战判定盒跟着朝向翻面。
##
## 【不修会怎样】MeleeHitbox 是场景里的固定节点（player.tscn 里 position.x = +52），
## 而"翻面"以前只翻了 Visual 这一个子节点 —— 判定盒和 Visual 是兄弟，
## 于是**玩家朝左时判定盒仍然留在右侧**，左边的任何东西都打不到。
## 实测（tools/_probe_side.gd，受控实验：同一个木桩、同样的 70px 距离、同样的点按 J）：
##   朝右 → 木桩 320 → 294.3
##   朝左 → 木桩 320 → 320.0（一滴血不掉）
## 这是"我明明贴着怪打，就是不中"的那类 bug，玩家最不能忍，
## 而且在机器人试玩里伪装成了"击杀数看运气"（命中率 0.3%）——
## 排查了很久才定位到朝向，所以这条注释写长一点。
##
## 【为什么用 _melee_base_offset_x 而不是直接 *= -1】反复翻面时连乘会让偏移
## 指数级缩水（52 → -52 → 52 看着没事，但一旦有中间态就会漂）。用绝对值基准最稳。
## 基准值在 _ready 里从场景节点读，所以设计师在编辑器里挪判定盒也不会被这条逻辑顶掉。
func _sync_melee_offset() -> void:
	if _melee != null:
		_melee.position.x = _melee_base_offset_x * float(facing)
	# 调试视图一起翻 —— 否则它会画在"判定盒真正所在的位置"的另一边，
	# 让人按错误的画面调手感（DebugDraw 只是可视化，不参与判定）。
	var dbg := get_node_or_null("DebugDraw/MeleeShape")
	if dbg is Node2D:
		(dbg as Node2D).position.x = _melee_base_offset_x * float(facing)


func _set_visual_scale(s: Vector2) -> void:
	if _visual == null:
		return
	var adjusted := Vector2.ONE + (s - Vector2.ONE) * squash_strength
	_visual.scale = Vector2(absf(adjusted.x) * float(facing), adjusted.y)
	_sync_visual_pivot()


func _lerp_visual_scale(t: float) -> void:
	if _visual == null:
		return
	var target := Vector2(1.0 * float(facing), 1.0)
	_visual.scale = _visual.scale.lerp(target, clampf(t, 0.0, 1.0))
	_sync_visual_pivot()

func _sync_visual_pivot() -> void:
	if _visual == null:
		return
	# Stretch around the foot position, so the detailed sprite does not slide through the floor.
	_visual.position = Vector2(_hit_recoil_x, foot_offset * (1.0 - _visual.scale.y))


# ------------------------------------------------------- Desktop action flow
func _sprite_config() -> Dictionary:
	return get_meta("character", {}).get("sprite", {})

func _start_turn(target: int) -> void:
	var sprite := _sprite_config()
	var config: Dictionary = sprite.get("locomotion", {})
	if not bool(config.get("enabled", false)):
		return
	var raw: Variant = config.get("turnRight" if target > 0 else "turnLeft", "")
	var options: Dictionary = raw if raw is Dictionary else {"animation": str(raw)}
	var animation := str(options.get("animation", ""))
	var clip: Dictionary = sprite.get("animations", {}).get(animation, {})
	if clip.get("frames", []).is_empty():
		return
	_turn_target = target
	_turn_clip = clip
	_turn_options = options
	locomotion_source_facing = facing
	locomotion_animation = animation
	locomotion_clock = 0.0
	locomotion_frame = 0

func _advance_locomotion(delta: float) -> void:
	if locomotion_animation.is_empty():
		return
	if state != State.NEUTRAL or not is_on_floor():
		_cancel_locomotion()
		return
	locomotion_clock += delta * maxf(float(_turn_options.get("playbackSpeed", 1.0)), 0.05)
	locomotion_frame = Timeline.frame_at(_turn_clip, locomotion_clock, -1.0, true, false)
	var flip := int(_turn_options.get("flipFrame", _turn_clip.get("flipFrame", 0)))
	if locomotion_frame >= flip:
		_set_facing(_turn_target)
	if _turn_can_cancel() and input_direction != 0 and input_direction != _turn_target:
		_cancel_locomotion()
		if input_direction != facing:
			_start_turn(input_direction)
			# A missing reverse transition must not retain the obsolete intent.
			if locomotion_animation.is_empty():
				_set_facing(input_direction)
		return
	var duration := Timeline.ticks_before(_turn_clip.get("frames", []), _turn_clip.get("frames", []).size()) / maxf(float(_turn_clip.get("fps", 24)), 0.001)
	if locomotion_clock + 0.000001 >= duration:
		_set_facing(_turn_target)
		_cancel_locomotion()

func _turn_can_cancel() -> bool:
	return locomotion_frame >= int(_turn_options.get("cancelFrame", _turn_clip.get("cancelFrame", 0)))

func _cancel_locomotion() -> void:
	locomotion_animation = ""
	locomotion_clock = 0.0
	locomotion_frame = 0
	_turn_clip = {}
	_turn_options = {}

func _reset_air_combo() -> void:
	air_combo_index = 0
	air_suspend_used = 0

func _start_air_combo_move() -> void:
	if is_on_floor() or air_combo.is_empty():
		return
	if combat_rework_enabled:
		if air_combo.size() >= 4 and _consume_keen_edge():
			air_combo_index = air_combo.size()
			_rework_next_air = 0
			_rework_air_combo_timer = 0
			var kmv: Resource = air_combo[air_combo.size() - 1]
			_start_move(kmv, false, &"", true)
			move_frame = mini(2, maxi(int(kmv.startup_frames) - 2, 0))
			_check_swing_cue(kmv)
			return
		var idx := (_rework_next_air if _rework_air_combo_timer > 0 else 0) % air_combo.size()
		air_combo_index = idx + 1
		_start_move(air_combo[idx], false)
		return
	air_combo_index %= air_combo.size()
	var mv: Resource = air_combo[air_combo_index]
	air_combo_index += 1
	_start_move(mv, false)

func _apply_air_attack_gravity(delta: float, _mv: Resource) -> void:
	if (_mv == charge_move or _mv == combo_k_cleave_move) and _charge_authored_hop:
		return
	if finisher_intent == &"slam" and not is_on_floor():
		# 几乎瞬移：一次就顶到 PLUNGE_SPEED（不再"加速到"），落地那一帧由 move_and_slide 接住
		velocity.y = PLUNGE_SPEED
		return
	# Whiffs follow normal gravity; confirmed hits can briefly slow the descent.
	_apply_gravity(delta, _air_gravity())

func _process_dash_attack(delta: float, mv: Resource, phase: StringName, frame: InputBuffer.Frame = null) -> void:
	# 空中斩中人以后停在敌人另一侧（11-03 用户：“在空中的时候，斩到人就会在敌人另一边停下”）：
	# 停住以后这一招只剩“落下来”，不再按位移曲线往前推。
	if _dash_stopped:
		_process_dash_stopped(delta, mv)
		return
	if _dash_in_air and _dash_cross_target != null and is_instance_valid(_dash_cross_target):
		if _try_dash_cross_stop(_dash_cross_target):
			return
	if phase == &"active":
		_do_hit_check(mv)
		if hitstop_this_tick:
			return
	elif phase == &"recovery" and frame != null and _dash_recovery_cancel(delta, mv, frame):
		return
	# 位移曲线按【动画进度】走（分段变速后，身体在哪一帧，位移就到哪一步）
	var before: float = mv.distance_at(mv.anim_progress(float(move_frame)))
	var after: float = mv.distance_at(mv.anim_progress(float(move_frame + 1)))
	velocity.x = (after - before) * float(_dash_facing) / maxf(delta, 0.000001)
	velocity.x += _root_motion_step(mv) * float(_dash_facing) / maxf(delta, 0.000001)
	_set_facing(_dash_facing)
	if _dash_in_air and phase != &"recovery" and not is_on_floor():
		velocity.y = 0.0    # 空中冲刺斩：冲刺段平着冲出去，后摇再开始下落
	else:
		_apply_gravity(delta, _air_gravity())
	var prev_x := global_position.x
	move_and_slide()
	if combat_rework_enabled and (mv == combo_k_pierce_move or mv == combo_k_pierce_left_move):
		_track_passed_enemy(prev_x)
	move_frame += 1
	if move_frame >= (_air_dash_total(mv) if _dash_in_air else mv.total_frames()):
		var ended_pierce := mv == combo_k_pierce_move or mv == combo_k_pierce_left_move
		_end_attack()
		velocity.x = 0.0
		if ended_pierce and _dash_passed_enemy != null and is_instance_valid(_dash_passed_enemy):
			var bdx := _dash_passed_enemy.global_position.x - global_position.x
			if absf(bdx) > 4.0:
				_set_facing(1 if bdx > 0.0 else -1)
			_dash_passed_enemy = null

## 空中冲刺斩的帧段判定（11-03）：用招式数据的"空中版本"帧数（起手更短、后摇更短），
## 而不是招式原值。地面冲刺斩仍走 `mv.phase_at()`。
func _air_dash_phase(mv: Resource, f: int) -> StringName:
	var a: Dictionary = mv.air_frames()
	var s: int = a.startup
	var total: int = a.total
	if f < s:
		return &"startup"
	if f < s + int(a.active):
		return &"active"
	if f < total:
		return &"recovery"
	return &"done"


## 空中冲刺斩的整招帧数（收招判定用）
func _air_dash_total(mv: Resource) -> int:
	return int(mv.air_frames().total)


## 空中冲刺斩砍中敌人后，从它身上穿过去、在**另一侧**停住。
##
## 【为什么是穿过去再停，而不是原地停】冲刺斩的卖点是“从人身上冲过去”，
## 停在敌人一侧等于把这一招变成了普通突进；停到另一侧才有“错身而过”的爽感，
## 而且停的位置离敌人半个身子多一点，落地后立刻能回头接刀。
## 只在空中生效（`_dash_in_air`）：地面冲刺斩照旧冲完整个距离。
func _try_dash_cross_stop(t: Node2D) -> bool:
	var margin: float = float(t.get(&"half_w")) + 52.0
	var past := (global_position.x - t.global_position.x) * float(_dash_facing)
	if past < margin:
		return false
	# 站到敌人另一侧（不依赖这一帧冲了多远，直接贴到该停的位置，避免高速一帧冲过头）
	global_position.x = t.global_position.x + float(_dash_facing) * margin
	velocity = Vector2.ZERO
	_dash_stopped = true
	_dash_in_air = false          # 冲刺段结束：开始正常下落
	_dash_cross_target = null
	hitstop_frames = maxi(hitstop_frames, 8)
	hitstop_this_tick = true
	# 穿过去以后回头面对它（11-03 用户：“空中冲刺斩能击飞然后……”）：不然人站在敌人另一侧、
	# 朝向还是冲刺方向，接下来那刀会因为"只打身前"直接挥空，等于白穿。
	if absf(t.global_position.x - global_position.x) > 1.0:
		_set_facing(1 if t.global_position.x > global_position.x else -1)
	if current_move != null:
		move_frame = maxi(move_frame, current_move.startup_frames + current_move.active_frames)
	return true


## 停住之后的收尾：不再有位移，只在下落 + 走完后摇。
func _process_dash_stopped(delta: float, mv: Resource) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 6000.0 * delta)
	velocity.y = move_toward(velocity.y, 0.0, 6000.0 * delta) if is_on_floor() else velocity.y
	_apply_gravity(delta, _air_gravity())
	move_and_slide()
	move_frame += 1
	# 这里不再强行把朝向顶回冲刺方向：急停时已经回头面对敌人了，再顶回去就白回头
	if move_frame >= _air_dash_total(mv) or is_on_floor():
		velocity.x = 0.0
		_end_attack()


## 冲刺斩的后摇取消：弹刀 / 跳随时；接招点之后可以 冲刺 / J / K，再晚一点按方向键直接收招。
func _dash_recovery_cancel(delta: float, mv: Resource, frame: InputBuffer.Frame) -> bool:
	if _has_edge(&"parry"):
		_link_into(&"parry")
		return true
	if _try_buffered_jump(frame):
		_end_attack()
		return true
	if not link_open and move_frame >= mv.startup_frames + mv.active_frames + mv.cancel_frame:
		link_open = true
		link_open_count += 1
	if link_open:
		if _try_dash_cancel():
			return true
		if _has_edge(&"attack_ranged"):
			_link_into(&"attack_ranged")
		if combat_rework_enabled and _has_edge(&"attack_heavy"):
			if not is_on_floor():
				_start_air_finisher(&"slam" if _rework_wants_slam(frame) else &"drive")
				return true
			if flash_heavy_timer > 0.0:
				_take_edge(&"attack_heavy")
				_consume_flash_heavy()
				_start_instant_heavy(1.0, 14)
				return true
			_start_heavy_charge(frame)
			if charge_frames >= 0:
				_process_charge(delta, frame)
			return true
		# 空中冲刺斩之后的 J 接空中连段
		if not is_on_floor() and _has_edge(&"attack_light") and _resolve_light_press():
			return true
		if _has_edge(&"attack_light") and not light_combo.is_empty():
			# 实战下冲刺斩突进贴脸后按 J 可接着续连未完成的地面普攻；否则从第一刀起（W+J 仍是上挑）
			if combat_rework_enabled and _rework_combo_timer > 0:
				combo_index = _rework_next_light
			else:
				combo_index = -1
			_link_into(&"attack_light")
			return true
	if _try_move_cancel(mv):
		_process_neutral(delta, frame)
		return true
	return false


## 后摇里按 Shift：直接接一次冲刺斩（方向以按键那一帧为准）。
func _try_dash_cancel() -> bool:
	if combat_rework_enabled or dash_move == null:
		return false
	var f := _unconsumed_edge_frame(&"dash_modifier")
	var dir := _dash_edge_direction(f)
	if dir == 0 or not _dash_allowed():
		return false
	_pending_dash_direction = dir
	_begin_command(&"dash", f)
	return true


## 这一招算不算「空中自由打断」的一员：空中三连 / 空中上挑 / 下落攻击 / 空中冲刺斩。
func _is_air_interrupt_move(mv: Resource) -> bool:
	if mv == null:
		return false
	if is_dash_move(mv):
		return true
	return air_combo.has(mv) or mv == air_up_move or mv == air_plunge_move


## 这一招 / 这条指令是不是「空中攻击」（不含空中冲刺斩）。
func _is_air_attack_move(mv: Resource) -> bool:
	if mv == null:
		return false
	return air_combo.has(mv) or mv == air_up_move or mv == air_plunge_move


func _is_air_attack_command(cmd: StringName) -> bool:
	return cmd in [&"air_combo", &"air_up", &"air_slam", &"air_drive"]


## 这条指令算不算「空中招」（空中冲刺斩 / 空中攻击）。
func _is_air_interrupt_command(cmd: StringName) -> bool:
	if cmd == &"dash" or cmd == &"dash_strike":
		return true          # 人已经在空中，_dash_move_for 会给空中那套
	return _is_air_attack_command(cmd)


## 空中抢招：人在天上时，「空中冲刺斩 / 空中攻击」可以切掉别的招式。
##
## 【为什么不复用 link_open】那套只在前摇/判定过去之后才开窗口，正好和用户要的相反：
## 他要的是"空中冲刺斩能打断任何招式"，也就是出刀起手那一帧就能被抢。
##
## 【唯一的例外：空中攻击不能打断空中攻击】（用户 11-03 补充：“空中攻击应该是能打断空中攻击以外的”）
## 空中三连之间仍然要走正常接招窗口，否则连按 J 就能一路平推，空连没有节奏也没有判定意义。
func _try_air_interrupt(mv: Resource, frame: InputBuffer.Frame) -> bool:
	if is_on_floor():
		return false
	var cmd := _resolve_attack_command(frame)
	# 只有「空中冲刺斩 / 空中攻击」有抢招权：K 远射、弹刀、蓄力仍然不打断空中连段
	# （10-xx 定的"K 不冻结、不回退空中连段"那条规则继续有效）。
	if not _is_air_interrupt_command(cmd):
		return false
	if _is_air_attack_move(mv) and _is_air_attack_command(cmd):
		var heavy_finisher_chain: bool = combat_rework_enabled and _has_edge(&"attack_heavy") \
				and mv != air_plunge_move and finisher_intent == &"" \
				and (last_swing_hit or mv.phase_at(move_frame) == &"recovery")
		if not heavy_finisher_chain:
			return false          # 空中攻击 × 空中攻击：不抢，交给接招窗口
	_begin_command(cmd, frame)
	return true


## 现在能不能放冲刺斩：地上（含土狼时间）随时；空中默认无限（`air_dash_unlimited`），
## 关掉那个开关就回到"每次腾空 air_dash_uses 次"。
func _dash_allowed() -> bool:
	if unlimited_dash:
		return true
	if shadow_cost_enabled and shadow_charges < 1:
		return false
	if is_on_floor() or air_frames <= coyote_frames:
		return true
	return air_dash_unlimited or _air_dash_left > 0


## 冲刺斩用哪一套招式资源：空中用独立的那对（air_dash_*），没配就退回地面那对。
## 11-03 用户：“空中冲刺斩我也希望当成单独动作”——独立资源才能单独给帧数、判定盒，以后单独换动画。
func _dash_move_for(direction: int) -> Resource:
	var use_air := _dash_in_air
	var left: Resource = air_dash_left_move if use_air else dash_left_move
	var right: Resource = air_dash_move if use_air else dash_move
	if left == null:
		left = dash_left_move
	if right == null:
		right = dash_move
	return left if direction < 0 and left != null else right


## 是不是冲刺斩（地面 / 空中各自的招式资源都算）。11-03 起空中冲刺斩是独立招式，
## 所以判"这一发是不是冲刺斩"不能只比 dash_move。
func is_dash_move(mv: Resource) -> bool:
	if mv == null:
		return false
	return mv == dash_move or mv == dash_left_move or mv == air_dash_move or mv == air_dash_left_move \
			or mv == combo_k_pierce_move or mv == combo_k_pierce_left_move


## 冲刺斩键（Shift / 右键 / 手柄 B，动作名沿用 dash_modifier）这一下朝哪边：按着 A / D 就朝那边，
## 没按方向就朝面向；f 为空 = 没按（0）。11-01 用户：“冲刺斩改成 Shift 就行”，不再要 J。
func _dash_edge_direction(f: InputBuffer.Frame) -> int:
	if f == null:
		return 0
	var dir := int(signf(f.axis.x)) if absf(f.axis.x) > 0.15 else 0
	return dir if dir != 0 else facing


## 双击方向 = 冲刺斩（11-03 用户：“冲刺斩改成 aa 或 dd”）。
##
## 【为什么从输入缓冲里找，而不是在 _physics_process 里攒状态】顿帧时
## `_physics_process` 会直接 return，实时攒的"上一次点方向"会在顿帧里过期；
## 缓冲里留着最近几帧的按下边沿，顿帧结束照样认得出这是一次双击。
## 【为什么不复用 dash_modifier】Shift / 右键 / 手柄 B 都还留着当别名，
## 双击是"键盘上更顺手的那个"，老手感不拆。
func _double_tap_direction() -> int:
	var span := mini(input_buffer.frame_count(), double_tap_frames + 2)
	for d in [-1, 1]:
		var act: StringName = &"move_left" if d < 0 else &"move_right"
		var presses: Array[int] = []
		for i in span:
			var f := input_buffer.frame_at(i)
			if f == null or not f.pressed_this_frame.has(act):
				continue
			presses.append(i)          # i 越小越新：presses[0] 是最近一次按下
		if presses.size() < 2:
			continue
		if int(presses[0]) - int(presses[1]) > double_tap_frames:
			continue
		var newest := input_buffer.frame_at(presses[0])
		if newest == null or newest.seq == _double_tap_seq:
			continue               # 这一次双击已经用掉了
		return d
	return 0


## 缓冲里那个方向最近一次按下的 seq（双击出招时用来记账，避免一发双击连出好几刀）
func _newest_press_seq(action: StringName) -> int:
	for i in input_buffer.frame_count():
		var f := input_buffer.frame_at(i)
		if f != null and f.pressed_this_frame.has(action):
			return f.seq
	return -1


## 收招尾巴的"方向键取消"：接招点之后再过 move_cancel_delay 帧，
## 没有待处理的攻击/弹刀输入、又按着方向 → 直接收招，这一帧就开始跑。
## 打中过的话连段指针往前推一格（马上再按 J 接下一刀，而不是从头再来）。
func _try_move_cancel(mv: Resource) -> bool:
	if mv.move_cancel_delay < 0 or not is_on_floor() or input_direction == 0:
		return false
	# 后摇被移动打断的时机：默认是接招点；招式自己写了 move_cancel_after_active 就按"判定段结束 + N 帧"算
	var gate: int = mv.startup_frames + mv.active_frames + mv.cancel_frame + mv.move_cancel_delay
	if mv.move_cancel_after_active >= 0:
		gate = mv.startup_frames + mv.active_frames + mv.move_cancel_after_active
	if move_frame < gate:
		return false
	if _has_edge(&"attack_light") or _has_edge(&"attack_heavy") or _has_edge(&"attack_ranged") \
			or _has_edge(&"parry") or _has_edge(&"dash_modifier") or _has_edge(&"short_dash"):
		return false
	var index := light_combo.find(mv)
	if combat_rework_enabled and index >= 0:
		combo_index = _rework_next_light if _rework_combo_timer > 0 else 0
	elif last_swing_hit and index >= 0:
		combo_index = index + 1 if index + 1 < light_combo.size() else 0
	_end_attack()
	return true


## 这一物理帧的根位移（世界像素，朝前为正）。
## 画面在本帧结束后显示 move_frame+1 对应的动画帧，所以取两帧之差。
func _root_motion_step(mv: Resource) -> float:
	if mv == null or mv.root_motion_x.is_empty():
		return 0.0
	var clip: Dictionary = _sprite_config().get("animations", {}).get(mv.animation, {})
	if clip.is_empty():
		return 0.0
	var n: int = mv.root_motion_x.size()
	if bool(clip.get("rootMotionSmooth", false)):
		# 动画 24 帧/秒、物理 60 帧/秒：按帧取值会一帧猛冲上百像素、接着一两帧不动（一顿一顿）。
		# 平滑版在相邻两帧之间线性插值，每帧开头仍然正好落在该帧的位置。
		return (_root_motion_at(mv, clip, float(move_frame + 1)) - _root_motion_at(mv, clip, float(move_frame))) * mv.root_motion_scale
	var i0 := clampi(Timeline.frame_at(clip, mv.anim_seconds(float(move_frame)), mv.animation_fps, true, false), 0, n - 1)
	var i1 := clampi(Timeline.frame_at(clip, mv.anim_seconds(float(move_frame + 1)), mv.animation_fps, true, false), 0, n - 1)
	return (float(mv.root_motion_x[i1]) - float(mv.root_motion_x[i0])) * mv.root_motion_scale


## 招式第 f 个物理帧时的累计根位移（在当前动画帧和下一帧之间线性插值）。
func _root_motion_at(mv: Resource, clip: Dictionary, f: float, curve: Array = []) -> float:
	var frames: Array = clip.get("frames", [])
	var values: Array = mv.root_motion_x if curve.is_empty() else curve
	var n: int = mini(values.size(), frames.size())
	if n == 0:
		return 0.0
	var seconds: float = mv.anim_seconds(f)
	var i := clampi(Timeline.frame_at(clip, seconds, mv.animation_fps, true, false), 0, n - 1)
	if i >= n - 1:
		return float(values[n - 1])
	var start := Timeline.ticks_before(frames, i)
	var length := maxf(Timeline.duration_ticks(frames[i]), 0.000001)
	var t := clampf((maxf(seconds, 0.0) * mv.animation_fps - start) / length, 0.0, 1.0)
	return lerpf(float(values[i]), float(values[i + 1]), t)


## 贴身刹车（试玩版）：敌人不是物理体、挡不住人，根位移往前推时
## 最多推到"敌人身前 ROOT_MOTION_CONTACT"为止，不会把玩家推到敌人背后导致后续几刀打空。
## 组里的节点需要 half_w 属性，可选 blocks_body() 方法（死了/还没出场就不挡）。
## root_motion_block_group 为空（训练场）时完全不生效。
func _clamp_root_motion(step_px: float) -> float:
	if root_motion_block_group == &"" or step_px == 0.0 or not is_inside_tree():
		return step_px
	var dir := signf(step_px)
	var allowed := absf(step_px)
	for n in get_tree().get_nodes_in_group(root_motion_block_group):
		if not (n is Node2D):
			continue
		if n.has_method(&"blocks_body") and not n.call(&"blocks_body"):
			continue
		var dx: float = ((n as Node2D).global_position.x - global_position.x) * dir
		if dx <= 0.0 or absf((n as Node2D).global_position.y - global_position.y) > 110.0:
			continue
		var gap := dx - (float(n.get(&"half_w")) + ROOT_MOTION_CONTACT)
		allowed = minf(allowed, maxf(gap, 0.0))
	return allowed * dir


## 普通招式：输入/惯性速度 + 本帧根位移，一起交给物理（撞墙会停住）。
## 根位移只作用这一帧，不留在 velocity 里，免得变成惯性滑步。
func _move_with_root_motion(delta: float, mv: Resource) -> void:
	var is_cleave_like := mv == charge_move or mv == combo_k_cleave_move
	var root_step := 0.0
	if ((is_on_floor() or finisher_intent != &"") and not is_cleave_like) \
			or (is_cleave_like and not mv.root_motion_x.is_empty()):
		root_step = _root_motion_step(mv)
	var hop_active := is_cleave_like and _charge_authored_hop
	var hop := 0.0
	if hop_active:
		var clip: Dictionary = _sprite_config().get("animations", {}).get(mv.animation, {})
		hop = _root_motion_at(mv, clip, float(move_frame + 1), mv.root_motion_y)
		_charge_hop_started = _charge_hop_started or hop < -0.1
		velocity.y = (_charge_hop_origin_y + hop - global_position.y) / maxf(delta, 0.000001)
	var rv := _clamp_root_motion(root_step * float(facing)) / maxf(delta, 0.000001)
	velocity.x += rv
	move_and_slide()
	if rv != 0.0 and is_on_wall() and signf(velocity.x) != signf(rv):
		velocity.x = 0.0
	else:
		velocity.x -= rv
	if hop_active:
		if is_on_ceiling() or (_charge_hop_started and hop >= -0.001):
			_charge_authored_hop = false
		velocity.y = 0.0


func _guard_config() -> Dictionary:
	var character: Dictionary = get_meta("character", {})
	return character.get("sprite", {}).get("guard", character.get("guard", {}))

func _begin_guard_or_parry() -> void:
	if bool(_guard_config().get("enabled", false)):
		# Recovery cancel must actually leave the previous attack.
		current_move = null
		state = State.NEUTRAL
		_start_guard(true)
	else:
		_start_move(parry_move, false)

func _start_guard(precise: bool) -> void:
	_cancel_locomotion()
	_guard_active = true
	_guard_frames = 0 if precise else int(_guard_config().get("parryWindowFrames", 0)) + 1
	_guard_parried = not precise
	guard_clock = 0.0
	guard_animation = str(_guard_config().get("startupAnimation", "")) if precise else str(_guard_config().get("holdAnimation", ""))
	action_serial += 1

func _stop_guard() -> void:
	_guard_active = false
	guard_animation = ""
	guard_clock = 0.0

func is_guarding() -> bool:
	if _guard_active and state == State.NEUTRAL:
		return true
	if not _reaction_guard_held or state != State.ATTACK \
			or not (guard_reactions.has(current_move) or parry_reactions.has(current_move)):
		return false
	var latest := input_buffer.frame_at(0)
	return latest != null and latest.actions.has(&"parry")

func _process_guard(delta: float, frame: InputBuffer.Frame, started: bool = false) -> bool:
	if not frame.actions.has(&"parry") and (_has_edge(&"attack_light") or _has_edge(&"attack_heavy") \
			or _has_edge(&"attack_ranged") or _has_edge(&"dash_modifier") or _has_edge(&"short_dash")):
		_stop_guard()
		return false
	if not started:
		_guard_frames += 1
	# A tap grants the same precise window as a hold. Release ends defense only
	# after that local window expires; continued holding then becomes ordinary guard.
	if not frame.actions.has(&"parry") and not is_parrying():
		_stop_guard()
		return false
	var config := _guard_config()
	var startup := str(config.get("startupAnimation", ""))
	if not started:
		guard_clock += delta * (maxf(float(config.get("startupAnimationSpeed", 1.0)), 0.05) if guard_animation == startup else 1.0)
	var clip: Dictionary = _sprite_config().get("animations", {}).get(startup, {})
	var startup_frames: Array = clip.get("frames", [])
	var startup_done := _guard_frames > int(config.get("parryWindowFrames", 0))
	if not startup_frames.is_empty() and guard_animation == startup:
		var duration := Timeline.ticks_before(startup_frames, startup_frames.size()) / maxf(float(clip.get("fps", 24)), 0.001)
		startup_done = guard_clock + 0.000001 >= duration
	if startup_done:
		var hold := str(config.get("holdAnimation", ""))
		if guard_animation != hold:
			guard_animation = hold
			guard_clock = 0.0
	_move_horizontal(delta, frame, float(config.get("movementScale", 0.85)))
	if _try_buffered_jump(frame):
		return true
	_apply_gravity(delta, _air_gravity())
	move_and_slide()
	return true


## Success poses are feedback, not movement recovery or a new parry window.
func _process_guard_reaction(delta: float, frame: InputBuffer.Frame, mv: Resource) -> void:
	var held := frame.actions.has(&"parry")
	_reaction_guard_held = held
	if not held and (_has_edge(&"attack_light") or _has_edge(&"attack_heavy") \
			or _has_edge(&"attack_ranged") or _has_edge(&"dash_modifier") or _has_edge(&"short_dash")):
		_end_attack()
		_process_neutral(delta, frame)
		return
	_move_horizontal(delta, frame, float(_guard_config().get("movementScale", 0.85)) if held else 1.0)
	if not _try_buffered_jump(frame):
		_apply_gravity(delta, _air_gravity())
		move_and_slide()
	move_frame += 1
	if move_frame >= mv.total_frames():
		_end_attack()

func _do_block(attacker: Node, point: Vector2) -> void:
	var config := _guard_config()
	# Presentation is event-only; an empty L press never reaches this method.
	var pause := roundi(float(config.blockHitstopFrames) * hitstop_multiplier) if config.has("blockHitstopFrames") else parry_hitstop_frames
	hitstop_frames = maxi(hitstop_frames, pause)
	_play_guard_reaction(guard_reactions, false)
	block_success.emit(attacker, point)

func _play_guard_reaction(reactions: Array, parried: bool) -> void:
	if reactions.is_empty():
		return
	var latest := input_buffer.frame_at(0)
	var keep_guard := is_guarding() and latest != null and latest.actions.has(&"parry")
	var index := _parry_variant if parried else _guard_variant
	var mv: Resource = reactions[index % reactions.size()]
	if parried:
		_parry_variant += 1
	else:
		_guard_variant += 1
	_start_move(mv, false)
	_reaction_guard_held = keep_guard

func _interrupt_action_flow() -> void:
	_charge_authored_hop = false
	_charge_hop_started = false
	_uppercut_jump_pending = false
	_air_hit_slow_frames = 0
	_reaction_guard_held = false
	_keen_swing_active = false
	_short_dash_ticks = 0
	_pursuit_target = null
	_pursuit_offset = Vector2.ZERO
	_dash_preserving_charge = false
	_post_dash_window = 0
	_post_dash_was_pursuit = false
	_dash_passed_enemy = null
	_cancel_locomotion()
	_stop_guard()
	_reset_air_combo()
	charge_frames = -1
	_charge_accum = 0.0

func is_combat_action_active() -> bool:
	return state == State.ATTACK or charge_frames >= 0 or _guard_active or _short_dash_ticks > 0


# ---------------------------------------------------------------- 残影池与瞬步 / 追影冲刺（1A + 无限闪 + 四连强化 A）

## 启用实战重设计：无限闪（零残影消耗）+ 地面四段普攻（被打断续连 + 阶梯式顿帧震屏 A1 → A2 → A3 → 强化 A4）
func enable_combat_rework() -> void:
	combat_rework_enabled = true
	unlimited_dash = true
	shadow_cost_enabled = false
	air_dash_unlimited = true
	shadow_charges = max_shadow_charges
	if light_combo.size() == 3 and light_combo[0] != null and light_combo[1] != null and light_combo[2] != null:
		var m1: MoveDefinition = light_combo[0] as MoveDefinition
		var m2: MoveDefinition = light_combo[1] as MoveDefinition
		var m3: MoveDefinition = light_combo[2] as MoveDefinition
		# 削弱纯基础普攻直伤（原 4 刀共 66 → 现 34），把爆发让位给「J+K 派生树」与「紫电锋芒强普」
		m1.damage = 5.5
		m2.damage = 6.5
		m3.damage = 8.5
		# 阶梯式刀刀入肉曲线：普通 3 刀大幅收紧攻方顿帧（2/3/4 帧 + 仅首目标触发 hitstop_first_only）杜绝靠顿帧悬停；第 4 刀强普保留明显重顿帧反差
		m1.hitstop_first_only = true
		m2.hitstop_first_only = true
		m3.hitstop_first_only = true
		if hitstop_multiplier <= 0.0:
			m1.hitstop_frames = 0
			m1.victim_hitstop_frames = 0
			m2.hitstop_frames = 0
			m2.victim_hitstop_frames = 0
			m3.hitstop_frames = 0
			m3.victim_hitstop_frames = 0
		else:
			m1.hitstop_frames = maxi(roundi(2.0 * hitstop_multiplier), 1)
			m1.victim_hitstop_frames = maxi(roundi(7.0 * hitstop_multiplier), m1.hitstop_frames + 3)
			m2.hitstop_frames = maxi(roundi(3.0 * hitstop_multiplier), m1.hitstop_frames + 1)
			m2.victim_hitstop_frames = maxi(roundi(10.0 * hitstop_multiplier), m1.victim_hitstop_frames + 2)
			m3.hitstop_frames = maxi(roundi(4.0 * hitstop_multiplier), m2.hitstop_frames + 1)
			m3.victim_hitstop_frames = maxi(roundi(13.0 * hitstop_multiplier), m2.victim_hitstop_frames + 2)
		m1.shake_amount = maxf(m1.shake_amount * 1.45, 15.0)
		m1.squash = Vector2(1.30, 0.76)
		m2.shake_amount = maxf(m2.shake_amount * 1.55, 20.0)
		m2.squash = Vector2(1.38, 0.70)
		# 第 3 刀重刃压迫蓄势，紧凑过渡不提前击飞断连，稳稳喂入第 4 刀强化 A 或 J→J→J→K 断岳崩裂
		m3.forces_launch = false
		m3.launch_speed = 0.0
		m3.knockback = 240.0
		m3.cancel_frame = mini(m3.cancel_frame, 5)
		m3.shake_amount = maxf(m3.shake_amount * 1.35, 29.0)
		m3.squash = Vector2(1.54, 0.54)
		var base4: MoveDefinition = (up_strike_move if up_strike_move != null else light_combo[2]) as MoveDefinition
		var m4: MoveDefinition = base4.duplicate()
		m4.id = &"light_4"
		m4.display_name = "第四刀 · 强化普攻"
		m4.command = &"light"
		m4.direction = 0
		m4.damage = 13.5
		m4.forces_launch = true
		m4.knockback = 460.0
		m4.launch_speed = 980.0
		m4.lunge = 210.0
		m4.wall_damage_factor = 0.85
		m4.hitbox = Rect2(Vector2(148.0, -112.0), Vector2(310.0, 236.0))
		m4.hitstop_first_only = true
		if hitstop_multiplier <= 0.0:
			m4.hitstop_frames = 0
			m4.victim_hitstop_frames = 0
		else:
			m4.hitstop_frames = maxi(roundi(13.0 * hitstop_multiplier), m3.hitstop_frames + 7)
			m4.victim_hitstop_frames = maxi(roundi(20.0 * hitstop_multiplier), m3.victim_hitstop_frames + 6)
		m4.shake_amount = maxf(m3.shake_amount * 1.55, 45.0)
		m4.squash = Vector2(1.78, 0.38)
		m4.move_cancel_after_active = 6
		m1.next_move = m2
		m2.next_move = m3
		m3.next_move = m4
		m4.next_move = null
		light_combo = [m1, m2, m3, m4]
	if air_combo.size() == 3 and air_combo[0] != null and air_combo[1] != null and air_combo[2] != null:
		var am1: MoveDefinition = air_combo[0] as MoveDefinition
		var am2: MoveDefinition = air_combo[1] as MoveDefinition
		var am3: MoveDefinition = air_combo[2] as MoveDefinition
		var am4: MoveDefinition = am3.duplicate()
		am1.damage = 6.0
		am2.damage = 7.0
		am3.damage = 8.5
		# 空中四段普攻阶梯式打击曲线：收紧普通空 1..3 顿帧（2/3/4 帧 + 仅首目标触发 hitstop_first_only）杜绝滞空，保留空中强普 空4 爆发反差
		am1.hitstop_first_only = true
		am2.hitstop_first_only = true
		am3.hitstop_first_only = true
		if hitstop_multiplier <= 0.0:
			am1.hitstop_frames = 0
			am1.victim_hitstop_frames = 0
			am2.hitstop_frames = 0
			am2.victim_hitstop_frames = 0
			am3.hitstop_frames = 0
			am3.victim_hitstop_frames = 0
		else:
			am1.hitstop_frames = maxi(roundi(2.0 * hitstop_multiplier), 1)
			am1.victim_hitstop_frames = maxi(roundi(6.0 * hitstop_multiplier), am1.hitstop_frames + 3)
			am2.hitstop_frames = maxi(roundi(3.0 * hitstop_multiplier), am1.hitstop_frames + 1)
			am2.victim_hitstop_frames = maxi(roundi(9.0 * hitstop_multiplier), am1.victim_hitstop_frames + 2)
			am3.hitstop_frames = maxi(roundi(4.0 * hitstop_multiplier), am2.hitstop_frames + 1)
			am3.victim_hitstop_frames = maxi(roundi(12.0 * hitstop_multiplier), am2.victim_hitstop_frames + 2)
		am1.shake_amount = maxf(am1.shake_amount * 1.42, 14.0)
		am1.squash = Vector2(1.28, 0.76)
		am2.shake_amount = maxf(am2.shake_amount * 1.52, 19.0)
		am2.squash = Vector2(1.36, 0.70)
		am3.forces_launch = false
		am3.launch_speed = 320.0
		am3.knockback = 180.0
		am3.cancel_frame = mini(am3.cancel_frame, 4)
		am3.shake_amount = maxf(am3.shake_amount * 1.32, 27.0)
		am3.squash = Vector2(1.52, 0.56)
		am4.id = &"air_light_4"
		am4.display_name = "空中第四刀 · 强化空斩"
		am4.command = &"light"
		am4.is_air = true
		am4.direction = 0
		am4.damage = 14.5
		am4.forces_launch = true
		am4.knockback = 420.0
		am4.launch_speed = 760.0
		am4.wall_damage_factor = 0.85
		am4.hitbox = Rect2(Vector2(132.0, -108.0), Vector2(276.0, 252.0))
		am4.hitstop_first_only = true
		if hitstop_multiplier <= 0.0:
			am4.hitstop_frames = 0
			am4.victim_hitstop_frames = 0
		else:
			am4.hitstop_frames = maxi(roundi(12.0 * hitstop_multiplier), am3.hitstop_frames + 6)
			am4.victim_hitstop_frames = maxi(roundi(19.0 * hitstop_multiplier), am3.victim_hitstop_frames + 6)
		am4.shake_amount = maxf(am3.shake_amount * 1.55, 42.0)
		am4.squash = Vector2(1.74, 0.40)
		am1.next_move = am2
		am2.next_move = am3
		am3.next_move = am4
		am4.next_move = null
		air_combo = [am1, am2, am3, am4]
	if ranged_move != null:
		ranged_move.damage = 5.0
		ranged_speed = maxf(ranged_speed, 1180.0)
	# 方向 1：三式 J+K 轻重派生终结技（零蓄力等待，按连段阶数自动派生破势重招）
	if up_strike_move != null:
		var c1: MoveDefinition = (up_strike_move as MoveDefinition).duplicate()
		c1.id = &"combo_k_launch"
		c1.display_name = "一式 · 升龙挑月"
		c1.command = &"heavy"
		c1.direction = 1
		c1.is_charge = false
		c1.damage = 18.0
		c1.forces_launch = true
		c1.launch_speed = 1020.0
		c1.knockback = 150.0
		c1.lunge = 175.0
		c1.wall_damage_factor = 0.72
		c1.hitbox = Rect2(Vector2(128.0, -118.0), Vector2(268.0, 248.0))
		c1.hitstop_frames = maxi(roundi(12 * hitstop_multiplier), 12)
		c1.victim_hitstop_frames = maxi(roundi(18 * hitstop_multiplier), 18)
		c1.shake_amount = 24.5
		c1.squash = Vector2(0.80, 1.38)
		c1.next_move = null
		combo_k_launch_move = c1
	if dash_move != null:
		var c2: MoveDefinition = (dash_move as MoveDefinition).duplicate()
		c2.id = &"combo_k_pierce"
		c2.display_name = "二式 · 穿云破阵"
		c2.command = &"heavy"
		c2.direction = 0
		c2.is_charge = false
		c2.damage = 22.0
		c2.forces_launch = true
		c2.launch_speed = 680.0
		c2.knockback = 560.0
		c2.wall_damage_factor = 0.85
		c2.hitstop_frames = maxi(roundi(13 * hitstop_multiplier), 13)
		c2.victim_hitstop_frames = maxi(roundi(19 * hitstop_multiplier), 19)
		c2.shake_amount = 26.5
		c2.squash = Vector2(1.48, 0.58)
		c2.next_move = null
		combo_k_pierce_move = c2
	if dash_left_move != null:
		var c2l: MoveDefinition = (dash_left_move as MoveDefinition).duplicate()
		c2l.id = &"combo_k_pierce_left"
		c2l.display_name = "二式 · 穿云破阵"
		c2l.command = &"heavy"
		c2l.direction = 0
		c2l.is_charge = false
		c2l.damage = 22.0
		c2l.forces_launch = true
		c2l.launch_speed = 680.0
		c2l.knockback = 560.0
		c2l.wall_damage_factor = 0.85
		c2l.hitstop_frames = maxi(roundi(13 * hitstop_multiplier), 13)
		c2l.victim_hitstop_frames = maxi(roundi(19 * hitstop_multiplier), 19)
		c2l.shake_amount = 26.5
		c2l.squash = Vector2(1.48, 0.58)
		c2l.next_move = null
		combo_k_pierce_left_move = c2l
	if charge_move != null:
		var c3: MoveDefinition = (charge_move as MoveDefinition).duplicate()
		c3.id = &"combo_k_cleave"
		c3.display_name = "三式 · 断岳崩裂"
		c3.command = &"heavy"
		c3.direction = 0
		c3.is_charge = false
		c3.damage = 38.0
		c3.charge_damage_bonus = 1.0
		c3.charge_knockback_bonus = 1.0
		c3.charge_hitstop_bonus = 0
		c3.forces_launch = true
		c3.launch_speed = 560.0
		c3.knockback = 760.0
		c3.wall_damage_factor = 0.95
		c3.hitstop_frames = maxi(roundi(18 * hitstop_multiplier), 18)
		c3.victim_hitstop_frames = maxi(roundi(26 * hitstop_multiplier), 26)
		c3.shake_amount = 38.5
		c3.squash = Vector2(1.64, 0.45)
		c3.screen_flash = maxf(c3.screen_flash, 0.35)
		c3.next_move = null
		combo_k_cleave_move = c3


func consume_shadow(cost: int = 1) -> bool:
	if unlimited_dash or not shadow_cost_enabled or cost <= 0:
		return true
	if shadow_charges < cost:
		return false
	shadow_charges -= cost
	if shadow_charges < max_shadow_charges and _shadow_regen_timer <= 0.0:
		_shadow_regen_timer = shadow_regen_seconds
	shadow_changed.emit(shadow_charges, max_shadow_charges)
	return true


func refund_shadow(amount: int = 1) -> void:
	if amount <= 0:
		return
	var prev := shadow_charges
	shadow_charges = clampi(shadow_charges + amount, 0, max_shadow_charges)
	if shadow_charges >= max_shadow_charges:
		_shadow_regen_timer = 0.0
	if shadow_charges != prev:
		shadow_changed.emit(shadow_charges, max_shadow_charges)


func _tick_shadow_regen(delta: float) -> void:
	if shadow_charges >= max_shadow_charges:
		_shadow_regen_timer = 0.0
		return
	if shadow_regen_seconds <= 0.0:
		return
	if _shadow_regen_timer <= 0.0:
		_shadow_regen_timer = shadow_regen_seconds
	else:
		_shadow_regen_timer = minf(_shadow_regen_timer, shadow_regen_seconds)
	_shadow_regen_timer -= delta
	if _shadow_regen_timer <= 0.0:
		shadow_charges = mini(shadow_charges + 1, max_shadow_charges)
		_shadow_regen_timer = shadow_regen_seconds if shadow_charges < max_shadow_charges else 0.0
		shadow_changed.emit(shadow_charges, max_shadow_charges)


func _grant_flash_heavy(duration: float) -> void:
	if duration <= 0.0:
		return
	var was_ready := flash_heavy_timer > 0.0
	flash_heavy_timer = maxf(flash_heavy_timer, duration)
	if not was_ready and flash_heavy_timer > 0.0:
		flash_heavy_ready_changed.emit(true)


func _consume_flash_heavy() -> bool:
	if flash_heavy_timer <= 0.0:
		return false
	flash_heavy_timer = 0.0
	flash_heavy_ready_changed.emit(false)
	return true


func is_keen_swing() -> bool:
	return _keen_swing_active


func _grant_keen_edge(duration: float) -> void:
	if duration <= 0.0:
		return
	var was_ready := keen_edge_timer > 0.0
	keen_edge_timer = maxf(keen_edge_timer, duration)
	if not was_ready and keen_edge_timer > 0.0:
		keen_edge_ready_changed.emit(true)


func _consume_keen_edge() -> bool:
	if keen_edge_timer <= 0.0:
		return false
	keen_edge_timer = 0.0
	keen_edge_ready_changed.emit(false)
	return true


func can_chain_cancel() -> bool:
	return state == State.ATTACK and current_move != null \
			and move_frame >= int(current_move.startup_frames) + int(current_move.active_frames) + int(current_move.cancel_frame)


func _combo_k_stage() -> int:
	if not combat_rework_enabled or not is_on_floor():
		return 0
	if state == State.ATTACK and current_move != null:
		var lc_idx := light_combo.find(current_move)
		if lc_idx >= 0 and lc_idx <= 2:
			return lc_idx + 1
		return 0
	if state == State.NEUTRAL and _short_dash_ticks <= 0 and _post_dash_window <= 0 \
			and frames_since_attack <= 18 and _rework_combo_timer > 0 \
			and _rework_next_light >= 1 and _rework_next_light <= 3:
		return _rework_next_light
	return 0


func _start_combo_k_finisher(stage_idx: int, frame: InputBuffer.Frame = null) -> void:
	_take_edge(&"attack_heavy")
	_post_dash_window = 0
	_post_dash_was_pursuit = false
	_dash_passed_enemy = null
	charge_frames = -1
	_charge_accum = 0.0
	if frame != null and absf(frame.axis.x) > 0.15:
		_set_facing(1 if frame.axis.x > 0.0 else -1)
	_rework_next_light = 0
	_rework_combo_timer = 0
	combo_index = 0
	match stage_idx:
		1:
			var m_launch: Resource = combo_k_launch_move if combo_k_launch_move != null else up_strike_move
			if m_launch == null:
				return
			_start_move(m_launch, true)
			move_frame = mini(2, maxi(int(m_launch.startup_frames) - 2, 0))
			_check_swing_cue(m_launch)
			combo_finisher_triggered.emit(m_launch, 1)
		2:
			_dash_in_air = false
			var m_pierce: Resource = combo_k_pierce_left_move if facing < 0 and combo_k_pierce_left_move != null else combo_k_pierce_move
			if m_pierce == null:
				m_pierce = _dash_move_for(facing)
			if m_pierce == null:
				return
			_start_move(m_pierce, false)
			move_frame = mini(3, maxi(int(m_pierce.startup_frames) - 3, 0))
			_check_swing_cue(m_pierce)
			combo_finisher_triggered.emit(m_pierce, 2)
		3:
			var m_cleave: Resource = combo_k_cleave_move if combo_k_cleave_move != null else charge_move
			if m_cleave == null:
				return
			_start_move(m_cleave, false)
			move_frame = mini(12, maxi(int(m_cleave.startup_frames) - 6, 0))
			_check_swing_cue(m_cleave)
			combo_finisher_triggered.emit(m_cleave, 3)


func _rework_wants_slam(frame: InputBuffer.Frame) -> bool:
	if frame != null and frame.axis.y > 0.5:
		return true
	var edge := _unconsumed_edge_frame(&"attack_heavy")
	return edge != null and edge.axis.y > 0.5


func _rework_followup_dir(frame: InputBuffer.Frame) -> int:
	if frame != null and absf(frame.axis.x) > 0.15:
		return 1 if frame.axis.x > 0.0 else -1
	if _dash_passed_enemy != null and is_instance_valid(_dash_passed_enemy):
		var bdx := _dash_passed_enemy.global_position.x - global_position.x
		if absf(bdx) > 4.0:
			return 1 if bdx > 0.0 else -1
	return facing


func is_short_dashing() -> bool:
	return _short_dash_ticks > 0


func is_shadow_pursuing() -> bool:
	return _short_dash_ticks > 0 and _pursuit_target != null


## 1A 半空智能索敌「追影冲刺」：寻找前方 <= pursuit_range_x（总距 <= pursuit_max_distance）的浮空影怪；
## 若玩家明确按住反方向键（explicit_dir 与敌人方向相反），绝不强吸，尊重后撤闪避意图。
func _find_pursuit_target(explicit_dir: int) -> Node2D:
	if not combat_rework_enabled or not is_inside_tree():
		return null
	var best: Node2D = null
	var best_dist := INF
	for n in get_tree().get_nodes_in_group(&"shade"):
		if not (n is Node2D) or not is_instance_valid(n):
			continue
		if int(n.get(&"state")) != 6:   # Shade.State.LAUNCHED == 6（含未落地的 overkilled 躯体）
			continue
		if n.has_method(&"on_ground") and bool(n.call(&"on_ground")):
			continue
		var s2d := n as Node2D
		var pinned := n.get(&"_pin_frames") != null and int(n.get(&"_pin_frames")) > 0
		var range_mul := 1.45 if pinned else 1.0
		var dx := s2d.global_position.x - global_position.x
		var dy := s2d.global_position.y - global_position.y
		if absf(dx) > pursuit_range_x * range_mul or dy > (240.0 if pinned else 190.0):
			continue
		var dist := Vector2(dx, dy).length()
		if dist > pursuit_max_distance * range_mul:
			continue
		if explicit_dir != 0:
			if absf(dx) > 36.0 and signf(dx) != float(explicit_dir):
				continue
		else:
			if dx * float(facing) < -48.0:
				continue
		if dist < best_dist:
			best_dist = dist
			best = s2d
	return best


func _check_perfect_dodge() -> void:
	if not combat_rework_enabled or not is_inside_tree():
		return
	for n in get_tree().get_nodes_in_group(&"shade"):
		if not (n is Node2D) or not is_instance_valid(n):
			continue
		var st := int(n.get(&"state"))
		if st != 2 and st != 3:   # WINDUP == 2, STRIKE == 3
			continue
		if st == 2:
			var spec_d: Variant = n.get(&"spec")
			var windup_total := int(spec_d.get("windup", 24)) if spec_d is Dictionary else 24
			if int(n.get(&"state_frames")) < maxi(windup_total - 14, 1):
				continue
		var s2d := n as Node2D
		if absf(s2d.global_position.x - global_position.x) > 205.0 \
				or absf(s2d.global_position.y - global_position.y) > 140.0:
			continue
		var lock_id := s2d.get_instance_id()
		if tick_count - int(_perfect_dodge_locks.get(lock_id, -999)) < 28:
			continue
		_perfect_dodge_locks[lock_id] = tick_count
		refund_shadow(1)
		_grant_flash_heavy(flash_heavy_duration)
		_grant_keen_edge(keen_edge_duration)
		perfect_dodge_triggered.emit(s2d, global_position)
		return
	for proj in get_tree().get_nodes_in_group(&"shade_projectile"):
		if not (proj is Node2D) or not is_instance_valid(proj):
			continue
		var p2d := proj as Node2D
		if absf(p2d.global_position.x - global_position.x) > 95.0 \
				or absf(p2d.global_position.y - global_position.y) > 95.0:
			continue
		var plock := p2d.get_instance_id()
		if tick_count - int(_perfect_dodge_locks.get(plock, -999)) < 28:
			continue
		_perfect_dodge_locks[plock] = tick_count
		refund_shadow(1)
		_grant_flash_heavy(flash_heavy_duration)
		_grant_keen_edge(keen_edge_duration)
		perfect_dodge_triggered.emit(p2d, global_position)
		return


func _track_passed_enemy(prev_x: float) -> void:
	if not combat_rework_enabled or not is_inside_tree():
		return
	var cur_x := global_position.x
	var move_dx := cur_x - prev_x
	var move_dir := signf(move_dx)
	var min_x := minf(prev_x, cur_x) - 24.0
	var max_x := maxf(prev_x, cur_x) + 24.0
	for n in get_tree().get_nodes_in_group(&"shade"):
		if not (n is Node2D) or not is_instance_valid(n) or int(n.get(&"state")) == 9:
			continue
		var s2d := n as Node2D
		if absf(s2d.global_position.y - global_position.y) > 130.0:
			continue
		var ex := s2d.global_position.x
		if ex >= min_x and ex <= max_x:
			_dash_passed_enemy = s2d
			if absf(move_dx) > 1.0 and (ex - prev_x) * move_dir >= -14.0 and (cur_x - ex) * move_dir >= -8.0:
				var eid := s2d.get_instance_id()
				if tick_count - int(_keen_cross_locks.get(eid, -999)) >= 108:
					_keen_cross_locks[eid] = tick_count
					_grant_keen_edge(keen_edge_duration)


## 原生高速穿身瞬步（及 1A 追影冲刺 / 蓄力闪斩）：耗 1 格残影，穿敌不挡，后续任意帧可出刀 / 跳跃 / 弹刀自由取消。
func start_short_dash(dir: int = 0, frame: InputBuffer.Frame = null) -> bool:
	if ult_frame >= 0 or state in [State.LAUNCHED, State.DOWN, State.DEAD] or _short_dash_ticks > 0:
		return false
	if combat_rework_enabled and not _dash_allowed():
		return false
	if not consume_shadow(1):
		return false
	var explicit_dir := signi(dir)
	var chosen := explicit_dir
	if chosen == 0:
		var latest := frame if frame != null else input_buffer.frame_at(0)
		if latest != null and absf(latest.axis.x) > 0.15:
			chosen = 1 if latest.axis.x > 0.0 else -1
		else:
			chosen = facing

	var preserve_charge := combat_rework_enabled and charge_frames >= 0 \
			and _charge_action == &"attack_heavy" \
			and frame != null and frame.actions.has(&"attack_heavy")
	var saved_cf := charge_frames
	var saved_accum := _charge_accum
	var saved_act := _charge_action
	var keep_combo := last_swing_hit and current_move != null and not _is_light_finisher(current_move)

	if combat_rework_enabled and frame != null:
		# 清除冲刺前残留的旧攻击边沿，避免紧急闪避被几帧前的缓冲攻击误打断；同帧按下的 Shift+J/K 则完整保留
		if not frame.pressed_this_frame.has(&"attack_light"):
			_take_edge(&"attack_light")
		if not frame.pressed_this_frame.has(&"attack_heavy"):
			_take_edge(&"attack_heavy")

	_interrupt_action_flow()
	current_move = null
	current_is_up = false
	finisher_intent = &""
	state = State.NEUTRAL
	link_open = false
	if preserve_charge:
		charge_frames = saved_cf
		_charge_accum = saved_accum
		_charge_action = saved_act
		_dash_preserving_charge = true
	if combat_rework_enabled:
		combo_index = _rework_next_light if _rework_combo_timer > 0 else 0
	elif not keep_combo and frames_since_attack > combo_keep_frames:
		combo_index = 0
	frames_since_attack = 0
	_landing_lag = 0
	hitstop_frames = 0
	hitstop_this_tick = false
	_air_normal_hit_chain = 0
	_air_a4_braked_this_flight = false

	var same_tick_attack := combat_rework_enabled and frame != null \
			and (frame.pressed_this_frame.has(&"attack_light") or frame.pressed_this_frame.has(&"attack_heavy"))
	var pursuit: Node2D = null
	if combat_rework_enabled and not preserve_charge and not same_tick_attack:
		pursuit = _find_pursuit_target(explicit_dir)

	if combat_rework_enabled and not is_on_floor() and air_frames > coyote_frames and not air_dash_unlimited:
		_air_dash_left = maxi(_air_dash_left - 1, 0)

	if pursuit != null:
		var pdx := pursuit.global_position.x - global_position.x
		var pdir := (1 if pdx > 0.0 else -1) if absf(pdx) > 12.0 else chosen
		var enemy_hw := float(pursuit.get(&"half_w")) if pursuit.get(&"half_w") != null else 24.0
		_pursuit_target = pursuit
		_pursuit_offset = Vector2(-float(pdir) * (enemy_hw + 42.0), -12.0)
		_set_facing(pdir)
		_short_dash_dir = pdir
		_short_dash_ticks = maxi(pursuit_frames, 1)
		invuln_frames = maxi(invuln_frames, _short_dash_ticks + 4)
		ground_frames = 0
		air_frames = maxi(air_frames, coyote_frames + 1)
		_ground_jump_used = true
		_reset_air_combo()
		_air_light_left = maxi(_air_light_left, 1)
		if pursuit.get(&"velocity") is Vector2:
			var pv: Vector2 = pursuit.get(&"velocity")
			if pv.y > -240.0:
				pursuit.set(&"velocity", Vector2(pv.x * 0.55, -260.0))
		if pursuit.get(&"_air_light_juggle_streak") != null:
			pursuit.set(&"_air_light_juggle_streak", 0)
		if pursuit.get(&"_air_raw_a4_count") != null:
			pursuit.set(&"_air_raw_a4_count", 0)
		_set_visual_scale(Vector2(1.28, 0.76))
		_squash_timer = _short_dash_ticks
		action_serial += 1
		action_idle_frames = 0
		shadow_pursuit_started.emit(pursuit, global_position)
		short_dash_started.emit(_short_dash_dir, global_position)
		return true

	_set_facing(chosen)
	_short_dash_dir = chosen
	var dur := step_dash_frames if combat_rework_enabled else short_dash_frames
	_short_dash_ticks = maxi(dur, 1)
	invuln_frames = maxi(invuln_frames, _short_dash_ticks + (3 if combat_rework_enabled else 2))
	_set_visual_scale(Vector2(1.24, 0.80))
	_squash_timer = _short_dash_ticks
	action_serial += 1
	action_idle_frames = 0
	short_dash_started.emit(_short_dash_dir, global_position)
	return true


func _try_rework_dash_input(frame: InputBuffer.Frame) -> bool:
	var tap_dir := _double_tap_direction()
	if tap_dir != 0:
		var tap_seq := _newest_press_seq(&"move_left" if tap_dir < 0 else &"move_right")
		if tap_seq >= 0:
			_double_tap_seq = tap_seq
			if _dash_allowed():
				return start_short_dash(tap_dir, frame)
			return false
	var f_sd := _unconsumed_edge_frame(&"short_dash")
	var f_dm := _unconsumed_edge_frame(&"dash_modifier")
	var f := f_sd if f_sd != null else f_dm
	if f == null:
		return false
	_take_edge(&"short_dash")
	_take_edge(&"dash_modifier")
	if not _dash_allowed():
		return false
	var dir := 0
	if absf(f.axis.x) > 0.15:
		dir = 1 if f.axis.x > 0.0 else -1
	elif frame != null and absf(frame.axis.x) > 0.15:
		dir = 1 if frame.axis.x > 0.0 else -1
	return start_short_dash(dir, frame)


func _try_short_dash_input(frame: InputBuffer.Frame) -> bool:
	var f := _unconsumed_edge_frame(&"short_dash")
	if f == null:
		return false
	_take_edge(&"short_dash")
	var dir := 0
	if absf(f.axis.x) > 0.15:
		dir = 1 if f.axis.x > 0.0 else -1
	elif frame != null and absf(frame.axis.x) > 0.15:
		dir = 1 if frame.axis.x > 0.0 else -1
	return start_short_dash(dir, frame)


func _process_short_dash(delta: float, frame: InputBuffer.Frame, started_this_tick: bool = false) -> void:
	if combat_rework_enabled:
		_check_perfect_dodge()
		if _dash_preserving_charge and charge_frames >= 0:
			_charge_accum += maxf(charge_rate_scale, 0.05)
			while _charge_accum >= 1.0:
				_charge_accum -= 1.0
				charge_frames += 1
			if frame != null and not frame.actions.has(_charge_action):
				_short_dash_ticks = 0
				_dash_preserving_charge = false
				velocity.x = 0.0
				var cdir := _rework_followup_dir(frame)
				_dash_passed_enemy = null
				_set_facing(cdir)
				_release_charge()
				if state == State.ATTACK and current_move != null:
					_process_attack(delta, frame)
				return

	var can_cancel_attack := not started_this_tick
	if combat_rework_enabled and not _dash_preserving_charge:
		if _pursuit_target != null and is_instance_valid(_pursuit_target):
			var goal_now := _pursuit_target.global_position + _pursuit_offset
			can_cancel_attack = (not started_this_tick) and (global_position.distance_to(goal_now) <= 110.0 or _short_dash_ticks <= 1)
		else:
			can_cancel_attack = true

	if can_cancel_attack and not _dash_preserving_charge:
		# 保留出刀 / 弹刀自由取消手感：瞬步任意帧（含同帧 Shift+J/K）输入攻击或弹刀即刻收闪出刀
		var cmd := _resolve_attack_command(frame)
		if cmd != &"":
			var was_pursuit := _pursuit_target != null
			if was_pursuit:
				_reset_air_combo()
				_air_light_left = maxi(_air_light_left, 1)
				if is_instance_valid(_pursuit_target):
					var adx := _pursuit_target.global_position.x - global_position.x
					if absf(adx) > 2.0:
						_set_facing(1 if adx > 0.0 else -1)
			_short_dash_ticks = 0
			_pursuit_target = null
			_pursuit_offset = Vector2.ZERO
			_post_dash_was_pursuit = was_pursuit
			velocity.x = 0.0
			if not combat_rework_enabled and frame != null and absf(frame.axis.x) > 0.15:
				_set_facing(1 if frame.axis.x > 0.0 else -1)
			elif combat_rework_enabled and cmd in [&"light", &"up", &"air_combo", &"air_up", &"ranged", &"parry"]:
				if frame != null and absf(frame.axis.x) > 0.15:
					_set_facing(1 if frame.axis.x > 0.0 else -1)
				elif _dash_passed_enemy != null and is_instance_valid(_dash_passed_enemy):
					var bdx := _dash_passed_enemy.global_position.x - global_position.x
					if absf(bdx) > 4.0:
						_set_facing(1 if bdx > 0.0 else -1)
					_dash_passed_enemy = null
			_begin_command(cmd, frame)
			if state == State.ATTACK and current_move != null:
				_process_attack(delta, frame)
			elif _guard_active:
				_process_guard(delta, frame, true)
			elif charge_frames >= 0:
				_process_charge(delta, frame)
			return

	if combat_rework_enabled and _pursuit_target != null:
		if is_instance_valid(_pursuit_target) and int(_pursuit_target.get(&"state")) != 9:
			var goal := _pursuit_target.global_position + _pursuit_offset
			if _pursuit_target.has_method(&"level_y"):
				var lvl_y := float(_pursuit_target.call(&"level_y"))
				if is_finite(lvl_y):
					goal.y = minf(goal.y, lvl_y - foot_offset - 95.0)
			var step_vec := (goal - global_position) / float(maxi(_short_dash_ticks, 1))
			velocity = step_vec / maxf(delta, 0.000001)
			var fdx := _pursuit_target.global_position.x - global_position.x
			if absf(fdx) > 2.0:
				_set_facing(1 if fdx > 0.0 else -1)
			move_and_slide()
			_check_perfect_dodge()
			_short_dash_ticks -= 1
			if _short_dash_ticks <= 0:
				var end_dx := _pursuit_target.global_position.x - global_position.x
				if absf(end_dx) > 2.0:
					_set_facing(1 if end_dx > 0.0 else -1)
				velocity = Vector2(0.0, -740.0)
				_air_hit_slow_frames = maxi(_air_hit_slow_frames, 26)
				_reset_air_combo()
				_air_light_left = maxi(_air_light_left, 1)
				_post_dash_window = 12
				_post_dash_was_pursuit = true
				_pursuit_target = null
				_pursuit_offset = Vector2.ZERO
			return
		_pursuit_target = null
		_pursuit_offset = Vector2.ZERO

	var prev_x := global_position.x
	_set_facing(_short_dash_dir)
	var dash_spd := step_dash_speed if combat_rework_enabled else short_dash_speed
	velocity.x = float(_short_dash_dir) * dash_spd
	velocity.y = 0.0
	move_and_slide()
	if combat_rework_enabled:
		_track_passed_enemy(prev_x)
		_check_perfect_dodge()
	_short_dash_ticks -= 1
	if _short_dash_ticks <= 0:
		velocity.x = 0.0
		if combat_rework_enabled:
			_dash_preserving_charge = false
			_post_dash_window = 11
			_post_dash_was_pursuit = false
			if _dash_passed_enemy != null and is_instance_valid(_dash_passed_enemy) \
					and (frame == null or absf(frame.axis.x) <= 0.15):
				var bdx := _dash_passed_enemy.global_position.x - global_position.x
				if absf(bdx) > 4.0:
					_set_facing(1 if bdx > 0.0 else -1)


# ---------------------------------------------------------------- 大招（第四轮）

func add_ult_energy(amount: float) -> void:
	if not ult_enabled or ult_frame >= 0 or state == State.DEAD:
		return
	ult_energy = clampf(ult_energy + amount, 0.0, ult_max)


func ult_ready() -> bool:
	return ult_enabled and ult_energy >= ult_max


func is_ult() -> bool:
	return ult_frame >= 0


## 大招用的招式数据：借蓄力斩的动画，伤害 / 击飞单独定（id = &"ult"，敌人那边据此破格挡、破霸体）
func ult_move() -> Resource:
	if _ult_move == null:
		var base: Resource = charge_move
		if base == null and not light_combo.is_empty():
			base = light_combo[light_combo.size() - 1]
		if base == null:
			return null
		_ult_move = base.duplicate()
		_ult_move.id = &"ult"
		_ult_move.command = &"ult"
		_ult_move.display_name = "大招"
		_ult_move.is_charge = false
		_ult_move.damage = ult_damage
		_ult_move.knockback = 1150.0
		_ult_move.knockback_angle = 38.0
		_ult_move.forces_launch = true
		_ult_move.launch_speed = 900.0
		_ult_move.hitstop_frames = roundi(18 * hitstop_multiplier)
		_ult_move.victim_hitstop_frames = roundi(26 * hitstop_multiplier)
		_ult_move.shake_amount = 0.0
		_ult_move.wall_damage_factor = 1.0
		_ult_move.lunge = 0.0
		_ult_move.next_move = null
	return _ult_move


## R（手柄 RT）单按；或 J + K：两个按键都在最近 ult_chord_frames 帧里按下过，而且这一对还没用过
func _try_ult() -> bool:
	if not ult_ready():
		return false
	if state != State.NEUTRAL and state != State.ATTACK:
		return false
	var key := _unconsumed_edge_frame(&"ult")
	if key != null and key.seq > _ult_used_seq:
		_take_edge(&"ult")
		_ult_used_seq = key.seq
		_start_ult()
		return true
	var sj := -1
	var sk := -1
	for i in mini(ult_chord_frames, input_buffer.frame_count()):
		var f := input_buffer.frame_at(i)
		if f == null:
			continue
		if sj < 0 and f.pressed_this_frame.has(&"attack_light"):
			sj = f.seq
		if sk < 0 and f.pressed_this_frame.has(&"attack_ranged"):
			sk = f.seq
	if sj < 0 or sk < 0 or mini(sj, sk) <= _ult_used_seq:
		return false
	_ult_used_seq = maxi(sj, sk)
	# 这两个按键算用掉了，别在大招之后又冒出一刀普攻 / 一发远射
	_consumed_edge[&"attack_light"] = sj
	_consumed_edge[&"attack_ranged"] = sk
	_start_ult()
	return true


func _start_ult() -> void:
	var mv := ult_move()
	if mv == null:
		return
	_interrupt_action_flow()
	current_move = mv
	current_is_up = false
	state = State.ATTACK
	move_frame = 0
	ult_frame = 0
	ult_energy = 0.0
	ult_from_x = global_position.x
	_reset_ult_flow()
	_update_ult_pose()
	link_open = false
	last_swing_hit = true
	_hit_this_swing.clear()
	swing_hit_count = 0
	velocity = Vector2.ZERO
	hitstop_frames = 0
	invuln_frames = maxi(invuln_frames, ult_total_frames + 100)
	_set_visual_scale(Vector2(1.12, 0.88))
	_squash_timer = 6
	ult_started.emit()


func _reset_ult_flow() -> void:
	ult_cut_pos = PackedVector2Array()
	ult_cut_face = PackedInt32Array()
	ult_stand_pos = Vector2.INF
	ult_stand_face = facing
	ult_hidden = false
	ult_body = &""


func _process_ult(_delta: float, _frame: InputBuffer.Frame) -> void:
	var mv := current_move
	if mv == null:
		ult_frame = -1
		ult_clip = ""
		ult_pose = -1
		ult_hidden = false
		ult_body = &""
		state = State.NEUTRAL
		return
	ult_frame += 1
	if ult_frame == ult_vanish_frame:
		_ult_fill_defaults()
	var k := ult_cut_frames.find(ult_frame)
	if k >= 0:
		ult_strike.emit(k, ult_cut_frames.size())
	if ult_frame == ult_calm_start:
		ult_arrive.emit()
	if ult_frame == ult_final_frame:
		ult_reveal.emit()
	_update_ult_pose()
	move_frame = mini(int(mv.total_frames()) - 1, int(float(ult_frame) / float(maxi(ult_total_frames, 1)) * float(mv.total_frames())))
	_move_ult()
	ult_tick.emit()
	if ult_frame >= ult_total_frames:
		ult_frame = -1
		ult_clip = ""
		ult_pose = -1
		ult_hidden = false
		ult_body = &""
		_end_attack()
		ult_finished.emit()


## 关卡没给路线（测试直接起手）时：站定在身前远处（ult_cut_pos 只留给表现层参考）
func _ult_fill_defaults() -> void:
	var fx := float(facing)
	var p := global_position
	if ult_cut_pos.size() < ult_cut_frames.size():
		ult_cut_pos = PackedVector2Array([p + Vector2(fx * 520.0, -60.0), p + Vector2(fx * 120.0, -260.0), p + Vector2(fx * 560.0, -20.0)])
		ult_cut_face = PackedInt32Array([-facing, facing, -facing])
	if ult_stand_pos == Vector2.INF:
		ult_stand_pos = p + Vector2(fx * 640.0, 0.0)
		ult_stand_face = facing


## 位置：起手原地 → 过场视频期间不在场上 → 冲击帧那一刻已经站在敌群背后。全程不走物理（直接写位置）
func _move_ult() -> void:
	velocity = Vector2.ZERO
	if ult_frame < ult_calm_start:
		ult_hidden = ult_frame >= ult_vanish_frame
		return
	if ult_stand_pos != Vector2.INF:
		global_position = ult_stand_pos
		_set_facing(ult_stand_face)
	ult_hidden = false


## 姿势：开场居合架势 → （视频）→ 地图斩和收刀的姿势由表现层画（ult_fx / ult_map_slash.gd）。
## ult_clip / ult_pose 给 character_view 兜底（表现层没接上时也有个像样的姿势），大招结束后从收刀接着收
func _update_ult_pose() -> void:
	if ult_frame < 0:
		ult_clip = ""
		ult_pose = -1
		ult_body = &""
		return
	if ult_frame < ult_vanish_frame:
		ult_body = &"iai"
		ult_clip = "draw"
		ult_pose = 14
		return
	if ult_frame < ult_calm_start:
		ult_body = &""
		return
	ult_body = &"zanshin" if ult_frame < ult_final_frame else &"sheathed"
	ult_clip = "sheathe"
	ult_pose = 18
