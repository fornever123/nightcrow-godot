extends Node2D
## 背景线 11-19「3D 街体」（环境变量 RAIN_3D=1 才开；默认游戏不变）。
## 用户原话：“我想法是地面做成3d，近景有距离的做真实的贴图距离 / 就是能走的地方，都是3d”。
##
## 做法：一个 3D 子画面，透视相机跟 2D 镜头走，z = 0 平面与 2D 世界 1:1（单位 = 世界像素），角色、敌人、碰撞都在 z = 0。
##   · 街面：一整块真 3D 石子路，从街对面楼脚（WALL_Z）一直铺到镜头跟前（FLOOR_FRONT），屏幕下方不再是黑带。
##   · 能走的台子（步廊、阳台、石台）：按地形碰撞现建真 3D 石块，前沿正好在 z = 0 和碰撞重合、往后一直接到楼面。
##   · 楼：站立层原画按**真实比例**立在街对面 WALL_Z 处（不放大），所以走起来比角色慢、自然有视差；原画里画的街面切掉。
##   · 灯：布局里的路灯 = 真 OmniLight3D，在 3D 街面、台面上照出光池；月光是一盏冷色平行光。
##   · 角色脚下一块接触阴影（3D 里贴在脚下那个面上）。
## 出图贴回 2D：一张跟镜头的 Sprite2D（z 同站立层 −80），角色照常画在上面。

const StoneShader := preload("res://scripts/night/redesign/street3d_stone.gdshader")
const TEX := "res://assets/image/rain_street/street3d/"
const CAM_D := 1200.0        ## 相机到 z = 0 的距离（越小透视越强）
const WALL_Z := -260.0       ## 街对面楼面（原画卡片）的深度
const FLOOR_FRONT := 900.0   ## 街面往镜头这边铺到哪
const DECK_T := 34.0         ## 台面石板厚
const FACE_H := 96.0         ## 台口立面（压檐 + 托石）高
const LAMP_E := 4.5
const LAMP_R := 520.0
const POST_STEP := 820.0     ## 街灯杆间距
const POST_Z := -150.0       ## 街灯杆立在街中偏里（角色身后、楼前）
const POST_H := 400.0        ## 头顶没台子时的高度；头顶有步廊就换矮的（灯笼要在台底下）
const POST_H_LOW := 230.0
const BOLLARD_Z := -46.0     ## 石桩贴着角色身后一排
const BOLLARD_H := 78.0
const S := 0.01              ## 3D 里 1 单位 = 100 世界像素（Godot 4 点光源按距离平方衰减，按像素当单位灯光照不到地）

var vp: SubViewport
var cam: Camera3D
var out_sprite: Sprite2D
var root3: Node3D
var floor_y := 580.0
var x_lo := INF
var x_hi := -INF
var floor_mi: MeshInstance3D
var decks := {}               ## key → Node3D
var lamp_lights: Array = []   ## {light, e, sp}
var shadow_mi: MeshInstance3D
var t := 0.0
var _poll := 0.0
var mat_floor: ShaderMaterial
var mat_deck: ShaderMaterial
var mat_face: StandardMaterial3D
var posts := {}               ## x → Node3D（等地形建好再按头顶有没有台子定高矮）
var glow_tex: Texture2D


func _tex(name: String) -> Texture2D:
	var p := TEX + name + ".png"
	if ResourceLoader.exists(p):
		return load(p) as Texture2D
	if FileAccess.file_exists(p):
		var im := Image.new()
		if im.load_png_from_buffer(FileAccess.get_file_as_bytes(p)) == OK:
			im.generate_mipmaps()
			return ImageTexture.create_from_image(im)
	return null


func setup(z: int, floor_world_y: float) -> void:
	floor_y = floor_world_y
	vp = SubViewport.new()
	vp.size = Vector2i(1920, 1080)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	root3 = Node3D.new()
	root3.scale = Vector3.ONE * S    # 下面所有几何都按世界像素写，整体缩成米
	vp.add_child(root3)

	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.66, 0.72)
	env.ambient_light_energy = _envf("S3_AMB", 0.4)
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.glow_enabled = false
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)

	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.near = 40.0 * S
	cam.far = (CAM_D + 4000.0) * S
	vp.add_child(cam)

	var moon := DirectionalLight3D.new()    # 左上方冷月光：台口、台面边沿擦一道冷边，台子往楼面投影
	moon.light_color = Color(0.7, 0.78, 0.95)
	moon.light_energy = _envf("S3_MOON", 1.0)
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = (CAM_D + 2000.0) * S
	moon.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(-25.0), 0.0)
	vp.add_child(moon)

	var cob := _tex("floor_cobble")
	var top := _tex("deck_top")
	var wall := _tex("wall_stone")
	mat_floor = ShaderMaterial.new()
	mat_floor.shader = StoneShader
	mat_floor.set_shader_parameter("top_tex", cob)
	mat_floor.set_shader_parameter("face_tex", wall)
	mat_floor.set_shader_parameter("side_tex", wall)
	mat_floor.set_shader_parameter("top_scale", Vector2(300.0, 300.0) * S)
	mat_floor.set_shader_parameter("face_scale", Vector2(220.0, 220.0) * S)
	mat_floor.set_shader_parameter("fade_z0", (-WALL_Z + 20.0) * S)
	mat_floor.set_shader_parameter("fade_z1", (-WALL_Z + 360.0) * S)
	mat_deck = mat_floor.duplicate() as ShaderMaterial
	mat_deck.set_shader_parameter("top_tex", top if top != null else cob)
	mat_deck.set_shader_parameter("top_scale", Vector2(240.0, 240.0) * S)
	mat_deck.set_shader_parameter("rough_top", 0.55)
	mat_deck.set_shader_parameter("fade_z0", 99999.0)
	mat_deck.set_shader_parameter("fade_z1", 100000.0)
	var face := _tex("deck_face")
	if face != null:
		mat_face = StandardMaterial3D.new()
		mat_face.albedo_texture = face
		mat_face.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mat_face.alpha_scissor_threshold = 0.5
		mat_face.roughness = 0.85
		mat_face.texture_repeat = true
		mat_face.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC

	shadow_mi = MeshInstance3D.new()    # 脚下接触阴影
	var sq := PlaneMesh.new()
	sq.size = Vector2(150.0, 70.0)
	shadow_mi.mesh = sq
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.albedo_texture = _shadow_tex()
	sm.albedo_color = Color(0, 0, 0, 0.75)
	shadow_mi.material_override = sm
	shadow_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root3.add_child(shadow_mi)

	out_sprite = Sprite2D.new()
	out_sprite.texture = vp.get_texture()
	out_sprite.z_as_relative = false
	out_sprite.z_index = z
	add_child(out_sprite)


static func _envf(k: String, d: float) -> float:
	var v := OS.get_environment(k)
	return float(v) if v != "" else d


static func _shadow_tex() -> Texture2D:
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


## 一张站立层原画：按真实比例立在 WALL_Z（world_rect 是它在 2D 世界里的框），street_frac 以下（画出来的街面）切掉
func add_card(tex: Texture2D, uv: Rect2, world_rect: Rect2, street_frac: float) -> void:
	var keep := clampf(street_frac + 0.004, 0.0, 1.0)
	var h := world_rect.size.y * keep
	var qm := QuadMesh.new()
	qm.size = Vector2(world_rect.size.x, h)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	m.albedo_texture = tex
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	m.uv1_offset = Vector3(uv.position.x, uv.position.y, 0.0)
	m.uv1_scale = Vector3(uv.size.x, uv.size.y * keep, 1.0)
	var mi := MeshInstance3D.new()
	mi.mesh = qm
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(world_rect.position.x + world_rect.size.x * 0.5, -(world_rect.position.y + h * 0.5), WALL_Z)
	root3.add_child(mi)
	x_lo = minf(x_lo, world_rect.position.x)
	x_hi = maxf(x_hi, world_rect.end.x)
	_rebuild_floor()


func _cut_card(tex: Texture2D, h: float, x: float, z: float, mod: Color, shadow: bool) -> MeshInstance3D:
	var w := h * float(tex.get_width()) / float(tex.get_height())
	var qm := QuadMesh.new()
	qm.size = Vector2(w, h)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.albedo_texture = tex
	m.albedo_color = mod
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var mi := MeshInstance3D.new()
	mi.mesh = qm
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(x, -(floor_y - h * 0.5), z)
	root3.add_child(mi)
	return mi


func _glow_quad(p: Vector3, size: float, col: Color) -> void:
	if glow_tex == null:
		glow_tex = _shadow_tex()
	var qm := QuadMesh.new()
	qm.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_texture = glow_tex
	m.albedo_color = col
	var mi := MeshInstance3D.new()
	mi.mesh = qm
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = p
	root3.add_child(mi)


## 街中的立体道具：街灯杆（带真灯）+ 石桩。头顶有台子的地方换矮灯杆
func _sync_props(ter: Node) -> void:
	var lamp_t := _tex("prop_lamp")
	if lamp_t == null:
		return
	var bol: Array = []
	for i in 3:
		var bt := _tex("prop_bollard_%d" % i)
		if bt != null:
			bol.append(bt)
	var x := x_lo + 520.0
	var k := 0
	while x < x_hi - 200.0:
		var key := int(x)
		if not posts.has(key):
			var covered := false
			for p in ter.get("platforms"):
				if x > float(p.x0) - 60.0 and x < float(p.x1) + 60.0 and float(p.y) < floor_y - 2.0:
					covered = true
			var h := POST_H
			var n := Node3D.new()
			root3.add_child(n)
			posts[key] = n
			if covered:    # 头顶是步廊：不立灯杆（墙上画着壁灯），只留石桩
				h = 0.0
			var ly := floor_y - h * 0.83    # 灯笼中心大约在杆顶往下 17%
			if h > 0.0:
				_cut_card(lamp_t, h, x, POST_Z, Color(0.62, 0.62, 0.66), true).reparent(n)
				var l := OmniLight3D.new()
				l.position = Vector3(x, -ly, POST_Z + 8.0) * S
				l.light_color = Color(1.0, 0.88, 0.72)
				l.light_energy = LAMP_E * 0.8
				l.omni_range = LAMP_R * 0.9 * S
				l.omni_attenuation = 0.7
				l.shadow_enabled = true
				vp.add_child(l)
				lamp_lights.append({"light": l, "e": l.light_energy, "sp": randf_range(3.0, 7.0)})
				_glow_quad(Vector3(x, -ly, POST_Z + 4.0), 120.0, Color(1.0, 0.8, 0.55, 0.55))
			if not bol.is_empty():    # 灯杆两侧各一个石桩，贴着角色身后
				for side in [-1.0, 1.0]:
					var bt: Texture2D = bol[(k + int(side + 1.0)) % bol.size()]
					_cut_card(bt, BOLLARD_H, x + side * 230.0, BOLLARD_Z, Color(0.7, 0.7, 0.74), true).reparent(n)
		x += POST_STEP
		k += 1


## 布局里的路灯（画在楼面上）：灯在楼面前一点，照街面和台子
func add_lamp(p: Vector2) -> void:
	var l := OmniLight3D.new()
	l.position = Vector3(p.x, -p.y, WALL_Z + 70.0) * S    # 灯不放进缩放过的 root3：光照范围不跟节点缩放走
	l.light_color = Color(1.0, 0.87, 0.7)    # 暖白偏淡金，不要橙
	l.light_energy = _envf("S3_LAMP", LAMP_E)
	l.omni_range = LAMP_R * S
	l.omni_attenuation = _envf("S3_ATT", 0.7)
	l.shadow_enabled = true
	vp.add_child(l)
	lamp_lights.append({"light": l, "e": l.light_energy, "sp": randf_range(3.0, 7.0)})


func _rebuild_floor() -> void:
	if floor_mi != null:
		floor_mi.queue_free()
	var x0 := x_lo - 1400.0
	var x1 := x_hi + 1400.0
	floor_mi = _box(Vector3(x0, -floor_y - 60.0, WALL_Z - 420.0), Vector3(x1, -floor_y, FLOOR_FRONT), mat_floor)


func _box(a: Vector3, b: Vector3, mat: Material) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = (b - a).abs()
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.material_override = mat
	mi.position = (a + b) * 0.5
	root3.add_child(mi)
	return mi


## 台子：前沿在 z = 0（和碰撞重合）往后接到楼面；顶面石板、台口一条压檐托石立面
func _build_deck(x0: float, x1: float, y: float, bottom: float) -> Node3D:
	var n := Node3D.new()
	root3.add_child(n)
	var front := 16.0
	var b := _box(Vector3(x0, -(y + DECK_T if is_nan(bottom) else bottom), WALL_Z), Vector3(x1, -y, front), mat_deck)
	b.reparent(n)
	if mat_face != null and is_nan(bottom):
		var qm := QuadMesh.new()
		qm.size = Vector2(x1 - x0, FACE_H)
		var fm := mat_face.duplicate() as StandardMaterial3D
		fm.uv1_scale = Vector3((x1 - x0) / (FACE_H * 4.0), 1.0, 1.0)
		var q := MeshInstance3D.new()
		q.mesh = qm
		q.material_override = fm
		q.position = Vector3((x0 + x1) * 0.5, -(y + FACE_H * 0.5 - 2.0), front + 1.0)
		n.add_child(q)
	return n


## 每隔一会儿对一次地形：新生成的台子建 3D，拆掉的跟着拆（只管有原画卡片的那一截街）
func sync_terrain(ter: Node) -> void:
	if ter == null or x_hi < x_lo:
		return
	var want := {}
	for p in ter.get("platforms"):
		var x0 := float(p.x0)
		var x1 := float(p.x1)
		if x1 < x_lo or x0 > x_hi or float(p.y) >= floor_y - 2.0:
			continue
		want["p%d_%d_%d" % [int(x0), int(x1), int(p.y)]] = [x0, x1, float(p.y), NAN]
	for bl in ter.get("blocks"):
		var x0 := float(bl.x0)
		var x1 := float(bl.x1)
		if x1 < x_lo or x0 > x_hi or float(bl.y) >= floor_y - 2.0:
			continue
		var bot: float = float(bl.get("bottom", NAN)) if bl.has("bottom") else NAN
		if is_nan(bot):
			bot = floor_y
		want["b%d_%d_%d" % [int(x0), int(x1), int(bl.y)]] = [x0, x1, float(bl.y), bot]
	for k in decks.keys():
		if not want.has(k):
			(decks[k] as Node3D).queue_free()
			decks.erase(k)
	for k in want.keys():
		if not decks.has(k):
			var w: Array = want[k]
			decks[k] = _build_deck(w[0], w[1], w[2], w[3])
	_sync_props(ter)


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


## 每帧：2D 镜头中心 + 缩放 → 3D 相机；出图贴满屏幕；接触阴影跟脚
func follow(center: Vector2, zoom: float, dt: float, hero: Vector2, ter: Node) -> void:
	if cam == null:
		return
	t += dt
	_poll -= dt
	if _poll <= 0.0:
		_poll = 0.25
		sync_terrain(ter)
	var half_h := 360.0 / maxf(zoom, 0.05)
	cam.fov = rad_to_deg(2.0 * atan(half_h / CAM_D))
	cam.position = Vector3(center.x, -center.y, CAM_D) * S
	out_sprite.global_position = center
	out_sprite.scale = Vector2.ONE * (1280.0 / float(vp.size.x)) / maxf(zoom, 0.05)
	if hero != Vector2.INF:
		var sy := _surface_below(ter, hero)
		var air := clampf((sy - hero.y) / 260.0, 0.0, 1.0)
		shadow_mi.position = Vector3(hero.x, -sy + 1.5, 0.0)
		shadow_mi.scale = Vector3.ONE * (1.0 - 0.45 * air)
		(shadow_mi.material_override as StandardMaterial3D).albedo_color.a = 0.75 * (1.0 - 0.7 * air)
	for r in lamp_lights:
		var s := float(r.sp)
		(r.light as OmniLight3D).light_energy = float(r.e) * (1.0 + 0.06 * sin(t * s) + 0.03 * sin(t * s * 2.7 + 1.0))
