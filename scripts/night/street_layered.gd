extends Node2D
## 雨夜河岸街的分层背景（背景线 11-12，用户“做进游戏先”：把分层试验屏 tests/dev/preview_rain_layers.gd 做进游戏）。
## street_backdrop.gd 在布局里有 "layered" 时建这一层，挂在自己下面。
##
## 两部分：
## 1) 整条街的背景（换掉旧天空 / 远景城市 / 背街两排）：暗天、远景城、天际线钟楼、中景成图、两排中景专属楼
##    （暖窗、烟、乌鸦、月光边、楼脚雾）、三层流动雾、两层远处雨幕、后街路灯、闪电。按视差无限平铺，走到哪都有。
## 2) 开局入口街（第 0 处封印竞技场左边）：分层试验的站立层 + 门洞昼光、停在昼光里的雨、台面湿光和滴水、
##    灯下的雨、河面倒影、前景吊臂。能站的台面在布局第 0 段的 platforms 里（选项 {"layered": true}），灯在 lamps 里（第 5 项 {"layered": true}）。
##
## 坐标：所有背景件放在容器 bgw 里，bgw 以（门洞中心 anchor, 地面 580）为支点整体缩放 bg_k（11-12 用户定 0.75：建筑小一点），
## 人物、地面、水线不变。件的 x、y 是“镜头在 anchor、在街面取景时”的容器坐标，f 是视差（1 = 站立层）。
## 素材：tools/art/rain_layer_test_prep.py 出图 → tools/art/rain_layered_export.py 拷到 assets/image/rain_street/layered/。

const DIR := "res://assets/image/rain_street/layered/"
const DepthShader := preload("res://scripts/night/rain_layer_depth.gdshader")
const CurtainShader := preload("res://scripts/night/rain_layer_curtain.gdshader")
const LayerFogShader := preload("res://scripts/night/rain_layer_fog.gdshader")
const GlowShader := preload("res://scripts/night/rain_glow.gdshader")

const PX := 1.62                  ## 成图 1 像素 = 多少容器单位（和旧近景同比例，再按 bg_k 缩）
const ARCH_PX := 1248.0           ## 站立层成图里门洞中心的 x
const STREET_PX := 800.0          ## 站立层成图里脚踩的那一行
const CAM_Y := 272.3              ## 走在街面上时镜头中心的 y
const FLOOR := 580.0
const SKY_TOWER := Vector2(100.0, -630.0)    ## 天际线钟楼左上角（容器坐标，相对 anchor）
const SKY_TOWER_S := 0.6
const SKY_DROP := 260.0           ## 远景和中景整体往下压多少：给天际线钟楼留出天空
const FAR_HAZE := 0.5             ## 远近明暗阶梯：越往后越接近雾色
const MID_HAZE := 0.42
const ROW2_HAZE := 0.36
const ROW1_HAZE := 0.26
const ROW_PERIOD := 4800.0        ## 两排中景楼每隔这么宽（容器单位、各自视差下）重复一次
const BACK_LAMP_STEP := 760.0
const C_LIGHT := Color(1.0, 0.93, 0.78)
const C_LAMP := Color(1.0, 0.9, 0.72)
const RAIN_TILT := 0.1            ## 雨的斜度：每往下 1，往左 0.1
const LEDGE_SHEEN := Color(0.62, 0.72, 0.9)

## 11-17 背景线画面重构（用户“画面要商业级”→ 样板屏 scenes/dev/rain_redesign_sample.tscn 定稿后“接进正式游戏”）：
## 远景换成新天空 / 司辰母钟楼放大 / 远城 / 中城 / 后排街屋 + 两条雾带 + 远处白光柱；
## 入口街站立层换成同比例升级的三张近景（N3 | N2 | N1，从左到右），N1 的门洞对准 anchor，右边裁在楼和塔之间的巷缝，
## 右缘仍落在原接缝（edge_x ≈ 2018.2），所以门洞整体左移约 192。能站的台面 / 灯在两份布局的 layered 行里，按新图量好。
## 素材：tools/art/rain_redesign_codex.py 出图 → tools/art/rain_redesign_cutout.py 抠图到 RD_DIR（含 layers.json）。
var redesign := true             ## 开发对比用：环境变量 RAIN_OLD_BG=1 时回到 11-12 旧版（只给截图对比，游戏里不设）
const RD_DIR := "res://assets/image/rain_street/redesign_20261117/"
const RdDepthShader := preload("res://scripts/night/redesign/rd_depth.gdshader")
const RdFogShader := preload("res://scripts/night/redesign/rd_fog.gdshader")
const RD_FOG := Color(0.33, 0.4, 0.5)
const RD_WARM := Color(1.0, 0.72, 0.42)
const RD_SX0 := 100.0             ## 样板屏 x = 0 对应的正式游戏世界 x（出生点 300 − 样板出生点 200），远景构图和样板屏一致
const RD_N1_ARCH := 890.0         ## N1 成图里门洞中心的 x
const RD_N1_CROP := 1300.0        ## N1 裁到这里（门楼右沿，再往右是巷缝和塔）
const RD_VIS_W := 1280.0 / 0.65
const RD_SHAFTS := [[700.0, 420.0, 1.0], [1820.0, 240.0, 0.5]]
const RD_SHAFT_PERIOD := 3200.0
var rd_meta: Dictionary = {}
var rd_sky: Sprite2D
var rd_follow: Array = []         ## 跟镜头横移的雾带：{node, w, f, mat, ns}
var rd_far_shafts: Node2D
var rd_profile: Texture2D

var bd                            ## street_backdrop
var bg_k := 0.75
var anchor := 0.0                 ## 门洞中心（世界 x）
var edge_x := 0.0                 ## 入口街站立层的右边缘（世界 x）：再往右是钟楼广场的旧成图
var bgw: Node2D
var items: Array = []             ## {node, x, y, f, period, half}
var tiles: Array = []             ## 镜像平铺的整幅层：{nodes, x, y, f, tw}
var screen_fx: Array = []         ## 贴屏幕的雾 / 雨幕 / 闪电：{node, mat}
var lamps: Array = []             ## 站立层两盏灯的柔光：{node, a, sp}
var chain: Sprite2D
var beads: Array = []
var bead_tex: Texture2D
var glow_t: Texture2D
var bead_back: Node2D
var bead_front: Node2D
var refl: Node2D
var refl_src: Array = []
var lit_node: Node2D
var lit_src: Array = []
var lit_rain: Array = []
var ledge_node: Node2D
var drip_node: Node2D
var ledges: Array = []            ## 容器坐标
var drips: Array = []
var front_nodes: Array = []       ## 大招时藏起来的
var house_info := {}
var depth_mats: Array = []
var win_anim: Array = []
var smoke_src: Array = []
var puffs: Array = []
var smoke_nodes := {}
var crows: Array = []
var crow_nodes := {}
var curtains: Array = []
var flash_sky: Sprite2D
var flash_all: Sprite2D
var bolt_t := 6.0
var bolt_age := 99.0
var time := 0.0
var rng := RandomNumberGenerator.new()
var _through_mode := -1
var _through_size := 0.0
var _ch1_enabled := false
var _ch1_layer: Node2D
var _ch1_manifest: Dictionary = {}
var _ch1_tex_cache: Dictionary = {}
var _ch1_route_codes: Dictionary = {0: "1-1A", 1: "1-2B", 2: "1-3B"}


func setup(backdrop, cfg: Dictionary) -> void:
	bd = backdrop
	bg_k = float(cfg.get("k", 0.75))
	anchor = float(bd.first_x) + float(cfg.get("anchorRel", -2688.0))
	_ch1_enabled = bool(cfg.get("ch1ShadowStreet", false))
	if _ch1_enabled:
		bolt_t = 22.0
	redesign = OS.get_environment("RAIN_OLD_BG") != "1"
	if redesign:    # 新近景 N1 的右缘落在原接缝上：门洞跟着左移
		anchor += ((float(cfg.get("cropPx", 1500.0)) - ARCH_PX) - (RD_N1_CROP - RD_N1_ARCH)) * PX * bg_k
		edge_x = anchor + (RD_N1_CROP - RD_N1_ARCH) * PX * bg_k
	else:
		edge_x = to_world(Vector2(anchor + (float(cfg.get("cropPx", 1500.0)) - ARCH_PX) * PX, FLOOR)).x
	rng.seed = 20261112


func _ready() -> void:
	bgw = Node2D.new()
	bgw.scale = Vector2(bg_k, bg_k)
	bgw.position = Vector2(anchor, FLOOR) * (1.0 - bg_k)
	add_child(bgw)
	glow_t = _glow_tex()
	bead_tex = _bead_tex()
	var noise := NoiseTexture2D.new()
	noise.seamless = true
	noise.width = 512
	noise.height = 512
	var fn := FastNoiseLite.new()
	fn.frequency = 0.008
	fn.fractal_octaves = 4
	noise.noise = fn
	if redesign:
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(RD_DIR + "layers.json"))
		rd_meta = parsed if parsed is Dictionary else {}
		_build_world_rd(noise)
	else:
		_build_world(noise)
	_build_entry()
	if _ch1_enabled:
		_build_ch1_shadow_street()
		if redesign:
			_build_rd_1a()
	if ying_on and redesign:
		ying = preload("res://scripts/night/redesign/ying_look.gd").new()
		add_child(ying)
		ying.build(self)


# ---------------------------------------------------------------- 整条街的背景

func _build_world(noise: Texture2D) -> void:
	var top := FLOOR - STREET_PX * PX
	var sky_t := tex_at("res://assets/image/rain_street/sky.png")
	var sky_s := Vector2(3600.0 / sky_t.get_width(), 1700.0 / sky_t.get_height())
	add_tiles(sky_t, -1800.0, -900.0, sky_s, 0.05, -100, Color(0.5, 0.52, 0.6), 3600.0)
	add_glow(glow_t, 0.0, -60.0, 3000.0, 760.0, 0.0, -99, Color(0.42, 0.5, 0.68), 0.42)
	flash_sky = screen_quad(-99)    # 闪电照亮天：远处的楼都成黑剪影
	for sp in add_tiles(tex("far"), -1500.0, top - 470.0 * PX + SKY_DROP, Vector2(PX, PX), 0.10, -98, Color.WHITE, 1672.0 * PX):
		depth(sp, Color.WHITE, FAR_HAZE, 0.7, 0.0, 0.0, 0.0)
	# 天际线钟楼：比远景屋顶高出一大截，几乎钉在画面上，走动时在近处楼缝里时隐时现；钟室透月光，侧面表盘只一点暗红
	add(tex("sky_tower"), SKY_TOWER.x, SKY_TOWER.y, SKY_TOWER_S, 0.12, -97)
	add_glow(glow_t, SKY_TOWER.x + 275.0 * SKY_TOWER_S, SKY_TOWER.y + 525.0 * SKY_TOWER_S, 420.0 * SKY_TOWER_S, 300.0 * SKY_TOWER_S, 0.12, -97, Color(0.7, 0.8, 1.0), 0.12)
	add_glow(glow_t, SKY_TOWER.x + 482.0 * SKY_TOWER_S, SKY_TOWER.y + 670.0 * SKY_TOWER_S, 140.0 * SKY_TOWER_S, 200.0 * SKY_TOWER_S, 0.12, -97, Color(0.9, 0.3, 0.18), 0.05)
	for sp in add_tiles(tex("mid"), -1450.0, top - 300.0 * PX + SKY_DROP, Vector2(PX, PX), 0.35, -96, Color.WHITE, 1672.0 * PX):
		depth(sp, Color.WHITE, MID_HAZE, 0.75, 0.0, 0.35, 0.45)
	add_fog(-95, Color(0.14, 0.18, 0.28), 0.25, 0.012, 0.05, 0.85, 0.42, noise)
	add_curtain(-95, 0.3, 7.0, 0.32, 380.0, 40.0, 0.09, 0.0, 0.8, Color(0.55, 0.62, 0.8))    # 最远的一层雨幕：细、慢、淡
	# 两排中景专属楼（11-12 生成）：六栋各有身份；z 都在旧近景成图（−90）后面
	var ny := top + 60.0 * PX
	var ns := PX * 0.9
	var mr := RandomNumberGenerator.new()
	mr.seed = 1112
	var tint2 := Color(0.72, 0.74, 0.82)
	var info: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIR + "mid_houses.json"))
	house_info = info if info is Dictionary else {}
	mid_house("mh_a3", -2300.0, ny - 60.0, ns, 0.52, -94, false, tint2, ROW2_HAZE, 0.75, 1.4, 0.55, 0.5, 1, 1, mr)
	mid_house("mh_b2", -1200.0, ny - 40.0, ns, 0.52, -94, false, tint2, ROW2_HAZE, 0.75, 1.4, 0.55, 0.5, 1, 1, mr)
	mid_house("mh_b1", 560.0, ny - 50.0, ns, 0.52, -94, true, tint2, ROW2_HAZE, 0.75, 1.4, 0.55, 0.5, 2, 1, mr)
	add_fog(-93, Color(0.2, 0.25, 0.36), 0.55, 0.018, 0.0, 0.95, 0.42, noise)
	add_curtain(-93, 0.6, 11.0, 0.3, 620.0, 70.0, 0.09, 0.0, 0.9, Color(0.58, 0.65, 0.82))    # 中间一层雨幕
	mid_house("mh_a1", -1950.0, ny, ns, 0.68, -93, false, Color.WHITE, ROW1_HAZE, 0.85, 0.9, 0.45, 0.7, 3, 1, mr)
	mid_house("mh_a2", -950.0, ny + 20.0, ns, 0.68, -93, false, Color.WHITE, ROW1_HAZE, 0.85, 0.9, 0.45, 0.7, 1, 0, mr)
	mid_house("mh_b3", 200.0, ny + 30.0, ns, 0.72, -93, false, Color.WHITE, ROW1_HAZE, 0.85, 0.9, 0.45, 0.7, 3, 1, mr)
	mid_house("mh_a3", 1150.0, ny + 10.0, ns, 0.72, -93, true, Color.WHITE, ROW1_HAZE, 0.85, 0.9, 0.45, 0.7, 2, 1, mr)
	for s in smoke_src:
		_smoke_node(s.sp)
	for h in items:
		var nm := String(h.get("name", ""))
		if nm != "":
			var perch: Array = house_info.get(nm, {}).get("perch", [])
			if perch.size() > 0:
				add_crows(h.node, perch)
	# 后街的路灯：藏在中景楼脚，雾里一团暖光，从近处的楼缝里看得到
	var lx := -2300.0
	for i in 6:
		add_glow(glow_t, lx, 505.0, 320.0, 230.0, 0.7, -93, C_LAMP, 0.2, BACK_LAMP_STEP * 6.0)
		add_glow(glow_t, lx, 455.0, 34.0, 34.0, 0.7, -93, C_LAMP, 0.75, BACK_LAMP_STEP * 6.0)
		lx += BACK_LAMP_STEP
	add_fog(-92, Color(0.16, 0.2, 0.3), 0.75, 0.024, 0.1, 1.0, 0.3, noise)
	flash_all = screen_quad(40)
	front_nodes.append(flash_all)


# ---------------------------------------------------------------- 11-17 画面重构：远景栈 + 新近景

## 样板屏的世界坐标 → 本容器坐标（x 相对 anchor）。样板屏里一件东西在视差 f 下的屏幕位置是 xs − f·(镜头 x − RD_SX0)，
## 这里换算成同样的屏幕位置，所以构图、远近、走动时的错动都和样板屏一致
func rd_x(xs: float, f: float) -> float:
	return (xs + f * (RD_SX0 - anchor)) / bg_k


func rd_y(ys: float) -> float:
	return FLOOR + (ys - FLOOR) / bg_k


func _rd_depth(haze: float, darken := 1.0, base_fade := 0.0, base_start := 0.85, base_col := Color(0.05, 0.07, 0.1)) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = RdDepthShader
	m.set_shader_parameter("fog_color", RD_FOG)
	m.set_shader_parameter("haze", haze)
	m.set_shader_parameter("darken", darken)
	m.set_shader_parameter("base_fade", base_fade)
	m.set_shader_parameter("base_fade_start", base_start)
	m.set_shader_parameter("base_color", base_col)
	return m


## 横向雾带：y0..y1 是世界 y，跟着镜头横移，噪声按视差 f 慢慢流
func _rd_fog(y0: float, y1: float, f: float, tint: Color, density: float, nscale: Vector2, speed: float, z: int, noise: Texture2D) -> void:
	var r := ColorRect.new()
	var w := RD_VIS_W * 1.6
	r.size = Vector2(w, y1 - y0)
	r.position = Vector2(-w / 2.0, y0)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.z_as_relative = false
	r.z_index = z
	var m := ShaderMaterial.new()
	m.shader = RdFogShader
	m.set_shader_parameter("noise", noise)
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("density", density)
	m.set_shader_parameter("nscale", nscale)
	m.set_shader_parameter("speed", speed)
	m.set_shader_parameter("top_soft", 0.4)
	m.set_shader_parameter("bottom_soft", 0.4)
	r.material = m
	add_child(r)
	rd_follow.append({"node": r, "w": w, "f": f, "mat": m, "ns": nscale.x})


## 一层里的暖窗各配一团柔光（相近的合并）；ox、oy 是这层左上角在样板屏里的世界坐标
func _rd_layer_glows(code: String, ox: float, oy: float, s: float, size_k: float, gain: float, f: float, z: int, period: float) -> void:
	var pts: Array = []
	for l in rd_meta.get(code, {}).get("lights", []):
		var p := Vector2(float(l[0]), float(l[1]))
		var dup := false
		for q in pts:
			if q.distance_to(p) < 40.0:
				dup = true
				break
		if not dup:
			pts.append(p)
	for p in pts:
		var sz := 34.0 * s * size_k / bg_k
		add_glow(glow_t, rd_x(ox + p.x * s, f), rd_y(oy + p.y * s), sz, sz, f, z, RD_WARM, gain, period)


func _build_world_rd(noise: Texture2D) -> void:
	rd_profile = _profile_tex()
	# 天空：整张贴满屏幕
	rd_sky = Sprite2D.new()
	rd_sky.texture = tex_at(RD_DIR + "L1_sky.png")
	rd_sky.z_as_relative = false
	rd_sky.z_index = -100
	rd_sky.modulate = Color(0.86, 0.9, 0.95)    # 样板屏是 (0.95, 1, 1.08)，正式游戏跳上阳台露天多，压一点蓝
	add_child(rd_sky)
	screen_fx.append({"node": rd_sky, "mat": null})
	flash_sky = screen_quad(-99)    # 闪电照亮天：远处的楼都成黑剪影
	# 司辰母钟楼（用户定稿的天际线钟楼）：放大，几乎钉在天上
	var tower := add(tex("sky_tower"), rd_x(-640.0, 0.04), rd_y(-420.0), 1.3 / bg_k, 0.04, -98)
	tower.material = _rd_depth(0.46, 1.1)
	tower.modulate.a = 0.96
	# 远城（D2：换成一整条雾城 + 母钟楼 + 天顶白光，只替换最远这一层；中城、后排街屋照旧，楼缝里不会空到街面）
	if d2_on and _d2_has("far"):
		_build_far_d2()
	else:
		var m2: Dictionary = rd_meta.get("L2_far", {})
		var s2 := 1.7
		var t2 := tex_at(RD_DIR + "L2_far.png")
		var mat2 := _rd_depth(0.18, 1.05)
		for sp in add_tiles(t2, rd_x(0.0, 0.1), rd_y(-190.0 - float(m2.get("content_top", 0)) * s2), Vector2(s2, s2) / bg_k, 0.1, -97, Color.WHITE, t2.get_width() * s2 / bg_k, false):
			sp.material = mat2
	_rd_fog(160.0, 560.0, 0.15, Color(0.5, 0.58, 0.68, 1.0), 0.55, Vector2(1.5, 1.0), 0.004, -96, noise)
	if d2_on and _d2_has("behind_a"):    # D2：房子后面换成两层密的夜城天际线（亮窗零星）
		_build_behind_d2(noise)
		_build_vista_tower()
		return
	# 中城
	var m3: Dictionary = rd_meta.get("L3_mid", {})
	var s3 := 1.45
	var t3 := tex_at(RD_DIR + "L3_mid.png")
	var oy3 := 0.0 - float(m3.get("content_top", 0)) * s3
	var mat3 := _rd_depth(0.3, 1.0, 0.6, 0.6, RD_FOG)
	var tw3 := t3.get_width() * s3 / bg_k
	for sp in add_tiles(t3, rd_x(0.0, 0.26), rd_y(oy3), Vector2(s3, s3) / bg_k, 0.26, -95, Color.WHITE, tw3, false):
		sp.material = mat3
	_rd_layer_glows("L3_mid", 0.0, oy3, s3, 1.0, 0.35, 0.26, -95, tw3)
	add_curtain(-95, 0.3, 7.0, 0.32, 380.0, 40.0, 0.09, 0.0, 0.8, Color(0.55, 0.62, 0.8))    # 最远的一层雨幕：细、慢、淡
	_rd_fog(300.0, 680.0, 0.35, Color(0.42, 0.5, 0.6, 1.0), 0.6, Vector2(2.2, 1.0), 0.008, -94, noise)
	# 远处的白光柱（中城和后排街屋之间，慢）
	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	rd_far_shafts = _layer(self, -93, _rd_draw_far_shafts, add_mat)
	# 后排街屋：两栋一组，中间留空给中城和光柱
	var sF := 0.8
	var wa: float = float(rd_meta.get("L4a_facade", {}).get("size", [1672, 941])[0]) * sF
	var period := (wa * 2.0 + 1000.0 + 1500.0) / bg_k
	var oy4 := 630.0 - 866.0 * sF
	var mat4 := _rd_depth(0.27, 1.15, 0.85, 0.7, Color(0.12, 0.15, 0.2))
	for pair in [["L4a_facade", 0.0], ["L4b_facade", wa + 1000.0]]:
		var sp4 := add(tex_at(RD_DIR + String(pair[0]) + ".png"), rd_x(float(pair[1]), 0.52), rd_y(oy4), sF / bg_k, 0.52, -92, false, Color.WHITE, period)
		sp4.material = mat4
		_rd_layer_glows(String(pair[0]), float(pair[1]), oy4, sF, 1.6, 0.55, 0.52, -92, period)
	add_curtain(-92, 0.6, 11.0, 0.3, 620.0, 70.0, 0.09, 0.0, 0.9, Color(0.58, 0.65, 0.82))    # 中间一层雨幕
	flash_all = screen_quad(40)
	front_nodes.append(flash_all)


## D2 远景：一整条雾城（天、远城屋顶、母钟楼、天顶白光都在这张里），极慢视差；再加一层雾和一层远雨幕
const D2_TOWER_PX := 1737.0


## 用户 11-19：“你这个明显就一个很窄的长廊，房子后面明显什么也没有”——房子后面叠两层夜城：
## 远一层（视差 0.2，雾里、淡）+ 近一层（视差 0.5，密的屋顶 / 尖塔 / 烟囱，零星亮窗），屋脊都要高过前排房子，楼缝里看得见一整座城
func _build_behind_d2(noise: Texture2D) -> void:
	if _d2_has("behind_b"):
		var tb := tex_at(RD_D2_DIR + "behind_b.png")
		var sb := _envf_sl("D2_BB_S", 1.1)
		var mb := _rd_depth(_envf_sl("D2_BB_FOG", 0.4), 1.0)
		for sp in add_tiles(tb, rd_x(0.0, 0.2), rd_y(_envf_sl("D2_BB_Y", -437.0)), Vector2(sb, sb) / bg_k, 0.2, -96, Color(_envf_sl("D2_BB_LUM", 1.0), _envf_sl("D2_BB_LUM", 1.0) * 1.01, _envf_sl("D2_BB_LUM", 1.0) * 1.04), tb.get_width() * sb / bg_k, false):
			sp.material = mb
	# 远城与近城之间的流动雨雾（拉开后面两排夜城的空气透视，绝不再是平贴剪影）
	_rd_fog(120.0, 660.0, 0.3, Color(0.28, 0.30, 0.34, 1.0), 0.42, Vector2(2.0, 1.0), 0.010, -95, noise)
	add_curtain(-95, 0.3, 7.0, 0.32, 380.0, 40.0, 0.09, 0.0, 0.8, Color(0.55, 0.6, 0.68))
	var ta := tex_at(RD_D2_DIR + "behind_a.png")
	var sa := _envf_sl("D2_BA_S", 1.35)
	var ma := _rd_depth(_envf_sl("D2_BA_FOG", 0.12), 1.0)
	for sp in add_tiles(ta, rd_x(0.0, 0.5), rd_y(_envf_sl("D2_BA_Y", -540.0)), Vector2(sa, sa) / bg_k, 0.5, -92, Color(_envf_sl("D2_BA_LUM", 1.0), _envf_sl("D2_BA_LUM", 1.0), _envf_sl("D2_BA_LUM", 1.0) * 1.02), ta.get_width() * sa / bg_k, false):
		sp.material = ma
	# 近夜城与站立层之间的轻雾带（层与层之间有雾气流动）
	_rd_fog(220.0, 620.0, 0.65, Color(0.18, 0.19, 0.22, 1.0), 0.34, Vector2(2.6, 1.0), 0.016, -91, noise)
	add_curtain(-92, 0.6, 11.0, 0.3, 620.0, 70.0, 0.09, 0.0, 0.9, Color(0.55, 0.6, 0.7))
	# 11-19 贴着街面的低雾（慢慢横移，盖住墙根和街沿的接缝，站立层底部有空气感；不是水，不反光）
	_rd_fog(FLOOR - 90.0, FLOOR + 26.0, 1.0, Color(0.46, 0.47, 0.5, 1.0), _envf_sl("D2_MIST", 0.22), Vector2(3.2, 1.0), 0.02, -78, noise)
	# §3.1.1 拱洞深处暗巷底衬（z = -82，仅垫在低处拱洞高度 FLOOR-220..FLOOR+60，彻底消灭拱洞底灰白平板！）
	var arch_back := _layer(self, -82, _draw_d2_arch_dark_back)
	_d2_arch_back = arch_back
	flash_all = screen_quad(40)
	front_nodes.append(flash_all)


var _d2_arch_back: Node2D
var _d2_ambient: Node2D


func _draw_d2_arch_dark_back() -> void:
	if bd == null or bd.camera == null or _d2_arch_back == null:
		return
	var cx: float = bd.camera.get_screen_center_position().x
	var x0 := maxf(edge_x - 80.0, cx - 1400.0)
	var x1 := cx + 1400.0
	if x1 <= x0:
		return
	# 顶部柔和淡出、底部深炭暗巷，只遮住低处拱洞透出的远景亮雾，屋脊和上方夜城 100% 通透
	var pts := PackedVector2Array([
		Vector2(x0, FLOOR - 230.0), Vector2(x1, FLOOR - 230.0),
		Vector2(x1, FLOOR - 90.0), Vector2(x0, FLOOR - 90.0),
	])
	var cols := PackedColorArray([
		Color(0.035, 0.038, 0.046, 0.0), Color(0.035, 0.038, 0.046, 0.0),
		Color(0.035, 0.038, 0.046, 0.88), Color(0.035, 0.038, 0.046, 0.88),
	])
	_d2_arch_back.draw_polygon(pts, cols)
	_d2_arch_back.draw_rect(Rect2(x0, FLOOR - 90.0, x1 - x0, 180.0), Color(0.028, 0.030, 0.038, 0.96))


## 11-19 到 8 分：远景开口里的母钟楼（镇场大形）。从 far.png 裁出塔 + 塔后天光，边缘羽化，
## 放在近城（behind_a，z −92）后面、远城（behind_b，z −96）前面：塔脚藏进近城屋顶，塔身和天光从开口里整个露出来。
## 第一章还不知道光是坏的：它只是远处带天光的地标；不画正面钟盘、不加紫。D2_VTOWER=0 关。
func _build_vista_tower() -> void:
	if _envf_sl("D2_VISTA", 1.0) <= 0.0 or _envf_sl("D2_VTOWER", 1.0) <= 0.0:
		return
	var src := tex_at(RD_D2_DIR + "far.png").get_image()
	if src.is_compressed():
		src.decompress()
	src.convert(Image.FORMAT_RGBA8)
	var cw := 560
	var ch := 620
	var cx0 := int(D2_TOWER_PX) - cw / 2
	var img := src.get_region(Rect2i(cx0, 0, cw, ch))
	for yy in ch:    # 椭圆羽化：中心实、四周淡出，和后面同一张远景的云接上
		for xx in cw:
			var u := (float(xx) / float(cw) - 0.5) * 2.0
			var v := (float(yy) / float(ch) - 0.42) * 2.0
			var r := sqrt(u * u * 1.5 + v * v * 0.55)
			var a := 1.0 - smoothstep(0.45, 1.0, r)
			var c := img.get_pixel(xx, yy)
			# 塔身压成深色剪影、天光留亮：以 0.3 为支点拉反差（暗的更暗，亮的不动）
			var k := _envf_sl("D2_VT_K", 2.6)
			c.r = clampf((c.r - 0.3) * k + 0.3, 0.0, 1.0) if c.r < 0.3 else c.r
			c.g = clampf((c.g - 0.3) * k + 0.3, 0.0, 1.0) if c.g < 0.3 else c.g
			c.b = clampf((c.b - 0.3) * k + 0.3, 0.0, 1.0) if c.b < 0.3 else c.b
			c.a = a
			img.set_pixel(xx, yy, c)
	var t := ImageTexture.create_from_image(img)
	var f := _envf_sl("D2_VT_F", 0.12)
	var s := _envf_sl("D2_VT_S", 1.5)
	var cam_w := _envf_sl("D2_VT_CAM", (VISTA_X0 + VISTA_X1) * 0.5)    # 镜头走到开口中间时塔在屏幕正中
	var dxl := (cam_w - anchor) / bg_k
	var w := float(cw) * s
	var top_w := _envf_sl("D2_VT_TOP", -230.0)    # 塔图上沿的世界 y
	var lum := _envf_sl("D2_VT_LUM", 1.0)
	var tsp := add(t, f * dxl - w * 0.5, rd_y(top_w), s, f, int(_envf_sl("D2_VT_Z", -90.0)), false, Color(lum * 0.94, lum * 0.96, lum))
	var km := ShaderMaterial.new()    # 只在开口那段露：塔在近城前面，不加这道会从别处楼缝漏出半截光晕
	km.shader = VistaCutSh
	km.set_shader_parameter("cut_x0", VISTA_X0 - 380.0)    # 开口左边原画本来就有一块天，硬切会在天上留一道竖边：放宽 + 长羽化
	km.set_shader_parameter("cut_x1", VISTA_X1 + 160.0)
	km.set_shader_parameter("feather_x", 320.0)
	km.set_shader_parameter("keep_inside", 1.0)
	tsp.material = km


func _build_far_d2() -> void:
	var t := tex_at(RD_D2_DIR + "far.png")
	var s := _envf_sl("D2_FAR_S", 1.2)
	var tw := t.get_width() * s / bg_k
	var oy := _envf_sl("D2_FAR_Y", -424.0)    # 远城屋脊落在二层步廊上方一点：楼缝里看得见远城，塔尖在屏幕上沿
	var mat := _rd_depth(_envf_sl("D2_FAR_FOG", 0.3), 1.0)
	# 母钟楼在长条里约 x = TOWER_PX；放到 1-1A 一路都在屏幕右半（和 2D 版钟楼同一视差 0.04）
	for sp in add_tiles(t, rd_x(_envf_sl("D2_FAR_X", 650.0) - D2_TOWER_PX * s, 0.04), rd_y(oy), Vector2(s, s) / bg_k, 0.04, -97, Color(_envf_sl("D2_FAR_LUM", 1.05) * 0.9, _envf_sl("D2_FAR_LUM", 1.05) * 0.92, _envf_sl("D2_FAR_LUM", 1.05) * 0.95), tw, false):
		sp.material = mat
	# 塔后天顶白光（远景比近处亮：前暗后亮的纵深）
	add_glow(glow_t, rd_x(_envf_sl("D2_FAR_X", 650.0), 0.04), rd_y(oy + 140.0 * s), 1500.0 / bg_k, 1100.0 / bg_k, 0.04, -96, Color(0.92, 0.94, 0.97), _envf_sl("D2_GLOW", 0.14))


## 远处白光柱（样板屏 Parallax2D(0.45) 里那几道，按同样的屏幕位置画在世界坐标里）
func _rd_draw_far_shafts() -> void:
	if bd == null or bd.camera == null:
		return
	var cam: Vector2 = bd.camera.get_screen_center_position()
	var base := cam.x - 0.45 * (cam.x - RD_SX0)
	var period := RD_SHAFT_PERIOD * 0.9
	var k0 := floori((cam.x - RD_VIS_W - base) / period) - 1
	var k1 := ceili((cam.x + RD_VIS_W - base) / period) + 1
	for k in range(k0, k1 + 1):
		for s in RD_SHAFTS:
			var cx_b: float = base + k * period + float(s[0]) * 0.8
			var w_b: float = float(s[1]) * 0.55
			var top := -440.0
			var bot := 900.0
			var cx_t := cx_b - 0.3 * (bot - top)
			var w_t := w_b * 0.72
			var mid := lerpf(top, bot, 0.55)
			var cxm := lerpf(cx_t, cx_b, 0.55)
			var wm := lerpf(w_t, w_b, 0.55)
			var a: float = float(s[2]) * 0.7 * (0.9 + 0.1 * sin(time * 0.7 + k * 1.3 + float(s[0])))
			var c0 := Color(0.82, 0.9, 1.0, 0.0)
			var c1 := Color(0.82, 0.9, 1.0, 0.17 * a)
			var c2 := Color(0.9, 0.95, 1.0, 0.26 * a)
			rd_far_shafts.draw_polygon(
				PackedVector2Array([Vector2(cx_t - w_t / 2, top), Vector2(cx_t + w_t / 2, top), Vector2(cxm + wm / 2, mid), Vector2(cx_b + w_b / 2, bot), Vector2(cx_b - w_b / 2, bot), Vector2(cxm - wm / 2, mid)]),
				PackedColorArray([c0, c0, c1, c2, c2, c1]),
				PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 0.5), Vector2(1, 1), Vector2(0, 1), Vector2(0, 0.5)]),
				rd_profile)


## 整屏夜色后期（night_post.gdshader，光影线）默认压暗 0.9、对比 1.18、暗部偏蓝、天顶和四角压暗：
## 新近景的银灰石墙被它压成深蓝（用户 11-17：“背景和起点街区变蓝了”，要和样板屏一样）。
## 入口街这一段把它往样板屏的调色（rd_grade：轻 S 曲线、暗部微冷、暗角 0.38）收；过了接缝 edge_x 慢慢回到原值，第一章影街不受影响。
const RD_POST := {
	"exposure": [0.9, 1.0], "contrast": [1.18, 1.04], "sat": [1.08, 1.0],
	"shadow_tint": [Vector3(0.88, 0.96, 1.08), Vector3(0.95, 0.985, 1.03)],
	"vig_amt": [0.46, 0.38], "vig_top": [0.18, 0.04], "vig_bottom": [0.34, 0.3],
}
var _rd_post_mat: ShaderMaterial
var _rd_post_w := -1.0


func _rd_post_grade(cam_x: float) -> void:
	if _rd_post_mat == null:
		var stage: Node = bd.get_parent()
		var post = stage.get("post") if stage != null else null
		if post == null or post.get("mat") == null:
			return
		_rd_post_mat = post.mat
	var w := 1.0 - clampf((cam_x - (edge_x - 200.0)) / 800.0, 0.0, 1.0)
	if absf(w - _rd_post_w) < 0.002:
		return
	_rd_post_w = w
	for k in RD_POST:
		var pair: Array = RD_POST[k]
		_rd_post_mat.set_shader_parameter(k, lerp(pair[0], pair[1], w))


static func _profile_tex() -> Texture2D:
	var t := GradientTexture2D.new()
	t.width = 128
	t.height = 4
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.5, Color(1, 1, 1, 1))
	g.add_point(0.3, Color(1, 1, 1, 0.55))
	g.add_point(0.7, Color(1, 1, 1, 0.55))
	t.gradient = g
	return t


## 脚踩的那一行：新图用“第一行整行不透明”再加上原站立层同样量出来的差值（800 − 787）
func _rd_street_row(code: String) -> float:
	var r := float(rd_meta.get(code, {}).get("street_row", -1))
	if r < 0.0:
		return STREET_PX
	return r + (STREET_PX - float(rd_meta.get("stand", {}).get("street_row", STREET_PX)))


## 入口街新近景：N1（门洞对准 anchor，裁到 RD_N1_CROP）往左接 N2、N3；暖窗各一团柔光，灯下一片暖光池
func _build_rd_near(lamp_w: Array) -> void:
	var x := -RD_N1_ARCH * PX
	var first := true
	for code in ["N1_near", "N2_near", "N3_near"]:
		var t := tex_at(RD_DIR + code + ".png")
		if not first:
			x -= t.get_width() * PX
		var top := FLOOR - _rd_street_row(code) * PX
		var sp := add(t, x, top, PX, 1.0, -80)
		if first:
			sp.region_enabled = true
			sp.region_rect = Rect2(0.0, 0.0, RD_N1_CROP, t.get_height())
		var kept: Array = []
		for l in rd_meta.get(code, {}).get("lights", []):
			if first and float(l[0]) > RD_N1_CROP - 8.0:
				continue
			var dup := false
			for q in kept:
				if absf(float(q[0]) - float(l[0])) < 70.0 and absf(float(q[1]) - float(l[1])) < 70.0:
					dup = true
					break
			if not dup:
				kept.append(l)
		for l in kept:
			var lx := x + float(l[0]) * PX
			var ly := top + float(l[1]) * PX
			var wp := to_world(Vector2(anchor + lx, ly))
			var by_lamp := false
			for lp in lamp_w:
				if (lp as Vector2).distance_to(wp) < 60.0:
					by_lamp = true
					break
			if by_lamp:
				continue    # 灯本身由下面的灯光柔光画
			var sz := maxf(70.0, float(l[2]) * PX * bg_k * 3.0) / bg_k
			add_glow(glow_t, lx, ly, sz, sz, 1.0, -78, C_LAMP, 0.14)
		first = false
	for lp in lamp_w:    # 灯照到街面上的暖光
		var lc := to_local_bg(lp)
		add_glow(glow_t, lc.x - anchor, FLOOR + 6.0 / bg_k, 320.0 / bg_k, 46.0 / bg_k, 1.0, -4, C_LAMP, 0.13)


# ---------------------------------------------------------------- 1-1A「灯影空轿街」上下两层街样板角（11-18，方向丙）
## 和入口街 N1～N3 同一比例，紧接 N1 右缘往右铺到 1-1A 尾；slot0 换成别的段时整组隐藏，影街三联画照常画。

const RD_1A_DIR := "res://assets/image/rain_street/ch1_1a_two_level/"
## 11-19 背景线 D2「前景压框三层景深」（用户选 D2，看完夜城版说“对了”“设为默认”——默认开；RAIN_BG=OLD 退回旧背景）：
## 站立层换成按 D2 画质重绘的 B1～B3（结构不动）、远景换成一条雾城长条、镜头跟前加一层虚化的暗栏杆 / 石柱、站立层后面整体糊掉。
const RD_D2_DIR := "res://assets/image/rain_street/ch1_1a_d2/"
var d2_on := OS.get_environment("RAIN_BG") != "OLD"


func _d2_has(n: String) -> bool:
	return ResourceLoader.exists(RD_D2_DIR + n + ".png") or FileAccess.file_exists(RD_D2_DIR + n + ".png")


func _rd_1a_tex(code: String) -> Texture2D:
	if d2_on:
		var p := RD_D2_DIR + code + ".png"
		if ResourceLoader.exists(p) or FileAccess.file_exists(p):
			return tex_at(p)
	return tex_at(RD_1A_DIR + code + ".png")
var rd_1a_nodes: Array = []
var rd_1a_on := false
var rd_j1_on := false      ## J1 岔路换成同比例新图后，影街层不再画旧 j_fork


func _build_rd_1a() -> void:
	var path := RD_1A_DIR + "tiles.json"
	if not FileAccess.file_exists(path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		return
	var meta: Dictionary = parsed
	var lamp_w: Array = []
	var secs: Array = bd.layout.get("sections", [])
	if not secs.is_empty() and secs[0] is Dictionary:
		for l in secs[0].get("lamps", []):
			if not (l.size() > 4 and l[4] is Dictionary and l[4].get("layered", false)):
				lamp_w.append(Vector2(float(bd.first_x) + float(l[0]), float(l[1]) - (float(l[3]) if l.size() > 3 else 112.0)))
	var x := (RD_N1_CROP - RD_N1_ARCH) * PX    # N1 裁切右缘（容器坐标，相对 anchor）
	var n0 := items.size()
	var x_start := x
	if d2_on and _d2_ambient == null:
		_d2_ambient = preload("res://scripts/night/redesign/d2_ambient_fx.gd").new()
		_d2_ambient.call("setup", self)
		add_child(_d2_ambient)
	for code in ["B1", "B2", "B3"]:
		if meta.has(code):
			x = _rd_place_tile(code, meta[code], x, lamp_w)
	if relief_mode in ["A", "AB"] or d2_on:
		_rd_fg_layer(x_start, x)
	for i in range(n0, items.size()):
		rd_1a_nodes.append(items[i].node)
	rd_1a_on = true
	_set_rd_1a(String(_ch1_route_codes.get(0, "1-1A")) == "1-1A")
	# J1 街口高低分流岔路：不管首段走 1-1A 还是 1-1B 都在（接在首段尾 first_x+2440 往右）
	if meta.has("C1"):
		rd_j1_on = true
		_rd_place_tile("C1", meta["C1"], (float(bd.first_x) + 2440.0 - anchor) / bg_k, lamp_w)
	# §3.1.2 + §3.4：有厚度的哥特石街沿横条（顶面湿石 + 立体石街沿 + 下方粗石挡墙与排水拱券），
	# 放在 z = -79 贯穿整条街（不随 1-1A 隐藏、不在 J1 断掉，彻底消灭底部 1/5 死黑带！）
	if d2_on and (_d2_has("street_thick") or _d2_has("street")):
		var st_name := "street_thick" if _d2_has("street_thick") else "street"
		var st := tex_at(RD_D2_DIR + st_name + ".png")
		var sh_h := _envf_sl("D2_STREET_H", 380.0 if st_name == "street_thick" else 300.0)
		var ss := sh_h / float(st.get_height())
		var sy := FLOOR + _envf_sl("D2_STREET_Y", 4.0 if st_name == "street_thick" else 118.0)
		add_tiles(st, 0.0, sy, Vector2(ss, ss), 1.0, -79, Color(0.76, 0.75, 0.74), st.get_width() * ss, false)
		# 11-19 返工：street_backdrop 的雨点涟漪在这条厚街面上读成"一排白圈 / 积水"，压到很淡
		var gnd: Variant = bd.get("_ground")
		if gnd is Node2D and (gnd as Node2D).material is ShaderMaterial:
			((gnd as Node2D).material as ShaderMaterial).set_shader_parameter("strength", _envf_sl("D2_RIPPLE", 0.25))


## 铺一张同比例站立层（裁切 + 每张微缩放 + 街下石墙下延 + 窗灯柔光），返回右缘容器 x（相对 anchor）
func _rd_place_tile(code: String, m: Dictionary, x: float, lamp_w: Array) -> float:
	var t := _rd_1a_tex(code)
	var crop: Array = m.get("crop", [0, t.get_width()])
	var c0 := float(crop[0])
	var c1 := float(crop[1])
	var ps := PX * float(m.get("scale", 1.0))    # 每张微缩放，让街面和步廊面在几张之间都对齐
	var sr := float(m.get("street_row", 810))
	var top := FLOOR - sr * ps
	var sp := add(t, x, top, ps, 1.0, -80)
	sp.region_enabled = true
	sp.region_rect = Rect2(c0, 0.0, c1 - c0, t.get_height())
	rd_tiles.append({"sp": sp, "code": code})
	if d2_on and _envf_sl("D2_VISTA", 1.0) > 0.0:    # 11-19 到 8 分：远景开口（vista_cut.gdshader，玩法线确认方案 A）
		var vm := ShaderMaterial.new()
		vm.shader = VistaCutSh
		vm.set_shader_parameter("cut_x0", VISTA_X0)
		vm.set_shader_parameter("cut_x1", VISTA_X1)
		vm.set_shader_parameter("cut_y", _envf_sl("D2_VISTA_Y", VISTA_Y))
		sp.material = vm
	if s3d_on:    # 11-19 3D 街体：原画按真实比例立到街对面，2D 这张、下延、窗灯柔光都不画
		_s3d_card(t, sp, c0, c1, sr, x, top, ps, lamp_w)
		return x + (c1 - c0) * ps
	# 街下石墙往下再接两截（越往下越暗），屏幕下沿不再是一条死黑带（第一章往东零水面，不接入口街的倒影）
	var band := float(t.get_height()) - (sr + 24.0)
	for j in (0 if d2_on and _d2_has("street") else 2):    # D2：下面换成一整条湿石板街面（_build_rd_1a 里铺）
		var ext := add(t, x, top + (float(t.get_height()) + band * j) * ps, ps, 1.0, -80, false, Color(0.5 - 0.22 * j, 0.52 - 0.22 * j, 0.58 - 0.22 * j))
		ext.region_enabled = true
		ext.region_rect = Rect2(c0, sr + 24.0, c1 - c0, band)
	var kept: Array = []
	var img: Image = t.get_image() if d2_on else null    # 11-19 重构返工：上半截熄了灯的窗不再挂光晕（不然暗处飘光点）
	if img != null and img.is_compressed():
		img.decompress()
	for l in m.get("lights", []):
		if float(l[0]) < c0 + 6.0 or float(l[0]) > c1 - 6.0:
			continue
		if img != null and _rd_img_lum(img, int(l[0]), int(l[1])) < 0.45:
			continue
		var lw := to_world(Vector2(anchor + x + (float(l[0]) - c0) * ps, top + float(l[1]) * ps))
		if _in_vista(lw):
			continue    # 开口里那截楼已挖掉，窗灯不能飘在夜空里
		var by_lamp := false
		for lp in lamp_w:
			if (lp as Vector2).distance_to(lw) < 60.0:
				by_lamp = true
				break
		if by_lamp:
			continue    # 布局里的灯自带会闪的柔光
		var dup := false
		for q in kept:
			if absf(float(q[0]) - float(l[0])) < 70.0 and absf(float(q[1]) - float(l[1])) < 70.0:
				dup = true
				break
		if not dup:
			kept.append(l)
	for l in kept:
		var sz := maxf(70.0, float(l[2]) * PX * bg_k * 3.0) / bg_k
		add_glow(glow_t, x + (float(l[0]) - c0) * ps, top + float(l[1]) * ps, sz, sz, 1.0, -78, C_LAMP, 0.14)
	if relief_on:
		_rd_relief(code, sp, x, x + (c1 - c0) * ps, lamp_w, kept, c0, top, ps)
	elif d2_on:
		_rd_d2_true_lights(code, x, x + (c1 - c0) * ps, lamp_w, kept, c0, top, ps)
	return x + (c1 - c0) * ps


## 站立层原图上某点附近（5×5）的平均亮度：窗还亮着才挂光晕和点光
static func _rd_img_lum(img: Image, px: int, py: int) -> float:
	var s := 0.0
	var n := 0
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var x := clampi(px + dx * 2, 0, img.get_width() - 1)
			var y := clampi(py + dy * 2, 0, img.get_height() - 1)
			var c := img.get_pixel(x, y)
			s += c.r * 0.299 + c.g * 0.587 + c.b * 0.114
			n += 1
	return s / float(n)


## §3.3 真灯光：给 D2 站立层每盏焦点街灯与底层主亮窗挂上真实 PointLight2D（照到角色、带闪烁、在湿街面拉出竖向湿光）
func _rd_d2_true_lights(_code: String, x0: float, x1: float, lamp_w: Array, wins: Array, c0: float, top: float, ps: float) -> void:
	var placed: Array = []
	for lp in lamp_w:
		var lc := to_local_bg(lp as Vector2)
		if lc.x < anchor + x0 - 40.0 or lc.x > anchor + x1 + 40.0:
			continue
		var pl := _relief_light(lc, Color(1.0, 0.84, 0.56), 0.48, 2.6, 120.0)
		relief_lamps.append({"light": pl, "e": 0.48, "sp": rng.randf_range(6.4, 9.2)})
		placed.append(lc)
		if _d2_ambient != null:
			_d2_ambient.call("register_lamp", (lp as Vector2).x, (lp as Vector2).y, rng.randf_range(6.4, 9.2), 1.0)
	# 底层亮橱窗与壁灯（仅取人走活动带附近、互不重叠的焦点窗，避免处处过亮）
	for l in wins:
		var lc := Vector2(anchor + x0 + (float(l[0]) - c0) * ps, top + float(l[1]) * ps)
		var lw := to_world(lc)
		if lw.y < 320.0 or lw.y > FLOOR + 10.0:
			continue
		var too_close := false
		for p0 in placed:
			if (p0 as Vector2).distance_to(lc) < 280.0:
				too_close = true
				break
		if too_close:
			continue
		var pl2 := _relief_light(lc, Color(1.0, 0.80, 0.48), 0.38, 2.2, 100.0)
		relief_lamps.append({"light": pl2, "e": 0.38, "sp": rng.randf_range(5.2, 8.1)})
		placed.append(lc)
		if _d2_ambient != null:
			_d2_ambient.call("register_lamp", lw.x, lw.y, rng.randf_range(5.2, 8.1), 0.78)


# ---------------------------------------------------------------- 11-18 立体感试验（RAIN_DEPTH=1 才开）
## 站立层每张图配一张深度图 + 法线图（tools/art/bg_depth_normal_codex.py 出图 → bg_relief_prep.py 对齐）：
## 底色压暗、按深度进雾；布局里的灯和窗灯换成真 2D 点光源，按法线照出石块、拱券、栏杆的起伏；主角身上一盏跟随的冷光。
## RAIN_DEPTH=1 只加法线光；=A 路线 A「切块分层」（前景层 + 远处糊板 + 法线光）；=B 路线 B「投影浮雕」（3D 子画面）；=AB 两条合在一起（站立层 3D 浮雕 + 前景层 + 糊板）
var relief_mode := OS.get_environment("RAIN_DEPTH")
var s3d_on := OS.get_environment("RAIN_3D") in ["1", "U2"]    ## 11-19 3D 街体（见 redesign/street_3d.gd；U2 = redesign/street_hd2d.gd 全建模版）
var s3d_u2 := OS.get_environment("RAIN_3D") == "U2"
var street3d: Node2D


func _s3d_card(t: Texture2D, sp: Sprite2D, c0: float, c1: float, sr: float, x: float, top: float, ps: float, lamp_w: Array) -> void:
	if s3d_u2:    # U2：近处的街全部 3D 建模，原画不再用，只记这一段的范围
		if street3d == null:
			street3d = preload("res://scripts/night/redesign/street_hd2d.gd").new()
			add_child(street3d)
			street3d.setup(-80, FLOOR)
		sp.visible = false
		var tl0 := to_world(Vector2(anchor + x, top))
		street3d.set_range(tl0.x, tl0.x + (c1 - c0) * ps * bg_k)
		return
	if street3d == null:
		street3d = preload("res://scripts/night/redesign/street_3d.gd").new()
		add_child(street3d)
		street3d.setup(-80, FLOOR)
	sp.visible = false
	var tw := float(t.get_width())
	var th := float(t.get_height())
	var tl := to_world(Vector2(anchor + x, top))
	var sz := Vector2((c1 - c0) * ps, th * ps) * bg_k
	street3d.add_card(t, Rect2(c0 / tw, 0.0, (c1 - c0) / tw, 1.0), Rect2(tl, sz), sr / th)
	var x0w := tl.x
	var x1w := tl.x + sz.x
	for lp in lamp_w:
		var v := lp as Vector2
		if v.x >= x0w and v.x <= x1w:
			street3d.add_lamp(v)
const VistaCutSh := preload("res://scripts/night/redesign/vista_cut.gdshader")
const VISTA_X0 := 3432.0    ## 玩法线 11-19：世界 x 3432～4347 三层以上无碰撞，两端的三层平台画面要留
const VISTA_X1 := 4347.0
const VISTA_Y := 222.0      ## 世界 y：二层栏杆顶，以上挖掉


func _in_vista(w: Vector2) -> bool:
	return d2_on and _envf_sl("D2_VISTA", 1.0) > 0.0 and w.x > VISTA_X0 and w.x < VISTA_X1 and w.y < _envf_sl("D2_VISTA_Y", VISTA_Y)


var rd_tiles: Array = []          ## 每张同比例站立层：{sp, code}（影街墨影要叠在上面）
## 11-18 影街「影 2 影流向钟楼」（用户选定）：11-19 随 D2 一起设为默认（D2 的调色、去墨带都在 ying_look 里）；RAIN_LOOK=OLD 关掉，见 redesign/ying_look.gd
var ying_on := OS.get_environment("RAIN_LOOK") != "OLD"
var ying: Node2D
var relief_on := relief_mode in ["1", "A", "B", "AB"]
var relief3d: Node2D
var relief_player_light: PointLight2D
var relief_lamps: Array = []      ## {light, e, sp}
var _relief_tex: Texture2D

func _relief_light(pos: Vector2, col: Color, energy: float, scl: float, h: float) -> PointLight2D:
	if _relief_tex == null:
		var g := GradientTexture2D.new()
		g.width = 256
		g.height = 256
		g.fill = GradientTexture2D.FILL_RADIAL
		g.fill_from = Vector2(0.5, 0.5)
		g.fill_to = Vector2(1.0, 0.5)
		var gr := Gradient.new()
		gr.set_color(0, Color(1, 1, 1, 1))
		gr.set_color(1, Color(1, 1, 1, 0))
		gr.add_point(0.25, Color(0.75, 0.75, 0.75, 1))
		gr.add_point(0.6, Color(0.22, 0.22, 0.22, 1))
		g.gradient = gr
		_relief_tex = g
	var l := PointLight2D.new()
	l.texture = _relief_tex
	l.texture_scale = scl
	l.color = col
	l.energy = energy
	l.height = h
	l.range_z_min = -85        # 只照站立层、灯光柔光和角色，不照远景
	l.range_z_max = 200
	l.position = pos
	bgw.add_child(l)
	return l


func _rd_relief(code: String, sp: Sprite2D, x0: float, x1: float, lamp_w: Array, wins: Array, c0: float, top: float, ps: float) -> void:
	var dp := RD_1A_DIR + code + "_depth.png"
	var np := RD_1A_DIR + code + "_normal.png"
	if not (ResourceLoader.exists(np) or FileAccess.file_exists(np)):
		return
	var ct := CanvasTexture.new()
	ct.diffuse_texture = sp.texture
	ct.normal_texture = tex_at(np)
	ct.specular_color = Color(0.55, 0.6, 0.7)
	ct.specular_shininess = 0.55
	sp.texture = ct
	var m := ShaderMaterial.new()
	m.shader = preload("res://scripts/night/redesign/rd_relief.gdshader")
	m.set_shader_parameter("depth_tex", tex_at(dp))
	sp.material = m
	if relief_mode in ["B", "AB"]:
		var lamps3: Array = []
		var wins3: Array = []
		for lp in lamp_w:
			var lc0 := to_local_bg(lp)
			if lc0.x - anchor >= x0 and lc0.x - anchor <= x1:
				lamps3.append(lp)
		for w in wins:
			wins3.append(to_world(Vector2(anchor + x0 + (float(w[0]) - c0) * ps, top + float(w[1]) * ps)))
		var diff: Texture2D = ct.diffuse_texture
		var tw := float(diff.get_width())
		var reg := sp.region_rect
		var tl := to_world(Vector2(anchor + x0, top))
		var sz := Vector2(reg.size.x * ps, reg.size.y * ps) * bg_k
		if relief3d == null:
			relief3d = preload("res://scripts/night/redesign/relief_3d.gd").new()
			add_child(relief3d)
			relief3d.setup(-80)
		var dsoft := RD_1A_DIR + code + "_depth_soft.png"    # 只留大形的柔化深度：细栏杆不被挤成糊块
		if not (ResourceLoader.exists(dsoft) or FileAccess.file_exists(dsoft)):
			dsoft = dp
		relief3d.add_tile(diff, tex_at(dsoft), tex_at(np), Rect2(reg.position.x / tw, 0.0, reg.size.x / tw, 1.0), Rect2(tl, sz), lamps3, wins3)
		sp.self_modulate.a = 0.0    # 2D 那张藏起来（2D 灯仍照角色）
	for lp in lamp_w:
		var lc := to_local_bg(lp)
		if lc.x - anchor < x0 or lc.x - anchor > x1:
			continue
		var l := _relief_light(lc, Color(1.0, 0.8, 0.55), 1.7, 3.4, 60.0)
		relief_lamps.append({"light": l, "e": 1.7, "sp": rng.randf_range(4.0, 7.0)})
	for w in wins:    # 窗里的灯：小、暖、贴墙（高度低 → 只擦亮窗框和窗台）
		var l := _relief_light(Vector2(anchor + x0 + (float(w[0]) - c0) * ps, top + float(w[1]) * ps), Color(1.0, 0.74, 0.45), 0.9, 1.4, 25.0)
		relief_lamps.append({"light": l, "e": 0.9, "sp": rng.randf_range(1.0, 2.0)})
	if relief_player_light == null:
		relief_player_light = _relief_light(Vector2.ZERO, Color(0.62, 0.72, 1.0), 0.6, 2.4, 80.0)
		var moon := DirectionalLight2D.new()    # 左上方的冷月光：每个朝上、朝左的面都擦出一道冷亮边
		moon.color = Color(0.6, 0.72, 1.0)
		moon.energy = 0.32
		moon.height = 0.35
		moon.rotation = deg_to_rad(-35.0)
		moon.range_z_min = -85
		moon.range_z_max = -70
		bgw.add_child(moon)


## 路线 A：镜头最前面的遮挡件（视差 1.4，走得比站立层快；暗、离焦、压在角色前面）+ 站立层背后一块“糊板”。
## 件来自 FG1.png（tools/art/bg_foreground_codex.py → bg_foreground_cutout.py）：0 石柱 1 路灯杆 2 栏杆 3 断拱 4 碎石堆
const FG_SEQ := [[4, "bottom", 1.35], [3, "top", 1.25], [1, "full", 1.75], [2, "bottom", 1.2], [0, "full", 1.75]]    ## 碎石打头：起点楼梯口别被石柱整根挡住
const FG_F := 1.4
var relief_fg: Array = []    ## 前景件：角色走到后面时淡成半透明，不挡人
const FG_STEP := 950.0      ## 容器单位（≈ 710 世界单位），一屏里最多一两件

## D2 前景件：[件号, 位置, 目标高（容器单位）]；full = 从屏幕上沿外长到下沿外的整根柱子
const FG_SEQ_D2 := [[0, "bottom", 520.0], [3, "bottom", 440.0], [0, "bottom", 520.0], [2, "bottom", 480.0]]    ## 11-19 用户“背景怪怪的”：整根石柱常竖在画面正中，去掉


func _rd_fg_layer(x_start: float, x_end: float) -> void:
	if d2_on and (ResourceLoader.exists(RD_D2_DIR + "fg_0.png") or FileAccess.file_exists(RD_D2_DIR + "fg_0.png")):
		_rd_fg_layer_d2(x_start, x_end)
		return
	var path0 := RD_1A_DIR + "fg_0.png"
	if not (ResourceLoader.exists(path0) or FileAccess.file_exists(path0)):
		return
	var sh := preload("res://scripts/night/redesign/fg_near.gdshader")
	var k := 0
	var lx := x_start + 520.0
	while lx < x_end - 200.0:
		var e: Array = FG_SEQ[k % FG_SEQ.size()]
		var t := tex_at(RD_1A_DIR + "fg_%d.png" % int(e[0]))
		var s := float(e[2])
		var w := t.get_width() * s
		var h := t.get_height() * s
		var y := -620.0                 # 屏幕上沿约 −570（街面镜头），整根件从上沿外长到下沿外
		if String(e[1]) == "bottom":
			y = 990.0 - h               # 从屏幕下沿长出来，盖住街下那条暗带
		var flip := (k / FG_SEQ.size()) % 2 == 1
		# 镜头在 lx 时这件正好居中：容器 x = f·lx（见 _process 里 x + dx·(1 − f)）
		var sp := add(t, FG_F * lx - w * 0.5, y, s, FG_F, 30, flip, Color(0.3, 0.33, 0.41))
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("blur", 2.6)
		sp.material = m
		front_nodes.append(sp)
		relief_fg.append(sp)
		lx += FG_STEP
		k += 1
	# 糊板：先抓一次屏幕（此时只画完了 z < −81 的远景栈），再盖一张糊过的回去
	var bb := BackBufferCopy.new()
	bb.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	bb.z_as_relative = false
	bb.z_index = -81
	add_child(bb)
	var q := _white_quad(-81)
	var bm := ShaderMaterial.new()
	bm.shader = preload("res://scripts/night/redesign/blur_plane.gdshader")
	q.material = bm
	screen_fx.append({"node": q, "mat": null})


func _rd_fg_layer_d2(x_start: float, x_end: float) -> void:
	var sh := preload("res://scripts/night/redesign/fg_near.gdshader")
	var k := 0
	# §3.4 前景改稀疏大剪影：每两三屏才快速掠过一次（默认间距 2400），不再底边连成一排糊栏杆
	var lx := x_start + 1350.0
	var step := float(_envf_sl("D2_FG_STEP", 2400.0))
	while lx < x_end + 1800.0:
		var e: Array = FG_SEQ_D2[k % FG_SEQ_D2.size()]
		var p := RD_D2_DIR + "fg_%d.png" % int(e[0])
		if not (ResourceLoader.exists(p) or FileAccess.file_exists(p)):
			p = RD_D2_DIR + "fg_0.png"
		var t := tex_at(p)
		var s := float(e[2]) * _envf_sl("D2_FG_K", 0.6) / float(t.get_height())    # 11-19 返工：前景只压在画面下沿，顶端低过角色脚面，不再挡人
		var w := t.get_width() * s
		var h := t.get_height() * s
		var y := -640.0
		if String(e[1]) == "bottom":
			y = 1010.0 - h    # 从屏幕下沿长出来，压住画面最下沿
		var sp := add(t, FG_F * lx - w * 0.5, y, s, FG_F, 30, (k / 2) % 2 == 1, Color(_envf_sl("D2_FG_LUM", 0.42), _envf_sl("D2_FG_LUM", 0.42) * 1.02, _envf_sl("D2_FG_LUM", 0.42) * 1.05))
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("blur", _envf_sl("D2_FG_BLUR", 3.6) / s)
		sp.material = m
		front_nodes.append(sp)
		relief_fg.append(sp)
		lx += step + rng_fg.randf_range(-240.0, 240.0)
		k += 1
	_rd_fg_band_d2(x_start, x_end, sh)
	# 糊板：站立层后面的远景栈整体糊掉（移轴：只有角色那一层清楚）
	var bb := BackBufferCopy.new()
	bb.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	bb.z_as_relative = false
	bb.z_index = -81
	add_child(bb)
	var q := _white_quad(-81)
	var bm := ShaderMaterial.new()
	bm.shader = preload("res://scripts/night/redesign/blur_plane.gdshader")
	bm.set_shader_parameter("tint", Color(0.24, 0.25, 0.27))    # 蒙的雾用中性冷灰，不再是蓝滤镜
	bm.set_shader_parameter("haze", _envf_sl("D2_HAZE", 0.05))
	bm.set_shader_parameter("radius", _envf_sl("D2_BLUR", 1.0))    # 糊轻一点：后面那座城要认得出来
	q.material = bm
	screen_fx.append({"node": q, "mat": null})


var rng_fg := RandomNumberGenerator.new()


## 11-19 到 8 分：画面下沿一条连续的近景剪影（参照渎神 / 终焉之莉莉的下沿：黑剪影前景，不是空墙）。
## 石栏杆、铁栏、断墙交替，中间留小缺口；比街面跑得快（FG_F）、离焦、压暗；顶端低过角色脚面，不挡人。
## D2_BAND=0 关掉；D2_BAND_H 高度、D2_BAND_LUM 亮度、D2_BAND_SINK 往屏幕下沿外沉多少。
func _rd_fg_band_d2(x_start: float, x_end: float, sh: Shader) -> void:
	if _envf_sl("D2_BAND", 1.0) <= 0.0:
		return
	var seq := [0, 2, 0, 3, 2, 0, 3]
	var hh := _envf_sl("D2_BAND_H", 210.0)
	var lum := _envf_sl("D2_BAND_LUM", 0.13)
	var sink := _envf_sl("D2_BAND_SINK", -110.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7719
	var lx := x_start - 600.0
	var k := 0
	while lx < x_end + 1800.0:
		var p := RD_D2_DIR + "fg_%d.png" % int(seq[k % seq.size()])
		var t := tex_at(p)
		var s := hh * rng.randf_range(0.86, 1.08) / float(t.get_height())
		var w := t.get_width() * s
		var h := t.get_height() * s
		var sp := add(t, FG_F * lx, 1010.0 - h + sink, s, FG_F, 30, rng.randf() < 0.5, Color(lum, lum * 1.03, lum * 1.08))
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("blur", _envf_sl("D2_BAND_BLUR", 3.2) / s)
		sp.material = m
		front_nodes.append(sp)
		relief_fg.append(sp)
		lx += w / FG_F + rng.randf_range(20.0, 260.0)
		k += 1


static func _envf_sl(k: String, d: float) -> float:
	var v := OS.get_environment(k)
	return float(v) if v != "" else d


func _relief_update(delta: float) -> void:
	if relief3d != null:
		relief3d.follow(bd.camera.get_screen_center_position(), float(bd.camera.zoom.x), delta)
	if relief_player_light != null:
		relief_player_light.position = to_local_bg(_player_pos() + Vector2(0.0, -70.0))
	if not relief_fg.is_empty():
		var pl := to_local_bg(_player_pos() + Vector2(0.0, -80.0))
		for sp in relief_fg:
			var fs := sp as Sprite2D
			var sz := fs.texture.get_size() * fs.scale
			var r := Rect2(fs.position, sz).grow_individual(40.0, 0.0, 40.0, 0.0)
			var hit := r.has_point(pl)
			var a := 0.35 if hit else 1.0
			fs.modulate.a = move_toward(fs.modulate.a, a, delta * 3.0)
	for r in relief_lamps:
		var s := float(r.sp)
		(r.light as PointLight2D).energy = float(r.e) * (1.0 + 0.08 * sin(time * s) + 0.05 * sin(time * s * 2.7 + 1.0))


func _set_rd_1a(on: bool) -> void:
	rd_1a_on = on and not rd_1a_nodes.is_empty()
	for n in rd_1a_nodes:
		(n as CanvasItem).visible = rd_1a_on


# ---------------------------------------------------------------- 入口街：站立层 + 门洞昼光

func _build_entry() -> void:
	var top := FLOOR - STREET_PX * PX
	var x0 := anchor - ARCH_PX * PX       # 站立层左边缘（容器坐标）
	# 门洞里那条街：两排小楼往里收，中间留缝给昼光（z −91：在旧近景成图后面，走到广场时不会盖到旧图上）
	var dark := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	dark.fill(Color(0.07, 0.085, 0.14))
	if not redesign:    # 重构版门洞直接透出新远景（后排街屋 + 雾），和样板屏一样；旧版用暗底 + 三栋小楼剪影
		var back := add(ImageTexture.create_from_image(dark), -260.0, 130.0, 1.0, 0.9, -91)
		back.scale = Vector2(130.0, 125.0)
		add(tex("near_a"), -130.0, 280.0, 0.36, 0.93, -91, false, Color(0.5, 0.53, 0.62))
		add(tex("arch_b"), -400.0, 150.0, 0.62, 0.86, -91, false, Color(0.4, 0.42, 0.5))
		add(tex("arch_c"), 53.0, 150.0, 0.62, 0.86, -91, true, Color(0.4, 0.42, 0.5))
	# 昼光在楼后面：两排小楼压成剪影，缝里越往深处越亮
	add_glow(glow_t, 0.0, 440.0, 520.0, 620.0, 0.9, -91, C_LIGHT, 0.62)
	add_glow(glow_t, 0.0, 570.0, 300.0, 300.0, 0.9, -91, C_LIGHT, 0.5)
	var shaft := add_glow(_beam_tex(), 0.0, 340.0, 300.0, 520.0, 0.9, -91, C_LIGHT, 0.24)
	shaft.scale = Vector2(380.0 / 64.0, 520.0 / 64.0)
	shaft.rotation = -0.1
	add_glow(glow_t, 0.0, 470.0, 420.0, 480.0, 0.9, -91, C_LIGHT, 0.12)

	# 站立层：入口这张裁到大楼和塔之间的街缝，右沿羽化接钟楼广场；左边整张镜像接长
	var lamp_w: Array = []
	for l in _layered_rows("lamps", 4):
		lamp_w.append(Vector2(float(bd.first_x) + float(l[0]), float(l[1])))
	if redesign:
		_build_rd_near(lamp_w)
	else:
		var st := tex("stand_entry")
		var full := tex("stand")
		add(st, x0 - anchor, top, PX, 1.0, -80)
		add(full, x0 - anchor - full.get_width() * PX, top, PX, 1.0, -80, true)
	# 布局里的 layered 灯：能动的柔光盖在站立层上，火苗微闪
	var spd := [7.3, 9.1]
	var lamp_a := [[0.22, 420.0], [0.18, 340.0]]
	for i in lamp_w.size():
		var lp := to_local_bg(lamp_w[i])
		var la: Array = lamp_a[mini(i, 1)]
		lamps.append({"node": add_glow(glow_t, lp.x - anchor, lp.y, float(la[1]), float(la[1]), 1.0, -78, C_LIGHT, float(la[0])), "a": float(la[0]), "sp": spd[i % 2]})
	# 门洞的昼光泼到街面上
	add_glow(glow_t, 0.0, 596.0, 760.0, 80.0, 1.0, -4, C_LIGHT, 0.62)
	add_glow(glow_t, 0.0, 590.0, 280.0, 44.0, 1.0, -4, C_LIGHT, 0.55)
	# 门洞两侧的石柱被里面的光勾出来
	add_glow(glow_t, -150.0, 360.0, 150.0, 480.0, 1.0, -78, C_LIGHT, 0.14)
	add_glow(glow_t, 150.0, 360.0, 150.0, 480.0, 1.0, -78, C_LIGHT, 0.14)
	# 雨进了昼光就停：看不见的光罩，外面的雨到这里消失
	var dome := OccluderPolygon2D.new()
	dome.polygon = PackedVector2Array([Vector2(-190, 580), Vector2(-190, 300), Vector2(-120, 190), Vector2(0, 130), Vector2(120, 190), Vector2(190, 300), Vector2(190, 580)])
	var occ := LightOccluder2D.new()
	occ.occluder = dome
	occ.sdf_collision = true
	occ.occluder_light_mask = 0
	occ.position = Vector2(anchor, 0.0)
	bgw.add_child(occ)

	_build_beads()

	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	# 河面倒影：门洞和两盏灯在水里各一条被雨点打碎、微微晃动的光（世界坐标）
	refl_src = [[anchor, 160.0 * bg_k, 1.0]]
	for i in lamp_w.size():
		refl_src.append([lamp_w[i].x, (50.0 if i == 0 else 46.0) * bg_k, 0.85 if i == 0 else 0.75])
	refl = _layer(self, 7, draw_reflections, add_mat)
	front_nodes.append(refl)
	# 灯下的雨：灯光范围里的雨丝被照亮；门洞外的雨落到光罩边上就没了（容器坐标）
	for i in lamp_w.size():
		var lp := to_local_bg(lamp_w[i])
		lit_src.append([lp.x, lp.y, 170.0 if i == 0 else 150.0, 0.85 if i == 0 else 0.75, C_LAMP, false])
	lit_src.append([anchor, 330.0, 280.0, 0.8, C_LIGHT, true])
	for si in lit_src.size():
		for i in 50:
			var q := {"s": si, "x": 0.0, "y": 0.0}
			respawn_streak(q, true)
			lit_rain.append(q)
	lit_node = _layer(bgw, 19, draw_lit_rain, add_mat)
	front_nodes.append(lit_node)
	# 能站的台面：一道统一的冷白湿边，亮点沿边慢慢走，边上不时滴水（滴进昼光里的那几滴会停住）
	for p in _layered_rows("platforms", 4):
		var a := to_local_bg(Vector2(float(bd.first_x) + float(p[0]), float(p[2])))
		var b := to_local_bg(Vector2(float(bd.first_x) + float(p[1]), float(p[2])))
		ledges.append({"x0": a.x, "x1": b.x, "y": a.y, "next": rng.randf_range(0.2, 1.5), "ph": rng.randf_range(0.0, 400.0)})
	ledge_node = _layer(bgw, -79, draw_ledges, add_mat)
	drip_node = _layer(bgw, -3, draw_drips)
	front_nodes.append(drip_node)

	# 前景：按深度拆开，虚焦，只从画面上方露出来，不挡角色
	if not redesign:    # 吊臂是码头件（红线：不要码头 / 吊车），重构版只留顶上垂下的铁链
		front_nodes.append(add(tex("fg_crane"), -420.0, -375.0, 1.15, 1.3, 22))
	chain = add(tex("fg_chain"), -420.0 + (1560.0 - 860.0) * 1.15, -220.0, 0.8, 1.3, 22)    # 钩子停在壁灯上方，走过去不挡灯
	chain.offset = Vector2(-70.0, 0.0)
	front_nodes.append(chain)


## 布局第 0 段里标了 {"layered": true} 的行（opt_at：选项字典在第几项）
func _layered_rows(key: String, opt_at: int) -> Array:
	var out: Array = []
	var secs: Array = bd.layout.get("sections", [])
	if secs.is_empty():
		return out
	for r in secs[0].get(key, []):
		if r.size() > opt_at and r[opt_at] is Dictionary and r[opt_at].get("layered", false):
			out.append(r)
	return out


# ---------------------------------------------------------------- 每帧

func _process(delta: float) -> void:
	if bd == null or bd.camera == null:
		return
	time += delta
	var cam: Vector2 = bd.camera.get_screen_center_position()
	var cl := to_local_bg(cam)
	var cy0 := FLOOR + (CAM_Y - FLOOR) / bg_k
	var dx := cl.x - anchor
	var dy := cl.y - cy0
	for it in items:
		var f: float = it.f
		var x: float = it.x
		if float(it.period) > 0.0:
			var target := anchor + f * dx
			x += roundf((target - (x + float(it.half))) / float(it.period)) * float(it.period)
		it.node.position = Vector2(x + dx * (1.0 - f), float(it.y) + dy * (1.0 - f))
	for tl in tiles:
		var f: float = tl.f
		var tw: float = tl.tw
		var u := floori((anchor + f * dx - float(tl.x)) / tw)
		for j in 3:
			var i := u - 1 + j
			var sp: Sprite2D = tl.nodes[j]
			sp.position = Vector2(float(tl.x) + float(i) * tw + dx * (1.0 - f), float(tl.y) + dy * (1.0 - f))
			var fl := posmod(i, 2) == 1 and bool(tl.get("mirror", true))
			if sp.flip_h != fl:
				sp.flip_h = fl
				if sp.material is ShaderMaterial:
					(sp.material as ShaderMaterial).set_shader_parameter("rim_dir", Vector2(-0.35 if fl else 0.35, -0.94))
	for f in screen_fx:
		f.node.global_position = cam
		if f.mat != null:
			f.mat.set_shader_parameter("cam_x", cam.x)
			f.mat.set_shader_parameter("t", time)
	if rd_sky != null:    # 天空贴满屏幕（按当前镜头缩放算，大招拉镜头也不露边）
		var z: float = maxf(float(bd.camera.zoom.x), 0.05)
		var tsz := rd_sky.texture.get_size()
		rd_sky.scale = Vector2.ONE * maxf(1280.0 / tsz.x, 720.0 / tsz.y) * 1.04 / z
	for fo in rd_follow:
		fo.node.position.x = cam.x - float(fo.w) / 2.0
		fo.mat.set_shader_parameter("scroll", (cam.x - RD_SX0) * float(fo.f) / float(fo.w) * float(fo.ns))
	if rd_far_shafts != null:
		rd_far_shafts.queue_redraw()
	if redesign:
		_rd_post_grade(cam.x)
	if relief_on or d2_on:
		_relief_update(delta)
	if _d2_arch_back != null:
		_d2_arch_back.queue_redraw()
	if street3d != null:
		var st: Node = bd.get_parent()
		var ter: Node = st.get("terrain") if st != null and "terrain" in st else null
		street3d.follow(cam, float(bd.camera.zoom.x), delta, _player_pos(), ter)
	if ying != null:
		ying.update(delta, cam)
	for l in lamps:
		var fl := 1.0 + 0.1 * sin(time * float(l.sp)) + 0.06 * sin(time * float(l.sp) * 2.7 + 1.0)
		l.node.material.set_shader_parameter("gain", float(l.a) * fl)
	# 入口街附近才算的东西（停雨、灯下雨、滴水、倒影）
	var near := cam.x < edge_x + 1400.0
	if _ch1_enabled and refl != null:
		refl.modulate.a = 1.0 - clampf((cam.x - (edge_x - 260.0)) / 520.0, 0.0, 1.0)
	if near:
		update_beads(delta)
		update_lit_rain(delta)
		update_drips(delta)
		refl.queue_redraw()
		lit_node.queue_redraw()
		ledge_node.queue_redraw()
		drip_node.queue_redraw()
		bead_back.queue_redraw()
		bead_front.queue_redraw()
	if chain != null:
		chain.rotation = sin(time * 0.9) * 0.03 + sin(time * 2.3) * 0.006
	if _ch1_enabled and _ch1_layer != null:
		_ch1_layer.queue_redraw()
	update_mid(delta)
	_through_rain(near)


## 不碰撞的那层雨在门洞附近也要停在昼光罩上（远处照旧一直落进河里）
func _through_rain(near: bool) -> void:
	var r: GPUParticles2D = bd.get("_rain_through")
	if r == null:
		return
	var pm := r.process_material as ParticleProcessMaterial
	if _through_mode < 0:
		_through_mode = pm.collision_mode
		_through_size = r.collision_base_size
	var want := ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT if near else _through_mode
	if pm.collision_mode != want:
		pm.collision_mode = want
		r.collision_base_size = 2.0 if near else _through_size


func set_ult_mode(on: bool) -> void:
	for n in front_nodes:
		n.visible = not on


func _player_pos() -> Vector2:
	var h: Vector2 = bd.call("_hero_world_pos")
	return h if h != Vector2.INF else Vector2(anchor, FLOOR)


# ---------------------------------------------------------------- 搭建工具

func tex(name: String) -> Texture2D:
	return tex_at(DIR + name + ".png")


## 没经过编辑器导入时直接读 PNG（和 street_backdrop._load_tex 一样）
func tex_at(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	var image := Image.new()
	if image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
		push_error("分层背景缺图：" + path)
		image = Image.create(4, 4, false, Image.FORMAT_RGBA8)
	return ImageTexture.create_from_image(image)


## 加一层 / 一件：x、y 是镜头在 anchor 时的左上角容器坐标（x 相对 anchor），f 是视差（1 = 站立层）；period > 0 时按视差无限重复
func add(t: Texture2D, x: float, y: float, s: float, f: float, z: int, flip := false, mod := Color.WHITE, period := 0.0) -> Sprite2D:
	var sp := Sprite2D.new()
	sp.texture = t
	sp.centered = false
	sp.flip_h = flip
	sp.scale = Vector2(s, s)
	sp.z_as_relative = false
	sp.z_index = z
	sp.modulate = mod
	bgw.add_child(sp)
	items.append({"node": sp, "x": anchor + x, "y": y, "f": f, "period": period, "half": t.get_width() * s * 0.5})
	return sp


## 整幅层：三张按“正、反、正”镜像平铺，跟着镜头换位
func add_tiles(t: Texture2D, x: float, y: float, s: Vector2, f: float, z: int, mod: Color, tw: float, mirror := true) -> Array:
	var nodes: Array = []
	for j in 3:
		var sp := Sprite2D.new()
		sp.texture = t
		sp.centered = false
		sp.scale = s
		sp.z_as_relative = false
		sp.z_index = z
		sp.modulate = mod
		bgw.add_child(sp)
		nodes.append(sp)
	tiles.append({"nodes": nodes, "x": anchor + x, "y": y, "f": f, "tw": tw, "mirror": mirror})
	return nodes


func add_glow(t: Texture2D, x: float, y: float, sx: float, sy: float, f: float, z: int, c: Color, gain: float, period := 0.0) -> Sprite2D:
	var sp := add(t, x, y, 1.0, f, z, false, c, period)
	sp.centered = true
	sp.scale = Vector2(sx / t.get_width(), sy / t.get_height())
	items[items.size() - 1].half = 0.0
	var m := ShaderMaterial.new()
	m.shader = GlowShader
	m.set_shader_parameter("gain", gain)
	sp.material = m
	return sp


func add_fog(z: int, c: Color, k: float, spd: float, y0: float, y1: float, strength: float, noise: Texture2D) -> void:
	var m := ShaderMaterial.new()
	m.shader = LayerFogShader
	m.set_shader_parameter("n", noise)
	m.set_shader_parameter("col", c)
	m.set_shader_parameter("k", k)
	m.set_shader_parameter("spd", spd)
	m.set_shader_parameter("y0", y0)
	m.set_shader_parameter("y1", y1)
	m.set_shader_parameter("strength", strength)
	var sp := _white_quad(z)
	sp.material = m
	screen_fx.append({"node": sp, "mat": m})


func add_curtain(z: int, k: float, cell: float, density: float, speed: float, seg: float, alpha: float, y0: float, y1: float, c: Color) -> void:
	var m := ShaderMaterial.new()
	m.shader = CurtainShader
	m.set_shader_parameter("k", k)
	m.set_shader_parameter("cell", cell)
	m.set_shader_parameter("density", density)
	m.set_shader_parameter("speed", speed)
	m.set_shader_parameter("seg", seg)
	m.set_shader_parameter("period", seg * 6.0)
	m.set_shader_parameter("alpha", alpha)
	m.set_shader_parameter("y0", y0)
	m.set_shader_parameter("y1", y1)
	m.set_shader_parameter("col", c)
	m.set_shader_parameter("tilt", RAIN_TILT)
	var sp := _white_quad(z)
	sp.material = m
	screen_fx.append({"node": sp, "mat": m})
	curtains.append(m)


func screen_quad(z: int) -> Sprite2D:
	var sp := _white_quad(z)
	var am := CanvasItemMaterial.new()
	am.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	sp.material = am
	sp.modulate = Color(1, 1, 1, 0)
	screen_fx.append({"node": sp, "mat": null})
	return sp


func _white_quad(z: int) -> Sprite2D:
	var sp := Sprite2D.new()
	var w := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	w.fill(Color.WHITE)
	sp.texture = ImageTexture.create_from_image(w)
	sp.scale = Vector2(600, 360)
	sp.z_as_relative = false
	sp.z_index = z
	add_child(sp)
	return sp


func _layer(parent: Node, z: int, cb: Callable, mat: Material = null) -> Node2D:
	var n := Node2D.new()
	n.z_as_relative = false
	n.z_index = z
	n.material = mat
	n.draw.connect(cb)
	parent.add_child(n)
	return n


## 容器坐标 ↔ 世界坐标
func to_world(v: Vector2) -> Vector2:
	return Vector2(anchor, FLOOR) + (v - Vector2(anchor, FLOOR)) * bg_k


func to_local_bg(v: Vector2) -> Vector2:
	return Vector2(anchor, FLOOR) + (v - Vector2(anchor, FLOOR)) / bg_k


static func _glow_tex() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.add_point(0.45, Color(1, 1, 1, 0.32))
	g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 512
	t.height = 512
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	return t


## 一束从上往下的光：中间亮、两边软，上下都淡出
static func _beam_tex() -> Texture2D:
	var im := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for yy in 64:
		var v := yy / 63.0
		var fade := smoothstep(0.0, 0.25, v) * (1.0 - smoothstep(0.7, 1.0, v))
		for xx in 64:
			im.set_pixel(xx, yy, Color(1, 1, 1, (1.0 - absf(xx / 31.5 - 1.0)) * fade))
	return ImageTexture.create_from_image(im)


static func _bead_tex() -> Texture2D:
	var bi := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for yy in 32:
		for xx in 32:
			var d := Vector2(xx - 15.5, yy - 15.5).length() / 15.5
			bi.set_pixel(xx, yy, Color(1, 1, 1, clampf((1.0 - d) * 2.4, 0.0, 1.0)))
	return ImageTexture.create_from_image(bi)


# ---------------------------------------------------------------- 中景：远近处理、暖窗、烟、乌鸦、闪电

## 给一层背景套上远近处理（明暗阶梯、楼脚雾、月光边）
func depth(sp: Sprite2D, tint: Color, haze: float, contrast: float, blur: float, fog_amt: float, rim: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = DepthShader
	m.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	m.set_shader_parameter("haze", haze)
	m.set_shader_parameter("contrast", contrast)
	m.set_shader_parameter("blur_px", blur)
	m.set_shader_parameter("fog_amt", fog_amt)
	m.set_shader_parameter("rim_amt", rim)
	m.set_shader_parameter("rim_dir", Vector2(-0.35 if sp.flip_h else 0.35, -0.94))
	m.set_shader_parameter("win", [Vector4.ZERO, Vector4.ZERO, Vector4.ZERO, Vector4.ZERO, Vector4.ZERO, Vector4.ZERO, Vector4.ZERO, Vector4.ZERO])
	m.set_shader_parameter("win_on", PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0]))
	sp.material = m
	sp.modulate = Color.WHITE
	depth_mats.append(m)
	return m


## 中景的一栋楼：远近处理 + 几扇亮着的窗 + 烟囱冒烟；按 ROW_PERIOD 无限重复
func mid_house(nm: String, x: float, y: float, s: float, f: float, z: int, flip: bool, tint: Color, haze: float, contrast: float, blur: float, fog_amt: float, rim: float, nwin: int, nsmoke: int, r: RandomNumberGenerator) -> Sprite2D:
	var t := tex(nm)
	var sp := add(t, x, y, s, f, z, flip, Color.WHITE, ROW_PERIOD)
	items[items.size() - 1]["name"] = nm
	var m := depth(sp, tint, haze, contrast, blur, fog_amt, rim)
	var hi: Dictionary = house_info.get(nm, {})
	var pool: Array = (hi.get("wins", []) as Array).duplicate()
	pool = pool.filter(func(w): return float(w[3]) - float(w[1]) < 300.0)
	m.set_shader_parameter("glass_lo", 0.035)
	m.set_shader_parameter("glass_hi", 0.07)
	var wins: Array = []
	var ons := PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0])
	for i in mini(mini(nwin, 8), pool.size()):
		var w: Array = pool.pop_at(r.randi_range(0, pool.size() - 1))
		wins.append(Vector4(w[0], w[1], w[2], w[3]))
		ons[i] = r.randf_range(0.55, 1.0)
	var n_on := wins.size()
	while wins.size() < 8:
		wins.append(Vector4.ZERO)
	m.set_shader_parameter("win", wins)
	m.set_shader_parameter("win_on", ons)
	m.set_shader_parameter("win_gain", 0.55 + 0.45 * f)
	if n_on > 0:      # 每栋楼有一扇窗过一阵会慢慢亮起或熄灭
		win_anim.append({"mat": m, "ons": ons, "i": r.randi_range(0, n_on - 1), "base": 0.9, "on": true, "k": 1.0, "next": r.randf_range(0.8, 3.0)})
	var chims: Array = (hi.get("chims", []) as Array).duplicate()
	for i in mini(nsmoke, chims.size()):
		var c: Array = chims.pop_at(r.randi_range(0, chims.size() - 1))
		var cx: float = float(c[0])
		if flip:
			cx = t.get_width() - cx
		smoke_src.append({"sp": sp, "x": cx, "y": float(c[1]) - 6.0, "next": r.randf_range(0.0, 0.5), "haze": haze})
	return sp


func update_mid(dt: float) -> void:
	for w in win_anim:
		w.next = float(w.next) - dt
		if float(w.next) <= 0.0:
			w.on = not bool(w.on)
			w.next = rng.randf_range(5.0, 12.0)
		w.k = move_toward(float(w.k), 1.0 if bool(w.on) else 0.0, dt / 1.4)
		var ons: PackedFloat32Array = w.ons
		ons[int(w.i)] = float(w.base) * smoothstep(0.0, 1.0, float(w.k))
		w.mat.set_shader_parameter("win_on", ons)
	# 烟：一团团从烟囱口冒出来，往上、顺着风往左飘，越飘越大越淡
	for s in smoke_src:
		s.next = float(s.next) - dt
		if float(s.next) <= 0.0:
			s.next = rng.randf_range(0.35, 0.6)
			puffs.append({"sp": s.sp, "x": float(s.x) + rng.randf_range(-2.0, 2.0), "y": float(s.y), "age": 0.0, "life": rng.randf_range(4.0, 5.5), "vx": rng.randf_range(-20.0, -12.0), "vy": rng.randf_range(-26.0, -18.0), "haze": s.haze})
	for q in puffs:
		q.age = float(q.age) + dt
		q.x = float(q.x) + float(q.vx) * dt
		q.y = float(q.y) + float(q.vy) * dt
		q.vx = float(q.vx) - 4.0 * dt
	puffs = puffs.filter(func(q): return float(q.age) < float(q.life))
	for n in smoke_nodes.values():
		n.queue_redraw()
	# 乌鸦：主角走近就飞走，过一阵再落回来
	var px := _player_pos().x
	for cw in crows:
		var gp: Vector2 = (cw.sp as Sprite2D).get_global_transform() * Vector2(float(cw.x), float(cw.y))
		match int(cw.state):
			0:
				cw.peck = float(cw.peck) + dt
				if absf(gp.x - px) < 230.0:
					cw.state = 1
					cw.t = 0.0
					cw.vx = rng.randf_range(50.0, 110.0) * (1.0 if rng.randf() < 0.7 else -1.0)
					cw.vy = rng.randf_range(-60.0, -30.0)
					cw.delay = rng.randf_range(0.0, 0.35)
			1:
				cw.t = float(cw.t) + dt
				if float(cw.t) > float(cw.delay):
					cw.vy = float(cw.vy) - 90.0 * dt
					cw.dx = float(cw.dx) + float(cw.vx) * dt
					cw.dy = float(cw.dy) + float(cw.vy) * dt
				if float(cw.t) > 4.0:
					cw.state = 2
					cw.t = 0.0
			2:
				cw.t = float(cw.t) + dt
				if float(cw.t) > 9.0 and absf(gp.x - px) > 400.0:
					cw.state = 0
					cw.dx = 0.0
					cw.dy = 0.0
					cw.fade = 0.0
		cw.fade = minf(float(cw.fade) + dt / 0.8, 1.0)
	for n in crow_nodes.values():
		n.queue_redraw()
	# 闪电：隔一阵打一次，两下闪，照亮天和远处的轮廓
	bolt_t -= dt
	if bolt_t <= 0.0:
		bolt_t = rng.randf_range(14.0, 24.0)
		bolt_age = 0.0
	bolt_age += dt
	var fl := 0.0
	if bolt_age < 0.07:
		fl = 1.0
	elif bolt_age < 0.16:
		fl = 0.12
	elif bolt_age < 0.24:
		fl = 0.8
	elif bolt_age < 1.2:
		fl = 0.8 * exp(-(bolt_age - 0.24) * 5.0)
	if _ch1_enabled:
		flash_sky.modulate = Color(0.32, 0.35, 0.42, fl * 0.14)
		flash_all.modulate = Color(0.36, 0.39, 0.45, fl * 0.03)
	else:
		flash_sky.modulate = Color(0.5, 0.58, 0.85, fl * 0.55)
		flash_all.modulate = Color(0.55, 0.6, 0.78, fl * 0.07)
	var shader_fl := fl * 0.32 if _ch1_enabled else fl
	for m in depth_mats:
		m.set_shader_parameter("flash", shader_fl)
	for c in curtains:
		c.set_shader_parameter("flash", shader_fl)


func _smoke_node(sp: Sprite2D) -> Node2D:
	if not smoke_nodes.has(sp):
		var n := Node2D.new()
		n.draw.connect(draw_smoke.bind(sp))
		sp.add_child(n)
		smoke_nodes[sp] = n
	return smoke_nodes[sp]


func draw_smoke(sp: Sprite2D) -> void:
	var n: Node2D = smoke_nodes[sp]
	for q in puffs:
		if q.sp != sp:
			continue
		var a := float(q.age) / float(q.life)
		var r := lerpf(7.0, 36.0, sqrt(a))
		var al := 0.42 * smoothstep(0.0, 0.12, a) * (1.0 - a) * (1.0 - 0.3 * float(q.haze))
		n.draw_texture_rect(bead_tex, Rect2(float(q.x) - r, float(q.y) - r * 0.8, r * 2.0, r * 1.6), false, Color(0.42, 0.47, 0.58, al))


## 一群乌鸦站在某栋中景楼的屋脊 / 烟囱上（成图像素）
func add_crows(sp: Sprite2D, pts: Array) -> void:
	if not crow_nodes.has(sp):
		var n := Node2D.new()
		n.draw.connect(draw_crows.bind(sp))
		sp.add_child(n)
		crow_nodes[sp] = n
	for pt in pts:
		var cx: float = float(pt[0])
		if sp.flip_h:
			cx = sp.texture.get_width() - cx
		crows.append({"sp": sp, "x": cx, "y": float(pt[1]), "face": -1.0 if rng.randf() < 0.5 else 1.0, "state": 0, "t": 0.0, "dx": 0.0, "dy": 0.0, "vx": 0.0, "vy": 0.0, "delay": 0.0, "peck": rng.randf_range(0.0, 6.0), "fade": 1.0})


func draw_crows(sp: Sprite2D) -> void:
	var n: Node2D = crow_nodes[sp]
	var col := Color(0.05, 0.055, 0.075)
	for cw in crows:
		if cw.sp != sp or int(cw.state) == 2:
			continue
		var al := float(cw.fade)
		var c := Color(col.r, col.g, col.b, al)
		n.draw_set_transform(Vector2(float(cw.x) + float(cw.dx), float(cw.y) + float(cw.dy)), 0.0, Vector2(1.9, 1.9))    # 中景太远，按真实比例只有几像素，放大到认得出
		var o := Vector2.ZERO
		if int(cw.state) == 1 and float(cw.t) > float(cw.delay):
			var fx := signf(float(cw.vx))
			var flap := sin(float(cw.t) * 22.0)
			n.draw_colored_polygon(PackedVector2Array([o + Vector2(-7 * fx, 0), o + Vector2(0, -2), o + Vector2(8 * fx, -1), o + Vector2(0, 2)]), c)
			n.draw_colored_polygon(PackedVector2Array([o + Vector2(-2 * fx, -1), o + Vector2(3 * fx, -1), o + Vector2(-1 * fx, -1 - 11 * flap)]), c)
			n.draw_colored_polygon(PackedVector2Array([o + Vector2(-1 * fx, 0), o + Vector2(4 * fx, 0), o + Vector2(1 * fx, 7 * flap)]), Color(c.r, c.g, c.b, al * 0.8))
		else:
			var fc := float(cw.face)
			var bob := 1.5 if fmod(float(cw.peck), 5.0) < 0.35 else 0.0     # 偶尔低头啄一下
			n.draw_colored_polygon(PackedVector2Array([o + Vector2(-6 * fc, -1), o + Vector2(-2 * fc, -7), o + Vector2(4 * fc, -7), o + Vector2(5 * fc, -2), o + Vector2(0, 0)]), c)
			n.draw_circle(o + Vector2(5 * fc, -9 + bob), 2.6, c)
			n.draw_colored_polygon(PackedVector2Array([o + Vector2(7 * fc, -10 + bob), o + Vector2(11 * fc, -8.5 + bob), o + Vector2(7 * fc, -8 + bob)]), c)
			n.draw_colored_polygon(PackedVector2Array([o + Vector2(-5 * fc, -2), o + Vector2(-11 * fc, 1), o + Vector2(-9 * fc, 2), o + Vector2(-3 * fc, -1)]), c)
	n.draw_set_transform(Vector2.ZERO)


# ---------------------------------------------------------------- 门洞昼光里停住的雨（容器坐标，x 相对 anchor）

## 昼光强度：停住的雨靠它决定亮不亮
func light_at(x: float, y: float) -> float:
	return exp(-pow(x / 175.0, 2.0) - pow((y - 470.0) / 270.0, 2.0))


## 看不见的光罩上沿（和雨的遮挡多边形一致）
func dome_top(x: float) -> float:
	var ax := absf(x)
	if ax < 120.0:
		return 130.0 + ax / 120.0 * 60.0
	return 190.0 + (ax - 120.0) / 70.0 * 110.0


func in_dome(x: float, y: float) -> bool:
	var rx := x - anchor
	return absf(rx) < 190.0 and y > dome_top(rx)


func _build_beads() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 511
	var cx := -182.0
	while cx < 182.0:
		var yy := dome_top(cx) + r.randf_range(10.0, 60.0)
		while yy < 572.0:
			if r.randf() < 0.35 + 0.65 * light_at(cx, yy):
				beads.append(new_bead(r, cx - (yy - 370.0) * RAIN_TILT, yy, false, r.randf_range(0.8, 1.5) if r.randf() < 0.85 else r.randf_range(1.8, 2.4)))
			yy += r.randf_range(22.0, 58.0)
		cx += r.randf_range(8.0, 18.0)
	# 门洞口往外：挂在主角前进的路上，碰到就重新落下
	var fx := -232.0
	while fx < 232.0:
		var fy := maxf(dome_top(fx), 150.0) + r.randf_range(0.0, 50.0)
		while fy < 566.0:
			var e := 1.0 - clampf(Vector2(fx / 245.0, (fy - 470.0) / 300.0).length(), 0.0, 1.0)
			if r.randf() < e * 1.3:
				beads.append(new_bead(r, fx - (fy - 370.0) * RAIN_TILT, fy, true, r.randf_range(1.1, 1.9) if r.randf() < 0.8 else r.randf_range(2.2, 3.0)))
			fy += r.randf_range(30.0, 72.0)
		fx += r.randf_range(13.0, 26.0)
	# 刚进光里的雨：从光罩上沿落进来，越落越慢，停住；停一会儿淡掉，再来一滴
	for i in 22:
		var nb := new_bead(r, 0.0, 0.0, i % 3 == 0, r.randf_range(1.0, 1.8))
		nb.mode = 1
		respawn_arrival(nb, r.randf_range(0.0, 5.0))
		beads.append(nb)
	bead_back = _layer(bgw, -85, draw_beads.bind(false))
	bead_front = _layer(bgw, -3, draw_beads.bind(true))
	front_nodes.append(bead_front)


func new_bead(r: RandomNumberGenerator, x: float, y: float, front: bool, rad: float) -> Dictionary:
	return {"x": x, "y": y, "r": rad, "front": front, "ph": r.randf_range(0.0, TAU), "sp": r.randf_range(0.35, 1.0), "state": 0, "dy": 0.0, "v": 0.0, "t": 0.0, "mode": 0}


func respawn_arrival(b: Dictionary, delay: float) -> void:
	var x := rng.randf_range(-150.0, 150.0)
	var top := dome_top(x) + 8.0
	b.x0 = x
	b.y0 = top
	b.y1 = top + rng.randf_range(60.0, 150.0)
	b.t = -delay
	b.hold = rng.randf_range(3.0, 6.0)


func draw_beads(front: bool) -> void:
	var n: Node2D = bead_front if front else bead_back
	if bd.camera == null:
		return
	var shift := (to_local_bg(bd.camera.get_screen_center_position()).x - anchor) * (0.0 if front else 0.1)
	for b in beads:
		if bool(b.front) != front:
			continue
		var rad := float(b.r)
		var x := float(b.x)
		var y := float(b.y)
		var alpha := 1.0
		var tail := rad * 5.0
		if int(b.mode) == 1:      # 正在慢下来的那几滴
			var t := float(b.t)
			if t < 0.0:
				continue
			var span := float(b.y1) - float(b.y0)
			var k := exp(-4.0 * t)
			y = float(b.y1) - span * k
			x = float(b.x0) - (y - float(b.y0)) * RAIN_TILT
			tail += span * 4.0 * k * 0.06
			alpha = clampf(t / 0.15, 0.0, 1.0) * (1.0 - clampf((t - float(b.hold)) / 0.8, 0.0, 1.0))
		else:
			var state := int(b.state)
			if state == 1:      # 被碰到，重新落下
				y += float(b.dy)
				tail = rad * 12.0
			elif state == 2:    # 落地的小水圈
				var kk := float(b.t) / 0.28
				n.draw_set_transform(Vector2(anchor + x + shift, 574.0), 0.0, Vector2(1.0, 0.3))
				n.draw_arc(Vector2.ZERO, 3.0 + 13.0 * kk, 0.0, TAU, 20, Color(1.0, 0.98, 0.92, 0.6 * (1.0 - kk)), 1.5)
				continue
			elif state == 3:
				continue
			elif state == 4:    # 慢慢重新停回来
				alpha = float(b.t) / 0.7
		var lf := light_at(x, y)
		var glint := pow(maxf(0.0, sin(time * float(b.sp) + float(b.ph))), 12.0)
		var lum := (0.22 + 0.78 * lf) * (0.8 + 0.7 * glint) * alpha * (1.0 if front else 0.7)
		var col := Color(0.72, 0.82, 1.0).lerp(Color(1.0, 0.95, 0.84), lf)
		n.draw_set_transform(Vector2(anchor + x + shift, y), RAIN_TILT, Vector2.ONE)
		n.draw_texture_rect(bead_tex, Rect2(-rad * 0.32, -tail, rad * 0.64, tail), false, Color(col.r, col.g, col.b, lum * 0.45))
		n.draw_texture_rect(bead_tex, Rect2(-rad, -rad * 1.3, rad * 2.0, rad * 2.2), false, Color(col.r, col.g, col.b, minf(lum, 1.0)))
	n.draw_set_transform(Vector2.ZERO)


func update_beads(dt: float) -> void:
	var pl := to_local_bg(_player_pos())
	var px: float = pl.x - anchor
	var py: float = pl.y
	for b in beads:
		if int(b.mode) == 1:
			b.t = float(b.t) + dt
			if float(b.t) > float(b.hold) + 0.8:
				respawn_arrival(b, rng.randf_range(0.2, 1.5))
			continue
		if not bool(b.front):
			continue
		match int(b.state):
			0:
				if absf(float(b.x) - px) < 46.0 and absf(float(b.y) - py) < 100.0:
					b.state = 1
					b.v = 30.0
			1:
				b.v = float(b.v) + 1900.0 * dt
				b.dy = float(b.dy) + float(b.v) * dt
				if float(b.y) + float(b.dy) >= 574.0:
					b.state = 2
					b.t = 0.0
			2, 3, 4:
				b.t = float(b.t) + dt
				if int(b.state) == 2 and float(b.t) > 0.28:
					b.state = 3
					b.t = 0.0
				elif int(b.state) == 3 and float(b.t) > 2.2:
					b.state = 4
					b.t = 0.0
					b.dy = 0.0
				elif int(b.state) == 4 and float(b.t) > 0.7:
					b.state = 0


# ---------------------------------------------------------------- 倒影、灯下的雨、台面湿边和滴水

func draw_reflections() -> void:
	for s in refl_src:
		var cxw: float = s[0]
		var w0: float = s[1]
		var a0: float = s[2]
		var y := 668.0
		while y < 840.0:
			var d := y - 668.0
			var n1 := 0.5 + 0.5 * sin(y * 0.21 + time * 3.1) * sin(y * 0.077 - time * 1.7 + cxw * 0.01)
			var wob := sin(y * 0.09 + time * 2.3 + cxw * 0.003) * (3.0 + d * 0.05)
			var ww := w0 * (0.55 + 0.6 * n1) * maxf(1.0 - d / 420.0, 0.2)
			var a := a0 * exp(-d / 85.0) * (0.35 + 0.65 * n1)
			# 软边的长椭圆光斑，上下互相叠一点，不留硬的横缝
			var hh := 5.0 + 4.0 * n1
			refl.draw_texture_rect(bead_tex, Rect2(cxw - ww * 0.5 + wob, y - hh * 0.5, ww, hh), false, Color(C_LIGHT.r, C_LIGHT.g, C_LIGHT.b, a * 0.42))
			refl.draw_texture_rect(bead_tex, Rect2(cxw - ww * 0.2 + wob * 1.3, y - hh * 0.35, ww * 0.4, hh * 0.7), false, Color(C_LIGHT.r, C_LIGHT.g, C_LIGHT.b, a * 0.5))
			y += 4.0 + 3.0 * (1.0 - n1)


func respawn_streak(q: Dictionary, anywhere: bool) -> void:
	var s: Array = lit_src[int(q.s)]
	var rad: float = s[2]
	q.x = float(s[0]) + rng.randf_range(-rad, rad)
	if anywhere:
		q.y = float(s[1]) + rng.randf_range(-rad, rad * 0.4)
	else:
		q.y = float(s[1]) - rad * rng.randf_range(0.9, 1.3)


func update_lit_rain(dt: float) -> void:
	for q in lit_rain:
		q.y = float(q.y) + 1250.0 * dt
		q.x = float(q.x) - 1250.0 * dt * RAIN_TILT
		var s: Array = lit_src[int(q.s)]
		if float(q.y) > 580.0 or (bool(s[5]) and in_dome(float(q.x), float(q.y))) or float(q.y) > float(s[1]) + float(s[2]) * 1.6:
			respawn_streak(q, false)


func draw_lit_rain() -> void:
	for q in lit_rain:
		var s: Array = lit_src[int(q.s)]
		var rad: float = s[2]
		var dx := (float(q.x) - float(s[0])) / rad
		var dy := (float(q.y) - float(s[1]) - rad * 0.25) / (rad * 1.3)
		var a: float = float(s[3]) * exp(-(dx * dx + dy * dy) * 1.6)
		if a < 0.01:
			continue
		var c: Color = s[4]
		lit_node.draw_line(Vector2(float(q.x), float(q.y)), Vector2(float(q.x) + 24.0 * RAIN_TILT, float(q.y) - 24.0), Color(c.r, c.g, c.b, a), 1.6)


func draw_ledges() -> void:
	for L in ledges:
		var lx0: float = L.x0
		var lx1: float = L.x1
		var y: float = float(L.y) - 1.0
		ledge_node.draw_rect(Rect2(lx0, y, lx1 - lx0, 2.0), Color(LEDGE_SHEEN, 0.1))
		var span := lx1 - lx0
		var gx := lx0 + fposmod(time * 70.0 + float(L.ph), span + 300.0) - 150.0    # 一颗亮点沿着湿边慢慢走
		for i in 13:
			var o := (i - 6) * 9.0
			var xx := gx + o
			if xx < lx0 or xx > lx1:
				continue
			ledge_node.draw_rect(Rect2(xx, y, 9.0, 2.0), Color(0.75, 0.85, 1.0, 0.32 * exp(-pow(o / 30.0, 2.0))))


func update_drips(dt: float) -> void:
	for L in ledges:
		L.next = float(L.next) - dt
		if float(L.next) <= 0.0:
			L.next = rng.randf_range(0.5, 1.8)
			drips.append({"x": rng.randf_range(float(L.x0) + 8.0, float(L.x1) - 8.0), "y": float(L.y) + 4.0, "v": 0.0, "t": 0.0, "state": 0})
	for d in drips:
		match int(d.state):
			0:
				if in_dome(float(d.x), float(d.y)):      # 滴进昼光：慢下来停住
					d.v = float(d.v) * exp(-7.0 * dt)
					if float(d.v) < 8.0:
						d.state = 2
				else:
					d.v = float(d.v) + 1800.0 * dt
				d.y = float(d.y) + float(d.v) * dt
				if float(d.y) >= 578.0:
					d.y = 578.0
					d.state = 1
			1, 2:
				d.t = float(d.t) + dt
	drips = drips.filter(func(d): return not ((int(d.state) == 1 and float(d.t) > 0.3) or (int(d.state) == 2 and float(d.t) > 4.0)))


func draw_drips() -> void:
	for d in drips:
		var x: float = d.x
		var y: float = d.y
		if int(d.state) == 1:
			var k: float = float(d.t) / 0.3
			drip_node.draw_set_transform(Vector2(x, y), 0.0, Vector2(1.0, 0.3))
			drip_node.draw_arc(Vector2.ZERO, 2.0 + 9.0 * k, 0.0, TAU, 16, Color(0.8, 0.88, 1.0, 0.45 * (1.0 - k)), 1.2)
			drip_node.draw_set_transform(Vector2.ZERO)
			continue
		var a := 0.55 if int(d.state) == 0 else 0.55 * (1.0 - clampf((float(d.t) - 3.2) / 0.8, 0.0, 1.0))
		var ln := clampf(float(d.v) * 0.012, 3.0, 12.0)
		drip_node.draw_texture_rect(bead_tex, Rect2(x - 1.2, y - ln, 2.4, ln + 1.5), false, Color(0.82, 0.9, 1.0, a))


# ---------------------------------------------------------------- 第一章「影街与司辰母钟楼」多节点分层成图带

const CH1_MANIFEST_PATH := "res://assets/image/rain_street/ch1_shadow_street/manifest.json"
const CH1_CODE_PREFIX := {
	"1-1A": "s1_1a",
	"1-1B": "s1_1b",
	"1-2A": "s1_2a",
	"1-2B": "s1_2b",
	"1-3A": "s1_3a",
	"1-3B": "s1_3b",
	"1-3C": "s1_3c",
	"1-4": "s1_4",
	"S1": "s1_rest",
	"E1": "e1_court",
}


func _build_ch1_shadow_street() -> void:
	if FileAccess.file_exists(CH1_MANIFEST_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CH1_MANIFEST_PATH))
		if parsed is Dictionary:
			_ch1_manifest = parsed
	var secs: Array = bd.layout.get("sections", [])
	for i in secs.size():
		if secs[i] is Dictionary and secs[i].has("ch1_code"):
			_ch1_route_codes[i] = String(secs[i].get("ch1_code"))
	# z = -82：在 5 层动态天空/天际线母钟楼/冒烟停鸦中景楼群（-100..-92）前方，
	# 在入口街右缘羽化层（-80）、台面湿光（-79）、灯晕（-78）与湿街面涟漪（-5）后方。
	_ch1_layer = _layer(self, -82, _draw_ch1_shadow_street)


func set_ch1_route_code(slot_idx: int, code: String) -> void:
	_ch1_route_codes[slot_idx] = code
	if slot_idx == 0 and not rd_1a_nodes.is_empty():
		_set_rd_1a(code == "1-1A")
	if _ch1_layer != null:
		_ch1_layer.queue_redraw()


func _ch1_entry_info(entry_id: String, fallback_id: String) -> Dictionary:
	if _ch1_manifest.has(entry_id):
		return {"id": entry_id, "meta": _ch1_manifest[entry_id], "fallback": false}
	if _ch1_manifest.has(fallback_id):
		return {"id": fallback_id, "meta": _ch1_manifest[fallback_id], "fallback": true}
	return {}


func _ch1_tex(entry_id: String) -> Texture2D:
	if _ch1_tex_cache.has(entry_id):
		return _ch1_tex_cache[entry_id]
	var meta: Dictionary = _ch1_manifest.get(entry_id, {})
	var path := String(meta.get("tex", ""))
	if path == "":
		return null
	var t := tex_at(path)
	_ch1_tex_cache[entry_id] = t
	return t


func _draw_ch1_tile(x0: float, x1: float, entry_id: String, fallback_id: String, mirror_if_fallback: bool, ground_y_override: float = NAN) -> void:
	var info := _ch1_entry_info(entry_id, fallback_id)
	if info.is_empty():
		return
	var use_id := String(info["id"])
	var meta: Dictionary = info["meta"]
	var t := _ch1_tex(use_id)
	if t == null:
		return
	var w := x1 - x0
	if w <= 4.0:
		return
	var w_px := float(meta.get("width_px", t.get_width()))
	var h_px := float(meta.get("height_px", t.get_height()))
	var g_px := float(meta.get("ground_px", h_px * 0.86))
	var k := w / maxf(w_px, 1.0)
	var h := h_px * k
	var gy := ground_y_override if is_finite(ground_y_override) else FLOOR
	var y_top := gy - g_px * k
	var flip := mirror_if_fallback and bool(info["fallback"])
	if bool(meta.get("indoor", false)):
		_ch1_layer.draw_rect(Rect2(x0, y_top - 520.0, w, 524.0), Color(0.022, 0.026, 0.038, 1.0))
	if y_top + h < FLOOR + 320.0:
		_ch1_layer.draw_rect(Rect2(x0, y_top + h - 6.0, w, (FLOOR + 340.0) - (y_top + h - 6.0)), Color(0.022, 0.026, 0.038, 1.0))
	var draw_w := -w if flip else w
	if bool(meta.get("indoor", false)):
		_ch1_layer.draw_texture_rect_region(t, Rect2(x0, y_top - 520.0, draw_w, 522.0), Rect2(0.0, 0.0, w_px, 2.0))
	_ch1_layer.draw_texture_rect(t, Rect2(x0, y_top, draw_w, h), false)


const CH1_ARENA_TRIPLETS := {
	"1-1A": ["s1_1a_left", "s1_1a_center", "s1_1a_right"],
	"1-1B": ["s1_1b_left", "s1_1b_right", "s1_1a_right"],
	"1-2A": ["s1_2a_left", "s1_2a_center", "s1_2a_right"],
	"1-2B": ["s1_2b_left", "s1_2b_center", "s1_2b_right"],
	"1-3A": ["s1_3a_left", "s1_3a_center", "s1_3a_right"],
	"1-3B": ["s1_3b_left", "s1_3b_center", "s1_3b_right"],
	"1-3C": ["s1_3a_left", "s1_3c_left", "s1_3c_right"],
	"E1": ["s1_2b_left", "e1_court_center", "s1_2b_right"],
}


func _draw_ch1_arena_triplet(x_start: float, x_end: float, code: String) -> void:
	var seq: Array = CH1_ARENA_TRIPLETS.get(code, CH1_ARENA_TRIPLETS["1-1A"])
	var prefix := String(CH1_CODE_PREFIX.get(code, "s1_1a"))
	var fb_id := prefix + "_center"
	if not _ch1_manifest.has(fb_id):
		fb_id = "s1_1a_center"
	var span := x_end - x_start
	var w3 := span / 3.0
	_draw_ch1_tile(x_start, x_start + w3 + 2.0, String(seq[0]), fb_id, false)
	_draw_ch1_tile(x_start + w3, x_start + w3 * 2.0 + 2.0, String(seq[1]), fb_id, false)
	_draw_ch1_tile(x_start + w3 * 2.0, x_end + 2.0, String(seq[2]), fb_id, false)


func _draw_ch1_shadow_street() -> void:
	if bd == null or bd.camera == null or _ch1_manifest.is_empty():
		return
	var cam: Vector2 = bd.camera.get_screen_center_position()
	var z: float = float(bd.camera.zoom.x) if float(bd.camera.zoom.x) > 0.0 else 0.65
	var half_w: float = 700.0 / z
	var view_l: float = cam.x - half_w - 260.0
	var view_r: float = cam.x + half_w + 260.0

	var c0 := float(bd.first_x)
	var sp := float(bd.spacing)
	var c1 := c0 + sp
	var c2 := c0 + sp * 2.0

	# 出生点 x=320..2038.2 完整保留玩家最满意的「11-12 起点入口街」（stand_entry 右缘 z=-80 羽化至 edge_x≈2038.2）；
	# 第一章 24 张影街在 z=-82 从 a0_l = c0 - 2460 (1960) 起无缝垫在入口街右缘羽化带后方，走出门洞即自然踏入新影街！
	var a0_l := c0 - 2460.0
	var a0_r := c0 + 2440.0
	var j1_r := c1 - 2440.0
	var a1_r := c1 + 2440.0
	var j2_r := c2 - 2440.0
	var a2_r := c2 + 2440.0
	var s4_mid := a2_r + 1960.0
	var s4_end := s4_mid + 1960.0

	var s0_code := String(_ch1_route_codes.get(0, "1-1A"))

	if view_r > a0_l and view_l < a0_r and not (rd_1a_on and s0_code == "1-1A"):    # 1-1A 两层街样板角由 _build_rd_1a 画
		_draw_ch1_arena_triplet(a0_l, a0_r, s0_code)
	if view_r > a0_r and view_l < j1_r and not rd_j1_on:    # J1 新图由 _build_rd_1a 画
		_draw_ch1_tile(a0_r, j1_r + 2.0, "j_fork_center", "j_fork_center", false)
	if view_r > j1_r and view_l < a1_r:
		_draw_ch1_arena_triplet(j1_r, a1_r, String(_ch1_route_codes.get(1, "1-2B")))
	if view_r > a1_r and view_l < j2_r:
		_draw_ch1_tile(a1_r, j2_r + 2.0, "s1_rest_center", "j_fork_center", false)
	if view_r > j2_r and view_l < a2_r:
		_draw_ch1_arena_triplet(j2_r, a2_r, String(_ch1_route_codes.get(2, "1-3B")))
	if view_r > a2_r and view_l < s4_mid:
		_draw_ch1_tile(a2_r, s4_mid + 2.0, "s1_4_center", "s1_4_center", false)
	if view_r > s4_mid and view_l < s4_end:
		_draw_ch1_tile(s4_mid, s4_end, "s1_4_upper", "s1_4_center", false)

