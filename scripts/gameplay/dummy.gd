extends CharacterBody2D
## M0 手感灰盒 · 木桩怪。
##
## 它的唯一职责是**把击退和撞墙二次伤害这条链路完整跑通**：
##   被打中 → hitstop → 抛飞 → 撞墙／撞地 → 二次伤害 → 落地僵直 → 复活
##
## M0 里它不会主动攻击，但受击侧的所有代码路径都是最终版本要用的。

signal damaged(amount: float, total: float, point: Vector2)
signal wall_slam(impact_speed: float, damage: float, point: Vector2)
signal launched_state_changed(is_launched: bool)
signal died()
signal respawned()
## 被弹刀弹开了。**不算受击**：不掉血、不发 damaged、不计入 total_damage_taken，
## 只做后仰 + 短硬直。
signal parried(by: Node, point: Vector2)

## 显式 preload，不依赖 .godot/global_script_class_cache.cfg（纯命令行项目里可能是空的）
const MoveDefinition := preload("res://scripts/core/move_definition.gd")
## 配色表。表现层的东西（闪白/HP 条颜色）都从这里取，别在代码里写死色值。
const Pal := preload("res://scripts/presentation/palette.gd")

enum State { IDLE, HIT, LAUNCHED, DOWN, STUNNED, RESPAWNING }

@export_group("血量")
@export var max_hp: float = 320.0
@export var hp_bar_width: float = 64.0

@export_group("受击")
## 受击顿帧系数：木桩自己比玩家多冻一点，打击感更实
@export var hitstop_scale: float = 1.0
@export var wall_hitstop_frames: int = 12
@export var flash_frames: int = 2
@export var flash_enabled: bool = true
@export var squash_return_speed: float = 0.18

@export_group("击退物理")
@export var wall_restitution: float = 0.30
## 撞墙伤害的全局缩放，必须和 player.gd 的 wall_damage_scale 保持一致
@export var wall_damage_scale: float = 0.15
@export var min_wall_impact_speed: float = 90.0
@export var launch_gravity_scale: float = 1.35
@export var ground_friction: float = 260.0

@export_group("复活")
@export var respawn_delay_frames: int = 100
@export var respawn_shake: float = 6.0

@export_group("弹刀")
## 被招架后对手的后仰硬直帧数。
## **必须明显长于普通被打断** —— "弹到了"的一半正反馈来自"对面停了一下"。
@export var parry_stun_frames: int = 26
## 被招架后推开对手的速度（px/s）。纯横向，向上只给一点点，
## 读起来是"被拨开了"而不是"挨了一拳"。
@export var parry_knockback: float = 300.0

var state: State = State.IDLE
var hp: float = 320.0
var hitstop_frames: int = 0
var down_frames: int = 0
var respawn_counter: int = 0
var active_move: MoveDefinition = null
var last_hit_damage: float = 0.0
var last_wall_damage: float = 0.0
var wall_slam_count: int = 0
var total_damage_taken: float = 0.0
## 浮空连段计数（设计文档 §2.5）。落地归零
var juggle_count: int = 0
var total_juggles: int = 0
## 控制（硬直）剩余帧数
var stun_frames: int = 0
## 落地时要施加的控制时长。受击瞬间记下来，落地时才转成 STUNNED
var pending_stun: int = 0

var _spawn_position: Vector2
var _gravity: float = 1900.0
var _flash_timer: int = 0
var _combat_log: Array[String] = []

@onready var _visual: Node2D = get_node_or_null("Visual")
@onready var _hp_bar: Node2D = get_node_or_null("HpBar")
## 受击白闪覆盖层（和剪影同形的白色色块）。见 dummy.tscn 的 FlashOverlay 注释。
@onready var _flash_overlay: CanvasItem = get_node_or_null("Visual/FlashOverlay")


func _ready() -> void:
	_spawn_position = global_position
	hp = max_hp
	add_to_group(&"dummy")
	_update_hp_bar()
	if _hp_bar != null:
		_hp_bar.visible = true


func _physics_process(delta: float) -> void:
	if _flash_timer > 0:
		_flash_timer -= 1
		if _flash_timer == 0:
			_end_flash()
	elif hitstop_frames == 0:
		_lerp_visual_scale(squash_return_speed)

	# Hitstop：自己数帧
	if hitstop_frames > 0:
		hitstop_frames -= 1
		if state != State.LAUNCHED:
			velocity = Vector2.ZERO
		return

	match state:
		State.IDLE, State.HIT:
			_apply_gravity(delta, _gravity)
			velocity.x = move_toward(velocity.x, 0.0, ground_friction * delta)
			move_and_slide()
			if is_on_floor() and absf(velocity.x) < 4.0:
				state = State.IDLE
		State.LAUNCHED:
			_process_launched(delta)
		State.DOWN:
			_process_down(delta)
		State.STUNNED:
			_process_stunned(delta)
		State.RESPAWNING:
			respawn_counter -= 1
			if respawn_counter <= 0:
				_respawn()


# ---------------------------------------------------------------- 被击

## 玩家在 active 帧调用。
## charge_t   = 蓄力量化 0..1（0 = 没蓄力）
## from_up    = 是不是"向上打"（上挑/空中追击）。向上打会把目标往天上送，
##              并累加浮空倍率，这样才有"把怪挑起来再连一套"的爽感。
## damage_mul = 【外部】受伤倍率，默认 1.0，只缩放伤害、不动击退。
##              三个来源会用到它，都不改招式资源：怪的原型/精英倍率、
##              PVP 全局缩放、突然死亡。
##
## 【为什么这个参数必须和 player.gd 的同名参数一模一样】玩家→怪、怪→玩家、
## 玩家→玩家三种组合共用同一批调用点（player.gd 的 _do_hit_check、
## enemy.gd 的 _resolve_attack）。签名一旦不一致，就打不出伤害，而报错只有一行
## "Invalid call to function 'take_hit' ... Expected N argument(s)"。
## 本项目踩过：PVP 给 player.gd 加了第 6 个参数，enemy.gd / dummy.gd 没跟上，
## 于是"玩家永远打不死怪"，日志里看着像是数值没配。
@warning_ignore("unused_parameter")
func take_hit(mv: MoveDefinition, from_facing: int, point: Vector2,
		charge_t: float = 0.0, from_up: bool = false, damage_mul: float = 1.0,
		attacker: Node = null) -> bool:
	# 【attacker 在本类里用不上】木桩不会招架，也不会被别人弹开。
	# 但这一位【必须占着】：player / dummy / enemy 三个 take_hit 共用同一批
	# 调用点，签名一旦不一致就是"打不出伤害"（见上方那段长注释）。
	# 【为什么返回 bool】true = 被弹开了。木桩永远返回 false，
	# 但返回类型必须和 player.gd 的一致，调用点才能统一处理。
	if state == State.RESPAWNING:
		return false

	# 蓄力加成：伤害/击退/顿帧一起放大
	var dmg_mul := 1.0 + (mv.charge_damage_bonus - 1.0) * charge_t
	var kb_mul := 1.0 + (mv.charge_knockback_bonus - 1.0) * charge_t
	var hs_bonus := int(round(mv.charge_hitstop_bonus * charge_t))

	# 浮空连段倍率（设计文档 §2.5）：空中被再次击中，伤害递增
	if not is_on_floor() or state == State.LAUNCHED:
		juggle_count += 1
		var juggle_mul := 1.0 + 0.2 * float(mini(juggle_count, 4))
		dmg_mul *= juggle_mul

	var dealt := mv.damage * dmg_mul * damage_mul

	hitstop_frames = maxi(hitstop_frames,
			int(round(mv.victim_hitstop_frames * hitstop_scale)) + hs_bonus)
	hp -= dealt
	last_hit_damage = dealt
	total_damage_taken += dealt
	if from_up:
		total_juggles += 1

	# 蓄力 / 上挑 / 浮空连段打得更"炸"：整只白闪闪得更满，读得出来"这一下不一样"
	var heavy := charge_t > 0.35 or from_up or juggle_count > 1
	_start_flash(flash_frames, 0.95 if heavy else 0.55)

	_set_visual_scale(Vector2(mv.squash.x, mv.squash.y))
	damaged.emit(dealt, hp, point)

	if hp <= 0.0:
		_die()
		return false

	active_move = mv
	state = State.LAUNCHED
	# 控制时长（设计文档 §4）：第三段/蓄力会带 stun，落地后转成"站不起来的硬直"
	pending_stun = mv.stun_frames
	stun_frames = mv.stun_frames
	# 向上打：强制把目标往天上送
	var kb := mv.knockback_velocity(from_facing) * kb_mul
	if from_up:
		kb.y = minf(kb.y, -absf(mv.launch_speed))
		kb.x *= 0.55
	velocity = kb
	launched_state_changed.emit(true)
	_push_log("击中 -%.0f%s" % [dealt, " (浮空x%d)" % juggle_count if juggle_count > 1 else ""])
	return false


## 被弹刀弹开。**不是受击**：不掉血、不发 damaged、不计入 total_damage_taken，
## 只做"后仰 + 短硬直"。
##
## 【为什么必须和 take_hit 分成两个入口】复用 take_hit 就得往里塞
## `if no_damage:` 分支 —— 而 take_hit 里已经叠了蓄力 / 浮空 / 撞墙三套倍率，
## 再混一条"不结算伤害"的路径，谁改它都会踩到。分成两个入口之后，
## "弹刀不造成伤害"就从一条需要记住的约定，变成结构上的事实。
##
## cause = 弹开我的那个节点（拿它算后仰方向）。允许为 null。
func on_parried(cause: Node = null) -> void:
	if state == State.RESPAWNING or hp <= 0.0:
		return
	var dir := 1.0
	# 形参类型是 Node（和 take_hit 的 attacker 通道共用），所以要判 Node2D。
	if cause != null and is_instance_valid(cause) and cause is Node2D:
		var d: float = global_position.x - (cause as Node2D).global_position.x
		if absf(d) > 0.5:
			dir = signf(d)
	# 青闪：和"被打中"的白闪、"撞墙"的烫色都不同 ——
	# 一眼读得出"这一下没吃进身体里"。
	_start_flash(3, 0.85, Pal.PLAYER_LIGHT)
	_set_visual_scale(Vector2(0.86, 1.18))
	state = State.STUNNED
	stun_frames = parry_stun_frames
	pending_stun = 0
	active_move = null
	velocity = Vector2(dir * parry_knockback, -120.0)
	parried.emit(cause, global_position)


# ---------------------------------------------------------------- 抛飞

## 核心：自己积分位移 + 撞到东西结算二次伤害（设计文档 §2.1）。
##
## 为什么上升阶段不用 move_and_collide：
## 木桩贴地时引擎会持续报出一个 normal=(0,1) 的"地面"碰撞，把上升直接挡住
## （实测位移被压到 0.0002 px，上挑只能抬 20px 就卡住）。
## 既然击退位移本来就是我们自己积分的，上升段就干脆手动推位置，
## 只在下落/水平段才做真正的碰撞检测 —— 撞墙二次伤害不受影响。
func _process_launched(delta: float) -> void:
	var impact_speed := velocity.length()

	if velocity.y < 0.0:
		# 上升段：忽略碰撞，纯手动积分
		global_position += velocity * delta
		velocity.y += _gravity * launch_gravity_scale * delta
		velocity.x = move_toward(velocity.x, 0.0, 190.0 * delta)
		return

	var col := move_and_collide(velocity * delta)

	if col != null:
		var normal := col.get_normal()
		var impact_pos := global_position + col.get_travel()

		# 【关键】正在【向上飞】时完全忽略碰撞响应。
		#
		# 实测数据：上挑把木桩送上去时，引擎会报一个 normal=(0,1) 的碰撞
		# （朝上的地面法线），即便这一帧位移是 -2.6 px（在上升）。
		# 一旦走下面的"落地"分支，上挑速度就被清成 0 并转入倒地僵直 ——
		# 表现就是"上挑完全挑不起来，只抬 20px 就掉下来"。
		if velocity.y < 0.0:
			velocity.y += _gravity * launch_gravity_scale * delta
			velocity.x = move_toward(velocity.x, 0.0, 190.0 * delta)
			return

		if impact_speed >= min_wall_impact_speed:
			var wall_damage := wall_slam_damage(impact_speed)
			hp -= wall_damage
			last_wall_damage = wall_damage
			total_damage_taken += wall_damage
			wall_slam_count += 1
			hitstop_frames = maxi(hitstop_frames, wall_hitstop_frames)
			# 撞墙 = 烫：闪暖色，和普通命中的白闪区分开
			_start_flash(3, 0.92, Pal.ACCENT_DANGER)
			_set_visual_scale(Vector2(0.7, 1.34))
			wall_slam.emit(impact_speed, wall_damage, impact_pos)
			_push_log("撞墙 -%.0f (%.0f px/s)" % [wall_damage, impact_speed])
			if hp <= 0.0:
				_die()
				return

		if absf(normal.x) > 0.7:
			# 撞侧墙：水平弹回，垂直略损失（贴墙摩擦）
			velocity.x *= -wall_restitution
			velocity.y *= 0.86
		elif normal.y < -0.7:
			# 落地：速度够就弹一次（restitution 0.3），否则进入倒地僵直
			if absf(velocity.y) > 220.0:
				velocity.y = -absf(velocity.y) * wall_restitution
			else:
				velocity.y = 0.0
				_enter_down()
				return
		else:
			velocity = velocity.bounce(normal) * wall_restitution

	velocity.y += _gravity * launch_gravity_scale * delta
	velocity.x = move_toward(velocity.x, 0.0, 190.0 * delta)

	if is_on_floor() and absf(velocity.x) < 12.0:
		_enter_down()


func _wall_factor() -> float:
	if active_move != null:
		return active_move.wall_damage_factor
	return 0.5


## 撞墙二次伤害的唯一公式入口：撞墙速度 × 招式系数 × 全局缩放。
## 低于 min_wall_impact_speed 的撞击直接返回 0 —— 防止贴墙时被反复蹭伤害。
func wall_slam_damage(impact_speed: float) -> float:
	if impact_speed < min_wall_impact_speed:
		return 0.0
	return impact_speed * _wall_factor() * wall_damage_scale


## 落地僵直。stun 是这一刀带的控制帧数（第三段/蓄力会给更长）。
func _enter_down(stun: int = 0) -> void:
	state = State.DOWN
	down_frames = maxi(26, stun)
	velocity = Vector2.ZERO
	# 控制越久压得越扁，读得出来"这次被打得更狠"
	var sq := 1.28 + 0.02 * float(mini(stun, 30))
	_set_visual_scale(Vector2(sq, 0.7))
	launched_state_changed.emit(false)


func _process_down(delta: float) -> void:
	_apply_gravity(delta, _gravity)
	velocity.x = move_toward(velocity.x, 0.0, 900.0 * delta)
	move_and_slide()
	down_frames -= 1
	if down_frames <= 0:
		# 落地 = 浮空连段结束
		juggle_count = 0
		if pending_stun > 0:
			state = State.STUNNED
			stun_frames = pending_stun
			pending_stun = 0
		else:
			state = State.IDLE
			_set_visual_scale(Vector2.ONE)


## 控制状态：站不起来，头上转圈（M0 用黄色闪烁代替）。
func _process_stunned(delta: float) -> void:
	_apply_gravity(delta, _gravity)
	velocity.x = move_toward(velocity.x, 0.0, ground_friction * delta)
	move_and_slide()
	stun_frames -= 1
	# 眩晕闪烁
	if _visual != null:
		var blink := 0.55 + 0.45 * sin(float(stun_frames) * 0.6)
		_visual.modulate = Color(1.0, 0.85 + 0.15 * blink, 0.25 * blink)
	_set_visual_scale(Vector2(1.12, 0.9))
	if stun_frames <= 0:
		state = State.IDLE
		stun_frames = 0
		if _visual != null:
			_visual.modulate = Color.WHITE
		_set_visual_scale(Vector2.ONE)
	if is_on_floor():
		velocity.y = 0.0


# ---------------------------------------------------------------- 死亡 / 复活

func _die() -> void:
	state = State.RESPAWNING
	respawn_counter = respawn_delay_frames
	velocity = Vector2.ZERO
	hp = 0.0
	_update_hp_bar()
	_set_visual_scale(Vector2(1.4, 0.45))
	_end_flash()
	if _visual != null:
		_visual.modulate = Color(0.35, 0.35, 0.4)
	stun_frames = 0
	pending_stun = 0
	died.emit()
	_push_log("木桩倒下 · 撞墙 %d 次" % wall_slam_count)


func _respawn() -> void:
	global_position = _spawn_position
	velocity = Vector2.ZERO
	hp = max_hp
	state = State.IDLE
	hitstop_frames = 0
	active_move = null
	wall_slam_count = 0
	total_damage_taken = 0.0
	last_wall_damage = 0.0
	last_hit_damage = 0.0
	juggle_count = 0
	total_juggles = 0
	stun_frames = 0
	pending_stun = 0
	_combat_log.clear()
	_end_flash()
	if _visual != null:
		_visual.modulate = Color.WHITE
	_set_visual_scale(Vector2(1.3, 0.7))
	_update_hp_bar()
	respawned.emit()


func reset_state() -> void:
	_respawn()


func heal_full() -> void:
	hp = max_hp
	_update_hp_bar()


# ---------------------------------------------------------------- 表现

func _update_hp_bar() -> void:
	if _hp_bar == null:
		return
	var ratio := clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0)
	var fill := _hp_bar.get_node_or_null("Fill") as ColorRect
	if fill != null:
		fill.size = Vector2(hp_bar_width * ratio, 6.0)
		# V3 的调色板里没有绿色。HP 三档改成 白 → 琥珀 → 橙红，
		# 和木桩自己的琥珀身份色同一族，也和"撞墙烫伤"的暖色呼应。
		fill.color = Pal.HP_HIGH if ratio > 0.5 else (
			Pal.HP_MID if ratio > 0.22 else Pal.HP_LOW)


## 受击闪白。**为什么不用 modulate**：
## modulate 是【相乘】，只能压暗、永远提亮不了 —— 灰盒时期角色是黑剪影时，
## `modulate = Color(1, .35, .35)` 会把白闪静默吃掉（乘完还是黑）。
## V3 的做法是另挂一层和剪影同形的白色覆盖层（Visual/FlashOverlay），
## 受击瞬间整只变白；`alpha` 决定"闪多满"，`color` 用来区分撞墙的烫色。
##
## 【别改 _flash_timer 的帧数】它同时兼着"这几帧不做 squash 回弹"的作用
## （见 _physics_process），动帧数会连带改打击手感。
func _start_flash(frames: int, alpha: float, color: Color = Color.WHITE) -> void:
	if not flash_enabled:
		return
	_flash_timer = frames
	if _flash_overlay != null:
		_flash_overlay.visible = true
		_flash_overlay.modulate = Color(color.r, color.g, color.b, alpha)


func _end_flash() -> void:
	if _flash_overlay != null:
		_flash_overlay.visible = false


func _set_visual_scale(s: Vector2) -> void:
	if _visual != null:
		_visual.scale = s


func _lerp_visual_scale(t: float) -> void:
	if _visual != null:
		_visual.scale = _visual.scale.lerp(Vector2.ONE, clampf(t, 0.0, 1.0))


func _apply_gravity(delta: float, g: float) -> void:
	# 注意：不要用 is_on_floor() 提前 return —— 被上挑的瞬间角色还"贴着地面"，
	# 那时 is_on_floor() 仍是 true，会把刚给的向上速度当场清零，人根本飞不起来。
	# 只有"正在下落(v.y>0)且贴地"才归零。
	if is_on_floor() and velocity.y > 0.0:
		velocity.y = 0.0
		return
	velocity.y += g * delta
	velocity.y = minf(velocity.y, 2400.0)


func _push_log(line: String) -> void:
	_combat_log.append(line)
	while _combat_log.size() > 3:
		_combat_log.pop_front()


func combat_log() -> String:
	return " | ".join(_combat_log)


func hp_ratio() -> float:
	return clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0)


func debug_state_name() -> String:
	match state:
		State.IDLE: return "IDLE"
		State.HIT: return "HIT"
		State.LAUNCHED: return "LAUNCHED"
		State.DOWN: return "DOWN"
		State.STUNNED: return "STUNNED(%d)" % stun_frames
		State.RESPAWNING: return "RESPAWN"
	return "?"


func is_being_launched() -> bool:
	return state == State.LAUNCHED
