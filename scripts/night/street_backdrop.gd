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
##
## 分层背景（11-12，street_layered.gd）：布局里有 "layered" 时，整条街的天空 / 远景 / 背街换成分层背景，
## 开局入口街（第 0 处封印左边）换成分层试验的站立层；这里的旧天空、远景、背街两排、远中两层雾就不画了，
## 入口街范围里也不再画上一段（第 −1 槽）的成图、灯、前景件和门洞。

const FogShader := preload("res://scripts/night/rain_fog.gdshader")
const GlowShader := preload("res://scripts/night/rain_glow.gdshader")
const StreetLayered := preload("res://scripts/night/street_layered.gd")

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
## 街道深处的两排背街，先画远的。bottom = 镜头在街面取景时图下沿的世界 y（越远的街面在画面上越高）
const DEPTH_ROWS := [
	{"tex": "res://assets/image/rain_street/depth_deep_row_20261106.png", "scroll": 0.48, "bottom": 500.0},
	{"tex": "res://assets/image/rain_street/depth_back_row_20261106.png", "scroll": 0.72, "bottom": 560.0},
]
## D1 门洞/桥洞昼光默认坐标兜底（布局某段未显式写 arches 时按段名取）：[中心相对 x, 半宽, 拱顶 y, 落地 y, 类型(open/painted)]
const DEFAULT_ARCHES := {
	"钟楼广场": [
		[-565.0, 52.0, 145.0, 580.0, "open"],
		[1512.0, 52.0, 155.0, 580.0, "open"],
		[2810.0, 82.0, 330.0, 580.0, "painted"],
		[3320.0, 165.0, 130.0, 580.0, "painted"],
	],
	"廊桥": [
		[-696.0, 215.0, 115.0, 580.0, "open"],
		[-103.0, 102.0, 105.0, 580.0, "open"],
		[1524.0, 220.0, 238.0, 580.0, "open"],
	],
	"河岸石阶": [
		[-966.0, 185.0, 195.0, 580.0, "painted"],
		[1560.0, 118.0, 245.0, 580.0, "open"],
	],
}
const FOG_FAR_STRENGTH := 0.40
const FOG_MID_STRENGTH := 0.38
const FOG_NEAR_STRENGTH := 0.28
const HERO_MIST_GAIN := 0.105
const C_DAYLIGHT := Color(1.0, 0.93, 0.78)
const C_LAMP_SOFT := Color(1.0, 0.86, 0.62)
const C_HERO_MIST := Color(0.54, 0.66, 0.92)
const C_LEDGE_WET := Color(0.66, 0.76, 0.92)

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
## 修改器能改的背景（layout.backdrop），没改就是上面的常量。
var sky_screen_h := SKY_SCREEN_H
var sky_scroll := SKY_SCROLL
var sky_shift := SKY_SHIFT
var far_scroll := FAR_SCROLL
var far_top := FAR_TOP
var rain_drops := RAIN_DROPS
var rain_through := RAIN_THROUGH
var rain_speed := RAIN_SPEED
var rain_wind := RAIN_WIND
var fog_enabled: bool = true
var fog_far_strength: float = FOG_FAR_STRENGTH
var fog_mid_strength: float = FOG_MID_STRENGTH
var fog_near_strength: float = FOG_NEAR_STRENGTH
var hero_mist_gain: float = HERO_MIST_GAIN
var daylight_enabled: bool = true
var daylight_gain: float = 1.0
var beads_enabled: bool = true
var ledge_sheen: float = 1.0
var lamp_glow_gain: float = 1.0
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
var _occluders: Node2D            ## 只给 SDF 用的遮挡形状（平台、石台、街面、昼光拱门罩），不投影、不碰撞
var _occ_key := ""
var _sky_tex: Texture2D
var _far_tex: Texture2D
var _depth_rows: Array = []
var _front_rows: Array = []
var _far_fog: Color = C_FOG       ## 远景图底边的雾色：图下面接着铺这个颜色
var _art_tex: Dictionary = {}     ## 成图路径 → Texture2D
var _water: Node2D
var _ground: Node2D              ## 湿街面上的雨点涟漪（rain_ground.gdshader，加色）
var _water_mat: ShaderMaterial

## D1 零生图分层质感节点与纹理（仅正式雨街启用，不影响子类决斗台）
var _fog_noise: Texture2D
var _glow_tex: Texture2D
var _beam_tex: Texture2D
var _bead_tex: Texture2D
var _fog_far: Node2D
var _fog_mid: Node2D
var _fog_near: Node2D
var _fog_mats: Array = []
var _depth_deep: Node2D
var _depth_near: Node2D
var _arch_mask: Node2D
var _arch_back: Node2D
var _arch_pool: Node2D
var _ledge_wet: Node2D
var _soft_glow: Node2D
var _bead_back: Node2D
var _bead_front: Node2D
var _arch_beads: Dictionary = {}  ## 段中心 int → 悬停白珠数组
const CH1_LAYOUT_PATH := "res://assets/data/ch1_shadow_street_layout.json"

var _layered: Node2D               ## 分层背景（street_layered.gd），没有就是 null
var _layer_edge := -INF            ## 入口街站立层的右边缘（世界 x）：左边的前景件、灯光盘不画
var _ch1_shadow_mode := false      ## 第一章「影街与司辰母钟楼」正式成图模式（入口街往东禁水面、禁灰盒灯杆）
var _ch1_dry_x := INF              ## 入口街河面倒影截止的世界 x（往东全为湿青黑石板，零水面）
var _ch1_route_variants: Dictionary = {}
var _prev_hero: Vector2 = Vector2.INF
var _hero_mist_k: float = 0.65


func _try_activate_ch1_shadow_street_on_stage() -> void:
	var st := get_parent()
	if st == null:
		return
	var forced := st.has_meta("ch1_shadow_street") and bool(st.get_meta("ch1_shadow_street"))
	var disabled := st.has_meta("ch1_shadow_street") and not bool(st.get_meta("ch1_shadow_street"))
	if disabled:
		return
	var scene_path := String(st.scene_file_path)
	var is_main_street_scene := (scene_path == "res://scenes/rain_trial.tscn" or scene_path == "res://scenes/rain_street.tscn")
	var is_custom_test_tree := (get_tree() != null and get_tree().get_script() != null)
	if not forced and (not is_main_street_scene or is_custom_test_tree):
		return
	if not FileAccess.file_exists(CH1_LAYOUT_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CH1_LAYOUT_PATH))
	if not (parsed is Dictionary):
		return
	layout = (parsed as Dictionary).duplicate(true)
	_ch1_route_variants = (layout.get("routeVariants", {}) as Dictionary).duplicate(true)
	for sec_item in layout.get("sections", []):
		if sec_item is Dictionary and sec_item.has("ch1_code"):
			_ch1_route_variants[String(sec_item.get("ch1_code"))] = (sec_item as Dictionary).duplicate(true)
	# 开局首段 50% 随机轮换 1-1A「灯影空轿街」与 1-1B「停摆电车雨站」（支持测试脚本通过 ch1_slot0_code 显式指定）
	# 11-18 背景线：1-1A 按方向丙重做成两层街样板角，1-1B 还是旧图；样板角期间开局固定 1-1A（RAIN_OLD_BG=1 时恢复轮换），1-1B 重出后恢复
	var rotate_slot0 := OS.get_environment("RAIN_OLD_BG") == "1"
	var init_slot0_code := String(st.get_meta("ch1_slot0_code")) if st.has_meta("ch1_slot0_code") else ("1-1B" if (rotate_slot0 and not is_custom_test_tree and randi() % 2 == 1) else "1-1A")
	if init_slot0_code == "1-1B" and _ch1_route_variants.has("1-1B"):
		var secs_arr: Array = layout.get("sections", [])
		if not secs_arr.is_empty():
			secs_arr[0] = (_ch1_route_variants["1-1B"] as Dictionary).duplicate(true)
	if "layout" in st:
		st.set("layout", layout)
	var ter: Variant = st.get("terrain") if "terrain" in st else null
	if ter is Node and is_instance_valid(ter):
		var secs: Array = layout.get("sections", [])
		ter.set("sections", secs)
		if ter.has_method("replace_section") and not secs.is_empty():
			var built_dict: Variant = ter.get("_built")
			if built_dict is Dictionary and (built_dict as Dictionary).has(0):
				ter.call("replace_section", 0, first_x, secs[0])
	call_deferred("_bind_ch1_stage_hooks")


func _bind_ch1_stage_hooks() -> void:
	if not _ch1_shadow_mode:
		return
	var st := get_parent()
	if st == null or not is_instance_valid(st):
		return
	var hud_node: Variant = st.get("hud") if "hud" in st else null
	if hud_node is Object and hud_node.has_method("banner"):
		var secs_now: Array = layout.get("sections", [])
		var s0_code := String((secs_now[0] as Dictionary).get("ch1_code", "1-1A")) if not secs_now.is_empty() and secs_now[0] is Dictionary else "1-1A"
		var sub_title := "停摆电车雨站 · 钟停 5:59" if s0_code == "1-1B" else "灯影空轿街 · 钟停 5:59"
		hud_node.call("banner", "第一章 · 影街与司辰母钟楼", sub_title, 3.4)
	_snap_player_to_ch1_ground()
	var fo: Node = st.get_node_or_null("ForkChoiceOverlay")
	if fo != null:
		if fo.has_signal("route_selected"):
			var cb := Callable(self, "_on_stage_fork_route_selected")
			if not fo.is_connected("route_selected", cb):
				fo.connect("route_selected", cb)
		if fo.has_signal("breach_requested"):
			var b_cb := Callable(self, "_on_stage_breach_requested")
			if not fo.is_connected("breach_requested", b_cb):
				fo.connect("breach_requested", b_cb, CONNECT_DEFERRED)
		if fo.has_signal("table_finished"):
			var t_cb := Callable(self, "_on_stage_table_finished")
			if not fo.is_connected("table_finished", t_cb):
				fo.connect("table_finished", t_cb, CONNECT_DEFERRED)


func _on_stage_breach_requested() -> void:
	if not _ch1_shadow_mode:
		return
	var st := get_parent()
	if st == null or not is_instance_valid(st):
		return
	var enc_idx := clampi(int(st.get("encounter_index")) if "encounter_index" in st else 0, 0, 2)
	swap_ch1_slot_stage(enc_idx, "E1")
	var ter: Variant = st.get("terrain") if "terrain" in st else null
	var enc: Variant = st.get("encounter") if "encounter" in st else null
	if ter is Node and is_instance_valid(ter) and ter.has_method("spawn_points") and enc is Object and "spawn_points" in enc:
		enc.set("spawn_points", ter.call("spawn_points", enc_idx, first_x + float(enc_idx) * spacing))


func _on_stage_table_finished() -> void:
	if not _ch1_shadow_mode:
		return
	var st := get_parent()
	if st == null or not is_instance_valid(st):
		return
	var is_custom_test_tree := (get_tree() != null and get_tree().get_script() != null)
	if is_custom_test_tree or st.has_meta("ch1_slot2_code"):
		return
	var enc_idx := int(st.get("encounter_index")) if "encounter_index" in st else 0
	if enc_idx == 2 and randi() % 2 == 1:
		swap_ch1_slot_stage(2, "1-3C")


func _on_stage_fork_route_selected(route_id: String) -> void:
	if not _ch1_shadow_mode:
		return
	var st := get_parent()
	if st == null:
		return
	var enc_idx := int(st.get("encounter_index")) if "encounter_index" in st else 0
	if route_id == "dawn_breach":
		# 破晓乱入 / 同道试刀加赛：就地切入 E1「漏光校晷小广场（白光驱逐时间鲜活定格场）」
		swap_ch1_slot_stage(clampi(enc_idx, 0, 2), "E1")
		return
	var next_slot := enc_idx + 1
	if next_slot == 1:
		swap_ch1_slot_stage(1, "1-2A" if route_id == "bell_tower" else "1-2B")
	elif next_slot == 2:
		if route_id == "bell_tower":
			swap_ch1_slot_stage(2, "1-3C" if randi() % 2 == 1 else "1-3A")
		else:
			swap_ch1_slot_stage(2, "1-3C" if randi() % 2 == 1 else "1-3B")


func swap_ch1_slot_stage(slot_idx: int, code: String) -> void:
	var lookup_key := code
	if code == "E1":
		if slot_idx == 0 and _ch1_route_variants.has("E1_S0"):
			lookup_key = "E1_S0"
		elif slot_idx == 2 and _ch1_route_variants.has("E1_S2"):
			lookup_key = "E1_S2"
	var target_sec: Dictionary = {}
	if _ch1_route_variants.has(lookup_key):
		target_sec = (_ch1_route_variants[lookup_key] as Dictionary).duplicate(true)
	else:
		for s in layout.get("sections", []):
			if s is Dictionary and String(s.get("ch1_code", "")) == code:
				target_sec = (s as Dictionary).duplicate(true)
				break
	if target_sec.is_empty():
		return
	var st := get_parent()
	if st != null and "terrain" in st:
		var ter: Variant = st.get("terrain")
		if ter is Node and is_instance_valid(ter) and ter.has_method("replace_section"):
			ter.call("replace_section", slot_idx, first_x + float(slot_idx) * spacing, target_sec)
	set_ch1_route_code(slot_idx, code, target_sec)
	_snap_player_to_ch1_ground()


func _snap_player_to_ch1_ground() -> void:
	var st := get_parent()
	if st == null or not is_instance_valid(st):
		return
	var ter: Variant = st.get("terrain") if "terrain" in st else null
	var p: Variant = st.get("player") if "player" in st else null
	if ter is Node and is_instance_valid(ter) and ter.has_method("support_y") and p is CharacterBody2D and is_instance_valid(p):
		var foot_off := float(p.get("foot_offset")) if "foot_offset" in p else 0.0
		var cur_foot := (p as CharacterBody2D).global_position.y + foot_off
		if absf(cur_foot - floor_y) <= 72.0:
			var sy := float(ter.call("support_y", (p as CharacterBody2D).global_position.x, floor_y - 120.0))
			if sy < cur_foot - 0.5 and sy >= floor_y - 110.0:
				(p as CharacterBody2D).global_position.y = sy - foot_off - 4.0


func _unfreeze_root_transition_overlays() -> void:
	var tree := get_tree()
	if tree == null or tree.root == null:
		return
	for child in tree.root.get_children():
		if child is CanvasLayer and child.get_script() == null and (child as CanvasLayer).layer >= 100:
			if child.get_child_count() == 1 and child.get_child(0) is ColorRect:
				if child.has_meta("_ch1_unfrozen"):
					continue
				child.set_meta("_ch1_unfrozen", true)
				child.process_mode = Node.PROCESS_MODE_ALWAYS
				var rect := child.get_child(0) as ColorRect
				rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
				# 兜底保险：若跨场景过渡 Tween 因开局暂停帧错位未能自销，也在 0.8s 内平滑退白并释放（绝不卡死白屏）
				var fallback_tw := child.create_tween()
				fallback_tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
				fallback_tw.tween_interval(0.10)
				fallback_tw.tween_property(rect, "modulate:a", 0.0, 0.65).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
				fallback_tw.tween_callback(child.queue_free)


func _ready() -> void:
	_unfreeze_root_transition_overlays()
	_unfreeze_root_transition_overlays.call_deferred()
	_try_activate_ch1_shadow_street_on_stage()
	z_index = -90
	var bd: Dictionary = layout.get("backdrop", {})
	var sky: Dictionary = bd.get("sky", {})
	var far: Dictionary = bd.get("far", {})
	var rain: Dictionary = bd.get("rain", {})
	sky_screen_h = float(sky.get("screenH", SKY_SCREEN_H))
	sky_scroll = float(sky.get("scroll", SKY_SCROLL))
	sky_shift = float(sky.get("shift", SKY_SHIFT))
	far_scroll = float(far.get("scroll", FAR_SCROLL))
	far_top = float(far.get("top", FAR_TOP))
	rain_drops = maxi(1, int(rain.get("drops", RAIN_DROPS)))
	rain_through = maxi(1, int(rain.get("through", RAIN_THROUGH)))
	rain_speed = float(rain.get("speed", RAIN_SPEED))
	rain_wind = float(rain.get("wind", RAIN_WIND))
	_apply_d1_backdrop_tuning(bd)
	_sky_tex = _load_tex(String(sky.get("tex", SKY_TEX)))
	_far_tex = _load_tex(String(far.get("tex", FAR_TEX)))
	for spec in bd.get("depth", DEPTH_ROWS):
		var depth_tex := _load_tex(String(spec.tex))
		if depth_tex != null:
			_depth_rows.append({"tex": depth_tex, "scroll": spec.scroll, "bottom": spec.bottom})
	for spec in bd.get("front", []):   # 前景剪影层（默认没有；一屏样板用，见 tools/art/rain_mood_sample.py）
		var front_tex := _load_tex(String(spec.tex))
		if front_tex != null:
			_front_rows.append({"tex": front_tex, "scroll": spec.scroll, "top": spec.top})
	if _far_tex != null:
		var img := _far_tex.get_image()
		var acc := Color(0, 0, 0, 0)
		for x in range(0, img.get_width(), 8):
			acc += img.get_pixel(x, img.get_height() - 1)
		if acc.a > 0.0:   # 修改器换的图下沿可能全透明
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
	var m := ShaderMaterial.new()
	m.shader = GlowShader
	_glow.material = m
	_glow.draw.connect(_draw_glow)
	add_child(_glow)
	_fg = Node2D.new()
	_fg.z_as_relative = false   # 同水面：不叠加父节点的 −90，雨丝和前景件才真的在角色前面
	_fg.z_index = 20
	_fg.draw.connect(_draw_fg)
	add_child(_fg)
	if _is_street_mode():
		_build_street_layers()
	_build_rain()
	if _is_street_mode() and layout.get("layered") is Dictionary:
		_build_layered(layout.layered)
	ok = true


func _build_layered(cfg: Dictionary) -> void:
	_ch1_shadow_mode = bool(cfg.get("ch1ShadowStreet", false))
	_layered = StreetLayered.new()
	_layered.name = "Layered"
	_layered.setup(self, cfg)
	add_child(_layered)
	_layer_edge = _layered.edge_x
	if _ch1_shadow_mode:
		_ch1_dry_x = float(cfg.get("ch1DryX", 2018.0))
		if _ch1_dry_x <= -1000.0:
			_water.modulate.a = 0.0
			_water.visible = false
		if _fog_near != null:
			_fog_near.visible = false
	_sky.visible = false             # 天空、远景城市
	for n in [_depth_deep, _depth_near, _fog_far, _fog_mid]:   # 背街两排和它们之间的雾
		if n != null:
			n.visible = false


func set_ch1_route_code(slot_idx: int, code: String, sec_dict: Dictionary = {}) -> void:
	var secs: Array = layout.get("sections", [])
	if slot_idx >= 0 and slot_idx < secs.size() and not sec_dict.is_empty():
		secs[slot_idx] = sec_dict
	_occ_key = ""
	if _layered != null and _layered.has_method("set_ch1_route_code"):
		_layered.call("set_ch1_route_code", slot_idx, code)


func is_interior() -> bool:
	return false


func _is_street_mode() -> bool:
	return not is_interior() and get_script().resource_path.ends_with("/street_backdrop.gd")


func set_ult_mode(on: bool) -> void:
	_fg.visible = not on
	_rain.visible = not on
	_splash.visible = not on
	_rain_through.visible = not on
	_ground.visible = not on
	if _fog_near != null:
		_fog_near.visible = (not _ch1_shadow_mode) and fog_enabled and not on
	if _ledge_wet != null:
		_ledge_wet.visible = ledge_sheen > 0.001 and not on
	if _soft_glow != null:
		_soft_glow.visible = not on
	if _arch_pool != null:
		_arch_pool.visible = daylight_enabled and not on
	if _bead_back != null:
		_bead_back.visible = daylight_enabled and beads_enabled and not on
	if _bead_front != null:
		_bead_front.visible = daylight_enabled and beads_enabled and not on
	if _layered != null:
		_layered.set_ult_mode(on)


func moon_screen() -> Vector2:
	if _layered != null:   # 分层背景的天上没有月亮：月光光柱的源头放到很远的上方，光柱就没了
		return Vector2(640.0, -40000.0)
	if _sky_tex == null:
		return MOON
	var k := sky_screen_h / float(_sky_tex.get_height())
	var tw := float(_sky_tex.get_width()) * k
	var off := fposmod(_center().x * sky_scroll * _z() - sky_shift, 2.0 * tw)   # 镜像平铺：两张一个周期，月亮在正向那张里
	var x := -off + SKY_MOON.x * k
	if x < 640.0 - tw:
		x += 2.0 * tw
	return Vector2(x, _sky_top() + SKY_MOON.y * k)


func _sky_top() -> float:
	return -50.0 - (_center().y - 272.0) * _z() * 0.05


## 修改器出的图没经过编辑器导入，ResourceLoader 找不到，直接读 PNG（导出包的 *.png 过滤器会带上原文件）。
static func _load_tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	if not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	if image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
		return null
	return ImageTexture.create_from_image(image)


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
	var sp := 7.2 + 2.4 * _hash(int(roundf(x)), 19)
	return 0.87 + 0.085 * sin(_time * sp + x * 0.37) + 0.045 * sin(_time * (sp * 2.65) + x * 0.19 + 1.1)


func _process(delta: float) -> void:
	_time += delta
	_collect_lamps()
	queue_redraw()
	_sky.queue_redraw()
	_glow.queue_redraw()
	_fg.queue_redraw()
	if _ch1_shadow_mode:
		var w_fade := 0.0 if _ch1_dry_x <= -1000.0 else (1.0 - clampf((_center().x - (_ch1_dry_x - 260.0)) / 520.0, 0.0, 1.0))
		_water.modulate.a = w_fade
		_water.visible = w_fade > 0.004
	_water.queue_redraw()
	_ground.queue_redraw()
	if _is_street_mode():
		_process_street_layers(delta)
	_update_rain()


# ---------------------------------------------------------------- 镜头 / 布局

func _z() -> float:
	return camera.zoom.x if camera != null and camera.zoom.x > 0.0 else 1.0


func _center() -> Vector2:
	return camera.get_screen_center_position() if camera != null else Vector2(640, 360)


## 屏幕像素 → 世界坐标（贴屏幕的东西用）
func _scr(p: Vector2) -> Vector2:
	return _center() + (p - Vector2(640, 360)) / _z()


## 镜头附近的几处：[{center, sec, idx, slot}]
func _near_sections() -> Array:
	var out: Array = []
	var secs: Array = layout.get("sections", [])
	if secs.is_empty():
		return out
	var k := int(floor((_center().x - first_x) / spacing))
	for i in range(k - 1, k + 2):
		var idx := posmod(i, secs.size())
		var sec: Dictionary = secs[idx]
		if i < 0 and _layered != null:   # 开局入口街是分层站立层：上一段的成图、平台、灯、前景、门洞都不要
			sec = {}
		out.append({"center": first_x + float(i) * spacing, "sec": sec, "idx": idx, "slot": i})
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
			var lay: bool = l.size() > 4 and l[4] is Dictionary and l[4].get("layered", false)   # 分层站立层上画的灯：光晕由 street_layered 画
			_lamps.append({"p": Vector2(x, y - rise), "base": Vector2(x, y), "street": street, "art": _in_span(span, x, x), "layered": lay})


# ---------------------------------------------------------------- 天空 + 远景（贴屏幕 / 慢视差）

func _draw_sky() -> void:
	if camera == null:
		return
	if _sky_tex != null and _far_tex != null:
		_draw_art_sky()
		_draw_art_far()
		if not _is_street_mode():
			for d in _depth_rows:
				_draw_art_depth(d)
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


## 天空成图：几乎贴屏幕（sky_scroll），按屏幕像素算好再换回世界坐标
func _draw_art_sky() -> void:
	var z := _z()
	var k := sky_screen_h / float(_sky_tex.get_height())
	var tw := float(_sky_tex.get_width()) * k
	var off := fposmod(_center().x * sky_scroll * z - sky_shift, 2.0 * tw)
	var top := _scr(Vector2(0.0, _sky_top())).y
	var l := _scr(Vector2(-off, 0.0)).x
	_mirror_tiles(_sky, _sky_tex, l, tw / z, top, sky_screen_h / z, _scr(Vector2(1290.0, 0.0)).x, false)
	var bottom := top + sky_screen_h / z
	var br := _scr(Vector2(1284.0, 724.0))
	if br.y > bottom:   # 镜头往上看到头时，天空图下面接雾色
		_sky.draw_rect(Rect2(Vector2(_scr(Vector2(-4.0, 0.0)).x, bottom), Vector2(br.x - _scr(Vector2(-4.0, 0.0)).x, br.y - bottom)), _far_fog)


## 远景城市成图：和近景同一比例，far_scroll 视差，镜像平铺；图下面接同色的雾
func _draw_art_far() -> void:
	var c := _center()
	var tw := float(_far_tex.get_width()) * ART_SCALE
	var th := float(_far_tex.get_height()) * ART_SCALE
	var top := far_top + (c.y - 272.0) * (1.0 - far_scroll)
	var l := _scr(Vector2(-4.0, 0.0)).x
	var r := _scr(Vector2(1284.0, 0.0)).x
	var u0 := floorf((l - c.x * (1.0 - far_scroll)) / tw)   # 屏幕左边落在这一层第几张
	var x_first := c.x * (1.0 - far_scroll) + u0 * tw
	_mirror_tiles(_sky, _far_tex, x_first, tw, top, th, r, posmod(int(u0), 2) == 1)
	var bot := _scr(Vector2(0.0, 724.0)).y
	if bot > top + th:
		_sky.draw_rect(Rect2(l, top + th - 1.0, r - l, bot - top - th + 1.0), _far_fog)


## 街道深处的背街（tools/art/rain_kit_depth.py）：夹在远景和近景之间，图的下沿落在 bottom（镜头在街面取景时），镜像平铺
func _draw_art_depth(d: Dictionary, ci: CanvasItem = null) -> void:
	var target: CanvasItem = ci if ci != null else _sky
	var tex: Texture2D = d.tex
	var scroll: float = d.scroll
	var c := _center()
	var tw := float(tex.get_width()) * ART_SCALE
	var th := float(tex.get_height()) * ART_SCALE
	var top: float = float(d.bottom) - th + (c.y - 272.0) * (1.0 - scroll)
	var l := _scr(Vector2(-4.0, 0.0)).x
	var r := _scr(Vector2(1284.0, 0.0)).x
	var u0 := floorf((l - c.x * (1.0 - scroll)) / tw)
	_mirror_tiles(target, tex, c.x * (1.0 - scroll) + u0 * tw, tw, top, th, r, posmod(int(u0), 2) == 1)


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
	if bot > WATER_Y:   # 入口街往东在第一章影街模式下为干湿青黑石板基座，禁河水
		var water_r := minf(r, _ch1_dry_x)
		if water_r > l:
			draw_rect(Rect2(l, WATER_Y, water_r - l, bot - WATER_Y), C_WATER)
		if r > _ch1_dry_x:
			var dry_l := maxf(l, _ch1_dry_x)
			draw_rect(Rect2(dry_l, WATER_Y, r - dry_l, bot - WATER_Y), Color(0.04, 0.05, 0.08))


## 湿街面那一条：涟漪全由 rain_ground.gdshader 算
func _draw_ground() -> void:
	if camera == null:
		return
	var l := _scr(Vector2(-4, 0)).x
	var r := _scr(Vector2(1284, 0)).x
	_ground.draw_rect(Rect2(l, floor_y - 2.0, r - l, 30.0), Color.WHITE)


## 河面：一块盖住水线以下屏幕的矩形，颜色全由 rain_water.gdshader 算（第一章影街仅保留入口街区段倒影，往东零水面）
func _draw_water() -> void:
	if camera == null:
		return
	var l := _scr(Vector2(-4, 0)).x
	var r := minf(_scr(Vector2(1284, 0)).x, _ch1_dry_x)
	var bot := _scr(Vector2(0, 724)).y
	if bot > WATER_Y and r > l:
		_water.draw_rect(Rect2(l, WATER_Y, r - l, bot - WATER_Y), Color.WHITE)


func _draw_lamp_posts() -> void:
	for lp in _lamps:
		var b: Vector2 = lp.base
		if lp.art or lp.get("layered", false) or _ch1_shadow_mode:   # 成图与分层场景里已画灯杆
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
		if lp.art or lp.get("layered", false) or _ch1_shadow_mode:   # 成图里已经画了灯的光晕（外加 _soft_glow IGN 柔光），不叠旧圆盘
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
	if not _ch1_shadow_mode:
		for d in _front_rows:
			_draw_art_front(d)
	var hit_rects := _actor_rects()
	# 底边原来有一排河岸栏杆 + 铁链（视差 1.15），正好压在水面上挡住倒影，2026-10-29 去掉
	# 大件前景：按布局摆，各自的视差；压到角色时变淡
	for s in _near_sections():
		var span := _art_span(s)
		for item in s.sec.get("foreground", []):
			var kind := String(item[1])
			var k := float(rules.get(kind, {}).get("scroll", 1.3))
			var wx: float = float(s.center) + float(item[0])
			if _in_span(span, wx, wx) or wx < _layer_edge:   # 成图段先不放灰盒前景件（朱红长旗和成图配色冲突），前景层之后按成图另做；入口街有自己的前景
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


## 前景剪影层：比角色更靠近镜头，视差 > 1，镜像平铺；top = 镜头在街面取景时图上沿的世界 y
func _draw_art_front(d: Dictionary) -> void:
	var tex: Texture2D = d.tex
	var k: float = d.scroll
	var c := _center()
	var tw := float(tex.get_width()) * ART_SCALE
	var th := float(tex.get_height()) * ART_SCALE
	var top: float = float(d.top) + (c.y - 272.0) * (1.0 - k)
	var l := _scr(Vector2(-4.0, 0.0)).x
	var r := _scr(Vector2(1284.0, 0.0)).x
	var u0 := floorf((c.x + (l - c.x) / k) / tw)
	_mirror_tiles(_fg, tex, c.x + (u0 * tw - c.x) * k, tw * k, top, th * k, r, posmod(int(u0), 2) == 1)


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
	pm.direction = Vector3(rain_wind, 1.0, 0.0)
	pm.spread = 2.0
	pm.initial_velocity_min = rain_speed * 0.85
	pm.initial_velocity_max = rain_speed * 1.1
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
	_rain.amount = rain_drops
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
	_rain_through.amount = rain_through
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
			if not (p.size() > 4 and p[4] is Dictionary and p[4].get("off", false)):
				_add_occluder(cx + float(p[0]), cx + float(p[1]), float(p[2]), _bar_h(p, false))
		for b in s.sec.get("blocks", []):
			if not (b.size() > 4 and b[4] is Dictionary and b[4].get("off", false)):
				_add_occluder(cx + float(b[0]), cx + float(b[1]), float(b[2]), _bar_h(b, true))
		for r in s.sec.get("slopes", []):   # 雨也落在斜坡上
			if not (r.size() > 5 and r[5] is Dictionary and r[5].get("off", false)):
				_add_slope_occluder(cx + float(r[0]), float(r[1]), cx + float(r[2]), float(r[3]))
		if _is_street_mode() and daylight_enabled:   # 雨进了门洞/桥洞昼光边界就停住
			for a in _section_arches(s.sec):
				_add_arch_occluder(cx + float(a[0]), float(a[1]), float(a[2]), float(a[3]))


## 雨打在这条平台或石台上的厚度：能跳穿的是薄片，实心的到它的下沿
func _bar_h(row: Array, is_block: bool) -> float:
	var o: Dictionary = row[4] if row.size() > 4 and row[4] is Dictionary else {}
	if o.get("pass", false) or not o.get("solid", is_block):
		return 14.0
	return minf(float(o.get("bottom", floor_y if is_block else float(row[2]) + 14.0)), floor_y) - float(row[2])


func _add_occluder(x0: float, x1: float, y: float, h: float) -> void:
	var poly := OccluderPolygon2D.new()
	poly.polygon = PackedVector2Array([Vector2(x0, y), Vector2(x1, y), Vector2(x1, y + h), Vector2(x0, y + h)])
	var o := LightOccluder2D.new()
	o.occluder = poly
	o.sdf_collision = true
	o.occluder_light_mask = 0
	_occluders.add_child(o)


func _add_slope_occluder(x0: float, y0: float, x1: float, y1: float) -> void:
	var poly := OccluderPolygon2D.new()
	poly.polygon = PackedVector2Array([Vector2(x0, y0), Vector2(x1, y1), Vector2(x1, y1 + 14.0), Vector2(x0, y0 + 14.0)])
	var o := LightOccluder2D.new()
	o.occluder = poly
	o.sdf_collision = true
	o.occluder_light_mask = 0
	_occluders.add_child(o)


func _add_arch_occluder(wx: float, hw: float, y_top: float, y_bot: float) -> void:
	if hw <= 4.0 or y_bot <= y_top + 8.0:
		return
	var poly := OccluderPolygon2D.new()
	poly.polygon = _arch_polygon(wx, hw, y_top, y_bot)
	var o := LightOccluder2D.new()
	o.occluder = poly
	o.sdf_collision = true
	o.occluder_light_mask = 0
	_occluders.add_child(o)


static func _hash(a: int, b: int) -> float:
	var n := (a * 374761393 + b * 668265263) & 0x7fffffff
	n = ((n ^ (n >> 13)) * 1274126177) & 0x7fffffff
	return float((n ^ (n >> 16)) & 0xffff) / 65535.0


# ---------------------------------------------------------------- D1 零生图分层质感：3 层 IGN 流动雾 + 门洞昼光悬停白珠 + 湿台面亮边与柔光微闪

func _apply_d1_backdrop_tuning(bd: Dictionary) -> void:
	var fog_cfg: Variant = bd.get("fog", {})
	if fog_cfg is bool:
		fog_enabled = fog_cfg
	elif fog_cfg is Dictionary:
		var fd: Dictionary = fog_cfg
		fog_enabled = bool(fd.get("enabled", true))
		fog_far_strength = float(fd.get("farStrength", FOG_FAR_STRENGTH))
		fog_mid_strength = float(fd.get("midStrength", FOG_MID_STRENGTH))
		fog_near_strength = float(fd.get("nearStrength", FOG_NEAR_STRENGTH))
		hero_mist_gain = float(fd.get("heroMist", HERO_MIST_GAIN))
	var day_cfg: Variant = bd.get("daylight", {})
	if day_cfg is bool:
		daylight_enabled = day_cfg
	elif day_cfg is Dictionary:
		var dd: Dictionary = day_cfg
		daylight_enabled = bool(dd.get("enabled", true))
		daylight_gain = float(dd.get("gain", 1.0))
		beads_enabled = bool(dd.get("beads", true))
	var ledge_cfg: Variant = bd.get("ledgeSheen", 1.0)
	if ledge_cfg is float or ledge_cfg is int:
		ledge_sheen = float(ledge_cfg)
	elif ledge_cfg is Dictionary:
		var ld: Dictionary = ledge_cfg
		ledge_sheen = float(ld.get("gain", 1.0)) if bool(ld.get("enabled", true)) else 0.0
	var lg_cfg: Variant = bd.get("lampGlow", 1.0)
	if lg_cfg is float or lg_cfg is int:
		lamp_glow_gain = float(lg_cfg)
	elif lg_cfg is Dictionary:
		var gd: Dictionary = lg_cfg
		lamp_glow_gain = float(gd.get("gain", 1.0)) if bool(gd.get("enabled", true)) else 0.0


func _build_street_layers() -> void:
	var fn := FastNoiseLite.new()
	fn.seed = 20261108
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fn.frequency = 0.018
	fn.fractal_octaves = 4
	_fog_noise = ImageTexture.create_from_image(fn.get_seamless_image(128, 128))
	_glow_tex = _make_glow_tex()
	_beam_tex = _make_beam_tex()
	_bead_tex = _make_bead_tex()

	# 远、中、近 3 层带 IGN 抖动的流动雾，把两排背街与近景站立层彻底拉开深度；
	# 第 3 层（_fog_near，z = -84）贴在近景暗墙前、地形与角色后，给两灯之间的死黑墙面铺一层微弱冷雾衬底。
	_fog_far = _add_fog_layer(-98, Color(0.14, 0.18, 0.28), 0.25, 0.012, 0.05, 0.84, 1.05, fog_far_strength, 0.12)
	_depth_deep = _add_plain_layer(-96, _draw_depth_split.bind(true))
	_fog_mid = _add_fog_layer(-95, Color(0.20, 0.25, 0.36), 0.55, 0.018, 0.03, 0.90, 1.05, fog_mid_strength, 0.14)
	_depth_near = _add_plain_layer(-94, _draw_depth_split.bind(false))
	_arch_mask = _add_plain_layer(-92, _draw_arch_mask)
	_arch_back = _add_glow_layer(-91, _draw_arch_back)
	_fog_near = _add_fog_layer(-84, Color(0.20, 0.26, 0.38), 0.78, 0.024, 0.18, 0.78, 0.90, fog_near_strength, 0.32)
	_ledge_wet = _add_plain_layer(-79, _draw_ledge_wet)
	_soft_glow = _add_glow_layer(-78, _draw_soft_glow)
	_bead_back = _add_plain_layer(-76, _draw_beads.bind(false))
	_arch_pool = _add_glow_layer(-6, _draw_arch_pool)
	_bead_front = _add_plain_layer(-2, _draw_beads.bind(true))

	_fog_far.visible = fog_enabled
	_fog_mid.visible = fog_enabled
	_fog_near.visible = fog_enabled
	_arch_mask.visible = daylight_enabled
	_arch_back.visible = daylight_enabled
	_arch_pool.visible = daylight_enabled
	_ledge_wet.visible = ledge_sheen > 0.001
	_bead_back.visible = daylight_enabled and beads_enabled
	_bead_front.visible = daylight_enabled and beads_enabled


func _add_plain_layer(z: int, cb: Callable) -> Node2D:
	var n := Node2D.new()
	n.z_as_relative = false
	n.z_index = z
	n.draw.connect(cb)
	add_child(n)
	return n


func _add_glow_layer(z: int, cb: Callable) -> Node2D:
	var n := _add_plain_layer(z, cb)
	var m := ShaderMaterial.new()
	m.shader = GlowShader
	n.material = m
	return n


func _add_fog_layer(z: int, col: Color, k: float, spd: float, y0: float, y1: float, y_end: float, strength: float, base_lift: float) -> Node2D:
	var m := ShaderMaterial.new()
	m.shader = FogShader
	m.set_shader_parameter("n", _fog_noise)
	m.set_shader_parameter("col", col)
	m.set_shader_parameter("k", k)
	m.set_shader_parameter("spd", spd)
	m.set_shader_parameter("y0", y0)
	m.set_shader_parameter("y1", y1)
	m.set_shader_parameter("y_end", y_end)
	m.set_shader_parameter("strength", strength)
	m.set_shader_parameter("base_lift", base_lift)
	var n := Node2D.new()
	n.z_as_relative = false
	n.z_index = z
	n.material = m
	n.draw.connect(_draw_fog_quad.bind(n))
	add_child(n)
	_fog_mats.append(m)
	return n


static func _make_glow_tex() -> Texture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.22, 0.48, 0.76, 1.0])
	g.colors = PackedColorArray([
		Color(1, 1, 1, 1.0),
		Color(1, 1, 1, 0.62),
		Color(1, 1, 1, 0.28),
		Color(1, 1, 1, 0.06),
		Color(1, 1, 1, 0.0),
	])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 256
	t.height = 256
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	return t


static func _make_beam_tex() -> Texture2D:
	var im := Image.create_empty(32, 32, false, Image.FORMAT_RGBA8)
	for yy in 32:
		var v := float(yy) / 31.0
		var fade := smoothstep(0.0, 0.25, v) * (1.0 - smoothstep(0.7, 1.0, v))
		for xx in 32:
			var hx := 1.0 - absf(float(xx) / 15.5 - 1.0)
			im.set_pixel(xx, yy, Color(1, 1, 1, hx * fade))
	return ImageTexture.create_from_image(im)


static func _make_bead_tex() -> Texture2D:
	var bi := Image.create_empty(32, 32, false, Image.FORMAT_RGBA8)
	for yy in 32:
		for xx in 32:
			var d := Vector2(float(xx) - 15.5, float(yy) - 15.5).length() / 15.5
			bi.set_pixel(xx, yy, Color(1, 1, 1, clampf((1.0 - d) * 2.4, 0.0, 1.0)))
	return ImageTexture.create_from_image(bi)


func _process_street_layers(delta: float) -> void:
	var cx := _center().x
	for m in _fog_mats:
		var sm := m as ShaderMaterial
		sm.set_shader_parameter("cam_x", cx)
		sm.set_shader_parameter("t", _time)
	if _layered != null and _fog_near != null:   # 近墙冷雾是给旧近景成图的：入口街与第一章影街都有各自的分层雾，不再叠一层旧蓝雾
		var w := 0.0 if _ch1_shadow_mode else clampf((cx - _layer_edge) / 900.0, 0.0, 1.0)
		(_fog_near.material as ShaderMaterial).set_shader_parameter("strength", fog_near_strength * w)
	_update_beads(delta)
	_fog_far.queue_redraw()
	_fog_mid.queue_redraw()
	_fog_near.queue_redraw()
	_depth_deep.queue_redraw()
	_depth_near.queue_redraw()
	_arch_mask.queue_redraw()
	_arch_back.queue_redraw()
	_arch_pool.queue_redraw()
	_ledge_wet.queue_redraw()
	_soft_glow.queue_redraw()
	_bead_back.queue_redraw()
	_bead_front.queue_redraw()


func _section_arches(sec: Dictionary) -> Array:
	if sec.has("arches"):
		var arr: Variant = sec.get("arches")
		return arr if arr is Array else []
	var sec_name := String(sec.get("name", ""))
	return DEFAULT_ARCHES.get(sec_name, [])


static func _arch_polygon(wx: float, hw: float, y_top: float, y_bot: float) -> PackedVector2Array:
	var h := y_bot - y_top
	var y_spring := y_top + minf(h * 0.42, hw * 1.15)
	var y_shoulder := y_top + (y_spring - y_top) * 0.36
	return PackedVector2Array([
		Vector2(wx - hw, y_bot),
		Vector2(wx - hw, y_spring),
		Vector2(wx - hw * 0.62, y_shoulder),
		Vector2(wx, y_top),
		Vector2(wx + hw * 0.62, y_shoulder),
		Vector2(wx + hw, y_spring),
		Vector2(wx + hw, y_bot),
	])


func _draw_fog_quad(ci: Node2D) -> void:
	if camera == null or not fog_enabled:
		return
	var tl := _scr(Vector2(-8.0, -8.0))
	var br := _scr(Vector2(1288.0, 728.0))
	ci.draw_rect(Rect2(tl, br - tl), Color.WHITE)


func _draw_depth_split(far_half: bool) -> void:
	if camera == null or _sky_tex == null or _far_tex == null or _depth_rows.is_empty():
		return
	var n := _depth_rows.size()
	var split := maxi(1, n / 2) if n > 1 else 1
	var from_i := 0 if far_half else split
	var to_i := split if far_half else n
	var target: CanvasItem = _depth_deep if far_half else _depth_near
	for i in range(from_i, to_i):
		_draw_art_depth(_depth_rows[i], target)


func _draw_glow_quad(ci: CanvasItem, tex: Texture2D, center: Vector2, size: Vector2, col: Color, gain_a: float, rot: float = 0.0) -> void:
	if gain_a <= 0.002 or tex == null:
		return
	var c := Color(col.r, col.g, col.b, gain_a)
	if absf(rot) > 0.0001:
		ci.draw_set_transform(center, rot, Vector2.ONE)
		ci.draw_texture_rect(tex, Rect2(-size * 0.5, size), false, c)
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		ci.draw_texture_rect(tex, Rect2(center - size * 0.5, size), false, c)


## 镂空拱门背后的暗雾底衬：压住后排平铺楼影，走动时背街屋脊不会横穿昼光核心
func _draw_arch_mask() -> void:
	if camera == null or not daylight_enabled:
		return
	var view_l := _scr(Vector2(-160.0, 0.0)).x
	var view_r := _scr(Vector2(1440.0, 0.0)).x
	for s in _near_sections():
		var cx := float(s.center)
		for a in _section_arches(s.sec):
			var kind := String(a[4]) if a.size() > 4 else "open"
			if kind != "open":
				continue
			var wx := cx + float(a[0])
			var hw := float(a[1])
			if wx + hw < view_l or wx - hw > view_r:
				continue
			_arch_mask.draw_colored_polygon(_arch_polygon(wx, hw * 1.06, float(a[2]) - 8.0, float(a[3]) + 2.0), Color(0.065, 0.082, 0.135, 0.84))


## 镂空拱门背后的昼光核心与斜射光束（画在近景成图 z=-90 之后，由成图石拱天然裁切）
func _draw_arch_back() -> void:
	if camera == null or not daylight_enabled or daylight_gain <= 0.001:
		return
	var cam_x := _center().x
	var view_l := _scr(Vector2(-200.0, 0.0)).x
	var view_r := _scr(Vector2(1480.0, 0.0)).x
	for s in _near_sections():
		var cx := float(s.center)
		for a in _section_arches(s.sec):
			var kind := String(a[4]) if a.size() > 4 else "open"
			if kind != "open":
				continue
			var wx := cx + float(a[0])
			var hw := float(a[1])
			if wx + hw * 1.8 < view_l or wx - hw * 1.8 > view_r:
				continue
			var y_top := float(a[2])
			var y_bot := float(a[3])
			var h := maxf(y_bot - y_top, 60.0)
			var w := hw * 2.0
			var par := (cam_x - wx) * 0.08   # 0.92 深度轻微视差，门洞深处的光更有纵深
			_draw_glow_quad(_arch_back, _glow_tex, Vector2(wx + par, y_bot - h * 0.30), Vector2(w * 1.48, h * 1.32), C_DAYLIGHT, 0.56 * daylight_gain)
			_draw_glow_quad(_arch_back, _glow_tex, Vector2(wx + par, y_bot - 14.0), Vector2(w * 0.92, minf(h * 0.68, 300.0)), C_DAYLIGHT, 0.46 * daylight_gain)
			_draw_glow_quad(_arch_back, _beam_tex, Vector2(wx + par * 0.7, y_top + h * 0.46), Vector2(w * 0.98, h * 1.12), C_DAYLIGHT, 0.22 * daylight_gain, -0.10)


## 门洞/桥洞昼光泼到湿街面上的光滩（z = -6，可被河面 rain_water 实时倒映）
func _draw_arch_pool() -> void:
	if camera == null or not daylight_enabled or daylight_gain <= 0.001:
		return
	var view_l := _scr(Vector2(-240.0, 0.0)).x
	var view_r := _scr(Vector2(1520.0, 0.0)).x
	for s in _near_sections():
		var cx := float(s.center)
		for a in _section_arches(s.sec):
			var wx := cx + float(a[0])
			var hw := float(a[1])
			if wx + hw * 2.2 < view_l or wx - hw * 2.2 > view_r:
				continue
			var y_bot := float(a[3])
			var w := hw * 2.0
			_draw_glow_quad(_arch_pool, _glow_tex, Vector2(wx, y_bot + 14.0), Vector2(maxf(w * 2.1, 240.0), 76.0), C_DAYLIGHT, 0.48 * daylight_gain)
			_draw_glow_quad(_arch_pool, _glow_tex, Vector2(wx, y_bot + 8.0), Vector2(maxf(w * 0.95, 120.0), 42.0), C_DAYLIGHT, 0.42 * daylight_gain)


## 可站立台面湿亮边微调：只沿生效的平台、石台、斜坡顶沿描断续湿石反光，严守原有坐标与 off 开关
func _draw_ledge_wet() -> void:
	if camera == null or ledge_sheen <= 0.001:
		return
	var view_l := _scr(Vector2(-80.0, 0.0)).x
	var view_r := _scr(Vector2(1360.0, 0.0)).x
	for s in _near_sections():
		var cx := float(s.center)
		var slot_seed := int(s.get("slot", 0)) * 97 + int(s.get("idx", 0)) * 31
		var pi := 0
		for p in s.sec.get("platforms", []):
			if not (p.size() > 4 and p[4] is Dictionary and (p[4].get("off", false) or p[4].get("layered", false) or p[4].get("ch1_hidden", false))):   # 分层/第一章厚涂台面自带手绘湿亮边
				var py := float(p[2])
				_draw_wet_span(cx + float(p[0]), py, cx + float(p[1]), py, slot_seed * 131 + pi, view_l, view_r)
			pi += 1
		var bi := 0
		for b in s.sec.get("blocks", []):
			if not (b.size() > 4 and b[4] is Dictionary and (b[4].get("off", false) or b[4].get("ch1_hidden", false))):
				var bx0 := cx + float(b[0])
				var bx1 := cx + float(b[1])
				var by := float(b[2])
				_draw_wet_span(bx0, by, bx1, by, slot_seed * 197 + 500 + bi, view_l, view_r)
			bi += 1
		var si := 0
		for r in s.sec.get("slopes", []):
			if not (r.size() > 5 and r[5] is Dictionary and (r[5].get("off", false) or r[5].get("ch1_hidden", false))):
				_draw_wet_span(cx + float(r[0]), float(r[1]), cx + float(r[2]), float(r[3]), slot_seed * 251 + 900 + si, view_l, view_r)
			si += 1


func _draw_wet_span(x0: float, y0: float, x1: float, y1: float, seed_id: int, view_l: float, view_r: float) -> void:
	var span_w := x1 - x0
	if span_w < 12.0:
		return
	var pad := minf(6.0, span_w * 0.08)
	var sx0 := x0 + pad
	var sx1 := x1 - pad
	if sx1 < view_l or sx0 > view_r:
		return
	var step := 44.0
	var first_idx := maxi(0, int(floorf((view_l - 60.0 - sx0) / step)))
	var last_idx := mini(int(ceilf((sx1 - sx0) / step)), int(ceilf((view_r + 60.0 - sx0) / step)))
	var gain := clampf(ledge_sheen, 0.0, 2.5)
	for seg_i in range(first_idx, last_idx + 1):
		var h0 := _hash(seed_id, seg_i * 3)
		var gap := (4.0 + 7.0 * _hash(seed_id, seg_i * 3 + 1)) if h0 > 0.26 else 0.0
		var ax := maxf(sx0, sx0 + float(seg_i) * step + gap * 0.5)
		var bx := minf(sx1, sx0 + float(seg_i + 1) * step - gap * 0.5)
		if bx - ax < 5.0:
			continue
		var t0 := (ax - x0) / span_w
		var t1 := (bx - x0) / span_w
		var p0 := Vector2(ax, lerpf(y0, y1, t0))
		var p1 := Vector2(bx, lerpf(y0, y1, t1))
		var mid := (p0 + p1) * 0.5
		var shim := 0.86 + 0.14 * sin(_time * 2.3 + _hash(seed_id, seg_i * 5 + 2) * TAU)
		var lw := clampf(lantern_light(mid).x, 0.0, 1.0)
		var col := C_LEDGE_WET.lerp(Color(0.98, 0.85, 0.62), lw * 0.55)
		var a := (0.20 + 0.14 * _hash(seed_id, seg_i * 7 + 3)) * shim * gain
		_ledge_wet.draw_line(p0 + Vector2(0.0, 1.0), p1 + Vector2(0.0, 1.0), Color(col, a * 0.30), 4.5)
		_ledge_wet.draw_line(p0, p1, Color(col, a * 0.88), 1.8)


## 站立层前方的柔光层（z = -78，IGN 加色无色带）：
## 1) 路灯与壁灯火苗微闪柔光 + 路面暖斑；
## 2) 门洞/桥洞两侧石柱受光勾边与实心绘景拱门内部昼光晕染；
## 3) 主角走在两灯之间死黑墙面前的自适应微弱冷雾衬底（进灯下或昼光自动隐退）。
func _draw_soft_glow() -> void:
	if camera == null:
		return
	var view_l := _scr(Vector2(-260.0, 0.0)).x
	var view_r := _scr(Vector2(1540.0, 0.0)).x
	if lamp_glow_gain > 0.001:
		for lp in _lamps:
			var p: Vector2 = lp.p
			if p.x < view_l or p.x > view_r or lp.get("layered", false):
				continue
			var f := _flicker(p.x)
			var street := bool(lp.street)
			var rad := 400.0 if street else 290.0
			var base_a := (0.115 if street else 0.095) * lamp_glow_gain * f
			_draw_glow_quad(_soft_glow, _glow_tex, p, Vector2(rad, rad), C_LAMP_SOFT, base_a)
			if street:
				var b: Vector2 = lp.base
				var pool_w := 340.0 if b.y >= floor_y - 1.0 else 200.0
				_draw_glow_quad(_soft_glow, _glow_tex, Vector2(b.x, b.y + 6.0), Vector2(pool_w, pool_w * 0.22), C_LAMP_SOFT, 0.09 * lamp_glow_gain * f)

	if daylight_enabled and daylight_gain > 0.001:
		for s in _near_sections():
			var cx := float(s.center)
			for a in _section_arches(s.sec):
				var wx := cx + float(a[0])
				var hw := float(a[1])
				if wx + hw * 1.8 < view_l or wx - hw * 1.8 > view_r:
					continue
				var y_top := float(a[2])
				var y_bot := float(a[3])
				var h := maxf(y_bot - y_top, 60.0)
				var w := hw * 2.0
				var kind := String(a[4]) if a.size() > 4 else "open"
				if kind == "painted":   # 绘有雾巷内景的拱门：在近景之上柔和提亮昼光纵深
					_draw_glow_quad(_soft_glow, _glow_tex, Vector2(wx, y_bot - h * 0.34), Vector2(w * 1.05, h * 0.96), C_DAYLIGHT, 0.26 * daylight_gain)
					_draw_glow_quad(_soft_glow, _glow_tex, Vector2(wx, y_bot - 18.0), Vector2(w * 0.76, minf(h * 0.55, 240.0)), C_DAYLIGHT, 0.22 * daylight_gain)
					_draw_glow_quad(_soft_glow, _beam_tex, Vector2(wx, y_top + h * 0.48), Vector2(w * 0.82, h * 0.95), C_DAYLIGHT, 0.14 * daylight_gain, -0.10)
				else:
					_draw_glow_quad(_soft_glow, _glow_tex, Vector2(wx, y_bot - h * 0.28), Vector2(w * 1.15, h * 0.92), C_DAYLIGHT, 0.10 * daylight_gain)
				# 门洞两侧石柱内沿被昼光勾出柔边
				var pillar_y := (y_top + y_bot) * 0.5 + 24.0
				var pillar_w := clampf(hw * 0.72, 54.0, 150.0)
				_draw_glow_quad(_soft_glow, _glow_tex, Vector2(wx - hw * 0.96, pillar_y), Vector2(pillar_w, h * 0.95), C_DAYLIGHT, 0.12 * daylight_gain)
				_draw_glow_quad(_soft_glow, _glow_tex, Vector2(wx + hw * 0.96, pillar_y), Vector2(pillar_w, h * 0.95), C_DAYLIGHT, 0.12 * daylight_gain)

	if fog_enabled and hero_mist_gain > 0.001:
		var hero := _hero_world_pos()
		if hero != Vector2.INF:
			_draw_glow_quad(_soft_glow, _glow_tex, hero + Vector2(0.0, -18.0), Vector2(500.0, 560.0), C_HERO_MIST, hero_mist_gain * _hero_mist_k)


func _hero_world_pos() -> Vector2:
	if not actors.is_valid():
		return Vector2.INF
	var list: Variant = actors.call()
	if not (list is Array) or (list as Array).is_empty():
		return Vector2.INF
	var hero: Variant = (list as Array)[0]
	if hero is Node2D and is_instance_valid(hero):
		return (hero as Node2D).global_position
	return Vector2.INF


func _ensure_section_beads(s: Dictionary) -> Array:
	var key := int(roundf(float(s.center)))
	if _arch_beads.has(key):
		return _arch_beads[key]
	var list: Array = []
	var cx := float(s.center)
	var sec_idx := int(s.get("idx", 0))
	var arches := _section_arches(s.sec)
	for ai in arches.size():
		var a: Array = arches[ai]
		var wx := cx + float(a[0])
		var hw := float(a[1])
		var y_top := float(a[2])
		var y_bot := float(a[3])
		var h := y_bot - y_top
		if hw <= 8.0 or h <= 40.0:
			continue
		var y_spring := y_top + minf(h * 0.42, hw * 1.15)
		var rng := RandomNumberGenerator.new()
		rng.seed = 511 + sec_idx * 977 + ai * 131
		var step_back_min := clampf(hw * 0.14, 18.0, 26.0)
		var step_back_max := clampf(hw * 0.26, 30.0, 48.0)
		# 后排悬停白珠：沿雨线微斜成列挂在拱门昼光深处
		var bx := -hw * 0.90
		while bx < hw * 0.90:
			var by := rng.randf_range(y_top + 42.0, y_top + minf(150.0, h * 0.42))
			while by < y_bot - 6.0:
				var arch_hw := hw if by >= y_spring else hw * clampf((by - y_top) / maxf(y_spring - y_top, 1.0), 0.18, 1.0)
				var rx := bx - (by - (y_top + h * 0.55)) * 0.08
				if absf(rx) <= arch_hw * 0.88:
					var fall := 1.0 - clampf(Vector2(rx / maxf(hw, 1.0), (by - (y_bot - h * 0.24)) / maxf(h * 0.65, 1.0)).length(), 0.0, 1.0)
					if rng.randf() < 0.30 + fall:
						var rad := rng.randf_range(2.5, 3.9) if rng.randf() < 0.75 else rng.randf_range(4.8, 7.2)
						list.append({
							"anchor": wx, "hw": arch_hw * 0.90, "x": rx, "wx": wx + rx, "y": by, "y_land": y_bot - 6.0,
							"r": rad, "ph": rx * 0.02 + by * 0.012 + rng.randf() * 0.5, "sp": 0.7,
							"a": 0.25 + 0.75 * fall, "front": false, "state": 0, "dx": 0.0, "dy": 0.0, "sway": 0.0
						})
				by += rng.randf_range(46.0, 106.0)
			bx += rng.randf_range(step_back_min, step_back_max)
		# 前排可交互悬停白珠：挂在门洞口主角经过的路径上，触碰即轻柔坠落溅起小水圈，片刻后重新凝停
		var step_front_min := clampf(hw * 0.18, 22.0, 32.0)
		var step_front_max := clampf(hw * 0.32, 36.0, 58.0)
		var fx := -hw * 1.12
		while fx < hw * 1.12:
			var fy := rng.randf_range(y_top + 32.0, y_top + minf(145.0, h * 0.40))
			while fy < y_bot - 14.0:
				var arch_hw_f := hw if fy >= y_spring else hw * clampf((fy - y_top) / maxf(y_spring - y_top, 1.0), 0.22, 1.0)
				var rfx := fx - (fy - (y_top + h * 0.55)) * 0.08
				if absf(rfx) <= arch_hw_f * 1.12:
					var ef := 1.0 - clampf(Vector2(rfx / maxf(hw * 1.18, 1.0), (fy - (y_bot - h * 0.26)) / maxf(h * 0.70, 1.0)).length(), 0.0, 1.0)
					if rng.randf() < ef * 1.25:
						var rad_f := rng.randf_range(2.9, 4.5) if rng.randf() < 0.75 else rng.randf_range(5.2, 7.8)
						list.append({
							"anchor": wx, "hw": arch_hw_f * 1.12, "x": rfx, "wx": wx + rfx, "y": fy, "y_land": y_bot - 6.0,
							"r": rad_f, "ph": rfx * 0.02 + fy * 0.012 + rng.randf() * 0.5, "sp": 0.7,
							"a": 0.35 + 0.65 * ef, "front": true, "state": 0, "dx": 0.0, "dy": 0.0, "v": 0.0, "vx": 0.0, "t": 0.0, "sway": 0.0
						})
				fy += rng.randf_range(52.0, 116.0)
			fx += rng.randf_range(step_front_min, step_front_max)
	_arch_beads[key] = list
	return list


func _update_beads(delta: float) -> void:
	var secs := _near_sections()
	var cam_x := _center().x
	for k in _arch_beads.keys():
		if absf(float(k) - cam_x) > spacing * 2.2:
			_arch_beads.erase(k)
	var hero := _hero_world_pos()
	var hero_vx := 0.0
	if hero != Vector2.INF:
		if _prev_hero != Vector2.INF and delta > 0.0001 and absf(hero.x - _prev_hero.x) < 360.0:
			hero_vx = clampf((hero.x - _prev_hero.x) / delta, -900.0, 900.0)
		_prev_hero = hero
		# 计算主角所处位置的受光度（路灯暖光锥 + 门洞昼光），决定暗处冷雾衬底的显隐
		var lit := 0.0
		for lp in _lamps:
			var head: Vector2 = lp.p
			var w := 0.0
			if bool(lp.street) and hero.y > head.y:
				var cone := 50.0 + (hero.y - head.y) * 0.95
				w = clampf(1.0 - absf(head.x - hero.x) / cone, 0.0, 1.0)
			else:
				var reach := 300.0 if bool(lp.street) else 230.0
				w = clampf(1.0 - head.distance_to(hero) / reach, 0.0, 1.0)
			lit = maxf(lit, w)
		if daylight_enabled:
			for s in secs:
				var scx := float(s.center)
				for a in _section_arches(s.sec):
					var awx := scx + float(a[0])
					var ahw := float(a[1])
					var ayb := float(a[3])
					if absf(hero.y - (ayb - 80.0)) < 260.0:
						var aw := clampf(1.0 - maxf(absf(hero.x - awx) - ahw * 0.65, 0.0) / 220.0, 0.0, 1.0)
						lit = maxf(lit, aw)
		_hero_mist_k = lerpf(_hero_mist_k, 1.0 - lit * 0.82, clampf(delta * 6.0, 0.0, 1.0))

	if not daylight_enabled or not beads_enabled:
		return
	for s in secs:
		var list := _ensure_section_beads(s)
		for b in list:
			var bd: Dictionary = b
			if not bool(bd.front):
				continue
			var st := int(bd.state)
			if st == 0 and absf(float(bd.wx) - cam_x) > 1500.0 and absf(float(bd.sway)) < 0.01:
				continue
			bd.sway = move_toward(float(bd.sway), 0.0, delta * 16.0)
			match st:
				0:
					if hero != Vector2.INF:
						var dx := float(bd.wx) - hero.x
						var dy := float(bd.y) - hero.y
						if absf(dx) < 46.0 and absf(dy) < 100.0:
							bd.state = 1
							bd.v = 32.0
							var dir_s := 1.0 if dx >= 0.0 else -1.0
							bd.vx = clampf(hero_vx * 0.07 + dir_s * 14.0, -42.0, 42.0)
							bd.dx = 0.0
							bd.dy = 0.0
						elif absf(dx) < 78.0 and absf(dy) < 128.0:
							var dir_n := 1.0 if dx >= 0.0 else -1.0
							var push := (1.0 - absf(dx) / 78.0) * (hero_vx * 0.014 + dir_n * 5.0)
							bd.sway = clampf(float(bd.sway) + push * delta * 8.0, -10.0, 10.0)
				1:
					bd.v = float(bd.v) + 1900.0 * delta
					bd.dy = float(bd.dy) + float(bd.v) * delta
					bd.dx = float(bd.dx) + float(bd.vx) * delta
					if float(bd.y) + float(bd.dy) >= float(bd.y_land):
						bd.state = 2
						bd.t = 0.0
				2, 3, 4:
					bd.t = float(bd.t) + delta
					if st == 2 and float(bd.t) > 0.28:
						bd.state = 3
						bd.t = 0.0
					elif st == 3 and float(bd.t) > 2.2:
						bd.state = 4
						bd.t = 0.0
						bd.dx = 0.0
						bd.dy = 0.0
					elif st == 4 and float(bd.t) > 0.7:
						bd.state = 0


func _draw_beads(front: bool) -> void:
	if camera == null or not daylight_enabled or not beads_enabled or _bead_tex == null:
		return
	var ci: Node2D = _bead_front if front else _bead_back
	var cam_x := _center().x
	var view_l := _scr(Vector2(-120.0, 0.0)).x
	var view_r := _scr(Vector2(1400.0, 0.0)).x
	for s in _near_sections():
		var list := _ensure_section_beads(s)
		for b in list:
			var bd: Dictionary = b
			if bool(bd.front) != front:
				continue
			var anchor := float(bd.anchor)
			if anchor + 320.0 < view_l or anchor - 320.0 > view_r:
				continue
			var shift := 0.0 if front else clampf((cam_x - anchor) * 0.08, -float(bd.hw) * 0.22, float(bd.hw) * 0.22)
			var ph := float(bd.ph)
			var pulse := 0.84 + 0.16 * sin(_time * float(bd.sp) + ph)
			var hover_y := sin(_time * 1.35 + ph) * 1.4
			var pos := Vector2(float(bd.wx) + shift + float(bd.sway), float(bd.y) + hover_y)
			if pos.x < view_l or pos.x > view_r:
				continue
			var r := float(bd.r)
			var alpha := 0.95 * pulse * float(bd.a) * clampf(daylight_gain, 0.0, 1.6)
			var state := int(bd.state)
			if state == 1:      # 被主角碰落：化作细亮雨滴坠地
				var fall_pos := Vector2(pos.x + float(bd.dx), float(bd.y) + float(bd.dy))
				ci.draw_texture_rect(_bead_tex, Rect2(fall_pos.x - r * 0.35, fall_pos.y - r * 3.0, r * 0.7, r * 3.0), false, Color(0.90, 0.95, 1.0, 0.82))
				continue
			if state == 2:      # 落地溅开一圈小水纹
				var k := clampf(float(bd.t) / 0.28, 0.0, 1.0)
				ci.draw_set_transform(Vector2(pos.x + float(bd.dx), float(bd.y_land)), 0.0, Vector2(1.0, 0.30))
				ci.draw_arc(Vector2.ZERO, 3.0 + 13.0 * k, 0.0, TAU, 20, Color(1.0, 0.98, 0.92, 0.72 * (1.0 - k)), 1.5)
				ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				continue
			if state == 3:
				continue
			if state == 4:      # 重新在昼光里凝停浮现
				alpha *= clampf(float(bd.t) / 0.7, 0.0, 1.0)
			var c := Color(1.0, 0.98, 0.92, alpha)
			ci.draw_texture_rect(_bead_tex, Rect2(pos.x - r * 0.2, pos.y - r * 9.0, r * 0.4, r * 9.0), false, Color(c.r, c.g, c.b, alpha * 0.50))
			ci.draw_texture_rect(_bead_tex, Rect2(pos - Vector2(r, r) * 3.2, Vector2(r, r) * 6.4), false, Color(c.r, c.g, c.b, alpha * 0.065))
			ci.draw_texture_rect(_bead_tex, Rect2(pos - Vector2(r, r * 1.2), Vector2(r * 2.0, r * 2.4)), false, c)
