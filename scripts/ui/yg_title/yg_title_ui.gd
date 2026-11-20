extends Control
## [YG-MARK] 由 YG 新增（首页「断晓 · 断光」WebGL 版移植到 Godot）。
##
## 首页界面：章节铭文 / 副标题 / 菜单（斜切字）/ 设置 / 退出确认 / 提示 / 结束卡。
## 布局单位 u = min(H, W*0.5625)/100，和网页版 CSS 的 --u 一致；
## 字距一律按 em（相对字号）给，和 CSS 的 letter-spacing 对齐。
## 菜单字「被同一道刀口切成上下两半、错开」用两个带裁切着色器的图层叠出来。
##
## 删除方法：见 docs/YG-首页断光-删除清单.md。

const CUT_TEXT_SHADER := preload("res://assets/shaders/yg_title/yg_cut_text.gdshader")
const CUT_HALF := preload("res://scripts/ui/yg_title/yg_cut_half.gd")
const GothicFonts := preload("res://scripts/ui/gothic_fonts.gd")
const GAME_VERSION := "DEMO BUILD · v0.9"

const DIM := Color("8e919e")
const VIO := Color("b9a8ff")

var sim: RefCounted
var u := 7.2
var _expect := Vector2(1280.0, 720.0)

var mode := "menu"
var sel := 0
var rsel := 0
var csel := 1
var has_save := false
var ui_on := false

var _t := 0.0
var _a := 0.0
var _toast := ""
var _toast_t := 0.0
var _card_title := "断晓"
var _card_sub := ""
var _card_key := ""

## [YG-MARK] 11-05 适配：字体打包进游戏（Noto Serif SC 可变字体），玩家电脑没装也一样
const FONT_FILE := "res://assets/fonts/yg_title/NotoSerifSC-VF.ttf"

var _serif: Font
var _serif_light: Font
var _gothic: Font
var _menu_font: Font
var _blackletter: Font     # [YG-MARK] 11-05：副标题的哥特字，和暂停菜单「Intermissio」、战斗评价字母同一款
var pad_mode := false       ## [YG-MARK] 最近一次用的是手柄 → 提示换成手柄键名

var _halves: Array = []

## [YG-MARK] 11-05：「继续」没有存档系统撑着（只存了个时间戳，进去和开始一样），换成「操作说明」
var MENU := [
	{"act": "start", "num": "I", "label": "开始游戏", "tag": ""},
	{"act": "help", "num": "II", "label": "操作说明", "tag": ""},
	{"act": "settings", "num": "III", "label": "设置", "tag": ""},
	{"act": "quit", "num": "IV", "label": "退出", "tag": ""},
]

## [YG-MARK] 11-05：加主音量（总线 0，和暂停菜单同一个）、全屏、超采样、操作方式；值都问 app.row_value()
var ROWS := [
	{"k": "quality", "label": "画面品质", "type": "choice", "opts": ["低", "中", "高"]},
	{"k": "rain", "label": "雨量", "type": "slider"},
	{"k": "shake", "label": "镜头震动", "type": "toggle"},
	{"k": "master", "label": "主音量", "type": "slider"},
	{"k": "fullscreen", "label": "全屏", "type": "toggle"},
	{"k": "ssaa", "label": "超采样", "type": "toggle"},
	{"k": "scheme", "label": "操作方式", "type": "choice", "opts": ["键盘", "键鼠"]},
	{"k": "back", "label": "返回", "type": "back"},
]

const ROW_H := 3.1


func setup(s: RefCounted, view: Vector2) -> void:
	sim = s
	size = view
	position = Vector2.ZERO
	_expect = view
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	u = min(view.y, view.x * 0.5625) / 100.0
	_serif = GothicFonts.serif(400)
	_serif_light = GothicFonts.serif(300)
	# 拉丁碑刻与按键徽章走开源商用石刻衬线 Cinzel-VF，中文自动回退思源重宋
	_gothic = GothicFonts.cinzel(600, false, 500)
	_menu_font = GothicFonts.serif(600)
	# 副标题 Lux Scissa 统一使用打包的开源维多利亚尖角哥特黑体 PirataOne-Regular
	_blackletter = GothicFonts.blackletter(700)
	_build_halves()


## [YG-MARK] 打包思源宋体的指定字重（兼容接口，零系统字体依赖）
func _font(weight: int) -> Font:
	return GothicFonts.serif(weight)


func _exit_tree() -> void:
	var app := get_parent()
	if app != null:
		var aud = app.get("audio")
		if aud is Node:
			for child in (aud as Node).get_children():
				if child is AudioStreamPlayer:
					var ap := child as AudioStreamPlayer
					ap.stop()
					ap.stream = null
			var streams = aud.get("_streams")
			if streams is Dictionary:
				(streams as Dictionary).clear()
	if ui_on:
		var game_scene := "res://scenes/rain_trial.tscn"
		var st := ResourceLoader.load_threaded_get_status(game_scene)
		if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS or st == ResourceLoader.THREAD_LOAD_LOADED:
			var _discard = ResourceLoader.load_threaded_get(game_scene)
	# 给混音线程留出一个混音切片周期释放已 stop 的 Ogg 播放实例，避免直接退出时报 resources still in use
	OS.delay_msec(80)


func _build_halves() -> void:
	for i in MENU.size():
		for side in 2:
			var c := Control.new()
			c.set_script(CUT_HALF)
			c.mouse_filter = Control.MOUSE_FILTER_IGNORE
			c.set_anchors_preset(Control.PRESET_FULL_RECT)
			var m := ShaderMaterial.new()
			m.shader = CUT_TEXT_SHADER
			c.material = m
			add_child(c)
			_halves.append({"item": i, "side": side, "ctl": c})


func show_ui() -> void:
	ui_on = true
	_t = 0.0
	mode = "menu"
	sel = 0


func hide_ui() -> void:
	ui_on = false


func set_mode(m: String) -> void:
	mode = m


func refresh_continue() -> void:
	pass     # [YG-MARK] 11-05：「继续」已拿掉，留个空壳给 app 调


func toast(t: String) -> void:
	_toast = t
	_toast_t = 1.6


func set_card(title: String, sub: String, key: String) -> void:
	_card_title = title
	_card_sub = sub
	_card_key = key


# ---------------------------------------------------------------- 每帧
func tick(dt: float) -> void:
	if size != _expect:
		size = _expect
	if ui_on:
		_t += dt
		_a = minf(1.0, _a + dt * 4.0)
	else:
		_a = maxf(0.0, _a - dt * 3.0)
	if _toast_t > 0.0:
		_toast_t -= dt
	_layout_halves()
	queue_redraw()


func _layout_halves() -> void:
	var menu_y := _menu_top()
	for h in _halves:
		var item: int = h["item"]
		var side: int = h["side"]
		var c: Control = h["ctl"]
		var y := menu_y + item * _item_h() + _item_h() * 0.5
		var ctr := Vector2(size.x * 0.5, y)
		var off := Vector2.ZERO
		var is_sel := (mode == "menu" and sel == item)
		if is_sel:
			off = Vector2(-0.16 * u, -0.06 * u) if side == 0 else Vector2(0.16 * u, 0.06 * u)
		var m := c.material as ShaderMaterial
		m.set_shader_parameter("uRes", size)
		m.set_shader_parameter("uLine", ctr)
		m.set_shader_parameter("uN", sim.N)   # [YG-MARK] 11-08 跟断口同一个角度
		m.set_shader_parameter("uSide", 1.0 if side == 0 else -1.0)
		var a := _elem_a(0.15 + item * 0.12) * _a
		if mode != "menu":
			a = 0.0
		c.label_text = MENU[item]["label"]
		c.num_text = ""    # [YG-MARK] 11-05 更高级：罗马数字 Ⅰ～Ⅳ 小到看不清，去掉
		c.font_serif = _menu_font
		c.font_gothic = _gothic
		c.unit = u
		c.label_size = MENU_FS_SEL if is_sel else MENU_FS   # [YG-MARK] 11-08 选中项大一号
		c.label_spacing = 0.62
		c.ctr = ctr + off
		var dim: bool = (MENU[item]["tag"] != "")
		var lab := Color(0.929, 0.902, 0.859, a) if is_sel else Color(0.69, 0.70, 0.745, a)   # [YG-MARK] 11-08 提亮
		if dim and not is_sel:
			lab = Color(0.282, 0.29, 0.337, a)
		elif dim:
			lab = Color(0.471, 0.482, 0.541, a)
		c.label_col = lab
		# [YG-MARK] 11-05：选中时左边是紫菱，罗马数字让位
		c.num_col = Color(0.878, 0.855, 0.808, 0.0) if is_sel else Color(0.322, 0.337, 0.408, a)
		c.visible = a > 0.001
		c.queue_redraw()


func _elem_a(delay: float) -> float:
	if not ui_on:
		return 0.0
	return clampf((_t - delay) / 0.7, 0.0, 1.0)


## [YG-MARK] 11-05 改好看：菜单挂在副标题下面 7.5u（原来紧贴字标），字 2.25u → 2.5u、字重 500
## [YG-MARK] 11-08 换 G03：按定稿图放大，选中 3.5u、其余 2.75u（原来都是 2.5u）
const MENU_FS := 2.75
const MENU_FS_SEL := 3.5


func _menu_top() -> float:
	return sim.logo_cy + sim.F * 0.92 + 13.6 * u   # [YG-MARK] 11-08：字标不再以刀口为中心；选中项中心落在定稿图的高度（2/3 屏）


func _item_h() -> float:
	return (MENU_FS * 1.55 + 1.6) * u


# ---------------------------------------------------------------- 绘制
func _draw() -> void:
	if _a <= 0.001 and not ui_on:
		return
	# [YG-MARK] 11-05 改好看：四角框线、章节铭文、右上快捷键、DEMO 版本号是网页演示用的，游戏里去掉
	if mode != "help":     # [YG-MARK] 说明页面板高，会压在副标题上，副标题先收起
		_draw_sub()
	if mode == "menu":
		_draw_menu_decor()
	if mode == "settings":
		_draw_settings()
	if mode == "confirm":
		_draw_confirm()
	if mode == "help":
		_draw_help()
	else:
		_draw_hint()
	_draw_toast()
	if mode == "card":
		_draw_card()


func _draw_frame() -> void:
	var a := clampf((_t - 0.6) / 2.0, 0.0, 1.0) * _a
	if a <= 0.01:
		return
	var r := Rect2(Vector2(1.9 * u, 1.9 * u), size - Vector2(3.8 * u, 3.8 * u))
	draw_rect(r, Color(0.86, 0.84, 0.80, 0.07 * a), false, 1.0)
	var cs := 1.4 * u
	var col := Color(0.88, 0.855, 0.81, 0.28 * a)
	var corners := [
		[Vector2(0, 0), Vector2(1, 0), Vector2(0, 1)],
		[Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1)],
		[Vector2(0, 1), Vector2(1, 0), Vector2(0, -1)],
		[Vector2(1, 1), Vector2(-1, 0), Vector2(0, -1)],
	]
	for corner in corners:
		var o: Vector2 = r.position + Vector2(corner[0].x * r.size.x, corner[0].y * r.size.y)
		draw_line(o, o + Vector2(corner[1].x, corner[1].y) * cs, col, 1.0)
		draw_line(o, o + Vector2(corner[2].x, corner[2].y) * cs, col, 1.0)


func _draw_chap() -> void:
	var a := clampf((_t - 0.8) / 1.5, 0.0, 1.0) * _a
	if a <= 0.01:
		return
	var fs := int(round(1.02 * u))
	var pos := Vector2(3.6 * u, 3.1 * u + fs)
	var d := 0.42 * u
	_diamond(Vector2(3.6 * u + d * 0.5, pos.y - fs * 0.34), d * 0.5, Color(0.765, 0.706, 1.0, 0.55 * a))
	_text_spaced(Vector2(pos.x + d + 1.1 * u, pos.y), "序 幕 · 昼 与 影 之 界", _serif, fs,
			Color(0.424, 0.447, 0.533, a), 0.38)


func _draw_sub() -> void:
	var a := clampf((_t - 0.1) / 1.6, 0.0, 1.0) * _a
	if a <= 0.01:
		return
	var y: float = sim.logo_cy + sim.F * 0.92   # [YG-MARK] 11-08 换 G03：去掉两边的线和菱形，只留字
	# [YG-MARK] 11-05 更高级：副标题回到定好的哥特小字 Lux Scissa（移植时跟着网页版成了拉开字距的宋体大写）
	var txt := "Lux Scissa"
	var fs := int(round(2.5 * u))
	var w := _spaced_width(txt, _blackletter, fs, 0.04)
	var cx := size.x * 0.5
	_text_spaced(Vector2(cx - w * 0.5, y + fs * 0.3), txt, _blackletter, fs, Color(0.86, 0.84, 0.8, a), 0.04)


func _draw_menu_decor() -> void:
	# [YG-MARK] 11-05 改好看：菜单底下垫一块羽化的暗，压住倒影和雨，字才看得清
	var a0 := _elem_a(0.1) * _a
	if a0 > 0.01:
		var mc := Vector2(size.x * 0.5, _menu_top() + _item_h() * MENU.size() * 0.5)
		_soft_backdrop(mc, 30.0 * u, _item_h() * MENU.size() * 0.72, 0.62 * a0)
	for i in MENU.size():
		var a := _elem_a(0.15 + i * 0.12) * _a
		if a <= 0.01:
			continue
		var y := _menu_top() + i * _item_h() + _item_h() * 0.5
		var is_sel := (sel == i)
		var cx := size.x * 0.5
		if is_sel:
			# [YG-MARK] 11-08 换 G03：字下面一道冷白的斩线，比字宽，两头收细（原来是紫菱 + 银线）
			var fs := int(round(MENU_FS_SEL * u))
			var lw := _spaced_width(MENU[i]["label"], _menu_font, fs, 0.62)
			_home_slash(Vector2(cx, y + fs * 0.86), lw * 0.5 + 5.5 * u, a)
		var tag: String = MENU[i]["tag"]
		if tag != "":
			var tfs := int(round(0.92 * u))
			var tw := _spaced_width(tag, _serif, tfs, 0.26)
			var tp := Vector2(cx + 9.0 * u, y)
			var box := Rect2(tp + Vector2(-tw * 0.5 - 0.55 * u, -0.9 * u), Vector2(tw + 1.36 * u, 1.7 * u))
			draw_rect(box, Color(0.047, 0.055, 0.086, 0.55 * a), true)
			draw_rect(box, Color(0.47, 0.494, 0.588, 0.25 * a), false, 1.0)
			_text_spaced(Vector2(tp.x - tw * 0.5, tp.y + tfs * 0.34), tag, _serif, tfs,
					Color(0.408, 0.424, 0.502, a), 0.26)


func _draw_hint() -> void:
	var a := clampf((_t - 0.9) / 1.5, 0.0, 1.0) * _a
	if a <= 0.01:
		return
	var y := size.y - 2.9 * u
	# [YG-MARK] 11-05 改好看：网页演示的玩法提示（拂过悬珠 / 拖拽 X / R 重播）去掉，按键照样能用
	var parts := [["↑ ↓", "选择"], ["Enter", "确认"]]
	if pad_mode:     # [YG-MARK] 11-05：手柄只给能按的
		parts = [["十字键", "选择"], ["A", "确认"], ["B", "返回"]]
	elif mode != "menu":
		parts = [["↑ ↓", "选择"], ["← →", "调整"], ["Enter", "确认"], ["Esc", "返回"]]
	var widths: Array = []
	var total := 0.0
	var gapw := 2.2 * u
	var lfs := int(round(1.5 * u))     # [YG-MARK] 11-05 更高级：提示放大一号、提亮；11-08 再大一点
	for p in parts:
		var kw := _chip_width(p[0])
		var tw := _spaced_width(p[1], _serif_light, lfs, 0.26)
		var w := kw + 0.55 * u + tw
		widths.append([kw, tw, w])
		total += w + gapw
	total -= gapw
	var x := size.x * 0.5 - total * 0.5
	for i in parts.size():
		var kw: float = widths[i][0]
		_chip(Rect2(Vector2(x, y - 1.1 * u), Vector2(kw, 2.2 * u)), parts[i][0], a)
		_text_spaced(Vector2(x + kw + 0.55 * u, y + lfs * 0.34), parts[i][1], _serif_light, lfs,
				Color(0.69, 0.71, 0.76, a), 0.26)
		x += float(widths[i][2]) + gapw


func _draw_ver() -> void:
	var a := clampf((_t - 1.2) / 1.5, 0.0, 1.0) * _a
	if a <= 0.01:
		return
	var fs := int(round(0.98 * u))
	var w := _spaced_width(GAME_VERSION, _gothic, fs, 0.36)
	_text_spaced(Vector2(size.x - 3.6 * u - w, size.y - 3.1 * u), GAME_VERSION, _gothic, fs,
			Color(0.322, 0.345, 0.424, a), 0.36)


func _draw_top_hud() -> void:
	var a := clampf((_t - 1.0) / 1.0, 0.0, 1.0) * _a
	if a <= 0.01:
		return
	var fs := int(round(1.02 * u))
	# [YG-MARK] 11-06：手柄也有这两个键了（Back 重播、Y 声音），手柄时换键名而不是藏起来
	var txt := "重播开场 · Back" if pad_mode else "重播开场 · R"
	var w := _spaced_width(txt, _serif_light, fs, 0.26)
	var bh := 2.0 * u
	var right := size.x - 3.6 * u
	var y_top := 3.1 * u
	var bw1 := w + 1.4 * u
	var x1 := right - bw1
	_btn(Rect2(Vector2(x1, y_top), Vector2(bw1, bh)), a)
	_text_spaced(Vector2(x1 + 0.7 * u, y_top + bh * 0.5 + fs * 0.34), txt, _serif_light, fs,
			Color(0.541, 0.573, 0.667, a), 0.26)
	var txt2 := "声音 · Y" if pad_mode else "声音 · M"
	var w2 := _spaced_width(txt2, _serif_light, fs, 0.26)
	var bw2 := w2 + 2.2 * u
	var x2 := x1 - 0.9 * u - bw2
	_btn(Rect2(Vector2(x2, y_top), Vector2(bw2, bh)), a)
	draw_circle(Vector2(x2 + 0.9 * u, y_top + bh * 0.5), 0.25 * u, Color(0.608, 0.549, 1.0, a))
	_text_spaced(Vector2(x2 + 1.5 * u, y_top + bh * 0.5 + fs * 0.34), txt2, _serif_light, fs,
			Color(0.541, 0.573, 0.667, a), 0.26)


func _draw_toast() -> void:
	if _toast_t <= 0.0:
		return
	var a := clampf(_toast_t / 0.4, 0.0, 1.0)
	var fs := int(round(1.3 * u))
	var w := _spaced_width(_toast, _serif, fs, 0.4)
	_text_spaced(Vector2(size.x * 0.5 - w * 0.5, _menu_top() + 27.0 * u), _toast, _serif, fs,
			Color(0.706, 0.69, 0.658, a), 0.4)


func _draw_card() -> void:
	var fs1 := int(round(2.4 * u))
	var w1 := _spaced_width(_card_title, _serif, fs1, 0.9)
	_text_spaced(Vector2(size.x * 0.5 - w1 * 0.5, size.y * 0.5 - 3.0 * u), _card_title, _serif, fs1,
			Color(0.91, 0.894, 0.863, 1.0), 0.9)
	draw_line(Vector2(size.x * 0.5 - 11.0 * u, size.y * 0.5), Vector2(size.x * 0.5 + 11.0 * u, size.y * 0.5),
			Color(0.941, 0.925, 0.894, 0.8), 1.0)
	var fs2 := int(round(1.35 * u))
	var w2 := _spaced_width(_card_sub, _serif_light, fs2, 0.5)
	_text_spaced(Vector2(size.x * 0.5 - w2 * 0.5, size.y * 0.5 + 2.6 * u), _card_sub, _serif_light, fs2,
			Color(0.561, 0.584, 0.671, 1.0), 0.5)
	var fs3 := int(round(1.05 * u))
	var w3 := _spaced_width(_card_key, _serif_light, fs3, 0.4)
	_text_spaced(Vector2(size.x * 0.5 - w3 * 0.5, size.y * 0.5 + 8.6 * u), _card_key, _serif_light, fs3,
			Color(0.306, 0.329, 0.4, 1.0), 0.4)


# ---------------------------------------------------------------- 设置面板
func _panel_rect() -> Rect2:
	var w := 58.0 * u
	var h := (2.0 + 1.25 + 1.4 + ROW_H * ROWS.size() + 1.4) * u
	# [YG-MARK] 11-05：行多了，底边不出屏（离底 5u），放不下就往上顶
	var top := minf(_menu_top() - 3.0 * u, size.y - 5.0 * u - h)
	return Rect2(Vector2(size.x * 0.5 - w * 0.5, top), Vector2(w, h))


## [YG-MARK] 11-05：鼠标点在设置页第几行（没点中 = -1）
func row_at(p: Vector2) -> int:
	var r := _panel_rect()
	var y0 := r.position.y + (2.0 + 1.25 + 1.4) * u
	if p.x < r.position.x or p.x > r.position.x + r.size.x or p.y < y0:
		return -1
	var i := int(floor((p.y - y0) / (ROW_H * u)))
	return i if i >= 0 and i < ROWS.size() else -1


func _row_value(key: String) -> Variant:
	var app := get_parent()
	if app != null and app.has_method("row_value"):
		return app.row_value(key)
	return null


func _draw_settings() -> void:
	var r := _panel_rect()
	_panel_bg(r)
	var fs := int(round(1.25 * u))
	var head := "设 　 置"
	var hw := _spaced_width(head, _serif, fs, 0.9)
	var hx := size.x * 0.5
	var hy := r.position.y + 2.0 * u + fs
	_text_spaced(Vector2(hx - hw * 0.5, hy), head, _serif, fs, Color(0.604, 0.627, 0.714, 1.0), 0.9)
	var ly := hy - fs * 0.55
	_line_grad(Vector2(r.position.x + 2.4 * u, ly), Vector2(hx - hw * 0.5 - 1.6 * u, ly), Color(0.784, 0.769, 0.737, 0.45), false)
	_line_grad(Vector2(hx + hw * 0.5 + 1.6 * u, ly), Vector2(r.position.x + r.size.x - 2.4 * u, ly), Color(0.784, 0.769, 0.737, 0.45), true)
	var y := r.position.y + (2.0 + 1.25 + 1.4) * u
	for i in ROWS.size():
		var row: Dictionary = ROWS[i]
		var rh := ROW_H * u
		var ry := y + i * rh
		var is_sel := (rsel == i)
		var lfs := int(round(1.6 * u))     # [YG-MARK] 11-05：8 行，字从 1.85u 收到 1.6u
		if row["type"] == "back":
			var bw := _spaced_width(ROWS[i]["label"], _serif, lfs, 0.4)
			if is_sel:
				_sel_mark(Vector2(size.x * 0.5, ry + rh * 0.5), bw * 0.5, lfs, 1.0)
			_text_spaced(Vector2(size.x * 0.5 - bw * 0.5, ry + rh * 0.5 + lfs * 0.34), ROWS[i]["label"], _serif, lfs,
					Color(0.961, 0.949, 0.925) if is_sel else Color(0.557, 0.569, 0.62), 0.4)
			continue
		if is_sel:
			_row_sel(r, ry, rh)
		# [YG-MARK] 11-05 更高级：标签正常字距（原来按四个字两端撑开，“雨　　量”很怪）
		_text_spaced(Vector2(r.position.x + 2.6 * u, ry + rh * 0.5 + lfs * 0.34), row["label"], _serif, lfs,
				Color(0.961, 0.949, 0.925) if is_sel else Color(0.6, 0.612, 0.66), 0.14)
		_draw_row_ctl(row, Vector2(r.position.x + r.size.x - 2.0 * u, ry + rh * 0.5), is_sel)


func _draw_row_ctl(row: Dictionary, right: Vector2, is_sel: bool) -> void:
	var fs := int(round(1.6 * u))     # [YG-MARK] 11-05 更高级：选项放大
	var key: String = row["k"]
	match str(row["type"]):
		"choice":
			# [YG-MARK] 11-05：通用选项行（画质 / 操作方式），从右往左画 › 选项… ‹
			var opts: Array = row["opts"]
			var idx := maxi(0, int(_row_value(key)))
			var parts := ["›"]
			for j in range(opts.size() - 1, -1, -1):
				parts.append(opts[j])
			parts.append("‹")
			var x := right.x - 0.6 * u
			for i in parts.size():
				var t: String = parts[i]
				var w := _spaced_width(t, _serif, fs, 0.2)
				var c := Color(0.365, 0.388, 0.467)
				if i == 0 or i == parts.size() - 1:
					c = Color(0.541, 0.573, 0.667)
				elif opts.size() - i == idx:
					c = Color(0.953, 0.941, 0.918)
				_text_spaced(Vector2(x - w, right.y + fs * 0.34), t, _serif, fs, c, 0.2)
				x -= w + 1.1 * u
		"slider":
			var v: int = int(_row_value(key))
			var x := right.x
			var vs := str(v)
			var vfs := int(round(1.3 * u))
			var vw := _spaced_width(vs, _gothic, vfs, 0.05)
			_text_spaced(Vector2(x - vw, right.y + vfs * 0.34), vs, _gothic, vfs, Color(0.561, 0.584, 0.667), 0.05)
			x -= vw + 1.2 * u
			var bw := 0.55 * u
			var bg := 0.36 * u
			var filled := int(round(v / 10.0))
			for i in range(9, -1, -1):
				var bx := x - bw
				var rr := Rect2(Vector2(bx, right.y - 0.75 * u), Vector2(bw, 1.5 * u))
				var c := Color(0.169, 0.184, 0.235) if i >= filled else Color(0.871, 0.855, 0.824)
				_skew_rect(rr, c)
				x -= bw + bg
			x -= 0.4 * u
			_text_spaced(Vector2(x - 0.9 * u, right.y + fs * 0.34), "‹", _serif, fs, Color(0.541, 0.573, 0.667), 0.2)
			_text_spaced(Vector2(right.x + 0.5 * u, right.y + fs * 0.34), "›", _serif, fs, Color(0.541, 0.573, 0.667), 0.2)
		"toggle":
			var on: bool = bool(_row_value(key))
			var x := right.x - 0.6 * u
			var labels := ["›", "关", "开"]
			for i in 3:
				var t: String = labels[i]
				var w := _spaced_width(t, _serif, fs, 0.2)
				# [YG-MARK] 11-05 更高级：没选的那个压暗，开 / 关一眼分得出
				var c := Color(0.541, 0.573, 0.667) if i == 0 else Color(0.365, 0.388, 0.467)
				if i == 1 and not on:
					c = Color(0.953, 0.941, 0.918)
				elif i == 2 and on:
					c = Color(0.953, 0.941, 0.918)
				_text_spaced(Vector2(x - w, right.y + fs * 0.34), t, _serif, fs, c, 0.2)
				x -= w + 1.1 * u
			_text_spaced(Vector2(x - 0.9 * u, right.y + fs * 0.34), "‹", _serif, fs, Color(0.541, 0.573, 0.667), 0.2)


# ---------------------------------------------------------------- [YG-MARK] 11-05 操作说明页
## 键位跟暂停菜单「操作说明」同一来源（player_factory 的当前方案）；手柄按 player_factory 顶上的注释
func _help_rows_kb() -> Array:
	var F = load("res://scripts/night/player_factory.gd")
	var atk: String = F.key_label("attack")
	return [
		["A / D", "移动"], ["W / 空格", "跳（可二段）"], ["S", "从木台跳下"],
		[atk, "攻击"], ["按住 " + atk, "蓄力，松开释放"], ["W + " + atk, "跳起上挑"],
		["S + " + atk, "空中下砸"], [F.key_label("dash"), "冲刺斩"], [F.key_label("ranged"), "远射"],
		[F.key_label("parry"), "格挡 / 弹刀"], ["R", "大招「绝影」"], ["Esc", "暂停"],
	]


func _help_rows_pad() -> Array:
	return [
		["左摇杆 / 十字键", "移动"], ["A", "跳（可二段）"], ["↓", "从木台跳下"],
		["X", "攻击"], ["按住 X", "蓄力，松开释放"], ["↑ + X", "跳起上挑"],
		["↓ + X", "空中下砸"], ["B", "冲刺斩"], ["Y", "远射"],
		["RB", "格挡 / 弹刀"], ["RT", "大招「绝影」"], ["Start", "暂停"],
	]


func _draw_help() -> void:
	var kb := _help_rows_kb()
	var pad := _help_rows_pad()
	var n := maxi(kb.size(), pad.size())
	var rh := 2.35 * u
	var w := 86.0 * u
	var h := (2.0 + 1.25 + 1.4 + 2.6) * u + rh * n + 3.4 * u
	var r := Rect2(Vector2(size.x * 0.5 - w * 0.5, minf(_menu_top() - 3.0 * u, size.y - 5.0 * u - h)), Vector2(w, h))
	_panel_bg(r)
	var fs := int(round(1.25 * u))
	var head := "操 作 说 明"
	var hw := _spaced_width(head, _serif, fs, 0.9)
	var hx := size.x * 0.5
	var hy := r.position.y + 2.0 * u + fs
	_text_spaced(Vector2(hx - hw * 0.5, hy), head, _serif, fs, Color(0.604, 0.627, 0.714, 1.0), 0.9)
	var ly := hy - fs * 0.55
	_line_grad(Vector2(r.position.x + 2.4 * u, ly), Vector2(hx - hw * 0.5 - 1.6 * u, ly), Color(0.784, 0.769, 0.737, 0.45), false)
	_line_grad(Vector2(hx + hw * 0.5 + 1.6 * u, ly), Vector2(r.position.x + r.size.x - 2.4 * u, ly), Color(0.784, 0.769, 0.737, 0.45), true)
	var F = load("res://scripts/night/player_factory.gd")
	var cols := [[str(F.scheme_name()), kb], ["手柄", pad]]
	var col_w := (w - 6.0 * u) * 0.5
	var y0 := r.position.y + (2.0 + 1.25 + 1.4) * u
	var kfs := int(round(1.2 * u))
	var tfs := int(round(1.3 * u))
	for c in 2:
		var x0 := r.position.x + 3.0 * u + c * col_w
		var title: String = cols[c][0]
		_diamond(Vector2(x0 + 0.3 * u, y0 + 0.9 * u), 0.22 * u, Color(0.765, 0.706, 1.0, 0.8))
		_text_spaced(Vector2(x0 + 1.2 * u, y0 + 0.9 * u + tfs * 0.34), title, _serif, tfs, Color(0.84, 0.816, 0.776), 0.4)
		var rows: Array = cols[c][1]
		for i in rows.size():
			var ry := y0 + 2.6 * u + i * rh + rh * 0.5
			var key: String = rows[i][0]
			var kw := _spaced_width(key, _gothic, kfs, 0.08)
			var chip := Rect2(Vector2(x0, ry - 0.85 * u), Vector2(kw + 1.2 * u, 1.7 * u))
			draw_rect(chip, Color(0.071, 0.086, 0.133, 0.7), true)
			draw_rect(chip, Color(0.627, 0.667, 0.784, 0.24), false, 1.0)
			_text_spaced(Vector2(chip.position.x + 0.6 * u, ry + kfs * 0.34), key, _gothic, kfs, Color(0.82, 0.83, 0.88), 0.08)
			_text_spaced(Vector2(x0 + 13.5 * u, ry + kfs * 0.34), str(rows[i][1]), _serif_light, kfs,
					Color(0.66, 0.68, 0.75), 0.2)
	# 底下一行：怎么回去
	var back := "B 返回" if pad_mode else "Esc / Enter 返回"
	var bfs := int(round(1.05 * u))
	var bw := _spaced_width(back, _serif_light, bfs, 0.3)
	_text_spaced(Vector2(hx - bw * 0.5, r.position.y + r.size.y - 1.1 * u), back, _serif_light, bfs,
			Color(0.45, 0.47, 0.55), 0.3)


func _draw_confirm() -> void:
	var y := _menu_top() + 4.0 * u
	_soft_backdrop(Vector2(size.x * 0.5, y + 1.6 * u), 26.0 * u, 9.0 * u, 0.7)
	var fs := int(round(2.0 * u))
	var q := "就此离开？"
	var w := _spaced_width(q, _serif, fs, 0.6)
	_text_spaced(Vector2(size.x * 0.5 - w * 0.5, y), q, _serif, fs, Color(0.843, 0.827, 0.902), 0.6)
	var yy := y + 4.2 * u
	var opts := ["离开", "留下"]
	for i in 2:
		var cx := size.x * 0.5 + (-1.0 if i == 0 else 1.0) * 7.0 * u
		var is_sel := (csel == i)
		var w2 := _spaced_width(opts[i], _serif, fs, 0.6)
		if is_sel:
			_sel_mark(Vector2(cx, yy - fs * 0.34), w2 * 0.5, fs, 1.0)
		_text_spaced(Vector2(cx - w2 * 0.5, yy), opts[i], _serif, fs,
				Color(0.965, 0.953, 0.933) if is_sel else Color(0.557, 0.569, 0.62), 0.6)


# ---------------------------------------------------------------- 小工具
func _text_spaced(pos: Vector2, text: String, font: Font, fs: int, col: Color, em: float) -> void:
	var spacing := em * float(fs)
	var x := pos.x
	for i in text.length():
		var ch := text.substr(i, 1)
		draw_string(font, Vector2(x, pos.y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		x += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + spacing


func _spaced_width(text: String, font: Font, fs: int, em: float) -> float:
	var spacing := em * float(fs)
	var w := 0.0
	for i in text.length():
		w += font.get_string_size(text.substr(i, 1), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + spacing
	if text.length() > 0:
		w -= spacing
	return w


func _line_grad(a: Vector2, b: Vector2, col: Color, to_left: bool) -> void:
	var steps := 12
	for i in steps:
		var t0 := float(i) / steps
		var t1 := float(i + 1) / steps
		var al := (1.0 - t0) if to_left else t0
		var c := Color(col.r, col.g, col.b, col.a * al)
		draw_line(a.lerp(b, t0), a.lerp(b, t1), c, 1.0)


func _diamond(c: Vector2, s: float, col: Color) -> void:
	var pts := PackedVector2Array([c + Vector2(0, -s), c + Vector2(s, 0), c + Vector2(0, s), c + Vector2(-s, 0)])
	draw_colored_polygon(pts, col)


func _skew_rect(r: Rect2, col: Color) -> void:
	var sk := r.size.y * 0.24
	var pts := PackedVector2Array([
			r.position + Vector2(sk, 0), r.position + Vector2(r.size.x + sk, 0),
			r.position + Vector2(r.size.x, r.size.y), r.position + Vector2(0, r.size.y)])
	draw_colored_polygon(pts, col)


func _cut_line(c: Vector2, width: float, a: float) -> void:
	var ang := deg_to_rad(10.32)
	var d := Vector2(cos(ang), sin(ang))
	var a0 := c - d * width * 0.5
	var a1 := c + d * width * 0.5
	var steps := 26
	for i in steps:
		var t0 := float(i) / steps
		var t1 := float(i + 1) / steps
		var tm := (t0 + t1) * 0.5
		var al := 0.0
		if tm < 0.08:
			al = 0.0
		elif tm < 0.32:
			al = lerpf(0.0, 0.65, (tm - 0.08) / 0.24)
		elif tm < 0.5:
			al = lerpf(0.65, 1.0, (tm - 0.32) / 0.18)
		elif tm < 0.68:
			al = lerpf(1.0, 0.65, (tm - 0.5) / 0.18)
		elif tm < 0.92:
			al = lerpf(0.65, 0.0, (tm - 0.68) / 0.24)
		var col := Color(0.804, 0.745, 1.0).lerp(Color(1.0, 0.992, 0.98), minf(1.0, al))
		draw_line(a0.lerp(a1, t0), a0.lerp(a1, t1), Color(col.r, col.g, col.b, al * a), 1.5)


## [YG-MARK] 11-05 更高级：椭圆光斑 / 暗底都改用一张平滑的径向渐变图拉伸着画。
## 原来是一圈圈半透明圆叠出来的，背后一亮（玩家划刀）就露出一道道同心台阶。
var _radial: GradientTexture2D


func _radial_tex() -> GradientTexture2D:
	if _radial == null:
		var g := Gradient.new()
		var offs := PackedFloat32Array()
		var cols := PackedColorArray()
		for i in 17:
			var t := float(i) / 16.0
			offs.append(t)
			var a := 1.0 - smoothstep(0.35, 1.0, t)
			cols.append(Color(1, 1, 1, a))
		g.offsets = offs
		g.colors = cols
		_radial = GradientTexture2D.new()
		_radial.gradient = g
		_radial.fill = GradientTexture2D.FILL_RADIAL
		_radial.fill_from = Vector2(0.5, 0.5)
		_radial.fill_to = Vector2(1.0, 0.5)
		_radial.width = 256
		_radial.height = 256
	return _radial


func _radial_blob(c: Vector2, rx: float, ry: float, col: Color) -> void:
	draw_texture_rect(_radial_tex(), Rect2(c - Vector2(rx, ry), Vector2(rx, ry) * 2.0), false, col)


func _glow_ellipse(c: Vector2, rx: float, ry: float, a: float) -> void:
	# 网页版是 radial-gradient 的椭圆光斑
	_radial_blob(c, rx, ry, Color(0.80, 0.76, 0.98, 0.12 * a))


## [YG-MARK] 11-05：羽化的暗底（中心约 strength，从 0.35 半径起淡到边缘 0）
func _soft_backdrop(c: Vector2, rx: float, ry: float, strength: float) -> void:
	_radial_blob(c, rx, ry, Color(0.008, 0.01, 0.018, clampf(strength, 0.0, 0.98)))


## [YG-MARK] 11-05 改好看：设置 / 说明页的底——不画方框，一块羽化的暗 + 上下两道渐隐细线（暂停菜单的味道）
func _panel_bg(r: Rect2) -> void:
	_soft_backdrop(r.get_center(), r.size.x * 0.66, r.size.y * 0.74, 0.9)
	var c := Color(0.784, 0.769, 0.737, 0.35)
	for yy in [r.position.y, r.position.y + r.size.y]:
		_line_grad(Vector2(r.position.x, yy), Vector2(r.get_center().x, yy), c, false)
		_line_grad(Vector2(r.get_center().x, yy), Vector2(r.position.x + r.size.x, yy), c, true)
		_diamond(Vector2(r.get_center().x, yy), 0.3 * u, Color(0.74, 0.66, 1.0, 0.7))


## [YG-MARK] 11-05：设置页选中行——左边一颗紫菱 + 一条很淡的亮底
func _row_sel(r: Rect2, ry: float, rh: float) -> void:
	var band := Rect2(Vector2(r.position.x + 0.6 * u, ry + 0.25 * rh), Vector2(r.size.x - 1.2 * u, rh * 0.5))
	_glow_ellipse(band.get_center(), band.size.x * 0.5, rh * 0.42, 0.35)
	_diamond(Vector2(r.position.x + 0.8 * u, ry + rh * 0.5), 0.3 * u, Color(0.74, 0.66, 1.0, 0.95))


## [YG-MARK] 11-08 换 G03：首页菜单的选中线
func _home_slash(c: Vector2, half_w: float, a: float) -> void:
	var steps := 24
	for i in steps:
		var t0 := float(i) / steps
		var t1 := float(i + 1) / steps
		var e := 1.0 - pow(absf((t0 + t1) - 1.0), 2.0)
		var p0 := Vector2(c.x + lerpf(-half_w, half_w, t0), c.y)
		var p1 := Vector2(c.x + lerpf(-half_w, half_w, t1), c.y)
		draw_line(p0, p1, Color(0.82, 0.86, 0.96, 0.10 * e * a), 4.0)
		draw_line(p0, p1, Color(0.97, 0.97, 0.99, e * a), 1.2)


## [YG-MARK] 11-05：选中标记，照暂停菜单：两侧紫菱 + 字下面一道银线（左端带紫色线头）
func _sel_mark(c: Vector2, half_w: float, fs: int, a: float) -> void:
	var dx := half_w + 2.0 * u
	var ds := 0.44 * u
	_diamond(Vector2(c.x - dx, c.y), ds, Color(0.74, 0.66, 1.0, 0.95 * a))
	_diamond(Vector2(c.x + dx, c.y), ds, Color(0.74, 0.66, 1.0, 0.95 * a))
	var ly := c.y + fs * 0.62
	var x0 := c.x - half_w
	var x1 := c.x + half_w
	var steps := 18
	for i in steps:
		var t0 := float(i) / steps
		var t1 := float(i + 1) / steps
		var tm := (t0 + t1) * 0.5
		var col := Color(0.72, 0.62, 1.0).lerp(Color(0.86, 0.85, 0.83), smoothstep(0.0, 0.25, tm))
		col.a = a * (0.95 - 0.55 * tm)
		draw_line(Vector2(lerpf(x0, x1, t0), ly), Vector2(lerpf(x0, x1, t1), ly), col, 1.2)


func _chip(r: Rect2, text: String, a: float) -> void:
	draw_rect(r, Color(0.071, 0.086, 0.133, 0.55 * a), true)
	draw_rect(r, Color(0.627, 0.667, 0.784, 0.24 * a), false, 1.0)
	var fs := int(round(1.3 * u))
	var w := _spaced_width(text, _gothic, fs, 0.1)
	_text_spaced(Vector2(r.position.x + r.size.x * 0.5 - w * 0.5, r.position.y + r.size.y * 0.5 + fs * 0.35),
			text, _gothic, fs, Color(0.722, 0.749, 0.831, a), 0.1)


func _chip_width(text: String) -> float:
	return _spaced_width(text, _gothic, int(round(1.3 * u)), 0.1) + 1.3 * u


func _btn(r: Rect2, a: float) -> void:
	draw_rect(r, Color(0.039, 0.047, 0.078, 0.55 * a), true)
	draw_rect(r, Color(0.647, 0.686, 0.804, 0.22 * a), false, 1.0)
