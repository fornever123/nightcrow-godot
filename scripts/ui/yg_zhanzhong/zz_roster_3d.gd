extends Control
## [YG-MARK] 《司辰母钟 · 四象异镜》V3 创意运镜与重构构图旗舰版
## 彻底告别“固定机位证件照转盘”与“直线傻推”——让镜头本身成为穿行于巨钟内部的电影摄影机：
## 1. 首页 → 选角【绕钟掠齿 + 剑针擦镜】：镜头不再直线穿洞，而是先压低广角沿巨钟右缘做 52° 立体绕弧贴近铸铁罗马数字厚边 → 巨型剑形分针实体扫过镜头作前景擦镜 → 掠过刀锋瞬间扎入巨钟内部！
## 2. 四姝【四套截然不同的电影机位 + 动态排版镜像重构】：
##    - 01 朔（夜鸦）：猎手低倾斜角（人居右、前景巨大铸铁齿轮掠过右下角制造纵深、左侧雕塑简报）
##    - 02 萤（惊风）：高空俯冲反构图！（镜头甩镜翻转，人跃居左侧 65%、高机位俯拍 +7.5° 滚转，UI 动态镜像切到右侧！）
##    - 03 薇（残火）：锻炉贴地超低仰拍！（镜头贴近地面 +14° 仰视，巨剑与上方罗马巨钟形成压迫感，左上方精炼简报！）
##    - 04 曜（破晓）：圣殿居中绝对对称！（镜头回正 0° 长焦居中，曜与背后流金母钟轴心完美重合如圣像祭坛，底部左右双翼对称神圣排版！）
## 3. 确认出战 → 选章【希区柯克变焦 + 仰镜追钟入塔】：镜头拉近同时急压长焦（背后巨钟产生骇人畸变逼近感）→ 1 帧瞬杀 + 双道紫芒剑弧 → 镜头上仰追随聚拢飞升的巨型铸铁钟，直砸第一章雨夜钟楼钟口！

const W := 1920.0
const H := 1080.0
const DEG := PI / 180.0
const INK := Color("#08070c")
const WHITE := Color("#f5f2eb")
const IMG := "res://assets/image/yg_zhanzhong/"

const HERO_SHADER := preload("res://scripts/ui/yg_zhanzhong/zz_hero_diorama.gdshader")
const AURA_SHADER := preload("res://scripts/ui/yg_zhanzhong/zz_cathedral_aura.gdshader")
const SLASH_SHADER := preload("res://scripts/ui/yg_zhanzhong/zz_slash_arc_3d.gdshader")

const ARENA_CENTER := Vector3(-10.0, 0.0, -4150.0)
const ORBIT_R := 1320.0

const T_ENTER_HOME := 0.86
const T_ENTER_SEL := 0.50
const T_LEAVE_HOME := 0.54
const T_CONFIRM := 0.52

# 四姝平权档案 + 各自独一无二的电影摄影机机位与排版形态！
# hud_mode: "left" (朔) | "right" (萤·镜像反构图!) | "low_left" (薇·贴地仰拍!) | "center" (曜·绝对对称圣坛!)
const DATA := [
	{
		"key": "shuo", "num": "01", "name": "朔", "epithet": "夜鸦", "word": "rs_shuo",
		"cutout": "hero3d_shuo", "face": "roster_shuo.jpg", "face_uv_y": 0.20, "playable": true,
		"weapon": "鸦黑直刃 · 紫晶裂口",
		"quote": "「影街的夜太长了，先把挡路的黑影斩干净。」",
		"tags": ["高速斩击", "精准弹刀", "裂口突进"],
		"stats": [0.95, 0.78, 0.92],
		"quad_h": 985.0, "x_off": 24.0, "y_off": -36.0,
		"hud_mode": "left",
		"cam_pos": Vector3(-310.0, -55.0, -820.0),
		"cam_look": Vector3(-200.0, 20.0, -2830.0),
		"cam_fov": 35.0, "cam_roll": -0.072,
		"dash_vec": Vector3(280.0, -70.0, 240.0),
		"accent": Color("#9d73ff"), "glow": Color("#6d38ff"), "rim": Color("#d8c4ff"),
		"pmode": 0,
	},
	{
		"key": "ying", "num": "02", "name": "萤", "epithet": "惊风", "word": "rs_ying",
		"cutout": "hero3d_ying", "face": "roster_ying.jpg", "face_uv_y": 0.22, "playable": false,
		"weapon": "断环双刃 · 锁链飞爪",
		"quote": "「风停了，但我还听见楼顶的瓦片在响。」",
		"tags": ["钩索空战", "残影连闪", "尚在光中"],
		"stats": [0.89, 0.66, 0.98],
		"quad_h": 1005.0, "x_off": -10.0, "y_off": -26.0,
		"hud_mode": "right",   # 反构图：镜头再右移留足右侧文字净空，萤跃居左半屏零兵器压字！
		"cam_pos": Vector3(465.0, 265.0, -940.0),
		"cam_look": Vector3(285.0, -35.0, -2830.0),
		"cam_fov": 41.0, "cam_roll": 0.088,
		"dash_vec": Vector3(-480.0, 120.0, 110.0),
		"accent": Color("#38ead8"), "glow": Color("#0e9c92"), "rim": Color("#b3fff7"),
		"pmode": 1,
	},
	{
		"key": "wei", "num": "03", "name": "薇", "epithet": "残火", "word": "rs_wei",
		"cutout": "hero3d_wei", "face": "roster_wei.jpg", "face_uv_y": 0.20, "playable": false,
		"weapon": "缺口黑铁巨剑 · 烈红残披",
		"quote": "「管它是什么鬼东西，一剑劈成两半再说。」",
		"tags": ["重剑蓄力", "霸体硬拼", "尚在光中"],
		"stats": [0.64, 0.99, 0.60],
		"quad_h": 945.0, "x_off": 48.0, "y_off": 24.0,
		"hud_mode": "low_left", # 贴地超低广角仰拍：红披风下摆与左下铭牌槽彻底拉开留白！
		"cam_pos": Vector3(-385.0, -310.0, -1040.0),
		"cam_look": Vector3(-200.0, 95.0, -2830.0),
		"cam_fov": 43.0, "cam_roll": -0.052,
		"dash_vec": Vector3(-80.0, 340.0, 140.0),
		"accent": Color("#ff5e4d"), "glow": Color("#c41e30"), "rim": Color("#ffc6bc"),
		"pmode": 2,
	},
	{
		"key": "yao", "num": "04", "name": "曜", "epithet": "破晓", "word": "rs_yao",
		"cutout": "hero3d_yao", "face": "roster_yao.jpg", "face_uv_y": 0.18, "playable": false,
		"weapon": "圣光十字大剑 · 圣银战铠",
		"quote": "「白昼已近，所有迷途者皆应归位。」",
		"tags": ["圣剑裁决", "光盾格挡", "尚在光中"],
		"stats": [0.84, 0.91, 0.76],
		"quad_h": 1065.0, "x_off": 0.0, "y_off": -12.0,
		"hud_mode": "center",  # 绝对对称圣坛：长焦正中，曜与背后流金母钟轴心重合，左右双翼神圣排版！
		"cam_pos": Vector3(-10.0, -40.0, -680.0),
		"cam_look": Vector3(-10.0, 28.0, -2830.0),
		"cam_fov": 29.0, "cam_roll": 0.0,
		"dash_vec": Vector3(0.0, 260.0, -140.0),
		"accent": Color("#ffd863"), "glow": Color("#c98614"), "rim": Color("#fff3c4"),
		"pmode": 3,
	},
]
const STAT_NAMES := ["斩速", "破势", "机动"]

var T: Node = null
var clock: Node3D = null
var idx: int = 0
var state: String = "hidden"
var now: float = 0.0
var t_state: float = -10.0

# 三维弹簧与平滑摄影机轨
var orbit_ang: float = 0.0
var orbit_goal: float = 0.0
var orbit_vel: float = 0.0
var bank_roll: float = 0.0
var bank_vel: float = 0.0
var fov_kick: float = 0.0
var fov_vel: float = 0.0
var ring_kick_ang: float = 0.0
var ring_kick_vel: float = 0.0

# 机位当前插值状态（四姝之间真实三维轨道飞行，绝不瞬切！）
var cam_pos_cur: Vector3 = Vector3(-310.0, -55.0, -820.0)
var cam_look_cur: Vector3 = Vector3(-200.0, 20.0, -2830.0)
var cam_fov_cur: float = 35.0
var cam_roll_cur: float = -0.072

var stat_vals: Array = [0.95, 0.78, 0.92]
var stat_vels: Array = [0.0, 0.0, 0.0]

var chroma_pulse: float = 0.0
var blur_pulse: float = 0.0
var impact_pulse: float = 0.0
var letterbox_cur: float = 0.0

var switch_t: float = -10.0
var switch_dir: int = 1
var lock_shake: float = 0.0
var hover_cta: bool = false
var hover_node: int = -1
var cta_k: float = 0.0
var pointer: Vector2 = Vector2.ZERO
var ui_alpha: float = 0.0

var home_xf: Transform3D = Transform3D.IDENTITY
var from_sel_xf: Transform3D = Transform3D.IDENTITY
var last_cam_xf: Transform3D = Transform3D.IDENTITY
var confirm_cb: Callable = Callable()
var confirm_fired: bool = false
var leave_cb: Callable = Callable()
var enter_sfx_fired: bool = false
var cam_st: Dictionary = {}
var cine_st: Dictionary = {}

# 三维节点
var cathedral_root: Node3D
var backdrop_mi: MeshInstance3D
var sanctum_clock: Node3D
var sc_parts: Dictionary = {}
var fg_gear_mi: MeshInstance3D       # 近景巨型旋转铸铁齿轮（贴近镜头边缘制造真前景遮挡纵深！）
var fg_gear_m: ShaderMaterial
var wipe_hand_piv: Node3D            # 擦镜实体剑形分针（首页绕钟转场 + 切角瞬间扫过镜头！）
var wipe_hand_mi: MeshInstance3D
var wipe_hand_m: ShaderMaterial
var armillary_rings: Array = []
var colonnade_root: Node3D
var colonnade_slits: Array = []
var floor_astrolabe: Node3D
var floor_rings: Array = []
var carousel: Node3D
var slots: Array = []
var particles_mmi: MultiMeshInstance3D
var particles_mat: ShaderMaterial
var particles_data: Array = []

# 四姝专属三维特效节点
var slash_pivot: Node3D
var slash_mi: MeshInstance3D
var slash_mat: ShaderMaterial
var slash2_mi: MeshInstance3D
var slash2_mat: ShaderMaterial
var vortex_mi: MeshInstance3D
var vortex_mat: ShaderMaterial
var shockwave_mi: MeshInstance3D
var shockwave_mat: ShaderMaterial
var yao_pillars: Array = []

# 二维悬浮 HUD
var overlay: Control
var _tex_cache: Dictionary = {}
var _cta_rect: Rect2 = Rect2(94, 650, 360, 74)
var _card_rects: Array = [Rect2(), Rect2(), Rect2(), Rect2()]


# ================================================================ 搭建
func setup(title: Node) -> void:
	T = title
	clock = T.clock
	size = Vector2(W, H)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_3d()
	_build_2d()
	visible = false
	cathedral_root.visible = false


func _exit_tree() -> void:
	_tex_cache.clear()


func _load_tex(file_name: String) -> Texture2D:
	if not _tex_cache.has(file_name):
		var path := IMG + (file_name if file_name.contains(".") else (file_name + ".png"))
		_tex_cache[file_name] = load(path)
	return _tex_cache[file_name] as Texture2D


func _build_3d() -> void:
	cathedral_root = Node3D.new()
	cathedral_root.name = "Roster3DCathedral"
	cathedral_root.visible = false
	T.add_child(cathedral_root)

	var dial_t: Texture2D = clock.tex("dial")
	var gear_t: Texture2D = clock.tex("gear_main")
	var esc_t: Texture2D = clock.tex("gear_escape")
	var h_hour_t: Texture2D = clock.tex("hand_hour")
	var h_min_t: Texture2D = clock.tex("hand_minute")
	var ros_t: Texture2D = clock.tex("rosette")
	var ring_t: Texture2D = clock.circle_tex(0.968, 1.0, 512)
	var ring_thin_t: Texture2D = clock.circle_tex(0.986, 1.0, 512)

	# 1. 深渊鸦墨天幕
	var bg_q := QuadMesh.new()
	bg_q.size = Vector2(26000.0, 16000.0)
	var bg_m: ShaderMaterial = clock.flat_mat(null, Color("#040409"), 1.0)
	bg_m.render_priority = -9
	backdrop_mi = MeshInstance3D.new()
	backdrop_mi.mesh = bg_q
	backdrop_mi.material_override = bg_m
	backdrop_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	backdrop_mi.extra_cull_margin = 16384.0
	backdrop_mi.position = ARENA_CENTER + Vector3(0.0, 0.0, -3900.0)
	cathedral_root.add_child(backdrop_mi)

	# 2. 【核心意象常驻】殿堂巨型三维哥特铸铁母钟
	sanctum_clock = Node3D.new()
	sanctum_clock.position = ARENA_CENTER + Vector3(0.0, 60.0, -980.0)
	cathedral_root.add_child(sanctum_clock)

	var sc_dial_q := QuadMesh.new()
	sc_dial_q.size = Vector2(3800.0, 3800.0)
	var sc_dial_m: ShaderMaterial = clock.flat_mat(dial_t, Color("#767a8a"), 0.56)
	sc_dial_m.render_priority = -7
	var sc_dial := MeshInstance3D.new()
	sc_dial.mesh = sc_dial_q
	sc_dial.material_override = sc_dial_m
	sc_dial.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sc_dial.extra_cull_margin = 16384.0
	sanctum_clock.add_child(sc_dial)

	var sc_rim_q := QuadMesh.new()
	sc_rim_q.size = Vector2(3540.0, 3540.0)
	var sc_rim_m: ShaderMaterial = clock.add_mat(dial_t, WHITE, 0.25)
	sc_rim_m.render_priority = -6
	var sc_rim := MeshInstance3D.new()
	sc_rim.mesh = sc_rim_q
	sc_rim.material_override = sc_rim_m
	sc_rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sc_rim.extra_cull_margin = 16384.0
	sc_rim.position.z = 22.0
	sanctum_clock.add_child(sc_rim)

	var sc_gm_q := QuadMesh.new()
	sc_gm_q.size = Vector2(1900.0, 1900.0)
	var sc_gm_m: ShaderMaterial = clock.flat_mat(gear_t, Color("#606478"), 0.50)
	sc_gm_m.render_priority = -7
	var sc_gm := MeshInstance3D.new()
	sc_gm.mesh = sc_gm_q
	sc_gm.material_override = sc_gm_m
	sc_gm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sc_gm.position = Vector3(-440.0, 270.0, 65.0)
	sanctum_clock.add_child(sc_gm)

	var sc_ge_q := QuadMesh.new()
	sc_ge_q.size = Vector2(1460.0, 1460.0)
	var sc_ge_m: ShaderMaterial = clock.add_mat(esc_t, WHITE, 0.24)
	sc_ge_m.render_priority = -6
	var sc_ge := MeshInstance3D.new()
	sc_ge.mesh = sc_ge_q
	sc_ge.material_override = sc_ge_m
	sc_ge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sc_ge.position = Vector3(380.0, -240.0, 90.0)
	sanctum_clock.add_child(sc_ge)

	var sh_piv := Node3D.new()
	sh_piv.position.z = 140.0
	sanctum_clock.add_child(sh_piv)
	var sh_q := QuadMesh.new()
	sh_q.size = Vector2(1800.0, 470.0)
	sh_q.center_offset = Vector3(810.0, 0.0, 0.0)
	var sh_m: ShaderMaterial = clock.flat_mat(h_hour_t, Color("#c8cad4"), 0.58)
	sh_m.render_priority = -6
	var sh_mi := MeshInstance3D.new()
	sh_mi.mesh = sh_q
	sh_mi.material_override = sh_m
	sh_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sh_piv.add_child(sh_mi)

	var sm_piv := Node3D.new()
	sm_piv.position.z = 165.0
	sanctum_clock.add_child(sm_piv)
	var sm_q := QuadMesh.new()
	sm_q.size = Vector2(2220.0, 286.0)
	sm_q.center_offset = Vector3(990.0, 0.0, 0.0)
	var sm_m: ShaderMaterial = clock.add_mat(h_min_t, WHITE, 0.46)
	sm_m.render_priority = -5
	var sm_mi := MeshInstance3D.new()
	sm_mi.mesh = sm_q
	sm_mi.material_override = sm_m
	sm_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sm_piv.add_child(sm_mi)

	var sc_ros_q := QuadMesh.new()
	sc_ros_q.size = Vector2(640.0, 640.0)
	var sc_ros_m: ShaderMaterial = clock.add_mat(ros_t, WHITE, 0.36)
	sc_ros_m.render_priority = -5
	var sc_ros := MeshInstance3D.new()
	sc_ros.mesh = sc_ros_q
	sc_ros.material_override = sc_ros_m
	sc_ros.position.z = 185.0
	sanctum_clock.add_child(sc_ros)

	sc_parts = {
		"dial": sc_dial, "dial_m": sc_dial_m, "rim": sc_rim, "rim_m": sc_rim_m,
		"gm": sc_gm, "gm_m": sc_gm_m, "ge": sc_ge, "ge_m": sc_ge_m,
		"hour": sh_piv, "hour_m": sh_m, "min": sm_piv, "min_m": sm_m,
		"ros": sc_ros, "ros_m": sc_ros_m,
	}

	# 2b. 【电影前景纵深道具】近景暗铸铁巨齿（位于镜头近处边角缓缓咬合，一动镜头就产生炸裂的前景视差！）
	var fg_q := QuadMesh.new()
	fg_q.size = Vector2(920.0, 920.0)
	fg_gear_m = clock.flat_mat(gear_t, Color("#14151e"), 0.72)
	fg_gear_m.render_priority = 4
	fg_gear_mi = MeshInstance3D.new()
	fg_gear_mi.mesh = fg_q
	fg_gear_mi.material_override = fg_gear_m
	fg_gear_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fg_gear_mi.extra_cull_margin = 16384.0
	cathedral_root.add_child(fg_gear_mi)

	# 2c. 【前景物理擦镜】巨型黑银剑形指针（绕钟进场与切角换镜瞬间实体横扫镜头前方！）
	wipe_hand_piv = Node3D.new()
	cathedral_root.add_child(wipe_hand_piv)
	var wh_q := QuadMesh.new()
	wh_q.size = Vector2(1850.0, 320.0)
	wh_q.center_offset = Vector3(520.0, 0.0, 0.0)
	wipe_hand_m = clock.flat_mat(h_min_t, Color("#151620"), 0.0)
	wipe_hand_m.render_priority = 6
	wipe_hand_mi = MeshInstance3D.new()
	wipe_hand_mi.mesh = wh_q
	wipe_hand_mi.material_override = wipe_hand_m
	wipe_hand_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wipe_hand_mi.extra_cull_margin = 16384.0
	wipe_hand_piv.add_child(wipe_hand_mi)

	# 3. 八根远景黑曜石哥特柱廊（外推拉开深邃纵深，绝不切出贴脸硬黑竖条！）
	colonnade_root = Node3D.new()
	colonnade_root.position = ARENA_CENTER
	cathedral_root.add_child(colonnade_root)
	var col_r := 3420.0
	var pil_mesh := BoxMesh.new()
	pil_mesh.size = Vector3(190.0, 3600.0, 190.0)
	var pil_mat: ShaderMaterial = clock.flat_mat(null, Color("#0a0b12"), 0.44)
	pil_mat.render_priority = -5
	for ci in 8:
		var cang := float(ci) * TAU / 8.0 + PI / 8.0
		var pnode := Node3D.new()
		pnode.position = Vector3(sin(cang) * col_r, 0.0, cos(cang) * col_r)
		pnode.rotation.y = cang
		colonnade_root.add_child(pnode)
		var pmi := MeshInstance3D.new()
		pmi.mesh = pil_mesh
		pmi.material_override = pil_mat
		pmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pnode.add_child(pmi)
		var slit_q := QuadMesh.new()
		slit_q.size = Vector2(9.0, 3100.0)
		var slit_m: ShaderMaterial = clock.add_mat(null, WHITE, 0.42)
		slit_m.render_priority = -4
		var smi := MeshInstance3D.new()
		smi.mesh = slit_q
		smi.material_override = slit_m
		smi.position = Vector3(0.0, 0.0, -108.0)
		pnode.add_child(smi)
		colonnade_slits.append(slit_m)

	# 4. 三重立体倾斜浑天仪钟环
	var arm_specs := [
		{"sz": 4200.0, "rot": Vector3(68.0 * DEG, 14.0 * DEG, 0.0), "sp": 0.12, "op": 0.36, "tex": dial_t},
		{"sz": 3560.0, "rot": Vector3(-72.0 * DEG, -22.0 * DEG, 0.0), "sp": -0.18, "op": 0.46, "tex": ring_thin_t},
		{"sz": 3080.0, "rot": Vector3(24.0 * DEG, -30.0 * DEG, 0.0), "sp": 0.22, "op": 0.30, "tex": ring_t},
	]
	for asp in arm_specs:
		var piv := Node3D.new()
		piv.position = ARENA_CENTER + Vector3(0.0, -20.0, 0.0)
		piv.rotation = asp["rot"]
		cathedral_root.add_child(piv)
		var aq := QuadMesh.new()
		var asz: float = float(asp["sz"])
		aq.size = Vector2(asz, asz)
		var am: ShaderMaterial = clock.add_mat(asp["tex"] as Texture2D, WHITE, float(asp["op"]))
		am.render_priority = -4
		var ami := MeshInstance3D.new()
		ami.mesh = aq
		ami.material_override = am
		ami.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ami.extra_cull_margin = 16384.0
		piv.add_child(ami)
		armillary_rings.append({"piv": piv, "mi": ami, "m": am, "sp": float(asp["sp"]), "base_op": float(asp["op"]), "rot0": asp["rot"]})

	# 5. 地面巨型三维司辰星盘阵
	floor_astrolabe = Node3D.new()
	floor_astrolabe.position = ARENA_CENTER + Vector3(0.0, -565.0, 0.0)
	floor_astrolabe.rotation = Vector3(-79.0 * DEG, 0.0, 0.0)
	cathedral_root.add_child(floor_astrolabe)
	for fs in [
		{"tex": dial_t, "sz": 5600.0, "z": -60.0, "sp": 0.06, "op": 0.24, "add": false},
		{"tex": ring_t, "sz": 4200.0, "z": 0.0, "sp": -0.11, "op": 0.45, "add": true},
		{"tex": gear_t, "sz": 3100.0, "z": 35.0, "sp": 0.14, "op": 0.24, "add": true},
		{"tex": ring_thin_t, "sz": 2740.0, "z": 58.0, "sp": -0.22, "op": 0.65, "add": true},
	]:
		var q := QuadMesh.new()
		var s: float = float(fs["sz"])
		q.size = Vector2(s, s)
		var m: ShaderMaterial = clock.add_mat(fs["tex"] as Texture2D, WHITE, float(fs["op"])) if bool(fs["add"]) else clock.flat_mat(fs["tex"] as Texture2D, Color("#787c8c"), float(fs["op"]))
		m.render_priority = -6
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 16384.0
		mi.position.z = float(fs["z"])
		floor_astrolabe.add_child(mi)
		floor_rings.append({"mi": mi, "m": m, "sp": float(fs["sp"]), "base_op": float(fs["op"]), "add": bool(fs["add"]), "z0": float(fs["z"])})

	# 6. 四象三维轨道转盘（带 3 重高速残影）
	carousel = Node3D.new()
	carousel.position = ARENA_CENTER
	cathedral_root.add_child(carousel)

	for i in DATA.size():
		var d: Dictionary = DATA[i]
		var ang: float = float(i) * PI * 0.5
		var slot := Node3D.new()
		slot.position = Vector3(sin(ang) * ORBIT_R, 0.0, cos(ang) * ORBIT_R)
		carousel.add_child(slot)

		var acc: Color = d["accent"]

		var aura_q := QuadMesh.new()
		aura_q.size = Vector2(1820.0, 1820.0)
		var aura_m := ShaderMaterial.new()
		aura_m.shader = AURA_SHADER
		aura_m.render_priority = -3
		aura_m.set_shader_parameter("accent_col", acc)
		var aura_mi := MeshInstance3D.new()
		aura_mi.mesh = aura_q
		aura_mi.material_override = aura_m
		aura_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		aura_mi.extra_cull_margin = 16384.0
		aura_mi.position = Vector3(0.0, 40.0, -450.0)
		slot.add_child(aura_mi)

		var wt: Texture2D = _load_tex(String(d["word"]))
		var wasp: float = float(wt.get_width()) / maxf(1.0, float(wt.get_height()))
		var kh := 740.0
		var kanji_q := QuadMesh.new()
		kanji_q.size = Vector2(kh * wasp, kh)
		var kanji_m: ShaderMaterial = clock.add_mat(wt, acc.lerp(WHITE, 0.2), 0.14)
		kanji_m.render_priority = -2
		var kanji_mi := MeshInstance3D.new()
		kanji_mi.mesh = kanji_q
		kanji_mi.material_override = kanji_m
		kanji_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		kanji_mi.extra_cull_margin = 16384.0
		kanji_mi.position = Vector3(-160.0 if i != 1 else 160.0, 130.0, -310.0)
		slot.add_child(kanji_mi)

		var halo_q := QuadMesh.new()
		halo_q.size = Vector2(1240.0, 1240.0)
		var halo_m: ShaderMaterial = clock.add_mat(ring_thin_t, acc.lerp(WHITE, 0.25), 0.56)
		halo_m.render_priority = -1
		var halo_mi := MeshInstance3D.new()
		halo_mi.mesh = halo_q
		halo_mi.material_override = halo_m
		halo_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		halo_mi.extra_cull_margin = 16384.0
		halo_mi.position = Vector3(0.0, 20.0, -95.0)
		halo_mi.rotation = Vector3(16.0 * DEG, -18.0 * DEG, 0.0)
		slot.add_child(halo_mi)

		var ct: Texture2D = _load_tex(String(d["cutout"]))
		var casp: float = float(ct.get_width()) / maxf(1.0, float(ct.get_height()))
		var qh: float = float(d["quad_h"])
		var hero_q := QuadMesh.new()
		hero_q.size = Vector2(qh * casp, qh)
		hero_q.subdivide_width = 12
		hero_q.subdivide_depth = 16

		var ghosts: Array = []
		for gi in 3:
			var gm: ShaderMaterial = clock.add_mat(ct, acc.lerp(WHITE, 0.22 * float(gi)), 0.0)
			gm.render_priority = 1
			var gmi := MeshInstance3D.new()
			gmi.mesh = hero_q
			gmi.material_override = gm
			gmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			gmi.extra_cull_margin = 16384.0
			gmi.visible = false
			slot.add_child(gmi)
			ghosts.append({"mi": gmi, "m": gm})

		var hero_m := ShaderMaterial.new()
		hero_m.shader = HERO_SHADER
		hero_m.render_priority = 2 if i == 0 else 1
		hero_m.set_shader_parameter("albedo_tex", ct)
		hero_m.set_shader_parameter("accent_col", acc)
		hero_m.set_shader_parameter("focus_k", 1.0 if i == 0 else 0.0)
		hero_m.set_shader_parameter("locked_k", 0.0 if bool(d["playable"]) else 1.0)
		hero_m.set_shader_parameter("opacity", 1.0)
		var hero_mi := MeshInstance3D.new()
		hero_mi.mesh = hero_q
		hero_mi.material_override = hero_m
		hero_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		hero_mi.extra_cull_margin = 16384.0
		hero_mi.position = Vector3(float(d["x_off"]), float(d["y_off"]), 0.0)
		slot.add_child(hero_mi)

		slots.append({
			"idx": i, "ang": ang, "slot": slot,
			"aura_mi": aura_mi, "aura_m": aura_m,
			"kanji_mi": kanji_mi, "kanji_m": kanji_m,
			"halo_mi": halo_mi, "halo_m": halo_m,
			"ghosts": ghosts,
			"hero_mi": hero_mi, "hero_m": hero_m,
			"x0": float(d["x_off"]), "y0": float(d["y_off"]),
			"focus": 1.0 if i == 0 else 0.0,
			"flash": 0.0, "glint": -1.5,
			"accent": acc,
		})

	# 7. 四姝专属三维粒子生态
	var pq := QuadMesh.new()
	pq.size = Vector2(1.0, 1.0)
	var pmm := MultiMesh.new()
	pmm.transform_format = MultiMesh.TRANSFORM_3D
	pmm.mesh = pq
	pmm.instance_count = 200
	particles_mmi = MultiMeshInstance3D.new()
	particles_mmi.multimesh = pmm
	particles_mat = clock.add_mat(null, WHITE, 0.86)
	particles_mat.render_priority = 3
	particles_mmi.material_override = particles_mat
	particles_mmi.custom_aabb = AABB(Vector3(-1e5, -1e5, -1e5), Vector3(2e5, 2e5, 2e5))
	cathedral_root.add_child(particles_mmi)

	var rng := RandomNumberGenerator.new()
	rng.seed = 20261119
	for pi in pmm.instance_count:
		particles_data.append({
			"x": rng.randf_range(-1750.0, 1850.0),
			"y": rng.randf_range(-720.0, 760.0),
			"z": rng.randf_range(-3450.0, -1350.0),
			"sp": rng.randf_range(0.55, 1.50),
			"ph": rng.randf_range(0.0, TAU),
			"sz": rng.randf_range(5.0, 16.0),
			"len": rng.randf_range(2.2, 7.2),
		})

	# 8. 四姝专属三维登场特效集
	slash_pivot = Node3D.new()
	cathedral_root.add_child(slash_pivot)
	var ribbon_mesh := _make_slash_ribbon(1180.0, 290.0, 40)
	slash_mat = ShaderMaterial.new()
	slash_mat.shader = SLASH_SHADER
	slash_mat.render_priority = 5
	slash_mi = MeshInstance3D.new()
	slash_mi.mesh = ribbon_mesh
	slash_mi.material_override = slash_mat
	slash_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	slash_mi.extra_cull_margin = 16384.0
	slash_pivot.add_child(slash_mi)

	slash2_mat = ShaderMaterial.new()
	slash2_mat.shader = SLASH_SHADER
	slash2_mat.render_priority = 5
	slash2_mi = MeshInstance3D.new()
	slash2_mi.mesh = ribbon_mesh
	slash2_mi.material_override = slash2_mat
	slash2_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	slash2_mi.extra_cull_margin = 16384.0
	slash2_mi.rotation = Vector3(0.0, 0.0, 58.0 * DEG)
	slash_pivot.add_child(slash2_mi)

	var vq := QuadMesh.new()
	vq.size = Vector2(2400.0, 2400.0)
	vortex_mat = clock.add_mat(ring_t, Color("#38ead8"), 0.0)
	vortex_mat.render_priority = 4
	vortex_mi = MeshInstance3D.new()
	vortex_mi.mesh = vq
	vortex_mi.material_override = vortex_mat
	vortex_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	vortex_mi.position = ARENA_CENTER + Vector3(0.0, -40.0, ORBIT_R)
	vortex_mi.rotation = Vector3(-76.0 * DEG, 12.0 * DEG, 0.0)
	cathedral_root.add_child(vortex_mi)

	var sq := QuadMesh.new()
	sq.size = Vector2(2800.0, 2800.0)
	shockwave_mat = clock.add_mat(ring_t, Color("#ff5e4d"), 0.0)
	shockwave_mat.render_priority = 4
	shockwave_mi = MeshInstance3D.new()
	shockwave_mi.mesh = sq
	shockwave_mi.material_override = shockwave_mat
	shockwave_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shockwave_mi.position = ARENA_CENTER + Vector3(0.0, -490.0, ORBIT_R)
	shockwave_mi.rotation = Vector3(-82.0 * DEG, 0.0, 0.0)
	cathedral_root.add_child(shockwave_mi)

	for yp in [Vector3(-280.0, 220.0, ORBIT_R - 140.0), Vector3(0.0, 220.0, ORBIT_R - 60.0), Vector3(280.0, 220.0, ORBIT_R - 180.0)]:
		var pqy := QuadMesh.new()
		pqy.size = Vector2(210.0, 2600.0)
		var pmy: ShaderMaterial = clock.add_mat(null, Color("#ffe38a"), 0.0)
		pmy.render_priority = 4
		var pmiy := MeshInstance3D.new()
		pmiy.mesh = pqy
		pmiy.material_override = pmy
		pmiy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pmiy.position = ARENA_CENTER + (yp as Vector3)
		cathedral_root.add_child(pmiy)
		yao_pillars.append({"mi": pmiy, "m": pmy})


func _make_slash_ribbon(radius: float, width: float, segs: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var a0 := -1.32
	var a1 := 1.32
	for i in segs:
		var u0 := float(i) / float(segs)
		var u1 := float(i + 1) / float(segs)
		var ang0 := lerpf(a0, a1, u0)
		var ang1 := lerpf(a0, a1, u1)
		var r_in := radius - width * 0.5
		var r_out := radius + width * 0.5
		var p00 := Vector3(sin(ang0) * r_in, -width * 0.55, cos(ang0) * r_in - radius)
		var p01 := Vector3(sin(ang0) * r_out, width * 0.55, cos(ang0) * r_out - radius)
		var p10 := Vector3(sin(ang1) * r_in, -width * 0.55, cos(ang1) * r_in - radius)
		var p11 := Vector3(sin(ang1) * r_out, width * 0.55, cos(ang1) * r_out - radius)
		st.set_uv(Vector2(u0, 0.0)); st.add_vertex(p00)
		st.set_uv(Vector2(u0, 1.0)); st.add_vertex(p01)
		st.set_uv(Vector2(u1, 1.0)); st.add_vertex(p11)
		st.set_uv(Vector2(u0, 0.0)); st.add_vertex(p00)
		st.set_uv(Vector2(u1, 1.0)); st.add_vertex(p11)
		st.set_uv(Vector2(u1, 0.0)); st.add_vertex(p10)
	return st.commit()


func _build_2d() -> void:
	overlay = Control.new()
	overlay.size = Vector2(W, H)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.draw.connect(_draw_hud)
	add_child(overlay)


# ================================================================ 对外接口
func current_key() -> String:
	return String(DATA[idx]["key"])


func is_playable() -> bool:
	return bool(DATA[idx]["playable"])


func clock_state() -> Dictionary:
	return cam_st


func cine_state() -> Dictionary:
	return cine_st


func enter(hero_key: String) -> void:
	idx = _index_of(hero_key)
	state = "enter_home"
	t_state = now
	enter_sfx_fired = false
	confirm_fired = false
	home_xf = (clock.camera as Camera3D).global_transform
	orbit_goal = -float(idx) * PI * 0.5
	orbit_ang = orbit_goal + 0.52
	orbit_vel = -2.1
	bank_roll = -0.11
	bank_vel = 0.0
	fov_kick = 0.0
	fov_vel = 0.0
	ring_kick_vel = 4.2
	cam_pos_cur = DATA[idx]["cam_pos"]
	cam_look_cur = DATA[idx]["cam_look"]
	cam_fov_cur = float(DATA[idx]["cam_fov"])
	cam_roll_cur = float(DATA[idx]["cam_roll"])
	var st_arr: Array = DATA[idx]["stats"]
	for k in 3:
		stat_vals[k] = 0.0
		stat_vels[k] = float(st_arr[k]) * 5.2
	switch_t = now + 0.30
	switch_dir = 1
	_trigger_slot_glint(idx, 0.9)
	visible = true
	cathedral_root.visible = true
	if T != null and T.has_method("_apply_hero"):
		T._apply_hero(current_key(), false)


func enter_from_select(hero_key: String, start_xf: Transform3D) -> void:
	idx = _index_of(hero_key)
	state = "enter_select"
	t_state = now
	from_sel_xf = start_xf
	orbit_goal = -float(idx) * PI * 0.5
	orbit_ang = orbit_goal - 0.30
	orbit_vel = 1.6
	bank_roll = 0.08
	bank_vel = 0.0
	fov_kick = 14.0
	fov_vel = -28.0
	ring_kick_vel = -2.6
	cam_pos_cur = DATA[idx]["cam_pos"]
	cam_look_cur = DATA[idx]["cam_look"]
	cam_fov_cur = float(DATA[idx]["cam_fov"])
	cam_roll_cur = float(DATA[idx]["cam_roll"])
	chroma_pulse = 0.014
	blur_pulse = 0.022
	switch_t = now + 0.14
	switch_dir = -1
	_trigger_slot_glint(idx, 0.8)
	visible = true
	cathedral_root.visible = true
	if T != null and T.has_method("_apply_hero"):
		T._apply_hero(current_key(), false)


func leave() -> void:
	leave_to_home(Callable())


func leave_to_home(on_done: Callable) -> void:
	if state == "hidden":
		if on_done.is_valid():
			on_done.call()
		return
	leave_cb = on_done
	state = "leave_home"
	t_state = now
	last_cam_xf = (clock.camera as Camera3D).global_transform
	blur_pulse = 0.024
	if T != null and T.has_method("_play"):
		T._play("h3_unsheathe" if T.sfx.has("h3_unsheathe") else "ult_push", -4.5, 1.06)


func confirm_to_select(on_handoff: Callable) -> void:
	if state != "shown" and state != "enter_home" and state != "enter_select":
		return
	confirm_cb = on_handoff
	confirm_fired = false
	state = "confirm"
	t_state = now
	enter_sfx_fired = false
	_trigger_slot_glint(idx, 1.0)
	chroma_pulse = 0.014
	if T != null:
		if T.has_method("_play"):
			T._play("h3_parry_lock" if T.sfx.has("h3_parry_lock") else "ui_move", -2.5, 1.04)
		T.hitstop = 0.045
		if T.has_method("_hit"):
			T._hit(13.0, 0.014, 0.30)


func select_index(new_idx: int) -> void:
	var n := DATA.size()
	var target := posmod(new_idx, n)
	if target == idx:
		return
	var diff := wrapi(target - idx, -2, 2)
	if diff == 0:
		diff = 1
	idx = target
	switch_dir = 1 if diff > 0 else -1
	switch_t = now
	orbit_goal -= float(diff) * PI * 0.5
	orbit_vel -= float(diff) * 3.1
	bank_vel += float(switch_dir) * 2.1
	fov_vel += 112.0
	ring_kick_vel += float(switch_dir) * 5.2

	for k in 3:
		stat_vals[k] = float(stat_vals[k]) * 0.22
		stat_vels[k] = 3.5
	chroma_pulse = 0.016 if idx == 2 else 0.012
	blur_pulse = 0.026
	impact_pulse = 0.68
	_trigger_slot_glint(idx, 1.0)

	if T != null:
		if T.has_method("_apply_hero"):
			T._apply_hero(current_key(), false)
		if T.has_method("_play"):
			if idx == 2:
				T._play("h3_anvil_bell" if T.sfx.has("h3_anvil_bell") else "ult_impact", -4.5, 0.86)
			elif idx == 3:
				T._play("h3_parry_lock" if T.sfx.has("h3_parry_lock") else "ui_move", -4.0, 1.24)
			else:
				T._play("h3_slash_fast" if T.sfx.has("h3_slash_fast") else "ui_move", -4.5, 1.02 + float(idx) * 0.06)
		if T.has_method("_clack"):
			T._clack(1.20 - float(idx) * 0.06, -9.0)
		if T.has_method("_hit"):
			T._hit(16.0 if idx == 2 else 9.5, 0.014 if idx == 2 else 0.009, 0.26 if idx == 2 else 0.16)


func bump_locked() -> void:
	lock_shake = 1.0
	fov_vel -= 42.0
	chroma_pulse = 0.012
	var sl: Dictionary = slots[idx]
	sl["flash"] = 0.65


func _index_of(k: String) -> int:
	for i in DATA.size():
		if String(DATA[i]["key"]) == k:
			return i
	return 0


func _trigger_slot_glint(i: int, flash_amt: float = 0.65) -> void:
	var sl: Dictionary = slots[i]
	sl["glint"] = -0.35
	sl["flash"] = maxf(float(sl["flash"]), flash_amt)


# ================================================================ 鼠标命中
func hit_cta(p: Vector2) -> bool:
	if state != "shown" and state != "enter_home":
		return false
	return _cta_rect.has_point(p)


func hit_slice(p: Vector2) -> int:
	if state != "shown" and state != "enter_home":
		return -1
	for i in _card_rects.size():
		if (_card_rects[i] as Rect2).has_point(p):
			return i
	if p.x > 1640.0 and p.y > 140.0 and p.y < 880.0:
		return posmod(idx + 1, DATA.size())
	if p.x < 240.0 and p.y > 140.0 and p.y < 880.0 and String(DATA[idx]["hud_mode"]) == "right":
		return posmod(idx - 1, DATA.size())
	return -1


func set_hover(p: Vector2) -> bool:
	hover_cta = hit_cta(p)
	hover_node = -1
	for i in _card_rects.size():
		if (_card_rects[i] as Rect2).has_point(p):
			hover_node = i
			break
	return hover_cta or hover_node >= 0


# ================================================================ 缓动
static func _seg(t: float, a: float, d: float) -> float:
	return clampf((t - a) / maxf(0.0001, d), 0.0, 1.0)


static func _expo(t: float) -> float:
	return 1.0 if t >= 1.0 else 1.0 - pow(2.0, -10.0 * t)


static func _in_out(t: float) -> float:
	return 4.0 * t * t * t if t < 0.5 else 1.0 - pow(-2.0 * t + 2.0, 3.0) / 2.0


static func _cubic_out(t: float) -> float:
	return 1.0 - pow(1.0 - t, 3.0)


# ================================================================ 每帧更新（四套电影机位真三维无缝飞行！）
func update(dt: float, ptr: Vector2) -> void:
	now += dt
	pointer = ptr
	if state == "hidden":
		visible = false
		cathedral_root.visible = false
		cam_st = {}
		cine_st = {}
		return

	visible = true
	cathedral_root.visible = true
	var ts := now - t_state

	var steps := maxi(1, ceili(dt / 0.004))
	var h := dt / float(steps)
	var st_goals: Array = DATA[idx]["stats"]
	for _s in steps:
		orbit_vel += ((orbit_goal - orbit_ang) * 155.0 - orbit_vel * 16.0) * h
		orbit_ang += orbit_vel * h
		bank_vel += (-bank_roll * 165.0 - bank_vel * 14.5) * h
		bank_roll += bank_vel * h
		fov_vel += (-fov_kick * 135.0 - fov_vel * 14.0) * h
		fov_kick += fov_vel * h
		ring_kick_vel *= exp(-h * 4.5)
		ring_kick_ang += ring_kick_vel * h
		for k in 3:
			var g: float = float(st_goals[k])
			stat_vels[k] = float(stat_vels[k]) + ((g - float(stat_vals[k])) * 210.0 - float(stat_vels[k]) * 16.0) * h
			stat_vals[k] = clampf(float(stat_vals[k]) + float(stat_vels[k]) * h, 0.0, 1.08)

	# 摄影机平滑飞往当前主角专属电影机位（位置 / 瞄准点 / 焦距 / 滚转角全独立动画！）
	var cam_lerp := 1.0 - exp(-dt * 8.5)
	var goal_pos: Vector3 = DATA[idx]["cam_pos"]
	var goal_look: Vector3 = DATA[idx]["cam_look"]
	cam_pos_cur = cam_pos_cur.lerp(goal_pos, cam_lerp)
	cam_look_cur = cam_look_cur.lerp(goal_look, cam_lerp)
	cam_fov_cur = lerpf(cam_fov_cur, float(DATA[idx]["cam_fov"]), cam_lerp)
	cam_roll_cur = lerpf(cam_roll_cur, float(DATA[idx]["cam_roll"]), cam_lerp)

	chroma_pulse = maxf(0.0, chroma_pulse - dt * 0.115)
	blur_pulse = maxf(0.0, blur_pulse - dt * 0.125)
	impact_pulse = maxf(0.0, impact_pulse - dt * 15.0)
	lock_shake = maxf(0.0, lock_shake - dt * 3.4)
	cta_k = lerpf(cta_k, 1.0 if hover_cta else 0.0, minf(1.0, dt * 15.0))

	var acc: Color = DATA[idx]["accent"]
	var sw_age := now - switch_t

	# 切角瞬间摄影机划出一道大弧度三维航拍弧（绝不直来直去！）
	var arc_w := exp(-maxf(sw_age, 0.0) * 7.0) * sin(clampf(sw_age / 0.36, 0.0, 1.0) * PI) if (sw_age >= 0.0 and sw_age < 0.5) else 0.0
	var rest_pos := cam_pos_cur + Vector3(
		pointer.x * 78.0 + sin(now * 0.55) * 28.0 + float(switch_dir) * 260.0 * arc_w,
		-pointer.y * 44.0 + cos(now * 0.43) * 18.0 + 90.0 * arc_w,
		sin(now * 0.37) * 34.0 + 210.0 * arc_w
	)
	var rest_look := cam_look_cur + Vector3(pointer.x * 24.0, -pointer.y * 14.0, 0.0)
	var rest_xf := Transform3D(Basis.looking_at(rest_look - rest_pos, Vector3.UP), rest_pos)

	var cam_xf := rest_xf
	var cam_fov := cam_fov_cur + clampf(fov_kick, -10.0, 18.0)
	var cam_roll := cam_roll_cur + clampf(bank_roll, -0.18, 0.18)
	var explode_k := 0.0
	var cathedral_op := 1.0
	var slash_prog := 0.0
	var slash_op := 0.0
	var slash2_prog := 0.0
	var lb_goal := 0.0
	var wipe_p := -1.0

	var c_split := 0.0
	var c_htilt := 0.0
	var c_dial_a := 0.0
	var c_hand_a := 0.0
	var c_bg_a := 0.0
	var c_rift_a := 0.0
	var c_seam_a := 0.0
	var c_home_a := 0.0
	var c_ring_dz := [0.0, 0.0, 0.0, 0.0, 0.0]
	var c_ring_rot := [0.0, 0.0, 0.0, 0.0, 0.0]

	match state:
		"enter_home":
			# 【创意镜头 1：绕钟掠齿 52° 立体航拍 + 巨型剑形分针实体擦镜切入钟心！】
			var p_orbit := _seg(ts, 0.0, 0.34)
			var e_orbit := _in_out(p_orbit)
			var p_dive := _seg(ts, 0.24, 0.56)
			var e_dive := _in_out(p_dive)
			lb_goal = lerpf(0.098, 0.0, _seg(ts, 0.44, 0.36))

			if ts >= 0.22 and not enter_sfx_fired:
				enter_sfx_fired = true
				chroma_pulse = 0.022
				blur_pulse = 0.036
				impact_pulse = 0.88
				if T != null:
					if T.has_method("_play"):
						T._play("h3_slash_heavy" if T.sfx.has("h3_slash_heavy") else "ult_cut_0", -1.2, 1.02)
						T._play("ult_impact", -5.0, 1.10)
					if T.has_method("_hit"):
						T._hit(22.0, 0.024, 0.44)
					T.hitstop = 0.036

			# 中转机位：贴近铸铁巨钟右侧边缘 52° 侧飞掠齿（真实看到 5 圈铸铁厚度！）
			var rim_pos := Vector3(1120.0, -240.0, 720.0)
			var rim_look := Vector3(-120.0, 40.0, -520.0)
			var rim_xf := Transform3D(Basis.looking_at(rim_look - rim_pos, Vector3.UP), rim_pos)

			if ts < 0.24:
				cam_xf = home_xf.interpolate_with(rim_xf, e_orbit)
				cam_fov = lerpf(30.0, 50.0, e_orbit)
				cam_roll = -0.14 * e_orbit
			else:
				cam_xf = rim_xf.interpolate_with(rest_xf, e_dive)
				cam_xf.origin += Vector3(-220.0, 110.0, 0.0) * sin(PI * p_dive)
				cam_fov = lerpf(50.0, cam_fov_cur, e_dive) + 12.0 * sin(PI * p_dive)
				cam_roll = lerpf(-0.14, cam_roll_cur, e_dive)

			# 前景实体剑形分针在 0.20..0.50s 贴着镜头挥过擦镜！
			if ts >= 0.18 and ts <= 0.52:
				wipe_p = _seg(ts, 0.18, 0.34)

			var sp_k := _expo(_seg(ts, 0.20, 0.42))
			c_split = sp_k * 1850.0
			c_htilt = sp_k * 0.52
			c_dial_a = 1.0 - _seg(ts, 0.44, 0.22)
			# 旧钟指针与轴心在劈开瞬间立刻收净，绝不在左侧空中孤零零悬空！
			c_hand_a = 1.0 - _seg(ts, 0.18, 0.12)
			c_bg_a = 1.0 - _seg(ts, 0.14, 0.10)
			c_rift_a = 1.0 - _seg(ts, 0.10, 0.08)
			c_seam_a = 1.0 - _seg(ts, 0.10, 0.06)
			c_home_a = 1.0 - _seg(ts, 0.0, 0.16)
			for ri in 5:
				c_ring_dz[ri] = float(ri - 2) * 480.0 * sp_k
				c_ring_rot[ri] = (1.0 if ri % 2 == 0 else -1.0) * (0.38 * p_orbit + 1.55 * sp_k)

			slash_prog = _seg(ts, 0.20, 0.34)
			slash_op = 1.0 if (slash_prog > 0.0 and slash_prog < 1.0) else 0.0
			cathedral_op = _seg(ts, 0.16, 0.24)
			ui_alpha = _cubic_out(_seg(ts, 0.50, 0.32))

			if ts >= T_ENTER_HOME:
				state = "shown"
				if T != null:
					T.busy = false

		"enter_select":
			var p := _seg(ts, 0.0, T_ENTER_SEL)
			var e := _expo(p)
			lb_goal = lerpf(0.072, 0.0, e)
			cam_xf = from_sel_xf.interpolate_with(rest_xf, e)
			cam_fov = lerpf(48.0, cam_fov_cur, e) + fov_kick * 0.4
			cam_roll = 0.08 * (1.0 - e) + cam_roll
			explode_k = (1.0 - e) * 0.72
			cathedral_op = clampf(p * 2.2, 0.0, 1.0)
			ui_alpha = _cubic_out(_seg(ts, 0.18, 0.28))
			if ts >= T_ENTER_SEL:
				state = "shown"
				if T != null:
					T.busy = false

		"shown":
			ui_alpha = lerpf(ui_alpha, 1.0, minf(1.0, dt * 14.0))
			if idx == 0 and sw_age >= 0.0 and sw_age < 0.36:
				slash_prog = _seg(sw_age, 0.02, 0.26)
				slash2_prog = _seg(sw_age, 0.09, 0.25)
				slash_op = 1.0
			# 切角瞬间也掠过一道极快前景剑针暗影，衔接机位大甩镜！
			if sw_age >= 0.0 and sw_age < 0.22:
				wipe_p = sw_age / 0.22
			if lock_shake > 0.001:
				cam_xf.origin += Vector3(sin(now * 86.0), cos(now * 68.0), 0.0) * 28.0 * lock_shake * lock_shake

		"confirm":
			# 【创意镜头 3：希区柯克 Vertigo 变焦贴脸锁眼 → 1帧瞬杀双紫斩 → 上仰追随巨钟飞入夜空砸进钟楼！】
			var p_tight := _cubic_out(_seg(ts, 0.0, 0.19))
			var p_slash := _seg(ts, 0.19, 0.33)
			var e_dash := pow(p_slash, 1.65)
			lb_goal = 0.112

			# 希区柯克变焦：镜头微微后撤的同时急压长焦 35° → 19.5°，让背后的巨钟骇人膨胀逼近！
			var tight_pos := Vector3(-42.0, 52.0, -1120.0)
			var tight_look := Vector3(-8.0, 56.0, -2830.0)
			var tight_xf := Transform3D(Basis.looking_at(tight_look - tight_pos, Vector3.UP), tight_pos)
			# 斩破后：镜头猛然仰起追随聚拢升空的巨钟直冲钟楼！
			var sky_pos := Vector3(140.0, -220.0, -2420.0)
			var sky_look := Vector3(240.0, 380.0, -5200.0)
			var sky_xf := Transform3D(Basis.looking_at(sky_look - sky_pos, Vector3.UP), sky_pos)

			if ts < 0.19:
				cam_xf = rest_xf.interpolate_with(tight_xf, p_tight)
				cam_fov = lerpf(cam_fov_cur, 19.5, p_tight)
				cam_roll = lerpf(cam_roll, -0.135, p_tight)
			else:
				if not enter_sfx_fired:
					enter_sfx_fired = true
					chroma_pulse = 0.026
					blur_pulse = 0.042
					impact_pulse = 0.96
					if T != null:
						if T.has_method("_play"):
							T._play("h3_slash_heavy" if T.sfx.has("h3_slash_heavy") else "ult_cut_2", -0.5, 0.98)
							T._play("ult_impact", -2.0, 0.90)
						if T.has_method("_hit"):
							T._hit(30.0, 0.028, 0.60)
						T.hitstop = 0.044
				cam_xf = tight_xf.interpolate_with(sky_xf, e_dash)
				cam_fov = lerpf(19.5, 50.0, e_dash)
				cam_roll = lerpf(-0.135, 0.07, e_dash)

			slash_prog = _seg(ts, 0.17, 0.28)
			slash2_prog = _seg(ts, 0.22, 0.26)
			slash_op = 1.0 if (slash_prog > 0.0 or slash2_prog > 0.0) else 0.0
			explode_k = _cubic_out(p_slash)
			cathedral_op = 1.0 - _seg(ts, 0.35, 0.17)
			ui_alpha = 1.0 - _seg(ts, 0.0, 0.12)

			if ts >= T_CONFIRM and not confirm_fired:
				confirm_fired = true
				last_cam_xf = cam_xf
				state = "hidden"
				visible = false
				cathedral_root.visible = false
				cam_st = {}
				cine_st = {}
				if confirm_cb.is_valid():
					var cb := confirm_cb
					confirm_cb = Callable()
					cb.call(last_cam_xf)
				return

		"leave_home":
			var p := _seg(ts, 0.0, T_LEAVE_HOME)
			var e := _in_out(p)
			lb_goal = 0.0
			cam_xf = last_cam_xf.interpolate_with(home_xf, e)
			cam_xf.origin += Vector3(260.0, -60.0, 0.0) * sin(PI * p)
			cam_fov = lerpf(cam_fov_cur, 30.0, e) + 14.0 * sin(PI * p)
			cam_roll = 0.09 * sin(PI * p)
			var sp_k := 1.0 - _expo(_seg(ts, 0.10, 0.40))
			c_split = sp_k * 1750.0
			c_htilt = sp_k * 0.46
			c_dial_a = _seg(ts, 0.06, 0.24)
			c_hand_a = _seg(ts, 0.24, 0.22)
			c_bg_a = _seg(ts, 0.34, 0.16)
			c_rift_a = _seg(ts, 0.34, 0.18)
			c_seam_a = _seg(ts, 0.36, 0.16)
			c_home_a = _seg(ts, 0.32, 0.20)
			for ri in 5:
				c_ring_dz[ri] = float(ri - 2) * 380.0 * sp_k
				c_ring_rot[ri] = (1.0 if ri % 2 == 0 else -1.0) * 1.15 * sp_k
			cathedral_op = 1.0 - _seg(ts, 0.26, 0.22)
			ui_alpha = 1.0 - _seg(ts, 0.0, 0.16)

			if ts >= T_LEAVE_HOME:
				state = "hidden"
				visible = false
				cathedral_root.visible = false
				cam_st = {}
				cine_st = {}
				if leave_cb.is_valid():
					var cb := leave_cb
					leave_cb = Callable()
					cb.call()
				return

	letterbox_cur = lerpf(letterbox_cur, lb_goal, minf(1.0, dt * 12.0))
	last_cam_xf = cam_xf

	_update_3d_arena(dt, acc, explode_k, cathedral_op, cam_xf, slash_prog, slash2_prog, slash_op, sw_age, wipe_p)

	cam_st = {
		"cam_xf": cam_xf, "cam_blend": 1.0, "cam_fov": cam_fov,
		"cam_arc": Vector3.ZERO, "cam_roll": cam_roll,
		"cam_shake": (T.shake["p"] as Vector2) if T != null else Vector2.ZERO,
		"split": c_split, "half_tilt": c_htilt,
		"ring_dz": c_ring_dz, "ring_rot": c_ring_rot,
		"dial_a": c_dial_a, "hub_a": c_hand_a, "hour_a": c_hand_a, "minute_a": c_hand_a,
		"seam_a": c_seam_a, "rift_a": c_rift_a, "bg_a": c_bg_a,
		"rain_a": c_home_a, "motes_a": c_home_a * 0.4, "debris": c_dial_a,
		"readout_a": c_home_a, "glint": c_home_a, "mark_a": c_home_a, "home_a": c_home_a,
		"flash": 0.0, "pulse": 0.0,
	}
	cine_st = {
		"accent_col": acc,
		"chroma_amp": clampf(chroma_pulse + absf(orbit_vel) * 0.0028, 0.0, 0.030),
		"radial_blur": clampf(blur_pulse + absf(orbit_vel) * 0.0042, 0.0, 0.042),
		"impact_k": impact_pulse,
		"letterbox_ratio": letterbox_cur,
		"vignette_k": 0.72 * cathedral_op,
		"focus_uv": Vector2(0.38 if idx == 1 else (0.50 if idx == 3 else 0.58), 0.48),
	}

	overlay.queue_redraw()


func _update_3d_arena(dt: float, acc: Color, explode_k: float, cathedral_op: float, cam_xf: Transform3D, slash_prog: float, slash2_prog: float, slash_op: float, sw_age: float, wipe_p: float) -> void:
	var ring_tint := acc.lerp(WHITE, 0.26)

	# 1. 常驻殿堂巨型三维哥特母钟（在曜居中构图时与正中心完美轴对称，其余机位呈宏伟偏移透视！）
	var sc_x := 0.0 if idx == 3 else ( -120.0 if idx == 1 else 110.0)
	sanctum_clock.position = ARENA_CENTER + Vector3(sc_x - pointer.x * 42.0, 60.0 + explode_k * 520.0 + pointer.y * 26.0, -980.0 - explode_k * 1750.0)
	var sc_scale := lerpf(1.0, 0.44, explode_k)
	sanctum_clock.scale = Vector3.ONE * sc_scale
	(sc_parts["dial"] as MeshInstance3D).rotation.z = -28.0 * DEG + now * 0.035 + ring_kick_ang * 0.45
	(sc_parts["rim"] as MeshInstance3D).rotation.z = -28.0 * DEG - now * 0.055 - ring_kick_ang * 0.75
	(sc_parts["gm"] as MeshInstance3D).rotation.z = -now * 0.24 - ring_kick_ang * 1.4
	(sc_parts["ge"] as MeshInstance3D).rotation.z = now * 0.42 + ring_kick_ang * 2.2
	(sc_parts["ros"] as MeshInstance3D).rotation.z = now * 0.18 + ring_kick_ang
	var tick_tremble := sin(now * 28.0) * 0.012 * pow(maxf(0.0, sin(now * PI)), 6.0)
	(sc_parts["hour"] as Node3D).rotation.z = 112.0 * DEG + ring_kick_ang * 0.2
	(sc_parts["min"] as Node3D).rotation.z = 96.0 * DEG + tick_tremble + ring_kick_ang * 0.6
	(sc_parts["dial_m"] as ShaderMaterial).set_shader_parameter("opacity", 0.56 * cathedral_op)
	(sc_parts["rim_m"] as ShaderMaterial).set_shader_parameter("tint", ring_tint)
	(sc_parts["rim_m"] as ShaderMaterial).set_shader_parameter("opacity", (0.26 + clampf(absf(ring_kick_vel) * 0.08, 0.0, 0.35)) * cathedral_op)
	(sc_parts["gm_m"] as ShaderMaterial).set_shader_parameter("opacity", 0.52 * cathedral_op)
	(sc_parts["ge_m"] as ShaderMaterial).set_shader_parameter("tint", ring_tint)
	(sc_parts["ge_m"] as ShaderMaterial).set_shader_parameter("opacity", 0.26 * cathedral_op)
	(sc_parts["hour_m"] as ShaderMaterial).set_shader_parameter("opacity", 0.60 * cathedral_op)
	(sc_parts["min_m"] as ShaderMaterial).set_shader_parameter("tint", acc.lerp(WHITE, 0.55))
	(sc_parts["min_m"] as ShaderMaterial).set_shader_parameter("opacity", 0.52 * cathedral_op)
	(sc_parts["ros_m"] as ShaderMaterial).set_shader_parameter("tint", ring_tint)
	(sc_parts["ros_m"] as ShaderMaterial).set_shader_parameter("opacity", 0.38 * cathedral_op)

	# 2. 近景暗铸铁巨齿（紧贴相机下右/下左前缘旋转，打造顶级电影前景视差！）
	var fg_side := -1.0 if idx == 1 else 1.0
	var fg_fwd := -cam_xf.basis.z
	var fg_right := cam_xf.basis.x
	var fg_up := cam_xf.basis.y
	fg_gear_mi.visible = cathedral_op > 0.2 and idx != 3 and state != "confirm"
	if fg_gear_mi.visible:
		fg_gear_mi.global_position = cam_xf.origin + fg_fwd * 1020.0 + fg_right * (fg_side * 660.0) - fg_up * 440.0
		fg_gear_mi.global_basis = cam_xf.basis * Basis(Vector3.BACK, now * 0.28 * fg_side + ring_kick_ang * 1.1)
		fg_gear_m.set_shader_parameter("opacity", 0.58 * cathedral_op * (1.0 - explode_k))

	# 3. 实体前景剑形分针擦镜（首页绕钟进场 / 切角瞬间横扫镜头！）
	wipe_hand_mi.visible = wipe_p >= 0.0 and wipe_p <= 1.0
	if wipe_hand_mi.visible:
		var wp_e := _in_out(wipe_p)
		wipe_hand_piv.global_position = cam_xf.origin + fg_fwd * 540.0 + fg_right * lerpf(620.0, -680.0, wp_e) - fg_up * 260.0
		wipe_hand_piv.global_basis = cam_xf.basis * Basis(Vector3.BACK, lerpf(-0.95, 1.15, wp_e))
		wipe_hand_m.set_shader_parameter("opacity", sin(wipe_p * PI) * 0.92)

	# 4. 八柱柱廊 / 三重浑天仪 / 地面星盘
	colonnade_root.rotation.y = orbit_ang * 0.65 + now * 0.02
	for sm: ShaderMaterial in colonnade_slits:
		sm.set_shader_parameter("tint", acc.lerp(WHITE, 0.3))
		sm.set_shader_parameter("opacity", 0.38 * cathedral_op * (1.0 - explode_k))

	for ar in armillary_rings:
		var ami: MeshInstance3D = ar["mi"]
		var am: ShaderMaterial = ar["m"]
		ami.rotation.z = now * float(ar["sp"]) + ring_kick_ang * 0.85
		var piv: Node3D = ar["piv"]
		var r0: Vector3 = ar["rot0"]
		piv.rotation = r0 + Vector3(sin(now * 0.4) * 0.04, orbit_ang * 0.25, 0.0)
		piv.scale = Vector3.ONE * (1.0 + explode_k * 0.75)
		am.set_shader_parameter("tint", ring_tint)
		am.set_shader_parameter("opacity", float(ar["base_op"]) * cathedral_op * (1.0 - explode_k * 0.85))

	for fr in floor_rings:
		var mi: MeshInstance3D = fr["mi"]
		var m: ShaderMaterial = fr["m"]
		mi.rotation.z = now * float(fr["sp"]) + ring_kick_ang * (1.2 if bool(fr["add"]) else -0.45)
		mi.position.z = float(fr["z0"]) - explode_k * 650.0
		var s_exp := 1.0 + explode_k * 0.85
		mi.scale = Vector3(s_exp, s_exp, 1.0)
		if bool(fr["add"]):
			m.set_shader_parameter("tint", ring_tint)
		m.set_shader_parameter("opacity", float(fr["base_op"]) * cathedral_op * (1.0 - explode_k * 0.85))

	# 5. 四座神龛与 3 重高速残影
	carousel.rotation.y = orbit_ang
	var cur_mode := String(DATA[idx]["hud_mode"])
	for i in slots.size():
		var sl: Dictionary = slots[i]
		var is_cur := i == idx
		var f_goal := 1.0 if is_cur else 0.0
		sl["focus"] = lerpf(float(sl["focus"]), f_goal, minf(1.0, dt * 11.5))
		sl["flash"] = maxf(0.0, float(sl["flash"]) - dt * 3.0)
		sl["glint"] = minf(2.4, float(sl["glint"]) + dt * 2.8)

		var fk: float = float(sl["focus"])
		var slot: Node3D = sl["slot"]
		var ang: float = float(sl["ang"])
		var rel_ang := wrapf(ang + orbit_ang, -PI, PI)

		var r_cur := ORBIT_R + (explode_k * 1650.0 if not is_cur else explode_k * 260.0)
		var y_cur := (explode_k * 240.0 if not is_cur else 0.0) + sin(now * 1.35 + float(i) * 1.57) * 10.0 * (1.0 - fk * 0.5)
		slot.position = Vector3(sin(ang) * r_cur, y_cur, cos(ang) * r_cur)
		slot.rotation.y = -orbit_ang + sin(rel_ang) * 0.34

		var dash_vec: Vector3 = DATA[i]["dash_vec"]
		var dash_k := exp(-maxf(sw_age, 0.0) * 11.5) if (is_cur and sw_age >= 0.0 and sw_age < 0.65) else 0.0

		var hero_mi: MeshInstance3D = sl["hero_mi"]
		var hero_m: ShaderMaterial = sl["hero_m"]
		var lunge_z := fk * 125.0 + dash_k * 55.0
		var lock_x := sin(now * 78.0) * 28.0 * lock_shake * lock_shake if is_cur else 0.0
		var hpos := Vector3(float(sl["x0"]) + lock_x, float(sl["y0"]), lunge_z) + dash_vec * dash_k * 0.42
		hero_mi.position = hpos
		var hscale := lerpf(0.84, 1.04 + dash_k * 0.14, fk) * (1.0 + (explode_k * 0.16 if is_cur else -explode_k * 0.2))
		hero_mi.scale = Vector3(hscale, hscale, 1.0)

		# 根据当前主角的 HUD 方位动态压暗对应侧翼背景角色（萤 HUD 在右 → 压暗右侧背景；其余压暗左侧背景！）
		var hud_hush := 1.0
		if cur_mode == "right":
			hud_hush = 1.0 - smoothstep(0.35, 1.25, rel_ang) * (1.0 - fk) * 0.86
		elif cur_mode == "center":
			hud_hush = 1.0 - (1.0 - fk) * 0.58
		else:
			hud_hush = 1.0 - smoothstep(0.35, 1.25, -rel_ang) * (1.0 - fk) * 0.86

		hero_m.render_priority = 2 if is_cur else 1
		hero_m.set_shader_parameter("active_theme_col", acc)
		hero_m.set_shader_parameter("focus_k", fk)
		hero_m.set_shader_parameter("flash_k", float(sl["flash"]))
		hero_m.set_shader_parameter("glint_u", float(sl["glint"]))
		hero_m.set_shader_parameter("time_sec", now + float(i) * 2.1)
		hero_m.set_shader_parameter("opacity", cathedral_op * hud_hush * (1.0 - (explode_k * 0.9 if not is_cur else explode_k * 0.28)))

		var ghosts: Array = sl["ghosts"]
		for gi in ghosts.size():
			var gd: Dictionary = ghosts[gi]
			var gmi: MeshInstance3D = gd["mi"]
			var gm: ShaderMaterial = gd["m"]
			var ga := dash_k * (0.58 - float(gi) * 0.15) * cathedral_op
			gmi.visible = is_cur and ga > 0.02
			if gmi.visible:
				var gstep := float(gi + 1) * 0.55
				gmi.position = hpos + dash_vec * dash_k * gstep
				gmi.scale = Vector3.ONE * (hscale * (1.0 + float(gi) * 0.05 * dash_k))
				gm.set_shader_parameter("opacity", ga)

		var aura_m: ShaderMaterial = sl["aura_m"]
		var aura_mi: MeshInstance3D = sl["aura_mi"]
		aura_m.set_shader_parameter("time_sec", now + float(i) * 1.7)
		aura_m.set_shader_parameter("burst_k", float(sl["flash"]))
		aura_m.set_shader_parameter("opacity", lerpf(0.20, 0.88, fk) * hud_hush * cathedral_op * (1.0 - explode_k * 0.7))
		aura_mi.scale = Vector3.ONE * lerpf(0.76, 1.10 + float(sl["flash"]) * 0.16, fk)

		var kanji_mi: MeshInstance3D = sl["kanji_mi"]
		var kanji_m: ShaderMaterial = sl["kanji_m"]
		kanji_m.set_shader_parameter("opacity", lerpf(0.04, 0.13 + float(sl["flash"]) * 0.12, fk) * hud_hush * cathedral_op * (1.0 - explode_k))

		var halo_mi: MeshInstance3D = sl["halo_mi"]
		var halo_m: ShaderMaterial = sl["halo_m"]
		halo_mi.rotation.z = now * (0.30 if i % 2 == 0 else -0.26) + ring_kick_ang * 0.5
		halo_m.set_shader_parameter("opacity", lerpf(0.10, 0.52 + float(sl["flash"]) * 0.4, fk) * hud_hush * cathedral_op * (1.0 - explode_k))

	# 6. 四姝专属粒子生态
	var pmode: int = int(DATA[idx]["pmode"])
	particles_mat.set_shader_parameter("tint", acc.lerp(WHITE, 0.36))
	particles_mat.set_shader_parameter("opacity", 0.78 * cathedral_op * (1.0 - explode_k * 0.6))
	var mm := particles_mmi.multimesh
	for pi in particles_data.size():
		var pd: Dictionary = particles_data[pi]
		var sp: float = float(pd["sp"])
		var ph: float = float(pd["ph"])
		var px: float = float(pd["x"])
		var py: float = float(pd["y"])
		var pz: float = float(pd["z"])
		var sx: float = float(pd["sz"])
		var sy: float = sx * float(pd["len"])
		var rot_z: float = 0.0
		match pmode:
			0:
				var tt := fmod(now * 280.0 * sp + ph * 300.0, 2200.0)
				px = fposmod(px - tt * 0.48 + 1800.0, 3600.0) - 1800.0
				py = fposmod(py - tt * 0.88 + 800.0, 1600.0) - 800.0
				rot_z = -28.0 * DEG; sx *= 0.42; sy *= 1.65
			1:
				px = fposmod(px - now * 740.0 * sp + 1800.0, 3600.0) - 1800.0
				py += sin(now * 2.4 * sp + ph) * 44.0
				rot_z = 82.0 * DEG; sx *= 0.34; sy *= 2.5
			2:
				py = fposmod(py + now * 340.0 * sp + 800.0, 1600.0) - 800.0
				px += sin(now * 3.2 * sp + ph) * 68.0
				rot_z = sin(now * 2.0 + ph) * 0.4; sx *= 0.70; sy *= 0.95
			_:
				py = fposmod(py - now * 98.0 * sp + 800.0, 1600.0) - 800.0
				px += cos(now * 0.8 * sp + ph) * 28.0
				rot_z = 0.0; sx *= 0.64; sy *= 0.64
		mm.set_instance_transform(pi, Transform3D(Basis(Vector3.BACK, rot_z).scaled(Vector3(sx, sy, 1.0)), Vector3(px, py, pz)))

	# 7. 四姝专属三维登场特效
	var s1_vis := slash_op > 0.005 and slash_prog > 0.001 and slash_prog < 0.999
	var s2_vis := slash_op > 0.005 and slash2_prog > 0.001 and slash2_prog < 0.999
	slash_mi.visible = s1_vis
	slash2_mi.visible = s2_vis
	if s1_vis or s2_vis:
		slash_pivot.global_position = cam_xf.origin + fg_fwd * 750.0
		var tilt_ang := (-62.0 if state == "enter_home" else 20.0) * DEG
		slash_pivot.global_basis = cam_xf.basis * Basis(Vector3.BACK, tilt_ang) * Basis(Vector3.RIGHT, 0.16)
		slash_mat.set_shader_parameter("accent_col", acc)
		slash_mat.set_shader_parameter("progress", slash_prog)
		slash_mat.set_shader_parameter("opacity", slash_op)
		slash2_mat.set_shader_parameter("accent_col", acc)
		slash2_mat.set_shader_parameter("progress", slash2_prog)
		slash2_mat.set_shader_parameter("opacity", slash_op * 0.92)

	var ying_v := exp(-maxf(sw_age, 0.0) * 5.2) if (idx == 1 and sw_age >= 0.0 and sw_age < 0.85 and state == "shown") else 0.0
	vortex_mi.visible = ying_v > 0.01
	if vortex_mi.visible:
		var vp := clampf(sw_age / 0.55, 0.0, 1.0)
		vortex_mi.scale = Vector3.ONE * lerpf(0.38, 1.38, _expo(vp))
		vortex_mi.rotation.z = now * 6.5
		vortex_mat.set_shader_parameter("opacity", ying_v * 0.88 * cathedral_op)

	var wei_v := exp(-maxf(sw_age, 0.0) * 4.5) if (idx == 2 and sw_age >= 0.0 and sw_age < 0.95 and state == "shown") else 0.0
	shockwave_mi.visible = wei_v > 0.01
	if shockwave_mi.visible:
		var wp := clampf(sw_age / 0.65, 0.0, 1.0)
		shockwave_mi.scale = Vector3.ONE * lerpf(0.24, 1.68, _expo(wp))
		shockwave_mat.set_shader_parameter("opacity", wei_v * 0.95 * cathedral_op)

	var yao_v := exp(-maxf(sw_age, 0.0) * 3.2) if (idx == 3 and sw_age >= 0.0 and sw_age < 1.2 and state == "shown") else 0.0
	for yi in yao_pillars.size():
		var yp: Dictionary = yao_pillars[yi]
		var ymi: MeshInstance3D = yp["mi"]
		var ym: ShaderMaterial = yp["m"]
		ymi.visible = yao_v > 0.01
		if ymi.visible:
			ymi.scale = Vector3(lerpf(1.45, 0.35, clampf(sw_age / 0.85, 0.0, 1.0)), 1.0, 1.0)
			ym.set_shader_parameter("opacity", yao_v * (0.42 if yi == 1 else 0.24) * cathedral_op)


# ================================================================ 动态异构悬浮 HUD（随 4 种机位智能重构版式！）
func _draw_hud() -> void:
	if ui_alpha <= 0.005:
		return
	var c := overlay
	var a := ui_alpha
	var d: Dictionary = DATA[idx]
	var acc: Color = d["accent"]
	var rim: Color = d["rim"]
	var playable: bool = bool(d["playable"])
	var mode: String = String(d["hud_mode"])
	var is_right := mode == "right"
	var is_center := mode == "center"
	var f_cn: Font = T.font_cn as Font
	var f_med: Font = T.font_cn_med as Font
	var f_lat: Font = T.font_lat as Font

	var sw := clampf((now - switch_t) / 0.32, 0.0, 1.0)
	var sw_e := _cubic_out(sw)
	var slide_x := (1.0 - sw_e) * (66.0 if is_right else -66.0)
	var txt_a := a * clampf(sw_e * 1.4, 0.0, 1.0)

	# 1. 随构图方向自适应柔羽化暗场托底（超宽平滑渐变，零硬切垂直边界线！）
	var sc_l := Color(INK, 0.90 * a)
	var sc_m := Color(INK, 0.56 * a)
	var sc_0 := Color(INK, 0.0)
	if is_right:
		c.draw_polygon(PackedVector2Array([Vector2(900, 0), Vector2(1340, 0), Vector2(1340, H), Vector2(900, H)]), PackedColorArray([sc_0, sc_m, sc_m, sc_0]))
		c.draw_polygon(PackedVector2Array([Vector2(1340, 0), Vector2(W, 0), Vector2(W, H), Vector2(1340, H)]), PackedColorArray([sc_m, sc_l, sc_l, sc_m]))
	elif is_center:
		c.draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(620, 0), Vector2(620, H), Vector2(0, H)]), PackedColorArray([sc_l, sc_0, sc_0, sc_l]))
		c.draw_polygon(PackedVector2Array([Vector2(1300, 0), Vector2(W, 0), Vector2(W, H), Vector2(1300, H)]), PackedColorArray([sc_0, sc_l, sc_l, sc_0]))
	else:
		c.draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(520, 0), Vector2(520, H), Vector2(0, H)]), PackedColorArray([sc_l, sc_m, sc_m, sc_l]))
		c.draw_polygon(PackedVector2Array([Vector2(520, 0), Vector2(920, 0), Vector2(920, H), Vector2(520, H)]), PackedColorArray([sc_m, sc_0, sc_0, sc_m]))

	# 2. 顶部司辰标尺抬头（根据构图切左右）
	var top_x := 1340.0 if is_right else 88.0
	var top_y := 58.0
	c.draw_line(Vector2(top_x, top_y), Vector2(top_x, top_y + 34), Color(acc, 0.96 * a), 3.0, true)
	c.draw_string(f_med, Vector2(top_x + 20.0, top_y + 23), "司辰四象 · 选择主角", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(WHITE, 0.95 * a))
	c.draw_string(f_lat, Vector2(top_x + 280.0, top_y + 22), "05:59", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(rim, 0.78 * a))
	c.draw_line(Vector2(top_x, top_y + 42), Vector2(top_x + 480.0, top_y + 42), Color(WHITE, 0.18 * a), 1.0, true)

	# 3. 角色信息主锚点（朔/薇在左 94；萤镜像反构图在右 1340；曜圣坛左右双翼分置！）
	var ox := (1340.0 if is_right else 94.0) + slide_x
	var num_y := 258.0 + (1.0 - sw_e) * 44.0
	c.draw_string(f_lat, Vector2(ox - 12.0, num_y), String(d["num"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 148, Color(acc, 0.15 * txt_a))

	var wt: Texture2D = _load_tex(String(d["word"]))
	var wasp := float(wt.get_width()) / maxf(1.0, float(wt.get_height()))
	var wh := 196.0
	var ww := wh * wasp
	var wpos := Vector2(ox - 14.0, 142.0)
	c.draw_texture_rect(wt, Rect2(wpos + Vector2(10, 12), Vector2(ww, wh)), false, Color(INK, 0.94 * txt_a))
	c.draw_texture_rect(wt, Rect2(wpos + Vector2(-4, 0), Vector2(ww, wh)), false, Color(acc, 0.52 * txt_a))
	c.draw_texture_rect(wt, Rect2(wpos, Vector2(ww, wh)), false, Color(WHITE, 0.99 * txt_a))

	var sub_x := ox + ww - 2.0
	var ep_txt := "「" + String(d["epithet"]) + "」"
	c.draw_string(f_med, Vector2(sub_x + 2, 232.0), ep_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color(INK, 0.92 * txt_a))
	c.draw_string(f_med, Vector2(sub_x, 230.0), ep_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color(acc.lerp(WHITE, 0.22), 0.98 * txt_a))
	c.draw_line(Vector2(sub_x + 4.0, 250.0), Vector2(sub_x + 230.0, 250.0), Color(acc, 0.66 * txt_a), 1.6, true)
	var wp_txt := String(d["weapon"])
	c.draw_string(f_cn, Vector2(sub_x + 6.0, 286.0), wp_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 21, Color(INK, 0.92 * txt_a))
	c.draw_string(f_cn, Vector2(sub_x + 4.0, 284.0), wp_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 21, Color(WHITE, 0.88 * txt_a))

	# 台词
	var qy := 386.0
	c.draw_line(Vector2(ox, qy - 14.0), Vector2(ox, qy + 30.0), Color(acc, 0.88 * txt_a), 2.5, true)
	var qtxt := String(d["quote"])
	c.draw_string(f_med, Vector2(ox + 22.0, qy + 18.0), qtxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(INK, 0.94 * txt_a))
	c.draw_string(f_med, Vector2(ox + 20.0, qy + 16.0), qtxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(WHITE, 0.95 * txt_a))

	# 统计条 + 标签 + CTA（曜右侧加极薄暗黑曜石磨砂玻璃托底，彻底解决亮金钟面吃字！）
	var stat_x := (1390.0 - slide_x) if is_center else ox
	var by0 := 412.0 if is_center else 438.0
	if is_center:
		var panel_p := PackedVector2Array([
			Vector2(stat_x - 16.0, by0 - 18.0), Vector2(stat_x + 412.0, by0 - 18.0),
			Vector2(stat_x + 396.0, by0 + 132.0), Vector2(stat_x - 32.0, by0 + 132.0),
		])
		c.draw_colored_polygon(panel_p, Color(INK, 0.78 * txt_a))
		c.draw_polyline(PackedVector2Array([panel_p[0], panel_p[1], panel_p[2], panel_p[3], panel_p[0]]), Color(acc, 0.42 * txt_a), 1.2, true)
	for k in 3:
		var by := by0 + float(k) * 36.0
		var v := clampf(float(stat_vals[k]), 0.0, 1.0)
		c.draw_string(f_med, Vector2(stat_x + 2.0, by + 18.0), STAT_NAMES[k], HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color(INK, 0.94 * txt_a))
		c.draw_string(f_med, Vector2(stat_x, by + 16.0), STAT_NAMES[k], HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color(WHITE, 0.92 * txt_a))
		var bx := stat_x + 58.0
		var bw := 284.0
		c.draw_rect(Rect2(bx, by + 6.0, bw, 7.0), Color(WHITE, 0.16 * txt_a))
		var fw := maxf(4.0, bw * v)
		var fill_poly := PackedVector2Array([
			Vector2(bx + 4, by + 5.0), Vector2(bx + fw + 4, by + 5.0),
			Vector2(bx + fw, by + 13.0), Vector2(bx, by + 13.0),
		])
		c.draw_polygon(fill_poly, PackedColorArray([Color(acc.darkened(0.2), 0.94 * txt_a), Color(rim, 0.99 * txt_a), Color(rim, 0.99 * txt_a), Color(acc.darkened(0.2), 0.94 * txt_a)]))
		for ti in 5:
			var tx := bx + bw * float(ti + 1) / 5.0
			c.draw_line(Vector2(tx, by + 4.0), Vector2(tx, by + 14.0), Color(INK, 0.65 * txt_a), 1.4)
		var vtxt := "%02d" % int(round(v * 100.0))
		c.draw_string(f_lat, Vector2(bx + bw + 16.0, by + 18.0), vtxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(INK, 0.94 * txt_a))
		c.draw_string(f_lat, Vector2(bx + bw + 14.0, by + 16.0), vtxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(rim, 0.96 * txt_a))

	var tags: Array = d["tags"]
	var ty := 558.0 if is_center else 562.0
	var tx := stat_x
	for ti in tags.size():
		var ttxt := String(tags[ti])
		var tw := f_med.get_string_size(ttxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x + 32.0
		var poly := PackedVector2Array([
			Vector2(tx + 7, ty), Vector2(tx + tw, ty),
			Vector2(tx + tw - 7, ty + 34), Vector2(tx, ty + 34),
		])
		c.draw_colored_polygon(poly, Color(INK, 0.84 * txt_a))
		c.draw_polyline(PackedVector2Array([poly[0], poly[1], poly[2], poly[3], poly[0]]), Color(acc if ti == 0 else WHITE, (0.82 if ti == 0 else 0.30) * txt_a), 1.2, true)
		c.draw_string(f_med, Vector2(tx + 16, ty + 23), ttxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color(rim if ti == 0 else WHITE, 0.95 * txt_a))
		tx += tw + 12.0

	var lsh := sin(now * 78.0) * 12.0 * lock_shake * lock_shake
	var cx := stat_x + lsh
	var cy := 626.0 if is_center else 628.0
	var cw := 372.0 + cta_k * 20.0
	var ch := 74.0
	_cta_rect = Rect2(cx - 8.0, cy - 8.0, cw + 16.0, ch + 16.0)
	var skew := 14.0
	var btn := PackedVector2Array([
		Vector2(cx + skew, cy), Vector2(cx + cw, cy),
		Vector2(cx + cw - skew, cy + ch), Vector2(cx, cy + ch),
	])
	var btn_sh := PackedVector2Array()
	for bp in btn:
		btn_sh.append(bp + Vector2(8, 10))
	c.draw_colored_polygon(btn_sh, Color(INK, 0.90 * a))

	if playable:
		var bg_l := acc.darkened(0.28).lerp(acc, cta_k * 0.45)
		var bg_r := acc.lerp(WHITE, 0.16 + cta_k * 0.18)
		bg_l.a = 0.96 * a
		bg_r.a = 0.98 * a
		c.draw_polygon(btn, PackedColorArray([bg_l, bg_r, bg_r, bg_l]))
		var sp := fmod(now * 0.72, 1.0)
		var sx0 := cx + lerpf(-40.0, cw + 20.0, sp)
		var shine_a := sin(sp * PI) * 0.38 * a
		c.draw_line(Vector2(clampf(sx0, cx + 10, cx + cw - 10), cy + 2), Vector2(clampf(sx0 - 24.0, cx + 4, cx + cw - 12), cy + ch - 2), Color(1, 1, 1, shine_a), 24.0, true)
		c.draw_polyline(PackedVector2Array([btn[0], btn[1], btn[2], btn[3], btn[0]]), Color(WHITE, (0.78 + 0.22 * cta_k) * a), 1.8, true)
		var dm := Vector2(cx + 38.0, cy + ch * 0.5)
		c.draw_colored_polygon(PackedVector2Array([dm + Vector2(-8, 0), dm + Vector2(0, -8), dm + Vector2(8, 0), dm + Vector2(0, 8)]), Color(WHITE, a))
		c.draw_string(f_med, Vector2(cx + 66.0, cy + 48.0), "确认出战", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(WHITE, a))
		c.draw_string(f_lat, Vector2(cx + cw - 104.0, cy + 45.0), "ENTER", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(WHITE, 0.85 * a))
	else:
		c.draw_colored_polygon(btn, Color("#12131c", 0.90 * a))
		c.draw_polyline(PackedVector2Array([btn[0], btn[1], btn[2], btn[3], btn[0]]), Color(acc, (0.58 + 0.4 * lock_shake) * a), 1.5, true)
		c.draw_string(f_med, Vector2(cx + 34.0, cy + 47.0), "尚在光中 · 暂未解锁", HORIZONTAL_ALIGNMENT_LEFT, -1, 25, Color(rim, 0.88 * a))

	# 4. 四象眼神铭牌切换槽（随构图方向自动停泊于左下或右下！）
	var dock_x0 := 1340.0 if is_right else 92.0
	for i in DATA.size():
		var nd: Dictionary = DATA[i]
		var nacc: Color = nd["accent"]
		var is_on := i == idx
		var is_hov := i == hover_node
		var r0 := Rect2(dock_x0 + float(i) * 124.0, 822.0, 112.0, 126.0)
		_card_rects[i] = r0
		var lift := -14.0 if is_on else (-5.0 if is_hov else 0.0)
		var cr := Rect2(r0.position + Vector2(0.0, lift), r0.size)

		c.draw_rect(Rect2(cr.position + Vector2(5, 7), cr.size), Color(INK, 0.86 * a))
		var ft: Texture2D = _load_tex(String(nd["face"]))
		var fw := float(ft.get_width())
		var fh := float(ft.get_height())
		var uy: float = float(nd["face_uv_y"])
		var src := Rect2(fw * 0.14, fh * uy, fw * 0.72, fh * 0.50)
		var tint_f := Color(1.0, 1.0, 1.0, 0.98 * a) if is_on else Color(0.55, 0.56, 0.62, 0.78 * a)
		c.draw_texture_rect_region(ft, cr, src, tint_f)
		c.draw_rect(Rect2(cr.position.x, cr.end.y - 34.0, cr.size.x, 34.0), Color(INK, 0.82 * a))
		c.draw_rect(Rect2(cr.position.x, cr.position.y, cr.size.x, 4.0 if is_on else 2.0), Color(nacc, (0.98 if is_on else 0.45) * a))
		c.draw_rect(cr, Color(WHITE if is_on else nacc, (0.92 if is_on else 0.34) * a), false, 2.0 if is_on else 1.1)
		c.draw_string(f_med, Vector2(cr.position.x + 10.0, cr.end.y - 9.0), String(nd["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 22 if is_on else 19, Color(WHITE if is_on else Color("#b8bac8"), 0.98 * a))
		c.draw_string(f_lat, Vector2(cr.end.x - 32.0, cr.end.y - 10.0), String(nd["num"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(nacc.lerp(WHITE, 0.25), (0.95 if is_on else 0.55) * a))
