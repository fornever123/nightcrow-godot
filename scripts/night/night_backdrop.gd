extends Node2D
## 「月下堤岸」夜景（节点 4，设计见 docs/HANDOFF-试玩版.md §11）。
##
## 三层图（用户用 GPT 出的原图 → tools/art/make_night_layers.py 抠图 + 无缝 → base64 文本）：
##   远景 far  ：星空 + 月亮 + 海，固定在屏幕上（无限远），海面波光 / 星星闪烁用 shader 做
##   中景 mid  ：雪山 + 城堡 + 石桥，0.25 倍视差，横向无限重复
##   近景 near ：石砌堤岸步道 + 石灯笼 + 野花，跟地面一起走（1 倍），横向无限重复
## 另外全是程序特效：桥和步道在水里的倒影、地平线雾、萤火虫、花瓣、流星、灯笼暖光。
## 所有东西 z_index 为负，画在角色和敌人后面（花瓣和少量萤火在前面，很淡）。
##
## 坐标：屏幕 1280×720、镜头只横向移动（竖直固定在 360）。步道顶面 = floor_y。

const DIR := "res://assets/scenery/moon_embankment/"
const MID_SCROLL := 0.25
const FOG_SCROLL := 0.4
const NEAR_STAND_ROW := 139.0     ## 近景图块里“脚踩的那一行”（石板顶面中间）
const LANTERN_IN_TILE := Vector2(639.0, 61.0)   ## 近景图块里灯笼火光的位置
const BRIDGE_LAMPS := [65.0, 124.0, 184.0, 245.0, 307.0, 368.0, 731.0, 791.0, 848.0, 908.0]
const BRIDGE_LAMP_Y := 203.0       ## 中景图块里桥灯的行
const MARGIN := 48.0

static var _cache: Dictionary = {}

var camera: Camera2D
var floor_y: float = 580.0
var meta: Dictionary = {}
var ok: bool = false

var far_tex: Texture2D
var mid_tex: Texture2D
var near_tex: Texture2D
var _far: Sprite2D
var _mid: Sprite2D
var _mid_reflect: Sprite2D
var _fog: Sprite2D
var _near: Sprite2D
var _near_reflect: Sprite2D
var _glow_back: Node2D           ## 加色混合：灯笼光、桥灯、萤火（在角色后面）
var _front: Node2D               ## 普通混合：花瓣、少量萤火（在角色前面）
var _sky: Node2D                 ## 流星（在中景后面）
var _mid_glow: Node2D            ## 桥灯（中景上面、雾下面）
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


func near_top() -> float:
	return floor_y - NEAR_STAND_ROW


func horizon_y() -> float:
	return float(meta.get("far", {}).get("horizonY", 417))


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
	var tex := ImageTexture.create_from_image(img)
	_cache[path] = tex
	return tex


func _ready() -> void:
	_rng.seed = 20261018
	var mf := FileAccess.get_file_as_string(DIR + "layers.json")
	var parsed: Variant = JSON.parse_string(mf) if mf != "" else null
	if parsed is Dictionary:
		meta = parsed
	far_tex = load_b64_texture(DIR + "far.webp.b64")
	mid_tex = load_b64_texture(DIR + "mid.webp.b64")
	near_tex = load_b64_texture(DIR + "near.webp.b64")
	ok = far_tex != null and mid_tex != null and near_tex != null and meta.has("near") and meta.has("mid")
	if not ok:
		return
	_far = _sprite(far_tex, -100, false)
	_far.material = _shader_mat(preload("res://assets/shaders/night_far.gdshader"), {"horizon": horizon_y() / 720.0})
	_sky = Node2D.new()
	_sky.z_index = -98
	_sky.material = _add_mat()
	_sky.draw.connect(_draw_sky)
	add_child(_sky)
	_mid_reflect = _sprite(mid_tex, -96, true)
	_mid_reflect.flip_v = true
	_mid_reflect.material = _shader_mat(preload("res://assets/shaders/night_reflect.gdshader"),
			{"strength": 0.32, "ripple": 2.2, "tint": Color(0.2, 0.32, 0.6)})
	_mid = _sprite(mid_tex, -94, true)
	_mid_glow = Node2D.new()
	_mid_glow.z_index = -93
	_mid_glow.material = _add_mat()
	_mid_glow.draw.connect(_draw_mid_glow)
	add_child(_mid_glow)
	_fog = _sprite(_make_fog_texture(), -92, true)
	_fog.material = _shader_mat(preload("res://assets/shaders/night_fog.gdshader"), {})
	_near_reflect = _sprite(near_tex, -91, true)
	_near_reflect.flip_v = true
	_near_reflect.material = _shader_mat(preload("res://assets/shaders/night_reflect.gdshader"),
			{"strength": 0.72, "ripple": 3.0, "tint": Color(0.1, 0.16, 0.34), "tint_amt": 0.38})
	_near = _sprite(near_tex, -90, true)
	_glow_back = Node2D.new()
	_glow_back.z_index = -80
	_glow_back.material = _add_mat()
	_glow_back.draw.connect(_draw_glow_back)
	add_child(_glow_back)
	_front = Node2D.new()
	_front.z_index = 15
	_front.draw.connect(_draw_front)
	add_child(_front)
	for i in 9:
		_petals.append(_new_petal(true))


func _sprite(tex: Texture2D, z: int, repeat: bool) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = false
	s.z_index = z
	s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	if repeat:
		s.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		s.region_enabled = true
	add_child(s)
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


func screen_left() -> float:
	if camera == null:
		return 0.0
	return camera.get_screen_center_position().x - 640.0


func _process(delta: float) -> void:
	if not ok:
		return
	_time += delta
	var cl := screen_left()
	var top_y := 0.0
	if camera != null:
		top_y = camera.get_screen_center_position().y - 360.0
	var w := 1280.0 + MARGIN * 2.0
	# 远景：贴着屏幕
	_far.position = Vector2(cl, top_y)
	# 中景：0.25 倍视差
	var mp := float(meta.mid.period)
	var mh := float(meta.mid.size[1])
	var mtop := float(meta.mid.top)
	_mid.position = Vector2(cl - MARGIN, top_y + mtop)
	# 屏幕第 0 列显示图块的 cl×0.25 列；精灵本身从 cl−MARGIN 开始画
	_mid.region_rect = Rect2(fposmod(cl * MID_SCROLL - MARGIN, mp), 0, w, mh)
	# 中景倒影：只取桥的下半截（最后 46 行）翻到水里
	var rh := 46.0
	_mid_reflect.position = Vector2(cl - MARGIN, top_y + mtop + mh - 3.0)
	_mid_reflect.region_rect = Rect2(_mid.region_rect.position.x, mh - rh, w, rh)
	# 雾：在地平线上慢慢飘
	_fog.position = Vector2(cl - MARGIN, top_y + horizon_y() - 70.0)
	_fog.region_rect = Rect2(fposmod(cl * FOG_SCROLL + _time * 9.0, 768.0), 0, w, 96)
	# 近景：和地面一起走
	var np := float(meta.near.period)
	var nh := float(meta.near.size[1])
	_near.position = Vector2(cl - MARGIN, near_top())
	_near.region_rect = Rect2(fposmod(cl - MARGIN, np), 0, w, nh)
	# 近景倒影：石墙在水里的影子（只取墙面那一段，翻下来）
	var wall_rows := nh - 131.0
	_near_reflect.position = Vector2(cl - MARGIN, near_top() + nh - 1.0)
	_near_reflect.region_rect = Rect2(_near.region_rect.position.x, 131.0, w, wall_rows)
	_update_meteor(delta)
	_update_petals(delta)
	_sky.queue_redraw()
	_mid_glow.queue_redraw()
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


func _draw_sky() -> void:
	# 画在屏幕坐标系：节点跟着镜头左上角
	var origin := Vector2(screen_left(), camera.get_screen_center_position().y - 360.0 if camera else 0.0)
	if _meteor.t >= 0.0:
		var k: float = _meteor.t / 0.75
		var head: Vector2 = _meteor.from + _meteor.dir * _meteor.len * 1.6 * k
		var tail_len: float = _meteor.len * sin(PI * minf(k * 1.3, 1.0))
		var fade := sin(PI * k)
		for i in 6:
			var a := float(i) / 6.0
			var p0: Vector2 = head - _meteor.dir * tail_len * a
			var p1: Vector2 = head - _meteor.dir * tail_len * (a + 1.0 / 6.0)
			_sky.draw_line(origin + p0, origin + p1, Color(0.75, 0.85, 1.0, 0.75 * fade * (1.0 - a)), 2.2 - a * 1.6)
		_sky.draw_circle(origin + head, 2.6, Color(1, 1, 1, 0.9 * fade))


func _draw_mid_glow() -> void:
	# 桥灯（中景，0.25 倍视差）微微呼吸
	var origin := Vector2(screen_left(), camera.get_screen_center_position().y - 360.0 if camera else 0.0)
	var mp := float(meta.mid.period)
	var y := origin.y + float(meta.mid.top) + BRIDGE_LAMP_Y
	var base := screen_left() * MID_SCROLL
	var k0 := floorf((base - 40.0) / mp)
	for t in 3:
		for lx in BRIDGE_LAMPS:
			var wx: float = (k0 + float(t)) * mp + float(lx)
			var sx := wx - base
			if sx < -30.0 or sx > 1310.0:
				continue
			var fl := 0.75 + 0.25 * sin(_time * 2.3 + float(lx) * 0.37)
			_mid_glow.draw_circle(origin + Vector2(sx, y), 9.0, Color(1.0, 0.7, 0.35, 0.10 * fl))
			_mid_glow.draw_circle(origin + Vector2(sx, y), 4.0, Color(1.0, 0.8, 0.5, 0.22 * fl))


func _draw_glow_back() -> void:
	var cl := screen_left()
	var np := float(meta.near.period)
	# 灯笼：火光 + 地上的一圈暖光（随火苗轻微跳动）
	var k0 := floorf((cl - 300.0 - LANTERN_IN_TILE.x) / np)
	for t in 4:
		var lx := (k0 + float(t)) * np + LANTERN_IN_TILE.x
		if lx < cl - 400.0 or lx > cl + 1680.0:
			continue
		var c := Vector2(lx, near_top() + LANTERN_IN_TILE.y)
		var fl := 0.85 + 0.1 * sin(_time * 9.0 + lx) + 0.05 * sin(_time * 23.0)
		for i in 6:
			var r := 18.0 + float(i) * 22.0
			_glow_back.draw_circle(c, r * fl, Color(1.0, 0.62, 0.3, 0.045 * fl))
		_glow_back.draw_circle(c, 9.0, Color(1.0, 0.85, 0.55, 0.35 * fl))
		_draw_ground_pool(Vector2(lx, floor_y - 2.0), 190.0 * fl, 16.0, Color(1.0, 0.6, 0.28, 0.07 * fl))
	# 萤火虫：按 220px 一格程序生成，同一格每次都一样（往回走不会变）
	var cell := 220.0
	var c0 := floorf((cl - 100.0) / cell)
	for i in 9:
		var ci := c0 + float(i)
		var h := _hash(ci)
		if h > 0.72:
			continue
		var bx := ci * cell + h * cell
		var by := floor_y - 60.0 - _hash(ci + 17.3) * 170.0
		var p := Vector2(bx + sin(_time * 0.7 + h * 20.0) * 26.0, by + sin(_time * 1.1 + h * 31.0) * 14.0)
		var blink := clampf(0.5 + 0.5 * sin(_time * (1.6 + h) + h * 40.0), 0.0, 1.0)
		blink = blink * blink
		_glow_back.draw_circle(p, 9.0, Color(0.75, 1.0, 0.55, 0.08 * blink))
		_glow_back.draw_circle(p, 2.2, Color(0.85, 1.0, 0.7, 0.75 * blink))


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
	var top := camera.get_screen_center_position().y - 360.0 if camera else 0.0
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
