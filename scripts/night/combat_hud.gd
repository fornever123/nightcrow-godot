extends Control
## 试玩版 HUD：生命、大招、波次、连击 + 评价、中间弹出的"主题事件"字、提示、横幅、结算。
## 全部用 _draw 画，没有图片资源。数据由 night_trial.gd 每帧塞进来。
## 10-31 UI 线按 A+C 结合版重画（样图 docs/视觉设计/UI/方向样图_20261031/AC-combat.png）：
## 斜切暗底面板 + 分格斜血条（两头铸铁矛尖）+ 5 根鸦羽大招；右上哥特黑体评价字母 + 段位名 + 斜体连击数；
## 弹出字带斜切黑底；提示是斜切双线牌子。配色只用骨白 / 银 / 冷灰蓝，紫只给主角（大招、高评价的光）。
## 中文用思源宋体（特粗 / 常规），数字用 Georgia 斜体，评价字母用 Old English（发布前要换开源字体打包）。

const Style := preload("res://scripts/night/style_meter.gd")

const INK := Color(0.024, 0.031, 0.051)
const MOON := Color("dfe8ff")
const SILVER := Color("e6e9ef")
const BONE := Color("ece8de")
const STEEL := Color("7f8ba0")
const MIST := Color("9aa6ba")
const RULE := Color("8d96a8")
const IRON := Color("b3bbc8")
const VIOLET := Color("9a6cff")
const VIOLET_LIGHT := Color("c8b0ff")
const WINE := Color(0.42, 0.05, 0.11)
const GOLD := Color("ffd27a")             ## 旧接口默认色（调用方还会传），画的时候换成骨白
## 评价 D → S：越高越亮，A / S 带主角的紫光
const RANK_COLORS: Array[Color] = [Color("7f8ba0"), Color("b9c1ce"), Color("e6e9ef"), Color("f1eee6"), Color("ffffff")]
const RANK_GLOW: Array[float] = [0.0, 0.0, 0.12, 0.3, 0.55]
const SKEW := 0.445                       ## tan(24°)：血条 / 面板的斜切
const FEATHERS := 5

var style: Style
var player_hp: float = 100.0
var player_max_hp: float = 100.0
var ult_frac: float = 0.0          ## 大招能量 0..1（满 = 可以放）
var wave_text: String = ""
var help_visible: bool = true
var help_text: String = ""
var muted := false                 ## 大招期间不弹提示字（ult_fx 控制）

var _font: Font                    ## 旧字体（微软雅黑粗），试玩结算页还在用
var _serif: Font
var _heavy: Font
var _digits: Font
var _black: Font
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
var _feather_pts: PackedVector2Array
# ---- 左上“剑”的动效状态（10-31 用户：换成帅气的有动效的 UI）----
var _prev_hp := -1.0
var _prev_ult := 0.0
var _hp_disp := 100.0              ## 滚动显示的血量数字
var _hp_flash := 0.0               ## 掉血闪白 1 → 0
var _shake := 0.0                  ## 挨打时纹章 / 数字抖动 1 → 0
var _sheen := -1.0                 ## 寒光扫过进度 0..1（<0 = 没在扫）
var _sheen_wait := 1.5
var _full_t := -1.0                ## 大招满了多久（<0 = 没满）
var _feather_pop: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]
var _shards: Array = []            ## 掉血崩出的碎片 {p, v, r, w, life, t}
var _motes: Array = []             ## 大招满时羽尖冒的紫光点 {p, v, life, t}
var _flying: Array = []            ## 放大招时四散的羽毛 {p, v, a, w, life, t}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = _system(["Microsoft YaHei", "Noto Sans CJK SC", "Noto Sans SC", "sans-serif"], 700)
	_serif = _system(["Noto Serif SC", "Source Han Serif SC", "SimSun", "serif"], 400)
	_heavy = _system(["Source Han Serif SC Heavy", "Source Han Serif SC", "Noto Serif SC", "serif"], 900)
	_digits = _system(["Georgia", "Noto Serif SC", "serif"], 700)
	(_digits as SystemFont).font_italic = true
	_black = _system(["Old English Text MT", "Noto Serif SC", "serif"], 400)
	# 鸦羽：两段贝塞尔叶形，羽轴竖直，长 30 宽 11（画的时候再旋转）
	var c := Curve2D.new()
	c.add_point(Vector2(0, -15), Vector2.ZERO, Vector2(5.5, 7))
	c.add_point(Vector2(0, 15), Vector2(5.5, -10), Vector2(-5.5, -10))
	c.add_point(Vector2(0, -15), Vector2(-5.5, 7), Vector2.ZERO)
	_feather_pts = c.tessellate(4, 6)


func _system(names: Array, weight: int) -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(names)
	f.font_weight = weight
	return f


func callout(text: String, color: Color = GOLD, size: int = 34) -> void:
	if muted:
		return
	# 同样的字刚弹过就只刷新时间（连锁一串时不刷屏）
	for c in _callouts:
		if c.text == text and c.t < 0.35:
			c.t = 0.0
			return
	_callouts.push_front({"text": text, "color": color, "t": 0.0, "life": 1.15, "size": size})
	while _callouts.size() > 3:
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
	_step_blade(delta)
	queue_redraw()


# ---------------------------------------------------------------- 左上“剑”：鸦纹剑柄 + 剑身血条 + 鸦羽翼大招

const EMBLEM := Vector2(50, 58)           ## 鸦纹中心
const BLADE_X0 := 104.0                   ## 剑身起点（护手右边）
const BLADE_X1 := 430.0                   ## 剑尖
const BLADE_TOP := 38.0
const BLADE_BOT := 54.0


func _blade_frac_x(f: float) -> float:
	return lerpf(BLADE_X0, BLADE_X1 - 20.0, f)


func _step_blade(delta: float) -> void:
	var maxhp := maxf(player_max_hp, 1.0)
	if _prev_hp < 0.0:
		_prev_hp = player_hp
		_hp_disp = player_hp
	if player_hp < _prev_hp - 0.01:
		# 掉血：缺口闪白，碎片从新旧两端之间崩出去，纹章和数字抖一下
		_hp_flash = 1.0
		_shake = 1.0
		var xa := _blade_frac_x(clampf(player_hp / maxhp, 0.0, 1.0))
		var xb := _blade_frac_x(clampf(_prev_hp / maxhp, 0.0, 1.0))
		var n := clampi(int((xb - xa) / 6.0) + 4, 5, 14)
		for i in n:
			var x := _rng.randf_range(xa, maxf(xb, xa + 4.0))
			_shards.append({"p": Vector2(x, _rng.randf_range(BLADE_TOP, BLADE_BOT - 4.0)),
					"v": Vector2(_rng.randf_range(-30.0, 150.0), _rng.randf_range(-170.0, -40.0)),
					"r": _rng.randf_range(0.0, TAU), "w": _rng.randf_range(-12.0, 12.0),
					"s": _rng.randf_range(2.0, 4.5), "life": _rng.randf_range(0.45, 0.7), "t": 0.0})
	_prev_hp = player_hp
	_hp_disp = move_toward(_hp_disp, player_hp, maxf(30.0, absf(_hp_disp - player_hp) * 8.0) * delta)
	_hp_flash = maxf(0.0, _hp_flash - delta * 3.5)
	_shake = maxf(0.0, _shake - delta * 4.0)
	# 寒光：每隔几秒从剑根扫到剑尖
	if _sheen >= 0.0:
		_sheen += delta / 0.55
		if _sheen > 1.0:
			_sheen = -1.0
			_sheen_wait = _rng.randf_range(2.6, 4.0)
	else:
		_sheen_wait -= delta
		if _sheen_wait <= 0.0:
			_sheen = 0.0
	# 鸦羽：每攒满一根弹一下；全满开始计时；满了之后掉下去 = 放了大招，羽毛四散
	for i in FEATHERS:
		var th := float(i + 1) / FEATHERS
		if _prev_ult < th - 0.001 and ult_frac >= th - 0.001:
			_feather_pop[i] = 1.0
		_feather_pop[i] = maxf(0.0, _feather_pop[i] - delta * 4.0)
	var full := ult_frac >= 0.999
	if full:
		_full_t = 0.0 if _full_t < 0.0 else _full_t + delta
		if _rng.randf() < delta * 9.0:
			var i := _rng.randi_range(0, FEATHERS - 1)
			_motes.append({"p": _feather_center(i) + Vector2(_rng.randf_range(-4, 8), _rng.randf_range(-14, -4)),
					"v": Vector2(_rng.randf_range(4.0, 26.0), _rng.randf_range(-38.0, -16.0)), "life": _rng.randf_range(0.7, 1.2), "t": 0.0})
	else:
		if _full_t >= 0.0 and ult_frac < 0.5:
			for i in FEATHERS:
				_flying.append({"p": _feather_center(i), "v": Vector2(_rng.randf_range(40.0, 160.0), _rng.randf_range(-120.0, -30.0)),
						"a": _feather_angle(i), "w": _rng.randf_range(-5.0, 5.0), "life": _rng.randf_range(0.7, 1.0), "t": 0.0})
		_full_t = -1.0
	_prev_ult = ult_frac
	for s in _shards:
		s.t += delta
		s.v.y += 620.0 * delta
		s.p += s.v * delta
		s.r += s.w * delta
	_shards = _shards.filter(func(s): return s.t < s.life)
	for m in _motes:
		m.t += delta
		m.p += m.v * delta
	_motes = _motes.filter(func(m): return m.t < m.life)
	for f in _flying:
		f.t += delta
		f.v.y += 90.0 * delta
		f.p += f.v * delta
		f.a += f.w * delta
	_flying = _flying.filter(func(f): return f.t < f.life)


func _spread() -> float:
	return 0.0 if _full_t < 0.0 else 1.0 - pow(1.0 - clampf(_full_t / 0.3, 0.0, 1.0), 3.0)


## 鸦羽翼：5 根从剑柄下方往右展开，越往后越长、越平
func _feather_center(i: int) -> Vector2:
	var s := _spread()
	return Vector2(98.0 + 21.0 * i + 3.0 * s * i, 76.0 - 1.5 * i - 2.0 * s)


func _feather_angle(i: int) -> float:
	return deg_to_rad(38.0 - 5.0 * i + 6.0 * _spread())


func _blade_top(x: float) -> float:
	return BLADE_TOP if x < BLADE_X1 - 26.0 else lerpf(BLADE_TOP, BLADE_TOP + 7.0, (x - (BLADE_X1 - 26.0)) / 26.0)


func _blade_bot(x: float) -> float:
	# 剑刃下沿从根部 54 慢慢收到 50，最后 26 像素收成剑尖
	var b := lerpf(BLADE_BOT, BLADE_BOT - 4.0, (x - BLADE_X0) / (BLADE_X1 - BLADE_X0))
	return b if x < BLADE_X1 - 26.0 else lerpf(b, BLADE_TOP + 7.0, (x - (BLADE_X1 - 26.0)) / 26.0)


## x0..x1 这一段剑身的多边形（上沿从左到右，下沿从右到左）
func _blade_poly(x0: float, x1: float) -> PackedVector2Array:
	var xs: Array[float] = [x0]
	var knee := BLADE_X1 - 26.0
	if x0 < knee and x1 > knee:
		xs.append(knee)
	xs.append(x1)
	var pts := PackedVector2Array()
	for x in xs:
		pts.append(Vector2(x, _blade_top(x)))
	for i in range(xs.size() - 1, -1, -1):
		pts.append(Vector2(xs[i], _blade_bot(xs[i])))
	return pts


func _blade_colors(pts: PackedVector2Array, top_c: Color, bot_c: Color) -> PackedColorArray:
	var cols := PackedColorArray()
	var half := pts.size() / 2
	for i in pts.size():
		cols.append(top_c if i < half else bot_c)
	return cols


# ---------------------------------------------------------------- 画字

func _text(pos: Vector2, text: String, size: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT,
		width: float = -1.0, outline: int = 6) -> void:
	if outline > 0:
		draw_string_outline(_font, pos, text, align, width, size, outline, Color(INK, 0.85 * color.a))
	draw_string(_font, pos, text, align, width, size, color)


func _width(text: String, font: Font, size: int, spacing: float) -> float:
	var w := 0.0
	for ch in text:
		w += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + spacing
	return w - spacing


## 带字距的字；align 左 / 中 / 右以 pos.x 为准。shadow > 0 时先画一层往右下偏的墨色。返回宽度。
func _say(pos: Vector2, text: String, font: Font, size: int, color: Color, spacing: float = 0.0,
		align := HORIZONTAL_ALIGNMENT_LEFT, shadow: float = 0.0, outline: int = 0) -> float:
	var w := _width(text, font, size, spacing)
	var x := pos.x
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		x -= w * 0.5
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		x -= w
	for ch in text:
		var p := Vector2(x, pos.y)
		if outline > 0:
			draw_string_outline(font, p, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, Color(INK, 0.8 * color.a))
		if shadow > 0.0:
			draw_string(font, p + Vector2(shadow, shadow), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(INK, 0.9 * color.a))
		draw_string(font, p, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
		x += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + spacing
	return w


## 调用方传来的彩色（金 / 蓝 / 橙…）一律换成骨白；本来就是灰的保留
func _tone(c: Color) -> Color:
	return Color(c, c.a) if c.s < 0.25 else Color(BONE, c.a)


# ---------------------------------------------------------------- 图形小件

## 往右斜的平行四边形（上边往右、下边往左各偏 h/2·tan）
func _para(x: float, y: float, w: float, h: float, k: float = SKEW) -> PackedVector2Array:
	var s := h * 0.5 * k
	return PackedVector2Array([Vector2(x + s, y), Vector2(x + w + s, y), Vector2(x + w - s, y + h), Vector2(x - s, y + h)])


## 动态切出来的多边形（intersect_polygons 的碎片、血量很少时的剑身）可能是零面积细条，
## 引擎三角化失败会报 “Invalid polygon data”；先用同一个三角化试一遍，失败就不画
func _can_fill(pts: PackedVector2Array) -> bool:
	return pts.size() >= 3 and not Geometry2D.triangulate_polygon(pts).is_empty()


func _fill(pts: PackedVector2Array, color: Color) -> void:
	if _can_fill(pts):
		draw_colored_polygon(pts, color)


func _outline(pts: PackedVector2Array, color: Color, width: float = 1.0) -> void:
	var loop := pts.duplicate()
	loop.append(pts[0])
	draw_polyline(loop, color, width, true)


## 铸铁矛尖（11×26，pos = 左上角）
func _finial(pos: Vector2, color: Color) -> void:
	var p := PackedVector2Array([Vector2(5.5, 0), Vector2(10, 8), Vector2(6.6, 8), Vector2(6.6, 13), Vector2(8.5, 13),
			Vector2(8.5, 15), Vector2(6.6, 15), Vector2(6.6, 26), Vector2(4.4, 26), Vector2(4.4, 15), Vector2(2.5, 15),
			Vector2(2.5, 13), Vector2(4.4, 13), Vector2(4.4, 8), Vector2(1, 8)])
	for i in p.size():
		p[i] += pos
	draw_colored_polygon(p, color)


func _feather(center: Vector2, angle: float, scale_k: float, fill: Color, edge: Color) -> void:
	var pts := PackedVector2Array()
	for v in _feather_pts:
		pts.append(center + (v * scale_k).rotated(angle))
	if fill.a > 0.0:
		draw_colored_polygon(pts, fill)
	if edge.a > 0.0:
		var loop := pts.duplicate()
		loop.append(pts[0])
		draw_polyline(loop, edge, 1.0, true)
	var shaft := Vector2(0, 13 * scale_k).rotated(angle)
	draw_line(center - shaft, center + shaft, Color(Color("ede4ff"), maxf(fill.a, edge.a) * 0.8), 0.8, true)


## 两头透明、中间亮的细线
func _fade_line(a: Vector2, b: Vector2, color: Color, peak: float = 0.5, width: float = 1.0) -> void:
	var mid := a.lerp(b, peak)
	draw_polyline_colors(PackedVector2Array([a, mid, b]), PackedColorArray([Color(color, 0.0), color, Color(color, 0.0)]), width, true)


func _diamond(c: Vector2, r: float, color: Color, filled := true) -> void:
	var pts := PackedVector2Array([c + Vector2(0, -r * 1.25), c + Vector2(r, 0), c + Vector2(0, r * 1.25), c + Vector2(-r, 0)])
	if filled:
		draw_colored_polygon(pts, color)
	else:
		_outline(pts, color)


## 横向渐隐的暗底（左右两头透明）
func _band(rect: Rect2, alpha: float, k: float = 0.0, edge: float = 0.22) -> void:
	var xs := [rect.position.x, rect.position.x + rect.size.x * edge, rect.end.x - rect.size.x * edge, rect.end.x]
	var al := [0.0, alpha, alpha, 0.0]
	var s := rect.size.y * 0.5 * k
	for i in 3:
		var pts := PackedVector2Array([Vector2(xs[i] + s, rect.position.y), Vector2(xs[i + 1] + s, rect.position.y),
				Vector2(xs[i + 1] - s, rect.end.y), Vector2(xs[i] - s, rect.end.y)])
		draw_polygon(pts, PackedColorArray([Color(INK, al[i]), Color(INK, al[i + 1]), Color(INK, al[i + 1]), Color(INK, al[i])]))


# ---------------------------------------------------------------- 主体

func _draw() -> void:
	var vp := get_viewport_rect().size
	_draw_hurt(vp)
	_draw_hp()
	_draw_combo(vp)
	if _result_t <= 0.0:
		# 结算面板打开时不画弹出字和横幅，免得透过面板叠在一起；横幅在的时候也不画弹出字（不打架）
		if _banner == "" or _banner_t > _banner_life:
			_draw_callouts(vp)
		_draw_banner(vp)
	_draw_hint(vp)
	_draw_result(vp)
	if help_visible and help_text != "":
		var lines := help_text.split("\n")
		var y := vp.y - 18.0 - 20.0 * float(lines.size() - 1)
		for line in lines:
			_say(Vector2(24, y), line, _serif, 14, Color(MOON, 0.72), 0.0, HORIZONTAL_ALIGNMENT_LEFT, 0.0, 4)
			y += 20.0


func _draw_hp() -> void:
	# 斜切暗底面板：左边 0.88 → 0.6 → 右边透明，右缘往左下斜
	var top := 12.0
	var bot := 112.0
	var xr := func(y: float) -> float: return 500.0 - (y - top) * 0.49
	var xm := func(y: float) -> float: return xr.call(y) - 150.0
	draw_polygon(PackedVector2Array([Vector2(0, top), Vector2(xm.call(top), top), Vector2(xm.call(bot), bot), Vector2(0, bot)]),
			PackedColorArray([Color(INK, 0.88), Color(INK, 0.6), Color(INK, 0.6), Color(INK, 0.88)]))
	draw_polygon(PackedVector2Array([Vector2(xm.call(top), top), Vector2(xr.call(top), top), Vector2(xr.call(bot), bot), Vector2(xm.call(bot), bot)]),
			PackedColorArray([Color(INK, 0.6), Color(INK, 0.0), Color(INK, 0.0), Color(INK, 0.6)]))
	var jit := Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * 3.0 * _shake
	_draw_blade()
	_draw_wing()
	_draw_emblem(EMBLEM + jit)
	# 血量数字：滚动 + 挨打时一跳一红
	var nc := BONE.lerp(Color(0.95, 0.55, 0.6), _hp_flash)
	_say(Vector2(BLADE_X1 + 14, 54) + jit * 1.5, "%d" % ceili(_hp_disp), _digits, int(24 + 4 * _hp_flash), nc, 0.0,
			HORIZONTAL_ALIGNMENT_LEFT, 2.0)
	if wave_text != "":
		_say(Vector2(30, 132), wave_text, _serif, 13, MIST, 2.0, HORIZONTAL_ALIGNMENT_LEFT, 0.0, 4)


func _draw_blade() -> void:
	var maxhp := maxf(player_max_hp, 1.0)
	var frac := clampf(player_hp / maxhp, 0.0, 1.0)
	var ghost := clampf(_hp_ghost / maxhp, 0.0, 1.0)
	var xf := _blade_frac_x(frac) if frac < 0.999 else BLADE_X1
	var xg := _blade_frac_x(ghost) if ghost < 0.999 else BLADE_X1
	var low := frac < 0.3
	var beat := pow(maxf(0.0, sin(_time * 7.0)), 6.0) if low else 0.0     # 心跳式的尖脉冲
	# 护手（剑格）：竖的一截银条 + 两头小菱形
	var gx := BLADE_X0 - 9.0
	draw_colored_polygon(_para(gx, 30.0, 5.0, 32.0, 0.0), IRON)
	_diamond(Vector2(gx + 2.5, 28.0), 3.0, IRON)
	_diamond(Vector2(gx + 2.5, 64.0), 3.0, IRON)
	# 空槽
	var whole := _blade_poly(BLADE_X0, BLADE_X1)
	draw_colored_polygon(whole, Color(INK, 0.7))
	# 掉血残影：先闪白，再变成淡紫慢慢退
	if xg > xf + 0.5:
		var gc := Color(VIOLET_LIGHT, 0.32).lerp(Color(1, 1, 1, 0.95), _hp_flash)
		_fill(_blade_poly(xf, xg), gc)
	# 剑身
	if frac > 0.0:
		var top_c := Color.WHITE
		var bot_c := Color("aab2c0")
		if low:
			top_c = top_c.lerp(Color(0.9, 0.62, 0.66), 0.55 + 0.35 * beat)
			bot_c = bot_c.lerp(WINE.lightened(0.2), 0.6 + 0.3 * beat)
		var body := _blade_poly(BLADE_X0, xf)
		if _can_fill(body):
			draw_polygon(body, _blade_colors(body, top_c, bot_c))
		# 血槽：剑身中间一道暗线
		var gy := (BLADE_TOP + BLADE_BOT) * 0.5 - 1.0
		draw_line(Vector2(BLADE_X0 + 4, gy), Vector2(minf(xf, BLADE_X1 - 34.0), gy - 1.5), Color(INK, 0.35), 2.0)
		# 寒光扫过：一道斜的亮带，只画在剑身范围里
		if _sheen >= 0.0:
			var sx := lerpf(BLADE_X0 - 30.0, BLADE_X1 + 10.0, _sheen)
			var band := PackedVector2Array([Vector2(sx, BLADE_TOP - 2), Vector2(sx + 16, BLADE_TOP - 2), Vector2(sx + 6, BLADE_BOT + 2), Vector2(sx - 10, BLADE_BOT + 2)])
			for piece in Geometry2D.intersect_polygons(band, body):
				_fill(piece, Color(1, 1, 1, 0.75 * sin(_sheen * PI)))
		# 断口：亮的一条竖线
		if frac < 0.999:
			draw_line(Vector2(xf, _blade_top(xf)), Vector2(xf, _blade_bot(xf)), Color(1, 1, 1, 0.9), 1.5)
	# 分格刻痕（上沿的小 V 口）
	for i in range(1, 4):
		var x := _blade_frac_x(0.25 * i)
		draw_colored_polygon(PackedVector2Array([Vector2(x - 3, BLADE_TOP), Vector2(x + 3, BLADE_TOP), Vector2(x, BLADE_TOP + 4)]), Color(INK, 0.9))
	var edge := Color(SILVER, 0.6).lerp(Color(0.85, 0.35, 0.45, 0.9), beat)
	_outline(whole, edge, 1.0 + beat)
	# 碎片
	for s in _shards:
		var k: float = 1.0 - s.t / s.life
		var c := Color.WHITE.lerp(Color(0.8, 0.5, 0.6), 1.0 - k)
		c.a = k
		var sz: float = s.s
		var tri := PackedVector2Array([Vector2(-sz, -sz * 0.4), Vector2(sz, 0), Vector2(-sz * 0.3, sz * 0.6)])
		for i in tri.size():
			tri[i] = s.p + tri[i].rotated(s.r)
		draw_colored_polygon(tri, c)


func _draw_wing() -> void:
	var full := ult_frac >= 0.999
	var pulse := 0.5 + 0.5 * sin(_time * 5.0)
	for i in FEATHERS:
		var c := _feather_center(i)
		var a := _feather_angle(i)
		var sc := (0.92 + 0.07 * i) * (1.0 + 0.35 * _feather_pop[i])
		var k := clampf(ult_frac * FEATHERS - i, 0.0, 1.0)
		if full:
			_feather(c, a, sc * (1.28 + 0.08 * pulse), Color(VIOLET, 0.2 + 0.12 * pulse), Color(0, 0, 0, 0))
		# 底：暗羽 + 灰边
		_feather(c, a, sc, Color(INK, 0.6), Color(Color("4a5163"), 1.0))
		# 紫色从羽根往羽尖灌
		if k > 0.0:
			var pts := PackedVector2Array()
			for v in _feather_pts:
				pts.append(c + (v * sc).rotated(a))
			var h := 15.0 * sc
			var y_cut := h - 2.0 * h * k
			var clip := PackedVector2Array([Vector2(-10, y_cut), Vector2(10, y_cut), Vector2(10, h + 2), Vector2(-10, h + 2)])
			for j in clip.size():
				clip[j] = c + clip[j].rotated(a)
			var fill := Color(VIOLET, 0.95).lerp(Color(1, 1, 1, 1), _feather_pop[i] * 0.7)
			for piece in Geometry2D.intersect_polygons(pts, clip):
				_fill(piece, fill)
			var shaft := Vector2(0, 13 * sc).rotated(a)
			draw_line(c - shaft, c + shaft, Color(Color("ede4ff"), 0.8 * k), 0.8, true)
	# 满了：羽尖冒紫光点 + “J+K 绝影”，字上有一道光扫过
	for m in _motes:
		var k: float = 1.0 - m.t / m.life
		draw_circle(m.p, 1.6 * k + 0.6, Color(VIOLET_LIGHT, 0.85 * k))
	if full:
		var lx := 214.0
		var ly := 86.0
		var appear := clampf(_full_t / 0.25, 0.0, 1.0)
		lx += _say(Vector2(lx + (1.0 - appear) * 10.0, ly), "J+K", _digits, 16, Color(VIOLET_LIGHT, appear), 1.0) + 8.0
		var tw := _say(Vector2(lx + (1.0 - appear) * 10.0, ly), "绝影", _heavy, 16, Color(VIOLET_LIGHT, appear), 4.0)
		var sweep := fmod(_full_t, 1.6) / 0.5
		if sweep < 1.0:
			var sx := lerpf(lx - 50.0, lx + tw + 10.0, sweep)
			_fade_line(Vector2(sx - 6, ly + 4), Vector2(sx + 6, ly - 16), Color(1, 1, 1, 0.8 * sin(sweep * PI)), 0.5, 3.0)
	# 放了大招：羽毛四散
	for f in _flying:
		var k: float = 1.0 - f.t / f.life
		_feather(f.p, f.a, 1.0, Color(VIOLET, 0.85 * k), Color(0, 0, 0, 0))


## 鸦纹：菱形纹章当剑柄，里面的紫核随大招能量长大，满了呼吸发光；中间一根银羽
func _draw_emblem(c: Vector2) -> void:
	var r := 22.0
	var full := ult_frac >= 0.999
	var pulse := 0.5 + 0.5 * sin(_time * 5.0)
	if full:
		for i in 3:
			_diamond(c, r + 4.0 + 4.0 * i + 2.0 * pulse, Color(VIOLET, (0.16 - 0.05 * i) * (0.6 + 0.4 * pulse)))
	_diamond(c, r + 5.0, Color(SILVER, 0.3), false)
	_diamond(c, r, Color(INK, 0.92))
	_diamond(c, r, Color(SILVER, 0.85), false)
	var core := (r - 7.0) * sqrt(clampf(ult_frac, 0.0, 1.0))
	if core > 0.5:
		_diamond(c, core, Color(VIOLET, 0.55 + (0.35 * pulse if full else 0.2)))
	_diamond(c, r - 7.0, Color(SILVER, 0.35), false)
	# 顶上铸铁矛尖、底下小坠
	_finial(Vector2(c.x - 5.5, c.y - r * 1.25 - 24.0), IRON)
	_diamond(Vector2(c.x, c.y + r * 1.25 + 5.0), 3.0, IRON)
	_feather(c, deg_to_rad(24.0), 0.85, Color(Color("f2eeff") if full else SILVER, 0.95), Color(0, 0, 0, 0))


func _draw_combo(vp: Vector2) -> void:
	if style == null:
		return
	var right := vp.x - 30.0
	var r := style.rank_index()
	var rc := RANK_COLORS[r]
	# ---- 评价字母（哥特黑体）+ 斜线 + 段位名 ----
	var pop := 1.0 + 0.4 * _rank_pop
	var size := int(round(112.0 * pop))
	var glow := RANK_GLOW[r] * (1.0 + 0.35 * sin(_time * 5.0) if r == 4 else 1.0)
	var lw := _black.get_string_size(style.rank_letter(), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var lp := Vector2(right - lw, 112.0)
	if glow > 0.0:
		for o in [Vector2(-3, 0), Vector2(3, 0), Vector2(0, -3), Vector2(0, 3)]:
			draw_string(_black, lp + o, style.rank_letter(), HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(VIOLET, glow * 0.45))
	draw_string(_black, lp + Vector2(0, 3), style.rank_letter(), HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(INK, 0.9))
	draw_string(_black, lp + Vector2(0, 1), style.rank_letter(), HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color("6b778b"))
	draw_string(_black, lp, style.rank_letter(), HORIZONTAL_ALIGNMENT_LEFT, -1, size, rc)
	var sc := Vector2(right - 125.0, 92.0)
	var sd := Vector2(cos(deg_to_rad(-12.0)), sin(deg_to_rad(-12.0))) * 125.0
	_fade_line(sc - sd, sc + sd, Color(Color("e8ebf1"), 0.9), 0.6, 2.0)
	_say(Vector2(right - 118.0, 78.0), style.rank_name(), _heavy, 26, Color("f4f2ec"), 8.0, HORIZONTAL_ALIGNMENT_RIGHT, 2.0)
	var mx := right - 120.0 - 150.0
	draw_colored_polygon(_para(mx, 100.0, 150.0, 3.0, 0.58), Color(1, 1, 1, 0.14))
	draw_colored_polygon(_para(mx, 100.0, 150.0 * style.rank_progress(), 3.0, 0.58), Color(SILVER, 0.95))
	# ---- 连击数 ----
	if style.combo >= 2:
		var cpop := 1.0 + 0.35 * _combo_pop
		var csize := int(round(60.0 * cpop))
		var unit_w := _say(Vector2(right - 10.0, 202.0), "连击", _heavy, 16, Color("aeb7c6"), 5.0, HORIZONTAL_ALIGNMENT_RIGHT, 1.5)
		var col := BONE
		if style.combo >= 30:
			col = BONE.lerp(VIOLET_LIGHT, 0.25 + 0.15 * sin(_time * 6.0))
		_say(Vector2(right - 18.0 - unit_w, 202.0), "%d" % style.combo, _digits, csize, col, 0.0, HORIZONTAL_ALIGNMENT_RIGHT, 3.0)
		var tx := right - 10.0 - 180.0
		draw_colored_polygon(_para(tx, 214.0, 180.0, 4.0, 0.58), Color(1, 1, 1, 0.12))
		var f := style.combo_fraction()
		draw_colored_polygon(_para(tx + 180.0 * (1.0 - f), 214.0, 180.0 * f, 4.0, 0.58), Color(Color("e8ebf1"), 0.95))


func _draw_callouts(vp: Vector2) -> void:
	var y := 236.0
	var first := true
	for c in _callouts:
		var t: float = c.t
		var life: float = c.life
		var appear := clampf(t / 0.09, 0.0, 1.0)
		var fade := clampf((life - t) / 0.3, 0.0, 1.0)
		var scale := lerpf(1.5, 1.0, appear)
		var base: int = c.size if first else int(c.size * 0.72)
		var size := int(round(float(base) * scale))
		var col := _tone(c.color)
		col.a = fade * (1.0 if first else 0.8)
		var spacing := 14.0 if first else 8.0
		var w := _width(c.text, _heavy, size, spacing)
		var yy := y + (1.0 - fade) * 10.0
		if first:
			# 最新的一条：斜切黑底 + 两边细线 + 底下一道紫色刀痕
			var bw := w + 300.0
			_band(Rect2(vp.x * 0.5 - bw * 0.5, yy - size * 0.95, bw, size * 1.35), 0.82 * fade, SKEW, 0.22)
			var gap := w * 0.5 + 26.0
			_fade_line(Vector2(vp.x * 0.5 - gap - 110.0, yy - size * 0.32), Vector2(vp.x * 0.5 - gap, yy - size * 0.32), Color(Color("c9ced8"), fade), 1.0)
			_fade_line(Vector2(vp.x * 0.5 + gap, yy - size * 0.32), Vector2(vp.x * 0.5 + gap + 110.0, yy - size * 0.32), Color(Color("c9ced8"), fade), 0.0)
			var cut := lerpf(0.2, 1.0, appear) * (w + 120.0)
			_fade_line(Vector2(vp.x * 0.5 - cut * 0.5, yy + 10.0), Vector2(vp.x * 0.5 + cut * 0.5, yy + 6.0), Color(VIOLET_LIGHT, 0.85 * fade))
		_say(Vector2(vp.x * 0.5, yy), c.text, _heavy, size, col, spacing, HORIZONTAL_ALIGNMENT_CENTER, 3.0)
		# 新的在最上面，旧的往下让位、淡出时继续往下沉（不会和新字叠在一起）
		y += float(base) * lerpf(1.35, 1.55, 1.0 - appear) + 12.0
		first = false


func _draw_banner(vp: Vector2) -> void:
	if _banner == "" or _banner_t > _banner_life:
		return
	var a := clampf(_banner_t / 0.18, 0.0, 1.0) * clampf((_banner_life - _banner_t) / 0.4, 0.0, 1.0)
	var mid := vp.y * 0.36
	var h := 96.0 if _banner_sub == "" else 122.0
	_band(Rect2(Vector2(0, mid - 58), Vector2(vp.x, h)), 0.62 * a, 0.0, 0.3)
	_fade_line(Vector2(vp.x * 0.12, mid - 58), Vector2(vp.x * 0.88, mid - 58), Color(Color("c9ced8"), 0.45 * a))
	_fade_line(Vector2(vp.x * 0.12, mid - 58 + h), Vector2(vp.x * 0.88, mid - 58 + h), Color(Color("c9ced8"), 0.45 * a))
	var spread := lerpf(10.0, 0.0, clampf(_banner_t / 0.35, 0.0, 1.0))
	_say(Vector2(vp.x * 0.5, mid + 6), _banner, _heavy, 40, Color(BONE, a), 14.0 + spread, HORIZONTAL_ALIGNMENT_CENTER, 3.0)
	# 铁艺分隔线：两段细线 + 紫色空心菱形
	var open_k := clampf(_banner_t / 0.4, 0.0, 1.0)
	var half := lerpf(24.0, 150.0, 1.0 - pow(1.0 - open_k, 3.0))
	draw_line(Vector2(vp.x * 0.5 - half, mid + 24), Vector2(vp.x * 0.5 - 14, mid + 24), Color(RULE, a), 1.0)
	draw_line(Vector2(vp.x * 0.5 + 14, mid + 24), Vector2(vp.x * 0.5 + half, mid + 24), Color(RULE, a), 1.0)
	_diamond(Vector2(vp.x * 0.5, mid + 24), 6.0, Color(VIOLET_LIGHT, a), false)
	if _banner_sub != "":
		_say(Vector2(vp.x * 0.5, mid + 52), _banner_sub, _serif, 18, Color(MIST, a), 4.0, HORIZONTAL_ALIGNMENT_CENTER, 2.0)


func _draw_hint(vp: Vector2) -> void:
	if _hint_t <= 0.0 or _hint == "":
		return
	var a := clampf(_hint_t / 0.5, 0.0, 1.0)
	var size := 17
	var w := _width(_hint, _serif, size, 2.0) + 72.0
	var rect := Rect2(Vector2((vp.x - w) * 0.5, vp.y - 128.0), Vector2(w, 40))
	var k := 0.65                                        # tan(~33°)，牌子斜得比血条多一点
	var plate := _para(rect.position.x, rect.position.y, rect.size.x, rect.size.y, k)
	draw_colored_polygon(plate, Color(INK, 0.8 * a))
	_outline(plate, Color(SILVER, 0.5 * a))
	_outline(_para(rect.position.x - 4, rect.position.y - 4, rect.size.x + 8, rect.size.y + 8, k), Color(SILVER, 0.16 * a))
	_say(Vector2(vp.x * 0.5, rect.position.y + 27), _hint, _serif, size, Color(BONE, a), 2.0, HORIZONTAL_ALIGNMENT_CENTER)


func _draw_hurt(vp: Vector2) -> void:
	if _hurt_t <= 0.0:
		return
	var a := _hurt_t / 0.45
	var c := Color(WINE, 0.0)
	for i in 6:
		var k := float(i) * 10.0
		c.a = 0.09 * a * (1.0 - float(i) / 6.0)
		draw_rect(Rect2(0, 0, vp.x, k + 10), c)
		draw_rect(Rect2(0, vp.y - k - 10, vp.x, k + 10), c)
		draw_rect(Rect2(0, 0, k + 10, vp.y), c)
		draw_rect(Rect2(vp.x - k - 10, 0, k + 10, vp.y), c)


func _draw_result(vp: Vector2) -> void:
	# 只有无限循环的基类在用（雨街试玩用 scripts/ui/rain_trial_result.gd）
	if _result_t <= 0.0 or _result.is_empty():
		return
	var a := clampf(_result_t / 0.4, 0.0, 1.0) * clampf((6.5 - _result_t) / 0.3, 0.0, 1.0)
	var lines: Array = _result.get("lines", [])
	var h := 120.0 + 30.0 * float(lines.size())
	var rect := Rect2(Vector2(vp.x * 0.5 - 230.0, vp.y * 0.5 - h * 0.5 - 30.0), Vector2(460, h))
	draw_rect(rect, Color(INK, 0.93 * a))
	draw_rect(rect, Color(SILVER, 0.45 * a), false, 1.0)
	_say(Vector2(rect.position.x + rect.size.x * 0.5, rect.position.y + 42), String(_result.get("title", "结算")), _heavy, 28,
			Color(BONE, a), 6.0, HORIZONTAL_ALIGNMENT_CENTER, 2.0)
	var y := rect.position.y + 82.0
	for line in lines:
		_say(Vector2(rect.position.x + 40, y), String(line[0]), _serif, 17, Color(MIST, a), 3.0)
		_say(Vector2(rect.end.x - 40, y), String(line[1]), _serif, 17, Color(BONE, a), 0.0, HORIZONTAL_ALIGNMENT_RIGHT)
		y += 30.0
	var grade := String(_result.get("grade", ""))
	if grade != "":
		var gi := maxi(Style.RANKS.find(grade), 0)
		draw_string(_black, Vector2(rect.end.x - 92, rect.position.y + 64), grade, HORIZONTAL_ALIGNMENT_LEFT, -1, 64, Color(RANK_COLORS[gi], a))
	var foot := String(_result.get("footer", ""))
	if foot != "":
		_say(Vector2(rect.position.x + rect.size.x * 0.5, rect.end.y - 18), foot, _serif, 14, Color(STEEL, a), 1.0, HORIZONTAL_ALIGNMENT_CENTER)
