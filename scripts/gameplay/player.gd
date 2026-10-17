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
signal hit_confirmed(target: Node2D, move: Resource, point: Vector2)
signal landed()
signal jumped(is_double: bool)
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

const InputBuffer := preload("res://scripts/core/input_buffer.gd")
const ProjectileScene := preload("res://scenes/actors/projectile.tscn")

enum State { NEUTRAL, ATTACK, LAUNCHED, DOWN, DEAD }

const TRACKED_ACTIONS: Array[StringName] = [
	&"jump", &"attack_light", &"attack_ranged", &"aim_up",
	&"move_left", &"move_right", &"parry",
]
const AXIS_ACTIONS: Array[StringName] = [&"move_left", &"move_right", &"aim_up", &"move_down"]
## J 连续按住多少帧才认定是"蓄力"而不是"点按"。
## 默认 10 帧约 167ms；这个门槛由修改器配置，点按立即出刀。
@export var hold_to_charge_frames: int = 10
@export var foot_offset: float = 84.0
@export var acceleration: float = 4800.0

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
## 出招期间的水平移速倍率。不是 0 —— 出招能走位是这个手感的关键
@export var attack_move_scale: float = 0.62

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

@export_group("手感表现")
@export var squash_strength: float = 1.0

var state: State = State.NEUTRAL
var facing: int = 1
var hp: float = 100.0
var hitstop_frames: int = 0
var hitstop_this_tick: bool = false
var parry_hitstop_frames: int = 3
var ground_frames: int = 0
var air_frames: int = 0
var down_frames: int = 0

var current_move: Resource = null
var move_frame: int = 0
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

var input_buffer: InputBuffer

var _jump_velocity: float = -560.0
var _gravity: float = 1600.0
var _fall_gravity: float = 1600.0
var _jump_buffer_counter: int = 0
var _air_jumps_left: int = 0
var _frame_counter: int = 0
var _hit_this_swing: Dictionary = {}
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
	input_buffer = InputBuffer.new(64)
	hp = max_hp
	_recalculate_jump()
	up_direction = Vector2.UP
	if _visual != null:
		_visual.scale = Vector2.ONE
	# 记下场景里作者摆的判定盒前伸距离（absf 取正），翻面时以它为基准
	if _melee != null:
		_melee_base_offset_x = absf(_melee.position.x)
	_sync_melee_offset()
	apply_combat_identity()


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
		return InputBuffer.sample(TRACKED_ACTIONS, AXIS_ACTIONS)
	var tracked: Array[StringName] = []
	for a in TRACKED_ACTIONS:
		tracked.append(StringName(String(a) + action_suffix))
	var axes: Array[StringName] = []
	for a in AXIS_ACTIONS:
		axes.append(StringName(String(a) + action_suffix))
	var f := InputBuffer.sample(tracked, axes)
	for i in f.actions.size():
		f.actions[i] = _unsuffix(f.actions[i])
	for i in f.pressed_this_frame.size():
		f.pressed_this_frame[i] = _unsuffix(f.pressed_this_frame[i])
	return f


func _unsuffix(a: StringName) -> StringName:
	var s := String(a)
	if s.ends_with(action_suffix):
		s = s.substr(0, s.length() - action_suffix.length())
	return StringName(s)


func _physics_process(delta: float) -> void:
	hitstop_this_tick = false
	_frame_counter += 1
	tick_count += 1
	if invuln_frames > 0:
		invuln_frames -= 1

	# ---- 1. 取这一帧的输入（必须在 hitstop 的 return 之前！）----
	# 优先级：注入队列 > 粘住帧 > 真实 Input 采样
	var frame: InputBuffer.Frame
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
	if frame == null:
		frame = InputBuffer.Frame.new()
	input_buffer.push(frame)

	# ---- 2. Hitstop：冻结自己，不影响别人 ----
	if hitstop_frames > 0:
		hitstop_this_tick = true
		hitstop_frames -= 1
		# 只在"站得住"的状态下清零；LAUNCHED 必须保留击退速度，
		# 否则被击飞时挨顿帧会把自己钉在原地
		if state != State.LAUNCHED:
			velocity = Vector2.ZERO
		return

	_squash_timer = maxi(_squash_timer - 1, 0)
	if _squash_timer == 0:
		_lerp_visual_scale(0.18)

	# ---- 3. 地面/空中计数放在最前面 ----
	# 出招期间也要更新，否则"出招中能不能跳"的判断会用到过期数据。
	# 但跳跃缓冲的计数只在允许自由行动时消耗（见 _try_buffered_jump）。
	_update_ground_air()
	# J 的"按住了几帧"计时器也必须每帧更新（含顿帧期间的输入）
	_update_attack_hold(frame)

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
		_air_light_left = air_light_uses
		if ground_frames == 1:
			landed.emit()
	else:
		air_frames += 1
		ground_frames = 0
	frames_since_attack += 1


# ---------------------------------------------------------------- NEUTRAL

func _process_neutral(delta: float, frame: InputBuffer.Frame) -> void:
	# 【顺序很重要】先判跳跃，再判出招。
	# 反过来的话，缓冲里一条还没过期的攻击边沿会在每帧抢先起手，
	# 然后把跳跃输入一直压在缓冲里 —— 表现就是"按跳没反应"。
	# 而 W+J 的上挑不受影响：那条路径靠 aim_up（W 按住）+ attack_light 判定，
	# 只有在"攻击边沿存在"时才走，所以先判跳跃不会吃掉上挑。
	# W 同时是跳跃和上方向；W+J 必须优先判成地面上挑，不能先跳起来。
	var wants_up_attack := frame.actions.has(&"aim_up") and _has_edge(&"attack_light")
	if not wants_up_attack and _try_buffered_jump(frame):
		return

	var cmd := _resolve_attack_command(frame)
	if cmd != &"":
		# 起手这一帧也照常移动，点按 J / K 不能吞掉一帧走路或跳跃轨迹。
		_move_horizontal(delta, frame, 1.0)
		_apply_gravity(delta, _gravity)
		move_and_slide()
		_begin_command(cmd, frame)
		return

	_move_horizontal(delta, frame, 1.0)
	_apply_gravity(delta, _gravity)
	move_and_slide()


# ---------------------------------------------------------------- 跳跃

## 记录跳跃缓冲。任何状态都可以记录，只有允许自由行动时才消费。
##
## 【必须去边沿】一条按下边沿只能记一次跳跃。
## 早期版本这里只判 `pressed_this_frame` 就直接把缓冲拉满，而它在
## `_try_buffered_jump` 里是【先于】缓冲判定执行的 —— 于是第一跳之后的
## 下一个物理帧，同一条仍然存在于缓冲顶部的边沿又把缓冲拉满，
## 当场自动跳出第二跳（表现：按一次跳，二段跳被白白吃掉，且按键完全失灵）。
## 这和攻击边沿用 `_take_edge` 记账是同一个道理，所以这里也用 seq 记账。
func _buffer_jump(frame: InputBuffer.Frame) -> void:
	if frame.pressed_this_frame.has(&"jump"):
		if frame.seq != _consumed_edge.get(&"jump", -1):
			_consumed_edge[&"jump"] = frame.seq
			_jump_buffer_counter = jump_buffer_frames
	elif _jump_buffer_counter > 0:
		_jump_buffer_counter -= 1


func _can_jump() -> bool:
	if ground_frames > 0:
		return true
	if air_frames > 0 and air_frames <= coyote_frames:
		return true
	return _air_jumps_left > 0


## 消费跳跃缓冲；真的跳了返回 true。
func _try_buffered_jump(frame: InputBuffer.Frame) -> bool:
	_buffer_jump(frame)
	if _jump_buffer_counter <= 0 or not _can_jump():
		return false
	_do_jump()
	return true


func _do_jump() -> void:
	var is_double := ground_frames == 0 and not (air_frames > 0 and air_frames <= coyote_frames)
	_jump_buffer_counter = 0
	ground_frames = 0
	# 起跳前先把自己从几何体里"挤"出来。
	# 如果角色和地形有重叠（掉帧、被顶进平台、测试里瞬移），
	# move_and_slide 会优先解算重叠，把这一帧的起跳速度直接吃掉 ——
	# 实测表现是"按跳完全没反应"，而且 is_on_floor() 还是 false，
	# 光看地面判定根本查不出来。
	_depenetrate()
	if is_double:
		_air_jumps_left = maxi(_air_jumps_left - 1, 0)
		velocity.y = _jump_velocity * double_jump_scale
		# 二段跳更夸张的拉伸，和一段跳区分开
		_set_visual_scale(Vector2(0.74, 1.30))
		_squash_timer = 7
	else:
		# 首跳（含土狼时间内的那一跳）。
		#
		# 【重要契约】土狼窗口在首跳之后必须继续正常倒数，这里【不能】把
		# air_frames 清零重来：那会把窗口从起跳那一刻重新续上 6 帧，
		# 玩家在这段时间里按的第二跳会被一直算成"首跳"，
		# 二段跳的次数一点都掉不下去（实测就是这个症状）。
		# 让它自然走完 ≤coyote_frames 帧，之后再按才是真正的二段跳。
		air_frames = maxi(air_frames, 1)
		velocity.y = _jump_velocity
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
	velocity.y = minf(velocity.y, 2400.0)


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
	var axis := frame.axis
	var target := axis.x * speed * move_scale
	if not is_on_floor():
		target = velocity.x + (target - velocity.x) * air_control
	velocity.x = move_toward(velocity.x, target, acceleration * delta)
	if absf(axis.x) > 0.15:
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

	if airborne and _has_edge(&"attack_light"):
		if _air_light_left > 0:
			return &"air_up"
		# 没次数时也消费这次按键，避免之后被 K 重置后自动补出一刀。
		_take_edge(&"attack_light")
		return &""
	if _has_edge(&"attack_ranged"):
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
	for i in mini(attack_buffer_frames, input_buffer.frame_count()):
		var f := input_buffer.frame_at(i)
		if f == null or not f.pressed_this_frame.has(action):
			continue
		if f.seq == _consumed_edge.get(action, -1):
			return false
		_consumed_edge[action] = f.seq
		return true
	return false


func _has_edge(action: StringName) -> bool:
	for i in mini(attack_buffer_frames, input_buffer.frame_count()):
		var f := input_buffer.frame_at(i)
		if f != null and f.pressed_this_frame.has(action):
			# 只看最新一条匹配边沿；若它已消费，就不能让更老的边沿复活。
			return f.seq != _consumed_edge.get(action, -1)
	return false


func _held_within(action: StringName, n: int) -> bool:
	return input_buffer.held_within(action, n)


# ---------------------------------------------------------------- 起手

func _begin_command(cmd: StringName, frame: InputBuffer.Frame) -> void:
	match cmd:
		&"parry":
			_take_edge(&"parry")
			_start_move(parry_move, false)
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
			# 连段断太久就从头起手（但"取消不重置"——见 _end_attack）
			if frames_since_attack > combo_keep_frames:
				combo_index = 0
			_start_move(light_combo[clampi(combo_index, 0, light_combo.size() - 1)], false)


func _start_move(mv: Resource, is_up: bool) -> void:
	if mv == null:
		return
	current_move = mv
	if not mv.is_charge:
		_charge_t = 0.0
	current_is_up = is_up
	move_frame = 0
	if _melee != null and mv.hitbox.size.x > 0:
		_melee_base_offset_x = absf(mv.hitbox.position.x)
		_melee.position.y = mv.hitbox.position.y + foot_offset
		var shape: RectangleShape2D = _melee.get_node("CollisionShape2D").shape
		shape.size = mv.hitbox.size
		_sync_melee_offset()
	state = State.ATTACK
	link_open = false
	last_swing_hit = false
	_hit_this_swing.clear()
	if _is_light_finisher(mv):
		_air_light_left = maxi(_air_light_left, 1)
	# 前摇反向蓄力（设计文档 §8.4 Anticipation）
	var windup := Vector2(0.90, 1.12)
	if is_up:
		windup = Vector2(1.10, 0.90)
	_set_visual_scale(windup)
	_squash_timer = 4
	move_started.emit(mv, combo_index if light_combo.has(mv) else -1)


func _start_charge() -> void:
	if charge_move == null:
		return
	_take_edge(&"attack_light")
	if not is_on_floor() and air_frames > coyote_frames:
		return
	charge_frames = 0
	_charge_accum = 0.0
	velocity.x = 0.0
	charge_started.emit()


## K：发射一发远程弹丸。
##
## 刻意【不】改 combo_index、也不走 _start_move —— 所以：
##   · 连段指针被"存"住，J→K→J 的第三个 J 仍然是强化普攻
##   · 远程不占连段帧，随时能放
func _start_ranged() -> void:
	if ranged_move == null:
		return
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
	p.global_position = global_position + Vector2(ranged_offset.x * float(facing), ranged_offset.y)
	if p.has_signal(&"hit_target"):
		p.hit_target.connect(_on_projectile_hit)
	# 连段保留窗口要放长：远程是"存连段"的中转，不能因为它把连段过期掉
	frames_since_attack = 0
	ranged_fired.emit(p)


func _on_projectile_hit(target: Node, point: Vector2) -> void:
	last_swing_hit = true
	hit_confirmed.emit(target, ranged_move, point)


# ---------------------------------------------------------------- 蓄力

## 蓄力阶段：站着攒，攒到上限就继续攒但不加成了。
func _process_charge(delta: float, frame: InputBuffer.Frame) -> void:
	# 蓄力速率是倍率（charge_boost 道具写 charge_rate_scale）。
	# 【为什么要浮点累加器】直接用 int 递增会丢掉 1.6 这种非整数倍率的零头，
	# 于是"加速 60%"实际只快 50% —— 玩家能感觉到不对劲但说不清哪里不对。
	_charge_accum += maxf(charge_rate_scale, 0.05)
	while _charge_accum >= 1.0:
		_charge_accum -= 1.0
		charge_frames += 1
	var cm := charge_move
	var cap: int = cm.max_charge_frames
	var t := clampf(float(charge_frames) / float(maxi(cap, 1)), 0.0, 1.0)

	# 蓄力表现：越攒越"缩"，同时抖起来
	var sq := Vector2(1.0 + 0.18 * t, 1.0 - 0.18 * t)
	if charge_frames % 3 == 0:
		sq.x += 0.03 * t * (1.0 if charge_frames % 6 == 0 else -1.0)
	_set_visual_scale(sq)
	_squash_timer = 2

	velocity.x = move_toward(velocity.x, 0.0, speed * 8.0 * delta)

	# 松开（或到达上限自动放）就出招
	var released := not frame.actions.has(&"attack_light")
	if released and charge_frames >= cm.min_charge_frames:
		_release_charge()
		return
	if charge_frames >= cm.max_charge_frames:
		_release_charge()
		return
	# 还没到最短蓄力就松手 → 当成一次普通轻击（不惩罚玩家）
	if released and charge_frames < cm.min_charge_frames:
		charge_frames = -1
		if not light_combo.is_empty():
			_start_move(light_combo[0], false)
		return

	_apply_gravity(delta, _gravity)
	move_and_slide()


## 放出蓄力斩：把蓄力量化成 damage / knockback / hitstop 三个倍率。
func _release_charge() -> void:
	last_charge_frames = charge_frames
	var cm := charge_move
	var t := clampf(float(charge_frames) / float(maxi(cm.max_charge_frames, 1)), 0.0, 1.0)
	# 存进"这一刀的实际数值"，命中时用
	_charge_t = t
	charge_frames = -1
	_charge_accum = 0.0
	_start_move(cm, false)
	charge_released.emit(last_charge_frames, t > 0.35)


# ---------------------------------------------------------------- 出招

func _process_attack(delta: float, frame: InputBuffer.Frame) -> void:
	var mv := current_move
	if mv == null:
		state = State.NEUTRAL
		return

	var phase: StringName = mv.phase_at(move_frame)

	if phase == &"startup":
		# 前摇：能走位，但不能取消
		_move_horizontal(delta, frame, mv.startup_movement_scale)

	elif phase == &"active":
		# 弹刀【不做攻击判定】—— 它是防守动作，"谁在窗口里打我我就弹谁"
		# 这条判定在 take_hit 那一侧。让它顺手打一下的话，0 伤害 0 击退的一击
		# 仍然会把怪推进 LAUNCHED → 倒地 26 帧，等于白送一个击倒。
		if not _is_parry_move(mv):
			_do_hit_check(mv)
			if hitstop_this_tick:
				return
		# 命中前冲：只在判定帧的头几帧推一次，做出"撞上去"的顿挫
		if move_frame == mv.startup_frames and mv.lunge > 0.0 and absf(frame.axis.x) < 0.15:
			velocity.x = float(facing) * mv.lunge
		_move_horizontal(delta, frame, mv.movement_scale)

	elif phase == &"recovery":
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
				return
			# K 随时能补一发远程，且不影响连段指针（"存连段"的中转）
			if _has_edge(&"attack_ranged"):
				_link_into(&"attack_ranged")
				return
			# J：按住 → 蓄力斩；点按 → 推进连段
			if _resolve_light_press():
				return
			link_open = false
		# 后摇也能走位（走得慢一点），这是"取消不重置"之外的第二条流畅度来源
		_move_horizontal(delta, frame, mv.recovery_movement_scale)
		# 后摇里按 W 可以跳起来取消（地面常用）
		if _try_buffered_jump(frame):
			return

	_apply_gravity(delta, _gravity)
	move_and_slide()

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
##   · 空中且已过土狼时间 → 那种情况要出的是"空中向上打"，不是蓄力
func _should_charge_on_hold() -> bool:
	if charge_move == null or current_move == charge_move:
		return false
	if not is_on_floor() and air_frames > coyote_frames:
		return false
	return _attack_hold_frames >= hold_to_charge_frames


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
		_start_move(parry_move, false)
		return
	_take_edge(&"attack_light")
	var frame_ctx := input_buffer.frame_at(0)
	var aim_up := frame_ctx != null and frame_ctx.actions.has(&"aim_up")
	if aim_up and up_strike_move != null:
		_start_move(up_strike_move, true)
		return
	if light_combo.is_empty():
		return
	combo_index = mini(combo_index + 1, light_combo.size() - 1)
	_start_move(light_combo[combo_index], false)


func _end_attack() -> void:
	current_move = null
	current_is_up = false
	state = State.NEUTRAL
	frames_since_attack = 0
	# 连段指针的规则：
	#   · 打中了 → 保留（"取消连段不重置"）
	#   · 完全挥空 → 归零
	# 这样"打空一下"会断连段，但"取消/走位后接着打"不会。
	if not last_swing_hit:
		combo_index = 0
	link_open = false


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
		if owner_node.get("hp") != null and float(owner_node.get("hp")) <= 0.0:
			continue
		# 只打身前（朝向那一侧），避免背对敌人也能命中
		var dx: float = owner_node.global_position.x - global_position.x
		if absf(dx) > 1.0 and signf(dx) != float(facing):
			continue

		_hit_this_swing[owner_node.get_instance_id()] = true
		var point: Vector2 = (global_position + owner_node.global_position) * 0.5
		var parried: bool = owner_node.take_hit(mv, facing, point, _charge_t, current_is_up, attack_damage_mul, self)
		if parried:
			continue
		last_swing_hit = true
		# Apply the attacker's pause on a real hit, not only when this actor receives damage.
		var charge_bonus := roundi(mv.charge_hitstop_bonus * _charge_t)
		hitstop_frames = maxi(hitstop_frames, mv.hitstop_frames + charge_bonus)
		hitstop_this_tick = hitstop_frames > 0
		_set_visual_scale(mv.squash)
		_squash_timer = 2
		hit_confirmed.emit(owner_node, mv, point)


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

	velocity.y += _fall_gravity * gravity_scale_launched * delta
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
	state = State.DEAD
	hp = 0.0
	velocity = Vector2.ZERO
	hitstop_frames = 0
	charge_frames = -1
	_charge_accum = 0.0
	_set_visual_scale(Vector2(1.40, 0.45))
	died.emit()


func _enter_down() -> void:
	state = State.DOWN
	down_frames = 26
	velocity = Vector2.ZERO
	_set_visual_scale(Vector2(1.25, 0.72))
	_squash_timer = 0
	# 【一次性预支整段无敌窗口】而不是在 _process_down 里逐帧续期。
	# take_hit 只看 invuln_frames 这一个数，预支出去之后这段窗口就是连续、
	# 不可被打断的；逐帧续则会在"起身那一帧"露出一个空档，又被打回倒地。
	if getup_invuln_frames > 0:
		invuln_frames = maxi(invuln_frames, down_frames + getup_invuln_frames)


func _process_down(delta: float) -> void:
	_apply_gravity(delta, _fall_gravity)
	velocity.x = move_toward(velocity.x, 0.0, 900.0 * delta)
	move_and_slide()
	down_frames -= 1
	if down_frames <= 0:
		state = State.NEUTRAL
		combo_index = 0
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
	if attacker != null and attacker.has_method(&"on_parried") and is_parrying():
		_do_parry(attacker, _point)
		return true
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
	# 被击退时朝向攻击者
	_set_facing(-from_facing)
	return false


## 现在处于"招架判定帧"吗 —— 弹刀唯一的**时间**条件。
##
## 【为什么每次去问招式数据】窗口长度就是 .tres 里的 active_frames。
## 在工坊里把它从 4 改成 6，判定当场变宽，代码一行不用动。
## 走的又是 MoveDefinition.is_parry_move()，所以"哪种招式算招架"
## 全项目只有一个来源（加"上段弹刀"不用改这里）。
func is_parrying() -> bool:
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
	hitstop_frames = maxi(hitstop_frames, parry_hitstop_frames)
	hitstop_this_tick = hitstop_frames > 0
	set(&"velocity", Vector2(velocity.x * 0.2, velocity.y))
	_set_visual_scale(Vector2(1.16, 0.88))
	_squash_timer = 5
	# 弹开算"有效动作"：连段指针不该因为这一下被当成挥空而归零
	last_swing_hit = true
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
	hitstop_frames = maxi(hitstop_frames, 8)
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
	global_position = pos
	velocity = Vector2.ZERO
	hp = max_hp
	state = State.NEUTRAL
	current_move = null
	current_is_up = false
	move_frame = 0
	combo_index = 0
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
	down_frames = 0
	ground_frames = 0
	air_frames = 0
	_air_jumps_left = extra_air_jumps
	_air_light_left = air_light_uses
	_jump_buffer_counter = 0
	input_buffer.clear()
	_sync_melee_offset()      # 复活/换边后判定盒要重新贴回当前朝向
	if _visual != null:
		_visual.scale = Vector2(float(facing), 1.0)
		_sync_visual_pivot()


func is_busy() -> bool:
	return state != State.NEUTRAL

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
	# Stretch around the foot position, so the detailed sprite does not slide through the floor.
	_visual.position.y = foot_offset * (1.0 - _visual.scale.y)
