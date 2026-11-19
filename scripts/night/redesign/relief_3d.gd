extends Node2D
## 背景线 11-18 立体感试验 · 路线 B「投影浮雕」（RAIN_DEPTH=B 才开）：
## 一张站立层原画 + 深度图 + 法线图 → 3D 子画面里的浮雕网格；透视相机跟着 2D 镜头走，z=0 平面和 2D 世界 1:1 对齐，
## 所以深度为 1 的东西（街面、步廊、阳台沿）和碰撞完全重合，往后退的墙和楼按透视自然慢下来，侧面会露出来。
## 灯 = OmniLight3D（带阴影），左上冷月光 = DirectionalLight3D（带阴影），远的部分进雾、景深糊。
## 出图贴回 2D：一张跟镜头的 Sprite2D（z 同站立层），角色照常画在前面。

const ReliefShader := preload("res://scripts/night/redesign/relief_3d.gdshader")
const CAM_D := 1500.0      ## 相机到 z=0 平面的距离（越小透视越强）
const RELIEF := 170.0      ## 深度 0 往后退多少
const LAMP_E := 1.05       ## 路灯亮度（1.5 时楼梯被照爆）
const SUBDIV := 1000.0     ## 每段浮雕网格横向细分（越密，深度跳变处的锯齿越小）

var vp: SubViewport
var cam: Camera3D
var out_sprite: Sprite2D
var lamp_lights: Array = []    ## {light, e, sp}
var t := 0.0


## 建 3D 子画面（一次）：环境、相机、月光、出图精灵。之后每段站立层调 add_tile
func setup(z: int) -> void:
	vp = SubViewport.new()
	vp.size = Vector2i(1920, 1080)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)

	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1.0, 1.0, 1.0)
	env.ambient_light_energy = float(OS.get_environment("RB_AMB")) if OS.get_environment("RB_AMB") != "" else 0.18
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.17, 0.21, 0.3)
	env.fog_density = 0.45
	env.fog_depth_begin = CAM_D + 110.0
	env.fog_depth_end = CAM_D + RELIEF * 5.0
	env.fog_depth_curve = 1.0
	env.glow_enabled = false
	env.glow_intensity = 0.6
	env.glow_hdr_threshold = 1.1
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)

	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.near = 50.0
	cam.far = CAM_D + RELIEF * 4.0
	vp.add_child(cam)

	var moon := DirectionalLight3D.new()    # 左上方冷月光，带阴影：阳台、栏杆、楼梯会往墙上投影
	moon.light_color = Color(0.62, 0.72, 1.0)
	moon.light_energy = 0.12
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = CAM_D + RELIEF * 3.0
	moon.rotation = Vector3(deg_to_rad(-38.0), deg_to_rad(-30.0), 0.0)
	vp.add_child(moon)

	out_sprite = Sprite2D.new()
	out_sprite.texture = vp.get_texture()
	out_sprite.z_as_relative = false
	out_sprite.z_index = z
	add_child(out_sprite)


## 一段站立层：原画 uv_rect 那一截 + 深度 + 法线 → 浮雕网格（和 2D 世界 world_rect 对齐）+ 垫底卡；这一段的灯和窗灯
func add_tile(albedo: Texture2D, depth: Texture2D, normal: Texture2D, uv_rect: Rect2, world_rect: Rect2, lamps: Array, wins: Array) -> void:
	var pm := PlaneMesh.new()
	pm.orientation = PlaneMesh.FACE_Z
	pm.size = world_rect.size
	pm.subdivide_width = int(SUBDIV)
	pm.subdivide_depth = int(SUBDIV * world_rect.size.y / world_rect.size.x)
	var mat := ShaderMaterial.new()
	mat.shader = ReliefShader
	mat.set_shader_parameter("albedo_tex", albedo)
	mat.set_shader_parameter("depth_tex", depth)
	mat.set_shader_parameter("normal_tex", normal)
	mat.set_shader_parameter("uv_rect", Vector4(uv_rect.position.x, uv_rect.position.y, uv_rect.size.x, uv_rect.size.y))
	mat.set_shader_parameter("relief", RELIEF)
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.material_override = mat
	var c := world_rect.get_center()
	mi.position = Vector3(c.x, -c.y, 0.0)
	vp.add_child(mi)
	# 垫底卡：同一张画平放在主墙深度，补上被丢掉的拉伸面
	var back_z := -0.45 * RELIEF
	var bm := mat.duplicate() as ShaderMaterial
	bm.set_shader_parameter("flat_card", true)
	var bi := MeshInstance3D.new()
	var bpm := PlaneMesh.new()
	bpm.orientation = PlaneMesh.FACE_Z
	bpm.size = world_rect.size * ((CAM_D - back_z) / CAM_D)
	bi.mesh = bpm
	bi.material_override = bm
	bi.position = Vector3(c.x, -c.y, back_z)
	vp.add_child(bi)

	for p in lamps:
		lamp_lights.append(_omni(p as Vector2, 90.0, Color(1.0, 0.78, 0.5), LAMP_E, 280.0, true))
	for p in wins:
		lamp_lights.append(_omni(p as Vector2, 25.0, Color(1.0, 0.72, 0.42), 0.8, 130.0, false))


func _omni(p: Vector2, front: float, col: Color, e: float, rng: float, shadow: bool) -> Dictionary:
	var l := OmniLight3D.new()
	l.position = Vector3(p.x, -p.y, front)
	l.light_color = col
	l.light_energy = e
	l.omni_range = rng
	l.omni_attenuation = 1.5
	l.shadow_enabled = shadow
	vp.add_child(l)
	return {"light": l, "e": e, "sp": randf_range(3.0, 7.0)}


## 每帧：2D 镜头中心 + 缩放 → 3D 相机；出图贴满屏幕
func follow(center: Vector2, zoom: float, dt: float) -> void:
	if cam == null:
		return
	t += dt
	var half_h := 360.0 / maxf(zoom, 0.05)
	cam.fov = rad_to_deg(2.0 * atan(half_h / CAM_D))
	cam.position = Vector3(center.x, -center.y, CAM_D)
	out_sprite.global_position = center
	out_sprite.scale = Vector2.ONE * (1280.0 / float(vp.size.x)) / maxf(zoom, 0.05)
	for r in lamp_lights:
		var s := float(r.sp)
		(r.light as OmniLight3D).light_energy = float(r.e) * (1.0 + 0.07 * sin(t * s) + 0.04 * sin(t * s * 2.7 + 1.0))
