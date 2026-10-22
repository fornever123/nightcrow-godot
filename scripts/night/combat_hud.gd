extends Control
## 试玩版 HUD：生命、波次、连击 + 评价、中间弹出的"主题事件"字、提示、横幅、结算。
## 全部用 _draw 画，没有图片资源。数据由 night_trial.gd 每帧塞进来。

const Style := preload("res://scripts/night/style_meter.gd")

const RANK_COLORS: Array[Color] = [Color("8d96ab"), Color("6fd6c4"), Color("86b8ff"), Color("ffb054"), Color("ffe066")]
const GOLD := Color("ffd27a")
const MOON := Color("dfe8ff")
const INK := Color(0.02, 0.03, 0.07)

var style: Style
var player_hp: float = 100.0
var player_max_hp: float = 100.0
var ult_frac: float = 0.0          ## 大招能量 0..1（满 = 可以放）
var wave_text: String = ""
var help_visible: bool = true
var help_text: String = ""
var muted := false                 ## 大招期间不弹提示字（ult_fx 控制）

var _font: Font
var _callouts: Array = []       ## {text, color, t, life, size}
var _hint: String = ""
var _hint_t: float = 0.0
var _banner: String = ""
var _banner_sub: String = ""
var _banner_t: float = 0.0
var _banner_life: float = 0.0
var _hurt_t: float = 0.0
var _hp_ghost: float = 100.0
var _combo_pop: float = 0.0
var _last_combo: int = 0
var _last_rank: int = 0
var _rank_pop: float = 0.0
var _result: Dictionary = {}
var _result_t: float = 0.0
var _time: float = 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "Noto Sans SC", "sans-serif"])
	sf.font_weight = 700
	_font = sf


func callout(text: String, color: Color = GOLD, size: int = 34) -> void:
	if muted:
		return
	# 同样的字刚弹过就只刷新时间（连锁一串时不刷屏）
	for c in _callouts:
		if c.text == text and c.t < 0.35:
			c.t = 0.0
			return
	_callouts.push_front({"text": text, "color": color, "t": 0.0, "life": 1.15, "size": size})
	while _callouts.size() > 4:
		_callouts.pop_back()


func hint(text: String, seconds: float = 5.0) -> void:
	_hint = text
	_hint_t = seconds


func banner(text: String, sub: String = "", seconds: float = 2.2) -> void:
	_banner = text
	_banner_sub = sub
	_banner_t = 0.0
	_banner_life = seconds


func hurt() -> void:
	_hurt_t = 0.45


func show_result(data: Dictionary, seconds: float = 6.0) -> void:
	_result = data
	_result_t = seconds


func hide_result() -> void:
	_result_t = 0.0


func _process(delta: float) -> void:
	_time += delta
	for c in _callouts:
		c.t += delta
	_callouts = _callouts.filter(func(c): return c.t < c.life)
	_hint_t = maxf(0.0, _hint_t - delta)
	_banner_t += delta
	_hurt_t = maxf(0.0, _hurt_t - delta)
	_hp_ghost = move_toward(_hp_ghost, player_hp, maxf(8.0, absf(_hp_ghost - player_hp) * 2.2) * delta) if _hp_ghost > player_hp else player_hp
	_result_t = maxf(0.0, _result_t - delta)
	if style != null:
		if style.combo > _last_combo:
			_combo_pop = 1.0
		_last_combo = style.combo
		var r := style.rank_index()
		if r > _last_rank:
			_rank_pop = 1.0
		_last_rank = r
	_combo_pop = maxf(0.0, _combo_pop - delta * 6.0)
	_rank_pop = maxf(0.0, _rank_pop - delta * 3.0)
	queue_redraw()


func _text(pos: Vector2, text: String, size: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT,
		width: float = -1.0, outline: int = 6) -> void:
	if outline > 0:
		draw_string_outline(_font, pos, text, align, width, size, outline, Color(INK, 0.85 * color.a))
	draw_string(_font, pos, text, align, width, size, color)


func _draw() -> void:
	var vp := get_viewport_rect().size
	_draw_hurt(vp)
	_draw_hp()
	_draw_combo(vp)
	if _result_t <= 0.0:
		# 结算面板打开时不画弹出字和横幅，免得透过面板叠在一起
		_draw_callouts(vp)
		_draw_banner(vp)
	_draw_hint(vp)
	_draw_result(vp)
	if help_visible and help_text != "":
		var lines := help_text.split("\n")
		var y := vp.y - 18.0 - 20.0 * float(lines.size() - 1)
		for line in lines:
			_text(Vector2(24, y), line, 15, Color(MOON, 0.78), HORIZONTAL_ALIGNMENT_LEFT, -1, 4)
			y += 20.0


func _draw_hp() -> void:
	var origin := Vector2(28, 26)
	var w := 300.0
	_text(origin + Vector2(0, 16), "生命", 16, MOON)
	var bar := Rect2(origin + Vector2(44, 3), Vector2(w, 14))
	draw_rect(bar.grow(2), Color(INK, 0.8))
	var frac := clampf(player_hp / maxf(player_max_hp, 1.0), 0.0, 1.0)
	var ghost := clampf(_hp_ghost / maxf(player_max_hp, 1.0), 0.0, 1.0)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * ghost, bar.size.y)), Color(1.0, 0.85, 0.75, 0.55))
	var col := Color("7fe3c8").lerp(Color("ff6a5c"), clampf(1.0 - frac * 1.6, 0.0, 1.0))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), col)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, 4)), Color(1, 1, 1, 0.25))
	_text(origin + Vector2(52 + w, 16), "%d" % ceili(player_hp), 16, MOON)
	# 大招能量条（满了发光 + 提示 J+K）
	var ub := Rect2(origin + Vector2(44, 25), Vector2(w * 0.72, 7))
	var full := ult_frac >= 0.999
	_text(origin + Vector2(0, 33), "大招", 13, Color(GOLD, 0.9) if full else Color(MOON, 0.7), HORIZONTAL_ALIGNMENT_LEFT, -1, 4)
	draw_rect(ub.grow(2), Color(INK, 0.8))
	var ucol := Color("ffb85c")
	if full:
		var pulse := 0.5 + 0.5 * sin(_time * 7.0)
		draw_rect(ub.grow(3 + 2 * pulse), Color(GOLD, 0.18 + 0.2 * pulse))
		ucol = Color("ffd27a").lerp(Color(1, 0.97, 0.88), pulse * 0.6)
	draw_rect(Rect2(ub.position, Vector2(ub.size.x * clampf(ult_frac, 0.0, 1.0), ub.size.y)), ucol)
	if full:
		_text(ub.position + Vector2(ub.size.x + 10, 8), "J+K", 14, GOLD, HORIZONTAL_ALIGNMENT_LEFT, -1, 4)
	if wave_text != "":
		_text(origin + Vector2(0, 58), wave_text, 17, Color(MOON, 0.92))


func _draw_combo(vp: Vector2) -> void:
	if style == null:
		return
	var right := vp.x - 30.0
	var r := style.rank_index()
	var rc := RANK_COLORS[r]
	# ---- 评价字母 ----
	var pop := 1.0 + 0.45 * _rank_pop
	var letter_size := int(round(66.0 * pop))
	var letter_pos := Vector2(right - 70.0, 92.0)
	if r == 4:
		var glow := 0.5 + 0.5 * sin(_time * 7.0)
		draw_circle(letter_pos + Vector2(26, -22), 46.0 + 4.0 * glow, Color(rc, 0.10 + 0.08 * glow))
	_text(letter_pos + Vector2(-letter_size * 0.1, 0), style.rank_letter(), letter_size, rc, HORIZONTAL_ALIGNMENT_LEFT, -1, 8)
	_text(Vector2(right - 260.0, 62.0), style.rank_name(), 20, Color(rc, 0.95), HORIZONTAL_ALIGNMENT_RIGHT, 180.0)
	var pbar := Rect2(Vector2(right - 260.0, 74.0), Vector2(180.0, 6.0))
	draw_rect(pbar.grow(1.5), Color(INK, 0.75))
	draw_rect(Rect2(pbar.position, Vector2(pbar.size.x * style.rank_progress(), pbar.size.y)), rc)
	# ---- 连击数 ----
	if style.combo >= 2:
		var cpop := 1.0 + 0.35 * _combo_pop
		var size := int(round(48.0 * cpop))
		var col := MOON.lerp(GOLD, clampf(float(style.combo) / 30.0, 0.0, 1.0))
		_text(Vector2(right - 360.0, 150.0), "%d" % style.combo, size, col, HORIZONTAL_ALIGNMENT_RIGHT, 280.0, 8)
		_text(Vector2(right - 72.0, 148.0), "连击", 20, Color(col, 0.95))
		var tbar := Rect2(Vector2(right - 200.0, 160.0), Vector2(170.0, 4.0))
		draw_rect(tbar.grow(1.0), Color(INK, 0.7))
		draw_rect(Rect2(tbar.position, Vector2(tbar.size.x * style.combo_fraction(), tbar.size.y)), Color(col, 0.9))


func _draw_callouts(vp: Vector2) -> void:
	var y := 214.0
	for c in _callouts:
		var t: float = c.t
		var life: float = c.life
		var appear := clampf(t / 0.09, 0.0, 1.0)
		var fade := clampf((life - t) / 0.3, 0.0, 1.0)
		var scale := lerpf(1.6, 1.0, appear)
		var size := int(round(float(c.size) * scale))
		var col: Color = c.color
		col.a = fade
		# 新的在最上面，旧的往下让位、淡出时继续往下沉（不会和新字叠在一起）
		_text(Vector2(0, y + (1.0 - fade) * 10.0), c.text, size, col, HORIZONTAL_ALIGNMENT_CENTER, vp.x, 8)
		y += float(c.size) * lerpf(1.25, 1.45, 1.0 - appear) + 10.0


func _draw_banner(vp: Vector2) -> void:
	if _banner == "" or _banner_t > _banner_life:
		return
	var a := clampf(_banner_t / 0.18, 0.0, 1.0) * clampf((_banner_life - _banner_t) / 0.4, 0.0, 1.0)
	var mid := vp.y * 0.36
	var band := Rect2(Vector2(0, mid - 46), Vector2(vp.x, 78 if _banner_sub == "" else 104))
	draw_rect(band, Color(INK, 0.45 * a))
	draw_line(band.position, band.position + Vector2(vp.x, 0), Color(GOLD, 0.5 * a), 1.0)
	draw_line(band.end - Vector2(vp.x, 0), band.end, Color(GOLD, 0.5 * a), 1.0)
	var spread := lerpf(18.0, 0.0, clampf(_banner_t / 0.3, 0.0, 1.0))
	_text(Vector2(0, mid + 6), _banner, 40, Color(MOON, a), HORIZONTAL_ALIGNMENT_CENTER, vp.x + spread, 8)
	if _banner_sub != "":
		_text(Vector2(0, mid + 40), _banner_sub, 19, Color(GOLD, a), HORIZONTAL_ALIGNMENT_CENTER, vp.x, 5)


func _draw_hint(vp: Vector2) -> void:
	if _hint_t <= 0.0 or _hint == "":
		return
	var a := clampf(_hint_t / 0.5, 0.0, 1.0)
	var size := 20
	var w := _font.get_string_size(_hint, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 44.0
	var rect := Rect2(Vector2((vp.x - w) * 0.5, vp.y - 128.0), Vector2(w, 40))
	draw_rect(rect, Color(INK, 0.62 * a))
	draw_rect(rect, Color(GOLD, 0.55 * a), false, 1.0)
	_text(Vector2(0, rect.position.y + 27), _hint, size, Color(Color("fff4dc"), a), HORIZONTAL_ALIGNMENT_CENTER, vp.x, 4)


func _draw_hurt(vp: Vector2) -> void:
	if _hurt_t <= 0.0:
		return
	var a := _hurt_t / 0.45
	var c := Color(0.85, 0.08, 0.1, 0.0)
	for i in 6:
		var k := float(i) * 10.0
		c.a = 0.07 * a * (1.0 - float(i) / 6.0)
		draw_rect(Rect2(0, 0, vp.x, k + 10), c)
		draw_rect(Rect2(0, vp.y - k - 10, vp.x, k + 10), c)
		draw_rect(Rect2(0, 0, k + 10, vp.y), c)
		draw_rect(Rect2(vp.x - k - 10, 0, k + 10, vp.y), c)


func _draw_result(vp: Vector2) -> void:
	if _result_t <= 0.0 or _result.is_empty():
		return
	var a := clampf(_result_t / 0.4, 0.0, 1.0) * clampf((6.5 - _result_t) / 0.3, 0.0, 1.0)
	var lines: Array = _result.get("lines", [])
	var h := 120.0 + 30.0 * float(lines.size())
	var rect := Rect2(Vector2(vp.x * 0.5 - 230.0, vp.y * 0.5 - h * 0.5 - 30.0), Vector2(460, h))
	draw_rect(rect, Color(INK, 0.93 * a))
	draw_rect(rect, Color(GOLD, 0.6 * a), false, 1.5)
	_text(Vector2(rect.position.x, rect.position.y + 42), String(_result.get("title", "结算")), 28,
			Color(MOON, a), HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 6)
	var y := rect.position.y + 82.0
	for line in lines:
		_text(Vector2(rect.position.x + 40, y), String(line[0]), 18, Color(MOON, 0.85 * a), HORIZONTAL_ALIGNMENT_LEFT, -1, 3)
		_text(Vector2(rect.position.x + 40, y), String(line[1]), 18, Color(GOLD, a), HORIZONTAL_ALIGNMENT_RIGHT, rect.size.x - 80.0, 3)
		y += 30.0
	var grade := String(_result.get("grade", ""))
	if grade != "":
		var gi := Style.RANKS.find(grade)
		var gc: Color = RANK_COLORS[maxi(gi, 0)]
		_text(Vector2(rect.end.x - 92, rect.position.y + 58), grade, 60, Color(gc, a), HORIZONTAL_ALIGNMENT_LEFT, -1, 8)
	var foot := String(_result.get("footer", ""))
	if foot != "":
		_text(Vector2(rect.position.x, rect.end.y - 18), foot, 15, Color(MOON, 0.6 * a), HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 3)
