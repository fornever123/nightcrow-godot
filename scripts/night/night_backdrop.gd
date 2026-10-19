extends Node2D
## 「月下堤岸」夜景（节点 4 建，第二轮节点 9 改成多层视差，设计见 docs/HANDOFF-试玩版.md §11、§13）。
##
## 图层（用户用 GPT 出的原图 → tools/art/make_night_layers_v2.py 拆层 + 无缝 → base64 文本）。
## 括号里是跟镜头移动的倍率（0 = 贴在屏幕上不动，1 = 跟地面一起走）：
##   月亮 moon + 月晕 halo（0，超远景）  星空银河 sky（0.01）  云 clouds（0.05，另加风飘）
##   海面 sea（逐行视差：桥脚 0.42 → 步道后沿 1.0；步道下面 1.0 → 屏幕底 1.25；月光带固定在月亮下方）
##   雪山 mountains（0.12）  城堡小镇 castle（0.3）  雾（0.36，程序噪声）  石桥 bridge（0.42）
##   近景步道 near（1.0，沿用 v1）
## 另外全是程序特效：桥和步道在水里的倒影、萤火虫、花瓣、流星、灯笼暖光、桥灯呼吸。
## 所有东西 z_index 为负，画在角色和敌人后面（花瓣和少量萤火在前面，很淡）。
##
## 坐标（第三轮节点 15 起）：镜头缩放 zoom = 0.5（世界 2 单位 = 屏幕 1 像素，角色在屏幕上缩小一半）。
## 远景各层都放在一个“屏幕容器” _scr 里：容器缩放 = 1/zoom，所以容器里 1 单位 = 屏幕 1 像素，
## 原来按“屏幕 1280×720”写的摆放公式基本不用改；横向用“虚拟镜头” screen_left() = 镜头中心 x × zoom − 640。
## 近景步道、灯笼光也在容器里，但按世界比例显示（缩放 zoom），位置由世界坐标换算（to_v）。
## 各层的滚动都对齐到 SNAP（2 屏幕像素 = 背景像素块大小），配合 night_pixel.gdshader 像素化后移动不闪。
## 步道顶面 = floor_y（世界坐标）。

const DIR := "res://assets/scenery/moon_embankment/"
const FOG_SCROLL := 0.36
const NEAR_STAND_ROW := 139.0     ## 近景图块里“脚踩的那一行”（石板顶面中间）
const LANTERN_IN_TILE := Vector2(639.0, 61.0)   ## 近景图块里灯笼火光的位置
const MARGIN := 48.0
const LANTERN_REACH := 330.0      ## 灯笼暖光照到角色身上的半径
const SNAP := 2.0                 ## 滚动对齐的步长（屏幕像素）= 背景像素块大小
const PIXEL_Z := -75              ## 像素化 + 退后调色这一层：它下面的全部夜景层被处理，上面的（地形、角色）不受影响
const LAYERS := ["sky", "halo", "moon", "clouds", "sea", "mountains", "castle", "bridge", "near"]

static var _cache: Dictionary = {}

var camera: Camera2D
var floor_y: float = 580.0
var meta: Dictionary = {}
var ok: bool = false

var tex: Dictionary = {}          ## 图层名 → Texture2D
var near_tex: Texture2D
var _spr: Dictionary = {}         ## 图层名 → Sprite2D
var _bridge_reflect: Sprite2D
var _fog: Sprite2D
var _near_reflect: Sprite2D
var _glow_back: Node2D           ## 加色混合：灯笼光、萤火（在角色后面）
var _front: Node2D               ## 普通混合：花瓣、少量萤火（在角色前面）
var _meteors: Node2D             ## 流星（在月亮和云后面）
var _mid_glow: Node2D            ## 桥灯（桥上面）
var _sea_mat: ShaderMaterial
var _scr: Node2D                 ## 屏幕容器（见文件头）
var _pix: Node2D                 ## 像素化 + 退后调色（全屏，读屏幕纹理）
var pixel_mat: ShaderMaterial
var z: float = 1.0               ## 镜头缩放
var _near_shift: float = 0.0     ## 近景对齐像素格后的偏移（世界单位）：灯笼光跟着一起挪
var _time: float = 0.0
var _rng := RandomNumberGenerator.new()
var _meteor := {"t": -1.0, "next": 4.0, "from": Vector2.ZERO, "dir": Vector2.ZERO, "len": 0.0}
var _petals: Array = []

## 灯笼在世界里的火光位置（给环境光用）：返回离 x 最近的那盏
func nearest_lantern(x: float) -> Vector2:
	if not ok:
		return Vector2(INF, INF)
	var p := float(meta.near.period)
	var k := roundf((x - LANTERN_IN_TILE.x) / p)
	return Vector2(k * p + LANTERN_IN_TILE.x, near_top() + LANTERN_IN_TILE.y)


## 灯笼火苗的跳动（地上暖光圈、角色身上的暖光都用它，保持同步）
func lantern_flicker(lx: float) -> float:
	return 0.85 + 0.1 * sin(_time * 9.0 + lx) + 0.05 * sin(_time * 23.0)


## 某点受到的灯笼暖光：x = 强度 0..1（含火苗跳动），(y, z) = 从该点指向灯笼的单位方向（屏幕坐标）
func lantern_light(p: Vector2) -> Vector3:
	var lan := nearest_lantern(p.x)
	if not is_finite(lan.x):
		return Vector3.ZERO
	var d := lan - p
	var dist := d.length()
	var w := clampf(1.0 - dist / LANTERN_REACH, 0.0, 1.0)
	w = w * w * (3.0 - 2.0 * w) * lantern_flicker(lan.x)
	var dir := d / maxf(dist, 0.001)
	return Vector3(w, dir.x, dir.y)


func near_top() -> float:
	return floor_y - NEAR_STAND_ROW


func horizon_y() -> float:
	return float(meta.get("far", {}).get("horizonY", 417))


## 各层跟镜头移动的倍率（layers.json 里有就用它）
func _scroll(layer: String, def: float) -> float:
	return float(meta.get(layer, {}).get("scroll", def))


static func load_b64_texture(path: String) -> Texture2D:
	if _cache.has(path):
		return _cache[path]
	if not FileAccess.file_exists(path):
		push_warning("夜景图层缺失：" + path)
		return null
	var raw := Marshalls.base64_to_raw(FileAccess.get_file_as_string(path).strip_edges())
	var img := Image.new()
	if img.load_webp_from_buffer(raw) != OK:
		push_warning("夜景图层解码失败：" + path)
		return null
	var t := ImageTexture.create_from_image(img)
	_cache[path] = t
	return t


func _ready() -> void:
	_rng.seed = 20261018
	var mf := FileAccess.get_file_as_string(DIR + "layers.json")
	var parsed: Variant = JSON.parse_string(mf) if mf != "" else null
	if parsed is Dictionary:
		meta = parsed
	ok = true
	for n in LAYERS:
		var t := load_b64_texture(DIR + n + ".webp.b64")
		ok = ok and t != null and meta.has(n)
		tex[n] = t
	if not ok:
		return
	near_tex = tex.near
	# 镜头在本帧移动后再摆夜景（否则冲刺时远景会晚一帧，屏幕边露出底色）
	process_priority = 100
	_scr = Node2D.new()
	_scr.name = "Screen"
	add_child(_scr)
	var sky := _sprite(tex.sky, -100, true)
	sky.texture_repeat = CanvasItem.TEXTURE_REPEAT_MIRROR   # 0.01 倍，走十几万像素才会看到镜像处
	sky.material = _shader_mat(preload("res://assets/shaders/night_sky.gdshader"), {})
	_spr.sky = sky
	_meteors = Node2D.new()
	_meteors.z_index = -99
	_meteors.material = _add_mat()
	_meteors.draw.connect(_draw_meteors)
	_scr.add_child(_meteors)
	var halo := _sprite(tex.halo, -98, false)
	halo.centered = true
	halo.material = _add_mat()
	_spr.halo = halo
	var moon := _sprite(tex.moon, -97, false)
	moon.centered = true
	_spr.moon = moon
	_spr.clouds = _sprite(tex.clouds, -96, true)
	var sea := _sprite(tex.sea, -95, true)
	_sea_mat = _shader_mat(preload("res://assets/shaders/night_sea.gdshader"), {
		"margin": MARGIN, "top_y": float(meta.sea.top), "band_x": float(meta.moon.center[0]) - 50.0,
		"bridge_f": _scroll("bridge", 0.42)})
	sea.material = _sea_mat
	_spr.sea = sea
	_bridge_reflect = _sprite(tex.bridge, -94, true)
	_bridge_reflect.flip_v = true
	_bridge_reflect.material = _shader_mat(preload("res://assets/shaders/night_reflect.gdshader"),
			{"strength": 0.36, "ripple": 2.2, "tint": Color(0.2, 0.32, 0.6)})
	_spr.mountains = _sprite(tex.mountains, -93, true)
	_spr.castle = _sprite(tex.castle, -92, true)
	_fog = _sprite(_make_fog_texture(), -91, true)
	_fog.material = _shader_mat(preload("res://assets/shaders/night_fog.gdshader"), {})
	_spr.bridge = _sprite(tex.bridge, -90, true)
	_mid_glow = Node2D.new()
	_mid_glow.z_index = -89
	_mid_glow.material = _add_mat()
	_mid_glow.draw.connect(_draw_mid_glow)
	_scr.add_child(_mid_glow)
	_near_reflect = _sprite(near_tex, -88, true)
	_near_reflect.flip_v = true
	_near_reflect.material = _shader_mat(preload("res://assets/shaders/night_reflect.gdshader"),
			{"strength": 0.72, "ripple": 3.0, "tint": Color(0.1, 0.16, 0.34), "tint_amt": 0.38})
	_spr.near = _sprite(near_tex, -87, true)
	_glow_back = Node2D.new()
	_glow_back.z_index = -80
	_glow_back.material = _add_mat()
	_glow_back.draw.connect(_draw_glow_back)
	_scr.add_child(_glow_back)
	_front = Node2D.new()
	_front.z_index = 15
	_front.draw.connect(_draw_front)
	_scr.add_child(_front)
	for i in 9:
		_petals.append(_new_petal(true))
	_pix = Node2D.new()
	_pix.name = "Pixelate"
	_pix.z_index = PIXEL_Z
	pixel_mat = _shader_mat(preload("res://assets/shaders/night_pixel.gdshader"), {})
	_pix.material = pixel_mat
	_pix.draw.connect(func(): _pix.draw_rect(Rect2(screen_left() - 8.0, -8.0, 1296.0, 736.0), Color.WHITE))
	_scr.add_child(_pix)
	_sync_screen()


func _sprite(t: Texture2D, z: int, repeat: bool) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = t
	s.centered = false
	s.z_index = z
	s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	if repeat:
		s.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		s.region_enabled = true
	_scr.add_child(s)
	return s


func _shader_mat(sh: Shader, params: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = sh
	for k in params:
		m.set_shader_parameter(k, params[k])
	return m


func _add_mat() -> CanvasItemMaterial:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return m


func _make_fog_texture() -> Texture2D:
	var n := FastNoiseLite.new()
	n.seed = 7
	n.frequency = 0.012
	n.fractal_octaves = 4
	var img := n.get_seamless_image(768, 96, false, false, 0.2, true)
	return ImageTexture.create_from_image(img)


## 虚拟镜头左边缘（容器坐标，= 屏幕像素）：镜头中心 x × zoom − 640
func screen_left() -> float:
	if camera == null:
		return 0.0
	return camera.get_screen_center_position().x * _zoom() - 640.0


## 容器坐标里屏幕顶边永远是 0（容器自己跟着镜头竖直移动）
func _top_y() -> float:
	return 0.0


func _zoom() -> float:
	return camera.zoom.x if camera and camera.zoom.x > 0.0 else 1.0


## 让容器盖住当前屏幕：容器 1 单位 = 屏幕 1 像素，竖直方向屏幕顶边 = 容器 y 0
func _sync_screen() -> void:
	z = _zoom()
	var cy := camera.get_screen_center_position().y if camera else 360.0
	_scr.scale = Vector2.ONE / z
	_scr.position = Vector2(0.0, cy - 360.0 / z)


## 世界坐标 → 容器坐标
func to_v(p: Vector2) -> Vector2:
	return Vector2(p.x * z, (p.y - _scr.position.y) * z)


## 横向重复的一层：屏幕第 0 列显示图块的 cl×倍率 + 偏移 列（对齐到 SNAP）；精灵本身从 cl−MARGIN 开始画
func _place_strip(s: Sprite2D, layer: String, factor: float, extra: float, y: float) -> void:
	var m: Dictionary = meta[layer]
	var cl := screen_left()
	s.position = Vector2(cl - MARGIN, y)
	var off := snappedf(cl * factor + extra, SNAP)
	s.region_rect = Rect2(fposmod(off - MARGIN, float(m.period) * 2.0), 0, 1280.0 + MARGIN * 2.0, float(m.size[1]))


func _process(delta: float) -> void:
	if not ok:
		return
	_time += delta
	_sync_screen()
	var cl := screen_left()
	var top_y := _top_y()
	var w := 1280.0 + MARGIN * 2.0
	# 星空：0.01 倍，镜像重复
	var sky: Sprite2D = _spr.sky
	sky.position = Vector2(cl - MARGIN, top_y)
	sky.region_rect = Rect2(snappedf(cl * _scroll("sky", 0.01), SNAP) - MARGIN, 0, w, float(meta.sky.size[1]))
	# 月亮 + 月晕：贴在屏幕上
	var mc := Vector2(float(meta.moon.center[0]), float(meta.moon.center[1]))
	(_spr.moon as Sprite2D).position = Vector2(cl, top_y) + mc
	(_spr.halo as Sprite2D).position = Vector2(cl, top_y) + mc
	# 云：0.05 倍 + 风飘（向左）
	_place_strip(_spr.clouds, "clouds", _scroll("clouds", 0.05), _time * float(meta.clouds.get("drift", 3.0)), top_y)
	# 海面：逐行视差在着色器里算
	var sea: Sprite2D = _spr.sea
	sea.position = Vector2(cl - MARGIN, top_y + float(meta.sea.top))
	sea.region_rect = Rect2(0, 0, w, float(meta.sea.size[1]))
	var nh := float(meta.near.size[1])
	_sea_mat.set_shader_parameter("cam_x", cl)
	_sea_mat.set_shader_parameter("bridge_y", float(meta.bridge.top) + float(meta.bridge.size[1]))
	_sea_mat.set_shader_parameter("back_y", to_v(Vector2(0, floor_y - 8.0)).y)
	_sea_mat.set_shader_parameter("front_y", roundf(to_v(Vector2(0, near_top())).y) + nh * z)
	# 雪山 / 城堡小镇 / 石桥
	_place_strip(_spr.mountains, "mountains", _scroll("mountains", 0.12), 0.0, top_y + float(meta.mountains.top))
	_place_strip(_spr.castle, "castle", _scroll("castle", 0.3), 0.0, top_y + float(meta.castle.top))
	var bridge: Sprite2D = _spr.bridge
	_place_strip(bridge, "bridge", _scroll("bridge", 0.42), 0.0, top_y + float(meta.bridge.top))
	# 桥的倒影：整座桥翻到水里
	var bh := float(meta.bridge.size[1])
	_bridge_reflect.position = Vector2(cl - MARGIN, bridge.position.y + bh - 2.0)
	_bridge_reflect.region_rect = bridge.region_rect
	# 雾：在地平线上慢慢飘
	_fog.position = Vector2(cl - MARGIN, top_y + horizon_y() - 70.0)
	_fog.region_rect = Rect2(fposmod(snappedf(cl * FOG_SCROLL + _time * 9.0, SNAP), 768.0), 0, w, 96)
	# 近景：和地面一起走，按世界比例显示（缩放 zoom）；左边缘的世界 x 对齐到 SNAP 屏幕像素
	var near: Sprite2D = _spr.near
	var period := float(meta.near.period)
	var wl := (cl - MARGIN) / z
	var wl_s := snappedf(wl, SNAP / z)
	_near_shift = wl_s - wl
	var ny := roundf(to_v(Vector2(0, near_top())).y)
	near.scale = Vector2(z, z)
	near.position = Vector2(cl - MARGIN, ny)
	near.region_rect = Rect2(fposmod(wl_s, period * 4.0), 0, w / z, nh)
	# 近景倒影：石墙在水里的影子（只取墙面那一段，翻下来）
	var wall_rows := nh - 131.0
	_near_reflect.scale = Vector2(z, z)
	_near_reflect.position = Vector2(cl - MARGIN, ny + (nh - 1.0) * z)
	_near_reflect.region_rect = Rect2(near.region_rect.position.x, 131.0, w / z, wall_rows)
	_update_meteor(delta)
	_update_petals(delta)
	_meteors.queue_redraw()
	_mid_glow.queue_redraw()
	_pix.queue_redraw()
	_glow_back.queue_redraw()
	_front.queue_redraw()


# ---------------------------------------------------------------- 程序特效

func _update_meteor(delta: float) -> void:
	if _meteor.t < 0.0:
		_meteor.next -= delta
		if _meteor.next <= 0.0:
			_meteor.t = 0.0
			_meteor.from = Vector2(_rng.randf_range(80.0, 1000.0), _rng.randf_range(30.0, 160.0))
			var ang := deg_to_rad(_rng.randf_range(18.0, 34.0))
			var side := 1.0 if _rng.randf() < 0.6 else -1.0
			_meteor.dir = Vector2(cos(ang) * side, sin(ang))
			_meteor.len = _rng.randf_range(160.0, 280.0)
	else:
		_meteor.t += delta
		if _meteor.t > 0.75:
			_meteor.t = -1.0
			_meteor.next = _rng.randf_range(5.0, 11.0)


func _draw_meteors() -> void:
	# 画在屏幕坐标系：节点跟着镜头左上角
	var origin := Vector2(screen_left(), _top_y())
	if _meteor.t >= 0.0:
		var k: float = _meteor.t / 0.75
		var head: Vector2 = _meteor.from + _meteor.dir * _meteor.len * 1.6 * k
		var tail_len: float = _meteor.len * sin(PI * minf(k * 1.3, 1.0))
		var fade := sin(PI * k)
		for i in 6:
			var a := float(i) / 6.0
			var p0: Vector2 = head - _meteor.dir * tail_len * a
			var p1: Vector2 = head - _meteor.dir * tail_len * (a + 1.0 / 6.0)
			_meteors.draw_line(origin + p0, origin + p1, Color(0.75, 0.85, 1.0, 0.75 * fade * (1.0 - a)), 2.2 - a * 1.6)
		_meteors.draw_circle(origin + head, 2.6, Color(1, 1, 1, 0.9 * fade))


func _draw_mid_glow() -> void:
	# 桥灯（跟桥一起 0.42 倍视差）微微呼吸
	var origin := Vector2(screen_left(), _top_y())
	var bm: Dictionary = meta.bridge
	var bp := float(bm.period)
	var y := origin.y + float(bm.lampY)
	var base := snappedf(screen_left() * _scroll("bridge", 0.42), SNAP)
	var k0 := floorf((base - 40.0) / bp)
	for t in 5:
		for lx in bm.lamps:
			var wx: float = (k0 + float(t)) * bp + float(lx)
			var sx := wx - base
			if sx < -30.0 or sx > 1310.0:
				continue
			var fl := 0.75 + 0.25 * sin(_time * 2.3 + wx * 0.37)
			_mid_glow.draw_circle(origin + Vector2(sx, y), 9.0, Color(1.0, 0.7, 0.35, 0.10 * fl))
			_mid_glow.draw_circle(origin + Vector2(sx, y), 4.0, Color(1.0, 0.8, 0.5, 0.22 * fl))


## 灯笼光、萤火：位置按世界坐标算，画在容器坐标里（to_v）；灯笼光跟近景一起按 zoom 缩小
func _draw_glow_back() -> void:
	var cl := screen_left() / z          # 屏幕左边缘的世界 x
	var span := 1280.0 / z
	var np := float(meta.near.period)
	# 灯笼：火光 + 地上的一圈暖光（随火苗轻微跳动）
	var k0 := floorf((cl - 300.0 - LANTERN_IN_TILE.x) / np)
	var nt := roundf(to_v(Vector2(0, near_top())).y) / z
	for t in int(ceilf(span / np)) + 3:
		var lx := (k0 + float(t)) * np + LANTERN_IN_TILE.x
		if lx < cl - 400.0 or lx > cl + span + 400.0:
			continue
		var c := Vector2((lx - _near_shift) * z, (nt + LANTERN_IN_TILE.y) * z)
		var fl := lantern_flicker(lx)
		for i in 6:
			var r := 18.0 + float(i) * 22.0
			_glow_back.draw_circle(c, r * fl * z, Color(1.0, 0.62, 0.3, 0.045 * fl))
		_glow_back.draw_circle(c, 9.0 * z, Color(1.0, 0.85, 0.55, 0.35 * fl))
		_draw_ground_pool(to_v(Vector2(lx - _near_shift, floor_y - 2.0)), 190.0 * fl * z, 16.0 * z, Color(1.0, 0.6, 0.28, 0.07 * fl))
	# 萤火虫：按 220 世界单位一格程序生成，同一格每次都一样（往回走不会变）
	var cell := 220.0
	var c0 := floorf((cl - 100.0) / cell)
	for i in int(ceilf(span / cell)) + 2:
		var ci := c0 + float(i)
		var h := _hash(ci)
		if h > 0.72:
			continue
		var bx := ci * cell + h * cell
		var by := floor_y - 60.0 - _hash(ci + 17.3) * 300.0
		var p := to_v(Vector2(bx + sin(_time * 0.7 + h * 20.0) * 26.0, by + sin(_time * 1.1 + h * 31.0) * 14.0))
		var blink := clampf(0.5 + 0.5 * sin(_time * (1.6 + h) + h * 40.0), 0.0, 1.0)
		blink = blink * blink
		_glow_back.draw_circle(p, 7.0, Color(0.75, 1.0, 0.55, 0.08 * blink))
		_glow_back.draw_circle(p, 1.6, Color(0.85, 1.0, 0.7, 0.75 * blink))


func _draw_ground_pool(c: Vector2, rx: float, ry: float, col: Color) -> void:
	for i in 4:
		var k := 1.0 - float(i) * 0.22
		var pts := PackedVector2Array()
		for j in 24:
			var a := TAU * float(j) / 24.0
			pts.append(c + Vector2(cos(a) * rx * k, sin(a) * ry * k))
		_glow_back.draw_colored_polygon(pts, col)


func _hash(x: float) -> float:
	return fposmod(sin(x * 127.1 + 311.7) * 43758.5453, 1.0)


func _new_petal(anywhere: bool) -> Dictionary:
	return {
		"x": _rng.randf_range(0.0, 1280.0) if anywhere else _rng.randf_range(1290.0, 1400.0),
		"y": _rng.randf_range(-40.0, 560.0) if anywhere else _rng.randf_range(-60.0, 300.0),
		"vx": -_rng.randf_range(28.0, 60.0), "vy": _rng.randf_range(16.0, 34.0),
		"ph": _rng.randf_range(0.0, TAU), "spin": _rng.randf_range(1.5, 3.5),
		"size": _rng.randf_range(2.6, 4.2), "par": _rng.randf_range(0.15, 0.45),
	}


func _update_petals(delta: float) -> void:
	for i in _petals.size():
		var p: Dictionary = _petals[i]
		p.x += (p.vx + sin(_time * 1.3 + p.ph) * 14.0) * delta
		p.y += (p.vy + sin(_time * 2.1 + p.ph) * 8.0) * delta
		if p.x < -40.0 or p.y > 640.0:
			_petals[i] = _new_petal(false)


func _draw_front() -> void:
	var cl := screen_left()
	var top := _top_y()
	for p in _petals:
		# 花瓣画在屏幕坐标里，再加一点视差，镜头移动时有前后感
		var sx: float = fposmod(float(p.x) - cl * float(p.par), 1320.0) - 20.0
		var c := Vector2(cl + sx, top + float(p.y))
		var a: float = _time * float(p.spin) + float(p.ph)
		var s: float = p.size
		var d := Vector2(cos(a), sin(a))
		var flat := absf(sin(a * 0.7)) * 0.7 + 0.3
		var pts := PackedVector2Array([c + d * s * 1.4, c + Vector2(-d.y, d.x) * s * flat, c - d * s * 0.9, c - Vector2(-d.y, d.x) * s * flat])
		_front.draw_colored_polygon(pts, Color(0.96, 0.9, 0.95, 0.55))
