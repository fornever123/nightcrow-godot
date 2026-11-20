extends CanvasLayer
## 断晓肉鸽 · 哥特铁艺「万象牌桌」（ForkChoiceOverlay）
## 美术对齐《断晓》主视觉（墨黑 · 冷紫 · 银白 · 微金 · 5:59 旋转钟盘 · 慢雨 · 铁艺菱纹 · 刀锋卡边）：
## 全程仅用内置开源字体（NotoSerifSC-VF / Cinzel-VF / PirataOne，零 SystemFont）：
##   - OPEN_SETUP：开局择 1 张本命核心（初始 Lv.10）
##   - SHOP_TABLE：键鼠（1-4 买牌 · U 升级 · R 刷新 · 空格出战）
##                手柄（十字键/左摇杆/LB·RB 选牌 · A 购买/确认 · Y 升级 · X 刷新 · Start 出战）

const GamepadManager := preload("res://scripts/core/gamepad_manager.gd")
const GothicFonts := preload("res://scripts/ui/gothic_fonts.gd")
const FONT_SERIF_PATH := "res://assets/fonts/yg_title/NotoSerifSC-VF.ttf"

const COL_INK := Color(0.028, 0.025, 0.048, 0.94)
const COL_PANEL_BG := Color(0.042, 0.036, 0.072, 0.96)
const COL_SILVER := Color("e6e9ef")
const COL_BONE := Color("f2eee4")
const COL_STEEL := Color("8b95a8")
const COL_VIOLET := Color("9a6cff")
const COL_VIOLET_LIGHT := Color("d4bcff")
const COL_GOLD := Color("f5dfa3")
const COL_MINT := Color("b8f5d8")
const COL_RAIN := Color(0.54, 0.60, 0.72)

const ROMAN_NUMS: Array[String] = ["Ⅰ", "Ⅱ", "Ⅲ", "Ⅳ"]
const RAIN_COUNT := 96
const RAIN_SLANT := -0.22

signal opening_confirmed(core_id: String)
signal table_finished()

enum Mode { NONE, OPEN_SETUP, SHOP_TABLE }

var mode: int = Mode.NONE
var is_open: bool = false
var director: Node = null
var current_seal_no: int = 1
var is_final_seal: bool = false

var _selected_core_id: String = "core_rift"
var _prefer_focus_target: String = "auto"

var _font: Font = null
var _font_bold: Font = null
var _font_cinzel: Font = null
var _font_blackletter: Font = null
var _theme: Theme = null
var _root: Control = null
var _bg_canvas: Control = null
var _main_panel: PanelContainer = null
var _frame_deco: Control = null
var _content_box: VBoxContainer = null

var _core_btns: Array[Button] = []
var _core_meta: Array[Dictionary] = []
var _start_btn: Button = null
var _shop_card_btns: Array[Button] = []
var _draft_btns: Array[Button] = []
var _up_btn: Button = null
var _roll_btn: Button = null
var _go_btn: Button = null
var _hint_lbl: Label = null
var _stick := GamepadManager.StickRepeater.new()

## 背景慢雨、旋转 5:59 钟环与卡片焦点动效（墙钟时间驱动，暂停时流畅运行）
var _drops: Array = []
var _rng := RandomNumberGenerator.new()
var _anim_t: float = 0.0
var _last_us: int = 0
var _card_decos: Array[Control] = []


func _ready() -> void:
	GamepadManager.ensure_ui_actions()
	layer = 26
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 559
	if ResourceLoader.exists(FONT_SERIF_PATH):
		_font = load(FONT_SERIF_PATH) as Font
	if _font == null:
		_font = GothicFonts.serif(450)
	_font_bold = GothicFonts.serif(850)
	_font_cinzel = GothicFonts.cinzel(700, false, 850)
	_font_blackletter = GothicFonts.blackletter(700)
	if GamepadManager.instance != null and not GamepadManager.instance.device_changed.is_connected(_on_device_changed):
		GamepadManager.instance.device_changed.connect(_on_device_changed)
	_build_theme()
	_build_shell()
	close_overlay()


func _process(_delta: float) -> void:
	if not is_open:
		return
	var now_us := Time.get_ticks_usec()
	var dt := clampf(float(now_us - _last_us) / 1000000.0, 0.0, 0.05)
	_last_us = now_us
	_anim_t += dt
	_step_rain(dt)
	if _bg_canvas != null:
		_bg_canvas.queue_redraw()
	if _frame_deco != null:
		_frame_deco.queue_redraw()
	for deco in _card_decos:
		if is_instance_valid(deco):
			deco.queue_redraw()


func _seed_rain() -> void:
	var vp := get_viewport().get_visible_rect().size if get_viewport() != null else Vector2(1280, 720)
	_drops.clear()
	for _i in RAIN_COUNT:
		_drops.append([
			Vector2(_rng.randf_range(-40.0, vp.x + 140.0), _rng.randf_range(-40.0, vp.y)),
			_rng.randf_range(12.0, 30.0),
			_rng.randf_range(0.06, 0.22),
			_rng.randf_range(280.0, 480.0),
		])


func _step_rain(dt: float) -> void:
	if _drops.is_empty():
		_seed_rain()
	var vp := get_viewport().get_visible_rect().size if get_viewport() != null else Vector2(1280, 720)
	for d in _drops:
		var p: Vector2 = d[0]
		p += Vector2(RAIN_SLANT, 1.0) * float(d[3]) * dt
		if p.y > vp.y + 40.0:
			p = Vector2(_rng.randf_range(-40.0, vp.x + 140.0), _rng.randf_range(-60.0, -16.0))
		d[0] = p


func _draw_bg() -> void:
	if _bg_canvas == null:
		return
	var vp := _bg_canvas.get_viewport_rect().size
	var cx := vp.x * 0.5
	var cy := vp.y * 0.5

	# 1. 深墨幕底 + 边角暗幕
	_bg_canvas.draw_rect(Rect2(Vector2.ZERO, vp), Color(0.020, 0.018, 0.040, 0.88))
	_bg_canvas.draw_circle(Vector2(cx, cy), maxf(vp.x, vp.y) * 0.44, Color(0.10, 0.06, 0.18, 0.14))

	# 2. 旋转 5:59 哥特刻蚀巨钟虚影
	var dial_r := minf(vp.x, vp.y) * 0.46
	var rot := _anim_t * 0.055
	_bg_canvas.draw_arc(Vector2(cx, cy), dial_r, 0.0, TAU, 72, Color(COL_VIOLET_LIGHT, 0.10), 1.4, true)
	_bg_canvas.draw_arc(Vector2(cx, cy), dial_r * 0.88, 0.0, TAU, 64, Color(COL_SILVER, 0.07), 1.0, true)
	for i in 12:
		var ang := rot + float(i) * (TAU / 12.0)
		var p0 := Vector2(cx, cy) + Vector2(cos(ang), sin(ang)) * (dial_r * 0.88)
		var p1 := Vector2(cx, cy) + Vector2(cos(ang), sin(ang)) * dial_r
		_bg_canvas.draw_line(p0, p1, Color(COL_SILVER, 0.14 if i % 3 == 0 else 0.07), 2.0 if i % 3 == 0 else 1.0, true)
	# 冻结 5:59 指针剪影
	var h_ang := -PI * 0.5 + (5.95 / 12.0) * TAU
	var m_ang := -PI * 0.5 + (59.0 / 60.0) * TAU
	_bg_canvas.draw_line(Vector2(cx, cy), Vector2(cx, cy) + Vector2(cos(h_ang), sin(h_ang)) * (dial_r * 0.52), Color(COL_VIOLET, 0.14), 3.0, true)
	_bg_canvas.draw_line(Vector2(cx, cy), Vector2(cx, cy) + Vector2(cos(m_ang), sin(m_ang)) * (dial_r * 0.78), Color(COL_SILVER, 0.12), 1.8, true)

	# 3. 暗夜慢雨（世界暂停而雨丝不停）
	for d in _drops:
		var p: Vector2 = d[0]
		var l: float = float(d[1])
		_bg_canvas.draw_line(p, p + Vector2(RAIN_SLANT * l, l), Color(COL_RAIN, float(d[2])), 1.0, true)


func _draw_frame_deco() -> void:
	if _frame_deco == null:
		return
	var sz := _frame_deco.size
	if sz.x < 40.0 or sz.y < 40.0:
		return
	var pad := 6.0
	var inner := Rect2(pad, pad, sz.x - pad * 2.0, sz.y - pad * 2.0)
	_frame_deco.draw_rect(inner, Color(COL_VIOLET_LIGHT, 0.18), false, 1.0)

	# 四角哥特锻铁折角 + 冷紫菱钉
	var arm := 22.0
	var corners := [
		[Vector2(2.0, 2.0), Vector2(1.0, 0.0), Vector2(0.0, 1.0)],
		[Vector2(sz.x - 2.0, 2.0), Vector2(-1.0, 0.0), Vector2(0.0, 1.0)],
		[Vector2(2.0, sz.y - 2.0), Vector2(1.0, 0.0), Vector2(0.0, -1.0)],
		[Vector2(sz.x - 2.0, sz.y - 2.0), Vector2(-1.0, 0.0), Vector2(0.0, -1.0)],
	]
	for c in corners:
		var pt: Vector2 = c[0]
		var dx: Vector2 = c[1]
		var dy: Vector2 = c[2]
		_frame_deco.draw_line(pt, pt + dx * arm, Color(COL_SILVER, 0.72), 2.0, true)
		_frame_deco.draw_line(pt, pt + dy * arm, Color(COL_SILVER, 0.72), 2.0, true)
		_draw_diamond(_frame_deco, pt + dx * 8.0 + dy * 8.0, 3.2, Color(COL_VIOLET_LIGHT, 0.85), true)

	# 顶边与底边中央紫色空心菱徽
	_draw_diamond(_frame_deco, Vector2(sz.x * 0.5, 2.0), 6.0, COL_VIOLET_LIGHT, false)
	_draw_diamond(_frame_deco, Vector2(sz.x * 0.5, sz.y - 2.0), 5.0, Color(COL_SILVER, 0.65), false)


func _draw_diamond(canvas: Control, center: Vector2, r: float, col: Color, filled: bool) -> void:
	var pts := PackedVector2Array([
		center + Vector2(0.0, -r * 1.2),
		center + Vector2(r, 0.0),
		center + Vector2(0.0, r * 1.2),
		center + Vector2(-r, 0.0),
	])
	if filled:
		canvas.draw_colored_polygon(pts, col)
	else:
		pts.append(pts[0])
		canvas.draw_polyline(pts, col, 1.2, true)


func _on_device_changed(using_pad: bool) -> void:
	if not is_open:
		return
	# 原地刷新按键文案，绝不在 _input 派发中途销毁重建按钮树（防止吞掉首个手柄按键）
	if mode == Mode.OPEN_SETUP:
		if _start_btn != null and is_instance_valid(_start_btn):
			_start_btn.text = "[A / Start] 启程入夜" if using_pad else "[空格] 启程入夜"
		if _hint_lbl != null and is_instance_valid(_hint_lbl):
			_hint_lbl.text = "十字键 / 左摇杆 / LB·RB 切换本命核心　·　按 A 或 Start 立即开战" if using_pad else "按 1-4 或方向键择核心　·　空格 / 回车 启程入夜（支持手柄即插即用）"
	elif mode == Mode.SHOP_TABLE and director != null:
		if _up_btn != null and is_instance_valid(_up_btn) and int(director.player_tier) < director.MAX_PLAYER_TIER:
			_up_btn.text = "%s 升阶 (%d⚡ · 赐天赋)" % [("[Y]" if using_pad else "[U]"), int(director.upgrade_cost())]
		if _roll_btn != null and is_instance_valid(_roll_btn):
			_roll_btn.text = "[X] 换牌 (1⚡)" if using_pad else "[R] 换牌 (1⚡)"
		if _go_btn != null and is_instance_valid(_go_btn):
			var gk := "[Start]" if using_pad else "[空格]"
			_go_btn.text = ("%s 终局结算" % gk) if is_final_seal else ("%s 执刃出战" % gk)
		if _hint_lbl != null and is_instance_valid(_hint_lbl):
			if director.is_draft_active():
				_hint_lbl.text = "十字键 / 左摇杆 / LB·RB 择奖　·　按 A 确认刻印" if using_pad else "按 1-3 或方向键择奖　·　回车 / 空格 确认刻印"
			else:
				_hint_lbl.text = "十字键/摇杆 选牌 · A 购买 · Y 升阶 · X 换牌 · Start 出战" if using_pad else "按 1-4 买牌 · U 升阶 · R 换牌 · 空格 出战（全程支持手柄）"


func _build_theme() -> void:
	_theme = Theme.new()
	if _font != null:
		_theme.default_font = _font
	_theme.default_font_size = 16


func _build_shell() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.theme = _theme
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	_bg_canvas = Control.new()
	_bg_canvas.name = "GothicBackdrop"
	_bg_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_bg_canvas.draw.connect(_draw_bg)
	_root.add_child(_bg_canvas)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	_main_panel = PanelContainer.new()
	_main_panel.custom_minimum_size = Vector2(1080.0, 560.0)
	_main_panel.add_theme_stylebox_override("panel", _make_box(COL_PANEL_BG, Color("7b5cc4"), 2, 3, 24))
	center.add_child(_main_panel)

	_content_box = VBoxContainer.new()
	_content_box.add_theme_constant_override("separation", 14)
	_main_panel.add_child(_content_box)

	_frame_deco = Control.new()
	_frame_deco.name = "GothicFrameDeco"
	_frame_deco.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_frame_deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame_deco.draw.connect(_draw_frame_deco)
	_main_panel.add_child(_frame_deco)


func close_overlay() -> void:
	is_open = false
	mode = Mode.NONE
	visible = false
	_core_btns.clear()
	_core_meta.clear()
	_shop_card_btns.clear()
	_draft_btns.clear()
	_card_decos.clear()
	_start_btn = null
	_up_btn = null
	_roll_btn = null
	_go_btn = null
	if _root != null:
		_root.visible = false


func uses_only_open_source_fonts() -> bool:
	return _font != null and not (_font is SystemFont) and FONT_SERIF_PATH.begins_with("res://assets/fonts/")


func confirm_opening_with(c_id: String, _legacy_arg: String = "") -> void:
	_selected_core_id = c_id
	_confirm_opening()


func finish_table_now() -> void:
	_finish_table()


func _make_divider_ctrl(accent: Color = COL_VIOLET_LIGHT) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0.0, 14.0)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func() -> void:
		var w := c.size.x
		var cy := c.size.y * 0.5
		var cx := w * 0.5
		c.draw_line(Vector2(24.0, cy), Vector2(cx - 26.0, cy), Color(COL_SILVER, 0.28), 1.0, true)
		c.draw_line(Vector2(cx + 26.0, cy), Vector2(w - 24.0, cy), Color(COL_SILVER, 0.28), 1.0, true)
		c.draw_circle(Vector2(cx - 18.0, cy), 1.8, Color(COL_SILVER, 0.65))
		c.draw_circle(Vector2(cx + 18.0, cy), 1.8, Color(COL_SILVER, 0.65))
		_draw_diamond(c, Vector2(cx, cy), 5.5, accent, false)
	)
	return c


func _attach_card_deco(btn: Button, accent: Color, is_gold: bool = false, is_highlight: bool = false) -> void:
	var deco := Control.new()
	deco.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	deco.draw.connect(_draw_card_deco.bind(deco, btn, accent, is_gold, is_highlight))
	btn.add_child(deco)
	_card_decos.append(deco)


func _draw_card_deco(deco: Control, btn: Button, accent: Color, is_gold: bool, is_highlight: bool) -> void:
	if not is_instance_valid(btn):
		return
	var sz := deco.size
	if sz.x < 24.0 or sz.y < 24.0:
		return
	var focused := btn.has_focus() or btn.is_hovered()
	var disabled := btn.disabled
	var alpha := 0.22 if disabled else (1.0 if focused else 0.72)
	var stripe_col := COL_GOLD if is_gold else accent

	# 左侧哥特竖刃光条
	var bar_w := 5.0 if focused else 3.0
	deco.draw_rect(Rect2(2.0, 2.0, bar_w, sz.y - 4.0), Color(stripe_col, alpha))

	# 右上 / 右下微刻折角
	var rim := Color(COL_GOLD, alpha) if (focused or is_gold) else Color(COL_SILVER, 0.35 * alpha)
	deco.draw_line(Vector2(sz.x - 16.0, 3.0), Vector2(sz.x - 3.0, 3.0), rim, 1.4, true)
	deco.draw_line(Vector2(sz.x - 3.0, 3.0), Vector2(sz.x - 3.0, 16.0), rim, 1.4, true)
	deco.draw_line(Vector2(sz.x - 16.0, sz.y - 3.0), Vector2(sz.x - 3.0, sz.y - 3.0), rim, 1.4, true)
	deco.draw_line(Vector2(sz.x - 3.0, sz.y - 16.0), Vector2(sz.x - 3.0, sz.y - 3.0), rim, 1.4, true)

	# 顶部中央菱徽
	if not disabled:
		_draw_diamond(deco, Vector2(sz.x * 0.5, 4.0), 4.2 if focused else 3.2, Color(stripe_col, 0.85 * alpha), focused or is_highlight)

	# 金卡 / 即将合成卡：斜向微光丝纹
	if (is_gold or is_highlight) and not disabled:
		var pulse := 0.14 + 0.08 * sin(_anim_t * 3.6)
		deco.draw_line(Vector2(sz.x * 0.65, 4.0), Vector2(sz.x - 4.0, sz.y * 0.32), Color(COL_GOLD, pulse), 1.6, true)
		deco.draw_line(Vector2(sz.x * 0.78, 4.0), Vector2(sz.x - 4.0, sz.y * 0.20), Color(COL_SILVER, pulse * 0.8), 1.0, true)

	# 聚焦底边银紫流动光带
	if focused and not disabled:
		var sweep := 0.5 + 0.5 * sin(_anim_t * 4.5)
		var x0 := 14.0
		var x1 := sz.x - 14.0
		var y := sz.y - 5.0
		var pts := PackedVector2Array([Vector2(x0, y), Vector2(lerpf(x0, x1, sweep), y), Vector2(x1, y)])
		var cols := PackedColorArray([Color(stripe_col, 0.15), Color(COL_SILVER, 0.95), Color(stripe_col, 0.15)])
		deco.draw_polyline_colors(pts, cols, 2.0, true)


# ---------------------------------------------------------------- 1. 开局择 1 张本命核心

func open_opening_draft(p_director: Node) -> void:
	GamepadManager.ensure_ui_actions()
	director = p_director
	mode = Mode.OPEN_SETUP
	is_open = true
	visible = true
	_root.visible = true
	_last_us = Time.get_ticks_usec()
	if _drops.is_empty():
		_seed_rain()
	_main_panel.custom_minimum_size = Vector2(1060.0, 480.0)

	if director != null and director.catalog != null:
		var cores: Array[Dictionary] = director.catalog.get_core_cards()
		if not cores.is_empty() and _selected_core_id == "":
			_selected_core_id = String(cores[0]["card_id"])

	_rebuild_opening_ui()


func _rebuild_opening_ui() -> void:
	_clear_children(_content_box)
	_core_btns.clear()
	_core_meta.clear()
	_card_decos.clear()
	_start_btn = null
	if director == null or director.catalog == null:
		return

	var pad := GamepadManager.is_using_gamepad()

	var head_vb := VBoxContainer.new()
	head_vb.add_theme_constant_override("separation", 2)
	_content_box.add_child(head_vb)
	var epigraph := _make_label("ARCANA CORE · V:LIX", 14, Color(COL_STEEL, 0.9), HORIZONTAL_ALIGNMENT_CENTER, _font_cinzel)
	head_vb.add_child(epigraph)
	head_vb.add_child(_make_label("择定本命核心", 28, COL_BONE, HORIZONTAL_ALIGNMENT_CENTER, _font_bold))
	_content_box.add_child(_make_divider_ctrl(COL_VIOLET_LIGHT))

	var core_row := HBoxContainer.new()
	core_row.add_theme_constant_override("separation", 14)
	core_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content_box.add_child(core_row)

	var cores: Array[Dictionary] = director.catalog.get_core_cards()
	var sel_idx := 0
	for i in cores.size():
		var c: Dictionary = cores[i]
		var cid := String(c["card_id"])
		if cid == _selected_core_id:
			sel_idx = i
		var accent: Color = c.get("accent_color", COL_VIOLET)

		var btn := Button.new()
		btn.name = "Core_%d" % i
		btn.focus_mode = Control.FOCUS_ALL
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(236.0, 244.0)
		core_row.add_child(btn)
		_attach_card_deco(btn, accent, false, cid == _selected_core_id)

		var vb := VBoxContainer.new()
		vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 18)
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.alignment = BoxContainer.ALIGNMENT_CENTER
		vb.add_theme_constant_override("separation", 10)
		btn.add_child(vb)

		var roman := ROMAN_NUMS[i] if i < ROMAN_NUMS.size() else str(i + 1)
		vb.add_child(_make_label(roman, 15, Color(COL_STEEL, 0.85), HORIZONTAL_ALIGNMENT_CENTER, _font_cinzel))

		var title_prefix := String(c["title"]) if pad else "[%d] %s" % [i + 1, String(c["title"])]
		var title_lbl := _make_label(title_prefix, 22, COL_BONE, HORIZONTAL_ALIGNMENT_CENTER, _font_bold)
		vb.add_child(title_lbl)
		vb.add_child(_make_label("初始 Lv.10 · 三阶境界", 14, COL_GOLD, HORIZONTAL_ALIGNMENT_CENTER, _font_cinzel))
		vb.add_child(_make_label(String(c["summary"]), 15, Color("e6e2f2"), HORIZONTAL_ALIGNMENT_CENTER))
		vb.add_child(_make_label(String(c["subtitle"]), 13, Color("9fa6bc"), HORIZONTAL_ALIGNMENT_CENTER))

		_core_btns.append(btn)
		_core_meta.append({"cid": cid, "accent": accent, "title_lbl": title_lbl})

		btn.focus_entered.connect(_on_core_btn_focused.bind(cid))
		btn.pressed.connect(_on_core_btn_pressed.bind(cid))

	_start_btn = Button.new()
	_start_btn.name = "StartBtn"
	_start_btn.focus_mode = Control.FOCUS_ALL
	_start_btn.custom_minimum_size = Vector2(320.0, 50.0)
	_start_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_start_btn.text = "[A / Start] 启程入夜" if pad else "[空格] 启程入夜"
	_start_btn.add_theme_font_override("font", _font_bold)
	_start_btn.add_theme_font_size_override("font_size", 19)
	_start_btn.add_theme_color_override("font_color", Color("fff8e8"))
	_start_btn.add_theme_stylebox_override("normal", _make_box(Color("22163b"), COL_VIOLET_LIGHT, 2, 3, 10))
	_start_btn.add_theme_stylebox_override("hover", _make_box(Color("312054"), COL_GOLD, 2, 3, 10))
	_start_btn.add_theme_stylebox_override("focus", _make_box(Color("382460"), Color("fff4d4"), 3, 3, 10))
	_start_btn.add_theme_stylebox_override("pressed", _make_box(Color("422b70"), Color("fff4d4"), 3, 3, 10))
	_start_btn.pressed.connect(_confirm_opening)
	_content_box.add_child(_start_btn)
	_attach_card_deco(_start_btn, COL_GOLD, false, true)

	var hint_txt := "十字键 / 左摇杆 / LB·RB 切换本命核心　·　按 A 或 Start 立即开战" if pad else "按 1-4 或方向键择核心　·　空格 / 回车 启程入夜（支持手柄即插即用）"
	_hint_lbl = _make_label(hint_txt, 13, Color(COL_STEEL, 0.9), HORIZONTAL_ALIGNMENT_CENTER)
	_content_box.add_child(_hint_lbl)

	var n := _core_btns.size()
	for i in n:
		var b := _core_btns[i]
		b.focus_neighbor_left = _core_btns[(i + n - 1) % n].get_path()
		b.focus_neighbor_right = _core_btns[(i + 1) % n].get_path()
		b.focus_neighbor_bottom = _start_btn.get_path()
		b.focus_neighbor_top = _start_btn.get_path()
	if n > 0:
		_start_btn.focus_neighbor_top = _core_btns[sel_idx].get_path()
		_start_btn.focus_neighbor_bottom = _core_btns[sel_idx].get_path()
		_start_btn.focus_neighbor_left = _core_btns[maxi(sel_idx - 1, 0)].get_path()
		_start_btn.focus_neighbor_right = _core_btns[mini(sel_idx + 1, n - 1)].get_path()

	_update_opening_selection_visuals()
	if n > 0:
		_safe_focus.call_deferred(_core_btns[sel_idx])
	else:
		_safe_focus.call_deferred(_start_btn)


func _update_opening_selection_visuals() -> void:
	var sel_btn: Button = null
	for i in _core_btns.size():
		var btn := _core_btns[i]
		if not is_instance_valid(btn):
			continue
		var meta: Dictionary = _core_meta[i]
		var cid := String(meta["cid"])
		var accent: Color = meta["accent"]
		var title_lbl: Label = meta["title_lbl"]
		var selected := (cid == _selected_core_id)
		if selected:
			sel_btn = btn
		var bg := Color("161028") if selected else Color("0b0915")
		var border := accent if selected else Color("342e4a")
		btn.add_theme_stylebox_override("normal", _make_box(bg, border, 2 if selected else 1, 3, 16))
		btn.add_theme_stylebox_override("hover", _make_box(Color("1e1636"), accent, 2, 3, 16))
		btn.add_theme_stylebox_override("pressed", _make_box(Color("271c47"), COL_GOLD, 3, 3, 16))
		btn.add_theme_stylebox_override("focus", _make_box(Color("221840"), COL_GOLD, 3, 3, 16))
		if is_instance_valid(title_lbl):
			title_lbl.add_theme_color_override("font_color", accent if selected else COL_BONE)
	if sel_btn != null and _start_btn != null and is_instance_valid(_start_btn):
		_start_btn.focus_neighbor_top = sel_btn.get_path()
		_start_btn.focus_neighbor_bottom = sel_btn.get_path()


func _on_core_btn_focused(cid: String) -> void:
	if _selected_core_id != cid:
		_selected_core_id = cid
		_update_opening_selection_visuals()


func _on_core_btn_pressed(cid: String) -> void:
	if GamepadManager.is_using_gamepad() or _selected_core_id == cid:
		_selected_core_id = cid
		_confirm_opening()
	else:
		_selected_core_id = cid
		_update_opening_selection_visuals()


func _confirm_opening() -> void:
	if mode != Mode.OPEN_SETUP:
		return
	var c := _selected_core_id
	close_overlay()
	opening_confirmed.emit(c)


# ---------------------------------------------------------------- 2. 波间万象牌桌（升级赐天赋 · 合成赐锦囊）

func open_wanxiang_table(p_director: Node, seal_no: int, final_seal: bool = false) -> void:
	GamepadManager.ensure_ui_actions()
	director = p_director
	current_seal_no = seal_no
	is_final_seal = final_seal
	mode = Mode.SHOP_TABLE
	is_open = true
	visible = true
	_root.visible = true
	_last_us = Time.get_ticks_usec()
	if _drops.is_empty():
		_seed_rain()
	_prefer_focus_target = "auto"
	_main_panel.custom_minimum_size = Vector2(1090.0, 588.0)
	if director != null and not director.table_updated.is_connected(_on_director_table_updated):
		director.table_updated.connect(_on_director_table_updated)
	_rebuild_shop_ui()


func _on_director_table_updated() -> void:
	if is_open and mode == Mode.SHOP_TABLE:
		_rebuild_shop_ui()


func _capture_current_shop_focus() -> void:
	if get_viewport() == null:
		return
	var cur := get_viewport().gui_get_focus_owner()
	if cur == null:
		return
	for i in _shop_card_btns.size():
		if cur == _shop_card_btns[i]:
			_prefer_focus_target = "slot_%d" % i
			return
	if cur == _up_btn:
		_prefer_focus_target = "up"
	elif cur == _roll_btn:
		_prefer_focus_target = "roll"
	elif cur == _go_btn:
		_prefer_focus_target = "go"


func _rebuild_shop_ui() -> void:
	_clear_children(_content_box)
	_shop_card_btns.clear()
	_draft_btns.clear()
	_card_decos.clear()
	_up_btn = null
	_roll_btn = null
	_go_btn = null
	if director == null or director.catalog == null:
		return
	var rig: Node2D = director.perk_rig
	var pad := GamepadManager.is_using_gamepad()
	var in_draft: bool = director.is_draft_active()

	# --- 第 1 行：哥特顶栏（封印纪元 + 牌手等阶 + 已持天赋/技录状态 + 提示 + 能量） ---
	var top_bar := HBoxContainer.new()
	top_bar.add_theme_constant_override("separation", 12)
	_content_box.add_child(top_bar)

	var seal_r := ROMAN_NUMS[clampi(current_seal_no - 1, 0, ROMAN_NUMS.size() - 1)]
	top_bar.add_child(_make_label("封印 %s · 牌手 Lv.%d" % [seal_r, int(director.player_tier)], 20, COL_BONE, HORIZONTAL_ALIGNMENT_LEFT, _font_bold))

	var tags := ""
	for tid in director.active_talents:
		var tinfo: Dictionary = director.catalog.get_card(String(tid))
		tags += "【%s】" % String(tinfo.get("title", tid))
	if rig != null:
		if bool(rig.get("skill_unlock_all")):
			tags += " ✦全技解锁"
		elif int(rig.get("skill_early_unlocks")) > 0:
			tags += " ✦技阶+%d" % int(rig.get("skill_early_unlocks"))
		if int(rig.get("style_rank_floor")) >= 2:
			tags += " ✦保底B"
		if float(rig.get("lifesteal_ratio")) > 0.001:
			tags += " ✦吸血%d%%" % roundi(float(rig.get("lifesteal_ratio")) * 100.0)
		if bool(rig.get("attack_poise")):
			tags += " ✦霸体"
		elif int(rig.get("poise_max_charges")) > 0:
			tags += " ✦韧性%d" % int(rig.get("poise_max_charges"))
	if tags != "":
		var tag_lbl := _make_label(tags.strip_edges(), 14, Color("c4dcff"))
		tag_lbl.clip_text = true
		tag_lbl.custom_minimum_size.x = 240.0
		top_bar.add_child(tag_lbl)

	if bool(director.duplicator_armed):
		top_bar.add_child(_make_label("✦下张×2", 15, COL_GOLD, HORIZONTAL_ALIGNMENT_LEFT, _font_bold))

	var toast_lbl := _make_label(String(director.status_toast), 15, COL_GOLD, HORIZONTAL_ALIGNMENT_CENTER, _font_bold)
	toast_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(toast_lbl)

	var energy_panel := PanelContainer.new()
	energy_panel.add_theme_stylebox_override("panel", _make_box(Color("161124"), COL_GOLD, 1, 3, 6))
	energy_panel.add_child(_make_label("⚡ %d" % int(director.energy), 22, COL_GOLD, HORIZONTAL_ALIGNMENT_CENTER, _font_cinzel))
	top_bar.add_child(energy_panel)

	_content_box.add_child(_make_divider_ctrl(COL_GOLD if in_draft else COL_VIOLET_LIGHT))

	# --- 第 2 行：牌面槽位（1 核心 + 4 属性，满 3 格 ●●● 合成赐锦囊） ---
	var board_row := HBoxContainer.new()
	board_row.add_theme_constant_override("separation", 10)
	_content_box.add_child(board_row)

	var core_info: Dictionary = director.catalog.get_card(String(director.core_id))
	var core_lv: int = int(rig.core_level) if rig != null else 10
	var core_acc: Color = core_info.get("accent_color", COL_VIOLET)
	var core_pips := _format_pips(int(director.synth_pips.get("core", 0)), 3, "◆", "◇")

	var core_panel := PanelContainer.new()
	core_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	core_panel.size_flags_stretch_ratio = 1.9
	core_panel.add_theme_stylebox_override("panel", _make_box(Color("130e24"), core_acc, 2, 3, 10))
	board_row.add_child(core_panel)

	var cvb := VBoxContainer.new()
	cvb.add_theme_constant_override("separation", 4)
	core_panel.add_child(cvb)
	cvb.add_child(_make_label("◆ %s   Lv.%d   %s" % [
		String(core_info.get("title", "核心")), core_lv, core_pips
	], 18, core_acc, HORIZONTAL_ALIGNMENT_LEFT, _font_bold))

	var tier_hb := HBoxContainer.new()
	tier_hb.add_theme_constant_override("separation", 14)
	cvb.add_child(tier_hb)
	var m_keys := ["tier_10", "tier_40", "tier_100"]
	var m_reqs := [10, 40, 100]
	for mi in 3:
		var unlocked: bool = rig.has_core_tier(m_reqs[mi]) if rig != null else (mi == 0)
		var m_txt := ("✦ " if unlocked else "· ") + String(core_info.get(m_keys[mi], str(m_reqs[mi])))
		tier_hb.add_child(_make_label(m_txt, 13, COL_GOLD if unlocked else Color("68647e")))

	for st_id in ["stat_atk", "stat_spd", "stat_crit", "stat_def"]:
		var st_card: Dictionary = director.catalog.get_card(st_id)
		var st_lv: int = int(rig.stat_levels.get(st_id, 1)) if rig != null else 1
		var pip_cnt := int(director.synth_pips.get(st_id, 0))
		var st_pips := _format_pips(pip_cnt, 3, "◆", "◇")
		var sp := PanelContainer.new()
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sp.add_theme_stylebox_override("panel", _make_box(Color("0e0c1a"), COL_GOLD if pip_cnt == 2 else Color("3a3354"), 1, 3, 10))
		board_row.add_child(sp)
		var svb := VBoxContainer.new()
		svb.add_theme_constant_override("separation", 4)
		sp.add_child(svb)
		svb.add_child(_make_label("%s  Lv.%d" % [String(st_card.get("title", st_id)), st_lv], 16, st_card.get("accent_color", COL_SILVER), HORIZONTAL_ALIGNMENT_CENTER, _font_bold))
		svb.add_child(_make_label(st_pips, 13, COL_GOLD if pip_cnt == 2 else Color("8b86a3"), HORIZONTAL_ALIGNMENT_CENTER))

	# --- 第 3 行：中央选牌区（三选一天赋/锦囊 或 4 张哥特商店牌） ---
	if in_draft:
		_build_draft_zone(pad)
	else:
		_build_shop_cards_zone(pad)

	# --- 第 4 行：锻铁底栏（升阶赐天赋 · 换牌 · 执刃出战） ---
	var bottom_bar := HBoxContainer.new()
	bottom_bar.add_theme_constant_override("separation", 14)
	_content_box.add_child(bottom_bar)

	_up_btn = Button.new()
	_up_btn.name = "UpgradeBtn"
	_up_btn.focus_mode = Control.FOCUS_NONE if in_draft else Control.FOCUS_ALL
	_up_btn.custom_minimum_size = Vector2(266.0, 52.0)
	if int(director.player_tier) >= director.MAX_PLAYER_TIER:
		_up_btn.text = "已臻满阶 Lv.5"
		_up_btn.disabled = true
	else:
		var up_key := "[Y]" if pad else "[U]"
		_up_btn.text = "%s 升阶 (%d⚡ · 赐天赋)" % [up_key, int(director.upgrade_cost())]
		_up_btn.disabled = not director.can_upgrade_tier()
	_up_btn.add_theme_font_override("font", _font_bold)
	_up_btn.add_theme_font_size_override("font_size", 17)
	_up_btn.add_theme_color_override("font_color", Color("fff4d4"))
	_up_btn.add_theme_stylebox_override("normal", _make_box(Color("1e162e"), COL_GOLD, 2, 3, 10))
	_up_btn.add_theme_stylebox_override("hover", _make_box(Color("2c2042"), Color("fff4d4"), 2, 3, 10))
	_up_btn.add_theme_stylebox_override("focus", _make_box(Color("34254f"), Color("fff4d4"), 3, 3, 10))
	_up_btn.add_theme_stylebox_override("disabled", _make_box(Color("0c0a14"), Color("282238"), 1, 3, 10))
	_up_btn.pressed.connect(func() -> void:
		_prefer_focus_target = "up"
		director.upgrade_tier()
	)
	bottom_bar.add_child(_up_btn)
	_attach_card_deco(_up_btn, COL_GOLD, false, not _up_btn.disabled)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom_bar.add_child(spacer)

	_roll_btn = Button.new()
	_roll_btn.name = "RefreshBtn"
	_roll_btn.focus_mode = Control.FOCUS_NONE if in_draft else Control.FOCUS_ALL
	_roll_btn.custom_minimum_size = Vector2(182.0, 52.0)
	_roll_btn.text = ("[X] 换牌 (1⚡)" if pad else "[R] 换牌 (1⚡)")
	_roll_btn.disabled = not director.can_refresh_shop()
	_roll_btn.add_theme_font_override("font", _font_bold)
	_roll_btn.add_theme_font_size_override("font_size", 17)
	_roll_btn.add_theme_color_override("font_color", COL_SILVER)
	_roll_btn.add_theme_stylebox_override("normal", _make_box(Color("131024"), Color("8e74d4"), 2, 3, 10))
	_roll_btn.add_theme_stylebox_override("hover", _make_box(Color("1e1838"), COL_VIOLET_LIGHT, 2, 3, 10))
	_roll_btn.add_theme_stylebox_override("focus", _make_box(Color("271f47"), COL_GOLD, 3, 3, 10))
	_roll_btn.add_theme_stylebox_override("disabled", _make_box(Color("0c0a14"), Color("282238"), 1, 3, 10))
	_roll_btn.pressed.connect(func() -> void:
		_prefer_focus_target = "slot_0"
		director.refresh_shop()
	)
	bottom_bar.add_child(_roll_btn)
	_attach_card_deco(_roll_btn, COL_VIOLET_LIGHT, false, false)

	_go_btn = Button.new()
	_go_btn.name = "DeployBtn"
	_go_btn.focus_mode = Control.FOCUS_NONE if in_draft else Control.FOCUS_ALL
	_go_btn.custom_minimum_size = Vector2(226.0, 52.0)
	var go_key := "[Start]" if pad else "[空格]"
	_go_btn.text = ("%s 终局结算" % go_key) if is_final_seal else ("%s 执刃出战" % go_key)
	_go_btn.disabled = in_draft
	_go_btn.add_theme_font_override("font", _font_bold)
	_go_btn.add_theme_font_size_override("font_size", 18)
	_go_btn.add_theme_color_override("font_color", Color("fff8e8"))
	_go_btn.add_theme_stylebox_override("normal", _make_box(Color("261842"), COL_VIOLET_LIGHT, 2, 3, 10))
	_go_btn.add_theme_stylebox_override("hover", _make_box(Color("35215c"), COL_GOLD, 2, 3, 10))
	_go_btn.add_theme_stylebox_override("focus", _make_box(Color("3f276e"), Color("fff4d4"), 3, 3, 10))
	_go_btn.add_theme_stylebox_override("disabled", _make_box(Color("0c0a14"), Color("282238"), 1, 3, 10))
	_go_btn.pressed.connect(_finish_table)
	bottom_bar.add_child(_go_btn)
	_attach_card_deco(_go_btn, COL_VIOLET, false, not _go_btn.disabled)

	var bar_hint := ""
	if in_draft:
		bar_hint = "十字键 / 左摇杆 / LB·RB 择奖　·　按 A 确认刻印" if pad else "按 1-3 或方向键择奖　·　回车 / 空格 确认刻印"
	else:
		bar_hint = "十字键/摇杆 选牌 · A 购买 · Y 升阶 · X 换牌 · Start 出战" if pad else "按 1-4 买牌 · U 升阶 · R 换牌 · 空格 出战（全程支持手柄）"
	_hint_lbl = _make_label(bar_hint, 13, Color(COL_STEEL, 0.88), HORIZONTAL_ALIGNMENT_CENTER)
	_content_box.add_child(_hint_lbl)

	_wire_and_restore_shop_focus(in_draft)


func _build_shop_cards_zone(pad: bool) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.custom_minimum_size.y = 256.0
	_content_box.add_child(row)

	for i in director.shop_slots.size():
		var slot: Dictionary = director.shop_slots[i]
		var bought := bool(slot.get("bought", false))
		var kind := String(slot.get("card_kind", "stat"))
		var is_core := (kind == "core")
		var is_effect := (kind == "effect")
		var is_gold := bool(slot.get("is_gold", false))
		var cost_val := int(slot.get("cost", 2))
		var gain_val := int(slot.get("gain", 6))
		var accent: Color = slot.get("accent_color", COL_VIOLET)
		var will_synth: bool = director.will_slot_synthesize(slot)

		var card_btn := Button.new()
		card_btn.name = "ShopCard_%d" % i
		card_btn.focus_mode = Control.FOCUS_ALL
		card_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card_btn.custom_minimum_size = Vector2(236.0, 250.0)
		card_btn.disabled = bought or (int(director.energy) < cost_val)

		var bg := Color("0a0812") if bought else (Color("1e1710") if is_gold else (Color("17102c") if is_core else (Color("101724") if is_effect else Color("0f0d1c"))))
		var bd := Color("231e33") if bought else (COL_GOLD if (is_gold or will_synth) else (accent if (is_core or is_effect) else Color("4a3e6b")))
		card_btn.add_theme_stylebox_override("normal", _make_box(bg, bd, 2 if (is_gold or is_core or will_synth) else 1, 3, 14))
		card_btn.add_theme_stylebox_override("hover", _make_box(bg.lightened(0.08), COL_GOLD, 2, 3, 14))
		card_btn.add_theme_stylebox_override("focus", _make_box(bg.lightened(0.14), Color("fff4d4"), 3, 3, 14))
		card_btn.add_theme_stylebox_override("disabled", _make_box(Color("0a0812"), Color("221d30"), 1, 3, 14))
		card_btn.pressed.connect(_on_shop_card_pressed.bind(i))
		row.add_child(card_btn)
		_shop_card_btns.append(card_btn)
		_attach_card_deco(card_btn, accent, is_gold, will_synth)

		var vb := VBoxContainer.new()
		vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 16)
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.alignment = BoxContainer.ALIGNMENT_CENTER
		vb.add_theme_constant_override("separation", 12)
		card_btn.add_child(vb)

		if bought:
			vb.add_child(_make_label("已刻印", 18, Color("56506b"), HORIZONTAL_ALIGNMENT_CENTER, _font_bold))
			continue

		# 顶部类别与稀有度微标
		var rarity_lbl := String(slot.get("rarity_label", ""))
		var rarity_col: Color = slot.get("rarity_color", COL_STEEL)
		var kind_tag := "GOLD ARCANA" if is_gold else ("CORE" if is_core else (("RELIC · " + rarity_lbl) if is_effect and rarity_lbl != "" else "STAT"))
		var tag_col := COL_GOLD if is_gold else (rarity_col if is_effect else Color(COL_STEEL, 0.85))
		vb.add_child(_make_label(kind_tag, 12, tag_col, HORIZONTAL_ALIGNMENT_CENTER, _font_cinzel))

		# 锚点 1：牌名
		var head_prefix := "◆ " if is_core else ""
		var title_txt := "%s%s" % [head_prefix, String(slot["title"])] if pad else "[%d] %s%s" % [i + 1, head_prefix, String(slot["title"])]
		vb.add_child(_make_label(title_txt, 20, accent, HORIZONTAL_ALIGNMENT_CENTER, _font_bold))

		# 锚点 2：大号核心数值（或效果说明）
		if is_effect:
			var sum_lbl := _make_label(String(slot["summary"]), 19, COL_BONE, HORIZONTAL_ALIGNMENT_CENTER, _font_bold)
			sum_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			vb.add_child(sum_lbl)
		elif is_gold:
			vb.add_child(_make_label("✦ +%d 级" % gain_val, 27, COL_GOLD, HORIZONTAL_ALIGNMENT_CENTER, _font_cinzel))
		else:
			vb.add_child(_make_label("+%d 级" % gain_val, 27, COL_BONE, HORIZONTAL_ALIGNMENT_CENTER, _font_cinzel))

		# 锚点 3：合成提示 + 价格
		if will_synth:
			vb.add_child(_make_label("◆◆◆ 三合赐锦囊!", 14, COL_GOLD, HORIZONTAL_ALIGNMENT_CENTER, _font_bold))
		elif is_effect:
			vb.add_child(_make_label("秘药 · 效果牌", 13, Color("a4bfd9"), HORIZONTAL_ALIGNMENT_CENTER))
		else:
			vb.add_child(_make_label("◆◆ 双格充能" if is_gold else "◆ +1 合成格", 13, Color("8f89a8"), HORIZONTAL_ALIGNMENT_CENTER))

		var price_txt := "0⚡ 免单" if cost_val == 0 else "%d⚡" % cost_val
		var price_col := COL_MINT if cost_val == 0 else (COL_GOLD if int(director.energy) >= cost_val else Color("6e6380"))
		vb.add_child(_make_label(price_txt, 19, price_col, HORIZONTAL_ALIGNMENT_CENTER, _font_cinzel))


func _build_draft_zone(pad: bool) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.custom_minimum_size.y = 256.0
	_content_box.add_child(box)

	var is_talent := (String(director.pending_draft_kind) == "talent")
	var sub_en := "ASCENSION TALENT" if is_talent else "SYNTHESIS TACTIC"
	var head_txt := "✦ 升阶至 Lv.%d · 择一永久天赋" % int(director.player_tier) if is_talent else "✦ 三合天成 · 择一瞬发锦囊"
	box.add_child(_make_label(sub_en, 12, Color(COL_STEEL, 0.9), HORIZONTAL_ALIGNMENT_CENTER, _font_cinzel))
	box.add_child(_make_label(head_txt, 21, COL_GOLD, HORIZONTAL_ALIGNMENT_CENTER, _font_bold))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(row)

	for i in director.pending_draft_choices.size():
		var item: Dictionary = director.pending_draft_choices[i]
		var acc: Color = item.get("accent_color", COL_GOLD)
		var btn := Button.new()
		btn.name = "Draft_%d" % i
		btn.focus_mode = Control.FOCUS_ALL
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(308.0, 200.0)
		btn.add_theme_stylebox_override("normal", _make_box(Color("161128"), acc, 2, 3, 16))
		btn.add_theme_stylebox_override("hover", _make_box(Color("22193c"), Color("fff4d4"), 2, 3, 16))
		btn.add_theme_stylebox_override("focus", _make_box(Color("2a1f4a"), Color("fff4d4"), 3, 3, 16))
		btn.add_theme_stylebox_override("pressed", _make_box(Color("34265c"), Color("fff4d4"), 3, 3, 16))
		btn.pressed.connect(_on_draft_card_pressed.bind(i))
		row.add_child(btn)
		_draft_btns.append(btn)
		_attach_card_deco(btn, acc, not is_talent, true)

		var vb := VBoxContainer.new()
		vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 18)
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.alignment = BoxContainer.ALIGNMENT_CENTER
		vb.add_theme_constant_override("separation", 12)
		btn.add_child(vb)

		var rarity_lbl := String(item.get("rarity_label", "普通"))
		var rarity_col: Color = item.get("rarity_color", COL_STEEL)
		var badge := ("%s · 天赋刻印" if is_talent else "%s · 瞬发锦囊") % rarity_lbl
		vb.add_child(_make_label(badge, 13, rarity_col, HORIZONTAL_ALIGNMENT_CENTER, _font_bold))
		var dt_txt := String(item.get("title", "")) if pad else "[%d] %s" % [i + 1, String(item.get("title", ""))]
		vb.add_child(_make_label(dt_txt, 23, acc, HORIZONTAL_ALIGNMENT_CENTER, _font_bold))
		var desc_lbl := _make_label(String(item.get("summary", "")), 16, COL_BONE, HORIZONTAL_ALIGNMENT_CENTER)
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(desc_lbl)


func _on_shop_card_pressed(slot_idx: int) -> void:
	_prefer_focus_target = "slot_%d" % slot_idx
	if director != null:
		director.buy_slot(slot_idx)


func _on_draft_card_pressed(choice_idx: int) -> void:
	if director != null:
		director.pick_draft_choice(choice_idx)


func _wire_and_restore_shop_focus(in_draft: bool) -> void:
	if in_draft:
		var dn := _draft_btns.size()
		for i in dn:
			var db := _draft_btns[i]
			db.focus_neighbor_left = _draft_btns[(i + dn - 1) % dn].get_path()
			db.focus_neighbor_right = _draft_btns[(i + 1) % dn].get_path()
			db.focus_neighbor_top = db.get_path()
			db.focus_neighbor_bottom = db.get_path()
		if dn > 0:
			_safe_focus.call_deferred(_draft_btns[0])
		return

	var cn := _shop_card_btns.size()
	var bot_btns: Array[Button] = [_up_btn, _roll_btn, _go_btn]
	for i in cn:
		var cb := _shop_card_btns[i]
		cb.focus_neighbor_left = _shop_card_btns[(i + cn - 1) % cn].get_path()
		cb.focus_neighbor_right = _shop_card_btns[(i + 1) % cn].get_path()
		var down_target: Button = _go_btn
		if i <= 1 and _up_btn != null and not _up_btn.disabled:
			down_target = _up_btn
		elif i == 2 and _roll_btn != null and not _roll_btn.disabled:
			down_target = _roll_btn
		elif _roll_btn != null and not _roll_btn.disabled and i <= 1:
			down_target = _roll_btn
		cb.focus_neighbor_bottom = down_target.get_path()
		cb.focus_neighbor_top = down_target.get_path()

	for bi in bot_btns.size():
		var bb := bot_btns[bi]
		if bb == null:
			continue
		bb.focus_neighbor_left = bot_btns[(bi + bot_btns.size() - 1) % bot_btns.size()].get_path()
		bb.focus_neighbor_right = bot_btns[(bi + 1) % bot_btns.size()].get_path()
		if cn > 0:
			var up_idx := clampi(bi + (1 if bi > 0 else 0), 0, cn - 1)
			bb.focus_neighbor_top = _shop_card_btns[up_idx].get_path()
			bb.focus_neighbor_bottom = _shop_card_btns[up_idx].get_path()

	var target_ctrl: Control = null
	if _prefer_focus_target.begins_with("slot_"):
		var sidx := int(_prefer_focus_target.trim_prefix("slot_"))
		if sidx >= 0 and sidx < cn and not _shop_card_btns[sidx].disabled:
			target_ctrl = _shop_card_btns[sidx]
		else:
			for k in cn:
				var try_i := (sidx + k) % maxi(cn, 1)
				if not _shop_card_btns[try_i].disabled:
					target_ctrl = _shop_card_btns[try_i]
					break
	elif _prefer_focus_target == "up" and _up_btn != null and not _up_btn.disabled:
		target_ctrl = _up_btn
	elif _prefer_focus_target == "roll" and _roll_btn != null and not _roll_btn.disabled:
		target_ctrl = _roll_btn
	elif _prefer_focus_target == "go" and _go_btn != null:
		target_ctrl = _go_btn

	if target_ctrl == null:
		for cb in _shop_card_btns:
			if not cb.disabled:
				target_ctrl = cb
				break
	if target_ctrl == null:
		if _up_btn != null and not _up_btn.disabled:
			target_ctrl = _up_btn
		elif _roll_btn != null and not _roll_btn.disabled:
			target_ctrl = _roll_btn
		else:
			target_ctrl = _go_btn

	if target_ctrl != null:
		_safe_focus.call_deferred(target_ctrl)


func _safe_focus(ctrl: Control) -> void:
	if is_open and ctrl != null and is_instance_valid(ctrl) and ctrl.is_inside_tree() and ctrl.focus_mode != Control.FOCUS_NONE:
		ctrl.grab_focus()


func _finish_table() -> void:
	if mode != Mode.SHOP_TABLE:
		return
	if director != null and director.is_draft_active():
		return
	close_overlay()
	table_finished.emit()


func _step_horizontal_focus(step: int) -> void:
	if mode == Mode.OPEN_SETUP and not _core_btns.is_empty():
		var idx := 0
		for i in _core_meta.size():
			if String(_core_meta[i]["cid"]) == _selected_core_id:
				idx = i
				break
		var nxt := wrapi(idx + step, 0, _core_btns.size())
		_selected_core_id = String(_core_meta[nxt]["cid"])
		_update_opening_selection_visuals()
		_safe_focus(_core_btns[nxt])
		return
	if mode == Mode.SHOP_TABLE:
		var arr: Array[Button] = _draft_btns if (director != null and director.is_draft_active()) else _shop_card_btns
		if arr.is_empty():
			return
		var cur := get_viewport().gui_get_focus_owner() if get_viewport() != null else null
		var cur_i := arr.find(cur as Button) if cur is Button else 0
		if cur_i < 0:
			cur_i = 0
		var nxt_i := wrapi(cur_i + step, 0, arr.size())
		_safe_focus(arr[nxt_i])


# ---------------------------------------------------------------- 3. 单手键盘热键 + Xbox/通用手柄快捷操作

func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return

	if event is InputEventJoypadButton:
		var jb := event as InputEventJoypadButton
		if not jb.pressed or jb.echo:
			return
		GamepadManager.set_using_gamepad(true)

		if mode == Mode.OPEN_SETUP:
			match jb.button_index:
				JOY_BUTTON_LEFT_SHOULDER:
					_step_horizontal_focus(-1)
					get_viewport().set_input_as_handled()
				JOY_BUTTON_RIGHT_SHOULDER:
					_step_horizontal_focus(1)
					get_viewport().set_input_as_handled()
				JOY_BUTTON_A, JOY_BUTTON_START:
					_confirm_opening()
					get_viewport().set_input_as_handled()
			return

		if mode == Mode.SHOP_TABLE and director != null:
			if director.is_draft_active():
				match jb.button_index:
					JOY_BUTTON_LEFT_SHOULDER:
						_step_horizontal_focus(-1)
						get_viewport().set_input_as_handled()
					JOY_BUTTON_RIGHT_SHOULDER:
						_step_horizontal_focus(1)
						get_viewport().set_input_as_handled()
					JOY_BUTTON_A:
						var f_owner := get_viewport().gui_get_focus_owner() if get_viewport() != null else null
						var di := _draft_btns.find(f_owner as Button) if f_owner is Button else 0
						director.pick_draft_choice(maxi(di, 0))
						get_viewport().set_input_as_handled()
				return

			match jb.button_index:
				JOY_BUTTON_LEFT_SHOULDER:
					_step_horizontal_focus(-1)
					get_viewport().set_input_as_handled()
				JOY_BUTTON_RIGHT_SHOULDER:
					_step_horizontal_focus(1)
					get_viewport().set_input_as_handled()
				JOY_BUTTON_Y:
					if director.can_upgrade_tier():
						_prefer_focus_target = "up"
						director.upgrade_tier()
					get_viewport().set_input_as_handled()
				JOY_BUTTON_X:
					if director.can_refresh_shop():
						_prefer_focus_target = "slot_0"
						director.refresh_shop()
					get_viewport().set_input_as_handled()
				JOY_BUTTON_START:
					_finish_table()
					get_viewport().set_input_as_handled()
				JOY_BUTTON_A:
					var f_cur := get_viewport().gui_get_focus_owner() if get_viewport() != null else null
					if f_cur == null:
						_wire_and_restore_shop_focus(false)
					get_viewport().set_input_as_handled()
		return

	if not (event is InputEventKey):
		return
	var k := event as InputEventKey
	if not k.pressed or k.echo:
		return
	GamepadManager.set_using_gamepad(false)

	if mode == Mode.OPEN_SETUP:
		var cores: Array[Dictionary] = director.catalog.get_core_cards() if (director != null and director.catalog != null) else []
		if k.keycode == KEY_1 and cores.size() >= 1:
			_selected_core_id = String(cores[0]["card_id"])
			_rebuild_opening_ui()
			get_viewport().set_input_as_handled()
		elif k.keycode == KEY_2 and cores.size() >= 2:
			_selected_core_id = String(cores[1]["card_id"])
			_rebuild_opening_ui()
			get_viewport().set_input_as_handled()
		elif k.keycode == KEY_3 and cores.size() >= 3:
			_selected_core_id = String(cores[2]["card_id"])
			_rebuild_opening_ui()
			get_viewport().set_input_as_handled()
		elif k.keycode == KEY_4 and cores.size() >= 4:
			_selected_core_id = String(cores[3]["card_id"])
			_rebuild_opening_ui()
			get_viewport().set_input_as_handled()
		elif k.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
			_confirm_opening()
			get_viewport().set_input_as_handled()
		return

	if mode == Mode.SHOP_TABLE and director != null:
		if director.is_draft_active():
			if k.keycode == KEY_1:
				director.pick_draft_choice(0)
				get_viewport().set_input_as_handled()
			elif k.keycode == KEY_2:
				director.pick_draft_choice(1)
				get_viewport().set_input_as_handled()
			elif k.keycode == KEY_3:
				director.pick_draft_choice(2)
				get_viewport().set_input_as_handled()
			return

		match k.keycode:
			KEY_1:
				_prefer_focus_target = "slot_0"
				director.buy_slot(0)
				get_viewport().set_input_as_handled()
			KEY_2:
				_prefer_focus_target = "slot_1"
				director.buy_slot(1)
				get_viewport().set_input_as_handled()
			KEY_3:
				_prefer_focus_target = "slot_2"
				director.buy_slot(2)
				get_viewport().set_input_as_handled()
			KEY_4:
				_prefer_focus_target = "slot_3"
				director.buy_slot(3)
				get_viewport().set_input_as_handled()
			KEY_U:
				_prefer_focus_target = "up"
				director.upgrade_tier()
				get_viewport().set_input_as_handled()
			KEY_R:
				_prefer_focus_target = "slot_0"
				director.refresh_shop()
				get_viewport().set_input_as_handled()
			KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
				_finish_table()
				get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- 样式辅助

func _format_pips(cur: int, total: int, full_ch: String, empty_ch: String) -> String:
	var out := ""
	for i in total:
		out += full_ch if i < cur else empty_ch
	return out


func _make_label(txt: String, fsize: int, col: Color, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, custom_font: Font = null) -> Label:
	var lbl := Label.new()
	lbl.text = txt
	lbl.horizontal_alignment = align
	if custom_font != null:
		lbl.add_theme_font_override("font", custom_font)
	lbl.add_theme_font_size_override("font_size", fsize)
	lbl.add_theme_color_override("font_color", col)
	return lbl


func _make_box(bg: Color, border: Color, bw: int, radius: int, pad: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(float(pad))
	return sb


func _clear_children(node: Node) -> void:
	if node == null:
		return
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()
