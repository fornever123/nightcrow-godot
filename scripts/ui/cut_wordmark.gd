extends Control
## 「断晓」字标。上半留在昼光里（暖白），下半沉进影子里（冷银），
## 中间那一道就是斩断世界的刀口：上下两半各自错开，断口由 stage 的熔线照亮。
## 字全部自己画（逐字带字距），没有图片。

const GLYPHS := "断晓"
const FONT_NAMES := ["Source Han Serif SC Heavy", "Source Han Serif SC", "Noto Serif SC", "SimSun"]

var font_size := 166
var spacing := 44.0
var center_x := 640.0
var baseline := 346.0
var cut_y := 304.0

var offset_up := Vector2.ZERO
var offset_down := Vector2.ZERO
var alpha_up := 0.0
var alpha_down := 0.0
var tint_up := Color("ffedd2")
var tint_down := Color("9dabc4")
var dim := 0.0          ## 字标背后的压暗强度
var glow := 0.0         ## 上半字标额外的一层暖光（叠加副本）
var spread := 0.0       ## 斩后上下两半的错开量（0..1，由控制器给的动画曲线）
var cut_k := 0.0        ## 断口开合程度（0..1）
var down_dark := 0.0    ## 下半从“还在光里”沉进影子的程度（0..1）
var flash := 0.0        ## 斩断瞬间的一下白闪
var shadow_amt := 0.42  ## 字压在光上的一层暗投影

var _font: SystemFont
var _top: Control
var _bottom: Control
var _shadow: ImageTexture
var _vp := Vector2(1280, 720)


func _ready() -> void:
	name = "Wordmark"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vp = get_viewport_rect().size
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(FONT_NAMES)
	_font.font_weight = 900
	_font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	_shadow = _make_soft(320, 160)
	_top = _make_half("Top", 0.0, cut_y)
	_bottom = _make_half("Bottom", cut_y, maxf(_vp.y - cut_y, 1.0))
	_top.draw.connect(_draw_top)
	_bottom.draw.connect(_draw_bottom)


func _make_half(node_name: String, y0: float, h: float) -> Control:
	var c := Control.new()
	c.name = node_name
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.clip_contents = true
	c.position = Vector2(0, y0)
	c.size = Vector2(_vp.x, h)
	add_child(c)
	return c


func _make_soft(w: int, h: int) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in h:
		for x in w:
			var u := (float(x) / float(w) - 0.5) * 2.0
			var v := (float(y) / float(h) - 0.5) * 2.0
			var d := sqrt(u * u + v * v)
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = a * a * (3.0 - 2.0 * a)
			img.set_pixel(x, y, Color(0.010, 0.012, 0.024, a))
	return ImageTexture.create_from_image(img)


func word_width() -> float:
	var w := 0.0
	for ch in GLYPHS:
		w += _font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + spacing
	return w - spacing


func _paint(ci: Control, off: Vector2, tint: Color, a: float, y_base: float, is_upper: bool) -> void:
	if a <= 0.002:
		return
	var w := word_width()
	var x := center_x - w * 0.5 + off.x
	var y := baseline + off.y + y_base
	for ch in GLYPHS:
		var cw := _font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		# 先落一层暗投影：字是从光里浮出来的，不是贴上去的
		if shadow_amt > 0.001:
			ci.draw_string(_font, Vector2(x + 2.6, y + 3.2), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
					Color(0.0, 0.0, 0.0, a * shadow_amt))
		# 一层很淡的暖光垫底（只在光里那半），让字像被光浸着
		if glow > 0.001 and is_upper:
			ci.draw_string(_font, Vector2(x + 1.5, y + 1.5), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
					Color(1.0, 0.88, 0.62, a * glow * 0.22))
			ci.draw_string(_font, Vector2(x - 1.5, y + 1.5), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
					Color(1.0, 0.90, 0.70, a * glow * 0.16))
		ci.draw_string(_font, Vector2(x, y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(tint, a))
		x += cw + spacing


func _draw_top() -> void:
	_paint(_top, offset_up, tint_up, alpha_up, 0.0, true)
	_seam_edge(_top, cut_y - 0.9, 1.0)


func _draw_bottom() -> void:
	_paint(_bottom, offset_down, tint_up.lerp(tint_down, down_dark), alpha_down, -cut_y, false)
	if flash > 0.001:
		_paint(_bottom, offset_down, Color(1, 0.97, 0.92), alpha_down * flash * 0.55, -cut_y, false)
	_seam_edge(_bottom, 0.9, 1.0)


## 字标断口上的一条熔光：和 stage 里那条刀痕是一条线
func _seam_edge(ci: Control, y: float, dir: float) -> void:
	if cut_k <= 0.01:
		return
	var w := word_width() + 118.0
	var a := cut_k * (0.55 + 0.35 * sin(Time.get_ticks_msec() * 0.0019))
	var x0 := center_x - w * 0.5
	var pts := PackedVector2Array([Vector2(x0, y), Vector2(x0 + w * 0.5, y), Vector2(x0 + w, y)])
	var cols := PackedColorArray([Color(0.66, 0.50, 1.0, 0.0), Color(0.96, 0.90, 1.0, a), Color(0.66, 0.50, 1.0, 0.0)])
	# 一圈很淡的熔光，再一条细亮芯
	ci.draw_polyline_colors(pts, PackedColorArray([Color(0.72, 0.58, 1.0, 0.0), Color(0.72, 0.58, 1.0, a * 0.22), Color(0.72, 0.58, 1.0, 0.0)]), 7.0, true)
	ci.draw_polyline_colors(pts, PackedColorArray([Color(0.80, 0.66, 1.0, 0.0), Color(0.86, 0.78, 1.0, a * 0.55), Color(0.80, 0.66, 1.0, 0.0)]), 3.0, true)
	ci.draw_polyline_colors(pts, cols, 1.8, true)


func _draw() -> void:
	# 字标背后的一团压暗：让字从光柱上跳出来，但不像贴纸
	if dim > 0.001:
		var s := Vector2(980.0, 470.0)
		var r := Rect2(Vector2(center_x - s.x * 0.5, baseline - 250.0), s)
		draw_texture_rect(_shadow, r, false, Color(1, 1, 1, dim))


func refresh() -> void:
	_top.size = Vector2(_vp.x, maxf(cut_y, 1.0))
	_bottom.position = Vector2(0, cut_y)
	_bottom.size = Vector2(_vp.x, maxf(_vp.y - cut_y, 1.0))
	_top.queue_redraw()
	_bottom.queue_redraw()
	queue_redraw()
