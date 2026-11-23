extends Control
## 独立测试首领战「司辰母钟楼」顶部 HUD（clocktower_boss_bar.gd）
##
## 展示内容：
##   1. 首领名 + 当前母钟罗马时刻与阶段名（Ⅲ:00 凝晷序幕 / Ⅸ:00 逆时潮汐 / Ⅻ:00 拔针裁昼）；
##   2. 主血条（含 70% Ⅸ:00 与 35% Ⅻ:00 双阶段钟刻度线）；
##   3. 白金凝壳条 / 二阶段「时间倒流」可打断吟唱条；
##   4. 实时时钟联动 Buff / Debuff 状态胶囊（我方 + 首领双栏清晰可读）。

const GothicFonts := preload("res://scripts/ui/gothic_fonts.gd")

var stage: Node = null
var _font_cn: Font = null
var _font_bold: Font = null
var _font_roman: Font = null
var _lag_hp_ratio: float = 1.0
var _pulse: float = 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font_cn = GothicFonts.serif(500)
	_font_bold = GothicFonts.serif(800)
	_font_roman = GothicFonts.cinzel(700)


func _process(delta: float) -> void:
	_pulse += delta
	if stage != null and stage.get("boss") != null and is_instance_valid(stage.boss):
		var boss: Node2D = stage.boss
		var target_ratio := clampf(float(boss.hp) / maxf(float(boss.max_hp), 1.0), 0.0, 1.0)
		if target_ratio < _lag_hp_ratio:
			_lag_hp_ratio = move_toward(_lag_hp_ratio, target_ratio, delta * 0.36)
		else:
			_lag_hp_ratio = target_ratio
	queue_redraw()


func _draw() -> void:
	if stage == null or stage.get("boss") == null or not is_instance_valid(stage.boss):
		return
	if _font_cn == null or _font_roman == null:
		return
	var boss: Node2D = stage.boss
	var w := minf(size.x * 0.48, 640.0)
	var x := (size.x - w) * 0.5
	var y := 44.0

	var p_idx: int = int(stage.get("clock_phase"))
	var time_roman := "III : 00" if p_idx == 1 else ("IX : 00" if p_idx == 2 else "XII : 00")
	var phase_title := "凝晷序幕" if p_idx == 1 else ("逆时潮汐" if p_idx == 2 else "拔针裁昼")
	var phase_col := Color("a8dcff") if p_idx == 1 else (Color("d498ff") if p_idx == 2 else Color("ff5c54"))

	# 1. 顶部标题行
	draw_string(_font_bold, Vector2(x, y - 10.0), String(stage.BOSS_NAME), HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color("f4efe6"))
	draw_string(_font_roman, Vector2(x + 178.0, y - 10.0), time_roman, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, phase_col)
	draw_string(_font_bold, Vector2(x, y - 10.0), "阶段 %d · %s" % [p_idx, phase_title], HORIZONTAL_ALIGNMENT_RIGHT, w, 15, phase_col)

	# 2. 主血条 + 70% / 35% 钟刻阶段线
	var hp_ratio := clampf(float(boss.hp) / maxf(float(boss.max_hp), 1.0), 0.0, 1.0)
	draw_rect(Rect2(x - 3.0, y - 3.0, w + 6.0, 19.0), Color(0.03, 0.025, 0.05, 0.88))
	draw_rect(Rect2(x - 2.0, y - 2.0, w + 4.0, 17.0), Color(phase_col.r, phase_col.g, phase_col.b, 0.52), false, 1.2)
	if _lag_hp_ratio > hp_ratio:
		draw_rect(Rect2(x, y, w * _lag_hp_ratio, 13.0), Color(0.96, 0.90, 0.82, 0.52))
	var hp_col := Color("c42834") if p_idx == 1 else (Color("9632b8") if p_idx == 2 else Color("e82c24"))
	draw_rect(Rect2(x, y, w * hp_ratio, 13.0), hp_col)
	draw_rect(Rect2(x, y, w * hp_ratio, 3.0), Color(1.0, 0.78, 0.72, 0.34))

	for tick in [[0.70, "IX"], [0.35, "XII"]]:
		var tx := x + w * float(tick[0])
		draw_line(Vector2(tx, y - 4.0), Vector2(tx, y + 17.0), Color(0.98, 0.86, 0.62, 0.86), 2.0)

	# 3. 凝壳条 或 二阶段「时间倒流」可打断吟唱条
	var y2 := y + 22.0
	var rewinding: bool = bool(stage.get("rewind_channel_active"))
	if rewinding:
		var prog: float = clampf(float(stage.get("rewind_channel_progress")), 0.0, 1.0)
		var blink := 0.72 + 0.28 * sin(_pulse * 18.0)
		draw_rect(Rect2(x - 2.0, y2 - 2.0, w + 4.0, 14.0), Color(0.08, 0.02, 0.14, 0.92))
		draw_rect(Rect2(x, y2, w * prog, 10.0), Color(0.84, 0.34, 1.0, blink))
		draw_rect(Rect2(x - 2.0, y2 - 2.0, w + 4.0, 14.0), Color(1.0, 0.45, 0.62, blink), false, 1.6)
		draw_string(_font_bold, Vector2(x, y2 + 25.0), "▲ 时间倒流咏唱中！使用 弹刀 或 时缓搓招技能 立刻打断并震碎凝壳！", HORIZONTAL_ALIGNMENT_CENTER, w, 13, Color(1.0, 0.82, 0.98, blink))
	else:
		var bar_w := w * 0.52
		draw_rect(Rect2(x - 1.0, y2 - 1.0, bar_w + 2.0, 8.0), Color(0.02, 0.025, 0.05, 0.84))
		var note := ""
		if not boss.is_shell_broken:
			var sh_ratio := clampf(float(boss.shell) / maxf(float(boss.max_shell), 1.0), 0.0, 1.0)
			draw_rect(Rect2(x, y2, bar_w * sh_ratio, 6.0), Color(0.86, 0.91, 0.99, 0.95))
			note = "白金凝壳 %d%%" % int(round(sh_ratio * 100.0))
			if p_idx == 2:
				note += " · 回溯缓充中"
			elif p_idx == 3:
				note += " · 拔针狂刃"
		else:
			draw_rect(Rect2(x, y2, bar_w, 6.0), Color(0.46, 0.92, 1.0, 0.92))
			note = "破壳重创！刀刀真伤 · 可追斩搓招"
		draw_string(_font_cn, Vector2(x + bar_w + 10.0, y2 + 7.0), note, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.86, 0.90, 0.98, 0.92))

	# 4. 母钟联动 Buff / Debuff 胶囊行
	var pill_y := y2 + (32.0 if rewinding else 16.0)
	var buffs: Array = stage.call(&"get_active_clock_effects") if stage.has_method(&"get_active_clock_effects") else []
	var px := x
	for ef in buffs:
		var label_txt := String(ef.get("label", ""))
		var is_debuff := bool(ef.get("debuff", false))
		var is_boss := bool(ef.get("target", "player") == "boss")
		var pw := maxf(108.0, float(label_txt.length()) * 11.5 + 22.0)
		var bg := Color(0.18, 0.04, 0.08, 0.84) if is_debuff else (Color(0.14, 0.06, 0.22, 0.84) if is_boss else Color(0.05, 0.14, 0.20, 0.84))
		var bd := Color("ff6c7c") if is_debuff else (Color("e094ff") if is_boss else Color("8ce8ff"))
		var r := Rect2(px, pill_y, pw, 22.0)
		draw_rect(r, bg)
		draw_rect(r, Color(bd.r, bd.g, bd.b, 0.72), false, 1.1)
		draw_string(_font_cn, r.position + Vector2(8.0, 15.0), label_txt, HORIZONTAL_ALIGNMENT_LEFT, pw - 12.0, 12, bd)
		px += pw + 8.0
		if px > x + w - 40.0:
			px = x
			pill_y += 26.0
