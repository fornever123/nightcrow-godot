extends Node2D
## 像素特效画布（第四轮 · 角色特效）。
## 命中闪光、斩线、火花、碎块、尘土、冲击环……全部先画进一张“半分辨率”的小画布：
##   小画布 1 格 = pix（2）个屏幕像素，和背景像素块一样大；再用最近邻放大贴回世界 → 硬边像素风。
##   透明度用拜耳抖动（fx_dither.gdshader）：淡出是“碎成像素点”，不是变半透明。
## 坐标一律用世界坐标；小画布每帧按主镜头对齐（含震屏），所以特效跟着世界走。
## 外面（impact_fx.gd）负责“配方”：一次命中由哪些零件组成、多大、什么颜色。

const DITHER := preload("res://assets/shaders/fx_dither.gdshader")
enum K { STAR, STREAK, RING, DISC, SPARK, CHUNK, PUFF, LINES, CRACK, BURST, SLIT }
## 画的先后（0 最先画 = 最下面）：尘土 → 碎块 / 冲击环 → 斩线 / 速度线 → 火花 → 闪光
const LAYER_OF := {K.PUFF: 0, K.CRACK: 0, K.CHUNK: 1, K.RING: 1, K.LINES: 2, K.STREAK: 2,
	K.SPARK: 3, K.DISC: 4, K.STAR: 4, K.BURST: 4, K.SLIT: 4}
const LAYERS := 5

var pix: float = 2.0            ## 小画布 1 格 = 几个屏幕像素
var max_items: int = 900
var viewport: SubViewport
var canvas: Node2D
var display: Sprite2D
var items: Array[Fx] = []


class Fx:
	var kind: int = 0
	var layer: int = 0
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var age: float = 0.0
	var delay: float = 0.0
	var life: float = 0.2
	var ang: float = 0.0
	var spin: float = 0.0
	var a: float = 0.0           ## 主尺寸（半径 / 长度 / 起始半径）
	var b: float = 0.0           ## 次尺寸（宽 / 结束半径）
	var c: float = 0.0           ## 其他（拉伸 / 起始粗细）
	var d: float = 0.0           ## 其他（结束粗细 / 线长）
	var squash: float = 1.0      ## 冲击环压扁（地面上的环）
	var drag: float = 0.0        ## 每秒速度衰减系数
	var grav: float = 0.0
	var floor_y: float = INF     ## 落到这里弹一下
	var c0 := Color.WHITE        ## 核心 / 亮部
	var c1 := Color.WHITE        ## 外圈 / 主色
	var c2 := Color.WHITE        ## 末段 / 暗部
	var angs := PackedFloat32Array()
	var lens := PackedFloat32Array()
	var pts := PackedVector2Array()


func _ready() -> void:
	viewport = SubViewport.new()
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	viewport.size = Vector2i(640, 360)
	add_child(viewport)
	canvas = Node2D.new()
	var mat := ShaderMaterial.new()
	mat.shader = DITHER
	mat.set_shader_parameter("cell", 1.0)
	canvas.material = mat
	viewport.add_child(canvas)
	canvas.draw.connect(_draw_items)
	display = Sprite2D.new()
	display.centered = false
	display.texture = viewport.get_texture()
	display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	display.visible = false
	add_child(display)
	RenderingServer.frame_pre_draw.connect(_sync)


func _exit_tree() -> void:
	if RenderingServer.frame_pre_draw.is_connected(_sync):
		RenderingServer.frame_pre_draw.disconnect(_sync)


## 每帧画之前：小画布对齐主镜头（含震屏），显示用的贴图盖住整个屏幕
func _sync() -> void:
	if not is_inside_tree():
		return
	var vp := get_viewport()
	var ct := vp.get_canvas_transform()
	var size := vp.get_visible_rect().size
	var want := Vector2i(ceili(size.x / pix), ceili(size.y / pix))
	if viewport.size != want:
		viewport.size = want
	viewport.canvas_transform = Transform2D(0.0, Vector2(1.0 / pix, 1.0 / pix), 0.0, Vector2.ZERO) * ct
	display.global_transform = ct.affine_inverse() * Transform2D(0.0, Vector2(pix, pix), 0.0, Vector2.ZERO)


## 世界单位 / 屏幕像素（镜头 zoom 0.5 时是 2）
func world_per_px() -> float:
	if not is_inside_tree():
		return 1.0
	return 1.0 / maxf(get_viewport().get_canvas_transform().x.length(), 0.0001)


func add(kind: int, pos: Vector2, life: float, delay: float = 0.0) -> Fx:
	var f := Fx.new()
	f.kind = kind
	f.layer = LAYER_OF[kind]
	f.pos = pos
	f.life = maxf(life, 0.001)
	f.delay = delay
	if items.size() < max_items:
		items.append(f)
	return f


func count() -> int:
	return items.size()


func clear() -> void:
	items.clear()
	if canvas != null:
		canvas.queue_redraw()
	if display != null:
		display.visible = false


func _process(delta: float) -> void:
	if items.is_empty():
		if display.visible:
			display.visible = false
		return
	display.visible = true
	for f in items:
		if f.age < f.delay:
			f.age += delta
			continue
		f.age += delta
		if f.drag > 0.0:
			f.vel *= exp(-f.drag * delta)
		f.vel.y += f.grav * delta
		f.pos += f.vel * delta
		f.ang += f.spin * delta
		if f.pos.y > f.floor_y and f.vel.y > 0.0:
			f.pos.y = f.floor_y
			f.vel.y *= -0.32
			f.vel.x *= 0.55
			f.spin *= 0.5
	items = items.filter(func(f: Fx) -> bool: return f.age < f.delay + f.life)
	canvas.queue_redraw()


# ---------------------------------------------------------------- 画

func _draw_items() -> void:
	for layer in LAYERS:
		for f in items:
			if f.layer != layer or f.age < f.delay:
				continue
			var t := clampf((f.age - f.delay) / f.life, 0.0, 1.0)
			match f.kind:
				K.STAR: _draw_star(f, t)
				K.STREAK: _draw_streak(f, t)
				K.RING: _draw_ring(f, t)
				K.DISC: _draw_disc(f, t)
				K.SPARK: _draw_spark(f, t)
				K.CHUNK: _draw_chunk(f, t)
				K.PUFF: _draw_puff(f, t)
				K.LINES: _draw_lines(f, t)
				K.CRACK: _draw_crack(f, t)
				K.BURST: _draw_burst(f, t)
				K.SLIT: _draw_slit(f, t)


static func _fade(t: float, from: float) -> float:
	return 1.0 if t < from else clampf(1.0 - (t - from) / (1.0 - from), 0.0, 1.0)


## 四角星：a = 半径，c = 长轴拉伸，d = 核心比例（0 = 没有核心）
func _draw_star(f: Fx, t: float) -> void:
	var s: float
	if t < 0.16:
		s = 0.55 + 0.6 * t / 0.16
	else:
		s = 1.15 * (1.0 - pow((t - 0.16) / 0.84, 1.7))
	if s <= 0.02:
		return
	var al := _fade(t, 0.55)
	canvas.draw_colored_polygon(_star_pts(f.pos, f.a * s, maxf(f.c, 1.0), f.ang, 0.17), Color(f.c1, al))
	if f.d > 0.0:
		canvas.draw_colored_polygon(_star_pts(f.pos, f.a * s * f.d, maxf(f.c, 1.0), f.ang, 0.2), Color(f.c0, al))


static func _star_pts(p: Vector2, r: float, stretch: float, ang: float, inner: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var short := r / sqrt(stretch)
	for i in 8:
		var a := ang + float(i) * TAU / 8.0
		var rr: float
		if i % 2 == 1:
			rr = r * inner
		elif i % 4 == 0:
			rr = r * stretch
		else:
			rr = short
		out.append(p + Vector2.from_angle(a) * rr)
	return out


## 斩线（细长的梭形）：a = 长，b = 宽；先“唰”地拉长，再变细消失，同时沿斩的方向滑一点
func _draw_streak(f: Fx, t: float) -> void:
	var grow := 1.0 - pow(1.0 - minf(t / 0.22, 1.0), 2.0)
	var length := f.a * (0.3 + 0.8 * grow)
	var width := f.b * (1.0 if t < 0.3 else maxf(0.0, 1.0 - (t - 0.3) / 0.7))
	if width < 0.5 or length < 1.0:
		return
	var u := Vector2.from_angle(f.ang)
	var p := f.pos + u * f.a * 0.14 * t
	canvas.draw_colored_polygon(_lens(p, u, length, width), f.c1)
	if f.c > 0.0:
		canvas.draw_colored_polygon(_lens(p + u * length * 0.04, u, length * 0.82, width * f.c), f.c0)


static func _lens(p: Vector2, u: Vector2, length: float, width: float) -> PackedVector2Array:
	var v := Vector2(-u.y, u.x)
	var h := length * 0.5
	var w := width * 0.5
	return PackedVector2Array([p - u * h, p - u * h * 0.5 + v * w * 0.72, p + v * w, p + u * h * 0.5 + v * w * 0.72,
		p + u * h, p + u * h * 0.5 - v * w * 0.72, p - v * w, p - u * h * 0.5 - v * w * 0.72])


## 冲击环：a → b 半径，c → d 粗细，squash = 竖向压扁，ang = 旋转
func _draw_ring(f: Fx, t: float) -> void:
	var e := 1.0 - pow(1.0 - t, 3.0)
	var r := lerpf(f.a, f.b, e)
	# 粗细一路收细到 d（一般是 0）：硬边的冲击波，不是越来越淡的细线圈
	var th := lerpf(f.c, f.d, pow(t, 0.6))
	if th < 0.75 or r < 0.5:
		return
	var segs := clampi(int(r / 3.0), 16, 64)
	canvas.draw_set_transform(f.pos, f.ang, Vector2(1.0, f.squash))
	# 后半段碎成几段弧（不留一个干净的细圆圈，否则像瞄准镜）
	var gap := smoothstep(0.2, 0.9, t) * 0.75
	var col := Color(f.c1, _fade(t, 0.8))
	var rr := maxf(r - th * 0.5, th * 0.5)
	if gap < 0.02:
		canvas.draw_arc(Vector2.ZERO, rr, 0.0, TAU, segs, col, th)
	else:
		var n := 6
		var span := TAU / float(n)
		for i in n:
			var a0 := float(i) * span + f.d * 0.0 + float(i % 2) * 0.12
			canvas.draw_arc(Vector2.ZERO, rr, a0, a0 + span * (1.0 - gap), maxi(3, segs / n), col, th)
	canvas.draw_set_transform_matrix(Transform2D.IDENTITY)


## 实心闪光圆：只亮一两帧
func _draw_disc(f: Fx, t: float) -> void:
	canvas.draw_circle(f.pos, f.a * (1.0 + 0.35 * t), Color(f.c1, 1.0 - t))


## 火花：沿速度方向拉成短线；白 → 黄 → 橙
func _draw_spark(f: Fx, t: float) -> void:
	var col := f.c0 if t < 0.3 else (f.c1 if t < 0.65 else f.c2)
	var tail := f.vel * f.d
	if tail.length() < f.b:
		tail = tail.normalized() * f.b if tail.length() > 0.001 else Vector2(f.b, 0)
	var w := f.b * (1.0 if t < 0.6 else 0.6)
	canvas.draw_line(f.pos - tail, f.pos, Color(col, _fade(t, 0.75)), maxf(w, 1.0))


## 碎块：转着飞的小方块（石屑 / 影子碎片）
func _draw_chunk(f: Fx, t: float) -> void:
	var h := f.a * 0.5
	var u := Vector2.from_angle(f.ang) * h
	var v := Vector2(-u.y, u.x)
	var al := _fade(t, 0.65)
	canvas.draw_colored_polygon(PackedVector2Array([f.pos - u - v, f.pos + u - v, f.pos + u + v, f.pos - u + v]), Color(f.c1, al))
	if f.b > 0.0:
		canvas.draw_circle(f.pos + Vector2(h * 0.35, -h * 0.35), f.a * 0.3, Color(f.c0, al))


## 尘土团：暗部 + 主色 + 右上亮部（月亮在右上）；越来越大，最后碎成像素点
func _draw_puff(f: Fx, t: float) -> void:
	var e := 1.0 - pow(1.0 - t, 2.2)
	var r := lerpf(f.a, f.b, e)
	var al := 1.0 - pow(t, 1.3)
	canvas.draw_circle(f.pos + Vector2(-r * 0.1, r * 0.2), r, Color(f.c2, al))
	canvas.draw_circle(f.pos, r * 0.9, Color(f.c1, al))
	canvas.draw_circle(f.pos + Vector2(r * 0.26, -r * 0.3), r * 0.52, Color(f.c0, al * 0.95))


## 放射速度线：angs 是每根线的角度；a 起始半径，b 结束半径，c 粗，d 线长
func _draw_lines(f: Fx, t: float) -> void:
	var e := 1.0 - pow(1.0 - t, 2.0)
	var r_out: float
	var r_in: float
	if f.b < f.a:
		# 往里收：外端先走，越收越短
		r_in = lerpf(f.a, f.b, e)
		r_out = lerpf(f.a + f.d, f.b, pow(e, 1.3))
	else:
		r_out = lerpf(f.a + f.d, f.b, e)
		r_in = lerpf(f.a, f.b, minf(1.0, e * 1.3))
	if r_out - r_in < 1.0:
		return
	for g in f.angs:
		var u := Vector2.from_angle(f.ang + g)
		var v := Vector2(-u.y, u.x) * f.c * 0.5
		canvas.draw_colored_polygon(PackedVector2Array([f.pos + u * r_in + v, f.pos + u * r_out, f.pos + u * r_in - v]), f.c1)


## 地裂：一条折线，先显出来再慢慢碎掉
func _draw_crack(f: Fx, t: float) -> void:
	if f.pts.size() < 2:
		return
	var n := clampi(int(ceil(float(f.pts.size()) * minf(t / 0.12, 1.0))), 2, f.pts.size())
	var al := _fade(t, 0.45)
	var part := f.pts.slice(0, n)
	canvas.draw_polyline(part, Color(f.c1, al), f.a)
	if f.b > 0.0:
		var lit := PackedVector2Array()
		for q in part:
			lit.append(q + Vector2(0, f.b))
		canvas.draw_polyline(lit, Color(f.c0, al * 0.8), maxf(f.a * 0.5, 1.0))


## 爆闪（命中的主体）：一圈长短不一的尖刺，白芯 + 彩色外圈；先“砰”地胀开，再收成细刺消失
## a = 半径；angs / lens = 每根刺的角度和长短；c0 芯，c1 外圈，c2 冷却后的外圈色
func _draw_burst(f: Fx, t: float) -> void:
	var s: float
	if t < 0.18:
		s = 0.7 + 0.45 * t / 0.18
	else:
		s = 1.15 * (1.0 - pow((t - 0.18) / 0.82, 1.4))
	if s <= 0.04:
		return
	var inner := 0.34 * (1.0 - 0.55 * t)
	var rim := f.c1 if t < 0.55 else f.c2
	canvas.draw_colored_polygon(_burst_pts(f, f.a * s, inner), rim)
	if t < 0.7:
		canvas.draw_colored_polygon(_burst_pts(f, f.a * s * 0.58, inner * 1.1), f.c0)


func _burst_pts(f: Fx, r: float, inner: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := f.angs.size()
	for i in n:
		var a0 := f.ang + f.angs[i]
		var a1 := f.ang + (f.angs[(i + 1) % n] + (TAU if i == n - 1 else 0.0))
		out.append(f.pos + Vector2.from_angle(a0) * r * f.lens[i])
		out.append(f.pos + Vector2.from_angle((a0 + a1) * 0.5) * r * inner)
	return out


## 一闪（冲刺斩命中）：沿冲刺路径的一道细长亮线，白芯 + 浅紫 + 紫边（实色分层，不抖动）。
## a = 长，b = 粗，ang = 冲刺方向，c = 整条亮着停住的时间比例；
## 停住之后从尾端往刀尖收、同时变细（刀尖那头还往前探一点）。
func _draw_slit(f: Fx, t: float) -> void:
	var u := Vector2.from_angle(f.ang)
	var s := 0.0 if t < f.c else (t - f.c) / maxf(1.0 - f.c, 0.001)
	var e := 1.0 - pow(1.0 - s, 2.0)
	var head := f.pos + u * f.a * (0.5 + 0.06 * e)
	var tail := (f.pos - u * f.a * 0.5).lerp(head, pow(s, 1.3))
	var width := f.b * (1.0 - e * 0.85)
	if width < 0.5 or head.distance_to(tail) < 2.0:
		return
	canvas.draw_colored_polygon(_needle(tail, head, width * 1.9), f.c2)
	canvas.draw_colored_polygon(_needle(tail, head, width), f.c1)
	if s < 0.75:
		canvas.draw_colored_polygon(_needle(tail.lerp(head, 0.04), head, maxf(width * 0.42, 2.4)), f.c0)


static func _needle(a: Vector2, b: Vector2, width: float) -> PackedVector2Array:
	var d := b - a
	var v := Vector2(-d.y, d.x).normalized() * width * 0.5
	return PackedVector2Array([a, a + d * 0.08 + v, b - d * 0.12 + v, b, b - d * 0.12 - v, a + d * 0.08 - v])
