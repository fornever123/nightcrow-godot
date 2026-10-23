extends Node2D
## 试玩版敌人「影」：程序绘制的影子剑士（不需要新美术）。
##
## 战斗主题“眩晕连段”的另一半就在这里（设计见 docs/HANDOFF-试玩版.md §7）：
##   连续命中 → 基础击退逐段增强 → 重招/上挑进入浮空
##   → 浮空连段（每一下把它托住，但越连托得越低、掉得越快 = 衰减）
##   → 方向终结（S+J 下砸：落地反弹 + 冲击波；前+第三刀：横斩撞墙）
##   → 连锁击飞（高速飞出去的影撞到别的影，把它们一起撞飞）
##
## 物理全部手动积分（地面 floor_y + 多层地形 terrain.gd，封印墙是 arena_left/right），
## 不依赖碰撞体，所以不会出现“贴地时上挑被地面法线挡住”的老问题。
## 多层地形（第三轮节点 17）：脚下的面问 terrain.support_y()，石台侧面问 terrain.push_out()；
## 会跳上平台、从单向平台往下穿去追玩家，只和同一层的人互推、只打同一层的玩家。
## 原点 = 身体中心（和木桩一致：玩家的命中点 = 两者中点）。
##
## 第四轮（照《疯狂小人战斗》，见交接文档 §16）：
##   · 四种影：影卒（快攻，会举刀格挡 / 翻滚）、甲影（重甲霸体，常格挡）、
##     影弓（拉开距离射影矢）、影爆（抛炸弹）。参数全在 KINDS 表里。
##   · 连击击退：第一下就有明确推力，连续命中按 combo_taken 逐步增强；落地后清零。
##   · 连段伤害递增：同一套连段里越往后越疼，落地站起清零。
##   · 会误伤：影卒 / 甲影的刀、影矢、炸弹都会打到挡在路上的同伴。

const MoveDefinition := preload("res://scripts/core/move_definition.gd")
const Bolt := preload("res://scripts/night/shade_bolt.gd")
const Bomb := preload("res://scripts/night/shade_bomb.gd")
var hitstop_multiplier: float = 1.0

signal damaged(amount: float, total: float, point: Vector2)
signal wall_slam(impact_speed: float, damage: float, point: Vector2)
signal died()
signal parried(by: Node, point: Vector2)
signal broken(point: Vector2)
signal launched_high(point: Vector2)
signal chain_hit(level: int, point: Vector2)
signal slam_impact(point: Vector2, strength: float)
signal strike_landed(point: Vector2)
## 音效用：开始蓄力 / 挥出（heavy = 甲影）
signal windup_started(heavy: bool)
signal strike_started(heavy: bool)
signal guarded(point: Vector2)            ## 举刀挡住了玩家这一刀
signal guard_broken(point: Vector2)       ## 格挡被重招砸开
signal dodged(point: Vector2)             ## 翻滚躲开
signal friendly_hit(point: Vector2)       ## 打到了自己人（误伤）
signal projectile_spawned(node: Node2D)   ## 射出影矢 / 扔出炸弹

enum Kind { GRUNT, BRUTE, ARCHER, BOMBER }
enum State { IDLE, APPROACH, WINDUP, STRIKE, RECOVER, HITSTUN, LAUNCHED, DOWN, STUNNED, DEAD, GUARD, ROLL }

## weight：击退倍率（疯狂小人的“体重”：越小越重、越难打飞）；guard / roll：看到玩家出招时举刀 / 翻滚的概率；
## keep_min / keep_max：远程影想保持的距离；down：倒地帧数。
const KINDS := {
	Kind.GRUNT: {"name": "影卒", "hp": 90.0, "poise": 40.0, "half_w": 24.0, "half_h": 60.0, "speed": 230.0,
		"range": 132.0, "windup": 16, "strike": 6, "recover": 18, "damage": 8.0, "knock": 260.0,
		"cool_min": 25, "cool_max": 60, "stun": 60, "armor": false, "lunge": 300.0,
		"weight": 1.0, "guard": 0.2, "roll": 0.15, "guard_frames": 22, "down": 24, "ranged": false},
	Kind.BRUTE: {"name": "甲影", "hp": 220.0, "poise": 110.0, "half_w": 36.0, "half_h": 76.0, "speed": 120.0,
		"range": 175.0, "windup": 26, "strike": 8, "recover": 30, "damage": 15.0, "knock": 420.0,
		"cool_min": 45, "cool_max": 90, "stun": 80, "armor": true, "lunge": 200.0,
		"weight": 0.6, "guard": 0.35, "roll": 0.0, "guard_frames": 34, "down": 20, "ranged": false},
	Kind.ARCHER: {"name": "影弓", "hp": 70.0, "poise": 34.0, "half_w": 22.0, "half_h": 58.0, "speed": 210.0,
		"range": 760.0, "windup": 24, "strike": 6, "recover": 20, "damage": 9.0, "knock": 300.0,
		"cool_min": 50, "cool_max": 100, "stun": 50, "armor": false, "lunge": 0.0,
		"weight": 1.1, "guard": 0.0, "roll": 0.4, "guard_frames": 0, "down": 24, "ranged": true,
		"keep_min": 430.0, "keep_max": 700.0},
	Kind.BOMBER: {"name": "影爆", "hp": 80.0, "poise": 36.0, "half_w": 26.0, "half_h": 56.0, "speed": 170.0,
		"range": 640.0, "windup": 28, "strike": 6, "recover": 24, "damage": 14.0, "knock": 560.0,
		"cool_min": 70, "cool_max": 120, "stun": 50, "armor": false, "lunge": 0.0,
		"weight": 1.15, "guard": 0.0, "roll": 0.2, "guard_frames": 0, "down": 24, "ranged": true,
		"keep_min": 300.0, "keep_max": 600.0},
}
const LAUNCH_GRAVITY := 1600.0
const FALL_GRAVITY := 2000.0
const CHAIN_SPEED := 480.0
const JUGGLE_SOFT_CAP := 12        ## 超过后不再托起（浮空衰减的硬上限）
const PARRY_POISE := 55.0
const WALL_DAMAGE_SCALE := 0.045
const POISE_REGEN_DELAY := 90
const POISE_REGEN := 0.55          ## 每帧
const PARRY_CUE := 10              ## 出刀前多少帧亮"刀尖白星"（配合试玩场景 12 帧弹刀窗口）
const BASE_KNOCKBACK_SCALE := 1.35 ## 格斗游戏式基础推力：第一下也能读出位移
const COMBO_KNOCK_STEP := 0.24     ## 每次连续命中额外 +24% 推力
const COMBO_KNOCK_MAX := 2.5
const COMBO_DMG_STEP := 0.05       ## 同一套连段每多挨一下，伤害 +5%（最多 +50%）
const ROLL_FRAMES := 18
const ROLL_IFRAMES := 14
const ROLL_SPEED := 620.0
const FRIENDLY_DAMAGE := 0.5       ## 误伤同伴打几折
## 这些招式能砸开举刀格挡（其余的会被挡住）
const GUARD_BREAKERS := [&"light_3", &"charge_1", &"up_strike", &"dash_slash", &"dash_slash_left", &"ult"]

var kind: int = Kind.GRUNT
var spec: Dictionary
var state: State = State.IDLE
var facing: int = -1
var velocity: Vector2 = Vector2.ZERO
var hp: float = 110.0
var max_hp: float = 110.0
var hp_scale: float = 1.0
var poise: float = 0.0
var max_poise: float = 46.0
var half_w: float = 24.0
var half_h: float = 60.0
var floor_y: float = 580.0
var arena_left: float = -INF
var arena_right: float = INF
var target: Node2D = null
## 多层地形（terrain.gd）；为空 = 平地（训练/测试场景）
var terrain = null
var active: bool = true
var max_attackers: int = 1

var hitstop_frames: int = 0
var state_frames: int = 0
var stun_frames: int = 0
var stun_total: int = 1
var pending_stun: int = 0
var cooldown: int = 60
var down_frames: int = 0
var poise_idle: int = 0
var break_resist: int = 0
var juggle_count: int = 0
var bounces: int = 0
var slammed: bool = false
var driven_frames: int = 0
var chain_armed: bool = false
var chain_level: int = 0
var wall_slam_count: int = 0
var last_hit_damage: float = 0.0
var total_damage_taken: float = 0.0
var dead_frames: int = 0
var spawn_frames: int = 0
var pct: float = 0.0                ## 击退百分比（= 累计挨的伤害，显示在血条旁）
var combo_taken: int = 0            ## 这一套连段挨了几下（站起来清零）
var guard_frames: int = 0
var roll_frames: int = 0
var roll_dir: int = 1
var react_cool: int = 0
var _seen_serial: int = -1
var aim: Vector2 = Vector2.RIGHT     ## 影弓瞄准方向 / 影爆抛投目标（世界坐标差）
var _chained: Dictionary = {}
var _probe_y: float = INF           ## 这一帧开始时的脚底 y（落地判定用：穿过平台的那一帧也接得住）
var _drop_y: float = NAN            ## 正在往下穿的单向平台高度
var jump_cool: int = 0
var _blocked: int = 0               ## 这一帧被石台侧面挡住：+1 石台在右、−1 在左
var _target_level: float = NAN      ## 玩家最近一次站着时脚下那一层的高度
var _strike_done: bool = false
var _wall_factor: float = 0.5
var strike_move: MoveDefinition

# 表现
var anim_t: float = 0.0
var flash: int = 0
var flash_color: Color = Color.WHITE
var squash: Vector2 = Vector2.ONE
var armor_flash: int = 0
var lamp: Vector3 = Vector3.ZERO      ## 灯笼暖光（night_trial 每帧填）：x 强度，(y,z) 指向灯笼
var _rng := RandomNumberGenerator.new()
var _hurtbox: Area2D
static var _font: Font


func setup(p_kind: int, p_target: Node2D, p_floor_y: float, hp_mul: float = 1.0) -> void:
	kind = p_kind
	target = p_target
	floor_y = p_floor_y
	hp_scale = hp_mul


func _ready() -> void:
	if _font == null:
		var sf := SystemFont.new()
		sf.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "Noto Sans SC", "sans-serif"])
		_font = sf
	add_to_group(&"shade")
	_rng.randomize()
	spec = KINDS[kind]
	max_hp = float(spec.hp) * hp_scale
	hp = max_hp
	max_poise = float(spec.poise) * (1.0 + (hp_scale - 1.0) * 0.5)
	half_w = float(spec.half_w)
	half_h = float(spec.half_h)
	cooldown = _rng.randi_range(40, 90)
	position.y = ground_y()
	spawn_frames = 36
	strike_move = MoveDefinition.new()
	strike_move.id = &"shade_strike"
	strike_move.damage = float(spec.damage)
	strike_move.knockback = float(spec.knock)
	strike_move.knockback_angle = 24.0
	# 强反馈档：命中双方独立停顿；统一倍率也覆盖敌人与次生碰撞。
	strike_move.victim_hitstop_frames = roundi((14 if kind == Kind.BRUTE else 10) * hitstop_multiplier)
	strike_move.hitstop_frames = roundi((10 if kind == Kind.BRUTE else 8) * hitstop_multiplier)
	strike_move.squash = Vector2(1.25, 0.82)
	strike_move.shake_amount = 12.0 if kind == Kind.BRUTE else 7.0
	if kind == Kind.ARCHER:
		strike_move.id = &"shade_bolt"
		strike_move.knockback_angle = 14.0
		strike_move.victim_hitstop_frames = roundi(8 * hitstop_multiplier)
		strike_move.shake_amount = 4.0
	elif kind == Kind.BOMBER:
		strike_move.id = &"shade_bomb"
		strike_move.knockback_angle = 58.0
		strike_move.forces_launch = true
		strike_move.launch_speed = absf(float(spec.knock)) * 0.85
		strike_move.victim_hitstop_frames = roundi(16 * hitstop_multiplier)
		strike_move.shake_amount = 0.0
	_hurtbox = Area2D.new()
	_hurtbox.name = "Hurtbox"
	_hurtbox.collision_layer = 4
	_hurtbox.collision_mask = 0
	_hurtbox.monitoring = false
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(half_w * 2.0 + 18.0, half_h * 2.0 + 6.0)
	shape.shape = rect
	_hurtbox.add_child(shape)
	add_child(_hurtbox)


func ground_y() -> float:
	if terrain == null:
		return floor_y - half_h
	return terrain.support_y(position.x, minf(position.y + half_h, _probe_y), half_w * 0.5, _drop_y) - half_h


func feet_y() -> float:
	return position.y + half_h


## 现在站的这一层的高度（脚下的面）
func level_y() -> float:
	return ground_y() + half_h


func on_ground() -> bool:
	return velocity.y >= -1.0 and position.y >= ground_y() - 0.5


func is_stunned() -> bool:
	return state == State.STUNNED


## 给玩家的"贴身刹车"用（player._clamp_root_motion）
func blocks_body() -> bool:
	return state != State.DEAD and spawn_frames <= 0


func is_airborne() -> bool:
	return state == State.LAUNCHED or (state == State.DEAD and not on_ground())


func is_attacking() -> bool:
	return state == State.WINDUP or state == State.STRIKE


func is_armored() -> bool:
	return bool(spec.armor) and is_attacking()


func is_alive() -> bool:
	return state != State.DEAD


func is_ranged_kind() -> bool:
	return bool(spec.get("ranged", false))


## 现在挨打会飞多远：基础推力 × 体重 × 连续命中倍率。
func knock_mul() -> float:
	var combo_step := clampi(combo_taken - 1, 0, 6)
	return clampf(float(spec.get("weight", 1.0)) * (1.0 + COMBO_KNOCK_STEP * float(combo_step)), 0.3, COMBO_KNOCK_MAX)


## 翻滚的无敌帧
func is_dodging() -> bool:
	return state == State.ROLL and roll_frames > ROLL_FRAMES - ROLL_IFRAMES


func telegraph() -> float:
	if state == State.WINDUP:
		return clampf(float(state_frames) / float(spec.windup), 0.0, 1.0)
	if state == State.STRIKE:
		return 1.0
	return 0.0


func display_name() -> String:
	return String(spec.name)


# ---------------------------------------------------------------- 主循环

func _physics_process(delta: float) -> void:
	_probe_y = position.y + half_h
	if is_finite(_drop_y) and _probe_y > _drop_y + 30.0:
		_drop_y = NAN
	if jump_cool > 0:
		jump_cool -= 1
	anim_t += delta
	if flash > 0:
		flash -= 1
	if armor_flash > 0:
		armor_flash -= 1
	squash = squash.lerp(Vector2.ONE, 0.2)
	if state == State.DEAD:
		_process_dead(delta)
		queue_redraw()
		return
	if hitstop_frames > 0:
		hitstop_frames -= 1
		queue_redraw()
		return
	if spawn_frames > 0:
		spawn_frames -= 1
	if react_cool > 0:
		react_cool -= 1
	_update_poise()
	if state == State.IDLE or state == State.APPROACH:
		combo_taken = 0
		_react_to_player()
	elif target != null and is_instance_valid(target) and target.get(&"action_serial") != null:
		# 挨打 / 出刀 / 倒地期间玩家出的招不算“看到了”——站起来以后只对新出的招反应
		_seen_serial = int(target.get(&"action_serial"))
	match state:
		State.IDLE, State.APPROACH:
			if is_ranged_kind():
				_process_ranged_ai(delta)
			else:
				_process_ai(delta)
		State.WINDUP:
			_process_windup(delta)
		State.STRIKE:
			_process_strike(delta)
		State.RECOVER:
			_process_recover(delta)
		State.HITSTUN:
			_process_hitstun(delta)
		State.LAUNCHED:
			_process_launched(delta)
		State.DOWN:
			_process_down(delta)
		State.STUNNED:
			_process_stunned(delta)
		State.GUARD:
			_process_guard(delta)
		State.ROLL:
			_process_roll(delta)
	if state != State.LAUNCHED:
		_separate()
	queue_redraw()


func _update_poise() -> void:
	if break_resist > 0:
		break_resist -= 1
	if state == State.STUNNED:
		return
	poise_idle += 1
	if poise_idle > POISE_REGEN_DELAY and poise > 0.0:
		poise = maxf(0.0, poise - POISE_REGEN)


# ---------------------------------------------------------------- AI

func _target_ok() -> bool:
	if not active or spawn_frames > 0 or target == null or not is_instance_valid(target):
		return false
	var st = target.get(&"state")
	# 玩家 State.DEAD = 4（player.gd 的 enum State { NEUTRAL, ATTACK, LAUNCHED, DOWN, DEAD }）
	return st == null or int(st) != 4


func _process_ai(delta: float) -> void:
	_ground_physics(delta)
	if not _target_ok():
		velocity.x = move_toward(velocity.x, 0.0, 900.0 * delta)
		state = State.IDLE
		return
	var dx := target.global_position.x - global_position.x
	var dist := absf(dx)
	if dist > 6.0:
		facing = 1 if dx > 0.0 else -1
	cooldown -= 1
	var want := float(spec.range) * 0.82
	# 多层地形：玩家站在别的层 → 先想办法上去 / 下去，不在原地干等
	var lvl := _level_gap()
	if absf(lvl) >= 40.0:
		state = State.APPROACH
		_chase_level(lvl, dx, delta)
		return
	if dist > want:
		state = State.APPROACH
		velocity.x = move_toward(velocity.x, float(facing) * float(spec.speed), 900.0 * delta)
		_hop_obstacle()
	elif dist < want * 0.45:
		# 贴太近：往后让一步，给玩家留出看得清的出刀距离
		state = State.APPROACH
		velocity.x = move_toward(velocity.x, -float(facing) * float(spec.speed) * 0.6, 900.0 * delta)
	else:
		state = State.IDLE
		velocity.x = move_toward(velocity.x, 0.0, 1400.0 * delta)
	var dy := absf(target.global_position.y - global_position.y)
	if cooldown <= 0 and dist <= float(spec.range) * 1.05 and dy < 150.0 and on_ground() and _attack_slot_free():
		_begin_windup()


## 玩家那一层减去自己这一层（负 = 玩家在上面）。玩家跳起来时沿用他最近站过的那一层。
func _level_gap() -> float:
	if terrain == null:
		return 0.0
	var tf := _target_feet()
	var standing := true
	if target is CharacterBody2D:
		standing = (target as CharacterBody2D).is_on_floor()
	if standing or not is_finite(_target_level):
		_target_level = terrain.support_y(target.global_position.x, tf, 12.0)
	if not on_ground():
		return 0.0 if absf(_target_level - feet_y()) < 40.0 else _target_level - level_y()
	return _target_level - level_y()


func _target_feet() -> float:
	var fo = target.get(&"foot_offset")
	return target.global_position.y + (float(fo) if fo != null else half_h)


## 追到别的层：玩家在上面 → 走近了就起跳（跳到比那一层高 40）；在下面 → 单向平台直接往下穿，石台就走下边缘
func _chase_level(lvl: float, dx: float, delta: float) -> void:
	var sp := float(spec.speed)
	var dist := absf(dx)
	if lvl < 0.0:
		var near := dist < 300.0
		var goal := float(facing) * sp * (1.15 if not on_ground() else (1.0 if dist > 40.0 else 0.0))
		velocity.x = move_toward(velocity.x, goal, 900.0 * delta)
		if near and on_ground() and jump_cool <= 0:
			_jump(-lvl + 40.0)
		else:
			_hop_obstacle()
	else:
		velocity.x = move_toward(velocity.x, float(facing) * sp, 900.0 * delta)
		_hop_obstacle()
		if on_ground() and not is_finite(_drop_y):
			var ow: float = terrain.one_way_at(position.x, feet_y(), half_w * 0.5)
			if is_finite(ow) and (dist < 360.0 or _rng.randf() < 0.02):
				_drop_y = ow
				squash = Vector2(1.12, 0.9)


## 往前走被石台侧面挡住 → 跳上去（翻过去）
func _hop_obstacle() -> void:
	if terrain == null or _blocked != facing or not on_ground() or jump_cool > 0:
		return
	var top: float = terrain.solid_top(position.x + float(facing) * (half_w + 12.0), 4.0)
	_jump(feet_y() - top + 36.0)


func _jump(height: float) -> void:
	velocity.y = -sqrt(2.0 * FALL_GRAVITY * maxf(height, 40.0))
	position.y += velocity.y / 60.0
	jump_cool = 50 if kind == Kind.GRUNT else 80
	squash = Vector2(0.84, 1.18)


func _attack_slot_free() -> bool:
	var n := 0
	var ranged := is_ranged_kind()
	for o in get_tree().get_nodes_in_group(&"shade"):
		# 远程影和近战影各算各的名额：弓手拉弓时，影卒照样能冲上来
		if o != self and o.is_attacking() and o.is_ranged_kind() == ranged:
			n += 1
	return n < (1 if ranged else max_attackers)


# ---------------------------------------------------------------- 第四轮：看到出招就反应（格挡 / 翻滚）

## 玩家每出一招（action_serial 变了）只掷一次骰子。只有站着没事干的时候才会反应——
## 已经在挨打（硬直 / 浮空 / 倒地）的影挡不了，所以“先打中的人赢”。
func _react_to_player() -> void:
	if react_cool > 0 or not _target_ok():
		return
	var serial = target.get(&"action_serial")
	if serial == null or int(serial) == _seen_serial:
		return
	var st = target.get(&"state")
	var mv = target.get(&"current_move")
	if st == null or int(st) != 1 or mv == null:   # 玩家 State.ATTACK = 1
		return
	_seen_serial = int(serial)
	var cmd: StringName = mv.get(&"command") if mv.get(&"command") != null else &""
	if not cmd in [&"light", &"charge", &"dash", &"air_light", &"ranged"]:
		return
	var dx := global_position.x - target.global_position.x
	var reach := 520.0 if cmd == &"ranged" or cmd == &"dash" else 300.0
	if absf(dx) > reach or absf(target.global_position.y - global_position.y) > 140.0:
		return
	var tf = target.get(&"facing")
	if tf != null and absf(dx) > 8.0 and signf(dx) != float(int(tf)):
		return   # 玩家背对着我出招，不用躲
	var r := _rng.randf()
	var g := float(spec.get("guard", 0.0))
	var ro := float(spec.get("roll", 0.0))
	if r < g:
		_begin_guard()
	elif r < g + ro and on_ground():
		_begin_roll()


func _begin_guard() -> void:
	state = State.GUARD
	guard_frames = int(spec.get("guard_frames", 22))
	react_cool = guard_frames + 30
	velocity.x = 0.0
	squash = Vector2(0.92, 1.08)
	if target != null and is_instance_valid(target):
		var dx := target.global_position.x - global_position.x
		if absf(dx) > 4.0:
			facing = 1 if dx > 0.0 else -1


func _process_guard(delta: float) -> void:
	_ground_physics(delta)
	velocity.x = move_toward(velocity.x, 0.0, 1400.0 * delta)
	guard_frames -= 1
	if guard_frames <= 0:
		# 放下刀马上反击（挡完就砍，逼玩家弹刀）
		state = State.IDLE
		cooldown = mini(cooldown, 2)


## 翻滚：往后撤；背后贴墙就从玩家身边滚过去（穿身）
func _begin_roll() -> void:
	var away := 1 if global_position.x >= target.global_position.x else -1
	var room := (arena_right - global_position.x) if away > 0 else (global_position.x - arena_left)
	roll_dir = away if room > 220.0 else -away
	state = State.ROLL
	roll_frames = ROLL_FRAMES
	react_cool = 70
	velocity.x = float(roll_dir) * ROLL_SPEED
	facing = -roll_dir if roll_dir == away else roll_dir
	squash = Vector2(1.2, 0.75)
	dodged.emit(global_position)


func _process_roll(delta: float) -> void:
	_ground_physics(delta)
	roll_frames -= 1
	squash = Vector2(1.28, 0.62) if roll_frames > 4 else squash
	if roll_frames < 6:
		velocity.x = move_toward(velocity.x, 0.0, 4000.0 * delta)
	if roll_frames <= 0:
		state = State.IDLE
		cooldown = mini(cooldown, _rng.randi_range(6, 20))
		if target != null and is_instance_valid(target):
			var dx := target.global_position.x - global_position.x
			if absf(dx) > 4.0:
				facing = 1 if dx > 0.0 else -1


# ---------------------------------------------------------------- 第四轮：远程影（影弓 / 影爆）

## 保持距离：太近就后撤（背后没地方就翻滚穿过去），太远就靠近，距离合适就出手
func _process_ranged_ai(delta: float) -> void:
	_ground_physics(delta)
	if not _target_ok():
		velocity.x = move_toward(velocity.x, 0.0, 900.0 * delta)
		state = State.IDLE
		return
	var dx := target.global_position.x - global_position.x
	var dist := absf(dx)
	if dist > 6.0:
		facing = 1 if dx > 0.0 else -1
	cooldown -= 1
	var keep_min := float(spec.get("keep_min", 400.0))
	var keep_max := float(spec.get("keep_max", 700.0))
	var lvl := _level_gap()
	if absf(lvl) >= 40.0 and dist < keep_min * 0.8:
		state = State.APPROACH
		_chase_level(lvl, dx, delta)
		return
	var cornered := false
	if dist < keep_min:
		state = State.APPROACH
		var back := -facing
		var room := (arena_right - global_position.x) if back > 0 else (global_position.x - arena_left)
		cornered = room < 120.0
		if room < 120.0 and dist < 200.0 and react_cool <= 0 and on_ground():
			_begin_roll()
			return
		velocity.x = move_toward(velocity.x, float(back) * float(spec.speed), 1100.0 * delta)
	elif dist > keep_max:
		state = State.APPROACH
		velocity.x = move_toward(velocity.x, float(facing) * float(spec.speed), 900.0 * delta)
		_hop_obstacle()
	else:
		state = State.IDLE
		velocity.x = move_toward(velocity.x, 0.0, 1400.0 * delta)
	var dy := absf(target.global_position.y - global_position.y)
	# 被贴身时先拉开距离再出手（除非背后没路了）
	var spaced := dist >= keep_min * 0.6 or cornered
	if cooldown <= 0 and spaced and dist <= float(spec.range) and dist >= 160.0 and dy < 300.0 and on_ground() and _attack_slot_free():
		_begin_windup()


func _update_aim() -> void:
	if target == null or not is_instance_valid(target):
		return
	var to: Vector2 = target.global_position - global_position
	if kind == Kind.ARCHER:
		var d := Vector2(to.x, to.y + 10.0)
		if absf(d.x) < 1.0:
			d.x = float(facing)
		var ang := clampf(atan2(d.y, absf(d.x)), -0.45, 0.45)
		aim = Vector2(cos(ang) * signf(d.x), sin(ang))
	else:
		# 影爆：瞄玩家脚下，稍微提前量（玩家在跑就往前丢一点）
		var feet: Vector2 = target.global_position
		if target.get(&"foot_offset") != null:
			feet.y += float(target.get(&"foot_offset"))
		var tv = target.get(&"velocity")
		if tv is Vector2:
			feet.x += (tv as Vector2).x * 0.25
		aim = feet - global_position


func _fire_bolt() -> void:
	var b: Node2D = Bolt.new()
	b.setup(self, global_position + Vector2(float(facing) * (half_w + 18.0), -half_h * 0.35), aim, strike_move, hitstop_multiplier)
	get_parent().add_child(b)
	projectile_spawned.emit(b)


func _throw_bomb() -> void:
	var b: Node2D = Bomb.new()
	var from := global_position + Vector2(float(facing) * 10.0, -half_h - 16.0)
	var land := global_position + aim
	b.setup(self, from, land, strike_move, terrain, floor_y, arena_left, arena_right, hitstop_multiplier)
	get_parent().add_child(b)
	projectile_spawned.emit(b)


func _begin_windup() -> void:
	state = State.WINDUP
	state_frames = 0
	velocity.x = 0.0
	squash = Vector2(0.9, 1.1)
	windup_started.emit(kind == Kind.BRUTE)


func _process_windup(delta: float) -> void:
	_ground_physics(delta)
	velocity.x = move_toward(velocity.x, 0.0, 1400.0 * delta)
	state_frames += 1
	# 前摇前半段还会转身对准玩家，后半段锁定方向（给玩家绕背的机会）
	if target != null and state_frames < int(spec.windup) / 2:
		var dx := target.global_position.x - global_position.x
		if absf(dx) > 6.0:
			facing = 1 if dx > 0.0 else -1
	# 远程影：瞄准一直跟到出手前 8 帧才锁定（瞄准线变亮 = 快射了）
	if is_ranged_kind() and state_frames < int(spec.windup) - 8:
		if target != null and is_instance_valid(target):
			var tdx := target.global_position.x - global_position.x
			if absf(tdx) > 6.0:
				facing = 1 if tdx > 0.0 else -1
		_update_aim()
	if state_frames >= int(spec.windup):
		state = State.STRIKE
		state_frames = 0
		_strike_done = false
		velocity.x = float(facing) * float(spec.lunge)
		squash = Vector2(1.2, 0.86)
		strike_started.emit(kind == Kind.BRUTE)


func _process_strike(delta: float) -> void:
	_ground_physics(delta)
	velocity.x = move_toward(velocity.x, 0.0, 1600.0 * delta)
	state_frames += 1
	if not _strike_done and state_frames >= 2:
		_strike_done = true
		if kind == Kind.ARCHER:
			_fire_bolt()
		elif kind == Kind.BOMBER:
			_throw_bomb()
		else:
			_strike_check()
	if state == State.STRIKE and state_frames >= int(spec.strike):
		state = State.RECOVER
		state_frames = 0


func _strike_check() -> void:
	_friendly_strike()
	if target == null or not is_instance_valid(target) or not target.has_method(&"take_hit"):
		return
	var dx := target.global_position.x - global_position.x
	var dy := target.global_position.y - global_position.y
	if absf(dx) > 2.0 and signf(dx) != float(facing):
		return
	if absf(dx) > float(spec.range) + 24.0 or absf(dy) > 120.0:
		return
	var point := global_position + Vector2(float(facing) * minf(absf(dx), float(spec.range)) * 0.6, -10.0)
	var hp_before: float = float(target.get(&"hp"))
	var blocked: bool = bool(target.call(&"take_hit", strike_move, facing, point, 0.0, false, 1.0, self))
	if not blocked:
		# take_hit also returns false for invulnerability: that is a miss.
		if is_equal_approx(float(target.get(&"hp")), hp_before):
			return
		hitstop_frames = maxi(hitstop_frames, strike_move.hitstop_frames)
		strike_landed.emit(point)
	elif state == State.STRIKE:
		# 被格挡（不是弹刀）：手被震了一下，后摇更长
		state = State.RECOVER
		state_frames = -14
		hitstop_frames = maxi(hitstop_frames, roundi(6 * hitstop_multiplier))
		velocity.x = -float(facing) * 140.0


## 刀是不长眼的：身前刀够得着的同伴也会挨这一刀（打几折）
func _friendly_strike() -> void:
	var hit_any := false
	for o in get_tree().get_nodes_in_group(&"shade"):
		if o == self or o.state == State.DEAD or o.spawn_frames > 0:
			continue
		var dx: float = o.global_position.x - global_position.x
		if absf(dx) < 2.0 or signf(dx) != float(facing):
			continue
		if absf(dx) > float(spec.range) + o.half_w or absf(o.feet_y() - feet_y()) > 50.0:
			continue
		var point: Vector2 = o.global_position + Vector2(-float(facing) * o.half_w * 0.6, -10.0)
		if not o.take_hit(strike_move, facing, point, 0.0, false, FRIENDLY_DAMAGE, self):
			hit_any = true
	if hit_any:
		hitstop_frames = maxi(hitstop_frames, strike_move.hitstop_frames)
		friendly_hit.emit(global_position + Vector2(float(facing) * float(spec.range) * 0.5, -20.0))


func _process_recover(delta: float) -> void:
	_ground_physics(delta)
	velocity.x = move_toward(velocity.x, 0.0, 1200.0 * delta)
	state_frames += 1
	if state_frames >= int(spec.recover):
		state = State.IDLE
		cooldown = _rng.randi_range(int(spec.cool_min), int(spec.cool_max))


func _process_hitstun(delta: float) -> void:
	_ground_physics(delta)
	velocity.x = move_toward(velocity.x, 0.0, 1400.0 * delta)
	state_frames -= 1
	if state_frames <= 0:
		state = State.IDLE
		cooldown = maxi(cooldown, 12)


func _process_stunned(delta: float) -> void:
	_ground_physics(delta)
	velocity.x = move_toward(velocity.x, 0.0, 900.0 * delta)
	stun_frames -= 1
	poise = max_poise * clampf(float(stun_frames) / float(stun_total), 0.0, 1.0)
	if stun_frames <= 0:
		_end_stun()
		state = State.IDLE
		cooldown = 36


func _end_stun() -> void:
	stun_frames = 0
	poise = 0.0
	break_resist = 150


func _process_down(delta: float) -> void:
	_ground_physics(delta)
	velocity.x = move_toward(velocity.x, 0.0, 1000.0 * delta)
	down_frames -= 1
	if down_frames <= 0:
		juggle_count = 0
		chain_level = 0
		_chained.clear()
		if pending_stun > 0:
			_enter_stun(pending_stun)
			pending_stun = 0
		else:
			state = State.IDLE
			cooldown = maxi(cooldown, 20)
			squash = Vector2(0.9, 1.12)


func _ground_physics(delta: float) -> void:
	var gy := ground_y()
	if velocity.y < 0.0 or position.y < gy - 0.5:
		velocity.y += FALL_GRAVITY * delta
		position.y += velocity.y * delta
		gy = ground_y()
		if velocity.y >= 0.0 and position.y >= gy:
			position.y = gy
			velocity.y = 0.0
	else:
		velocity.y = 0.0
		position.y = gy
	position.x += velocity.x * delta
	_clamp_walls(false)


func _clamp_walls(_impact: bool) -> void:
	if position.x - half_w < arena_left:
		position.x = arena_left + half_w
		velocity.x = maxf(velocity.x, 0.0)
	elif position.x + half_w > arena_right:
		position.x = arena_right - half_w
		velocity.x = minf(velocity.x, 0.0)
	var po := _terrain_push()
	_blocked = int(po.y)
	if po.y > 0.0:
		velocity.x = minf(velocity.x, 0.0)
	elif po.y < 0.0:
		velocity.x = maxf(velocity.x, 0.0)


## 石台侧面挡路：推出去并返回 Vector2(新 x, 撞到的一侧)；没有地形 / 没撞返回 y = 0
func _terrain_push() -> Vector2:
	if terrain == null:
		return Vector2(position.x, 0.0)
	var po: Vector2 = terrain.push_out(position.x, half_w, minf(feet_y(), _probe_y))
	position.x = po.x
	return po


## 地面上的影互相推开（不叠成一团，也让“连锁”有东西可撞）；只推同一层的
func _separate() -> void:
	if not on_ground():
		return
	for o in get_tree().get_nodes_in_group(&"shade"):
		if o == self or o.state == State.DEAD or o.state == State.LAUNCHED:
			continue
		if absf(o.position.y + o.half_h - feet_y()) > 20.0:
			continue
		var d: float = position.x - o.position.x
		var need: float = (half_w + o.half_w) * 0.9
		if absf(d) < need:
			var push := (need - absf(d)) * 0.25 * (1.0 if d >= 0.0 else -1.0)
			if absf(d) < 0.01:
				push = 1.0 if get_instance_id() > o.get_instance_id() else -1.0
			position.x += push


# ---------------------------------------------------------------- 浮空 / 方向终结 / 连锁

func _process_launched(delta: float) -> void:
	var g := LAUNCH_GRAVITY * (1.0 + 0.06 * float(mini(juggle_count, JUGGLE_SOFT_CAP)))
	var drag := 220.0
	if driven_frames > 0:
		driven_frames -= 1
		g *= 0.12
		drag = 40.0
	velocity.y += g * delta
	velocity.x = move_toward(velocity.x, 0.0, drag * delta)
	position += velocity * delta
	_wall_check()
	if chain_armed and velocity.length() >= CHAIN_SPEED:
		_chain_check()
	if velocity.y >= 0.0 and position.y >= ground_y():
		position.y = ground_y()
		_floor_impact()


func _wall_check() -> void:
	var side := 0
	if position.x - half_w < arena_left:
		position.x = arena_left + half_w
		side = -1
	elif position.x + half_w > arena_right:
		position.x = arena_right - half_w
		side = 1
	else:
		side = int(_terrain_push().y)   # 撞到石台侧面也算撞墙
	if side == 0:
		return
	var speed := absf(velocity.x)
	if speed >= 300.0 and float(side) * velocity.x > 0.0:
		var dmg := speed * _wall_factor * WALL_DAMAGE_SCALE * (2.0 if driven_frames > 0 or chain_armed else 1.0)
		_apply_damage(dmg)
		wall_slam_count += 1
		flash = 4
		flash_color = Color(1.0, 0.55, 0.3)
		squash = Vector2(0.7, 1.3)
		hitstop_frames = maxi(hitstop_frames, roundi(12 * hitstop_multiplier))
		var point := global_position + Vector2(float(side) * half_w, 0.0)
		wall_slam.emit(speed, dmg, point)
		# 撞墙弹回并往上弹一点：留一个“墙边追打”的窗口
		velocity.x = -velocity.x * 0.32
		velocity.y = minf(velocity.y, -320.0)
		driven_frames = 0
		chain_armed = false
		if hp <= 0.0:
			_die(-side)
	else:
		velocity.x = 0.0


func _floor_impact() -> void:
	if slammed:
		slammed = false
		var strength := clampf(velocity.y / 1400.0, 0.4, 1.4)
		_apply_damage(6.0)
		flash = 4
		flash_color = Color(1.0, 0.85, 0.55)
		squash = Vector2(1.45, 0.6)
		hitstop_frames = maxi(hitstop_frames, roundi(12 * hitstop_multiplier))
		var point := global_position + Vector2(0.0, half_h)
		slam_impact.emit(point, strength)
		_shockwave(point, 230.0)
		# 地面反弹：弹回半空，可以接着打
		velocity = Vector2(velocity.x * 0.25, -620.0)
		chain_armed = false
		if hp <= 0.0:
			_die(facing)
		return
	if velocity.y > 520.0 and bounces < 1:
		bounces += 1
		velocity.y = -velocity.y * 0.32
		velocity.x *= 0.6
		squash = Vector2(1.25, 0.78)
		return
	_enter_down()


func _shockwave(point: Vector2, radius: float) -> void:
	for o in get_tree().get_nodes_in_group(&"shade"):
		if o == self or o.state == State.DEAD:
			continue
		var d: Vector2 = o.global_position - point
		if absf(d.x) < radius and absf(o.position.y + o.half_h - point.y) < 40.0 and o.on_ground():
			o.take_chain(self, Vector2(signf(d.x) * 160.0, -760.0), chain_level + 1, true)


func _chain_check() -> void:
	for o in get_tree().get_nodes_in_group(&"shade"):
		if o == self or o.state == State.DEAD:
			continue
		var id: int = o.get_instance_id()
		if _chained.has(id):
			continue
		var d: Vector2 = o.global_position - global_position
		if absf(d.x) < half_w + o.half_w + 8.0 and absf(d.y) < (half_h + o.half_h) * 0.75:
			_chained[id] = true
			o.take_chain(self, velocity, chain_level + 1, false)
			velocity *= 0.62


## 被别的影撞到（或被下砸冲击波掀起）。
func take_chain(source: Node2D, vel: Vector2, level: int, shock: bool) -> void:
	if state == State.DEAD:
		return
	_chained[source.get_instance_id()] = true
	var dmg := (8.0 if shock else 5.0 + vel.length() * 0.012)
	_apply_damage(dmg)
	_add_poise(30.0)
	flash = 3
	flash_color = Color(1.0, 0.8, 0.45)
	hitstop_frames = maxi(hitstop_frames, roundi(10 * hitstop_multiplier))
	var point := global_position
	damaged.emit(dmg, hp, point)
	chain_hit.emit(level, point)
	if hp <= 0.0:
		_die(int(signf(vel.x)) if absf(vel.x) > 1.0 else facing)
		velocity = Vector2(vel.x * 0.8, minf(-420.0, vel.y * 0.5))
		return
	if bool(spec.armor) and state != State.STUNNED and not shock:
		# 甲影不会被普通的连锁撞飞，只是被撞得一个踉跄
		_flinch(int(signf(vel.x)), 28, absf(vel.x) * 0.25)
		return
	_cancel_stun_into_launch()
	state = State.LAUNCHED
	chain_level = level
	chain_armed = not shock
	bounces = 0
	slammed = false
	driven_frames = 0
	velocity = Vector2(vel.x * 0.78, minf(-380.0, vel.y * 0.55)) if not shock else vel
	juggle_count = maxi(juggle_count, 1)


# ---------------------------------------------------------------- 受击

## 签名必须和 player.gd / dummy.gd 的 take_hit 完全一致（见 dummy.gd 的长注释）。
func take_hit(mv: MoveDefinition, from_facing: int, point: Vector2,
		charge_t: float = 0.0, from_up: bool = false, damage_mul: float = 1.0,
		attacker: Node = null) -> bool:
	if state == State.DEAD:
		return false
	# 翻滚的无敌帧：这一刀整个落空（返回 true = 攻方不算命中、不顿帧、不出命中声）
	var is_ult := mv.id == &"ult"   # 大招：躲不开、挡不住、霸体也扛不住
	if is_dodging() and not is_ult:
		return true
	var intent: StringName = &""
	if attacker != null and attacker.has_method(&"combat_intent"):
		intent = attacker.call(&"combat_intent")
	# 举刀格挡：只挡正面。重招（第三刀 / 蓄力 / 挑飞 / 冲刺斩 / 大招）把刀砸开，这一下照常结算
	if state == State.GUARD and from_facing == -facing:
		if mv.id in GUARD_BREAKERS or charge_t > 0.3:
			state = State.IDLE
			guard_frames = 0
			if not is_ult:          # §16.12：大招不让人晕（只打飞）
				_add_poise(25.0)
			guard_broken.emit(point)
		else:
			_guard_block(mv, from_facing, point, attacker)
			return true
	var stunned := state == State.STUNNED
	var airborne := state == State.LAUNCHED
	combo_taken += 1
	var dmg_mul := 1.0 + (mv.charge_damage_bonus - 1.0) * charge_t
	if airborne:
		juggle_count += 1
	# 连段伤害递增（疯狂小人：连得越长每下越疼；站起来清零）
	dmg_mul *= 1.0 + COMBO_DMG_STEP * float(mini(combo_taken - 1, 10))
	if stunned:
		dmg_mul *= 1.25
	var dealt := mv.damage * dmg_mul * damage_mul
	_wall_factor = mv.wall_damage_factor
	hitstop_frames = maxi(hitstop_frames, mv.victim_hitstop_frames + int(round(mv.charge_hitstop_bonus * charge_t)))
	_apply_damage(dealt)
	last_hit_damage = dealt
	flash = 3
	flash_color = Color.WHITE
	squash = Vector2(mv.squash.x, mv.squash.y).lerp(Vector2.ONE, 0.45)
	damaged.emit(dealt, hp, point)
	if hp <= 0.0:
		_die(from_facing)
		_death_fling(mv, from_facing, from_up, intent)
		return false
	facing = -from_facing
	var launches := mv.forces_launch or from_up
	var km := knock_mul()
	# ---- 浮空中：托住 / 方向终结 ----
	if airborne and not is_ult:
		_juggle(mv, from_facing, from_up, intent)
		return false
	# ---- 甲影霸体：没破防时普通攻击打不断它 ----
	if bool(spec.armor) and not stunned and state != State.DOWN and not is_ult:
		if is_armored():
			armor_flash = 8
			velocity.x += float(from_facing) * 30.0
			return false
		if launches or charge_t > 0.3:
			_flinch(from_facing, 22, minf(mv.knockback * 0.5 * km, 420.0))
		else:
			_flinch(from_facing, 14, minf(mv.knockback * 0.35 * km, 220.0))
		return false
	if state == State.DOWN:
		# 倒地追击：只有挑飞类能把它重新挑起来
		if launches:
			_launch(mv, from_facing, from_up, false, charge_t)
		return false
	if launches:
		_launch(mv, from_facing, from_up, stunned, charge_t)
	elif stunned:
		# 兼容显式硬直状态；普通连击仍按连续命中推力移动。
		velocity.x = float(from_facing) * minf(mv.knockback * BASE_KNOCKBACK_SCALE * km, 760.0)
	else:
		# 格斗游戏式击退：第一下就明显，连续命中逐步增加，挥空不触发。
		_flinch(from_facing, 14 + mv.victim_hitstop_frames, minf(mv.knockback * BASE_KNOCKBACK_SCALE * km, 760.0))
		if on_ground():
			velocity.y = -minf(120.0 * km, 260.0)
	return false


## 举刀挡住：不掉血，防守方停8帧、攻方停6帧。挡多了一样会失衡。
func _guard_block(mv: MoveDefinition, from_facing: int, point: Vector2, attacker: Node) -> void:
	hitstop_frames = maxi(hitstop_frames, roundi(8 * hitstop_multiplier))
	velocity.x = float(from_facing) * minf(120.0 + mv.knockback * 0.25, 260.0)
	flash = 3
	flash_color = Color(0.75, 0.85, 1.0)
	squash = Vector2(0.9, 1.06)
	guard_frames = maxi(guard_frames, 8)
	_add_poise(mv.damage * 0.6)
	if attacker != null and is_instance_valid(attacker) and attacker.get(&"hitstop_frames") != null:
		attacker.set(&"hitstop_frames", maxi(int(attacker.get(&"hitstop_frames")), roundi(6 * hitstop_multiplier)))
	guarded.emit(point)


func _apply_damage(dmg: float) -> void:
	hp -= dmg
	total_damage_taken += dmg
	pct += dmg


func _add_poise(amount: float) -> void:
	# 旧失衡条字段保留以兼容存档/编辑器，但不再参与战斗状态。
	poise = 0.0


func _break() -> void:
	var point := global_position + Vector2(0.0, -half_h - 18.0)
	flash = 6
	flash_color = Color(1.0, 0.86, 0.4)
	squash = Vector2(1.18, 0.84)
	hitstop_frames = maxi(hitstop_frames, roundi(16 * hitstop_multiplier))
	if state == State.LAUNCHED:
		# 空中被打满：落地后再晕
		pending_stun = int(spec.stun)
		poise = max_poise
	else:
		_enter_stun(int(spec.stun))
	broken.emit(point)


func _enter_stun(frames: int) -> void:
	state = State.STUNNED
	stun_frames = frames
	stun_total = maxi(frames, 1)
	poise = max_poise
	velocity.x = 0.0


func _cancel_stun_into_launch() -> void:
	if state == State.STUNNED:
		_end_stun()
	pending_stun = 0


func _flinch(from_facing: int, frames: int, push: float) -> void:
	if state == State.STUNNED:
		velocity.x = float(from_facing) * push * 0.4
		return
	state = State.HITSTUN
	state_frames = frames
	velocity.x = float(from_facing) * push


func _launch(mv: MoveDefinition, from_facing: int, from_up: bool, stunned: bool, charge_t: float) -> void:
	var kb_mul := 1.0 + (mv.charge_knockback_bonus - 1.0) * charge_t
	var v := mv.knockback_velocity(from_facing) * kb_mul
	# 连续命中倍率主要让人横着飞得更远；竖直只加一点（挑飞高度要稳定，空中连段才接得上）
	var km := knock_mul()
	v.x *= km
	if not from_up:
		v.y *= lerpf(1.0, km, 0.35)
	if from_up:
		v.y = minf(v.y, -absf(mv.launch_speed))
		v.x *= 0.45
		# 挑飞要能跳起来追：保证够高（≈ 一段跳的高度）
		v.y = minf(v.y * 1.25, -900.0)
	if stunned:
		v.y *= 1.12
	if (from_up and state != State.LAUNCHED) or stunned:
		# 挑飞（上挑类招式把它打上天）：评价、提示、音效都挂在这个信号上
		launched_high.emit(global_position + Vector2(0.0, -half_h))
	_cancel_stun_into_launch()
	state = State.LAUNCHED
	bounces = 0
	slammed = false
	driven_frames = 0
	juggle_count = maxi(juggle_count, 1)
	# 横向很快的终结（第三刀 / 蓄力 / 冲刺斩）带“连锁”判定
	chain_armed = absf(v.x) >= 300.0
	chain_level = 0
	_chained.clear()
	velocity = v


func _juggle(mv: MoveDefinition, from_facing: int, from_up: bool, intent: StringName) -> void:
	bounces = 0
	match intent:
		&"slam":
			velocity = Vector2(float(from_facing) * 90.0, 1500.0)
			slammed = true
			driven_frames = 0
			chain_armed = false
			hitstop_frames += roundi(5 * hitstop_multiplier)
			return
		&"drive":
			velocity = Vector2(float(from_facing) * 1150.0 * maxf(1.0, knock_mul()), -150.0)
			driven_frames = 18
			chain_armed = true
			chain_level = 0
			_chained.clear()
			hitstop_frames += roundi(5 * hitstop_multiplier)
			return
	if juggle_count > JUGGLE_SOFT_CAP:
		# 衰减到头：不再托起，往下掉（“滑脱”）
		velocity = Vector2(float(from_facing) * 160.0, maxf(velocity.y, 260.0))
		return
	var hover := maxf(110.0, 430.0 - 34.0 * float(juggle_count))
	if from_up or mv.forces_launch:
		hover = maxf(hover, absf(mv.launch_speed) * maxf(0.35, 1.0 - 0.07 * float(juggle_count)))
	if mv.id == &"air_light_3":
		# 空中第三刀不带方向：斜着挑开，可以二段跳追
		velocity = Vector2(float(from_facing) * 420.0, -maxf(hover, 360.0))
		chain_armed = true
		return
	velocity = Vector2(float(from_facing) * (60.0 + mv.knockback * 0.12 * knock_mul()), -hover)


func on_parried(cause: Node = null) -> void:
	if state == State.DEAD:
		return
	var dir := -facing
	if cause != null and is_instance_valid(cause) and cause is Node2D:
		dir = 1 if global_position.x > (cause as Node2D).global_position.x else -1
	flash = 5
	flash_color = Color(0.6, 0.95, 1.0)
	hitstop_frames = maxi(hitstop_frames, roundi(14 * hitstop_multiplier))
	parried.emit(cause, global_position)
	_add_poise(PARRY_POISE)
	if state == State.STUNNED:
		velocity.x = float(dir) * 120.0
		return
	state = State.HITSTUN
	state_frames = 40 if kind == Kind.GRUNT else 34
	velocity.x = float(dir) * 300.0


func _enter_down() -> void:
	state = State.DOWN
	down_frames = int(spec.get("down", 24))
	velocity = Vector2.ZERO
	position.y = ground_y()
	squash = Vector2(1.35, 0.66)
	slammed = false
	chain_armed = false
	driven_frames = 0


# ---------------------------------------------------------------- 死亡

func _die(from_facing: int) -> void:
	if state == State.DEAD:
		return
	hp = 0.0
	state = State.DEAD
	dead_frames = 0
	poise = 0.0
	_hurtbox.set_deferred(&"monitorable", false)
	velocity = Vector2(float(from_facing) * 260.0, -420.0)
	died.emit()


func _death_fling(mv: MoveDefinition, from_facing: int, from_up: bool, intent: StringName) -> void:
	match intent:
		&"slam":
			velocity = Vector2(float(from_facing) * 90.0, 1500.0)
			slammed = true
			return
		&"drive":
			velocity = Vector2(float(from_facing) * 1150.0, -150.0)
			driven_frames = 18
			chain_armed = true
			return
	var v := mv.knockback_velocity(from_facing) * 1.3 * maxf(1.0, knock_mul())
	v.y = minf(v.y, -420.0)
	if from_up:
		v.y = minf(v.y, -900.0)
		v.x *= 0.5
	velocity = v
	chain_armed = absf(v.x) >= 300.0


## 死了也继续飞：尸体照样能撞墙、能连锁（“一刀带走一串”）
func _process_dead(delta: float) -> void:
	if hitstop_frames > 0:
		hitstop_frames -= 1
		return
	dead_frames += 1
	var g := LAUNCH_GRAVITY * (0.12 if driven_frames > 0 else 1.0)
	if driven_frames > 0:
		driven_frames -= 1
	velocity.y += g * delta
	velocity.x = move_toward(velocity.x, 0.0, 200.0 * delta)
	position += velocity * delta
	var dside := 0
	if position.x - half_w < arena_left or position.x + half_w > arena_right:
		dside = -1 if position.x - half_w < arena_left else 1
		position.x = arena_left + half_w if dside < 0 else arena_right - half_w
	else:
		dside = int(_terrain_push().y)
	if dside != 0 and float(dside) * velocity.x > 0.0:
		if absf(velocity.x) > 300.0:
			wall_slam.emit(absf(velocity.x), 0.0, global_position + Vector2(float(dside) * half_w, 0.0))
		velocity.x = -velocity.x * 0.3
	if chain_armed and velocity.length() >= CHAIN_SPEED:
		_chain_check()
	if velocity.y >= 0.0 and position.y >= ground_y():
		position.y = ground_y()
		if slammed:
			slammed = false
			var point := global_position + Vector2(0.0, half_h)
			slam_impact.emit(point, 1.0)
			_shockwave(point, 230.0)
			velocity.y = -380.0
		elif velocity.y > 300.0:
			velocity.y = -velocity.y * 0.3
		else:
			velocity = Vector2(velocity.x * 0.8, 0.0)
	if dead_frames > 70:
		queue_free()


# ---------------------------------------------------------------- 绘制（程序画的影子剑士）

const INK := Color(0.035, 0.043, 0.082)
const INK_SOFT := Color(0.075, 0.09, 0.16)
const RIM := Color(0.48, 0.6, 0.9)
const EYE := Color(1.0, 0.8, 0.45)
const WARN := Color(1.0, 0.54, 0.24)
const GOLD := Color(1.0, 0.86, 0.4)
const LAMP := Color(1.0, 0.66, 0.34)
## 头顶血条 / 失衡条 / 文字 / 预警符号的放大倍数（镜头缩到 0.5 时设 2，保持屏幕上看得清）；
## 轮廓光线宽也跟着加粗一点（细于 1 屏幕像素会断断续续）
var ui_scale: float = 1.0


func _draw() -> void:
	var fade := 1.0
	if state == State.DEAD:
		fade = clampf(1.0 - float(dead_frames - 20) / 50.0, 0.0, 1.0)
	if spawn_frames > 0:
		fade *= 1.0 - float(spawn_frames) / 36.0
	var s := squash
	var t := anim_t
	var f := float(facing)
	var h := half_h
	var w := half_w
	var brute := kind == Kind.BRUTE
	var archer := kind == Kind.ARCHER
	var bomber := kind == Kind.BOMBER
	# 接地影子（随离地高度变淡变小）
	var air := clampf((ground_y() - position.y) / 300.0, 0.0, 1.0)
	_draw_ellipse(Vector2(0, h + 2), Vector2(w * 1.5 * (1.0 - air * 0.5), 6.0), Color(0, 0, 0, 0.45 * fade * (1.0 - air * 0.7)))
	if lamp.x > 0.03:   # 灯笼投影：背向灯笼拉长
		var away := -1.0 if lamp.y > 0.0 else 1.0
		_draw_ellipse(Vector2(away * (w + 22.0 * lamp.x), h + 2), Vector2(w * 1.4 + 30.0 * lamp.x, 4.0), Color(0, 0, 0, 0.25 * lamp.x * fade * (1.0 - air)))
	draw_set_transform(Vector2(0, h), 0.0, s)
	var lean := 0.0
	var tele := telegraph()
	match state:
		State.APPROACH:
			lean = 0.12 * f
		State.WINDUP:
			lean = -0.18 * f * tele
		State.STRIKE:
			lean = 0.3 * f
		State.HITSTUN:
			lean = -0.22 * f
		State.STUNNED:
			lean = sin(t * 5.0) * 0.12
		State.LAUNCHED, State.DEAD:
			lean = -0.5 * f + sin(t * 9.0) * 0.1
		State.DOWN:
			lean = -1.1 * f
		State.GUARD:
			lean = -0.1 * f
		State.ROLL:
			lean = 0.75 * float(roll_dir) + sin(t * 30.0) * 0.08
	var bob := sin(t * 3.2) * 2.0
	var body_h := h * 2.0
	var top := -body_h + bob
	# 斗篷：肩线 + 前后襟 + 飘动的下摆（坐标按朝向归一：x>0 = 前方）
	var hw := w * (1.25 if brute else (1.3 if bomber else 1.1))
	var hem := 7 if not brute else 9
	var moving := 1.0 if state == State.APPROACH or state == State.STRIKE else 0.35
	var trail := (6.0 + 8.0 * moving) + sin(t * 4.0) * 3.0
	var sh_y := top + body_h * 0.22
	var front := PackedVector2Array([
		_fp(-w * 0.32, sh_y - 4.0, f, lean, body_h),
		_fp(w * 0.42, sh_y - 2.0, f, lean, body_h),
		_fp(w * 0.72, sh_y + body_h * 0.07, f, lean, body_h),
		_fp(w * 0.82, top + body_h * 0.55, f, lean, body_h),
		_fp(hw * 0.92, -4.0, f, lean, body_h)])
	var back := PackedVector2Array([
		_fp(-w * 0.62, sh_y + body_h * 0.06, f, lean, body_h),
		_fp(-w * 0.86 - trail * 0.3, top + body_h * 0.5, f, lean, body_h),
		_fp(-hw - trail, -6.0, f, lean, body_h)])
	var pts := front.slice(0, 4)
	for i in hem + 1:
		var u := float(i) / float(hem)
		var x := lerpf(hw * 0.92, -hw - trail, u)
		var y := -2.0 + (sin(t * 6.0 + u * 9.0) * 4.0 if i % 2 == 0 else -10.0 + sin(t * 5.0 + u * 7.0) * 3.0)
		y -= u * u * trail * 0.5
		pts.append(_fp(x, y, f, lean, body_h))
	for i in range(back.size() - 2, -1, -1):
		pts.append(back[i])
	var cloak := INK
	if flash > 0:
		cloak = INK.lerp(Color.WHITE, 0.85) if flash_color == Color.WHITE else INK.lerp(flash_color, 0.7)
	cloak.a = fade
	draw_colored_polygon(pts, cloak)
	var wash := LAMP
	wash.a = 0.16 * lamp.x * fade
	if wash.a > 0.004:
		draw_colored_polygon(pts, wash)   # 灯笼边：斗篷整体透一点暖色
	# 衣褶：两道略亮的竖纹，让斗篷不像一整块剪影
	var fold := INK_SOFT
	fold.a = 0.9 * fade
	for k in 2:
		var fx := w * (0.15 - 0.45 * float(k))
		draw_line(_fp(fx, sh_y + body_h * 0.12, f, lean, body_h), _fp(fx - w * 0.2 - trail * 0.2 * float(k), -12.0, f, lean, body_h), fold, 3.0)
	# 甲影：肩甲 + 胸甲
	if brute:
		var plate := INK_SOFT.lerp(RIM, 0.25)
		if armor_flash > 0 or is_armored():
			plate = plate.lerp(WARN, 0.35 + 0.35 * sin(t * 30.0))
		plate.a = fade
		draw_colored_polygon(PackedVector2Array([_fp(-w * 0.95, top + body_h * 0.2, f, lean, body_h),
			_fp(w * 0.98, top + body_h * 0.2, f, lean, body_h), _fp(w * 0.78, top + body_h * 0.48, f, lean, body_h),
			_fp(-w * 0.72, top + body_h * 0.48, f, lean, body_h)]), plate)
		var seam := INK
		seam.a = fade
		draw_line(_fp(-w * 0.8, top + body_h * 0.34, f, lean, body_h), _fp(w * 0.85, top + body_h * 0.34, f, lean, body_h), seam, 2.0)
	# 头 / 兜帽：尖顶向后拖，前面一块更黑的脸洞
	var head := _lean(Vector2(0, top + body_h * 0.12), lean, body_h)
	var r := w * (0.66 if brute else 0.62)
	var hood_pts := PackedVector2Array([head + Vector2(-f * r * 0.95, -r * 1.55)])
	for i in 11:
		var a := deg_to_rad(lerpf(-100.0, 150.0, float(i) / 10.0))
		hood_pts.append(head + Vector2(cos(a) * r * f, sin(a) * r))
	hood_pts.append(head + Vector2(-f * r * 1.15, -r * 0.25))
	var hood := cloak
	draw_colored_polygon(hood_pts, hood)
	var void_col := Color(0.0, 0.0, 0.01, fade)
	_draw_ellipse(head + Vector2(f * r * 0.32, r * 0.08), Vector2(r * 0.55, r * 0.62), void_col)
	if archer:
		# 影弓：高高的尖兜帽
		draw_colored_polygon(PackedVector2Array([head + Vector2(-f * r * 0.7, -r * 0.6), head + Vector2(-f * r * 1.5, -r * 2.3), head + Vector2(f * r * 0.25, -r * 0.85)]), hood)
	if bomber:
		# 影爆：宽檐斗笠
		draw_colored_polygon(PackedVector2Array([head + Vector2(-r * 1.9, -r * 0.55), head + Vector2(0.0, -r * 1.65), head + Vector2(r * 1.9, -r * 0.55), head + Vector2(0.0, -r * 0.8)]), hood)
		var brim := RIM
		brim.a = 0.45 * fade
		draw_line(head + Vector2(-r * 1.9, -r * 0.55), head + Vector2(r * 1.9, -r * 0.55), brim, 1.5)
	if brute:
		# 角
		draw_colored_polygon(PackedVector2Array([head + Vector2(-r * 0.45, -r * 0.5), head + Vector2(-r * 0.95, -r * 1.55), head + Vector2(-r * 0.05, -r * 0.8)]), hood)
		draw_colored_polygon(PackedVector2Array([head + Vector2(r * 0.45, -r * 0.5), head + Vector2(r * 0.95, -r * 1.55), head + Vector2(r * 0.05, -r * 0.8)]), hood)
	# 月光轮廓：月亮在右上方，所以只描屏幕右侧的边
	var rim := RIM
	rim.a = 0.7 * fade
	var rim_edge := front if f > 0 else back
	var lw := maxf(1.0, ui_scale * 0.8)
	draw_polyline(rim_edge, rim, 2.0 * lw)
	var hood_rim := PackedVector2Array()
	for i in 13:
		var a := deg_to_rad(lerpf(-75.0, 40.0, float(i) / 12.0))
		hood_rim.append(head + Vector2(cos(a) * (r + 0.5), sin(a) * (r + 0.5)))
	draw_polyline(hood_rim, rim, 1.5 * lw)
	# 灯笼暖光：朝灯笼那一侧再描一道暖边
	if lamp.x > 0.02:
		var wc := LAMP
		wc.a = lamp.x * fade
		var side := 1.0 if lamp.y > 0.0 else -1.0
		var warm_edge := front if side * f > 0.0 else back
		var glow := LAMP
		glow.a = 0.28 * lamp.x * fade
		draw_polyline(warm_edge, glow, 7.0 * lw)
		draw_polyline(warm_edge, wc, 3.0 * lw)
		var warm_rim := PackedVector2Array()
		for i in 13:
			var a := deg_to_rad(lerpf(-75.0, 40.0, float(i) / 12.0))
			warm_rim.append(head + Vector2(cos(a) * side * (r + 0.5), sin(a) * (r + 0.5)))
		draw_polyline(warm_rim, wc, 1.5 * lw)
	# 下摆的影雾：几团慢慢上飘的半透明黑烟
	for i in 4:
		var ph := fmod(t * 0.6 + float(i) * 0.27, 1.0)
		var sx := lerpf(hw * 0.7, -hw - trail, fmod(float(i) * 0.37 + 0.1, 1.0))
		var puff := INK_SOFT
		puff.a = 0.42 * (1.0 - ph) * fade
		draw_circle(_fp(sx - ph * 10.0, -4.0 - ph * 26.0, f, 0.0, body_h), 4.0 + ph * 7.0, puff)
	# 眼睛：前摇时变成警示橙并变大
	var eye := EYE.lerp(WARN, tele)
	var eye_r := 2.6 + tele * 2.4
	if state == State.STUNNED:
		eye = Color(0.6, 0.6, 0.7)
		eye_r = 2.0
	eye.a = fade
	var e0 := head + Vector2(f * r * 0.22, -1.0)
	draw_circle(e0, eye_r, eye)
	draw_circle(e0 + Vector2(f * r * 0.42, 0.5), eye_r * 0.85, eye)
	if tele > 0.0:
		var glow := WARN
		glow.a = 0.28 * tele * fade
		draw_circle(e0 + Vector2(f * r * 0.2, 0), 10.0 + tele * 10.0, glow)
	# 手臂（从前肩到握刀手）
	var shoulder := _fp(w * 0.5, sh_y + 4.0, f, lean, body_h)
	var hand := _lean(Vector2(f * w * 0.75, top + body_h * 0.45), lean, body_h)
	if bomber and state == State.WINDUP:
		hand = _lean(Vector2(-f * w * 0.2, top - 6.0 - 10.0 * tele), lean, body_h)   # 把炸弹举过头顶
	elif archer and (state == State.WINDUP or state == State.STRIKE):
		hand = _lean(Vector2(f * w * 1.05, top + body_h * 0.3), lean, body_h)        # 举弓平端
	var arm := cloak
	draw_line(shoulder, hand, arm, 8.0 if brute else 6.0)
	var aim_from := Vector2(0, h) + hand * s     # 解除变形后的手的位置（画瞄准线用）
	if archer:
		_draw_bow(hand, f, tele, fade, lw)
	elif bomber:
		_draw_held_bomb(hand, tele, fade)
		# 腰上还挂着两颗
		for k in 2:
			var bp := _fp(-w * 0.15 + float(k) * w * 0.4, top + body_h * 0.62, f, lean, body_h)
			draw_circle(bp, 6.0, INK_SOFT.lerp(RIM, 0.15) * Color(1, 1, 1, fade))
	else:
		var ang := 0.35
		match state:
			State.WINDUP:
				ang = lerpf(0.35, -2.2, tele)
			State.STRIKE:
				ang = 1.05
			State.RECOVER:
				ang = 0.9
			State.STUNNED:
				ang = 1.4
			State.GUARD:
				ang = -1.45   # 刀竖在身前
		var blade_len := 96.0 if brute else 70.0
		var dir := Vector2(cos(ang) * f, sin(ang))
		if f < 0:
			dir = Vector2(-cos(ang), sin(ang))
		var blade := Color(0.16, 0.18, 0.28).lerp(WARN, tele * 0.6)
		blade.a = fade
		draw_line(hand, hand + dir * blade_len, blade, 6.0 if brute else 4.0)
		var edge := RIM.lerp(WARN, tele)
		edge.a = 0.8 * fade
		draw_line(hand + dir * 8.0, hand + dir * blade_len, edge, 1.5 * lw)
		var guard := Vector2(-dir.y, dir.x) * (9.0 if brute else 7.0)
		draw_line(hand + dir * 6.0 - guard, hand + dir * 6.0 + guard, blade, 3.0)
		# 弹刀时机提示：出刀前 PARRY_CUE 帧，刀尖亮起一颗白星（这时按 L 正好弹开）
		if state == State.WINDUP:
			var remain := int(spec.windup) - state_frames
			if remain <= PARRY_CUE:
				var k := 1.0 - float(remain) / float(PARRY_CUE)
				var tip := hand + dir * blade_len
				var star := Color(1, 1, 1, fade * (0.55 + 0.45 * k))
				_draw_star(tip, 6.0 + 12.0 * k, star)
				draw_circle(tip, 10.0 + 16.0 * k, Color(1.0, 0.95, 0.8, 0.22 * fade))
		# 举刀格挡：身前一道淡蓝的弧（看到它 = 普通刀会被挡，换重招 / 绕背）
		if state == State.GUARD:
			var gc := Color(0.75, 0.85, 1.0, 0.55 * fade)
			var gcen := _fp(w * 0.9, top + body_h * 0.45, f, lean, body_h)
			var a0 := -1.1 if f > 0 else PI - 1.1
			draw_arc(gcen, body_h * 0.42, a0, a0 + 2.2, 14, gc, 3.0)
		# 出刀弧光
		if state == State.STRIKE:
			var arc := WARN
			arc.a = 0.65 * fade * (1.0 - float(state_frames) / float(spec.strike))
			var c := hand
			var a0 := -1.6 if f > 0 else PI + 1.6
			var a1 := 1.1 if f > 0 else PI - 1.1
			draw_arc(c, blade_len * 0.95, minf(a0, a1), maxf(a0, a1), 18, arc, 6.0)
	# 翻滚：身后拖一道影雾
	if state == State.ROLL:
		for i in 4:
			var puff := INK_SOFT
			puff.a = 0.5 * fade * (1.0 - float(i) / 4.0)
			draw_circle(Vector2(-float(roll_dir) * (14.0 + 16.0 * float(i)), -h * 0.6), 12.0 - float(i) * 2.0, puff)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 影弓瞄准线：前摇时从弓指向玩家，最后 8 帧锁定、变亮变粗 = 马上放箭
	if archer and state == State.WINDUP:
		var locked := int(spec.windup) - state_frames <= 8
		var lc := WARN
		lc.a = (0.18 + 0.5 * tele) * fade
		var seg := 26.0
		for i in 22:
			var p0 := aim_from + aim * (float(i) * seg * 1.6)
			draw_line(p0, p0 + aim * seg, lc, (3.5 if locked else 1.5) * lw)
	# 前摇预警：脚下橙色弧 + 头顶“!”
	if tele > 0.0 and state == State.WINDUP:
		var ring := WARN
		ring.a = (0.35 + 0.5 * tele) * fade
		if not is_ranged_kind():
			draw_arc(Vector2(f * float(spec.range) * 0.5, h), float(spec.range) * 0.55, PI + 0.25, TAU - 0.25, 20, ring, 2.0 + tele * 2.0)
		if tele > 0.55:
			draw_set_transform(Vector2(0, -h - 34.0), 0.0, Vector2(ui_scale, ui_scale))
			draw_string(_font, Vector2(-5, 0), "!", HORIZONTAL_ALIGNMENT_CENTER, -1, 26, ring)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 眩晕：头顶转圈的星
	if state == State.STUNNED:
		for i in 3:
			var a := t * 4.0 + float(i) * TAU / 3.0
			var p := Vector2(cos(a) * 20.0 * ui_scale, -h - 22.0 * ui_scale + sin(a) * 6.0 * ui_scale)
			_draw_star(p, 5.0 * ui_scale, GOLD)
	draw_set_transform(Vector2(0, -half_h), 0.0, Vector2(ui_scale, ui_scale))
	_draw_bars(fade)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 影弓的弓：竖着的一道弧 + 弦；拉弓时弦往后拉、搭着一支发光的箭
func _draw_bow(hand: Vector2, f: float, tele: float, fade: float, lw: float) -> void:
	var wood := Color(0.16, 0.18, 0.28).lerp(WARN, tele * 0.4)
	wood.a = fade
	var r := 34.0
	var c := hand + Vector2(-f * 14.0, 0.0)
	var a0 := -1.15 if f > 0 else PI - 1.15
	draw_arc(c, r, a0, a0 + 2.3, 14, wood, 4.0)
	var top := c + Vector2(cos(a0), sin(a0)) * r
	var bot := c + Vector2(cos(a0 + 2.3), sin(a0 + 2.3)) * r
	var pull := hand + Vector2(-f * (8.0 + 18.0 * tele), 0.0)
	var string_col := RIM
	string_col.a = 0.7 * fade
	draw_line(top, pull, string_col, 1.2 * lw)
	draw_line(bot, pull, string_col, 1.2 * lw)
	if state == State.WINDUP:
		var arrow := WARN
		arrow.a = (0.5 + 0.5 * tele) * fade
		draw_line(pull, pull + Vector2(f * 54.0, 0.0), arrow, 3.0)
		draw_circle(pull + Vector2(f * 54.0, 0.0), 4.0 + 4.0 * tele, arrow)


## 影爆手里的炸弹（前摇时举过头顶、引信火星越来越亮）
func _draw_held_bomb(hand: Vector2, tele: float, fade: float) -> void:
	var body := INK.lerp(WARN, 0.2 * tele)
	body.a = fade
	draw_circle(hand + Vector2(0, -8.0), 12.0, body)
	var spark := Color(1.0, 0.95, 0.75, fade * (0.5 + 0.5 * tele))
	draw_line(hand + Vector2(3, -18), hand + Vector2(7, -26), INK * Color(1, 1, 1, fade), 2.5)
	draw_circle(hand + Vector2(7, -26), 2.5 + 3.0 * tele, spark)


func _fp(x: float, y: float, f: float, lean: float, body_h: float) -> Vector2:
	# 朝向归一的点（x>0 = 面朝方向）再做倾斜
	return _lean(Vector2(x * f, y), lean, body_h)


func _lean(p: Vector2, lean: float, body_h: float) -> Vector2:
	# 以脚底为轴倾斜（p 在脚底坐标系，y 向上为负）
	var k := -p.y / body_h
	return Vector2(p.x + lean * body_h * k * 0.6, p.y)


func _draw_ellipse(c: Vector2, r: Vector2, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 20:
		var a := TAU * float(i) / 20.0
		pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	draw_colored_polygon(pts, col)


func _draw_star(c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI / 2.0 + TAU * float(i) / 10.0
		var rr := r if i % 2 == 0 else r * 0.45
		pts.append(c + Vector2(cos(a) * rr, sin(a) * rr))
	draw_colored_polygon(pts, col)


func _draw_bars(fade: float) -> void:
	if state == State.DEAD:
		return
	var w := 88.0 if kind == Kind.BRUTE else (60.0 if kind == Kind.ARCHER else 64.0)
	var y := -16.0 - (16.0 if kind == Kind.BRUTE else (14.0 if kind == Kind.ARCHER else 0.0))   # 相对头顶（调用前已平移到 -half_h 并按 ui_scale 缩放）
	var x := -w / 2.0
	draw_rect(Rect2(x - 1, y - 1, w + 2, 5), Color(0, 0, 0, 0.6 * fade))
	draw_rect(Rect2(x, y, w * clampf(hp / max_hp, 0.0, 1.0), 3), Color(0.92, 0.93, 0.96, fade))
	# 不再显示失衡条/百分比；用连续命中数表达击退递增。
	if combo_taken > 1:
		var combo_col := Color(1.0, 0.78, 0.38, 0.95 * fade)
		draw_string(_font, Vector2(x + w + 5.0, y + 8.0), "连击×%d" % combo_taken, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, combo_col)


func debug_state_name() -> String:
	return State.keys()[state]
