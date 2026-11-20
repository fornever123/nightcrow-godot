extends CanvasLayer
## 仅用于有限试玩的结果页。世界暂停后仍响应按钮、方向导航、手柄 A 确认和 F5/Back 重玩。
## 字体统一走开源商用哥特 / 石刻 / 重宋（GothicFonts）。
signal restart_requested()

const GothicFonts := preload("res://scripts/ui/gothic_fonts.gd")
const GamepadManager := preload("res://scripts/core/gamepad_manager.gd")
const TITLE_SCENE := "res://scenes/yg_title_zhanzhong.tscn"

var summary: Dictionary = {}
var result_font: Font
var _body_font: Font
var _title_font: Font
var _grade_font: Font
var _hint_lbl: Label


func _ready() -> void:
	GamepadManager.ensure_ui_actions()
	GamepadManager.stop_all_rumble()
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	if result_font is FontVariation or result_font is FontFile:
		_body_font = result_font
	else:
		_body_font = GothicFonts.cinzel(500, false, 450)
	_title_font = GothicFonts.cinzel(800, false, 900)
	_grade_font = GothicFonts.blackletter(700)

	var screen := ColorRect.new()
	screen.name = "Screen"
	screen.color = Color(0.015, 0.025, 0.05, 0.84)
	add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var theme := Theme.new()
	theme.default_font = _body_font
	theme.default_font_size = 20
	screen.theme = theme
	var center := CenterContainer.new()
	center.name = "Center"
	screen.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.custom_minimum_size = Vector2(540, 0)
	var box := StyleBoxFlat.new()
	box.bg_color = Color("0b101d")
	box.border_color = Color("b4bbc7")
	box.set_border_width_all(1)
	box.content_margin_left = 32.0
	box.content_margin_right = 32.0
	box.content_margin_top = 26.0
	box.content_margin_bottom = 24.0
	panel.add_theme_stylebox_override("panel", box)
	center.add_child(panel)
	var rows := VBoxContainer.new()
	rows.name = "Rows"
	rows.add_theme_constant_override("separation", 12)
	panel.add_child(rows)
	_label(rows, "三处封印 · 全部解除", 30, Color("ece8de"), _title_font)
	var grade := String(summary.get("grade", "D"))
	_label(rows, grade, 68, Color("e6e9ef"), _grade_font)
	_label(rows, "雨街战斗试玩完成", 18, Color("9aa6ba"), _body_font)
	var seconds := int(summary.get("seconds", 0.0))
	var stats := "总用时  %d:%02d     最高连击  %d\n挑飞  %d     下砸  %d     撞墙  %d\n连锁  %d     弹刀  %d     受击  %d 次" % [
		seconds / 60, seconds % 60, int(summary.get("max_combo", 0)),
		int(summary.get("launch", 0)), int(summary.get("slam", 0)), int(summary.get("wall", 0)),
		int(summary.get("chain", 0)), int(summary.get("parry", 0)), int(summary.get("times_hit", 0))]
	_label(rows, stats, 19, Color("c7d3e5"), _body_font)

	var retry := Button.new()
	retry.name = "Retry"
	retry.text = "再试一次  ·  Back" if GamepadManager.is_using_gamepad() else "再试一次  ·  F5"
	retry.custom_minimum_size.y = 48
	_style_button(retry)
	retry.pressed.connect(func():
		_silence_stage_media()
		restart_requested.emit()
	)
	rows.add_child(retry)

	var to_title := Button.new()
	to_title.name = "ToTitle"
	to_title.text = "回到标题"
	to_title.custom_minimum_size.y = 44
	_style_button(to_title)
	to_title.pressed.connect(_go_title)
	rows.add_child(to_title)

	var leave := Button.new()
	leave.name = "Leave"
	leave.text = "退出试玩"
	leave.custom_minimum_size.y = 44
	_style_button(leave)
	leave.pressed.connect(func():
		_silence_stage_media()
		get_tree().quit()
	)
	rows.add_child(leave)

	retry.focus_neighbor_top = leave.get_path()
	retry.focus_neighbor_bottom = to_title.get_path()
	to_title.focus_neighbor_top = retry.get_path()
	to_title.focus_neighbor_bottom = leave.get_path()
	leave.focus_neighbor_top = to_title.get_path()
	leave.focus_neighbor_bottom = retry.get_path()
	retry.grab_focus.call_deferred()

	var hint := "方向键 / 左摇杆选择，按 A 确认，Back 重试" if GamepadManager.is_using_gamepad() else "战斗已暂停，可用方向键/手柄选择，回车 / A 确认"
	_hint_lbl = _label(rows, hint, 15, Color("7f8ba0"), _body_font)


func _style_button(btn: Button) -> void:
	btn.focus_mode = Control.FOCUS_ALL
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("131b2e")
	normal.border_color = Color("5c6b85")
	normal.set_border_width_all(1)
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color("222d4a")
	focus.border_color = Color("f5dfa3")
	focus.set_border_width_all(3)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", focus)
	btn.add_theme_stylebox_override("focus", focus)
	btn.add_theme_stylebox_override("pressed", focus)
	btn.add_theme_color_override("font_color", Color("dfe7f5"))
	btn.add_theme_color_override("font_focus_color", Color("fff8e6"))
	btn.add_theme_color_override("font_hover_color", Color("fff8e6"))


func _label(rows: VBoxContainer, text: String, size: int, color: Color, font: Font = null) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if font != null:
		label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	rows.add_child(label)
	return label


func _go_title() -> void:
	_silence_stage_media()
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file.call_deferred(TITLE_SCENE)


func _silence_stage_media() -> void:
	var st := get_parent()
	if st == null:
		return
	var pm := st.get_node_or_null("PauseMenu")
	if pm != null and pm.has_method("_silence_stage_audio"):
		pm._silence_stage_audio()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("reset") and not event.is_echo():
		get_viewport().set_input_as_handled()
		_silence_stage_media()
		restart_requested.emit()
