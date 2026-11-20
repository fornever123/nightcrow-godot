extends Node2D
## 错拍专用特效：斩痕、迟到数字、环、闪光、空挥。

var trial: Node = null
var items: Array = []
var _font: SystemFont


func _ready() -> void:
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Source Han Serif SC", "Microsoft YaHei", "SimHei"])


func _process(delta: float) -> void:
	var alive: Array = []
	for it in items:
		it["t"] = float(it["t"]) + delta
		if float(it["t"]) < float(it["life"]):
			alive.append(it)
	items = alive
	queue_redraw()


func hit_ghost(from: Vector2, at: Vector2, damage: float, beat: bool) -> void:
	var col := Color(0.98, 0.96, 1.0, 1.0) if beat else Color(0.78, 0.58, 1.0, 1.0)
	items.append({"kind": "cut", "a": from, "b": at, "life": 0.30, "t": 0.0, "color": col, "w": 3.2})
	items.append({"kind": "ring", "pos": at, "r0": 8.0, "r1": 62.0, "life": 0.32, "t": 0.0, "color": col})
	items.append({"kind": "num", "pos": at + Vector2(0, -30), "text": "-%d" % int(damage), "size": 30, "life": 0.9, "t": 0.0, "color": col})
	if beat:
		items.append({"kind": "ring", "pos": at, "r0": 30.0, "r1": 110.0, "life": 0.42, "t": 0.0, "color": Color(0.85, 0.92, 1.0, 0.8)})


func impact(pos: Vector2, color: Color) -> void:
	items.append({"kind": "ring", "pos": pos, "r0": 6.0, "r1": 54.0, "life": 0.28, "t": 0.0, "color": color})
	items.append({"kind": "cut", "a": pos + Vector2(-46, -18), "b": pos + Vector2(46, 18), "life": 0.22, "t": 0.0, "color": color, "w": 2.4})


func ring(pos: Vector2, radius: float, color: Color) -> void:
	items.append({"kind": "ring", "pos": pos, "r0": 10.0, "r1": radius, "life": 0.5, "t": 0.0, "color": color})


func flash(color: Color, alpha: float) -> void:
	items.append({"kind": "flash", "color": color, "alpha": alpha, "life": 0.24, "t": 0.0})


func whiff(rect: Rect2) -> void:
	var dir := 1.0
	if rect.size.x > 0.0 and rect.position.x < 0.0:
		dir = 1.0
	items.append({"kind": "whiff", "pos": rect.position + rect.size * 0.5, "life": 0.30, "t": 0.0, "dir": dir})


func _draw() -> void:
	for it in items:
		var k := clampf(float(it["t"]) / maxf(0.001, float(it["life"])), 0.0, 1.0)
		var fade := 1.0 - k
		match String(it["kind"]):
			"cut":
				var a: Vector2 = it["a"]
				var b: Vector2 = it["b"]
				var col: Color = it["color"]
				col.a *= fade
				draw_line(a, b, col, float(it["w"]), true)
				draw_line(a, b, Color(1, 1, 1, 0.9 * fade), float(it["w"]) * 0.4, true)
			"ring":
				var pos: Vector2 = it["pos"]
				var r := lerpf(float(it["r0"]), float(it["r1"]), k)
				var rc: Color = it["color"]
				rc.a *= fade * 0.9
				draw_arc(pos, r, 0.0, TAU, 32, rc, 2.0 + 3.0 * fade, true)
			"num":
				var p: Vector2 = it["pos"] + Vector2(0, -44.0 * k)
				var nc: Color = it["color"]
				nc.a *= fade
				var shadow := Color(0.02, 0.02, 0.05, 0.9 * fade)
				draw_string(_font, p + Vector2(2, 2), String(it["text"]), HORIZONTAL_ALIGNMENT_CENTER, -1, int(it["size"]), shadow)
				draw_string(_font, p, String(it["text"]), HORIZONTAL_ALIGNMENT_CENTER, -1, int(it["size"]), nc)
			"flash":
				var fc: Color = it["color"]
				fc.a = float(it["alpha"]) * fade
				draw_rect(Rect2(-3000, -2200, 6000, 4400), fc)
			"whiff":
				var wp: Vector2 = it["pos"]
				var wc := Color(0.62, 0.55, 0.85, 0.55 * fade)
				draw_arc(wp, 54.0 + 30.0 * k, -1.0, 1.2, 16, wc, 1.6, true)
				draw_string(_font, wp + Vector2(0, -70), "打的是现在", HORIZONTAL_ALIGNMENT_CENTER, -1, 17, Color(0.68, 0.6, 0.9, 0.8 * fade))
