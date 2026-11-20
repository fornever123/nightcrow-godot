extends Control
## 错拍 HUD：延迟条 / 合拍 / 连击 / 影斑 / 波次 / 结算。

var trial: Node = null
var _t: float = 0.0
var _title: SystemFont
var _body: SystemFont
var _num: SystemFont

const C_BONE := Color(0.88, 0.90, 0.94)
const C_SILVER := Color(0.58, 0.62, 0.72)
const C_DIM := Color(0.40, 0.43, 0.52)
const C_PURPLE := Color(0.64, 0.44, 1.0)
const C_COLD := Color(0.80, 0.92, 1.0)
const C_RED := Color(0.66, 0.16, 0.20)
const C_DARK := Color(0.015, 0.02, 0.04, 0.62)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title = SystemFont.new()
	_title.font_names = PackedStringArray(["Source Han Serif SC", "Microsoft YaHei", "SimHei"])
	_body = SystemFont.new()
	_body.font_names = PackedStringArray(["Source Han Serif SC", "Microsoft YaHei", "SimHei"])
	_num = SystemFont.new()
	_num.font_names = PackedStringArray(["Georgia", "Times New Roman", "Cambria"])


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	if trial == null:
		return
	var w := size.x if size.x > 0.0 else 1280.0
	var h := size.y if size.y > 0.0 else 720.0
	_draw_delay(w, h)
	_draw_hp(w)
	_draw_right(w)
	_draw_umbra(w, h)
	_draw_center(w, h)
	_draw_footer(w, h)
	if trial.wave_state == "done":
		_draw_result(w, h)


func _draw_delay(w: float, _h: float) -> void:
	var delay := float(trial.delay)
	var beat := delay <= 0.02 or float(trial.preview_t) > 0.0
	var ratio := clampf(delay / 0.84, 0.0, 1.0)
	draw_rect(Rect2(30, 22, 306, 118), C_DARK)
	draw_line(Vector2(30, 140), Vector2(336, 140), Color(0.4, 0.36, 0.55, 0.55), 1.0, true)
	draw_string(_title, Vector2(44, 48), "错 拍", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, C_DIM)
	var num_col := C_COLD if beat else C_PURPLE
	draw_string(_num, Vector2(42, 92), "%.2f" % delay, HORIZONTAL_ALIGNMENT_LEFT, -1, 38, num_col)
	draw_string(_body, Vector2(126, 92), "s", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, C_DIM)
	if beat:
		var pulse := 0.6 + 0.4 * sin(_t * 6.0)
		draw_string(_title, Vector2(150, 92), "合 拍", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(C_COLD.r, C_COLD.g, C_COLD.b, pulse))
		draw_rect(Rect2(30, 22, 306, 118), Color(0.7, 0.85, 1.0, 0.05 * pulse), false, 1.0)
	# 延迟条
	var bx := 44.0
	var by := 104.0
	var bw := 272.0
	draw_rect(Rect2(bx, by, bw, 9), Color(0.08, 0.07, 0.13, 0.9))
	var fill := bw * ratio
	draw_rect(Rect2(bx, by, fill, 9), Color(num_col.r, num_col.g, num_col.b, 0.85))
	draw_rect(Rect2(bx, by, bw, 9), Color(0.5, 0.48, 0.6, 0.5), false, 1.0)
	for i in 6:
		var tx := bx + bw * float(i) / 6.0
		draw_line(Vector2(tx, by - 2), Vector2(tx, by + 11), Color(0.1, 0.1, 0.16, 0.8), 1.0)
	draw_string(_body, Vector2(bx, by + 26), "左端 = 合拍  右端 = 0.84s", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, C_DIM)
	if float(trial.preview_t) > 0.0:
		draw_string(_title, Vector2(bx + 176, by + 26), "预演中", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, C_COLD)
	elif float(trial.freeze_t) > 0.0:
		draw_string(_title, Vector2(bx + 176, by + 26), "定格中", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, C_PURPLE)


func _draw_hp(w: float) -> void:
	var hp := float(trial.player.hp)
	var max_hp := maxf(1.0, float(trial.player.max_hp))
	draw_rect(Rect2(30, 152, 306, 26), C_DARK)
	draw_string(_title, Vector2(44, 171), "命", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, C_DIM)
	draw_rect(Rect2(74, 160, 240, 8), Color(0.08, 0.07, 0.1, 0.9))
	draw_rect(Rect2(74, 160, 240 * clampf(hp / max_hp, 0.0, 1.0), 8), C_RED)
	draw_rect(Rect2(74, 160, 240, 8), Color(0.55, 0.5, 0.58, 0.5), false, 1.0)
	draw_string(_num, Vector2(214, 171), "%d" % int(ceil(hp)), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, C_BONE)
	var zone := "光里 · 延迟 -0.12"
	var zc := C_COLD
	if not bool(trial.player.in_light):
		zone = "影里 · 延迟 +0.12"
		zc = C_PURPLE
	draw_string(_body, Vector2(44, 196), zone, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(zc.r, zc.g, zc.b, 0.85))


func _draw_right(w: float) -> void:
	var x := w - 30.0
	draw_string(_title, Vector2(x - 240, 48), "第 %d / 3 拍" % (int(trial.wave_index) + 1), HORIZONTAL_ALIGNMENT_RIGHT, 240, 18, C_SILVER)
	var combo := int(trial.combo)
	if combo > 0:
		draw_string(_num, Vector2(x - 140, 102), "%d" % combo, HORIZONTAL_ALIGNMENT_RIGHT, 80, 40, C_BONE)
		draw_string(_title, Vector2(x - 54, 102), "连击", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, C_SILVER)
		var keep := clampf(float(trial.combo_timer) / maxf(0.001, float(trial.settings_delay.get("comboKeepSeconds", 2.5))), 0.0, 1.0)
		draw_rect(Rect2(x - 240, 114, 240 * keep, 3), Color(0.6, 0.48, 1.0, 0.75))
	var alive: int = int(trial.shades_alive().size())
	draw_string(_body, Vector2(x - 240, 140), "影子 %d" % alive, HORIZONTAL_ALIGNMENT_RIGHT, 240, 14, C_DIM)


func _draw_umbra(w: float, h: float) -> void:
	var n := int(trial.umbra_max)
	var have := int(trial.umbra)
	var gap := 30.0
	var total := gap * float(n - 1)
	var cx := w * 0.5 - total * 0.5
	var cy := h - 66.0
	for i in n:
		var c := Vector2(cx + gap * float(i), cy)
		var pts := PackedVector2Array([c + Vector2(0, -9), c + Vector2(9, 0), c + Vector2(0, 9), c + Vector2(-9, 0)])
		if i < have:
			draw_colored_polygon(pts, Color(0.62, 0.45, 1.0, 0.85))
			draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), Color(0.88, 0.82, 1.0, 0.9), 1.0, true)
		else:
			draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), Color(0.36, 0.34, 0.46, 0.8), 1.0, true)
	draw_string(_body, Vector2(w * 0.5 - 60, h - 34), "影斑", HORIZONTAL_ALIGNMENT_CENTER, 120, 13, C_DIM)


func _draw_center(w: float, h: float) -> void:
	if float(trial.hint_t) > 0.0 and not trial.hint.is_empty():
		var a := clampf(float(trial.hint_t) / 0.6, 0.0, 1.0)
		draw_string(_title, Vector2(0, h * 0.40), String(trial.hint), HORIZONTAL_ALIGNMENT_CENTER, w, 22, Color(0.86, 0.84, 0.92, a))
	if trial.wave_state == "fight" and float(trial.wave_t) < 2.6:
		var a2 := clampf((2.6 - float(trial.wave_t)) / 0.8, 0.0, 1.0)
		draw_string(_title, Vector2(0, h * 0.22), String(trial.wave_label), HORIZONTAL_ALIGNMENT_CENTER, w, 30, Color(0.9, 0.88, 0.96, a2))
		draw_line(Vector2(w * 0.5 - 120, h * 0.22 + 14), Vector2(w * 0.5 + 120, h * 0.22 + 14), Color(0.58, 0.44, 0.9, 0.5 * a2), 1.0, true)
	if trial.wave_state == "dead":
		draw_string(_title, Vector2(0, h * 0.45), "你的影子替你活了下去", HORIZONTAL_ALIGNMENT_CENTER, w, 30, Color(0.82, 0.78, 0.9, 0.9))


func _draw_footer(w: float, h: float) -> void:
	draw_string(_body, Vector2(0, h - 12.0), "A / D 移动 · 空格 跳 · J 攻击 · Shift 冲刺 · Q 预演 · E 定格 · F5 重开",
		HORIZONTAL_ALIGNMENT_CENTER, w, 13, Color(0.44, 0.46, 0.55, 0.9))
	if int(trial.umbra) > 0 and float(trial.hint_t) <= 0.0:
		draw_string(_body, Vector2(0, h - 88.0), "Q 预演（1 影斑）   E 定格（2 影斑）", HORIZONTAL_ALIGNMENT_CENTER, w, 13, Color(0.55, 0.5, 0.7, 0.85))


func _draw_result(w: float, h: float) -> void:
	draw_rect(Rect2(0, 0, w, h), Color(0.01, 0.012, 0.025, 0.55))
	draw_rect(Rect2(w * 0.5 - 250, h * 0.5 - 130, 500, 260), C_DARK)
	draw_rect(Rect2(w * 0.5 - 250, h * 0.5 - 130, 500, 260), Color(0.55, 0.48, 0.75, 0.6), false, 1.0)
	draw_string(_title, Vector2(0, h * 0.5 - 70), "三 拍 走 完", HORIZONTAL_ALIGNMENT_CENTER, w, 30, C_BONE)
	draw_string(_body, Vector2(0, h * 0.5 - 20), "合拍率  %d%%" % int(round(float(trial.beat_ratio()) * 100.0)), HORIZONTAL_ALIGNMENT_CENTER, w, 20, C_COLD)
	draw_string(_body, Vector2(0, h * 0.5 + 14), "最长连击  %d" % int(trial.max_combo), HORIZONTAL_ALIGNMENT_CENTER, w, 20, C_SILVER)
	draw_string(_body, Vector2(0, h * 0.5 + 48), "打中影身  %d 次" % int(trial.hit_count), HORIZONTAL_ALIGNMENT_CENTER, w, 20, C_SILVER)
	draw_string(_body, Vector2(0, h * 0.5 + 92), "F5 再来一拍", HORIZONTAL_ALIGNMENT_CENTER, w, 15, C_DIM)
