extends CanvasLayer
## 雨街试玩的暂停菜单（UI 方向 A「铁艺」，样图 docs/视觉设计/UI/方向样图_20261031/A-pause.png）。
## Esc 打开 / 关闭；主菜单：继续 / 重新开始 / 操作说明 / 设置 / 退出游戏。
## 全部用 _draw 画（和 combat_hud.gd 一样没有图片资源）。世界暂停后本节点仍运行。
## 10-31 加料（用户选 ④⑤）：背景虚化 + 菜单自己一层慢雨（世界停了雨不停）；
## 打开时标题浮出、分隔线从中间展开、选项依次浮出；选中项底下银线划过；翻页淡入；关闭时淡出。
## 设置会存盘：主音量、全屏和首页共用 user://settings.cfg；操作方式由 player_factory 存进 user://controls.cfg；底部提示、伤害数字只在本次运行有效。

const Factory := preload("res://scripts/night/player_factory.gd")
const GothicFonts := preload("res://scripts/ui/gothic_fonts.gd")
const INK := Color(0.024, 0.031, 0.051)
const SILVER := Color("e6e9ef")
const BONE := Color("e9e4d8")
const IDLE := Color("8f99ab")
const STEEL := Color("7f8ba0")
const FAINT := Color("6d778a")
const RULE := Color("8d96a8")
const DOT := Color("aab2c0")
const VIOLET := Color("9a6cff")
const VIOLET_LIGHT := Color("c8b0ff")
const RAIN := Color(0.52, 0.58, 0.68)   ## 11-01 用户：“暂停界面雨要压暗”（原 0.78, 0.83, 0.91）
const ROMAN: Array[String] = ["Ⅰ", "Ⅱ", "Ⅲ", "Ⅳ", "Ⅴ", "Ⅵ"]
const FADE_MS := 180.0            ## 打开：压暗 / 虚化淡入
const CLOSE_MS := 140.0           ## 关闭：世界马上恢复，菜单这段时间里淡出
const SWEEP_MS := 220.0           ## 选中项银线划过
const PAGE_MS := 160.0            ## 翻页淡入
const RAIN_DROPS := 170
const RAIN_SLANT := -0.22         ## 雨丝每往下 1 像素往左偏多少
const RAIN_SPEED := Vector2(380.0, 620.0)   ## 像素/秒，比游戏里的雨慢

enum Page { MAIN, HELP, SETTINGS }

const MAIN_ITEMS: Array[String] = ["继续", "重新开始", "操作说明", "设置", "回到标题", "退出游戏"]
const TITLE_SCENE := "res://scenes/yg_title_zhanzhong.tscn"   ## 首页线的标题画面《斩钟》（11-05 请我们加“回到标题”，11-15 从断光改到斩钟）
const SETTINGS_CFG := "user://settings.cfg"   ## 和首页共用：[audio] master 0..1、[display] fullscreen
## 键位以 scripts/night/player_factory.gd 为准；攻击 / 远射 / 弹刀 / 冲刺斩随操作方式（键盘 / 键鼠）变，见 _help_rows()
const HELP_PAD := "手柄：A 跳 · X 攻击 · Y 远射 · B 冲刺斩 · RB 弹刀 · RT 大招 · Start 暂停 · Back 重开"

var stage: Node                    ## rain_trial.gd，读封印进度 / 用时，重新开始也交给它

var page := Page.MAIN
var index := 0
var opened := false
var _closing := false
var _open_ms := 0.0
var _close_ms := 0.0
var _sel_ms := 0.0
var _page_ms := 0.0
var _last_us := 0
var _canvas: Control
var _rain: Control
var _dim: ColorRect
var _drops: Array = []             ## [Vector2 位置, 长度, 透明度, 速度, 粗细]
var _hits: Array = []              ## 本帧画出来的可点区域 [Rect2, index]
var _title_font: Font
var _serif: Font
var _serif_bold: Font
var _digits: Font
var _volume := 1.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	layer = 28                     # HUD 10 之上，试玩结算页 30 之下
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_title_font = GothicFonts.blackletter(700)
	_serif = GothicFonts.serif(450)
	_serif_bold = GothicFonts.cinzel(800, false, 900)   # 西文/数字走石刻 Cinzel，中文走思源重宋 900
	_digits = GothicFonts.digits(600, true)
	_load_shared_settings()
	_volume = db_to_linear(AudioServer.get_bus_volume_db(0))
	_dim = ColorRect.new()
	_dim.name = "Dim"
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var mat := ShaderMaterial.new()
	mat.shader = _backdrop_shader()
	_dim.material = mat
	add_child(_dim)
	_rain = Control.new()
	_rain.name = "Rain"
	_rain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rain.draw.connect(_draw_rain)
	add_child(_rain)
	_canvas = Control.new()
	_canvas.name = "Menu"
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas.draw.connect(_draw_menu)
	_canvas.gui_input.connect(_on_gui_input)
	add_child(_canvas)
	_rng.seed = 7


func _backdrop_shader() -> Shader:
	# 底下的画面先虚化、去掉一点饱和，再按椭圆压暗（中间偏上 0.68、四周 0.94）
	var s := Shader.new()
	s.code = """shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec4 ink : source_color = vec4(0.024, 0.031, 0.051, 1.0);
uniform float fade = 1.0;
uniform float blur_lod = 2.0;
void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE * 4.0;
	vec3 b = textureLod(screen_tex, SCREEN_UV, blur_lod).rgb * 4.0;
	b += textureLod(screen_tex, SCREEN_UV + vec2(px.x, 0.0), blur_lod).rgb * 2.0;
	b += textureLod(screen_tex, SCREEN_UV - vec2(px.x, 0.0), blur_lod).rgb * 2.0;
	b += textureLod(screen_tex, SCREEN_UV + vec2(0.0, px.y), blur_lod).rgb * 2.0;
	b += textureLod(screen_tex, SCREEN_UV - vec2(0.0, px.y), blur_lod).rgb * 2.0;
	b += textureLod(screen_tex, SCREEN_UV + px, blur_lod).rgb;
	b += textureLod(screen_tex, SCREEN_UV - px, blur_lod).rgb;
	b += textureLod(screen_tex, SCREEN_UV + vec2(px.x, -px.y), blur_lod).rgb;
	b += textureLod(screen_tex, SCREEN_UV + vec2(-px.x, px.y), blur_lod).rgb;
	b /= 16.0;
	b = mix(vec3(dot(b, vec3(0.299, 0.587, 0.114))), b, 0.75);
	vec3 sharp = textureLod(screen_tex, SCREEN_UV, 0.0).rgb;
	vec2 d = (UV - vec2(0.5, 0.45)) * vec2(1.0, 0.9);
	float a = mix(0.68, 0.94, smoothstep(0.0, 0.62, length(d)));
	COLOR = vec4(mix(mix(sharp, b, fade), ink.rgb, a * fade), 1.0);
}"""
	return s


# ---------------------------------------------------------------- 开关

func can_open() -> bool:
	if opened or get_tree().paused:
		return false
	return stage == null or stage.get("trial_completed") != true    # 雨街无限场景没有这个字段


func open() -> void:
	if not can_open():
		return
	opened = true
	_closing = false
	page = Page.MAIN
	index = 0
	_open_ms = Time.get_ticks_msec()
	_sel_ms = _open_ms + 260.0     # 第一道银线等“继续”浮出来再划
	_page_ms = 0.0
	_last_us = Time.get_ticks_usec()
	if _drops.is_empty():
		_seed_rain()
	visible = true
	_set_hud(false)                # 暂停时收起战斗 HUD，菜单底下只留虚化压暗的街景
	get_tree().paused = true
	_canvas.queue_redraw()


func close() -> void:
	if not opened:
		return
	opened = false
	_closing = true
	_close_ms = Time.get_ticks_msec()
	_set_hud(true)
	get_tree().paused = false


func _set_hud(on: bool) -> void:
	if stage != null and stage.get("hud") != null:
		stage.hud.visible = on


func _fade() -> float:
	var now := Time.get_ticks_msec()
	if _closing:
		return 1.0 - clampf((now - _close_ms) / CLOSE_MS, 0.0, 1.0)
	return clampf((now - _open_ms) / FADE_MS, 0.0, 1.0)


func _process(_delta: float) -> void:
	if not opened and not _closing:
		return
	var k := _fade()
	if _closing and k <= 0.0:
		_closing = false
		visible = false
		return
	_dim.material.set_shader_parameter("fade", k)
	_canvas.modulate.a = k
	_rain.modulate.a = k
	# 用真实时间推雨，不受大招 / 顿帧改的 time_scale 影响
	var now_us := Time.get_ticks_usec()
	var dt := minf((now_us - _last_us) / 1000000.0, 0.05)
	_last_us = now_us
	_step_rain(dt)
	_rain.queue_redraw()
	_canvas.queue_redraw()


# ---------------------------------------------------------------- 雨

func _seed_rain() -> void:
	var vp := get_viewport().get_visible_rect().size
	_drops.clear()
	for i in RAIN_DROPS:
		_drops.append([Vector2(_rng.randf_range(-30.0, vp.x + 160.0), _rng.randf_range(-40.0, vp.y)),
				_rng.randf_range(10.0, 32.0), _rng.randf_range(0.08, 0.28),
				_rng.randf_range(RAIN_SPEED.x, RAIN_SPEED.y), 1.2 if _rng.randf() < 0.2 else 0.7])


func _step_rain(dt: float) -> void:
	var vp := get_viewport().get_visible_rect().size
	for d in _drops:
		var p: Vector2 = d[0]
		p += Vector2(RAIN_SLANT, 1.0) * d[3] * dt
		if p.y > vp.y + 40.0:
			p = Vector2(_rng.randf_range(-30.0, vp.x + 160.0), _rng.randf_range(-60.0, -20.0))
		d[0] = p


func _draw_rain() -> void:
	for d in _drops:
		var p: Vector2 = d[0]
		var l: float = d[1]
		_rain.draw_line(p, p + Vector2(RAIN_SLANT * l, l), Color(RAIN, d[2]), d[4], true)


# ---------------------------------------------------------------- 输入

func _unhandled_input(event: InputEvent) -> void:
	if not opened:
		if event.is_action_pressed("ui_cancel") and not event.is_echo() and can_open():
			get_viewport().set_input_as_handled()
			open()
		return
	if not (event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion):
		return
	get_viewport().set_input_as_handled()
	if not event.is_pressed():
		return
	# 手柄 B 不在 ui_cancel 里（战斗里 B 是冲刺斩），菜单打开时单独当返回
	var pad_back: bool = event is InputEventJoypadButton and event.button_index == JOY_BUTTON_B
	if (event.is_action_pressed("ui_cancel") or pad_back) and not event.is_echo():
		_back()
	elif event.is_action_pressed("ui_up", true) or event.is_action_pressed("aim_up", true):
		_move(-1)
	elif event.is_action_pressed("ui_down", true) or event.is_action_pressed("move_down", true):
		_move(1)
	elif event.is_action_pressed("ui_left", true) or event.is_action_pressed("move_left", true):
		_adjust(-1)
	elif event.is_action_pressed("ui_right", true) or event.is_action_pressed("move_right", true):
		_adjust(1)
	elif (event.is_action_pressed("ui_accept") or event.is_action_pressed("attack_light")) and not event.is_echo():
		_activate()


func _on_gui_input(event: InputEvent) -> void:
	if not opened:
		return
	if event is InputEventMouseMotion:
		var i := _hit(event.position)
		if i >= 0 and i != index:
			_select(i)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var i := _hit(event.position)
		if i >= 0:
			_select(i)
			_activate()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_back()


func _hit(pos: Vector2) -> int:
	for h in _hits:
		if (h[0] as Rect2).has_point(pos):
			return h[1]
	return -1


func _count() -> int:
	match page:
		Page.MAIN:
			return MAIN_ITEMS.size()
		Page.SETTINGS:
			return _settings().size() + 1   # 最后一项“返回”
	return 1


func _select(i: int) -> void:
	if i != index:
		index = i
		_sel_ms = Time.get_ticks_msec()


func _go(to: Page, i: int) -> void:
	page = to
	index = i
	_page_ms = Time.get_ticks_msec()
	_sel_ms = _page_ms


func _move(step: int) -> void:
	_select(wrapi(index + step, 0, _count()))


func _back() -> void:
	if page == Page.MAIN:
		close()
	else:
		_go(Page.MAIN, 2 if page == Page.HELP else 3)


func _activate() -> void:
	match page:
		Page.MAIN:
			match index:
				0: close()
				1: _restart()
				2: _go(Page.HELP, 0)
				3: _go(Page.SETTINGS, 0)
				4: _to_title()
				5: _quit_game()
		Page.HELP:
			_back()
		Page.SETTINGS:
			if index >= _settings().size():
				_back()
			else:
				_adjust(1)


func _silence_stage_audio() -> void:
	var root_target: Node = stage if stage != null else (get_tree().current_scene if get_tree() != null else null)
	if stage != null:
		var audio: Node = stage.get("audio")
		if audio != null:
			audio.set("enabled", false)
			audio.set_process(false)
			audio.set_physics_process(false)
			if audio.has_method("stop_all"):
				audio.stop_all()
			var voices = audio.get("_voices")
			if voices is Dictionary:
				voices.clear()
		var ult_fx: Node = stage.get("ult_fx")
		if ult_fx != null:
			ult_fx.set_process(false)
			ult_fx.set_physics_process(false)
			if ult_fx.has_method("clear"):
				ult_fx.clear()
	if root_target != null:
		_stop_media_players_recursive(root_target)


func _stop_media_players_recursive(node: Node) -> void:
	if node is AudioStreamPlayer:
		var ap := node as AudioStreamPlayer
		ap.stop()
		ap.stream = null
	elif node is AudioStreamPlayer2D:
		var ap2 := node as AudioStreamPlayer2D
		ap2.stop()
		ap2.stream = null
	elif node is AudioStreamPlayer3D:
		var ap3 := node as AudioStreamPlayer3D
		ap3.stop()
		ap3.stream = null
	elif node is VideoStreamPlayer:
		var vp := node as VideoStreamPlayer
		vp.stop()
		vp.stream = null
	for child in node.get_children():
		_stop_media_players_recursive(child)


func _to_title() -> void:
	opened = false
	_closing = false
	_silence_stage_audio()
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file.call_deferred(TITLE_SCENE)


func _quit_game() -> void:
	opened = false
	_closing = false
	_silence_stage_audio()
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().quit()


## 主音量、全屏和首页共用 user://settings.cfg；无头测试不读不写，免得动到玩家的设置
func _load_shared_settings() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_CFG) != OK:
		return
	if cfg.has_section_key("audio", "master"):
		var v := clampf(float(cfg.get_value("audio", "master")), 0.0, 1.0)
		AudioServer.set_bus_volume_db(0, linear_to_db(maxf(v, 0.0001)))
		AudioServer.set_bus_mute(0, v <= 0.0)
	if cfg.has_section_key("display", "fullscreen"):
		var want := bool(cfg.get_value("display", "fullscreen"))
		var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		if want != full:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if want else DisplayServer.WINDOW_MODE_WINDOWED)


func _save_shared_setting(section: String, key: String, value: Variant) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_CFG)
	cfg.set_value(section, key, value)
	cfg.save(SETTINGS_CFG)


func _restart() -> void:
	opened = false
	_closing = false
	_silence_stage_audio()
	if stage != null and stage.has_method("_restart_trial"):
		stage._restart_trial()
	else:
		get_tree().paused = false
		Engine.time_scale = 1.0
		get_tree().reload_current_scene.call_deferred()


# ---------------------------------------------------------------- 设置（音量、全屏存 user://settings.cfg，操作方式存 user://controls.cfg）

func _settings() -> Array:
	var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	var hud = stage.get("hud") if stage != null else null
	var fx = stage.get("fx") if stage != null else null
	return [
		["主音量", "%d%%" % roundi(_volume * 100.0)],
		["全屏", "开" if full else "关"],
		["底部操作提示", "开" if hud != null and hud.help_visible else "关"],
		["伤害数字", "开" if fx != null and fx.damage_numbers_enabled else "关"],
		["操作方式", Factory.scheme_name()],
	]


## 操作说明：攻击 / 远射 / 弹刀 / 冲刺斩按当前方案只显示一种（战斗线 11-01：键盘和键鼠二选一，默认键盘）
## 11-03：冲刺斩改成双击 A / D（战斗线通知），Shift / 右键仍能出，页上只写主键位
func _help_rows() -> Array:
	var atk := Factory.key_label("attack")
	var dash := Factory.key_label("dash")
	return [
		["A / D", "移动"], ["W / 空格", "跳（可二段）"], ["S", "从木台跳下"],
		[atk, "攻击 · 空中三连可循环"], ["按住 " + atk, "蓄力，松开释放"], ["W + " + atk, "跳起上挑"],
		["S + " + atk, "空中下砸"], ["前 + " + atk, "空中横扫（撞墙）"], [dash, "冲刺斩"],
		[Factory.key_label("ranged"), "远射"], [Factory.key_label("parry"), "格挡 / 看准时机弹刀"], ["R", "大招「绝影」"],
		["空格", "取消出招"], ["H", "隐藏底部操作提示"], ["F5", "重开"], ["Esc", "暂停"],
	]


func _adjust(step: int) -> void:
	if page != Page.SETTINGS or index >= _settings().size():
		return
	match index:
		0:
			_volume = clampf(snappedf(_volume + 0.1 * step, 0.1), 0.0, 1.0)
			AudioServer.set_bus_volume_db(0, linear_to_db(maxf(_volume, 0.0001)))
			AudioServer.set_bus_mute(0, _volume <= 0.0)
			_save_shared_setting("audio", "master", _volume)
		1:
			var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
			_save_shared_setting("display", "fullscreen", not full)
		2:
			if stage != null and stage.get("hud") != null:
				stage.hud.help_visible = not stage.hud.help_visible
		3:
			if stage != null and stage.get("fx") != null:
				stage.fx.damage_numbers_enabled = not stage.fx.damage_numbers_enabled
		4:
			var n: int = Factory.SCHEMES.size()
			var next: String = Factory.SCHEMES[wrapi(Factory.SCHEMES.find(Factory.scheme()) + step, 0, n)]
			# 无头测试不写玩家的 controls.cfg（scheme() 在无头下也不读它）
			Factory.set_scheme(next, DisplayServer.get_name() != "headless")
			if stage != null and stage.has_method("apply_control_scheme"):
				stage.apply_control_scheme()
	_sel_ms = Time.get_ticks_msec()


# ---------------------------------------------------------------- 画

## 从 start 毫秒开始、持续 dur 毫秒的缓出进度（0..1）
func _ease(since: float, start: float, dur: float) -> float:
	var t := clampf((Time.get_ticks_msec() - since - start) / dur, 0.0, 1.0)
	return 1.0 - pow(1.0 - t, 3.0)


func _text(pos: Vector2, text: String, font: Font, size: int, color: Color, spacing: float = 0.0,
		align := HORIZONTAL_ALIGNMENT_CENTER) -> float:
	## 带字距的单行字；返回宽度。居中时以 pos.x 为中心。
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
	var pts := PackedVector2Array([c + Vector2(0, -r * 1.25), c + Vector2(r, 0), c + Vector2(0, r * 1.25), c + Vector2(-r, 0)])
	if filled:
		_canvas.draw_colored_polygon(pts, color)
	else:
		pts.append(pts[0])
		_canvas.draw_polyline(pts, color, 1.0, true)


func _divider(cx: float, y: float, open_k: float, alpha: float) -> void:
	# 铁艺分隔线：两段细线从中间往两边展开 + 两颗铆钉 + 中间紫色空心菱形
	var half := lerpf(30.0, 180.0, open_k)
	if half > 31.0:
		_canvas.draw_line(Vector2(cx - half, y), Vector2(cx - 30, y), Color(RULE, alpha), 1.0)
		_canvas.draw_line(Vector2(cx + 30, y), Vector2(cx + half, y), Color(RULE, alpha), 1.0)
	_canvas.draw_circle(Vector2(cx - 20, y), 2.0, Color(DOT, alpha))
	_canvas.draw_circle(Vector2(cx + 20, y), 2.0, Color(DOT, alpha))
	_diamond(Vector2(cx, y), 8.0, Color(VIOLET_LIGHT, alpha), false)


func _heading(cx: float, big: String, small: String, big_font: Font, big_size: int, y: float, since: float) -> void:
	var k := _ease(since, 0.0, 240.0)
	var yy := y + (1.0 - k) * 10.0
	_text(Vector2(cx, yy + 2), big, big_font, big_size, Color("6b7486", k), 2.0)
	_text(Vector2(cx, yy), big, big_font, big_size, Color(SILVER, k), 2.0)
	_text(Vector2(cx, yy + 34), small, _serif_bold, 14, Color(STEEL, k), 12.0)
	_divider(cx, y + 76, _ease(since, 80.0, 380.0), _ease(since, 40.0, 160.0))


## 选中项底下的银线：从左往右划过去，然后留着；线头带一点紫
func _sweep(x0: float, x1: float, y: float, alpha: float) -> void:
	var k := _ease(_sel_ms, 0.0, SWEEP_MS)
	if k <= 0.0:
		return
	var x := lerpf(x0, x1, k)
	var mid := lerpf(x0, x, 0.55)
	var pts := PackedVector2Array([Vector2(x0, y), Vector2(mid, y), Vector2(x, y)])
	var cols := PackedColorArray([Color(SILVER, 0.0), Color(SILVER, 0.75 * alpha), Color(VIOLET_LIGHT, (0.9 if k < 1.0 else 0.0) * alpha)])
	_canvas.draw_polyline_colors(pts, cols, 1.0, true)
	if k < 1.0:
		_canvas.draw_circle(Vector2(x, y), 1.6, Color(VIOLET_LIGHT, alpha))


func _draw_menu() -> void:
	_hits.clear()
	var vp := _canvas.get_viewport_rect().size
	var cx := vp.x * 0.5
	var since := _open_ms if _page_ms <= 0.0 else _page_ms
	match page:
		Page.MAIN:
			_heading(cx, "Intermissio", "暂停", _title_font, 64, 206, since)
			var y := 352.0
			for i in MAIN_ITEMS.size():
				var k := _ease(since, 140.0 + 45.0 * i, 220.0)
				_item(cx, y + (1.0 - k) * 8.0, MAIN_ITEMS[i], i, k)
				y += 46.0
			_text(Vector2(cx, 625), _footer(), _serif_bold, 13, Color(FAINT, _ease(since, 380.0, 240.0)), 3.0)
		Page.HELP:
			_heading(cx, "操作说明", "CONTROLS", _serif_bold, 34, 150, since)
			var help := _help_rows()
			var rows := help.size()
			var half := ceili(rows / 2.0)
			for i in rows:
				var col := 0 if i < half else 1
				var row := i - col * half
				var k := _ease(since, 100.0 + 18.0 * row, 200.0)
				var x := cx - 300.0 + 330.0 * col
				var yy := 290.0 + 34.0 * row + (1.0 - k) * 6.0
				_text(Vector2(x + 120, yy), help[i][0], _serif_bold, 16, Color(BONE, k), 1.0, HORIZONTAL_ALIGNMENT_RIGHT)
				_text(Vector2(x + 140, yy), help[i][1], _serif, 16, Color(IDLE, k), 1.0, HORIZONTAL_ALIGNMENT_LEFT)
			# 战斗线 11-02 的规则（地面招式不再给跳），一行脚注，不占格子
			var atk := Factory.key_label("attack")
			_text(Vector2(cx, 290.0 + 34.0 * half - 6.0), "空中 %s 每打中一下 · W + %s 上挑、空中冲刺斩 也各给一次空中跳" % [atk, atk], _serif, 13,
					Color(FAINT, _ease(since, 240.0, 200.0)), 2.0)
			_text(Vector2(cx, 290.0 + 34.0 * half + 16.0), HELP_PAD, _serif, 13,
					Color(FAINT, _ease(since, 250.0, 200.0)), 2.0)
			_item(cx, 610.0, "返回", 0, _ease(since, 260.0, 200.0))
			_text(Vector2(cx, 648), "当前操作方式：%s（设置里切换）　·　Esc / 手柄 B 返回" % Factory.scheme_name(), _serif, 13, Color(FAINT, _ease(since, 300.0, 200.0)), 3.0)
		Page.SETTINGS:
			_heading(cx, "设置", "SETTINGS", _serif_bold, 34, 150, since)
			var list := _settings()
			var y := 300.0
			for i in list.size():
				var k := _ease(since, 120.0 + 45.0 * i, 220.0)
				_setting_row(cx, y + (1.0 - k) * 8.0, list[i][0], list[i][1], i, k)
				y += 52.0
			_item(cx, y + 12.0, "返回", list.size(), _ease(since, 120.0 + 45.0 * list.size(), 220.0))
			_text(Vector2(cx, 640), "← → 调整　·　Esc 返回　·　音量、全屏、操作方式会记住", _serif, 13, Color(FAINT, _ease(since, 380.0, 240.0)), 3.0)


func _item(cx: float, y: float, label: String, i: int, alpha: float) -> void:
	var sel := i == index
	var w := _text(Vector2(cx, y), label, _serif_bold if sel else _serif, 22, Color(BONE if sel else IDLE, alpha), 10.0)
	if sel:
		var pop := 1.0 + 0.6 * (1.0 - _ease(_sel_ms, 0.0, 180.0))
		_diamond(Vector2(cx - w * 0.5 - 22, y - 8), 4.0 * pop, Color(VIOLET, alpha))
		_diamond(Vector2(cx + w * 0.5 + 22, y - 8), 4.0 * pop, Color(VIOLET, alpha))
		_sweep(cx - w * 0.5 - 60.0, cx + w * 0.5 + 60.0, y + 13.0, alpha)
	_hits.append([Rect2(cx - 160, y - 34, 320, 48), i])


func _setting_row(cx: float, y: float, label: String, value: String, i: int, alpha: float) -> void:
	var sel := i == index
	_text(Vector2(cx - 40, y), label, _serif_bold if sel else _serif, 20, Color(BONE if sel else IDLE, alpha), 6.0, HORIZONTAL_ALIGNMENT_RIGHT)
	var vf: Font = _digits if value.ends_with("%") else _serif
	_text(Vector2(cx + 120, y), value, vf, 20, Color(BONE if sel else IDLE, alpha), 2.0)
	if sel:
		var pop := 1.0 + 0.6 * (1.0 - _ease(_sel_ms, 0.0, 180.0))
		_diamond(Vector2(cx + 40, y - 7), 4.0 * pop, Color(VIOLET, alpha))
		_diamond(Vector2(cx + 200, y - 7), 4.0 * pop, Color(VIOLET, alpha))
		_text(Vector2(cx + 62, y), "‹", _serif, 22, Color(VIOLET_LIGHT, alpha))
		_text(Vector2(cx + 178, y), "›", _serif, 22, Color(VIOLET_LIGHT, alpha))
		_sweep(cx - 240.0, cx + 240.0, y + 12.0, alpha)
	_hits.append([Rect2(cx - 260, y - 32, 500, 46), i])


func _footer() -> String:
	if stage == null:
		return "雨夜河岸街"
	var total: int = stage.round_waves.size() if stage.get("round_waves") != null else 3
	var n := clampi(int(stage.get("encounter_index")) + 1, 1, total)
	var seals := "雨夜河岸街 · 封印 %s / %s" % [ROMAN[n - 1], ROMAN[total - 1]]
	if stage.get("_trial_time") == null:
		return seals     # 雨街无限场景不计时
	var secs := int(float(stage.get("_trial_time")))
	return seals + "　　用时 %d:%02d" % [secs / 60, secs % 60]
