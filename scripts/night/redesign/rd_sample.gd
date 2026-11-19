extends Node2D
## 背景线 · 画面重构样板屏「光压城，影沉底」（2026-11-17 草稿，未接入正式游戏）
## 七层视差 + 白光柱（雨落进光里就停住）+ 街下暗处翻涌 + 整帧调色。
## 打开 scenes/dev/rain_redesign_sample.tscn 直接跑，A / D 走，W / 空格跳。

const Config := preload("res://scripts/core/configuration.gd")
const Factory := preload("res://scripts/night/player_factory.gd")
const Rain := preload("res://scripts/night/redesign/rd_rain.gd")
const DepthSh := preload("res://scripts/night/redesign/rd_depth.gdshader")
const FogSh := preload("res://scripts/night/redesign/rd_fog.gdshader")
const DeepSh := preload("res://scripts/night/redesign/rd_deep.gdshader")
const GradeSh := preload("res://scripts/night/redesign/rd_grade.gdshader")
const ReflectSh := preload("res://scripts/night/redesign/rd_reflect.gdshader")

const DIR := "res://assets/image/rain_street/redesign_20261117/"
const TOWER := "res://assets/image/rain_street/layered/sky_tower.png"
const FLOOR := 580.0
const ZOOM := 0.65
const CAM_Y := 272.0
const VIS_W := 1280.0 / ZOOM
const FOG := Color(0.33, 0.4, 0.5)
const WARM := Color(1.0, 0.72, 0.42)
## 11-17 用户：“近处和以前能不能不要这么大改动” → 近处用回入口街原站立层（同比例、同脚踩高度），只换它背后的远景
const NEAR_OLD := true
## 11-17 用户：“近景也不是完全不让动……近景可以看看能不能升级的” → 同比例的 Codex 升级版站立层；false 退回原 stand.png
const NEAR_NEW := true
const OLD_DIR := "res://assets/image/rain_street/layered/"
const OLD_S := 1.62 * 0.75      ## 和正式游戏 street_layered 一样：成图 1 像素 = 1.215 世界单位
const OLD_STREET_PX := 800.0
const C_LAMP := Color(1.0, 0.9, 0.72)

## 白光柱：每 PERIOD 重复一组。[底部中心 x 偏移, 底宽, 强度]
const SHAFT_PERIOD := 3200.0
const SHAFTS := [[700.0, 420.0, 1.0], [1820.0, 240.0, 0.5]]
const SHAFT_TOP := -440.0
const SHAFT_SLANT := 0.3        ## 往上每 1，往左偏多少

var meta: Dictionary = {}
var player: CharacterBody2D
var camera: Camera2D
var glows: Array = []           ## {node, base, ph, sp}
var follow: Array = []          ## 跟镜头走的雾 / 渐变：{node, w, f, mat}
var radial: GradientTexture2D
var profile: GradientTexture2D
var noise_tex: NoiseTexture2D
var auto_run := false           ## 截图脚本用：自己往右跑


func cam_x() -> float:
	return camera.get_screen_center_position().x if camera != null else 0.0


func _ready() -> void:
	meta = JSON.parse_string(FileAccess.get_file_as_string(DIR + "layers.json"))
	get_viewport().use_hdr_2d = false   ## HDR 2D 下整帧被重复转线性、画面压成黑，先不用
	RenderingServer.set_default_clear_color(Color(0.02, 0.025, 0.04))
	_make_textures()
	_environment()
	_sky()
	_build_layers()
	_spawn_player()
	if OS.get_environment("RD_NOGRADE") != "1":
		_grade()


# ---------------------------------------------------------------- 基础件

func _make_textures() -> void:
	radial = GradientTexture2D.new()
	radial.fill = GradientTexture2D.FILL_RADIAL
	radial.fill_from = Vector2(0.5, 0.5)
	radial.fill_to = Vector2(1.0, 0.5)
	radial.width = 128
	radial.height = 128
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.35, Color(1, 1, 1, 0.45))
	radial.gradient = g
	profile = GradientTexture2D.new()
	profile.width = 128
	profile.height = 4
	var pg := Gradient.new()
	pg.set_color(0, Color(1, 1, 1, 0))
	pg.set_color(1, Color(1, 1, 1, 0))
	pg.add_point(0.5, Color(1, 1, 1, 1))
	pg.add_point(0.3, Color(1, 1, 1, 0.55))
	pg.add_point(0.7, Color(1, 1, 1, 0.55))
	profile.gradient = pg
	noise_tex = NoiseTexture2D.new()
	noise_tex.width = 512
	noise_tex.height = 256
	noise_tex.seamless = true
	var fn := FastNoiseLite.new()
	fn.frequency = 0.008
	fn.fractal_octaves = 4
	noise_tex.noise = fn


func _environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_strength = 1.0
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 0.62
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.set_glow_level(2, 1.0)
	env.set_glow_level(3, 0.8)
	env.set_glow_level(4, 0.6)
	env.set_glow_level(5, 0.4)
	we.environment = env
	add_child(we)


func _add_mat(node: CanvasItem) -> void:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	node.material = m


func _depth_mat(haze: float, darken := 1.0, base_fade := 0.0, base_start := 0.85, base_col := Color(0.05, 0.07, 0.1)) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = DepthSh
	m.set_shader_parameter("fog_color", FOG)
	m.set_shader_parameter("haze", haze)
	m.set_shader_parameter("darken", darken)
	m.set_shader_parameter("base_fade", base_fade)
	m.set_shader_parameter("base_fade_start", base_start)
	m.set_shader_parameter("base_color", base_col)
	return m


func _parallax(f: float, repeat_w: float) -> Parallax2D:
	var px := Parallax2D.new()
	px.scroll_scale = Vector2(f, 1.0)
	if repeat_w > 0.0:
		px.repeat_size = Vector2(repeat_w, 0.0)
		px.repeat_times = int(ceil(VIS_W / repeat_w)) + 1
	add_child(px)
	return px


func _sprite(parent: Node, path: String, pos: Vector2, s: float, mat: Material = null) -> Sprite2D:
	var sp := Sprite2D.new()
	sp.texture = load(path)
	sp.centered = false
	sp.position = pos
	sp.scale = Vector2(s, s)
	if mat != null:
		sp.material = mat
	parent.add_child(sp)
	return sp


func _glow(parent: Node, pos: Vector2, size: float, col: Color, energy: float, flicker := 0.12) -> void:
	var sp := Sprite2D.new()
	sp.texture = radial
	sp.position = pos
	sp.scale = Vector2.ONE * size / 128.0
	sp.modulate = Color(col.r * energy, col.g * energy, col.b * energy, 1.0)
	_add_mat(sp)
	parent.add_child(sp)
	glows.append({"node": sp, "base": sp.modulate, "ph": randf() * TAU, "sp": randf_range(0.6, 1.6), "fl": flicker})


## 一层里所有暖窗都配一团柔光（近的合并掉）
func _layer_glows(parent: Node, code: String, origin: Vector2, s: float, size_k: float, energy: float, copies: Array = [0.0]) -> void:
	var pts: Array = []
	for l in meta[code].get("lights", []):
		var p := Vector2(l[0], l[1])
		var dup := false
		for q in pts:
			if q.distance_to(p) < 40.0:
				dup = true
				break
		if not dup:
			pts.append(p)
	for dx in copies:
		for p in pts:
			_glow(parent, origin + Vector2(dx, 0) + p * s, 34.0 * s * size_k, WARM, energy, 0.08)


## 跟着镜头横移的雾带 / 渐变（自身不铺满世界，只盖住屏幕）
func _fog(y0: float, y1: float, f: float, tint: Color, density: float, nscale := Vector2(2.0, 1.0), speed := 0.006, hdr := 1.0, soft := Vector2(0.4, 0.4)) -> ColorRect:
	var r := ColorRect.new()
	var w := VIS_W * 1.4
	r.size = Vector2(w, y1 - y0)
	r.position = Vector2(-w / 2.0, y0)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = FogSh
	m.set_shader_parameter("noise", noise_tex)
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("density", density)
	m.set_shader_parameter("nscale", nscale)
	m.set_shader_parameter("speed", speed)
	m.set_shader_parameter("hdr", hdr)
	m.set_shader_parameter("top_soft", soft.x)
	m.set_shader_parameter("bottom_soft", soft.y)
	r.material = m
	add_child(r)
	follow.append({"node": r, "w": w, "f": f, "mat": m, "ns": nscale.x})
	return r


func _gradient(y0: float, y1: float, c0: Color, c1: Color) -> Polygon2D:
	var pg := Polygon2D.new()
	var w := VIS_W * 1.4
	pg.polygon = PackedVector2Array([Vector2(0, y0), Vector2(w, y0), Vector2(w, y1), Vector2(0, y1)])
	pg.vertex_colors = PackedColorArray([c0, c0, c1, c1])
	add_child(pg)
	follow.append({"node": pg, "w": w, "f": 1.0, "mat": null, "ns": 0.0})
	return pg


# ---------------------------------------------------------------- 天空

func _sky() -> void:
	var cl := CanvasLayer.new()
	cl.layer = -100
	add_child(cl)
	var tr := TextureRect.new()
	tr.texture = load(DIR + "L1_sky.png")
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr.modulate = Color(0.95, 1.0, 1.08)
	cl.add_child(tr)


# ---------------------------------------------------------------- 七层

func _build_layers() -> void:
	# 远：司辰母钟楼（用户定稿的天际线钟楼）
	var pt := _parallax(0.04, 0.0)
	## 11-17 用户“远景可以更大”：近处是旧站立层时，钟楼、远城、中城、后排街屋都放大抬高，从矮楼顶和楼缝里露出来
	var tw := _sprite(pt, TOWER, Vector2(-640, -420), 1.3, _depth_mat(0.46, 1.1)) if NEAR_OLD else _sprite(pt, TOWER, Vector2(420, -330), 0.8, _depth_mat(0.5, 1.1))
	tw.modulate = Color(1, 1, 1, 0.96)
	# 远城
	var m2: Dictionary = meta["L2_far"]
	var s2 := 1.7 if NEAR_OLD else 1.12
	var w2: float = m2.size[0] * s2
	var p2 := _parallax(0.1, w2)
	_sprite(p2, DIR + "L2_far.png", Vector2(0, (-190.0 if NEAR_OLD else 40.0) - m2.content_top * s2), s2, _depth_mat(0.18, 1.05))
	_fog(160, 560, 0.15, Color(0.5, 0.58, 0.68, 1), 0.55, Vector2(1.5, 1.0), 0.004)
	# 中城
	var m3: Dictionary = meta["L3_mid"]
	var s3 := 1.45 if NEAR_OLD else 1.0
	var w3: float = m3.size[0] * s3
	var p3 := _parallax(0.26, w3)
	var o3 := Vector2(0, (0.0 if NEAR_OLD else 170.0) - m3.content_top * s3)
	_sprite(p3, DIR + "L3_mid.png", o3, s3, _depth_mat(0.3, 1.0, 0.6, 0.6, FOG))
	_layer_glows(p3, "L3_mid", o3, s3, 1.0, 0.35)
	_fog(300, 680, 0.35, Color(0.42, 0.5, 0.6, 1), 0.6, Vector2(2.2, 1.0), 0.008)
	# 远处的光柱（在中城和近楼之间，慢）
	var pf := _parallax(0.45, SHAFT_PERIOD * 0.9)
	var far_shafts := Node2D.new()
	_add_mat(far_shafts)
	far_shafts.draw.connect(_draw_shafts.bind(far_shafts, 0.55, 0.7))
	pf.add_child(far_shafts)
	# 近后景街屋
	var sF := 0.8 if NEAR_OLD else 0.74
	var wa: float = meta["L4a_facade"].size[0] * sF
	var gap := 1000.0
	var gap2 := 1500.0
	var period := wa * 2.0 + gap + gap2
	var p4 := _parallax(0.52 if NEAR_OLD else 0.62, period)
	var base_row := 866.0
	var o4a := Vector2(0, 630 - base_row * sF)
	var o4b := Vector2(wa + gap, 630 - base_row * sF)
	_sprite(p4, DIR + "L4a_facade.png", o4a, sF, _depth_mat(0.27, 1.15, 0.85, 0.7, Color(0.12, 0.15, 0.2)))
	_sprite(p4, DIR + "L4b_facade.png", o4b, sF, _depth_mat(0.27, 1.15, 0.85, 0.7, Color(0.12, 0.15, 0.2)))
	_layer_glows(p4, "L4a_facade", o4a, sF, 1.6, 0.55)
	_layer_glows(p4, "L4b_facade", o4b, sF, 1.6, 0.55)
	# 远雨（在近楼前、街前）
	_rain("RainBack", 260, Vector2(-80, 1150), Vector2(16, 28), 1.0, Color(0.55, 0.63, 0.74, 0.16), 640.0, false)
	if NEAR_OLD:
		# 近处是旧码头墙：墙下干净地沉进暗色，不露下层旧城的碎条
		_gradient(560, 740, Color(0.03, 0.04, 0.06, 0.0), Color(0.02, 0.025, 0.04, 1.0))
		_gradient(740, 1000, Color(0.02, 0.025, 0.04, 1.0), Color(0.01, 0.012, 0.02, 1.0))
		_finish_ground()
		return
	# 街下：渐黑 → 下层旧城 → 暗处翻涌
	var mist := Color(0.31, 0.37, 0.46, 1.0)
	_gradient(500, 640, Color(mist.r, mist.g, mist.b, 0.0), mist)
	_gradient(680, 920, mist, Color(0.01, 0.015, 0.03, 1.0))
	var m6: Dictionary = meta["L6_lower"]
	var s6 := 0.95
	var w6: float = m6.size[0] * s6
	var p6 := _parallax(0.5, w6)
	var o6 := Vector2(0, 645 - m6.content_top * s6)
	_sprite(p6, DIR + "L6_lower.png", o6, s6, _depth_mat(0.16, 0.95, 0.95, 0.5, Color(0.01, 0.015, 0.03)))
	_layer_glows(p6, "L6_lower", o6, s6, 1.0, 0.4)
	_fog(560, 760, 0.55, Color(0.3, 0.37, 0.47, 1), 0.45, Vector2(2.5, 1.0), 0.01)
	var deep := ColorRect.new()
	deep.size = Vector2(VIS_W * 1.4, 260)
	deep.position = Vector2(-VIS_W * 0.7, 700)
	deep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dm := ShaderMaterial.new()
	dm.shader = DeepSh
	dm.set_shader_parameter("noise", noise_tex)
	deep.material = dm
	add_child(deep)
	follow.append({"node": deep, "w": VIS_W * 1.4, "f": 0.7, "mat": dm, "ns": 3.0})
	_finish_ground()


func _finish_ground() -> void:
	if NEAR_OLD:
		_build_old_near()
	else:
		# 战斗面：高架石街
		var m5: Dictionary = meta["L5_deck"]
		var s5 := 0.62
		var w5: float = m5.size[0] * s5
		var p5 := _parallax(1.0, w5)
		_sprite(p5, DIR + "L5_deck.png", Vector2(0, FLOOR - m5.rim_row * s5), s5, _depth_mat(0.0, 1.0))
	var floor_body := StaticBody2D.new()
	var cs := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(200000, 200)
	cs.shape = box
	floor_body.position = Vector2(0, FLOOR + 100)
	floor_body.add_child(cs)
	add_child(floor_body)
	# 近处的白光柱 + 落在街面上的光池
	var near_shafts := Node2D.new()
	near_shafts.name = "Shafts"
	_add_mat(near_shafts)
	near_shafts.draw.connect(_draw_shafts.bind(near_shafts, 1.0, 1.0))
	add_child(near_shafts)
	near_shafts.set_process(true)


## 近处站立层。NEAR_NEW = 用 Codex 升级版三张（N1→N2→N3 顺序拼，不镜像）；否则用入口街原站立层（正放 + 镜像）
## 两种都按原站立层比例：成图 1 像素 = OLD_S 世界单位，脚踩的那一行对齐 FLOOR
func _near_tiles() -> Array:
	if NEAR_NEW:
		var out: Array = []
		for c in ["N1_near", "N2_near", "N3_near"]:
			if meta.has(c):
				out.append({"path": DIR + c + ".png", "code": c, "flip": false})
		if out.size() > 0:
			return out
	return [{"path": OLD_DIR + "stand.png", "code": "stand", "flip": false}, {"path": OLD_DIR + "stand.png", "code": "stand", "flip": true}]


## 脚踩的那一行：原站立层是 800；新图用“第一行整行不透明”再加上原图里同样量出来的差值（800 − 787）
func _street_row(code: String) -> float:
	if code == "stand":
		return OLD_STREET_PX
	var r := float(meta[code].get("street_row", -1))
	if r < 0:
		return OLD_STREET_PX
	return r + (OLD_STREET_PX - float(meta["stand"].get("street_row", OLD_STREET_PX)))


func _build_old_near() -> void:
	var tiles := _near_tiles()
	var xs: Array = []
	var total := 0.0
	for t in tiles:
		xs.append(total)
		total += float(meta[t.code].size[0]) * OLD_S
	var p := _parallax(1.0, total)
	# 站立层后面一层冷白雾光：只从门洞、巷缝里露出来（旧版门洞透光的感觉）
	var gx := 300.0
	while gx < total:
		var g := Sprite2D.new()
		g.texture = radial
		g.position = Vector2(gx, FLOOR - 170.0)
		g.scale = Vector2(620.0, 640.0) / 128.0
		g.modulate = Color(0.36, 0.42, 0.5)
		_add_mat(g)
		p.add_child(g)
		gx += 560.0
	var water_y := FLOOR + 72.0
	for i in tiles.size():
		var t: Dictionary = tiles[i]
		var m: Dictionary = meta[t.code]
		var row := _street_row(t.code)
		var top := FLOOR - row * OLD_S
		var sp := _sprite(p, t.path, Vector2(xs[i], top), OLD_S)
		sp.flip_h = t.flip
	# 码头墙下的河面：旧版入口街就有（用户 11-15 恢复的版本）
	var water := ColorRect.new()
	water.position = Vector2(0, water_y)
	water.size = Vector2(total, 400)
	water.color = Color(0.025, 0.032, 0.05)
	water.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(water)
	for i in tiles.size():
		var t: Dictionary = tiles[i]
		var m: Dictionary = meta[t.code]
		var row := _street_row(t.code)
		var rf := Sprite2D.new()
		rf.texture = load(t.path)
		rf.centered = false
		rf.region_enabled = true
		rf.region_rect = Rect2(0, 0, m.size[0], row)
		rf.flip_v = true
		rf.flip_h = t.flip
		rf.scale = Vector2(OLD_S, OLD_S)
		rf.position = Vector2(xs[i], water_y)
		var rm := ShaderMaterial.new()
		rm.shader = ReflectSh
		rm.set_shader_parameter("edge", row / float(m.size[1]))
		rf.material = rm
		p.add_child(rf)
	var lip := ColorRect.new()          # 墙沿被雨打湿的一道细亮边
	lip.position = Vector2(0, water_y - 2.0)
	lip.size = Vector2(total, 2.0)
	lip.color = Color(0.5, 0.58, 0.7, 0.35)
	lip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(lip)
	for i in tiles.size():
		var t: Dictionary = tiles[i]
		var m: Dictionary = meta[t.code]
		var row := _street_row(t.code)
		var top := FLOOR - row * OLD_S
		var tw: float = float(m.size[0]) * OLD_S
		var kept: Array = []             ## 相近的灯点合成一个（一扇窗常被量成好几块）
		for l in m.lights:
			var dup := false
			for q in kept:
				if absf(q[0] - l[0]) < 70.0 and absf(q[1] - l[1]) < 70.0:
					dup = true
					break
			if not dup:
				kept.append(l)
		for l in kept:
			var lx: float = l[0] * OLD_S
			if t.flip:
				lx = tw - lx
			lx += xs[i]
			_glow(p, Vector2(lx, top + l[1] * OLD_S), maxf(70.0, l[2] * OLD_S * 3.0), C_LAMP, 0.14, 0.12)
			# 只有路灯那一带（街面以上约 1～2 层楼、小而亮的点）才往街上、水里投光
			if l[1] > row - 330.0 and l[1] < row - 60.0 and l[2] < 90:
				# 灯照到街面上的暖光
				var pool := Sprite2D.new()
				pool.texture = radial
				pool.position = Vector2(lx, FLOOR + 6.0)
				pool.scale = Vector2(320.0, 46.0) / 128.0
				pool.modulate = Color(C_LAMP.r * 0.13, C_LAMP.g * 0.13, C_LAMP.b * 0.13, 1.0)
				_add_mat(pool)
				p.add_child(pool)
				# 路灯在水里拉出的一条暖光
				_glow(p, Vector2(lx, water_y + 70.0), 1.0, C_LAMP, 0.0)
				var st: Sprite2D = glows[-1].node
				st.scale = Vector2(30.0, 150.0) / 128.0
				glows[-1].base = Color(C_LAMP.r * 0.3, C_LAMP.g * 0.3, C_LAMP.b * 0.3, 1.0)
				glows[-1].fl = 0.3


func _rain(nm: String, n: int, spd: Vector2, ln: Vector2, w: float, col: Color, bottom: float, freeze: bool) -> Node2D:
	var r: Node2D = Rain.new()
	r.name = nm
	r.host = self
	r.count = n
	r.speed = spd
	r.length_px = ln
	r.width = w
	r.color = col
	r.bottom = bottom
	r.freeze = freeze
	add_child(r)
	return r


func _spawn_player() -> void:
	var config := Config.read()
	var moves := Config.moves(config)
	Factory.register_input()
	player = Factory.build(config, moves, Vector2(200, FLOOR))
	add_child(player)
	camera = Camera2D.new()
	camera.zoom = Vector2(ZOOM, ZOOM)
	camera.position = Vector2(player.global_position.x, CAM_Y)
	add_child(camera)
	camera.make_current()
	# 主雨：在人前面；落进光柱就停住
	var main_rain := _rain("RainMain", 520, Vector2(-120, 1500), Vector2(26, 44), 1.6, Color(0.66, 0.74, 0.84, 0.3), FLOOR, true)
	main_rain.setup()
	get_node("RainBack").setup()
	# 近雨：少、长、糊
	var near_rain := _rain("RainNear", 60, Vector2(-180, 2300), Vector2(70, 110), 3.0, Color(0.6, 0.68, 0.78, 0.1), 900.0, false)
	near_rain.setup()
	_foreground()


func _foreground() -> void:
	var it: Array = meta["L7_fg"]["items"]
	var p := _parallax(1.32, 5200.0)
	var dark := _depth_mat(0.0, 0.3)
	# [素材序号, x, 底边 y（负数 = 顶边贴着画面上沿）, 缩放]
	var place := [[0, 260.0, 930.0, 1.08], [3, 1500.0, -330.0, 1.0], [1, 2300.0, 900.0, 0.95], [6, 3400.0, -330.0, 1.0], [5, 4300.0, 940.0, 1.0]]
	if NEAR_OLD:
		place = [[3, 1500.0, -330.0, 1.0]]   ## 近处不大改：只留顶上垂下的铁链（旧版也有）
	for pl in place:
		var item: Dictionary = it[pl[0]]
		var b: Array = item.box
		var h: float = (b[3] - b[1]) * pl[3]
		var y: float = pl[2] - h if pl[2] > 0 else pl[2]
		_sprite(p, DIR + item.file, Vector2(pl[1], y), pl[3], dark)
		if pl[0] == 0:
			_glow(p, Vector2(pl[1], y) + Vector2(57, 103) * pl[3], 120.0, WARM, 0.9, 0.18)


func _grade() -> void:
	var cl := CanvasLayer.new()
	cl.layer = 90
	add_child(cl)
	var r := ColorRect.new()
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = GradeSh
	r.material = m
	cl.add_child(r)


# ---------------------------------------------------------------- 白光柱

func _shaft_geom(cx_bottom: float, w_bottom: float, depth_k: float) -> Array:
	var top := SHAFT_TOP
	var bot := FLOOR + 6.0 if depth_k >= 1.0 else 900.0
	var h := bot - top
	var cx_top := cx_bottom - SHAFT_SLANT * h
	var w_top := w_bottom * 0.72
	return [top, bot, cx_top, cx_bottom, w_top, w_bottom]


func _draw_shafts(node: Node2D, depth_k: float, strength: float) -> void:
	var period := SHAFT_PERIOD if depth_k >= 1.0 else SHAFT_PERIOD * 0.9
	var cxw := cam_x() if depth_k >= 1.0 else 0.0
	var k0 := int(floor((cxw - VIS_W) / period)) - 1
	var k1 := int(ceil((cxw + VIS_W) / period)) + 1
	if depth_k < 1.0:
		k0 = -1
		k1 = 1
	var t := Time.get_ticks_msec() / 1000.0
	for k in range(k0, k1 + 1):
		for s in SHAFTS:
			var g := _shaft_geom(k * period + s[0] * (1.0 if depth_k >= 1.0 else 0.8), s[1] * depth_k, depth_k)
			var top: float = g[0]
			var bot: float = g[1]
			var mid := lerpf(top, bot, 0.55)
			var cxm := lerpf(g[2], g[3], 0.55)
			var wm := lerpf(g[4], g[5], 0.55)
			var breathe := 0.9 + 0.1 * sin(t * 0.7 + k * 1.3 + s[0])
			var a: float = s[2] * strength * breathe
			var c0 := Color(0.82, 0.9, 1.0, 0.0)
			var c1 := Color(0.82, 0.9, 1.0, (0.42 if depth_k >= 1.0 else 0.17) * a)
			var c2 := Color(0.9, 0.95, 1.0, (0.6 if depth_k >= 1.0 else 0.26) * a)
			node.draw_polygon(
				PackedVector2Array([Vector2(g[2] - g[4] / 2, top), Vector2(g[2] + g[4] / 2, top), Vector2(cxm + wm / 2, mid), Vector2(g[3] + g[5] / 2, bot), Vector2(g[3] - g[5] / 2, bot), Vector2(cxm - wm / 2, mid)]),
				PackedColorArray([c0, c0, c1, c2, c2, c1]),
				PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 0.5), Vector2(1, 1), Vector2(0, 1), Vector2(0, 0.5)]),
				profile)
			if depth_k >= 1.0:
				# 光落到街面：一片亮池，压过街沿
				var pool := Rect2(g[3] - g[5] * 0.9, bot - 46.0, g[5] * 1.8, 92.0)
				node.draw_texture_rect(radial, pool, false, Color(0.9, 0.95, 1.0, 0.35 * a))
				var core := Rect2(g[3] - g[5] * 0.45, bot - 14.0, g[5] * 0.9, 28.0)
				node.draw_texture_rect(radial, core, false, Color(1.0, 1.0, 1.0, 0.4 * a))


func shaft_hit(p: Vector2) -> float:
	var k := int(floor(p.x / SHAFT_PERIOD))
	var best := 0.0
	for kk in [k - 1, k, k + 1]:
		for s in SHAFTS:
			var g := _shaft_geom(kk * SHAFT_PERIOD + s[0], s[1], 1.0)
			if p.y < g[0] or p.y > g[1]:
				continue
			var tt: float = (p.y - g[0]) / (g[1] - g[0])
			var cx := lerpf(g[2], g[3], tt)
			var hw := lerpf(g[4], g[5], tt) * 0.5
			var d := absf(p.x - cx) / hw
			if d < 1.0:
				best = maxf(best, (1.0 - d) * s[2])
	return best


# ---------------------------------------------------------------- 每帧

func _process(_dt: float) -> void:
	if player != null and camera != null:
		if auto_run:
			Input.action_press("move_right")
		var target := Vector2(player.global_position.x + 120.0 * signf(player.velocity.x), CAM_Y)
		camera.position = camera.position.lerp(target, 0.08)
	var cx := cam_x()
	for fo in follow:
		fo.node.position.x = cx - fo.w / 2.0
		if fo.mat != null:
			fo.mat.set_shader_parameter("scroll", cx * fo.f / fo.w * fo.ns)
	var t := Time.get_ticks_msec() / 1000.0
	for gl in glows:
		var k: float = 1.0 - gl.fl + gl.fl * (0.6 + 0.4 * sin(t * gl.sp * 3.0 + gl.ph) * sin(t * gl.sp * 1.3 + gl.ph * 2.0))
		gl.node.modulate = Color(gl.base.r * k, gl.base.g * k, gl.base.b * k, 1.0)
	var sh := get_node_or_null("Shafts")
	if sh != null:
		sh.queue_redraw()
	for c in get_children():
		if c is Parallax2D:
			for n in c.get_children():
				if n is Node2D and n.draw.get_connections().size() > 0:
					n.queue_redraw()
