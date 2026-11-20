extends Control
## 首页字标「断晓」：被光一笔一笔写出来，然后被一刀斩成上下两半、错开。
## 用嵌套的 clip_contents 做「写到哪儿显示到哪儿」，再用 clip 做上下切分，所以是真字、不是贴图。
## 由 title_art.gd 挂在光层和前层之间（在后期辉光之下，所以字会发光）。

const T_MARK := 2.25        ## 开始写
const T_SPLIT := 3.59       ## 刀光扫过中线，字被斩开
const WRITE_SEC := 1.15
const SPLIT_SEC := 0.55

const WARM := Color("fff2d2")
const WARM_HOT := Color("fffdf2")
const SILVER := Color("dbe3f1")
const STEEL := Color("93a0b8")
const VIOLET_HOT := Color("c8b0ff")
const VIOLET := Color("9a6cff")

const TEXT := "断晓"
const SUB := "LUX SCISSA"

var clock := 0.0

var _font: Font
var _small: Font
var _top_clip: Control
var _top_writer: Control
var _top_paint: Control
var _bot_clip: Control
var _bot_writer: Control
var _bot_paint: Control
var _overlay: Control

var _glyph_w := 520.0
var _glyph_x := 380.0
var _base_y := 296.0
var _cut_y := 306.0
var _top_y := 150.0
var _bot_h := 170.0
var _pad := 60.0
var _size := 132
var _spacing := 22.0
var _small_size := 15
var _k := 1.0
var _char_x: Array[float] = []
var _sub_y := 0.0


func _ready() -> void:
	name = "Wordmark"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = _system(["Source Han Serif SC Heavy", "Source Han Serif SC", "Noto Serif SC", "SimSun", "serif"], 900)
	_small = _system(["Georgia", "Noto Serif SC", "Source Han Serif SC", "serif"], 400)
	_build()
	_layout()


func _system(names: Array, weight: int) -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(names)
	f.font_weight = weight
	return f


func _build() -> void:
	_top_clip = _clip()
	_top_writer = _clip()
	_top_paint = Control.new()
	_top_paint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top_paint.draw.connect(_paint_slice.bind(true))
	_top_writer.add_child(_top_paint)
	_top_clip.add_child(_top_writer)

	_bot_clip = _clip()
	_bot_writer = _clip()
	_bot_paint = Control.new()
	_bot_paint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bot_paint.draw.connect(_paint_slice.bind(false))
	_bot_writer.add_child(_bot_paint)
	_bot_clip.add_child(_bot_writer)

	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)


func _clip() -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.clip_contents = true
	return c


func _size_v() -> Vector2:
	var r := get_viewport_rect().size
	return Vector2(maxf(r.x, 320.0), maxf(r.y, 240.0))


func _layout() -> void:
	var vp := _size_v()
	_k = clampf(vp.y / 720.0, 0.55, 2.5)
	_size = int(round(132.0 * _k))
	_spacing = 22.0 * _k
	_pad = 70.0 * _k
	_base_y = 296.0 * _k
	_cut_y = 306.0 * _k
	var ascent := _font.get_ascent(_size)
	_glyph_w = 0.0
	_char_x.clear()
	for ch in TEXT:
		var cw := _font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, _size).x
		_char_x.append(cw)
		_glyph_w += cw + _spacing
	_glyph_w -= _spacing
	_glyph_x = vp.x * 0.5 - _glyph_w * 0.5
	_top_y = _base_y - ascent - 30.0 * _k
	_bot_h = (_base_y + _font.get_descent(_size) + 30.0 * _k) - _cut_y
	_small_size = int(round(15.0 * _k))
	_sub_y = _cut_y + 74.0 * _k
	_position_clips()


func _position_clips() -> void:
	if _top_clip == null:
		return
	var vp := _size_v()
	var split := _split_k()
	var warm_shift := _ease_out(split)
	_top_clip.position = Vector2(_glyph_x - _pad, _top_y + 8.0 * warm_shift - 6.0 * split) - _shake()
	_top_clip.size = Vector2(_glyph_w + _pad * 2.0, _cut_y - _top_y + 8.0 * warm_shift)
	_top_clip.pivot_offset = _top_clip.size * 0.5
	_top_clip.rotation = -0.0055 * split
	_bot_clip.position = Vector2(_glyph_x - _pad, _cut_y + 7.0 * split) - _shake()
	_bot_clip.size = Vector2(_glyph_w + _pad * 2.0, _bot_h - 8.0 * warm_shift)
	_bot_clip.pivot_offset = _bot_clip.size * 0.5
	_bot_clip.rotation = 0.0045 * split
	var reveal := clampf(_write_k() * (_glyph_w + _pad + 30.0 * _k), 0.0, _glyph_w + _pad * 2.0)
	_top_writer.size = Vector2(reveal, _top_clip.size.y)
	_bot_writer.size = Vector2(reveal, _bot_clip.size.y)
	_top_paint.size = _top_writer.size
	_bot_paint.size = _bot_writer.size
	if _overlay != null:
		_overlay.size = vp


func _shake() -> Vector2:
	var a := get_parent()
	if a != null and a.has_method("_shake_offset"):
		return a._shake_offset() * 1.2
	return Vector2.ZERO


func _write_k() -> float:
	return _ease_out(clampf((clock - T_MARK) / WRITE_SEC, 0.0, 1.0))


func _split_k() -> float:
	return _ease_out(clampf((clock - T_SPLIT) / SPLIT_SEC, 0.0, 1.0))


func _cold_k() -> float:
	return clampf((clock - T_SPLIT - 0.15) / 1.30, 0.0, 1.0)


func _ease_out(t: float) -> float:
	var k := clampf(t, 0.0, 1.0)
	return 1.0 - pow(1.0 - k, 3.0)


func get_glyph_width() -> float:
	return _glyph_w


func seek(t: float) -> void:
	clock = t
	_layout()
	_redraw_all()


func skip_intro() -> void:
	clock = maxf(clock, 5.8)
	_redraw_all()


func _process(delta: float) -> void:
	clock += delta
	_layout()
	_redraw_all()


func _redraw_all() -> void:
	for c in [_top_clip, _bot_clip, _top_writer, _bot_writer, _top_paint, _bot_paint, _overlay]:
		if c != null:
			c.queue_redraw()


# ---------------------------------------------------------------- 画字

func _paint_slice(top: bool) -> void:
	var writer: Control = _top_writer if top else _bot_writer
	var painter: Control = _top_paint if top else _bot_paint
	if writer == null or painter == null:
		return
	var reveal_px := _pad + _glyph_w * _write_k() + 20.0 * _k
	var since_write := clock - T_MARK - WRITE_SEC * 0.55
	var breathe := 0.94 + 0.06 * sin(clock * 1.35)
	var base := WARM
	if top:
		base = WARM
	else:
		base = WARM.lerp(SILVER, _cold_k())
	var y := (_base_y - _top_y) if top else (_base_y - _cut_y)
	var x := _pad
	for i in TEXT.length():
		var ch := TEXT[i]
		var a := clampf((reveal_px - x) / (34.0 * _k), 0.0, 1.0)
		if a <= 0.001:
			x += _char_x[i] + _spacing
			continue
		var col := Color(base.r * breathe, base.g * breathe, base.b * breathe, 1.0)
		# 刚被光写过的地方偏白，一秒内冷下来
		var hot := clampf(1.0 - (clock - T_MARK - 0.35 * i) / 1.6, 0.0, 1.0)
		col = col.lerp(WARM_HOT, hot * 0.55)
		# 断口下面一点紫
		if not top:
			var edge := clampf(1.0 - absf(y - 0.0) / 60.0, 0.0, 1.0)
			col = col.lerp(VIOLET_HOT, edge * 0.20 * (1.0 - _cold_k()))
		painter.draw_string(_font, Vector2(x, y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, _size, Color(col.r, col.g, col.b, a))
		x += _char_x[i] + _spacing
	# 写字的笔光是最后一道阴影，压一点黄
	if since_write < 0.45 and not top:
		pass


# ---------------------------------------------------------------- 覆盖层（写字光 / 拉丁小字 / 断口 / 扫光）

func _draw_overlay() -> void:
	var off := _shake()
	var write := _write_k()
	var split := _split_k()
	# 写字的笔光：一道竖着的白光，跟着笔画走
	if write > 0.02 and write < 0.999:
		var px := _glyph_x - _pad * 0.5 + (_glyph_w + _pad) * write
		var top := _cut_y - 150.0 * _k
		var bot := _cut_y + 150.0 * _k
		var w := 26.0 * _k
		var pts := PackedVector2Array([Vector2(px - w, top), Vector2(px + w * 0.25, top),
				Vector2(px + w * 0.25, bot), Vector2(px - w, bot)])
		var gc := PackedColorArray([Color(VIOLET_HOT, 0.0), Color(VIOLET_HOT, 0.16),
				Color(VIOLET_HOT, 0.16), Color(VIOLET_HOT, 0.0)])
		draw_polygon(pts, gc)
		draw_line(Vector2(px, top + 6.0), Vector2(px, bot - 6.0), Color(1.0, 0.96, 1.0, 0.55), 1.2, true)
	# 断口：一条熔线，从紫烧到冷
	if split > 0.0:
		var since := clock - T_SPLIT
		var hot := clampf(1.0 - since / 1.2, 0.0, 1.0)
		var col := VIOLET_HOT.lerp(SILVER, 1.0 - hot)
		var a := 0.55 * clampf(1.0 - (since - 1.0) / 2.6, 0.0, 1.0)
		var w2 := (_glyph_w + _pad * 2.2) * lerpf(0.55, 1.0, split)
		var pts2 := PackedVector2Array()
		var cols2 := PackedColorArray()
		for i in 27:
			var t := float(i) / 26.0
			var x := _size_v().x * 0.5 - w2 * 0.5 + w2 * t
			pts2.append(Vector2(x, _cut_y + sin(t * PI * 1.1) * 2.4 * hot + off.y))
			cols2.append(Color(col.r, col.g, col.b, a * (0.25 + 0.95 * sin(t * PI))))
		draw_polyline_colors(pts2, cols2, 1.4 + 2.6 * hot, true)
		# 断口边缘剥落的碎光
		if since < 0.8:
			for i in 9:
				var t2 := float(i) / 8.0
				var x2 := _size_v().x * 0.5 - _glyph_w * 0.5 + _glyph_w * t2
				var y2 := _cut_y + (_rngf(i) - 0.5) * 40.0 * since
				draw_circle(Vector2(x2, y2), 1.3, Color(VIOLET_HOT, 0.5 * (1.0 - since / 0.8)))
	# LUX SCISSA
	var sub_a := clampf((clock - T_MARK - 0.55) / 0.9, 0.0, 1.0)
	if sub_a > 0.01:
		var col2 := STEEL.lerp(SILVER, 0.35)
		var sz := _small_size
		var spacing := 12.0 * _k
		var wsum := 0.0
		for ch in SUB:
			wsum += _small.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x + spacing
		wsum -= spacing
		var x := _size_v().x * 0.5 - wsum * 0.5
		for ch in SUB:
			draw_string(_small, Vector2(x, _sub_y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, sz,
					Color(col2.r, col2.g, col2.b, 0.62 * sub_a))
			x += _small.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x + spacing
	# 缓慢扫过字面的一道光
	if clock > T_SPLIT + 2.0:
		var period := 7.5
		var ph := fmod(clock - T_SPLIT - 2.0, period) / period
		var sx := _size_v().x * (0.5 - 0.42) + _size_v().x * 0.84 * ph
		var top3 := _cut_y - 130.0 * _k
		var bot3 := _cut_y + 130.0 * _k
		var pts3 := PackedVector2Array([Vector2(sx - 46.0, top3), Vector2(sx + 6.0, top3),
				Vector2(sx - 14.0, bot3), Vector2(sx - 66.0, bot3)])
		var gc3 := PackedColorArray([Color(WARM_HOT, 0.0), Color(WARM_HOT, 0.075),
				Color(WARM_HOT, 0.055), Color(WARM_HOT, 0.0)])
		draw_polygon(pts3, gc3)


func _rngf(i: int) -> float:
	var x := sin(float(i) * 127.1 + 311.7) * 43758.5453
	return x - floorf(x)
