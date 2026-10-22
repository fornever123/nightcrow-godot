extends Node2D
## 大招「月下斩」的全屏表现（世界坐标，跟着镜头）。第四轮 §16.11 起分三段：
##   ① 起手 begin()：背景压暗；脚下炸开一圈风压、尘土往两边吹；四周紫色光丝往刀上聚；身边光点往上飘；
##      刀身从刀柄往刀尖一路点亮（fx_glow_sprite 的 blade / sweep / boost），最后刀尖“叮”一颗十字星。
##   ② 出刀 slash()：（待做）—— 目前还是几道横贯全屏的剑气 + 一下闪光，然后暗层慢慢退掉
##   ③ 余波：（待做）
## 不显示字；镜头不动（只震屏）。特效零件都画进 impact_fx 的像素特效画布（同一套像素风 + 辉光）。
const ImpactFX := preload("res://scripts/presentation/impact_fx.gd")
const K := preload("res://scripts/presentation/pixel_fx.gd").K
const VIEW := Vector2(2560.0, 1440.0)    ## 镜头 ZOOM 0.5 → 世界里一屏的大小
const CORE := Color(1.0, 0.97, 0.88)
const GLOW := Color(1.0, 0.72, 0.38)
const WHITE := ImpactFX.WHITE
const VIO_L := ImpactFX.VIO_L
const VIO := ImpactFX.VIO
const VIO_D := ImpactFX.VIO_D
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
var slashes: Array = []        ## {y, ang, t, life, delay, w, dir}
var _dim: Node2D
var _phase: int = 0            ## 0 没在放 / 1 起手 / 2 出刀之后
var _t: float = 0.0
var _windup: float = 0.4
var _star_done: bool = false
var _boost_after: float = 0.0
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	z_index = 20                    # 剑气画在所有东西前面（包括近景 15）
	_dim = Node2D.new()
	_dim.z_as_relative = false
	_dim.z_index = -1               # 地形 −70 之上、角色 0 之下
	add_child(_dim)
	_dim.draw.connect(_draw_dim)


func begin() -> void:
	dark_target = 1.0
	slashes.clear()
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
	slashes.clear()
	_boost_after = 0.0
	if is_instance_valid(fx):
		fx.blade_boost = 0.0
		fx.blade_seg = Vector4.ZERO


## center_y = 剑气中心高度（玩家胸口）；dir = 玩家朝向；extra_ys = 被砍中的敌人高度（各补一道）
func slash(center_y: float, dir: int, extra_ys: Array = []) -> void:
	_phase = 2
	_boost_after = 1.0
	flash = 1.0
	dark_target = 0.0
	var ys := [center_y, center_y - 70.0, center_y + 60.0]
	for y in extra_ys.slice(0, 2):     # 最多再补两道，多了一屏全是线
		ys.append(float(y))
	var i := 0
	for y in ys:
		slashes.append({"y": y, "ang": (0.035 if i % 2 == 0 else -0.05) * float(dir), "t": 0.0,
			"life": 0.34 + 0.04 * float(i % 3), "delay": 0.02 * float(i), "w": 16.0 if i == 0 else 9.0, "dir": dir})
		i += 1


func busy() -> bool:
	return dark > 0.001 or flash > 0.001 or not slashes.is_empty() or _phase == 1


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		global_position = cam.get_screen_center_position()
	dark = move_toward(dark, dark_target, delta * (5.0 if dark_target > dark else 1.6))
	_tick_windup(delta)
	flash = maxf(0.0, flash - delta * 3.5)
	for s in slashes:
		s.t += delta
	slashes = slashes.filter(func(s): return s.t < s.delay + s.life)
	queue_redraw()
	_dim.queue_redraw()


func _draw_dim() -> void:
	if dark <= 0.001:
		return
	_dim.draw_rect(Rect2(-VIEW * 0.6, VIEW * 1.2), Color(0.015, 0.02, 0.04, 0.62 * dark))


func _draw() -> void:
	var half := VIEW.x * 0.6
	for s in slashes:
		var t: float = s.t - s.delay
		if t < 0.0:
			continue
		var p := t / float(s.life)
		# 前 18% 从一侧扫到另一侧，之后变细淡出
		var sweep := clampf(p / 0.18, 0.0, 1.0)
		var fade := 1.0 - clampf((p - 0.18) / 0.82, 0.0, 1.0)
		var d := float(s.dir)
		var a := Vector2(-half * d, 0.0)
		var b := a.lerp(Vector2(half * d, 0.0), 1.0 - pow(1.0 - sweep, 3.0))
		var rot := Transform2D(float(s.ang), Vector2(0.0, float(s.y) - global_position.y))
		a = rot * a
		b = rot * b
		var w: float = float(s.w) * (0.35 + 0.65 * fade) * (1.0 + 0.6 * (1.0 - sweep))
		draw_line(a, b, Color(GLOW, 0.14 * fade), w * 3.6)
		draw_line(a, b, Color(GLOW, 0.4 * fade), w * 1.8)
		draw_line(a, b, Color(CORE, 0.95 * fade), w)
		# 刀尖一点亮光
		if sweep < 1.0:
			draw_circle(b, w * 1.6, Color(CORE, 0.9))
	if flash > 0.001:
		draw_rect(Rect2(-VIEW * 0.6, VIEW * 1.2), Color(1.0, 0.93, 0.78, 0.28 * flash * flash))


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
