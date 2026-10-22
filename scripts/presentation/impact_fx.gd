extends Node2D
## 战斗特效“配方”（第四轮 · 角色特效重做）。
## 图形全部交给 pixel_fx.gd：半分辨率像素画布（1 格 = 2 屏幕像素，和背景像素块一样大），
## 硬边 + 抖动淡出，赛璐璐风，不做写实粒子。这里只决定：一次命中由哪些零件组成、多大、什么颜色。
## 尺寸都按“屏幕像素”写，_w() 换算成世界单位（镜头 zoom 0.5 时 1 屏幕像素 = 2 世界单位）。
##
## 颜色分工（一眼分得清是谁打谁）：
##   主角打中 —— 白芯 + 金黄火花 + 紫色斩线（主角的颜色）
##   主角挨打 —— 白芯 + 橙红
##   弹刀 / 格挡 —— 白芯 + 淡钢蓝，金属火星（暖色、会落地弹跳）
##   撞墙 / 下砸 / 炸弹 —— 暖橙冲击波 + 石屑 + 尘土
##   尘土 —— 月光下的石板灰（右上受光）
const Feel := preload("res://scripts/core/feel_scale.gd")
const PixelFx := preload("res://scripts/presentation/pixel_fx.gd")
const DITHER := preload("res://assets/shaders/fx_dither.gdshader")
const GHOST := preload("res://assets/shaders/fx_ghost.gdshader")
const GLOW := preload("res://assets/shaders/fx_glow_sprite.gdshader")
const K := PixelFx.K

const WHITE := Color("fffcf2")
const GOLD := Color("ffe486")
const AMBER := Color("ffac4a")
const EMBER := Color("e8622c")
const VIO_L := Color("ddd2ff")
const VIO := Color("a487ff")
const VIO_D := Color("6a4fe0")
const STEEL_L := Color("eaf5ff")
const STEEL := Color("a9d3f5")
const INK := Color("1b1526")
const INK_RIM := Color("ff9a3c")
const DUST_L := Color("a3adc2")
const DUST := Color("737e97")
const DUST_D := Color("4b546c")
const STONE_L := Color("aeb8ca")
const STONE := Color("737e97")
const STONE_D := Color("464e65")
const WARM_L := Color("ffe2ad")
const WARM := Color("ffb25a")
const HURT := Color("ff5a48")
const SMOKE_L := Color("5f6378")
const SMOKE := Color("3b3d4e")

var enabled: bool = true
var damage_numbers_enabled: bool = true
var max_effects: int = 64            ## 同时最多几个伤害数字
var last_hit_plan: Array[Dictionary] = []
var last_kind: String = ""
var last_hit_variant: int = 0   ## 上一次命中用了第几种随机变体（测试 / 样片用）
var debug_variant: int = -1     ## ≥0 时强制用这一种变体（样片 REEL=hits 用）
var text_sequence: int = 0
var font: SystemFont
## 伤害数字的放大倍数（试玩关卡镜头缩到 0.5 时，数字放大 2 倍保持看得清）
var text_scale: float = 1.0
## 特效整体再放大多少（1 = 按下面写的屏幕像素）
var fx_scale: float = 1.0
## 地面高度查询 (x, y) -> 地面 y；火花、碎块落地会弹一下。没设就不弹。
var floor_at: Callable

var pfx: PixelFx
var ghosts: Node2D
var _ghost_mat: ShaderMaterial
var _ghost_list: Array = []           ## [Sprite2D, age, life, 起始不透明度]
var _ghost_src: Sprite2D
var _ghost_left: float = 0.0
var _ghost_tint := VIO_L
var _ghost_spacing: float = 16.0      ## 残影间距（屏幕像素）：按“走了多远”留，不按时间（起步没动时不会叠成一坨）
var _ghost_last := Vector2.INF
var _ghost_total: float = 0.3
var _dash_from := Vector2.INF        ## 这次冲刺斩起步的位置（“一闪”从这里画到命中点）
var _dash_slit: PixelFx.Fx
var _player: Node2D
var _charge_ready_shown: bool = false
var _charge_pulse: float = 0.0
var _step_dist: float = 0.0
var _last_feet := Vector2.INF
var _dissolving: Array = []
var rng := RandomNumberGenerator.new()
var _frame_seen := {}
## 刀光辉光（§16.10）：跟着主角精灵的“影子精灵”，只让帧里亮紫的刀光发光
var glow_base: float = 0.55
var _glow_src: Sprite2D
var _glow: Sprite2D
var _glow_mat: ShaderMaterial
var _glow_pulse: float = 0.0
## 大招起手“刀身点亮”（§16.11，ult_fx.gd 每帧写）：刀柄 xy → 刀尖 zw（贴图像素）、点亮到哪（0..1）、额外亮度
var blade_seg := Vector4.ZERO
var blade_sweep: float = 0.0
var blade_boost: float = 0.0
## 重击冲击帧（§16.10）：打中那一下背景压暗、角色和特效亮着，停一下再退
var impact_frames_enabled: bool = true
var _impact: Node2D
var _impact_a: float = 0.0
var _impact_hold: float = 0.0
var _impact_fade: float = 0.18
var _impact_peak: float = 0.0


func _ready() -> void:
	z_index = 20
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC"])
	pfx = PixelFx.new()
	add_child(pfx)
	_impact = Node2D.new()
	_impact.top_level = true
	_impact.z_as_relative = false
	_impact.z_index = -1                 # 和大招压暗一样：地形 −70 之上、角色 0 之下
	_impact.visible = false
	add_child(_impact)
	_impact.draw.connect(_draw_impact)
	ghosts = Node2D.new()
	ghosts.z_as_relative = false
	ghosts.z_index = -1                  # 残影在角色身后、地形前面
	add_child(ghosts)
	_ghost_mat = ShaderMaterial.new()
	_ghost_mat.shader = GHOST
	rng.randomize()


## 一招的“打击力度”0..1：按伤害算（轻击 8 → 0.1，第三刀 18 → 0.6，蓄力斩 26 → 1）
static func power_of(mv: Resource) -> float:
	if mv == null:
		return 0.3
	var p := clampf((float(mv.damage) - 6.0) / 20.0, 0.0, 1.0)
	if bool(mv.forces_launch):
		p = maxf(p, 0.45)
	return p


## 场上还有多少特效（像素零件 + 残影 + 伤害数字）
func active_count() -> int:
	var n := pfx.count() + _ghost_list.size()
	for node in get_children():
		if node is Label:
			n += 1
	return n


# ---------------------------------------------------------------- 零件（尺寸都是屏幕像素）

func _w() -> float:
	return pfx.world_per_px() * fx_scale


func _r(a: float, b: float) -> float:
	return rng.randf_range(a, b)


func _floor(p: Vector2) -> float:
	if floor_at.is_valid():
		return float(floor_at.call(p.x, p.y))
	return INF


func _plan(name: String, delay: float, life: float) -> void:
	last_hit_plan.append({"name": name, "delay": delay, "life": life})


func _star(p: Vector2, r: float, ang: float, stretch: float, rim: Color, core: Color, life: float,
		delay: float = 0.0, core_k: float = 0.55, spin: float = 0.0) -> void:
	var f := pfx.add(K.STAR, p, life, delay)
	f.a = r * _w(); f.c = stretch; f.d = core_k; f.ang = ang; f.spin = spin
	f.c1 = rim; f.c0 = core


func _streak(p: Vector2, length: float, width: float, ang: float, rim: Color, core: Color, life: float,
		delay: float = 0.0, core_k: float = 0.42, vel := Vector2.ZERO) -> void:
	var w := _w()
	var f := pfx.add(K.STREAK, p, life, delay)
	f.a = length * w; f.b = width * w; f.c = core_k; f.ang = ang; f.vel = vel * w
	f.c1 = rim; f.c0 = core


func _ring(p: Vector2, r0: float, r1: float, th0: float, th1: float, col: Color, life: float,
		delay: float = 0.0, squash: float = 1.0, ang: float = 0.0) -> void:
	var w := _w()
	var f := pfx.add(K.RING, p, life, delay)
	f.a = r0 * w; f.b = r1 * w; f.c = th0 * w; f.d = th1 * w; f.squash = squash; f.ang = ang
	f.c1 = col
	# §16.11 断弧：2–4 段，长短、粗细、消失快慢都不一样，缺口也不均匀
	var n := rng.randi_range(2, 4)
	var cover := _r(0.5, 0.78) * TAU
	var ws: Array[float] = []
	var gs: Array[float] = []
	for i in n:
		ws.append(_r(0.4, 1.6))
		gs.append(_r(0.3, 1.7))
	var wsum: float = 0.0
	var gsum: float = 0.0
	for i in n:
		wsum += ws[i]
		gsum += gs[i]
	var a := _r(0.0, TAU)
	for i in n:
		var span := cover * ws[i] / wsum
		f.angs.append(a)
		f.lens.append(span)
		f.pts.append(Vector2(_r(0.6, 1.3), _r(0.2, 1.0)))
		a += span + (TAU - cover) * gs[i] / gsum


## 爆闪：n 根刺（±1 根随机），顺着 ang 方向的那半边长、背后短；总有一根特别长的往前戳，偶尔一根很短 —— 不对称
func _burst(p: Vector2, r: float, ang: float, n: int, rim: Color, core: Color, cool: Color, life: float,
		delay: float = 0.0) -> void:
	var f := pfx.add(K.BURST, p, life, delay)
	f.a = r * _w(); f.ang = ang
	f.c0 = core; f.c1 = rim; f.c2 = cool
	var m := maxi(n + rng.randi_range(-1, 1), 5)
	var front: Array[int] = []
	for i in m:
		var g := float(i) * TAU / float(m) + _r(-0.22, 0.22)
		f.angs.append(g)
		var c := cos(g)
		var l := _r(0.38, 0.68) + pow(maxf(c, 0.0), 2.0) * _r(0.4, 0.7) - maxf(-c, 0.0) * _r(0.05, 0.2)
		if rng.randf() < 0.2:
			l *= 0.55
		f.lens.append(maxf(l, 0.22))
		if c > 0.35:
			front.append(i)
	if not front.is_empty():
		f.lens[front[rng.randi() % front.size()]] = _r(1.25, 1.5)


func _disc(p: Vector2, r: float, col: Color, life: float, delay: float = 0.0) -> void:
	var f := pfx.add(K.DISC, p, life, delay)
	f.a = r * _w(); f.c1 = col


## 一把火花：ang 中心方向，spread 半张角；cols = [刚出来, 中段, 快灭]
func _sparks(p: Vector2, n: int, ang: float, spread: float, v0: float, v1: float, life0: float, life1: float,
		cols: Array, grav: float = 800.0, width: float = 2.0, bounce: bool = false, delay: float = 0.0,
		tail: float = 0.024, drag: float = 4.0) -> void:
	var w := _w()
	var fy := _floor(p) if bounce else INF
	for i in n:
		var f := pfx.add(K.SPARK, p, _r(life0, life1), delay + _r(0.0, 0.02))
		f.vel = Vector2.from_angle(ang + _r(-spread, spread)) * _r(v0, v1) * w
		# §16.11 大小不一（偶尔一颗大的）、拖尾长短不一、消失方式不一样（淡出 / 闪着灭 / 缩成点）
		var sz := rng.randf()
		var wk := 0.6 if sz < 0.3 else (1.0 if sz < 0.75 else (1.5 if sz < 0.93 else 2.2))
		f.grav = grav * w; f.drag = drag; f.b = width * w * wk; f.d = tail * _r(0.6, 1.5); f.floor_y = fy
		var mr := rng.randf()
		f.mode = 0 if mr < 0.5 else (1 if mr < 0.75 else 2)
		f.seed = float(rng.randi() % 2)
		f.c0 = cols[0]; f.c1 = cols[1]; f.c2 = cols[2]


## 碎块（石屑 / 影子碎片 / 玻璃渣）
func _chunks(p: Vector2, n: int, ang: float, spread: float, v0: float, v1: float, s0: float, s1: float,
		cols: Array, grav: float = 1200.0, life0: float = 0.4, life1: float = 0.7, bounce: bool = true,
		lit: bool = false) -> void:
	var w := _w()
	var fy := _floor(p) if bounce else INF
	for i in n:
		var f := pfx.add(K.CHUNK, p + Vector2(_r(-4, 4), _r(-4, 4)) * w, _r(life0, life1), 0.0)
		f.vel = Vector2.from_angle(ang + _r(-spread, spread)) * _r(v0, v1) * w
		f.grav = grav * w; f.drag = 1.0; f.floor_y = fy
		f.a = _r(s0, s1) * w; f.b = 1.0 if lit and f.a >= 5.0 * w else 0.0
		f.ang = _r(0, TAU); f.spin = _r(-14, 14)
		f.c1 = cols[rng.randi() % cols.size()]; f.c0 = WHITE


## 一团尘土：vel 屏幕像素/秒，r0 → r1 半径
func _puff(p: Vector2, vel: Vector2, r0: float, r1: float, life: float, delay: float = 0.0,
		cols: Array = [DUST_L, DUST, DUST_D], drag: float = 3.5) -> void:
	var w := _w()
	var f := pfx.add(K.PUFF, p, life, delay)
	f.vel = vel * w; f.drag = drag; f.a = r0 * w; f.b = r1 * w
	f.c0 = cols[0]; f.c1 = cols[1]; f.c2 = cols[2]


## 放射速度线。fwd 给了（有限值）= 只往前 fwd ± spread 那一片随机撒（§16.11 普通命中）；没给 = 一圈
func _lines(p: Vector2, n: int, r0: float, r1: float, width: float, length: float, col: Color, life: float,
		delay: float = 0.0, fwd: float = INF, spread: float = 0.9) -> void:
	var w := _w()
	var f := pfx.add(K.LINES, p, life, delay)
	f.a = r0 * w; f.b = r1 * w; f.c = width * w; f.d = length * w; f.c1 = col
	if is_finite(fwd):
		f.ang = fwd
		for i in maxi(n + rng.randi_range(-2, 2), 3):
			f.angs.append(_r(-spread, spread) * _r(0.3, 1.0))
			f.lens.append(_r(0.45, 1.25))
	else:
		f.ang = _r(0, TAU)
		for i in n:
			f.angs.append(float(i) * TAU / float(n) + _r(-0.18, 0.18))
			f.lens.append(_r(0.7, 1.15))


## 笔刷月牙（K.CRESCENT）：圆心 center，半径 r、最粗 b（屏幕像素），从角 c 扫到角 d。
## cols = [刃口白芯, 中段, 外层]；edge = 1 亮刃口在外缘 / −1 在内缘；hairs = 尾段几根刷毛；rough = 毛边有多毛
func _crescent(center: Vector2, r: float, b: float, c: float, d: float, life: float, delay: float = 0.0,
		cols: Array = [WHITE, VIO_L, VIO], s0: float = 0.16, s1: float = 0.45, edge: float = 1.0,
		hairs: int = 6, rough: float = 1.0) -> PixelFx.Fx:
	var w := _w()
	var f := pfx.add(K.CRESCENT, center, life, delay)
	f.a = r * w; f.b = b * w; f.c = c; f.d = d
	f.s0 = s0; f.s1 = s1; f.edge = edge; f.seed = _r(0.0, TAU)
	f.c0 = cols[0]; f.c1 = cols[1]; f.c2 = cols[2]
	var m := clampi(int(absf(d - c) * r / 14.0), 12, 96)
	for i in m:
		f.angs.append(_r(-1.0, 1.0))
		# 毛边：大多数地方小抖，隔几格冒出一撮长毛 / 缺一口
		var x := _r(-0.4, 0.5)
		if rng.randf() < 0.18:
			x = _r(0.6, 1.2) if rng.randf() < 0.7 else _r(-0.9, -0.6)
		f.lens.append(x * rough)
	for j in hairs:
		f.pts.append(Vector2(_r(0.35, 1.15), _r(0.8, 1.8)))
		var v0 := _r(-0.16, 0.12)
		f.pts.append(Vector2(v0, v0 + _r(0.18, 0.5)))
	return f


## 月牙在时刻 t（0..1）时刀头 / 尾巴的位置（弧上 0..1），和 _draw_crescent 一致
static func crescent_span(f: PixelFx.Fx, t: float) -> Vector2:
	var uh := 1.0 - pow(1.0 - minf(t / maxf(f.s0, 0.001), 1.0), 3.0)
	var er := clampf((t - f.s1) / maxf(1.0 - f.s1, 0.001), 0.0, 1.0)
	return Vector2(pow(er, 1.5) * uh, uh)


static func crescent_point(f: PixelFx.Fx, u: float, off: float = 0.0) -> Vector2:
	return f.pos + Vector2.from_angle(lerpf(f.c, f.d, u)) * (f.a + f.edge * off)


## 命中斩线（§16.11）：一道穿过 p、顺着 ang 方向扫的小月牙。length / width 屏幕像素；
## curve = 半径 / 长度（越大越直）；bend = 往哪边弯；mode = 消失方式（见 pixel_fx Fx.mode）
func _arc_cut(p: Vector2, ang: float, length: float, width: float, life: float, delay: float = 0.0,
		curve: float = 1.6, bend: float = 1.0, mode: int = 0, cols: Array = [WHITE, VIO_L, VIO], hairs: int = 2) -> PixelFx.Fx:
	var t := Vector2.from_angle(ang)
	var r := maxf(length * curve, 8.0)
	var cen := p + Vector2(-t.y, t.x) * bend * r * _w()
	var phi := (p - cen).angle()
	var s := length * 0.5 / r
	var f := _crescent(cen, r, width, phi - s * bend, phi + s * bend, life, delay, cols, 0.26, 0.42, 1.0, hairs, 0.8)
	f.mode = mode
	return f


# ---------------------------------------------------------------- 命中

## 主角打中敌人。strength = 力度 0..1（大招 1.6）；dir = 打击方向（没给就按 up 取上 / 右）
## 同一帧打中好几只：第一只给全套，后面的只给闪光 + 一道斩痕 + 少量火花，免得糊成一片
## slim = 冲刺斩：有“一闪”亮线顶着，不画白圈和放射线，爆闪也小一号
## style = 招式 id（§16.11）：每招斩痕形状不同，每招还有 3 种随机变体；没给就按 up / slim 猜
func spawn_hit(point: Vector2, strength: float, up: bool = false, dir := Vector2.ZERO, slim: bool = false,
		style: StringName = &"") -> void:
	last_kind = "hit"
	last_hit_plan.clear()
	if not enabled:
		return
	var main := _first_this_frame(&"hit")
	var p := clampf(strength, 0.0, 1.6)
	if dir.length_squared() < 0.01:
		dir = Vector2.UP if up else Vector2.RIGHT
	dir = dir.normalized()
	var side := 1.0 if dir.x >= 0.0 else -1.0
	var a := dir.angle()
	var k := 1.0 if main else 0.65
	if slim:
		k *= 0.7
	var fam := _hit_family(style, up, slim)
	var v := rng.randi() % 3 if debug_variant < 0 else debug_variant
	last_hit_variant = v
	var back := Vector2(-side, 0.0)
	var life := 0.13 + 0.05 * p
	var ln := (110.0 + 80.0 * p) * k
	var wd := (12.0 + 7.0 * p) * k
	var w := _w()
	var cut := a
	match fam:
		&"down":
			cut = a + side * _r(0.25, 0.55)
		&"rise":
			cut = a - side * _r(0.3, 0.6)
		&"steep":
			cut = a + side * _r(0.7, 1.05) * (-1.0 if v == 2 else 1.0)
		&"up":
			cut = -PI * 0.5 + _r(-0.22, 0.22)
			back = Vector2(-1.0 if rng.randf() < 0.5 else 1.0, 0.0)
		&"dash":
			cut = a + _r(-0.1, 0.1)
		&"heavy", &"charge":
			cut = a + side * _r(0.15, 0.5)
		_:
			cut = a + _r(-0.35, 0.35)
	var t := Vector2.from_angle(cut)
	var nrm := Vector2(-t.y, t.x)
	# ---- 闪光（§16.10 有了辉光以后金色爆闪收小一号）
	var star_r := (22.0 + 13.0 * p) * k
	if fam == &"ranged" or (fam == &"dash" and v == 1):
		star_r *= 0.75
	if main:
		_disc(point, (9.0 + 9.0 * p) * k, WHITE, 0.035)
	if fam == &"ranged" and v == 0:
		_star(point, star_r * 0.9, cut, 1.6, VIO_L, WHITE, 0.1)
	else:
		_burst(point, star_r, cut, (8 if p < 0.55 else 10) - (2 if fam == &"ranged" else 0), GOLD, WHITE, AMBER, 0.1 + 0.04 * p)
	_plan("flash", 0.0, 0.1 + 0.04 * p)
	# ---- 斩痕：一道道小月牙，消失方式随机
	match fam:
		&"down", &"rise", &"steep":
			_hit_arc(point, cut, ln, wd, life, 0.0, 1.4, back)
			if main and v == 1:
				_hit_arc(point - nrm * _bend(cut, back) * 13.0 * k * w, cut, ln * 0.6, wd * 0.45, life * 0.9, 0.03, 1.6, back)
			elif main and v == 2:
				var q := point + t * ln * 0.22 * w
				var g := cut + _r(0.3, 0.5) * (1.0 if rng.randf() < 0.5 else -1.0)
				_hit_arc(q + Vector2.from_angle(g) * ln * 0.18 * w, g, ln * 0.42, wd * 0.5, life * 0.85, 0.04, 1.2, back)
		&"heavy":
			if v == 0 or not main:
				_hit_arc(point, cut, ln * 1.3, wd * 1.2, life * 1.1, 0.0, 1.0, back)
				if main:
					var g := cut - side * _r(0.35, 0.55)
					_hit_arc(point + t * ln * 0.3 * w + Vector2.from_angle(g) * ln * 0.2 * w, g, ln * 0.5, wd * 0.55, life, 0.04, 1.3, back)
			elif v == 1:
				var g1 := cut - side * _r(0.45, 0.65)
				var g2 := cut + side * _r(0.45, 0.65)
				_hit_arc(point, g1, ln * 0.9, wd * 0.9, life, 0.0, 1.5, back)
				_hit_arc(point, g2, ln * 0.85, wd * 0.85, life, 0.035, 1.5, back)
			else:
				var bd := _bend(cut, back)
				var lk := [0.8, 1.0, 0.72]
				for i in 3:
					var o := float(i - 1) * 15.0 * k
					_hit_arc(point + nrm * bd * o * w + t * _r(-8, 8) * w, cut, ln * float(lk[i]), wd * 0.7, life,
						0.02 * float(i), 1.2, back)
		&"charge":
			_hit_arc(point, cut, ln * 1.5, wd * 1.35, life * 1.15, 0.0, 0.9, back)
			if main:
				if v == 0:
					_hit_arc(point - nrm * _bend(cut, back) * 18.0 * k * w, cut, ln * 0.7, wd * 0.5, life, 0.035, 1.1, back)
				elif v == 1:
					var g := cut - side * _r(0.9, 1.2)
					_hit_arc(point + t * 10.0 * w, g, ln * 0.85, wd * 0.8, life, 0.05, 1.4, back)
				else:
					var g := cut + _r(0.3, 0.45) * (1.0 if rng.randf() < 0.5 else -1.0)
					_hit_arc(point + t * ln * 0.3 * w + Vector2.from_angle(g) * ln * 0.3 * w, g, ln * 0.75, wd * 0.6, life, 0.04, 1.2, back)
					_ring(point, 10.0, 44.0 + 20.0 * p, 7.0, 0.0, VIO_L, 0.14, 0.05)
		&"up":
			if v == 1 and main:
				for sgn: float in [-1.0, 1.0]:
					var g := cut + sgn * _r(0.28, 0.42)
					_hit_arc(point + Vector2.from_angle(g) * ln * 0.38 * w, g, ln * 0.85, wd * 0.85, life, 0.0 if sgn < 0.0 else 0.03,
						1.6, Vector2(sgn, 0.0))
			else:
				_hit_arc(point, cut, ln * 1.15, wd, life, 0.0, 1.3, back)
				if v == 2 and main:
					var g := cut + _r(0.35, 0.5) * (1.0 if rng.randf() < 0.5 else -1.0)
					_hit_arc(point + t * ln * 0.25 * w + Vector2.from_angle(g) * ln * 0.18 * w, g, ln * 0.45, wd * 0.5, life, 0.04, 1.2, back)
		&"dash":
			if v == 0:
				_hit_arc(point, cut - 0.42, ln * 1.1, wd * 0.5, life, 0.0, 2.2, back)
				_hit_arc(point, cut + 0.42, ln * 1.05, wd * 0.5, life, 0.025, 2.2, back)
			elif v == 2:
				for sgn: float in [-1.0, 1.0]:
					_hit_arc(point + t * sgn * ln * 0.2 * w + nrm * sgn * 8.0 * w, cut + sgn * 0.5, ln * 0.45, wd * 0.6, life,
						0.0 if sgn < 0.0 else 0.03, 0.6, back)
			else:
				_hit_arc(point, cut, ln * 1.4, wd * 0.3, life * 0.7, 0.0, 4.0, back)
		_:
			if v == 0:
				_hit_arc(point, cut, ln * 0.45, wd * 0.5, life * 0.8, 0.0, 1.4, back)
			elif v == 1:
				_arc_cut(point, cut, ln * 0.6, wd * 0.55, life, 0.0, 1.0, _bend(cut, back), 1)
			else:
				_hit_arc(point, cut, ln * 0.55, wd * 0.6, life, 0.0, 1.2, back)
	_plan("cut", 0.0, life)
	# ---- 火花 / 墨点
	var ns := (6 + int(8.0 * p)) if main else 3
	var spread := 0.75
	if fam == &"ranged":
		ns = maxi(ns - 2, 3) + (4 if v != 1 else 0)
		spread = 0.55
	elif fam == &"up":
		spread = 0.6
	_sparks(point, ns, a, spread, 260.0, 520.0 + 380.0 * p, 0.14, 0.26 + 0.1 * p, [WHITE, GOLD, AMBER], 700.0, 3.0 if p >= 0.5 else 2.0)
	_plan("spark", 0.0, 0.26 + 0.1 * p)
	_chunks(point, (3 + int(5.0 * p)) if main else 2, a, 1.0, 120.0, 280.0 + 180.0 * p, 2.0, 5.0, [INK, INK, INK_RIM], 1000.0, 0.3, 0.55)
	_plan("ink", 0.0, 0.55)
	if not main:
		return
	glow_hit(p)
	if p >= 0.6:
		impact_frame(p)
	# ---- 断环（2–4 段）+ 只往前撒的速度线
	if p >= 0.3 and not slim and fam != &"ranged":
		_ring(point, 10.0, 28.0 + 26.0 * p, 8.0 + 4.0 * p, 0.0, VIO_L, 0.1 + 0.03 * p)
	_plan("ring", 0.0, 0.1 + 0.03 * p)
	if p >= 0.55 and not slim:
		_lines(point, 9, 18.0, 72.0 + 36.0 * p, 4.0, 26.0, WHITE, 0.15, 0.0, a, 0.8 if fam != &"up" else 0.55)
		_plan("lines", 0.0, 0.15)
	if p >= 0.9 and not slim:
		_disc(point, 15.0 + 6.0 * p, WHITE, 0.05)
		_ring(point, 10.0, 40.0 + 26.0 * p, 8.0, 0.0, VIO_L, 0.16, 0.04)
	if up:
		for i in 3:
			_streak(point + Vector2(_r(-16, 16), _r(-10, 10)) * w, _r(40, 64), 4.0, -PI * 0.5, VIO_L, WHITE, 0.2,
				0.03 + 0.03 * float(i), 0.0, Vector2(0, -520))


## 招式 id → 斩痕家族
func _hit_family(style: StringName, up: bool, slim: bool) -> StringName:
	match style:
		&"light_1":
			return &"down"
		&"light_2":
			return &"rise"
		&"light_3", &"air_light_3":
			return &"heavy"
		&"charge_1":
			return &"charge"
		&"up_strike", &"air_up":
			return &"up"
		&"dash_slash", &"dash_slash_left":
			return &"dash"
		&"ranged_1":
			return &"ranged"
		&"air_light_1", &"air_light_2":
			return &"steep"
	if up:
		return &"up"
	if slim:
		return &"dash"
	return &"down" if rng.randf() < 0.5 else &"rise"


## 弧往哪边弯：圆心放在 back（身后）那一侧，看起来是从身后抡过来的；说不清时随机
func _bend(ang: float, back: Vector2) -> float:
	var t := Vector2.from_angle(ang)
	var d := Vector2(-t.y, t.x).dot(back)
	if absf(d) < 0.15:
		return 1.0 if rng.randf() < 0.5 else -1.0
	return signf(d)


## 命中斩痕：曲率小抖、消失方式随机
func _hit_arc(p: Vector2, ang: float, length: float, width: float, life: float, delay: float, curve: float,
		back: Vector2, cols: Array = [WHITE, VIO_L, VIO]) -> void:
	_arc_cut(p, ang, length, width, life, delay, curve * _r(0.85, 1.2), _bend(ang, back), rng.randi() % 3, cols)


## 同一物理帧里第一次出这种特效吗（多目标同时命中时减量）
func _first_this_frame(kind: StringName) -> bool:
	var f := Engine.get_physics_frames()
	if _frame_seen.get(kind, -1) == f:
		return false
	_frame_seen[kind] = f
	return true


## 主角挨打（敌人颜色：橙红）
func spawn_hurt(point: Vector2, dir := Vector2.ZERO, heavy: bool = false) -> void:
	last_kind = "hurt"
	if not enabled:
		return
	if dir.length_squared() < 0.01:
		dir = Vector2.LEFT
	var a := dir.normalized().angle()
	var k := 1.35 if heavy else 1.0
	_burst(point, 22.0 * k, a + 0.5, 7, HURT, WHITE, EMBER, 0.11)
	_sparks(point, int(7 * k), a, 0.9, 200.0, 460.0 * k, 0.12, 0.26, [WHITE, AMBER, HURT], 800.0, 2.0)
	_ring(point, 4.0, 26.0 * k, 7, 0.0, HURT, 0.18)


## 弹刀：最爽的一下 —— 白爆闪 + 一道横向的长“镲”光 + 一大把会落地弹跳的金属火星（不用同心圆，免得像准星）
func spawn_parry(point: Vector2, dir: Vector2) -> void:
	last_kind = "parry"
	if not enabled:
		return
	if dir.length_squared() < 0.01:
		dir = Vector2.RIGHT
	var a := dir.normalized().angle()
	var side := 1.0 if dir.x >= 0.0 else -1.0
	_disc(point, 16.0, WHITE, 0.05)
	_burst(point, 40.0, _r(0.2, 0.5), 12, STEEL_L, WHITE, STEEL, 0.15)
	_streak(point, 230.0, 9.0, _r(-0.08, 0.08), STEEL, WHITE, 0.2, 0.0, 0.45)
	_streak(point, 90.0, 6.0, PI * 0.5 + _r(-0.15, 0.15), STEEL, WHITE, 0.13, 0.0, 0.45)
	_ring(point, 12.0, 58.0, 14.0, 0.0, STEEL_L, 0.16)
	_sparks(point, 18, a - 0.35 * side, 1.25, 320.0, 820.0, 0.28, 0.55, [WHITE, GOLD, AMBER], 1500.0, 3.0, true)
	_sparks(point, 6, a + PI, 0.9, 200.0, 420.0, 0.2, 0.35, [WHITE, GOLD, AMBER], 1500.0, 2.0, true)
	_burst(point + Vector2(side * 10.0, -10.0) * _w(), 12.0, 0.0, 4, WHITE, WHITE, GOLD, 0.16, 0.12)


## 刀砍在敌人的格挡上（或者主角举刀挡住）：小一号的金属碰撞，火星往回弹
func spawn_block(point: Vector2, dir: Vector2) -> void:
	last_kind = "block"
	if not enabled:
		return
	if dir.length_squared() < 0.01:
		dir = Vector2.RIGHT
	var back := (-dir.normalized()).angle()
	_burst(point, 24.0, _r(0.0, 0.6), 8, STEEL, WHITE, STEEL, 0.1)
	_streak(point, 110.0, 6.0, _r(-0.1, 0.1), STEEL, WHITE, 0.13, 0.0, 0.45)
	_sparks(point, 8, back - 0.3, 0.9, 240.0, 560.0, 0.2, 0.38, [WHITE, GOLD, AMBER], 1400.0, 2.0, true)


## 破防 / 眩晕：金色闪 + 一圈碎玻璃一样的格挡碎片
func spawn_break(point: Vector2) -> void:
	last_kind = "break"
	if not enabled or not _first_this_frame(&"break"):
		return
	_burst(point, 32.0, _r(-0.4, 0.4), 10, GOLD, WHITE, AMBER, 0.13)
	_ring(point, 6.0, 46.0, 10.5, 0.0, GOLD, 0.24)
	_chunks(point, 9, -PI * 0.5, 2.4, 160.0, 420.0, 3.0, 6.0, [STEEL_L, STEEL, WHITE], 1300.0, 0.45, 0.7, true)


## 打回去的箭 / 炸弹
func spawn_deflect(point: Vector2, dir: Vector2) -> void:
	spawn_block(point, -dir)
	last_kind = "deflect"
	_star(point, 20.0, dir.angle(), 2.0, GOLD, WHITE, 0.1)


## 撞墙：dir = 撞向墙的方向
func spawn_wall_slam(point: Vector2, dir: Vector2, strength: float) -> void:
	last_kind = "wall"
	if not enabled:
		return
	if dir.length_squared() < 0.01:
		dir = Vector2.RIGHT
	dir = dir.normalized()
	if dir.y > 0.8:
		spawn_ground_slam(point, strength)
		last_kind = "wall"
		return
	var s := clampf(strength, 0.2, 1.3)
	var n := -dir
	var along := dir.angle() + PI * 0.5
	_star(point, 14.0 + 12.0 * s, along, 1.8, WARM, WHITE, 0.1)
	_ring(point, 6.0, 36.0 + 30.0 * s, 10.5, 0.0, WARM_L, 0.26, 0.0, 0.4, along)
	_chunks(point, 5 + int(8.0 * s), n.angle(), 1.1, 140.0, 320.0 + 260.0 * s, 3.0, 7.0, [STONE_L, STONE, STONE_D], 1300.0, 0.5, 0.9, true, true)
	_sparks(point, 4 + int(4.0 * s), n.angle(), 0.9, 200.0, 480.0, 0.15, 0.3, [WHITE, WARM, EMBER], 900.0)
	var w := _w()
	var perp := Vector2(-dir.y, dir.x)
	for i in 2 + int(3.0 * s):
		_puff(point + perp * _r(-20, 20) * w, n * _r(40, 120) + Vector2(0, -20), 5.0, 12.0 + 8.0 * s, _r(0.4, 0.6), _r(0.0, 0.05))


## 下砸 / 重重砸在地上：贴地的扁冲击环 + 石屑往上崩 + 两边滚出去的尘土 + 地裂
func spawn_ground_slam(point: Vector2, strength: float = 1.0) -> void:
	last_kind = "slam"
	if not enabled:
		return
	var s := clampf(strength, 0.3, 1.5)
	var w := _w()
	_star(point, 20.0 + 6.0 * s, 0.0, 2.4, WARM, WHITE, 0.12)
	_ring(point, 10.0, 80.0 + 40.0 * s, 14, 0.0, WARM_L, 0.3, 0.0, 0.26)
	_ring(point, 6.0, 56.0, 7, 0.0, WHITE, 0.22, 0.05, 0.26)
	_chunks(point, 8 + int(8.0 * s), -PI * 0.5, 1.3, 220.0, 560.0, 3.0, 7.0, [STONE_L, STONE, STONE_D], 1400.0, 0.6, 1.0, true, true)
	for side in [-1.0, 1.0]:
		for i in 3:
			_puff(point + Vector2(side * _r(4, 18), _r(-6, 0)) * w, Vector2(side * _r(90, 220), _r(-40, -10)),
				6.0, 15.0 + 8.0 * s, _r(0.45, 0.7), 0.02 * float(i))
		_crack(point, side, s)


func _crack(point: Vector2, side: float, s: float) -> void:
	var w := _w()
	var f := pfx.add(K.CRACK, point, 0.9)
	f.a = 2.0 * w; f.b = 2.0 * w; f.c1 = Color("232838"); f.c0 = STONE_L
	var q := point + Vector2(0, 2.0 * w)
	f.pts.append(q)
	for i in 5:
		q += Vector2(side * _r(8, 16) * (1.0 + 0.3 * s), _r(-3, 3)) * w
		f.pts.append(q)


## 炸弹爆炸
func spawn_explosion(point: Vector2, strength: float = 1.0) -> void:
	last_kind = "bomb"
	if not enabled:
		return
	var s := clampf(strength, 0.5, 1.5)
	var w := _w()
	_disc(point, 22.0 * s, WARM_L, 0.06)
	_disc(point, 14.0 * s, WHITE, 0.04, 0.02)
	_star(point, 28.0 * s, _r(0, 1), 1.2, WARM, WHITE, 0.12)
	_ring(point, 8.0, 70.0 * s, 14, 0.0, WARM, 0.28)
	for i in 6:
		var u := Vector2.from_angle(_r(0, TAU))
		_puff(point + u * _r(2, 10) * w, u * _r(60, 160), 8.0, 18.0 * s, _r(0.25, 0.4), 0.0, [WARM_L, WARM, EMBER])
	for i in 6:
		var u := Vector2.from_angle(_r(0, TAU))
		_puff(point + u * _r(4, 14) * w, u * _r(30, 80) + Vector2(0, -40), 8.0, 22.0 * s, _r(0.6, 0.9), 0.08, [SMOKE_L, SMOKE, INK])
	_sparks(point, 10, -PI * 0.5, 1.4, 200.0, 520.0, 0.4, 0.8, [GOLD, AMBER, EMBER], 600.0, 2.0, true)
	_chunks(point, 6, -PI * 0.5, 1.2, 200.0, 460.0, 3.0, 6.0, [STONE_L, STONE, STONE_D], 1300.0, 0.6, 0.9, true, true)


## 敌人被挑飞：几道往上冲的速度线
func spawn_launch(point: Vector2) -> void:
	if not enabled:
		return
	var w := _w()
	for i in 4:
		_streak(point + Vector2(_r(-24, 24), _r(-20, 20)) * w, _r(40, 70), _r(3, 4), -PI * 0.5, VIO_L, WHITE, 0.22,
			0.02 * float(i), 0.0, Vector2(0, -640))


## 击杀：一圈白环 + 放射线（终结那一下要读得出来）
func spawn_kill(point: Vector2) -> void:
	if not enabled or not _first_this_frame(&"kill"):
		return
	_disc(point, 18.0, WHITE, 0.05)
	_burst(point, 34.0, _r(0, 1), 10, VIO_L, WHITE, VIO, 0.14)
	_lines(point, 12, 20.0, 110.0, 5.0, 34.0, WHITE, 0.18)


## 远射出手：枪口小闪
func spawn_muzzle(point: Vector2, dir: Vector2) -> void:
	if not enabled:
		return
	_star(point, 9.0, dir.angle(), 2.2, VIO, WHITE, 0.07)
	_sparks(point, 4, dir.angle(), 0.35, 160.0, 360.0, 0.08, 0.15, [WHITE, VIO_L, VIO], 0.0, 2.0)


# ---------------------------------------------------------------- 尘土

## 通用的一小团尘土（敌人出现、翻滚……）
func spawn_dust(point: Vector2, strength: float = 0.45) -> void:
	if not enabled:
		return
	var s := clampf(strength, 0.2, 1.5)
	var w := _w()
	for i in 2 + int(3.0 * s):
		var side := -1.0 if i % 2 == 0 else 1.0
		_puff(point + Vector2(_r(-8, 8), _r(-4, 0)) * w, Vector2(side * _r(40, 110), _r(-50, -20)), 4.0, 9.0 + 8.0 * s,
			_r(0.35, 0.55), _r(0.0, 0.04))


## 落地：两边各滚出几团；重落地再加一圈贴地的环和小石子
func spawn_land(point: Vector2, heavy: bool = false) -> void:
	if not enabled:
		return
	var w := _w()
	var n := 3 if heavy else 2
	for side in [-1.0, 1.0]:
		for i in n:
			_puff(point + Vector2(side * _r(4, 14), _r(-4, 0)) * w, Vector2(side * _r(70, 150 if not heavy else 210), _r(-28, -10)),
				4.0 if not heavy else 6.0, 10.0 if not heavy else 16.0, _r(0.32, 0.48), 0.02 * float(i))
	if heavy:
		_ring(point, 8.0, 56.0, 7, 0.0, DUST_L, 0.25, 0.0, 0.25)
		_chunks(point, 4, -PI * 0.5, 1.0, 120.0, 260.0, 2.0, 4.0, [STONE_L, STONE, STONE_D], 1300.0, 0.4, 0.6, true)


## 起跳 / 二段跳（二段跳脚下踩出一圈淡紫的气环）
func spawn_jump(point: Vector2, is_double: bool = false) -> void:
	if not enabled:
		return
	var w := _w()
	if is_double:
		_ring(point, 8.0, 44.0, 12.0, 0.0, VIO_L, 0.2, 0.0, 0.35)
		_ring(point, 4.0, 26.0, 7.0, 0.0, WHITE, 0.15, 0.03, 0.35)
		for side in [-1.0, 1.0]:
			_streak(point + Vector2(side * 14.0, 4.0) * w, 34.0, 4.0, PI * 0.5 - side * 0.5, VIO_L, WHITE, 0.16, 0.0, 0.4,
				Vector2(side * 160.0, 260.0))
		_sparks(point, 5, PI * 0.5, 1.3, 60.0, 160.0, 0.18, 0.3, [WHITE, VIO_L, VIO], -100.0, 2.0)
	else:
		for side in [-1.0, 1.0]:
			_puff(point + Vector2(side * 6.0, -2.0) * w, Vector2(side * _r(30, 70), _r(-20, -8)), 3.0, 8.0, _r(0.28, 0.36))


## 冲刺起步：身后踢起尘土 + 几道横向速度线
func spawn_dash(point: Vector2, facing: int) -> void:
	if not enabled:
		return
	var w := _w()
	var back := -float(facing)
	# 尘土帧里已经烘焙了（浅灰蓝），这里只补一小团贴地的，免得抖动点糊成一片
	_puff(point + Vector2(back * 6.0, -2.0) * w, Vector2(back * 90.0, -10.0), 3.0, 8.0, 0.3)
	for i in 4:
		var h := _r(16, 70)
		_streak(point + Vector2(back * _r(0, 30), -h) * w, _r(40, 72), 2.0, 0.0, VIO_L, WHITE, _r(0.16, 0.24),
			_r(0.0, 0.08), 0.0, Vector2(back * 420.0, 0))


## 冲刺斩起步：记下起点（命中时“一闪”从这里画起）
func mark_dash_start(point: Vector2) -> void:
	_dash_from = point
	_dash_slit = null


## 冲刺斩命中“一闪”：沿冲刺路径一道细长亮线（白芯紫边），整条停 2 帧，再从尾端往刀尖收细消失；
## 上下各一根细速度线往前滑，线上崩出几粒紫色碎光。一次冲刺打中好几个：同一条线往前接长、重新亮一下。
func spawn_dash_hit(point: Vector2, facing: int) -> void:
	if not enabled:
		return
	var w := _w()
	var f := float(facing)
	var x0 := _dash_from.x if _dash_from != Vector2.INF else point.x - f * 150.0 * w
	var x1 := point.x + f * 70.0 * w
	if _dash_slit != null and pfx.items.has(_dash_slit):
		var old_tail := _dash_slit.pos.x - f * _dash_slit.a * 0.5
		x0 = old_tail
		x1 = point.x + f * 70.0 * w if f * (point.x - _dash_slit.pos.x) > 0.0 else _dash_slit.pos.x + f * _dash_slit.a * 0.5
	var length := clampf(absf(x1 - x0), 110.0 * w, 560.0 * w)
	x0 = x1 - f * length
	var center := Vector2((x0 + x1) * 0.5, point.y)
	var sl: PixelFx.Fx = _dash_slit if (_dash_slit != null and pfx.items.has(_dash_slit)) else pfx.add(K.SLIT, center, 0.3)
	sl.pos = center; sl.age = 0.0; sl.delay = 0.0
	sl.a = length; sl.b = 6.0 * w; sl.c = 0.12; sl.ang = 0.0 if facing > 0 else PI
	sl.c0 = WHITE; sl.c1 = VIO_L; sl.c2 = VIO
	_dash_slit = sl
	_plan("dash_slit", 0.0, 0.3)
	for k in [-1.0, 1.0]:
		_streak(center + Vector2(f * length * 0.12, k * _r(9, 13)) * Vector2(1.0, w), length * 0.55 / w, 2.0, sl.ang,
			VIO, VIO_L, _r(0.18, 0.24), 0.03, 0.0, Vector2(f * 260.0, 0))
	for i in 6:
		var q := Vector2(lerpf(x0, x1, _r(0.25, 1.0)), point.y + _r(-3, 3) * w)
		var sp := pfx.add(K.SPARK, q, _r(0.18, 0.3), _r(0.02, 0.08))
		sp.vel = Vector2(f * _r(40, 140), _r(-70, -20)) * w
		sp.drag = 3.0; sp.grav = 220.0 * w
		sp.b = 2.0 * w; sp.d = 0.02; sp.c0 = WHITE; sp.c1 = VIO_L; sp.c2 = VIO


## 跑步脚步扬起的一点点灰
func spawn_step(point: Vector2, facing: int) -> void:
	if not enabled:
		return
	_puff(point + Vector2(-float(facing) * 6.0, -1.0) * _w(), Vector2(-float(facing) * _r(20, 50), _r(-18, -6)), 2.0, 6.0, _r(0.22, 0.3))


# ---------------------------------------------------------------- 残影 / 蓄力 / 消散（需要每帧跟着角色）

## 冲刺斩等：seconds 秒内，身体每走 spacing 个屏幕像素留一个残影。
## 第四轮 v2：只取身体轮廓（帧里烘焙的刀光 / 尘土不算），平滑半透明 + 外圈亮边（fx_ghost.gdshader），
## 浅紫 → 深紫渐隐；越晚留下的越淡，5～7 个就够，多了会糊成一团。
func start_ghosts(src: Sprite2D, seconds: float = 0.45, spacing: float = 16.0, tint := VIO_L) -> void:
	if not enabled or src == null:
		return
	_ghost_src = src
	_ghost_left = seconds
	_ghost_total = seconds
	_ghost_spacing = spacing
	_ghost_tint = tint
	_ghost_last = src.global_position
	_emit_ghost()


func _emit_ghost(at := Vector2.INF) -> void:
	if not is_instance_valid(_ghost_src) or not _ghost_src.visible or _ghost_src.texture == null:
		return
	var g := Sprite2D.new()
	g.texture = _ghost_src.texture
	g.centered = _ghost_src.centered
	g.offset = _ghost_src.offset
	g.region_enabled = _ghost_src.region_enabled
	g.region_rect = _ghost_src.region_rect
	g.flip_h = _ghost_src.flip_h
	g.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	g.material = _ghost_mat
	ghosts.add_child(g)
	g.global_transform = _ghost_src.global_transform
	if at != Vector2.INF:
		g.global_position = at
	_ghost_last = g.global_position
	# 亮边约 1.5 个屏幕像素：换算成贴图像素
	var spp := _ghost_src.get_global_transform_with_canvas().get_scale().x
	_ghost_mat.set_shader_parameter("rim", clampf(1.5 / maxf(absf(spp), 0.01), 1.0, 12.0))
	# 冲刺越往后留下的残影越淡（第一个最实）
	var k := 1.0 - clampf(1.0 - _ghost_left / maxf(_ghost_total, 0.01), 0.0, 1.0) * 0.45
	var a0 := 0.85 * k
	g.modulate = Color(_ghost_tint, a0)
	_ghost_list.append([g, 0.0, 0.32, a0])


## 刀光辉光：给主角精灵挂一张相加混合的“影子精灵”（子节点，跟着走、跟着翻）
func track_glow(src: Sprite2D) -> void:
	if src == null:
		return
	_glow_src = src
	if _glow == null or not is_instance_valid(_glow):
		_glow = Sprite2D.new()
		_glow.name = "BladeGlow"
		_glow_mat = ShaderMaterial.new()
		_glow_mat.shader = GLOW
		_glow.material = _glow_mat
		_glow.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		_glow.region_enabled = true
		_glow.region_filter_clip_enabled = false
	if _glow.get_parent() != src:
		if _glow.get_parent() != null:
			_glow.get_parent().remove_child(_glow)
		src.add_child(_glow)
	_sync_glow()


## 打中时刀光亮一下（力度越大越亮）
func glow_hit(p: float) -> void:
	_glow_pulse = maxf(_glow_pulse, 0.45 + 0.45 * clampf(p, 0.0, 1.0))


func _sync_glow() -> void:
	if _glow == null or not is_instance_valid(_glow) or not is_instance_valid(_glow_src):
		return
	var src := _glow_src
	var on := enabled and src.visible and src.texture != null
	_glow.visible = on
	if not on:
		return
	var tex := src.texture
	var tsize := tex.get_size()
	var rect := src.region_rect if src.region_enabled else Rect2(Vector2.ZERO, tsize)
	# 光晕约 7 个屏幕像素：换算成贴图像素；四周多留一圈给光晕
	var spp := absf(src.get_global_transform_with_canvas().get_scale().x)
	var radius := clampf(7.0 / maxf(spp, 0.01), 4.0, 64.0)
	var pad := ceilf(radius + 2.0)
	_glow.texture = tex
	_glow.centered = src.centered
	_glow.flip_h = src.flip_h
	_glow.flip_v = src.flip_v
	_glow.region_rect = rect.grow(pad)
	_glow.offset = src.offset - Vector2(pad, pad)
	_glow_mat.set_shader_parameter("radius", radius)
	_glow_mat.set_shader_parameter("bounds", Vector4(rect.position.x / tsize.x, rect.position.y / tsize.y,
		rect.end.x / tsize.x, rect.end.y / tsize.y))
	_glow_mat.set_shader_parameter("strength", glow_base + _glow_pulse)
	_glow_mat.set_shader_parameter("blade", blade_seg)
	_glow_mat.set_shader_parameter("sweep", blade_sweep)
	_glow_mat.set_shader_parameter("boost", blade_boost if blade_seg != Vector4.ZERO else 0.0)


## 重击冲击帧：背景压暗（角色、敌人、特效不压），停 hold 秒再淡回去。p ≥ 0.9（蓄力斩）更暗更久
func impact_frame(p: float) -> void:
	if not enabled or not impact_frames_enabled:
		return
	var a := 0.4 if p < 0.9 else 0.52
	if a < _impact_a:
		return
	_impact_peak = a
	_impact_a = a
	_impact_hold = 0.06 if p < 0.9 else 0.09
	_impact_fade = 0.16 if p < 0.9 else 0.22
	_impact.visible = true
	_impact.queue_redraw()


func impact_alpha() -> float:
	return _impact_a


func _tick_impact(delta: float) -> void:
	if _impact_a <= 0.0:
		return
	if _impact_hold > 0.0:
		_impact_hold -= delta
	else:
		_impact_a = maxf(_impact_a - _impact_peak * delta / maxf(_impact_fade, 0.01), 0.0)
	_impact.visible = _impact_a > 0.0
	_impact.queue_redraw()


func _draw_impact() -> void:
	if _impact_a <= 0.0 or not is_inside_tree():
		return
	var vp := get_viewport()
	var inv := vp.get_canvas_transform().affine_inverse()
	var r := inv * vp.get_visible_rect()
	_impact.draw_rect(r.grow(maxf(r.size.x, r.size.y) * 0.1), Color(0.015, 0.02, 0.04, _impact_a))


## 跟踪主角：蓄力聚气、跑步扬灰
func track_player(player: Node2D) -> void:
	_player = player


## 跟踪死掉的影：身体慢慢化成往上飘的黑烟和火星
func track_dissolve(s: Node2D) -> void:
	_dissolving.append(s)


func _process(delta: float) -> void:
	_tick_impact(delta)
	if _glow_pulse > 0.0:
		_glow_pulse = maxf(_glow_pulse - delta * 3.2, 0.0)
	_sync_glow()
	_tick_ghosts(delta)
	_tick_player(delta)
	_tick_dissolve()


func _tick_ghosts(delta: float) -> void:
	if _ghost_left > 0.0:
		_ghost_left -= delta
		# 一帧走得比间距远（冲刺很快）：在这段路上按间距补几个，残影才连成均匀的一串
		if is_instance_valid(_ghost_src):
			var gap := _ghost_spacing * _w()
			var to := _ghost_src.global_position
			var n := 0
			while _ghost_last.distance_to(to) >= gap and n < 4:
				var nxt := _ghost_last.move_toward(to, gap)
				_emit_ghost(nxt if nxt.distance_to(to) > 1.0 else Vector2.INF)
				n += 1
	var keep: Array = []
	for e in _ghost_list:
		var g: Sprite2D = e[0]
		e[1] += delta
		var t: float = e[1] / e[2]
		if t >= 1.0 or not is_instance_valid(g):
			if is_instance_valid(g):
				g.queue_free()
			continue
		# 浅紫 → 深紫，透明度先快后慢地淡掉（平滑，不碎成点）
		g.modulate = Color(_ghost_tint.lerp(VIO_D, minf(t * 1.25, 1.0)), float(e[3]) * pow(1.0 - t, 1.6))
		keep.append(e)
	_ghost_list = keep


func _tick_player(delta: float) -> void:
	if not enabled or not is_instance_valid(_player) or not _player.is_inside_tree():
		return
	var w := _w()
	var facing := float(_player.get("facing")) if _player.get("facing") != null else 1.0
	# 蓄力：四周的光丝往刀上聚，到“可以放”的那一刻刀上叮一下
	if _player.has_method("is_charging") and _player.is_charging():
		var cm: Resource = _player.get("charge_move")
		var cf: int = int(_player.get("charge_frames"))
		var cap := float(cm.max_charge_frames) if cm != null else 48.0
		var need := int(cm.min_charge_frames) if cm != null else 22
		var t := clampf(float(cf) / cap, 0.0, 1.0)
		var center := _player.global_position + Vector2(facing * 12.0, -4.0) * w
		var n := int(_r(0.0, 1.0) + (0.6 + 1.4 * t))
		for i in n:
			var u := Vector2.from_angle(_r(0, TAU))
			var dist := _r(56, 84)
			var f := pfx.add(K.SPARK, center + u * dist * w, 0.2)
			f.vel = -u * dist / 0.2 * w
			f.b = 2.0 * w; f.d = 0.03; f.c0 = VIO; f.c1 = VIO_L; f.c2 = WHITE
		_charge_pulse -= delta
		if _charge_pulse <= 0.0:
			_charge_pulse = 0.22 - 0.08 * t
			# 往里收的一圈光刺（不用细圆圈，免得像准星）
			_lines(center, 8, 70.0, 10.0, 4.0, 22.0, VIO_L if cf < need else WHITE, 0.2)
		if cf >= need and not _charge_ready_shown:
			_charge_ready_shown = true
			_disc(center, 10.0, WHITE, 0.05)
			_burst(center + Vector2(facing * 18.0, -14.0) * w, 22.0, 0.0, 4, VIO_L, WHITE, VIO, 0.22)
			_lines(center, 10, 16.0, 70.0, 4.0, 22.0, WHITE, 0.16)
	else:
		_charge_ready_shown = false
		_charge_pulse = 0.0
	# 跑步扬灰：在地上跑、速度够快，每跑一段距离踢一下
	var feet: Vector2 = _player.global_position + Vector2(0, float(_player.get("foot_offset")) if _player.get("foot_offset") != null else 0.0)
	var on_floor: bool = _player.has_method("is_on_floor") and _player.is_on_floor()
	var vx: float = (_player.get("velocity") as Vector2).x if _player.get("velocity") != null else 0.0
	if on_floor and absf(vx) > 160.0 and _last_feet != Vector2.INF:
		_step_dist += absf(feet.x - _last_feet.x)
		if _step_dist >= 120.0:
			_step_dist = 0.0
			spawn_step(feet, 1 if vx > 0.0 else -1)
	else:
		_step_dist = 60.0
	_last_feet = feet


func _tick_dissolve() -> void:
	if _dissolving.is_empty():
		return
	var keep: Array = []
	var w := _w()
	for s in _dissolving:
		if not is_instance_valid(s) or not s.is_inside_tree():
			continue
		var df: int = int(s.get("dead_frames"))
		if df > 75:
			continue
		keep.append(s)
		if df < 16 or not enabled:
			continue
		var hw: float = float(s.get("half_w"))
		var hh: float = float(s.get("half_h"))
		for i in 2:
			var p: Vector2 = s.global_position + Vector2(_r(-hw, hw) * 0.8, _r(-hh, hh) * 0.9)
			_puff(p, Vector2(_r(-14, 14), _r(-120, -60)), 3.0, _r(6, 10), _r(0.4, 0.6), 0.0, [SMOKE_L, SMOKE, INK], 2.0)
		if rng.randf() < 0.35:
			var q: Vector2 = s.global_position + Vector2(_r(-hw, hw), _r(-hh, hh) * 0.6)
			var f := pfx.add(K.SPARK, q, _r(0.4, 0.7))
			f.vel = Vector2(_r(-20, 20), _r(-160, -90)) * w
			f.drag = 1.5; f.b = 2.0 * w; f.d = 0.02
			f.c0 = GOLD; f.c1 = INK_RIM; f.c2 = EMBER
	_dissolving = keep


# ---------------------------------------------------------------- 伤害数字

func spawn_text(point: Vector2, text: String, amount: float = 0, wall: bool = false) -> void:
	if not damage_numbers_enabled:
		return
	var labels := 0
	for node in get_children():
		if node is Label:
			labels += 1
	if labels >= max_effects:
		return
	text_sequence += 1
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font",font)
	label.add_theme_font_size_override("font_size",int(clampf(18+amount*0.35,18,34)))
	label.add_theme_color_override("font_color",Color("ffc88f") if wall else Color("f4eaff"))
	label.add_theme_color_override("font_outline_color",Color("211b2d"))
	label.add_theme_constant_override("outline_size",3)
	label.z_index = 30
	add_child(label)
	label.scale = Vector2(text_scale,text_scale)
	label.global_position = point + Vector2(-10,-30-float(text_sequence%3)*15)*text_scale
	var tween := label.create_tween().set_parallel(true)
	tween.tween_property(label,"position:y",label.position.y-36*text_scale,0.65).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label,"modulate:a",0.0,0.42).set_delay(0.23)
	tween.chain().tween_callback(label.queue_free)


func clear() -> void:
	for node in get_children():
		if node is Label:
			remove_child(node)
			node.queue_free()
	for e in _ghost_list:
		if is_instance_valid(e[0]):
			e[0].queue_free()
	_ghost_list.clear()
	_ghost_left = 0.0
	_dissolving.clear()
	_glow_pulse = 0.0
	blade_boost = 0.0
	blade_seg = Vector4.ZERO
	_impact_a = 0.0
	_impact_hold = 0.0
	if _impact != null:
		_impact.visible = false
	pfx.clear()
	last_hit_plan.clear()
	last_kind = ""
	text_sequence = 0
