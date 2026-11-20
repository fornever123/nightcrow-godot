extends CanvasLayer
## 首领战「司晷 · 断晷天井」结算页：使用思源宋体与哥特字体展示评价、用时、弹刀、撞碑、断壳爆核与染紫逆爆，支持重战或返回影街新一轮。
signal restart_requested()
signal new_run_requested()

const BossFonts := preload("res://scripts/boss_sample/boss_fonts.gd")
const GamepadManager := preload("res://scripts/core/gamepad_manager.gd")
const GRADE_COLOR := {"S": Color("ffe0a2"), "A": Color("dfe8ff"), "B": Color("c7d3e5"), "C": Color("9caec5"), "D": Color("7c8aa0")}

var summary: Dictionary = {}
var result_font: Font
var _cn_font: Font
var _gothic_font: Font


func _ready() -> void:
	GamepadManager.ensure_ui_actions()
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	_cn_font = BossFonts.load_font(BossFonts.SERIF_SC)
	_gothic_font = BossFonts.load_font(BossFonts.GOTHIC_PIRATA)
	var base_font: Font = _cn_font if _cn_font != null else result_font

	var screen := ColorRect.new()
	screen.name = "Screen"
	screen.color = Color(0.015, 0.022, 0.042, 0.80)
	add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if base_font != null:
		var theme := Theme.new()
		theme.default_font = base_font
		theme.default_font_size = 20
		screen.theme = theme

	var center := CenterContainer.new()
	screen.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var rows := VBoxContainer.new()
	rows.name = "Rows"
	rows.custom_minimum_size = Vector2(540, 0)
	rows.add_theme_constant_override("separation", 12)
	center.add_child(rows)

	_label(rows, String(summary.get("name", "")) + " · 断晓归位", 34, Color("eef2fa"), _cn_font)
	var g := String(summary.get("grade", "D"))
	_label(rows, g, 104, GRADE_COLOR.get(g, Color.WHITE), _gothic_font if _gothic_font != null else _cn_font)

	var seconds := int(summary.get("seconds", 0.0))
	_label(rows, "用时  %d:%02d     挨打  %d 下" % [seconds / 60, seconds % 60, int(summary.get("hits", 0))], 22, Color("c7d3e5"), _cn_font)
	_label(rows, "弹刀  %d     轰塔  %d     拽回  %d" % [
		int(summary.get("parry", 0)),
		int(summary.get("wall", 0)),
		int(summary.get("yanks", 0)),
	], 19, Color("9caec5"), _cn_font)
	_label(rows, "断甲改造核  +%d     染紫反杀  %d" % [
		int(summary.get("cores", 0)),
		int(summary.get("purple_rifts", 0)),
	], 20, Color("ffd984"), _cn_font)

	var btn_row := HBoxContainer.new()
	btn_row.name = "Buttons"
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 16)
	rows.add_child(btn_row)

	var retry := Button.new()
	retry.name = "Retry"
	retry.focus_mode = Control.FOCUS_ALL
	retry.text = "再战塔顶  ·  A / F5" if GamepadManager.is_using_gamepad() else "再战塔顶  ·  F5"
	retry.custom_minimum_size = Vector2(240, 48)
	retry.pressed.connect(func(): restart_requested.emit())
	btn_row.add_child(retry)

	var street := Button.new()
	street.name = "NewStreetRun"
	street.focus_mode = Control.FOCUS_ALL
	street.text = "返回影街新一轮"
	street.custom_minimum_size = Vector2(240, 48)
	street.pressed.connect(func(): new_run_requested.emit())
	btn_row.add_child(street)

	retry.focus_neighbor_right = street.get_path()
	retry.focus_neighbor_left = street.get_path()
	street.focus_neighbor_left = retry.get_path()
	street.focus_neighbor_right = retry.get_path()
	retry.grab_focus.call_deferred()


func _label(rows: VBoxContainer, text: String, fsize: int, color: Color, font_override: Font = null) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if font_override != null:
		label.add_theme_font_override("font", font_override)
	label.add_theme_font_size_override("font_size", fsize)
	label.add_theme_color_override("font_color", color)
	rows.add_child(label)


func _unhandled_input(event: InputEvent) -> void:
	var pad_reset := event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed and not event.is_echo() and (event as InputEventJoypadButton).button_index == JOY_BUTTON_BACK
	if (event.is_action_pressed("reset") or pad_reset) and not event.is_echo():
		get_viewport().set_input_as_handled()
		restart_requested.emit()
