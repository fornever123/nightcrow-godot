extends Control
## 截弦 · 纸影戏背景（屏幕空间，全部代码绘制）。
## 暖白纸 + 三层墨山 + 淡朱日 + 松 / 塔 / 鼓 / 判台剪影 + 飘纸屑。

const P := preload("res://dsh/scripts/chord_palette.gd")

var camera_x: float = 0.0
var camera_y: float = 300.0
var act_index: int = 0
var act_center: float = 0.0
var focus: float = 0.0          # 0..1，战斗紧张时四角墨晕加深

var _t: float = 0.0
var _grain: ImageTexture
var _scraps: Array = []
var _birds: Array = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_rng.seed = 20261103
	_build_grain()
	_build_scraps()
	_build_birds()


func _build_grain() -> void:
	var img := Image.create(160, 160, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))
	for y in 160:
		for x in 160:
			var v := _rng.randf()
			if v > 0.80:
				img.set_pixel(x, y, Color(0.16, 0.14, 0.12, (v - 0.80) * 0.55))
			elif v < 0.16:
				img.set_pixel(x, y, Color(1, 1, 1, (0.16 - v) * 0.55))
	_grain = ImageTexture.create_from_image(img)


func _build_scraps() -> void:
	for i in 34:
		_scraps.append({
			"x": _rng.randf_range(-80.0, 1360.0),
			"y": _rng.randf_range(-60.0, 720.0),
			"vy": _rng.randf_range(9.0, 26.0),
			"vx": _rng.randf_range(-16.0, 24.0),
			"rot": _rng.randf_range(0.0, TAU),
			"spin": _rng.randf_range(-1.1, 1.1),
			"w": _rng.randf_range(3.0, 8.0),
			"h": _rng.randf_range(2.0, 4.0),
			"a": _rng.randf_range(0.10, 0.28),
			"p": _rng.randf_range(0.55, 0.95),
		})


func _build_birds() -> void:
	for i in 3:
		_birds.append({
			"x": _rng.randf_range(200.0, 1100.0),
			"y": _rng.randf_range(90.0, 210.0),
			"v": _rng.randf_range(6.0, 13.0),
			"ph": _rng.randf_range(0.0, TAU),
			"s": _rng.randf_range(4.0, 8.0),
		})


func _process(delta: float) -> void:
	_t += delta
	var d := delta
	for s in _scraps:
		s["y"] = float(s["y"]) + float(s["vy"]) * d
		s["x"] = float(s["x"]) + (float(s["vx"]) + sin(_t * 0.7 + float(s["rot"])) * 6.0) * d
		s["rot"] = float(s["rot"]) + float(s["spin"]) * d
		if float(s["y"]) > 740.0:
			s["y"] = -20.0
			s["x"] = _rng.randf_range(-80.0, 1360.0)
		if float(s["x"]) > 1360.0:
			s["x"] = -40.0
	for b in _birds:
		b["x"] = float(b["x"]) + float(b["v"]) * d
		if float(b["x"]) > 1340.0:
			b["x"] = -60.0
			b["y"] = _rng.randf_range(90.0, 220.0)
	queue_redraw()


func _draw() -> void:
	var w := size.x if size.x > 0.0 else 1280.0
	var h := size.y if size.y > 0.0 else 720.0
	_draw_paper(w, h)
	_draw_sun(w, h)
	_draw_mountains(w, h)
	_draw_accent(w, h)
	_draw_pines(w, h)
	_draw_wash(w, h)
	_draw_birds()
	_draw_scraps()
	_draw_grain(w, h)
	_draw_vignette(w, h)


func _draw_paper(w: float, h: float) -> void:
	draw_rect(Rect2(-4, -4, w + 8, h + 8), P.PAPER)
	# 纸的受光：上亮下暗
	for i in 12:
		var k := float(i) / 12.0
		var col := P.PAPER_LIGHT.lerp(P.PAPER_DEEP, k)
		col.a = 0.10
		draw_rect(Rect2(-4, h * k * 0.9, w + 8, h * 0.1 + 2.0), col)
	# 几道纸纤维
	for i in 9:
		var y := h * (0.12 + 0.09 * float(i)) + sin(float(i) * 2.1) * 12.0
		var a := 0.035 + 0.01 * float(i % 3)
		draw_line(Vector2(0, y), Vector2(w, y + sin(float(i)) * 8.0), Color(0.24, 0.20, 0.16, a), 1.0)


func _draw_sun(w: float, _h: float) -> void:
	var sx := w * 0.5 + (act_center + 430.0 - camera_x) * 0.05
	var sy := 176.0 - (camera_y - 300.0) * 0.04
	var r := 92.0
	# 淡朱日：一圈圈压出纸上的晕
	for i in 9:
		var k := 1.0 - float(i) * 0.09
		var col := P.RED_BRIGHT
		col.a = 0.012 + 0.012 * float(i)
		draw_circle(Vector2(sx, sy), r * k, col)
	var disc := P.RED_BRIGHT
	disc.a = 0.20
	draw_circle(Vector2(sx, sy), r * 0.92, disc)
	var inner := P.RED
	inner.a = 0.12
	draw_circle(Vector2(sx, sy), r * 0.62, inner)
	# 印章式的外框
	var ring := P.RED_DEEP
	ring.a = 0.22
	draw_arc(Vector2(sx, sy), r * 1.02, 0.0, TAU, 64, ring, 1.0, true)


func _ridge(wx: float, layer: int) -> float:
	var a := 0.0
	match layer:
		0:
			a = sin(wx * 0.0021 + 1.7) * 46.0 + sin(wx * 0.0047 + 4.1) * 20.0 + sin(wx * 0.0009) * 34.0
		1:
			a = sin(wx * 0.0032 + 0.4) * 32.0 + sin(wx * 0.0072 + 2.2) * 14.0 + sin(wx * 0.0012 + 5.0) * 26.0
		_:
			a = sin(wx * 0.0051 + 3.3) * 22.0 + sin(wx * 0.0110 + 0.9) * 9.0 + sin(wx * 0.0018 + 2.6) * 18.0
	return a


func _draw_mountains(w: float, h: float) -> void:
	var specs := [
		{"p": 0.07, "base": 372.0, "alpha": 0.075, "layer": 0},
		{"p": 0.14, "base": 430.0, "alpha": 0.105, "layer": 1},
		{"p": 0.24, "base": 500.0, "alpha": 0.135, "layer": 2},
	]
	for spec in specs:
		var p: float = float(spec["p"])
		var pts := PackedVector2Array()
		var step := 34.0
		var x := -80.0
		while x <= w + 80.0:
			var wx := (x - w * 0.5) / p + camera_x
			pts.append(Vector2(x, float(spec["base"]) - _ridge(wx, int(spec["layer"]))))
			x += step
		var poly := PackedVector2Array(pts)
		poly.append(Vector2(w + 80.0, h + 40.0))
		poly.append(Vector2(-80.0, h + 40.0))
		var col := P.INK
		col.a = float(spec["alpha"])
		draw_colored_polygon(poly, col)
		# 山脊上一道更深的墨线
		var line_col := P.INK
		line_col.a = float(spec["alpha"]) * 1.5
		draw_polyline(pts, line_col, 1.6, true)


func _draw_accent(w: float, h: float) -> void:
	match act_index:
		0:
			# 远处一座纸塔
			_tower(w, h, 640.0, 0.30, 372.0, 1.0, 0.10)
		1:
			_tower(w, h, 220.0, 0.34, 392.0, 0.85, 0.10)
			_lantern(w, h, 980.0, 0.42, 250.0)
		2:
			_drum(w, h, 380.0, 0.30, 430.0, 176.0)
			_tower(w, h, 1000.0, 0.26, 400.0, 0.9, 0.09)
		3:
			_hall(w, h)
			_seal(w, h)


func _tower(w: float, h: float, wx: float, p: float, base: float, s: float, alpha: float) -> void:
	var x := w * 0.5 + (act_center + wx - camera_x) * p
	var col := P.INK
	col.a = alpha
	var body := PackedVector2Array([
		Vector2(x - 26 * s, base), Vector2(x - 18 * s, base - 120 * s),
		Vector2(x + 18 * s, base - 120 * s), Vector2(x + 26 * s, base)])
	draw_colored_polygon(body, col)
	for i in 3:
		var y := base - 120 * s - float(i) * 46.0 * s
		var ww := (44.0 - float(i) * 7.0) * s
		var roof := PackedVector2Array([
			Vector2(x - ww, y + 14 * s),
			Vector2(x - ww * 0.55, y - 6 * s),
			Vector2(x, y - 20 * s),
			Vector2(x + ww * 0.55, y - 6 * s),
			Vector2(x + ww, y + 14 * s),
			Vector2(x + ww * 0.7, y + 10 * s),
			Vector2(x, y + 2 * s),
			Vector2(x - ww * 0.7, y + 10 * s),
		])
		draw_colored_polygon(roof, col)
	# 塔尖
	draw_line(Vector2(x, base - 262 * s), Vector2(x, base - 292 * s), col, 2.0 * s)


func _lantern(w: float, h: float, wx: float, p: float, y: float) -> void:
	var x := w * 0.5 + (act_center + wx - camera_x) * p
	draw_line(Vector2(x, 40), Vector2(x, y - 26), Color(0.16, 0.14, 0.12, 0.20), 1.0)
	var glow := P.RED_BRIGHT
	glow.a = 0.13
	draw_circle(Vector2(x, y), 34.0, glow)
	var body := P.RED
	body.a = 0.26
	draw_circle(Vector2(x, y), 17.0, body)
	var rim := P.RED_DEEP
	rim.a = 0.32
	draw_arc(Vector2(x, y), 17.0, 0.0, TAU, 24, rim, 1.2, true)
	draw_line(Vector2(x - 10, y - 22), Vector2(x + 10, y - 22), rim, 1.2)
	draw_line(Vector2(x - 10, y + 22), Vector2(x + 10, y + 22), rim, 1.2)


func _drum(w: float, h: float, wx: float, p: float, base: float, r: float) -> void:
	var x := w * 0.5 + (act_center + wx - camera_x) * p
	var col := P.INK
	col.a = 0.10
	draw_circle(Vector2(x, base), r, col)
	var rim := P.INK
	rim.a = 0.16
	draw_arc(Vector2(x, base), r, 0.0, TAU, 48, rim, 3.0, true)
	draw_arc(Vector2(x, base), r * 0.78, 0.0, TAU, 40, rim, 1.4, true)
	draw_arc(Vector2(x, base), r * 0.56, 0.0, TAU, 32, rim, 1.0, true)
	# 鼓钉
	for i in 12:
		var a := TAU * float(i) / 12.0
		draw_circle(Vector2(x + cos(a) * r * 0.89, base + sin(a) * r * 0.89), 3.0, rim)


func _hall(w: float, h: float) -> void:
	var x := w * 0.5 + (act_center + 300.0 - camera_x) * 0.22
	var col := P.INK
	col.a = 0.11
	var base := 470.0
	draw_colored_polygon(PackedVector2Array([
		Vector2(x - 300, base), Vector2(x - 300, base - 150), Vector2(x + 300, base - 150),
		Vector2(x + 300, base)]), col)
	# 三间门
	for i in 3:
		var px := x - 200.0 + float(i) * 200.0
		draw_rect(Rect2(px - 34, base - 128, 68, 128), Color(0.93, 0.90, 0.82, 0.55))
	# 屋檐
	var roof := PackedVector2Array([
		Vector2(x - 380, base - 160), Vector2(x - 250, base - 196), Vector2(x, base - 214),
		Vector2(x + 250, base - 196), Vector2(x + 380, base - 160),
		Vector2(x + 380, base - 140), Vector2(x + 120, base - 158), Vector2(x, base - 150),
		Vector2(x - 120, base - 158), Vector2(x - 380, base - 140)])
	var rcol := P.INK
	rcol.a = 0.16
	draw_colored_polygon(roof, rcol)


func _seal(w: float, h: float) -> void:
	var x := w * 0.5 + (act_center + 470.0 - camera_x) * 0.08
	var y := 150.0
	var col := P.RED
	col.a = 0.16
	draw_rect(Rect2(x - 62, y - 62, 124, 124), col, false, 5.0)
	var fill := P.RED
	fill.a = 0.06
	draw_rect(Rect2(x - 58, y - 58, 116, 116), fill)
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Source Han Serif SC", "Microsoft YaHei", "SimSun"])
	draw_string(f, Vector2(x - 40, y + 26), "判", HORIZONTAL_ALIGNMENT_LEFT, -1, 64, Color(0.545, 0.153, 0.129, 0.22))


func _draw_pines(w: float, h: float) -> void:
	var start := -900.0
	var idx := 0
	while start < 6600.0:
		var wx := start + float((idx * 337) % 700)
		var p := 0.52
		var x := w * 0.5 + (wx - camera_x) * p
		if x > -140.0 and x < w + 140.0:
			_pine(x, 592.0 + sin(float(idx) * 1.7) * 10.0, 0.85 + 0.1 * float(idx % 3), 0.34)
		start += 700.0
		idx += 1


func _pine(x: float, base: float, s: float, alpha: float) -> void:
	var ink := P.INK
	ink.a = alpha
	var top := base - 210.0 * s
	var trunk := PackedVector2Array()
	for i in 7:
		var k := float(i) / 6.0
		trunk.append(Vector2(x + sin(k * 2.2) * 10.0 * s, lerpf(base, top, k)))
	draw_polyline(trunk, ink, 4.0 * s, true)
	for i in 4:
		var k := 0.22 + 0.20 * float(i)
		var by := lerpf(base, top, k)
		var dir := -1.0 if i % 2 == 0 else 1.0
		var reach := (88.0 - float(i) * 10.0) * s * (1.0 - k * 0.35)
		var tip := Vector2(x + dir * reach, by - 10.0 * s)
		draw_line(Vector2(x, by), tip, ink, 2.4 * s, true)
		draw_line(Vector2(x, by - 2.0), Vector2(x + dir * reach * 0.55, by - 22.0 * s), ink, 1.6 * s, true)
		# 松针：一簇一簇的短墨
		for j in 5:
			var kk := 0.16 + 0.17 * float(j)
			var px := lerpf(x, tip.x, kk)
			var py := lerpf(by, tip.y, kk)
			draw_line(Vector2(px, py), Vector2(px + dir * 7.0, py - 13.0 * s), ink, 1.2 * s, true)
	draw_circle(Vector2(x, top), 3.0 * s, ink)


func _draw_wash(w: float, h: float) -> void:
	# 底部墨积
	for i in 5:
		var col := P.INK
		col.a = 0.020 + 0.010 * float(i)
		draw_rect(Rect2(-4, h - 150.0 + float(i) * 26.0, w + 8, 44.0), col)
	# 中景一条很淡的雾
	var mist := P.WHITE
	mist.a = 0.10
	draw_rect(Rect2(-4, 432, w + 8, 74), mist)


func _draw_birds() -> void:
	for b in _birds:
		var x := float(b["x"])
		var y := float(b["y"]) + sin(_t * 1.6 + float(b["ph"])) * 4.0
		var s := float(b["s"])
		var ink := P.INK
		ink.a = 0.24
		draw_line(Vector2(x - s, y), Vector2(x - s * 0.2, y - s * 0.45), ink, 1.2, true)
		draw_line(Vector2(x + s * 0.2, y - s * 0.45), Vector2(x + s, y), ink, 1.2, true)


func _draw_scraps() -> void:
	for s in _scraps:
		var x := float(s["x"])
		var y := float(s["y"])
		var a := float(s["a"])
		var w := float(s["w"])
		var h := float(s["h"])
		var rot := float(s["rot"])
		var p: float = float(s["p"])
		# 视差
		var dx := (camera_x - act_center) * (1.0 - p) * 0.12
		var c := P.INK
		c.a = a
		var pts := PackedVector2Array()
		for k in 4:
			var ang := rot + TAU * float(k) / 4.0
			pts.append(Vector2(x + dx + cos(ang) * w, y + sin(ang) * h))
		draw_colored_polygon(pts, c)


func _draw_grain(w: float, h: float) -> void:
	if _grain != null:
		draw_texture_rect(_grain, Rect2(-8, -8, w + 16, h + 16), true, Color(1, 1, 1, 0.55))


func _draw_vignette(w: float, h: float) -> void:
	var strength := 0.030 + focus * 0.050
	for i in 14:
		var a := strength * (1.0 - float(i) / 14.0)
		var col := P.INK
		col.a = a
		var band := 7.0
		draw_rect(Rect2(float(i) * band, float(i) * band, w - float(i) * band * 2.0, h - float(i) * band * 2.0), col, false, band + 1.0)
