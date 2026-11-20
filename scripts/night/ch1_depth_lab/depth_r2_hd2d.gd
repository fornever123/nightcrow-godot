extends Node2D
## 路线 2（R2）：Godot 4.7.2 Forward+ 真实 3D SubViewport HD-2D 哥特影街样板（U2 实景街）
## 真正 3D 透视街道 + 手绘厚涂无缝 PBR 材质（法线/湿石粗糙度/窗光自发光）+ 实时 3D 点光/阴影
## + 原生 3D 体积雾（VolumetricFog）+ 物理前后景深（CameraAttributesPractical DOF）
## + 主角 3D 接触软影与紫刀光地面实时反光！

const ART_DIR := "res://assets/image/rain_street/depth_lab_20261118/"
const FLOOR := 580.0
const WORLD_TO_3D := 0.01       # 100 世界像素 = 1.0 米，比例直观精准

var camera: Camera2D
var player: Node2D
var _t := 0.0

var _vp: SubViewport
var _view_sprite: Sprite2D
var _cam3d: Camera3D
var _hero_light: OmniLight3D
var _hero_shadow_mesh: MeshInstance3D
var _lamp_lights: Array[OmniLight3D] = []
var _fg_contact_layer: Node2D


static func _load_png(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	if not FileAccess.file_exists(path):
		return null
	var img := Image.new()
	if img.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
		return null
	return ImageTexture.create_from_image(img)


func setup(cam: Camera2D, hero: Node2D) -> void:
	camera = cam
	player = hero


func _make_pbr(name: String, uv_scale: Vector3, metallic: float, rough_mul: float, emit_energy: float = 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _load_png(ART_DIR + name + ".png")
	mat.normal_enabled = true
	mat.normal_texture = _load_png(ART_DIR + name + "_normal.png")
	mat.normal_scale = 1.15
	mat.roughness_texture = _load_png(ART_DIR + name + "_rough.png")
	mat.roughness = rough_mul
	mat.metallic = metallic
	mat.uv1_scale = uv_scale
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if emit_energy > 0.0:
		var et := _load_png(ART_DIR + name + "_emit.png")
		if et != null:
			mat.emission_enabled = true
			mat.emission_texture = et
			mat.emission_energy_multiplier = emit_energy
	return mat


func _add_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, cast_shadow: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _add_cyl(parent: Node3D, r_top: float, r_bot: float, h: float, pos: Vector3, mat: Material, segs: int = 12) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	cm.radial_segments = segs
	mi.mesh = cm
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _ready() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(1280, 720)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.use_taa = true
	add_child(_vp)

	_view_sprite = Sprite2D.new()
	_view_sprite.texture = _vp.get_texture()
	_view_sprite.z_as_relative = false
	_view_sprite.z_index = -80
	add_child(_view_sprite)

	_fg_contact_layer = Node2D.new()
	_fg_contact_layer.z_as_relative = false
	_fg_contact_layer.z_index = -3
	_fg_contact_layer.draw.connect(_draw_2d_contact)
	add_child(_fg_contact_layer)

	var root3d := Node3D.new()
	_vp.add_child(root3d)
	_build_environment(root3d)
	_build_gothic_street_3d(root3d)
	_build_camera_and_hero_proxy(root3d)


func _build_environment(root3d: Node3D) -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var psky := ProceduralSkyMaterial.new()
	# 无蓝滤镜的中性银灰雨夜天顶 + 远处驱时冷白雾光
	psky.sky_top_color = Color(0.11, 0.12, 0.145)
	psky.sky_horizon_color = Color(0.36, 0.37, 0.39)
	psky.ground_bottom_color = Color(0.05, 0.055, 0.065)
	psky.ground_horizon_color = Color(0.24, 0.25, 0.27)
	psky.sun_angle_max = 24.0
	psky.sun_curve = 0.25
	sky.sky_material = psky
	env.sky = sky

	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.30, 0.31, 0.34)
	env.ambient_light_energy = 0.65

	# 原生 Forward+ 物理体积雾（VolumetricFog）+ 远距空气透视雾
	env.fog_enabled = true
	env.fog_light_color = Color(0.34, 0.35, 0.37)
	env.fog_light_energy = 0.85
	env.fog_density = 0.011
	env.fog_aerial_perspective = 0.55

	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.022
	env.volumetric_fog_albedo = Color(0.46, 0.47, 0.50)
	env.volumetric_fog_emission = Color(0.08, 0.085, 0.095)
	env.volumetric_fog_anisotropy = 0.58
	env.volumetric_fog_length = 95.0

	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.08
	env.glow_enabled = true
	env.glow_intensity = 0.65
	env.glow_bloom = 0.18
	env.glow_hdr_threshold = 0.92
	env.ssao_enabled = true
	env.ssao_radius = 1.4
	env.ssao_intensity = 1.6
	we.environment = env

	# 物理 HD-2D 移轴前后景深（聚焦在主角所走的 Z=0 湿石板街道，前景栏杆与远处城群自然虚化！）
	var ca := CameraAttributesPractical.new()
	ca.dof_blur_far_enabled = true
	ca.dof_blur_far_distance = 22.0
	ca.dof_blur_far_transition = 28.0
	ca.dof_blur_near_enabled = true
	ca.dof_blur_near_distance = 10.5
	ca.dof_blur_near_transition = 5.0
	ca.dof_blur_amount = 0.11
	we.camera_attributes = ca
	root3d.add_child(we)

	# 右上天顶冷白「驱时天光」斜劈穿透体积雾
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(0.95, 0.96, 1.0)
	sun.light_energy = 1.65
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-34.0, 38.0, 0.0)
	root3d.add_child(sun)


func _build_gothic_street_3d(root3d: Node3D) -> void:
	var mat_road := _make_pbr("r2_tex_cobble", Vector3(24.0, 4.5, 1.0), 0.12, 0.42)
	var mat_facade := _make_pbr("r2_tex_facade", Vector3(1.5, 1.2, 1.0), 0.04, 0.85, 2.4)
	var mat_stone := _make_pbr("r2_tex_stone_trim", Vector3(2.0, 2.0, 1.0), 0.05, 0.78)
	var mat_iron := StandardMaterial3D.new()
	mat_iron.albedo_color = Color(0.06, 0.065, 0.075)
	mat_iron.metallic = 0.75
	mat_iron.roughness = 0.36
	var mat_roof := StandardMaterial3D.new()
	mat_roof.albedo_color = Color(0.11, 0.115, 0.13)
	mat_roof.roughness = 0.58
	var mat_bulb := StandardMaterial3D.new()
	mat_bulb.albedo_color = Color(1.0, 0.92, 0.72)
	mat_bulb.emission_enabled = true
	mat_bulb.emission = Color(1.0, 0.84, 0.52)
	mat_bulb.emission_energy_multiplier = 4.5

	# 1. 宽厚带真实透视的 3D 湿青石板街道（沿 X 轴 0..80 米，Z = -5.5..+5.0 米）
	_add_box(root3d, Vector3(90.0, 0.8, 11.5), Vector3(40.0, -0.4, -0.4), mat_road)
	# 道路两侧立体路缘石与下方石桥胸墙（彻底消灭底部死黑空洞）
	_add_box(root3d, Vector3(90.0, 0.35, 0.65), Vector3(40.0, 0.12, -4.8), mat_stone)
	_add_box(root3d, Vector3(90.0, 0.42, 0.75), Vector3(40.0, 0.15, 4.4), mat_stone)
	# 路面下方的厚重石桥墩群
	for i in range(0, 12):
		var bx := 6.0 + float(i) * 6.8
		_add_box(root3d, Vector3(1.6, 8.0, 11.0), Vector3(bx, -4.4, -0.4), mat_stone)

	# 2. 前景低矮雕花石柱 + 锻铁护栏（Z = +4.55，离镜头较近，DOF 自然微虚化压框！）
	for i in range(0, 16):
		var px := 6.0 + float(i) * 4.6
		_add_box(root3d, Vector3(0.48, 1.35, 0.48), Vector3(px, 0.68, 4.55), mat_stone)
		_add_box(root3d, Vector3(0.62, 0.18, 0.62), Vector3(px, 1.42, 4.55), mat_stone)
		_add_box(root3d, Vector3(4.2, 0.10, 0.10), Vector3(px + 2.3, 1.05, 4.55), mat_iron, false)
		for b in range(1, 7):
			_add_cyl(root3d, 0.03, 0.035, 0.95, Vector3(px + float(b) * 0.62, 0.56, 4.55), mat_iron, 6)

	# 3. 街对面错落有致的 3D 哥特建筑群（Z = -6.8..-11.0：留出豁口透出后方深渊城市与母钟楼！）
	var houses := [
		{"x": 16.0, "w": 9.5, "h": 11.5, "d": 5.5, "z": -7.8, "roof": true},
		{"x": 27.0, "w": 8.2, "h": 9.2, "d": 5.2, "z": -8.2, "roof": true},
		# x=33..41 敞开大豁口：只留过街低拱桥 + 背后通透远景！
		{"x": 45.5, "w": 9.2, "h": 12.2, "d": 5.6, "z": -7.6, "roof": true},
		{"x": 57.0, "w": 8.6, "h": 9.8, "d": 5.0, "z": -8.4, "roof": true},
	]
	for h in houses:
		var hx: float = h["x"]
		var hw: float = h["w"]
		var hh: float = h["h"]
		var hd: float = h["d"]
		var hz: float = h["z"]
		_add_box(root3d, Vector3(hw, hh, hd), Vector3(hx, hh * 0.5, hz), mat_facade)
		# 凸出石雕腰线与二楼凸窗体块（制造真实 3D 凹凸阴影）
		_add_box(root3d, Vector3(hw + 0.5, 0.45, hd + 0.6), Vector3(hx, 4.4, hz), mat_stone)
		_add_box(root3d, Vector3(2.8, 3.2, 1.1), Vector3(hx, 6.4, hz + hd * 0.5 + 0.35), mat_facade)
		# 底层石拱廊柱列
		for ci in range(-1, 2):
			_add_box(root3d, Vector3(0.75, 4.2, 0.85), Vector3(hx + float(ci) * (hw * 0.36), 2.1, hz + hd * 0.5 + 0.35), mat_stone)
		# 陡峭哥特坡屋顶（旋转棱柱感）
		var roof := _add_box(root3d, Vector3(hw + 0.6, 3.2, hd * 0.82), Vector3(hx, hh + 1.1, hz), mat_roof)
		roof.scale = Vector3(1.0, 1.0, 0.85)
		_add_cyl(root3d, 0.35, 0.45, 2.8, Vector3(hx - hw * 0.28, hh + 2.6, hz + 0.4), mat_stone, 8)

	# 豁口处（x=36.5）一座通透的 3D 远景石拱高架桥，连接两侧老城并露出后方司辰母钟楼！
	_add_box(root3d, Vector3(16.0, 0.85, 2.4), Vector3(36.5, 4.2, -16.5), mat_stone)
	for bi in [-5.5, -1.8, 1.8, 5.5]:
		_add_box(root3d, Vector3(1.2, 6.2, 2.6), Vector3(36.5 + bi, 1.1, -16.5), mat_stone)

	# 4. 沿街真实 3D 暖白铸铁街灯（发散真实 3D 光锥，湿石板泛出真实高光！）
	for lx in [19.0, 27.5, 35.5, 43.5, 51.5]:
		var lz := -4.3
		_add_cyl(root3d, 0.10, 0.20, 4.6, Vector3(lx, 2.3, lz), mat_iron, 10)
		_add_box(root3d, Vector3(0.46, 0.64, 0.46), Vector3(lx, 4.75, lz), mat_bulb, false)
		var ol := OmniLight3D.new()
		ol.position = Vector3(lx, 4.65, lz + 0.65)
		ol.light_color = Color(1.0, 0.84, 0.54)
		ol.light_energy = 7.5
		ol.omni_range = 13.5
		ol.omni_attenuation = 1.35
		ol.shadow_enabled = true
		root3d.add_child(ol)
		_lamp_lights.append(ol)

	# 5. 远处多层 3D 哥特城剪影（Z = -26..-48，吃满体积雾与 DOF 远景虚化）
	var far_mat := StandardMaterial3D.new()
	far_mat.albedo_color = Color(0.18, 0.19, 0.21)
	far_mat.roughness = 0.92
	for i in range(0, 14):
		var fx := 10.0 + float(i) * 4.4
		var fh := 9.0 + fmod(float(i) * 5.7, 11.0)
		var fz := -25.0 - fmod(float(i) * 7.3, 18.0)
		_add_box(root3d, Vector3(3.4, fh, 3.6), Vector3(fx, fh * 0.5 - 2.0, fz), far_mat, false)
		_add_cyl(root3d, 0.06, 1.2, 5.5, Vector3(fx, fh + 0.7, fz), far_mat, 6)

	# 6. 远景天际线百米青铜【司辰母钟楼】巨塔 + 裸露青铜巨齿侧影（Z = -58，绝无正面大表盘）
	var tower_mat := StandardMaterial3D.new()
	tower_mat.albedo_color = Color(0.24, 0.24, 0.26)
	tower_mat.metallic = 0.35
	tower_mat.roughness = 0.65
	var tx := 44.0
	var tz := -58.0
	_add_box(root3d, Vector3(7.5, 34.0, 7.5), Vector3(tx, 14.0, tz), tower_mat, false)
	_add_cyl(root3d, 0.15, 3.8, 16.0, Vector3(tx, 38.0, tz), tower_mat, 8)
	# 侧面错落巨型青铜齿轮环
	for gi in [Vector3(-4.2, 22.0, 0.0), Vector3(4.5, 27.0, 0.0)]:
		var torus := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 2.6
		tm.outer_radius = 3.8
		torus.mesh = tm
		torus.rotation_degrees = Vector3(90.0, 0.0, 0.0)
		torus.position = Vector3(tx, 0.0, tz) + gi
		torus.material_override = tower_mat
		root3d.add_child(torus)


func _build_camera_and_hero_proxy(root3d: Node3D) -> void:
	_cam3d = Camera3D.new()
	_cam3d.fov = 38.0
	_cam3d.near = 0.2
	_cam3d.far = 160.0
	_cam3d.position = Vector3(36.0, 4.1, 14.8)
	_cam3d.rotation_degrees = Vector3(-8.5, 0.0, 0.0)
	_cam3d.current = true
	root3d.add_child(_cam3d)

	# 同步主角位置：在 3D 湿石板面上投出真实 3D 软影 + 微弱冷紫刀光反光（让 2D 主角真正融进 3D 街道！）
	_hero_light = OmniLight3D.new()
	_hero_light.light_color = Color(0.72, 0.56, 1.0)
	_hero_light.light_energy = 1.6
	_hero_light.omni_range = 4.8
	_hero_light.position = Vector3(36.0, 1.2, 0.6)
	root3d.add_child(_hero_light)

	_hero_shadow_mesh = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(1.5, 0.9)
	_hero_shadow_mesh.mesh = pm
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.01, 0.01, 0.02, 0.55)
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_hero_shadow_mesh.material_override = sm
	_hero_shadow_mesh.position = Vector3(36.0, 0.03, 0.0)
	root3d.add_child(_hero_shadow_mesh)


func _process(delta: float) -> void:
	_t += delta
	if camera == null:
		return
	var c := camera.get_screen_center_position()
	var z := camera.zoom.x if camera.zoom.x > 0.0 else 0.65
	_view_sprite.global_position = c
	_view_sprite.scale = Vector2.ONE / z

	# 3D 相机精准同步 2D 镜头横向走动，产生 100% 真实 3D 透视视差！
	var cx3 := c.x * WORLD_TO_3D
	var cy3 := 4.05 + (290.0 - c.y) * WORLD_TO_3D * 0.55
	_cam3d.position = Vector3(cx3, cy3, 14.8)

	if player != null:
		var px3 := player.global_position.x * WORLD_TO_3D
		var foot_off := float(player.get("foot_offset")) if "foot_offset" in player else 0.0
		var py3 := maxf(0.0, (FLOOR - (player.global_position.y + foot_off)) * WORLD_TO_3D)
		_hero_light.position = Vector3(px3, 1.1 + py3, 0.45)
		_hero_shadow_mesh.position = Vector3(px3, 0.03, 0.0)
		var sk := clampf(1.0 - py3 / 3.0, 0.25, 1.0)
		_hero_shadow_mesh.scale = Vector3(sk, 1.0, sk)

	# 街灯火焰微呼吸
	for i in _lamp_lights.size():
		_lamp_lights[i].light_energy = 7.2 + 0.55 * sin(_t * (4.1 + float(i) * 0.7) + float(i))

	_fg_contact_layer.queue_redraw()


func _draw_2d_contact() -> void:
	if player == null:
		return
	var px := player.global_position.x
	var foot_off := float(player.get("foot_offset")) if "foot_offset" in player else 0.0
	var h_above := maxf(0.0, FLOOR - (player.global_position.y + foot_off))
	var k := clampf(1.0 - h_above / 260.0, 0.15, 1.0)
	_fg_contact_layer.draw_set_transform(Vector2(px, FLOOR + 3.0), 0.0, Vector2(1.0, 0.24))
	_fg_contact_layer.draw_circle(Vector2.ZERO, 48.0 * k, Color(0.01, 0.01, 0.02, 0.50 * k))
	_fg_contact_layer.draw_set_transform(Vector2.ZERO)
