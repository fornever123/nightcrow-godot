extends Node2D
## 截弦 · 台面（世界空间）：地、可站平台、纸门、每折的道具。

const P := preload("res://dsh/scripts/chord_palette.gd")

var act: Dictionary = {}
var ground_y: float = 580.0
var platforms: Array = []
var gate_x: float = 0.0
var gate_open: float = 0.0
var act_index: int = 0
var t: float = 0.0
var rng := RandomNumberGenerator.new()

var _edge: PackedVector2Array = PackedVector2Array()


func setup(a: Dictionary, index: int) -> void:
	act = a
	act_index = index
	ground_y = float(a.get("ground", 580.0))
	platforms = a.get("platforms", [])
	gate_x = float(a.get("right", 800.0)) - 46.0
	rng.seed = 9001 + index * 77
	_edge = PackedVector2Array()
	var x := float(a.get("left", -600.0)) - 260.0
	var right := float(a.get("right", 800.0)) + 260.0
	while x <= right:
		_edge.append(Vector2(x, ground_y + rng.randf_range(-3.0, 3.0)))
		x += 42.0


func _process(delta: float) -> void:
	t += delta
	queue_redraw()


func _draw() -> void:
	if act.is_empty():
		return
	_draw_ground()
	_draw_platforms()
	_draw_props()
	_draw_gate()


func _draw_ground() -> void:
	var left := float(act.get("left", -600.0)) - 260.0
	var right := float(act.get("right", 800.0)) + 260.0
	var poly := PackedVector2Array(_edge)
	poly.append(Vector2(right, ground_y + 420.0))
	poly.append(Vector2(left, ground_y + 420.0))
	draw_colored_polygon(poly, Color(P.INK.r, P.INK.g, P.INK.b, 0.93))
	# 墨积的下沿
	for i in 6:
		var c := P.INK
		c.a = 0.05
		draw_rect(Rect2(left, ground_y + 40.0 + float(i) * 34.0, right - left, 36.0), c)
	# 纸被撕开的白边
	draw_polyline(_edge, P.PAPER_LIGHT, 2.6, true)
	var edge2 := PackedVector2Array()
	for p in _edge:
		edge2.append(p + Vector2(0, 5.0))
	draw_polyline(edge2, Color(0.999, 0.988, 0.965, 0.28), 1.2, true)
	# 地面上很淡的横纹
	for i in 7:
		var y := ground_y + 16.0 + float(i) * 26.0
		draw_line(Vector2(left, y), Vector2(right, y), Color(0.94, 0.92, 0.86, 0.05), 1.0)


func _draw_platforms() -> void:
	for p in platforms:
		var px := float(p.get("x", 0.0))
		var py := float(p.get("y", 460.0))
		var pw := float(p.get("w", 220.0))
		var r := Rect2(px - pw * 0.5, py, pw, 20.0)
		draw_rect(r, P.INK)
		draw_line(Vector2(r.position.x, r.position.y), Vector2(r.end.x, r.position.y), P.PAPER_LIGHT, 2.4, true)
		# 支脚
		draw_line(Vector2(r.position.x + 12.0, r.end.y), Vector2(r.position.x + 6.0, r.end.y + 34.0), P.INK, 3.0)
		draw_line(Vector2(r.end.x - 12.0, r.end.y), Vector2(r.end.x - 6.0, r.end.y + 34.0), P.INK, 3.0)
		# 纸纹
		for i in 5:
			var hx := r.position.x + 18.0 + float(i) * (pw - 36.0) / 4.0
			draw_line(Vector2(hx, r.position.y + 6.0), Vector2(hx + 6.0, r.end.y - 4.0), Color(0.94, 0.92, 0.86, 0.10), 1.0)


func _draw_props() -> void:
	match act_index:
		0:
			_railing()
		1:
			_railing()
			_hanging_lanterns()
		2:
			_stage_drum()
		3:
			_judge_desk()


func _railing() -> void:
	var left := float(act.get("left", -600.0)) + 40.0
	var right := float(act.get("right", 800.0)) - 90.0
	var rail_y := ground_y - 128.0
	var ink := P.INK
	ink.a = 0.42
	var x := left
	while x <= right:
		draw_line(Vector2(x, ground_y - 4.0), Vector2(x, rail_y), Color(P.INK.r, P.INK.g, P.INK.b, 0.30), 3.0)
		draw_circle(Vector2(x, rail_y - 4.0), 4.0, Color(P.INK.r, P.INK.g, P.INK.b, 0.34))
		x += 152.0
	draw_line(Vector2(left, rail_y), Vector2(right, rail_y), ink, 2.4, true)
	draw_line(Vector2(left, rail_y + 26.0), Vector2(right, rail_y + 26.0), ink, 1.4, true)
	# 垂下的纸幡
	for i in 5:
		var fx := left + 120.0 + float(i) * 210.0
		var sway := sin(t * 1.2 + float(i)) * 3.0
		var pts := PackedVector2Array([
			Vector2(fx, rail_y + 2.0), Vector2(fx + 16.0 + sway, rail_y + 2.0),
			Vector2(fx + 12.0 + sway, rail_y + 46.0), Vector2(fx - 4.0 + sway, rail_y + 40.0)])
		draw_colored_polygon(pts, Color(P.INK.r, P.INK.g, P.INK.b, 0.14))


func _hanging_lanterns() -> void:
	var left := float(act.get("left", -600.0))
	for i in 4:
		var x := left + 360.0 + float(i) * 380.0
		var y := 220.0 + sin(t * 0.9 + float(i) * 1.3) * 5.0
		draw_line(Vector2(x, 30.0), Vector2(x, y - 20.0), Color(0.16, 0.14, 0.12, 0.16), 1.0)
		draw_circle(Vector2(x, y), 40.0, Color(P.RED_BRIGHT.r, P.RED_BRIGHT.g, P.RED_BRIGHT.b, 0.07))
		draw_circle(Vector2(x, y), 15.0, Color(P.RED.r, P.RED.g, P.RED.b, 0.22))
		draw_arc(Vector2(x, y), 15.0, 0.0, TAU, 20, Color(P.RED_DEEP.r, P.RED_DEEP.g, P.RED_DEEP.b, 0.30), 1.2, true)


func _stage_drum() -> void:
	var cx := float(act.get("left", -600.0)) + 520.0
	var cy := ground_y - 6.0
	draw_circle(Vector2(cx, cy - 70.0), 96.0, Color(P.INK.r, P.INK.g, P.INK.b, 0.86))
	draw_arc(Vector2(cx, cy - 70.0), 96.0, 0.0, TAU, 48, Color(P.PAPER_LIGHT.r, P.PAPER_LIGHT.g, P.PAPER_LIGHT.b, 0.35), 2.4, true)
	draw_arc(Vector2(cx, cy - 70.0), 74.0, 0.0, TAU, 40, Color(P.PAPER_LIGHT.r, P.PAPER_LIGHT.g, P.PAPER_LIGHT.b, 0.16), 1.2, true)
	for i in 10:
		var a := TAU * float(i) / 10.0
		draw_circle(Vector2(cx + cos(a) * 85.0, cy - 70.0 + sin(a) * 85.0), 3.0, Color(0.94, 0.92, 0.86, 0.28))
	# 鼓架
	draw_line(Vector2(cx - 60.0, cy), Vector2(cx - 40.0, cy - 150.0), P.INK, 8.0)
	draw_line(Vector2(cx + 60.0, cy), Vector2(cx + 40.0, cy - 150.0), P.INK, 8.0)
	# 「鼓」字
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Source Han Serif SC", "Microsoft YaHei", "SimSun"])
	draw_string(f, Vector2(cx - 34, cy - 52), "鼓", HORIZONTAL_ALIGNMENT_LEFT, -1, 46, Color(0.94, 0.92, 0.86, 0.22))


func _judge_desk() -> void:
	var left := float(act.get("left", -600.0))
	var cx := left + 1000.0
	var base := ground_y
	# 判官案
	draw_rect(Rect2(cx - 200.0, base - 96.0, 400.0, 24.0), P.INK)
	draw_rect(Rect2(cx - 200.0, base - 72.0, 22.0, 72.0), P.INK)
	draw_rect(Rect2(cx + 178.0, base - 72.0, 22.0, 72.0), P.INK)
	draw_line(Vector2(cx - 200.0, base - 96.0), Vector2(cx + 200.0, base - 96.0), Color(P.PAPER_LIGHT.r, P.PAPER_LIGHT.g, P.PAPER_LIGHT.b, 0.35), 2.0)
	# 案上的卷宗
	for i in 4:
		var x := cx - 150.0 + float(i) * 78.0
		var h := 26.0 + float((i * 13) % 18)
		draw_rect(Rect2(x, base - 96.0 - h, 46.0, h), Color(P.PAPER_LIGHT.r, P.PAPER_LIGHT.g, P.PAPER_LIGHT.b, 0.55))
		draw_rect(Rect2(x, base - 96.0 - h, 46.0, h), Color(P.INK.r, P.INK.g, P.INK.b, 0.45), false, 1.5)
	# 两条悬卷
	for i in 2:
		var x := cx - 260.0 + float(i) * 520.0
		draw_line(Vector2(x, 0), Vector2(x, 190.0), Color(0.16, 0.14, 0.12, 0.20), 1.4)
		var pts := PackedVector2Array([
			Vector2(x - 26.0, 190.0), Vector2(x + 26.0, 190.0),
			Vector2(x + 30.0, 300.0), Vector2(x - 30.0, 296.0)])
		draw_colored_polygon(pts, Color(P.PAPER_LIGHT.r, P.PAPER_LIGHT.g, P.PAPER_LIGHT.b, 0.52))
		draw_polyline(pts, Color(P.INK.r, P.INK.g, P.INK.b, 0.35), 1.2)


func _draw_gate() -> void:
	if gate_open >= 0.999:
		# 开：两片纸门向外翻折，纸屑落下
		var lean := 66.0
		draw_line(Vector2(gate_x, ground_y), Vector2(gate_x - lean, ground_y - 250.0), Color(P.INK.r, P.INK.g, P.INK.b, 0.35), 10.0)
		draw_line(Vector2(gate_x + 34.0, ground_y), Vector2(gate_x + 34.0 + lean, ground_y - 250.0), Color(P.INK.r, P.INK.g, P.INK.b, 0.35), 10.0)
		return
	var a := 0.75 * (1.0 - gate_open)
	var col := Color(P.INK.r, P.INK.g, P.INK.b, a)
	draw_line(Vector2(gate_x, ground_y), Vector2(gate_x, ground_y - 250.0), col, 10.0)
	draw_line(Vector2(gate_x + 34.0, ground_y), Vector2(gate_x + 34.0, ground_y - 250.0), col, 10.0)
	draw_line(Vector2(gate_x, ground_y - 250.0), Vector2(gate_x + 34.0, ground_y - 250.0), col, 7.0)
	# 门上的符
	var fx := gate_x + 17.0
	var pts := PackedVector2Array([
		Vector2(fx - 15.0, ground_y - 208.0), Vector2(fx + 15.0, ground_y - 208.0),
		Vector2(fx + 12.0, ground_y - 132.0), Vector2(fx - 12.0, ground_y - 136.0)])
	draw_colored_polygon(pts, Color(0.94, 0.92, 0.86, 0.85 * a))
	draw_polyline(pts, Color(P.RED.r, P.RED.g, P.RED.b, 0.7 * a), 1.4)
	# 符上的朱字
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Source Han Serif SC", "Microsoft YaHei", "SimSun"])
	draw_string(f, Vector2(fx - 10.0, ground_y - 152.0), "封", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.545, 0.153, 0.129, 0.8 * a))
