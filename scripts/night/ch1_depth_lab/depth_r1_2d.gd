extends Node2D
## 路线 1（R1）：2D 真四层大纵深重构样板（U3 断崖大纵深 + U2 透视湿街 + BlurPlane 离焦 + 色调 3）
## 独立外挂节点，仅在样板评测中挂载到 stage，零修改主游戏默认代码。

const ART_DIR := "res://assets/image/rain_street/depth_lab_20261118/"
const YING_DIR := "res://assets/image/rain_street/ying2/"
const BlurSh := preload("res://scripts/night/redesign/blur_plane.gdshader")
const WetSh := preload("res://scripts/night/ch1_depth_lab/wet_viaduct.gdshader")
const RibbonSh := preload("res://scripts/night/redesign/ying_ribbon.gdshader")
const FLOOR := 580.0
const PLAY_SPAN := 2280.0   # 单块高架桥跨度（让门楼单层 >= 1.65 个角色高，宏大威严不缩模型屋）

var camera: Camera2D
var player: Node2D
var _t := 0.0
var _meta: Dictionary = {}
var _tex_far: Texture2D
var _tex_mid: Texture2D
var _tex_play: Texture2D
var _tex_fg: Texture2D
var _tex_glow: Texture2D

var _far_layer: Node2D
var _mid_far_layer: Node2D
var _blur_far: Sprite2D
var _mid_near_layer: Node2D
var _blur_near: Sprite2D
var _play_layer: Node2D
var _wet_rect: Sprite2D
var _wet_mat: ShaderMaterial
var _fg_layer: Node2D
var _glow_layer: Node2D
var _hero_contact_shadow: Node2D
var _sky_ribbons: Array = []
var _lamp_world_xs: PackedFloat32Array = PackedFloat32Array([2680.0, 3440.0, 4240.0, 4960.0])


static func _load_png(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	if not FileAccess.file_exists(path):
		return null
	var img := Image.new()
	if img.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
		return null
	return ImageTexture.create_from_image(img)


static func _make_glow_tex() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.add_point(0.42, Color(1, 1, 1, 0.32))
	g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 256
	t.height = 256
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	return t


static func _white_tex() -> Texture2D:
	var im := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	im.fill(Color.WHITE)
	return ImageTexture.create_from_image(im)


func _layer(z: int, cb: Callable, mat: Material = null) -> Node2D:
	var n := Node2D.new()
	n.z_as_relative = false
	n.z_index = z
	n.material = mat
	n.draw.connect(cb)
	add_child(n)
	return n


func _blur_quad(z: int, radius: float, tint: Color, haze: float) -> Sprite2D:
	var sp := Sprite2D.new()
	sp.texture = _white_tex()
	sp.scale = Vector2(720.0, 420.0)
	sp.z_as_relative = false
	sp.z_index = z
	var m := ShaderMaterial.new()
	m.shader = BlurSh
	m.set_shader_parameter("radius", radius)
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("haze", haze)
	sp.material = m
	add_child(sp)
	return sp


func setup(cam: Camera2D, hero: Node2D) -> void:
	camera = cam
	player = hero


func _ready() -> void:
	var mp := ART_DIR + "meta.json"
	if FileAccess.file_exists(mp):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(mp))
		if parsed is Dictionary:
			_meta = parsed
	_tex_far = _load_png(ART_DIR + "r1_far_sky_tower.png")
	_tex_mid = _load_png(ART_DIR + "r1_mid_city_abyss.png")
	_tex_play = _load_png(ART_DIR + "r1_play_viaduct.png")
	_tex_fg = _load_png(ART_DIR + "r1_fg_frame.png")
	_tex_glow = _make_glow_tex()

	# 层级顺序（严格 4 级明度/锐度阶梯）：
	# -100: 远景天光 + 母钟楼（视差 0.05，最亮雾化）
	#  -96: 高空墨影流向母钟楼（只在高空，绝不贴地）
	#  -94: 中远深渊哥特城（视差 0.24，偏亮银灰雾）
	#  -93: BlurPlane 远距柔焦雾板
	#  -91: 中近深渊哥特城（视差 0.48，稍暗、清晰度提高）
	#  -90: BlurPlane 中距微离焦雾板（拉出空气透视，衬托角色和暗影敌人！）
	#  -80: 玩法站立层高架石桥与门楼（视差 1.0，全锐度、厚实透视湿石板 + 镂空桥洞）
	#  -78: 暖白街灯光晕（加色）
	#   -4: 透视湿石板微反光 + 主角接触阴影
	#   22: 最前景暗剪影压框（视差 1.32，离焦、压底边和边角，绝不挡战斗区）
	_far_layer = _layer(-100, _draw_far)
	_build_sky_ribbons()
	_mid_far_layer = _layer(-94, _draw_mid_far)
	_blur_far = _blur_quad(-93, 2.2, Color(0.24, 0.25, 0.28, 1.0), 0.16)
	_mid_near_layer = _layer(-91, _draw_mid_near)
	_blur_near = _blur_quad(-90, 1.3, Color(0.18, 0.19, 0.22, 1.0), 0.10)
	_play_layer = _layer(-80, _draw_play)

	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow_layer = _layer(-78, _draw_glow, add_mat)

	_wet_rect = Sprite2D.new()
	_wet_rect.texture = _white_tex()
	_wet_rect.z_as_relative = false
	_wet_rect.z_index = -4
	_wet_mat = ShaderMaterial.new()
	_wet_mat.shader = WetSh
	_wet_rect.material = _wet_mat
	add_child(_wet_rect)

	_hero_contact_shadow = _layer(-3, _draw_hero_shadow)
	_fg_layer = _layer(22, _draw_fg)


func _build_sky_ribbons() -> void:
	for i in 4:
		var tx := _load_png(YING_DIR + "ink_%d.png" % i)
		if tx == null:
			continue
		var sp := Sprite2D.new()
		sp.texture = tx
		sp.z_as_relative = false
		sp.z_index = -96
		sp.modulate = Color(1, 1, 1, 0.42 if i % 2 == 0 else 0.30)
		var m := ShaderMaterial.new()
		m.shader = RibbonSh
		m.set_shader_parameter("seed", float(i) * 13.7 + 2.1)
		sp.material = m
		add_child(sp)
		_sky_ribbons.append({"sp": sp, "mat": m, "phase": float(i) * 0.25, "y_off": -270.0 + float(i) * 75.0, "w": 1150.0 + float(i) * 160.0})


func _cam() -> Vector2:
	return camera.get_screen_center_position() if camera != null else Vector2(3600.0, 290.0)


func _process(delta: float) -> void:
	_t += delta
	var c := _cam()
	if _blur_far != null:
		_blur_far.global_position = c
	if _blur_near != null:
		_blur_near.global_position = c
	if _wet_rect != null:
		_wet_rect.global_position = Vector2(c.x, FLOOR + 26.0)
		_wet_rect.scale = Vector2(800.0, 24.0)   # 3200 x 96 世界范围覆盖透视湿石板路面
		_wet_mat.set_shader_parameter("time_sec", _t)
		_wet_mat.set_shader_parameter("cam_x", c.x)
		if player != null:
			_wet_mat.set_shader_parameter("hero_x", player.global_position.x)
	for rb in _sky_ribbons:
		var sp: Sprite2D = rb["sp"]
		var m: ShaderMaterial = rb["mat"]
		m.set_shader_parameter("t", _t)
		var u := fposmod(float(rb["phase"]) + _t * 0.014, 1.0)
		var sx := c.x - 1350.0 + u * 2700.0
		var sy := c.y + float(rb["y_off"]) - u * 160.0
		sp.global_position = Vector2(sx, sy)
		sp.rotation = -0.14
		var sc: float = float(rb["w"]) / maxf(float(sp.texture.get_width()), 1.0)
		sp.scale = Vector2(sc, sc * 0.72)
		var fade := sin(u * PI)
		sp.modulate.a = 0.44 * fade
	_far_layer.queue_redraw()
	_mid_far_layer.queue_redraw()
	_mid_near_layer.queue_redraw()
	_play_layer.queue_redraw()
	_glow_layer.queue_redraw()
	_hero_contact_shadow.queue_redraw()
	_fg_layer.queue_redraw()


func _draw_far() -> void:
	if _tex_far == null:
		return
	var c := _cam()
	# 远景宽幅微动（视差 0.05），确保铺满 0.65 镜头下的 1970×1108 视口
	var w := 2480.0
	var h := w * float(_tex_far.get_height()) / maxf(float(_tex_far.get_width()), 1.0)
	var ox := c.x - (c.x - 3600.0) * 0.05
	var oy := c.y - 40.0
	_far_layer.draw_texture_rect(_tex_far, Rect2(ox - w * 0.5, oy - h * 0.5, w, h), false, Color(1.02, 1.01, 0.99, 1.0))


func _draw_mid_far() -> void:
	if _tex_mid == null:
		return
	var c := _cam()
	var tw := 2150.0
	var th := tw * float(_tex_mid.get_height()) / maxf(float(_tex_mid.get_width()), 1.0)
	var scroll_x := c.x * 0.24
	var base_i := floori((c.x - scroll_x - 1600.0) / tw)
	var y_top := FLOOR - th * 0.64
	for k in range(base_i - 1, base_i + 3):
		var x0 := float(k) * tw + scroll_x
		var flip := posmod(k, 2) == 1
		var dw := -tw if flip else tw
		_mid_far_layer.draw_texture_rect(_tex_mid, Rect2(x0, y_top, dw, th), false, Color(0.95, 0.96, 0.98, 0.92))


func _draw_mid_near() -> void:
	if _tex_mid == null:
		return
	var c := _cam()
	var tw := 2380.0
	var th := tw * float(_tex_mid.get_height()) / maxf(float(_tex_mid.get_width()), 1.0)
	var scroll_x := c.x * 0.48
	var base_i := floori((c.x - scroll_x - 1800.0) / tw)
	var y_top := FLOOR - th * 0.54
	for k in range(base_i - 1, base_i + 3):
		var x0 := float(k) * tw + scroll_x + 540.0
		var flip := posmod(k, 2) == 0
		var dw := -tw if flip else tw
		_mid_near_layer.draw_texture_rect(_tex_mid, Rect2(x0, y_top, dw, th), false, Color(0.76, 0.75, 0.77, 1.0))


func _draw_play() -> void:
	if _tex_play == null:
		return
	var c := _cam()
	var meta_p: Dictionary = _meta.get("r1_play_viaduct", {})
	var w_px := float(meta_p.get("w", _tex_play.get_width()))
	var h_px := float(meta_p.get("h", _tex_play.get_height()))
	var g_px := float(meta_p.get("ground_px", h_px * 0.73))
	var k := PLAY_SPAN / maxf(w_px, 1.0)
	var h := h_px * k
	var y_top := FLOOR - g_px * k
	var start_idx := floori((c.x - 2400.0) / PLAY_SPAN)
	for idx in range(start_idx, start_idx + 4):
		var x0 := float(idx) * PLAY_SPAN
		_play_layer.draw_texture_rect(_tex_play, Rect2(x0, y_top, PLAY_SPAN + 2.0, h), false, Color(1.03, 1.01, 0.98, 1.0))


func _draw_glow() -> void:
	if _tex_glow == null:
		return
	var pulse := 0.92 + 0.08 * sin(_t * 4.7)
	for lx in _lamp_world_xs:
		_glow_layer.draw_texture_rect(_tex_glow, Rect2(lx - 180.0, FLOOR - 340.0, 360.0, 360.0), false, Color(1.0, 0.86, 0.58, 0.24 * pulse))
		_glow_layer.draw_texture_rect(_tex_glow, Rect2(lx - 260.0, FLOOR - 36.0, 520.0, 120.0), false, Color(1.0, 0.84, 0.55, 0.22 * pulse))


func _draw_hero_shadow() -> void:
	if player == null:
		return
	var px := player.global_position.x
	var foot_y := FLOOR + 4.0
	# 脚下真实接触软影（随离地高度衰减）
	var foot_off := float(player.get("foot_offset")) if "foot_offset" in player else 0.0
	var h_above := maxf(0.0, FLOOR - (player.global_position.y + foot_off))
	var k := clampf(1.0 - h_above / 260.0, 0.15, 1.0)
	_hero_contact_shadow.draw_set_transform(Vector2(px, foot_y), 0.0, Vector2(1.0, 0.26))
	_hero_contact_shadow.draw_circle(Vector2.ZERO, 54.0 * k, Color(0.01, 0.01, 0.02, 0.58 * k))
	_hero_contact_shadow.draw_set_transform(Vector2.ZERO)


func _draw_fg() -> void:
	if _tex_fg == null:
		return
	var c := _cam()
	var tw := 2300.0
	var th := tw * float(_tex_fg.get_height()) / maxf(float(_tex_fg.get_width()), 1.0)
	var scroll_x := (c.x - 3600.0) * (1.0 - 1.32)
	var base_i := floori((c.x - scroll_x - 1800.0) / tw)
	var y_top := c.y - th * 0.48
	for idx in range(base_i - 1, base_i + 3):
		var x0 := float(idx) * tw + scroll_x
		_fg_layer.draw_texture_rect(_tex_fg, Rect2(x0, y_top, tw, th), false, Color(0.85, 0.86, 0.90, 0.90))
