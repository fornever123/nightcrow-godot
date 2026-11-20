extends Node3D
## [YG-MARK] 首页《斩钟》：三维哥特司辰钟（保留原版立体钟盘/机芯/双剑指针/悬停碎片，净除模糊拼缝网点与斜纹字标）
## 坐标沿用 1920×1080 屏幕像素映射至深度 z：静止镜头下构图精准，镜头一动各层按真三维透视错开。
## 斩缝是一张穿过钟心的 28° 竖直裁切面，原生支持四位女主主色（朔紫 / 萤青 / 薇红 / 曜金）实时切换。

const W := 1920.0
const H := 1080.0
const DEG := PI / 180.0
const TILT := 28.0 * DEG
const ALONG := Vector2(0.4694716, -0.8829476)    # sin28, -cos28：屏幕里指向 12 点
const ACROSS := Vector2(0.8829476, 0.4694716)    # 指向裂口主色半边
const HUB := Vector2(950, 540)
const FOV := 30.0
const GAP := 6.0 * DEG
const HOLE_PX := 440.0     # 钟窗：表盘贴图里开孔半径（像素，罗马数字环内沿）
const PETALS := 8
# 11-17 钟动效：表盘按半径切成五圈（贴图像素，和选章分解钟同一套切法），各圈放在不同深度，背后叠暗片做铸铁厚度
const RINGS := [[0.0, 292.0], [292.0, 345.0], [345.0, 432.0], [432.0, 556.0], [556.0, 640.0]]
const RING_KEYS := ["dial", "ring1", "ring2", "ring3", "ring4"]
const RING_Z := [-600.0, -520.0, -455.0, -390.0, -330.0]   # 中心机芯最深、外沿最近：一只碗
const THICK_N := 3
const THICK_STEP := 9.0
var D: float = H * 0.5 / tan(FOV * 0.5 * DEG)
var TWELVE: float = atan2(ALONG.y, ALONG.x)
var REST: float = atan2(-ALONG.y, -ALONG.x)

const INK := Color("#08070c")
const WHITE := Color("#f5f2eb")
const VIOLET := Color("#5b2be0")
const DIR := "res://assets/image/yg_zhanzhong/"

const LIT_SHADER := preload("res://scripts/ui/yg_zhanzhong/zz_lit.gdshader")
const FLAT_SHADER := preload("res://scripts/ui/yg_zhanzhong/zz_flat.gdshader")
const ADD_SHADER := preload("res://scripts/ui/yg_zhanzhong/zz_add.gdshader")
const RIFT_SHADER := preload("res://scripts/ui/yg_zhanzhong/zz_rift_field.gdshader")

const META := {
	"dial": [621.0, 615.5, 1243.0, 1232.0],
	"gear_main": [211.5, 216.0, 425.0, 433.0],
	"gear_escape": [178.0, 181.0, 357.0, 363.0],
	"pallet_fork": [157.5, 54.0, 316.0, 283.0],
	"hand_hour": [79.7, 223.2, 1636.0, 430.0],
	"hand_minute": [100.3, 103.6, 1591.0, 206.0],
	"rosette": [299.0, 299.5, 599.0, 600.0],
}

const DEBRIS := [
	{"i": 1, "dx": 255, "dy": -385, "s": 0.5, "r": -16, "z": 260, "tx": 0.35, "ty": -0.5},
	{"i": 3, "dx": -70, "dy": 392, "s": 0.56, "r": 166, "z": 330, "tx": -0.4, "ty": 0.3},
	{"i": 0, "dx": 800, "dy": -370, "s": 0.34, "r": 28, "z": 140, "tx": 0.2, "ty": 0.6, "dim": 0.8},
	{"i": 2, "dx": -430, "dy": 430, "s": 0.36, "r": -42, "z": 200, "tx": -0.5, "ty": -0.2, "dim": 0.85},
	{"i": 0, "dx": 95, "dy": -470, "s": 0.2, "r": 70, "z": 420, "tx": 0.6, "ty": 0.4},
	{"i": 2, "dx": 690, "dy": 330, "s": 0.62, "r": 12, "z": 900, "tx": 0.3, "ty": 0.25, "near": true},
	{"i": 1, "dx": -760, "dy": -300, "s": 0.5, "r": -120, "z": 780, "tx": -0.2, "ty": 0.5, "near": true},
	{"i": 3, "dx": 520, "dy": -160, "s": 0.12, "r": 40, "z": -120, "tx": 0.7, "ty": 0.1, "dim": 0.6},
	{"i": 0, "dx": -260, "dy": -260, "s": 0.1, "r": -60, "z": -60, "tx": 0.2, "ty": -0.7, "dim": 0.6},
	{"i": 1, "dx": 380, "dy": 250, "s": 0.09, "r": 100, "z": 60, "tx": -0.6, "ty": 0.3, "dim": 0.7},
]

var camera: Camera3D
var S := {}
var _mats_violet: Array[ShaderMaterial] = []
var _mats_ink: Array[ShaderMaterial] = []
var _plane_violet := Vector4.ZERO
var _hub_w := Vector3.ZERO
var _tex := {}

var _violet_plane: MeshInstance3D
var _rift_mat: ShaderMaterial
var _ink_vig: MeshInstance3D
var _hush: MeshInstance3D
var _menu_glow: MeshInstance3D
var _mov := {}
var _parts := {}
var _thick := {}
var _rain: Array = []
var _motes: Array = []
var _debris: Array = []
var _hands := {}
var _hub_parts: Array[MeshInstance3D] = []
var _rosette: MeshInstance3D
var _seam: Node3D
var _seam_lines: Array[MeshInstance3D] = []
var _seam_aura: MeshInstance3D
var _glint: MeshInstance3D
var _flash: MeshInstance3D
var _mark_halves: Array = []
var _mark_accent_mats: Array[ShaderMaterial] = []
var _readout: Array[Label3D] = []
var rake: OmniLight3D
var seam_lamp: OmniLight3D
var _rng := RandomNumberGenerator.new()
var _ink_bg: MeshInstance3D
var _iris: Node3D
var _petals: Array = []


func k_at(z: float) -> float:
	return (D - z) / D


func to_world(sx: float, sy: float, z: float) -> Vector3:
	var k := k_at(z)
	return Vector3((sx - W * 0.5) * k, (H * 0.5 - sy) * k, z)


func tex(name: String) -> Texture2D:
	if not _tex.has(name):
		_tex[name] = load(DIR + name + ".png")
	return _tex[name]


# ---------------------------------------------------------------- 材质
func lit_mat(t: Texture2D, n: Texture2D, tint: Color, glow_col: Color, glow: float, opacity: float = 1.0, metal: float = 0.85, rough: float = 0.3, side: String = "") -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = LIT_SHADER
	m.set_shader_parameter("tex", t)
	m.set_shader_parameter("nrm", n)
	m.set_shader_parameter("use_nrm", n != null)
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("glow_col", glow_col)
	m.set_shader_parameter("glow", glow)
	m.set_shader_parameter("metal", metal)
	m.set_shader_parameter("rough", rough)
	m.set_shader_parameter("opacity", opacity)
	m.set_meta("base", opacity)
	m.set_meta("tint0", tint)
	_side(m, side)
	return m


func flat_mat(t: Texture2D, tint: Color = Color.WHITE, opacity: float = 1.0, tex_rgb: float = 1.0, side: String = "") -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = FLAT_SHADER
	m.set_shader_parameter("tex", t)
	m.set_shader_parameter("use_tex", t != null)
	m.set_shader_parameter("tex_rgb", tex_rgb)
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("opacity", opacity)
	m.set_meta("base", opacity)
	_side(m, side)
	return m


func add_mat(t: Texture2D, tint: Color = Color.WHITE, opacity: float = 1.0, side: String = "") -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = ADD_SHADER
	m.set_shader_parameter("tex", t)
	m.set_shader_parameter("use_tex", t != null)
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("opacity", opacity)
	m.set_meta("base", opacity)
	_side(m, side)
	return m


func _side(m: ShaderMaterial, side: String) -> void:
	if side == "violet":
		_mats_violet.append(m)
	elif side == "ink":
		_mats_ink.append(m)


static func op(mi: GeometryInstance3D, v: float) -> void:
	var m := mi.material_override as ShaderMaterial
	m.set_shader_parameter("opacity", v)


static func base(mi: GeometryInstance3D) -> float:
	return float((mi.material_override as ShaderMaterial).get_meta("base", 1.0))


func pivot_quad(w: float, h: float, px: float, py: float, scale: float, z: float, mat: Material) -> MeshInstance3D:
	var k := k_at(z) * scale
	var q := QuadMesh.new()
	q.size = Vector2(w * k, h * k)
	q.center_offset = Vector3((w * 0.5 - px) * k, (py - h * 0.5) * k, 0.0)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func meta_quad(key: String, scale: float, z: float, mat: Material) -> MeshInstance3D:
	var m: Array = META[key]
	return pivot_quad(m[2], m[3], m[0], m[1], scale, z, mat)


## 只取贴图里以支点为中心、半径 r_px 的一块做面片（五圈各自只画自己那圈，省掉大片透明的过绘）
func crop_quad(key: String, r_px: float, scale: float, z: float, mat: Material) -> MeshInstance3D:
	var m: Array = META[key]
	var px: float = m[0]
	var py: float = m[1]
	var tw: float = m[2]
	var th: float = m[3]
	var k := k_at(z) * scale
	var x0 := maxf(0.0, px - r_px)
	var x1 := minf(tw, px + r_px)
	var y0 := maxf(0.0, py - r_px)
	var y1 := minf(th, py + r_px)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corners := [Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)]
	for idx in [0, 1, 2, 0, 2, 3]:
		var c: Vector2 = corners[idx]
		st.set_normal(Vector3(0, 0, 1))
		st.set_uv(Vector2(c.x / tw, c.y / th))
		st.add_vertex(Vector3((c.x - px) * k, -(c.y - py) * k, 0.0))
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func place(n: Node3D, sx: float, sy: float, z: float) -> void:
	n.position = to_world(sx, sy, z)


func circle_tex(r_in: float, r_out: float, size: int = 128) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := (size - 1) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x - c, y - c).length() / c
			var a := clampf((r_out - d) * c, 0.0, 1.0) * clampf((d - r_in) * c + (1.0 if r_in <= 0.0 else 0.0), 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


# ---------------------------------------------------------------- 搭场景
func build() -> void:
	_rng.seed = 9071
	camera = Camera3D.new()
	camera.fov = FOV
	camera.near = 20.0
	camera.far = 9000.0
	add_child(camera)
	camera.current = true
	_hub_w = to_world(HUB.x, HUB.y, 0.0)
	var nv := Vector3(ACROSS.x, -ACROSS.y, 0.0)
	_plane_violet = Vector4(nv.x, nv.y, nv.z, -nv.dot(_hub_w))

	# 底：纯邃鸦墨暗夜 + 赛璐璐干笔刀光裂口场
	var field_z := -900.0
	var ink := pivot_quad(W * 5, H * 5, W * 2.5, H * 2.5, 1.0, field_z - 10, flat_mat(null, INK))
	ink.position = Vector3(0, 0, field_z - 10)
	add_child(ink)
	_ink_bg = ink
	_ink_vig = pivot_quad(W, H, W * 0.5, H * 0.5, 1.08, field_z - 5, flat_mat(tex("ink_vignette"), Color.WHITE, 0.85))
	_ink_vig.position = Vector3(0, 0, field_z - 5)
	add_child(_ink_vig)

	var vz := field_z + 40.0
	_rift_mat = ShaderMaterial.new()
	_rift_mat.shader = RIFT_SHADER
	_rift_mat.set_shader_parameter("plane_k", k_at(vz))
	_rift_mat.set_shader_parameter("across_dir", Vector2(ACROSS.x, -ACROSS.y))
	_rift_mat.set_shader_parameter("along_dir", Vector2(ALONG.x, -ALONG.y))
	_rift_mat.set_meta("base", 1.0)
	_side(_rift_mat, "violet")
	_violet_plane = pivot_quad(W * 4.2, H * 4.2, W * 2.1, H * 2.1, 1.0, vz, _rift_mat)
	add_child(_violet_plane)

	# 机芯：保留原版哥特钟盘与多层齿轮，提纯冷钢明暗对比（左半边冷银铸铁，右半边暗墨配主色受光刃边）
	for side in ["ink", "violet"]:
		var is_ink: bool = side == "ink"
		var g := Node3D.new()
		add_child(g)
		_mov[side] = g
		var P := {}
		var TH := {}
		for ri in RING_KEYS.size():
			var rk: String = RING_KEYS[ri]
			var rz: float = RING_Z[ri]
			var rm := lit_mat(tex("dial"), tex("dial_n"),
				Color("#d8d3c8") if is_ink else Color("#b89eff"), Color("#9e988e") if is_ink else Color("#11082e"),
				0.34 if is_ink else 0.72, 0.66 if is_ink else 0.82, 0.86, 0.34, side)
			rm.set_shader_parameter("ring", Vector2(float(RINGS[ri][0]), float(RINGS[ri][1])))
			var rq := crop_quad("dial", float(RINGS[ri][1]) + 4.0, 1.12, rz, rm)
			place(rq, HUB.x, HUB.y, rz)
			P[rk] = rq
			# 铸铁厚度：同一圈往后叠几层暗片（离得越远投影越小，正面看是一圈暗色内沿，侧面看是厚边）
			var slabs: Array = []
			for j in THICK_N:
				var tm := lit_mat(tex("dial"), null, Color("#24212b") if is_ink else Color("#160b33"), Color.BLACK, 0.0,
					0.95 if is_ink else 0.9, 0.7, 0.5, side)
				tm.set_shader_parameter("ring", Vector2(float(RINGS[ri][0]), float(RINGS[ri][1])))
				var tq := MeshInstance3D.new()
				tq.mesh = rq.mesh
				tq.material_override = tm
				tq.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				tq.position.z = -THICK_STEP * float(j + 1)
				rq.add_child(tq)
				slabs.append(tq)
			TH[rk] = slabs
		_thick[side] = TH
		P["gear_main"] = meta_quad("gear_main", 1.02, -300.0, lit_mat(tex("gear_main"), tex("gear_main_n"),
			Color("#ded8cd") if is_ink else Color("#9e82ff"), Color("#7f7970") if is_ink else Color("#1a0c42"),
			0.45 if is_ink else 0.75, 0.56 if is_ink else 0.76, 0.84, 0.34, side))
		place(P["gear_main"], HUB.x - 104, HUB.y - 62, -300.0)
		P["gear_escape"] = meta_quad("gear_escape", 0.78, -240.0, lit_mat(tex("gear_escape"), tex("gear_escape_n"),
			Color("#eee9df") if is_ink else Color("#ab94ff"), Color("#9f9990") if is_ink else Color("#160a38"),
			0.5 if is_ink else 0.78, 0.62 if is_ink else 0.82, 0.84, 0.32, side))
		place(P["gear_escape"], HUB.x + 70, HUB.y - 166, -240.0)
		P["pallet_fork"] = meta_quad("pallet_fork", 0.55, -200.0, lit_mat(tex("pallet_fork"), tex("pallet_fork_n"),
			Color("#ffffff") if is_ink else Color("#b59eff"), Color("#b8b2a8") if is_ink else Color("#140933"),
			0.56 if is_ink else 0.78, 0.72 if is_ink else 0.88, 0.84, 0.32, side))
		place(P["pallet_fork"], HUB.x + 92, HUB.y - 334, -200.0)
		for key in P:
			g.add_child(P[key])
		_parts[side] = P

	# 钟窗光圈：把表盘里圈（花格 + 机芯）切成 8 瓣真三维花瓣，铰链在罗马数字环内沿，
	# 打开时每瓣绕铰链朝镜头翻开、整组顺时针旋开（像相机光圈），露出钟后面的章节世界
	_iris = Node3D.new()
	add_child(_iris)
	place(_iris, HUB.x, HUB.y, -420.0)
	var kq := k_at(-420.0) * 1.12
	for i in PETALS:
		var a := (float(i) + 0.5) * TAU / PETALS
		var hinge := Vector3(cos(a), -sin(a), 0.0) * HOLE_PX * kq
		var piv := Node3D.new()
		piv.position = hinge
		_iris.add_child(piv)
		var pm := lit_mat(tex("dial"), tex("dial_n"), Color("#d8d3c8"), Color("#9e988e"), 0.34, 1.0, 0.86, 0.34)
		pm.set_shader_parameter("wedge", Vector3(a, PI / PETALS + 0.004, HOLE_PX + 1.0))
		var q := meta_quad("dial", 1.12, -420.0, pm)
		q.position = -hinge
		piv.add_child(q)
		_petals.append({"piv": piv, "q": q, "m": pm, "a": a, "hinge": hinge})
	_iris.visible = false

	# 负空间静场压暗：左上稳托《断晓》字标，右下稳托刀锋宋菜单（根治菜单字与机芯线打架）
	var hz := -150.0
	_hush = pivot_quad(1320, 1320, 660, 660, 1.0, hz, flat_mat(null, Color(0.031, 0.028, 0.044, 0.94), 1.0, 1.0, "ink"))
	(_hush.material_override as ShaderMaterial).set_shader_parameter("radial", 1.0)
	place(_hush, 390, 470, hz)
	add_child(_hush)
	_menu_glow = pivot_quad(1260, 1260, 630, 630, 1.0, hz, flat_mat(null, Color(0.055, 0.026, 0.16, 0.84), 1.0, 1.0, "violet"))
	(_menu_glow.material_override as ShaderMaterial).set_shader_parameter("radial", 1.0)
	place(_menu_glow, 1450, 580, hz)
	add_child(_menu_glow)

	# 雨：三层纵深
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	quad.center_offset = Vector3(0, 0.5, 0)
	for L in [{"z": -620.0, "n": 110, "len": [22.0, 72.0], "w": [1.2, 2.1], "a": 0.38},
			{"z": -60.0, "n": 64, "len": [32.0, 108.0], "w": [1.5, 2.6], "a": 0.48},
			{"z": 620.0, "n": 24, "len": [90.0, 250.0], "w": [3.0, 5.0], "a": 0.28}]:
		var drops: Array = []
		for i in int(L["n"]):
			drops.append({"u": _rng.randf() * 3000 - 1500, "v": _rng.randf() * 3000 - 1500,
				"len": lerpf(L["len"][0], L["len"][1], _rng.randf()), "w": lerpf(L["w"][0], L["w"][1], _rng.randf()), "k": _rng.randf()})
		var meshes := {}
		for side in ["ink", "violet"]:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = quad
			mm.instance_count = int(L["n"])
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.material_override = flat_mat(null, WHITE if side == "ink" else Color("#0b0520"),
				float(L["a"]) * (0.46 if side == "ink" else 0.72), 1.0, side)
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.custom_aabb = AABB(Vector3(-6000, -6000, -2000), Vector3(12000, 12000, 4000))
			add_child(mmi)
			meshes[side] = mmi
		_rain.append({"z": L["z"], "drops": drops, "meshes": meshes})

	# 光尘
	for L in [{"n": 64, "z": [-500.0, 200.0], "size": [4.5, 11.0], "a": 0.68}, {"n": 14, "z": [500.0, 900.0], "size": [54.0, 125.0], "a": 0.1}]:
		var data: Array = []
		for i in int(L["n"]):
			data.append({"u": _rng.randf() * 2400 - 1200, "v": (_rng.randf() - 0.5) * 1600 * (0.35 + _rng.randf() * 0.65),
				"z": lerpf(L["z"][0], L["z"][1], _rng.randf()), "sp": 8 + _rng.randf() * 26, "ph": _rng.randf() * TAU,
				"size": lerpf(L["size"][0], L["size"][1], _rng.randf())})
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		var q := QuadMesh.new()
		q.size = Vector2(1, 1)
		mm.mesh = q
		mm.instance_count = int(L["n"])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = add_mat(null, Color("#b99eff"), float(L["a"]))
		mmi.custom_aabb = AABB(Vector3(-6000, -6000, -2000), Vector3(12000, 12000, 4000))
		add_child(mmi)
		_motes.append({"mmi": mmi, "data": data})

	# 悬停钟面碎片
	for p in DEBRIS:
		var key := "shard_%d" % int(p["i"])
		var t := tex(key)
		var w := float(t.get_width())
		var h := float(t.get_height())
		var g := Node3D.new()
		var sh := pivot_quad(w, h, w * 0.5, h * 0.5, float(p["s"]), 0.0, flat_mat(t, Color("#060509"), 0.6, 0.0))
		sh.position = Vector3(9, -10, -14)
		var edge := pivot_quad(w, h, w * 0.5, h * 0.5, float(p["s"]), 0.0, flat_mat(t, Color("#2a2440"), 0.9, 0.0))
		edge.position = Vector3(0, 0, -4)
		var face := pivot_quad(w, h, w * 0.5, h * 0.5, float(p["s"]), 0.0, lit_mat(t, tex(key + "_n"), Color.WHITE, Color("#ece7df"), 0.58, float(p.get("dim", 1.0)), 0.72, 0.3))
		g.add_child(sh)
		g.add_child(edge)
		g.add_child(face)
		add_child(g)
		_debris.append({"p": p, "g": g, "face": face, "sh": sh, "edge": edge, "edge_mat": edge.material_override as ShaderMaterial})

	# 双剑指针与中枢轮毂
	var zh := 60.0
	var zm := 90.0
	_hands["hour_sh"] = meta_quad("hand_hour", 0.355, zh - 30, flat_mat(tex("hand_hour"), Color("#060509"), 0.88, 0.0))
	_hands["hour"] = meta_quad("hand_hour", 0.355, zh, lit_mat(tex("hand_hour"), tex("hand_hour_n"), Color.WHITE, Color.WHITE, 0.8, 1.0, 0.75, 0.26))
	_hands["minute_sh"] = meta_quad("hand_minute", 0.43, zm - 30, flat_mat(tex("hand_minute"), Color("#060509"), 0.88, 0.0))
	_hands["minute"] = meta_quad("hand_minute", 0.43, zm, lit_mat(tex("hand_minute"), tex("hand_minute_n"), Color.WHITE, Color.WHITE, 0.82, 1.0, 0.75, 0.26))
	for key in ["hour_sh", "hour", "minute_sh", "minute"]:
		add_child(_hands[key])
	place(_hands["minute"], HUB.x, HUB.y, zm)
	place(_hands["minute_sh"], HUB.x + 7, HUB.y + 8, zm - 30)
	var zb := 120.0
	var disc := circle_tex(0.0, 1.0)
	var hub_disc := pivot_quad(2, 2, 1, 1, 299 * 0.195 * 1.12, zb - 6, flat_mat(disc, INK, 0.92))
	place(hub_disc, HUB.x, HUB.y, zb - 6)
	_rosette = meta_quad("rosette", 0.195, zb, lit_mat(tex("rosette"), tex("rosette_n"), Color.WHITE, WHITE, 0.82, 1.0, 0.8, 0.25))
	place(_rosette, HUB.x, HUB.y, zb)
	var pin := pivot_quad(2, 2, 1, 1, 11, zb + 4, flat_mat(disc, INK))
	place(pin, HUB.x, HUB.y, zb + 4)
	var ring := pivot_quad(2, 2, 1, 1, 12.5, zb + 5, flat_mat(circle_tex(0.8, 1.0), Color("#d4cfc6")))
	place(ring, HUB.x, HUB.y, zb + 5)
	var dot := pivot_quad(2, 2, 1, 1, 4, zb + 6, flat_mat(disc, WHITE))
	place(dot, HUB.x, HUB.y, zb + 6)
	for n in [hub_disc, _rosette, pin, ring, dot]:
		add_child(n)
		_hub_parts.append(n)

	# 28° 刀光斩缝：亮白刃芯 + 主色辉光刃晕 + 寒铁掠光
	var sz := 20.0
	var sk := k_at(sz)
	_seam = Node3D.new()
	add_child(_seam)
	place(_seam, HUB.x, HUB.y, sz)
	_seam.rotation.z = -TWELVE
	_seam_aura = pivot_quad(5400, 34.0, 2700, 17.0, 1.0, sz - 2, add_mat(null, Color("#8f63ff"), 0.55))
	_seam_aura.position.z = -2
	_seam.add_child(_seam_aura)
	for spec in [[7.4, 0.0, Color(1.22, 1.2, 1.25), 0.98], [2.2, -5.8, INK, 0.88], [2.2, 5.8, INK, 0.88]]:
		var line := pivot_quad(5400, float(spec[0]), 2700, float(spec[0]) * 0.5, 1.0, sz, flat_mat(null, spec[2], spec[3]))
		line.position.y = -float(spec[1]) * sk
		_seam.add_child(line)
		_seam_lines.append(line)
	_glint = pivot_quad(440, 8.5, 220, 4.25, 1.0, sz + 2, flat_mat(null, Color(1.5, 1.48, 1.55), 0.0))
	(_glint.material_override as ShaderMaterial).set_shader_parameter("band", Vector2(0.5, 0.5))
	_glint.position.z = 2
	_seam.add_child(_glint)
	_flash = pivot_quad(5400, 1.8, 2700, 0.9, 1.0, sz + 4, add_mat(null, Color(1.6, 1.56, 1.72), 0.0))
	_flash.position.z = 4
	_seam.add_child(_flash)

	# 05:59 临界司辰读数
	var font := FontVariation.new()
	font.base_font = load("res://assets/fonts/gothic/Cinzel-VF.ttf")
	font.variation_opentype = {"wght": 800}
	for i in 2:
		var lb := Label3D.new()
		lb.text = "05:59"
		lb.font = font
		lb.font_size = 54
		lb.outline_size = 6 if i == 1 else 0
		lb.outline_modulate = INK
		lb.modulate = INK if i == 0 else WHITE
		lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		lb.shaded = false
		lb.double_sided = true
		lb.alpha_cut = Label3D.ALPHA_CUT_DISABLED
		var z := 30.0 + i
		lb.pixel_size = k_at(z)
		var x := HUB.x + ALONG.x * 292 - ACROSS.x * 78 + (5 if i == 0 else 0)
		var y := HUB.y + ALONG.y * 292 - ACROSS.y * 78 + (5 if i == 0 else 0)
		place(lb, x - 110, y, z)
		add_child(lb)
		_readout.append(lb)

	# 主字标《断晓》：改用纯净锋利的实心刀锋剪影（去掉旧版漫画斜排线），主色背刃 + 鸦墨厚边 + 骨白锋面三层错位斩开
	var mw := 760.0
	var mh := mw * 806.0 / 1240.0
	for sign_v in [-1, 1]:
		var layers: Array = []
		var specs := [
			[tex("mark_silhouette"), 0.0, 11.0, 11.0, "accent"],
			[tex("mark_silhouette"), 20.0, 5.5, 6.5, "ink"],
			[tex("mark_silhouette"), 40.0, 0.0, 0.0, "bone"],
		]
		for s in specs:
			var mat: ShaderMaterial
			if s[4] == "bone":
				mat = flat_mat(s[0], WHITE, 1.0, 0.0)
			elif s[4] == "accent":
				mat = flat_mat(s[0], VIOLET, 1.0, 0.0)
				_mark_accent_mats.append(mat)
			else:
				mat = flat_mat(s[0], INK, 1.0, 0.0)
			var z := 170.0 + float(s[1])
			var mi := pivot_quad(mw, mh, mw * 0.5, mh * 0.5, 1.0, z, mat)
			mi.rotation.z = 5.5 * DEG
			add_child(mi)
			layers.append({"mi": mi, "z": z, "dx": s[2], "dy": s[3]})
		_mark_halves.append({"sign": sign_v, "layers": layers})

	# 三维动态灯光
	rake = OmniLight3D.new()
	rake.light_color = Color("#f7f2ea")
	rake.omni_range = 30000.0
	rake.omni_attenuation = 0.0
	rake.light_energy = 2.15
	rake.light_specular = 0.85
	rake.light_cull_mask = 1   # 只照钟体，不照第 2 层的选章画片
	add_child(rake)
	seam_lamp = OmniLight3D.new()
	seam_lamp.light_color = Color("#b99eff")
	seam_lamp.omni_range = 30000.0
	seam_lamp.omni_attenuation = 0.0
	seam_lamp.light_energy = 1.15
	seam_lamp.light_cull_mask = 1
	add_child(seam_lamp)

	S = default_state()


## 实时切换四位女主主色（朔·冷紫 / 萤·幽青 / 薇·烈红 / 曜·流金），零全屏滤镜偏色、零异色残留
func set_palette(pal: Dictionary) -> void:
	var c_core: Color = pal.get("core", Color("#faf7ff"))
	var c_bright: Color = pal.get("bright", Color("#8f63ff"))
	var c_mid: Color = pal.get("mid", Color("#5224d6"))
	var c_deep: Color = pal.get("deep", Color("#1e0b5c"))
	var c_abyss: Color = pal.get("abyss", Color("#0b0521"))
	if _rift_mat != null:
		_rift_mat.set_shader_parameter("col_core", c_core)
		_rift_mat.set_shader_parameter("col_bright", c_bright)
		_rift_mat.set_shader_parameter("col_mid", c_mid)
		_rift_mat.set_shader_parameter("col_deep", c_deep)
		_rift_mat.set_shader_parameter("col_abyss", c_abyss)
	if _parts.has("violet"):
		var pv: Dictionary = _parts["violet"]
		var rim := c_bright.lerp(Color.WHITE, 0.32)
		var dark_glow := c_abyss.darkened(0.15)
		for k in RING_KEYS + ["gear_main", "gear_escape", "pallet_fork"]:
			var m := (pv[k] as MeshInstance3D).material_override as ShaderMaterial
			m.set_shader_parameter("tint", rim)
			m.set_meta("pal_tint", rim)
			m.set_shader_parameter("glow_col", dark_glow)
	if _menu_glow != null:
		var mg := _menu_glow.material_override as ShaderMaterial
		mg.set_shader_parameter("tint", Color(c_abyss.r, c_abyss.g, c_abyss.b, 0.82))
	if _seam_aura != null:
		(_seam_aura.material_override as ShaderMaterial).set_shader_parameter("tint", c_bright)
	if seam_lamp != null:
		seam_lamp.light_color = c_bright.lerp(Color.WHITE, 0.25)
	for M in _motes:
		var mm_mat := (M["mmi"] as MultiMeshInstance3D).material_override as ShaderMaterial
		mm_mat.set_shader_parameter("tint", c_bright.lerp(Color.WHITE, 0.45))
	for D_ in _debris:
		(D_["edge_mat"] as ShaderMaterial).set_shader_parameter("tint", c_deep.lightened(0.12))
	for m in _mark_accent_mats:
		m.set_shader_parameter("tint", c_bright)
	for L in _rain:
		var rm := (L["meshes"]["violet"] as MultiMeshInstance3D).material_override as ShaderMaterial
		rm.set_shader_parameter("tint", c_abyss.darkened(0.25))


func default_state() -> Dictionary:
	return {
		"t": 0.0, "view": {"hx": HUB.x, "hy": HUB.y, "z": 1.0, "r": 0.0}, "parallax": Vector2.ZERO, "dolly": 0.0,
		"violet": 1.0, "slip": 44.0, "slip_z": -140.0, "kick": Vector2.ZERO, "dial_reveal": 1.0, "dial_a": 1.0,
		"hour_a": 1.0, "hour_thrust": 0.0, "hour_angle": REST, "minute_a": 1.0, "minute_angle": TWELVE - GAP,
		"hub_a": 1.0, "seam_a": 1.0, "flash": 0.0, "pulse": 0.0, "debris": 1.0, "burst": 1.0,
		"mark": [1.0, 1.0, 1.0], "mark_split": 1.0, "mark_a": 1.0,
		"rain_a": 1.0, "fall": 0.0, "smear": 0.0, "motes_a": 1.0, "light_a": -0.6, "light_k": 1.0, "glint": 1.0,
		"home_a": 1.0, "esc": 0.0, "pallet": 0.0, "gear_spin": 0.0, "readout_a": 1.0, "split": 0.0,
		# 11-17 钟动效：五圈各自的转角偏移 / 前后偏移 / 翻转（x, y 弧度）/ 不透明度；两半的翻转；字标两半各自进度
		"ring_rot": [0.0, 0.0, 0.0, 0.0, 0.0], "ring_dz": [0.0, 0.0, 0.0, 0.0, 0.0],
		"ring_tilt": [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO],
		"ring_a": [1.0, 1.0, 1.0, 1.0, 1.0], "half_tilt": 0.0, "mark_half": [1.0, 1.0], "mark_kick": 0.0,
	}


func apply_camera(view: Dictionary, par: Vector2, dolly: float) -> void:
	var z: float = view["z"]
	var r: float = view["r"]
	var dx: float = (W * 0.5 - float(view["hx"])) / z
	var dy: float = (H * 0.5 - float(view["hy"])) / z
	var cr := cos(-r)
	var sr := sin(-r)
	var sx := HUB.x + dx * cr - dy * sr
	var sy := HUB.y + dx * sr + dy * cr
	var look := to_world(sx, sy, 0.0)
	var pos := Vector3(look.x + par.x * 46.0, look.y - par.y * 30.0, D / z + dolly)
	camera.look_at_from_position(pos, look, Vector3(sin(-r), cos(-r), 0.0))


func update(st: Dictionary) -> void:
	for k in st:
		S[k] = st[k]
	var t: float = S["t"]
	apply_camera(S["view"], S["parallax"], S["dolly"])
	# 选章：镜头交给三维钟轮画片机位接管（cam_blend 0→1 一镜到底），cam_arc 让镜头沿钟轮外缘绕过去
	var cb := float(S.get("cam_blend", 0.0))
	camera.fov = lerpf(FOV, float(S.get("cam_fov", FOV)), clampf(cb, 0.0, 1.0)) if S.has("cam_fov") else FOV
	if cb > 0.0001 and S.has("cam_xf"):
		var X := camera.global_transform.interpolate_with(S["cam_xf"] as Transform3D, cb)
		X.origin += (S.get("cam_arc", Vector3.ZERO) as Vector3) * 4.0 * cb * (1.0 - cb)
		var rl := float(S.get("cam_roll", 0.0))
		if rl != 0.0:
			X.basis = X.basis * Basis(Vector3.BACK, rl)
		var shk: Vector2 = S.get("cam_shake", Vector2.ZERO)
		X.origin += (X.basis.x * shk.x - X.basis.y * shk.y) * 0.8 * cb
		camera.global_transform = X
	var violet: float = S["violet"]
	var home_a: float = S["home_a"]
	var pulse: float = float(S.get("pulse", 0.0))
	var split: float = S["split"]

	var slide := (1.0 - violet) * 2200.0
	var shift := slide - float(S.get("flood", 0.0))
	var sh := Vector3(ACROSS.x * shift, -ACROSS.y * shift, 0.0)
	var shp := Vector3(ACROSS.x * slide, -ACROSS.y * slide, 0.0)
	var vz := -860.0
	var cut_w := to_world(HUB.x, HUB.y, vz) + shp * k_at(vz) + Vector3(ACROSS.x, -ACROSS.y, 0) * (split * 0.5) * k_at(vz)
	_violet_plane.position = cut_w
	_violet_plane.visible = violet > 0.001
	op(_violet_plane, float(S.get("rift_a", 1.0)))
	_rift_mat.set_shader_parameter("cut_origin", cut_w)
	_rift_mat.set_shader_parameter("time_sec", t)
	_rift_mat.set_shader_parameter("pulse", pulse + float(S["flash"]) * 0.8)

	var hubw := _hub_w + sh
	var nv := Vector3(_plane_violet.x, _plane_violet.y, _plane_violet.z)
	var pv := Vector4(nv.x, nv.y, nv.z, -nv.dot(hubw + nv * split * 0.5))
	var pi := Vector4(-nv.x, -nv.y, -nv.z, nv.dot(hubw - nv * split * 0.5))
	for m in _mats_violet:
		m.set_shader_parameter("clip_plane", pv)
	for m in _mats_ink:
		m.set_shader_parameter("clip_plane", pi)

	# 机芯
	var rv: float = S["dial_reveal"]
	var r_rot: Array = S["ring_rot"]
	var r_dz: Array = S["ring_dz"]
	var r_tl: Array = S["ring_tilt"]
	var r_a: Array = S["ring_a"]
	var h_tilt := float(S["half_tilt"])
	var along_w := Vector3(ALONG.x, -ALONG.y, 0.0).normalized()
	for side in ["ink", "violet"]:
		var P: Dictionary = _parts[side]
		var sl: float = float(S["slip"]) * violet if side == "violet" else 0.0
		var g: Node3D = _mov[side]
		var sp := split * 0.5 * (1.0 if side == "violet" else -1.0)
		g.position = Vector3(-ALONG.x * sl + ACROSS.x * sp, ALONG.y * sl - ACROSS.y * sp, float(S["slip_z"]) * violet if side == "violet" else 0.0)
		# 两半各自绕斩缝方向翻一点（斩开那一下：紫半边往外翻得多，墨半边反向少翻一点）
		g.basis = Basis(along_w, h_tilt * (1.0 if side == "violet" else -0.4)) if absf(h_tilt) > 0.00001 else Basis()
		P["gear_main"].rotation.z = -float(S["gear_spin"])
		P["gear_escape"].rotation.z = -float(S["esc"])
		P["pallet_fork"].rotation.z = -(float(S["pallet"]) + 18.0) * DEG
		var e := 1.0 - pow(2.0, -10.0 * rv) if rv < 1.0 else 1.0
		var face_k := clampf(rv * 1.4, 0, 1) * float(S["dial_a"]) * (violet if side == "violet" else 1.0) * float(S.get("dial_face_a", 1.0))
		var TH: Dictionary = _thick[side]
		for ri in RING_KEYS.size():
			var rk: String = RING_KEYS[ri]
			var rq: MeshInstance3D = P[rk]
			var tl: Vector2 = r_tl[ri]
			rq.position = to_world(HUB.x, HUB.y, float(RING_Z[ri])) + Vector3(0.0, 0.0, float(r_dz[ri]))
			rq.rotation = Vector3(tl.x, tl.y, -TILT + (1.0 - e) * 1.4 - float(S.get("dial_spin", 0.0)) - float(r_rot[ri]))
			rq.scale = Vector3.ONE * (0.82 + 0.18 * e)
			var ra := face_k * float(r_a[ri])
			op(rq, base(rq) * ra)
			rq.visible = ra > 0.002
			for slab: MeshInstance3D in TH[rk]:
				op(slab, base(slab) * ra)
			if side == "ink":
				var m_r := rq.material_override as ShaderMaterial
				var t0r: Color = m_r.get_meta("tint0", Color.WHITE)
				m_r.set_shader_parameter("tint", t0r.lerp(S.get("ink_tint", t0r), float(S.get("ink_tint_k", 0.0))))
		for key in ["gear_main", "gear_escape", "pallet_fork"]:
			op(P[key], base(P[key]) * clampf(rv * 1.4, 0, 1) * float(S["dial_a"]) * (violet if side == "violet" else 1.0) * float(r_a[0]))
			if side == "ink":
				var m_ink := (P[key] as MeshInstance3D).material_override as ShaderMaterial
				var t0: Color = m_ink.get_meta("tint0", Color.WHITE)
				m_ink.set_shader_parameter("tint", t0.lerp(S.get("ink_tint", t0), float(S.get("ink_tint_k", 0.0))))
	# 钟窗光圈：iris 0 = 表盘完整；>0 表盘开孔，花瓣翻开；1 = 全开只剩罗马数字环
	var iris := float(S.get("iris", 0.0))
	var ink_dial: MeshInstance3D = _parts["ink"]["dial"]
	for side in ["ink", "violet"]:
		var P: Dictionary = _parts[side]
		for rk in RING_KEYS:
			var dm := (P[rk] as MeshInstance3D).material_override as ShaderMaterial
			dm.set_shader_parameter("hole_px", HOLE_PX if iris > 0.0005 else -1.0)
			dm.set_shader_parameter("hole_rim", float(S.get("hole_rim", 0.0)))
		var gk := 1.0 - clampf(iris * 3.0, 0.0, 1.0)
		for key in ["gear_main", "gear_escape", "pallet_fork"]:
			# 上面机芯循环本帧已写过不透明度，这里只乘一次：光圈一开，齿轮先散掉
			var gm := (P[key] as MeshInstance3D).material_override as ShaderMaterial
			gm.set_shader_parameter("opacity", float(gm.get_shader_parameter("opacity")) * gk)
		if side == "violet":
			var vk := float(S.get("violet_tint_k", 0.0))
			for key in RING_KEYS + ["gear_main", "gear_escape", "pallet_fork"]:
				var mv := (P[key] as MeshInstance3D).material_override as ShaderMaterial
				var cur: Color = mv.get_meta("pal_tint", mv.get_meta("tint0", Color.WHITE))
				mv.set_shader_parameter("tint", cur.lerp(S.get("ink_tint", cur), vk))
	_iris.visible = iris > 0.0005 and iris < 0.999
	if _iris.visible:
		_iris.rotation.z = ink_dial.rotation.z - 0.55 * (1.0 - pow(1.0 - iris, 3.0))
		var it: Color = ((ink_dial.material_override as ShaderMaterial).get_shader_parameter("tint")) as Color
		for i in _petals.size():
			var pt: Dictionary = _petals[i]
			var pi_ := clampf((iris - float(i) * 0.025) / 0.8, 0.0, 1.0)
			var e := 1.0 - pow(1.0 - pi_, 3.0)
			var a: float = pt["a"]
			var piv: Node3D = pt["piv"]
			piv.position = (pt["hinge"] as Vector3) * (1.0 + 0.22 * e)
			piv.basis = Basis(Vector3(sin(a), cos(a), 0.0), e * 2.1)
			var pm: ShaderMaterial = pt["m"]
			pm.set_shader_parameter("tint", it)
			pm.set_shader_parameter("opacity", float(S["dial_a"]) * (1.0 - smoothstep(0.7, 1.0, pi_)))
	op(_hush, home_a)
	op(_menu_glow, home_a * violet)
	_ink_bg.visible = float(S.get("bg_a", 1.0)) > 0.5
	op(_ink_vig, home_a * 0.85)

	# 雨
	var rs: Vector3 = S.get("rain_shift", Vector3.ZERO)
	var q := Basis(Vector3(0, 0, 1), -TILT)
	for L in _rain:
		var z: float = L["z"]
		var k := k_at(z)
		var speed := 1.6 if z > 0 else (0.6 if z < -300 else 1.0)
		for side in ["ink", "violet"]:
			var mmi: MultiMeshInstance3D = L["meshes"][side]
			op(mmi, base(mmi) * float(S["rain_a"]) * (violet if side == "violet" else 1.0))
			var mm := mmi.multimesh
			var drops: Array = L["drops"]
			for i in drops.size():
				var d: Dictionary = drops[i]
				var u: float = float(d["u"]) - float(S["fall"]) * (0.7 + float(d["k"]) * 0.6) * speed
				u = fposmod(u + 1500.0, 3000.0) - 1500.0
				var sx: float = W * 0.5 + ALONG.x * u + ACROSS.x * float(d["v"])
				var sy: float = H * 0.5 + ALONG.y * u + ACROSS.y * float(d["v"])
				var ln: float = float(d["len"]) + float(S["smear"]) * (36.0 + float(d["k"]) * 70.0) * (2.2 if z > 0 else 1.0)
				var b := q.scaled(Vector3(float(d["w"]) * k, ln * k, 1.0))
				mm.set_instance_transform(i, Transform3D(b, Vector3((sx - W * 0.5) * k + rs.x, (H * 0.5 - sy) * k + rs.y, z)))

	# 光尘
	for M in _motes:
		var mmi: MultiMeshInstance3D = M["mmi"]
		op(mmi, base(mmi) * float(S["motes_a"]))
		var data: Array = M["data"]
		for i in data.size():
			var m: Dictionary = data[i]
			var u: float = fposmod(float(m["u"]) + fmod(t * float(m["sp"]), 2400.0) + 1200.0, 2400.0) - 1200.0
			var v: float = float(m["v"]) + sin(t * 0.4 + float(m["ph"])) * 18.0
			var sx := HUB.x + ALONG.x * u + ACROSS.x * v
			var sy := HUB.y + ALONG.y * u + ACROSS.y * v
			var z: float = m["z"]
			var k := k_at(z)
			mmi.multimesh.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * float(m["size"]) * 2.2 * k), Vector3((sx - W * 0.5) * k, (H * 0.5 - sy) * k, z)))

	# 碎片
	var cyc := floorf(t)
	for j in _debris.size():
		var D_: Dictionary = _debris[j]
		var p: Dictionary = D_["p"]
		var b: float = S["burst"]
		var jx := sin(cyc * 1.7 + j * 3.1) * 2.2
		var jy := cos(cyc * 2.3 + j * 1.3) * 2.2
		var sx: float = HUB.x + (float(p["dx"]) + jx) * b + ACROSS.x * split * 1.4 * (1.0 if float(p["dx"]) > 0 else -1.0)
		var sy: float = HUB.y + (float(p["dy"]) + jy) * b + ACROSS.y * split * 1.4 * (1.0 if float(p["dx"]) > 0 else -1.0)
		var z: float = -200.0 + (float(p["z"]) + 200.0) * b
		var kk := k_at(z)
		var g: Node3D = D_["g"]
		var kick: Vector2 = S["kick"]
		var kd := (z + 260.0) / 520.0
		sx += kick.x * kd
		sy += kick.y * kd
		g.position = Vector3((sx - W * 0.5) * kk, (H * 0.5 - sy) * kk, z)
		g.scale = Vector3.ONE * kk * (0.4 + 0.6 * b)
		var spin := (1.0 - b) * 5.0
		g.rotation = Vector3(float(p["ty"]) * 0.5 + spin * float(p["ty"]) + sin(t * 0.7 + j) * 0.08,
			float(p["tx"]) * 0.5 + spin * float(p["tx"]) + cos(t * 0.6 + j) * 0.1,
			-(float(p["r"]) + sin(cyc * 0.9 + j) * 0.9) * DEG - spin)
		var a: float = float(S["debris"]) * float(p.get("dim", 1.0)) * (home_a if p.get("near", false) else 1.0)
		op(D_["face"], a)
		op(D_["sh"], 0.6 * a)
		op(D_["edge"], 0.9 * a)
		g.visible = a > 0.005

	# 指针
	var ha: float = S["hour_angle"]
	var thrust: float = S["hour_thrust"]
	_hands["hour"].rotation.z = -ha
	_hands["hour_sh"].rotation.z = -ha
	place(_hands["hour"], HUB.x - cos(ha) * thrust, HUB.y - sin(ha) * thrust, 60.0)
	place(_hands["hour_sh"], HUB.x - cos(ha) * thrust + 7, HUB.y - sin(ha) * thrust + 8, 30.0)
	op(_hands["hour"], float(S["hour_a"]))
	op(_hands["hour_sh"], 0.88 * float(S["hour_a"]))
	var ma: float = S["minute_angle"]
	_hands["minute"].rotation.z = -ma
	_hands["minute_sh"].rotation.z = -ma
	op(_hands["minute"], float(S["minute_a"]))
	op(_hands["minute_sh"], 0.88 * float(S["minute_a"]))
	for n in _hub_parts:
		op(n, base(n) * float(S["hub_a"]))
	_rosette.rotation.z = -(TILT + float(S["gear_spin"]) * 0.2)

	# 斩缝与辉光
	var seam_vis := float(S["seam_a"]) * (1.0 - clampf(split / 120.0, 0, 1))
	for n in _seam_lines:
		op(n, base(n) * seam_vis)
	op(_seam_aura, (0.48 + pulse * 0.55) * seam_vis)
	_seam_aura.scale.y = 1.0 + pulse * 1.4
	var sk := k_at(20.0)
	var gg := fmod(t + 2.1, 5.4)
	var on := 1.0 if gg < 0.68 else 0.0
	var pp := gg / 0.68 if gg < 0.68 else 0.0
	var ee := 4.0 * pp * pp * pp if pp < 0.5 else 1.0 - pow(-2.0 * pp + 2.0, 3.0) / 2.0
	var pos := -820.0 + 1640.0 * ee
	_glint.position.x = pos * sk
	op(_glint, on * float(S["glint"]) * float(S["seam_a"]))
	seam_lamp.position = to_world(HUB.x + ALONG.x * pos, HUB.y + ALONG.y * pos, 160.0)
	seam_lamp.light_energy = (0.7 + 1.5 * on * float(S["glint"]) + float(S["flash"]) * 3.8 + pulse * 1.4) * float(S.get("lamp_k", 1.0))
	var fl: float = S["flash"]
	var flash_chasm := 1.0 - clampf(split / 180.0, 0.0, 1.0)
	_flash.scale.y = 2.0 + fl * 34.0
	op(_flash, fl * flash_chasm)

	# 读数（随左半钟面裂开平移，并在 5:59 倒卷入夜时实时跳回 18:00）
	var rtxt: String = str(S.get("readout_text", "05:59"))
	for i in _readout.size():
		var lb_r: Label3D = _readout[i]
		if lb_r.text != rtxt:
			lb_r.text = rtxt
		lb_r.modulate.a = float(S["readout_a"])
		var rz := 30.0 + i
		var rx := HUB.x + ALONG.x * 246 - ACROSS.x * (72 + split * 0.5) + (3 if i == 0 else 0) - 122.0
		var ry := HUB.y + ALONG.y * 246 - ACROSS.y * (72 + split * 0.5) + (4 if i == 0 else 0) + 18.0
		place(lb_r, rx, ry, rz)

	# 主字标《断晓》
	var spl: float = S["mark_split"]
	var slip_m := spl * 24.0
	var gap_m := spl * 10.0
	var mc := Vector2(396, 462)
	var cut := Vector2(mc.x + 146, mc.y)
	var marks: Array = S["mark"]
	var m_half: Array = S["mark_half"]
	for hi in _mark_halves.size():
		var hh: Dictionary = _mark_halves[hi]
		var sgn: float = hh["sign"]
		# 两半各自从斩缝外侧、朝镜头的方向砸回来（带一点冲过头再弹回）
		var mhp := clampf(float(m_half[hi]), 0.0, 1.0)
		var eh := 1.0 + 2.6 * pow(mhp - 1.0, 3.0) + 1.6 * pow(mhp - 1.0, 2.0)
		var h_off := Vector2(ACROSS.x, ACROSS.y) * sgn * (1.0 - eh) * 340.0
		var h_z := (1.0 - eh) * 900.0
		var ox := (-ALONG.x * slip_m * sgn + ACROSS.x * gap_m * sgn) * 0.5
		var oy := (-ALONG.y * slip_m * sgn + ACROSS.y * gap_m * sgn) * 0.5
		var layers: Array = hh["layers"]
		var cz := 190.0
		var cp := to_world(cut.x + ox, cut.y + oy, cz)
		var n := Vector3(ACROSS.x * sgn, -ACROSS.y * sgn, 0.0)
		var plane := Vector4(n.x, n.y, n.z, -n.dot(cp))
		for li in layers.size():
			var ly: Dictionary = layers[li]
			var p := clampf(float(marks[li]), 0.0, 1.0)
			var e := 1.0 - pow(2.0, -10.0 * p) if p < 1.0 else 1.0
			var z: float = float(ly["z"]) + (1.0 - e) * 1400.0 + h_z
			var fly := (1.0 - e) * -480.0
			var mi: MeshInstance3D = ly["mi"]
			mi.position = to_world(mc.x + float(ly["dx"]) + ox + ALONG.x * fly + h_off.x, mc.y + float(ly["dy"]) + oy + ALONG.y * fly + h_off.y, z)
			mi.scale = Vector3.ONE * (k_at(z) / k_at(float(ly["z"])))
			var m := mi.material_override as ShaderMaterial
			var hp := clampf(p * 4.0, 0, 1) * clampf(mhp * 6.0, 0.0, 1.0) * float(S.get("mark_a", 1.0))
			m.set_shader_parameter("opacity", hp)
			# 裁切面跟着这一半一起走，否则两半错开时会被对方的裁切面切掉
			var cp_h := to_world(cut.x + ox + h_off.x + ALONG.x * fly, cut.y + oy + h_off.y + ALONG.y * fly, z)
			m.set_shader_parameter("clip_plane", Vector4(n.x, n.y, n.z, -n.dot(cp_h)))
			mi.visible = hp > 0.001 and z < camera.global_position.z - 40.0

	# 掠光
	var la: float = S["light_a"]
	var lp := to_world(HUB.x + cos(la) * 980.0, HUB.y + sin(la) * 980.0, 0.0)
	rake.position = Vector3(lp.x, lp.y, -160.0)
	rake.light_energy = 2.15 * float(S["light_k"])
