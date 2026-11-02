extends CanvasLayer
## 仅用于有限试玩的结果页。世界暂停后仍响应按钮、方向导航和R重玩。
signal restart_requested()

var summary: Dictionary = {}
var result_font: Font


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	var screen := ColorRect.new()
	screen.name = "Screen"
	screen.color = Color(0.015, 0.025, 0.05, 0.82)
	add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var theme := Theme.new()
	theme.default_font = result_font
	theme.default_font_size = 20
	screen.theme = theme
	var center := CenterContainer.new()
	center.name = "Center"
	screen.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.custom_minimum_size = Vector2(500, 0)
	var box := StyleBoxFlat.new()
	box.bg_color = Color("10192b")
	box.border_color = Color("b99b65")
	box.set_border_width_all(2)
	box.content_margin_left = 28.0
	box.content_margin_right = 28.0
	box.content_margin_top = 24.0
	box.content_margin_bottom = 24.0
	panel.add_theme_stylebox_override("panel", box)
	center.add_child(panel)
	var rows := VBoxContainer.new()
	rows.name = "Rows"
	rows.add_theme_constant_override("separation", 14)
	panel.add_child(rows)
	_label(rows, "三处封印 · 全部解除", 30, Color("ffe0a2"))
	_label(rows, "雨街战斗试玩完成   ·   " + String(summary.get("grade", "D")), 20, Color("dfe8ff"))
	var seconds := int(summary.get("seconds", 0.0))
	var stats := "总用时  %d:%02d     最高连击  %d\n挑飞  %d     下砸  %d     撞墙  %d\n连锁  %d     弹刀  %d     受击  %d 次" % [
		seconds / 60, seconds % 60, int(summary.get("max_combo", 0)),
		int(summary.get("launch", 0)), int(summary.get("slam", 0)), int(summary.get("wall", 0)),
		int(summary.get("chain", 0)), int(summary.get("parry", 0)), int(summary.get("times_hit", 0))]
	_label(rows, stats, 20, Color("c7d3e5"))
	var retry := Button.new()
	retry.name = "Retry"
	retry.text = "再试一次  ·  R"
	retry.custom_minimum_size.y = 48
	retry.pressed.connect(func(): restart_requested.emit())
	rows.add_child(retry)
	var leave := Button.new()
	leave.name = "Leave"
	leave.text = "退出试玩"
	leave.custom_minimum_size.y = 44
	leave.pressed.connect(func(): get_tree().quit())
	rows.add_child(leave)
	retry.focus_neighbor_top = leave.get_path()
	retry.focus_neighbor_bottom = leave.get_path()
	leave.focus_neighbor_top = retry.get_path()
	leave.focus_neighbor_bottom = retry.get_path()
	retry.grab_focus.call_deferred()
	_label(rows, "战斗已暂停，可用方向键选择、回车确认", 15, Color("9caec5"))


func _label(rows: VBoxContainer, text: String, size: int, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	rows.add_child(label)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("reset") and not event.is_echo():
		get_viewport().set_input_as_handled()
		restart_requested.emit()
