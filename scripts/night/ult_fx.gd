extends Node2D
## 大招「月下斩」的全屏表现（世界坐标，跟着镜头）。第四轮 §16.11，约 1 秒，分三段：
##   ① 起手 begin()（前 0.4 秒）：背景压暗；脚下风压把尘土往两边吹；紫色光丝绕着往刀上聚；光点往上飘；
##      刀身从刀柄往刀尖一路点亮（fx_glow_sprite 的 blade / sweep / boost），最后刀尖“叮”一颗十字星。
##   ② 出刀 slash()：先定格两帧黑白（纸白底 + 墨色剪影，fx_ult_ink）；一道笔刷月牙巨斩扫过全屏（白芯紫边、毛边、
##      两头尖），紧跟两道交叉细斩成 X；画面沿斩线错开几像素再合上（fx_ult_split）；全屏辉光亮一下。
##   ③ 余波（后 0.6 秒）：被砍中的影先定住、身上浮现斩痕，隔 0.1 秒一个接一个爆开（紫白碎光 + 墨点）；
##      地面沿斩线扬尘；斩线从尾巴碎成光点飘散；背景亮回来。
## 不显示字；镜头不动（只震屏）。特效零件都画进 impact_fx 的像素特效画布（同一套像素风 + 辉光）。
signal popped(target: Node2D, point: Vector2)   ## ③ 某只影爆开了（关卡据此出伤害数字、音效、小震屏）

const ImpactFX := preload("res://scripts/presentation/impact_fx.gd")
const PixelFx := preload("res://scripts/presentation/pixel_fx.gd")
const K := PixelFx.K
const INK_SHADER := preload("res://assets/shaders/fx_ult_ink.gdshader")
const SPLIT_SHADER := preload("res://assets/shaders/fx_ult_split.gdshader")
const VIEW := Vector2(2560.0, 1440.0)    ## 镜头 ZOOM 0.5 → 世界里一屏的大小
const WHITE := ImpactFX.WHITE
const VIO_L := ImpactFX.VIO_L
const VIO := ImpactFX.VIO
const VIO_D := ImpactFX.VIO_D
const INK := ImpactFX.INK
const PAPER := Color(0.95, 0.94, 0.98)   ## 黑白定格的纸色（fx_ult_ink 的 paper 要一致）
const BW_FRAMES := 2
## 主斩月牙：半径 / 最粗（屏幕像素）、往上斜多少、半张角；寿命、扫出来 / 开始擦的时间比例
const MAIN_R := 3000.0
const MAIN_B := 54.0
const MAIN_TILT := 0.1
const MAIN_HALF := 0.33
const MAIN_LIFE := 0.5
const MAIN_S0 := 0.14
const MAIN_S1 := 0.4
const SPLIT_PX := 10.0                   ## 画面沿斩线错开几个屏幕像素
## 起手那几帧里刀的位置：动画名 → 帧号 → [刀柄 x, y, 刀尖 x, y]（贴图像素，tools/art 里用颜色 + 连通块量出来的）
const BLADE := {
	"charge_slash": {0: [705, 510, 542, 506], 1: [719, 506, 564, 519], 2: [737, 476, 608, 484], 3: [769, 448, 620, 447],
		4: [815, 442, 654, 429], 5: [844, 446, 665, 421], 6: [974, 458, 792, 445], 7: [1039, 473, 865, 451],
		8: [1039, 473, 865, 451]},
}

var fx: Node2D                 ## ImpactFX（像素特效 + 刀光辉光）
var player: Node2D
var dark := 0.0
var dark_target := 0.0
var flash := 0.0
var _dim: Node2D
var _back: PixelFx             ## 主斩月牙单独一张像素画布，画在角色身后：影和主角的剪影压在亮月牙上
var _paper: Node2D             ## 黑白定格：纸（夜景之上、地形之下）
var _ink: Node2D               ## 黑白定格：读屏幕，纸以外的都变墨色
var _ink_copy: BackBufferCopy
var _split: Node2D             ## 画面沿斩线错开
var _split_copy: BackBufferCopy
var _split_mat: ShaderMaterial
var _phase: int = 0            ## 0 没在放 / 1 起手 / 2 出刀之后
var _t: float = 0.0
var _st: float = 0.0           ## 出刀后过了多久
var _windup: float = 0.4
var _star_done: bool = false
var _boost_after: float = 0.0
var _bw: int = 0
var _bw_on: bool = false
var _dir: float = 1.0
var _main: PixelFx.Fx
var _cuts: Array = []          ## [月牙, 上一帧尾巴擦到哪, 碎光点密度]
var _targets: Array = []       ## {node, pt, ang, pass, pop, cut, done}
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	z_index = 20
	process_priority = 10           # 在像素特效之后跑：黑白那两帧要压住辉光
	rng.randomize()
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = add                  # 自己只画“全屏辉光”那一下：相加
	_dim = _layer(-1)               # 地形 −70 之上、角色 0 之下
	_dim.visible = true
	_dim.draw.connect(_draw_dim)
	_back = PixelFx.new()
	_back.z_as_relative = false
	_back.z_index = -1              # 和压暗同层、在它之后画
	add_child(_back)
	_paper = _layer(-74)            # 夜景像素化（−75）之上、地形（−70）之下：地形也变墨色剪影
	_paper.draw.connect(func(): _paper.draw_rect(Rect2(-VIEW * 0.6, VIEW * 1.2), PAPER))
	_ink_copy = _copy(39)
	_ink = _layer(40, INK_SHADER)   # 伤害数字（35）也一起变墨色；HUD 在 CanvasLayer 上不受影响
	_ink.draw.connect(func(): _ink.draw_rect(Rect2(-VIEW * 0.6, VIEW * 1.2), Color.WHITE))
	_split_copy = _copy(44)
	_split = _layer(45, SPLIT_SHADER)
	_split_mat = _split.material as ShaderMaterial
	_split.draw.connect(func(): _split.draw_rect(Rect2(-VIEW * 0.6, VIEW * 1.2), Color.WHITE))


func _layer(z: int, shader: Shader = null) -> Node2D:
	var n := Node2D.new()
	n.z_as_relative = false
	n.z_index = z
	n.visible = false
	if shader != null:
		var m := ShaderMaterial.new()
		m.shader = shader
		n.material = m
	add_child(n)
	return n


func _copy(z: int) -> BackBufferCopy:
	var b := BackBufferCopy.new()
	b.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	b.z_as_relative = false
	b.z_index = z
	b.visible = false
	add_child(b)
	return b


func begin() -> void:
	dark_target = 1.0
	_phase = 1
	_t = 0.0
	_star_done = false
	_windup = 0.4
	if is_instance_valid(player) and player.get("ult_hit_frame") != null:
		_windup = maxf(float(player.ult_hit_frame) / 60.0, 0.1)
	_windup_burst()


func clear() -> void:
	_phase = 0
	dark = 0.0
	dark_target = 0.0
	flash = 0.0
	_boost_after = 0.0
	_bw = 0
	_main = null
	_cuts.clear()
	_targets.clear()
	_show_bw(false)
	_split.visible = false
	_split_copy.visible = false
	_bloom_gain(0.0)
	_back.clear()
	if is_instance_valid(fx):
		fx.blade_boost = 0.0
		fx.blade_seg = Vector4.ZERO


## 第 i 个被砍中的影（按离主角远近排）多久以后爆开；关卡按这个给它定住的帧数
static func pop_delay(i: int) -> float:
	return 0.16 + 0.1 * float(i)


## 出刀。center_y = 主角胸口高度；dir = 朝向；targets = [{node, pt}]（被砍中的影，近的在前）
func slash(center_y: float, dir: int, targets: Array = []) -> void:
	_phase = 2
	_st = 0.0
	_bw = BW_FRAMES
	_boost_after = 1.0
	dark = 1.0
	dark_target = 0.0
	flash = 0.0
	_dir = 1.0 if dir >= 0 else -1.0
	_cuts.clear()
	_targets.clear()
	_main = null
	var ok := _ok()
	var w: float = fx._w() if is_instance_valid(fx) else 2.0
	var chest := Vector2(player.global_position.x if is_instance_valid(player) else global_position.x, center_y)
	# 主斩：一道大月牙（圆心在下面，弧顶略往前），从身后往前扫过全屏
	var tang := Vector2(_dir * cos(MAIN_TILT), -sin(MAIN_TILT))
	var through := chest + Vector2(_dir * 40.0, -6.0) * w
	if ok:
		var front = fx.pfx
		fx.pfx = _back
		_main = _arc_through(through, tang, MAIN_R, MAIN_R * MAIN_HALF, MAIN_B, MAIN_LIFE, 0.0, MAIN_S0, MAIN_S1, 10, 1.0, _dir)
		fx.pfx = front
		_cuts.append([_main, 0.0, 170])
	var cen: Vector2 = _main.pos if _main != null else through + Vector2(0.0, MAIN_R * w)
	var c0: float = _main.c if _main != null else 0.0
	var c1: float = _main.d if _main != null else 1.0
	# X：两道交叉细斩，交在敌人那边（没打中谁就在身前）
	var xc := chest + Vector2(_dir * 300.0, -10.0) * w
	if not targets.is_empty():
		var sum := Vector2.ZERO
		for tg in targets:
			sum += tg.pt
		xc = sum / float(targets.size())
		xc.x = clampf(xc.x, chest.x - 560.0 * w, chest.x + 560.0 * w)
	if ok:
		var a1 := deg_to_rad(_r(32.0, 40.0))
		var a2 := deg_to_rad(_r(30.0, 38.0))
		var x1 := _arc_through(xc, Vector2(_dir * cos(a1), sin(a1)), 2000.0, 600.0, 14.0, 0.34, 0.05, 0.2, 0.4, 3, 0.6, 1.0)
		var x2 := _arc_through(xc, Vector2(_dir * cos(a2), -sin(a2)), 2000.0, 600.0, 12.0, 0.32, 0.09, 0.2, 0.4, 3, 0.6, -1.0)
		_cuts.append([x1, 0.0, 30])
		_cuts.append([x2, 0.0, 30])
		_ground_dust(chest)
	# 被砍中的影：月牙扫到它的那一刻浮现斩痕，之后按远近一个接一个爆开
	var i := 0
	for tg in targets:
		var pt: Vector2 = tg.pt
		var u := clampf(wrapf((pt - cen).angle() - c0, -PI, PI) / (c1 - c0), 0.0, 1.0)
		var pass_t := (1.0 - pow(1.0 - u, 1.0 / 3.0)) * MAIN_S0 * MAIN_LIFE
		var main_ang := (pt - cen).angle() + PI * 0.5 * signf(c1 - c0)
		var tilt := _r(0.3, 0.7) * (1.0 if rng.randf() < 0.5 else -1.0)
		_targets.append({"node": tg.get("node"), "pt": pt, "ang": main_ang + tilt, "pass": pass_t,
			"pop": maxf(pop_delay(i), pass_t + 0.08), "cut": false, "done": false})
		i += 1


func busy() -> bool:
	return dark > 0.001 or flash > 0.001 or _phase != 0


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		global_position = cam.get_screen_center_position()
	_tick_windup(delta)
	if _phase == 2:
		_tick_slash(delta)
	else:
		dark = move_toward(dark, dark_target, delta * (5.0 if dark_target > dark else 1.6))
		flash = maxf(0.0, flash - delta * 6.0)
	queue_redraw()
	_dim.queue_redraw()


func _draw_dim() -> void:
	if dark <= 0.001 or _bw_on:
		return
	_dim.draw_rect(Rect2(-VIEW * 0.6, VIEW * 1.2), Color(0.015, 0.02, 0.04, 0.62 * dark))


## 全屏辉光（相加）：出刀定格一结束，整屏往紫白亮一下
func _draw() -> void:
	if flash > 0.001 and not _bw_on:
		var k := 0.2 * flash * flash
		draw_rect(Rect2(-VIEW * 0.6, VIEW * 1.2), Color(0.86 * k, 0.84 * k, 0.94 * k, 1.0))


# ---------------------------------------------------------------- ② 出刀 / ③ 余波

func _tick_slash(delta: float) -> void:
	_st += delta
	# 黑白两帧（数帧，不数时间：慢动作 / 掉帧时也正好两帧）
	_bw_on = _bw > 0
	if _bw_on:
		_bw -= 1
	_show_bw(_bw_on)
	# 定格一结束：全屏辉光，像素特效的辉光也加亮一下
	flash = 0.0 if _bw_on else clampf(1.0 - (_st - 0.03) / 0.13, 0.0, 1.0)
	_bloom_gain(flash)
	# 背景：出刀后一直暗着，余波后半段亮回来
	dark = 1.0 - smoothstep(0.32, 0.66, _st)
	# 画面沿斩线错开：月牙扫完开始，0.05 秒错开 → 停一下 → 0.13 秒合上
	var k := 0.0
	if _st >= 0.06:
		k = smoothstep(0.06, 0.1, _st) * (1.0 - smoothstep(0.16, 0.29, _st))
	var on := k > 0.02 and _main != null
	_split.visible = on
	_split_copy.visible = on
	if on:
		var w: float = fx._w()
		_split_mat.set_shader_parameter("center", _main.pos)
		_split_mat.set_shader_parameter("radius", _main.a)
		_split_mat.set_shader_parameter("amount", SPLIT_PX * k)
		_split_mat.set_shader_parameter("dir", _dir)
		_split_mat.set_shader_parameter("seam", 3.0 * w * k)
		_split.queue_redraw()
	if _ok():
		_tick_head()
		_tick_crumble()
	for tg in _targets:
		if not tg.cut and _st >= tg.pass:
			tg.cut = true
			_cut_mark(tg)
		if not tg.done and _st >= tg.pop:
			tg.done = true
			_pop(tg)
	if _st > 1.0 and _targets.all(func(t): return t.done):
		_phase = 0
		_show_bw(false)
		_split.visible = false
		_split_copy.visible = false
		_bloom_gain(0.0)
		dark = 0.0


func _show_bw(on: bool) -> void:
	_paper.visible = on
	_ink.visible = on
	_ink_copy.visible = on
	if on:
		_paper.queue_redraw()
		_ink.queue_redraw()
		_back.bloom.visible = false
		if is_instance_valid(fx):
			fx.pfx.bloom.visible = false
			fx._impact.visible = false


func _bloom_gain(k: float) -> void:
	for p in [_back, fx.pfx if is_instance_valid(fx) else null]:
		if p == null or p.bloom_src == null:
			continue
		var m := p.bloom_src.material as ShaderMaterial
		if m != null:
			m.set_shader_parameter("gain", 2.0 + 2.6 * k)


## 一道穿过点 p、在 p 处沿 tang 方向走的月牙；bend = 1 / −1 弯向哪边（圆心在 tang 的左 / 右手）
func _arc_through(p: Vector2, tang: Vector2, r: float, half: float, b: float, life: float, delay: float,
		s0: float, s1: float, hairs: int, rough: float, bend: float) -> PixelFx.Fx:
	var w: float = fx._w()
	var t := tang.normalized()
	var cen := p + Vector2(-t.y, t.x) * bend * r * w
	var phi := (p - cen).angle()
	var s := half / r
	var e := 1.0
	# 亮刃口朝上（外缘 / 内缘哪边在上就选哪边）
	if (p - cen).y > 0.0:
		e = -1.0
	return fx._crescent(cen, r, b, phi - s * bend, phi + s * bend, life, delay, [WHITE, VIO_L, VIO], s0, s1, e, hairs, rough)


## 主斩的刀头：扫过去的时候一路往外甩紫白火星
func _tick_head() -> void:
	if _main == null:
		return
	var t := _main.age / _main.life
	if t <= 0.0 or t > MAIN_S0 * 1.15:
		return
	var sp := ImpactFX.crescent_span(_main, t)
	var u := sp.y
	var head := ImpactFX.crescent_point(_main, u, _main.b * 0.3)
	var along := lerpf(_main.c, _main.d, u) + PI * 0.5 * signf(_main.d - _main.c)
	fx._sparks(head, 4, along, 0.45, 260.0, 720.0, 0.14, 0.3, [WHITE, VIO_L, VIO], 260.0, 2.5)
	fx._star(head, 26.0, along, 2.4, VIO_L, WHITE, 0.07, 0.0, 0.5)


## 斩线碎成光点：每道月牙从尾巴擦掉的那一段，撒成往上飘的小光点
func _tick_crumble() -> void:
	var w: float = fx._w()
	for e in _cuts:
		var f: PixelFx.Fx = e[0]
		if f.age < f.delay:
			continue
		var t := clampf((f.age - f.delay) / f.life, 0.0, 1.0)
		var sp := ImpactFX.crescent_span(f, t)
		var prev: float = e[1]
		if sp.x <= prev + 0.001:
			continue
		var n := int(ceil((sp.x - prev) * float(e[2])))
		var er := clampf((t - f.s1) / maxf(1.0 - f.s1, 0.001), 0.0, 1.0)
		for i in n:
			var u := rng.randf_range(prev, sp.x)
			var q := ImpactFX.crescent_point(f, u, _r(-0.45, 0.45) * f.b * (1.0 - 0.5 * er))
			var m = fx.pfx.add(K.SPARK, q, _r(0.4, 0.9))
			var along := lerpf(f.c, f.d, u) + PI * 0.5 * signf(f.d - f.c)
			m.vel = (Vector2.from_angle(along) * _r(10.0, 60.0) + Vector2(_r(-30.0, 30.0), _r(-90.0, -20.0))) * w
			m.drag = 1.4
			m.b = (3.0 if rng.randf() < 0.4 else 2.0) * w
			m.d = 0.02
			m.c0 = WHITE
			m.c1 = VIO_L if rng.randf() < 0.6 else WHITE
			m.c2 = VIO
		e[1] = sp.x


## 地面沿斩线扬尘：从身后到身前一路掀起来（跟着月牙扫的节奏），贴地还有几道风线
func _ground_dust(chest: Vector2) -> void:
	var w: float = fx._w()
	var feet := _feet()
	var x0 := global_position.x - _dir * VIEW.x * 0.52
	var x1 := global_position.x + _dir * VIEW.x * 0.52
	var n := 16
	for i in n:
		var k := (float(i) + _r(-0.3, 0.3)) / float(n - 1)
		var x := lerpf(x0, x1, k)
		var gy: float = fx._floor(Vector2(x, feet.y - 20.0))
		if not is_finite(gy) or absf(gy - feet.y) > 300.0:
			gy = feet.y
		var q := Vector2(x, gy - 3.0 * w)
		var delay := 0.02 + MAIN_S0 * MAIN_LIFE * k + _r(0.0, 0.03)
		fx._puff(q, Vector2(_dir * _r(40.0, 190.0), _r(-110.0, -30.0)), _r(2.0, 3.5), _r(7.0, 14.0), _r(0.45, 0.75), delay)
		if i % 2 == 0:
			fx._streak(q + Vector2(0.0, -_r(0.0, 6.0)) * w, _r(40.0, 90.0), _r(1.6, 2.6), 0.0 if _dir > 0.0 else PI,
				ImpactFX.DUST_L, WHITE, _r(0.24, 0.36), delay, 0.0, Vector2(_dir * _r(300.0, 520.0), 0.0))
		if rng.randf() < 0.35:
			fx._chunks(q, 2, -PI * 0.5 + _dir * 0.3, 0.6, 90.0, 220.0, 2.0, 3.5,
				[ImpactFX.STONE_L, ImpactFX.STONE, ImpactFX.STONE_D], 1200.0, 0.4, 0.6, true)


## ③ 斩痕：月牙扫到这只影的那一刻，身上浮现一道斜的细月牙，亮着撑到它爆开
func _cut_mark(tg: Dictionary) -> void:
	if not _ok():
		return
	var pt: Vector2 = tg.pt
	var life: float = float(tg.pop) - float(tg.pass) + 0.07
	var f := _arc_through(pt, Vector2.from_angle(float(tg.ang)), 240.0, 58.0, 9.0, life, 0.0,
		minf(0.05 / life, 0.4), 0.92, 2, 0.5, 1.0 if rng.randf() < 0.5 else -1.0)
	if f != null:
		f.c2 = VIO_D
	fx._star(pt, 16.0, float(tg.ang), 2.4, VIO_L, WHITE, 0.12, 0.0, 0.5)
	fx._sparks(pt, 5, float(tg.ang), 0.5, 200.0, 460.0, 0.1, 0.22, [WHITE, VIO_L, VIO], 0.0, 2.0)


## ③ 爆开：白芯闪 + 紫白爆闪 + 紫白碎光片 + 墨点 + 顺着斩痕两道亮线
func _pop(tg: Dictionary) -> void:
	var pt: Vector2 = tg.pt
	if _ok():
		var ang: float = tg.ang
		fx._disc(pt, 22.0, WHITE, 0.05)
		fx._burst(pt, 50.0, ang, 11, VIO_L, WHITE, VIO, 0.18)
		fx._ring(pt, 14.0, 74.0, 10.0, 0.0, VIO_L, 0.16, 0.0, 1.0, _r(0.0, TAU))
		fx._chunks(pt, 9, -PI * 0.5, PI, 160.0, 480.0, 2.0, 6.0, [WHITE, VIO_L, VIO], 500.0, 0.3, 0.6, false)
		fx._chunks(pt, 8, -PI * 0.5, PI, 120.0, 400.0, 3.0, 7.0, [INK, INK, ImpactFX.SMOKE], 900.0, 0.45, 0.75, true)
		fx._sparks(pt, 12, ang, PI, 220.0, 680.0, 0.16, 0.34, [WHITE, VIO_L, VIO], 400.0, 2.5)
		fx._streak(pt, 170.0, 11.0, ang, VIO, WHITE, 0.16)
		fx._streak(pt, 120.0, 7.0, ang + PI, VIO, WHITE, 0.14)
		fx.glow_hit(1.0)
	var node = tg.get("node")
	if node is Node2D and is_instance_valid(node):
		if node.get("flash") != null:
			node.set("flash", 5)
		popped.emit(node, pt)
	else:
		popped.emit(null, pt)


# ---------------------------------------------------------------- ① 起手

func _ok() -> bool:
	return is_instance_valid(fx) and is_instance_valid(player) and bool(fx.enabled)


func _r(a: float, b: float) -> float:
	return rng.randf_range(a, b)


func _feet() -> Vector2:
	return player.global_position + Vector2(0.0, float(player.foot_offset))


## 这一帧刀柄 / 刀尖的世界坐标（没量过的帧返回空）；顺手算好贴图像素版给辉光着色器
func _blade() -> Array:
	var v := player.get_node_or_null("Visual/ActorSprite") as Sprite2D
	if v == null or v.texture == null:
		return []
	var table: Dictionary = BLADE.get(String(v.get("clip_name")), {})
	var e = table.get(int(v.get("frame_index")), null)
	if e == null:
		return []
	var size := v.texture.get_size()
	var h := Vector2(float(e[0]), float(e[1]))
	var t := Vector2(float(e[2]), float(e[3]))
	var lh := v.offset + (Vector2(size.x - h.x, h.y) if v.flip_h else h)
	var lt := v.offset + (Vector2(size.x - t.x, t.y) if v.flip_h else t)
	return [v.global_transform * lh, v.global_transform * lt, Vector4(h.x, h.y, t.x, t.y)]


## 起手一瞬间：脚下的风压——贴地的风线往两边刮开（长短、高低、快慢都不一样）+ 少量尘土 + 几粒石屑蹦起来
func _windup_burst() -> void:
	if not _ok():
		return
	var feet := _feet()
	var w: float = fx._w()
	for side in [-1.0, 1.0]:
		for i in 7:
			var q := feet + Vector2(side * _r(6.0, 40.0), -_r(1.0, 16.0) * (0.4 + 0.6 * rng.randf())) * w
			fx._streak(q, _r(22.0, 64.0), _r(1.6, 3.2), 0.0 if side > 0.0 else PI,
				ImpactFX.DUST_L if rng.randf() < 0.5 else VIO_L, WHITE, _r(0.22, 0.38), _r(0.0, 0.08),
				0.4 if rng.randf() < 0.4 else 0.0, Vector2(side * _r(260.0, 520.0), _r(-10.0, 0.0)))
		for i in 3:
			var q := feet + Vector2(side * _r(4.0, 30.0), _r(-6.0, -1.0)) * w
			fx._puff(q, Vector2(side * _r(150.0, 320.0), _r(-30.0, -6.0)), _r(2.0, 3.0), _r(5.0, 9.0), _r(0.28, 0.42), _r(0.0, 0.05))
	fx._chunks(feet + Vector2(0, -4) * w, 5, -PI * 0.5, 1.25, 90.0, 240.0, 2.0, 4.0,
		[ImpactFX.STONE_L, ImpactFX.STONE, ImpactFX.STONE_D], 1200.0, 0.4, 0.6, true)
	fx._sparks(feet + Vector2(0, -6) * w, 6, -PI * 0.5, 1.3, 120.0, 300.0, 0.2, 0.36, [WHITE, VIO_L, VIO], 500.0, 2.0)


func _tick_windup(delta: float) -> void:
	if not _ok():
		return
	var boost: float = 0.0
	var sweep: float = 1.0
	if _phase == 1 and _t > 0.05 and player.has_method("is_ult") and not player.is_ult():
		_phase = 0          # 大招被打断（重开 / 死了）：起手特效停掉
	if _phase == 1:
		_t += delta
		var k := clampf(_t / _windup, 0.0, 1.0)
		var b := _blade()
		if not b.is_empty():
			fx.blade_seg = b[2]
			sweep = smoothstep(0.08, 0.78, k)
			boost = 2.4 * smoothstep(0.0, 0.45, k)
		var w: float = fx._w()
		var target: Vector2 = (b[0] as Vector2).lerp(b[1], 0.35) if not b.is_empty() else player.global_position
		# 光丝往刀上聚：绕着刀转着往里收（K.WISP），越到后面越密、越快；转的方向、圈数、粗细都随机
		if k < 0.86:
			var n := int(_r(0.0, 1.0) + 0.7 + 2.2 * k)
			for i in n:
				var life := _r(0.2, 0.34) * (1.0 - 0.35 * k)
				var f = fx.pfx.add(K.WISP, target, life)
				f.a = _r(46.0, 130.0) * w
				f.b = _r(1.4, 2.8) * w
				f.c = _r(0.0, TAU)
				f.d = _r(1.2, 2.6) * (1.0 if rng.randf() < 0.5 else -1.0)
				f.squash = _r(0.12, 0.3)
				f.c1 = VIO if rng.randf() < 0.6 else VIO_L
				f.c0 = WHITE if rng.randf() < 0.7 else VIO_L
		# 身边的光点往上飘
		if rng.randf() < 0.75:
			var q := _feet() + Vector2(_r(-130.0, 130.0), _r(-120.0, 0.0)) * w
			var m = fx.pfx.add(K.SPARK, q, _r(0.5, 0.9))
			m.vel = Vector2(_r(-16.0, 16.0), _r(-120.0, -50.0)) * w
			m.drag = 0.6
			m.b = (3.0 if rng.randf() < 0.2 else 2.0) * w
			m.d = 0.04
			m.c0 = WHITE; m.c1 = VIO_L; m.c2 = VIO
		# 刀尖“叮”：十字星（横长竖短）+ 斜 45° 的小星 + 一点白芯
		if k >= 0.8 and not _star_done and not b.is_empty():
			_star_done = true
			var tip: Vector2 = b[1]
			var along: float = ((b[1] as Vector2) - (b[0] as Vector2)).angle()
			fx._star(tip, 40.0, along, 2.6, VIO_L, WHITE, 0.24, 0.0, 0.5)
			fx._star(tip, 16.0, along + PI * 0.25, 1.0, WHITE, WHITE, 0.16, 0.02, 0.0)
			fx._disc(tip, 6.0, WHITE, 0.06)
			fx._sparks(tip, 5, along, 1.2, 60.0, 180.0, 0.14, 0.24, [WHITE, VIO_L, VIO], 0.0, 2.0)
	elif _boost_after > 0.0:
		# 出刀之后刀上的光很快退掉
		_boost_after = maxf(_boost_after - delta * 4.0, 0.0)
		boost = 2.4 * _boost_after
		if _boost_after <= 0.0:
			fx.blade_seg = Vector4.ZERO
	fx.blade_sweep = sweep
	fx.blade_boost = boost
