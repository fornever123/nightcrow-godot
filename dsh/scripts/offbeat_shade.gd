extends Node2D
## 「错拍」敌人：**本体 = 0.6 秒前的它，影身 = 此刻的它**。
##
## 逻辑一直跑在前面（影身 / logic_pos），节点显示的是历史回放（本体 / present_pos）。
## 玩家砍影身 = 真实命中，伤口在本体 0.6 秒后才裂开；玩家要躲的是本体的刀。
##
## 这套「逻辑在前、本体回放」的模型比做预测算法干净：两边永远一致，延迟改成多少都对得上。

enum S { APPROACH, WINDUP, STRIKE, RECOVER, HITSTUN, DEAD }

var kind: String = "grunt"
var data: Dictionary = {}

var logic_pos: Vector2 = Vector2.ZERO
var present_pos: Vector2 = Vector2.ZERO
var facing: int = -1
var max_hp: float = 100.0
var hp: float = 100.0

var state: int = S.APPROACH
var st: float = 0.0
var strike_seq: int = 0
var hitstun_time: float = 0.18
var flicker: float = 0.0

var history: Array = []
var present: Dictionary = {}
var keep_seconds: float = 1.6
var now: float = 0.0
var vel_x: float = 0.0
var spawn_y: float = 580.0
var dead_removed: bool = false
var trial: Node = null

var _hurt_flash: float = 0.0


func setup(cfg: Dictionary, spawn: Vector2, label: String) -> void:
	kind = label
	data = cfg.get("shade", {}).get(kind, cfg.get("shade", {}).get("grunt", {}))
	max_hp = float(data.get("hp", 100.0))
	hp = max_hp
	logic_pos = spawn
	present_pos = spawn
	position = spawn
	spawn_y = spawn.y
	flicker = float(data.get("flicker", 0.0))
	hitstun_time = 0.16 if kind == "grunt" else 0.10
	facing = -1


func _ready() -> void:
	set_process(false)


func logic_hurt_box() -> Rect2:
	var w := float(data.get("bodyWidth", 58.0))
	var h := float(data.get("bodyHeight", 132.0))
	return Rect2(logic_pos + Vector2(-w * 0.5, -h), Vector2(w, h))


func present_height() -> float:
	return float(data.get("bodyHeight", 132.0))


func hp_frac() -> float:
	return clampf(hp / maxf(1.0, max_hp), 0.0, 1.0)


func is_dead() -> bool:
	return state == S.DEAD


func tick(delta: float, player_pos: Vector2, delay: float) -> void:
	now += delta
	st += delta
	_hurt_flash = maxf(0.0, _hurt_flash - delta)
	if state == S.DEAD:
		if st >= 0.75 and not dead_removed:
			dead_removed = true
		_push_history()
		_update_present(delay)
		queue_redraw()
		return

	var dx: float = player_pos.x - logic_pos.x
	var dist: float = absf(dx)
	var toward: int = 1 if dx >= 0.0 else -1

	vel_x = lerpf(vel_x, 0.0, clampf(delta * 8.0, 0.0, 1.0))
	logic_pos.x += vel_x * delta

	match state:
		S.APPROACH:
			if dist > float(data.get("range", 150.0)):
				facing = toward
				logic_pos.x += float(data.get("speed", 168.0)) * toward * delta
				vel_x = float(data.get("speed", 168.0)) * toward * 0.0
			else:
				state = S.WINDUP
				st = 0.0
				facing = toward
		S.WINDUP:
			facing = toward
			if st >= float(data.get("windup", 0.5)):
				state = S.STRIKE
				st = 0.0
				strike_seq += 1
		S.STRIKE:
			if st >= float(data.get("strike", 0.14)):
				state = S.RECOVER
				st = 0.0
		S.RECOVER:
			if st >= float(data.get("recover", 0.42)):
				state = S.APPROACH
				st = 0.0
		S.HITSTUN:
			if st >= hitstun_time:
				state = S.APPROACH
				st = 0.0

	# 贴边的软推：不许叠在一起
	if trial != null:
		for other in trial.shades_alive():
			if other == self:
				continue
			var gap: float = other.logic_pos.x - logic_pos.x
			if absf(gap) < 46.0 and absf(other.logic_pos.y - logic_pos.y) < 60.0:
				logic_pos.x -= signf(gap) * 26.0 * delta * 60.0 * 0.02
	logic_pos.x = clampf(logic_pos.x, -1700.0, 1700.0)

	_push_history()
	_update_present(delay)
	queue_redraw()


func _push_history() -> void:
	history.append({
		"t": now,
		"pos": logic_pos,
		"state": state,
		"st": st,
		"facing": facing,
		"seq": strike_seq,
		"flash": _hurt_flash,
	})
	while history.size() > 3 and now - float(history[0]["t"]) > keep_seconds:
		history.pop_front()


func _update_present(delay: float) -> void:
	present = present_snapshot(delay)
	present_pos = present.get("pos", logic_pos)
	position = present_pos


func present_snapshot(delay: float) -> Dictionary:
	var target := now - delay
	var n := history.size()
	if n == 0:
		return {"pos": logic_pos, "state": state, "st": st, "facing": facing, "seq": strike_seq, "flash": 0.0}
	if target <= float(history[0]["t"]):
		return history[0]
	if target >= float(history[n - 1]["t"]):
		return history[n - 1]
	var lo := 0
	var hi := n - 1
	while lo + 1 < hi:
		var mid := (lo + hi) / 2
		if float(history[mid]["t"]) <= target:
			lo = mid
		else:
			hi = mid
	var a: Dictionary = history[lo]
	var b: Dictionary = history[hi]
	var span := maxf(0.0001, float(b["t"]) - float(a["t"]))
	var k := clampf((target - float(a["t"])) / span, 0.0, 1.0)
	var out := a.duplicate()
	out["pos"] = (a["pos"] as Vector2).lerp(b["pos"] as Vector2, k)
	return out


func take_hit(amount: float, dir: int, from_pos: Vector2) -> void:
	if state == S.DEAD:
		return
	hp -= amount
	_hurt_flash = 1.0
	vel_x = dir * (170.0 if kind == "grunt" else 80.0)
	if hp <= 0.0:
		hp = 0.0
		state = S.DEAD
		st = 0.0
	else:
		state = S.HITSTUN
		st = 0.0


## 本体这一帧有没有挥出一刀（用缓存的本体快照判定，所以和玩家看到的一致）
func present_strike_active() -> bool:
	return int(present.get("state", -1)) == S.STRIKE


func present_attack_box(snap: Dictionary = {}) -> Rect2:
	if snap.is_empty():
		snap = present
	if int(snap.get("state", -1)) != S.STRIKE:
		return Rect2()
	var p: Vector2 = snap.get("pos", present_pos)
	var f: int = int(snap.get("facing", facing))
	var reach := float(data.get("reach", 160.0))
	var h := float(data.get("bodyHeight", 132.0))
	var x := p.x if f > 0 else p.x - reach
	return Rect2(Vector2(x, p.y - h), Vector2(reach, h))


# ---------------------------------------------------------------- 绘制

func _draw() -> void:
	var ghost_off: Vector2 = logic_pos - present_pos
	var t := now

	# 时间线：本体 → 影身
	if ghost_off.length() > 4.0 and state != S.DEAD:
		_draw_timeline(ghost_off, t)

	# 影身（未来）
	if state != S.DEAD:
		_draw_figure(ghost_off + Vector2(0, -6), true, 1.0)

	# 本体（0.6 秒前）
	_draw_figure(Vector2.ZERO, false, 1.0)

	# 血条画在影身头上：玩家打的是「未来」的那一份
	if state != S.DEAD and hp < max_hp:
		var w := 54.0
		var y := -present_height() - 30.0
		var bx := ghost_off.x
		draw_rect(Rect2(bx - w * 0.5, y, w, 3.0), Color(0.05, 0.05, 0.09, 0.85))
		draw_rect(Rect2(bx - w * 0.5, y, w * hp_frac(), 3.0), Color(0.72, 0.24, 0.28, 0.95))


func _draw_timeline(off: Vector2, t: float) -> void:
	var steps := 6
	for i in steps:
		var k0 := float(i) / float(steps)
		var k1 := k0 + 0.5 / float(steps)
		var p0 := Vector2(0, -2).lerp(off + Vector2(0, -8), k0)
		var p1 := Vector2(0, -2).lerp(off + Vector2(0, -8), k1)
		draw_line(p0, p1, Color(0.55, 0.4, 0.95, 0.22), 1.0, true)
	var pulse := fmod(t * 1.6, 1.0)
	var dot := Vector2(0, -2).lerp(off + Vector2(0, -8), pulse)
	draw_circle(dot, 2.2, Color(0.75, 0.62, 1.0, 0.75))
	draw_circle(dot, 4.5, Color(0.65, 0.45, 1.0, 0.16))


func _draw_figure(off: Vector2, ghost: bool, _k: float) -> void:
	var snap: Dictionary
	if ghost:
		snap = {"pos": logic_pos, "state": state, "st": st, "facing": facing, "flash": _hurt_flash}
	else:
		snap = present
		if snap.is_empty():
			snap = {"pos": present_pos, "state": state, "st": st, "facing": facing, "flash": 0.0}
	var pose := int(snap.get("state", state))
	var pt := float(snap.get("st", st))
	var f := int(snap.get("facing", facing))
	var flash := float(snap.get("flash", 0.0))

	var h := float(data.get("bodyHeight", 132.0))
	var w := float(data.get("bodyWidth", 58.0))
	var scale := h / 132.0

	var body_col := Color(0.012, 0.014, 0.035, 0.82)
	var edge_col := Color(0.34, 0.29, 0.52, 0.62)
	var cloth_col := Color(0.02, 0.024, 0.055, 0.85)
	if ghost:
		body_col = Color(0.38, 0.26, 0.82, 0.30)
		cloth_col = Color(0.46, 0.32, 0.92, 0.22)
		edge_col = Color(0.74, 0.58, 1.0, 0.78)
	if flash > 0.0 and not ghost:
		body_col = Color(0.62, 0.58, 0.72, 0.95)

	var o := off
	# 脚下影
	var shadow_w := w * 0.95
	_draw_ellipse(o + Vector2(0, 2), Vector2(shadow_w, 7.0 * scale), Color(0.01, 0.01, 0.03, 0.55 if not ghost else 0.10))
	if ghost:
		# 影身脚下的一圈时相环：本体和它重叠时，也能一眼分出两层
		var rp := 22.0 + 5.0 * sin(now * 3.4)
		draw_arc(o + Vector2(0, 2), rp, 0.0, TAU, 26, Color(0.72, 0.52, 1.0, 0.32), 1.4, true)

	if pose == S.DEAD:
		_draw_dead(o, w, h, body_col, edge_col)
		return

	# 腿
	var lean := 0.0
	if pose == S.WINDUP:
		lean = -6.0 * scale
	elif pose == S.STRIKE:
		lean = 9.0 * scale
	elif pose == S.HITSTUN:
		lean = -10.0 * scale
	var hip := o + Vector2(lean * 0.4, -h * 0.45)
	draw_line(hip + Vector2(-w * 0.16, 0), o + Vector2(-w * 0.24, 0), body_col, 6.0 * scale)
	draw_line(hip + Vector2(w * 0.14, 0), o + Vector2(w * 0.20, 0), body_col, 6.0 * scale)

	# 披风（在身后）
	var cloak := PackedVector2Array([
		o + Vector2(-f * w * 0.30, -h * 0.78),
		o + Vector2(-f * w * 0.95, -h * 0.10),
		o + Vector2(-f * w * 0.55, -h * 0.02),
		o + Vector2(-f * w * 0.10, -h * 0.42),
	])
	draw_colored_polygon(cloak, cloth_col)
	draw_polyline(PackedVector2Array([cloak[0], cloak[1], cloak[2]]), edge_col, 1.2, true)

	# 躯干
	var torso := PackedVector2Array([
		hip + Vector2(-w * 0.30, -h * 0.02),
		hip + Vector2(w * 0.30, -h * 0.02),
		o + Vector2(w * 0.26, -h * 0.80),
		o + Vector2(-w * 0.26, -h * 0.80),
	])
	draw_colored_polygon(torso, body_col)
	draw_polyline(PackedVector2Array([torso[3], torso[2], torso[1]]), edge_col, 1.3, true)

	# 头
	var head := o + Vector2(lean * 0.6, -h * 0.90)
	draw_circle(head, h * 0.085, body_col)
	draw_arc(head, h * 0.085, 0.0, TAU, 18, edge_col, 1.2, true)
	# 一点紫色眼光
	if not ghost:
		draw_circle(head + Vector2(f * h * 0.045, -h * 0.005), 1.8, Color(0.72, 0.45, 1.0, 0.95))

	# 刀与手臂
	var blade_col := Color(0.86, 0.87, 0.96, 1.0) if not ghost else Color(0.78, 0.70, 1.0, 0.5)
	var hand := o + Vector2(f * w * 0.26, -h * 0.62)
	var ang := deg_to_rad(35.0)
	if pose == S.WINDUP:
		var k := clampf(pt / maxf(0.001, float(data.get("windup", 0.5))), 0.0, 1.0)
		ang = deg_to_rad(lerpf(35.0, 165.0, k))
	elif pose == S.STRIKE:
		var k := clampf(pt / maxf(0.001, float(data.get("strike", 0.14))), 0.0, 1.0)
		ang = deg_to_rad(lerpf(165.0, -25.0, k))
	elif pose == S.RECOVER:
		ang = deg_to_rad(-15.0)
	elif pose == S.HITSTUN:
		ang = deg_to_rad(60.0)
	var blade_len := h * 0.78
	var dir := Vector2(cos(ang) * f, -sin(ang))
	var tip := hand + dir * blade_len
	draw_line(hand, tip, Color(0.05, 0.05, 0.08, 1.0), 4.2 * scale)
	draw_line(hand + dir * 6.0, tip, blade_col, 1.8, true)
	if pose == S.STRIKE:
		var arc := PackedVector2Array()
		for i in 9:
			var a2 := deg_to_rad(lerpf(165.0, -25.0, float(i) / 8.0))
			var d2 := Vector2(cos(a2) * f, -sin(a2))
			arc.append(hand + d2 * (blade_len + 26.0))
		draw_polyline(arc, Color(0.92, 0.86, 1.0, 0.55 if not ghost else 0.2), 2.2, true)
	elif pose == S.WINDUP:
		# 刀尖白星：给玩家读招用（画在影身上，因为影身才是未来）
		var star := tip
		var frac := clampf(pt / maxf(0.001, float(data.get("windup", 0.5))), 0.0, 1.0)
		if frac > 0.2:
			draw_circle(star, 3.0 + 4.5 * (frac - 0.2), Color(1.0, 0.98, 0.92, 0.9))
			for i in 4:
				var a3 := TAU * float(i) / 4.0 + pt * 2.0
				draw_line(star, star + Vector2(cos(a3), sin(a3)) * 11.0, Color(1.0, 0.95, 0.85, 0.5), 1.0, true)


func _draw_dead(o: Vector2, w: float, h: float, body: Color, edge: Color) -> void:
	var pts := PackedVector2Array([
		o + Vector2(-w * 0.9, 0),
		o + Vector2(w * 0.15, -h * 0.10),
		o + Vector2(w * 0.95, 0),
		o + Vector2(w * 0.6, 5),
		o + Vector2(-w * 0.6, 5),
	])
	draw_colored_polygon(pts, body)
	draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2]]), edge, 1.2, true)


func _draw_ellipse(c: Vector2, r: Vector2, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 20:
		var a := TAU * float(i) / 20.0
		pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	draw_colored_polygon(pts, col)
