extends Node2D
## 2026-11-19 背景重构档 · 环境动态与光影细节层（§3.1.3 + §3.3.3 + §3.6）：
##   1. 主角脚下接地软影（z = -3，随离地高度缩放变淡）
##   2. 湿石街面灯位竖向拉长湿光（z = -4，随街灯火焰同步微闪，绝非水洼/镜面）
##   3. 屋檐滴水 + 台面/栏杆雨滴溅花（z = -3）
##   4. 屋顶烟囱袅袅冷灰暗烟（z = -84）
##   5. （11-19 撤掉）灯下墙影：手画的脱脚、像鬼影；真 2D 阴影在画死光的墙上几乎看不出，只留脚下接地影
##   6. 灯旁被照亮的雨丝（lamp_rain.gdshader，加色）：只在每盏灯周围一圈，雨丝反着暖光往下落
## 11-19 返工：滴水只从稀疏的固定屋檐点落（原来沿整段台面随机落，落地圈在街面排成一行白点），落地改成小水花不画圈。

const FLOOR := 580.0

var sl                             ## street_layered 引用
var lamps_world: Array = []        ## [{x: float, y: float, sp: float, gain: float}]
var ledges_world: Array = []       ## [{x0: float, x1: float, y: float}]
var chimneys_world: Array = []     ## [Vector2(wx, wy)]
var dark_corners: Array = []       ## [Vector2(wx, wy)] 灯照不到的暗处墙脚

var _t := 0.0
var _rng := RandomNumberGenerator.new()
var _drips: Array = []
var _splashes: Array = []
var _smokes: Array = []

var _wet_node: Node2D
var _fx_node: Node2D
var _smoke_node: Node2D
var _shadow_node: Node2D
var _eaves: Array = []             ## 稀疏屋檐滴水点（世界 x, y）
var _hero_view: Sprite2D
var _lit_rain_node: Node2D
var _white: Texture2D
const LIT_RAIN_R := 230.0          ## 灯旁亮雨的半径（世界单位）


func setup(street_layered) -> void:
	sl = street_layered


func register_lamp(wx: float, wy: float, sp: float = 7.5, gain: float = 1.0) -> void:
	lamps_world.append({"x": wx, "y": wy, "sp": sp, "gain": gain})


func register_ledge(x0: float, x1: float, wy: float) -> void:
	ledges_world.append({"x0": x0, "x1": x1, "y": wy})


func register_chimney(wx: float, wy: float) -> void:
	chimneys_world.append(Vector2(wx, wy))


func _layer(z: int, cb: Callable, additive: bool = false) -> Node2D:
	var n := Node2D.new()
	n.z_as_relative = false
	n.z_index = z
	if additive:
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		n.material = m
	n.draw.connect(cb)
	add_child(n)
	return n


func _ready() -> void:
	_rng.seed = 20261119
	_smoke_node = _layer(-84, _draw_smoke, false)
	_lit_rain_node = _layer(-2, _draw_lit_rain, false)
	var rm := ShaderMaterial.new()
	rm.shader = preload("res://scripts/night/redesign/lamp_rain.gdshader")
	_lit_rain_node.material = rm
	var wi := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	wi.fill(Color.WHITE)
	_white = ImageTexture.create_from_image(wi)
	_wet_node = _layer(-4, _draw_wet_streaks, true)
	_shadow_node = _layer(-3, _draw_hero_shadow, false)
	_fx_node = _layer(-2, _draw_drips_and_splashes, false)

	# 默认沿 1-1A / J1 屋顶烟囱与暗处墙根布点
	for cx in [2420.0, 3150.0, 4120.0, 5020.0, 5940.0, 7180.0]:
		chimneys_world.append(Vector2(cx, -120.0))
	for lx in [[2060.0, 3760.0, 290.0], [3860.0, 4760.0, 290.0], [4860.0, 6780.0, 290.0], [6920.0, 8100.0, 320.0]]:
		ledges_world.append({"x0": lx[0], "x1": lx[1], "y": lx[2]})
	# 稀疏屋檐滴水点：每 300～520 一处，挂在二层步廊下沿
	var ex := 2100.0
	while ex < 8200.0:
		_eaves.append(Vector2(ex, 300.0 + _rng.randf_range(-6.0, 6.0)))
		ex += _rng.randf_range(300.0, 520.0)


func _cam_x() -> float:
	if sl != null and sl.bd != null and sl.bd.camera != null:
		return sl.bd.camera.get_screen_center_position().x
	return 3300.0


func _process(delta: float) -> void:
	_t += delta
	var cx := _cam_x()

	# 1. 屋檐滴水 + 台面/栏杆溅花
	if _drips.size() < 10 and _rng.randf() < delta * 5.0:
		var ev: Vector2 = _eaves[_rng.randi() % _eaves.size()]
		if absf(ev.x - cx) < 1000.0:
			_drips.append({"x": ev.x, "y": ev.y, "v": _rng.randf_range(10.0, 40.0), "life": 0.0, "hit": false})
	for d in _drips:
		if not bool(d["hit"]):
			d["v"] = float(d["v"]) + 1500.0 * delta
			d["y"] = float(d["y"]) + float(d["v"]) * delta
			if float(d["y"]) >= FLOOR - 2.0:
				d["y"] = FLOOR - 2.0
				d["hit"] = true
				d["life"] = 0.0
		else:
			d["life"] = float(d["life"]) + delta
	_drips = _drips.filter(func(d): return (not bool(d["hit"])) or float(d["life"]) < 0.28)

	# 台面与栏杆上的细雨微溅花
	if _splashes.size() < 10 and _rng.randf() < delta * 10.0:
		var L2: Dictionary = ledges_world[_rng.randi() % ledges_world.size()]
		var sx0 := maxf(float(L2["x0"]), cx - 1050.0)
		var sx1 := minf(float(L2["x1"]), cx + 1050.0)
		if sx1 > sx0 + 16.0:
			_splashes.append({"x": _rng.randf_range(sx0, sx1), "y": float(L2["y"]) - 1.0, "age": 0.0, "max": _rng.randf_range(0.16, 0.28)})
	for s in _splashes:
		s["age"] = float(s["age"]) + delta
	_splashes = _splashes.filter(func(s): return float(s["age"]) < float(s["max"]))

	# 2. 烟囱袅袅冷灰暗烟
	if _smokes.size() < 42 and _rng.randf() < delta * 9.0:
		for ch in chimneys_world:
			if absf((ch as Vector2).x - cx) < 1250.0 and _rng.randf() < 0.45:
				_smokes.append({
					"x": (ch as Vector2).x + _rng.randf_range(-8.0, 8.0),
					"y": (ch as Vector2).y,
					"vx": _rng.randf_range(-22.0, -10.0),
					"vy": _rng.randf_range(-34.0, -20.0),
					"r": _rng.randf_range(14.0, 26.0),
					"age": 0.0,
					"max": _rng.randf_range(3.2, 5.0),
				})
	for sm in _smokes:
		sm["age"] = float(sm["age"]) + delta
		sm["x"] = float(sm["x"]) + float(sm["vx"]) * delta
		sm["y"] = float(sm["y"]) + float(sm["vy"]) * delta
		sm["r"] = float(sm["r"]) + 10.0 * delta
	_smokes = _smokes.filter(func(sm): return float(sm["age"]) < float(sm["max"]))

	_smoke_node.queue_redraw()
	_wet_node.queue_redraw()
	_shadow_node.queue_redraw()
	_fx_node.queue_redraw()
	_lit_rain_node.queue_redraw()


func _draw_wet_streaks() -> void:
	var cx := _cam_x()
	for l in lamps_world:
		var lx := float(l["x"])
		if absf(lx - cx) > 1300.0:
			continue
		var sp := float(l["sp"])
		var gain := float(l["gain"])
		var fl := (0.90 + 0.07 * sin(_t * sp) + 0.03 * sin(_t * sp * 2.4 + lx * 0.01)) * gain
		# 湿石板上的竖向拉长暖光带（柔和叠加、无硬边镜面水洼感）
		for k in 5:
			var fk := float(k) / 4.0
			var yy := FLOOR + 4.0 + fk * 46.0
			var w := lerpf(135.0, 48.0, fk) * (0.94 + 0.06 * sin(_t * 3.1 + fk * 6.0 + lx))
			var h := lerpf(14.0, 22.0, fk)
			var a := (1.0 - fk * 0.72) * 0.13 * fl
			_wet_node.draw_rect(Rect2(lx - w * 0.5, yy, w, h), Color(1.0, 0.85, 0.58, a))


func _draw_hero_shadow() -> void:
	if sl == null:
		return
	var hp: Vector2 = sl._player_pos()
	var stage: Node = sl.bd.get_parent() if sl.bd != null else null
	var foot_y := hp.y
	if stage != null and "player" in stage and stage.player != null and "foot_offset" in stage.player:
		foot_y = hp.y + float(stage.player.foot_offset)
	var h_above := maxf(0.0, FLOOR - foot_y)
	var k := clampf(1.0 - h_above / 280.0, 0.18, 1.0)
	# 双层软椭圆接地影，角色脚底彻底贴地不飘浮
	_shadow_node.draw_set_transform(Vector2(hp.x, FLOOR + 2.0), 0.0, Vector2(1.0, 0.24))
	_shadow_node.draw_circle(Vector2.ZERO, 56.0 * k, Color(0.01, 0.012, 0.018, 0.34 * k))
	_shadow_node.draw_circle(Vector2.ZERO, 34.0 * k, Color(0.005, 0.006, 0.01, 0.52 * k))
	_shadow_node.draw_set_transform(Vector2.ZERO)


func _draw_drips_and_splashes() -> void:
	for d in _drips:
		var x := float(d["x"])
		var y := float(d["y"])
		if bool(d["hit"]):
			var k := float(d["life"]) / 0.28    # 落地小水花：两三粒往上弹，不画圈
			var a := 0.4 * (1.0 - k)
			for j in 3:
				var dx := (float(j) - 1.0) * (3.0 + 7.0 * k)
				var dy := -(9.0 - 4.0 * absf(float(j) - 1.0)) * sin(k * PI)
				_fx_node.draw_circle(Vector2(x + dx, y + dy), 1.1, Color(0.8, 0.85, 0.92, a))
		else:
			var ln := clampf(float(d["v"]) * 0.012, 4.0, 14.0)
			_fx_node.draw_line(Vector2(x, y - ln), Vector2(x, y), Color(0.76, 0.82, 0.90, 0.46), 1.5)
	for s in _splashes:
		var k2 := float(s["age"]) / float(s["max"])
		var x2 := float(s["x"])
		var y2 := float(s["y"])
		var a2 := 0.42 * (1.0 - k2)
		_fx_node.draw_line(Vector2(x2, y2), Vector2(x2 - 5.0 * k2, y2 - 6.0 * (1.0 - k2)), Color(0.82, 0.86, 0.94, a2), 1.2)
		_fx_node.draw_line(Vector2(x2, y2), Vector2(x2 + 5.0 * k2, y2 - 6.0 * (1.0 - k2)), Color(0.82, 0.86, 0.94, a2), 1.2)


func _draw_smoke() -> void:
	for sm in _smokes:
		var k := float(sm["age"]) / float(sm["max"])
		var a := sin(k * PI) * 0.14
		_smoke_node.draw_circle(Vector2(float(sm["x"]), float(sm["y"])), float(sm["r"]), Color(0.20, 0.21, 0.24, a))


func _find_hero_view() -> Sprite2D:
	if _hero_view != null and is_instance_valid(_hero_view):
		return _hero_view
	_hero_view = null
	if sl == null or sl.bd == null or not sl.bd.actors.is_valid():
		return null
	var list: Variant = sl.bd.actors.call()
	if not (list is Array) or (list as Array).is_empty() or not ((list as Array)[0] is Node):
		return null
	for c in ((list as Array)[0] as Node).find_children("*", "Sprite2D", true, false):    # 角色图在 player/Visual 下面
		if c is Sprite2D and c.get_script() != null and String(c.get_script().resource_path).ends_with("character_view.gd"):
			_hero_view = c
			break
	return _hero_view


## 每盏灯周围画一块方片，lamp_rain.gdshader 在里面按世界坐标画往左斜落的雨丝，越靠灯越亮
func _draw_lit_rain() -> void:
	var cx := _cam_x()
	for l in lamps_world:
		var lx := float(l["x"])
		if absf(lx - cx) > 1300.0:
			continue
		var sp := float(l["sp"])
		var fl := (0.9 + 0.07 * sin(_t * sp) + 0.03 * sin(_t * sp * 2.4 + lx * 0.01)) * float(l["gain"])
		var r := LIT_RAIN_R
		_lit_rain_node.draw_texture_rect(_white, Rect2(lx - r, float(l["y"]) - r * 0.8, r * 2.0, r * 1.9), false, Color(1.0, 0.86, 0.62, fl))


static func _envf_fx(k: String, d: float) -> float:
	var s := OS.get_environment(k)
	return float(s) if s != "" else d
