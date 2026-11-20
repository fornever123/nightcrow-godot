extends Control
## [YG-MARK] 《机关舞台选章》第二版（11-15 首页线）：钟体展开 → 穿环 → 钟落成钟楼 → 景片砸入 → 闪电 → 灯链
## 进入：剑针蓄力斩下 → 钟沿中轴炸成立体分解图（表盘按半径切 5 圈 + 齿轮 + 中心花 + 双剑针），各圈反向转，镜头绕到侧面
##       → 硬停，冷光扫过各圈 → 镜头沿中轴冲进去一圈圈穿过：剑针擦着镜头飞走、齿轮甩开、中心盘沿斩缝开门
##       → 穿出是黑舞台和钟楼剪影；身后各圈追上来收拢成一只钟，卡进钟楼钟口：钟响、剑针跳到 5:59、冲击波推开云
##       → 中景左右两扇翻开、近景从镜头身后掠过落位 → 闪电亮场、开始下雨 → 路灯由近到远连锁点亮 → 整片打亮、章名砸下。
## 返回首页：整段倒放。换章：景片由近到远翻面（背面是铆钉铁板）。
## 本脚本管：分解钟、机位、景片、钟体覆盖值（clock_state）、左侧字；首页钟体本身仍由 zz_title 驱动。

const W := 1920.0
const H := 1080.0
const DEG := PI / 180.0
const INK := Color("#08070c")
const WHITE := Color("#f5f2eb")
const FLAT_SHADER := preload("res://scripts/ui/yg_zhanzhong/zz_stage_flat.gdshader")
const STAGE_DIR := "res://assets/image/yg_zhanzhong/stage/"

const DIAL_Z := -420.0
const OS_K := 1.08                 # 景片比画面多铺 8%，留给镜头漂移
const PAINT_CLOCK := Vector2(1626.0, 275.5)   # 影街插画里钟楼钟口的中心（像素）
const PAINT_R := 112.0                         # 钟面半径（像素）
const DIAL_R_PX := 570.0           # 三维表盘贴图里罗马数字环外沿半径（像素）
const DIST_T := 6000.0             # 终点机位到钟楼的距离
const EXIT_D := 1400.0             # 穿出中心盘后，镜头停在表盘后方多远
const LAYER_K := [1.9, 1.0, 0.62, 0.4]        # 景片离镜头的距离（以钟楼距离为 1）
const MID_SPLIT := 0.78            # 中景左右两扇门的分界（UV.x）
const STEP := 0.0                  # 兼容 zz_title 的钟盘咬合公式
const NAME_X := 94.0
const NAME_Y := 274.0
const NAME_H := 236.0
const NAME_MAXW := 700.0

const NAME_CUTS := {
	"bz_name_ch1": [0.5184],
	"bz_name_ch2": [0.1586, 0.4178, 0.6017, 0.8001],
	"bz_name_ch3": [0.26, 0.5673, 0.7093],
	"bz_name_ch4": [0.3075, 0.533, 0.7715],
	"bz_name_train": [0.2644, 0.5062, 0.7481],
}

# 表盘按半径切的 5 圈（贴图像素）：中心机芯盘 / 分钟圈 / 花窗圈 / 罗马数字圈 / 外沿
const RINGS := [[0.0, 292.0], [292.0, 345.0], [345.0, 432.0], [432.0, 556.0], [556.0, 640.0]]
const RING_Z := [-560.0, -260.0, -90.0, 90.0, 260.0]   # 展开后各圈离表盘的前后距离（正 = 朝镜头）
const RING_TURN := [1.0, -2.0, 1.0, -1.0, 1.0]         # 各圈在整段里转几圈（整数，落定时刻度回正）
const GEAR_Z := {"gear_main": -380.0, "gear_escape": -430.0, "pallet_fork": -470.0}

# 内部原版时间轴配合 PACE=1.68 商业提速（1.45s 完成整套拆钟穿环与亮场，0.55s 起允许抢按）
const PACE := 1.68
const T_SWAP := 0.13
const T_LAND := 1.2
const T_PULL := [1.3, 0.5]
const T_DOOR := [1.34, 0.2]
const T_NEAR := [1.42, 0.24]
const T_BOLT := 1.68
const T_LAMP := 1.76
const T_LIT := 1.98
const T_NAME := 2.05
const T_DONE := 2.45
const TV_END := 1.8
const OUT_LEN := 0.56
const CLOSE_D := 3400.0             # 钟响那一刻镜头离钟楼多远（钟约占画面四成）
const SKY_K := 1.8                  # 天幕面片放大倍数
const THICK_N := 6                  # 铸铁厚度：每件背后叠几层暗片
const THICK_STEP := 5.0
const GHOSTS := [0.3, 0.16, 0.08]  # 三个残影的不透明度

var T: Node = null
var clock: Node3D = null
var chapters: Array = []
var idx := 0
var prev := 0
var now := 0.0
var state := "hidden"      # hidden / in / shown / out / launch
var t_state := -10.0
var t_sw := -10.0
var reveal_t0 := 1e9
var old_t0 := -10.0
var hover := false
var hover_k := 0.0
var lock_shake := 0.0
var events := {}
var cam_st := {}
var pointer := Vector2.ZERO
var wheel_p := 0.0

# ---- 三维 ----
var stage_root: Node3D
var layers: Array = []     # [{kind, n, piv, mi, mat, z, w, h, hinge}]
var hub_w := Vector3.ZERO
var cam_f := Transform3D.IDENTITY
var o_e := Vector3.ZERO
var c_orbit := Vector3.ZERO
var t_c := Vector3.ZERO
var s_t := 0.5
var home_xf := Transform3D.IDENTITY
var hand_a := 0.0
var hour0 := 0.0
var min_home := 0.0
var hour_home := 0.0
var flip_t0 := -10.0
var flip_from := 0
var flip_dir := 1.0
var layer_tex := {}
var rig: Node3D
var rig_parts: Array = []
var rig_a := 1.0
var wave_mi: MeshInstance3D
var rain_mmi: MultiMeshInstance3D
var rain_drops: Array = []
var last_tv := 0.0
var c1 := Vector3.ZERO
var env_parts: Array = []
var near_ghosts: Array = []
var near_hist: Array = []
var roster_handoff_xf := Transform3D.IDENTITY
var roster_handoff_t0 := -10.0
var cine_st: Dictionary = {}
var sw_roll := 0.0
var sw_fov := 0.0
var sw_chroma := 0.0
var sw_blur := 0.0
var sw_impact := 0.0
var stage_hud: Control
var _hud_tex_cache: Dictionary = {}
var _cta_rect := Rect2(94, 748, 376, 76)
var _tower_rects: Array = []
var _hover_tower := -1
var tower_gear_ang := 0.0
var tower_gear_goal := 0.0

# ---- 二维 ----
var f_heavy: FontVariation
var f_bold: FontVariation
var head: Control
var head_img: TextureRect
var head_bg: Polygon2D
var info: Node2D
var info_old: Node2D
var name_cur := {}
var old_a := {}
var tag: Node2D
var tag_lb: Label
var tag_box: Polygon2D
var tag_box_sh: Polygon2D
var sub_clip: Control
var sub_bg: Polygon2D
var sub_lb: Label
var pip_bar: Control
var go: Node2D
var go_echo: Polygon2D
var go_plate: Polygon2D
var go_edge: Polygon2D
var go_border: Line2D
var go_key_bg: Polygon2D
var go_lb: Label
var go_sub_lb: Label
var go_hint: Label


# ================================================================ 搭建
func setup(title: Node, chs: Array) -> void:
	T = title
	clock = T.clock
	chapters = chs
	size = Vector2(W, H)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var noto: FontFile = load("res://assets/fonts/yg_title/NotoSerifSC-VF.ttf")
	var wght := TextServerManager.get_primary_interface().name_to_tag("wght")
	f_heavy = FontVariation.new()
	f_heavy.base_font = noto
	f_heavy.variation_opentype = {wght: 900}
	f_bold = FontVariation.new()
	f_bold.base_font = noto
	f_bold.variation_opentype = {wght: 700}
	_build_3d()
	_build_rig()
	_build_2d()
	visible = false


func _layer_tex(ci: int, n: int) -> Texture2D:
	var key := "%d_%d" % [ci, n]
	if not layer_tex.has(key):
		var art := String(chapters[ci]["art"]).replace("bz_art_", "")
		layer_tex[key] = load(STAGE_DIR + "st_%s_L%d.png" % [art, n])
	return layer_tex[key]


func _has_tower(ci: int) -> bool:
	return String(chapters[ci]["art"]) == "bz_art_ch1"


func _build_3d() -> void:
	var cam: Camera3D = clock.camera
	cam.far = 80000.0
	var D: float = clock.D
	hub_w = clock.to_world(clock.HUB.x, clock.HUB.y, DIAL_Z)
	c_orbit = hub_w + Vector3(0, 0, -150.0)
	o_e = hub_w + Vector3(0, 0, -EXIT_D)
	cam_f = Transform3D(Basis.IDENTITY, o_e)
	# 钟楼钟口：三维钟落进去时的位置和缩放（大小与画里的钟面一致）
	var c := Vector2(W * 0.5, H * 0.5) + (PAINT_CLOCK - Vector2(W * 0.5, H * 0.5)) * OS_K
	t_c = o_e + Vector3((c.x - W * 0.5) / D * DIST_T, (H * 0.5 - c.y) / D * DIST_T, -DIST_T)
	var kq: float = clock.k_at(DIAL_Z) * 1.12
	s_t = PAINT_R * OS_K / D * DIST_T / (DIAL_R_PX * kq)
	c1 = Vector3(t_c.x, t_c.y, t_c.z + CLOSE_D)

	stage_root = Node3D.new()
	stage_root.visible = false
	T.add_child(stage_root)
	# 景片：天幕 / 远景（钟楼）/ 中景左扇 / 中景右扇 / 近景
	for spec in [["sky", 0], ["far", 1], ["midL", 2], ["midR", 2], ["near", 3]]:
		var kind: String = spec[0]
		var n: int = spec[1]
		var z: float = DIST_T * float(LAYER_K[n]) + (DIST_T * 0.006 if n == 1 else 0.0)
		var w := W / D * z * OS_K
		var h := H / D * z * OS_K
		var q := QuadMesh.new()
		q.size = Vector2(w, h) * (SKY_K if n == 0 else 1.0)
		var mat := ShaderMaterial.new()
		mat.shader = FLAT_SHADER
		# 天幕、远景画在钟体后面；中景、近景压在钟体前面
		mat.render_priority = [-4, -3, 2, 3][n]
		if n == 0:
			mat.set_shader_parameter("uv_k", SKY_K)
		if kind == "midL":
			mat.set_shader_parameter("xr", Vector2(0.0, MID_SPLIT))
		elif kind == "midR":
			mat.set_shader_parameter("xr", Vector2(MID_SPLIT, 1.0))
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 16384.0
		var piv := Node3D.new()
		stage_root.add_child(piv)
		piv.add_child(mi)
		var center := o_e + Vector3(0, 0, -z)
		var hinge := center
		if kind == "midL":
			hinge = center + Vector3(-w * 0.5, 0, 0)
		elif kind == "midR":
			hinge = center + Vector3(w * 0.5, 0, 0)
		piv.position = hinge
		mi.position = center - hinge
		layers.append({"kind": kind, "n": n, "piv": piv, "mi": mi, "mat": mat, "z": z, "w": w, "h": h, "hinge": hinge})
		if kind == "near":
			for k in GHOSTS.size():
				var gm := ShaderMaterial.new()
				gm.shader = FLAT_SHADER
				gm.render_priority = 3
				var gq := MeshInstance3D.new()
				gq.mesh = q
				gq.material_override = gm
				gq.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				gq.extra_cull_margin = 16384.0
				gq.visible = false
				stage_root.add_child(gq)
				near_ghosts.append({"mi": gq, "m": gm})

	# 钟响冲击波：从钟口推出去的一圈冷白光环
	var wq := QuadMesh.new()
	wq.size = Vector2(2, 2)
	var wm: ShaderMaterial = clock.add_mat(clock.circle_tex(0.965, 1.0, 512), Color(0.82, 0.9, 1.0), 0.0)
	wm.render_priority = -2
	wave_mi = MeshInstance3D.new()
	wave_mi.mesh = wq
	wave_mi.material_override = wm
	wave_mi.extra_cull_margin = 16384.0
	wave_mi.position = t_c + Vector3(0, 0, 40.0)
	stage_root.add_child(wave_mi)

	# 舞台雨：闪电那一刻开始下
	var rq := QuadMesh.new()
	rq.size = Vector2(1, 1)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = rq
	mm.instance_count = 280
	rain_mmi = MultiMeshInstance3D.new()
	rain_mmi.multimesh = mm
	var rmat: ShaderMaterial = clock.flat_mat(null, Color(0.72, 0.8, 0.98), 0.0)
	rmat.render_priority = 4
	rain_mmi.material_override = rmat
	rain_mmi.custom_aabb = AABB(Vector3(-1e5, -1e5, -1e5), Vector3(2e5, 2e5, 2e5))
	stage_root.add_child(rain_mmi)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5959
	for i in mm.instance_count:
		rain_drops.append({"x": rng.randf() * 2.0 - 1.0, "y": rng.randf(), "z": lerpf(420.0, DIST_T * 0.85, pow(rng.randf(), 1.7)), "sp": 0.85 + rng.randf() * 0.5})


## 分解钟：和首页钟同一套贴图，按首页的摆位一件件复制出来，斩下那一刻替换上去
## 每件铸铁背后叠 6 层暗色片做出厚度；每件带 3 个残影（高速时显出拖影）
func _build_rig() -> void:
	rig = Node3D.new()
	rig.visible = false
	T.add_child(rig)
	var home := Transform3D(Basis(Vector3.BACK, -float(clock.TILT)), hub_w)
	var inv := home.affine_inverse()
	var tint := Color("#d6d4d0")
	var gcol := Color("#9e988e")
	var hub: Vector2 = clock.HUB
	for i in RINGS.size():
		var sides: Array = [-1.0, 1.0] if i == 0 else [0.0]
		for side: float in sides:
			var m: ShaderMaterial = clock.lit_mat(clock.tex("dial"), clock.tex("dial_n"), tint, gcol, 0.34, 1.0, 0.86, 0.34)
			m.set_shader_parameter("ring", Vector2(float(RINGS[i][0]), float(RINGS[i][1])))
			_add_part(clock.meta_quad("dial", 1.12, DIAL_Z, m), m, "ring", i, side, inv * hub_w)
	var gspec := [["gear_main", 1.02, -300.0, Vector2(-104, -62), Color("#ded8cd"), Color("#7f7970"), 0.45],
		["gear_escape", 0.78, -240.0, Vector2(70, -166), Color("#eee9df"), Color("#9f9990"), 0.5],
		["pallet_fork", 0.55, -200.0, Vector2(92, -334), Color("#ffffff"), Color("#b8b2a8"), 0.56]]
	for g: Array in gspec:
		var key: String = g[0]
		var gz: float = g[2]
		var off: Vector2 = g[3]
		var m2: ShaderMaterial = clock.lit_mat(clock.tex(key), clock.tex(key + "_n"), g[4], g[5], g[6], 1.0, 0.84, 0.33)
		_add_part(clock.meta_quad(key, g[1], gz, m2), m2, key, 0, 0.0, inv * clock.to_world(hub.x + off.x, hub.y + off.y, gz))
	for side: float in [-1.0, 1.0]:
		var m3: ShaderMaterial = clock.lit_mat(clock.tex("rosette"), clock.tex("rosette_n"), Color.WHITE, WHITE, 0.82, 1.0, 0.8, 0.25)
		_add_part(clock.meta_quad("rosette", 0.195, 120.0, m3), m3, "rosette", 0, side, inv * clock.to_world(hub.x, hub.y, 120.0))
	for hk: Array in [["hand_hour", 0.355, 60.0], ["hand_minute", 0.43, 90.0]]:
		var hkey: String = hk[0]
		var m4: ShaderMaterial = clock.lit_mat(clock.tex(hkey), clock.tex(hkey + "_n"), Color.WHITE, Color.WHITE, 0.8, 1.0, 0.75, 0.26)
		_add_part(clock.meta_quad(hkey, hk[1], hk[2], m4), m4, hkey, 0, 0.0, inv * clock.to_world(hub.x, hub.y, hk[2]))
	_build_env()


func _add_part(mi: MeshInstance3D, m: ShaderMaterial, kind: String, i: int, side: float, pos0: Vector3) -> void:
	mi.extra_cull_margin = 4096.0
	rig.add_child(mi)
	var thick: Array = []
	if not kind.begins_with("hand"):
		var t0: Color = m.get_shader_parameter("tint")
		for j in range(1, THICK_N + 1):
			var tm := m.duplicate() as ShaderMaterial
			var dk := lerpf(0.55, 0.3, float(j) / THICK_N)
			tm.set_shader_parameter("tint", Color(t0.r * dk, t0.g * dk, t0.b * dk * 1.08, 1.0))
			var tq := MeshInstance3D.new()
			tq.mesh = mi.mesh
			tq.material_override = tm
			tq.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			tq.extra_cull_margin = 4096.0
			tq.position = Vector3(0, 0, -THICK_STEP * j)
			mi.add_child(tq)
			thick.append(tm)
	var ghosts: Array = []
	if side == 0.0:
		for k in GHOSTS.size():
			var gm := m.duplicate() as ShaderMaterial
			var gq := MeshInstance3D.new()
			gq.mesh = mi.mesh
			gq.material_override = gm
			gq.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			gq.extra_cull_margin = 4096.0
			gq.visible = false
			T.add_child(gq)
			ghosts.append({"mi": gq, "m": gm})
	rig_parts.append({"mi": mi, "m": m, "kind": kind, "i": i, "side": side, "pos0": pos0,
		"g0": float(m.get_shader_parameter("glow")), "thick": thick, "ghosts": ghosts, "hist": []})


## 展开时的空间：钟背后的紫色裂光逆光（斩缝的刀光，准绳允许）、一道细长裂光、三层纵深薄雾
func _build_env() -> void:
	var specs := [
		[4200.0, 4200.0, -1150.0, Color("#6a3df0"), 0.42, 0.0],
		[9000.0, 150.0, -1080.0, Color("#c4b0ff"), 0.75, -float(clock.TWELVE)],
		[4200.0, 4200.0, 380.0, Color("#8a8ea8"), 0.035, 0.0],
		[4800.0, 4800.0, -320.0, Color("#8a8ea8"), 0.05, 0.0],
		[5400.0, 5400.0, -820.0, Color("#7a72b0"), 0.06, 0.0],
	]
	for sp: Array in specs:
		var q := QuadMesh.new()
		q.size = Vector2(float(sp[0]), float(sp[1]))
		var m: ShaderMaterial = clock.add_mat(null, sp[3], 0.0)
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 8192.0
		mi.position = hub_w + Vector3(0, 0, float(sp[2]))
		mi.rotation.z = float(sp[5])
		mi.visible = false
		T.add_child(mi)
		env_parts.append({"mi": mi, "m": m, "op": float(sp[4])})


## 残影：用前几帧「相对镜头」的位置画半透明副本——物体动、镜头动都会拖出来
func _ghost_update(P: Dictionary, world: Transform3D, cam: Transform3D, a_main: float, params: Dictionary) -> void:
	var hist: Array = P["hist"]
	hist.push_front([world, cam])
	if hist.size() > GHOSTS.size() + 1:
		hist.resize(GHOSTS.size() + 1)
	var gs: Array = P["ghosts"]
	if gs.is_empty():
		return
	var cinv := cam.affine_inverse()
	var vn := cinv * world.origin
	for k in gs.size():
		var g: Dictionary = gs[k]
		var gmi: MeshInstance3D = g["mi"]
		if hist.size() <= k + 1 or a_main <= 0.001:
			gmi.visible = false
			continue
		var h: Array = hist[k + 1]
		var pk: Transform3D = h[0]
		var ck: Transform3D = h[1]
		var G := cam * ck.affine_inverse() * pk
		var vk := cinv * G.origin
		var disp := 0.0
		if vn.z < -30.0 and vk.z < -30.0:
			disp = (Vector2(vn.x, vn.y) / -vn.z - Vector2(vk.x, vk.y) / -vk.z).length() * float(clock.D)
		var ga := clampf((disp - 10.0) / 40.0, 0.0, 1.0) * float(GHOSTS[k])
		gmi.visible = ga > 0.01
		if gmi.visible:
			gmi.transform = G
			var gm: ShaderMaterial = g["m"]
			for key in params:
				gm.set_shader_parameter(key, params[key])
			gm.set_shader_parameter("opacity", a_main * ga)


func _reset_trails() -> void:
	for P in rig_parts:
		(P["hist"] as Array).clear()
		for g: Dictionary in P["ghosts"]:
			(g["mi"] as MeshInstance3D).visible = false
	near_hist.clear()
	for g: Dictionary in near_ghosts:
		(g["mi"] as MeshInstance3D).visible = false


func _set_layers(ci: int) -> void:
	for L in layers:
		(L["mat"] as ShaderMaterial).set_shader_parameter("tex", _layer_tex(ci, int(L["n"])))
	var sky_m: ShaderMaterial = layers[0]["mat"]
	sky_m.set_shader_parameter("wave_c", PAINT_CLOCK / Vector2(W, H))


func _build_2d() -> void:
	# [YG-MARK] 新一代电影级《登天纵轴》择章 HUD（彻底废除旧版白块/黑框贴纸，与三维裂钟选角视觉一脉相承）
	stage_hud = Control.new()
	stage_hud.size = Vector2(W, H)
	stage_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage_hud.draw.connect(_draw_stage_hud)
	add_child(stage_hud)

	head = Control.new()
	head.visible = false
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(head)
	head_bg = Polygon2D.new()
	head.add_child(head_bg)
	head_img = TextureRect.new()
	head.add_child(head_img)
	pip_bar = Control.new()
	head.add_child(pip_bar)

	info_old = Node2D.new()
	add_child(info_old)
	old_a = _make_name(info_old)

	info = Node2D.new()
	add_child(info)
	tag = Node2D.new()
	tag.visible = false
	info.add_child(tag)
	tag_box_sh = Polygon2D.new()
	tag.add_child(tag_box_sh)
	tag_box = Polygon2D.new()
	tag.add_child(tag_box)
	tag_lb = _lbl("第一章", 50, INK, f_heavy, false)
	tag.add_child(tag_lb)

	name_cur = _make_name(info)

	sub_clip = Control.new()
	sub_clip.visible = false
	info.add_child(sub_clip)
	sub_bg = Polygon2D.new()
	sub_clip.add_child(sub_bg)
	sub_lb = _lbl("", 38, WHITE, f_bold, true)
	sub_clip.add_child(sub_lb)

	go = Node2D.new()
	go.visible = false
	info.add_child(go)
	go_echo = Polygon2D.new()
	go.add_child(go_echo)
	go_plate = Polygon2D.new()
	go.add_child(go_plate)
	go_edge = Polygon2D.new()
	go.add_child(go_edge)
	go_border = Line2D.new()
	go.add_child(go_border)
	go_key_bg = Polygon2D.new()
	go.add_child(go_key_bg)
	go_lb = _lbl("开始出击", 62, INK, f_heavy, false)
	go.add_child(go_lb)
	go_sub_lb = _lbl("完成前章后解锁", 20, Color(WHITE, 0.56), f_bold, false)
	go.add_child(go_sub_lb)
	go_hint = _lbl("ENTER", 24, WHITE, T.font_lat, false)
	go.add_child(go_hint)

	# 预计算右侧《登天纵轴》点击区（由下至上 I -> II -> III -> IV 逐层登天，底部分隔「试剑回廊」）
	_tower_rects.clear()
	var order_y := [618.0, 492.0, 366.0, 240.0, 774.0]
	for i in order_y.size():
		_tower_rects.append(Rect2(1612.0, float(order_y[i]) - 36.0, 258.0, 72.0))


func _exit_tree() -> void:
	_hud_tex_cache.clear()


func _hud_tex(file_name: String) -> Texture2D:
	if not _hud_tex_cache.has(file_name):
		_hud_tex_cache[file_name] = load("res://assets/image/yg_zhanzhong/" + file_name)
	return _hud_tex_cache[file_name] as Texture2D


func cine_state() -> Dictionary:
	return cine_st


func _draw_pips() -> void:
	var x := 0.0
	for i in chapters.size():
		var ch: Dictionary = chapters[i]
		var on := i == idx
		var unlocked: bool = ch["unlocked"]
		var w := 64.0 if on else 44.0
		var r := Rect2(x, 6.0, w, 28.0)
		var pts := PackedVector2Array([
			Vector2(r.position.x + 8, r.position.y), Vector2(r.end.x + 8, r.position.y),
			Vector2(r.end.x, r.end.y), Vector2(r.position.x, r.end.y),
		])
		var bg := Color(T.accent, 0.96) if on else Color(INK, 0.86 if unlocked else 0.72)
		pip_bar.draw_colored_polygon(pts, bg)
		var rim_c := WHITE if on else (Color(T.accent, 0.65) if unlocked else Color(WHITE, 0.24))
		for pi in 4:
			pip_bar.draw_line(pts[pi], pts[(pi + 1) % 4], rim_c, 1.5 if on else 1.0, true)
		var num := String(ch.get("num", str(i + 1)))
		var tw: float = (T.font_lat as Font).get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		pip_bar.draw_string(T.font_lat, Vector2(x + (w - tw) * 0.5 + 4.0, 26.0), num,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, WHITE if on else Color(WHITE, 0.78 if unlocked else 0.42))
		x += w + 10.0


func _lbl(text: String, sz: int, col: Color, f: Font, shadow: bool) -> Label:
	var lb := Label.new()
	lb.text = text
	lb.add_theme_font_override("font", f)
	lb.add_theme_font_size_override("font_size", sz)
	lb.add_theme_color_override("font_color", col)
	if shadow:
		lb.add_theme_color_override("font_shadow_color", INK)
		lb.add_theme_constant_override("shadow_offset_x", 4)
		lb.add_theme_constant_override("shadow_offset_y", 5)
	lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lb


func _make_name(parent: Node) -> Dictionary:
	var root := Node2D.new()
	parent.add_child(root)
	return {"root": root, "chars": [], "w": 0.0, "h": 0.0, "word": ""}


## 章名逐字切开（刀锋宋字图按字间空隙切块，便于逐字砸落）
func _set_name(d: Dictionary, word: String) -> void:
	if d["word"] == word:
		return
	d["word"] = word
	var root: Node2D = d["root"]
	for c in root.get_children():
		c.queue_free()
	if word == "":
		d["chars"] = []
		return
	var t: Texture2D = T._tex(word)
	var tw := float(t.get_width())
	var th := float(t.get_height())
	var h := minf(NAME_H, NAME_MAXW / (tw / th))
	var s := h / th
	var cuts: Array = [0.0]
	cuts.append_array(NAME_CUTS.get(word, []))
	cuts.append(1.0)
	var chars: Array = []
	for k in cuts.size() - 1:
		var u0: float = cuts[k]
		var u1: float = cuts[k + 1]
		var at := AtlasTexture.new()
		at.atlas = t
		at.region = Rect2(u0 * tw, 0.0, (u1 - u0) * tw, th)
		var cn := Node2D.new()
		cn.position = Vector2(u0 * tw * s, 0.0)
		root.add_child(cn)
		var sz := Vector2((u1 - u0) * tw * s, h)
		var lay := {}
		for key in ["echo", "sh", "face"]:
			var r := TextureRect.new()
			r.texture = at
			r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			r.stretch_mode = TextureRect.STRETCH_SCALE
			r.size = sz
			r.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cn.add_child(r)
			lay[key] = r
		(lay["sh"] as TextureRect).modulate = INK
		(lay["sh"] as TextureRect).position = Vector2(12, 14)
		(lay["face"] as TextureRect).modulate = WHITE
		chars.append({"n": cn, "x0": u0 * tw * s, "w": sz.x, "echo": lay["echo"], "face": lay["face"], "sh": lay["sh"]})
	d["chars"] = chars
	d["w"] = tw * s
	d["h"] = h


func _apply_chapter() -> void:
	var ch: Dictionary = chapters[idx]
	_set_name(name_cur, String(ch["word"]))
	tag_lb.text = String(ch["tag"])
	var tw := tag_lb.get_minimum_size().x
	var tbw := tw + 96.0
	tag_box.polygon = PackedVector2Array([Vector2(16, 0), Vector2(tbw, 0), Vector2(tbw - 16, 78), Vector2(0, 78)])
	tag_box_sh.polygon = tag_box.polygon
	sub_lb.text = String(ch["sub"])
	var sw := sub_lb.get_minimum_size().x + 52.0
	sub_clip.size = Vector2(sw, 66)
	sub_bg.polygon = PackedVector2Array([Vector2(12, 0), Vector2(sw, 0), Vector2(sw - 12, 66), Vector2(0, 66)])
	var unlocked: bool = ch["unlocked"]
	go_lb.text = "开始出击" if unlocked else "尚 未 开 放"
	go_hint.visible = unlocked
	go_key_bg.visible = unlocked
	if pip_bar != null:
		pip_bar.queue_redraw()


# ================================================================ 对外接口
func enter(i: int) -> void:
	idx = i
	prev = i
	state = "in"
	t_state = now
	t_sw = -10.0
	old_t0 = -10.0
	flip_t0 = -10.0
	reveal_t0 = 1e9
	roster_handoff_t0 = -10.0
	events = {}
	home_xf = (clock.camera as Camera3D).global_transform
	hand_a = clock.TWELVE - clock.GAP
	hour0 = float(T.hand["a"]) if T.get("hand") != null else float(clock.REST)
	rig_a = 1.0
	_reset_trails()
	_set_layers(i)
	_set_name(old_a, "")
	_apply_chapter()
	stage_root.visible = true
	visible = true


## 从《司辰母钟 · 裂钟心殿》角色确认斩裂后无缝接管镜头：
## 从 tv = 0.94 接续，让三维铸铁巨钟从主角身后向前飞聚并轰然砸入第一章雨夜钟楼钟口（钟作为核心意象全程不断裂！）
func enter_from_roster(i: int, start_xf: Transform3D) -> void:
	idx = i
	prev = i
	state = "in"
	t_state = now - (1.03 / PACE)
	t_sw = -10.0
	old_t0 = -10.0
	flip_t0 = -10.0
	reveal_t0 = 1e9
	roster_handoff_xf = start_xf
	roster_handoff_t0 = now
	sw_chroma = 0.020
	sw_blur = 0.030
	sw_impact = 0.0
	events = {"whoosh": true, "slash": true, "freeze": true, "ps0": true, "ps1": true, "ps2": true, "homes": true}
	home_xf = start_xf
	hand_a = clock.TWELVE - clock.GAP
	hour0 = float(T.hand["a"]) if T.get("hand") != null else float(clock.REST)
	min_home = -hand_a + float(clock.TILT)
	hour_home = -hour0 + float(clock.TILT)
	rig_a = 1.0 if _has_tower(i) else 0.0
	_reset_trails()
	_set_layers(i)
	_set_name(old_a, "")
	_apply_chapter()
	stage_root.visible = true
	visible = true


func leave_to_roster() -> void:
	state = "hidden"
	visible = false
	stage_root.visible = false
	rig.visible = false
	_env_vis(0.0)
	_reset_trails()
	roster_handoff_t0 = -10.0
	cam_st = {"cam_blend": 0.0}
	cine_st = {}


func leave() -> void:
	state = "out"
	t_state = now
	events = {}


func launch() -> void:
	state = "launch"
	t_state = now
	events = {}


func snap_in() -> void:
	if state == "in":
		state = "shown"
		t_state = now - T_DONE - 0.1
		reveal_t0 = minf(reveal_t0, now - 0.1)


func set_index(i: int, dir: int) -> void:
	if i == idx:
		return
	if state == "in":
		snap_in()
	if flip_t0 > 0.0 and now - flip_t0 < 0.8:
		_set_layers(idx)
	prev = idx
	idx = i
	t_sw = now
	old_t0 = now
	flip_t0 = now
	flip_from = prev
	flip_dir = 1.0 if dir >= 0 else -1.0
	reveal_t0 = now + 0.18
	tower_gear_goal += flip_dir * 60.0 * DEG
	# 登天纵轴张力脉冲：真三维垂直攀升/俯冲 + 向内长焦呼吸（绝不露黑边）+ 色散与 1 帧冲击！
	sw_roll = 0.032 * flip_dir
	sw_fov = -4.6
	sw_chroma = 0.015
	sw_blur = 0.026
	sw_impact = 0.44
	var pc: Dictionary = chapters[prev]
	_set_name(old_a, String(pc["word"]))
	_apply_chapter()


func locked_bump() -> void:
	lock_shake = 1.0


func home_leave() -> float:
	var ts := now - t_state
	match state:
		"in":
			return _expo(_seg(ts, 0.1, 0.3))
		"shown", "launch":
			return 1.0
		"out":
			return 1.0 - _expo(_seg(ts, OUT_LEN - 0.3, 0.3))
	return 0.0


func clock_state() -> Dictionary:
	return cam_st


func is_shown() -> bool:
	return state == "in" or state == "shown"


func _fire(name: String, at: float, ts: float) -> bool:
	if ts >= at and not events.has(name):
		events[name] = true
		if T.has_method("_sel_event"):
			T._sel_event(name)
		return true
	return false


# ================================================================ 缓动
static func _seg(t: float, a: float, d: float) -> float:
	return clampf((t - a) / d, 0.0, 1.0)


static func _expo(t: float) -> float:
	return 1.0 if t >= 1.0 else 1.0 - pow(2.0, -10.0 * t)


static func _in_out(t: float) -> float:
	return 4.0 * t * t * t if t < 0.5 else 1.0 - pow(-2.0 * t + 2.0, 3.0) / 2.0


static func _quint(t: float) -> float:
	return 16.0 * pow(t, 5.0) if t < 0.5 else 1.0 - pow(-2.0 * t + 2.0, 5.0) / 2.0


static func _out3(t: float) -> float:
	return 1.0 - pow(1.0 - t, 3.0)


static func _back(t: float, s: float = 1.7) -> float:
	return 1.0 + (s + 1.0) * pow(t - 1.0, 3.0) + s * pow(t - 1.0, 2.0)


## 机械锁定：先冲过头一点再咔地回位
static func _lock(t: float) -> float:
	if t >= 1.0:
		return 1.0
	return _back(t, 2.2)


# ================================================================ 主序列（tv = 进场时间轴上的时刻；返回首页时倒着走）
## 机位：首页 → 绕到侧面看分解钟 → 摆回中轴、往后一缩 → 冲过各圈 → 追着钟一路飞到钟楼前（钟占画面四成）
##       → 钟响往前一顶 → 猛地后拉揭开整条街（舞台机位）
func _cam_seq(tv: float) -> Transform3D:
	if tv >= T_LAND:
		var pb := _expo(_seg(tv, T_PULL[0], T_PULL[1]))
		var push := -70.0 * sin(PI * _seg(tv, T_LAND, 0.1))
		return Transform3D(Basis.IDENTITY, c1.lerp(o_e, pb) + Vector3(0, 0, push))
	var v0 := home_xf.origin - c_orbit
	var d0 := v0.length()
	var e_o := _in_out(_seg(tv, 0.1, 0.45))
	var e_al := _in_out(_seg(tv, 0.6, 0.18))
	var keep := e_o * (1.0 - e_al)
	var yaw := (38.0 + 4.0 * _seg(tv, 0.45, 0.2)) * DEG * keep
	var pitch := -14.0 * DEG * keep
	var R := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
	var d := d0 * (1.0 + 0.07 * e_o) - 60.0 * _seg(tv, 0.0, T_SWAP) * (1.0 - e_o)
	d += 200.0 * _out3(_seg(tv, 0.6, 0.08))
	d = lerpf(d, c1.z - c_orbit.z, _quint(_seg(tv, 0.68, T_LAND - 0.68)))
	var dir := v0.normalized().lerp(Vector3(0, 0, 1), e_al).normalized()
	var fr := _in_out(_seg(tv, 0.92, T_LAND - 0.92))
	var lat := Vector3(t_c.x - hub_w.x, t_c.y - hub_w.y, 0.0) * _in_out(_seg(tv, 0.84, T_LAND - 0.84))
	var pos := c_orbit + R * (dir * d) + lat
	# 绕侧面时镜头盯着分解钟（略偏，让整叠钟落在画面中间）；摆回中轴后朝正前方
	var hb := home_xf.basis.orthonormalized()
	var b := hb
	if e_al < 1.0 and (c_orbit - pos).length() > 50.0:
		var right := R * Vector3.RIGHT
		b = hb.slerp(Basis.looking_at(c_orbit - right * 380.0 * keep - pos, Vector3.UP), e_o)
	b = b.slerp(Basis.IDENTITY, e_al)
	return Transform3D(b, pos)


## 分解钟：展开、各圈反转、开门、甩齿轮、剑针飞出，再追上镜头收拢、落进钟楼
func _rig_seq(tv: float, glow_k: float, bell_k: float, cam: Transform3D) -> void:
	var ex := _back(_seg(tv, T_SWAP, 0.4), 1.3) * (1.0 - _in_out(_seg(tv, 0.98, 0.18)))
	ex -= 0.06 * sin(PI * _seg(tv, T_LAND - 0.04, 0.12))
	var spin_h := 0.5 * _expo(_seg(tv, T_SWAP, 0.6)) + 0.5 * _in_out(_seg(tv, 0.92, T_LAND - 0.92))
	var door := 1100.0 * _expo(_seg(tv, 0.8, 0.1)) * (1.0 - _in_out(_seg(tv, 1.08, 0.1)))
	var scat := _expo(_seg(tv, 0.78, 0.12)) * (1.0 - _in_out(_seg(tv, 1.06, 0.12)))
	var fly := pow(_seg(tv, 0.68, 0.16), 2.0) * (1.0 - _out3(_seg(tv, 0.98, 0.2)))
	var fr := _in_out(_seg(tv, 0.92, T_LAND - 0.92))
	var gs := now * 0.11 + 7.0 * _out3(_seg(tv, T_SWAP, 1.0))
	var sc := lerpf(1.0, s_t, fr)
	rig.position = Vector3(lerpf(hub_w.x, t_c.x, fr * fr), lerpf(hub_w.y, t_c.y, fr * fr), lerpf(hub_w.z, t_c.z, fr))
	rig.basis = Basis(Vector3.BACK, lerpf(-float(clock.TILT), 0.0, fr)).scaled(Vector3.ONE * sc)
	var nw := rig.basis.x.normalized()
	var tilt: float = clock.TILT
	# 落入第一章雨夜钟楼钟口时吃进冷蓝夜雾与微弱塔灯暖辉（彻底融入夜街钟楼石雕！）
	var tower_mix := _in_out(_seg(tv, T_LAND - 0.18, 0.24)) * (1.0 if _has_tower(idx) else 0.0)
	var gcol := Color(0.62, 0.6, 0.57).lerp(Color(0.86, 0.92, 1.0), glow_k)
	gcol = gcol.lerp(Color(0.24, 0.36, 0.62).lerp(Color(0.58, 0.52, 0.44), glow_k * 0.42), tower_mix)
	var night_tint := Color("#d6d4d0").lerp(Color("#4e6696"), tower_mix * 0.88)
	for P in rig_parts:
		var mi: MeshInstance3D = P["mi"]
		var m: ShaderMaterial = P["m"]
		var kind: String = P["kind"]
		var pos0: Vector3 = P["pos0"]
		var side: float = P["side"]
		var pos := pos0
		var rot := 0.0
		var wob := Vector2.ZERO
		match kind:
			"ring":
				var i: int = P["i"]
				pos.z += float(RING_Z[i]) * ex
				rot = float(RING_TURN[i]) * TAU * spin_h
				wob = Vector2(sin(i * 1.9 + tv * 2.6), cos(i * 1.3 + tv * 2.1)) * 0.16 * maxf(ex, 0.0)
				pos.x += side * door
			"gear_main", "gear_escape", "pallet_fork":
				pos.z = lerpf(pos0.z, float(GEAR_Z[kind]), ex)
				var rd := Vector2(pos0.x, pos0.y).normalized()
				pos += Vector3(rd.x, rd.y, 0.0) * 1150.0 * scat
				match kind:
					"gear_main":
						rot = -gs + tilt
					"gear_escape":
						rot = -(now * 2.0 + gs * 3.0) + tilt
					_:
						rot = -18.0 * DEG + tilt + sin(now * 9.0) * 0.1
				rot += scat * 6.0
			"rosette":
				pos.z = lerpf(pos0.z, -540.0, ex)
				pos.x += side * door
				rot = -gs * 0.2 + TAU * spin_h
			"hand_minute", "hand_hour":
				var is_m := kind == "hand_minute"
				pos.z += (150.0 if is_m else 80.0) * ex
				var sd := 1.0 if is_m else -1.0
				pos += Vector3(sd * 1000.0, 320.0 * sd, 3400.0) * fly
				rot = _hand_rot(is_m, tv)
		mi.transform = Transform3D(Basis.from_euler(Vector3(wob.x, wob.y, 0.0)) * Basis(Vector3.BACK, rot), pos)
		var glow := float(P["g0"]) * (1.0 + 1.5 * glow_k) + bell_k * 1.1
		if tower_mix > 0.01:
			glow *= lerpf(1.0, 0.30, tower_mix)
		var clip := Vector4.ZERO
		# 中心盘、中心花沿斩缝分两半开门：各自只留自己那一侧
		if side != 0.0:
			var o := rig.position + nw * side * door * sc
			var n := nw * side
			clip = Vector4(n.x, n.y, n.z, -n.dot(o))
		m.set_shader_parameter("clip_plane", clip)
		m.set_shader_parameter("opacity", rig_a)
		m.set_shader_parameter("glow", glow)
		if not kind.begins_with("hand"):
			m.set_shader_parameter("glow_col", gcol)
			m.set_shader_parameter("tint", night_tint)
		else:
			m.set_shader_parameter("tint", Color.WHITE.lerp(Color("#b6c8e6"), tower_mix * 0.55))
		for tm: ShaderMaterial in P["thick"]:
			tm.set_shader_parameter("clip_plane", clip)
			tm.set_shader_parameter("opacity", rig_a)
			tm.set_shader_parameter("glow", glow * 0.3)
		_ghost_update(P, rig.transform * mi.transform, cam, rig_a if (rig.visible and tv < T_LAND) else 0.0, {"glow": glow, "glow_col": m.get_shader_parameter("glow_col")})


## 剑针：斩下拨回 → 飞出时打转 → 回来落在 5:58 → 钟响那一下跳到 5:59
func _hand_rot(is_m: bool, tv: float) -> float:
	var a0 := min_home if is_m else hour_home
	var a1 := (102.0 if is_m else -89.0) * DEG
	var e := _in_out(_seg(tv, 0.2, T_LAND - 0.24))
	var a := lerpf(a0, a0 + wrapf(a1 - a0, -PI, PI), e) + (2.0 if is_m else -1.0) * TAU * _in_out(_seg(tv, 0.66, 0.5))
	if is_m and tv >= T_LAND:
		var k := _seg(tv, T_LAND, 0.14)
		a = a1 - 6.0 * DEG * (1.0 + 0.3 * sin(k * TAU) * (1.0 - k))
	return a


# ================================================================ 每帧（钟体更新之前）
func update(dt: float, ptr: Vector2, _kick: Vector2) -> void:
	now += dt
	pointer = ptr
	if state == "hidden":
		visible = false
		stage_root.visible = false
		rig.visible = false
		_env_vis(0.0)
		cam_st = {"cam_blend": 0.0}
		cine_st = {}
		return
	visible = true
	sw_roll *= exp(-dt * 11.0)
	sw_fov *= exp(-dt * 10.0)
	sw_chroma = maxf(0.0, sw_chroma - dt * 0.105)
	sw_blur = maxf(0.0, sw_blur - dt * 0.125)
	sw_impact = maxf(0.0, sw_impact - dt * 15.0)
	tower_gear_ang = lerpf(tower_gear_ang, tower_gear_goal, minf(1.0, dt * 10.5))
	var ts_raw := now - t_state
	var ts := ts_raw * PACE if state == "in" else ts_raw
	match state:
		"in":
			_fire("whoosh", 0.0, ts)
			_fire("slash", T_SWAP, ts)
			_fire("freeze", T_SWAP + 0.01, ts)
			for k in 3:
				if _fire("ps%d" % k, 0.86 + 0.035 * k, ts):
					T._sel_event("pass")
			if _fire("bell", T_LAND, ts):
				sw_chroma = maxf(sw_chroma, 0.018)
				sw_blur = maxf(sw_blur, 0.026)
				sw_impact = maxf(sw_impact, 0.42)
			if _fire("lkm", T_DOOR[0] + T_DOOR[1], ts):
				lock_shake = maxf(lock_shake, 0.5)
				T._sel_event("click")
			if _fire("land", T_NEAR[0] + T_NEAR[1], ts):
				lock_shake = 1.0
			if _fire("bolt", T_BOLT, ts):
				sw_chroma = maxf(sw_chroma, 0.015)
				sw_impact = maxf(sw_impact, 0.36)
			_fire("ignite", T_LAMP, ts)
			if ts >= T_NAME and reveal_t0 > now:
				reveal_t0 = now
			_fire("ready", T_DONE - 0.1, ts)
			_fire("click", T_DONE - 0.05, ts)
			if ts > T_DONE:
				state = "shown"
		"out":
			if ts_raw > OUT_LEN:
				state = "hidden"
				visible = false
				stage_root.visible = false
				rig.visible = false
				_env_vis(0.0)
				_reset_trails()
				cam_st = {"cam_blend": 0.0}
				return
	# 斩下前剑针往前推蓄力
	if state == "in" and ts < T_SWAP:
		var p := _seg(ts, 0.0, T_SWAP)
		hand_a = clock.TWELVE - clock.GAP + 0.55 * p * p
	elif state == "out":
		hand_a = clock.TWELVE - clock.GAP
	if state == "in" and not events.has("homes") and ts >= T_SWAP:
		events["homes"] = true
		min_home = -hand_a + float(clock.TILT)
		hour_home = -hour0 + float(clock.TILT)
	lock_shake = maxf(0.0, lock_shake - dt * 3.0)
	hover_k = lerpf(hover_k, 1.0 if (hover and state == "shown") else 0.0, minf(1.0, dt * 14.0))
	var rig_to := 1.0 if (_has_tower(idx) or (state == "in" and ts < T_LAND + 0.1) or state == "out") else 0.0
	# 切章离开第一章时，让钟体跟着远景钟楼一同坠落并同步消隐，绝不脱节悬空！
	var fl_rig := now - flip_t0
	if fl_rig >= 0.0 and fl_rig < 0.82 and state == "shown" and flip_from == 0 and idx != 0:
		var fp_f := _seg(fl_rig, 0.042 * 2.0, 0.48)
		rig_a = 1.0 - _seg(fp_f, 0.30, 0.18)
	else:
		rig_a = move_toward(rig_a, rig_to, dt * 4.5)
	_state_update(dt)


func _env_vis(k: float) -> void:
	for i in env_parts.size():
		var E: Dictionary = env_parts[i]
		var mi: MeshInstance3D = E["mi"]
		var m: ShaderMaterial = E["m"]
		mi.visible = k > 0.001
		m.set_shader_parameter("opacity", float(E["op"]) * k)
		if T != null and T.get("pal") != null:
			if i == 0:
				m.set_shader_parameter("tint", T.pal["mid"])
			elif i == 1:
				m.set_shader_parameter("tint", T.pal["bright"])
			elif i == 4:
				m.set_shader_parameter("tint", T.pal["deep"])


func _state_update(_dt: float) -> void:
	var ts_raw := now - t_state
	var ts := ts_raw * PACE if state == "in" else ts_raw
	# 进场时间轴上的时刻：进入正放；已展示 / 进关卡停在终点；返回首页先收景片、再整段倒放
	var tv := 10.0
	var lt := 10.0         # 景片 / 灯光用的时刻
	match state:
		"in":
			tv = ts
			lt = ts
		"out":
			tv = TV_END * (1.0 - _in_out(_seg(ts_raw, 0.08, OUT_LEN - 0.08)))
	var out_k := _seg(ts_raw, 0.0, 0.18) if state == "out" else 0.0
	last_tv = tv
	var swapped := tv >= T_SWAP

	# ---- 机位 ----
	var xf := _cam_seq(tv)
	var rh_age := now - roster_handoff_t0
	if rh_age >= 0.0 and rh_age < 0.34 and state == "in":
		var hk := _expo(clampf(rh_age / 0.34, 0.0, 1.0))
		xf = roster_handoff_xf.interpolate_with(xf, hk)
	var drift_k := _seg(ts, T_DONE - 0.5, 1.0) if state == "in" else (1.0 - _seg(ts, 0.0, 0.2) if state == "out" else 1.0)
	# 每章独有电影机位气质（告别千篇一律平视静态机位！）
	var ch_roll := 0.0
	var ch_pitch := 0.0
	var ch_fov_off := 0.0
	var ch_drift := Vector3(pointer.x * 70.0 + sin(now * 0.31) * 55.0, -pointer.y * 35.0 + cos(now * 0.23) * 25.0, sin(now * 0.19) * 120.0)
	match idx:
		0: # 第一章 影街：雨夜低倾角缓步前推，望向司辰母钟楼
			ch_roll = -0.018
			ch_drift.z -= sin(now * 0.28) * 110.0
		1: # 第二章 归晓大教堂：庄严仰视圣光彩窗与悬停圣女
			ch_pitch = 0.026
			ch_drift.y += sin(now * 0.36) * 42.0
		2: # 第三章 浮空白城：高空云海广角侧航滑行
			ch_drift.x += sin(now * 0.42) * 105.0
			ch_fov_off = -1.2
		3: # 第四章 天顶裂口：失重苍穹缓幅滚转悬浮
			ch_roll = sin(now * 0.52) * 0.036
			ch_drift.z += cos(now * 0.38) * 150.0
		_: # 演武 试剑回廊：沉静聚焦长焦推近
			ch_fov_off = -1.8
	xf.origin += ch_drift * drift_k
	# 【创意镜头 4：真三维垂直登天攀升 / 俯冲摇臂】切章时镜头真实仰角向上攀升或向下俯冲！
	var fl_cam := now - flip_t0
	if fl_cam >= 0.0 and fl_cam < 0.62 and state == "shown":
		var climb_p := sin(PI * clampf(fl_cam / 0.54, 0.0, 1.0))
		ch_pitch += 0.135 * flip_dir * climb_p
		xf.origin.y += 240.0 * flip_dir * climb_p
		xf.origin.z -= 340.0 * climb_p
	if absf(ch_pitch) > 0.0001:
		xf.basis = xf.basis * Basis(Vector3.RIGHT, ch_pitch * drift_k)
	if state == "launch":
		var e2 := pow(_in_out(_seg(ts, 0.35, 0.85)), 1.6)
		xf.origin += Vector3(0, 0, -DIST_T * 0.55 * e2)
	if lock_shake > 0.0:
		xf.origin += Vector3(sin(now * 71.0), cos(now * 53.0), 0.0) * 30.0 * lock_shake * lock_shake

	# ---- 分解钟与展开空间 ----
	rig.visible = swapped
	var glow_k := _in_out(_seg(lt, T_LAMP + 0.3, 0.3)) * (1.0 - out_k)
	var bell_k := exp(-maxf(lt - T_LAND, 0.0) * 7.0) if lt >= T_LAND and state == "in" else 0.0
	_rig_seq(tv, glow_k, bell_k, xf)
	# 若正从第一章垂直登天切离（或切回第一章），同步绑定 rig 垂直位移，保证钟体死死咬合钟楼绝不悬浮！
	var fl_r := now - flip_t0
	if fl_r >= 0.0 and fl_r < 0.82 and state == "shown":
		var far_h: float = float(layers[1]["h"])
		var fp_f := _seg(fl_r, 0.042 * 2.0, 0.48)
		if fp_f < 0.46 and flip_from == 0:
			var u_out := fp_f / 0.46
			rig.position.y -= flip_dir * far_h * u_out * u_out * 1.29
		elif fp_f >= 0.46 and idx == 0:
			var u_in := (fp_f - 0.46) / 0.54
			rig.position.y += flip_dir * far_h * pow(1.0 - _out3(u_in), 1.8) * 1.24
	var env_k := _seg(tv, T_SWAP, 0.15) * (1.0 - _seg(tv, 0.8, 0.12))
	_env_vis(env_k)

	# ---- 景片 ----
	stage_root.visible = tv >= 0.86 or state == "shown" or state == "launch"
	_layout_layers(lt, out_k, ts, xf)

	# ---- 首页钟体覆盖值 ----
	var fx_a := 1.0 - _seg(tv, T_SWAP, 0.3)
	var flash := 0.9 * exp(-(tv - T_SWAP) * 9.0) if swapped and tv < T_SWAP + 0.6 else 0.0
	var ca := 0.0 if swapped else 1.0
	var sweep := _seg(tv, 0.36, 0.26)
	var deb := 1.0 - _seg(tv, 0.62, 0.16)
	cam_st = {
		"cam_xf": xf, "cam_blend": 1.0, "cam_arc": Vector3.ZERO, "cam_roll": sw_roll + ch_roll * drift_k,
		"cam_fov": 30.0 + sw_fov + ch_fov_off * drift_k,
		"cam_shake": (T.shake["p"] as Vector2) if T != null else Vector2.ZERO,
		"minute_angle": hand_a, "hour_angle": hour0,
		"split": 0.0,
		"dial_a": ca, "dial_face_a": 1.0, "hub_a": ca, "minute_a": ca, "hour_a": ca,
		"seam_a": fx_a + flash, "rift_a": fx_a, "bg_a": ca,
		"rain_a": fx_a, "motes_a": maxf(fx_a, env_k), "debris": deb, "burst": 1.0 + 1.5 * _expo(_seg(tv, T_SWAP, 0.5)),
		"readout_a": fx_a, "glint": fx_a,
		"mark": [fx_a, fx_a, fx_a], "home_a": fx_a,
		"lamp_k": 0.4 + 0.6 * fx_a, "iris": 0.0,
		"flash": flash * 0.7, "pulse": flash,
		"light_a": lerpf(-2.6, 0.9, _in_out(sweep)) if swapped else -0.6,
		"light_k": (1.0 + 1.8 * sin(PI * sweep)) * (1.0 - 0.8 * _seg(tv, 0.8, 0.2)),
	}
	var lb_r := 0.0 if state == "shown" else (lerpf(0.098, 0.0, _seg(ts, 0.55, 0.65)) if state == "in" else 0.055)
	cine_st = {
		"accent_col": Color(T.accent) if T != null else Color("#9d73ff"),
		"chroma_amp": clampf(sw_chroma, 0.0, 0.032),
		"radial_blur": clampf(sw_blur, 0.0, 0.042),
		"impact_k": clampf(sw_impact, 0.0, 1.0),
		"letterbox_ratio": lb_r * (1.0 - out_k),
		"vignette_k": (0.45 if idx == 2 else 0.68) * (1.0 - out_k),
		"focus_uv": Vector2(0.62, 0.48),
	}


## 景片登场 / 灯光调度 / 翻面 / 退场
func _layout_layers(lt: float, out_k: float, ts: float, cam: Transform3D) -> void:
	var fl := now - flip_t0
	var stage_on := last_tv >= 0.86 or state == "shown" or state == "launch"
	var p_mid := _seg(lt, T_DOOR[0], T_DOOR[1])
	var p_near := _seg(lt, T_NEAR[0], T_NEAR[1])
	if state == "out":
		p_mid = 1.0 - _in_out(_seg(ts, 0.0, 0.2))
		p_near = 1.0 - _in_out(_seg(ts, 0.0, 0.24))
	# 灯光：若是从三维裂钟选角直接斩破接镜，第一帧即给足冷月夜底光，彻底消除 0.2 秒死黑空档！
	var sky_lit := 0.7 * _out3(_seg(lt, T_LAND, 0.25))
	if roster_handoff_t0 > 0.0 and state == "in":
		sky_lit = maxf(sky_lit, 0.38)
	sky_lit = lerpf(sky_lit, 1.0, _in_out(_seg(lt, T_LIT, 0.35)))
	var bolt := 0.0
	if lt >= T_BOLT:
		var bt := lt - T_BOLT
		bolt = 2.2 * exp(-bt * 22.0) + (1.0 * exp(-(bt - 0.09) * 26.0) if bt >= 0.09 else 0.0)
	var wave_e := _seg(lt, T_LAND, 0.7)
	for L in layers:
		var kind: String = L["kind"]
		var n: int = L["n"]
		var piv: Node3D = L["piv"]
		var m: ShaderMaterial = L["mat"]
		var w: float = L["w"]
		var h: float = L["h"]
		piv.position = L["hinge"]
		piv.rotation = Vector3.ZERO
		var p := 1.0 if stage_on else 0.0
		var lock_t := 10.0
		match kind:
			"midL", "midR":
				p = p_mid
				lock_t = lt - T_DOOR[0] - T_DOOR[1]
				piv.rotation.y = (1.0 if kind == "midL" else -1.0) * 100.0 * DEG * (1.0 - _lock(p))
			"near":
				p = p_near
				lock_t = lt - T_NEAR[0] - T_NEAR[1]
				# 从镜头身后掠过、冲到前景落位
				var e3 := _lock(p)
				piv.position += Vector3(-w * 0.3, -h * 0.08, float(L["z"]) + 900.0) * (1.0 - e3)
				piv.rotation.z = 0.08 * (1.0 - e3)
			"far":
				lock_t = lt - T_LAND
		var moving := 1.0 - _seg(p, 0.8, 0.2) if p < 1.0 else 0.0
		# 【真三维垂直登天升降】：近/中/远三层真景深错层坠落与高空降临；
		# 天幕层(n==0)严守安全视口区间内缓移+光雾过渡，100% 根除顶部像素边缘拉伸的竖条码穿帮！
		(L["mi"] as MeshInstance3D).rotation.y = 0.0
		var sky_cross := 0.0
		if fl < 0.82 and state != "out":
			var fp := _seg(fl, 0.042 * (3 - n), 0.48)
			if n == 0:
				if fp < 0.46:
					m.set_shader_parameter("tex", _layer_tex(flip_from, n))
					var u0 := fp / 0.46
					piv.position.y -= flip_dir * h * 0.07 * u0 * u0
					sky_cross = u0 * 0.42
				else:
					m.set_shader_parameter("tex", _layer_tex(idx, n))
					var u1 := (fp - 0.46) / 0.54
					piv.position.y += flip_dir * h * 0.07 * pow(1.0 - _out3(u1), 2.0)
					sky_cross = (1.0 - u1) * 0.42
			else:
				if fp < 0.46:
					m.set_shader_parameter("tex", _layer_tex(flip_from, n))
					var u_out := fp / 0.46
					var drop_k := u_out * u_out * (1.15 + float(n) * 0.14)
					piv.position.y -= flip_dir * h * drop_k
					piv.rotation.x += flip_dir * 0.16 * u_out
				else:
					m.set_shader_parameter("tex", _layer_tex(idx, n))
					var u_in := (fp - 0.46) / 0.54
					var rise_rem := pow(1.0 - _out3(u_in), 1.8) * (1.12 + float(n) * 0.12)
					var settle := -0.025 * sin(u_in * PI) * (1.0 - u_in)
					piv.position.y += flip_dir * h * (rise_rem + settle)
					piv.rotation.x -= flip_dir * 0.14 * (1.0 - _out3(u_in))
			moving = maxf(moving, sin(PI * fp))
		# 灯链：由近到远点亮暖光（近景路灯 → 中景窗灯 → 远景街灯到钟楼脚下）
		var front := 2.0
		match n:
			3:
				front = lerpf(-0.02, 1.02, _seg(lt, T_LAMP, 0.08))
			2:
				front = lerpf(-0.02, 1.02, _out3(_seg(lt, T_LAMP + 0.05, 0.22)))
			1:
				front = lerpf(0.45, 1.02, _seg(lt, T_LAMP + 0.24, 0.12))
		var lit := _in_out(_seg(lt, T_LIT + 0.04 * (3 - n), 0.36))
		if n == 0:
			lit = sky_lit
		lit *= 1.0 - out_k
		var fk := 0.0
		if lock_t >= 0.0 and lock_t < 0.5 and state == "in":
			fk = 0.45 * exp(-lock_t * 12.0)
		var params := {
			"lit": lit, "glow_front": front, "glow_on": 1.0 - out_k,
			"outline": 0.0 if n == 0 else 1.0 - lit, "rim": moving,
			"flash": fk + (bolt * 0.55 if n > 0 else 0.0),
			"sky_flash": (bolt + sky_cross) if n == 0 else 0.0,
		}
		for key in params:
			m.set_shader_parameter(key, params[key])
		m.set_shader_parameter("opacity", 1.0 if p > 0.0 else 0.0)
		if n == 0:
			var sky_z: float = o_e.z - float(L["z"])
			var t := (cam.origin.z - sky_z) / maxf(cam.origin.z - t_c.z, 1.0)
			var pp := cam.origin + (t_c - cam.origin) * t
			var sc0: Vector3 = o_e + Vector3(0, 0, -float(L["z"]))
			m.set_shader_parameter("wave_c", Vector2((pp.x - sc0.x) / w + 0.5, 0.5 - (pp.y - sc0.y) / h))
			m.set_shader_parameter("wave_r", 0.03 + 1.3 * _out3(wave_e) if lt >= T_LAND and wave_e < 1.0 else -1.0)
			m.set_shader_parameter("wave_k", pow(1.0 - wave_e, 1.4))
		if kind == "near":
			params["tex"] = m.get_shader_parameter("tex")
			params["flash"] = 0.0
			_near_trail(piv.transform * (L["mi"] as MeshInstance3D).transform, cam, 1.0 if p > 0.0 else 0.0, params)
	wave_mi.visible = false
	# 按《剧情与主题规划.md》分章气象粒子（严禁在无雨的浮空白城、定格大教堂、室内试剑回廊下斜雨！）
	var rain_k := _seg(lt, T_BOLT, 0.1) * (1.0 - out_k)
	var rmat := rain_mmi.material_override as ShaderMaterial
	var weather := 0  # 0=第1章影街冷雨, 1=第2章大教堂悬停金尘, 2=第3章浮空白城无雨微墨尘, 3=第4章天顶裂口升腾晶碎, 4=第5章室内试剑月光浮尘
	if idx == 1:
		weather = 1
	elif idx == 2:
		weather = 2
	elif idx == 3:
		weather = 3
	elif idx == 4:
		weather = 4
	match weather:
		0:
			rmat.set_shader_parameter("tint", Color(0.72, 0.80, 0.98))
			rmat.set_shader_parameter("opacity", 0.34 * rain_k)
		1:
			rmat.set_shader_parameter("tint", Color(1.0, 0.92, 0.72))
			rmat.set_shader_parameter("opacity", 0.36 * rain_k)
		2:
			rmat.set_shader_parameter("tint", Color(0.08, 0.08, 0.12))
			rmat.set_shader_parameter("opacity", 0.14 * rain_k)
		3:
			rmat.set_shader_parameter("tint", Color(1.0, 0.96, 0.88).lerp(Color(T.accent), 0.28))
			rmat.set_shader_parameter("opacity", 0.52 * rain_k)
		_:
			rmat.set_shader_parameter("tint", Color(0.82, 0.88, 0.98))
			rmat.set_shader_parameter("opacity", 0.24 * rain_k)
	rain_mmi.visible = rain_k > 0.001
	if rain_mmi.visible:
		var D: float = clock.D
		var mm := rain_mmi.multimesh
		var rb := Basis(Vector3.BACK, -9.0 * DEG) if weather == 0 else (Basis(Vector3.BACK, 45.0 * DEG) if weather == 3 else Basis.IDENTITY)
		for i in rain_drops.size():
			var d: Dictionary = rain_drops[i]
			var z: float = d["z"]
			var hw := W * 0.5 / D * z * 1.15
			var hh := H * 0.5 / D * z * 1.15
			var s := z / D
			var y: float
			var w_px: float
			var h_px: float
			match weather:
				0:
					y = (fposmod(float(d["y"]) - now * float(d["sp"]) * 1.7, 1.0) * 2.0 - 1.0) * hh
					w_px = 2.0 * s
					h_px = (44.0 + 28.0 * float(d["sp"])) * s
				1:
					# 归晓大教堂：光柱内悬停圣尘，集中在右侧光束路径附近，左侧标题区克制留白
					var in_beam := float(d["x"]) > -0.15
					var drift_y := sin(now * 0.45 + float(i) * 1.7) * 0.008
					y = ((float(d["y"]) + drift_y) * 2.0 - 1.0) * hh
					w_px = ((3.2 + 2.2 * float(d["sp"])) * s) if in_beam else 0.0
					h_px = ((4.6 + 3.2 * float(d["sp"])) * s) if in_beam else 0.0
				2:
					# 浮空白城：绝对无雨无风，极稀疏微尘
					var show_mote := (i % 4 == 0)
					y = ((float(d["y"]) + sin(now * 0.25 + float(i)) * 0.004) * 2.0 - 1.0) * hh
					w_px = (2.6 * s) if show_mote else 0.0
					h_px = (3.8 * s) if show_mote else 0.0
				3:
					# 天顶裂口：稀疏升腾的菱形时间晶碎（绝非雨丝！）
					var show_shard := (i % 2 == 0)
					y = (fposmod(float(d["y"]) + now * float(d["sp"]) * 0.34, 1.0) * 2.0 - 1.0) * hh
					w_px = ((4.2 + 2.4 * float(d["sp"])) * s) if show_shard else 0.0
					h_px = ((7.5 + 4.5 * float(d["sp"])) * s) if show_shard else 0.0
				_:
					# 试剑回廊（室内钟楼）：月光斜照下的微弱悬浮尘埃，绝不室内下雨
					var show_dust := (i % 2 == 0)
					y = ((float(d["y"]) + sin(now * 0.35 + float(i) * 1.3) * 0.012) * 2.0 - 1.0) * hh
					w_px = (3.2 * s) if show_dust else 0.0
					h_px = (3.2 * s) if show_dust else 0.0
			mm.set_instance_transform(i, Transform3D(rb * Basis.from_scale(Vector3(w_px, h_px, 1.0)), o_e + Vector3(float(d["x"]) * hw, y, -z)))


## 近景掠过镜头时的拖影
func _near_trail(world: Transform3D, cam: Transform3D, a_main: float, params: Dictionary) -> void:
	_ghost_update({"hist": near_hist, "ghosts": near_ghosts}, world, cam, a_main, params)


# ================================================================ 每帧（钟体更新之后：只排二维字）
func post_layout() -> void:
	if state == "hidden":
		return
	_layout_info()


func _layout_info() -> void:
	var ts := now - t_state
	var leaving := state == "out"
	var launching := state == "launch"
	var fade := 1.0 - _seg(ts, 0.0, 0.12) if leaving else 1.0
	var rt := now - reveal_t0
	var ch: Dictionary = chapters[idx]
	var unlocked: bool = ch["unlocked"]
	var lt := ts if launching else -10.0
	var slide := Vector2(-340.0, 0.0)
	var o_tag := _expo(_seg(lt, 0.0, 0.25))
	var o_name := _expo(_seg(lt, 0.04, 0.25))
	var o_sub := _expo(_seg(lt, 0.08, 0.25))
	var o_go := _expo(_seg(lt, 0.12, 0.25))
	var shk := Vector2(sin(now * 61.0), cos(now * 47.0)) * 9.0 * lock_shake * lock_shake

	var te := _expo(_seg(rt, 0.0, 0.18))
	var is_white_city := idx == 2
	var y_shift := -26.0 if is_white_city else 0.0
	tag.position = Vector2(NAME_X + 6.0 - 160.0 * (1.0 - te), NAME_Y - 102.0 + y_shift) + slide * o_tag
	tag.rotation = 0.0
	tag.modulate.a = clampf(te * 3.0, 0.0, 1.0) * fade * (1.0 - o_tag)
	tag_box.color = WHITE if (unlocked and not is_white_city) else (INK if is_white_city else Color("#12121b"))
	tag_lb.add_theme_color_override("font_color", INK if (unlocked and not is_white_city) else WHITE)
	head_bg.color = Color(INK, 0.88 if is_white_city else 0.0)
	head_img.modulate = WHITE

	var big := state == "in" or (state == "shown" and t_sw < t_state)
	var nm: Node2D = name_cur["root"]
	nm.position = Vector2(NAME_X, NAME_Y + y_shift) + slide * o_name + shk
	var chars: Array = name_cur["chars"]
	var hh: float = name_cur["h"]
	for k in chars.size():
		var c: Dictionary = chars[k]
		var tk := rt - 0.02 - 0.038 * k
		var e := _expo(_seg(tk, 0.0, 0.14)) if big else _back(_seg(tk, 0.0, 0.18), 1.5)
		var s0 := 1.45 if big else 1.18
		var s := lerpf(s0, 1.0, clampf(e, 0.0, 1.12))
		var cn: Node2D = c["n"]
		var cw: float = c["w"]
		var drop := Vector2(0.0, (-34.0 if big else -72.0) * (1.0 - clampf(e, 0.0, 1.0)))
		cn.position = Vector2(float(c["x0"]), 0.0) + drop + Vector2(cw, hh) * 0.5 * (1.0 - s)
		cn.scale = Vector2(s, s)
		cn.modulate.a = clampf(_seg(tk, 0.0, 0.04), 0.0, 1.0) * fade * (1.0 - o_name)
		var ee := _expo(_seg(tk, 0.04, 0.24))
		var echo: TextureRect = c["echo"]
		echo.modulate = Color(T.accent, 0.52 if is_white_city else 0.78)
		echo.position = Vector2(14, 10) + Vector2(56, -42) * (1.0 - ee)
		(c["face"] as TextureRect).modulate = WHITE if unlocked else Color("#e6e8f0")
		var sh_tr: TextureRect = c["sh"]
		sh_tr.modulate = INK
		sh_tr.position = Vector2(10, 12)

	var se := _expo(_seg(rt - 0.10, 0.0, 0.22))
	sub_clip.position = Vector2(NAME_X + 6.0, NAME_Y + hh + 18.0 + y_shift * 0.5) + slide * o_sub
	var sub_w := sub_lb.get_minimum_size().x + 52.0
	sub_clip.size.x = sub_w * se
	sub_clip.modulate.a = clampf(se * 4.0, 0.0, 1.0) * fade * (1.0 - o_sub)
	sub_bg.color = Color(INK, 0.92 if is_white_city else 0.82)

	var gw := 468.0 if unlocked else 412.0
	var gh := 104.0
	var sl := 20.0
	var box := PackedVector2Array([Vector2(sl, 0), Vector2(gw, 0), Vector2(gw - sl, gh), Vector2(0, gh)])
	go_plate.polygon = box
	go_echo.polygon = box
	go_edge.polygon = PackedVector2Array([Vector2(sl - 2, 0), Vector2(sl + 14, 0), Vector2(14, gh), Vector2(-2, gh)])
	go_edge.color = Color(T.accent) if unlocked else Color("#787f92")
	go_plate.color = WHITE.lerp(Color(1.18, 1.18, 1.18), hover_k) if unlocked else Color(0.045, 0.046, 0.068, 0.94)
	go_echo.color = Color(INK, 0.92)
	go_border.points = box
	go_border.default_color = Color(WHITE, 0.0 if unlocked else 0.28)
	go_lb.add_theme_font_size_override("font_size", 60 if unlocked else 42)
	var lsz := go_lb.get_minimum_size()
	go_lb.position = Vector2(54, (gh - lsz.y) * 0.5 - 2) if unlocked else Vector2(52, 12)
	go_lb.add_theme_color_override("font_color", INK if unlocked else Color(WHITE, 0.84))
	go_sub_lb.visible = not unlocked
	go_sub_lb.position = Vector2(52, 64)
	go_hint.text = "A" if T.last_pad else "ENTER"
	var hsz := go_hint.get_minimum_size()
	var kx := 54.0 + lsz.x + 26.0
	var kw := hsz.x + 28.0
	var kh := 38.0
	var ky := (gh - kh) * 0.5
	go_key_bg.polygon = PackedVector2Array([
		Vector2(kx + 8, ky), Vector2(kx + kw + 8, ky),
		Vector2(kx + kw, ky + kh), Vector2(kx, ky + kh),
	])
	go_key_bg.color = INK
	go_hint.add_theme_color_override("font_color", Color(T.accent).lightened(0.25))
	go_hint.position = Vector2(kx + 18.0, ky + 4.0)
	var ge := _expo(_seg(rt - 0.14, 0.0, 0.22))
	go.position = Vector2(NAME_X + 8.0 - 90.0 * (1.0 - ge), NAME_Y + hh + 104.0 + y_shift * 0.5) + slide * o_go + shk
	go.rotation = 0.0
	go.scale = Vector2.ONE * (lerpf(0.94, 1.0, ge) * (1.0 + 0.03 * hover_k))
	go.modulate.a = clampf(ge * 2.5, 0.0, 1.0) * fade * (1.0 - o_go)
	go_echo.position = Vector2(10, 10)

	var od := now - old_t0
	info_old.visible = od < 0.085 and old_t0 > t_state and String(old_a["word"]) != ""
	if info_old.visible:
		var r: Node2D = old_a["root"]
		r.position = Vector2(NAME_X, NAME_Y)
		var och: Array = old_a["chars"]
		for k in och.size():
			var c: Dictionary = och[k]
			var e := _in_out(_seg(od, 0.008 * k, 0.075))
			var cn: Node2D = c["n"]
			cn.position = Vector2(float(c["x0"]), -70.0 * e)
			cn.scale = Vector2.ONE
			cn.modulate.a = 1.0 - e
			(c["echo"] as TextureRect).modulate = Color(T.accent, 0.0)

	# 刷新新一代电影级《登天纵轴》择章 HUD（旧版白块/黑框贴纸已隐藏）
	if stage_hud != null:
		stage_hud.queue_redraw()


## [YG-MARK] 新一代电影级《登天纵轴》择章 HUD（彻底废除白块贴纸，融合左侧雕塑简报 + 出战角色眼神铭牌 + 锻钢出击刃 + 右侧垂直登天纵轴！）
func _draw_stage_hud() -> void:
	var ts := now - t_state
	var leaving := state == "out"
	var launching := state == "launch"
	var fade := 1.0 - _seg(ts, 0.0, 0.14) if leaving else 1.0
	var rt := now - reveal_t0
	var out_launch := _expo(_seg(ts, 0.0, 0.22)) if launching else 0.0
	# 框架层（暗场、抬头、右侧登天纵轴、出战主角）在切章时保持稳固不闪烁，仅首次进场淡入
	var is_switching := state == "shown" and t_sw > t_state
	var frame_e := 1.0 if is_switching else _expo(_seg(rt + 0.08, 0.0, 0.26))
	var base_a := clampf(frame_e, 0.0, 1.0) * fade * (1.0 - out_launch)
	if base_a <= 0.005:
		return
	# 章节内容层（章标、副标、出击刃）随切章干脆滑入
	var e_all := _expo(_seg(rt + 0.04, 0.0, 0.24))
	var a := clampf(e_all, 0.0, 1.0) * fade * (1.0 - out_launch)

	var c := stage_hud
	var ch: Dictionary = chapters[idx]
	var unlocked: bool = bool(ch["unlocked"])
	var is_white_city := idx == 2
	var acc := Color(T.accent) if T != null else Color("#9d73ff")
	var rim := acc.lerp(WHITE, 0.35)
	var f_cn: Font = T.font_cn as Font
	var f_med: Font = T.font_cn_med as Font
	var f_lat: Font = T.font_lat as Font
	var slide_x := -76.0 * (1.0 - e_all) - 240.0 * out_launch
	var shk := sin(now * 68.0) * 10.0 * lock_shake * lock_shake

	# 1. 左侧电影级氛围暗场渐层 + 右侧登天纵轴托底（切章稳固不闪！）
	var sc_l := Color(INK, (0.78 if is_white_city else 0.90) * base_a)
	var sc_m := Color(INK, (0.44 if is_white_city else 0.56) * base_a)
	var sc_0 := Color(INK, 0.0)
	c.draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(460, 0), Vector2(460, H), Vector2(0, H)]), PackedColorArray([sc_l, sc_m, sc_m, sc_l]))
	c.draw_polygon(PackedVector2Array([Vector2(460, 0), Vector2(860, 0), Vector2(860, H), Vector2(460, H)]), PackedColorArray([sc_m, sc_0, sc_0, sc_m]))
	var rs_0 := Color(INK, 0.0)
	var rs_r := Color(INK, (0.68 if is_white_city else 0.84) * base_a)
	c.draw_polygon(PackedVector2Array([Vector2(1500, 0), Vector2(W, 0), Vector2(W, H), Vector2(1500, H)]), PackedColorArray([rs_0, rs_r, rs_r, rs_0]))

	# 2. 左上角精细司辰抬头
	var ox := 94.0 + slide_x
	var top_y := 58.0
	c.draw_line(Vector2(88, top_y), Vector2(88, top_y + 34), Color(acc, 0.95 * base_a), 3.0, true)
	c.draw_string(f_med, Vector2(108, top_y + 23), "择章出击 · 登天纵轴", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(WHITE, 0.96 * base_a))
	c.draw_string(f_lat, Vector2(368, top_y + 22), "05:59", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(rim, 0.82 * base_a))
	c.draw_line(Vector2(88, top_y + 42), Vector2(536, top_y + 42), Color(WHITE, 0.20 * base_a), 1.0, true)

	# 3. 巨型冷钢罗马数字水印（I / II / III / IV / 试 浮于章名刀锋宋大字背后！）
	var num_str := String(ch.get("num", "I"))
	c.draw_string(f_lat if num_str != "试" else f_med, Vector2(ox - 10.0, 442.0), num_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 210, Color(acc if not is_white_city else WHITE, (0.14 if not is_white_city else 0.22) * a))

	# 4. 纯中文精刻司辰章节标签（彻底告别中英混排与白方块！）
	var tag_y := 240.0
	var dm0 := Vector2(ox + 7.0, tag_y - 7.0)
	c.draw_colored_polygon(PackedVector2Array([dm0 + Vector2(-7, 0), dm0 + Vector2(0, -7), dm0 + Vector2(7, 0), dm0 + Vector2(0, 7)]), Color(acc, 0.96 * a))
	var ch_num := "试" if idx == 4 else ("0%d" % (idx + 1))
	c.draw_string(f_lat if idx != 4 else f_med, Vector2(ox + 26.0, tag_y), ch_num, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(rim, 0.96 * a))
	c.draw_string(f_med, Vector2(ox + 68.0, tag_y), "·  " + String(ch["tag"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(WHITE, 0.96 * a))
	c.draw_line(Vector2(ox, tag_y + 14.0), Vector2(ox + 340.0, tag_y + 14.0), Color(acc, 0.45 * a), 1.3, true)

	# 5. 章名下方精刻副标与场景地点（位于刀锋宋大字之下 y = 528）
	var hh: float = float(name_cur.get("h", 220.0))
	var sub_y := NAME_Y + hh + 24.0
	c.draw_line(Vector2(ox, sub_y - 4.0), Vector2(ox, sub_y + 34.0), Color(acc, 0.92 * a), 3.0, true)
	var sub_txt := String(ch["sub"])
	c.draw_string(f_med, Vector2(ox + 20.0, sub_y + 26.0), sub_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(INK, 0.95 * a))
	c.draw_string(f_med, Vector2(ox + 18.0, sub_y + 24.0), sub_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(WHITE, 0.96 * a))

	# 6. 出战主角眼神铭牌（与三维角色选择无缝咬合，直接呈现当前选定女主！）
	var hero_k := String(T.hero) if T != null else "shuo"
	var hero_title := String(T.pal.get("title", "「夜鸦」朔")) if T != null else "「夜鸦」朔"
	var hero_note := String(T.pal.get("note", "鸦黑直刃 · 冷紫裂口")) if T != null else ""
	var badge_y := sub_y + 62.0
	var bw := 386.0
	var bh := 66.0
	var bpoly := PackedVector2Array([
		Vector2(ox + 10, badge_y), Vector2(ox + bw, badge_y),
		Vector2(ox + bw - 10, badge_y + bh), Vector2(ox, badge_y + bh),
	])
	c.draw_colored_polygon(bpoly, Color(INK, 0.84 * a))
	c.draw_polyline(PackedVector2Array([bpoly[0], bpoly[1], bpoly[2], bpoly[3], bpoly[0]]), Color(acc, 0.56 * a), 1.3, true)
	var ft: Texture2D = _hud_tex("roster_" + hero_k + ".jpg")
	if ft != null:
		var fw := float(ft.get_width())
		var fh := float(ft.get_height())
		c.draw_texture_rect_region(ft, Rect2(ox + 12.0, badge_y + 6.0, 96.0, 54.0), Rect2(fw * 0.16, fh * 0.18, fw * 0.68, fh * 0.36), Color(1, 1, 1, 0.96 * a))
		c.draw_rect(Rect2(ox + 12.0, badge_y + 6.0, 96.0, 54.0), Color(acc, 0.72 * a), false, 1.2)
	c.draw_string(f_med, Vector2(ox + 124.0, badge_y + 24.0), "当前出战", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(rim, 0.78 * a))
	c.draw_string(f_med, Vector2(ox + 124.0, badge_y + 50.0), hero_title + "  ·  " + hero_note.substr(0, 4), HORIZONTAL_ALIGNMENT_LEFT, -1, 21, Color(WHITE, 0.96 * a))

	# 7. 锻钢棱切出击刃按钮（彻底取代傻白方块！）
	var cx := ox + shk
	var cy := badge_y + 88.0
	var cw := 386.0 + hover_k * 22.0
	var ch_h := 78.0
	_cta_rect = Rect2(cx - 8.0, cy - 8.0, cw + 16.0, ch_h + 16.0)
	var sk := 16.0
	var btn := PackedVector2Array([
		Vector2(cx + sk, cy), Vector2(cx + cw, cy),
		Vector2(cx + cw - sk, cy + ch_h), Vector2(cx, cy + ch_h),
	])
	var btn_sh := PackedVector2Array()
	for bp in btn:
		btn_sh.append(bp + Vector2(9, 11))
	c.draw_colored_polygon(btn_sh, Color(INK, 0.90 * a))

	if unlocked:
		var bg_l := acc.darkened(0.28).lerp(acc, hover_k * 0.45)
		var bg_r := acc.lerp(WHITE, 0.18 + hover_k * 0.18)
		bg_l.a = 0.96 * a
		bg_r.a = 0.98 * a
		c.draw_polygon(btn, PackedColorArray([bg_l, bg_r, bg_r, bg_l]))
		var sp := fmod(now * 0.74, 1.0)
		var sx0 := cx + lerpf(-40.0, cw + 20.0, sp)
		var shine_a := sin(sp * PI) * 0.40 * a
		c.draw_line(Vector2(clampf(sx0, cx + 10, cx + cw - 10), cy + 2), Vector2(clampf(sx0 - 26.0, cx + 4, cx + cw - 12), cy + ch_h - 2), Color(1, 1, 1, shine_a), 26.0, true)
		c.draw_polyline(PackedVector2Array([btn[0], btn[1], btn[2], btn[3], btn[0]]), Color(WHITE, (0.82 + 0.18 * hover_k) * a), 1.9, true)
		var dm := Vector2(cx + 40.0, cy + ch_h * 0.5)
		c.draw_colored_polygon(PackedVector2Array([dm + Vector2(-9, 0), dm + Vector2(0, -9), dm + Vector2(9, 0), dm + Vector2(0, 9)]), Color(WHITE, a))
		c.draw_string(f_med, Vector2(cx + 68.0, cy + 50.0), "开始出击", HORIZONTAL_ALIGNMENT_LEFT, -1, 32, Color(WHITE, a))
		var key_t := "A" if (T != null and T.last_pad) else "ENTER"
		c.draw_string(f_lat, Vector2(cx + cw - 108.0, cy + 47.0), key_t, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color(WHITE, 0.88 * a))
	else:
		c.draw_colored_polygon(btn, Color("#10111a", 0.92 * a))
		c.draw_polyline(PackedVector2Array([btn[0], btn[1], btn[2], btn[3], btn[0]]), Color(WHITE, (0.34 + 0.42 * lock_shake) * a), 1.5, true)
		c.draw_string(f_med, Vector2(cx + 34.0, cy + 43.0), "尚未开放 · 封印中", HORIZONTAL_ALIGNMENT_LEFT, -1, 25, Color(WHITE, 0.84 * a))
		c.draw_string(f_cn, Vector2(cx + 34.0, cy + 66.0), "完成前序章节后解锁登天通道", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(rim, 0.68 * a))

	# 8. 右侧垂直《登天纵轴》司辰高程尺 + 机械咬合攀升齿轮（每次切章咔嚓转过 60° 托举升空！）
	var rx := 1842.0
	var gear_c := Vector2(1932.0, 430.0)
	var gear_r := 218.0
	c.draw_arc(gear_c, gear_r, PI * 0.55, PI * 1.45, 48, Color(WHITE, 0.18 * base_a), 2.0, true)
	c.draw_arc(gear_c, gear_r - 22.0, PI * 0.58, PI * 1.42, 40, Color(acc, 0.28 * base_a), 1.4, true)
	for gi in 24:
		var ga := tower_gear_ang + float(gi) * TAU / 24.0
		var gp := gear_c + Vector2(cos(ga), sin(ga)) * gear_r
		if gp.x < W + 10.0:
			var gp2 := gear_c + Vector2(cos(ga), sin(ga)) * (gear_r + (14.0 if gi % 3 == 0 else 8.0))
			c.draw_line(gp, gp2, Color(rim if gi % 3 == 0 else WHITE, (0.42 if gi % 3 == 0 else 0.18) * base_a), 2.4 if gi % 3 == 0 else 1.2, true)
	c.draw_line(Vector2(rx, 210.0), Vector2(rx, 648.0), Color(WHITE, 0.30 * base_a), 1.8, true)
	c.draw_line(Vector2(rx - 104.0, 696.0), Vector2(rx + 18.0, 696.0), Color(WHITE, 0.22 * base_a), 1.0, true)
	for ti in 23:
		var ty := lerpf(210.0, 648.0, float(ti) / 22.0)
		var maj := ti % 5 == 0
		c.draw_line(Vector2(rx, ty), Vector2(rx + (12.0 if maj else 6.0), ty), Color(WHITE, (0.42 if maj else 0.18) * base_a), 1.2)

	var order_y := [618.0, 492.0, 366.0, 240.0, 774.0]
	for i in chapters.size():
		var ci: Dictionary = chapters[i]
		var cy_n: float = float(order_y[i])
		var is_on := i == idx
		var is_un := bool(ci["unlocked"])
		var is_hov := i == _hover_tower
		var nc := Vector2(rx, cy_n)
		var r := 11.5 if is_on else (8.5 if is_hov else 6.5)

		if is_on:
			c.draw_line(Vector2(rx - 224.0, cy_n), Vector2(rx - 24.0, cy_n), Color(acc, 0.85 * base_a), 1.8, true)
			var rr := 20.0
			var rot := now * 1.1
			var rpts := PackedVector2Array()
			for k in 5:
				var ak := rot + float(k) * PI * 0.5
				rpts.append(nc + Vector2(cos(ak), sin(ak)) * rr)
			c.draw_polyline(rpts, Color(rim, 0.96 * base_a), 1.7, true)

		var dpts := PackedVector2Array([nc + Vector2(0, -r), nc + Vector2(r, 0), nc + Vector2(0, r), nc + Vector2(-r, 0)])
		c.draw_colored_polygon(dpts, Color(acc if is_on else (Color("#5e657c") if is_un else Color("#232534")), (0.98 if is_on else 0.88) * base_a))
		c.draw_polyline(PackedVector2Array([dpts[0], dpts[1], dpts[2], dpts[3], dpts[0]]), Color(WHITE if is_on else (rim if is_un else Color(WHITE, 0.36)), base_a), 1.4, true)

		var nm := String(ci["name"])
		var num_n := String(ci["num"])
		var fs := 24 if is_on else 19
		var sz_n := f_med.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var num_w := f_lat.get_string_size(num_n, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		var tx_n := rx - 32.0 - sz_n.x
		# 给每个登天节点配极薄暗黑曜石托片，哪怕在雪白浮空白城与亮金试剑齿轮上依然 100% 锐利可读！
		var pill_l := tx_n - num_w - 28.0
		var pill_r := rx - 18.0
		var pill_h := 34.0 if is_on else 28.0
		var pill := PackedVector2Array([
			Vector2(pill_l + 8.0, cy_n - pill_h * 0.5), Vector2(pill_r, cy_n - pill_h * 0.5),
			Vector2(pill_r - 8.0, cy_n + pill_h * 0.5), Vector2(pill_l, cy_n + pill_h * 0.5),
		])
		c.draw_colored_polygon(pill, Color(INK, (0.86 if is_on else 0.56) * base_a))
		if is_on:
			c.draw_polyline(PackedVector2Array([pill[0], pill[1], pill[2], pill[3], pill[0]]), Color(acc, 0.72 * base_a), 1.2, true)
		var col_n := WHITE if is_on else (Color("#f0f2fc") if is_un else Color("#c2c5da"))
		c.draw_string(f_med, Vector2(tx_n + 2.0, cy_n + 8.0), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(INK, 0.96 * base_a))
		c.draw_string(f_med, Vector2(tx_n, cy_n + 6.0), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(col_n, (0.99 if is_on else 0.90) * base_a))
		c.draw_string(f_lat if num_n != "试" else f_med, Vector2(tx_n - num_w - 14.0, cy_n + 5.0), num_n, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(acc if is_on else rim, (0.98 if is_on else 0.76) * base_a))


# ================================================================ 命中：支持点击锻钢「开始出击」或右侧《登天纵轴》直接跳章
func hit_card(p: Vector2) -> int:
	if state == "in" and now - t_state > 0.45:
		snap_in()
	if state != "shown":
		return -1
	_hover_tower = -1
	for i in _tower_rects.size():
		if (_tower_rects[i] as Rect2).has_point(p):
			_hover_tower = i
			return i
	return idx if _cta_rect.has_point(p) else -1
