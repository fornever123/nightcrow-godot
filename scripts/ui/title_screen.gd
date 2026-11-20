extends Control
## 首页（标题画面）控制器 ——「光弦断幕」。
## 画面全部由 scripts/ui/title_art.gd 程序画出（光弦、冻雨、黑羽、刀光、后期），
## 字标在 scripts/ui/title_wordmark.gd。本文件负责：进场时间轴、菜单、操作说明、设置、开场那一刀。
## 键位读 scripts/night/player_factory.gd，和暂停菜单保持一致。

const Factory := preload("res://scripts/night/player_factory.gd")
const TitleArt := preload("res://scripts/ui/title_art.gd")

const GAME_SCENE := "res://scenes/rain_trial.tscn"

const BONE := Color("e9e4d8")
const SILVER := Color("e6e9ef")
const MUTE := Color("8f99ab")
const FAINT := Color("6d778a")
const RULE := Color("8d96a8")
const DOT := Color("aab2c0")
const VIOLET := Color("9a6cff")
const VIOLET_LIGHT := Color("c8b0ff")
const INK := Color("06070b")

const MENU: Array[String] = ["开始游戏", "操作说明", "设置", "退出游戏"]
const NUMERALS: Array[String] = ["Ⅰ", "Ⅱ", "Ⅲ", "Ⅳ"]
const FOOTER := "愿你流血，愿你老去，愿你醒来时，已经在明天"
const FOOTER_NOTE := "黑索司 · 雨港分部"
const BUILD := "v0.1 · 雨夜河岸街"

enum Page { MAIN, HELP, SETTINGS }

var art: Control
var mark: Control

var page := Page.MAIN
var index := 0

var _ui_layer: CanvasLayer
var _canvas: Control
var _hits: Array = []
var _sel_ms := 0

var _serif: Font
var _serif_bold: Font
var _gothic: Font
var _digits: Font
var _soft: ImageTexture

var _starting := false
var _start_at := 0.0
var _scene_done := false
var _volume := 1.0
var _quit_after := -1.0


func _ready() -> void:
	name = "Title"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_serif = _system(["Noto Serif SC", "Source Han Serif SC", "SimSun", "serif"], 400)
	_serif_bold = _system(["Source Han Serif SC Heavy", "Source Han Serif SC", "Noto Serif SC", "serif"], 900)
	_gothic = _system(["Old English Text MT", "Noto Serif SC", "serif"], 400)
	_digits = _system(["Georgia", "Noto Serif SC", "serif"], 400)
	(_digits as SystemFont).font_italic = true
	_soft = _make_soft()
	_volume = db_to_linear(AudioServer.get_bus_volume_db(0))
	art = get_node_or_null("Art")
	_ui_layer = get_node_or_null("Ui")
	if _ui_layer == null:
		_ui_layer = CanvasLayer.new()
		_ui_layer.name = "Ui"
		add_child(_ui_layer)
	_ui_layer.layer = 2
	_canvas = Control.new()
	_canvas.name = "Canvas"
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.draw.connect(_draw_ui)
	_ui_layer.add_child(_canvas)
	if art != null:
		mark = art.mark
	_sel_ms = Time.get_ticks_msec()


func _system(names: Array, weight: int) -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(names)
	f.font_weight = weight
	return f


func _make_soft() -> ImageTexture:
	var n := 64
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	var buf := PackedByteArray()
	buf.resize(n * n * 4)
	var c := (n - 1) * 0.5
	for y in n:
		for x in n:
			var r := Vector2(x - c, y - c).length() / c
			var a := pow(clampf(1.0 - r, 0.0, 1.0), 2.2)
			var i := (y * n + x) * 4
			buf[i] = 255
			buf[i + 1] = 255
			buf[i + 2] = 255
			buf[i + 3] = int(a * 255.0)
	img.set_data(n, n, false, Image.FORMAT_RGBA8, buf)
	return ImageTexture.create_from_image(img)


func _size() -> Vector2:
	var r := get_viewport_rect().size
	return Vector2(maxf(r.x, 320.0), maxf(r.y, 240.0))


func _clock() -> float:
	return art.clock if art != null else 0.0


func _ready_for_input() -> bool:
	return not _starting and _clock() >= TitleArt.T_READY


func seek(t: float) -> void:
	if art != null:
		art.seek(t)
	if mark != null:
		mark.seek(t)
	_sel_ms = Time.get_ticks_msec()


# ---------------------------------------------------------------- 每帧

func _process(_delta: float) -> void:
	if _canvas != null:
		_canvas.queue_redraw()
	if _starting:
		var e := _clock() - _start_at
		if not _scene_done and e > 1.45:
			_scene_done = true
			Engine.time_scale = 1.0
			get_tree().change_scene_to_file(GAME_SCENE)


# ---------------------------------------------------------------- 输入

func _unhandled_input(event: InputEvent) -> void:
	if _starting:
		return
	var is_key := event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion
	if event is InputEventMouseMotion:
		if art != null:
			art.set_light(event.position)
		if page == Page.MAIN and _ready_for_input():
			var i := _hit(event.position)
			if i >= 0 and i != index:
				_select(i)
		return
	if event is InputEventMouseButton:
		if art != null:
			art.set_light(event.position)
		if not event.pressed:
			return
		if not _ready_for_input():
			_skip()
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			var i := _hit(event.position)
			if i >= 0:
				_select(i)
				_activate()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_back()
		return
	if not is_key:
		return
	if not event.is_pressed():
		return
	if not _ready_for_input():
		_skip()
		return
	var back: bool = event.is_action_pressed("ui_cancel") or (event is InputEventJoypadButton
			and event.button_index == JOY_BUTTON_B)
	if back and not event.is_echo():
		_back()
		return
	if _action(event, ["ui_up", "aim_up", "move_up"]):
		_move(-1)
	elif _action(event, ["ui_down", "move_down"]):
		_move(1)
	elif _action(event, ["ui_left", "move_left"]):
		_adjust(-1)
	elif _action(event, ["ui_right", "move_right"]):
		_adjust(1)
	elif _action(event, ["ui_accept", "attack_light"]) and not event.is_echo():
		_activate()


func _action(event: InputEvent, names: Array) -> bool:
	for n in names:
		if InputMap.has_action(n) and event.is_action_pressed(n, true):
			return true
	return false


func _skip() -> void:
	if art != null:
		art.skip_intro()
	if mark != null:
		mark.skip_intro()


func _hit(pos: Vector2) -> int:
	for h in _hits:
		if (h[0] as Rect2).has_point(pos):
			return h[1]
	return -1


func _count() -> int:
	match page:
		Page.MAIN:
			return MENU.size()
		Page.SETTINGS:
			return _settings().size() + 1
	return 1


func _select(i: int) -> void:
	if i != index:
		index = i
		_sel_ms = Time.get_ticks_msec()


func _move(step: int) -> void:
	_select(wrapi(index + step, 0, _count()))


func _go(to: Page, i: int) -> void:
	page = to
	index = i
	_sel_ms = Time.get_ticks_msec()


func _back() -> void:
	if page == Page.MAIN:
		return
	_go(Page.MAIN, 2 if page == Page.HELP else 1)


func _activate() -> void:
	match page:
		Page.MAIN:
			match index:
				0: _start_game()
				1: _go(Page.HELP, 0)
				2: _go(Page.SETTINGS, 0)
				3: _quit()
		Page.HELP:
			_back()
		Page.SETTINGS:
			if index >= _settings().size():
				_back()
			else:
				_adjust(1)


func _start_game() -> void:
	if _starting:
		return
	_starting = true
	_start_at = _clock()
	_quit_after = -1.0
	if art != null:
		art.exit_slash()


func _quit() -> void:
	_starting = true
	_start_at = _clock()
	_quit_after = _clock() + 0.55
	if art != null:
		art.exit_slash()
	await get_tree().create_timer(0.55).timeout
	get_tree().quit()


# ---------------------------------------------------------------- 设置（本次运行有效；操作方式会记住）

func _settings() -> Array:
	var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	return [
		["主音量", "%d%%" % roundi(_volume * 100.0)],
		["全屏", "开" if full else "关"],
		["操作方式", Factory.scheme_name()],
	]


func _adjust(step: int) -> void:
	if page != Page.SETTINGS or index >= _settings().size():
		return
	match index:
		0:
			_volume = clampf(snappedf(_volume + 0.1 * step, 0.1), 0.0, 1.0)
			AudioServer.set_bus_volume_db(0, linear_to_db(maxf(_volume, 0.0001)))
			AudioServer.set_bus_mute(0, _volume <= 0.0)
		1:
			var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full
					else DisplayServer.WINDOW_MODE_FULLSCREEN)
		2:
			var n: int = Factory.SCHEMES.size()
			var next: String = Factory.SCHEMES[wrapi(Factory.SCHEMES.find(Factory.scheme()) + step, 0, n)]
			Factory.set_scheme(next, DisplayServer.get_name() != "headless")
	_sel_ms = Time.get_ticks_msec()


func _help_rows() -> Array:
	var atk := Factory.key_label("attack")
	var dash := Factory.key_label("dash")
	if Factory.scheme() == Factory.SCHEME_MOUSE:
		dash += " / Shift"
	return [
		["A / D", "移动"], ["W / 空格", "跳（可二段）"], ["S", "从木台跳下"],
		[atk, "攻击 · 空中三连可循环"], ["按住 " + atk, "蓄力，松开释放"],
		["W + " + atk, "跳起上挑"], ["S + " + atk, "空中下砸"],
		["前 + " + atk, "空中横扫（撞墙）"], [dash, "冲刺斩"],
		[Factory.key_label("ranged"), "远射"], [Factory.key_label("parry"), "格挡 / 看准时机弹刀"],
		["R", "大招「绝影」"], ["空格", "取消出招"], ["F5", "重开"], ["Esc", "暂停"],
		["手柄", "A 跳 · X 攻击 · Y 远射 · B 冲刺斩 · RB 弹刀 · RT 大招"],
	]


# ---------------------------------------------------------------- 画

func _ease(since: int, start: float, dur: float) -> float:
	var t := clampf((Time.get_ticks_msec() - since - start) / dur, 0.0, 1.0)
	return 1.0 - pow(1.0 - t, 3.0)


func _text(pos: Vector2, text: String, font: Font, size: int, color: Color, spacing := 0.0,
		align := HORIZONTAL_ALIGNMENT_CENTER) -> float:
	var w := 0.0
	for ch in text:
		w += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + spacing
	w -= spacing
	var x := pos.x
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		x -= w * 0.5
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		x -= w
	for ch in text:
		_canvas.draw_string(font, Vector2(x, pos.y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
		x += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + spacing
	return w


func _diamond(c: Vector2, r: float, color: Color, filled := true) -> void:
	var pts := PackedVector2Array([c + Vector2(0, -r * 1.25), c + Vector2(r, 0), c + Vector2(0, r * 1.25),
			c + Vector2(-r, 0)])
	if filled:
		_canvas.draw_colored_polygon(pts, color)
	else:
		pts.append(pts[0])
		_canvas.draw_polyline(pts, color, 1.0, true)


func _glow(center: Vector2, size: Vector2, color: Color) -> void:
	_canvas.draw_texture_rect(_soft, Rect2(center - size * 0.5, size), false, color)


func _divider(cx: float, y: float, k: float, open_k: float, alpha: float) -> void:
	var half := lerpf(24.0, 188.0, open_k) * k
	if half > 26.0 * k:
		_canvas.draw_line(Vector2(cx - half, y), Vector2(cx - 26.0 * k, y), Color(RULE, alpha), 1.0)
		_canvas.draw_line(Vector2(cx + 26.0 * k, y), Vector2(cx + half, y), Color(RULE, alpha), 1.0)
	_canvas.draw_circle(Vector2(cx - 17.0 * k, y), 1.8 * k, Color(DOT, alpha))
	_canvas.draw_circle(Vector2(cx + 17.0 * k, y), 1.8 * k, Color(DOT, alpha))
	_diamond(Vector2(cx, y), 7.0 * k, Color(VIOLET_LIGHT, alpha * 0.9), false)


func _sweep(x0: float, x1: float, y: float, alpha: float, k: float) -> void:
	var p := _ease(_sel_ms, 0.0, 220.0)
	if p <= 0.0:
		return
	var x := lerpf(x0, x1, p)
	var mid := lerpf(x0, x, 0.55)
	_canvas.draw_polyline_colors(PackedVector2Array([Vector2(x0, y), Vector2(mid, y), Vector2(x, y)]),
			PackedColorArray([Color(SILVER, 0.0), Color(SILVER, 0.75 * alpha),
					Color(VIOLET_LIGHT, (0.9 if p < 1.0 else 0.0) * alpha)]), 1.0, true)
	if p < 1.0:
		_canvas.draw_circle(Vector2(x, y), 1.6 * k, Color(VIOLET_LIGHT, alpha))


func _brackets(vp: Vector2, alpha: float) -> void:
	var inset := 30.0
	var arm := 26.0
	var col := Color(RULE, alpha * 0.5)
	for c in [[Vector2(inset, inset), Vector2(1, 1)], [Vector2(vp.x - inset, inset), Vector2(-1, 1)],
			[Vector2(inset, vp.y - inset), Vector2(1, -1)], [Vector2(vp.x - inset, vp.y - inset), Vector2(-1, -1)]]:
		var p: Vector2 = c[0]
		var d: Vector2 = c[1]
		_canvas.draw_line(p, p + Vector2(arm * d.x, 0), col, 1.0)
		_canvas.draw_line(p, p + Vector2(0, arm * d.y), col, 1.0)


func _draw_ui() -> void:
	_hits.clear()
	var vp := _size()
	var k := clampf(vp.y / 720.0, 0.55, 2.5)
	var cx := vp.x * 0.5
	var clock := _clock()
	var since_mark := clampf((clock - TitleArt.T_MARK) / 1.2, 0.0, 1.0)
	_brackets(vp, 0.25 + 0.55 * since_mark)
	if page == Page.MAIN:
		_divider(cx, 404.0 * k, k, clampf((clock - TitleArt.T_MENU + 0.10) / 0.55, 0.0, 1.0),
				0.55 * clampf((clock - TitleArt.T_MENU + 0.15) / 0.45, 0.0, 1.0))
		var y := 468.0 * k
		for i in MENU.size():
			var appear := clampf((clock - (TitleArt.T_MENU + 0.12 * float(i))) / 0.42, 0.0, 1.0)
			if appear > 0.0:
				_item(cx, y, MENU[i], i, appear, k)
			y += 42.0 * k
		if clock > TitleArt.T_READY:
			var pulse := 0.35 + 0.20 * (0.5 + 0.5 * sin(clock * 1.8))
			_text(Vector2(cx, 634.0 * k), "↑ ↓ 选择　·　Enter 确认", _serif, int(round(12.0 * k)),
					Color(FAINT, pulse), 6.0 * k)
		_footer(vp, k, since_mark)
	elif page == Page.HELP:
		_head(cx, k, "操作说明", "CONTROLS", clock)
		var help := _help_rows()
		var rows := help.size()
		var half := ceili(rows / 2.0)
		for i in rows:
			var col := 0 if i < half else 1
			var row := i - col * half
			var a := clampf((clock - TitleArt.T_READY - 0.05 - 0.02 * float(row)) / 0.25, 0.0, 1.0)
			var x := cx - 320.0 * k + 350.0 * k * float(col)
			var yy := 300.0 * k + 33.0 * k * float(row)
			_text(Vector2(x + 118.0 * k, yy), help[i][0], _serif_bold, int(round(15.0 * k)),
					Color(BONE, a), 1.0 * k, HORIZONTAL_ALIGNMENT_RIGHT)
			_text(Vector2(x + 136.0 * k, yy), help[i][1], _serif, int(round(15.0 * k)),
					Color(MUTE, a), 1.0 * k, HORIZONTAL_ALIGNMENT_LEFT)
		_item(cx, 620.0 * k, "返回", 0, 1.0, k)
		_text(Vector2(cx, 664.0 * k), "当前操作方式：%s（设置里切换）　·　Esc 返回" % Factory.scheme_name(),
				_serif, int(round(12.0 * k)), Color(FAINT, 0.8), 4.0 * k)
	elif page == Page.SETTINGS:
		_head(cx, k, "设置", "SETTINGS", clock)
		var list := _settings()
		var y := 316.0 * k
		for i in list.size():
			_setting_row(cx, y, list[i][0], list[i][1], i, 1.0, k)
			y += 50.0 * k
		_item(cx, y + 6.0 * k, "返回", list.size(), 1.0, k)
		_text(Vector2(cx, 644.0 * k), "← → 调整　·　Esc 返回", _serif, int(round(12.0 * k)),
				Color(FAINT, 0.8), 4.0 * k)
	# 按“开始”之后：先压掉界面，再落黑
	if _starting:
		var e := _clock() - _start_at
		var a := clampf((e - 0.18) / 0.55, 0.0, 1.0)
		if a > 0.0:
			_canvas.draw_rect(Rect2(Vector2.ZERO, vp), Color(INK, a))


func _head(cx: float, k: float, big: String, small: String, clock: float) -> void:
	var a := clampf((clock - TitleArt.T_READY) / 0.4, 0.0, 1.0)
	_text(Vector2(cx, 168.0 * k), big, _serif_bold, int(round(32.0 * k)), Color(BONE, a), 10.0 * k)
	_text(Vector2(cx, 196.0 * k), small, _serif, int(round(13.0 * k)), Color(FAINT, a), 9.0 * k)
	_divider(cx, 220.0 * k, k, a, 0.5 * a)


func _item(cx: float, y: float, label: String, i: int, appear: float, k: float) -> void:
	var sel := i == index
	var font: Font = _serif_bold if sel else _serif
	var size := int(round((23.0 if sel else 21.0) * k))
	var col := BONE if sel else MUTE
	var yy := y + (1.0 - appear) * 9.0 * k
	if sel:
		_glow(Vector2(cx, yy - 9.0 * k), Vector2(300.0 * k, 62.0 * k), Color(0.50, 0.34, 0.92, 0.075 * appear))
	var w := _text(Vector2(cx, yy), label, font, size, Color(col, appear), 11.0 * k)
	_text(Vector2(cx - 158.0 * k, yy), NUMERALS[i] if i < NUMERALS.size() else "",
			_serif, int(round(12.0 * k)), Color(0.30, 0.35, 0.46, 0.85 * appear), 0.0)
	if sel:
		var pop := 1.0 + 0.7 * (1.0 - _ease(_sel_ms, 0.0, 190.0))
		_diamond(Vector2(cx - w * 0.5 - 27.0 * k, yy - 8.0 * k), 4.2 * k * pop, Color(VIOLET, appear))
		_diamond(Vector2(cx + w * 0.5 + 27.0 * k, yy - 8.0 * k), 4.2 * k * pop, Color(VIOLET, appear))
		_sweep(cx - w * 0.5 - 74.0 * k, cx + w * 0.5 + 74.0 * k, yy + 14.0 * k, appear, k)
	_hits.append([Rect2(cx - 200.0 * k, yy - 34.0 * k, 400.0 * k, 52.0 * k), i])


func _setting_row(cx: float, y: float, label: String, value: String, i: int, appear: float, k: float) -> void:
	var sel := i == index
	var font: Font = _serif_bold if sel else _serif
	_text(Vector2(cx - 60.0 * k, y), label, font, int(round(20.0 * k)),
			Color(BONE if sel else MUTE, appear), 6.0 * k, HORIZONTAL_ALIGNMENT_RIGHT)
	_text(Vector2(cx + 60.0 * k, y), value, _digits if value.ends_with("%") else _serif,
			int(round(20.0 * k)), Color(BONE if sel else MUTE, appear), 2.0 * k)
	if sel:
		var pop := 1.0 + 0.7 * (1.0 - _ease(_sel_ms, 0.0, 190.0))
		_diamond(Vector2(cx - 22.0 * k, y - 7.0 * k), 4.0 * k * pop, Color(VIOLET, appear))
		_diamond(Vector2(cx + 150.0 * k, y - 7.0 * k), 4.0 * k * pop, Color(VIOLET, appear))
		_text(Vector2(cx + 4.0 * k, y), "‹", _serif, int(round(22.0 * k)), Color(VIOLET_LIGHT, appear))
		_text(Vector2(cx + 124.0 * k, y), "›", _serif, int(round(22.0 * k)), Color(VIOLET_LIGHT, appear))
		_sweep(cx - 240.0 * k, cx + 240.0 * k, y + 12.0 * k, appear, k)
	_hits.append([Rect2(cx - 260.0 * k, y - 32.0 * k, 520.0 * k, 46.0 * k), i])


func _footer(vp: Vector2, k: float, since_mark: float) -> void:
	var a := clampf((since_mark - 0.55) / 0.9, 0.0, 1.0) * 0.62
	if a <= 0.01:
		return
	var cx := vp.x * 0.5
	_text(Vector2(cx, 664.0 * k), FOOTER, _serif, int(round(12.0 * k)), Color(FAINT, a), 5.0 * k)
	_text(Vector2(64.0 * k, vp.y - 34.0 * k), FOOTER_NOTE, _serif, int(round(11.0 * k)),
			Color(FAINT, a * 0.8), 4.0 * k, HORIZONTAL_ALIGNMENT_LEFT)
	_text(Vector2(vp.x - 64.0 * k, vp.y - 34.0 * k), BUILD, _serif, int(round(11.0 * k)),
			Color(FAINT, a * 0.7), 3.0 * k, HORIZONTAL_ALIGNMENT_RIGHT)
