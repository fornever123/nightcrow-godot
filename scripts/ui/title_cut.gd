extends Control
## 首页（标题画面）——《断晓》· 一刀两断。
##
## 画面全部由代码画：scripts/ui/cut_stage.gd 驱动 assets/shaders/cut_stage.gdshader
## 画墨影和昼光，scripts/ui/cut_wordmark.gd 画被斩开的字标，本文件画菜单与页脚，
## 并负责进场时间轴、输入、页面切换和转场。
##
## 世界观只取它自己的规则：昼光照到的地方时间停住（雨珠悬在半空、光丝凝住），
## 被挤出去的时间沉进脚下的影子里继续流动；斩断光，时间重新开始走。
## 所以画面里没有建筑、没有人物、没有钟表，只有一道凝滞的昼光、一片流着时间的影，
## 和那一刀。

const Stage := preload("res://scripts/ui/cut_stage.gd")
const Word := preload("res://scripts/ui/cut_wordmark.gd")
const Factory := preload("res://scripts/night/player_factory.gd")
const PostShader := preload("res://assets/shaders/cut_post.gdshader")

const GAME_SCENE := "res://scenes/rain_trial.tscn"

# ---------------------------------------------------------------- 时间轴（秒）
const T_LIGHT := 0.72          ## 昼光开始从上面落下来
const T_LIGHT_END := 2.18
const T_DUST := 1.24           ## 光里的雨珠、光尘被冻住
const T_DUST_END := 2.40
const T_MARK := 1.52           ## 字标上半在光里浮现
const T_MARK_END := 2.42
const T_SLASH := 2.62          ## 第一刀
const T_SLASH_LEN := 0.26
const T_MENU := 3.34           ## 菜单浮入
const T_FOOT := 4.30
const T_READY := 5.20

# ---------------------------------------------------------------- 色板
const BONE := Color("e9e4d8")
const SILVER := Color("e6e9ef")
const IDLE := Color("8f99ab")
const FAINT := Color("6d778a")
const RULE := Color("8d96a8")
const DOT := Color("aab2c0")
const VIOLET := Color("9a6cff")
const VIOLET_LIGHT := Color("c8b0ff")
const INK := Color("04050b")

const MENU: Array[String] = ["开始游戏", "操作说明", "设置", "退出游戏"]
const ROMAN: Array[String] = ["Ⅰ", "Ⅱ", "Ⅲ", "Ⅳ"]
const FOOTER := "愿你流血，愿你老去，愿你醒来时，已经在明天"
const FOOTER_NOTE := "黑索司 · 雨港分部"
const PLACE := "夜历六十年 · 雨港"
const BUILD := "v0.1"
const LUX := "LUX  SCISSA"

enum Phase { INTRO, IDLE, GO }
enum Page { MAIN, HELP, SETTINGS }

var stage: ColorRect
var word: Control
var post: ColorRect

var clock := 0.0
var phase := Phase.INTRO
var page := Page.MAIN
var index := 0
var go_t := 0.0
var seek_mode := false
var _ui_fade := 1.0

var _ui: CanvasLayer
var _canvas: Control
var _hits: Array = []
var _sel_ms := 0.0
var _page_ms := 0.0
var _mouse := Vector2.ZERO
var _mouse_target := Vector2.ZERO
var _vp := Vector2(1280, 720)

var _serif: SystemFont
var _serif_bold: SystemFont
var _latin: SystemFont
var _title: SystemFont
var _soft: ImageTexture
var _volume := 1.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vp = get_viewport_rect().size
	_rng.seed = 20261102
	_serif = _sys(["Noto Serif SC", "Source Han Serif SC", "SimSun", "serif"], 400)
	_serif_bold = _sys(["Source Han Serif SC Heavy", "Source Han Serif SC", "Noto Serif SC", "serif"], 900)
	_latin = _sys(["Georgia", "Times New Roman", "serif"], 400)
	_latin.font_italic = true
	_title = _sys(["Old English Text MT", "Noto Serif SC", "serif"], 400)
	_volume = db_to_linear(AudioServer.get_bus_volume_db(0))
	_soft = _make_soft(256, 64)

	stage = ColorRect.new()
	stage.set_script(Stage)
	stage.name = "Stage"
	add_child(stage)

	word = Control.new()
	word.set_script(Word)
	word.name = "Wordmark"
	add_child(word)
	word.cut_y = 302.0
	word.center_x = _vp.x * 0.5
	word.baseline = 352.0
	word.refresh()

	_ui = CanvasLayer.new()
	_ui.name = "Ui"
	_ui.layer = 3
	add_child(_ui)
	_canvas = Control.new()
	_canvas.name = "Canvas"
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.draw.connect(_draw_ui)
	_canvas.gui_input.connect(_on_gui_input)
	_ui.add_child(_canvas)

	var post_layer := CanvasLayer.new()
	post_layer.name = "Post"
	post_layer.layer = 6
	add_child(post_layer)
	post = ColorRect.new()
	post.name = "PostRect"
	post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	post.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	post.color = Color(0, 0, 0, 0)
	var mat := ShaderMaterial.new()
	mat.shader = PostShader
	post.material = mat
	post_layer.add_child(post)

	_sel_ms = Time.get_ticks_msec()
	_page_ms = _sel_ms
	_mouse = _vp * 0.5
	_mouse_target = _mouse
	_apply(0.0)


func _make_soft(w: int, h: int) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))
	for y in h:
		for x in w:
			var u := (float(x) / float(w) - 0.5) * 2.0
			var v := (float(y) / float(h) - 0.5) * 2.0
			var d := sqrt(u * u + v * v)
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = a * a * (3.0 - 2.0 * a)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


func _sys(names: Array, weight: int) -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(names)
	f.font_weight = weight
	return f


# ---------------------------------------------------------------- 时间轴

## 把 clock 换算成画面状态；seek 和正常播放都走这一条。
func _apply(c: float) -> void:
	clock = c
	# 昼光从上面落下来
	stage.clock = c
	stage.fade = smoothstep(0.0, 0.85, c)
	stage.reveal = smoothstep(T_LIGHT, T_LIGHT_END, c)
	stage.dust = smoothstep(T_DUST, T_DUST_END, c)
	stage.cut_y = word.cut_y
	stage.cx_off = 0.0
	stage.drift = 0.0
	stage.breathe = 0.5 + 0.5 * sin(c * 1.35)

	# 第一刀
	var sl0 := T_SLASH - T_SLASH_LEN
	var sl := clampf((c - sl0) / T_SLASH_LEN, 0.0, 1.0)
	var active := c >= sl0 and c <= T_SLASH + 0.10
	stage.slash_x = lerpf(_vp.x * 1.30, -_vp.x * 0.34, _ease_out(sl)) if active else -9999.0
	stage.slash_alpha = (sin(clampf(sl, 0.0, 1.0) * PI) * 1.35) if active else 0.0
	stage.flash = 0.22 * _pulse(c, T_SLASH, 0.10) if phase != Phase.GO else stage.flash

	# 断口
	var cut_k := _spring((c - T_SLASH) / 0.42)
	stage.gap = 18.0 * cut_k
	stage.up_shift = -10.0 * cut_k
	stage.down_shift = 11.5 * cut_k
	stage.upper_amt = 1.0 - 0.16 * smoothstep(T_SLASH + 0.20, 4.20, c)
	stage.lower_amt = 1.0 - 0.45 * smoothstep(T_SLASH + 0.20, 4.30, c)
	stage.leak = maxf(0.0, c - (T_SLASH + 0.08))
	# 断口崩开时的冲击波
	if c >= T_SLASH and c <= T_SLASH + 0.85:
		stage.shock = (c - T_SLASH) / 0.85 * 1.30
		stage.shock_amt = 1.0 - smoothstep(T_SLASH, T_SLASH + 0.85, c) * 0.85
	else:
		stage.shock = -2.0
		stage.shock_amt = 0.0

	# 字标：上半在光里，先出现；下半被斩进影子，稍后浮出
	var mark_k := smoothstep(T_MARK, T_MARK_END, c)
	word.alpha_up = mark_k
	word.alpha_down = mark_k
	word.down_dark = smoothstep(T_SLASH - 0.02, T_SLASH + 0.62, c)
	word.flash = (1.0 - smoothstep(T_SLASH, T_SLASH + 0.22, c)) * (1.0 if c >= T_SLASH else 0.0)
	word.offset_up = Vector2(-2.0, -7.5) * cut_k + Vector2(0, (1.0 - mark_k) * 10.0)
	word.offset_down = Vector2(2.0, 8.5) * cut_k
	word.dim = 0.88 * smoothstep(1.36, 2.50, c)
	word.cut_k = cut_k
	word.glow = smoothstep(1.70, 2.55, c) * (1.0 - 0.55 * cut_k)
	word.refresh()

	# 极慢的整屏漂浮 + 鼠标视差
	var par := Vector2((_mouse.x / maxf(_vp.x, 1.0) - 0.5), (_mouse.y / maxf(_vp.y, 1.0) - 0.5))
	stage.cx_off = -par.x * 26.0
	stage.drift = -par.y * 10.0 + sin(c * 0.42) * 2.0
	stage.push()

	if phase == Phase.GO:
		var g := go_t
		var sl2 := clampf(g / 0.11, 0.0, 1.0)
		stage.slash_x = lerpf(_vp.x * 1.30, -_vp.x * 0.34, _ease_out(sl2)) if g <= 0.16 else -9999.0
		stage.slash_alpha = sin(clampf(sl2, 0.0, 1.0) * PI) * 1.6 if g <= 0.16 else 0.0
		stage.flash = maxf(stage.flash, 0.95 * (1.0 - smoothstep(0.0, 0.085, g)))
		_ui_fade = 1.0 - smoothstep(0.0, 0.16, g)
		stage.ink = smoothstep(0.11, 0.62, g)
		stage.upper_amt *= 1.0 - smoothstep(0.0, 0.45, g)
		stage.lower_amt *= 1.0 - smoothstep(0.0, 0.45, g)
		stage.dust = maxf(0.0, stage.dust - smoothstep(0.0, 0.5, g))
		stage.push()
		word.alpha_up *= 1.0 - smoothstep(0.02, 0.34, g)
		word.alpha_down *= 1.0 - smoothstep(0.06, 0.40, g)
		word.cut_k = cut_k * (1.0 - smoothstep(0.0, 0.30, g))
		word.refresh()

	word.modulate.a = 1.0 if page == Page.MAIN else 0.0
	_canvas.modulate.a = _ui_fade
	_canvas.queue_redraw()


## 被斩断的两截不是平滑归位：先被弹开、再回来一点
func _spring(x: float) -> float:
	var k := clampf(x, 0.0, 1.0)
	return 1.0 - exp(-6.5 * k) * cos(9.2 * k)


func _ease_out(x: float) -> float:
	return 1.0 - pow(1.0 - clampf(x, 0.0, 1.0), 3.0)


func _pulse(c: float, at: float, dur: float) -> float:
	var k := clampf((c - at) / maxf(dur, 0.001), 0.0, 1.0)
	return sin(k * PI)


func _process(delta: float) -> void:
	if not seek_mode:
		if phase == Phase.INTRO:
			clock += delta
			if clock >= T_READY:
				phase = Phase.IDLE
				_sel_ms = Time.get_ticks_msec()
		elif phase == Phase.IDLE:
			clock += delta
		else:
			clock += delta
			go_t += delta
			if go_t >= 0.66:
				phase = Phase.INTRO
				set_process(false)
				get_tree().change_scene_to_file(GAME_SCENE)
				return
	_mouse = _mouse.lerp(_mouse_target, 1.0 - pow(0.0016, delta))
	_apply(clock)


## 截图工具用：把时间轴定到某一秒，关掉自动推进。
func seek(t: float) -> void:
	seek_mode = true
	phase = Phase.IDLE if t >= T_READY else Phase.INTRO
	_apply(t)


# ---------------------------------------------------------------- 输入

func _unhandled_input(event: InputEvent) -> void:
	if seek_mode or phase != Phase.IDLE:
		return
	if event is InputEventMouse:
		return
	if event is InputEventKey:
		if not event.pressed or event.echo:
			return
	elif event is InputEventJoypadButton:
		if not event.pressed:
			return
	elif event is InputEventJoypadMotion:
		if absf(event.axis_value) < 0.6:
			return
	else:
		return
	get_viewport().set_input_as_handled()
	if event.is_action_pressed("ui_up") or event.is_action_pressed("aim_up"):
		_move(-1)
	elif event.is_action_pressed("ui_down") or event.is_action_pressed("move_down"):
		_move(1)
	elif event.is_action_pressed("ui_left"):
		_adjust(-1)
	elif event.is_action_pressed("ui_right"):
		_adjust(1)
	elif event.is_action_pressed("ui_accept") or event.is_action_pressed("attack_light"):
		_activate()
	elif event.is_action_pressed("ui_cancel"):
		_back()


func _on_gui_input(event: InputEvent) -> void:
	if seek_mode or phase != Phase.IDLE:
		return
	if event is InputEventMouseMotion:
		_mouse_target = event.position
		var i := _hit(event.position)
		if i >= 0 and i != index:
			_select(i)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_mouse_target = event.position
			var i := _hit(event.position)
			if i >= 0:
				_select(i)
				_activate()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_back()


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


func _go_page(to: Page, i: int) -> void:
	page = to
	index = i
	_page_ms = Time.get_ticks_msec()
	_sel_ms = _page_ms


func _move(step: int) -> void:
	_select(wrapi(index + step, 0, _count()))


func _back() -> void:
	if page == Page.MAIN:
		return
	_go_page(Page.MAIN, 2 if page == Page.HELP else 3)


func _activate() -> void:
	match page:
		Page.MAIN:
			match index:
				0:
					phase = Phase.GO
					go_t = 0.0
				1:
					_go_page(Page.HELP, 0)
				2:
					_go_page(Page.SETTINGS, 0)
				3:
					get_tree().quit()
		Page.HELP:
			_back()
		Page.SETTINGS:
			if index >= _settings().size():
				_back()
			else:
				_adjust(1)


# ---------------------------------------------------------------- 设置（本次运行有效；操作方式会记住）

func _settings() -> Array:
	var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	return [
		["主音量", "%d%%" % roundi(_volume * 100.0)],
		["全屏", "开" if full else "关"],
		["操作方式", Factory.scheme_name()],
	]


func _help_rows() -> Array:
	var atk := Factory.key_label("attack")
	var dash := Factory.key_label("dash")
	if Factory.scheme() == Factory.SCHEME_MOUSE:
		dash += " / Shift"
	return [
		["A / D", "移动"],
		["W / 空格", "跳（可二段）"],
		["S", "从木台跳下"],
		[atk, "攻击 · 空中三连"],
		["按住 " + atk, "蓄力，松开释放"],
		["W + " + atk, "跳起上挑"],
		["S + " + atk, "空中下砸"],
		[dash, "冲刺斩"],
		[Factory.key_label("ranged"), "远射"],
		[Factory.key_label("parry"), "格挡 / 弹刀"],
		["R", "大招「绝影 · 鸦羽止」"],
		["Esc", "暂停"],
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
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
		2:
			var n: int = Factory.SCHEMES.size()
			var next: String = Factory.SCHEMES[wrapi(Factory.SCHEMES.find(Factory.scheme()) + step, 0, n)]
			Factory.set_scheme(next, DisplayServer.get_name() != "headless")
	_sel_ms = Time.get_ticks_msec()


# ---------------------------------------------------------------- 画界面

func _ease(since: float, start: float, dur: float) -> float:
	var t := clampf((Time.get_ticks_msec() - since - start) / dur, 0.0, 1.0)
	return 1.0 - pow(1.0 - t, 3.0)


## 从 clock 算菜单的出场进度（seek 也能用）
func _intro_k(start: float, dur := 0.42) -> float:
	return _ease_out(clampf((clock - start) / dur, 0.0, 1.0))


func _text(ci: Control, pos: Vector2, text: String, font: Font, size: int, color: Color,
		spacing := 0.0, align := HORIZONTAL_ALIGNMENT_CENTER) -> float:
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
		ci.draw_string(font, Vector2(x, pos.y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
		x += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + spacing
	return w


func _diamond(ci: Control, c: Vector2, r: float, color: Color, filled := true) -> void:
	var pts := PackedVector2Array([c + Vector2(0, -r * 1.3), c + Vector2(r, 0), c + Vector2(0, r * 1.3), c + Vector2(-r, 0)])
	if filled:
		ci.draw_colored_polygon(pts, color)
	else:
		pts.append(pts[0])
		ci.draw_polyline(pts, color, 1.0, true)


func _rule(ci: Control, cx: float, y: float, half: float, alpha: float) -> void:
	if half < 2.0:
		return
	var seg := half * 0.42
	ci.draw_line(Vector2(cx - half, y), Vector2(cx - seg * 0.30, y), Color(RULE, 0.55 * alpha), 1.0)
	ci.draw_line(Vector2(cx + seg * 0.30, y), Vector2(cx + half, y), Color(RULE, 0.55 * alpha), 1.0)
	_diamond(ci, Vector2(cx, y), 2.8, Color(VIOLET_LIGHT, 0.55 * alpha), false)
	ci.draw_circle(Vector2(cx - half, y), 1.1, Color(DOT, 0.40 * alpha))
	ci.draw_circle(Vector2(cx + half, y), 1.1, Color(DOT, 0.40 * alpha))


func _sweep(ci: Control, x0: float, x1: float, y: float, alpha: float) -> void:
	var k := _ease(_sel_ms, 0.0, 260.0)
	if k <= 0.0:
		return
	var x := lerpf(x0, x1, k)
	var mid := lerpf(x0, x, 0.6)
	ci.draw_polyline_colors(PackedVector2Array([Vector2(x0, y), Vector2(mid, y), Vector2(x, y)]),
			PackedColorArray([Color(SILVER, 0.0), Color(SILVER, 0.70 * alpha), Color(VIOLET_LIGHT, (0.9 if k < 1.0 else 0.0) * alpha)]), 1.0, true)
	if k < 1.0:
		ci.draw_circle(Vector2(x, y), 1.7, Color(VIOLET_LIGHT, alpha))


func _draw_ui() -> void:
	_hits.clear()
	_curtain()
	var cx := _vp.x * 0.5
	var ready_k := _intro_k(T_FOOT, 0.55)
	var top_k := _intro_k(T_FOOT - 0.15, 0.45)

	# 页眉：两个极小的角标，其他都留白
	_text(_canvas, Vector2(46, 46), PLACE, _serif, 12, Color(FAINT, 0.92 * top_k), 3.0, HORIZONTAL_ALIGNMENT_LEFT)
	_text(_canvas, Vector2(_vp.x - 46, 46), BUILD, _latin, 12, Color(FAINT, 0.72 * top_k), 2.0, HORIZONTAL_ALIGNMENT_RIGHT)

	match page:
		Page.MAIN:
			_main_page(cx, ready_k)
		Page.HELP:
			_help_page(cx)
		Page.SETTINGS:
			_settings_page(cx)


## 上下的暗幕：让字标和菜单从光影里浮出来，也把画面收成电影画幅
func _curtain() -> void:
	var steps := 26
	# 翻页时把整屏压暗，让字标退到背景里（字标本帧会被 modulate 关掉，这里再加一层）
	if page != Page.MAIN:
		_canvas.draw_rect(Rect2(0, 0, _vp.x, _vp.y), Color(0.004, 0.005, 0.011, 0.58))
	# 底部：影更重，菜单压在影上
	var y0 := _vp.y * 0.58
	var h := (_vp.y - y0) / float(steps)
	for i in steps:
		var k := float(i) / float(steps - 1)
		_canvas.draw_rect(Rect2(0, y0 + h * i, _vp.x, h + 1.5), Color(0.004, 0.005, 0.011, pow(k, 1.85) * 0.52))
	# 顶部：收一点，像片头的黑边
	var h2 := _vp.y * 0.16 / float(steps)
	for i in steps:
		var k := 1.0 - float(i) / float(steps - 1)
		_canvas.draw_rect(Rect2(0, h2 * i, _vp.x, h2 + 1.5), Color(0.004, 0.005, 0.011, pow(k, 2.2) * 0.46))


func _main_page(cx: float, foot_k: float) -> void:
	# 字标下面：拉丁小字 + 一条银线（就是断口那条线往下延伸的一小段）
	var latin_k := _intro_k(T_FOOT - 0.10, 0.5)
	var line_half := 118.0 * _intro_k(T_FOOT - 0.05, 0.55)
	var y := 412.0
	_text(_canvas, Vector2(cx, y), LUX, _latin, 13, Color(IDLE, 0.72 * latin_k), 10.0)
	_rule(_canvas, cx, y + 17.0, line_half, latin_k)

	# 光从字标上扫过去（进场时一次）
	var sweep_k := clampf((clock - 2.02) / 0.88, 0.0, 1.0)
	if sweep_k > 0.0 and sweep_k < 1.0 and phase != Phase.GO:
		var sx := lerpf(-380.0, _vp.x + 380.0, _ease_out(sweep_k))
		_canvas.draw_set_transform(Vector2(sx, 298.0), deg_to_rad(-7.0), Vector2(1, 1))
		_canvas.draw_texture_rect(_soft, Rect2(-470, -36, 940, 72), false,
				Color(1.0, 0.96, 0.88, 0.17 * sin(sweep_k * PI)))
		_canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2(1, 1))

	# 菜单
	var y0 := 474.0
	for i in MENU.size():
		var k := _intro_k(T_MENU + 0.055 * i, 0.40)
		_item(cx, y0 + 47.0 * i + (1.0 - k) * 9.0, MENU[i], i, k)

	# 页脚：誓词
	var fy := _vp.y - 48.0
	_text(_canvas, Vector2(cx, fy), FOOTER, _serif_bold, 11, Color(FAINT, 0.80 * foot_k), 3.0)
	_text(_canvas, Vector2(cx, fy + 18.0), FOOTER_NOTE, _serif, 10, Color(FAINT, 0.55 * foot_k), 4.0)


func _item(cx: float, y: float, label: String, i: int, alpha: float) -> void:
	if alpha <= 0.002:
		return
	var sel := i == index
	var f: Font = _serif_bold if sel else _serif
	var size := 23 if sel else 21
	var color := Color(BONE, alpha) if sel else Color(IDLE, 0.92 * alpha)
	var w := _text(_canvas, Vector2(cx, y), label, f, size, color, 9.0)
	if sel:
		var pop := 1.0 + 0.7 * (1.0 - _ease(_sel_ms, 0.0, 220.0))
		# 选中项背后一团很淡的柔光（用软斑纹理，没有硬边）
		_canvas.draw_texture_rect(_soft, Rect2(cx - 210.0, y - 32.0, 420.0, 68.0), false,
				Color(0.52, 0.66, 1.0, 0.165 * alpha))
		_diamond(_canvas, Vector2(cx - w * 0.5 - 24, y - 8), 3.4 * pop, Color(VIOLET, alpha))
		_diamond(_canvas, Vector2(cx + w * 0.5 + 24, y - 8), 3.4 * pop, Color(VIOLET, alpha))
		_sweep(_canvas, cx - w * 0.5 - 34.0, cx + w * 0.5 + 34.0, y + 12.0, alpha)
	_hits.append([Rect2(cx - 150, y - 33, 300, 46), i])


func _heading(cx: float, big: String, small: String, y: float) -> void:
	var k := _ease(_page_ms, 0.0, 240.0)
	_text(_canvas, Vector2(cx, y + 2), big, _serif_bold, 36, Color("6b7486", k), 4.0)
	_text(_canvas, Vector2(cx, y), big, _serif_bold, 36, Color(SILVER, k), 4.0)
	_text(_canvas, Vector2(cx, y + 30), small, _serif_bold, 12, Color(IDLE, 0.8 * k), 14.0)
	_rule(_canvas, cx, y + 66.0, 190.0 * _ease(_page_ms, 60.0, 360.0), k)


func _help_page(cx: float) -> void:
	_heading(cx, "操作说明", "CONTROLS", 148.0)
	var rows := _help_rows()
	var half := ceili(rows.size() / 2.0)
	for i in rows.size():
		var col := 0 if i < half else 1
		var row := i - col * half
		var k := _ease(_page_ms, 90.0 + 16.0 * row, 200.0)
		var x := cx - 330.0 + 384.0 * col
		_text(_canvas, Vector2(x + 112, 292.0 + 35.0 * row + (1.0 - k) * 6.0), rows[i][0], _serif_bold, 16,
				Color(BONE, k), 1.0, HORIZONTAL_ALIGNMENT_RIGHT)
		_text(_canvas, Vector2(x + 138, 292.0 + 35.0 * row + (1.0 - k) * 6.0), rows[i][1], _serif, 16,
				Color(IDLE, k), 1.0, HORIZONTAL_ALIGNMENT_LEFT)
	_item(cx, 610.0, "返回", 0, _ease(_page_ms, 180.0, 220.0))
	_text(_canvas, Vector2(cx, 650.0), "Esc / 手柄 B 返回", _serif, 11, Color(FAINT, 0.6 * _ease(_page_ms, 240.0, 200.0)), 3.0)


func _settings_page(cx: float) -> void:
	_heading(cx, "设置", "SETTINGS", 148.0)
	var list := _settings()
	for i in list.size():
		var k := _ease(_page_ms, 90.0 + 45.0 * i, 220.0)
		_setting_row(cx, 330.0 + 56.0 * i + (1.0 - k) * 8.0, list[i][0], list[i][1], i, k)
	_item(cx, 330.0 + 56.0 * list.size() + 26.0, "返回", list.size(), _ease(_page_ms, 90.0 + 45.0 * list.size(), 220.0))
	_text(_canvas, Vector2(cx, 650.0), "← → 调整　·　Esc 返回　·　操作方式会记住", _serif, 11, Color(FAINT, 0.6 * _ease(_page_ms, 300.0, 220.0)), 3.0)


func _setting_row(cx: float, y: float, label: String, value: String, i: int, alpha: float) -> void:
	var sel := i == index
	if sel:
		_canvas.draw_texture_rect(_soft, Rect2(cx - 250.0, y - 30.0, 500.0, 64.0), false,
				Color(0.52, 0.66, 1.0, 0.150 * alpha))
	_text(_canvas, Vector2(cx - 34, y), label, _serif_bold if sel else _serif, 20, Color(BONE if sel else IDLE, alpha), 6.0,
			HORIZONTAL_ALIGNMENT_RIGHT)
	var vx := cx + 56.0
	var vw := _text(_canvas, Vector2(vx, y), value, _serif_bold if sel else _serif, 20,
			Color(BONE if sel else IDLE, alpha), 2.0, HORIZONTAL_ALIGNMENT_LEFT)
	if sel:
		var pop := 1.0 + 0.7 * (1.0 - _ease(_sel_ms, 0.0, 200.0))
		_diamond(_canvas, Vector2(cx + 22.0, y - 7), 3.4 * pop, Color(VIOLET, alpha))
		_text(_canvas, Vector2(vx - 20.0, y), "‹", _serif, 21, Color(VIOLET_LIGHT, alpha))
		_text(_canvas, Vector2(vx + vw + 18.0, y), "›", _serif, 21, Color(VIOLET_LIGHT, alpha))
	_hits.append([Rect2(cx - 250, y - 32, 500, 46), i])
