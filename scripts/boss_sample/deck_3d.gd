extends Node2D
## 钟前校时天廊 · Blender 5.2 高精哥特 3D 实体桥面（SubViewport 真透视渲染）
##
## 彻底告别代码 BoxMesh / CSG 积木：
##   直接由 GLTFDocument 运行时加载 Blender 5.2.2 LTS 精雕导出的哥特高架石桥模块 (.glb)：
##   - 错落倒角青黑古石板桥面 + 中央凹陷镜面湿积水洼（roughness=0.04, clearcoat=1.0）
##   - 前后双层三阶退台哥特尖拱（真楔形拱石 Voussoirs + 拱心石 Keystone + 扶壁凸柱 + 垂吊 3D 青铜断链）
##   - 维多利亚哥特三叶草镂空锻铁栏杆 + 八角雕花石望柱 + 崩裂战损碎石块
##   - 精雕哥特弧形悬臂六棱锻铁煤气风灯（湿石板与镜面水洼实时铺开暖金 vs 暗红 vs 纯紫三色高光）

const S := 0.01                  ## 2D 1 像素 = 3D 0.01 米
const FOV := 46.0
const DIR3D := "res://assets/image/boss_duanchao/crimson_3d/"
const BAY_W := 4.20              ## 必须与 Blender 脚本 BAY_W = 4.20 严格一致

const DECK_BACK_Z := -3.15
const RAIL_Z := -2.82

var floor_y: float = 580.0
var center_x: float = 0.0
var half_len: float = 2750.0
var rail_x0: float = -2650.0     ## 整条桥面均带哥特铁栏杆（彻底告别穿帮旧翼楼）
var rail_x1: float = 2650.0
var lamp_rel_x: Array[float] = [-660.0, 660.0, -1480.0, 1320.0]

var crimson_light: OmniLight3D
var blade_light: OmniLight3D
var clash_light: OmniLight3D
var moon_light: DirectionalLight3D
var under_fill_light: DirectionalLight3D
var lamp_lights: Array[OmniLight3D] = []
var lamp_world: Array[Vector2] = []

var _is_headless := false
var _vp: SubViewport
var _cam: Camera3D
var _spr: Sprite2D
var _root3d: Node3D

var _mat_slate: StandardMaterial3D
var _mat_puddle: StandardMaterial3D
var _mat_carved: StandardMaterial3D
var _mat_abyss: StandardMaterial3D
var _mat_iron: StandardMaterial3D
var _mat_bronze: StandardMaterial3D
var _mat_glow: StandardMaterial3D

var _bay_rail_tpl: Node3D
var _bay_norail_tpl: Node3D
var _lamp_tpl: Node3D
var _built := false


func y3(y2d: float) -> float:
	return -y2d * S


func _ready() -> void:
	_is_headless = DisplayServer.get_name() == "headless"
	if _is_headless:
		return

	_vp = SubViewport.new()
	_vp.name = "Deck3DViewport"
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.size = _main_size()
	add_child(_vp)

	_root3d = Node3D.new()
	_root3d.name = "DeckWorld"
	_vp.add_child(_root3d)

	_cam = Camera3D.new()
	_cam.fov = FOV
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	_cam.near = 0.05
	_cam.far = 160.0
	_cam.current = true
	_root3d.add_child(_cam)

	_spr = Sprite2D.new()
	_spr.name = "Deck3DComposite"
	_spr.texture = _vp.get_texture()
	_spr.centered = true
	_spr.light_mask = 0
	_spr.z_as_relative = false
	_spr.z_index = -12
	add_child(_spr)

	_setup_env_and_lights()
	_make_materials()
	_bay_rail_tpl = _load_glb_template("gothic_skybridge_bay.glb")
	_bay_norail_tpl = _load_glb_template("gothic_skybridge_bay_norail.glb")
	_lamp_tpl = _load_glb_template("gothic_lamp_post.glb")
	RenderingServer.frame_pre_draw.connect(_sync)


func _exit_tree() -> void:
	if RenderingServer.frame_pre_draw.is_connected(_sync):
		RenderingServer.frame_pre_draw.disconnect(_sync)
	for tpl in [_bay_rail_tpl, _bay_norail_tpl, _lamp_tpl]:
		if tpl != null and is_instance_valid(tpl):
			tpl.free()


func _main_size() -> Vector2i:
	var s := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1280, 720)
	return Vector2i(maxi(int(s.x), 64), maxi(int(s.y), 64))


func configure(c_x: float, f_y: float, h_len: float) -> void:
	center_x = c_x
	floor_y = f_y
	half_len = h_len
	lamp_world.clear()
	for rx in lamp_rel_x:
		var side_off := 54.0 if rx < 0.0 else -54.0
		lamp_world.append(Vector2(center_x + rx + side_off, floor_y - 234.0))

	if _is_headless or _root3d == null:
		return

	if _built:
		for c in _root3d.get_children():
			if c != _cam and not (c is WorldEnvironment) and not (c is DirectionalLight3D) and c != crimson_light and c != blade_light and c != clash_light:
				c.queue_free()
		lamp_lights.clear()
	_build_geometry()
	_built = true


# ---------------------------------------------------------------- 灯光与 PBR 材质

func _setup_env_and_lights() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.14, 0.19, 0.28)
	env.ambient_light_energy = 0.72
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.fog_enabled = true
	env.fog_light_color = Color(0.045, 0.062, 0.095)
	env.fog_light_energy = 1.0
	env.fog_density = 0.022
	env.set("fog_mode", 1)
	env.set("fog_depth_begin", 12.8)
	env.set("fog_depth_end", 24.0)
	env.set("fog_depth_curve", 1.35)
	var we := WorldEnvironment.new()
	we.environment = env
	_root3d.add_child(we)

	moon_light = DirectionalLight3D.new()
	moon_light.light_color = Color(0.76, 0.80, 0.88)
	moon_light.light_energy = 1.05
	moon_light.rotation_degrees = Vector3(-44.0, -32.0, 0.0)
	moon_light.shadow_enabled = true
	moon_light.directional_shadow_max_distance = 44.0
	_root3d.add_child(moon_light)

	under_fill_light = DirectionalLight3D.new()
	under_fill_light.light_color = Color(0.46, 0.52, 0.62)
	under_fill_light.light_energy = 0.38
	under_fill_light.light_specular = 0.45
	under_fill_light.rotation_degrees = Vector3(24.0, -18.0, 0.0)
	under_fill_light.shadow_enabled = false
	_root3d.add_child(under_fill_light)

	crimson_light = OmniLight3D.new()
	crimson_light.name = "MotherClockCrimson"
	crimson_light.light_color = Color(0.86, 0.12, 0.10)
	crimson_light.light_energy = 1.35
	crimson_light.light_specular = 1.65
	crimson_light.omni_range = 18.0
	crimson_light.omni_attenuation = 1.35
	crimson_light.shadow_enabled = true
	_root3d.add_child(crimson_light)

	blade_light = OmniLight3D.new()
	blade_light.name = "BladeViolet"
	blade_light.light_color = Color(0.72, 0.32, 1.0)
	blade_light.light_energy = 0.0
	blade_light.light_specular = 1.65
	blade_light.omni_range = 5.0
	blade_light.omni_attenuation = 1.30
	_root3d.add_child(blade_light)

	clash_light = OmniLight3D.new()
	clash_light.name = "ClashBurst3D"
	clash_light.light_color = Color(0.98, 0.34, 0.26)
	clash_light.light_energy = 0.0
	clash_light.light_specular = 1.8
	clash_light.omni_range = 7.5
	clash_light.omni_attenuation = 1.15
	_root3d.add_child(clash_light)


func _tex(file_name: String) -> Texture2D:
	var p := DIR3D + file_name
	var gpath := ProjectSettings.globalize_path(p)
	if FileAccess.file_exists(gpath):
		var img := Image.load_from_file(gpath)
		if img != null and not img.is_empty():
			img.generate_mipmaps()
			return ImageTexture.create_from_image(img)
	if ResourceLoader.exists(p):
		return load(p) as Texture2D
	return null


func _make_materials() -> void:
	_mat_slate = StandardMaterial3D.new()
	_mat_slate.albedo_texture = _tex("gothic_slate_albedo.png")
	_mat_slate.albedo_color = Color(1.42, 1.54, 1.74)
	_mat_slate.normal_enabled = true
	_mat_slate.normal_texture = _tex("gothic_slate_n.png")
	_mat_slate.normal_scale = 1.15
	_mat_slate.roughness_texture = _tex("gothic_slate_rough.png")
	_mat_slate.roughness = 0.36
	_mat_slate.metallic = 0.14
	_mat_slate.metallic_specular = 0.90
	_mat_slate.clearcoat_enabled = true
	_mat_slate.clearcoat = 0.65
	_mat_slate.clearcoat_roughness = 0.18
	_mat_slate.uv1_triplanar = true
	_mat_slate.uv1_world_triplanar = true
	_mat_slate.uv1_scale = Vector3(0.14, 0.14, 0.14)

	_mat_puddle = StandardMaterial3D.new()
	_mat_puddle.albedo_color = Color(0.035, 0.048, 0.072)
	_mat_puddle.metallic = 0.28
	_mat_puddle.metallic_specular = 1.0
	_mat_puddle.roughness = 0.045
	_mat_puddle.clearcoat_enabled = true
	_mat_puddle.clearcoat = 1.0
	_mat_puddle.clearcoat_roughness = 0.03
	_mat_puddle.normal_enabled = true
	_mat_puddle.normal_texture = _tex("gothic_slate_n.png")
	_mat_puddle.normal_scale = 0.12
	_mat_puddle.uv1_triplanar = true
	_mat_puddle.uv1_world_triplanar = true
	_mat_puddle.uv1_scale = Vector3(0.22, 0.22, 0.22)

	_mat_carved = _mat_slate.duplicate()
	_mat_carved.albedo_color = Color(1.68, 1.76, 1.94)
	_mat_carved.roughness = 0.72
	_mat_carved.clearcoat = 0.18
	_mat_carved.uv1_scale = Vector3(0.18, 0.18, 0.18)

	_mat_abyss = StandardMaterial3D.new()
	_mat_abyss.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_abyss.albedo_color = Color(0.020, 0.026, 0.042)

	_mat_iron = StandardMaterial3D.new()
	_mat_iron.albedo_color = Color(0.072, 0.080, 0.102)
	_mat_iron.metallic = 0.90
	_mat_iron.roughness = 0.28
	_mat_iron.normal_enabled = true
	_mat_iron.normal_texture = _tex("ancient_bronze_n.png")
	_mat_iron.normal_scale = 0.50
	_mat_iron.uv1_triplanar = true
	_mat_iron.uv1_scale = Vector3(0.55, 0.55, 0.55)

	_mat_bronze = StandardMaterial3D.new()
	_mat_bronze.albedo_texture = _tex("ancient_bronze_albedo.png")
	_mat_bronze.albedo_color = Color(1.65, 1.48, 1.32)
	_mat_bronze.normal_enabled = true
	_mat_bronze.normal_texture = _tex("ancient_bronze_n.png")
	_mat_bronze.normal_scale = 0.92
	_mat_bronze.roughness_texture = _tex("ancient_bronze_rough.png")
	_mat_bronze.metallic = 0.90
	_mat_bronze.roughness = 0.34
	_mat_bronze.uv1_triplanar = true
	_mat_bronze.uv1_scale = Vector3(0.58, 0.58, 0.58)

	_mat_glow = StandardMaterial3D.new()
	_mat_glow.albedo_color = Color(0.32, 0.25, 0.15)
	_mat_glow.emission_enabled = true
	_mat_glow.emission = Color(1.0, 0.85, 0.56)
	_mat_glow.emission_energy_multiplier = 5.4


func _load_glb_template(file_name: String) -> Node3D:
	var gpath := ProjectSettings.globalize_path(DIR3D + file_name)
	if not FileAccess.file_exists(gpath):
		return null
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(gpath, state)
	if err != OK:
		push_warning("Deck3D: failed to load GLB %s (err=%d)" % [file_name, err])
		return null
	var root := doc.generate_scene(state) as Node3D
	if root != null:
		_apply_pbr_recursive(root)
	return root


func _apply_pbr_recursive(n: Node) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var nm := mi.name
		if nm.contains("Puddle"):
			mi.material_override = _mat_puddle
		elif nm.contains("Slate"):
			mi.material_override = _mat_slate
		elif nm.contains("Carved") or nm.contains("LampStone"):
			mi.material_override = _mat_carved
		elif nm.contains("Iron"):
			mi.material_override = _mat_iron
		elif nm.contains("Bronze"):
			mi.material_override = _mat_bronze
		elif nm.contains("Glow"):
			mi.material_override = _mat_glow
	for c in n.get_children():
		_apply_pbr_recursive(c)


# ---------------------------------------------------------------- 桥跨装配

func _build_geometry() -> void:
	var cx := center_x * S
	var y0 := y3(floor_y)
	var L := half_len * 2.0 * S + 4.0

	# 1) 沿整条 4800u 天廊无缝拼接 Blender 5.2 高精哥特桥跨
	var n_bays := int(ceil(L / BAY_W)) + 1
	if n_bays % 2 == 0:
		n_bays += 1
	var half_bays := n_bays / 2
	var r0 := (center_x + rail_x0) * S
	var r1 := (center_x + rail_x1) * S

	for i in range(-half_bays, half_bays + 1):
		var bx := cx + float(i) * BAY_W
		var use_rail := (bx >= r0 - 0.6) and (bx <= r1 + 0.6)
		var tpl := _bay_rail_tpl if use_rail else _bay_norail_tpl
		if tpl != null:
			var bay := tpl.duplicate() as Node3D
			bay.position = Vector3(bx, y0, 0.0)
			_root3d.add_child(bay)

	# 2) 桥洞后方深渊背板（顶边严格藏于 y0 - 0.48 石板厚度内部，绝不露头遮挡桥面后沿之上的 2D 母钟与石拱塔基！）
	var abyss_mi := MeshInstance3D.new()
	var abyss_bm := BoxMesh.new()
	abyss_bm.size = Vector3(L + 16.0, 9.0, 0.25)
	abyss_mi.mesh = abyss_bm
	abyss_mi.material_override = _mat_abyss
	abyss_mi.position = Vector3(cx, y0 - 0.48 - 4.5, DECK_BACK_Z - 0.22)
	_root3d.add_child(abyss_mi)

	# 3) 精雕 Blender 哥特弧形悬臂六棱煤气路灯 + 宽阔暖金镜面铺色点光
	for rx in lamp_rel_x:
		var lx := (center_x + rx) * S
		var arm_dir := 1.0 if rx < 0.0 else -1.0
		if _lamp_tpl != null:
			var lp := _lamp_tpl.duplicate() as Node3D
			lp.position = Vector3(lx, y0, RAIL_Z + 0.02)
			if arm_dir < 0.0:
				lp.rotation_degrees = Vector3(0.0, 180.0, 0.0)
			_root3d.add_child(lp)
		var ol := OmniLight3D.new()
		ol.light_color = Color(1.0, 0.80, 0.52)
		ol.light_energy = 1.10
		ol.light_specular = 1.45
		ol.omni_range = 5.4
		ol.omni_attenuation = 1.65
		ol.shadow_enabled = true
		ol.position = Vector3(lx + arm_dir * 0.54, y0 + 2.26, RAIL_Z + 0.42)
		_root3d.add_child(ol)
		lamp_lights.append(ol)


# ---------------------------------------------------------------- 每帧实时灯光与 3D 相机对齐

func set_crimson(world_pos: Vector2, energy: float, col: Color) -> void:
	if crimson_light == null:
		return
	crimson_light.position = Vector3(world_pos.x * S, y3(world_pos.y), -8.2)
	crimson_light.light_energy = energy * 1.15
	crimson_light.light_color = col


func set_blade(world_pos: Vector2, energy: float) -> void:
	if blade_light == null:
		return
	blade_light.position = Vector3(world_pos.x * S, y3(world_pos.y), 0.65)
	blade_light.light_energy = energy * 1.2


func set_clash(world_pos: Vector2, col: Color, energy: float) -> void:
	if clash_light == null:
		return
	clash_light.position = Vector3(world_pos.x * S, y3(world_pos.y), 0.75)
	clash_light.light_color = col
	clash_light.light_energy = energy * 1.2


func set_lamp_flicker(k: Array) -> void:
	if k.is_empty():
		return
	for i in lamp_lights.size():
		lamp_lights[i].light_energy = 3.25 * float(k[i % k.size()])


func _sync() -> void:
	if _is_headless or not is_inside_tree() or _cam == null or _vp == null:
		return
	var vp_main := get_viewport()
	var want := _main_size()
	if _vp.size != want:
		_vp.size = want
	var vsize := Vector2(want)
	var ct := vp_main.get_canvas_transform()
	var zoom := ct.x.length()
	if zoom <= 0.0001:
		return
	var center: Vector2 = ct.affine_inverse() * (vsize * 0.5)
	_spr.global_position = center
	_spr.scale = Vector2.ONE / zoom
	var h_world := vsize.y / zoom
	var d := (h_world * 0.5) / tan(deg_to_rad(FOV * 0.5))
	_cam.position = Vector3(center.x * S, y3(center.y), d * S)


func _process(_delta: float) -> void:
	_sync()
