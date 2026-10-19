extends Node2D
## 试玩版敌人「影」：程序绘制的影子剑士（不需要新美术）。
##
## 战斗主题“眩晕连段”的另一半就在这里（设计见 docs/HANDOFF-试玩版.md §7）：
##   打满失衡条 → 眩晕（站着发晕、受伤 +25%）→ 挑飞（眩晕中挑得更高）
##   → 浮空连段（每一下把它托住，但越连托得越低、掉得越快 = 衰减）
##   → 方向终结（S+J 下砸：落地反弹 + 冲击波；前+第三刀：横斩撞墙）
##   → 连锁击飞（高速飞出去的影撞到别的影，把它们一起撞飞）
##
## 物理全部手动积分（地面 floor_y + 多层地形 terrain.gd，封印墙是 arena_left/right），
## 不依赖碰撞体，所以不会出现“贴地时上挑被地面法线挡住”的老问题。
## 多层地形（第三轮节点 17）：脚下的面问 terrain.support_y()，石台侧面问 terrain.push_out()；
## 会跳上平台、从单向平台往下穿去追玩家，只和同一层的人互推、只打同一层的玩家。
## 原点 = 身体中心（和木桩一致：玩家的命中点 = 两者中点）。

const MoveDefinition := preload("res://scripts/core/move_definition.gd")

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

enum Kind { GRUNT, BRUTE }
enum State { IDLE, APPROACH, WINDUP, STRIKE, RECOVER, HITSTUN, LAUNCHED, DOWN, STUNNED, DEAD }

const KINDS := {
	Kind.GRUNT: {"name": "影卒", "hp": 110.0, "poise": 46.0, "half_w": 24.0, "half_h": 60.0, "speed": 135.0,
		"range": 132.0, "windup": 30, "strike": 8, "recover": 38, "damage": 8.0, "knock": 260.0,
		"cool_min": 55, "cool_max": 105, "stun": 150, "armor": false, "lunge": 230.0},
	Kind.BRUTE: {"name": "甲影", "hp": 250.0, "poise": 120.0, "half_w": 36.0, "half_h": 76.0, "speed": 92.0,
		"range": 175.0, "windup": 46, "strike": 10, "recover": 56, "damage": 16.0, "knock": 380.0,
		"cool_min": 80, "cool_max": 140, "stun": 170, "armor": true, "lunge": 160.0},
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

## 每招的失衡值 = 伤害 × 系数（终结类更容易打出失衡）
const POISE_MUL := {&"light_1": 1.3, &"light_2": 1.4, &"light_3": 2.0, &"charge_1": 2.4, &"up_strike": 1.5,
	&"dash_slash": 1.8, &"dash_slash_left": 1.8, &"ranged_1": 0.8, &"air_light_1": 1.0, &"air_light_2": 1.0,
	&"air_light_3": 1.4, &"air_up": 1.0}

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
	strike_move.victim_hitstop_frames = 9 if kind == Kind.GRUNT else 13
	strike_move.hitstop_frames = 6
	strike_move.squash = Vector2(1.25, 0.82)
	strike_move.shake_amount = 6.0 if kind == Kind.GRUNT else 10.0
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
	_update_poise()
	match state:
		State.IDLE, State.APPROACH:
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
	for o in get_tree().get_nodes_in_group(&"shade"):
		if o != self and o.is_attacking():
			n += 1
	return n < max_attackers


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
		_strike_check()
	if state == State.STRIKE and state_frames >= int(spec.strike):
		state = State.RECOVER
		state_frames = 0


func _strike_check() -> void:
	if target == null or not is_instance_valid(target) or not target.has_method(&"take_hit"):
		return
	var dx := target.global_position.x - global_position.x
	var dy := target.global_position.y - global_position.y
	if absf(dx) > 2.0 and signf(dx) != float(facing):
		return
	if absf(dx) > float(spec.range) + 24.0 or absf(dy) > 120.0:
		return
	var point := global_position + Vector2(float(facing) * minf(absf(dx), float(spec.range)) * 0.6, -10.0)
	var blocked: bool = bool(target.call(&"take_hit", strike_move, facing, point, 0.0, false, 1.0, self))
	if not blocked:
		strike_landed.emit(point)
	elif state == State.STRIKE:
		# 被格挡（不是弹刀）：手被震了一下，后摇更长
		state = State.RECOVER
		state_frames = -14
		velocity.x = -float(facing) * 140.0


func _process_recover(delta: float) -> void:
	_ground_physics(delta)
	velocity.x = move_toward(velocity.x, 0.0, 1200.0 * delta)
	state_frames += 1
	if state_frames >= int(spec.recover):
		state = State.IDLE
		cooldown = _rng.randi_range(int(spec.cool_min), int(spec.cool_max))


func _process_hitstun(delta: float) -> void:
	_ground_physics(delta)
	velocity.x = move_toward(velocity.x, 0.0, 1100.0 * delta)
	state_frames -= 1
	if state_frames <= 0:
		state = State.IDLE
		cooldown = maxi(cooldown, 24)


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
			cooldown = maxi(cooldown, 40)
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
		hitstop_frames = 6
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
		hitstop_frames = 5
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
	hitstop_frames = maxi(hitstop_frames, 6)
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
	var intent: StringName = &""
	if attacker != null and attacker.has_method(&"combat_intent"):
		intent = attacker.call(&"combat_intent")
	var stunned := state == State.STUNNED
	var airborne := state == State.LAUNCHED
	var dmg_mul := 1.0 + (mv.charge_damage_bonus - 1.0) * charge_t
	if airborne:
		juggle_count += 1
		dmg_mul *= 1.0 + 0.08 * float(mini(juggle_count, 8))
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
	if not stunned:
		_add_poise(mv.damage * float(POISE_MUL.get(mv.id, 1.2)) * (1.0 + charge_t))
	damaged.emit(dealt, hp, point)
	if hp <= 0.0:
		_die(from_facing)
		_death_fling(mv, from_facing, from_up, intent)
		return false
	if state == State.STUNNED and not stunned:
		# 这一下刚好打满失衡：先让它定在原地发晕（别被同一下打飞，眩晕要读得出来）
		velocity.x = float(from_facing) * 60.0
		return false
	facing = -from_facing
	var launches := mv.forces_launch or from_up
	# ---- 浮空中：托住 / 方向终结 ----
	if airborne:
		_juggle(mv, from_facing, from_up, intent)
		return false
	# ---- 甲影霸体：没破防时普通攻击打不断它 ----
	if bool(spec.armor) and not stunned and state != State.DOWN:
		if is_armored():
			armor_flash = 8
			velocity.x += float(from_facing) * 30.0
			return false
		if launches or charge_t > 0.3:
			_flinch(from_facing, 26, minf(mv.knockback * 0.35, 220.0))
		else:
			_flinch(from_facing, 14, minf(mv.knockback * 0.2, 120.0))
		return false
	if state == State.DOWN:
		# 倒地追击：只有挑飞类能把它重新挑起来
		if launches:
			_launch(mv, from_facing, from_up, false, charge_t)
		return false
	if launches:
		_launch(mv, from_facing, from_up, stunned, charge_t)
	elif stunned:
		# 眩晕中挨普通攻击：不解除眩晕，只被推一点
		velocity.x = float(from_facing) * minf(mv.knockback * 0.25, 90.0)
	else:
		_flinch(from_facing, 16 + mv.victim_hitstop_frames / 2, minf(mv.knockback * 0.55, 260.0))
	return false


func _apply_damage(dmg: float) -> void:
	hp -= dmg
	total_damage_taken += dmg


func _add_poise(amount: float) -> void:
	if state == State.STUNNED or state == State.DEAD:
		return
	poise_idle = 0
	poise += amount * (0.45 if break_resist > 0 else 1.0)
	if poise >= max_poise:
		poise = max_poise
		_break()


func _break() -> void:
	var point := global_position + Vector2(0.0, -half_h - 18.0)
	flash = 6
	flash_color = Color(1.0, 0.86, 0.4)
	squash = Vector2(1.18, 0.84)
	hitstop_frames = maxi(hitstop_frames, 10)
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
	if from_up:
		v.y = minf(v.y, -absf(mv.launch_speed))
		v.x *= 0.45
		# 挑飞要能跳起来追：保证够高（≈ 一段跳的高度）
		v.y = minf(v.y * 1.25, -900.0)
	if stunned:
		v.y *= 1.12
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
			hitstop_frames += 3
			return
		&"drive":
			velocity = Vector2(float(from_facing) * 1150.0, -150.0)
			driven_frames = 18
			chain_armed = true
			chain_level = 0
			_chained.clear()
			hitstop_frames += 3
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
	velocity = Vector2(float(from_facing) * (60.0 + mv.knockback * 0.12), -hover)


func on_parried(cause: Node = null) -> void:
	if state == State.DEAD:
		return
	var dir := -facing
	if cause != null and is_instance_valid(cause) and cause is Node2D:
		dir = 1 if global_position.x > (cause as Node2D).global_position.x else -1
	flash = 5
	flash_color = Color(0.6, 0.95, 1.0)
	hitstop_frames = maxi(hitstop_frames, 8)
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
	down_frames = 46 if kind == Kind.GRUNT else 38
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
	var v := mv.knockback_velocity(from_facing) * 1.3
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
	var bob := sin(t * 3.2) * 2.0
	var body_h := h * 2.0
	var top := -body_h + bob
	# 斗篷：肩线 + 前后襟 + 飘动的下摆（坐标按朝向归一：x>0 = 前方）
	var hw := w * (1.25 if brute else 1.1)
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
	# 刀
	var hand := _lean(Vector2(f * w * 0.75, top + body_h * 0.45), lean, body_h)
	var arm := cloak
	draw_line(shoulder, hand, arm, 6.0 if not brute else 8.0)
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
	var blade_len := 70.0 if not brute else 96.0
	var dir := Vector2(cos(ang) * f, sin(ang))
	if f < 0:
		dir = Vector2(-cos(ang), sin(ang))
	var blade := Color(0.16, 0.18, 0.28).lerp(WARN, tele * 0.6)
	blade.a = fade
	draw_line(hand, hand + dir * blade_len, blade, 4.0 if not brute else 6.0)
	var edge := RIM.lerp(WARN, tele)
	edge.a = 0.8 * fade
	draw_line(hand + dir * 8.0, hand + dir * blade_len, edge, 1.5 * lw)
	var guard := Vector2(-dir.y, dir.x) * (7.0 if not brute else 9.0)
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
	# 出刀弧光
	if state == State.STRIKE:
		var arc := WARN
		arc.a = 0.65 * fade * (1.0 - float(state_frames) / float(spec.strike))
		var c := hand
		var a0 := -1.6 if f > 0 else PI + 1.6
		var a1 := 1.1 if f > 0 else PI - 1.1
		draw_arc(c, blade_len * 0.95, minf(a0, a1), maxf(a0, a1), 18, arc, 6.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 前摇预警：脚下橙色弧 + 头顶“!”
	if tele > 0.0 and state == State.WINDUP:
		var ring := WARN
		ring.a = (0.35 + 0.5 * tele) * fade
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
	var w := 64.0 if kind == Kind.GRUNT else 88.0
	var y := -16.0 - (16.0 if kind == Kind.BRUTE else 0.0)   # 相对头顶（调用前已平移到 -half_h 并按 ui_scale 缩放）
	var x := -w / 2.0
	draw_rect(Rect2(x - 1, y - 1, w + 2, 5), Color(0, 0, 0, 0.6 * fade))
	draw_rect(Rect2(x, y, w * clampf(hp / max_hp, 0.0, 1.0), 3), Color(0.92, 0.93, 0.96, fade))
	# 失衡条：金色，满了闪
	var py := y + 5.0
	draw_rect(Rect2(x - 1, py - 1, w + 2, 5), Color(0, 0, 0, 0.6 * fade))
	var col := GOLD
	if state == State.STUNNED:
		col = GOLD.lerp(Color.WHITE, 0.5 + 0.5 * sin(anim_t * 18.0))
	elif break_resist > 0:
		col = Color(0.7, 0.62, 0.4)
	col.a = fade
	draw_rect(Rect2(x, py, w * clampf(poise / max_poise, 0.0, 1.0), 3), col)
	if kind == Kind.BRUTE:
		draw_string(_font, Vector2(x, y - 4), "霸体" if state != State.STUNNED else "破防", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 0.75, 0.45, 0.85 * fade))


func debug_state_name() -> String:
	return State.keys()[state]
