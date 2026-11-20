extends Control
## C6 极简先锋「G03 裂纹白石 × 冷银星盘」首领 HUD（100% 呼应黑白蚀光美学，零土金杂色）

const BossFonts := preload("res://scripts/boss_sample/boss_fonts.gd")
const CONTROLLER_ICON_SCRIPT := "res://addons/controller_icons/objects/ControllerIconTexture.gd"

const TEX_MAIN_PATH := "res://assets/image/boss_duanchao/c6_hud_main_bar.png"
const TEX_MAIN_OV_PATH := "res://assets/image/boss_duanchao/c6_hud_main_overlay.png"
const TEX_PRISM_PATH := "res://assets/image/boss_duanchao/c6_hud_prism_bar.png"
const TEX_PRISM_OV_PATH := "res://assets/image/boss_duanchao/c6_hud_prism_overlay.png"
const TEX_ANCHOR_PATH := "res://assets/image/boss_duanchao/c6_hud_anchor_icon.png"
const TEX_WATCH_PATH := "res://assets/image/boss_duanchao/c6_hud_watch_shard.png"
const METRICS_PATH := "res://assets/image/boss_duanchao/boss_c6_metrics.json"

var stage: Node = null
var font_cn: Font
var font_gothic: Font
var font_roman: Font

var _tex_main: Texture2D
var _tex_main_ov: Texture2D
var _tex_prism: Texture2D
var _tex_prism_ov: Texture2D
var _tex_anchor: Texture2D
var _tex_watch: Texture2D

var _main_slot_uv := Rect2(0.0985, 0.4729, 0.8016, 0.1453)
var _prism_slot_uv := Rect2(0.0146, 0.4421, 0.9707, 0.1737)

var _lag_hp_ratio: float = 1.0
var _lag_shell_ratio: float = 1.0

var _icon_dodge: Texture2D
var _icon_parry: Texture2D
var _icon_attack: Texture2D
var _icon_heavy: Texture2D


func _load_tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


func has_gothic_hud_art() -> bool:
	return _tex_main != null and _tex_main_ov != null and _tex_prism != null


func _make_controller_icon(action_path: String) -> Texture2D:
	if get_tree() == null or get_tree().root == null or get_tree().root.get_node_or_null("ControllerIcons") == null:
		return null
	var icon_script := load(CONTROLLER_ICON_SCRIPT) as GDScript
	if icon_script == null:
		return null
	var icon: Texture2D = icon_script.new()
	icon.set("path", action_path)
	var ls := LabelSettings.new()
	ls.font = font_roman
	icon.set("custom_label_settings", ls)
	return icon


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	font_cn = BossFonts.chinese_serif()
	font_gothic = BossFonts.gothic_title()
	font_roman = BossFonts.gothic_roman()

	_tex_main = _load_tex(TEX_MAIN_PATH)
	_tex_main_ov = _load_tex(TEX_MAIN_OV_PATH)
	_tex_prism = _load_tex(TEX_PRISM_PATH)
	_tex_prism_ov = _load_tex(TEX_PRISM_OV_PATH)
	_tex_anchor = _load_tex(TEX_ANCHOR_PATH)
	_tex_watch = _load_tex(TEX_WATCH_PATH)

	if FileAccess.file_exists(METRICS_PATH):
		var f := FileAccess.open(METRICS_PATH, FileAccess.READ)
		if f != null:
			var d: Variant = JSON.parse_string(f.get_as_text())
			if d is Dictionary:
				var muv: Array = d.get("hud_main_slot_uv", [])
				if muv.size() == 4:
					_main_slot_uv = Rect2(float(muv[0]), float(muv[1]), float(muv[2]), float(muv[3]))
				var puv: Array = d.get("hud_prism_slot_uv", [])
				if puv.size() == 4:
					_prism_slot_uv = Rect2(float(puv[0]), float(puv[1]), float(puv[2]), float(puv[3]))

	if DisplayServer.get_name() != "headless":
		_icon_dodge = _make_controller_icon("sample_dodge")
		_icon_parry = _make_controller_icon("parry")
		_icon_attack = _make_controller_icon("attack_light")
		_icon_heavy = _make_controller_icon("attack_heavy")


func _process(delta: float) -> void:
	if stage != null and stage.boss != null and is_instance_valid(stage.boss):
		var target_hp := clampf(float(stage.boss.hp) / maxf(float(stage.boss.max_hp), 1.0), 0.0, 1.0)
		if target_hp < _lag_hp_ratio:
			_lag_hp_ratio = move_toward(_lag_hp_ratio, target_hp, delta * 0.55)
		else:
			_lag_hp_ratio = target_hp

		var target_sh := clampf(float(stage.boss.shell) / maxf(float(stage.boss.max_shell), 1.0), 0.0, 1.0)
		if target_sh < _lag_shell_ratio:
			_lag_shell_ratio = move_toward(_lag_shell_ratio, target_sh, delta * 0.85)
		else:
			_lag_shell_ratio = target_sh
	queue_redraw()


func _draw_tapered_bar_fill(slot: Rect2, ratio: float, lag_ratio: float, col_dark: Color, col_bright: Color, specular: Color) -> void:
	draw_rect(slot, Color(0.03, 0.032, 0.040, 0.94))
	if lag_ratio > ratio + 0.002:
		draw_rect(Rect2(slot.position, Vector2(slot.size.x * lag_ratio, slot.size.y)), Color(0.92, 0.94, 0.98, 0.65))
	if ratio > 0.001:
		var fw := slot.size.x * ratio
		var top_h := slot.size.y * 0.52
		draw_rect(Rect2(slot.position, Vector2(fw, slot.size.y)), col_dark)
		draw_rect(Rect2(slot.position, Vector2(fw, top_h)), col_bright)
		draw_rect(Rect2(slot.position + Vector2(0.0, 1.0), Vector2(fw, 1.8)), specular)
		if ratio < 0.995 and fw > 4.0:
			draw_line(Vector2(slot.position.x + fw, slot.position.y), Vector2(slot.position.x + fw, slot.end.y), Color(1.0, 1.0, 1.0, 0.92), 2.0)


func _draw() -> void:
	if stage == null or stage.boss == null or not is_instance_valid(stage.boss):
		return
	if font_cn == null or font_roman == null:
		return

	var boss: Node2D = stage.boss
	var outline_col := Color(0.02, 0.02, 0.03, 0.96)
	var is_won := bool(stage.won)
	var vp_sz: Vector2 = size if size.x > 200.0 else get_viewport_rect().size
	if vp_sz.x <= 10.0:
		vp_sz = Vector2(1280.0, 720.0)

	# 极简暗黑魂系商业血条（黑铁锐边 + 深血红柱 + 干净宋体正名与 V:LIX 罗马刻度，彻底清掉旧表盘与棱壳废案字样）
	var bar_w := minf(vp_sz.x * 0.44, 540.0)
	var bar_h := 11.0
	var cx := vp_sz.x * 0.5
	var x0 := cx - bar_w * 0.5
	var bar_y := vp_sz.y - 34.0
	var hp_slot := Rect2(x0, bar_y, bar_w, bar_h)

	# 暗影托底 + 细黑铁锐边 + 两侧哥特菱形端饰
	draw_rect(Rect2(x0 - 14.0, bar_y - 26.0, bar_w + 28.0, 44.0), Color(0.015, 0.018, 0.025, 0.52))
	draw_rect(hp_slot.grow(2.0), Color(0.03, 0.035, 0.048, 0.96))
	draw_rect(hp_slot.grow(1.0), Color(0.42, 0.48, 0.58, 0.58), false, 1.0)
	var d_l := Vector2(x0 - 6.0, bar_y + bar_h * 0.5)
	var d_r := Vector2(x0 + bar_w + 6.0, bar_y + bar_h * 0.5)
	for pt in [d_l, d_r]:
		draw_colored_polygon(PackedVector2Array([
			pt + Vector2(-4.0, 0.0), pt + Vector2(0.0, -4.0), pt + Vector2(4.0, 0.0), pt + Vector2(0.0, 4.0)
		]), Color(0.68, 0.74, 0.84, 0.85))

	var hp_ratio := clampf(float(boss.hp) / maxf(float(boss.max_hp), 1.0), 0.0, 1.0)
	var hp_dark := Color(0.44, 0.06, 0.08) if not boss.is_phase2 else Color(0.62, 0.08, 0.09)
	var hp_bright := Color(0.84, 0.14, 0.15) if not boss.is_phase2 else Color(0.98, 0.22, 0.18)
	_draw_tapered_bar_fill(hp_slot, hp_ratio, _lag_hp_ratio, hp_dark, hp_bright, Color(1.0, 0.86, 0.84, 0.55))

	# 50% 二阶段细银刻线
	draw_line(Vector2(cx, bar_y - 2.0), Vector2(cx, bar_y + bar_h + 2.0), Color(0.86, 0.90, 0.96, 0.72), 1.5)

	# 左侧首领正名 + 右侧 V : LIX 终末刻
	var y_title := bar_y - 9.0
	var boss_title := String(stage.BOSS_NAME)
	draw_string_outline(font_cn, Vector2(x0, y_title), boss_title, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, 5, outline_col)
	draw_string(font_cn, Vector2(x0, y_title), boss_title, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(0.95, 0.97, 1.0, 0.96))

	var numeral := "VI : 00" if is_won else "V : LIX"
	var num_col := Color(0.95, 0.98, 1.0, 1.0) if is_won else (Color(1.0, 0.44, 0.38, 0.98) if boss.is_phase2 else Color(0.82, 0.86, 0.94, 0.90))
	draw_string_outline(font_roman, Vector2(x0, y_title), numeral, HORIZONTAL_ALIGNMENT_RIGHT, bar_w, 16, 5, outline_col)
	draw_string(font_roman, Vector2(x0, y_title), numeral, HORIZONTAL_ALIGNMENT_RIGHT, bar_w, 16, num_col)


func _draw_bottom_prompt_strip(vp_sz: Vector2, outline_col: Color) -> void:
	var items := [
		{"icon": _icon_dodge, "fallback": "Shift", "label": "扯断时痕/闪背"},
		{"icon": _icon_parry, "fallback": "L", "label": "弹倒带刃/弹针轰坠"},
		{"icon": _icon_attack, "fallback": "J", "label": "斩碎过去锚点"},
		{"icon": _icon_heavy, "fallback": "K", "label": "重斩染紫裂隙"},
	]
	var total_w := 0.0
	for it: Dictionary in items:
		var iw := 22.0 if it.icon != null else (font_roman.get_string_size(String(it.fallback), HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 12.0)
		var lw := font_cn.get_string_size(String(it.label), HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		total_w += iw + 6.0 + lw + 22.0
	total_w -= 22.0

	var start_x := (vp_sz.x - total_w) * 0.5
	var base_y := vp_sz.y - 14.0
	draw_rect(Rect2(start_x - 16.0, base_y - 19.0, total_w + 32.0, 25.0), Color(0.02, 0.02, 0.03, 0.56))

	var cur_x := start_x
	for it: Dictionary in items:
		var ic: Texture2D = it.icon
		if ic != null:
			draw_texture_rect(ic, Rect2(cur_x, base_y - 17.0, 20.0, 20.0), false, Color(0.94, 0.96, 1.0, 0.92))
			cur_x += 25.0
		else:
			var fb := "[%s]" % String(it.fallback)
			var fbw := font_roman.get_string_size(fb, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			draw_string_outline(font_roman, Vector2(cur_x, base_y - 2.0), fb, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 3, outline_col)
			draw_string(font_roman, Vector2(cur_x, base_y - 2.0), fb, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.95, 0.96, 1.0, 0.94))
			cur_x += fbw + 6.0
		var lb := String(it.label)
		var lw := font_cn.get_string_size(lb, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_string_outline(font_cn, Vector2(cur_x, base_y - 2.0), lb, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 3, outline_col)
		draw_string(font_cn, Vector2(cur_x, base_y - 2.0), lb, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.84, 0.87, 0.92, 0.92))
		cur_x += lw + 22.0
