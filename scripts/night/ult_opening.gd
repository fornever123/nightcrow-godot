extends Node2D
## 大招开场「领域展开」里立在墨面上的东西（10-31，照 Remotion UltOpeningDomainV10 / V12 移过来）：脚下墨泡、前沿墨冠、两只鸦式神。
## 墙、地面、立面和墨本身在 fx_ult_domain.gdshader 里画；这里只画“纸片”：每个纸片立在地面上的一点 (x, z)，
## 按开场镜头投影到屏幕、按深度缩放。front = true 画在她前面（z ≥ HER_Z）的那些，false 画她身后的。
## 坐标是 1280×720 屏幕像素，帧号 real 逐帧、f 一拍二（和 shader 一样）。

const W := 1280.0
const H := 720.0
const STREET := 170.0
const HER_Z := 85.0
const P := 1000.0
const RIM := Color("eef0ff")
const INK := Color.BLACK

var front := false
var base := 572.0
var hx := 500.0
var real := 0.0
var f := 0.0
var _bubbles: Array = []
var _crowns: Array = []
var _crows: Array = []
var _seeds := {}


static func ramp(t: float, a: float, b: float) -> float:
	return clampf((t - a) / (b - a), 0.0, 1.0)


static func ease_out(k: float) -> float:
	return 1.0 - pow(1.0 - k, 3.0)


static func ease_in_out(k: float) -> float:
	return 4.0 * k * k * k if k < 0.5 else 1.0 - pow(-2.0 * k + 2.0, 3.0) / 2.0


static func keyed(t: float, keys: Array) -> float:
	for i in keys.size() - 1:
		var k0: Vector2 = keys[i]
		var k1: Vector2 = keys[i + 1]
		if t <= k1.x:
			return k0.y + (k1.y - k0.y) * clampf((t - k0.x) / (k1.x - k0.x), 0.0, 1.0)
	return (keys[keys.size() - 1] as Vector2).y


## 影子前沿的“摊开距离”（和 shader 里的 reach 一样）
static func reach(t: float) -> float:
	return keyed(t, [Vector2(0, 0), Vector2(4, 10), Vector2(12, 46), Vector2(16, HER_Z + 4.0), Vector2(24, 420), Vector2(32, 800), Vector2(40, 1100)])


## 前沿走到摊开距离 d 的那一帧（一拍二取偶数）
static func arrive_at(d: float) -> float:
	var t := 0.0
	while t < 60.0 and reach(t) < d:
		t += 0.5
	return ceilf(t / 2.0) * 2.0


## 开场镜头（和 shader 一样）：oy 透视中心高度，ty / tz 整个场景的平移
static func cam(b: float, t: float) -> Vector3:
	var k := ease_in_out(ramp(t, 0.0, 16.0))
	var drift := ramp(t, 16.0, 66.0)
	return Vector3(b + (150.0 - b) * k - 30.0 * drift, -150.0 * k - 10.0 * drift, 70.0 * ease_out(drift))


## 场景里的点 (x, y, z) → 屏幕位置和缩放
static func project(b: float, t: float, pt: Vector3) -> Array:
	var c := cam(b, t)
	var s := P / (P - (pt.z + c.z))
	var o := Vector2(640.0, c.x)
	return [o + (Vector2(pt.x, pt.y + c.y) - o) * s, s]


func setup(base_y: float, her_x: float) -> void:
	base = base_y
	hx = her_x
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261031
	_bubbles.clear()
	for i in 9:
		var born := 2.0 * floorf(1.0 + 6.0 * rng.randf())
		var a := rng.randf() * TAU
		var r := maxf(8.0, reach(born) * 0.8) * sqrt(rng.randf())
		var p := _on_street(cos(a) * r * 1.4, HER_Z + sin(a) * r * 0.7, false)
		p["born"] = born
		p["s"] = 5.0 + 7.0 * rng.randf()
		_bubbles.append(p)
	_crowns.clear()
	var cp := [_on_street(280.0, 125.0), _on_street(-220.0, 158.0)]
	for i in cp.size():
		cp[i]["born"] = arrive_at(cp[i].d)
		cp[i]["s"] = 1.6 + 0.2 * i
		cp[i]["seed"] = i
		_crowns.append(cp[i])
	_crows.clear()
	var kp := [_on_street(-245.0, 42.0), _on_street(260.0, 150.0)]
	var ks := [1.8, 1.6]
	var kd := [-1.0, 1.0]
	for i in kp.size():
		kp[i]["born"] = arrive_at(kp[i].d) + 2.0
		kp[i]["s"] = ks[i]
		kp[i]["dir"] = kd[i]
		kp[i]["seed"] = i
		_crows.append(kp[i])
	_seeds.clear()


## 地面上的点：x 按她脚下的相对位置给（夹在画面里），v 是离墙多远
func _on_street(dx: float, v: float, clamp_x := true) -> Dictionary:
	var x := clampf(hx + dx, 110.0, W - 110.0) if clamp_x else hx + dx
	return {"x": x, "z": v, "d": Vector2(x - hx, v - HER_Z).length()}


func _rand(key: String) -> float:
	if not _seeds.has(key):
		_seeds[key] = float(hash(key) & 0xffff) / 65535.0
	return _seeds[key]


func _draw() -> void:
	for b in _bubbles:
		var t: float = f - b.born
		if t >= 0.0 and t <= 9.0 and _mine(b.z):
			_board(b, func(): _bubble(t, b.s))
	for c in _crowns:
		var t: float = f - c.born
		if t >= 0.0 and t <= 14.0 and _mine(c.z):
			_board(c, func(): _crown(t, c.s, c.seed))
	for k in _crows:
		var t: float = f - k.born
		if t >= 0.0 and _mine(k.z):
			_board(k, func(): _emerge(t, k.s, k.dir, k.seed))
	draw_set_transform_matrix(Transform2D.IDENTITY)


func _mine(z: float) -> bool:
	return (z >= HER_Z) == front


func _board(p: Dictionary, body: Callable) -> void:
	var pr := project(base, real, Vector3(p.x, base, p.z))
	draw_set_transform(pr[0], 0.0, Vector2(pr[1], pr[1]))
	body.call()


# ---------------------------------------------------------------- 画法小工具（SVG 路径压成折线）

static func _quad(a: Vector2, c: Vector2, b: Vector2, n := 8) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(1, n + 1):
		var t := float(i) / float(n)
		out.append(a.lerp(c, t).lerp(c.lerp(b, t), t))
	return out


static func _cubic(a: Vector2, c1: Vector2, c2: Vector2, b: Vector2, n := 10) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(1, n + 1):
		var t := float(i) / float(n)
		var u := 1.0 - t
		out.append(a * u * u * u + c1 * 3.0 * u * u * t + c2 * 3.0 * u * t * t + b * t * t * t)
	return out


static func _circle(c: Vector2, r: float, n := 14) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n:
		var a := TAU * float(i) / float(n)
		out.append(c + Vector2(cos(a), sin(a)) * r)
	return out


func _poly(pts: PackedVector2Array, col: Color, off := Vector2.ZERO, k := 1.0) -> void:
	if pts.size() < 3:
		return
	var q := PackedVector2Array()
	for v in pts:
		q.append(v * k + off)
	if Geometry2D.triangulate_polygon(q).is_empty():
		draw_polyline(q + PackedVector2Array([q[0]]), col, 1.0, true)
		return
	draw_colored_polygon(q, col)


## 黑形状 + 顶上一道白边：先画一份往上挪的白，再盖黑
func _rimmed(pts: PackedVector2Array, k := 1.0, dy := -2.0, dx := -0.6) -> void:
	_poly(pts, RIM, Vector2(dx, dy) * k, k)
	_poly(pts, INK, Vector2.ZERO, k)


# ---------------------------------------------------------------- 墨泡：鼓起来、破掉，破的时候甩一圈墨点

func _bubble(t: float, s: float) -> void:
	if t < 6.0:
		var k := ease_out(t / 6.0)
		var rx := s * (0.6 + 0.4 * k)
		var ry := s * k * 1.1
		var dome := PackedVector2Array()
		for i in 13:
			var a := PI + PI * float(i) / 12.0
			dome.append(Vector2(cos(a) * rx, sin(a) * ry))
		_poly(dome, INK)
		draw_polyline(dome, RIM, 0.9, true)
		var hl := PackedVector2Array([Vector2(-rx * 0.55, -ry * 0.45)])
		hl.append_array(_quad(hl[0], Vector2(-rx * 0.35, -ry * 0.85), Vector2(rx * 0.05, -ry * 0.82)))
		draw_polyline(hl, Color.WHITE, 1.6, true)
		return
	var k2 := (t - 6.0) / 3.0
	for i in 6:
		var a := PI * (0.1 + 0.8 * (float(i) / 5.0))
		var r := s * (0.6 + 1.6 * k2)
		_rimmed(_circle(Vector2(-cos(a) * r, -sin(a) * r * 1.3 + 6.0 * k2 * k2), 1.6 * (1.0 - k2) + 0.3, 8), 1.0, -1.0)


# ---------------------------------------------------------------- 墨冠：一圈往外翻的墨壁，口沿一排尖，尖上甩出墨珠

func _crown(t: float, s: float, seed: int) -> void:
	var up := ease_out(t / 5.0) if t < 5.0 else 1.0 - pow((t - 5.0) / 9.0, 1.5)
	var hgt := 26.0 * up
	var flare := 10.0 + 16.0 * ramp(t, 0.0, 9.0)
	var bw := 10.0
	var n := 8
	var rim := PackedVector2Array()
	var tips: Array[Vector2] = []
	for i in n + 1:
		var u := float(i) / float(n)
		var x := -flare + 2.0 * flare * u
		var y := -hgt * (0.75 + 0.1 * sin(u * PI))
		if i % 2 == 1 or i == 0 or i == n:
			var L := hgt * (0.35 + 0.45 * _rand("k%d_%d" % [seed, i]))
			var tp := Vector2(x * 1.18, y - L)
			rim.append(tp)
			tips.append(tp)
		else:
			rim.append(Vector2(x, y))
	var wall := PackedVector2Array([Vector2(-bw, 0)])
	wall.append_array(_quad(Vector2(-bw, 0), Vector2(-flare * 0.75, -hgt * 0.3), rim[0]))
	for i in range(1, rim.size()):
		wall.append(rim[i])
	wall.append_array(_quad(rim[rim.size() - 1], Vector2(flare * 0.75, -hgt * 0.3), Vector2(bw, 0)))
	_rimmed(wall, s, -1.6)
	if hgt > 6.0:
		var hl := PackedVector2Array([Vector2(-flare * 0.45, -hgt * 0.65) * s])
		for v in _quad(Vector2(-flare * 0.45, -hgt * 0.65), Vector2(-flare * 0.5, -hgt * 0.35), Vector2(-bw * 0.5, -2.0)):
			hl.append(v * s)
		draw_polyline(hl, Color(RIM, 0.8), 1.3 * s, true)
	if t > 3.0:
		var fly := t - 4.0 if t > 4.0 else 0.0
		for p in tips:
			_rimmed(_circle(Vector2(p.x * (1.0 + 0.06 * fly), p.y - 3.0 * fly + 0.45 * fly * fly), 2.2 * (1.0 - ramp(t, 10.0, 14.0)) + 0.3, 8), s, -1.2)


# ---------------------------------------------------------------- 鸦式神：正面朝镜头，张翅往上冲

## 翅膀轮廓（翅长 1，肩在原点，平伸向右，y 朝下）：前缘一道弧，翅尖五根分开的飞羽，后缘一排短羽
const WING: Array[Vector2] = [
	Vector2(0, 0), Vector2(0.18, -0.09), Vector2(0.38, -0.12), Vector2(0.6, -0.1), Vector2(0.8, -0.05), Vector2(0.94, 0.02),
	Vector2(1.0, 0.07), Vector2(0.86, 0.08), Vector2(0.98, 0.16), Vector2(0.83, 0.16), Vector2(0.92, 0.25), Vector2(0.77, 0.23),
	Vector2(0.83, 0.32), Vector2(0.69, 0.28), Vector2(0.72, 0.37), Vector2(0.6, 0.31), Vector2(0.57, 0.38), Vector2(0.5, 0.32),
	Vector2(0.45, 0.39), Vector2(0.39, 0.32), Vector2(0.33, 0.38), Vector2(0.27, 0.31), Vector2(0.2, 0.35), Vector2(0.13, 0.27),
	Vector2(0.04, 0.26), Vector2(0, 0.18)]


static func _wing(alpha: float, span: float, mirror: float) -> PackedVector2Array:
	var ca := cos(alpha)
	var sa := sin(alpha)
	var out := PackedVector2Array()
	for w in WING:
		out.append(Vector2(mirror * (5.0 + span * (w.x * ca + w.y * sa)), -8.0 + span * (-w.x * sa + w.y * ca)))
	return out


## 身子：头、扇形尾（喙在 _crow 里另画）
static func _crow_body() -> PackedVector2Array:
	var p := PackedVector2Array([Vector2(0, -28)])
	p.append_array(_cubic(Vector2(0, -28), Vector2(5, -28), Vector2(7, -23), Vector2(6, -18), 5))
	p.append_array(_cubic(Vector2(6, -18), Vector2(9, -13), Vector2(10, 0), Vector2(7, 10), 6))
	p.append_array(PackedVector2Array([Vector2(12, 27), Vector2(4, 22), Vector2(0, 30), Vector2(-4, 22), Vector2(-12, 27), Vector2(-7, 10)]))
	p.append_array(_cubic(Vector2(-7, 10), Vector2(-10, 0), Vector2(-9, -13), Vector2(-6, -18), 6))
	p.append_array(_cubic(Vector2(-6, -18), Vector2(-7, -23), Vector2(-5, -28), Vector2(0, -28), 5))
	return p


func _crow(at: Vector2, wing: float, span: float, s: float) -> void:
	var parts := [_wing(wing, span, 1.0), _wing(wing, span, -1.0), _crow_body()]
	for pts in parts:
		_poly(pts, RIM, (at + Vector2(-0.7, -2.2)) * s, s)
	for pts in parts:
		_poly(pts, INK, at * s, s)
	var beak := PackedVector2Array([Vector2(-2.4, -20), Vector2(0, -9), Vector2(2.4, -20)])
	_poly(beak, Color(0.06, 0.06, 0.08), at * s, s)
	# 眼睛：两道斜的白细缝
	draw_line((at + Vector2(-5, -23.5)) * s, (at + Vector2(-2.2, -22)) * s, Color.WHITE, 0.9 * s, true)
	draw_line((at + Vector2(5, -23.5)) * s, (at + Vector2(2.2, -22)) * s, Color.WHITE, 0.9 * s, true)
	draw_line((at + Vector2(-2.2, -19)) * s, (at + Vector2(0, -10)) * s, Color(RIM, 0.7), 0.6 * s, true)


static func _body_y(t: float) -> float:
	if t < 6.0:
		return 34.0
	if t < 14.0:
		return keyed(t, [Vector2(6, 34), Vector2(14, -34)])
	return -34.0 - 3.4 * (t - 14.0) - 0.16 * (t - 14.0) * (t - 14.0)


## 一只鸦从墨里钻出来：鼓包 → 露头拖墨丝 → 张翅往上冲，身上往下滴墨。t 是从鼓包开始的帧数
func _emerge(t: float, s: float, dir: float, seed: int) -> void:
	var body_y := _body_y(t)
	var sway := dir * (6.0 * sin((t - 14.0) * 0.18) + 0.8 * (t - 14.0) if t > 14.0 else 0.0)
	var open := ramp(t, 12.0, 18.0)
	var span := 16.0 + 40.0 * open
	var wing := 1.35 - 0.2 * open if open < 1.0 else 0.25 + 0.95 * cos((t - 18.0) * 0.55)
	var dome := ease_out(ramp(t, 0.0, 5.0)) * (1.0 - ramp(t, 7.0, 10.0)) if t < 10.0 else 0.0
	if dome > 0.0:
		var d := PackedVector2Array()
		for i in 13:
			var a := PI + PI * float(i) / 12.0
			d.append(Vector2(cos(a) * 22.0 * dome, sin(a) * 16.0 * dome))
		_poly(d, INK, Vector2.ZERO, s)
		var ds := PackedVector2Array()
		for v in d:
			ds.append(v * s)
		draw_polyline(ds, RIM, 1.0 * s, true)
		var hl := PackedVector2Array([Vector2(-12 * dome, -9 * dome) * s])
		for v in _quad(Vector2(-12 * dome, -9 * dome), Vector2(-6 * dome, -15 * dome), Vector2(3 * dome, -15 * dome)):
			hl.append(v * s)
		draw_polyline(hl, Color.WHITE, 2.0 * s, true)
	# 墨丝：从墨面拉到它身上，越拉越细，断开
	if t >= 7.0 and t < 18.0:
		var k := ramp(t, 7.0, 18.0)
		var wb := 16.0 - 12.0 * k
		var wt := 7.0 - 5.0 * k
		var top := minf(0.0, body_y + 26.0)
		var mid := top * 0.5
		var pinch := 1.5 + 4.0 * (1.0 - k)
		var st := PackedVector2Array([Vector2(-wb, 0)])
		st.append_array(_cubic(Vector2(-wb, 0), Vector2(-pinch, mid * 0.6), Vector2(-pinch, mid * 1.4), Vector2(-wt, top), 6))
		st.append(Vector2(wt, top))
		st.append_array(_cubic(Vector2(wt, top), Vector2(pinch, mid * 1.4), Vector2(pinch, mid * 0.6), Vector2(wb, 0), 6))
		_rimmed(st, s, -1.2)
	_crow(Vector2(sway, body_y), wing, span, s)
	# 往下滴的墨：从它身上掉下来，落回墨面
	for i in 4:
		var t0 := 13.0 + float(i) * 3.0
		var dt := t - t0
		if dt < 0.0:
			continue
		var y := _body_y(t0) + 22.0 + 0.9 * dt * dt
		if y > 0.0:
			continue
		var x := (_rand("dx%d_%d" % [seed, i]) - 0.5) * 30.0 + dir * (0.8 * (t0 - 14.0) if t0 > 14.0 else 0.0)
		var dp := PackedVector2Array([Vector2(x, y - 7)])
		dp.append_array(_quad(Vector2(x, y - 7), Vector2(x + 3, y - 1), Vector2(x, y + 2.5), 4))
		dp.append_array(_quad(Vector2(x, y + 2.5), Vector2(x - 3, y - 1), Vector2(x, y - 7), 4))
		_rimmed(dp, s, -1.0)
