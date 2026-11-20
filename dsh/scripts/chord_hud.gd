extends Control
## 截弦 · HUD（纸卷样式，全部代码绘制）：心、弦力、刀鞘、折名、判词、结算。

const P := preload("res://dsh/scripts/chord_palette.gd")

var trial: Node = null
var _t: float = 0.0
var _title: SystemFont
var _body: SystemFont
var _num: SystemFont
var _hearts: Array = []
var _heart_broken: Array = []
var _last_hearts: int = 5


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title = SystemFont.new()
	_title.font_names = PackedStringArray(["Source Han Serif SC", "Microsoft YaHei", "SimSun"])
	_title.font_weight = 700
	_body = SystemFont.new()
	_body.font_names = PackedStringArray(["Source Han Serif SC", "Microsoft YaHei", "SimSun"])
	_num = SystemFont.new()
	_num.font_names = PackedStringArray(["Georgia", "Times New Roman", "Cambria"])


func _process(delta: float) -> void:
	_t += delta
	if trial != null:
		var h := int(trial.hearts)
		if h < _last_hearts:
			_heart_broken.append(_t)
			if _heart_broken.size() > 8:
				_heart_broken.pop_front()
		_last_hearts = h
	queue_redraw()


func _draw() -> void:
	if trial == null:
		return
	var w := size.x if size.x > 0.0 else 1280.0
	var h := size.y if size.y > 0.0 else 720.0
	_draw_flash(w, h)
	if String(trial.phase) == "title":
		_draw_title(w, h)
		return
	_draw_hearts(w, h)
	_draw_meter(w, h)
	_draw_sheath(w, h)
	_draw_stats(w, h)
	_draw_act(w, h)
	_draw_hint(w, h)
	_draw_boss_mark(w, h)
	_draw_wipe(w, h)
	if String(trial.phase) == "result":
		_draw_result(w, h)
	if String(trial.phase) == "dead":
		_draw_dead(w, h)


# ------------------------------------------------------------------ 基础

func _draw_flash(w: float, h: float) -> void:
	var amt := float(trial.flash_amount)
	if amt > 0.001:
		var c: Color = trial.flash_color
		c.a = clampf(amt, 0.0, 1.0)
		draw_rect(Rect2(-4, -4, w + 8, h + 8), c)
	var slow := float(trial.slow_t)
	if slow > 0.0:
		# 断幕：纸白往里压，四边墨推进
		var k := clampf(slow / 0.6, 0.0, 1.0)
		draw_rect(Rect2(-4, -4, w + 8, h + 8), Color(1.0, 0.99, 0.96, 0.10 * k))
		for i in 4:
			var band := 30.0 + 26.0 * float(i)
			var col := P.INK
			col.a = 0.05 * k
			draw_rect(Rect2(0, 0, w, band - 20.0), col)
			draw_rect(Rect2(0, h - band + 20.0, w, band - 20.0), col)


func _heart_points(c: Vector2, s: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var steps := 26
	for i in steps:
		var a := TAU * float(i) / float(steps)
		var x := 16.0 * pow(sin(a), 3.0)
		var y := -(13.0 * cos(a) - 5.0 * cos(2.0 * a) - 2.0 * cos(3.0 * a) - cos(4.0 * a))
		pts.append(c + Vector2(x, y) * s * 0.9)
	return pts


func _draw_hearts(_w: float, _h: float) -> void:
	var max_h := int(trial.max_hearts)
	var cur := int(trial.hearts)
	for i in max_h:
		var c := Vector2(44.0 + float(i) * 34.0, 46.0)
		var full := i < cur
		var pts := _heart_points(c, 1.0)
		if full:
			draw_colored_polygon(pts, P.RED)
			draw_polyline(pts, Color(0.42, 0.12, 0.10, 0.8), 1.2, true)
			draw_line(c + Vector2(-4, -3), c + Vector2(3, -6), Color(1, 0.94, 0.9, 0.55), 1.2, true)
		else:
			draw_polyline(pts, Color(0.30, 0.26, 0.26, 0.45), 1.4, true)
			draw_line(c + Vector2(-6, -5), c + Vector2(6, 6), Color(0.30, 0.26, 0.26, 0.30), 1.0)
	# 刚碎的那颗：纸片散一下
	for t0 in _heart_broken:
		var age := _t - float(t0)
		if age < 0.5:
			var idx := max_h - 1
			var origin := Vector2(44.0 + float(idx) * 34.0, 46.0)
			var k := age / 0.5
			for j in 5:
				var a := TAU * float(j) / 5.0
				var d := Vector2(cos(a), sin(a)) * (12.0 + 30.0 * k)
				var c := P.RED
				c.a = 1.0 - k
				draw_rect(Rect2(origin + d - Vector2(3, 2), Vector2(6, 4)), c)


func _draw_meter(_w: float, _h: float) -> void:
	var ratio := clampf(float(trial.meter) / 100.0, 0.0, 1.0)
	var x := 32.0
	var y := 78.0
	var ww := 300.0
	# 底：一道干笔
	draw_line(Vector2(x, y), Vector2(x + ww, y), Color(0.16, 0.14, 0.14, 0.16), 7.0, true)
	var brush := PackedVector2Array()
	var steps := 20
	for i in steps + 1:
		var u := float(i) / float(steps)
		brush.append(Vector2(x + ww * u, y + sin(u * 9.0 + _t * 0.4) * 1.2))
	if ratio > 0.0:
		var n := maxi(2, int(float(steps) * ratio) + 1)
		var fill := PackedVector2Array()
		for i in n:
			fill.append(brush[i])
		var col := P.PURPLE if ratio < 0.999 else P.RED
		draw_polyline(fill, col, 7.0, true)
		if ratio >= 0.999:
			draw_polyline(fill, P.PURPLE_LIGHT, 2.2, true)
		draw_circle(fill[fill.size() - 1], 4.0, col)
	draw_string(_body, Vector2(x, y - 12.0), "弦 力", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.30, 0.26, 0.24, 0.55))
	if ratio >= 0.999:
		var pulse := 0.55 + 0.45 * sin(_t * 6.0)
		draw_string(_title, Vector2(x + ww + 12.0, y + 7.0), "断幕 R", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(P.RED.r, P.RED.g, P.RED.b, pulse))
	else:
		draw_string(_num, Vector2(x + ww + 12.0, y + 6.0), "%d" % int(float(trial.meter)), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.30, 0.26, 0.24, 0.45))


func _draw_sheath(_w: float, h: float) -> void:
	var arts: Array = trial.arts
	var slots: int = int(trial.sheath_slots)
	var base := Vector2(40.0, h - 92.0)
	draw_string(_body, base + Vector2(0, -14), "刀 鞘", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.30, 0.26, 0.24, 0.55))
	for i in slots:
		var x := base.x + float(i) * 66.0
		var r := Rect2(x, base.y, 54.0, 74.0)
		var has := i < arts.size()
		var pts := PackedVector2Array([
			Vector2(r.position.x + 6.0, r.position.y), Vector2(r.end.x - 6.0, r.position.y),
			Vector2(r.end.x, r.position.y + 8.0), Vector2(r.end.x, r.end.y),
			Vector2(r.position.x, r.end.y), Vector2(r.position.x, r.position.y + 8.0)])
		if has:
			var art_id := String(arts[i])
			var info: Dictionary = trial.arts_info.get(art_id, {})
			draw_colored_polygon(pts, Color(0.965, 0.949, 0.898, 0.92))
			draw_polyline(pts, P.INK, 1.6, true)
			var glyph := String(info.get("glyph", "?"))
			draw_string(_title, Vector2(x + 12.0, base.y + 46.0), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, 32, P.INK)
			draw_string(_num, Vector2(x + 6.0, base.y + 16.0), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.545, 0.153, 0.129, 0.85))
			draw_line(Vector2(x + 8.0, base.y + 58.0), Vector2(x + 46.0, base.y + 58.0), Color(P.RED.r, P.RED.g, P.RED.b, 0.55), 1.4)
		else:
			draw_polyline(pts, Color(0.30, 0.26, 0.24, 0.22), 1.2, true)
			draw_string(_num, Vector2(x + 6.0, base.y + 16.0), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.30, 0.26, 0.24, 0.25))
	draw_string(_body, Vector2(base.x, base.y + 96.0), "K 放最新 · 1/2/3 指定", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.30, 0.26, 0.24, 0.45))


func _draw_stats(w: float, _h: float) -> void:
	var txt := "绝 %d   截 %d   断 %d" % [int(trial.stat_jue), int(trial.stat_jie), int(trial.stat_duan)]
	var size := 16
	var tw := _num.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(_num, Vector2(w - 40.0 - tw, 44.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0.24, 0.21, 0.20, 0.62))
	var sub := "夺 %d · 破朱 %d" % [int(trial.stat_arts), int(trial.stat_broke)]
	var sw := _body.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	draw_string(_body, Vector2(w - 40.0 - sw, 66.0), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.30, 0.26, 0.24, 0.45))


func _draw_act(w: float, h: float) -> void:
	var label := String(trial.act_label)
	var sub := String(trial.act_subtitle)
	var age := _t - float(trial.act_t)
	if age > 3.2 or label.is_empty():
		return
	var a := clampf(1.0 - maxf(0.0, age - 2.2) / 1.0, 0.0, 1.0)
	var rise := 12.0 * clampf(age / 0.5, 0.0, 1.0)
	# 竖排折名
	var c := P.INK
	c.a = 0.78 * a
	var x := w * 0.5
	draw_string(_title, Vector2(x - 26.0, 176.0 + rise), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, c)
	draw_string(_title, Vector2(x - 22.0, 216.0 + rise), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 44, c)
	# 朱印
	var seal := P.RED
	seal.a = 0.72 * a
	var sr := Rect2(x + 44.0, 182.0 + rise, 30.0, 30.0)
	draw_rect(sr, seal, false, 2.0)
	draw_string(_title, Vector2(x + 50.0, 206.0 + rise), "截", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, seal)
	# 上下两道墨线
	draw_line(Vector2(x - 150.0, 246.0 + rise), Vector2(x + 150.0, 246.0 + rise), Color(0.16, 0.14, 0.12, 0.22 * a), 1.4)


func _draw_hint(w: float, h: float) -> void:
	var hint := String(trial.hint)
	if hint.is_empty() or float(trial.hint_t) <= 0.0:
		return
	var a := clampf(float(trial.hint_t) / 0.6, 0.0, 1.0)
	var tw := _body.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
	var c := Color(0.16, 0.14, 0.12, 0.72 * a)
	var x := w * 0.5 - tw * 0.5
	var y := h - 34.0
	draw_rect(Rect2(x - 20.0, y - 26.0, tw + 40.0, 40.0), Color(0.965, 0.949, 0.898, 0.55 * a))
	draw_string(_body, Vector2(x, y), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, c)


func _draw_boss_mark(w: float, _h: float) -> void:
	if not bool(trial.boss_active):
		return
	var boss = trial.boss
	if boss == null or not is_instance_valid(boss):
		return
	var name := "无常判官"
	var phase := int(boss.phase)
	var txt := name
	if phase >= 2:
		txt += " · 缝弦"
	if phase >= 3:
		txt += " · 绝笔"
	var tw := _title.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	draw_string(_title, Vector2(w * 0.5 - tw * 0.5, 92.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.545, 0.153, 0.129, 0.62))


func _draw_wipe(w: float, h: float) -> void:
	var wipe := float(trial.wipe)
	if wipe <= 0.0:
		return
	# 换折：纸从右往左刷过
	var pw := w * clampf(wipe, 0.0, 1.0)
	draw_rect(Rect2(w - pw, 0, pw, h), P.PAPER_LIGHT)
	draw_line(Vector2(w - pw, 0), Vector2(w - pw, h), Color(P.INK.r, P.INK.g, P.INK.b, 0.55), 3.0)
	for i in 5:
		var x := w - pw - 18.0 - float(i) * 9.0
		draw_line(Vector2(x, 0), Vector2(x + 30.0, h), Color(P.INK.r, P.INK.g, P.INK.b, 0.05), 3.0)


func _draw_title(w: float, h: float) -> void:
	draw_rect(Rect2(-4, -4, w + 8, h + 8), Color(0.929, 0.902, 0.831, 0.55))
	var cx := w * 0.5
	var fade := float(trial.title_fade)
	var a := clampf(fade, 0.0, 1.0)
	# 大印
	var seal := P.RED
	seal.a = 0.10 * a
	draw_rect(Rect2(cx - 210.0, 150.0, 420.0, 300.0), seal)
	var edge := P.RED_DEEP
	edge.a = 0.30 * a
	draw_rect(Rect2(cx - 210.0, 150.0, 420.0, 300.0), edge, false, 2.0)
	# 标题
	var c := P.INK
	c.a = 0.92 * a
	var tw := _title.get_string_size("截 弦", HORIZONTAL_ALIGNMENT_LEFT, -1, 86).x
	draw_string(_title, Vector2(cx - tw * 0.5, 300.0), "截 弦", HORIZONTAL_ALIGNMENT_LEFT, -1, 86, c)
	var sub := "沉 影 之 昼 · 纸 上 试 炼"
	var sw := _body.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	draw_string(_body, Vector2(cx - sw * 0.5, 340.0), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.24, 0.21, 0.20, 0.55 * a))
	# 一句话
	var line := "敌未出手，弦先到。断其弦者，得其招。"
	var lw := _body.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x
	draw_string(_body, Vector2(cx - lw * 0.5, 396.0), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color(0.16, 0.14, 0.12, 0.72 * a))
	# 操作
	var rows := [
		"A / D 移动    W / 空格 跳（二段）    J 斩（也是截弦）",
		"Shift 闪步（无敌，但不截弦）    K / 1 2 3 放夺来的招    R 断幕",
	]
	for i in rows.size():
		var rw := _body.get_string_size(rows[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		draw_string(_body, Vector2(cx - rw * 0.5, 448.0 + float(i) * 24.0), rows[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.24, 0.21, 0.20, 0.50 * a))
	if fade > 0.2:
		var pulse := 0.55 + 0.45 * sin(_t * 3.4)
		var ask := "按 J 起弦"
		var aw := _title.get_string_size(ask, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		draw_string(_title, Vector2(cx - aw * 0.5, 530.0), ask, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(P.RED.r, P.RED.g, P.RED.b, pulse * a))


func _draw_result(w: float, h: float) -> void:
	var a := clampf(float(trial.result_t) / 0.6, 0.0, 1.0)
	var panel := Rect2(w * 0.5 - 280.0, h * 0.5 - 210.0, 560.0, 420.0)
	draw_rect(panel, Color(0.965, 0.949, 0.898, 0.95 * a))
	draw_rect(panel, Color(0.16, 0.14, 0.12, 0.55 * a), false, 2.0)
	var cx := w * 0.5
	var title := "弦 尽"
	var tw := _title.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 56).x
	draw_string(_title, Vector2(cx - tw * 0.5, panel.position.y + 78.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 56, Color(0.09, 0.08, 0.09, 0.9 * a))
	var seal := P.RED
	seal.a = 0.85 * a
	draw_rect(Rect2(cx + 96.0, panel.position.y + 34.0, 42.0, 42.0), seal, false, 2.4)
	draw_string(_title, Vector2(cx + 106.0, panel.position.y + 66.0), "截", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, seal)
	var rows := [
		["绝", int(trial.stat_jue), "断在最后一瞬"],
		["截", int(trial.stat_jie), "刀锋压着弦走"],
		["断", int(trial.stat_duan), "稳，但还不够贪"],
		["夺招", int(trial.stat_arts), "从敌人身上拆下来的"],
		["破朱", int(trial.stat_broke), "用夺来的招打碎的"],
	]
	for i in rows.size():
		var y := panel.position.y + 130.0 + float(i) * 38.0
		draw_string(_body, Vector2(panel.position.x + 62.0, y), String(rows[i][0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(0.16, 0.14, 0.12, 0.7 * a))
		draw_string(_num, Vector2(panel.position.x + 150.0, y), str(rows[i][1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.09, 0.08, 0.09, 0.9 * a))
		draw_string(_body, Vector2(panel.position.x + 210.0, y), String(rows[i][2]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.30, 0.26, 0.24, 0.5 * a))
	var rank := String(trial.rank)
	var rw := _title.get_string_size(rank, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
	draw_string(_title, Vector2(cx - rw * 0.5, panel.position.y + 358.0), rank, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, P.RED_DEEP)
	var tip := "F5 重新起弦 · Esc 退出"
	var tp := _body.get_string_size(tip, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	draw_string(_body, Vector2(cx - tp * 0.5, panel.end.y + 30.0), tip, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.24, 0.21, 0.20, 0.5 * a))


func _draw_dead(_w: float, _h: float) -> void:
	var a := clampf(float(trial.death_t) / 1.2, 0.0, 1.0)
	var w := size.x
	var h := size.y
	draw_rect(Rect2(-4, -4, w + 8, h + 8), Color(0.09, 0.08, 0.09, 0.42 * a))
	var txt := "弦 断"
	var tw := _title.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 64).x
	draw_string(_title, Vector2(w * 0.5 - tw * 0.5, h * 0.5), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 64, Color(0.965, 0.949, 0.898, 0.9 * a))
