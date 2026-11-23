extends Node2D
## 独立测试首领战场地背景：「司辰母钟楼 · 血色玫瑰桥」（clocktower_backdrop.gd）
##
## 视觉复刻参考图（血红玫瑰窗司辰母钟 + 三道倾斜旋转暗铁符纹星环 + 哥特大教堂彩窗石桥 + 实时血色镜面水洼雨幕）：
##   1. 远景暴雨夜空、翻涌乌云与右上角倾泻月光柱；两侧对称哥特尖拱高塔与暖绯彩绘玻璃长窗；
##   2. 中央巨型「司辰母钟」：雕刻暗银石质外框、四向哥特尖饰、I–XII 罗马刻度、多层发光血红玫瑰花窗与内部啮合暗金齿轮；
##   3. 三道真 3D 透视投影倾斜旋转暗铁星环（背面弧段绘制在母钟后、正面弧段掠过母钟前，镶嵌暗红发光符纹与冷蓝高光）；
##   4. 可随首领血量拨动至不同时刻（Ⅲ:00 / Ⅸ:00 / Ⅻ:00）的巨型哥特镂空时针与分针；
##      进入三阶段「拔针裁昼」时调用 detach_clock_hands()，指针从母钟面震裂剥离，中央血红玫瑰窗裂开炽红裂隙；
##   5. 近景哥特石栏、左右边界残柱与湿青石桥面实时血红镜面倒影、角色倒影剪影及雨滴涟漪。

const GothicFonts := preload("res://scripts/ui/gothic_fonts.gd")

const ROMAN_NUMERALS: Array[String] = [
	"XII", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI",
]

var ok: bool = true
var layout: Dictionary = {}
var first_x: float = 0.0
var spacing: float = 6400.0
var actors: Callable = Callable()
var camera: Camera2D = null
var floor_y: float = 580.0
var cam_ref: float = 340.0
var section_center: float = 4100.0
var fight_half: float = 1120.0
var _lamps: Array = []

## 母钟联动状态（供 boss_clocktower_test.gd 与自动化测试观测）
var phase_index: int = 1
var target_hour_deg: float = 90.0          ## 12 点 = 0°，顺时针为正（3:00 = 90°，9:00 = 270°，12:00 = 0°）
var target_min_deg: float = 0.0
var current_hour_deg: float = 90.0
var current_min_deg: float = 0.0
var hands_detached: bool = false
var rewind_glow: float = 0.0
var boss_red_dim: float = 0.0
var eclipse_dim: float = 0.0

var _time: float = 0.0
var _gear_angle: float = 0.0
var _detach_flash: float = 0.0
var _crack_amount: float = 0.0
var _phase_blend_2: float = 0.0
var _phase_blend_3: float = 0.0
var _pillar_glow_l: float = 0.0
var _pillar_glow_r: float = 0.0
var _pillar_shake_l: float = 0.0
var _pillar_shake_r: float = 0.0
var _font_roman: Font = null
var _rng := RandomNumberGenerator.new()

var _rain_drops: Array[Dictionary] = []
var _rain_ripples: Array[Dictionary] = []
var _shatter_shards: Array[Dictionary] = []
var _splash_sparks: Array[Dictionary] = []

## 三道 3D 倾斜暗铁符纹星环配置
var _rings: Array[Dictionary] = [
	{"radius": 525.0, "width": 26.0, "tilt_x": 0.48, "tilt_y": -0.34, "roll": -0.38, "spin": 0.24, "phase": 0.3, "rune_col": Color(0.95, 0.20, 0.16)},
	{"radius": 590.0, "width": 22.0, "tilt_x": -0.58, "tilt_y": 0.42, "roll": 0.54, "spin": -0.19, "phase": 1.9, "rune_col": Color(0.88, 0.14, 0.24)},
	{"radius": 650.0, "width": 20.0, "tilt_x": 0.26, "tilt_y": 0.62, "roll": 0.18, "spin": 0.15, "phase": 3.7, "rune_col": Color(0.76, 0.16, 0.30)},
]


func _ready() -> void:
	name = "ClocktowerBackdrop"
	z_index = -20
	_rng.seed = 59590
	_font_roman = GothicFonts.cinzel(700)
	_init_rain()


func _init_rain() -> void:
	_rain_drops.clear()
	for i in 120:
		_rain_drops.append({
			"x": _rng.randf_range(-1600.0, 1600.0),
			"y": _rng.randf_range(-900.0, 620.0),
			"spd": _rng.randf_range(950.0, 1480.0),
			"len": _rng.randf_range(38.0, 82.0),
			"alpha": _rng.randf_range(0.14, 0.36),
		})
	_rain_ripples.clear()
	for i in 16:
		_rain_ripples.append({
			"x": _rng.randf_range(-1080.0, 1080.0),
			"y": _rng.randf_range(12.0, 128.0),
			"t": _rng.randf_range(0.0, 1.1),
			"max_t": _rng.randf_range(0.75, 1.35),
		})


func configure_duel_arena(center_x: float, half_w: float) -> void:
	section_center = center_x
	fight_half = half_w
	_lamps = [
		{"p": Vector2(center_x, floor_y - 380.0), "street": true},
		{"p": Vector2(center_x - half_w + 180.0, floor_y - 260.0), "street": false},
		{"p": Vector2(center_x + half_w - 180.0, floor_y - 260.0), "street": false},
	]
	queue_redraw()


func _flicker(x: float) -> float:
	return 0.92 + 0.08 * sin(_time * 6.5 + x * 0.01)


func lantern_light(p: Vector2) -> Vector3:
	var cw := get_clock_center_world()
	var d := cw - p
	var w := clampf(1.0 - d.length() / 1200.0, 0.25, 0.85)
	var dir := d / maxf(d.length(), 0.001)
	return Vector3(w, dir.x, dir.y)


func set_ult_mode(on: bool) -> void:
	eclipse_dim = 0.65 if on else 0.0


func set_boss_red_telegraph(v: float) -> void:
	boss_red_dim = clampf(v, 0.0, 1.0)


func set_eclipse_dim(v: float) -> void:
	eclipse_dim = clampf(v, 0.0, 1.0)


func set_rewind_glow(v: float) -> void:
	rewind_glow = clampf(v, 0.0, 1.0)


func set_clock_dial(hour_deg: float, min_deg: float, instant: bool = false) -> void:
	target_hour_deg = hour_deg
	target_min_deg = min_deg
	if instant:
		current_hour_deg = hour_deg
		current_min_deg = min_deg


func set_phase_visual(p_idx: int) -> void:
	phase_index = clampi(p_idx, 1, 3)


func detach_clock_hands() -> void:
	if hands_detached:
		return
	hands_detached = true
	_detach_flash = 1.0
	_shatter_shards.clear()
	for i in 34:
		var ang := _rng.randf_range(0.0, TAU)
		var spd := _rng.randf_range(160.0, 620.0)
		_shatter_shards.append({
			"ofs": Vector2(cos(ang), sin(ang)) * _rng.randf_range(12.0, 120.0),
			"vel": Vector2(cos(ang) * spd, sin(ang) * spd - 110.0),
			"rot": _rng.randf_range(0.0, TAU),
			"vrot": _rng.randf_range(-9.0, 9.0),
			"sz": _rng.randf_range(8.0, 26.0),
			"life": 0.0,
			"max_life": _rng.randf_range(1.1, 2.2),
			"crimson": _rng.randf() > 0.35,
		})


func notify_pillar_impact(side: int, strength: float = 1.0) -> void:
	var s := clampf(strength, 0.5, 2.0)
	if side < 0:
		_pillar_glow_l = 1.0
		_pillar_shake_l = 12.0 * s
	else:
		_pillar_glow_r = 1.0
		_pillar_shake_r = 12.0 * s


func slash_rain_at(pos: Vector2, radius: float, dir: Vector2) -> void:
	var n := clampi(int(radius / 45.0), 3, 8)
	for i in n:
		var ang := dir.angle() + _rng.randf_range(-0.9, 0.9)
		var spd := _rng.randf_range(180.0, 420.0)
		_splash_sparks.append({
			"pos": pos + Vector2(_rng.randf_range(-32.0, 32.0), _rng.randf_range(-28.0, 28.0)),
			"vel": Vector2(cos(ang) * spd, sin(ang) * spd - 60.0),
			"life": 0.0,
			"max_life": _rng.randf_range(0.18, 0.36),
			"col": Color(0.95, 0.42, 0.48, 0.85) if phase_index >= 3 else Color(0.82, 0.90, 1.0, 0.82),
		})


func get_clock_center_world() -> Vector2:
	var cam_dx := 0.0
	if camera != null and is_instance_valid(camera):
		cam_dx = (camera.global_position.x - section_center) * 0.22
	return Vector2(section_center + cam_dx, floor_y - 392.0)


func _process(delta: float) -> void:
	_time += delta
	var spin_dir := -2.6 if rewind_glow > 0.1 else (1.85 if phase_index >= 3 else (-0.85 if phase_index == 2 else 0.55))
	_gear_angle += delta * 0.38 * spin_dir

	var dial_k := clampf(delta * 5.2, 0.0, 1.0)
	current_hour_deg = _lerp_deg(current_hour_deg, target_hour_deg, dial_k)
	current_min_deg = _lerp_deg(current_min_deg, target_min_deg, dial_k * 1.25)

	_phase_blend_2 = lerpf(_phase_blend_2, 1.0 if phase_index >= 2 else 0.0, clampf(delta * 2.5, 0.0, 1.0))
	_phase_blend_3 = lerpf(_phase_blend_3, 1.0 if phase_index >= 3 else 0.0, clampf(delta * 2.8, 0.0, 1.0))
	if hands_detached:
		_crack_amount = lerpf(_crack_amount, 1.0, clampf(delta * 3.5, 0.0, 1.0))
	else:
		_crack_amount = lerpf(_crack_amount, 0.0, clampf(delta * 4.0, 0.0, 1.0))
	_detach_flash = maxf(0.0, _detach_flash - delta * 2.2)
	_pillar_glow_l = maxf(0.0, _pillar_glow_l - delta * 2.2)
	_pillar_glow_r = maxf(0.0, _pillar_glow_r - delta * 2.2)
	_pillar_shake_l = maxf(0.0, _pillar_shake_l - delta * 42.0)
	_pillar_shake_r = maxf(0.0, _pillar_shake_r - delta * 42.0)

	# 雨滴推进（倒流时雨丝缓慢悬停/微逆流）
	var rain_dir := -0.35 if rewind_glow > 0.25 else 1.0
	for d in _rain_drops:
		d["y"] = float(d["y"]) + float(d["spd"]) * delta * rain_dir
		d["x"] = float(d["x"]) - float(d["spd"]) * 0.16 * delta * rain_dir
		if float(d["y"]) > floor_y + 18.0:
			d["y"] = _rng.randf_range(-880.0, -460.0)
			d["x"] = _rng.randf_range(-1650.0, 1650.0)
		elif float(d["y"]) < -920.0:
			d["y"] = floor_y + 10.0

	for rp in _rain_ripples:
		rp["t"] = float(rp["t"]) + delta
		if float(rp["t"]) >= float(rp["max_t"]):
			rp["t"] = 0.0
			rp["x"] = _rng.randf_range(-fight_half + 40.0, fight_half - 40.0)
			rp["y"] = _rng.randf_range(10.0, 132.0)

	var si := _shatter_shards.size() - 1
	while si >= 0:
		var sh: Dictionary = _shatter_shards[si]
		sh["life"] = float(sh["life"]) + delta
		if float(sh["life"]) >= float(sh["max_life"]):
			_shatter_shards.remove_at(si)
		else:
			var vel: Vector2 = sh["vel"]
			vel.y += 420.0 * delta
			sh["vel"] = vel
			sh["ofs"] = (sh["ofs"] as Vector2) + vel * delta
			sh["rot"] = float(sh["rot"]) + float(sh["vrot"]) * delta
		si -= 1

	var pi := _splash_sparks.size() - 1
	while pi >= 0:
		var sp: Dictionary = _splash_sparks[pi]
		sp["life"] = float(sp["life"]) + delta
		if float(sp["life"]) >= float(sp["max_life"]):
			_splash_sparks.remove_at(pi)
		else:
			var v: Vector2 = sp["vel"]
			v.y += 520.0 * delta
			sp["vel"] = v
			sp["pos"] = (sp["pos"] as Vector2) + v * delta
		pi -= 1

	queue_redraw()


static func _lerp_deg(a: float, b: float, t: float) -> float:
	var diff := fposmod(b - a + 180.0, 360.0) - 180.0
	return a + diff * t


func _draw() -> void:
	var cw := get_clock_center_world()
	var left_x := section_center - fight_half - 680.0
	var right_x := section_center + fight_half + 680.0
	var top_y := floor_y - 1220.0
	var bot_y := floor_y + 420.0
	var dim_k := clampf((1.0 - 0.35 * boss_red_dim) * (1.0 - 0.55 * eclipse_dim), 0.30, 1.0)

	_draw_sky_and_clouds(left_x, right_x, top_y, bot_y, cw, dim_k)
	_draw_cathedral_wings(cw, dim_k)
	_draw_armillary_rings(cw, false, dim_k)
	_draw_mother_clock(cw, dim_k)
	_draw_armillary_rings(cw, true, dim_k)
	_draw_shatter_shards(cw)
	_draw_bridge_balustrade_and_pillars(dim_k)
	_draw_wet_bridge_floor_and_reflections(cw, left_x, right_x, bot_y, dim_k)
	_draw_rain_and_splashes(left_x, right_x, dim_k)


func _draw_sky_and_clouds(lx: float, rx: float, ty: float, by: float, cw: Vector2, dim_k: float) -> void:
	var w := rx - lx
	# 分段垂直夜空渐变（深黑蓝 -> 阴云暮紫 -> 钟楼底绯红暗雾）
	var c_top := Color(0.025, 0.030, 0.055).lerp(Color(0.055, 0.020, 0.035), _phase_blend_3 * 0.65) * dim_k
	var c_mid := Color(0.068, 0.066, 0.115).lerp(Color(0.11, 0.045, 0.14), _phase_blend_2 * 0.55).lerp(Color(0.15, 0.035, 0.045), _phase_blend_3 * 0.65) * dim_k
	var c_hor := Color(0.14, 0.042, 0.060).lerp(Color(0.24, 0.055, 0.065), _phase_blend_3 * 0.7) * dim_k
	c_top.a = 1.0
	c_mid.a = 1.0
	c_hor.a = 1.0
	draw_rect(Rect2(lx, ty, w, by - ty), c_top)
	var bands := 14
	var band_h := (floor_y - ty) / float(bands)
	for i in bands:
		var t := float(i) / float(bands - 1)
		var col := c_top.lerp(c_mid, clampf(t * 1.4, 0.0, 1.0))
		if t > 0.55:
			col = col.lerp(c_hor, (t - 0.55) / 0.45)
		col.a = 1.0
		draw_rect(Rect2(lx, ty + float(i) * band_h, w, band_h + 2.0), col)

	# 暴雨积云层次（绕母钟左右翻涌）
	var cloud_shift := sin(_time * 0.12) * 48.0
	var cloud_specs := [
		[-880.0, -560.0, 420.0, 145.0, 0.24],
		[-480.0, -680.0, 390.0, 155.0, 0.30],
		[-180.0, -760.0, 340.0, 130.0, 0.26],
		[340.0, -690.0, 440.0, 160.0, 0.25],
		[780.0, -580.0, 460.0, 150.0, 0.22],
		[-640.0, -320.0, 350.0, 110.0, 0.18],
		[660.0, -300.0, 360.0, 115.0, 0.18],
	]
	for cs in cloud_specs:
		var cx := cw.x + float(cs[0]) + cloud_shift * (0.6 if float(cs[0]) < 0.0 else -0.45)
		var cy := floor_y + float(cs[1])
		var rx_c := float(cs[2])
		var ry_c := float(cs[3])
		var a := float(cs[4]) * dim_k
		var cloud_col := Color(0.18, 0.19, 0.28, a).lerp(Color(0.28, 0.13, 0.24, a), _phase_blend_2 * 0.45)
		_draw_ellipse(Vector2(cx, cy), rx_c, ry_c, cloud_col, 24)
		_draw_ellipse(Vector2(cx + rx_c * 0.22, cy - ry_c * 0.25), rx_c * 0.62, ry_c * 0.52, Color(0.32, 0.35, 0.48, a * 0.42), 20)

	# 右上角斜射月光柱
	for bi in 3:
		var bx := cw.x + 520.0 + float(bi) * 210.0
		var bw := 110.0 + float(bi) * 45.0
		var beam_a := (0.055 - float(bi) * 0.012) * dim_k
		var poly := PackedVector2Array([
			Vector2(bx, ty),
			Vector2(bx + bw, ty),
			Vector2(bx - 540.0 + bw * 1.4, floor_y),
			Vector2(bx - 540.0, floor_y),
		])
		draw_colored_polygon(poly, Color(0.76, 0.84, 0.98, beam_a))

	# 钟楼正中底层血色雾光晕
	var crimson_boost := 1.0 + 0.45 * _phase_blend_3 + 0.35 * _detach_flash
	draw_circle(cw, 660.0, Color(0.68, 0.06, 0.10, 0.16 * dim_k * crimson_boost))
	draw_circle(cw, 480.0, Color(0.86, 0.10, 0.12, 0.18 * dim_k * crimson_boost))
	if rewind_glow > 0.02:
		draw_circle(cw, 580.0, Color(0.55, 0.22, 0.95, 0.24 * rewind_glow))


func _draw_cathedral_wings(cw: Vector2, dim_k: float) -> void:
	var stone_dark := Color(0.048, 0.048, 0.072, 0.96) * dim_k
	stone_dark.a = 0.98
	var stone_mid := Color(0.115, 0.110, 0.148, 0.96) * dim_k
	stone_mid.a = 0.98
	var rim := Color(0.38, 0.36, 0.44, 0.55 * dim_k)
	var win_glow := Color(0.95, 0.28, 0.16, 0.82 * dim_k).lerp(Color(0.74, 0.22, 0.92, 0.86 * dim_k), rewind_glow * 0.7)

	# 远景大教堂尖顶群与拱桥高架（左右对称围绕中央母钟）
	for side in [-1, 1]:
		var s := float(side)
		# 远景大拱桥连廊（3 跨尖拱）
		for k in 3:
			var ax := cw.x + s * (500.0 + float(k) * 265.0)
			var arch_top := floor_y - 330.0
			# 拱墩
			draw_rect(Rect2(ax - 24.0, arch_top, 48.0, 330.0), stone_dark)
			draw_line(Vector2(ax - 24.0, arch_top), Vector2(ax - 24.0, floor_y), rim, 1.5)
			# 拱梁与栏杆线
			draw_rect(Rect2(ax - 135.0, arch_top - 48.0, 270.0, 48.0), stone_mid)
			draw_line(Vector2(ax - 135.0, arch_top - 48.0), Vector2(ax + 135.0, arch_top - 48.0), rim, 2.0)
			# 尖拱洞内暗底 + 彩窗暖红透光
			_draw_gothic_arch_outline(Vector2(ax + s * 132.0, floor_y), 108.0, 300.0, rim, 2.5)

		# 两侧哥特教堂尖塔立面（含发光红橙尖拱彩窗，贴合参考图 2）
		var tower_x := cw.x + s * 785.0
		draw_rect(Rect2(tower_x - 135.0, floor_y - 640.0, 270.0, 640.0), stone_dark)
		draw_rect(Rect2(tower_x - 118.0, floor_y - 620.0, 236.0, 620.0), stone_mid)
		# 主尖顶 + 副尖塔
		for spire_raw in [-86.0, 0.0, 86.0]:
			var spire_dx := float(spire_raw)
			var sh := 260.0 if absf(spire_dx) < 1.0 else 175.0
			var sw := 58.0 if absf(spire_dx) < 1.0 else 34.0
			var base_y := floor_y - 620.0
			var tri := PackedVector2Array([
				Vector2(tower_x + spire_dx - sw, base_y),
				Vector2(tower_x + spire_dx, base_y - sh),
				Vector2(tower_x + spire_dx + sw, base_y),
			])
			draw_colored_polygon(tri, stone_dark)
			draw_polyline(tri, rim, 1.8)
		# 发光红琥珀彩窗（2 扇高窗）
		for wx_raw in [-52.0, 52.0]:
			var wx := tower_x + float(wx_raw)
			var wy := floor_y - 360.0
			_draw_lancet_window(Vector2(wx, wy), 34.0, 195.0, win_glow, stone_dark)
		# 外侧更宏伟的前景哥特大拱柱
		var outer_x := cw.x + s * 1075.0
		draw_rect(Rect2(outer_x - 125.0, floor_y - 780.0, 250.0, 780.0), stone_dark)
		_draw_lancet_window(Vector2(outer_x, floor_y - 440.0), 42.0, 250.0, Color(win_glow.r, win_glow.g, win_glow.b, win_glow.a * 0.72), stone_dark)


func _draw_lancet_window(center: Vector2, half_w: float, height: float, glow_col: Color, frame_col: Color) -> void:
	var top_y := center.y - height * 0.5
	var bot_y := center.y + height * 0.5
	var arch_y := top_y + height * 0.28
	var pts := PackedVector2Array([
		Vector2(center.x - half_w, bot_y),
		Vector2(center.x - half_w, arch_y),
		Vector2(center.x - half_w * 0.65, top_y + height * 0.12),
		Vector2(center.x, top_y),
		Vector2(center.x + half_w * 0.65, top_y + height * 0.12),
		Vector2(center.x + half_w, arch_y),
		Vector2(center.x + half_w, bot_y),
	])
	# 外发光
	draw_circle(center, height * 0.42, Color(glow_col.r, glow_col.g, glow_col.b, glow_col.a * 0.18))
	draw_colored_polygon(pts, glow_col)
	# 内部更亮核心
	var inner_pts := PackedVector2Array()
	for p in pts:
		inner_pts.append(center.lerp(p, 0.58))
	draw_colored_polygon(inner_pts, Color(1.0, 0.68, 0.38, glow_col.a * 0.85))
	# 铅条窗棂
	draw_line(Vector2(center.x, top_y + 10.0), Vector2(center.x, bot_y), frame_col, 3.0)
	draw_line(Vector2(center.x - half_w, center.y), Vector2(center.x + half_w, center.y), frame_col, 2.5)
	draw_line(Vector2(center.x - half_w, arch_y), Vector2(center.x + half_w, arch_y), frame_col, 2.5)
	var border := pts.duplicate()
	border.append(pts[0])
	draw_polyline(border, Color(0.55, 0.44, 0.42, 0.65), 2.0)


func _draw_gothic_arch_outline(base_center: Vector2, half_w: float, h: float, col: Color, width: float) -> void:
	var pts := PackedVector2Array()
	for i in 13:
		var t := float(i) / 12.0
		var ang := lerpf(PI, 0.0, t)
		var x := base_center.x + cos(ang) * half_w
		var y := base_center.y - h * 0.52 - sin(ang) * (h * 0.48) - (1.0 - absf(t * 2.0 - 1.0)) * 28.0
		pts.append(Vector2(x, y))
	draw_polyline(pts, col, width)


func _draw_mother_clock(cw: Vector2, dim_k: float) -> void:
	var r_outer := 428.0
	var r_num_outer := 408.0
	var r_num_mid := 350.0
	var r_rose := 288.0

	# 1. 母钟外暗影与暗铁石雕边框
	draw_circle(cw, r_outer + 26.0, Color(0.02, 0.02, 0.035, 0.85))
	draw_circle(cw, r_outer, Color(0.11, 0.115, 0.145, 0.98) * dim_k)
	draw_arc(cw, r_outer, 0.0, TAU, 96, Color(0.62, 0.60, 0.66, 0.78 * dim_k), 4.5, true)
	draw_arc(cw, r_num_outer, 0.0, TAU, 96, Color(0.45, 0.42, 0.48, 0.65 * dim_k), 2.5, true)
	draw_circle(cw, r_num_outer - 2.0, Color(0.075, 0.072, 0.092, 0.98))

	# 四向哥特尖饰（XII / III / VI / IX）
	for ci in 4:
		var ang := -PI * 0.5 + float(ci) * PI * 0.5
		var dir := Vector2(cos(ang), sin(ang))
		var perp := Vector2(-dir.y, dir.x)
		var p_base := cw + dir * (r_outer - 6.0)
		var p_tip := cw + dir * (r_outer + 54.0)
		var spire := PackedVector2Array([
			p_base - perp * 26.0,
			p_base + dir * 24.0 - perp * 11.0,
			p_tip,
			p_base + dir * 24.0 + perp * 11.0,
			p_base + perp * 26.0,
		])
		draw_colored_polygon(spire, Color(0.16, 0.16, 0.20, 0.98) * dim_k)
		var loop := spire.duplicate()
		loop.append(spire[0])
		draw_polyline(loop, Color(0.70, 0.66, 0.72, 0.72 * dim_k), 2.0)

	# 60 刻细刻度与 12 刻菱形铆钉
	for ti in 60:
		var a := -PI * 0.5 + TAU * float(ti) / 60.0
		var v := Vector2(cos(a), sin(a))
		var is_major := (ti % 5 == 0)
		var r0 := r_num_outer - (18.0 if is_major else 9.0)
		var col := Color(0.76, 0.68, 0.60, 0.75 * dim_k) if is_major else Color(0.42, 0.40, 0.46, 0.45 * dim_k)
		draw_line(cw + v * r0, cw + v * (r_num_outer - 2.0), col, 2.4 if is_major else 1.2)

	# 2. 罗马数字 I–XII（当前阶段时刻发炽红金光）
	var active_idx := 3 if phase_index == 1 else (9 if phase_index == 2 else 0)
	if _font_roman != null:
		for ni in 12:
			var a := -PI * 0.5 + TAU * float(ni) / 12.0
			var pos := cw + Vector2(cos(a), sin(a)) * r_num_mid
			var txt := ROMAN_NUMERALS[ni]
			var is_act := (ni == active_idx)
			var col := Color(0.92, 0.88, 0.80, 0.94 * dim_k)
			if is_act:
				col = Color(1.0, 0.48, 0.34, 1.0) if phase_index != 2 else Color(0.92, 0.64, 1.0, 1.0)
				draw_circle(pos, 32.0, Color(col.r, col.g, col.b, 0.24))
			draw_string(_font_roman, pos + Vector2(-42.0, 15.0), txt, HORIZONTAL_ALIGNMENT_CENTER, 84.0, 42 if is_act else 36, col)

	# 3. 中央血红玫瑰花窗底盘 + 内部旋转暗金齿轮
	draw_circle(cw, r_rose + 10.0, Color(0.18, 0.14, 0.18, 0.98))
	draw_arc(cw, r_rose + 10.0, 0.0, TAU, 80, Color(0.72, 0.56, 0.52, 0.78 * dim_k), 3.0, true)
	draw_circle(cw, r_rose, Color(0.26, 0.02, 0.03, 0.99))

	var pulse := 0.90 + 0.10 * sin(_time * 2.8) + 0.22 * _detach_flash
	var core_tint := Color(1.0, 0.28, 0.12).lerp(Color(0.86, 0.22, 0.82), rewind_glow * 0.55)
	# 多层发光红玉渐变
	draw_circle(cw, r_rose * 0.96, Color(0.58, 0.04, 0.06, 0.92 * dim_k))
	draw_circle(cw, r_rose * 0.76, Color(0.82, 0.09, 0.08, 0.88 * dim_k * pulse))
	draw_circle(cw, r_rose * 0.52, Color(core_tint.r, core_tint.g, core_tint.b, 0.84 * dim_k * pulse))
	draw_circle(cw, r_rose * 0.28, Color(1.0, 0.62, 0.28, 0.82 * dim_k * pulse))

	# 花窗内部可见的旋转机械齿轮剪影
	_draw_gear(cw + Vector2(-88.0, -76.0), 82.0, 14, _gear_angle * 1.1, Color(0.20, 0.02, 0.03, 0.55))
	_draw_gear(cw + Vector2(96.0, 82.0), 94.0, 16, -_gear_angle * 0.9, Color(0.20, 0.02, 0.03, 0.55))
	_draw_gear(cw + Vector2(92.0, -84.0), 68.0, 12, _gear_angle * 1.35, Color(0.24, 0.03, 0.04, 0.48))
	_draw_gear(cw + Vector2(-96.0, 86.0), 74.0, 12, -_gear_angle * 1.25, Color(0.24, 0.03, 0.04, 0.48))

	# 4. 血红彩绘玫瑰花窗铅条纹路（两层 12 瓣哥特尖花瓣，高度还原参考图 1 & 2）
	var lead_col := Color(0.08, 0.02, 0.03, 0.92)
	var vein_glow := Color(1.0, 0.42, 0.24, 0.42 * dim_k)
	for layer_i in 2:
		var petals := 12
		var r_in := 34.0 if layer_i == 0 else 132.0
		var r_out := 152.0 if layer_i == 0 else r_rose - 6.0
		var rot_ofs := 0.0 if layer_i == 0 else (PI / 12.0)
		for k in petals:
			var a := rot_ofs + TAU * float(k) / float(petals)
			var a_l := a - (PI / float(petals)) * 0.78
			var a_r := a + (PI / float(petals)) * 0.78
			var p0 := cw + Vector2(cos(a), sin(a)) * r_in
			var p_mid_l := cw + Vector2(cos(a_l), sin(a_l)) * lerpf(r_in, r_out, 0.58)
			var p_mid_r := cw + Vector2(cos(a_r), sin(a_r)) * lerpf(r_in, r_out, 0.58)
			var p_tip := cw + Vector2(cos(a), sin(a)) * r_out
			var petal_poly := PackedVector2Array([p0, p_mid_l, p_tip, p_mid_r])
			var fill_a := (0.28 if layer_i == 0 else 0.20) * dim_k
			draw_colored_polygon(petal_poly, Color(1.0, 0.22, 0.12, fill_a))
			var loop := petal_poly.duplicate()
			loop.append(p0)
			draw_polyline(loop, lead_col, 5.2 if layer_i == 1 else 4.2, true)
			draw_polyline(loop, vein_glow, 1.3, true)
			# 花瓣叶尖圆孔装饰
			draw_circle(cw + Vector2(cos(a), sin(a)) * lerpf(r_in, r_out, 0.76), 9.0 if layer_i == 1 else 6.0, Color(1.0, 0.45, 0.22, 0.42 * dim_k))
			draw_arc(cw + Vector2(cos(a), sin(a)) * lerpf(r_in, r_out, 0.76), 9.0 if layer_i == 1 else 6.0, 0.0, TAU, 14, lead_col, 2.2)

	draw_arc(cw, 146.0, 0.0, TAU, 64, lead_col, 5.0)
	draw_arc(cw, r_rose, 0.0, TAU, 80, lead_col, 7.0)

	# 5. 三阶段拔针后的炽红裂痕 OR 一二阶段可动巨型哥特指针
	if hands_detached:
		_draw_cracked_empty_hub(cw)
	else:
		_draw_clock_hands(cw, dim_k)

	# 拔针瞬时强闪
	if _detach_flash > 0.02:
		draw_circle(cw, r_rose * (1.1 + 0.4 * (1.0 - _detach_flash)), Color(1.0, 0.52, 0.34, 0.55 * _detach_flash))
		draw_arc(cw, r_rose * (0.4 + 1.1 * (1.0 - _detach_flash)), 0.0, TAU, 64, Color(1.0, 0.88, 0.62, 0.92 * _detach_flash), 10.0 * _detach_flash)


func _draw_gear(center: Vector2, radius: float, teeth: int, angle: float, col: Color) -> void:
	draw_arc(center, radius * 0.76, 0.0, TAU, 32, col, radius * 0.20)
	draw_arc(center, radius * 0.28, 0.0, TAU, 20, col, 6.0)
	for i in teeth:
		var a := angle + TAU * float(i) / float(teeth)
		var v := Vector2(cos(a), sin(a))
		draw_line(center + v * (radius * 0.80), center + v * (radius * 1.04), col, 8.0)
	for s in 4:
		var sa := angle + float(s) * PI * 0.5
		var sv := Vector2(cos(sa), sin(sa))
		draw_line(center + sv * (radius * 0.28), center + sv * (radius * 0.76), col, 6.0)


func _draw_clock_hands(cw: Vector2, dim_k: float) -> void:
	var iron := Color(0.06, 0.06, 0.085, 0.98)
	var edge := Color(0.76, 0.68, 0.64, 0.88 * dim_k)
	var crimson_vein := Color(1.0, 0.24, 0.20, 0.85) if phase_index != 2 else Color(0.84, 0.46, 1.0, 0.90)

	# 时针（较粗短、哥特阔刃）
	_draw_single_hand(cw, deg_to_rad(current_hour_deg - 90.0), 235.0, 74.0, 22.0, iron, edge, crimson_vein)
	# 分针（修长尖锐、长剑矛尖）
	_draw_single_hand(cw, deg_to_rad(current_min_deg - 90.0), 348.0, 96.0, 15.0, iron, edge, crimson_vein)

	# 中央黑铁轴心与血红魔眼珠
	draw_circle(cw, 36.0, Color(0.05, 0.05, 0.07, 0.98))
	draw_arc(cw, 36.0, 0.0, TAU, 32, edge, 3.0, true)
	draw_circle(cw, 17.0, crimson_vein)
	draw_circle(cw, 8.0, Color(1.0, 0.85, 0.70, 0.92))


func _draw_single_hand(cw: Vector2, rad: float, length: float, tail: float, half_w: float, fill: Color, rim: Color, glow: Color) -> void:
	var dir := Vector2(cos(rad), sin(rad))
	var perp := Vector2(-dir.y, dir.x)
	var poly := PackedVector2Array([
		cw - dir * tail,
		cw - dir * (tail * 0.35) + perp * (half_w * 0.72),
		cw + dir * (length * 0.24) + perp * half_w,
		cw + dir * (length * 0.74) + perp * (half_w * 0.42),
		cw + dir * length,
		cw + dir * (length * 0.74) - perp * (half_w * 0.42),
		cw + dir * (length * 0.24) - perp * half_w,
		cw - dir * (tail * 0.35) - perp * (half_w * 0.72),
	])
	# 微红/紫轮廓光晕，确保指针在血色玫瑰窗前极清晰
	draw_line(cw - dir * tail, cw + dir * length, Color(glow.r, glow.g, glow.b, 0.32), half_w * 1.45)
	draw_colored_polygon(poly, fill)
	var loop := poly.duplicate()
	loop.append(poly[0])
	draw_polyline(loop, rim, 2.2, true)
	# 刃脊发光线
	draw_line(cw + dir * 24.0, cw + dir * (length * 0.88), glow, 2.5)


func _draw_cracked_empty_hub(cw: Vector2) -> void:
	# 指针被 Boss 拔走后：空洞碎裂轴心 + 炽红空间裂纹
	var crack_col := Color(1.0, 0.36, 0.20, 0.92 * _crack_amount)
	var core_col := Color(1.0, 0.92, 0.76, 0.96 * _crack_amount)
	draw_circle(cw, 44.0, Color(0.03, 0.01, 0.02, 0.96))
	draw_arc(cw, 44.0, 0.0, TAU, 32, crack_col, 4.0)
	for i in 7:
		var a := -0.35 + float(i) * (TAU / 7.0) + 0.14 * sin(float(i) * 3.1)
		var p1 := cw + Vector2(cos(a), sin(a)) * 42.0
		var p2 := cw + Vector2(cos(a + 0.08), sin(a + 0.08)) * 145.0
		var p3 := cw + Vector2(cos(a - 0.06), sin(a - 0.06)) * (255.0 * _crack_amount)
		draw_line(p1, p2, crack_col, 5.5)
		draw_line(p2, p3, Color(crack_col.r, crack_col.g, crack_col.b, 0.78), 3.0)
		draw_line(p1, p2, core_col, 2.0)
	draw_circle(cw, 22.0 + 4.0 * sin(_time * 12.0), Color(1.0, 0.26, 0.14, 0.85))
	draw_circle(cw, 10.0, core_col)


func _draw_armillary_rings(cw: Vector2, front_pass: bool, dim_k: float) -> void:
	var segs := 64
	var speed_mul := -2.8 if rewind_glow > 0.1 else (2.2 if phase_index >= 3 else (-1.0 if phase_index == 2 else 1.0))
	for r_cfg in _rings:
		var rad: float = float(r_cfg["radius"])
		var rw: float = float(r_cfg["width"])
		var tx: float = float(r_cfg["tilt_x"]) + 0.08 * sin(_time * 0.4 + float(r_cfg["phase"]))
		var ty: float = float(r_cfg["tilt_y"]) + 0.07 * cos(_time * 0.35 + float(r_cfg["phase"]))
		var roll: float = float(r_cfg["roll"])
		var spin: float = float(r_cfg["spin"]) * speed_mul
		var ph: float = float(r_cfg["phase"]) + _time * spin
		var rune_base: Color = r_cfg["rune_col"]
		if rewind_glow > 0.1:
			rune_base = rune_base.lerp(Color(0.76, 0.36, 1.0), rewind_glow * 0.75)

		for i in segs:
			var a0 := ph + TAU * float(i) / float(segs)
			var a1 := ph + TAU * float(i + 1) / float(segs)
			var v0 := _project_ring_pt(rad, a0, tx, ty, roll)
			var v1 := _project_ring_pt(rad, a1, tx, ty, roll)
			var z_mid := (v0.z + v1.z) * 0.5
			if front_pass and z_mid < 0.0:
				continue
			if not front_pass and z_mid >= 0.0:
				continue
			var p0 := cw + Vector2(v0.x, v0.y)
			var p1 := cw + Vector2(v1.x, v1.y)
			var depth_k := clampf((z_mid / rad + 1.0) * 0.5, 0.28, 1.0)
			var w_cur := rw * lerpf(0.68, 1.18, depth_k)
			# 暗铁环主体
			var body_col := Color(0.035, 0.038, 0.056, 0.96) if front_pass else Color(0.045, 0.032, 0.050, 0.88)
			draw_line(p0, p1, body_col, w_cur)
			# 内部血红发光符纹刻度（间隔绘制形成铭文带）
			if (i % 2) == 0:
				var rune_a := (0.72 if front_pass else 0.48) * depth_k * dim_k
				draw_line(p0, p1, Color(rune_base.r, rune_base.g, rune_base.b, rune_a), w_cur * 0.34)
			# 外缘冷银/蓝紫金属反光高光
			var rim_a := (0.55 if front_pass else 0.22) * depth_k * dim_k
			var rim_col := Color(0.55, 0.66, 0.86, rim_a) if front_pass else Color(0.42, 0.32, 0.42, rim_a)
			var dir := (p1 - p0).normalized()
			var nrm := Vector2(-dir.y, dir.x) * (w_cur * 0.46)
			draw_line(p0 + nrm, p1 + nrm, rim_col, 2.0)
			draw_line(p0 - nrm, p1 - nrm, Color(0.75, 0.22, 0.22, rim_a * 0.65), 1.5)


static func _project_ring_pt(rad: float, ang: float, tilt_x: float, tilt_y: float, roll: float) -> Vector3:
	var x := cos(ang) * rad
	var y := sin(ang) * rad
	var z := 0.0
	# 绕 X 轴倾角
	var y1 := y * cos(tilt_x) - z * sin(tilt_x)
	var z1 := y * sin(tilt_x) + z * cos(tilt_x)
	# 绕 Y 轴偏航
	var x2 := x * cos(tilt_y) + z1 * sin(tilt_y)
	var z2 := -x * sin(tilt_y) + z1 * cos(tilt_y)
	# 绕 Z 轴翻滚
	var x3 := x2 * cos(roll) - y1 * sin(roll)
	var y3 := x2 * sin(roll) + y1 * cos(roll)
	return Vector3(x3, y3, z2)


func _draw_shatter_shards(cw: Vector2) -> void:
	for sh in _shatter_shards:
		var k := clampf(float(sh["life"]) / maxf(float(sh["max_life"]), 0.01), 0.0, 1.0)
		var alpha := 1.0 - k
		var pos := cw + (sh["ofs"] as Vector2)
		var sz := float(sh["sz"])
		var col := Color(1.0, 0.26, 0.18, alpha * 0.92) if bool(sh["crimson"]) else Color(0.76, 0.72, 0.78, alpha * 0.88)
		draw_set_transform(pos, float(sh["rot"]), Vector2.ONE)
		draw_colored_polygon(PackedVector2Array([
			Vector2(-sz * 0.6, -sz * 0.3),
			Vector2(sz * 0.7, -sz * 0.1),
			Vector2(sz * 0.1, sz * 0.6),
		]), col)
	if not _shatter_shards.is_empty():
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_bridge_balustrade_and_pillars(dim_k: float) -> void:
	var left_b := section_center - fight_half - 240.0
	var right_b := section_center + fight_half + 240.0
	var rail_top := floor_y - 98.0
	var stone := Color(0.055, 0.052, 0.070, 0.98) * dim_k
	stone.a = 0.98
	var trim := Color(0.36, 0.28, 0.32, 0.78 * dim_k)

	# 连续石质护栏顶梁与底座
	draw_rect(Rect2(left_b, rail_top, right_b - left_b, 14.0), stone)
	draw_line(Vector2(left_b, rail_top), Vector2(right_b, rail_top), trim, 2.2)
	draw_rect(Rect2(left_b, floor_y - 18.0, right_b - left_b, 18.0), stone)

	# 哥特矮栏柱与每 220px 一座尖顶立柱（贴合参考图 1 & 2 下沿桥栏）
	var x := left_b
	var post_idx := 0
	while x <= right_b:
		var is_major := (post_idx % 6 == 0)
		if is_major:
			draw_rect(Rect2(x - 16.0, rail_top - 14.0, 32.0, 112.0), stone)
			var finial := PackedVector2Array([
				Vector2(x - 14.0, rail_top - 14.0),
				Vector2(x, rail_top - 48.0),
				Vector2(x + 14.0, rail_top - 14.0),
			])
			draw_colored_polygon(finial, stone)
			draw_polyline(finial, Color(0.75, 0.30, 0.26, 0.58 * dim_k), 1.6)
		else:
			draw_rect(Rect2(x - 7.0, rail_top + 12.0, 14.0, 68.0), stone)
			draw_line(Vector2(x - 7.0, rail_top + 12.0), Vector2(x - 7.0, floor_y - 18.0), Color(0.28, 0.24, 0.30, 0.5 * dim_k), 1.2)
		x += 36.0
		post_idx += 1

	# 决斗台左右边界哥特石柱（支持横轰撞柱震颤发光）
	for side in [-1, 1]:
		var glow := _pillar_glow_l if side < 0 else _pillar_glow_r
		var shk := _pillar_shake_l if side < 0 else _pillar_shake_r
		var jx := sin(_time * 88.0) * shk
		var px := section_center + float(side) * fight_half + jx
		var p_left := px - 140.0 if side < 0 else px
		draw_rect(Rect2(p_left, floor_y - 760.0, 140.0, 760.0), Color(0.042, 0.040, 0.060, 0.98))
		var edge_col := Color(0.55, 0.30, 0.34, 0.72 * dim_k).lerp(Color(1.0, 0.78, 0.42, 0.95), glow)
		draw_line(Vector2(px, floor_y - 760.0), Vector2(px, floor_y), edge_col, 3.5 + 4.0 * glow)
		# 柱头暖红灯笼
		var lp := Vector2(px - float(side) * 26.0, floor_y - 260.0)
		draw_circle(lp, 68.0, Color(0.95, 0.28, 0.18, 0.12 * dim_k))
		draw_circle(lp, 16.0, Color(1.0, 0.58, 0.34, 0.65 * dim_k))


func _draw_wet_bridge_floor_and_reflections(cw: Vector2, lx: float, rx: float, by: float, dim_k: float) -> void:
	var floor_h := maxf(by - floor_y, 380.0)
	# 湿暗青石桥面基底
	draw_rect(Rect2(lx, floor_y, rx - lx, floor_h), Color(0.032, 0.028, 0.044, 1.0))
	# 桥面顶沿冷银微红高光线
	draw_line(Vector2(lx, floor_y), Vector2(rx, floor_y), Color(0.56, 0.42, 0.48, 0.72 * dim_k), 2.5)

	# 透视石砖接缝
	var tile_w := 148.0
	var start_x := floorf(lx / tile_w) * tile_w
	var tx := start_x
	while tx <= rx:
		draw_line(Vector2(tx, floor_y + 2.0), Vector2(tx + (tx - section_center) * 0.22, floor_y + 220.0), Color(0.14, 0.12, 0.18, 0.32), 1.4)
		tx += tile_w
	for row_raw in [floor_y + 26.0, floor_y + 62.0, floor_y + 112.0, floor_y + 178.0]:
		var row_y := float(row_raw)
		draw_line(Vector2(lx, row_y), Vector2(rx, row_y), Color(0.14, 0.12, 0.18, 0.28), 1.2)

	# 实时血红玫瑰母钟镜面水洼倒影（参考图 1 & 2 桥面最抓眼的猩红反射！）
	var refl_col := Color(0.86, 0.10, 0.12) if rewind_glow < 0.2 else Color(0.68, 0.20, 0.92)
	var shimmer := 0.88 + 0.12 * sin(_time * 4.2)
	_draw_ellipse(Vector2(cw.x, floor_y + 72.0), 560.0, 92.0, Color(refl_col.r, refl_col.g, refl_col.b, 0.24 * dim_k * shimmer), 36)
	_draw_ellipse(Vector2(cw.x, floor_y + 64.0), 340.0, 56.0, Color(1.0, 0.24, 0.16, 0.32 * dim_k * shimmer), 28)
	_draw_ellipse(Vector2(cw.x, floor_y + 52.0), 170.0, 28.0, Color(1.0, 0.50, 0.26, 0.26 * dim_k * shimmer), 20)

	# 实时玩家与 Boss 水洼倒影剪影
	if actors.is_valid():
		var list: Variant = actors.call()
		if list is Array:
			for a in list:
				if a == null or not is_instance_valid(a) or not (a is Node2D):
					continue
				var n := a as Node2D
				var ax := n.global_position.x
				var is_boss := n.is_in_group(&"shade")
				var rw := 54.0 if is_boss else 28.0
				var rh := 118.0 if is_boss else 76.0
				var tint := Color(0.88, 0.18, 0.24, 0.26) if is_boss else Color(0.58, 0.38, 0.98, 0.32)
				_draw_ellipse(Vector2(ax, floor_y + rh * 0.45), rw, rh * 0.42, Color(0.02, 0.015, 0.03, 0.55), 18)
				_draw_ellipse(Vector2(ax, floor_y + rh * 0.38), rw * 0.72, rh * 0.28, tint, 16)

	# 湿石雨滴涟漪
	for rp in _rain_ripples:
		var k := clampf(float(rp["t"]) / maxf(float(rp["max_t"]), 0.01), 0.0, 1.0)
		var rpx := section_center + float(rp["x"])
		var rpy := floor_y + float(rp["y"])
		var rx_e := lerpf(6.0, 44.0, k)
		var ry_e := rx_e * 0.24
		var ra := (1.0 - k) * 0.46 * dim_k
		var near_clock := clampf(1.0 - absf(rpx - cw.x) / 560.0, 0.0, 1.0)
		var rc := Color(0.75, 0.84, 0.96, ra).lerp(Color(1.0, 0.36, 0.30, ra * 1.25), near_clock)
		_draw_ellipse_outline(Vector2(rpx, rpy), rx_e, ry_e, rc, 1.6, 18)


func _draw_rain_and_splashes(_lx: float, _rx: float, dim_k: float) -> void:
	for d in _rain_drops:
		var x := section_center + float(d["x"])
		var y := float(d["y"])
		var ln := float(d["len"])
		var a := float(d["alpha"]) * dim_k
		var col := Color(0.78, 0.86, 0.98, a) if rewind_glow < 0.25 else Color(0.84, 0.64, 1.0, a * 1.15)
		draw_line(Vector2(x, y), Vector2(x - ln * 0.16, y + ln), col, 1.35)

	for sp in _splash_sparks:
		var k := clampf(float(sp["life"]) / maxf(float(sp["max_life"]), 0.01), 0.0, 1.0)
		var c: Color = sp["col"]
		c.a *= (1.0 - k)
		draw_circle(sp["pos"] as Vector2, lerpf(3.2, 0.8, k), c)


func _draw_ellipse(center: Vector2, rx: float, ry: float, col: Color, segs: int = 24) -> void:
	var pts := PackedVector2Array()
	for i in segs:
		var a := TAU * float(i) / float(segs)
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, col)


func _draw_ellipse_outline(center: Vector2, rx: float, ry: float, col: Color, width: float = 1.5, segs: int = 20) -> void:
	var pts := PackedVector2Array()
	for i in segs + 1:
		var a := TAU * float(i) / float(segs)
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	draw_polyline(pts, col, width)
