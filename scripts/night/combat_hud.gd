extends Control
## 试玩版 HUD：生命、大招、波次、连击 + 评价、中间弹出的"主题事件"字、提示、横幅、结算。
## 全部用 _draw 画，没有图片资源。数据由 night_trial.gd 每帧塞进来。
## 11-02 按墨银版定稿重画（docs/视觉设计/UI/整套重做_20261101/HUD定稿_墨银版_20261101.webp）：
## 左上细长银十字 + 红血条（细银框、荆棘银尖）+ 绝影五格银框紫条；右上银色手写评价字母 + 暗紫鸦羽翼 + 段位名 + 连击；
## “弹刀！”这类弹出字两边一对银荆棘饰翼。提示牌、横幅、结算沿用 10-31 的 A+C 版。紫只给主角（大招、高评价的光）。
## 字体：尖角哥特 PirataOne（评价字母）、石刻 Cinzel（连击数字）、毛笔狂草马善政（弹出字/段位名）、思源重宋（正文/横幅）。

const Style := preload("res://scripts/night/style_meter.gd")
const GothicFonts := preload("res://scripts/ui/gothic_fonts.gd")

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
const SKEW := 0.445                       ## tan(24°)：提示牌的斜切

var style: Style
var player_hp: float = 100.0
var player_max_hp: float = 100.0
var ult_frac: float = 0.0          ## 大招能量 0..1（满 = 可以放）
var wave_text: String = ""
var help_visible: bool = true
var help_text: String = ""
var muted := false                 ## 大招期间不弹提示字（ult_fx 控制）

var _font: Font                    ## 石刻混排重宋（兼容试玩结算页）
var _serif: Font
var _heavy: Font
var _digits: Font
var _black: Font
var _script: Font                  ## 兼容别名（指向尖角哥特黑体）
var _brush: Font                   ## 毛笔狂草（绝影、段位名、弹出字）
var _ult_icon: Texture2D           ## ControllerIconTexture(path="ult") 动态按键图标
var _ult_kb_fallback: Texture2D    ## 无头 / 脚本测试模式键鼠图标回退（R）
var _ult_pad_fallback: Texture2D   ## 无头 / 脚本测试模式手柄图标回退（RT）
var _ult_using_pad := false
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
# ---- 左上血条 / 绝影条的动效状态 ----
var _prev_hp := -1.0
var _prev_ult := 0.0
var _hp_disp := 100.0              ## 滚动显示的血量数字
var _hp_flash := 0.0               ## 掉血闪白 1 → 0
var _shake := 0.0                  ## 挨打时纹章 / 数字抖动 1 → 0
var _sheen := -1.0                 ## 银框寒光扫过进度 0..1（<0 = 没在扫）
var _sheen_wait := 1.5
var _full_t := -1.0                ## 大招满了多久（<0 = 没满）
var _cell_pop: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]
var _shards: Array = []            ## 掉血崩出的碎片 {p, v, r, w, s, life, t, red}
var _motes: Array = []             ## 大招满时格子上冒的紫光点 {p, v, life, t}
var _flying: Array = []            ## 放大招时从格子里飞散的紫光 {p, v, life, t}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = GothicFonts.cinzel(600, false, 600)
	_serif = GothicFonts.cinzel(500, false, 450)
	_heavy = GothicFonts.cinzel(800, false, 900)
	_digits = GothicFonts.digits(700, true)
	_black = GothicFonts.blackletter(700)
	_script = _black
	_brush = GothicFonts.brush(700)
	_setup_ult_icon()


func _exit_tree() -> void:
	if _ult_icon != null:
		if _ult_icon.changed.is_connected(queue_redraw):
			_ult_icon.changed.disconnect(queue_redraw)
		var ci := get_node_or_null("/root/ControllerIcons")
		if ci != null and _ult_icon.has_method("_on_input_type_changed"):
			var cb := Callable(_ult_icon, "_on_input_type_changed")
			if ci.is_connected("input_type_changed", cb):
				ci.disconnect("input_type_changed", cb)
		_ult_icon = null


func _input(event: InputEvent) -> void:
	if _ult_icon != null:
		return
	if event is InputEventKey or event is InputEventMouseButton:
		if _ult_using_pad:
			_ult_using_pad = false
			queue_redraw()
	elif event is InputEventJoypadButton:
		if not _ult_using_pad:
			_ult_using_pad = true
			queue_redraw()
	elif event is InputEventJoypadMotion:
		if absf((event as InputEventJoypadMotion).axis_value) >= 0.2 and not _ult_using_pad:
			_ult_using_pad = true
			queue_redraw()


const CONTROLLER_ICON_TEX_PATH := "res://addons/controller_icons/objects/ControllerIconTexture.gd"
const DEFAULT_ULT_KB_ICON := "res://addons/controller_icons/assets/key/r.png"
const DEFAULT_ULT_PAD_ICON := "res://addons/controller_icons/assets/xbox360/rt.png"


func _setup_ult_icon() -> void:
	_refresh_ult_fallback_icons()
	# 实机非无头且非 --script 独立 SceneTree 时启用 ControllerIconTexture(path="ult") 实时切换；
	# 无头或 --script 测试环境避免 DisplayServer.keyboard_get_keycode_from_physical 报错与全局标识符缺失。
	if DisplayServer.get_name() != "headless" and get_tree() != null and get_tree().get_script() == null:
		var ci := get_node_or_null("/root/ControllerIcons")
		if ci != null and ResourceLoader.exists(CONTROLLER_ICON_TEX_PATH):
			var icon_script: GDScript = load(CONTROLLER_ICON_TEX_PATH)
			if icon_script != null:
				var tex: Texture2D = icon_script.new()
				tex.set("path", "ult")
				tex.changed.connect(queue_redraw)
				_ult_icon = tex


func _refresh_ult_fallback_icons() -> void:
	var kb_path := ""
	var pad_path := ""
	if InputMap.has_action("ult"):
		for ev in InputMap.action_get_events("ult"):
			if ev is InputEventKey and kb_path == "":
				var kev := ev as InputEventKey
				var kc: int = kev.keycode if kev.keycode != 0 else kev.physical_keycode
				var ks := OS.get_keycode_string(kc).to_lower()
				var candidate := "res://addons/controller_icons/assets/key/%s.png" % ks
				if ResourceLoader.exists(candidate):
					kb_path = candidate
			elif ev is InputEventJoypadMotion and pad_path == "":
				var mev := ev as InputEventJoypadMotion
				match mev.axis:
					JOY_AXIS_TRIGGER_RIGHT:
						pad_path = "res://addons/controller_icons/assets/xbox360/rt.png"
					JOY_AXIS_TRIGGER_LEFT:
						pad_path = "res://addons/controller_icons/assets/xbox360/lt.png"
			elif ev is InputEventJoypadButton and pad_path == "":
				var bev := ev as InputEventJoypadButton
				match bev.button_index:
					JOY_BUTTON_RIGHT_SHOULDER:
						pad_path = "res://addons/controller_icons/assets/xbox360/rb.png"
					JOY_BUTTON_LEFT_SHOULDER:
						pad_path = "res://addons/controller_icons/assets/xbox360/lb.png"
	if kb_path == "":
		kb_path = DEFAULT_ULT_KB_ICON
	if pad_path == "":
		pad_path = DEFAULT_ULT_PAD_ICON
	if ResourceLoader.exists(kb_path):
		_ult_kb_fallback = load(kb_path)
	if ResourceLoader.exists(pad_path):
		_ult_pad_fallback = load(pad_path)


func is_using_pad_prompt() -> bool:
	if _ult_icon != null:
		var ci := get_node_or_null("/root/ControllerIcons")
		if ci != null:
			return int(ci.get("_last_input_type")) == 1
	return _ult_using_pad


func get_ult_prompt_texture() -> Texture2D:
	if _ult_kb_fallback == null or _ult_pad_fallback == null:
		_refresh_ult_fallback_icons()
	if _ult_icon != null and _ult_icon.get_width() > 2 and _ult_icon.get_height() > 2:
		return _ult_icon
	return _ult_pad_fallback if _ult_using_pad else _ult_kb_fallback


func get_ult_resolved_icon_path() -> String:
	if _ult_icon != null:
		var inner = _ult_icon.get("_textures")
		if inner is Array and not inner.is_empty() and inner[0] is Texture2D:
			return (inner[0] as Texture2D).resource_path
	var fb := _ult_pad_fallback if _ult_using_pad else _ult_kb_fallback
	return fb.resource_path if fb != null else ""


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
	_step_left(delta)
	queue_redraw()


# ---------------------------------------------------------------- 左上：十字表轴 + 红血条 + 绝影条（11-17 用户选定 G3「钟楼指针」）
# 部件全部从 docs/视觉设计/UI/HUD方案_20261117/HUD方案G3_钟楼指针.png 拆出来（tools/art/hud_g3_parts.py），
# 图是游戏里大小的 2 倍。下面的坐标 = (HUD_X, HUD_Y) + G3 像素坐标 × HUD_S；要调整组大小，改 HUD_S 并重新拆图。

const HUD_S := 0.2
const HUD_X := 0.0
const HUD_Y := -8.0
const HUD_FRAME := preload("res://assets/image/ui/hud/frame.png")
const HUD_SLOT := preload("res://assets/image/ui/hud/slot.png")
const HUD_FILL := preload("res://assets/image/ui/hud/fill.png")
const HUD_LABEL_ULT := preload("res://assets/image/ui/hud/label_ult.png")
const HUD_DIGITS := preload("res://assets/image/ui/hud/digits.png")
const HUD_CELLS: Array[Texture2D] = [
	preload("res://assets/image/ui/hud/cell_0.png"),
	preload("res://assets/image/ui/hud/cell_1.png"),
	preload("res://assets/image/ui/hud/cell_2.png"),
	preload("res://assets/image/ui/hud/cell_3.png"),
	preload("res://assets/image/ui/hud/cell_4.png"),
]
const FRAME_RECT := Rect2(HUD_X, HUD_Y + 40.0 * HUD_S, 1672.0 * HUD_S, 860.0 * HUD_S)
const LABEL_ULT_RECT := Rect2(HUD_X + 285.0 * HUD_S, HUD_Y + 565.0 * HUD_S, 260.0 * HUD_S, 140.0 * HUD_S)
const ULT_ICON_ANCHOR := Vector2(HUD_X + 1372.0 * HUD_S, HUD_Y + 628.0 * HUD_S)
const ULT_ICON_HEIGHT := 26.0
const ULT_ICON_MAX_W := 56.0
const CROSS := Vector2(HUD_X + 218.0 * HUD_S, HUD_Y + 435.0 * HUD_S)    ## 十字交点（表轴）
const BAR_X0 := HUD_X + 268.0 * HUD_S     ## 血槽
const BAR_X1 := HUD_X + 1452.0 * HUD_S
const BAR_TOP := HUD_Y + 406.0 * HUD_S
const BAR_BOT := HUD_Y + 476.0 * HUD_S
const BAR_LINE_TOP := HUD_Y + 391.0 * HUD_S   ## 框上下两道亮线（寒光沿着走）
const BAR_LINE_BOT := HUD_Y + 484.0 * HUD_S
const ULT_TOP := HUD_Y + 591.0 * HUD_S    ## 绝影五格
const ULT_BOT := HUD_Y + 665.0 * HUD_S
const CELL_X: Array[Vector2] = [
	Vector2(HUD_X + 636.0 * HUD_S, HUD_X + 762.0 * HUD_S),
	Vector2(HUD_X + 767.0 * HUD_S, HUD_X + 889.0 * HUD_S),
	Vector2(HUD_X + 894.0 * HUD_S, HUD_X + 1016.0 * HUD_S),
	Vector2(HUD_X + 1023.0 * HUD_S, HUD_X + 1143.0 * HUD_S),
	Vector2(HUD_X + 1151.0 * HUD_S, HUD_X + 1275.0 * HUD_S),
]
const CELLS := 5
const DIGIT_CELL := Vector2(51, 75)       ## 数字图集一格
const DIGIT_ADV := 15.3
const SLASH_ADV := 8.7
const DIGIT_STEEL := Color(0.8, 0.84, 0.9)    ## 数字压成 G3 的冷钢色，不要纯白
const FILL_GAIN := 1.3                        ## G3 的红血是深酒红，满血时略提一点亮
const BLOOD_DARK := Color("5e0a14")
const BLOOD := Color("b81c2b")
const BLOOD_LIGHT := Color("ff5560")


func _bar_x(f: float) -> float:
	return lerpf(BAR_X0, BAR_X1, clampf(f, 0.0, 1.0))


func _cell_rect(i: int) -> Rect2:
	return Rect2(CELL_X[i].x, ULT_TOP, CELL_X[i].y - CELL_X[i].x, ULT_BOT - ULT_TOP)


func _step_left(delta: float) -> void:
	var maxhp := maxf(player_max_hp, 1.0)
	if _prev_hp < 0.0:
		_prev_hp = player_hp
		_hp_disp = player_hp
	if player_hp < _prev_hp - 0.01:
		# 掉血：缺口闪白，碎片（血红 / 白）从新旧两端之间崩出去，十字和数字抖一下
		_hp_flash = 1.0
		_shake = 1.0
		var xa := _bar_x(player_hp / maxhp)
		var xb := _bar_x(_prev_hp / maxhp)
		var n := clampi(int((xb - xa) / 6.0) + 4, 5, 14)
		for i in n:
			_shards.append({"p": Vector2(_rng.randf_range(xa, maxf(xb, xa + 4.0)), _rng.randf_range(BAR_TOP, BAR_BOT)),
					"v": Vector2(_rng.randf_range(-30.0, 150.0), _rng.randf_range(-170.0, -40.0)),
					"r": _rng.randf_range(0.0, TAU), "w": _rng.randf_range(-12.0, 12.0),
					"s": _rng.randf_range(1.8, 3.8), "life": _rng.randf_range(0.45, 0.7), "t": 0.0,
					"red": _rng.randf() < 0.65})
	_prev_hp = player_hp
	_hp_disp = move_toward(_hp_disp, player_hp, maxf(30.0, absf(_hp_disp - player_hp) * 8.0) * delta)
	_hp_flash = maxf(0.0, _hp_flash - delta * 3.5)
	_shake = maxf(0.0, _shake - delta * 4.0)
	# 寒光：每隔几秒从十字扫到荆棘尖
	if _sheen >= 0.0:
		_sheen += delta / 0.7
		if _sheen > 1.0:
			_sheen = -1.0
			_sheen_wait = _rng.randf_range(2.6, 4.0)
	else:
		_sheen_wait -= delta
		if _sheen_wait <= 0.0:
			_sheen = 0.0
	# 绝影格：每攒满一格亮一下；全满开始计时；满了之后掉下去 = 放了大招，紫光从格子里飞散
	for i in CELLS:
		var th := float(i + 1) / CELLS
		if _prev_ult < th - 0.001 and ult_frac >= th - 0.001:
			_cell_pop[i] = 1.0
		_cell_pop[i] = maxf(0.0, _cell_pop[i] - delta * 4.0)
	if ult_frac >= 0.999:
		_full_t = 0.0 if _full_t < 0.0 else _full_t + delta
		if _rng.randf() < delta * 7.0:
			var r := _cell_rect(_rng.randi_range(0, CELLS - 1))
			_motes.append({"p": Vector2(_rng.randf_range(r.position.x, r.end.x), r.position.y),
					"v": Vector2(_rng.randf_range(4.0, 22.0), _rng.randf_range(-34.0, -14.0)), "life": _rng.randf_range(0.6, 1.0), "t": 0.0})
	else:
		if _full_t >= 0.0 and ult_frac < 0.5:
			for i in CELLS:
				var r := _cell_rect(i)
				for j in 4:
					_flying.append({"p": r.get_center() + Vector2(_rng.randf_range(-8, 8), 0),
							"v": Vector2(_rng.randf_range(60.0, 220.0), _rng.randf_range(-110.0, -20.0)),
							"life": _rng.randf_range(0.5, 0.9), "t": 0.0})
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
		f.v *= 1.0 - 1.8 * delta
		f.p += f.v * delta
	_flying = _flying.filter(func(f): return f.t < f.life)


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


## 弹出字两边的银荆棘饰翼：上下两根往外甩的荆棘枝（三次贝塞尔，根粗尖细），枝上交替往回勾的小刺，
## 中间一根短枝；k 0..1 = 长出来的进度，dir -1 左 / 1 右
const WING_BRANCHES := [
	[Vector2(0, -2), Vector2(42, 4), Vector2(84, -34), Vector2(128, -26), 2.2],
	[Vector2(0, 3), Vector2(38, 10), Vector2(72, 24), Vector2(108, 14), 1.8],
	[Vector2(0, 0), Vector2(26, -2), Vector2(52, -6), Vector2(78, -4), 1.3],
]


func _thorn_wing(o: Vector2, dir: float, k: float, alpha: float) -> void:
	var silver := Color(Color("e2e6ed"), alpha)
	var shade := Color(INK, 0.75 * alpha)
	for br in WING_BRANCHES:
		var pts := PackedVector2Array()
		for i in 17:
			var t := float(i) / 16.0 * k
			var u := 1.0 - t
			var p: Vector2 = br[0] * u * u * u + br[1] * 3.0 * u * u * t + br[2] * 3.0 * u * t * t + br[3] * t * t * t
			pts.append(o + Vector2(p.x * dir, p.y))
		var w0: float = br[4]
		for i in 16:
			var w := lerpf(w0, 0.5, float(i) / 15.0)
			draw_line(pts[i], pts[i + 1], shade, w + 1.6, true)
		for i in 16:
			var w := lerpf(w0, 0.5, float(i) / 15.0)
			draw_line(pts[i], pts[i + 1], silver, w, true)
		for n in 4:
			var j := 4 + n * 3
			var tang := (pts[j + 1] - pts[j - 1]).normalized()
			if tang == Vector2.ZERO:
				continue
			var reach := 7.0 - 1.2 * n
			var tip := pts[j] + tang.orthogonal() * (reach if n % 2 == 0 else -reach) - tang * reach * 0.8
			draw_line(pts[j], tip, shade, 2.4, true)
			draw_line(pts[j], tip, silver, 1.0, true)
	draw_circle(o, 4.0, Color(VIOLET, 0.3 * alpha))
	draw_circle(o, 1.6, Color(VIOLET_LIGHT, 0.9 * alpha))


## 两头透明、中间亮的细线
func _fade_line(a: Vector2, b: Vector2, color: Color, peak: float = 0.5, width: float = 1.0) -> void:
	var mid := a.lerp(b, peak)
	draw_polyline_colors(PackedVector2Array([a, mid, b]), PackedColorArray([Color(color, 0.0), color, Color(color, 0.0)]), width, true)


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
	var jit := Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * 2.5 * _shake
	draw_set_transform(jit * 0.4)
	_draw_bar()
	draw_texture_rect(HUD_FRAME, FRAME_RECT, false)
	_draw_cross_glow()
	_draw_sheen()
	_draw_ult()
	draw_set_transform(Vector2.ZERO)
	_draw_shards()
	# 血量数字：滚动 + 挨打时一跳一红
	var nc := DIGIT_STEEL.lerp(BLOOD_LIGHT, _hp_flash * 0.8)
	var pos := Vector2(HUD_X + 466.0 * HUD_S, HUD_Y + 334.0 * HUD_S) + jit
	pos.x += _digit_run(pos, "%d" % ceili(_hp_disp), nc, 1.0 + 0.1 * _hp_flash) + 4.0
	pos.x += _digit_run(pos, "/", Color(DIGIT_STEEL, 0.85), 1.0) + 4.0
	_digit_run(pos, "%d" % roundi(player_max_hp), Color(DIGIT_STEEL, 0.85), 1.0)
	if wave_text != "":
		_say(Vector2(56, 160), wave_text, _serif, 13, MIST, 2.0, HORIZONTAL_ALIGNMENT_LEFT, 0.0, 4)


## 画一串银色数字（0-9 和 /），pos 是基线左端，返回总宽度
func _digit_run(pos: Vector2, text: String, color: Color, scale: float) -> float:
	var x := pos.x
	var size := DIGIT_CELL * 0.5 * scale
	for ch in text:
		var i := 10 if ch == "/" else ch.to_int()
		draw_texture_rect_region(HUD_DIGITS, Rect2(x - 2.7 * scale, pos.y - 28.0 * scale, size.x, size.y),
				Rect2(i * DIGIT_CELL.x, 0.0, DIGIT_CELL.x, DIGIT_CELL.y), color)
		x += (SLASH_ADV if ch == "/" else DIGIT_ADV) * scale
	return x - pos.x


## 十字交点的紫光（图里已经有一层，这里随绝影加亮）
func _draw_cross_glow() -> void:
	var pulse := 0.5 + 0.5 * sin(_time * 4.0)
	var g := 0.25 + 0.75 * ult_frac
	if ult_frac >= 0.999:
		g *= 0.85 + 0.35 * pulse
	for i in 4:
		draw_circle(CROSS, 13.0 - 3.0 * i, Color(VIOLET, 0.045 * g * (i + 1)))
	_fade_line(CROSS - Vector2(13.0 * g, 0), CROSS + Vector2(13.0 * g, 0), Color(VIOLET_LIGHT, 0.6 * g), 0.5, 1.2)
	_fade_line(CROSS - Vector2(0, 13.0 * g), CROSS + Vector2(0, 13.0 * g), Color(VIOLET_LIGHT, 0.6 * g), 0.5, 1.2)


## 寒光：每隔几秒沿血条银框的上下两道亮线扫过去
func _draw_sheen() -> void:
	if _sheen < 0.0:
		return
	var sx := lerpf(BAR_X0 - 10.0, BAR_X1 + 40.0, _sheen)
	var c := Color(1, 1, 1, 0.85 * sin(_sheen * PI))
	for y in [BAR_LINE_TOP, BAR_LINE_BOT]:
		_fade_line(Vector2(sx - 20.0, y), Vector2(sx + 20.0, y), c, 0.5, 1.4)


## 血条：画在框下面。空槽 → 掉血残影 → 红血（都用 G3 的质感，从左往右露出来）
func _draw_bar() -> void:
	var maxhp := maxf(player_max_hp, 1.0)
	var frac := clampf(player_hp / maxhp, 0.0, 1.0)
	var ghost := clampf(_hp_ghost / maxhp, 0.0, 1.0)
	var xf := _bar_x(frac)
	var xg := _bar_x(ghost)
	var beat := pow(maxf(0.0, sin(_time * 7.0)), 6.0) if frac < 0.3 else 0.0     # 心跳式的尖脉冲
	var h := BAR_BOT - BAR_TOP
	draw_texture_rect(HUD_SLOT, Rect2(BAR_X0, BAR_TOP, BAR_X1 - BAR_X0, h), false)
	if xg > xf + 0.5:
		_bar_part(xf, xg, Color(0.62, 0.28, 0.3, 0.75))
		draw_rect(Rect2(xf, BAR_TOP + 1.5, minf(xg, BAR_X1 - 4.0) - xf, h - 3.0), Color(1, 1, 1, 0.95 * _hp_flash))
	if frac > 0.0:
		var bright := FILL_GAIN + 0.45 * beat
		_bar_part(BAR_X0, xf, Color(bright, bright, bright))
		if frac < 0.999:
			draw_rect(Rect2(xf - 4.0, BAR_TOP + 1.5, 4.0, h - 3.0), Color(BLOOD_LIGHT, 0.3 + 0.3 * beat))
			draw_line(Vector2(xf, BAR_TOP + 1.5), Vector2(xf, BAR_BOT - 1.5), Color(1, 0.88, 0.86, 0.95), 1.2)


func _bar_part(x0: float, x1: float, color: Color) -> void:
	var u := float(HUD_FILL.get_width()) / (BAR_X1 - BAR_X0)
	draw_texture_rect_region(HUD_FILL, Rect2(x0, BAR_TOP, x1 - x0, BAR_BOT - BAR_TOP),
			Rect2((x0 - BAR_X0) * u, 0.0, (x1 - x0) * u, HUD_FILL.get_height()), color)


## 掉血崩出的碎片
func _draw_shards() -> void:
	for s in _shards:
		var k: float = 1.0 - s.t / s.life
		var c := (BLOOD_LIGHT if s.red else Color.WHITE).lerp(BLOOD_DARK, 1.0 - k)
		c.a = k
		var sz: float = s.s
		var tri := PackedVector2Array([Vector2(-sz, -sz * 0.4), Vector2(sz, 0), Vector2(-sz * 0.3, sz * 0.6)])
		for i in tri.size():
			tri[i] = s.p + tri[i].rotated(s.r)
		draw_colored_polygon(tri, c)


## 绝影条：框和没亮的格子在 frame 里，这里画亮的格子、“绝影”和动态按键图标（键鼠 R / 手柄 RT）
func _draw_ult() -> void:
	var full := ult_frac >= 0.999
	var pulse := 0.5 + 0.5 * sin(_time * 5.0)
	draw_texture_rect(HUD_LABEL_ULT, LABEL_ULT_RECT, false, Color.WHITE.lerp(VIOLET_LIGHT, 0.45 * pulse if full else 0.0))
	for i in CELLS:
		var k := clampf(ult_frac * CELLS - i, 0.0, 1.0)
		if k <= 0.0:
			continue
		var r := _cell_rect(i)
		var tex: Texture2D = HUD_CELLS[i]
		var lit := 1.0 + (0.18 * pulse if full else 0.0)
		draw_texture_rect_region(tex, Rect2(r.position, Vector2(r.size.x * k, r.size.y)),
				Rect2(0.0, 0.0, tex.get_width() * k, tex.get_height()), Color(lit, lit, lit))
		if _cell_pop[i] > 0.0:
			draw_rect(r.grow(-1.5), Color(1, 1, 1, 0.75 * _cell_pop[i]))
	# 大招按键图标（ControllerIconTexture path="ult"）：没满时压暗，满了提亮并扫寒光
	var appear := clampf(_full_t / 0.25, 0.0, 1.0) if full else 0.0
	var key_tex := get_ult_prompt_texture()
	if key_tex != null and key_tex.get_width() > 2 and key_tex.get_height() > 2:
		var aspect := float(key_tex.get_width()) / maxf(float(key_tex.get_height()), 1.0)
		var ih := ULT_ICON_HEIGHT
		var iw := ih * aspect
		if iw > ULT_ICON_MAX_W:
			iw = ULT_ICON_MAX_W
			ih = iw / aspect
		var icon_rect := Rect2(ULT_ICON_ANCHOR.x, ULT_ICON_ANCHOR.y - ih * 0.5, iw, ih)
		draw_circle(icon_rect.get_center(), maxf(iw, ih) * 0.52, Color(INK, 0.45))
		if full:
			draw_circle(icon_rect.get_center(), maxf(iw, ih) * 0.62, Color(VIOLET, (0.22 + 0.16 * pulse) * appear))
		draw_texture_rect(key_tex, icon_rect, false, Color(0.62, 0.64, 0.7, 0.82).lerp(Color.WHITE, appear))
		if full:
			var sweep := fmod(_full_t, 1.6) / 0.5
			if sweep < 1.0:
				var sx := lerpf(icon_rect.position.x, icon_rect.end.x, sweep)
				_fade_line(Vector2(sx - 4.0, icon_rect.end.y - 3.0), Vector2(sx + 4.0, icon_rect.position.y + 3.0),
						Color(1, 1, 1, 0.85 * sin(sweep * PI)), 0.5, 2.6)
	for m in _motes:
		var k: float = 1.0 - m.t / m.life
		draw_circle(m.p, 1.5 * k + 0.6, Color(VIOLET_LIGHT, 0.85 * k))
	for f in _flying:
		var k: float = 1.0 - f.t / f.life
		draw_circle(f.p, 2.2 * k + 0.6, Color(VIOLET_LIGHT, 0.9 * k))
		draw_circle(f.p, 5.0 * k, Color(VIOLET, 0.25 * k))


# ---------------------------------------------------------------- 银饰小件

## 擦亮的银线（横的）：墨色衬边 + 银线 + 一段静止的高光
func _silver(a: Vector2, b: Vector2, width: float = 1.2, alpha: float = 1.0) -> void:
	draw_line(a + Vector2(0.5, 1.0), b + Vector2(0.5, 1.0), Color(INK, 0.8 * alpha), width + 1.6, true)
	draw_line(a, b, Color(Color("b4bbc7"), alpha), width, true)
	_fade_line(a, b, Color(1, 1, 1, 0.45 * alpha), 0.28, width)


## 荆棘银尖：从 (x0, y) 往 dir（1 右 / -1 左）收成细尖，中段两对往回勾的小刺
func _thorn(x0: float, y: float, length: float, h: float, dir: float = 1.0, alpha: float = 1.0) -> void:
	var body := PackedVector2Array([Vector2(x0, y - h * 0.32), Vector2(x0 + dir * length * 0.3, y - h * 0.16),
			Vector2(x0 + dir * length, y), Vector2(x0 + dir * length * 0.3, y + h * 0.16), Vector2(x0, y + h * 0.32)])
	var under := body.duplicate()
	for i in under.size():
		under[i] += Vector2(0.6, 1.0)
	_fill(under, Color(INK, 0.8 * alpha))
	_fill(body, Color(Color("c4cad5"), alpha))
	draw_line(Vector2(x0, y - 0.5), Vector2(x0 + dir * length * 0.92, y - 0.2), Color(1, 1, 1, 0.75 * alpha), 0.8, true)
	for k in [0.22, 0.5]:
		var bx: float = x0 + dir * length * k
		var reach: float = h * (1.15 - k)
		for s in [-1.0, 1.0]:
			var stroke := PackedVector2Array([Vector2(bx, y + s * h * 0.12), Vector2(bx + dir * 1.5, y + s * reach * 0.6),
					Vector2(bx - dir * 4.0, y + s * reach)])
			draw_polyline(stroke, Color(INK, 0.75 * alpha), 2.6, true)
			draw_polyline(stroke, Color(Color("d8dde5"), alpha), 1.1, true)


## 鸦羽：base 是羽根，沿 angle 长 length；一侧宽一侧窄，靠尖处两道缺口；edge 是上沿的一丝光
func _crow(base: Vector2, angle: float, length: float, width: float, fill: Color, edge: Color) -> void:
	var dir := Vector2.RIGHT.rotated(angle)
	var nrm := dir.orthogonal()
	var side_a := PackedVector2Array()
	var side_b := PackedVector2Array()
	var steps := 16
	for i in steps + 1:
		var t := float(i) / steps
		var prof := sin(PI * pow(t, 0.7)) * (1.0 - 0.2 * t)
		var wa := width * 0.62 * prof
		if absf(t - 0.6) < 0.035 or absf(t - 0.78) < 0.03:
			wa *= 0.5
		var p := base + dir * (length * t)
		side_a.append(p + nrm * wa)
		side_b.append(p - nrm * width * 0.36 * prof)
	var pts := side_a.duplicate()
	for i in range(steps - 1, 0, -1):
		pts.append(side_b[i])
	_fill(pts, fill)
	if edge.a > 0.0:
		draw_polyline(side_a, edge, 1.0, true)
	draw_line(base - dir * 4.0, base + dir * length * 0.9, Color(Color("6d7486"), fill.a * 0.7), 0.8, true)


## 右上评价字母背后的暗紫鸦羽翼：从字的左下往右上斜着甩出去，评价越高越亮；轻轻起伏
func _wing(root: Vector2, alpha: float, glow: bool) -> void:
	var lens := [104.0, 116.0, 120.0, 108.0, 88.0]
	draw_circle(root, 12.0, Color(INK, 0.55 * alpha))
	for i in range(4, -1, -1):
		var ang := deg_to_rad(-22.0 - 7.0 * i) + 0.03 * sin(_time * 2.0 + i * 0.6)
		var b := root + Vector2(-2.0 * i, 2.0 * i)
		_crow(b, ang, lens[i] + 4.0, 26.0, Color(VIOLET, (0.1 + (0.08 if glow else 0.0)) * alpha), Color(0, 0, 0, 0))
		_crow(b, ang, lens[i], 20.0, Color(Color("2c1752"), 0.95 * alpha),
				Color(VIOLET_LIGHT, (0.5 + (0.3 if glow else 0.0)) * alpha))


func _draw_combo(vp: Vector2) -> void:
	if style == null:
		return
	var right := vp.x - 34.0
	var r := style.rank_index()
	var rc := RANK_COLORS[r]
	var letter := style.rank_letter()
	var cx := right - 64.0
	var base_y := 118.0
	# ---- 评价字母：维多利亚尖角哥特黑体，背后一片暗紫鸦羽翼 ----
	_wing(Vector2(cx - 54.0, base_y + 4.0), 0.6 + 0.1 * r, r >= 3)
	var pop := 1.0 + 0.4 * _rank_pop
	var size := int(round(112.0 * pop))
	var lw := _black.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var lp := Vector2(cx - lw * 0.5, base_y)
	var glow := RANK_GLOW[r] * (1.0 + 0.35 * sin(_time * 5.0) if r == 4 else 1.0)
	if glow > 0.0:
		for o in [Vector2(-3, 0), Vector2(3, 0), Vector2(0, -3), Vector2(0, 3)]:
			draw_string(_black, lp + o, letter, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(VIOLET, glow * 0.45))
	draw_string_outline(_black, lp + Vector2(0, 2), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 8, Color(INK, 0.85))
	draw_string_outline(_black, lp + Vector2(0, 2), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 2, Color("5d6678"))
	draw_string_outline(_black, lp, letter, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 1, rc)
	draw_string(_black, lp, letter, HORIZONTAL_ALIGNMENT_LEFT, -1, size, rc)
	# ---- 段位名 + 细银线（亮的那截 = 到下一级的进度）----
	_say(Vector2(cx, base_y + 44.0), style.rank_name(), _brush, 30, Color("f1eee6"), 4.0, HORIZONTAL_ALIGNMENT_CENTER, 2.0, 4)
	var ly := base_y + 58.0
	_silver(Vector2(cx - 74.0, ly), Vector2(cx + 74.0, ly), 1.0, 0.85)
	_thorn(cx - 74.0, ly, 12.0, 7.0, -1.0, 0.85)
	_thorn(cx + 74.0, ly, 12.0, 7.0, 1.0, 0.85)
	draw_line(Vector2(cx - 74.0, ly), Vector2(cx - 74.0 + 148.0 * style.rank_progress(), ly), Color(VIOLET_LIGHT, 0.7), 1.2, true)
	# ---- 连击数：刀锋石刻数字 + “连击”，底下一根计时细线 ----
	if style.combo >= 2:
		var cy := base_y + 104.0
		var cpop := 1.0 + 0.35 * _combo_pop
		var csize := int(round(50.0 * cpop))
		var unit_w := _say(Vector2(right + 6.0, cy), "连击", _brush, 24, Color("d9dde5"), 2.0, HORIZONTAL_ALIGNMENT_RIGHT, 1.5, 3)
		var col := BONE
		if style.combo >= 30:
			col = BONE.lerp(VIOLET_LIGHT, 0.25 + 0.15 * sin(_time * 6.0))
		_say(Vector2(right - unit_w - 4.0, cy), "%d" % style.combo, _digits, csize, col, 1.0, HORIZONTAL_ALIGNMENT_RIGHT, 2.5, 4)
		var tx0 := right - 150.0
		draw_line(Vector2(tx0, cy + 10.0), Vector2(right + 6.0, cy + 10.0), Color(1, 1, 1, 0.12), 1.5)
		var f := style.combo_fraction()
		draw_line(Vector2(right + 6.0 - 156.0 * f, cy + 10.0), Vector2(right + 6.0, cy + 10.0), Color(Color("e8ebf1"), 0.9), 1.5)


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
		var spacing := 6.0 if first else 4.0
		size = int(round(float(size) * 1.15))       # 手写字比宋体显小
		var w := _width(c.text, _brush, size, spacing)
		var yy := y + (1.0 - fade) * 10.0
		if first:
			# 最新的一条：两边一对银荆棘饰翼（出来时从字边长出去），字背后一层淡紫光
			var gap := w * 0.5 + 14.0
			var grow := 1.0 - pow(1.0 - clampf(t / 0.2, 0.0, 1.0), 3.0)
			_thorn_wing(Vector2(vp.x * 0.5 - gap, yy - size * 0.36), -1.0, grow, fade)
			_thorn_wing(Vector2(vp.x * 0.5 + gap, yy - size * 0.36), 1.0, grow, fade)
			for o in [Vector2(-3, 0), Vector2(3, 0), Vector2(0, -3), Vector2(0, 3)]:
				_say(Vector2(vp.x * 0.5, yy) + o, c.text, _brush, size, Color(VIOLET, 0.22 * fade), spacing, HORIZONTAL_ALIGNMENT_CENTER)
		_say(Vector2(vp.x * 0.5, yy), c.text, _brush, size, col, spacing, HORIZONTAL_ALIGNMENT_CENTER, 3.0, 5)
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
	# 分隔线：两段细线，中间一点紫光（用户不要菱形）
	var open_k := clampf(_banner_t / 0.4, 0.0, 1.0)
	var half := lerpf(24.0, 150.0, 1.0 - pow(1.0 - open_k, 3.0))
	draw_line(Vector2(vp.x * 0.5 - half, mid + 24), Vector2(vp.x * 0.5 - 12, mid + 24), Color(RULE, a), 1.0)
	draw_line(Vector2(vp.x * 0.5 + 12, mid + 24), Vector2(vp.x * 0.5 + half, mid + 24), Color(RULE, a), 1.0)
	draw_circle(Vector2(vp.x * 0.5, mid + 24), 5.0, Color(VIOLET, 0.3 * a))
	draw_circle(Vector2(vp.x * 0.5, mid + 24), 2.0, Color(VIOLET_LIGHT, a))
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
