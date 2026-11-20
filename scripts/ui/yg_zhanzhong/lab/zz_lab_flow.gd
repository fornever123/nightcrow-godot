extends Node3D
## 《光粒子重构》技术样片（实验场景，不接首页）：
## 首页钟面沿时针顺时针化成光 → 绕钟轴卷成旋涡、镜头跟着往前滑 → 落成影街立体点云 → 线稿 → 灌色凝实
## → 镜头在影街里漂移（真实视差）→ 影街由近到远化光、镜头穿过粒子往前冲 → 落成雨夜河岸街真实开局画面
## → 无缝换成真正的关卡（自动确认开局核心，界面淡入），操作权交给玩家。

const DIR := "res://assets/image/yg_zhanzhong/lab/"
const POINTS_SH := preload("res://scripts/ui/yg_zhanzhong/lab/zz_lab_points.gdshader")
const RELIEF_SH := preload("res://scripts/ui/yg_zhanzhong/lab/zz_lab_relief.gdshader")
const GRAB := preload("res://scripts/ui/yg_zhanzhong/lab/zz_lab_handoff.gd")
const GX := 640
const GY := 360
const RX := 320
const RY := 180
const Z0 := 2000.0
const ZR := 0.32
const FPX := 2015.3

const S1 := 0.9          # 第一段（首页 → 影街）开始
const S2 := 6.0          # 第二段（影街 → 游戏）开始
const HANDOFF := 10.25   # 换成真关卡

var t := 0.0
var cam: Camera3D
var pmat: ShaderMaterial
var amat: ShaderMaterial
var bmat: ShaderMaterial
var plane_a: MeshInstance3D
var plane_b: MeshInstance3D
var camH := Transform3D.IDENTITY
var camC := Transform3D(Basis.IDENTITY, Vector3(0, 0, -900))
var camG := Transform3D(Basis.IDENTITY, Vector3(0, 0, -2500))
var stage := 0
var handed := false
var imgs := {}


func _ready() -> void:
	for k in ["home", "ch1", "game"]:
		imgs[k] = {
			"tex": load("res://assets/image/yg_zhanzhong/bz_art_ch1.jpg") if k == "ch1" else load(DIR + "lab_" + k + ".jpg"),
			"dep": load("res://assets/image/yg_zhanzhong/bz_depth_ch1.png") if k == "ch1" else load(DIR + "lab_" + k + "_depth.png"),
			"edge": load(DIR + "lab_" + k + "_edge.png"),
		}
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.012, 0.012, 0.02)
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	for i in 7:
		env.set_glow_level(i, 1.0 if i in [2, 3, 4, 5] else 0.0)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	cam = Camera3D.new()
	cam.fov = 30.0
	cam.near = 5.0
	cam.far = 30000.0
	add_child(cam)
	cam.make_current()

	var relief := _grid_mesh()
	amat = _relief_mat()
	bmat = _relief_mat()
	plane_a = MeshInstance3D.new()
	plane_a.mesh = relief
	plane_a.material_override = amat
	plane_a.extra_cull_margin = 16384.0
	add_child(plane_a)
	plane_b = MeshInstance3D.new()
	plane_b.mesh = relief
	plane_b.material_override = bmat
	plane_b.extra_cull_margin = 16384.0
	add_child(plane_b)

	pmat = ShaderMaterial.new()
	pmat.shader = POINTS_SH
	var pts := MeshInstance3D.new()
	pts.mesh = _points_mesh()
	pts.material_override = pmat
	pts.extra_cull_margin = 16384.0
	pts.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pts)

	_stage(1)
	_update()


func _common(m: ShaderMaterial) -> void:
	m.set_shader_parameter("z0", Z0)
	m.set_shader_parameter("zr", ZR)
	m.set_shader_parameter("fpx", FPX)
	m.set_shader_parameter("grid", Vector2(GX, GY))


func _relief_mat() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = RELIEF_SH
	_common(m)
	return m


func _grid_mesh() -> ArrayMesh:
	var v := PackedVector3Array()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()
	for y in RY + 1:
		for x in RX + 1:
			var u := Vector2(float(x) / RX, float(y) / RY)
			v.append(Vector3(u.x, u.y, 0.0))
			uv.append(u)
	for y in RY:
		for x in RX:
			var a := y * (RX + 1) + x
			idx.append_array([a, a + 1, a + RX + 1, a + 1, a + RX + 2, a + RX + 1])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


func _points_mesh() -> ArrayMesh:
	var v := PackedVector3Array()
	v.resize(GX * GY)
	var i := 0
	for y in GY:
		for x in GX:
			v[i] = Vector3((x + 0.5) / GX, (y + 0.5) / GY, 0.0)
			i += 1
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS, arr)
	return m


func _map(c: Transform3D, uv: Vector2, d: float) -> Vector3:
	var z := Z0 * (1.0 - ZR * (d - 0.5) * 2.0)
	return c * Vector3((uv.x - 0.5) * 1920.0 / FPX * z, (0.5 - uv.y) * 1080.0 / FPX * z, -z)


func _set_img(m: ShaderMaterial, key: String, suffix: String) -> void:
	var d: Dictionary = imgs[key]
	m.set_shader_parameter("tex" + suffix, d["tex"])
	m.set_shader_parameter("dep" + suffix, d["dep"])
	if suffix != "":
		m.set_shader_parameter("edge" + suffix, d["edge"])


func _stage(n: int) -> void:
	stage = n
	var a := "home" if n == 1 else "ch1"
	var b := "ch1" if n == 1 else "game"
	var ca := camH if n == 1 else camC
	var cb := camC if n == 1 else camG
	_set_img(pmat, a, "_a")
	_set_img(pmat, b, "_b")
	pmat.set_shader_parameter("cam_a", ca)
	pmat.set_shader_parameter("cam_b", cb)
	_set_img(amat, a, "")
	amat.set_shader_parameter("cam", ca)
	amat.set_shader_parameter("mode", 1)
	_set_img(bmat, b, "")
	bmat.set_shader_parameter("cam", cb)
	bmat.set_shader_parameter("mode", 2)
	for m: ShaderMaterial in [pmat, amat, bmat]:
		if n == 1:
			# 首页：钟面沿时针顺时针扫成光
			m.set_shader_parameter("dep_mode", 0)
			m.set_shader_parameter("dep_t0", 0.0)
			m.set_shader_parameter("dep_span", 1.15)
			m.set_shader_parameter("fly_dur", 1.55)
			m.set_shader_parameter("paint_t0", 2.55)
			m.set_shader_parameter("paint_span", 0.95)
			m.set_shader_parameter("hub", Vector2(950, 540))
		else:
			# 影街：近景先化光、由中心向外
			m.set_shader_parameter("dep_mode", 1)
			m.set_shader_parameter("dep_t0", 0.0)
			m.set_shader_parameter("dep_span", 0.95)
			m.set_shader_parameter("fly_dur", 1.5)
			m.set_shader_parameter("paint_t0", 2.45)
			m.set_shader_parameter("paint_span", 0.9)
	if n == 1:
		pmat.set_shader_parameter("ax_a", _map(camH, Vector2(950.0 / 1920.0, 0.5), 0.5))
		pmat.set_shader_parameter("ax_b", _map(camC, Vector2(0.5, 0.5), 0.5))
		pmat.set_shader_parameter("turns", 1.0)
		pmat.set_shader_parameter("stream", 900.0)
	else:
		pmat.set_shader_parameter("ax_a", _map(camC, Vector2(0.5, 0.5), 0.5))
		pmat.set_shader_parameter("ax_b", _map(camG, Vector2(0.5, 0.5), 0.5))
		pmat.set_shader_parameter("turns", -1.0)
		pmat.set_shader_parameter("stream", 1400.0)


static func _io(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * x * (x * (x * 6.0 - 15.0) + 10.0)


func _cam_at(tt: float) -> Transform3D:
	if tt < 1.3:
		return camH.translated(Vector3(0, 0, -40.0 * tt / 1.3))
	if tt < 4.0:
		var e := _io((tt - 1.3) / 2.7)
		var x := camH.translated(Vector3(0, 0, -40.0)).interpolate_with(camC, e)
		x.basis = x.basis * Basis(Vector3.BACK, 0.22 * sin(PI * e))
		x.origin += Vector3(-160.0, 60.0, 0.0) * sin(PI * e)
		return x
	if tt < 6.3:
		var p := (tt - 4.0) / 2.3
		var w := sin(PI * p)
		var x := camC
		var e := _io(p)
		x.origin += Vector3(90.0 * sin(PI * p), -30.0 * w, -260.0 * w)
		x.basis = Basis(Vector3.UP, 0.025 * sin(PI * p) * (1.0 - e))
		return x
	if tt < 9.3:
		var e := _io((tt - 6.3) / 3.0)
		var x := camC.interpolate_with(camG, e)
		x.basis = x.basis * Basis(Vector3.BACK, -0.14 * sin(PI * e))
		x.origin += Vector3(120.0, -50.0, 0.0) * sin(PI * e)
		return x
	return camG


func _process(dt: float) -> void:
	if handed:
		return
	t += dt
	if stage == 1 and t >= S2:
		_stage(2)
	_update()
	if t >= HANDOFF:
		_handoff()


func _update() -> void:
	cam.global_transform = _cam_at(t)
	var T := t - (S1 if stage == 1 else S2)
	for m: ShaderMaterial in [pmat, amat, bmat]:
		m.set_shader_parameter("T", T)


func _handoff() -> void:
	handed = true
	var w := Node.new()
	w.set_script(GRAB)
	w.set_meta("cover", DIR + "lab_game.jpg")
	w.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(w)
	get_tree().change_scene_to_file.call_deferred("res://scenes/rain_trial.tscn")
