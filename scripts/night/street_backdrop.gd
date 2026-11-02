extends Node2D
## 「雨夜河岸街」灰盒夜景（阶段一）：只求结构和层次看得懂，美术之后换成 GPT 照着这张图画的成图。
##
## 背景接口（night_trial 基类 / night_light 只用这些；原月下堤岸 night_backdrop.gd 已于 10-30 删除）：
##   camera / floor_y / ok / moon_screen() / lantern_light(p) / set_ult_mode(on)
##
## 图层（括号里是跟镜头移动的倍率，1 = 跟地面一起走）：
##   天空 + 月亮（贴屏幕）  远景城市剪影两层（0.12 / 0.3，带一座穹顶大教堂）  雾带
##   楼体（1.0，按布局 buildings 画：楼层线、窗、屋顶、钟面）  街面 / 河岸挡墙 / 河面
##   街灯和壁灯（1.0，暖光叠加）
##   前景（1.15 ~ 1.45，在角色前面）：底边河岸栏杆、顶边招牌长旗、近处路灯、入口石柱  + 雨丝
## 楼和平台的位置都来自 rain_street_layout.json（x 相对封印中心）。
##
## 阶段二成图（2026-10-28，标杆 v9.2）：天空、远景换成 assets/image/rain_street/ 的成图，全关镜像平铺；
## 布局里带 art 的那一段（钟楼广场左半）近景也换成成图，那段的灰盒楼、灯杆、前景件不再画。
## 河面全关用 rain_water.gdshader：实时倒影 + 往左流的波纹 + 灯光碎成横向波光（画在角色之后才照得到角色）。

const MOON := Vector2(1060.0, 110.0)    ## 灰盒天空的月亮在屏幕上的位置（设计分辨率像素）
const LAMP_REACH := 320.0
const RAIN_DROPS := 450                 ## 会撞到能站的面的雨滴（GPU 粒子，SDF 碰撞）。11-01 用户嫌雨太大：1000 → 450
const RAIN_THROUGH := 300               ## （11-01：700 → 300） 另一层更淡的雨，不碰撞，一直落进河里（雨是下在镜头和楼面之间的，楼面前也该有雨）
const RAIN_SPEED := 1350.0
const RAIN_WIND := -0.2                 ## 每往下落 1，往左飘多少
const WATER_Y := 665.0                  ## 水线（世界 y）：成图里河岸护墙的下沿

const SKY_TEX := "res://assets/image/rain_street/sky.png"
const FAR_TEX := "res://assets/image/rain_street/far_city.png"
const ART_SCALE := 2710.0 / 1672.0      ## 成图 1 像素 = 多少世界单位（和草图同一比例）
const SKY_SCREEN_H := 820.0             ## 天空成图在屏幕上的高度（像素），略大于 720 留出上下余量
const SKY_SCROLL := 0.02
const SKY_MOON := Vector2(770.0, 148.0) ## 月亮在天空成图里的像素位置
const SKY_SHIFT := 370.0               ## 天空图整体往右挪（屏幕像素）：月亮落到右上，和成图里“月光从右上来”一致
const FAR_SCROLL := 0.3
const FAR_TOP := -781.0                 ## 镜头在街面取景时远景图上沿的世界 y（天际线落在楼腰后面）

const C_SKY_TOP := Color(0.035, 0.05, 0.10)
const C_SKY_LOW := Color(0.20, 0.25, 0.34)
const C_FAR1 := Color(0.24, 0.28, 0.37)
const C_FAR2 := Color(0.16, 0.19, 0.26)
const C_FOG := Color(0.34, 0.40, 0.50)
const C_FACADE := Color(0.165, 0.18, 0.225)
const C_FACADE2 := Color(0.185, 0.20, 0.25)
const C_ROOF := Color(0.11, 0.12, 0.165)
const C_RIM := Color(0.70, 0.75, 0.85)
const C_WIN := Color(0.09, 0.10, 0.14)
const C_WIN_LIT := Color(1.0, 0.74, 0.40)
const C_RED := Color(0.85, 0.27, 0.21)
const C_ROAD := Color(0.24, 0.26, 0.31)
const C_WALL := Color(0.12, 0.13, 0.17)
const C_WATER := Color(0.06, 0.08, 0.12)
const C_LAMP := Color(1.0, 0.78, 0.45)
const C_FG := Color(0.03, 0.035, 0.055)
const C_FG_RIM := Color(0.45, 0.50, 0.60)

var camera: Camera2D
var floor_y: float = 580.0
var ok: bool = false
var layout: Dictionary = {}
var first_x: float = 0.0          ## 第 0 处封印中心
var spacing: float = 6400.0
var actors: Callable              ## 返回要躲开的角色（玩家 + 影），前景压到它们时变淡

var _time: float = 0.0
var _lamps: Array = []            ## 当前附近的灯：[{p: 火光世界坐标, kind}]
var _sky: Node2D
var _glow: Node2D
var _fg: Node2D
var _fg_alpha: Dictionary = {}    ## 前景件 → 当前不透明度（压到角色时平滑变淡）
var _rain: GPUParticles2D         ## 雨滴：撞到能站的面（2D SDF）就消失，并在那里溅起水花
var _splash: GPUParticles2D
var _rain_through: GPUParticles2D
var _occluders: Node2D            ## 只给 SDF 用的遮挡形状（平台、石台、街面），不投影、不碰撞
var _occ_key := ""
var _sky_tex: Texture2D
var _far_tex: Texture2D
var _far_fog: Color = C_FOG       ## 远景图底边的雾色：图下面接着铺这个颜色
var _art_tex: Dictionary = {}     ## 成图路径 → Texture2D
var _water: Node2D
var _ground: Node2D              ## 湿街面上的雨点涟漪（rain_ground.gdshader，加色）
var _water_mat: ShaderMaterial


func _ready() -> void:
	z_index = -90
	_sky_tex = _load_tex(SKY_TEX)
	_far_tex = _load_tex(FAR_TEX)
	if _far_tex != null:
		var img := _far_tex.get_image()
		var acc := Color(0, 0, 0, 0)
		for x in range(0, img.get_width(), 8):
			acc += img.get_pixel(x, img.get_height() - 1)
		_far_fog = Color(acc / acc.a, 1.0)
	_sky = Node2D.new()
	_sky.z_index = -100
	_sky.draw.connect(_draw_sky)
	add_child(_sky)
	_water = Node2D.new()
	_water.z_as_relative = false   # 不跟父节点（−90）叠加，否则实际 z 是 −84，比角色先画，倒影里就没有角色
	_water.z_index = 6             # 角色（0）和刀光（5）之后：倒影里要有它们
	_water_mat = ShaderMaterial.new()
	_water_mat.shader = load("res://assets/shaders/rain_water.gdshader")
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.012
	noise.fractal_octaves = 3
	var nt := NoiseTexture2D.new()
	nt.width = 256
	nt.height = 256
	nt.seamless = true
	nt.noise = noise
	_water_mat.set_shader_parameter("noise_tex", nt)
	_water_mat.set_shader_parameter("water_y", WATER_Y)
	_water.material = _water_mat
	_water.draw.connect(_draw_water)
	add_child(_water)
	_ground = Node2D.new()
	_ground.z_as_relative = false
	_ground.z_index = -5            # 背景（−90）和地形（−70）之后、角色（0）之前
	var gm := ShaderMaterial.new()
	gm.shader = load("res://assets/shaders/rain_ground.gdshader")
	gm.set_shader_parameter("street_y", floor_y)
	_ground.material = gm
	_ground.draw.connect(_draw_ground)
	add_child(_ground)
	_glow = Node2D.new()
	_glow.z_index = -60
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow.material = m
	_glow.draw.connect(_draw_glow)
	add_child(_glow)
	_fg = Node2D.new()
	_fg.z_as_relative = false   # 同水面：不叠加父节点的 −90，雨丝和前景件才真的在角色前面
	_fg.z_index = 20
	_fg.draw.connect(_draw_fg)
	add_child(_fg)
	_build_rain()
	ok = true


func set_ult_mode(on: bool) -> void:
	_fg.visible = not on
	_rain.visible = not on
	_splash.visible = not on
	_rain_through.visible = not on
	_ground.visible = not on


func moon_screen() -> Vector2:
	if _sky_tex == null:
		return MOON
	var k := SKY_SCREEN_H / float(_sky_tex.get_height())
	var tw := float(_sky_tex.get_width()) * k
	var off := fposmod(_center().x * SKY_SCROLL * _z() - SKY_SHIFT, 2.0 * tw)   # 镜像平铺：两张一个周期，月亮在正向那张里
	var x := -off + SKY_MOON.x * k
	if x < 640.0 - tw:
		x += 2.0 * tw
	return Vector2(x, _sky_top() + SKY_MOON.y * k)


func _sky_top() -> float:
	return -50.0 - (_center().y - 272.0) * _z() * 0.05


static func _load_tex(path: String) -> Texture2D:
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


func _art_texture(art: Dictionary) -> Texture2D:
	var path := String(art.get("near", ""))
	if not _art_tex.has(path):
		_art_tex[path] = _load_tex(path)
	return _art_tex[path]


## 某一段的成图在世界里的横向范围（没有成图返回空）
func _art_span(s: Dictionary) -> Vector2:
	var art: Dictionary = s.sec.get("art", {})
	if art.is_empty():
		return Vector2.INF
	var x0: float = float(s.center) + float(art.x0)
	return Vector2(x0, x0 + float(art.width))


static func _in_span(span: Vector2, x0: float, x1: float) -> bool:
	return span != Vector2.INF and x0 >= span.x and x1 <= span.y


## 某点受到的灯光：x = 强度 0..1（含火苗跳动），(y, z) = 从该点指向灯的单位方向
func lantern_light(p: Vector2) -> Vector3:
	var best := Vector3.ZERO
	for l in _lamps:
		var d: Vector2 = l.p - p
		var dist := d.length()
		var w := clampf(1.0 - dist / LAMP_REACH, 0.0, 1.0)
		w = w * w * (3.0 - 2.0 * w) * _flicker(l.p.x)
		if w > best.x:
			var dir := d / maxf(dist, 0.001)
			best = Vector3(w, dir.x, dir.y)
	return best


func _flicker(x: float) -> float:
	return 0.86 + 0.09 * sin(_time * 8.0 + x) + 0.05 * sin(_time * 21.0 + x * 0.3)


func _process(delta: float) -> void:
	_time += delta
	_collect_lamps()
	queue_redraw()
	_sky.queue_redraw()
	_glow.queue_redraw()
	_fg.queue_redraw()
	_water.queue_redraw()
	_ground.queue_redraw()
	_update_rain()


# ---------------------------------------------------------------- 镜头 / 布局

func _z() -> float:
	return camera.zoom.x if camera != null and camera.zoom.x > 0.0 else 1.0


func _center() -> Vector2:
	return camera.get_screen_center_position() if camera != null else Vector2(640, 360)


## 屏幕像素 → 世界坐标（贴屏幕的东西用）
func _scr(p: Vector2) -> Vector2:
	return _center() + (p - Vector2(640, 360)) / _z()


## 镜头附近的几处：[{center, sec}]
func _near_sections() -> Array:
	var out: Array = []
	var secs: Array = layout.get("sections", [])
	if secs.is_empty():
		return out
	var k := int(floor((_center().x - first_x) / spacing))
	for i in range(k - 1, k + 2):
		out.append({"center": first_x + float(i) * spacing, "sec": secs[posmod(i, secs.size())]})
	return out


func _collect_lamps() -> void:
	_lamps.clear()
	for s in _near_sections():
		var span := _art_span(s)
		for l in s.sec.get("lamps", []):
			var x: float = s.center + float(l[0])
			var y: float = float(l[1])
			var street := String(l[2]) == "street"
			var rise: float = float(l[3]) if l.size() > 3 else (132.0 if street else 112.0)   # 第 4 项：灯头离底座多高（成图里的灯按图量）
			_lamps.append({"p": Vector2(x, y - rise), "base": Vector2(x, y), "street": street, "art": _in_span(span, x, x)})


# ---------------------------------------------------------------- 天空 + 远景（贴屏幕 / 慢视差）

func _draw_sky() -> void:
	if camera == null:
		return
	if _sky_tex != null and _far_tex != null:
		_draw_art_sky()
		_draw_art_far()
		return
	var z := _z()
	var tl := _scr(Vector2(-4, -4))
	var br := _scr(Vector2(1284, 724))
	_sky.draw_polygon(PackedVector2Array([tl, Vector2(br.x, tl.y), br, Vector2(tl.x, br.y)]),
		PackedColorArray([C_SKY_TOP, C_SKY_TOP, C_SKY_LOW, C_SKY_LOW]))
	var mp := _scr(MOON)
	for i in 7:
		_sky.draw_circle(mp, (60.0 + float(i) * 34.0) / z, Color(0.62, 0.68, 0.80, 0.045))
	_sky.draw_circle(mp, 44.0 / z, Color(0.91, 0.92, 0.88))
	_sky.draw_circle(mp + Vector2(-10, -8) / z, 9.0 / z, Color(0.82, 0.84, 0.82))
	_draw_far(_sky, 0.12, 330.0, C_FAR1, 41, 300.0, true)
	_fog_band(_sky, 0.12, 330.0, 110.0, 0.55)
	_draw_far(_sky, 0.3, 430.0, C_FAR2, 17, 190.0, false)
	_fog_band(_sky, 0.3, 450.0, 120.0, 0.45)


## 一张图按“正、反、正、反……”镜像平铺：左右边缘天然接得上（成图本身左右不连续）
func _mirror_tiles(ci: CanvasItem, tex: Texture2D, x_first: float, tile_w: float, y: float, h: float, x_end: float, first_flipped: bool) -> void:
	var x := x_first
	var flip := first_flipped
	while x < x_end:
		if flip:
			ci.draw_set_transform(Vector2(x + tile_w, y), 0.0, Vector2(-1.0, 1.0))
		else:
			ci.draw_set_transform(Vector2(x, y), 0.0, Vector2.ONE)
		ci.draw_texture_rect(tex, Rect2(Vector2.ZERO, Vector2(tile_w, h)), false)
		x += tile_w
		flip = not flip
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 天空成图：几乎贴屏幕（SKY_SCROLL），按屏幕像素算好再换回世界坐标
func _draw_art_sky() -> void:
	var z := _z()
	var k := SKY_SCREEN_H / float(_sky_tex.get_height())
	var tw := float(_sky_tex.get_width()) * k
	var off := fposmod(_center().x * SKY_SCROLL * z - SKY_SHIFT, 2.0 * tw)
	var top := _scr(Vector2(0.0, _sky_top())).y
	var l := _scr(Vector2(-off, 0.0)).x
	_mirror_tiles(_sky, _sky_tex, l, tw / z, top, SKY_SCREEN_H / z, _scr(Vector2(1290.0, 0.0)).x, false)
	var bottom := top + SKY_SCREEN_H / z
	var br := _scr(Vector2(1284.0, 724.0))
	if br.y > bottom:   # 镜头往上看到头时，天空图下面接雾色
		_sky.draw_rect(Rect2(Vector2(_scr(Vector2(-4.0, 0.0)).x, bottom), Vector2(br.x - _scr(Vector2(-4.0, 0.0)).x, br.y - bottom)), _far_fog)


## 远景城市成图：和近景同一比例，FAR_SCROLL 视差，镜像平铺；图下面接同色的雾
func _draw_art_far() -> void:
	var c := _center()
	var tw := float(_far_tex.get_width()) * ART_SCALE
	var th := float(_far_tex.get_height()) * ART_SCALE
	var top := FAR_TOP + (c.y - 272.0) * (1.0 - FAR_SCROLL)
	var l := _scr(Vector2(-4.0, 0.0)).x
	var r := _scr(Vector2(1284.0, 0.0)).x
	var u0 := floorf((l - c.x * (1.0 - FAR_SCROLL)) / tw)   # 屏幕左边落在这一层第几张
	var x_first := c.x * (1.0 - FAR_SCROLL) + u0 * tw
	_mirror_tiles(_sky, _far_tex, x_first, tw, top, th, r, posmod(int(u0), 2) == 1)
	var bot := _scr(Vector2(0.0, 724.0)).y
	if bot > top + th:
		_sky.draw_rect(Rect2(l, top + th - 1.0, r - l, bot - top - th + 1.0), _far_fog)


## 远景剪影：u 是这一层自己的横坐标（镜头在 cx 时这一层平移了 cx × scroll）
func _draw_far(ci: CanvasItem, scroll: float, base_y: float, col: Color, seed_: int, h_max: float, cathedral: bool) -> void:
	var c := _center()
	var z := _z()
	var half := 660.0 / z
	var by := base_y + (c.y - 272.0) * (1.0 - scroll)   # 竖直方向：越远越跟着镜头走（看起来越不动）
	var u0 := c.x * scroll - half
	var cell := 90.0
	var k0 := int(floor(u0 / cell))
	var bottom := by + 900.0
	for k in range(k0, k0 + int(2.0 * half / cell) + 3):
		var hsh := _hash(k, seed_)
		var w := cell * (0.7 + 0.6 * _hash(k, seed_ + 3))
		var h := h_max * (0.25 + 0.55 * hsh)
		var u := float(k) * cell
		var x := c.x + (u - c.x * scroll)
		ci.draw_rect(Rect2(x, by - h, w, bottom - (by - h)), col)
		if hsh > 0.82:      # 少量尖顶 / 钟楼
			ci.draw_colored_polygon(PackedVector2Array([Vector2(x, by - h), Vector2(x + w * 0.5, by - h - h * 0.5), Vector2(x + w, by - h)]), col)
		elif hsh < 0.18:    # 少量小穹顶
			ci.draw_circle(Vector2(x + w * 0.5, by - h), w * 0.42, col)
	if cathedral:
		# 一座穹顶大教堂：每 9000 一座（镜头里最多一座）
		var period := 9000.0
		var uc := roundf((c.x * scroll) / period) * period + 2200.0
		var x := c.x + (uc - c.x * scroll)
		var dome := Vector2(x, by - 520.0)
		ci.draw_rect(Rect2(x - 420.0, by - 300.0, 840.0, 1200.0), col)
		ci.draw_rect(Rect2(x - 170.0, by - 520.0, 340.0, 240.0), col)
		ci.draw_circle(dome, 175.0, col)
		ci.draw_rect(Rect2(x - 26.0, dome.y - 260.0, 52.0, 90.0), col)
		ci.draw_colored_polygon(PackedVector2Array([Vector2(x - 20, dome.y - 260), Vector2(x, dome.y - 340), Vector2(x + 20, dome.y - 260)]), col)
		for sx in [-330.0, 330.0]:
			ci.draw_rect(Rect2(x + sx - 50.0, by - 420.0, 100.0, 140.0), col)
			ci.draw_circle(Vector2(x + sx, by - 420.0), 52.0, col)


func _fog_band(ci: CanvasItem, scroll: float, base_y: float, h: float, a: float) -> void:
	var c := _center()
	var by := base_y + (c.y - 272.0) * (1.0 - scroll)
	var l := _scr(Vector2(-4, 0)).x
	var r := _scr(Vector2(1284, 0)).x
	var clear := Color(C_FOG, 0.0)
	var fog := Color(C_FOG, a)
	ci.draw_polygon(PackedVector2Array([Vector2(l, by - h), Vector2(r, by - h), Vector2(r, by), Vector2(l, by)]),
		PackedColorArray([clear, clear, fog, fog]))
	ci.draw_rect(Rect2(l, by, r - l, 1600.0), fog)


# ---------------------------------------------------------------- 楼体 + 街面 + 河（跟地面一起走）

func _draw() -> void:
	if camera == null:
		return
	var floors: Dictionary = layout.get("floors", {})
	var lines: Array = [float(floors.get("f2", 300)), float(floors.get("f3", 20)), float(floors.get("roof", -260))]
	for s in _near_sections():
		var span := _art_span(s)
		var bi := 0
		for b in s.sec.get("buildings", []):
			var bx0: float = s.center + float(b[0])
			var bx1: float = s.center + float(b[1])
			if not _in_span(span, bx0, bx1):
				_draw_building(bx0, bx1, float(b[2]), lines, bi + int(s.center))
			bi += 1
	_draw_street()
	for s in _near_sections():   # 成图近景：楼、街面、河岸护墙都在图里，盖在灰盒街面上
		var art: Dictionary = s.sec.get("art", {})
		var tex := _art_texture(art) if not art.is_empty() else null
		if tex != null:
			var w := float(art.width)
			draw_texture_rect(tex, Rect2(float(s.center) + float(art.x0), float(art.y0), w, w * float(tex.get_height()) / float(tex.get_width())), false)
	_draw_lamp_posts()


func _draw_building(x0: float, x1: float, top: float, lines: Array, sd: int) -> void:
	var w := x1 - x0
	var tower := w < 700.0
	var col := C_FACADE if sd % 2 == 0 else C_FACADE2
	draw_rect(Rect2(x0, top, w, floor_y - top), col)
	var peak := top - (240.0 if tower else 130.0)
	draw_colored_polygon(PackedVector2Array([Vector2(x0 - 14, top), Vector2((x0 + x1) * 0.5, peak), Vector2(x1 + 14, top)]), C_ROOF)
	draw_line(Vector2((x0 + x1) * 0.5, peak), Vector2(x1 + 14, top), C_RIM, 4.0)       # 月光照屋顶右坡
	draw_line(Vector2(x1, top), Vector2(x1, floor_y), Color(C_RIM, 0.25), 3.0)          # 楼右边一线亮
	if not tower:
		var cx := x0 + w * (0.22 + 0.5 * _hash(sd, 5))
		draw_rect(Rect2(cx, peak + 40.0, 34.0, top - peak - 30.0), C_ROOF)
		draw_line(Vector2(cx + 34.0, peak + 40.0), Vector2(cx + 34.0, top), Color(C_RIM, 0.6), 3.0)
	# 楼层：腰线 + 每层一排尖拱窗（一层只开门，最安静）
	var storeys: Array = [floor_y]
	for y in lines:
		if float(y) > top + 40.0:
			storeys.append(float(y))
	storeys.append(top)
	for y in lines:
		if float(y) > top + 40.0:
			draw_rect(Rect2(x0, float(y) + 34.0, w, 8.0), C_ROOF)
	var n := maxi(2, int(w / 190.0))
	for si in storeys.size() - 1:
		var yb: float = storeys[si]
		var yt: float = storeys[si + 1]
		for k in n:
			var wx := x0 + (float(k) + 0.5) * w / float(n)
			if si == 0:
				if k % 2 == 0:
					draw_rect(Rect2(wx - 34.0, yb - 190.0, 68.0, 190.0), C_WIN)
					draw_circle(Vector2(wx, yb - 190.0), 34.0, C_WIN)
				continue
			var wt := yt + 70.0
			var wb := yb - 50.0
			if wb - wt < 60.0:
				continue
			var lit := _hash(sd * 7 + si, k) > 0.86
			var wc := C_WIN_LIT if lit else C_WIN
			draw_rect(Rect2(wx - 22.0, wt + 22.0, 44.0, wb - wt - 22.0), wc)
			draw_circle(Vector2(wx, wt + 22.0), 22.0, wc)
			if not lit:
				draw_line(Vector2(wx + 15.0, wt + 26.0), Vector2(wx + 15.0, wb - 4.0), Color(0.42, 0.47, 0.58, 0.5), 2.0)
	if tower:   # 钟楼：朱红钟面
		var cc := Vector2((x0 + x1) * 0.5, top + 150.0)
		draw_circle(cc, 74.0, C_ROOF)
		draw_circle(cc, 62.0, C_RED)
		draw_line(cc, cc + Vector2(0, -44), C_ROOF, 6.0)
		draw_line(cc, cc + Vector2(30, 10), C_ROOF, 6.0)


func _draw_street() -> void:
	var l := _scr(Vector2(-4, 0)).x
	var r := _scr(Vector2(1284, 0)).x
	var bot := _scr(Vector2(0, 724)).y
	var fy := floor_y
	draw_rect(Rect2(l, fy, r - l, 26.0), C_ROAD)
	draw_rect(Rect2(l, fy, r - l, 4.0), Color(0.62, 0.66, 0.76))
	draw_rect(Rect2(l, fy + 26.0, r - l, WATER_Y - fy - 26.0), C_WALL)
	draw_rect(Rect2(l, fy + 26.0, r - l, 4.0), Color(0.30, 0.32, 0.38))
	if bot > WATER_Y:   # 着色器没加载时的底色；正常情况由 _water 盖住
		draw_rect(Rect2(l, WATER_Y, r - l, bot - WATER_Y), C_WATER)


## 湿街面那一条：涟漪全由 rain_ground.gdshader 算
func _draw_ground() -> void:
	if camera == null:
		return
	var l := _scr(Vector2(-4, 0)).x
	var r := _scr(Vector2(1284, 0)).x
	_ground.draw_rect(Rect2(l, floor_y - 2.0, r - l, 30.0), Color.WHITE)


## 河面：一块盖住水线以下屏幕的矩形，颜色全由 rain_water.gdshader 算（倒影、波纹、波光）
func _draw_water() -> void:
	if camera == null:
		return
	var l := _scr(Vector2(-4, 0)).x
	var r := _scr(Vector2(1284, 0)).x
	var bot := _scr(Vector2(0, 724)).y
	if bot > WATER_Y:
		_water.draw_rect(Rect2(l, WATER_Y, r - l, bot - WATER_Y), Color.WHITE)


func _draw_lamp_posts() -> void:
	for lp in _lamps:
		var b: Vector2 = lp.base
		if lp.art:   # 成图里画了灯杆
			continue
		if lp.street:
			draw_rect(Rect2(b.x - 5.0, b.y - 122.0, 10.0, 122.0), Color(0.06, 0.06, 0.08))
			draw_rect(Rect2(b.x - 16.0, b.y - 150.0, 32.0, 30.0), C_LAMP)
			draw_colored_polygon(PackedVector2Array([Vector2(b.x - 20, b.y - 150), Vector2(b.x + 20, b.y - 150), Vector2(b.x, b.y - 170)]), Color(0.06, 0.06, 0.08))
		else:
			draw_line(Vector2(b.x - 30.0, b.y - 96.0), Vector2(b.x, b.y - 96.0), Color(0.06, 0.06, 0.08), 5.0)
			draw_rect(Rect2(b.x - 11.0, b.y - 126.0, 22.0, 30.0), C_LAMP)


func _draw_glow() -> void:
	for lp in _lamps:
		if lp.art:   # 成图里已经画了灯的光晕：再叠一圈圆盘会像贴在天上的纸片，只留角色身上的灯光（lantern_light）
			continue
		var f := _flicker(lp.p.x)
		for i in 6:
			_glow.draw_circle(lp.p, 30.0 + float(i) * 34.0, Color(1.0, 0.6, 0.28, 0.06 * f * (1.0 - float(i) / 6.0)))
		if lp.street:   # 路面上的光圈
			var pool := 1.0 if lp.base.y >= floor_y - 1.0 else 0.55   # 立在石台上的灯：光圈别比石台宽
			_glow.draw_set_transform(Vector2(lp.base.x, lp.base.y + 6.0), 0.0, Vector2(pool, 0.16 * pool))
			for i in 4:
				_glow.draw_circle(Vector2.ZERO, 70.0 + float(i) * 40.0, Color(1.0, 0.6, 0.28, 0.07 * f))
			_glow.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ---------------------------------------------------------------- 前景 + 雨（在角色前面）

func _draw_fg() -> void:
	if camera == null:
		return
	var rules: Dictionary = layout.get("foregroundRules", {})
	var z := _z()
	var c := _center()
	var u := 1.0 / z     # 屏幕 1 像素 = 世界 u 单位
	var hit_rects := _actor_rects()
	# 底边原来有一排河岸栏杆 + 铁链（视差 1.15），正好压在水面上挡住倒影，2026-10-29 去掉
	# 大件前景：按布局摆，各自的视差；压到角色时变淡
	for s in _near_sections():
		var span := _art_span(s)
		for item in s.sec.get("foreground", []):
			var kind := String(item[1])
			var k := float(rules.get(kind, {}).get("scroll", 1.3))
			var wx: float = float(s.center) + float(item[0])
			if _in_span(span, wx, wx):   # 成图段先不放灰盒前景件（朱红长旗和成图配色冲突），前景层之后按成图另做
				continue
			var x: float = c.x + (wx - c.x) * k
			var sx: float = 640.0 + (x - c.x) * z
			if sx < -300.0 or sx > 1580.0:
				continue
			var key := "%d:%s" % [int(wx), kind]
			var rect := _fg_rect(kind, sx)
			var want := 1.0
			for r in hit_rects:
				if rect.intersects(r):
					want = 0.25
			var a := move_toward(float(_fg_alpha.get(key, 1.0)), want, 0.08)
			_fg_alpha[key] = a
			_draw_fg_item(kind, sx, a)


## 前景件在屏幕上大概占的矩形（判断有没有压到角色）
func _fg_rect(kind: String, sx: float) -> Rect2:
	match kind:
		"pillar":
			return Rect2(sx - 72.0, 60.0, 144.0, 660.0)
		"lamp":
			return Rect2(sx - 26.0, 160.0, 52.0, 560.0)
		_:
			return Rect2(sx - 150.0, 0.0, 220.0, 170.0)


func _actor_rects() -> Array:
	var out: Array = []
	if not actors.is_valid():
		return out
	for a in actors.call():
		if a is Node2D and is_instance_valid(a):
			var p: Vector2 = (a as Node2D).get_global_transform_with_canvas().origin
			out.append(Rect2(p.x - 40.0, p.y - 120.0, 80.0, 150.0))
	return out


## 前景件按屏幕像素画（sx = 中心的屏幕 x）
func _draw_fg_item(kind: String, sx: float, a: float) -> void:
	var col := Color(C_FG, a)
	var rim := Color(C_FG_RIM, 0.7 * a)
	var P := func(x: float, y: float) -> Vector2: return _scr(Vector2(x, y))
	var R := func(x: float, y: float, w: float, h: float) -> Rect2: return Rect2(_scr(Vector2(x, y)), Vector2(w, h) / _z())
	var u := 1.0 / _z()
	match kind:
		"pillar":
			_fg.draw_rect(R.call(sx - 70, 630, 140, 90), col)
			_fg.draw_rect(R.call(sx - 46, 210, 92, 420), col)
			_fg.draw_rect(R.call(sx - 62, 180, 124, 34), col)
			_fg.draw_colored_polygon(PackedVector2Array([P.call(sx - 50, 180), P.call(sx - 30, 120), P.call(sx + 10, 104), P.call(sx + 52, 130), P.call(sx + 64, 180)]), col)
			_fg.draw_colored_polygon(PackedVector2Array([P.call(sx + 10, 104), P.call(sx + 40, 70), P.call(sx + 52, 96), P.call(sx + 30, 112)]), col)
			_fg.draw_colored_polygon(PackedVector2Array([P.call(sx - 30, 120), P.call(sx - 70, 60), P.call(sx - 20, 100)]), col)
			_fg.draw_line(P.call(sx + 46, 214), P.call(sx + 46, 630), rim, 2.0 * u)
			_fg.draw_polyline(PackedVector2Array([P.call(sx + 10, 104), P.call(sx + 52, 130), P.call(sx + 64, 180)]), rim, 2.0 * u)
		"lamp":
			_fg.draw_rect(R.call(sx - 10, 250, 20, 470), col)
			_fg.draw_rect(R.call(sx - 22, 190, 44, 62), col)
			_fg.draw_colored_polygon(PackedVector2Array([P.call(sx - 26, 190), P.call(sx + 26, 190), P.call(sx, 160)]), col)
			_fg.draw_rect(R.call(sx - 14, 200, 28, 44), Color(1.0, 0.75, 0.45, a))
			_fg.draw_line(P.call(sx + 10, 252), P.call(sx + 10, 720), rim, 2.0 * u)
		_:   # sign：铁艺招牌 + 朱红长旗，从顶边垂下
			_fg.draw_line(P.call(sx - 90, 0), P.call(sx - 90, 60), col, 8.0 * u)
			_fg.draw_line(P.call(sx - 90, 40), P.call(sx + 60, 40), col, 7.0 * u)
			_fg.draw_line(P.call(sx - 90, 90), P.call(sx - 20, 40), col, 5.0 * u)
			_fg.draw_line(P.call(sx + 20, 40), P.call(sx + 20, 70), col, 3.0 * u)
			_fg.draw_line(P.call(sx + 50, 40), P.call(sx + 50, 70), col, 3.0 * u)
			_fg.draw_rect(R.call(sx + 5, 70, 60, 80), col)
			_fg.draw_line(P.call(sx + 65, 74), P.call(sx + 65, 148), rim, 2.0 * u)
			_fg.draw_colored_polygon(PackedVector2Array([P.call(sx - 150, 0), P.call(sx - 110, 0), P.call(sx - 110, 170), P.call(sx - 130, 150), P.call(sx - 150, 170)]), Color(0.30, 0.07, 0.08, a))


# ---------------------------------------------------------------- 雨（Forward+：GPU 粒子 + 2D SDF 碰撞）
# 雨滴从镜头上方落下，撞到能站的面（阳台、屋檐、雨棚、吊臂、桥面、石台、街面）就消失，并在撞到的地方溅起几颗水珠；
# 阳台、雨棚底下自然不进雨。遮挡形状按布局里的平台实时生成（只开 sdf_collision，不投光影、不参与物理）。

func _build_rain() -> void:
	var drop := GradientTexture2D.new()       # 细长雨丝：上淡下实
	drop.width = 3
	drop.height = 34
	drop.fill_from = Vector2(0.5, 0.0)
	drop.fill_to = Vector2(0.5, 1.0)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	g.set_color(1, Color(1, 1, 1, 1))
	drop.gradient = g
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(1300.0, 40.0, 1.0)
	pm.direction = Vector3(RAIN_WIND, 1.0, 0.0)
	pm.spread = 2.0
	pm.initial_velocity_min = RAIN_SPEED * 0.85
	pm.initial_velocity_max = RAIN_SPEED * 1.1
	pm.gravity = Vector3(0, 400, 0)
	pm.particle_flag_align_y = true
	pm.scale_min = 0.7
	pm.scale_max = 1.25
	pm.color = Color(0.78, 0.84, 0.94, 0.4)
	pm.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	pm.collision_use_scale = true
	pm.sub_emitter_mode = ParticleProcessMaterial.SUB_EMITTER_AT_COLLISION
	pm.sub_emitter_amount_at_collision = 3
	_rain = GPUParticles2D.new()
	_rain.z_as_relative = false
	_rain.z_index = 20
	_rain.amount = RAIN_DROPS
	_rain.lifetime = 1.4
	_rain.preprocess = 1.4
	_rain.local_coords = false
	_rain.fixed_fps = 60
	_rain.collision_base_size = 2.0
	_rain.visibility_rect = Rect2(-1500, -200, 3000, 2200)
	_rain.process_material = pm
	_rain.texture = drop
	var dot := GradientTexture2D.new()        # 水花：小圆点
	dot.width = 6
	dot.height = 6
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5)
	dot.fill_to = Vector2(1.0, 0.5)
	var g2 := Gradient.new()
	g2.set_color(0, Color(1, 1, 1, 1))
	g2.set_color(1, Color(1, 1, 1, 0))
	dot.gradient = g2
	var sm := ParticleProcessMaterial.new()
	sm.direction = Vector3(0, -1, 0)
	sm.spread = 55.0
	sm.initial_velocity_min = 110.0
	sm.initial_velocity_max = 260.0
	sm.gravity = Vector3(0, 1400, 0)
	sm.scale_min = 0.8
	sm.scale_max = 1.5
	sm.color = Color(0.90, 0.94, 1.0, 0.9)
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	sm.color_ramp = ramp
	_splash = GPUParticles2D.new()
	_splash.z_as_relative = false
	_splash.z_index = 20
	_splash.amount = 2400
	_splash.lifetime = 0.28
	_splash.emitting = false
	_splash.local_coords = false
	_splash.visibility_rect = Rect2(-1500, -200, 3000, 2200)
	_splash.process_material = sm
	_splash.texture = dot
	add_child(_splash)
	add_child(_rain)
	_rain.sub_emitter = _rain.get_path_to(_splash)
	var tm := pm.duplicate() as ParticleProcessMaterial
	tm.collision_mode = ParticleProcessMaterial.COLLISION_DISABLED
	tm.sub_emitter_mode = ParticleProcessMaterial.SUB_EMITTER_DISABLED
	tm.color = Color(0.74, 0.80, 0.90, 0.2)
	tm.scale_min = 0.6
	tm.scale_max = 1.0
	_rain_through = GPUParticles2D.new()
	_rain_through.z_as_relative = false
	_rain_through.z_index = 20
	_rain_through.amount = RAIN_THROUGH
	_rain_through.lifetime = 1.6
	_rain_through.preprocess = 1.6
	_rain_through.local_coords = false
	_rain_through.fixed_fps = 60
	_rain_through.visibility_rect = Rect2(-1500, -200, 3000, 2400)
	_rain_through.process_material = tm
	_rain_through.texture = drop
	add_child(_rain_through)
	_occluders = Node2D.new()
	add_child(_occluders)


## 雨跟着镜头走（发射框放在屏幕上沿往上一点）；附近几段的遮挡形状按需重建
func _update_rain() -> void:
	if camera == null:
		return
	var top := _scr(Vector2(640, -40)).y
	_rain.global_position = Vector2(_center().x + 120.0, top)    # 往左飘，发射框往右挪一点
	_rain_through.global_position = _rain.global_position
	var secs := _near_sections()
	var key := ""
	for s in secs:
		key += "%d," % int(s.center)
	if key == _occ_key:
		return
	_occ_key = key
	for c in _occluders.get_children():
		c.queue_free()
	for s in secs:
		var cx: float = s.center
		_add_occluder(cx - spacing * 0.5, cx + spacing * 0.5, floor_y, 60.0)      # 街面
		for p in s.sec.get("platforms", []):
			_add_occluder(cx + float(p[0]), cx + float(p[1]), float(p[2]), 14.0)
		for b in s.sec.get("blocks", []):
			_add_occluder(cx + float(b[0]), cx + float(b[1]), float(b[2]), floor_y - float(b[2]))


func _add_occluder(x0: float, x1: float, y: float, h: float) -> void:
	var poly := OccluderPolygon2D.new()
	poly.polygon = PackedVector2Array([Vector2(x0, y), Vector2(x1, y), Vector2(x1, y + h), Vector2(x0, y + h)])
	var o := LightOccluder2D.new()
	o.occluder = poly
	o.sdf_collision = true
	o.occluder_light_mask = 0
	_occluders.add_child(o)


static func _hash(a: int, b: int) -> float:
	var n := (a * 374761393 + b * 668265263) & 0x7fffffff
	n = ((n ^ (n >> 13)) * 1274126177) & 0x7fffffff
	return float((n ^ (n >> 16)) & 0xffff) / 65535.0
