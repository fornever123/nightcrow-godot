extends Node2D
## 截弦 · 主角（纸影戏傀儡，全部代码绘制，不复用原版序列帧）。
## 物理手算；刀锋判定盒既打身体，也是唯一能「截弦」的东西。

const P := preload("res://dsh/scripts/chord_palette.gd")

signal swung(index: int)
signal dashed()
signal jumped(air: bool)
signal landed()
signal hurt(hearts_left: int)
signal died()

enum State { MOVE, ATTACK, DASH, HURT, DEAD }

## 三段斩：判定盒以脚底为原点，朝右为正（朝左时 x 取反）。
const ATK := [
	{"startup": 0.052, "active": 0.078, "recover": 0.118, "box": Rect2(12, -156, 148, 100), "dmg": 5.0, "chain": 0.09},
	{"startup": 0.048, "active": 0.080, "recover": 0.102, "box": Rect2(0, -142, 176, 110), "dmg": 6.0, "chain": 0.09},
	{"startup": 0.072, "active": 0.104, "recover": 0.172, "box": Rect2(-36, -176, 244, 196), "dmg": 9.0, "chain": 0.0},
]

var trial: Node = null
var settings: Dictionary = {}
var pos: Vector2 = Vector2.ZERO
var vel: Vector2 = Vector2.ZERO
var facing: int = 1
var on_floor: bool = true
var air_jumps: int = 1

var state: int = State.MOVE
var state_t: float = 0.0
var atk_index: int = 0
var atk_t: float = 0.0
var atk_queued: bool = false
var swing_id: int = 0
var swing_cut: bool = false

var dash_t: float = 0.0
var dash_cd: float = 0.0
var dash_dir: int = 1

var hearts: int = 5
var max_hearts: int = 5
var invuln: float = 0.0
var shield_t: float = 0.0
var dead: bool = false

var run_phase: float = 0.0
var idle_t: float = 0.0
var lean: float = 0.0
var bob: float = 0.0
var hair_lag: Vector2 = Vector2.ZERO
var coat_sway: float = 0.0
var flash: float = 0.0
var slash_ghost: float = 0.0

var _prev: Dictionary = {}


func setup(cfg: Dictionary, spawn: Vector2) -> void:
	settings = cfg.get("player", {})
	max_hearts = int(settings.get("hearts", 5))
	hearts = max_hearts
	air_jumps = int(settings.get("airJumps", 1))
	pos = spawn
	position = pos
	z_index = 3
	_run_input_pass()
	_prev.clear()


func _cfg(key: String, fallback: float) -> float:
	return float(settings.get(key, fallback))


# ------------------------------------------------------------------ 输入

func _pad(btn: int) -> bool:
	return Input.is_joy_button_pressed(0, btn)


func _axis_x() -> float:
	var v := Input.get_joy_axis(0, JOY_AXIS_LEFT_X)
	if absf(v) < 0.28:
		v = 0.0
	return v


func _down_left() -> bool:
	return Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT) \
		or _pad(JOY_BUTTON_DPAD_LEFT) or _axis_x() < -0.4


func _down_right() -> bool:
	return Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT) \
		or _pad(JOY_BUTTON_DPAD_RIGHT) or _axis_x() > 0.4


func _just_key(key: int) -> bool:
	var now := Input.is_physical_key_pressed(key)
	var was := bool(_prev.get(key, false))
	_prev[key] = now
	return now and not was


func _just_mouse(button: int) -> bool:
	var now := Input.is_mouse_button_pressed(button)
	var key := -button - 50
	var was := bool(_prev.get(key, false))
	_prev[key] = now
	return now and not was


func _just_pad(btn: int) -> bool:
	var now := Input.is_joy_button_pressed(0, btn)
	var key := -btn - 800
	var was := bool(_prev.get(key, false))
	_prev[key] = now
	return now and not was


func _run_input_pass() -> void:
	Input.is_physical_key_pressed(KEY_W)
	Input.is_physical_key_pressed(KEY_SPACE)
	Input.is_physical_key_pressed(KEY_UP)
	Input.is_physical_key_pressed(KEY_J)
	Input.is_physical_key_pressed(KEY_SHIFT)
	Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)


func _jump_just() -> bool:
	return _just_key(KEY_W) or _just_key(KEY_SPACE) or _just_key(KEY_UP) or _just_pad(JOY_BUTTON_A)


func _attack_just() -> bool:
	return _just_key(KEY_J) or _just_mouse(MOUSE_BUTTON_LEFT) or _just_pad(JOY_BUTTON_X)


func _dash_just() -> bool:
	return _just_key(KEY_SHIFT) or _just_mouse(MOUSE_BUTTON_RIGHT) or _just_pad(JOY_BUTTON_B)


# ------------------------------------------------------------------ 主循环

func _physics_process(delta: float) -> void:
	if trial == null:
		return
	_tick_timers(delta)
	if state == State.DEAD:
		_animate(delta)
		return
	if state == State.HURT:
		_tick_physics(delta)
		state_t += delta
		if state_t >= 0.30:
			state = State.MOVE
			state_t = 0.0
		_animate(delta)
		return

	_tick_input(delta)
	_tick_physics(delta)
	_animate(delta)
	if state == State.ATTACK:
		_tick_attack(delta)
	position = pos


func _tick_timers(delta: float) -> void:
	dash_cd = maxf(0.0, dash_cd - delta)
	invuln = maxf(0.0, invuln - delta)
	shield_t = maxf(0.0, shield_t - delta)
	flash = maxf(0.0, flash - delta * 5.0)
	slash_ghost = maxf(0.0, slash_ghost - delta * 3.4)
	idle_t += delta
	state_t += delta


func _tick_input(delta: float) -> void:
	var left := _down_left()
	var right := _down_right()
	var jump := _jump_just()
	var attack := _attack_just()
	var dash := _dash_just()

	if left and not right:
		facing = -1
	elif right and not left:
		facing = 1

	if state == State.DASH:
		if state_t >= dash_t:
			state = State.MOVE
			state_t = 0.0
			vel.x = 0.0
		return

	if jump:
		if on_floor:
			vel.y = -_cfg("jump", 812.0)
			on_floor = false
			emit_signal("jumped", false)
		elif air_jumps > 0:
			air_jumps -= 1
			vel.y = -_cfg("jump", 812.0) * 0.94
			emit_signal("jumped", true)

	if attack:
		if state == State.ATTACK:
			atk_queued = true
		else:
			_start_attack(1)
			return

	if dash and dash_cd <= 0.0 and state != State.ATTACK:
		_start_dash(1 if (right and not left) else (-1 if (left and not right) else facing))
		return


func _start_attack(index: int) -> void:
	state = State.ATTACK
	state_t = 0.0
	atk_index = clampi(index, 1, 3)
	atk_t = 0.0
	atk_queued = false
	swing_id += 1
	swing_cut = false
	slash_ghost = 1.0
	emit_signal("swung", atk_index)


func _start_dash(dir: int) -> void:
	facing = dir
	dash_dir = dir
	state = State.DASH
	state_t = 0.0
	dash_t = _cfg("dashTime", 0.20)
	dash_cd = _cfg("dashCooldown", 0.52)
	invuln = maxf(invuln, 0.19)
	vel.x = float(dir) * _cfg("dashSpeed", 780.0)
	vel.y = 0.0
	emit_signal("dashed")


func _tick_attack(delta: float) -> void:
	var a: Dictionary = ATK[atk_index - 1]
	atk_t += delta
	var start := float(a["startup"])
	var active := float(a["active"])
	var total := start + active + float(a["recover"])
	if atk_t >= start and atk_t < start + active:
		var box := slash_box()
		trial.player_strike(box, float(a["dmg"]), swing_id, self)
	if atk_queued and atk_index < 3 and atk_t >= start + active * 0.4:
		_start_attack(atk_index + 1)
		return
	if atk_t >= total:
		state = State.MOVE
		state_t = 0.0
		atk_queued = false


func _tick_physics(delta: float) -> void:
	var speed := _cfg("speed", 342.0)
	var air_speed := _cfg("airSpeed", 312.0)
	var mx := 0.0
	if state != State.DASH:
		if _down_left() and not _down_right():
			mx = -1.0
		elif _down_right() and not _down_left():
			mx = 1.0

	if state == State.DASH:
		var k := 1.0
		if state_t > dash_t * 0.55:
			k = 0.55
		vel.x = float(dash_dir) * _cfg("dashSpeed", 780.0) * k
		vel.y = 0.0
	else:
		var target := mx * (speed if on_floor else air_speed)
		if state == State.ATTACK:
			target *= 0.34
		if state == State.HURT:
			target = 0.0
		var accel := 16.0 if on_floor else 9.0
		vel.x = lerpf(vel.x, target, clampf(accel * delta, 0.0, 1.0))
		if absf(vel.x) < 2.0:
			vel.x = 0.0
		var g := _cfg("gravity", 2140.0)
		if state == State.ATTACK and not on_floor:
			g *= 0.55
		vel.y += g * delta

	var prev_y := pos.y
	pos += vel * delta

	# 平台（单向）
	var landed_now := false
	if vel.y >= 0.0:
		for pl in trial.platforms:
			var top := float(pl.get("y", 460.0))
			var cx := float(pl.get("x", 0.0))
			var hw := float(pl.get("w", 220.0)) * 0.5
			if pos.x > cx - hw + 6.0 and pos.x < cx + hw - 6.0:
				if prev_y <= top + 2.0 and pos.y >= top:
					pos.y = top
					vel.y = 0.0
					landed_now = true
					break

	var gy: float = float(trial.ground_y)
	if pos.y >= gy:
		pos.y = gy
		vel.y = 0.0
		landed_now = true

	if landed_now and not on_floor:
		emit_signal("landed")
	on_floor = landed_now
	if on_floor:
		air_jumps = int(_cfg("airJumps", 1))

	pos.x = clampf(pos.x, float(trial.bounds_left), float(trial.bounds_right))


func slash_box() -> Rect2:
	var a: Dictionary = ATK[clampi(atk_index, 1, 3) - 1]
	var r: Rect2 = a["box"]
	var x := r.position.x
	if facing < 0:
		x = -r.position.x - r.size.x
	return Rect2(pos + Vector2(x, r.position.y), r.size)


func hurtbox() -> Rect2:
	return Rect2(pos + Vector2(-22, -140), Vector2(44, 140))


func center() -> Vector2:
	return pos + Vector2(0, -82)


func take_hit(from_x: float) -> bool:
	if dead or invuln > 0.0:
		return false
	invuln = _cfg("invuln", 1.15)
	flash = 1.0
	hearts -= 1
	var dir := signf(pos.x - from_x)
	if dir == 0.0:
		dir = -1.0
	vel.x = dir * _cfg("knockback", 220.0)
	vel.y = -180.0
	on_floor = false
	state = State.HURT
	state_t = 0.0
	emit_signal("hurt", hearts)
	if hearts <= 0:
		_die()
	else:
		state = State.HURT
	return true


func _die() -> void:
	dead = true
	hearts = 0
	state = State.DEAD
	state_t = 0.0
	emit_signal("died")


func is_dead() -> bool:
	return dead


func heal(n: int) -> void:
	hearts = clampi(hearts + n, 0, max_hearts)


# ------------------------------------------------------------------ 画

func _animate(delta: float) -> void:
	position = pos
	if state == State.ATTACK:
		lean = lerpf(lean, 0.16 * float(facing), 0.4)
	elif state == State.DASH:
		lean = lerpf(lean, 0.30 * float(facing), 0.5)
	else:
		var speedx := absf(vel.x)
		var target_lean := clampf(speedx / 900.0, 0.0, 1.0) * 0.20 * float(facing)
		lean = lerpf(lean, target_lean, 0.16)
	if on_floor and absf(vel.x) > 20.0:
		run_phase += delta * (7.0 + absf(vel.x) / 120.0)
	elif not on_floor:
		run_phase += delta * 2.0
	else:
		run_phase = lerpf(run_phase, 0.0, 0.1)
	bob = sin(idle_t * 2.2) * 1.6 if on_floor and absf(vel.x) < 20.0 else 0.0
	coat_sway = lerpf(coat_sway, clampf(-vel.x / 620.0, -1.0, 1.0), 0.12)
	hair_lag = hair_lag.lerp(Vector2(clampf(-vel.x / 90.0, -8.0, 8.0), -3.0), 0.10)
	queue_redraw()


func _blade_pose() -> Vector2:
	# 返回刀尖相对手的方向（单位向量），朝右坐标系。
	if state == State.ATTACK:
		var a: Dictionary = ATK[atk_index - 1]
		var start := float(a["startup"])
		var active := float(a["active"])
		var total := start + active + float(a["recover"])
		var k := clampf((atk_t - start) / maxf(0.001, active + float(a["recover"]) * 0.5), 0.0, 1.0)
		var base := -2.15 + 0.35 * float(atk_index)
		var sweep := 2.5
		var ang := base + sweep * ease(k, 0.35)
		return Vector2(cos(ang), sin(ang))
	if state == State.DASH:
		return Vector2(0.55, 0.83)
	if not on_floor:
		return Vector2(0.35, 0.94)
	return Vector2(0.44, 0.90)


func _draw() -> void:
	if dead and state_t > 0.75:
		return
	var f := float(facing)
	var ink := P.INK
	# 落影
	var sh := 1.0 - clampf((pos.y - (float(trial.ground_y) - 200.0)) / 400.0, 0.0, 0.55)
	draw_set_transform(Vector2(0, 0), 0.0, Vector2(1, 1))
	var ground_here := float(trial.ground_y) - pos.y
	draw_colored_polygon(_ellipse(Vector2(0, ground_here), 30.0 * sh, 6.0 * sh), Color(0.09, 0.08, 0.09, 0.18))

	# 闪步残影
	if state == State.DASH:
		for i in 3:
			var off := Vector2(-f * (16.0 + float(i) * 18.0), 0)
			_silhouette(off, 0.10 - float(i) * 0.025)
	# 无敌闪烁
	if invuln > 0.0 and int(invuln * 22.0) % 2 == 0:
		_silhouette(Vector2.ZERO, 0.35)
		return
	_silhouette(Vector2.ZERO, 1.0)
	# 刀
	var hand := _hand_pos()
	var dir := _blade_pose()
	dir.x *= f
	var tip := hand + dir.normalized() * 94.0
	draw_line(hand, tip, Color(P.PURPLE.r, P.PURPLE.g, P.PURPLE.b, 0.16), 11.0, true)
	var blade := PackedVector2Array([
		hand + Vector2(0, -3.2), tip, hand + Vector2(0, 3.2)])
	draw_colored_polygon(blade, P.PURPLE_LIGHT)
	draw_line(hand, tip, P.PURPLE_WHITE, 1.6, true)
	draw_line(hand + Vector2(-f * 5.0, -5.0), hand + Vector2(f * 3.0, 4.0), P.INK, 3.0)
	# 斩击弧
	if state == State.ATTACK:
		_draw_arc_slash(hand)
	# 护罩
	if shield_t > 0.0:
		_draw_shield()
	if flash > 0.0:
		draw_circle(Vector2(0, -70), 56.0, Color(1, 1, 1, flash * 0.35))


func _hand_pos() -> Vector2:
	var f := float(facing)
	var hip := Vector2(0, -58 + bob)
	var shoulder := hip + Vector2(sin(lean) * 44.0, -48.0)
	return shoulder + Vector2(f * 22.0, 16.0)


func _limb(a: Vector2, b: Vector2, width: float, col: Color) -> void:
	draw_line(a, b, col, width, true)


func _ellipse(c: Vector2, rx: float, ry: float, steps: int = 22) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in steps:
		var a := TAU * float(i) / float(steps)
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


func _silhouette(off: Vector2, alpha: float) -> void:
	var f := float(facing)
	var ink := Color(P.INK.r, P.INK.g, P.INK.b, alpha)
	var hip := Vector2(0, -58 + bob) + off
	var shoulder := hip + Vector2(sin(lean) * 44.0, -48.0)
	var head := shoulder + Vector2(sin(lean) * 20.0, -20.0)

	# 腿
	var swing := sin(run_phase) * 26.0
	var lift := maxf(0.0, cos(run_phase)) * 12.0
	var foot_back := Vector2(-8.0 - swing * 0.4, 0) + off
	var foot_front := Vector2(10.0 + swing, -lift) + off
	if not on_floor:
		foot_back = Vector2(-16.0, -14.0) + off
		foot_front = Vector2(18.0, -24.0) + off
	if state == State.DEAD:
		foot_back = Vector2(-24.0, 0) + off
		foot_front = Vector2(20.0, 0) + off
	var knee_back := hip.lerp(foot_back, 0.55) + Vector2(-6.0, 0)
	var knee_front := hip.lerp(foot_front, 0.55) + Vector2(7.0, 0)
	_limb(hip, knee_back, 11.0, ink)
	_limb(knee_back, foot_back, 8.0, ink)
	_limb(hip, knee_front, 12.0, ink)
	_limb(knee_front, foot_front, 8.5, ink)
	# 前腿上一道白刻线
	draw_line(knee_front + Vector2(-2, 0), foot_front + Vector2(-1, 0), Color(0.96, 0.94, 0.88, alpha * 0.28), 1.2, true)

	# 大衣（下摆随速度飘）
	var sway := coat_sway * 16.0
	var coat := PackedVector2Array([
		shoulder + Vector2(-15.0, 4.0),
		shoulder + Vector2(16.0, 2.0),
		hip + Vector2(20.0, 6.0),
		hip + Vector2(15.0 + sway * 0.4, 26.0),
		hip + Vector2(2.0 + sway, 20.0),
		hip + Vector2(-12.0 + sway * 0.7, 24.0),
		hip + Vector2(-20.0, 5.0),
	])
	draw_colored_polygon(coat, ink)
	draw_polyline(PackedVector2Array([
		shoulder + Vector2(-15.0, 4.0), hip + Vector2(-20.0, 5.0), hip + Vector2(-12.0 + sway * 0.7, 24.0)]),
		Color(0.96, 0.94, 0.88, alpha * 0.30), 1.4, true)
	# 躯干
	draw_colored_polygon(PackedVector2Array([
		shoulder + Vector2(-12.0, 2.0), shoulder + Vector2(13.0, 0.0),
		hip + Vector2(9.0, 2.0), hip + Vector2(-9.0, 3.0)]), ink)

	# 后手
	var back_hand := shoulder + Vector2(-f * 16.0, 22.0)
	_limb(shoulder + Vector2(-6.0, 6.0), back_hand, 7.0, ink)
	# 前手
	var front_hand := _hand_pos() + off
	_limb(shoulder + Vector2(6.0, 4.0), front_hand, 7.5, ink)

	# 头
	draw_circle(head, 13.0, ink)
	# 头发（后脑一坨 + 马尾）
	draw_colored_polygon(PackedVector2Array([
		head + Vector2(-14.0, -6.0), head + Vector2(0.0, -15.0), head + Vector2(13.0, -3.0),
		head + Vector2(13.0, 10.0), head + Vector2(2.0, 14.0), head + Vector2(-12.0, 8.0)]), ink)
	var tail_a := head + Vector2(-12.0, 2.0)
	var tail_b := head + Vector2(-30.0 + hair_lag.x, 18.0)
	var tail_c := head + Vector2(-40.0 + hair_lag.x * 1.4, 44.0 + hair_lag.y)
	draw_polyline(PackedVector2Array([tail_a, tail_b, tail_c]), ink, 7.0, true)
	# 脸上一道白色刻线（侧脸）
	draw_line(head + Vector2(f * 4.0, -4.0), head + Vector2(f * 10.0, 3.0), Color(0.96, 0.94, 0.88, alpha * 0.75), 1.6, true)
	# 发梢一点紫（主角唯一的高光）
	draw_circle(tail_c, 2.4, Color(P.PURPLE.r, P.PURPLE.g, P.PURPLE.b, alpha * 0.9))


func _draw_arc_slash(hand: Vector2) -> void:
	var a: Dictionary = ATK[atk_index - 1]
	var start := float(a["startup"])
	var active := float(a["active"])
	var k := clampf((atk_t - start) / maxf(0.001, active), 0.0, 1.0)
	if atk_t < start * 0.6 or atk_t > start + active + 0.04:
		return
	var f := float(facing)
	var base := -2.15 + 0.35 * float(atk_index)
	var ang0 := base + 2.5 * ease(maxf(0.0, k - 0.55), 0.4)
	var ang1 := base + 2.5 * ease(minf(1.0, k + 0.12), 0.4)
	var inner := 54.0
	var outer := 138.0 + 34.0 * float(atk_index)
	var pts_outer := PackedVector2Array()
	var pts_inner := PackedVector2Array()
	var steps := 12
	for i in steps + 1:
		var ang := lerpf(ang0, ang1, float(i) / float(steps))
		var d := Vector2(cos(ang) * f, sin(ang))
		pts_outer.append(hand + d * outer)
		pts_inner.append(hand + d * inner)
	var band := PackedVector2Array(pts_outer)
	for i in range(pts_inner.size() - 1, -1, -1):
		band.append(pts_inner[i])
	var alpha := 0.55 * (1.0 - absf(k - 0.5) * 1.2)
	if alpha > 0.02:
		draw_colored_polygon(band, Color(P.PURPLE_LIGHT.r, P.PURPLE_LIGHT.g, P.PURPLE_LIGHT.b, alpha * 0.5))
		draw_polyline(pts_outer, Color(1, 0.98, 0.94, alpha), 2.2, true)
		draw_polyline(pts_inner, Color(P.PURPLE_WHITE.r, P.PURPLE_WHITE.g, P.PURPLE_WHITE.b, alpha * 0.7), 1.4, true)


func _draw_shield() -> void:
	var a := clampf(shield_t / 2.5, 0.0, 1.0)
	var c := Vector2(0, -74)
	# 纸伞：一圈伞骨
	draw_circle(c, 54.0, Color(P.PURPLE.r, P.PURPLE.g, P.PURPLE.b, 0.10 * a))
	draw_arc(c, 54.0, PI, TAU, 26, Color(P.INK.r, P.INK.g, P.INK.b, 0.55 * a), 2.6, true)
	draw_arc(c, 54.0, 0.0, PI, 26, Color(P.INK.r, P.INK.g, P.INK.b, 0.30 * a), 1.4, true)
	for i in 7:
		var ang := PI + PI * float(i) / 6.0
		draw_line(c, c + Vector2(cos(ang), sin(ang)) * 54.0, Color(P.INK.r, P.INK.g, P.INK.b, 0.40 * a), 1.2, true)
	draw_line(c, Vector2(0, -14), Color(P.INK.r, P.INK.g, P.INK.b, 0.5 * a), 2.0)
