extends Node3D
## 《斩钟》进选章转场 · 分镜预演（只出静帧，不进正式流程）
## 用法：ZZ_PREVIS=<输出目录> 运行首页场景，渲染 A「倒走留痕」、B「切片对位」两套分镜关键帧后退出；
## ZZ_PREVIS_ONLY=<名字前缀> 只渲染部分镜头。
## 线迹是按镜头实时重建的屏幕恒宽发光带；正面机位下所有线都按透视放大（越深越大），
## 所以正面看贴着表盘、侧面才看出纵深。

const D := 2015.0
const ZC := 2015.0          # 首页机位离钟盘中心的距离（=D）
const L_A := 2600.0         # A：线迹拉开的总纵深
const L_B := 3500.0         # B：切片拉开的总纵深
const TAN15 := 0.2679492
const LN_DIR := "C:/Users/MECHREVO/AppData/Local/Temp/claude/bad2dff93b2b5945/0fddf7d5-af25-4d6b-a51b-6b04d824eebd/scratchpad/prev/"
const STAGE_D := [9000.0, 4200.0, 2400.0, 1150.0]   # 影街四层离街景机位的距离
const TOWER_PX := Vector2(1626.0, 275.5)
const WARM := Color(1.0, 0.9, 0.74)
const COOL := Color(0.72, 0.8, 1.0)
const SILVER := Color(0.86, 0.88, 0.94)
const RINGS := [327.0, 386.0, 484.0, 552.0, 623.0, 640.0, 672.0]

var T: Node
var C: Node
var cam: Camera3D
var out := ""
var line_mi: MeshInstance3D
var lines: Array = []
var shot: Dictionary = {}
var rng := RandomNumberGenerator.new()
var stage: Node3D
var stage_mats: Array = []
var stage_ln: Array = []
var echo_ln: Array = []
var tower_dial: MeshInstance3D
var plates: Array = []
var S_xf := Transform3D.IDENTITY
var a_fine: Array = []
var a_bright: Array = []
var line_k := 1.0


func _ready() -> void:
	T = get_parent()
	C = T.clock
	cam = C.camera
	cam.far = 90000.0
	process_priority = 1000
	out = OS.get_environment("ZZ_PREVIS")
	DirAccess.make_dir_recursive_absolute(out)
	_build_line_mesh()
	_build_stage()
	_build_plates()
	_build_a_lines()
	_run.call_deferred()


func _ltex(name: String) -> ImageTexture:
	var img := Image.load_from_file(LN_DIR + name)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


# ---------------------------------------------------------------- 线迹网格
func _build_line_mesh() -> void:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
varying float inten;
void vertex() { inten = UV2.x; }
void fragment() {
	float y = UV.y;
	float a = exp(-y * y * 1.7);
	ALBEDO = COLOR.rgb * inten * a;
	ALPHA = 1.0;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.render_priority = 10
	line_mi = MeshInstance3D.new()
	line_mi.material_override = m
	line_mi.extra_cull_margin = 16384.0
	line_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(line_mi)


func _rebuild(X: Transform3D, fov: float) -> void:
	var f := 540.0 / tan(deg_to_rad(fov) * 0.5)
	var inv := X.affine_inverse()
	var V := PackedVector3Array()
	var CC := PackedColorArray()
	var U := PackedVector2Array()
	var U2 := PackedVector2Array()
	var I := PackedInt32Array()
	for L: Dictionary in lines:
		var P: PackedVector3Array = L["p"]
		var n := P.size()
		if n < 2:
			continue
		var w: float = L["w"]
		var wpx := maxf(w, 1.35)
		var k: float = float(L["k"]) * minf(1.0, w / 1.35)
		var col: Color = L["c"]
		var r0: float = L.get("r0", 0.0)
		var r1: float = L.get("r1", 1.0)
		var head: float = L.get("head", 0.0)
		var fog: float = L.get("fog", 0.0)
		var base := V.size()
		for i in n:
			var p := P[i]
			var tng := P[mini(i + 1, n - 1)] - P[maxi(i - 1, 0)]
			var dep := -(inv * p).z
			var u := float(i) / float(n - 1)
			var fade := smoothstep(r0 - 0.015, r0 + 0.015, u) * (1.0 - smoothstep(r1 - 0.015, r1 + 0.015, u))
			if head > 0.0:
				fade *= lerpf(1.0, 0.25, pow(u, head))
			var vis := smoothstep(25.0, 90.0, dep)
			var side := tng.cross(X.origin - p)
			if side.length() < 1e-5:
				side = Vector3.UP
			side = side.normalized()
			var hw := 2.2 * wpx * 0.5 * maxf(dep, 25.0) / f
			var inten := k * fade * vis * line_k
			if fog > 0.0:
				inten *= exp(-maxf(dep - 1500.0, 0.0) / fog)
			V.append(p + side * hw)
			V.append(p - side * hw)
			U.append(Vector2(u, 2.2))
			U.append(Vector2(u, -2.2))
			U2.append(Vector2(inten, 0))
			U2.append(Vector2(inten, 0))
			CC.append(col)
			CC.append(col)
		for i in n - 1:
			var a := base + i * 2
			I.append_array([a, a + 1, a + 2, a + 1, a + 3, a + 2])
	if V.is_empty():
		line_mi.mesh = null
		return
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = V
	arr[Mesh.ARRAY_COLOR] = CC
	arr[Mesh.ARRAY_TEX_UV] = U
	arr[Mesh.ARRAY_TEX_UV2] = U2
	arr[Mesh.ARRAY_INDEX] = I
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	line_mi.mesh = am


# ---------------------------------------------------------------- 几何工具
## 首页机位透视下：屏幕半径 rs（px）、屏幕角 a、深度 z 的那一点（正面看永远落在同一个屏幕圆上）
func _ana(rs: float, a: float, z: float) -> Vector3:
	var s := (ZC - z) / D
	return Vector3(-10.0 * s + rs * s * cos(a), -rs * s * sin(a), z)


## 街景机位下：屏幕像素 + 离机位距离 → 世界点
func _st(px: Vector2, d: float) -> Vector3:
	return S_xf * Vector3((px.x - 960.0) * d / D, (540.0 - px.y) * d / D, -d)


func _line(p: PackedVector3Array, w: float, k: float, c: Color, extra := {}) -> Dictionary:
	var L := {"p": p, "w": w, "k": k, "c": c}
	L.merge(extra)
	return L


# ---------------------------------------------------------------- A：倒走的指针留下层层弧线
func _build_a_lines() -> void:
	rng.seed = 559
	var NL := 14
	var ring_px := [386.0, 484.0, 552.0, 623.0]
	for l in NL:
		var ul := (float(l) + 0.5) / NL
		var zl := -440.0 - L_A * pow(ul, 1.1)
		# 每一层是一个「过去的时刻」：几道同心弧都停在同一深度，起点随层数倒转
		var turn := -0.55 * l
		var picks := ring_px.duplicate()
		picks.shuffle()
		for j in 3:
			var rs: float = picks[j]
			# 近乎整圈、留一个缺口：缺口的位置就是那一刻指针所在，层层旋转下去
			var span := TAU - rng.randf_range(0.45, 1.3)
			var a0 := turn + rng.randf_range(-0.12, 0.12)
			var stepped := rng.randf() < 0.25
			var P := PackedVector3Array()
			var nseg := int(span / 0.025) + 2
			for i in nseg:
				var t := float(i) / float(nseg - 1)
				var a := a0 - span * t
				if stepped:
					var st := span * t / (TAU / 60.0)
					a = a0 - (floorf(st) + smoothstep(0.7, 1.0, fposmod(st, 1.0))) * (TAU / 60.0)
				P.append(_ana(rs, a, zl))
			var kk := 0.85 if j == 0 else rng.randf_range(0.3, 0.55)
			a_fine.append(_line(P, 1.8 if j == 0 else 1.2, kk * lerpf(1.0, 0.55, ul), Color(0.93, 0.95, 1.0) if j == 0 else SILVER.lerp(COOL, rng.randf()), {"fog": 8000.0}))
	# 暗处交错的细线：斜穿各层的细螺旋
	for j in 14:
		var rs := rng.randf_range(300.0, 700.0)
		var turns := rng.randf_range(0.15, 0.6) * (1.0 if rng.randf() < 0.7 else -1.0)
		var za := -440.0 - rng.randf_range(0.0, 0.5) * L_A
		var zb := za - rng.randf_range(0.3, 0.6) * L_A
		var a0 := rng.randf() * TAU
		var P := PackedVector3Array()
		var n := int(absf(turns) * TAU / 0.025) + 2
		for i in n:
			var t := float(i) / float(n - 1)
			P.append(_ana(rs, a0 - turns * TAU * t, lerpf(za, zb, t)))
		a_fine.append(_line(P, 1.0, rng.randf_range(0.16, 0.32), COOL, {"fog": 7000.0}))
	# 领着视线的亮线：分针尖、时针尖、刻度圈各一条长螺旋，从指针所在处出发，斜着一路钻进纵深
	var mins: float = C.TWELVE - C.GAP
	a_bright.append(_helix(640.0, mins - 0.35, 0.7 * TAU, 90.0, -440.0 - L_A * 0.97, 3.0, 2.7, WARM))
	a_bright.append(_helix(552.0, C.REST + 0.3, 0.35 * TAU, 60.0, -440.0 - L_A * 0.9, 2.5, 2.2, WARM))
	a_bright.append(_helix(386.0, 2.0, 0.5 * TAU, -440.0, -440.0 - L_A * 0.75, 2.0, 1.5, Color(0.93, 0.95, 1.0)))


func _helix(rs: float, a0: float, turns: float, z0: float, z1: float, w: float, k: float, c: Color) -> Dictionary:
	var P := PackedVector3Array()
	var n := int(turns / 0.02) + 2
	for i in n:
		var t := float(i) / float(n - 1)
		P.append(_ana(rs, a0 - turns * t, lerpf(z0, z1, pow(t, 0.85))))
	return _line(P, w, k, c, {"fog": 9000.0, "head": 1.6})


## 街景里的时间隧道：以钟楼钟面为灭点的同心弧（世界半径恒定，所以越近屏幕越大）
func _street_tunnel(reach: float, kk := 1.0) -> Array:
	var res: Array = []
	rng.seed = 77
	for j in 56:
		var d := lerpf(300.0, 7600.0, pow(rng.randf(), 1.4))
		var rw := rng.randf_range(240.0, 980.0)
		var span := rng.randf_range(0.5, 2.6)
		var a0 := rng.randf() * TAU
		var P := PackedVector3Array()
		var n := int(span / 0.025) + 2
		for i in n:
			var t := float(i) / float(n - 1)
			var a := a0 - span * t
			var rs := rw * D / d
			P.append(_st(TOWER_PX + Vector2(cos(a), sin(a)) * rs, d))
		res.append(_line(P, rng.randf_range(0.95, 1.4), rng.randf_range(0.18, 0.45) * kk, SILVER, {"r1": reach}))
	return res


## 接画：一道近处的弧从画外扫进来，在 J 点与屋檐相切，再沿屋檐一路走向钟楼
func _eave_line(chain: Array, d0: float, d1: float, arc_r: float, sweep: float, w: float, k: float, reveal := 1.0) -> Dictionary:
	var J: Vector2 = chain[0]
	var tj: Vector2 = (chain[1] - chain[0]).normalized()
	var nrm := Vector2(-tj.y, tj.x)
	var best := {}
	for sgn: float in [1.0, -1.0]:
		var cen := J + nrm * arc_r * sgn
		var a_j := atan2(J.y - cen.y, J.x - cen.x)
		var dirv := 1.0 if Vector2(-sin(a_j), cos(a_j)).dot(tj) > 0.0 else -1.0
		var a_s := a_j - dirv * sweep
		var p0 := cen + Vector2(cos(a_s), sin(a_s)) * arc_r
		if best.is_empty() or p0.y < float(best["y"]):
			best = {"y": p0.y, "cen": cen, "a_j": a_j, "dir": dirv}
	var P := PackedVector3Array()
	var na := 90
	for i in na:
		var t := float(i) / float(na)
		var a: float = float(best["a_j"]) - float(best["dir"]) * sweep * (1.0 - t)
		var sp: Vector2 = best["cen"] + Vector2(cos(a), sin(a)) * arc_r
		P.append(_st(sp, lerpf(260.0, d0, pow(t, 2.4))))
	# 沿屋檐：按长度细分，深度由近到远
	var total := 0.0
	for i in chain.size() - 1:
		total += (chain[i + 1] - chain[i]).length()
	var acc := 0.0
	for i in chain.size() - 1:
		var a: Vector2 = chain[i]
		var b: Vector2 = chain[i + 1]
		var segl := (b - a).length()
		var ns := maxi(2, int(segl / 8.0))
		for s in ns:
			var t := float(s) / float(ns)
			var q := a.lerp(b, t)
			P.append(_st(q, lerpf(d0, d1, (acc + segl * t) / total)))
		acc += segl
	P.append(_st(chain[chain.size() - 1], d1))
	return _line(P, w, k, WARM, {"r1": reveal})


## 一道亮线从近处螺旋收进钟楼的钟口，变成钟面外圈
func _socket_line(w: float, k: float, reveal := 1.0) -> Dictionary:
	var P := PackedVector3Array()
	var n := 260
	for i in n:
		var t := float(i) / float(n - 1)
		var a := -2.4 + 1.65 * TAU * t
		var rs := lerpf(1300.0, 118.0, pow(t, 0.55))
		var d := lerpf(420.0, STAGE_D[1] - 20.0, pow(t, 0.7))
		P.append(_st(TOWER_PX + Vector2(cos(a), sin(a)) * rs, d))
	return _line(P, w, k, WARM, {"r1": reveal})


## Catmull-Rom 平滑屋檐折线（去掉拐角）
func _smooth(pts: Array) -> Array:
	var res: Array = []
	var n := pts.size()
	for i in n - 1:
		var p0: Vector2 = pts[maxi(i - 1, 0)]
		var p1: Vector2 = pts[i]
		var p2: Vector2 = pts[i + 1]
		var p3: Vector2 = pts[mini(i + 2, n - 1)]
		for s in 12:
			var t := float(s) / 12.0
			var t2 := t * t
			var t3 := t2 * t
			res.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	res.append(pts[n - 1])
	return res


# ---------------------------------------------------------------- 影街景片
func _build_stage() -> void:
	# 街景机位：在中轴深处，镜头朝向让画里钟楼的钟面正好落在中轴上
	var dl := Vector3((TOWER_PX.x - 960.0) / D, (540.0 - TOWER_PX.y) / D, -1.0).normalized()
	var R := Basis(Quaternion(dl, Vector3(0, 0, -1)))
	S_xf = Transform3D(R, Vector3(-10.0, 0.0, -420.0 - L_A - 700.0))
	stage = Node3D.new()
	stage.transform = S_xf
	add_child(stage)
	var shader: Shader = load("res://scripts/ui/yg_zhanzhong/zz_stage_flat.gdshader")
	for i in 4:
		var d: float = STAGE_D[i]
		var q := QuadMesh.new()
		var hh := d * TAN15 * (1.25 if i == 0 else 1.0)
		q.size = Vector2(hh * 2.0 * 16.0 / 9.0, hh * 2.0)
		var m := ShaderMaterial.new()
		m.shader = shader
		m.set_shader_parameter("tex", load("res://assets/image/yg_zhanzhong/stage/st_ch1_L%d.png" % i))
		m.set_shader_parameter("uv_k", 1.0 / 1.25 if i == 0 else 1.0)
		m.render_priority = -4 + i
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.material_override = m
		mi.position = Vector3(0, 0, -d)
		mi.extra_cull_margin = 16384.0
		stage.add_child(mi)
		stage_mats.append(m)
		if i == 0:
			continue
		# 线稿：同一位置叠一层，另在镜头和它之间按透视缩放放几份「回声」——只有站在街景机位才对齐
		var lt := _ltex("ln_L%d.png" % i)
		for f: float in [1.0, 0.8, 0.62, 0.47, 0.35]:
			var lq := QuadMesh.new()
			lq.size = q.size * f
			var lm: ShaderMaterial = C.add_mat(lt, Color(0.9, 0.93, 1.0), 0.0)
			lm.render_priority = 6
			var lmi := MeshInstance3D.new()
			lmi.mesh = lq
			lmi.material_override = lm
			lmi.position = Vector3(0, 0, -d * f)
			lmi.extra_cull_margin = 16384.0
			stage.add_child(lmi)
			if f == 1.0:
				stage_ln.append(lm)
			else:
				echo_ln.append({"m": lm, "f": f})
	# 钟楼钟口里的表盘（首页那面钟落位后的样子）
	var dd: float = STAGE_D[1] - 15.0
	var rr := 118.0 * dd / D
	var dq := QuadMesh.new()
	dq.size = Vector2(rr * 2.0 * 1243.0 / 1200.0, rr * 2.0 * 1232.0 / 1200.0)
	var dm: ShaderMaterial = C.lit_mat(C.tex("dial"), C.tex("dial_n"), Color("#e2ddd2"), Color("#b0aaa0"), 0.55, 1.0, 0.8, 0.32)
	dm.render_priority = -2
	tower_dial = MeshInstance3D.new()
	tower_dial.mesh = dq
	tower_dial.material_override = dm
	tower_dial.position = Vector3((TOWER_PX.x - 960.0) * dd / D, (540.0 - TOWER_PX.y) * dd / D, -dd)
	tower_dial.extra_cull_margin = 16384.0
	stage.add_child(tower_dial)


# ---------------------------------------------------------------- B：时间切片
func _build_plates() -> void:
	var dial_t := _ltex("ln_dial_sparse.png")
	var hand_t := _ltex("ln_hand_minute.png")
	var hour_t := _ltex("ln_hand_hour.png")
	var N := 16
	var mins: float = C.TWELVE - C.GAP
	for j in N:
		var u := float(j + 1) / float(N)
		var z := -440.0 - L_B * pow(u, 1.3)
		var g := Node3D.new()
		add_child(g)
		var dm: ShaderMaterial = C.add_mat(dial_t, Color(0.82, 0.86, 1.0), 0.0)
		dm.render_priority = 6
		var dq: MeshInstance3D = C.meta_quad("dial", 1.12, z, dm)
		C.place(dq, C.HUB.x, C.HUB.y, z)
		dq.extra_cull_margin = 16384.0
		g.add_child(dq)
		var hm: ShaderMaterial = C.add_mat(hand_t, WARM, 0.0)
		hm.render_priority = 7
		var hq: MeshInstance3D = C.meta_quad("hand_minute", 0.43, z, hm)
		C.place(hq, C.HUB.x, C.HUB.y, z)
		hq.rotation.z = -(mins - 0.16 * (j + 1))
		hq.extra_cull_margin = 16384.0
		g.add_child(hq)
		var om: ShaderMaterial = C.add_mat(hour_t, WARM, 0.0)
		om.render_priority = 7
		var oq: MeshInstance3D = C.meta_quad("hand_hour", 0.355, z, om)
		C.place(oq, C.HUB.x, C.HUB.y, z)
		oq.rotation.z = -(C.REST + 0.3 - 0.014 * (j + 1))
		oq.extra_cull_margin = 16384.0
		g.add_child(oq)
		plates.append({"g": g, "dial": dm, "hand": hm, "hour": om, "u": u, "j": j})


# ---------------------------------------------------------------- 镜头与每帧状态
func _look(pos: Vector3, at: Vector3, roll := 0.0) -> Transform3D:
	var X := Transform3D.IDENTITY.looking_at(at - pos, Vector3.UP)
	X.origin = pos
	if roll != 0.0:
		X.basis = X.basis * Basis(Vector3.BACK, roll)
	return X


func _home() -> Transform3D:
	return Transform3D(Basis.IDENTITY, Vector3(0, 0, ZC))


func _process(_dt: float) -> void:
	if shot.is_empty():
		return
	var X: Transform3D = shot["cam"]
	cam.fov = float(shot.get("fov", 30.0))
	cam.global_transform = X
	var bg: bool = shot.get("bg", false)
	var clock_vis: bool = shot.get("clock", true)
	C._ink_bg.visible = bg
	C._ink_vig.visible = bg
	C._violet_plane.visible = bg and C._violet_plane.visible
	C._seam.visible = bg
	for side in C._mov:
		(C._mov[side] as Node3D).visible = clock_vis
	for key in C._hands:
		(C._hands[key] as Node3D).visible = clock_vis
	for n in C._hub_parts:
		n.visible = clock_vis
	for d: Dictionary in C._debris:
		(d["g"] as Node3D).visible = (d["g"] as Node3D).visible and bg and shot.get("debris", true)
	for side in C._parts:
		var P: Dictionary = C._parts[side]
		for key in P:
			var mm := (P[key] as MeshInstance3D).material_override as ShaderMaterial
			mm.set_shader_parameter("opacity", float(mm.get_meta("base", 1.0)) * float(shot.get("dial_a", 1.0)))
	line_k = float(shot.get("lk", 1.0))
	for hh: Dictionary in C._mark_halves:
		for ly: Dictionary in hh["layers"]:
			(ly["mi"] as Node3D).visible = false
	for lb in C._readout:
		lb.visible = false
	if shot.has("min"):
		var ma: float = shot["min"]
		C._hands["minute"].rotation.z = -ma
		C._hands["minute_sh"].rotation.z = -ma
	if shot.has("hour"):
		var ha: float = shot["hour"]
		C._hands["hour"].rotation.z = -ha
		C._hands["hour_sh"].rotation.z = -ha
	_rebuild(X, cam.fov)


func _stage_state(vis: bool, lit: float, glow_front: float, line_a: float, echo_a: float, paint_a := 1.0, dial_vis := false) -> void:
	stage.visible = vis
	tower_dial.visible = dial_vis
	for i in 4:
		var m: ShaderMaterial = stage_mats[i]
		m.set_shader_parameter("lit", lit if i > 0 else lerpf(0.3, 1.0, lit))
		m.set_shader_parameter("glow_front", glow_front)
		m.set_shader_parameter("rim", 0.0)
		m.set_shader_parameter("opacity", paint_a)
	for m: ShaderMaterial in stage_ln:
		m.set_shader_parameter("opacity", line_a)
	for e: Dictionary in echo_ln:
		(e["m"] as ShaderMaterial).set_shader_parameter("opacity", echo_a * (0.2 + 0.6 * float(e["f"])))


func _plates_state(a: float, hand_a: float, count := 99, dial_fade := 1.0) -> void:
	for P: Dictionary in plates:
		var u: float = P["u"]
		var g: Node3D = P["g"]
		g.visible = a > 0.0 and int(P["j"]) < count
		var fade := 1.0 - dial_fade * smoothstep(0.6, 1.0, u)
		(P["dial"] as ShaderMaterial).set_shader_parameter("opacity", a * lerpf(0.42, 0.14, u) * fade)
		(P["hand"] as ShaderMaterial).set_shader_parameter("opacity", hand_a * lerpf(1.1, 0.35, u) * fade)
		(P["hour"] as ShaderMaterial).set_shader_parameter("opacity", hand_a * 0.5 * lerpf(1.0, 0.35, u) * fade)


func _run() -> void:
	T._finish_intro()
	T.stuck_next = 1e9
	for c in T.get_children():
		if c is CanvasLayer:
			c.visible = false
	for i in 30:
		await get_tree().process_frame
	var mins: float = C.TWELVE - C.GAP
	var shots := [
		# ---------- A 倒走留痕
		{"name": "A1", "cam": _home(), "min": mins - 0.35, "hour": C.REST + 0.3, "set": "A", "bg": true, "debris": false, "dial_a": 0.5, "lk": 1.5},
		{"name": "A2", "cam": _look(Vector3(-760, 620, 260), Vector3(260, -260, -1500), 0.5), "fov": 46.0, "min": mins - 0.9, "hour": C.REST + 0.25, "set": "A", "dial_a": 0.8},
		{"name": "A3", "cam": _look(Vector3(2600, 900, 500), Vector3(-300, -80, -1500)), "fov": 40.0, "min": mins - 1.4, "hour": C.REST + 0.2, "set": "A"},
		{"name": "A3b", "cam": _look(Vector3(-2500, 700, 300), Vector3(0, -50, -1400), -0.08), "fov": 40.0, "min": mins - 1.4, "hour": C.REST + 0.2, "set": "A"},
		{"name": "A3c", "cam": _look(Vector3(700, 2700, 200), Vector3(-10, 0, -1500)), "fov": 42.0, "min": mins - 1.4, "hour": C.REST + 0.2, "set": "A"},
		{"name": "A3d", "cam": _look(Vector3(1700, -500, 900), Vector3(-350, 120, -1700), 0.15), "fov": 44.0, "min": mins - 1.4, "hour": C.REST + 0.2, "set": "A"},
		{"name": "A4", "cam": _look(_ana(518.0, 2.4, -600.0), _ana(380.0, 2.4, -3000.0), 0.55), "fov": 52.0, "set": "A", "clock": false},
		{"name": "A5", "cam": S_xf, "set": "A5", "clock": false},
		{"name": "A6", "cam": S_xf, "set": "A6", "clock": false},
		# ---------- B 切片对位
		{"name": "B1", "cam": _home(), "min": mins, "hour": C.REST + 0.3, "set": "B1", "bg": true},
		{"name": "B2", "cam": _look(Vector3(2600, 900, 500), Vector3(-300, -80, -1600)), "fov": 40.0, "min": mins, "hour": C.REST + 0.3, "set": "B"},
		{"name": "B3", "cam": _look(Vector3(60, -60, -900), Vector3(-10, 0, -5000), 0.2), "fov": 50.0, "set": "B", "clock": false},
		{"name": "B4", "cam": _look((S_xf * Vector3(110, -50, 320)), _st(Vector2(1250, 540), 3000.0), 0.02), "fov": 31.0, "set": "B4", "clock": false},
		{"name": "B5", "cam": S_xf, "set": "B5", "clock": false},
		{"name": "B6", "cam": S_xf, "set": "B6", "clock": false},
	]
	var only := OS.get_environment("ZZ_PREVIS_ONLY")
	for s: Dictionary in shots:
		if only != "" and not String(s["name"]).begins_with(only):
			continue
		_prepare(s)
		shot = s
		for i in 8:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out.path_join(String(s["name"]) + ".png"))
		print("PREVIS ", s["name"])
	get_tree().quit()


func _prepare(s: Dictionary) -> void:
	var set_: String = s["set"]
	lines = []
	_stage_state(false, 0.0, -1.0, 0.0, 0.0)
	_plates_state(0.0, 0.0)
	var roof := _smooth([Vector2(1020, 286), Vector2(1151, 434), Vector2(1246, 551), Vector2(1346, 606)])
	match set_:
		"A":
			lines = a_fine + a_bright
		"A5":
			_stage_state(true, 0.07, 0.62, 0.0, 0.0)
			lines = _street_tunnel(1.0)
			lines.append(_eave_line(roof, 2000.0, 4200.0, 1100.0, 1.25, 3.2, 2.6))
			lines.append(_socket_line(2.4, 2.0))
		"A6":
			_stage_state(true, 1.0, 2.0, 0.0, 0.0, 1.0, true)
			lines = _street_tunnel(0.1, 0.7)
			lines.append(_eave_line(roof, 2000.0, 4200.0, 1100.0, 1.25, 2.4, 1.2, 0.06))
		"B1":
			_plates_state(1.0, 1.0, 9, 0.0)
		"B":
			_plates_state(1.0, 1.0)
			var cz: float = (s["cam"] as Transform3D).origin.z
			for P: Dictionary in plates:
				var g: Node3D = P["g"]
				var pz: float = (g.get_child(0) as Node3D).position.z
				if pz > cz - 380.0:
					g.visible = false
		"B4":
			_plates_state(0.6, 0.6)
			_stage_state(true, 0.0, -1.0, 0.8, 1.0, 0.0)
		"B5":
			_stage_state(true, 0.06, 0.5, 0.75, 0.8)
		"B6":
			_stage_state(true, 1.0, 2.0, 0.22, 0.0, 1.0, true)
