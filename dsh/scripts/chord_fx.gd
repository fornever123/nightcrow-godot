extends Node2D
## 截弦 · 墨与纸（世界空间特效）：断弦、墨溅、纸屑、印章、纸刺、斩弧。

const P := preload("res://dsh/scripts/chord_palette.gd")

var parts: Array = []
var _font: SystemFont
var _seal: SystemFont


func _ready() -> void:
	z_index = 9
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Source Han Serif SC", "Microsoft YaHei", "SimSun"])
	_seal = SystemFont.new()
	_seal.font_names = PackedStringArray(["Source Han Serif SC", "Microsoft YaHei", "SimSun"])
	_seal.font_weight = 800


func _process(delta: float) -> void:
	var keep: Array = []
	for p in parts:
		p["t"] = float(p["t"]) + delta
		if float(p["t"]) < float(p["life"]):
			keep.append(p)
	parts = keep
	queue_redraw()


func clear_all() -> void:
	parts.clear()


# ------------------------------------------------------------------ 生成

func stamp(pos: Vector2, text: String, col: Color = P.RED, size: int = 34, life: float = 0.9) -> void:
	parts.append({"k": "stamp", "pos": pos, "text": text, "col": col, "size": size, "life": life, "t": 0.0})


func ink(pos: Vector2, col: Color = P.INK, power: float = 1.0, count: int = 8, life: float = 0.55) -> void:
	for i in count:
		var ang := randf() * TAU
		var sp := randf_range(40.0, 210.0) * power
		parts.append({
			"k": "blob", "pos": pos, "vel": Vector2(cos(ang), sin(ang)) * sp - Vector2(0, 120.0),
			"r": randf_range(2.0, 7.0) * power, "col": col, "life": life * randf_range(0.7, 1.3),
			"t": 0.0, "spin": randf_range(-3.0, 3.0),
		})


func scraps(pos: Vector2, count: int = 10, power: float = 1.0) -> void:
	for i in count:
		var ang := randf_range(-PI * 0.95, -PI * 0.05)
		var sp := randf_range(70.0, 260.0) * power
		parts.append({
			"k": "scrap", "pos": pos, "vel": Vector2(cos(ang), sin(ang)) * sp,
			"w": randf_range(3.0, 9.0), "h": randf_range(2.0, 5.0),
			"rot": randf() * TAU, "spin": randf_range(-8.0, 8.0),
			"col": P.INK, "life": randf_range(0.8, 1.6), "t": 0.0,
		})


func ring(pos: Vector2, radius: float, col: Color = P.INK, life: float = 0.4, width: float = 2.0) -> void:
	parts.append({"k": "ring", "pos": pos, "r": radius, "col": col, "life": life, "t": 0.0, "w": width})


func end_curl(from: Vector2, to: Vector2, cut_point: Vector2, col: Color = P.INK) -> void:
	parts.append({"k": "end", "a": from, "b": to, "c": cut_point, "col": col, "life": 0.9, "t": 0.0})


func spike(pos: Vector2, height: float, col: Color = P.INK) -> void:
	parts.append({"k": "spike", "pos": pos, "h": height, "col": col, "life": 0.45, "t": 0.0})


func slash(pos: Vector2, facing: int, radius: float = 140.0, col: Color = P.PURPLE_LIGHT) -> void:
	parts.append({"k": "slash", "pos": pos, "f": facing, "r": radius, "col": col, "life": 0.20, "t": 0.0})


func wave(pos: Vector2, facing: int, reach: float, col: Color = P.INK) -> void:
	parts.append({"k": "wave", "pos": pos, "f": facing, "reach": reach, "col": col, "life": 0.38, "t": 0.0})


func seal(pos: Vector2, text: String, size: int = 96, life: float = 1.1) -> void:
	parts.append({"k": "seal", "pos": pos, "text": text, "size": size, "life": life, "t": 0.0})


func cut_burst(pos: Vector2, from: Vector2, to: Vector2, quality: float, red: bool, label: String) -> void:
	var col := P.RED if red else P.INK
	end_curl(from, pos, pos, col)
	end_curl(to, pos, pos, col)
	ink(pos, col, 1.0 + quality, 10, 0.6)
	ring(pos, 46.0 + 30.0 * quality, col, 0.35, 2.0)
	if not red:
		scraps(pos, 5 + int(quality * 6.0), 0.8)
	stamp(pos + Vector2(0, -34), label, P.RED if quality > 0.72 and not red else P.INK, 30 + int(quality * 10.0), 0.85)


# ------------------------------------------------------------------ 绘制

func _draw() -> void:
	for p in parts:
		var k := float(p["t"]) / maxf(0.001, float(p["life"]))
		match String(p["k"]):
			"blob":
				_draw_blob(p, k)
			"scrap":
				_draw_scrap(p, k)
			"ring":
				_draw_ring(p, k)
			"end":
				_draw_end(p, k)
			"spike":
				_draw_spike(p, k)
			"slash":
				_draw_slash(p, k)
			"wave":
				_draw_wave(p, k)
			"stamp":
				_draw_stamp(p, k)
			"seal":
				_draw_seal(p, k)


func _draw_blob(p: Dictionary, k: float) -> void:
	var pos: Vector2 = p["pos"] + p["vel"] * float(p["t"])
	pos.y += 520.0 * float(p["t"]) * float(p["t"])
	var col: Color = p["col"]
	col.a = (1.0 - k) * 0.85
	var r := float(p["r"]) * (1.0 - k * 0.35)
	var pts := PackedVector2Array()
	var n := 7
	for i in n:
		var a := TAU * float(i) / float(n) + float(p["spin"]) * float(p["t"])
		var rr := r * (0.7 + 0.3 * sin(float(i) * 2.3 + float(p["spin"])))
		pts.append(pos + Vector2(cos(a), sin(a)) * rr)
	if pts.size() >= 3:
		draw_colored_polygon(pts, col)


func _draw_scrap(p: Dictionary, k: float) -> void:
	var pos: Vector2 = p["pos"] + p["vel"] * float(p["t"])
	pos.y += 900.0 * float(p["t"]) * float(p["t"]) * 0.5
	var col: Color = p["col"]
	col.a = (1.0 - k) * 0.9
	var rot := float(p["rot"]) + float(p["spin"]) * float(p["t"])
	var w := float(p["w"])
	var h := float(p["h"])
	var pts := PackedVector2Array()
	var corners := [Vector2(-w, -h), Vector2(w, -h * 0.4), Vector2(w * 0.7, h), Vector2(-w * 0.8, h * 0.7)]
	for c in corners:
		pts.append(pos + c.rotated(rot))
	draw_colored_polygon(pts, col)


func _draw_ring(p: Dictionary, k: float) -> void:
	var col: Color = p["col"]
	col.a = (1.0 - k) * 0.55
	draw_arc(p["pos"], float(p["r"]) * (0.3 + k * 1.2), 0.0, TAU, 30, col, float(p["w"]) * (1.0 - k * 0.5), true)


func _draw_end(p: Dictionary, k: float) -> void:
	var a: Vector2 = p["a"]
	var c: Vector2 = p["c"]
	var dir := (c - a)
	var len := dir.length()
	if len < 1.0:
		return
	var n := dir / len
	var perp := Vector2(-n.y, n.x)
	# 断掉的一截慢慢垂下来、卷起来
	var fall := k * (24.0 + len * 0.10)
	var pts := PackedVector2Array()
	var steps := 6
	for i in steps + 1:
		var u := float(i) / float(steps)
		var base := a.lerp(c, u)
		var curl := sin(u * PI) * k * 10.0
		base += perp * curl + Vector2(0, fall * u * u)
		pts.append(base)
	var col: Color = p["col"]
	col.a = (1.0 - k) * 0.8
	draw_polyline(pts, col, 2.4, true)
	# 末梢一小片纸
	if pts.size() > 0:
		var tip: Vector2 = pts[pts.size() - 1]
		draw_circle(tip, 2.0 * (1.0 - k * 0.6), Color(col.r, col.g, col.b, col.a))


func _draw_spike(p: Dictionary, k: float) -> void:
	var pos: Vector2 = p["pos"]
	var h := float(p["h"])
	var grow := clampf(k * 4.0, 0.0, 1.0)
	var fade := clampf(1.0 - (k - 0.55) / 0.45, 0.0, 1.0)
	var col: Color = p["col"]
	col.a = 0.9 * fade
	var w := 16.0 * grow
	var pts := PackedVector2Array([
		pos + Vector2(-w, 0), pos + Vector2(-w * 0.25, -h * grow),
		pos + Vector2(w * 0.3, -h * 0.92 * grow), pos + Vector2(w, 0)])
	draw_colored_polygon(pts, col)
	var edge := Color(0.96, 0.94, 0.88, 0.4 * fade)
	draw_line(pos + Vector2(0, 0), pos + Vector2(0, -h * grow), edge, 1.2)


func _draw_slash(p: Dictionary, k: float) -> void:
	var pos: Vector2 = p["pos"]
	var f := float(p["f"])
	var r := float(p["r"])
	var col: Color = p["col"]
	col.a = (1.0 - k) * 0.55
	var a0 := -2.2 + k * 1.2
	var a1 := a0 + 1.6
	var pts_out := PackedVector2Array()
	var pts_in := PackedVector2Array()
	for i in 10:
		var a := lerpf(a0, a1, float(i) / 9.0)
		var d := Vector2(cos(a) * f, sin(a))
		pts_out.append(pos + d * r)
		pts_in.append(pos + d * r * 0.55)
	var band := PackedVector2Array(pts_out)
	for i in range(pts_in.size() - 1, -1, -1):
		band.append(pts_in[i])
	if band.size() >= 3:
		draw_colored_polygon(band, col)
	draw_polyline(pts_out, Color(1, 0.98, 0.94, (1.0 - k) * 0.8), 2.0, true)


func _draw_wave(p: Dictionary, k: float) -> void:
	var pos: Vector2 = p["pos"]
	var f := float(p["f"])
	var reach := float(p["reach"]) * k
	var col: Color = p["col"]
	col.a = (1.0 - k) * 0.7
	draw_arc(pos, maxf(4.0, reach), PI * 0.95, PI * 1.55 if f < 0 else PI * 1.45, 20, col, 4.0, true)


func _draw_stamp(p: Dictionary, k: float) -> void:
	var pos: Vector2 = p["pos"]
	var col: Color = p["col"]
	var a := 1.0 - k * k
	col.a = a
	var s := float(p["size"]) * (1.0 + 0.35 * (1.0 - minf(1.0, k * 5.0))) * (1.0 - k * 0.1)
	pos += Vector2(0, -28.0 * k)
	var txt := String(p["text"])
	var tw := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, int(s)).x
	draw_string(_font, pos + Vector2(-tw * 0.5, 0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, int(s), col)
	if k < 0.25:
		var edge := col
		edge.a = (0.25 - k) * 3.0
		draw_rect(Rect2(pos + Vector2(-tw * 0.5 - 8, -s * 0.9), Vector2(tw + 16, s * 1.1)), edge, false, 1.6)


func _draw_seal(p: Dictionary, k: float) -> void:
	var pos: Vector2 = p["pos"]
	var s := float(p["size"]) * (1.0 + 0.5 * (1.0 - minf(1.0, k * 4.0)))
	var a := clampf(1.0 - k * 1.2, 0.0, 1.0)
	var box := Rect2(pos - Vector2(s * 0.5, s * 0.5), Vector2(s, s))
	var col := P.RED
	col.a = 0.14 * a
	draw_rect(box, col)
	var edge := P.RED
	edge.a = 0.85 * a
	draw_rect(box, edge, false, maxf(2.0, s * 0.05))
	var txt := String(p["text"])
	var fs := int(s * 0.62)
	var tw := _seal.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(_seal, pos + Vector2(-tw * 0.5, s * 0.22), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.545, 0.153, 0.129, a))
