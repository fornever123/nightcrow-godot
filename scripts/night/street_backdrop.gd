extends Node2D
## 「雨夜河岸街」灰盒夜景（阶段一）：只求结构和层次看得懂，美术之后换成 GPT 照着这张图画的成图。
##
## 和 night_backdrop.gd 同一套接口（night_trial / night_light 只用这些）：
##   camera / floor_y / ok / moon_screen() / lantern_light(p) / set_ult_mode(on)
##
## 图层（括号里是跟镜头移动的倍率，1 = 跟地面一起走）：
##   天空 + 月亮（贴屏幕）  远景城市剪影两层（0.12 / 0.3，带一座穹顶大教堂）  雾带
##   楼体（1.0，按布局 buildings 画：楼层线、窗、屋顶、钟面）  街面 / 河岸挡墙 / 河面
##   街灯和壁灯（1.0，暖光叠加）
##   前景（1.15 ~ 1.45，在角色前面）：底边河岸栏杆、顶边招牌长旗、近处路灯、入口石柱  + 雨丝
## 楼和平台的位置都来自 rain_street_layout.json（x 相对封印中心）。

const MOON := Vector2(1060.0, 110.0)    ## 月亮在屏幕上的位置（设计分辨率像素）
const LAMP_REACH := 320.0
const RAIN := 240

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
var _rain: Array = []


func _ready() -> void:
	z_index = -90
	_sky = Node2D.new()
	_sky.z_index = -100
	_sky.draw.connect(_draw_sky)
	add_child(_sky)
	_glow = Node2D.new()
	_glow.z_index = -60
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow.material = m
	_glow.draw.connect(_draw_glow)
	add_child(_glow)
	_fg = Node2D.new()
	_fg.z_index = 20
	_fg.draw.connect(_draw_fg)
	add_child(_fg)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in RAIN:
		_rain.append(Vector3(rng.randf() * 1480.0, rng.randf() * 760.0, rng.randf_range(0.6, 1.0)))
	ok = true


func set_ult_mode(on: bool) -> void:
	_fg.visible = not on


func moon_screen() -> Vector2:
	return MOON


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
		for l in s.sec.get("lamps", []):
			var x: float = s.center + float(l[0])
			var y: float = float(l[1])
			var street := String(l[2]) == "street"
			_lamps.append({"p": Vector2(x, y - (132.0 if street else 112.0)), "base": Vector2(x, y), "street": street})


# ---------------------------------------------------------------- 天空 + 远景（贴屏幕 / 慢视差）

func _draw_sky() -> void:
	if camera == null:
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
		var bi := 0
		for b in s.sec.get("buildings", []):
			_draw_building(s.center + float(b[0]), s.center + float(b[1]), float(b[2]), lines, bi + int(s.center))
			bi += 1
	_draw_street()
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
	draw_rect(Rect2(l, fy + 26.0, r - l, 70.0), C_WALL)
	draw_rect(Rect2(l, fy + 26.0, r - l, 4.0), Color(0.30, 0.32, 0.38))
	var wy := fy + 96.0
	if bot > wy:
		draw_rect(Rect2(l, wy, r - l, bot - wy), C_WATER)
		# 水面波纹（往左慢慢流）
		var i := 0
		var y := wy + 14.0
		while y < bot:
			var off := fmod(_time * 30.0 * (1.0 + float(i % 3) * 0.3) + float(i) * 97.0, 220.0)
			var x := l - off
			while x < r:
				draw_line(Vector2(x, y), Vector2(x + 60.0 + float(i % 4) * 20.0, y), Color(0.40, 0.46, 0.58, 0.18), 2.0)
				x += 220.0
			y += 22.0
			i += 1
		# 街灯在水里的暖色倒影
		for lp in _lamps:
			if not lp.street:
				continue
			var lx: float = lp.base.x
			var yy := wy + 10.0
			var j := 0
			while yy < minf(bot, wy + 320.0):
				var wob := sin(_time * 3.0 + float(j) * 1.7 + lx) * 10.0
				var a := 0.35 * (1.0 - (yy - wy) / 320.0)
				draw_line(Vector2(lx - 14.0 + wob, yy), Vector2(lx + 14.0 + wob, yy), Color(C_LAMP, a), 6.0)
				yy += 16.0
				j += 1


func _draw_lamp_posts() -> void:
	for lp in _lamps:
		var b: Vector2 = lp.base
		if lp.street:
			draw_rect(Rect2(b.x - 5.0, b.y - 122.0, 10.0, 122.0), Color(0.06, 0.06, 0.08))
			draw_rect(Rect2(b.x - 16.0, b.y - 150.0, 32.0, 30.0), C_LAMP)
			draw_colored_polygon(PackedVector2Array([Vector2(b.x - 20, b.y - 150), Vector2(b.x + 20, b.y - 150), Vector2(b.x, b.y - 170)]), Color(0.06, 0.06, 0.08))
		else:
			draw_line(Vector2(b.x - 30.0, b.y - 96.0), Vector2(b.x, b.y - 96.0), Color(0.06, 0.06, 0.08), 5.0)
			draw_rect(Rect2(b.x - 11.0, b.y - 126.0, 22.0, 30.0), C_LAMP)


func _draw_glow() -> void:
	for lp in _lamps:
		var f := _flicker(lp.p.x)
		for i in 6:
			_glow.draw_circle(lp.p, 30.0 + float(i) * 34.0, Color(1.0, 0.6, 0.28, 0.06 * f * (1.0 - float(i) / 6.0)))
		if lp.street:   # 路面上的光圈
			_glow.draw_set_transform(Vector2(lp.base.x, floor_y + 6.0), 0.0, Vector2(1.0, 0.16))
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
	# 底边：河岸栏杆 + 铁链（一直都在）
	var k_rail := float(rules.get("rail", {}).get("scroll", 1.15))
	var step := 240.0
	var bottom := _scr(Vector2(0, 720)).y
	var n0 := int(floor((c.x - 1200.0 * u) / step))
	for n in range(n0, n0 + int(2400.0 * u / step) + 3):
		var x := c.x + (float(n) * step - c.x) * k_rail
		var nx := c.x + (float(n + 1) * step - c.x) * k_rail
		var top := bottom - 64.0 * u
		_fg.draw_rect(Rect2(x - 9.0 * u, top, 18.0 * u, 64.0 * u), C_FG)
		_fg.draw_colored_polygon(PackedVector2Array([Vector2(x - 12.0 * u, top), Vector2(x + 12.0 * u, top), Vector2(x, top - 16.0 * u)]), C_FG)
		_fg.draw_line(Vector2(x + 8.0 * u, top), Vector2(x + 8.0 * u, bottom), Color(C_FG_RIM, 0.6), 2.0 * u)
		var pts := PackedVector2Array()
		for t in 13:
			pts.append(Vector2(lerpf(x, nx, float(t) / 12.0), top + 14.0 * u + 16.0 * u * sin(PI * float(t) / 12.0)))
		_fg.draw_polyline(pts, C_FG, 4.0 * u)
	# 大件前景：按布局摆，各自的视差；压到角色时变淡
	for s in _near_sections():
		for item in s.sec.get("foreground", []):
			var kind := String(item[1])
			var k := float(rules.get(kind, {}).get("scroll", 1.3))
			var wx: float = float(s.center) + float(item[0])
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
	_draw_rain()


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


func _draw_rain() -> void:
	var u := 1.0 / _z()
	for r in _rain:
		var x := fposmod(r.x - _time * 260.0 * r.z, 1480.0) - 100.0
		var y := fposmod(r.y + _time * 1150.0 * r.z, 760.0) - 20.0
		var a := _scr(Vector2(x, y))
		var b := _scr(Vector2(x - 5.0 * r.z, y + 26.0 * r.z))
		_fg.draw_line(a, b, Color(0.72, 0.78, 0.88, 0.22 * r.z), 1.2 * u)


static func _hash(a: int, b: int) -> float:
	var n := (a * 374761393 + b * 668265263) & 0x7fffffff
	n = ((n ^ (n >> 13)) * 1274126177) & 0x7fffffff
	return float((n ^ (n >> 16)) & 0xffff) / 65535.0
