extends Node3D
## 《斩钟》进选章 · 传动链版分镜预演（只出静帧，不进正式流程）
## 用法：ZZ_PREVIS=<输出目录> ZZ_PREVIS_SET=gear 运行首页场景；ZZ_PREVIS_ONLY=<名字前缀> 只渲染部分镜头。
## 流程照用 zz_select 现有的「钟体展开」（斩 → 展开 → 穿环 → 落钟 → 钟响 → 揭示 → 章名），按镜头时刻把它停住，
## 在上面加一条传动链（全部齿轮按真实齿数、模数摆位，转角按齿比算，所以每一对都咬得上）：
##   发条鼓（唯一动力）→ 走时轮系 4 级 → 擒纵轮 → 擒纵叉 → 摆轮游丝（整条轮系跟着擒纵一格一格走）
##   发条鼓 → 四个取力轮 → 四根长轴 → 四个小齿轮 → 表盘四圈背面的内齿圈（各圈因此转动）
##   钟落进钟楼锁死 → 钟楼拱里的三只齿轮 → 塔脚万向节 → 台下主轴 → 中景两扇门轴冠轮（推门）/ 近景齿条（滑入）
##   → 灯链从钟楼脚下沿街往镜头传。

const DEG := PI / 180.0
const TX := 1.353                                  # 表盘贴图像素 → 世界单位（表盘所在深度）
const RING_IN := [292.0, 345.0, 432.0, 556.0]      # 第 1～4 圈内沿（贴图像素）
const RING_Z := [-260.0, -90.0, 90.0, 260.0]       # 第 1～4 圈展开后的前后位置（同 zz_select.RING_Z[1..4]）
const BZ := -1650.0                                # 发条鼓所在深度（rig 局部）
const W := 1920.0
const H := 1080.0

const GEAR_SH := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;
uniform vec3 c_hi = vec3(1.0, 0.86, 0.56);
uniform vec3 c_mid = vec3(0.64, 0.47, 0.25);
uniform vec3 c_lo = vec3(0.16, 0.10, 0.06);
uniform vec3 c_edge = vec3(1.0, 0.95, 0.82);
uniform vec3 c_rim = vec3(0.62, 0.68, 1.0);
uniform float half_t = 8.0;
uniform float fin = 1.0;
uniform float dim = 1.0;
uniform float fog_d = 14000.0;
uniform float fog_near = 2600.0;
uniform vec3 fog_col = vec3(0.012, 0.012, 0.03);
varying vec3 lp;
varying vec3 ln;
varying vec3 cv;
void vertex() {
	lp = VERTEX;
	ln = NORMAL;
	cv = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
}
void fragment() {
	vec3 L = normalize((VIEW_MATRIX * vec4(normalize(vec3(-0.5, 0.75, 0.45)), 0.0)).xyz);
	vec3 n = normalize(NORMAL);
	float nl = dot(n, L);
	float b = smoothstep(-0.12, 0.0, nl) + smoothstep(0.42, 0.55, nl);
	vec3 col = mix(c_lo, c_mid, clamp(b, 0.0, 1.0));
	col = mix(col, c_hi, clamp(b - 1.0, 0.0, 1.0));
	if (abs(ln.z) > 0.85) {
		// 正反两面：圆纹打磨 + 随灯位不动的「领结」反光
		vec2 d = VERTEX.xy - cv.xy;
		float ang = atan(d.y, d.x);
		float bow = pow(abs(cos(ang - 0.95)), 14.0);
		float r = length(lp.xy);
		col *= (0.9 + 0.1 * sin(r * 0.55)) * mix(1.0, 0.92, fin);
		col = mix(col, c_hi * 1.15, bow * 0.55 * fin);
	} else {
		// 侧壁：暗，靠近两面的倒角一圈亮线
		float e = smoothstep(half_t - 2.2, half_t - 0.3, abs(lp.z));
		col = mix(col * 0.5, c_edge, e);
	}
	float fr = pow(1.0 - abs(dot(n, normalize(-VERTEX))), 3.0);
	col += c_rim * fr * 0.28;
	float dep = -VERTEX.z;
	float f = exp(-max(dep - fog_near, 0.0) / fog_d);
	ALBEDO = mix(fog_col, col * dim, f);
}
"""

var T: Node
var C: Node
var S: Node
var cam: Camera3D
var out := ""
var shot: Dictionary = {}
var tv := 0.0
var gsh: Shader
var mats := {}

var mov: Node3D
var gears: Array = []          # 机芯里的每一只轮
var gm := {}                   # id → 轮
var arbors: Array = []         # [{mi, ids, r}]
var anchor: Dictionary = {}
var balance: Dictionary = {}

var stage_sh: Shader
var tw: Node3D                 # 钟楼拱里 + 台下的机械（世界坐标）
var tgears: Array = []
var deck: MeshInstance3D
var lay := {}                  # kind → zz_select 的景片
var rack: Node3D
var rack_x0 := 0.0
var door_crowns: Array = []


func _ready() -> void:
	T = get_parent()
	C = T.clock
	cam = C.camera
	process_priority = 1000
	out = OS.get_environment("ZZ_PREVIS")
	DirAccess.make_dir_recursive_absolute(out)
	gsh = Shader.new()
	gsh.code = GEAR_SH
	stage_sh = load("res://scripts/ui/yg_zhanzhong/lab/zz_previs_stage.gdshader")
	_run.call_deferred()


# ================================================================ 材质与网格
func _mat(kind: String, half_t: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = gsh
	m.set_shader_parameter("half_t", half_t)
	match kind:
		"steel":
			m.set_shader_parameter("c_hi", Color(0.93, 0.95, 1.0))
			m.set_shader_parameter("c_mid", Color(0.52, 0.55, 0.62))
			m.set_shader_parameter("c_lo", Color(0.09, 0.1, 0.13))
			m.set_shader_parameter("c_edge", Color(1.0, 1.0, 1.0))
		"blue":
			# 烤蓝钢（游丝、发条）：冷蓝而不是紫
			m.set_shader_parameter("c_hi", Color(0.55, 0.72, 1.0))
			m.set_shader_parameter("c_mid", Color(0.16, 0.26, 0.55))
			m.set_shader_parameter("c_lo", Color(0.03, 0.05, 0.12))
			m.set_shader_parameter("c_edge", Color(0.8, 0.9, 1.0))
		"ruby":
			m.set_shader_parameter("c_hi", Color(1.0, 0.45, 0.42))
			m.set_shader_parameter("c_mid", Color(0.62, 0.06, 0.08))
			m.set_shader_parameter("c_lo", Color(0.18, 0.0, 0.02))
			m.set_shader_parameter("c_edge", Color(1.0, 0.7, 0.65))
		"dark":
			m.set_shader_parameter("c_hi", Color(0.2, 0.22, 0.28))
			m.set_shader_parameter("c_mid", Color(0.08, 0.09, 0.12))
			m.set_shader_parameter("c_lo", Color(0.03, 0.035, 0.05))
			m.set_shader_parameter("c_edge", Color(0.45, 0.5, 0.6))
			m.set_shader_parameter("fin", 0.0)
	return m


class MB:
	var V := PackedVector3Array()
	var N := PackedVector3Array()
	var I := PackedInt32Array()

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
		var i := V.size()
		V.append_array([a, b, c, d])
		N.append_array([n, n, n, n])
		I.append_array([i, i + 1, i + 2, i, i + 2, i + 3])

	func mesh() -> ArrayMesh:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = V
		arr[Mesh.ARRAY_NORMAL] = N
		arr[Mesh.ARRAY_INDEX] = I
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return am


## 一条带：A、B 两条边（同点数），挤出厚度 t；正反两面 + 两条边的侧壁
static func _strip(mb: MB, A: PackedVector2Array, B: PackedVector2Array, closed: bool, t: float, wall_a := true, wall_b := true, caps := false, z0 := 0.0) -> void:
	var n := A.size()
	var h := t * 0.5
	var cnt := n if closed else n - 1
	for i in cnt:
		var j := (i + 1) % n
		mb.quad(Vector3(A[i].x, A[i].y, z0 + h), Vector3(B[i].x, B[i].y, z0 + h), Vector3(B[j].x, B[j].y, z0 + h), Vector3(A[j].x, A[j].y, z0 + h), Vector3(0, 0, 1))
		mb.quad(Vector3(A[i].x, A[i].y, z0 - h), Vector3(B[i].x, B[i].y, z0 - h), Vector3(B[j].x, B[j].y, z0 - h), Vector3(A[j].x, A[j].y, z0 - h), Vector3(0, 0, -1))
		for side in 2:
			if (side == 0 and not wall_a) or (side == 1 and not wall_b):
				continue
			var P := A if side == 0 else B
			var Q := B if side == 0 else A
			var e := P[j] - P[i]
			var nn := Vector2(e.y, -e.x).normalized()
			if nn.dot(P[i] - Q[i]) < 0.0:
				nn = -nn
			mb.quad(Vector3(P[i].x, P[i].y, z0 + h), Vector3(P[j].x, P[j].y, z0 + h), Vector3(P[j].x, P[j].y, z0 - h), Vector3(P[i].x, P[i].y, z0 - h), Vector3(nn.x, nn.y, 0))
	if caps and not closed:
		for k: int in [0, n - 1]:
			var e2 := B[k] - A[k]
			var nn2 := Vector2(e2.y, -e2.x).normalized()
			var other := A[1] if k == 0 else A[n - 2]
			if nn2.dot(A[k] - other) < 0.0:
				nn2 = -nn2
			mb.quad(Vector3(A[k].x, A[k].y, z0 + h), Vector3(B[k].x, B[k].y, z0 + h), Vector3(B[k].x, B[k].y, z0 - h), Vector3(A[k].x, A[k].y, z0 - h), Vector3(nn2.x, nn2.y, 0))


## 齿形：钟表轮的圆头尖拱齿；u = 在一个齿距里的位置（0 = 齿中心）
static func _tooth(u: float) -> float:
	var d := absf(wrapf(u, -0.5, 0.5))
	if d < 0.1:
		return 1.0
	if d < 0.3:
		return 0.5 + 0.5 * cos(PI * (d - 0.1) / 0.2)
	return 0.0


static func _ratchet(u: float) -> float:
	var x := fposmod(u + 0.08, 1.0)
	if x < 0.78:
		return pow(x / 0.78, 1.8)
	return clampf(1.0 - (x - 0.78) / 0.05, 0.0, 1.0)


static func _circle(r: float, n: int) -> PackedVector2Array:
	var P := PackedVector2Array()
	for i in n:
		var a := TAU * i / n
		P.append(Vector2(cos(a), sin(a)) * r)
	return P


## 一只轮的网格：kind = wheel / pinion / escape / ring / barrel / crown_flat
static func gear_mesh(N: int, r: float, t: float, kind: String, spokes := 5, bend := 0.2) -> ArrayMesh:
	var mb := MB.new()
	var m := 2.0 * r / N
	var spt := 12 if N < 40 else 8
	var ns := N * spt
	var prof := PackedVector2Array()
	for i in ns:
		var a := TAU * i / ns
		var u := float(i) / spt
		var rr: float
		match kind:
			"escape":
				rr = r - m * 0.55 + m * 0.95 * _ratchet(u)
			"ring":
				rr = r + 1.25 * m - 2.25 * m * _tooth(u)
			_:
				rr = r - 1.25 * m + 2.25 * m * _tooth(u)
		prof.append(Vector2(cos(a), sin(a)) * rr)
	if kind == "ring":
		_strip(mb, prof, _circle(r + 1.25 * m + maxf(14.0, m * 2.2), ns), true, t)
		return mb.mesh()
	var root := r - 1.25 * m
	if kind == "pinion":
		_strip(mb, _circle(maxf(4.0, r * 0.18), ns), prof, true, t)
		return mb.mesh()
	var rim_in := root - maxf(2.4 * m, r * 0.07)
	if kind == "escape":
		rim_in = root - maxf(m * 0.5, 9.0)
	var bore := maxf(5.0, r * 0.04)
	var hub := maxf(bore + 10.0, r * 0.17)
	_strip(mb, _circle(rim_in, ns), prof, true, t)
	_strip(mb, _circle(bore, 48), _circle(hub, 48), true, t * 1.25)
	# 弯辐：从轮毂到轮缘，略带 S 形
	for k in spokes:
		var th := TAU * k / spokes
		var A := PackedVector2Array()
		var B := PackedVector2Array()
		var steps := 14
		var pts: Array = []
		for s in steps + 1:
			var f := float(s) / steps
			var rad := lerpf(hub - 2.0, rim_in + 2.0, f)
			var ang := th + bend * sin(PI * f) - bend * 0.5 * f
			pts.append(Vector2(cos(ang), sin(ang)) * rad)
		for s in steps + 1:
			var f := float(s) / steps
			var p: Vector2 = pts[s]
			var tg: Vector2 = (pts[mini(s + 1, steps)] - pts[maxi(s - 1, 0)]).normalized()
			var nrm := Vector2(-tg.y, tg.x)
			var w := lerpf(r * 0.085, r * 0.045, f) * (1.0 + 0.6 * pow(1.0 - absf(f - 0.5) * 2.0, 6.0) * 0.0)
			A.append(p + nrm * w * 0.5)
			B.append(p - nrm * w * 0.5)
		_strip(mb, A, B, false, t * 0.8)
	return mb.mesh()


static func spiral_mesh(r0: float, r1: float, turns: float, band: float, t: float) -> ArrayMesh:
	var mb := MB.new()
	var n := int(turns * 120)
	var A := PackedVector2Array()
	var B := PackedVector2Array()
	for i in n:
		var f := float(i) / (n - 1)
		var a := TAU * turns * f
		var rr := lerpf(r0, r1, f)
		A.append(Vector2(cos(a), sin(a)) * rr)
		B.append(Vector2(cos(a), sin(a)) * (rr + band))
	_strip(mb, A, B, false, t, true, true, true)
	return mb.mesh()


## 粗线段（带厚度的折线），做擒纵叉、支架
static func bar_mesh(pts: Array, w0: float, w1: float, t: float) -> ArrayMesh:
	var mb := MB.new()
	var A := PackedVector2Array()
	var B := PackedVector2Array()
	var n := pts.size()
	for s in n:
		var p: Vector2 = pts[s]
		var tg: Vector2 = (pts[mini(s + 1, n - 1)] - pts[maxi(s - 1, 0)]).normalized()
		var nrm := Vector2(-tg.y, tg.x)
		var w := lerpf(w0, w1, float(s) / (n - 1))
		A.append(p + nrm * w * 0.5)
		B.append(p - nrm * w * 0.5)
	_strip(mb, A, B, false, t, true, true, true)
	return mb.mesh()


## 冠轮（齿朝轴向）：用来把一根轴的转动拐 90° 交给另一根轴
static func crown_mesh(N: int, r: float, h: float, wall: float) -> ArrayMesh:
	var mb := MB.new()
	var m := 2.0 * r / N
	var ns := N * 10
	var th := 1.6 * m
	for i in ns:
		var a0 := TAU * i / ns
		var a1 := TAU * (i + 1) / ns
		var z0 := h + th * _tooth(float(i) / 10.0)
		var z1 := h + th * _tooth(float(i + 1) / 10.0)
		for side in 2:
			var rr := r + (wall * 0.5 if side == 0 else -wall * 0.5)
			var p0 := Vector3(cos(a0) * rr, sin(a0) * rr, 0.0)
			var p1 := Vector3(cos(a1) * rr, sin(a1) * rr, 0.0)
			var nn := Vector3(cos(a0), sin(a0), 0.0) * (1.0 if side == 0 else -1.0)
			mb.quad(p0, p1, Vector3(p1.x, p1.y, z1), Vector3(p0.x, p0.y, z0), nn)
		var o0 := Vector2(cos(a0), sin(a0))
		var o1 := Vector2(cos(a1), sin(a1))
		var ri := r - wall * 0.5
		var ro := r + wall * 0.5
		mb.quad(Vector3(o0.x * ri, o0.y * ri, z0), Vector3(o0.x * ro, o0.y * ro, z0), Vector3(o1.x * ro, o1.y * ro, z1), Vector3(o1.x * ri, o1.y * ri, z1), Vector3(0, 0, 1))
	# 底盘
	var mb2 := mb
	_strip(mb2, _circle(r * 0.16, 64), _circle(r + wall * 0.5, 64), true, wall, true, true, false, wall * 0.5)
	return mb.mesh()


static func rack_mesh(rl: float, m: float, t: float, depth: float) -> ArrayMesh:
	var mb := MB.new()
	var n := int(rl / (PI * m))
	var A := PackedVector2Array()
	var B := PackedVector2Array()
	var spt := 10
	for i in n * spt + 1:
		var u := float(i) / spt
		var x := -rl * 0.5 + u * PI * m
		A.append(Vector2(x, 0.0))
		B.append(Vector2(x, -depth - 2.25 * m * _tooth(u)))
	_strip(mb, A, B, false, t, true, true, true)
	return mb.mesh()


func _mi(mesh: Mesh, mat: Material, parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 8192.0
	parent.add_child(mi)
	return mi


func _cyl(r: float, mat: Material, parent: Node3D) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = 1.0
	cm.radial_segments = 20
	cm.rings = 1
	return _mi(cm, mat, parent)


## 把单位长的圆柱摆成 a → b 的一根轴
static func _rod(mi: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var L := d.length()
	if L < 0.01:
		mi.visible = false
		return
	mi.visible = true
	var y := d / L
	var x := y.cross(Vector3.BACK if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	mi.transform = Transform3D(Basis(x, y * L, z), (a + b) * 0.5)


# ================================================================ 机芯：摆位与齿比
func _add(id: String, N: int, r: float, kind: String, p: Vector2, ze: float, t: float, mat: String, extra := {}) -> Dictionary:
	var node := Node3D.new()
	mov.add_child(node)
	var mesh: Mesh = gear_mesh(N, r, t, kind, int(extra.get("spokes", 5)), float(extra.get("bend", 0.2)))
	_mi(mesh, _mat(mat, t * 0.5), node)
	var g := {"id": id, "N": N, "r": r, "kind": kind, "p": p, "ze": ze, "node": node, "k": 1.0, "ph": 0.0}
	gears.append(g)
	gm[id] = g
	return g


func _mesh_to(child: Dictionary, parent: Dictionary) -> void:
	var al := (Vector2(child["p"]) - Vector2(parent["p"])).angle()
	var q := float(parent["N"]) / float(child["N"])
	child["k"] = -q * float(parent["k"])
	child["ph"] = al + PI + PI / float(child["N"]) - q * (float(parent["ph"]) - al)


func _arbor_to(child: Dictionary, parent: Dictionary, off := 0.0) -> void:
	child["k"] = parent["k"]
	child["ph"] = float(parent["ph"]) + off


func _ring_from(ring: Dictionary, pin: Dictionary) -> void:
	var al := (Vector2(pin["p"]) - Vector2(ring["p"])).angle()
	var q := float(pin["N"]) / float(ring["N"])
	ring["k"] = q * float(pin["k"])
	ring["ph"] = al + PI / float(ring["N"]) + q * (float(pin["ph"]) - al)


## 在父轮周围找一个点：离父轮中心 d，离表盘中心尽量接近 rad、方位尽量接近 ang
func _seek(par: Vector2, d: float, rad: float, ang: float) -> Vector2:
	var best := par
	var bc := 1e18
	for i in 720:
		var a := TAU * i / 720.0
		var c := par + Vector2(cos(a), sin(a)) * d
		var cost := pow((c.length() - rad) / 100.0, 2.0) + pow(angle_difference(c.angle(), ang) * 3.0, 2.0)
		if cost < bc:
			bc = cost
			best = c
	return best


func _build_movement() -> void:
	mov = Node3D.new()
	S.rig.add_child(mov)
	# 发条鼓：唯一的动力。深鼓，齿通身，前面敞开看得到里面卷着的发条
	var B := _add("B", 90, 324.0, "barrel", Vector2.ZERO, BZ, 240.0, "brass", {"spokes": 6, "bend": 0.0})
	var spring := Node3D.new()
	(B["node"] as Node3D).add_child(spring)
	_mi(spiral_mesh(58.0, 268.0, 9.0, 5.0, 200.0), _mat("blue", 100.0), spring)
	# 鼓里的发条是从鼓底下拉出来的，鼓的正面这里做成镂空：把通身齿换成「齿圈 + 后盖」
	(B["node"] as Node3D).get_child(0).queue_free()
	var bm := MB.new()
	var m := 7.2
	var ns := 900
	var prof := PackedVector2Array()
	for i in ns:
		var a := TAU * i / ns
		prof.append(Vector2(cos(a), sin(a)) * (324.0 - 1.25 * m + 2.25 * m * _tooth(float(i) / 10.0)))
	_strip(bm, _circle(286.0, ns), prof, true, 240.0)
	_strip(bm, _circle(22.0, 120), _circle(292.0, 120), true, 10.0, true, true, false, -118.0)
	_mi(bm.mesh(), _mat("brass", 120.0), B["node"])
	# 鼓前面的鼓桥（钢，三臂）压着发条轴
	_mi(bar_mesh([Vector2(-300, -40), Vector2(-120, -10), Vector2(0, 0), Vector2(120, 10), Vector2(300, 40)], 46.0, 46.0, 10.0), _mat("steel", 5.0), B["node"]).position.z = 128.0

	# 走时轮系：一路螺旋往前（往镜头这边），每级「小齿轮 + 大轮」同轴
	var p1 := _add("p1", 12, 43.2, "pinion", Vector2.from_angle(200.0 * DEG) * 367.2, BZ - 90.0, 44.0, "steel")
	_mesh_to(p1, B)
	var W1 := _add("W1", 84, 210.0, "wheel", p1["p"], -1390.0, 18.0, "brass", {"spokes": 5})
	_arbor_to(W1, p1)
	var p2 := _add("p2", 10, 25.0, "pinion", _seek(W1["p"], 235.0, 430.0, 250.0 * DEG), -1390.0, 34.0, "steel")
	_mesh_to(p2, W1)
	var W2 := _add("W2", 80, 160.0, "wheel", p2["p"], -1150.0, 16.0, "brass", {"spokes": 5})
	_arbor_to(W2, p2)
	var p3 := _add("p3", 10, 20.0, "pinion", _seek(W2["p"], 180.0, 440.0, 292.0 * DEG), -1150.0, 30.0, "steel")
	_mesh_to(p3, W2)
	var W3 := _add("W3", 72, 115.2, "wheel", p3["p"], -930.0, 14.0, "brass", {"spokes": 4})
	_arbor_to(W3, p3)
	var p4 := _add("p4", 8, 12.8, "pinion", _seek(W3["p"], 128.0, 450.0, 330.0 * DEG), -930.0, 26.0, "steel")
	_mesh_to(p4, W3)
	var E := _add("E", 15, 95.0, "escape", p4["p"], -770.0, 10.0, "steel", {"spokes": 5, "bend": 0.35})
	_arbor_to(E, p4)
	# 擒纵叉：叉轴离擒纵轮 1.42 倍半径，两只叉瓦（红宝石）卡在轮齿上，叉尾伸向摆轮
	var Ep: Vector2 = E["p"]
	var pa := _seek(Ep, 95.0 * 1.45, 560.0, 352.0 * DEG)
	var to_e := (Ep - pa).normalized()
	var an := Node3D.new()
	mov.add_child(an)
	var arms: Array = []
	for sgn: float in [-1.0, 1.0]:
		var q: Vector2 = Ep + (pa - Ep).normalized().rotated(sgn * 0.62) * 101.0 - pa
		var mid := q * 0.5 + Vector2(-q.y, q.x).normalized() * sgn * -18.0
		arms.append([Vector2.ZERO, mid, q])
		_mi(bar_mesh([Vector2.ZERO, mid, q], 16.0, 9.0, 9.0), _mat("steel", 4.5), an)
		var st := _mi(bar_mesh([q - to_e.rotated(sgn * 0.62) * 4.0, q + to_e.rotated(sgn * 0.62) * 14.0], 8.0, 8.0, 10.0), _mat("ruby", 5.0), an)
		st.position.z = 0.5
	var tail := -to_e * 150.0
	_mi(bar_mesh([Vector2.ZERO, tail * 0.55, tail], 14.0, 8.0, 9.0), _mat("steel", 4.5), an)
	_mi(bar_mesh([tail + to_e.orthogonal() * 12.0 - to_e * 14.0, tail + to_e.orthogonal() * 12.0, tail], 5.0, 5.0, 9.0), _mat("steel", 4.5), an)
	_mi(bar_mesh([tail - to_e.orthogonal() * 12.0 - to_e * 14.0, tail - to_e.orthogonal() * 12.0, tail], 5.0, 5.0, 9.0), _mat("steel", 4.5), an)
	anchor = {"node": an, "p": pa, "ze": -770.0, "base": to_e.angle()}
	# 摆轮 + 游丝（烤蓝），轮缘一圈调时螺丝
	var bp := pa - to_e * (150.0 + 16.0)
	var bn := Node3D.new()
	mov.add_child(bn)
	_mi(gear_mesh(3, 112.0, 12.0, "pinion"), _mat("brass", 6.0), bn).visible = false
	var bmb := MB.new()
	_strip(bmb, _circle(100.0, 160), _circle(114.0, 160), true, 12.0)
	_strip(bmb, _circle(5.0, 32), _circle(20.0, 32), true, 16.0)
	for k in 3:
		var th := TAU * k / 3.0 + 0.3
		var pts: Array = []
		for s in 9:
			var f := s / 8.0
			pts.append(Vector2.from_angle(th + 0.25 * sin(PI * f)) * lerpf(18.0, 102.0, f))
		var A2 := PackedVector2Array()
		var B2 := PackedVector2Array()
		for s in 9:
			var p: Vector2 = pts[s]
			var tg: Vector2 = (pts[mini(s + 1, 8)] - pts[maxi(s - 1, 0)]).normalized()
			A2.append(p + tg.orthogonal() * 5.0)
			B2.append(p - tg.orthogonal() * 5.0)
		_strip(bmb, A2, B2, false, 9.0)
	_mi(bmb.mesh(), _mat("brass", 6.0), bn)
	for k in 16:
		var sc := _cyl(5.5, _mat("brass", 1000.0), bn)
		var dir := Vector2.from_angle(TAU * k / 16.0)
		_rod(sc, Vector3(dir.x, dir.y, 0.0) * 112.0, Vector3(dir.x, dir.y, 0.0) * 126.0)
	var hs := _mi(spiral_mesh(10.0, 74.0, 11.0, 1.6, 4.0), _mat("blue", 2.0), bn)
	hs.position.z = 14.0
	balance = {"node": bn, "p": bp, "ze": -712.0}

	# 四个取力轮：发条鼓直接带四根长轴，轴头小齿轮咬着表盘四圈背面的内齿圈
	var bands := [-90.0, -30.0, 30.0, 90.0]
	var psi := [25.0, 115.0, 300.0, 160.0]
	for i in 4:
		var edge: float = RING_IN[i] * TX
		var Nt: int = [9, 30, 62, 108][i]
		var Np := 14
		var rt := Nt * m * 0.5
		var Nr := int(round(2.0 * (edge - 2.0) / 5.0))
		var mr := 2.0 * (324.0 + rt) / float(Nr - Np)
		var Rr := Nr * mr * 0.5
		var rp := Np * mr * 0.5
		var cpos := Vector2.from_angle(psi[i] * DEG) * (324.0 + rt)
		var tk := _add("t%d" % i, Nt, rt, "pinion" if Nt < 16 else "wheel", cpos, BZ + bands[i], 16.0 if Nt >= 16 else 40.0, "brass" if Nt >= 16 else "steel", {"spokes": 6 if Nt > 60 else 5})
		_mesh_to(tk, B)
		var rpn := _add("rp%d" % i, Np, rp, "pinion", cpos, RING_Z[i] - 40.0, 30.0, "steel")
		_arbor_to(rpn, tk)
		var rg := _add("rg%d" % i, Nr, Rr, "ring", Vector2.ZERO, RING_Z[i] - 40.0, 12.0, "brass")
		_ring_from(rg, rpn)
		arbors.append({"mi": _cyl(7.0, _mat("steel", 1000.0), mov), "ids": ["t%d" % i, "rp%d" % i]})
	for pair: Array in [["B"], ["p1", "W1"], ["p2", "W2"], ["p3", "W3"], ["p4", "E"]]:
		arbors.append({"mi": _cyl(6.0 if pair[0] != "B" else 16.0, _mat("steel", 1000.0), mov), "ids": pair})
	arbors.append({"mi": _cyl(4.5, _mat("steel", 1000.0), mov), "node": "anchor"})
	arbors.append({"mi": _cyl(4.5, _mat("steel", 1000.0), mov), "node": "balance"})


## 展开量（和 zz_select._rig_seq 同一条曲线）
func _ex(t: float) -> float:
	var ex: float = S._back(S._seg(t, S.T_SWAP, 0.4), 1.3) * (1.0 - S._in_out(S._seg(t, 0.98, 0.18)))
	return ex


func _z_of(ze: float, ex: float) -> float:
	return lerpf(-60.0 - 0.05 * absf(ze), ze, ex)


## 整条轮系跟着擒纵一格一格走（时间倒流：反着走）
func _movement_update(t: float) -> void:
	var ex := _ex(t)
	mov.visible = t >= S.T_SWAP and t < S.T_LAND + 0.02
	var E: Dictionary = gm["E"]
	var n := 26.0 * maxf(t - S.T_SWAP, 0.0) + 3.3
	var stp := floorf(n) + smoothstep(0.55, 1.0, fposmod(n, 1.0))
	var thE := -stp * TAU / 15.0
	var Th := (thE - float(E["ph"])) / float(E["k"])
	for g: Dictionary in gears:
		var node: Node3D = g["node"]
		var p: Vector2 = g["p"]
		var ze: float = g["ze"]
		var z := _z_of(ze, ex)
		if String(g["id"]).begins_with("rg"):
			z = float(ze + 40.0) * ex - 40.0
		elif String(g["id"]).begins_with("rp"):
			z = float(ze + 40.0) * ex - 40.0
		node.position = Vector3(p.x, p.y, z)
		node.rotation = Vector3(0, 0, float(g["k"]) * Th + float(g["ph"]))
	var beat := sin(n * PI)
	var an: Node3D = anchor["node"]
	var ap: Vector2 = anchor["p"]
	an.position = Vector3(ap.x, ap.y, _z_of(anchor["ze"], ex))
	an.rotation = Vector3(0, 0, beat * 0.07)
	var bn: Node3D = balance["node"]
	var bp: Vector2 = balance["p"]
	bn.position = Vector3(bp.x, bp.y, _z_of(balance["ze"], ex))
	bn.rotation = Vector3(0, 0, -beat * 1.9)
	for A: Dictionary in arbors:
		var mi: MeshInstance3D = A["mi"]
		if A.has("node"):
			var nd: Node3D = an if A["node"] == "anchor" else bn
			_rod(mi, nd.position + Vector3(0, 0, -40), nd.position + Vector3(0, 0, 40))
			continue
		var zs: Array = []
		var pp := Vector2.ZERO
		for id: String in A["ids"]:
			var g2: Dictionary = gm[id]
			zs.append((g2["node"] as Node3D).position.z)
			pp = g2["p"]
		var z0: float = zs.min() - (140.0 if A["ids"][0] == "B" else 30.0)
		var z1: float = zs.max() + (140.0 if A["ids"][0] == "B" else 30.0)
		_rod(mi, Vector3(pp.x, pp.y, z0), Vector3(pp.x, pp.y, z1))


# ================================================================ 钟楼与台下机械（世界坐标）
func _layer(kind: String) -> Dictionary:
	return lay[kind]


## 景片 kind 的像素 → 世界（dz：沿视线往后为负）
func _px(kind: String, px: Vector2, dz := 0.0) -> Vector3:
	var L := _layer(kind)
	var c: Vector3 = S.o_e + Vector3(0, 0, -float(L["z"]) + dz)
	return c + Vector3((px.x / W - 0.5) * float(L["w"]), (0.5 - px.y / H) * float(L["h"]), 0.0)


## 台面：画框下沿那一层面（各景片的底边都落在上面）
func _deck_pt(u: float, dist: float, below := 0.0) -> Vector3:
	var D: float = C.D
	var k: float = S.OS_K
	return S.o_e + Vector3((u - 0.5) * W / D * dist * k, -0.5 * H / D * dist * k - below, -dist)


func _build_tower() -> void:
	for L: Dictionary in S.layers:
		lay[L["kind"]] = L
		(L["mat"] as ShaderMaterial).shader = stage_sh
	tw = Node3D.new()
	T.add_child(tw)
	tw.visible = false
	var fw: float = float(_layer("far")["w"]) / W
	# 拱里挖空，后面放一块深色机舱背板 + 三只咬合的黄铜齿轮
	var back := _mi(QuadMesh.new(), _mat("dark", 1000.0), tw)
	(back.mesh as QuadMesh).size = Vector2(240.0, 380.0) * fw
	back.position = _px("far", Vector2(1634, 560), -420.0)
	var c1 := Vector2(1716, 690)
	var r1 := 124.0 * fw
	var N1 := 44
	var mod := 2.0 * r1 / N1
	var r2 := 30.0 * mod * 0.5
	var c2 := c1 + (Vector2(1630, 500) - c1).normalized() * (r1 + r2) / fw
	var r3 := 14.0 * mod * 0.5
	var c3 := c1 + (Vector2(1566, 650) - c1).normalized() * (r1 + r3) / fw
	for spec: Array in [["T1", N1, r1, c1], ["T2", 30, r2, c2], ["T3", 14, r3, c3]]:
		var nd := Node3D.new()
		tw.add_child(nd)
		nd.position = _px("far", spec[3], -150.0)
		var Nn: int = spec[1]
		_mi(gear_mesh(Nn, spec[2], 40.0, "wheel" if Nn > 20 else "pinion", 6), _mat("brass", 20.0), nd)
		tgears.append({"node": nd, "N": Nn, "p": Vector2(nd.position.x, nd.position.y), "k": 1.0, "ph": 0.0})
	tgears[1]["k"] = -float(N1) / 30.0
	tgears[1]["ph"] = _phase(tgears[0], tgears[1])
	tgears[2]["k"] = -float(N1) / 14.0
	tgears[2]["ph"] = _phase(tgears[0], tgears[2])
	# 钟背后一根立轴把钟口的转动送下来
	_rod(_cyl(14.0, _mat("steel", 1000.0), tw), _px("far", Vector2(1626, 275), -150.0), _px("far", c2, -150.0))

	# 台面（舞台的斜台）与台口亮边
	var dk := MB.new()
	var d0 := 1500.0
	var d1 := 6400.0
	var a0: Vector3 = _deck_pt(-0.25, d0) - S.o_e
	var b0: Vector3 = _deck_pt(1.25, d0) - S.o_e
	var a1: Vector3 = _deck_pt(-0.25, d1) - S.o_e
	var b1: Vector3 = _deck_pt(1.25, d1) - S.o_e
	var nrm := (b0 - a0).cross(a1 - a0).normalized()
	dk.quad(a0, b0, b1, a1, nrm)
	deck = _mi(dk.mesh(), _mat("dark", 1000.0), tw)
	deck.position = S.o_e
	# 台下主轴：从塔脚斜着一路伸到近景下面
	var s0 := _deck_pt(0.89, 6036.0, 150.0)
	var s1 := _deck_pt(0.42, 2400.0, 150.0)
	_rod(_cyl(22.0, _mat("steel", 1000.0), tw), s0, s1)
	# 塔脚：钟楼齿轮的轴伸到台下，经万向节接上主轴
	var t1w: Vector3 = (tgears[0]["node"] as Node3D).position
	var foot := Vector3(t1w.x, s0.y, t1w.z)
	_rod(_cyl(18.0, _mat("steel", 1000.0), tw), t1w, foot)
	var uj := _cyl(40.0, _mat("brass", 1000.0), tw)
	_rod(uj, foot + Vector3(0, -40, 0), foot + Vector3(0, 40, 0))
	_rod(_cyl(18.0, _mat("steel", 1000.0), tw), foot, s0)
	# 主轴上的轴环（看得出它在转）
	for k in 9:
		var f := (k + 0.5) / 9.0
		var col := _mi(gear_mesh(6, 46.0, 30.0, "pinion"), _mat("brass", 15.0), tw)
		var p := s0.lerp(s1, f)
		var dir := (s1 - s0).normalized()
		col.transform = Transform3D(Basis.looking_at(dir, Vector3.UP), p)
		col.set_meta("spin", true)
	# 中景两扇门：门轴下面一只大冠轮，主轴上的交叉轴经小齿轮推它
	var zm: float = _layer("midL")["z"]
	var fm := (zm - 2400.0) / (6036.0 - 2400.0)
	var J := s1.lerp(s0, fm)
	for kind: String in ["midL", "midR"]:
		var L := _layer(kind)
		var hinge: Vector3 = L["hinge"]
		var hb := Vector3(hinge.x, J.y, hinge.z)
		_rod(_cyl(16.0, _mat("steel", 1000.0), tw), J, hb + Vector3(signf(J.x - hb.x) * 300.0, 0, 0))
		var cr := Node3D.new()
		tw.add_child(cr)
		cr.position = hb
		cr.basis = Basis(Vector3.RIGHT, -PI * 0.5)
		_mi(crown_mesh(72, 300.0, 18.0, 26.0), _mat("brass", 1000.0), cr)
		var post := _cyl(20.0, _mat("steel", 1000.0), tw)
		_rod(post, hb, Vector3(hinge.x, _deck_pt(0.0, zm).y + 30.0, hinge.z))
		door_crowns.append({"node": cr, "kind": kind})
		var pin := _mi(gear_mesh(12, 50.0, 40.0, "pinion"), _mat("steel", 20.0), tw)
		var pp := hb + Vector3(signf(J.x - hb.x) * 300.0, 60.0, 0)
		pin.transform = Transform3D(Basis.looking_at(Vector3(signf(J.x - hb.x), 0, 0), Vector3.UP), pp)
	var jc := _mi(crown_mesh(36, 120.0, 14.0, 18.0), _mat("brass", 1000.0), tw)
	jc.transform = Transform3D(Basis.looking_at((s1 - s0).normalized(), Vector3.UP), J)
	# 近景：底边一根齿条，主轴末端的齿轮推着它滑进来
	var Ln := _layer("near")
	rack = Node3D.new()
	tw.add_child(rack)
	var rl := float(Ln["w"]) * 1.1
	_mi(rack_mesh(rl, 22.0, 60.0, 50.0), _mat("brass", 30.0), rack)
	rack_x0 = s1.x
	rack.position = Vector3(s1.x, s1.y + 70.0 + 50.0, s1.z)
	var rp := _mi(gear_mesh(16, 176.0, 60.0, "wheel", 5), _mat("brass", 30.0), tw)
	rp.transform = Transform3D(Basis.looking_at((s1 - s0).normalized(), Vector3.UP), s1 + Vector3(0, -176.0 + 120.0 - 50.0, 0))
	rp.set_meta("spin", true)


func _phase(a: Dictionary, b: Dictionary) -> float:
	var al := (Vector2(b["p"]) - Vector2(a["p"])).angle()
	var q := float(a["N"]) / float(b["N"])
	return al + PI + PI / float(b["N"]) - q * (float(a["ph"]) - al)


func _tower_update(t: float) -> void:
	tw.visible = t >= S.T_LAND - 0.02
	var lk := maxf(t - S.T_LAND, 0.0)
	var Th := -1.6 * lk - 0.5 * lk * lk
	for g: Dictionary in tgears:
		(g["node"] as Node3D).rotation = Vector3(0, 0, float(g["k"]) * Th + float(g["ph"]))
	for c in tw.get_children():
		if c.has_meta("spin"):
			var mi := c as MeshInstance3D
			if not mi.has_meta("b0"):
				mi.set_meta("b0", mi.transform.basis)
			mi.transform.basis = (mi.get_meta("b0") as Basis) * Basis(Vector3(0, 0, 1), 6.0 * lk)
	for dc: Dictionary in door_crowns:
		var L := _layer(dc["kind"])
		var piv: Node3D = L["piv"]
		(dc["node"] as Node3D).basis = Basis(Vector3.UP, piv.rotation.y) * Basis(Vector3.RIGHT, -PI * 0.5)
	# 齿条跟着近景走
	var Ln := _layer("near")
	var npiv: Node3D = Ln["piv"]
	rack.position.x = rack_x0 + (npiv.position.x - Vector3(Ln["hinge"]).x)
	# 钟楼拱里挖空（只在第一章钟楼）
	var m: ShaderMaterial = _layer("far")["mat"]
	m.set_shader_parameter("hole", Vector4(1536, 442, 1734, 744))
	m.set_shader_parameter("hole_arch", Vector3(1635, 446, 99))


# ================================================================ 机位
func _look(pos: Vector3, at: Vector3, roll := 0.0) -> Transform3D:
	var X := Transform3D.IDENTITY.looking_at(at - pos, Vector3.UP)
	X.origin = pos
	if roll != 0.0:
		X.basis = X.basis * Basis(Vector3.BACK, roll)
	return X


func _rigp(p: Vector3) -> Vector3:
	return S.rig.global_transform * p


func _process(_dt: float) -> void:
	if shot.is_empty():
		return
	# 把 zz_select 的进场时间轴停在 tv（下一帧 update 时 ts = tv）
	S.t_state = S.now - tv + 1.0 / 60.0
	_movement_update(tv)
	_tower_update(tv)
	_stage_override(tv)
	if shot.has("cam"):
		var cf: Callable = shot["cam"]
		cam.global_transform = cf.call()
		cam.fov = float(shot.get("fov", 30.0))
	elif shot.has("fov"):
		cam.fov = float(shot["fov"])


## 揭示段改成「被机械推开」：门按冠轮转角开、近景沿齿条横滑；灯链从钟楼脚下往外传
func _stage_override(t: float) -> void:
	if t < S.T_LAND - 0.02:
		return
	var pm: float = S._seg(t, S.T_DOOR[0], S.T_DOOR[1] + 0.12)
	var em: float = S._in_out(pm)
	for kind: String in ["midL", "midR"]:
		var L := _layer(kind)
		var piv: Node3D = L["piv"]
		piv.rotation.y = (1.0 if kind == "midL" else -1.0) * 100.0 * DEG * (1.0 - em)
		(L["mat"] as ShaderMaterial).set_shader_parameter("opacity", 1.0)
	var Ln := _layer("near")
	var pn: float = S._seg(t, S.T_NEAR[0], S.T_NEAR[1] + 0.1)
	var npiv: Node3D = Ln["piv"]
	npiv.position = Vector3(Ln["hinge"]) + Vector3(-float(Ln["w"]) * 0.95 * (1.0 - S._out3(pn)), 0.0, 0.0)
	npiv.rotation = Vector3.ZERO
	(Ln["mat"] as ShaderMaterial).set_shader_parameter("opacity", 1.0 if pn > 0.0 else 0.0)
	for g: Dictionary in S.near_ghosts:
		(g["mi"] as MeshInstance3D).visible = false
	var gr: float = lerpf(-0.05, 1.25, S._seg(t, S.T_LAMP - 0.1, 0.45))
	for kind: String in ["far", "midL", "midR", "near"]:
		var m: ShaderMaterial = _layer(kind)["mat"]
		m.set_shader_parameter("glow_c", Vector2(1712.0 / W, 985.0 / H))
		m.set_shader_parameter("glow_r", gr)


# ================================================================ 出片
func _run() -> void:
	T._finish_intro()
	T.stuck_next = 1e9
	for i in 20:
		await get_tree().process_frame
	S = T.sel
	_build_movement()
	_build_tower()
	T._go("select")
	for i in 4:
		await get_tree().process_frame
	var shots := [
		{"name": "G01", "tv": 0.11},
		{"name": "G02", "tv": 0.3},
		{"name": "G03", "tv": 0.56},
		{"name": "G03w", "tv": 0.56, "cam": func() -> Transform3D: return _look(_rigp(Vector3(2500, 1300, 900)), _rigp(Vector3(-150, 0, -900)), 0.0), "fov": 40.0},
		{"name": "G04", "tv": 0.7, "cam": func() -> Transform3D: return _look(_rigp(Vector3(900, -520, -1020)), _rigp(Vector3(-260, 120, -1500)), 0.25), "fov": 58.0},
		{"name": "G04b", "tv": 0.7, "cam": func() -> Transform3D: return _look(_rigp(Vector3(820, 560, -560)), _rigp(Vector3(-200, -60, -1250)), -0.2), "fov": 56.0},
		{"name": "G05", "tv": 0.88},
		{"name": "G06", "tv": 1.06},
		{"name": "G07", "tv": 1.26},
		{"name": "G07b", "tv": 1.3, "cam": func() -> Transform3D: return _look(_px("far", Vector2(1640, 520), 2600.0), _px("far", Vector2(1660, 560), 0.0)), "fov": 30.0},
		{"name": "G08", "tv": 1.5, "cam": func() -> Transform3D: return _look(_deck_pt(-0.05, 1700.0, 900.0), _deck_pt(0.62, 4800.0, -200.0), 0.0), "fov": 60.0},
		{"name": "G08b", "tv": 1.5, "cam": func() -> Transform3D: return _look(_deck_pt(1.25, 2300.0, 600.0), _deck_pt(0.3, 4600.0, 0.0), 0.0), "fov": 58.0},
		{"name": "G09", "tv": 1.86},
		{"name": "G10", "tv": 2.6, "ui": true},
	]
	var only := OS.get_environment("ZZ_PREVIS_ONLY")
	for s: Dictionary in shots:
		if only != "" and not String(s["name"]).begins_with(only):
			continue
		tv = float(s["tv"])
		shot = s
		for c in T.get_children():
			if c is CanvasLayer:
				c.visible = bool(s.get("ui", false))
		for i in 8:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out.path_join(String(s["name"]) + ".png"))
		print("PREVIS ", s["name"])
	get_tree().quit()
