extends Node2D
## 背景线 11-19「U2 · HD-2D 实景街」（环境变量 RAIN_3D=U2 才开；默认游戏不变）。
## 用户：“我想法是地面做成3d，近景有距离的做真实的贴图距离 / 就是能走的地方，都是3d”；看过三张目标图后：“还是u2看看”。
## 上一版（street_3d.gd）只加地板、楼还是一整张原画卡片，被否（“你这完全不行”）。这一版近处的街**全部真 3D 建模**，不用原画卡片：
##   · 街面：大石板 + 碎石混铺，湿润低粗糙度 + 屏幕空间反射（灯和亮窗在地上拖出一道薄倒影，红线：不做水洼）。
##   · 步廊：按地形碰撞建台面（前沿在 z = 0 和碰撞重合），台口压檐、一排 3D 宝瓶栏杆；下面一排圆柱 + 拱券，拱廊里是带门、店面、亮窗的后墙。
##   · 阳台 / 石台：从楼面挑出来一直伸到 z = 0。
##   · 楼：一栋栋按宽窄、高低、屋顶随机生成的 3D 房子（石墙、亮窗、凸窗、坡屋顶、烟囱），第二排更远更暗进雾。
##   · 街灯杆、石桩都是 3D 实体；灯 = 实时点光源 + 体积雾光晕。
##   · 镜头：比 2D 镜头抬高 CAM_H、但不俯仰，用离轴（镜头下移）投影——竖线保持竖直，看得见街面和台面顶，
##     z = 0 平面与 2D 世界仍是线性 1:1，角色 / 碰撞对得上。最前景一段栏杆、远处楼和雾靠景深虚化。
## 单位：所有几何按世界像素写，root3 整体缩成米（S）；灯不进缩放节点，位置和范围手动乘 S。

const StoneShader := preload("res://scripts/night/redesign/street3d_stone.gdshader")
const PaintShader := preload("res://scripts/night/redesign/street3d_paint.gdshader")
const TEX := "res://assets/image/rain_street/street3d/"
const S := 0.01
const CAM_D := 1200.0
const CAM_H := 450.0          ## 相机比 2D 镜头中心高多少（看得见街面和台面顶）
const DECK_BACK := -300.0     ## 步廊台面后沿（拱廊后墙）
const DECK_T := 34.0
const COL_Z := -26.0          ## 拱廊柱子（台面前沿下，角色身后）
const COL_R := 17.0
const BAY := 250.0            ## 拱廊开间
const HOUSE_Z := -330.0       ## 第一排楼面
const HOUSE2_Z := -1300.0      ## 第二排楼面
const FLOOR_BACK := -1700.0
const FLOOR_FRONT := 1200.0
const FG_Z := 400.0           ## 最前景栏杆
const LAMP_Z := -90.0

var vp: SubViewport
var cam: Camera3D
var out_sprite: Sprite2D
var root3: Node3D
var env: Environment
var floor_y := 580.0
var x_lo := INF
var x_hi := -INF
var built := false
var lamps: Array = []         ## {light, e, sp}
var shadow_mi: MeshInstance3D
var t := 0.0
var _poll := 0.0
var rng := RandomNumberGenerator.new()
var m_stone: ShaderMaterial
var m_floor: ShaderMaterial
var m_deck: ShaderMaterial
var m_dark: ShaderMaterial
var m_roof: ShaderMaterial
var m_emit: StandardMaterial3D
var m_iron: StandardMaterial3D
var tex_cache := {}
var parts := {}               ## 构件图切件：name → [Texture2D]
var opaque := false
var rvp: SubViewport          ## 镜像相机（地面倒影）
var rcam: Camera3D
var sky_rect: TextureRect
var tower_sp: Sprite2D
var tower_glow: Sprite2D
const YING := "res://assets/image/rain_street/ying2/"


static func _envf(k: String, d: float) -> float:
	var v := OS.get_environment(k)
	return float(v) if v != "" else d


func _tex(name: String) -> Texture2D:
	if tex_cache.has(name):
		return tex_cache[name]
	var p := TEX + name + ".png"
	var tx: Texture2D = null
	if ResourceLoader.exists(p):
		tx = load(p) as Texture2D
	elif FileAccess.file_exists(p):
		var im := Image.new()
		if im.load_png_from_buffer(FileAccess.get_file_as_bytes(p)) == OK:
			im.generate_mipmaps()
			tx = ImageTexture.create_from_image(im)
	tex_cache[name] = tx
	return tx


func _parts(prefix: String) -> Array:
	if parts.has(prefix):
		return parts[prefix]
	var out: Array = []
	for i in 8:
		var tx := _tex("%s_%d" % [prefix, i])
		if tx != null:
			tx.set_meta("emit", _tex("%s_%d_emit" % [prefix, i]))
		if tx == null:
			break
		out.append(tx)
	parts[prefix] = out
	return out


# ---------------------------------------------------------------- 搭台子

func setup(z: int, floor_world_y: float) -> void:
	floor_y = floor_world_y
	rng.seed = 1119
	vp = SubViewport.new()
	vp.size = Vector2i(1920, 1080)
	opaque = OS.get_environment("U2_OPAQUE") != ""
	vp.transparent_bg = not opaque    # 透明背景下引擎会关掉 SSR 和景深；不透明时天空、母钟楼搬进视口自己画
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.use_hdr_2d = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	root3 = Node3D.new()
	root3.scale = Vector3.ONE * S
	vp.add_child(root3)

	env = Environment.new()
	env.background_mode = Environment.BG_CANVAS if opaque else Environment.BG_CLEAR_COLOR
	env.background_canvas_max_layer = 0
	env.background_color = Color(0.13, 0.14, 0.16)
	if opaque:
		_build_sky()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.64, 0.7)
	env.ambient_light_energy = _envf("U2_AMB", 0.14)    # 环境光压低：明暗靠一盏盏灯分出来
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = _envf("U2_EXPO", 1.0)
	env.ssr_enabled = OS.get_environment("U2_NOSSR") == ""
	env.ssr_max_steps = 64
	env.ssr_fade_in = 0.15
	env.ssr_fade_out = 2.0
	env.ssr_depth_tolerance = 0.2
	env.glow_enabled = true
	env.glow_intensity = _envf("U2_GLOW", 0.6)
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.volumetric_fog_enabled = OS.get_environment("U2_NOVOL") == ""
	env.volumetric_fog_density = _envf("U2_FOG", 0.06)
	env.volumetric_fog_albedo = Color(0.75, 0.77, 0.8)
	env.volumetric_fog_emission = Color(0.035, 0.04, 0.05)
	env.volumetric_fog_emission_energy = 1.0
	env.volumetric_fog_length = 24.0
	env.volumetric_fog_anisotropy = 0.5
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.22, 0.24, 0.28)
	env.fog_depth_begin = (CAM_D + 500.0) * S
	env.fog_depth_end = (CAM_D + 2400.0) * S
	env.fog_density = 0.9
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)

	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_FRUSTUM
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.near = 60.0 * S
	cam.far = (CAM_D + 3000.0) * S
	var ca := CameraAttributesPractical.new()
	ca.dof_blur_far_enabled = OS.get_environment("U2_NODOF") == ""
	ca.dof_blur_far_distance = (CAM_D + 650.0) * S
	ca.dof_blur_far_transition = 9.0
	ca.dof_blur_near_enabled = OS.get_environment("U2_NODOF") == ""
	ca.dof_blur_near_distance = (CAM_D - 520.0) * S
	ca.dof_blur_near_transition = 2.0
	ca.dof_blur_amount = 0.09
	cam.attributes = ca
	vp.add_child(cam)

	var moon := DirectionalLight3D.new()    # 左上方冷月光：柱子、栏杆在湿石板上投影
	moon.light_color = Color(0.72, 0.78, 0.92)
	moon.light_energy = _envf("U2_MOON", 0.4)
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = (CAM_D + 1600.0) * S
	moon.rotation = Vector3(deg_to_rad(-48.0), deg_to_rad(-28.0), 0.0)
	moon.light_volumetric_fog_energy = 0.4
	vp.add_child(moon)

	_materials()
	if OS.get_environment("U2_NOREFL") == "":    # 地面倒影：同一个 3D 世界，从街面下方镜像再拍一遍（不拍街面自己）
		rvp = SubViewport.new()
		rvp.size = Vector2i(960, 540)
		rvp.world_3d = vp.find_world_3d()
		rvp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(rvp)
		rcam = Camera3D.new()
		rcam.projection = Camera3D.PROJECTION_FRUSTUM
		rcam.keep_aspect = Camera3D.KEEP_HEIGHT
		rcam.near = cam.near
		rcam.far = cam.far
		rcam.cull_mask = 0xFFFFF & ~2
		rvp.add_child(rcam)
		m_floor.set_shader_parameter("refl_tex", rvp.get_texture())
		m_floor.set_shader_parameter("refl", _envf("U2_REFL", 0.7))

	shadow_mi = MeshInstance3D.new()    # 脚下接触阴影
	var sq := PlaneMesh.new()
	sq.size = Vector2(150.0, 70.0)
	shadow_mi.mesh = sq
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.albedo_texture = _radial_tex()
	sm.albedo_color = Color(0, 0, 0, 0.7)
	shadow_mi.material_override = sm
	shadow_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root3.add_child(shadow_mi)

	out_sprite = Sprite2D.new()
	out_sprite.texture = vp.get_texture()
	out_sprite.z_as_relative = false
	out_sprite.z_index = z
	add_child(out_sprite)


## 不透明模式的天：视口自己的 2D 底层（BG_CANVAS）画夜空 + 母钟楼 + 塔后天顶白光；楼和雾都叠在它上面
func _build_sky() -> void:
	var cl := CanvasLayer.new()
	cl.layer = -1
	vp.add_child(cl)
	var sky := _load_abs(YING + "sky.png")
	if sky != null:
		sky_rect = TextureRect.new()
		sky_rect.texture = sky
		sky_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sky_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		sky_rect.size = Vector2(vp.size)
		sky_rect.modulate = Color(0.88, 0.92, 1.0)
		cl.add_child(sky_rect)
	tower_glow = Sprite2D.new()
	tower_glow.texture = _radial_tex()
	tower_glow.modulate = Color(0.92, 0.94, 0.97, 0.35)
	tower_glow.scale = Vector2(22.0, 16.0)
	cl.add_child(tower_glow)
	var tw := _load_abs(YING + "tower.png")
	if tw != null:
		tower_sp = Sprite2D.new()
		tower_sp.texture = tw
		tower_sp.centered = true
		tower_sp.modulate = Color(0.62, 0.64, 0.68)
		tower_sp.scale = Vector2.ONE * (float(vp.size.y) * 1.25 / float(tw.get_height()))
		cl.add_child(tower_sp)


func _load_abs(p: String) -> Texture2D:
	if ResourceLoader.exists(p):
		return load(p) as Texture2D
	if FileAccess.file_exists(p):
		var im := Image.new()
		if im.load_png_from_buffer(FileAccess.get_file_as_bytes(p)) == OK:
			return ImageTexture.create_from_image(im)
	return null


func _stone_mat(top: String, face: String, top_s: float, face_s: float, rough_top: float, tint: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = StoneShader
	var ft := _tex(face)
	m.set_shader_parameter("top_tex", _tex(top) if _tex(top) != null else ft)
	m.set_shader_parameter("face_tex", ft)
	m.set_shader_parameter("side_tex", ft)
	m.set_shader_parameter("top_scale", Vector2(top_s, top_s) * S)
	m.set_shader_parameter("face_scale", Vector2(face_s, face_s) * S)
	m.set_shader_parameter("rough_top", rough_top)
	m.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	return m


func _materials() -> void:
	m_stone = _stone_mat("deck_top", "wall_stone", 240.0, 230.0, 0.55, Color(0.92, 0.9, 0.88))
	m_floor = _stone_mat("u2_floor", "wall_stone", 420.0, 230.0, _envf("U2_ROUGH", 0.14), Color(0.66, 0.69, 0.74))    # 石面偏冷灰：暖的只该是灯照到的那一圈
	m_floor.set_shader_parameter("macro", 1.0)
	m_deck = _stone_mat("deck_top", "wall_stone", 220.0, 200.0, 0.4, Color(0.95, 0.93, 0.9))
	m_dark = _stone_mat("deck_top", "wall_stone", 240.0, 260.0, 0.7, Color(0.55, 0.56, 0.6))
	m_roof = _stone_mat("u2_roof", "u2_roof", 200.0, 200.0, 0.35, Color(0.7, 0.74, 0.8))
	m_emit = StandardMaterial3D.new()
	m_emit.albedo_color = Color(1.0, 0.86, 0.6)
	m_emit.emission_enabled = true
	m_emit.emission = Color(1.0, 0.82, 0.55)
	m_emit.emission_energy_multiplier = _envf("U2_EMIT", 2.0)
	m_iron = StandardMaterial3D.new()
	m_iron.albedo_color = Color(0.1, 0.1, 0.11)
	m_iron.metallic = 0.6
	m_iron.roughness = 0.45


static func _radial_tex() -> Texture2D:
	var g := GradientTexture2D.new()
	g.width = 128
	g.height = 128
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5)
	g.fill_to = Vector2(1.0, 0.5)
	var gr := Gradient.new()
	gr.set_color(0, Color(1, 1, 1, 1))
	gr.set_color(1, Color(1, 1, 1, 0))
	gr.add_point(0.45, Color(1, 1, 1, 0.55))
	g.gradient = gr
	return g


# ---------------------------------------------------------------- 基本件

func _box(a: Vector3, b: Vector3, mat: Material, parent: Node3D = null) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = (b - a).abs()
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.material_override = mat
	mi.position = (a + b) * 0.5
	(parent if parent != null else root3).add_child(mi)
	return mi


## 竖直圆柱：底中心 (x, y_bottom 世界 y, z)，高 h
func _cyl(x: float, y_bottom: float, z: float, r_bot: float, r_top: float, h: float, mat: Material, segs := 16) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.bottom_radius = r_bot
	cm.top_radius = r_top
	cm.height = h
	cm.radial_segments = segs
	cm.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	mi.material_override = mat
	mi.position = Vector3(x, -(y_bottom - h * 0.5), z)
	root3.add_child(mi)
	return mi


func _sphere(x: float, y: float, z: float, r: float, mat: Material) -> MeshInstance3D:
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 12
	sm.rings = 6
	var mi := MeshInstance3D.new()
	mi.mesh = sm
	mi.material_override = mat
	mi.position = Vector3(x, -y, z)
	root3.add_child(mi)
	return mi


## 一块拱券板：x0..x1 宽、y_top..y_spring（拱脚）高，厚 d，前面在 z；半圆拱从板底挖掉
func _arch_panel(x0: float, x1: float, y_top: float, y_spring: float, z: float, d: float, mat: Material) -> void:
	var w := x1 - x0
	var r := w * 0.5
	var csg := CSGCombiner3D.new()
	root3.add_child(csg)
	var bx := CSGBox3D.new()
	var h := (y_spring - y_top)
	bx.size = Vector3(w, h, d)
	bx.position = Vector3((x0 + x1) * 0.5, -(y_top + h * 0.5), z - d * 0.5)
	bx.material = mat
	csg.add_child(bx)
	var cy := CSGCylinder3D.new()
	cy.radius = r
	cy.height = d + 4.0
	cy.sides = 28
	cy.operation = CSGShape3D.OPERATION_SUBTRACTION
	cy.rotation = Vector3(deg_to_rad(90.0), 0.0, 0.0)
	cy.position = Vector3((x0 + x1) * 0.5, -y_spring, z - d * 0.5)
	cy.material = mat
	csg.add_child(cy)


## 构件图（窗 / 门 / 店面）贴在墙面前一点：底边在 y_bottom，高 h
func _decal(tex: Texture2D, x: float, y_bottom: float, z: float, h: float, lit: float) -> MeshInstance3D:
	var w := h * float(tex.get_width()) / float(tex.get_height())
	var qm := QuadMesh.new()
	qm.size = Vector2(w, h)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.albedo_texture = tex
	m.roughness = 0.6
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if lit > 0.0:    # 亮窗：窗里的暖光自己发亮（只亮画里本来就亮的部分）
		m.emission_enabled = true
		m.emission_texture = tex.get_meta("emit") if tex.has_meta("emit") and tex.get_meta("emit") != null else tex

		m.emission = Color(1, 1, 1)
		m.emission_energy_multiplier = lit * _envf("U2_WINE", 0.0)    # 窗画里本身就画着灯光；再加自发光会冲成白块
	var mi := MeshInstance3D.new()
	mi.mesh = qm
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(x, -(y_bottom - h * 0.5), z + 1.5)
	root3.add_child(mi)
	return mi


## 手绘构件卡片（11-19 用户选“手绘分层”）：画里自带的光影当底色（自发光），真实灯光再往上加一层
func _paint_mat(tex: Texture2D, tint: Color, rep := 1.0, flip := false) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = PaintShader
	m.set_shader_parameter("tex", tex)
	m.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	m.set_shader_parameter("lit", _envf("U2_PLIT", 0.55))
	m.set_shader_parameter("bake", _envf("U2_PBAKE", 0.75))
	m.set_shader_parameter("rep", rep)
	m.set_shader_parameter("flip", flip)
	return m


## 一张手绘卡片：底边中点 (x, y_bottom)，高 h，在深度 z
func _paint(tex: Texture2D, x: float, y_bottom: float, z: float, h: float, tint: Color, flip := false) -> MeshInstance3D:
	var w := h * float(tex.get_width()) / float(tex.get_height())
	var qm := QuadMesh.new()
	qm.size = Vector2(w, h)
	var mi := MeshInstance3D.new()
	mi.mesh = qm
	mi.material_override = _paint_mat(tex, tint, 1.0, flip)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(x, -(y_bottom - h * 0.5), z)
	root3.add_child(mi)
	return mi


## 横向无缝长条（拱廊、栏杆）：x0..x1、y_top..y_bottom，贴图按自身宽高比平铺
func _paint_strip(tex: Texture2D, x0: float, x1: float, y_top: float, y_bottom: float, z: float, tint: Color, vr := Vector2(0, 1)) -> MeshInstance3D:
	var h := y_bottom - y_top
	var tw := h * float(tex.get_width()) / (float(tex.get_height()) * (vr.y - vr.x))
	var qm := QuadMesh.new()
	qm.size = Vector2(x1 - x0, h)
	var mi := MeshInstance3D.new()
	mi.mesh = qm
	mi.material_override = _paint_mat(tex, tint, (x1 - x0) / tw)
	(mi.material_override as ShaderMaterial).set_shader_parameter("vrange", vr)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	mi.position = Vector3((x0 + x1) * 0.5, -(y_top + h * 0.5), z)
	root3.add_child(mi)
	return mi


func _light(p: Vector2, z: float, col: Color, e: float, r: float, shadow: bool, vol := 1.0) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = Vector3(p.x, -p.y, z) * S
	l.light_color = col
	l.light_energy = e
	l.omni_range = r * S
	l.omni_attenuation = 0.8
	l.shadow_enabled = shadow
	l.light_volumetric_fog_energy = vol
	vp.add_child(l)
	lamps.append({"light": l, "e": e, "sp": rng.randf_range(3.0, 7.0)})
	return l


# ---------------------------------------------------------------- 按地形建街

func set_range(x0: float, x1: float) -> void:
	x_lo = minf(x_lo, x0)
	x_hi = maxf(x_hi, x1)


func _covered(ter: Node, x: float, pad := 0.0) -> float:
	## 这个 x 头顶的步廊高度（没有就 NAN）
	for p in ter.get("platforms"):
		if x >= float(p.x0) - pad and x <= float(p.x1) + pad and float(p.y) > 200.0 and float(p.y) < floor_y - 2.0:
			return float(p.y)
	return NAN


func build(ter: Node) -> void:
	if built or ter == null or x_hi < x_lo:
		return
	if (ter.get("platforms") as Array).is_empty():
		return
	built = true
	# 街面
	var fl := _box(Vector3(x_lo - 1600.0, -floor_y - 60.0, FLOOR_BACK), Vector3(x_hi + 1600.0, -floor_y, FLOOR_FRONT), m_floor)
	fl.layers = 2    # 镜像相机不拍街面自己
	var walk: Array = []
	var high: Array = []
	for p in ter.get("platforms"):
		var x0 := float(p.x0)
		var x1 := float(p.x1)
		if x1 < x_lo or x0 > x_hi or float(p.y) >= floor_y - 2.0:
			continue
		if float(p.y) > 200.0 and x1 - x0 > 400.0:
			walk.append([x0, x1, float(p.y)])
		else:
			high.append([x0, x1, float(p.y)])
	for w in walk:
		_walkway(w[0], w[1], w[2])
	for h in high:
		_terrace(h[0], h[1], h[2])
	for bl in ter.get("blocks"):
		var x0 := float(bl.x0)
		var x1 := float(bl.x1)
		if x1 < x_lo or x0 > x_hi or float(bl.y) >= floor_y - 2.0:
			continue
		var bot: float = float(bl.get("bottom", floor_y)) if bl.has("bottom") else floor_y
		_box(Vector3(x0, -bot, DECK_BACK), Vector3(x1, -float(bl.y), 16.0), m_stone)
	_houses(ter)
	_street_props(ter)
	_foreground()


## 步廊：台面 + 台口 + 栏杆 + 下面的拱廊（柱、拱、后墙、门窗店面、壁灯）
func _walkway(x0: float, x1: float, y: float) -> void:
	var af := _tex("u2p_arcade_front")
	var ab := _tex("u2p_arcade_back")
	if af != null and ab != null and OS.get_environment("U2_PROC") == "":
		_walkway_painted(x0, x1, y, af, ab)
		return
	_box(Vector3(x0, -(y + DECK_T), DECK_BACK), Vector3(x1, -y, 14.0), m_deck)
	_box(Vector3(x0 - 6.0, -(y + DECK_T + 22.0), 2.0), Vector3(x1 + 6.0, -(y + DECK_T), 22.0), m_stone)   # 台口压檐
	_balustrade(x0, x1, y, -6.0)
	# 拱廊后墙
	_box(Vector3(x0, -floor_y, DECK_BACK - 40.0), Vector3(x1, -(y + DECK_T), DECK_BACK), m_dark)
	var n := maxi(1, int(round((x1 - x0) / BAY)))
	var bay := (x1 - x0) / float(n)
	var spring := y + DECK_T + 22.0 + bay * 0.5 + 18.0    # 拱脚高度
	var doors := _parts("u2_doors")
	var wins := _parts("u2_windows")
	for i in n + 1:
		var cx := x0 + bay * i
		# 柱：柱础 + 柱身 + 柱头
		_box(Vector3(cx - COL_R - 8.0, -floor_y, COL_Z - COL_R - 8.0), Vector3(cx + COL_R + 8.0, -(floor_y - 26.0), COL_Z + COL_R + 8.0), m_stone)
		_cyl(cx, floor_y - 26.0, COL_Z, COL_R, COL_R * 0.92, (floor_y - 26.0) - spring, m_stone)
		_box(Vector3(cx - COL_R - 7.0, -spring, COL_Z - COL_R - 7.0), Vector3(cx + COL_R + 7.0, -(spring - 16.0), COL_Z + COL_R + 7.0), m_stone)
		if i < n:
			_arch_panel(cx + COL_R * 0.6, cx + bay - COL_R * 0.6, y + DECK_T + 22.0, spring, COL_Z + COL_R, 26.0, m_stone)
			# 后墙上的门 / 店面 / 窗
			var mid := cx + bay * 0.5
			var pick := rng.randi() % 4
			if pick < 2 and not doors.is_empty():
				var dt: Texture2D = doors[rng.randi() % doors.size()]
				_decal(dt, mid, floor_y, DECK_BACK, minf(170.0, floor_y - spring + 60.0), 0.9)
			elif not wins.is_empty():
				var wt: Texture2D = wins[rng.randi() % wins.size()]
				_decal(wt, mid, floor_y - 50.0, DECK_BACK, 120.0, 1.0)
			if i % 2 == 0:    # 壁灯：后墙上一盏真灯，照拱廊和街面
				_wall_lamp(Vector2(cx + bay * 0.5 + bay * 0.32, spring + 30.0), DECK_BACK + 18.0)


## 手绘拱廊：台面仍是真 3D（能走、受光、有反光）；台口 + 柱拱是一条手绘长条贴在台面前沿下，
## 拱洞里看进去是另一条更远的手绘后墙（门、店面、亮窗），中间夹着真灯
func _walkway_painted(x0: float, x1: float, y: float, af: Texture2D, ab: Texture2D) -> void:
	_box(Vector3(x0, -(y + 10.0), DECK_BACK), Vector3(x1, -y, 6.0), m_deck)    # 台面（薄，前沿 = 碰撞）
	_paint_strip(af, x0, x1, y + 4.0, floor_y + 6.0, 2.0, Color(1, 1, 1))
	_paint_strip(ab, x0 - 40.0, x1 + 40.0, y + 20.0, floor_y + 4.0, DECK_BACK, Color(0.82, 0.82, 0.84))
	_box(Vector3(x0, -floor_y, DECK_BACK - 10.0), Vector3(x1, -(y + 10.0), DECK_BACK - 4.0), m_dark)    # 后墙背板挡光
	var bal := _tex("u2_balustrade")
	if bal != null:
		_paint_strip(bal, x0, x1, y - 62.0, y + 2.0, -4.0, Color(1, 1, 1))
	else:
		_balustrade(x0, x1, y, -6.0)
	var x := x0 + 180.0
	while x < x1 - 60.0:    # 拱廊里的真灯：照台面底、后墙前的街面
		_light(Vector2(x, y + 90.0), DECK_BACK * 0.5, Color(1.0, 0.84, 0.64), _envf("U2_WLAMP", 2.8), 420.0, false, 3.0)
		x += 520.0


func _wall_lamp(p: Vector2, z: float) -> void:
	_box(Vector3(p.x - 9.0, -(p.y + 14.0), z), Vector3(p.x + 9.0, -(p.y - 14.0), z + 18.0), m_emit)
	_light(p, z + 30.0, Color(1.0, 0.86, 0.68), _envf("U2_WLAMP", 2.8), 440.0, true, 3.0)


## 3D 宝瓶栏杆：扶手、底座、每隔 22 一根栏杆柱、每隔几段一根方柱带球头
func _balustrade(x0: float, x1: float, y: float, z: float) -> void:
	var hgt := 64.0
	_box(Vector3(x0, -y - 0.0, z - 10.0), Vector3(x1, -(y - 8.0), z + 10.0), m_stone)            # 底座
	_box(Vector3(x0, -(y - hgt), z - 11.0), Vector3(x1, -(y - hgt - 9.0), z + 11.0), m_stone)     # 扶手
	var x := x0 + 14.0
	var k := 0
	while x < x1 - 8.0:
		if k % 9 == 0:
			_box(Vector3(x - 12.0, -(y - 8.0), z - 12.0), Vector3(x + 12.0, -(y - hgt - 12.0), z + 12.0), m_stone)
			_sphere(x, y - hgt - 22.0, z, 10.0, m_stone)
		else:
			_cyl(x, y - 8.0, z, 5.5, 3.5, hgt - 8.0, m_stone, 8)
		x += 22.0
		k += 1


## 阳台 / 高台：从楼面一路伸到 z = 0，底面看得见（相机在下方时）
func _terrace(x0: float, x1: float, y: float) -> void:
	var af := _tex("u2p_arcade_front")
	var bal := _tex("u2_balustrade")
	if af != null and bal != null and OS.get_environment("U2_PROC") == "":
		_box(Vector3(x0, -(y + 10.0), HOUSE_Z), Vector3(x1, -y, 6.0), m_deck)    # 台面（真 3D，能站）
		_paint_strip(af, x0 - 6.0, x1 + 6.0, y + 2.0, y + 2.0 + 74.0, 4.0, Color(1, 1, 1), Vector2(0.0, _envf("U2_BEAMV", 0.27)))    # 台口：柱拱长条最上面的梁 + 托石
		_paint_strip(bal, x0, x1, y - 62.0, y + 2.0, -4.0, Color(1, 1, 1))
		for sx in [x0 + 14.0, x1 - 14.0]:    # 两头托到楼面的石撑
			_box(Vector3(sx - 9.0, -(y + 76.0), HOUSE_Z), Vector3(sx + 9.0, -(y + 10.0), -2.0), m_stone)
		return
	_box(Vector3(x0, -(y + DECK_T), HOUSE_Z), Vector3(x1, -y, 14.0), m_deck)
	_box(Vector3(x0 - 6.0, -(y + DECK_T + 18.0), 2.0), Vector3(x1 + 6.0, -(y + DECK_T), 20.0), m_stone)
	_balustrade(x0, x1, y, -6.0)
	# 托石
	var x := x0 + 30.0
	while x < x1 - 20.0:
		_box(Vector3(x - 10.0, -(y + DECK_T + 60.0), -60.0), Vector3(x + 10.0, -(y + DECK_T), 8.0), m_stone)
		x += 110.0


## 一栋栋 3D 房子：第一排在步廊后面（或直接落街），第二排更远更暗
func _houses(ter: Node) -> void:
	var hs: Array = []
	for k in ["u2p_house_a", "u2p_house_b", "u2p_house_c"]:
		hs.append_array(_parts(k))
	if not hs.is_empty() and OS.get_environment("U2_PROC") == "":
		_houses_painted(ter, hs)
		return
	var wins := _parts("u2_windows")
	var x := x_lo - 900.0
	while x < x_hi + 900.0:
		var w := rng.randf_range(300.0, 520.0)
		var cov := _covered(ter, x + w * 0.5, 40.0)
		var base := cov if not is_nan(cov) else floor_y
		var top := rng.randf_range(-40.0, 90.0)     # 压低：屋顶上面要露出天空、远城和母钟楼
		_house(x, x + w, base, top, HOUSE_Z, m_stone, wins, 0.9, true)
		x += w + rng.randf_range(-10.0, 30.0)
	x = x_lo - 1600.0
	while x < x_hi + 1600.0:
		var w := rng.randf_range(380.0, 700.0)
		_house(x, x + w, floor_y, rng.randf_range(-140.0, 20.0), HOUSE2_Z, m_dark, wins, 0.7, false)
		x += w + rng.randf_range(40.0, 160.0)


func _house(x0: float, x1: float, base: float, top: float, z: float, mat: Material, wins: Array, lit: float, near: bool) -> void:
	var depth := 260.0
	_box(Vector3(x0, -base, z - depth), Vector3(x1, -top, z), mat)
	# 檐口
	_box(Vector3(x0 - 10.0, -(top + 14.0), z - depth), Vector3(x1 + 10.0, -top, z + 14.0), m_stone)
	# 屋顶：一半是山墙朝街（三角形立面正对镜头、哥特尖山墙），一半是坡顶顺街
	var gable := rng.randf() < 0.55
	var rh := rng.randf_range(150.0, 240.0) if gable else rng.randf_range(110.0, 170.0)
	var pm := PrismMesh.new()
	var ri := MeshInstance3D.new()
	ri.mesh = pm
	ri.material_override = m_roof
	if gable:
		pm.size = Vector3(x1 - x0 + 24.0, rh, depth + 30.0)
		ri.position = Vector3((x0 + x1) * 0.5, -(top - rh * 0.5), z - depth * 0.5 + 8.0)
		# 山墙正面一块石三角（比屋顶前沿缩进一点），中间一扇窗
		var gm := PrismMesh.new()
		gm.size = Vector3(x1 - x0 - 10.0, rh - 12.0, 20.0)
		var gi := MeshInstance3D.new()
		gi.mesh = gm
		gi.material_override = mat
		gi.position = Vector3((x0 + x1) * 0.5, -(top - (rh - 12.0) * 0.5), z + 4.0)
		root3.add_child(gi)
		if not wins.is_empty() and rh > 170.0:
			_decal(wins[rng.randi() % wins.size()], (x0 + x1) * 0.5, top - 14.0, z + 14.0, minf(rh * 0.55, 110.0), lit if rng.randf() < 0.6 else 0.0)
		_cyl((x0 + x1) * 0.5, top - rh + 6.0, z, 7.0, 0.0, 60.0, m_iron, 6)    # 山尖铁尖饰
	else:
		pm.size = Vector3(depth + 30.0, rh, x1 - x0 + 24.0)
		ri.rotation = Vector3(0.0, deg_to_rad(90.0), 0.0)
		ri.position = Vector3((x0 + x1) * 0.5, -(top - rh * 0.5), z - depth * 0.5 + 8.0)
	root3.add_child(ri)
	# 墙角壁柱
	for cx in [x0 + 10.0, x1 - 10.0]:
		_box(Vector3(cx - 12.0, -base, z - 2.0), Vector3(cx + 12.0, -top, z + 16.0), mat)
	if rng.randf() < 0.6:    # 烟囱
		var cx := rng.randf_range(x0 + 40.0, x1 - 40.0)
		_box(Vector3(cx - 16.0, -(top - 10.0), z - depth * 0.6), Vector3(cx + 16.0, -(top - rh - 40.0), z - depth * 0.6 + 30.0), mat)
	if rng.randf() < 0.35 and near:    # 尖塔
		var sx := rng.randf_range(x0 + 60.0, x1 - 60.0)
		_cyl(sx, top + 30.0, z - 40.0, 34.0, 0.0, rh + 170.0, m_roof, 8)    # 塔底埋进墙里（镜头在下面时不露出锥底黑圆）
	# 窗：一层层
	if wins.is_empty():
		return
	var fl := base - 70.0
	while fl > top + 90.0:
		var nwin := maxi(1, int((x1 - x0) / 150.0))
		for i in nwin:
			var wx := lerpf(x0, x1, (float(i) + 0.5) / float(nwin))
			var wt: Texture2D = wins[rng.randi() % wins.size()]
			var on := lit if rng.randf() < 0.55 else 0.0
			_decal(wt, wx, fl, z, 105.0, on)
			_box(Vector3(wx - 30.0, -(fl + 8.0), z), Vector3(wx + 30.0, -fl, z + 12.0), mat)    # 窗台
		_box(Vector3(x0, -(fl + 30.0), z), Vector3(x1, -(fl + 40.0), z + 10.0), mat)    # 层间腰线
		fl -= 160.0
	if near and rng.randf() < 0.5:    # 凸窗：一个挑出来的盒子，正面一扇窗
		var bx := rng.randf_range(x0 + 70.0, x1 - 70.0)
		var by := base - 140.0
		if by - 150.0 > top:
			_box(Vector3(bx - 60.0, -by, z), Vector3(bx + 60.0, -(by - 150.0), z + 70.0), mat)
			_decal(wins[rng.randi() % wins.size()], bx, by - 22.0, z + 70.0, 110.0, lit)


## 手绘楼：第一排贴着步廊后沿（脚踩在台面高度，或直接落街），第二排远一倍、更大更暗进雾；
## 楼与楼之间留缝，透出后排和天空
func _houses_painted(ter: Node, hs: Array) -> void:
	var order := range(hs.size())
	var x := x_lo - 900.0
	var k := 0
	while x < x_hi + 900.0:
		var tx: Texture2D = hs[order[k % hs.size()]]
		var h := float(tx.get_height()) * rng.randf_range(0.36, 0.46) * _envf("U2_HSCALE", 1.0)    # 保留原画里各栋高矮；压矮露出天空和后排
		var w := h * float(tx.get_width()) / float(tx.get_height())
		var cov := _covered(ter, x + w * 0.5, 40.0)
		var base := (cov + 14.0) if not is_nan(cov) else floor_y + 4.0
		var dk := rng.randf_range(0.72, 1.0)    # 每栋明暗打散，别一排一样亮
		_paint(tx, x + w * 0.5, base, HOUSE_Z - rng.randf_range(0.0, 120.0), h, Color(dk, dk * 0.99, dk * 0.98), rng.randf() < 0.4)
		x += w + (rng.randf_range(90.0, 260.0) if rng.randf() < _envf("U2_GAP", 0.45) else rng.randf_range(-20.0, 20.0))
		k += 1
		if k % hs.size() == 0:
			order.shuffle()
	x = x_lo - 1700.0
	k = 2
	while x < x_hi + 1700.0:
		var tx: Texture2D = hs[k % hs.size()]
		var h := float(tx.get_height()) * rng.randf_range(0.7, 0.8) * _envf("U2_HSCALE", 1.0)
		var w := h * float(tx.get_width()) / float(tx.get_height())
		_paint(tx, x + w * 0.5, floor_y + 4.0, HOUSE2_Z, h, Color(0.62, 0.66, 0.74), rng.randf() < 0.5)
		x += w + rng.randf_range(30.0, 160.0)
		k += 3


func _street_props(ter: Node) -> void:
	var x := x_lo + 380.0
	var k := 0
	while x < x_hi:
		var cov := _covered(ter, x, 30.0)
		var h := 250.0 if not is_nan(cov) else 380.0
		_street_lamp(x, h)
		for side in [-1.0, 1.0]:
			_bollard(x + side * 210.0, -50.0)
		x += 760.0 + rng.randf_range(-60.0, 60.0)
		k += 1


func _street_lamp(x: float, h: float) -> void:
	var z := LAMP_Z
	var lt := _tex("prop_lamp")
	if lt != null and OS.get_environment("U2_PROC") == "":
		var hh := h + 40.0
		z = _envf("U2_LAMPZ", 40.0)    # 灯在柱拱前面的街上：放在柱子后面会把柱影往镜头方向拖成几道大黑斜影
		_paint(lt, x, floor_y + 4.0, z, hh, Color(1, 1, 1))
		_light(Vector2(x, floor_y - hh + hh * 0.12), z + 10.0, Color(1.0, 0.87, 0.7), _envf("U2_LAMP", 4.5), 600.0, true, _envf("U2_LVOL", 1.5))
		return
	_box(Vector3(x - 16.0, -floor_y, z - 16.0), Vector3(x + 16.0, -(floor_y - 34.0), z + 16.0), m_stone)
	_cyl(x, floor_y - 34.0, z, 6.0, 4.5, h - 70.0, m_iron, 10)
	var ly := floor_y - h + 22.0
	_box(Vector3(x - 15.0, -(ly + 22.0), z - 15.0), Vector3(x + 15.0, -(ly - 22.0), z + 15.0), m_emit)
	_cyl(x, ly - 22.0, z, 19.0, 0.0, 22.0, m_iron, 8)
	_light(Vector2(x, ly), z + 4.0, Color(1.0, 0.87, 0.7), _envf("U2_LAMP", 4.5), 600.0, true, 4.0)


func _bollard(x: float, z: float) -> void:
	var bs := _parts("prop_bollard")
	if not bs.is_empty() and OS.get_environment("U2_PROC") == "":
		_paint(bs[rng.randi() % bs.size()], x, floor_y + 3.0, z, 74.0, Color(1, 1, 1))
		return
	_cyl(x, floor_y, z, 15.0, 12.0, 62.0, m_stone, 12)
	_sphere(x, floor_y - 70.0, z, 12.0, m_stone)


## 最前景：镜头跟前一段矮栏杆（景深虚化），只露在屏幕最下沿
func _foreground() -> void:
	var n0 := root3.get_child_count()
	var x := x_lo - 400.0
	while x < x_hi + 400.0:
		var w := rng.randf_range(700.0, 1100.0)
		_box(Vector3(x, -floor_y, FG_Z - 14.0), Vector3(x + w, -(floor_y - 40.0), FG_Z + 14.0), m_dark)
		_box(Vector3(x, -(floor_y - 120.0), FG_Z - 15.0), Vector3(x + w, -(floor_y - 132.0), FG_Z + 15.0), m_dark)
		var bx := x + 20.0
		while bx < x + w - 10.0:
			_cyl(bx, floor_y - 40.0, FG_Z, 9.0, 6.0, 80.0, m_dark, 8)
			bx += 40.0
		_box(Vector3(x - 22.0, -floor_y, FG_Z - 22.0), Vector3(x + 22.0, -(floor_y - 150.0), FG_Z + 22.0), m_dark)
		_sphere(x, floor_y - 168.0, FG_Z, 20.0, m_dark)
		x += w + rng.randf_range(500.0, 1200.0)
	for i in range(n0, root3.get_child_count()):    # 最前景不投影：月光下会在街面拖出几道大黑斜影
		var c := root3.get_child(i)
		if c is GeometryInstance3D:
			(c as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_probes()


## 地面倒影：透明背景的 SubViewport 里引擎会关掉屏幕空间反射（和景深），
## 改用一排反射探针（盒投影，只拍一次）让湿石板映出拱廊、亮窗和灯
func _probes() -> void:
	if OS.get_environment("U2_NOPROBE") != "":
		return
	var step := 1400.0
	var x := x_lo - 700.0
	while x < x_hi + 700.0:
		var rp := ReflectionProbe.new()
		rp.update_mode = ReflectionProbe.UPDATE_ONCE
		rp.box_projection = true
		rp.size = Vector3(step + 200.0, 900.0, 1400.0) * S
		rp.origin_offset = Vector3(0.0, 0.0, 0.0)
		rp.position = Vector3(x, -(floor_y - 160.0), -250.0) * S
		rp.max_distance = 3000.0 * S
		rp.intensity = _envf("U2_PROBE", 1.0)
		rp.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
		vp.add_child(rp)
		x += step


func _surface_below(ter: Node, p: Vector2) -> float:
	var best := floor_y
	if ter != null:
		for q in ter.get("platforms"):
			if p.x >= float(q.x0) and p.x <= float(q.x1) and float(q.y) >= p.y - 4.0 and float(q.y) < best:
				best = float(q.y)
		for q in ter.get("blocks"):
			if p.x >= float(q.x0) and p.x <= float(q.x1) and float(q.y) >= p.y - 4.0 and float(q.y) < best:
				best = float(q.y)
	return best


## 每帧：2D 镜头中心 + 缩放 → 抬高的离轴相机；z = 0 平面和 2D 世界对齐
func follow(center: Vector2, zoom: float, dt: float, hero: Vector2, ter: Node) -> void:
	if cam == null:
		return
	t += dt
	_poll -= dt
	if not built and _poll <= 0.0:
		_poll = 0.25
		build(ter)
	var z := maxf(zoom, 0.05)
	var vis_h := 720.0 / z
	var n := cam.near
	var d := CAM_D * S
	var size := vis_h * S * n / d
	var off_y := -CAM_H * S * n / d * _envf("U2_OFFSIGN", 1.0)
	cam.set_frustum(size, Vector2(0.0, off_y), n, cam.far)
	cam.position = Vector3(center.x, -(center.y - CAM_H), CAM_D) * S
	if rcam != null:    # 镜像：位置按街面翻到下面，离轴偏移取反 → 倒影图上下翻转后与主镜头逐像素对齐
		rcam.set_frustum(size, Vector2(0.0, -off_y), n, cam.far)
		rcam.position = Vector3(cam.position.x, 2.0 * (-floor_y * S) - cam.position.y, cam.position.z)
	out_sprite.global_position = center
	if rvp != null and OS.get_environment("U2_DBGREFL") != "":
		out_sprite.texture = rvp.get_texture()
		out_sprite.scale = Vector2.ONE * (1280.0 / 960.0) / z
	if tower_sp != null:    # 母钟楼：极远，跟着镜头只挪一点点（和 2D 版同一个视差系数）
		var mid := (x_lo + x_hi) * 0.5 if x_hi > x_lo else center.x
		var tx := float(vp.size.x) * 0.74 - (center.x - mid) * 0.04 * float(vp.size.x) / 1280.0 * z
		tower_sp.position = Vector2(tx, float(vp.size.y) * 0.5)
		tower_glow.position = Vector2(tx, float(vp.size.y) * 0.22)
	if OS.get_environment("U2_DBGREFL") == "":
		out_sprite.scale = Vector2.ONE * (1280.0 / float(vp.size.x)) / z
	if hero != Vector2.INF:
		var sy := _surface_below(ter, hero)
		var air := clampf((sy - hero.y) / 260.0, 0.0, 1.0)
		shadow_mi.position = Vector3(hero.x, -sy + 1.5, 0.0)
		shadow_mi.scale = Vector3.ONE * (1.0 - 0.45 * air)
		(shadow_mi.material_override as StandardMaterial3D).albedo_color.a = 0.7 * (1.0 - 0.7 * air)
	for r in lamps:
		var s := float(r.sp)
		(r.light as OmniLight3D).light_energy = float(r.e) * (1.0 + 0.05 * sin(t * s) + 0.03 * sin(t * s * 2.7 + 1.0))
