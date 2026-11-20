extends CanvasLayer
## 断晓肉鸽 · 极简少字版「万象牌桌」（ForkChoiceOverlay）
## 全程仅用内置开源字体 NotoSerifSC-VF.ttf（零 SystemFont）：
##   - OPEN_SETUP：开局只选 1 张本命核心（Lv.10）
##   - SHOP_TABLE：1/2/3/4 买牌合成送锦囊 · U 升级送天赋 · R 刷新 · 空格出战

const FONT_SERIF_PATH := "res://assets/fonts/yg_title/NotoSerifSC-VF.ttf"

signal opening_confirmed(core_id: String)
signal table_finished()

enum Mode { NONE, OPEN_SETUP, SHOP_TABLE }

var mode: int = Mode.NONE
var is_open: bool = false
var director: Node = null
var current_seal_no: int = 1
var is_final_seal: bool = false

var _selected_core_id: String = "core_rift"

var _font: Font = null
var _theme: Theme = null
var _root: Control = null
var _main_panel: PanelContainer = null
var _content_box: VBoxContainer = null


func _ready() -> void:
	layer = 26
	process_mode = Node.PROCESS_MODE_ALWAYS
	if FileAccess.file_exists(FONT_SERIF_PATH):
		_font = load(FONT_SERIF_PATH) as Font
	_build_theme()
	_build_shell()
	close_overlay()


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

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.03, 0.025, 0.06, 0.84)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	_main_panel = PanelContainer.new()
	_main_panel.custom_minimum_size = Vector2(1040.0, 520.0)
	_main_panel.add_theme_stylebox_override("panel", _make_box(Color("0d0b16"), Color("7856b8"), 2, 10, 22))
	center.add_child(_main_panel)

	_content_box = VBoxContainer.new()
	_content_box.add_theme_constant_override("separation", 14)
	_main_panel.add_child(_content_box)


func close_overlay() -> void:
	is_open = false
	mode = Mode.NONE
	visible = false
	if _root != null:
		_root.visible = false


func uses_only_open_source_fonts() -> bool:
	return _font != null and not (_font is SystemFont) and FONT_SERIF_PATH.begins_with("res://assets/fonts/")


func confirm_opening_with(c_id: String, _legacy_arg: String = "") -> void:
	_selected_core_id = c_id
	_confirm_opening()


func finish_table_now() -> void:
	_finish_table()


# ---------------------------------------------------------------- 1. 开局只选 1 张本命核心

func open_opening_draft(p_director: Node) -> void:
	director = p_director
	mode = Mode.OPEN_SETUP
	is_open = true
	visible = true
	_root.visible = true
	_main_panel.custom_minimum_size = Vector2(1020.0, 420.0)

	if director != null and director.catalog != null:
		var cores: Array[Dictionary] = director.catalog.get_core_cards()
		if not cores.is_empty() and _selected_core_id == "":
			_selected_core_id = String(cores[0]["card_id"])

	_rebuild_opening_ui()


func _rebuild_opening_ui() -> void:
	_clear_children(_content_box)
	if director == null or director.catalog == null:
		return

	_content_box.add_child(_make_label("选择本命核心", 26, Color("f3ecff"), HORIZONTAL_ALIGNMENT_CENTER))

	var core_row := HBoxContainer.new()
	core_row.add_theme_constant_override("separation", 14)
	core_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content_box.add_child(core_row)

	var cores: Array[Dictionary] = director.catalog.get_core_cards()
	for i in cores.size():
		var c: Dictionary = cores[i]
		var cid := String(c["card_id"])
		var selected := (cid == _selected_core_id)
		var accent: Color = c.get("accent_color", Color("b678ff"))

		var btn := Button.new()
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(230.0, 230.0)
		var bg := Color("1c1433") if selected else Color("120f1d")
		var border := accent if selected else Color("3b3352")
		btn.add_theme_stylebox_override("normal", _make_box(bg, border, 3 if selected else 1, 8, 16))
		btn.add_theme_stylebox_override("hover", _make_box(Color("22193d"), accent, 2, 8, 16))
		btn.add_theme_stylebox_override("pressed", _make_box(Color("281e47"), accent, 3, 8, 16))
		btn.add_theme_stylebox_override("focus", _make_box(bg, accent, 3, 8, 16))
		btn.pressed.connect(func() -> void:
			if _selected_core_id == cid:
				_confirm_opening()
			else:
				_selected_core_id = cid
				_rebuild_opening_ui()
		)
		core_row.add_child(btn)

		var vb := VBoxContainer.new()
		vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 16)
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.alignment = BoxContainer.ALIGNMENT_CENTER
		vb.add_theme_constant_override("separation", 12)
		btn.add_child(vb)

		vb.add_child(_make_label("[%d]  %s" % [i + 1, String(c["title"])], 22, accent if selected else Color("eee8ff"), HORIZONTAL_ALIGNMENT_CENTER))
		vb.add_child(_make_label("初始 Lv.10", 15, Color("f5dfa3"), HORIZONTAL_ALIGNMENT_CENTER))
		vb.add_child(_make_label(String(c["summary"]), 15, Color("e4def5"), HORIZONTAL_ALIGNMENT_CENTER))
		vb.add_child(_make_label(String(c["subtitle"]), 13, Color("a59bc0"), HORIZONTAL_ALIGNMENT_CENTER))

	var start_btn := Button.new()
	start_btn.custom_minimum_size = Vector2(280.0, 50.0)
	start_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	start_btn.text = "[空格] 开战"
	start_btn.add_theme_font_size_override("font_size", 19)
	start_btn.add_theme_color_override("font_color", Color("fff8e6"))
	start_btn.add_theme_stylebox_override("normal", _make_box(Color("2d1d4c"), Color("d5a8ff"), 2, 8, 10))
	start_btn.add_theme_stylebox_override("hover", _make_box(Color("3c2766"), Color("f5dfa3"), 3, 8, 10))
	start_btn.add_theme_stylebox_override("focus", _make_box(Color("3c2766"), Color("f5dfa3"), 3, 8, 10))
	start_btn.pressed.connect(_confirm_opening)
	_content_box.add_child(start_btn)
	start_btn.grab_focus.call_deferred()


func _confirm_opening() -> void:
	if mode != Mode.OPEN_SETUP:
		return
	var c := _selected_core_id
	close_overlay()
	opening_confirmed.emit(c)


# ---------------------------------------------------------------- 2. 波间万象牌桌（升级送天赋 · 合成送锦囊）

func open_wanxiang_table(p_director: Node, seal_no: int, final_seal: bool = false) -> void:
	director = p_director
	current_seal_no = seal_no
	is_final_seal = final_seal
	mode = Mode.SHOP_TABLE
	is_open = true
	visible = true
	_root.visible = true
	_main_panel.custom_minimum_size = Vector2(1060.0, 540.0)
	if director != null and not director.table_updated.is_connected(_on_director_table_updated):
		director.table_updated.connect(_on_director_table_updated)
	_rebuild_shop_ui()


func _on_director_table_updated() -> void:
	if is_open and mode == Mode.SHOP_TABLE:
		_rebuild_shop_ui()


func _rebuild_shop_ui() -> void:
	_clear_children(_content_box)
	if director == null or director.catalog == null:
		return
	var rig: Node2D = director.perk_rig

	# --- 第 1 行：顶栏（牌手等级 + 已持天赋短签 + 提示 + 能量） ---
	var top_bar := HBoxContainer.new()
	top_bar.add_theme_constant_override("separation", 12)
	_content_box.add_child(top_bar)

	top_bar.add_child(_make_label("牌手 Lv.%d" % int(director.player_tier), 21, Color("f3ecff")))

	var talent_tags := ""
	for tid in director.active_talents:
		var tinfo: Dictionary = director.catalog.get_card(String(tid))
		talent_tags += "【%s】" % String(tinfo.get("title", tid))
	if talent_tags != "":
		top_bar.add_child(_make_label(talent_tags, 15, Color("b8dcff")))

	if bool(director.duplicator_armed):
		top_bar.add_child(_make_label("✦下张×2", 15, Color("f5dfa3")))

	var toast_lbl := _make_label(String(director.status_toast), 15, Color("f5dfa3"), HORIZONTAL_ALIGNMENT_CENTER)
	toast_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(toast_lbl)

	top_bar.add_child(_make_label("⚡ %d" % int(director.energy), 25, Color("f5dfa3")))

	# --- 第 2 行：牌面槽位（1 核心 + 4 属性，满 3 格 ●●● 合成送锦囊） ---
	var board_row := HBoxContainer.new()
	board_row.add_theme_constant_override("separation", 10)
	_content_box.add_child(board_row)

	var core_info: Dictionary = director.catalog.get_card(String(director.core_id))
	var core_lv: int = int(rig.core_level) if rig != null else 10
	var core_acc: Color = core_info.get("accent_color", Color("b678ff"))
	var core_pips := _format_pips(int(director.synth_pips.get("core", 0)), 3, "●", "○")

	var core_panel := PanelContainer.new()
	core_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	core_panel.size_flags_stretch_ratio = 1.85
	core_panel.add_theme_stylebox_override("panel", _make_box(Color("171129"), core_acc, 2, 8, 10))
	board_row.add_child(core_panel)

	var cvb := VBoxContainer.new()
	cvb.add_theme_constant_override("separation", 4)
	core_panel.add_child(cvb)
	cvb.add_child(_make_label("★ %s   Lv.%d   %s" % [
		String(core_info.get("title", "核心")), core_lv, core_pips
	], 18, core_acc))

	var tier_hb := HBoxContainer.new()
	tier_hb.add_theme_constant_override("separation", 14)
	cvb.add_child(tier_hb)
	var m_keys := ["tier_10", "tier_40", "tier_100"]
	var m_reqs := [10, 40, 100]
	for mi in 3:
		var unlocked: bool = rig.has_core_tier(m_reqs[mi]) if rig != null else (mi == 0)
		var m_txt := String(core_info.get(m_keys[mi], str(m_reqs[mi])))
		tier_hb.add_child(_make_label(m_txt, 13, Color("f5dfa3") if unlocked else Color("6f6788")))

	for st_id in ["stat_atk", "stat_spd", "stat_crit", "stat_def"]:
		var st_card: Dictionary = director.catalog.get_card(st_id)
		var st_lv: int = int(rig.stat_levels.get(st_id, 1)) if rig != null else 1
		var st_pips := _format_pips(int(director.synth_pips.get(st_id, 0)), 3, "●", "○")
		var sp := PanelContainer.new()
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sp.add_theme_stylebox_override("panel", _make_box(Color("120f1e"), Color("3d3556"), 1, 8, 10))
		board_row.add_child(sp)
		var svb := VBoxContainer.new()
		svb.add_theme_constant_override("separation", 4)
		sp.add_child(svb)
		svb.add_child(_make_label("%s  Lv.%d" % [String(st_card.get("title", st_id)), st_lv], 16, st_card.get("accent_color", Color("e6e0f8")), HORIZONTAL_ALIGNMENT_CENTER))
		svb.add_child(_make_label(st_pips, 13, Color("f5dfa3") if int(director.synth_pips.get(st_id, 0)) == 2 else Color("8e86a8"), HORIZONTAL_ALIGNMENT_CENTER))

	# --- 第 3 行：中央选牌区（三选一天赋/锦囊 或 4 张极简商店牌） ---
	if director.is_draft_active():
		_build_draft_zone()
	else:
		_build_shop_cards_zone()

	# --- 第 4 行：底栏（[U]升级送天赋 · [R]刷新 · [空格]出战） ---
	var bottom_bar := HBoxContainer.new()
	bottom_bar.add_theme_constant_override("separation", 14)
	_content_box.add_child(bottom_bar)

	var up_btn := Button.new()
	up_btn.custom_minimum_size = Vector2(250.0, 52.0)
	if int(director.player_tier) >= director.MAX_PLAYER_TIER:
		up_btn.text = "已满阶 Lv.5"
		up_btn.disabled = true
	else:
		up_btn.text = "[U] 升级 (%d⚡ · 送天赋)" % int(director.upgrade_cost())
		up_btn.disabled = not director.can_upgrade_tier()
	up_btn.add_theme_font_size_override("font_size", 17)
	up_btn.add_theme_color_override("font_color", Color("fff4d4"))
	up_btn.add_theme_stylebox_override("normal", _make_box(Color("241b36"), Color("f5dfa3"), 2, 8, 10))
	up_btn.add_theme_stylebox_override("hover", _make_box(Color("33264c"), Color("fff4d4"), 3, 8, 10))
	up_btn.add_theme_stylebox_override("disabled", _make_box(Color("110e1a"), Color("2c263d"), 1, 8, 10))
	up_btn.pressed.connect(func() -> void:
		director.upgrade_tier()
	)
	bottom_bar.add_child(up_btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom_bar.add_child(spacer)

	var roll_btn := Button.new()
	roll_btn.custom_minimum_size = Vector2(170.0, 52.0)
	roll_btn.text = "[R] 刷新 (1⚡)"
	roll_btn.disabled = not director.can_refresh_shop()
	roll_btn.add_theme_font_size_override("font_size", 17)
	roll_btn.add_theme_stylebox_override("normal", _make_box(Color("19152b"), Color("9f82e6"), 2, 8, 10))
	roll_btn.add_theme_stylebox_override("hover", _make_box(Color("251e3f"), Color("d5bfff"), 2, 8, 10))
	roll_btn.add_theme_stylebox_override("disabled", _make_box(Color("110e1a"), Color("2c263d"), 1, 8, 10))
	roll_btn.pressed.connect(func() -> void:
		director.refresh_shop()
	)
	bottom_bar.add_child(roll_btn)

	var go_btn := Button.new()
	go_btn.custom_minimum_size = Vector2(200.0, 52.0)
	go_btn.text = "[空格] 结算" if is_final_seal else "[空格] 出战"
	go_btn.disabled = director.is_draft_active()
	go_btn.add_theme_font_size_override("font_size", 18)
	go_btn.add_theme_color_override("font_color", Color("fff8e8"))
	go_btn.add_theme_stylebox_override("normal", _make_box(Color("2f1e4f"), Color("d5a8ff"), 2, 8, 10))
	go_btn.add_theme_stylebox_override("hover", _make_box(Color("3f2969"), Color("f5dfa3"), 3, 8, 10))
	go_btn.add_theme_stylebox_override("disabled", _make_box(Color("110e1a"), Color("2c263d"), 1, 8, 10))
	go_btn.pressed.connect(_finish_table)
	bottom_bar.add_child(go_btn)


func _build_shop_cards_zone() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.custom_minimum_size.y = 250.0
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
		var accent: Color = slot.get("accent_color", Color("b678ff"))
		var will_synth: bool = director.will_slot_synthesize(slot)

		var card_btn := Button.new()
		card_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card_btn.custom_minimum_size = Vector2(230.0, 245.0)
		card_btn.disabled = bought or (int(director.energy) < cost_val)

		var bg := Color("0d0b14") if bought else (Color("241b14") if is_gold else (Color("1d1433") if is_core else (Color("151d2b") if is_effect else Color("141122"))))
		var bd := Color("262136") if bought else (Color("f5dfa3") if (is_gold or will_synth) else (accent if (is_core or is_effect) else Color("5c4d82")))
		card_btn.add_theme_stylebox_override("normal", _make_box(bg, bd, 3 if (is_gold or is_core or will_synth) else 1, 8, 14))
		card_btn.add_theme_stylebox_override("hover", _make_box(bg.lightened(0.08), Color("f5dfa3"), 3, 8, 14))
		card_btn.add_theme_stylebox_override("disabled", _make_box(Color("0e0c16"), Color("262136"), 1, 8, 14))
		card_btn.pressed.connect(func() -> void:
			director.buy_slot(i)
		)
		row.add_child(card_btn)

		var vb := VBoxContainer.new()
		vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 14)
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.alignment = BoxContainer.ALIGNMENT_CENTER
		vb.add_theme_constant_override("separation", 14)
		card_btn.add_child(vb)

		if bought:
			vb.add_child(_make_label("已购", 18, Color("58506e"), HORIZONTAL_ALIGNMENT_CENTER))
			continue

		# 锚点 1：牌名
		var head_prefix := "★ " if is_core else ""
		vb.add_child(_make_label("[%d]  %s%s" % [i + 1, head_prefix, String(slot["title"])], 20, accent, HORIZONTAL_ALIGNMENT_CENTER))

		# 锚点 2：大号核心数值（或极短效果字）
		if is_effect:
			vb.add_child(_make_label(String(slot["summary"]), 22, Color("f3ecff"), HORIZONTAL_ALIGNMENT_CENTER))
		elif is_gold:
			vb.add_child(_make_label("✦ +%d 级" % gain_val, 28, Color("f5dfa3"), HORIZONTAL_ALIGNMENT_CENTER))
		else:
			vb.add_child(_make_label("+%d 级" % gain_val, 28, Color("f3ecff"), HORIZONTAL_ALIGNMENT_CENTER))

		# 锚点 3：合成提示 + 价格
		if will_synth:
			vb.add_child(_make_label("●●● 合成送锦囊!", 14, Color("f5dfa3"), HORIZONTAL_ALIGNMENT_CENTER))
		elif is_effect:
			vb.add_child(_make_label("效果牌", 13, Color("9eb8d8"), HORIZONTAL_ALIGNMENT_CENTER))
		else:
			vb.add_child(_make_label("●● 双格" if is_gold else "● +1格", 13, Color("8e86a8"), HORIZONTAL_ALIGNMENT_CENTER))

		var price_txt := "0⚡ 免费" if cost_val == 0 else "%d⚡" % cost_val
		var price_col := Color("b8f5d8") if cost_val == 0 else (Color("f5dfa3") if int(director.energy) >= cost_val else Color("6e6380"))
		vb.add_child(_make_label(price_txt, 18, price_col, HORIZONTAL_ALIGNMENT_CENTER))


func _build_draft_zone() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.custom_minimum_size.y = 250.0
	_content_box.add_child(box)

	var is_talent := (String(director.pending_draft_kind) == "talent")
	var head_txt := "✦ 升至 Lv.%d · 选 1 个天赋" % int(director.player_tier) if is_talent else "✦ 合成成功 · 选 1 个锦囊"
	box.add_child(_make_label(head_txt, 20, Color("f5dfa3"), HORIZONTAL_ALIGNMENT_CENTER))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(row)

	for i in director.pending_draft_choices.size():
		var item: Dictionary = director.pending_draft_choices[i]
		var acc: Color = item.get("accent_color", Color("f5dfa3"))
		var btn := Button.new()
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(300.0, 200.0)
		btn.add_theme_stylebox_override("normal", _make_box(Color("1c152e"), acc, 2, 8, 16))
		btn.add_theme_stylebox_override("hover", _make_box(Color("291f42"), Color("fff4d4"), 3, 8, 16))
		btn.pressed.connect(func() -> void:
			director.pick_draft_choice(i)
		)
		row.add_child(btn)

		var vb := VBoxContainer.new()
		vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 16)
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.alignment = BoxContainer.ALIGNMENT_CENTER
		vb.add_theme_constant_override("separation", 14)
		btn.add_child(vb)

		vb.add_child(_make_label("[%d]  %s" % [i + 1, String(item.get("title", ""))], 23, acc, HORIZONTAL_ALIGNMENT_CENTER))
		vb.add_child(_make_label(String(item.get("summary", "")), 17, Color("f0ebfc"), HORIZONTAL_ALIGNMENT_CENTER))


func _finish_table() -> void:
	if mode != Mode.SHOP_TABLE:
		return
	if director != null and director.is_draft_active():
		return
	close_overlay()
	table_finished.emit()


# ---------------------------------------------------------------- 3. 单手键盘热键（1/2/3/4、U、R、空格）

func _unhandled_input(event: InputEvent) -> void:
	if not is_open or not (event is InputEventKey):
		return
	var k := event as InputEventKey
	if not k.pressed or k.echo:
		return

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
				director.buy_slot(0)
				get_viewport().set_input_as_handled()
			KEY_2:
				director.buy_slot(1)
				get_viewport().set_input_as_handled()
			KEY_3:
				director.buy_slot(2)
				get_viewport().set_input_as_handled()
			KEY_4:
				director.buy_slot(3)
				get_viewport().set_input_as_handled()
			KEY_U:
				director.upgrade_tier()
				get_viewport().set_input_as_handled()
			KEY_R:
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


func _make_label(txt: String, fsize: int, col: Color, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var lbl := Label.new()
	lbl.text = txt
	lbl.horizontal_alignment = align
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
