extends Node2D
## 截弦 · 一根弦。
## 敌人出手前甩出的线：前 55% 是松的（砍上去只是挥空），后 45% 绷紧发亮（可截）。
## 截得越晚，收益越高。朱弦永远截不断。

const P := preload("res://dsh/scripts/chord_palette.gd")

var trial: Node = null
var source: Node2D = null
var move_key: String = ""
var art: String = ""
var red: bool = false
var main: bool = true
var decoy: bool = false
var group: int = 0

var kind: String = "spike"
var windup: float = 1.1
var t: float = 0.0
var spawn_t: float = 0.0
var bend: float = 0.0

var start: Vector2 = Vector2.ZERO
var end: Vector2 = Vector2.ZERO
var strike: Rect2 = Rect2()
var origin_fixed: bool = false

var dead: bool = false
var cut_flash: float = 0.0
var taut_at: float = 0.55


func setup(p_trial: Node, p_source: Node2D, p_key: String, p_cfg: Dictionary) -> void:
	trial = p_trial
	source = p_source
	move_key = p_key
	art = String(p_cfg.get("art", ""))
	red = bool(p_cfg.get("red", false))
	main = bool(p_cfg.get("main", true))
	decoy = bool(p_cfg.get("decoy", false))
	group = int(p_cfg.get("group", 0))
	kind = String(p_cfg.get("kind", "spike"))
	windup = maxf(0.18, float(p_cfg.get("windup", 1.0)))
	bend = float(p_cfg.get("bend", 0.0))
	taut_at = 0.55
	start = p_cfg.get("start", Vector2.ZERO)
	end = p_cfg.get("end", Vector2.ZERO)
	strike = p_cfg.get("strike", Rect2())
	origin_fixed = bool(p_cfg.get("origin_fixed", false))
	z_index = 6
	t = 0.0


func tautness() -> float:
	return clampf(t / taut_at, 0.0, 1.0)


func is_taut() -> bool:
	return t >= taut_at


func cuttable() -> bool:
	return not dead and not red and is_taut()


func quality() -> float:
	if not is_taut():
		return 0.0
	return clampf((t - taut_at) / maxf(0.0001, 1.0 - taut_at), 0.0, 1.0)


func tick(delta: float) -> void:
	if dead:
		return
	spawn_t += delta
	if source != null and is_instance_valid(source) and not origin_fixed:
		start = source.chord_origin(kind)
	t += delta / windup
	cut_flash = maxf(0.0, cut_flash - delta * 6.0)
	if t >= 1.0:
		t = 1.0
		if trial != null:
			trial.resolve_thread(self)
	queue_redraw()


func _ctrl() -> Vector2:
	var mid := (start + end) * 0.5
	var dir := (end - start)
	var n := Vector2(-dir.y, dir.x).normalized()
	var sag := bend * (1.0 - tautness())
	if absf(bend) < 0.01:
		sag = 26.0 * (1.0 - tautness()) * signf(dir.x if dir.x != 0.0 else 1.0) * 0.0
	return mid + n * sag


func point_at(u: float) -> Vector2:
	var p0 := start
	var p2 := end
	var p1 := _ctrl()
	var k := clampf(u, 0.0, 1.0)
	var a := p0.lerp(p1, k)
	var b := p1.lerp(p2, k)
	return a.lerp(b, k)


func polyline(samples: int = 16) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in samples + 1:
		pts.append(point_at(float(i) / float(samples)))
	return pts


func _draw() -> void:
	var pts := polyline()
	var hot := is_taut()
	var q := quality()
	var ink := P.INK
	if red:
		ink = P.RED_DEEP
	# 松：一条软塌塌的墨线；绷：外面墨、里面白芯
	if not hot:
		draw_polyline(pts, Color(ink.r, ink.g, ink.b, 0.72), 2.0, true)
		# 松弦上一节一节的粗点
		for i in 4:
			var u := 0.12 + 0.2 * float(i)
			draw_circle(point_at(u), 1.8, Color(ink.r, ink.g, ink.b, 0.5))
	else:
		var width := 3.4 if not red else 4.0
		draw_polyline(pts, Color(ink.r, ink.g, ink.b, 0.95), width, true)
		var core := P.WHITE if not red else Color(1.0, 0.86, 0.80, 1.0)
		core.a = 0.55 + 0.45 * q
		draw_polyline(pts, core, 1.2 + 1.0 * q, true)
		if red:
			# 朱弦：中间一道锯齿的朱线，表示截不断
			var zig := PackedVector2Array()
			for i in pts.size():
				if i % 2 == 0:
					zig.append(pts[i] + Vector2(0, (2.6 if i % 4 == 0 else 0.0) - 1.3))
			if zig.size() > 1:
				draw_polyline(zig, Color(0.98, 0.55, 0.45, 0.75), 1.0, true)
		if q > 0.8:
			# 「绝」窗口：弦上浮出白光
			draw_polyline(pts, Color(1, 0.97, 0.90, 0.18 + 0.25 * sin(spawn_t * 30.0)), 7.0, true)

	# 拍（珠子）
	var bp := point_at(t)
	var bead_r := 3.4 + 2.4 * (1.0 if hot else 0.0)
	if red:
		draw_circle(bp, bead_r + 2.4, Color(P.RED_BRIGHT.r, P.RED_BRIGHT.g, P.RED_BRIGHT.b, 0.20))
		draw_circle(bp, bead_r, P.RED)
		draw_circle(bp, bead_r * 0.45, P.WHITE)
	else:
		draw_circle(bp, bead_r + 2.0, Color(P.INK.r, P.INK.g, P.INK.b, 0.14))
		draw_circle(bp, bead_r, P.INK if not hot else P.WHITE)
		if hot:
			draw_circle(bp, bead_r * 0.42, P.RED if q > 0.8 else P.INK)

	# 剪口：落点上的十字
	var endp := point_at(1.0)
	var sz := 6.0 + 10.0 * t
	var mark := P.INK
	mark.a = 0.30 + 0.55 * t
	if red:
		mark = P.RED
	draw_line(endp + Vector2(-sz, 0), endp + Vector2(-sz * 0.34, 0), mark, 1.6, true)
	draw_line(endp + Vector2(sz * 0.34, 0), endp + Vector2(sz, 0), mark, 1.6, true)
	draw_line(endp + Vector2(0, -sz), endp + Vector2(0, -sz * 0.34), mark, 1.6, true)
	draw_line(endp + Vector2(0, sz * 0.34), endp + Vector2(0, sz), mark, 1.6, true)
	if t > 0.82:
		var pulse := 0.5 + 0.5 * sin(spawn_t * 22.0)
		draw_arc(endp, 16.0 + 6.0 * pulse, 0.0, TAU, 24, Color(mark.r, mark.g, mark.b, 0.25 + 0.35 * pulse), 1.4, true)

	# 落点在地面的投影
	if kind == "spike" or kind == "arc" or kind == "fan":
		var gy: float = 0.0
		if trial != null:
			gy = float(trial.ground_y)
		var gx := endp.x
		draw_line(Vector2(gx, endp.y), Vector2(gx, gy), Color(mark.r, mark.g, mark.b, 0.12 + 0.18 * t), 1.0)
		draw_line(Vector2(gx - 10, gy), Vector2(gx + 10, gy), Color(mark.r, mark.g, mark.b, 0.25 + 0.35 * t), 2.0)

	if cut_flash > 0.0:
		draw_circle(bp, 26.0 * (1.0 - cut_flash), Color(1, 1, 1, cut_flash * 0.6))
