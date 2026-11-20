extends Node
## [YG-MARK] 首页《斩钟 · 5:59 裂口司辰》（保留原版三维钟 + 全套商业级界面/动效/机位/音效重构）
## 1. 保留三维哥特司辰钟本体，清除模糊拼缝底图、圆点网点、巨字底纹与漫画斜纹字标；
## 2. 换装 AI 手工《刀锋宋》字图，新增四位女主（朔紫 / 萤青 / 薇红 / 曜金）原生无损主色实时切换；
## 3. 废除紫潮 PPT 巨字遮罩，改用一镜到底真三维甩镜（Whip-Pan）连通四大空间机位；
## 4. 重做「四章登天纵轴」出击页（实装 9.49/10 影街母钟楼厚涂视窗）与纯黑净空完整设置页（含键鼠切换）；
## 5. 严格对齐《剧情与主题规划.md》：进关卡为「5:59 触底倒卷入夜」（废除 06:00 闪白），接入 MiniMax-H3 真钢刀鸣。

const ClockScript := preload("res://scripts/ui/yg_zhanzhong/zz_clock.gd")
const RosterScript := preload("res://scripts/ui/yg_zhanzhong/zz_roster_3d.gd")   # [YG-MARK] 角色选择：旗舰真三维《司辰四象 · 三维裂时殿堂》（旧版 zz_fan_cards.gd / zz_roster.gd / zz_hero_cards.gd 均保留未删）
const SelectScript := preload("res://scripts/ui/yg_zhanzhong/zz_select.gd")
const SettingsScript := preload("res://scripts/ui/yg_zhanzhong/zz_settings.gd")   # [YG-MARK] 设置页「白光定格」
const CineFxShader := preload("res://scripts/ui/yg_zhanzhong/zz_cine_fx.gdshader")   # [YG-MARK] 电影级色散/径向模糊/1帧冲击/宽银幕黑边后处理
const Factory := preload("res://scripts/night/player_factory.gd")
const GothicFonts := preload("res://scripts/ui/gothic_fonts.gd")
const IMG := "res://assets/image/yg_zhanzhong/"

class TitleUiRoot extends Control:
	var _serif: Font
	var _serif_light: Font
	var _gothic: Font
	var _menu_font: Font
	var _blackletter: Font
const AUD := "res://assets/audio/yg_zhanzhong/"
const SHARED_CFG := "user://settings.cfg"
const GRAPHICS_CFG := "user://graphics.cfg"
const TITLE_CFG := "user://title.cfg"

const W := 1920.0
const H := 1080.0
const DEG := PI / 180.0
const INK := Color("#08070c")
const WHITE := Color("#f5f2eb")
const MUTED := Color("#8e8c99")
const STEEL := Color("#5f6070")

# 四位平权女主专属主色（严格遵循《剧情与主题规划.md》：仅「夜鸦」朔拥有冷紫，其余三姝零紫色残留）
const HERO_ORDER := ["shuo", "ying", "wei", "yao"]
const HEROES := {
	"shuo": {
		"name": "朔", "title": "「夜鸦」朔", "note": "鸦黑直刃 · 冷紫裂口",
		"core": Color("#fbf7ff"), "bright": Color("#9366ff"), "mid": Color("#5224d6"),
		"deep": Color("#1d0a59"), "abyss": Color("#0a041f"), "ui": Color("#9d73ff"),
	},
	"ying": {
		"name": "萤", "title": "「惊风」萤", "note": "深青风刃 · 幽青流光",
		"core": Color("#f0fffd"), "bright": Color("#34e6d4"), "mid": Color("#0e8c84"),
		"deep": Color("#063a3e"), "abyss": Color("#031619"), "ui": Color("#46efe0"),
	},
	"wei": {
		"name": "薇", "title": "「残火」薇", "note": "烈红披风 · 赤金余烬",
		"core": Color("#fff6f2"), "bright": Color("#ff5b4c"), "mid": Color("#c41e30"),
		"deep": Color("#4d0914"), "abyss": Color("#1c0409"), "ui": Color("#ff6c5e"),
	},
	"yao": {
		"name": "曜", "title": "「破晓」曜", "note": "纯白圣枪 · 白炽流金",
		"core": Color("#fffdf2"), "bright": Color("#ffd863"), "mid": Color("#c78516"),
		"deep": Color("#4d2e05"), "abyss": Color("#1c1002"), "ui": Color("#ffe078"),
	},
}

# 四章登天纵轴 + 演武回廊（100% 对齐《剧情与主题规划.md》）；《拨钟选章》用 AI 场景图 + 刀锋宋章节字
const CHAPTERS := [
	{"tag": "第一章", "num": "I", "name": "影街", "sub": "司辰母钟楼", "unlocked": true,
		"scene": "res://scenes/rain_trial.tscn", "art": "bz_art_ch1", "word": "bz_name_ch1"},
	{"tag": "第二章", "num": "II", "name": "归晓大教堂", "sub": "上下双境 · 永恒圣枢", "unlocked": false,
		"scene": "", "art": "bz_art_ch2", "word": "bz_name_ch2"},
	{"tag": "第三章", "num": "III", "name": "浮空白城", "sub": "云海之上的雪白旧都", "unlocked": false,
		"scene": "", "art": "bz_art_ch3", "word": "bz_name_ch3"},
	{"tag": "终　章", "num": "IV", "name": "天顶裂口", "sub": "苍穹尽头的断口", "unlocked": false,
		"scene": "", "art": "bz_art_ch4", "word": "bz_name_ch4"},
	{"tag": "演　武", "num": "试", "name": "试剑回廊", "sub": "司辰残廊 · 自由练刀", "unlocked": true,
		"scene": "res://scenes/training.tscn", "art": "bz_art_train", "word": "bz_name_train"},
]

# [YG-MARK] 6 项完整 Steam 商业设置（全部在白光定格里以专属器物动态呈现，并与暂停菜单共享 settings.cfg）
const SET_ITEMS := [
	{"key": "master", "name": "总音量"},
	{"key": "bgm", "name": "音乐音量"},
	{"key": "fullscreen", "name": "全屏"},
	{"key": "vsync", "name": "垂直同步"},
	{"key": "supersample", "name": "超采样"},
	{"key": "scheme", "name": "操作方式"},
]
const KB_ACTIONS := [
	["移动", ["key/a", "key/d"], ["key/a", "key/d"], ["xboxseries/l_stick"]],
	["跳跃", ["key/w", "key/space"], ["key/w", "key/space"], ["xboxseries/a"]],
	["攻击", ["key/j"], ["mouse/left"], ["xboxseries/x"]],
	["弹刀", ["key/l"], ["key/e"], ["xboxseries/rb"]],
	["远射", ["key/k"], ["key/q"], ["xboxseries/y"]],
	["冲刺", ["key/shift"], ["mouse/right", "key/shift"], ["xboxseries/b"]],
	["大招", ["key/r"], ["key/r"], ["xboxseries/rt"]],
]

const HOME_POS_4 := [Vector2(1312, 366), Vector2(1284, 504), Vector2(1252, 628), Vector2(1220, 752)]
const HOME_POS_3 := [Vector2(1306, 404), Vector2(1272, 558), Vector2(1238, 708)]
const HOME_WORDS := ["df_start", "df_continue", "df_settings", "df_exit"]
const TW := -62.0

# 五大真实三维空间机位（不盖任何二维 PPT 遮罩）
var VIEW := {
	"home": {"hx": 950.0, "hy": 540.0, "z": 1.0, "seam": TW},
	"roster": {"hx": 740.0, "hy": 540.0, "z": 1.15, "seam": -54.0},
	"select": {"hx": 2230.0, "hy": 560.0, "z": 1.25, "seam": TW, "ang": [180.0, 180.0, 180.0, 180.0, 180.0]},
	"settings": {"hx": 1090.0, "hy": 470.0, "z": 1.3, "seam": -90.0},   # [YG-MARK] 白光定格：钟推近、压暗当背景
}
const LAUNCH_VIEW := {"hx": 950.0, "hy": 548.0, "z": 1.18}

# 11-17 开场（约 2.7 秒，任意键跳过）：
# 黑里五圈散在纵深中 → 三声「咔」一圈圈咬合归位（像上发条），镜头从侧面贴着环转到正面
# → 分针加速扫向 59、镜头后拉露出整钟 → 硬停、灯压暗 → 一刀：全屏白一帧 + 顿帧，钟沿斩缝劈成两块，
#   紫半边翻出去下沉再弹回，碎片朝镜头飞 → 「断」「晓」两半从斩缝两侧先后砸进来 → 一道刀光划过菜单，字依次亮起
const T_ASM := [0.28, 0.52, 0.76]     # 三声「咔」：外两圈 / 中两圈 / 中心机芯
const T_MIN0 := 0.80
const T_MIN1 := 1.20      # 分针撞上 5:59 硬停
const T_CUT := 1.30       # 斩
const T_MARK_L := 1.38    # 「断」那一半砸入
const T_MARK_R := 1.47    # 「晓」那一半砸入
const T_MENU := 1.74      # 刀光划过菜单
const T_SETTLE := 2.2
const T_END := 2.7
const RING_GROUP := [2, 1, 1, 0, 0]   # 每一圈在第几声「咔」归位（0 = 第一声）
const RING_SCATTER_Z := [-950.0, -520.0, 420.0, 780.0, 1150.0]
const RING_SCATTER_ROT := [2.4, -1.7, 1.2, -2.1, 1.6]
const RING_SCATTER_TILT := [Vector2(0.5, -0.9), Vector2(-0.7, 0.4), Vector2(0.9, 0.6), Vector2(-0.4, -1.0), Vector2(0.8, -0.5)]
# 主菜单拨号：每选一项，外圈转一个钟点、罗马数字圈反向半个钟点
const DIAL_STEP := [0.0, 0.0, 0.0, -15.0 * PI / 180.0, 30.0 * PI / 180.0]

var clock: Node3D
var env: WorldEnvironment
var ss_pref := false   # [YG-MARK] 超采样存档偏好：首页里 2D 超采样会盖住 3D 钟，改成给 3D 钟 2 倍渲染，离开首页再交回 Supersample
var ui: Control
var layer: CanvasLayer
var font_cn: Font
var font_cn_med: Font
var font_lat: Font

var hero := "shuo"
var accent := Color("#9d73ff")
var pal: Dictionary = HEROES["shuo"]

var screen := "intro"     # intro / home / select / settings / quit / launch
var busy := false
var t_scene := 0.0
var intro_t := 0.0
var hitstop := 0.0
var pulse := 0.0
var home_idx := 0
var ch_idx := 0
var set_idx := 0
var quit_idx := 0

var cam := {"hx": 950.0, "hy": 540.0, "z": 1.0, "r": 0.0}
var tween_cam := {}
var dolly := {"d": 0.0, "v": 0.0}
var kick := {"p": Vector2.ZERO, "v": Vector2.ZERO}
var light := {"a": -0.9, "v": 0.0}
var hand := {"a": 0.0, "v": 0.0}
var min_hand := {"a": 0.0, "v": 0.0}   # 分针（设置页拨音量）
var shake := {"p": Vector2.ZERO, "v": Vector2.ZERO}
var roll := {"p": 0.0, "v": 0.0}
var shock := {"p": 0.0, "v": 0.0}

var page_t0 := -10.0
var page_d0 := 0.08
var stuck_t0 := -10.0
var stuck_next := 1e9
var stuck_hit := true
var amt := {"home": 0.0, "roster": 0.0, "select": 0.0, "settings": 0.0, "quit": 0.0}
var has_save := false
var home_actions: Array = []    # 动态菜单动作 ["start", "settings", "exit"] 或含 "continue"
var home_pos: Array = []
var pointer := Vector2.ZERO
var pointer_goal := Vector2.ZERO
var mouse_last := Vector2(-1e9, -1e9)

var launch_t := -1.0
var launch_scene := ""
var launch_cam := {}
var last_pad := false
var flash_ui := 0.0
var dial_kick := 0.0      # 拨钟：齿轮被拨动的瞬时转速
var gear_extra := 0.0
# 11-17 钟动效：五圈各自的弹簧（转角）、擒纵累计、开锁演出
var ring_rot: Array = [0.0, 0.0, 0.0, 0.0, 0.0]
var ring_vel: Array = [0.0, 0.0, 0.0, 0.0, 0.0]
var ring_esc: Array = [0.0, 0.0, 0.0, 0.0, 0.0]
var ring_dz: Array = [0.0, 0.0, 0.0, 0.0, 0.0]
var ring_dzv: Array = [0.0, 0.0, 0.0, 0.0, 0.0]
var tick_n := -1
var tick_k := 0.0          # 擒纵那一下的余震（1 → 0）
var unlock_t0 := -10.0
var unlock_from: Array = []
var unlock_then := Callable()
var unlock_full := true
var cut_flash: ColorRect
var menu_streak: Polygon2D
var queued_input := ""     # 演出没完时按下的键，演完立刻执行

# 界面节点
var home_items: Array = []
var quit_items: Array = []
var blade: Dictionary = {}
var page_home: Control
var page_roster: Control
var page_select: Control
var page_settings: Control
var page_quit: Control
var home_scrim: Control
var ver_lb: Label

var hero_bar: Control       # [YG-MARK] 左下「表冠」：从屏幕底边露出的半个表冠，刻着四姝的色口
var crown_cur := 0.0        # 表冠当前转到第几格（不取模，连续转）
var crown_v := 0.0
var crown_goal := 0.0
var swap_t := -10.0
var swap_from := ""
var swap_dir := 1
const CROWN_C := Vector2(206, 1080)
const CROWN_R := 150.0
const CROWN_STEP := 40.0 * PI / 180.0
var flood: Control          # 换主角色：新颜色从钟的断缝里涌出来
var flood_t := -10.0
var hint_bar: Control       # [YG-MARK] 底边刻度尺 + 键帽
var hint_keys: Control
var hint_items: Array = []
var _icon_cache := {}

var roster: Control         # 《刀裂四分》（zz_roster.gd）
var sel: Control            # 《机关舞台选章》（zz_select.gd）
var _tex_cache := {}

var setm: Control   # [YG-MARK] 设置页模块 zz_settings.gd
var _gray_shader: Shader

var quit_band_edge: Polygon2D
var veil: ColorRect
var skip_lb: Label
var cine_layer: CanvasLayer
var cine_rect: ColorRect
var cine_mat: ShaderMaterial

# 音频（含原创首页主题曲 BGM 与实时低通滤波动态总线）
var sfx := {}
var rain: AudioStreamPlayer
var bgm: AudioStreamPlayer
var bgm_bus_idx := -1
var bgm_lpf: AudioEffectLowPassFilter = null
var _bgm_vol := 0.90
var _bgm_cutoff := 16000.0
var _vsync_pref := true
var _sfx_done := {}


func _ready() -> void:
	for v in VIEW.values():
		v["r"] = (float(v["seam"]) - TW) * DEG
	var s0 := ConfigFile.new()
	s0.load(SHARED_CFG)
	_init_hero(s0)
	_load_settings()
	_ss_enter()
	Factory.scheme() # 初始化当前控制方案

	env = WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = INK
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color.WHITE
	e.ambient_light_energy = 0.12
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	e.glow_enabled = true
	e.glow_intensity = 0.52
	e.glow_strength = 0.98
	e.glow_bloom = 0.0
	e.glow_hdr_threshold = 1.06
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	e.set_glow_level(0, 0.0)
	e.set_glow_level(1, 0.0)
	e.set_glow_level(2, 1.0)
	e.set_glow_level(3, 0.58)
	e.set_glow_level(4, 0.26)
	env.environment = e
	add_child(env)

	clock = ClockScript.new()
	add_child(clock)
	clock.build()
	hand["a"] = clock.REST
	min_hand["a"] = clock.TWELVE - clock.GAP
	clock.set_palette(pal)

	_build_ui()
	_build_audio()

	if OS.has_environment("ZZ_SKIP_INTRO"):
		_finish_intro()
	if OS.has_environment("ZZ_PREVIS"):
		var pv := "res://scripts/ui/yg_zhanzhong/lab/zz_previs.gd"
		match OS.get_environment("ZZ_PREVIS_SET"):
			"gear":
				pv = "res://scripts/ui/yg_zhanzhong/lab/zz_previs_gear.gd"
			"line":
				pv = "res://scripts/ui/yg_zhanzhong/lab/zz_previs_line.gd"
		add_child(load(pv).new())
	if OS.has_environment("ZZ_DEMO"):
		_demo_run.call_deferred()
	if OS.has_environment("ZZ_CAPTURE"):
		_capture_run.call_deferred(OS.get_environment("ZZ_CAPTURE"))
	elif OS.has_environment("ZZ_AUTOLAUNCH"):
		_finish_intro()
		get_tree().create_timer(0.8).timeout.connect(_launch.bind(int(OS.get_environment("ZZ_AUTOLAUNCH"))))
	if DisplayServer.get_name() != "headless":
		ResourceLoader.load_threaded_request(CHAPTERS[0]["scene"])


func _exit_tree() -> void:
	_ss_leave()
	if rain != null:
		rain.stop()
		rain.stream = null
	if bgm != null:
		bgm.stop()
		bgm.stream = null
	if bgm_bus_idx >= 0 and bgm_bus_idx < AudioServer.bus_count and AudioServer.get_bus_name(bgm_bus_idx) == "TitleBGM":
		AudioServer.remove_bus(bgm_bus_idx)
		bgm_bus_idx = -1
		bgm_lpf = null
	for k in sfx:
		var p: AudioStreamPlayer = sfx[k]
		if p != null:
			p.stop()
			p.stream = null
	for sc_path: String in [String(CHAPTERS[0]["scene"]), launch_scene]:
		if sc_path == "":
			continue
		var st := ResourceLoader.load_threaded_get_status(sc_path)
		if st == ResourceLoader.THREAD_LOAD_LOADED or st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			var _discard = ResourceLoader.load_threaded_get(sc_path)


# ================================================================ 资源与基础控件
func _tex(n: String) -> Texture2D:
	if _tex_cache.has(n):
		return _tex_cache[n]
	var p_png := IMG + n + ".png"
	var p_jpg := IMG + n + ".jpg"
	var t: Texture2D = load(p_png) if ResourceLoader.exists(p_png) else load(p_jpg)
	_tex_cache[n] = t
	return t


func _font(base_path: String, wght: int) -> FontVariation:
	var f := FontVariation.new()
	f.base_font = load(base_path)
	f.variation_opentype = {"wght": wght}
	return f


func _label(text: String, size: int, color: Color = WHITE, shadow: bool = true) -> Label:
	var lb := Label.new()
	lb.text = text
	lb.add_theme_font_override("font", font_cn)
	lb.add_theme_font_size_override("font_size", size)
	lb.add_theme_color_override("font_color", color)
	if shadow:
		lb.add_theme_color_override("font_shadow_color", INK)
		lb.add_theme_constant_override("shadow_offset_x", 3)
		lb.add_theme_constant_override("shadow_offset_y", 4)
	lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lb


func _word(parent: Control, name: String) -> Dictionary:
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(root)
	var t := _tex(name)
	var sh := TextureRect.new()
	sh.texture = t
	sh.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sh.stretch_mode = TextureRect.STRETCH_SCALE
	sh.modulate = Color(INK, 0.94)
	sh.position = Vector2(6, 7)
	var im := TextureRect.new()
	im.texture = t
	im.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	im.stretch_mode = TextureRect.STRETCH_SCALE
	root.add_child(sh)
	root.add_child(im)
	var d := {
		"root": root, "img": im, "sh": sh,
		"aspect": float(t.get_width()) / float(t.get_height()),
		"pos": Vector2.ZERO, "h": 70.0, "goal_pos": Vector2.ZERO, "goal_h": 70.0,
		"on": 0.0, "punch": 0.0,
	}
	return d


# ================================================================ 界面搭建
func _build_ui() -> void:
	font_cn = GothicFonts.serif(900)
	font_cn_med = GothicFonts.serif(600)
	font_lat = GothicFonts.cinzel(700)

	layer = CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	var ui_root := TitleUiRoot.new()
	ui_root._serif = font_cn
	ui_root._serif_light = GothicFonts.serif(450)
	ui_root._gothic = font_lat
	ui_root._menu_font = font_cn_med
	ui_root._blackletter = GothicFonts.blackletter()
	ui = ui_root
	ui.size = Vector2(W, H)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui)

	# [YG-MARK] 选中项底牌 = 一截刀身的截面：刀镡色块固定在左，刀身从里面拔出来；
	# 上沿刀背偏灰、中间白钢面、下沿刃口一线主角色，右端斜斩断口露出钢的厚度
	var bn := Node2D.new()
	ui.add_child(bn)
	var inner := Node2D.new()
	bn.add_child(inner)
	blade = _new_blade(bn, inner, Vector2(560, 140))
	inner.draw.connect(_draw_blade.bind(blade))

	# ---------------- 1. 首页 ----------------
	page_home = Control.new()
	page_home.size = Vector2(W, H)
	page_home.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(page_home)
	# 菜单右列背后垫一层克制的暗墨柔化呼吸区，让未选中项在繁密齿轮上依然锐利可读
	home_scrim = Control.new()
	home_scrim.size = Vector2(W, H)
	home_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	home_scrim.draw.connect(_draw_home_scrim)
	page_home.add_child(home_scrim)

	has_save = FileAccess.file_exists("user://run_save.cfg") or FileAccess.file_exists("user://save.json")
	if has_save:
		home_actions = ["continue", "start", "settings", "exit"]
		home_pos = HOME_POS_4.duplicate()
		for w_name in ["df_continue", "df_start", "df_settings", "df_exit"]:
			home_items.append(_word(page_home, w_name))
	else:
		# 商业大作标配：零存档时干净收起「继续」，避免死按钮与大块“暂无存档”喧宾夺主
		home_actions = ["start", "settings", "exit"]
		home_pos = HOME_POS_3.duplicate()
		for w_name in ["df_start", "df_settings", "df_exit"]:
			home_items.append(_word(page_home, w_name))

	# 极简正式商品版本铭文（左下角安静留白处，替代原先突兀的半圆表冠）
	ver_lb = _label("NIGHTCROW  ·  v0.5", 18, Color(WHITE, 0.34), false)
	ver_lb.add_theme_font_override("font", font_lat)
	ver_lb.position = Vector2(56, 1024)
	page_home.add_child(ver_lb)

	# 保留 hero_bar 节点引用兼容旧回调，但视觉完全隐藏（主角切换全面升级为独立「刀裂四分」角色选择页！）
	hero_bar = Control.new()
	hero_bar.visible = false
	hero_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(hero_bar)
	crown_cur = float(HERO_ORDER.find(hero))
	crown_goal = crown_cur

	# 换色时从断缝涌出的颜色（叠加混合，压在所有字下面）
	flood = Control.new()
	flood.size = Vector2(W, H)
	flood.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fm := CanvasItemMaterial.new()
	fm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	flood.material = fm
	flood.draw.connect(_draw_flood)
	flood.visible = false
	ui.add_child(flood)
	ui.move_child(flood, 0)

	ui.move_child(bn, ui.get_child_count() - 1)
	ui.move_child(page_home, ui.get_child_count() - 1)

	# ---------------- 1.5. 角色选择 · 《刀裂四分》 ----------------
	page_roster = Control.new()
	page_roster.size = Vector2(W, H)
	page_roster.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(page_roster)
	roster = RosterScript.new()
	page_roster.add_child(roster)
	roster.setup(self)

	# ---------------- 2. 出击 · 《机关舞台选章》 ----------------
	page_select = Control.new()
	page_select.size = Vector2(W, H)
	page_select.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(page_select)
	sel = SelectScript.new()
	page_select.add_child(sel)
	sel.setup(self, CHAPTERS)

	# ---------------- 3. 设置 · 白光定格 ----------------
	page_settings = Control.new()
	page_settings.size = Vector2(W, H)
	page_settings.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(page_settings)

	setm = SettingsScript.new()
	page_settings.add_child(setm)
	setm.setup(self, SET_ITEMS, KB_ACTIONS)

	# ---------------- 4. 退出确认 · 合表断拍 ----------------
	page_quit = Control.new()
	page_quit.size = Vector2(W, H)
	page_quit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(page_quit)
	var dim := ColorRect.new()
	dim.color = Color(0.015, 0.012, 0.025, 0.80)
	dim.size = Vector2(W * 1.6, H * 1.6)
	dim.position = Vector2(-W * 0.3, -H * 0.3)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page_quit.add_child(dim)
	var quit_body := Polygon2D.new()
	quit_body.polygon = PackedVector2Array([Vector2(1062, 466), Vector2(W + 40, 442), Vector2(W + 40, 816), Vector2(1020, 840)])
	quit_body.color = Color(INK, 0.50)
	page_quit.add_child(quit_body)
	var band := Polygon2D.new()
	band.polygon = PackedVector2Array([Vector2(1090, 268), Vector2(W + 40, 240), Vector2(W + 40, 444), Vector2(1062, 468)])
	band.color = Color(INK, 0.96)
	page_quit.add_child(band)
	quit_band_edge = Polygon2D.new()
	quit_band_edge.polygon = PackedVector2Array([Vector2(1062, 468), Vector2(W + 40, 444), Vector2(W + 40, 452), Vector2(1060, 476)])
	quit_band_edge.color = accent
	page_quit.add_child(quit_band_edge)
	var q := TextureRect.new()
	q.texture = _tex("df_quit_game")
	q.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	q.size = Vector2(94.0 * q.texture.get_width() / q.texture.get_height(), 94.0)
	q.position = Vector2(1156, 298)
	page_quit.add_child(q)
	var q_sub := _label("今夜尚未斩断五点五十九分 · 确认返回桌面？", 24, Color(WHITE, 0.78), false)
	q_sub.add_theme_font_override("font", font_cn_med)
	q_sub.position = Vector2(1162, 404)
	page_quit.add_child(q_sub)
	for n in ["df_stay", "df_exit"]:
		quit_items.append(_word(page_quit, n))
	# 确保退出页选中白刃可见：把白刃排到 page_quit 内部紧随背景之后，或切状态控制层级
	# 这里保持 blade 在 page_home 前，quit 时动态调整子节点顺序

	# 底边刻度尺：刻度线跟着钟的擒纵每秒走一格，键帽灰度化成银色
	hint_bar = Control.new()
	hint_bar.size = Vector2(W, H)
	hint_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_bar.draw.connect(_draw_hint_bar)
	ui.add_child(hint_bar)
	hint_keys = Control.new()
	hint_keys.size = Vector2(W, H)
	hint_keys.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_keys.draw.connect(_draw_hint_keys)
	hint_keys.material = _gray_mat()
	ui.add_child(hint_keys)

	skip_lb = _label("按任意键跳过", 23, Color(WHITE, 0.52), true)
	skip_lb.add_theme_font_override("font", font_cn_med)
	skip_lb.position = Vector2(1690, 1012)
	ui.add_child(skip_lb)

	# 进关卡深渊暗幕（严格遵照总纲：5:59 触底倒卷入夜，深墨无缝切入夜街，绝不闪白！）
	veil = ColorRect.new()
	veil.color = Color(0.025, 0.024, 0.04, 0.0)
	veil.size = Vector2(W, H)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(veil)

	# 开场：斩那一帧的全屏白；刀光划过菜单
	menu_streak = Polygon2D.new()
	menu_streak.color = Color(1, 1, 1, 0)
	var streak_glow := Polygon2D.new()
	streak_glow.show_behind_parent = true
	menu_streak.add_child(streak_glow)
	ui.add_child(menu_streak)
	cut_flash = ColorRect.new()
	cut_flash.color = Color(1, 1, 1, 0)
	cut_flash.size = Vector2(W, H)
	cut_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(cut_flash)

	ui.move_child(hero_bar, ui.get_child_count() - 1)
	ui.move_child(hint_bar, ui.get_child_count() - 1)
	ui.move_child(hint_keys, ui.get_child_count() - 1)
	ui.move_child(veil, ui.get_child_count() - 1)

	# 电影级全屏后处理层（仅在三维选角/选章爆发瞬间激活，常态首页与设置页自动关闭零开销！）
	cine_layer = CanvasLayer.new()
	cine_layer.layer = 18
	add_child(cine_layer)
	cine_mat = ShaderMaterial.new()
	cine_mat.shader = CineFxShader
	cine_rect = ColorRect.new()
	cine_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	cine_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cine_rect.material = cine_mat
	cine_rect.visible = false
	cine_layer.add_child(cine_rect)

	_layout_all(true)


func _build_audio() -> void:
	for n in ["ui_move", "ui_back", "ult_cut_0", "ult_cut_2", "ult_impact", "ult_push", "ult_sheathe"]:
		var p := AudioStreamPlayer.new()
		p.stream = load(AUD + n + ".ogg")
		p.bus = "Master"
		add_child(p)
		sfx[n] = p
	for wn: String in ["h3_slash_heavy", "h3_slash_fast", "h3_unsheathe", "h3_parry_lock", "h3_anvil_bell"]:
		var wp: String = AUD + wn + ".wav"
		if ResourceLoader.exists(wp):
			var p := AudioStreamPlayer.new()
			p.stream = load(wp)
			p.bus = "Master"
			add_child(p)
			sfx[wn] = p
	rain = AudioStreamPlayer.new()
	var s := load(AUD + "rain_bed.ogg") as AudioStreamOggVorbis
	if s:
		s.loop = true
	rain.stream = s
	rain.volume_db = -60.0
	add_child(rain)

	# 原创哥特室内乐首页主题曲（独立 TitleBGM 总线 + 实时低通滤波，切页平滑闷化/打开）
	var bgm_path := AUD + "title_bgm.ogg"
	if ResourceLoader.exists(bgm_path):
		bgm_bus_idx = AudioServer.get_bus_index("TitleBGM")
		if bgm_bus_idx < 0:
			AudioServer.add_bus()
			bgm_bus_idx = AudioServer.bus_count - 1
			AudioServer.set_bus_name(bgm_bus_idx, "TitleBGM")
			AudioServer.set_bus_send(bgm_bus_idx, "Master")
			bgm_lpf = AudioEffectLowPassFilter.new()
			bgm_lpf.cutoff_hz = 16000.0
			bgm_lpf.resonance = 0.55
			AudioServer.add_bus_effect(bgm_bus_idx, bgm_lpf)
		else:
			if AudioServer.get_bus_effect_count(bgm_bus_idx) > 0:
				bgm_lpf = AudioServer.get_bus_effect(bgm_bus_idx, 0) as AudioEffectLowPassFilter
		bgm = AudioStreamPlayer.new()
		var bs := load(bgm_path) as AudioStreamOggVorbis
		if bs:
			bs.loop = true
		bgm.stream = bs
		bgm.bus = "TitleBGM"
		bgm.volume_db = -40.0
		add_child(bgm)
	_apply_bgm_vol()

	if DisplayServer.get_name() != "headless":
		rain.play()
		if bgm != null:
			bgm.play()


func _draw_home_scrim() -> void:
	# 1. 右侧菜单柔羽化暗场衬托（让黑曜锻钢刀锋与字标在三维钟盘上锐利通透）
	for k in range(6, 0, -1):
		var pad := float(k) * 36.0
		var a := 0.068 * (1.0 - float(k - 1) / 6.5)
		var pts := PackedVector2Array([
			Vector2(1210.0 - pad, 300.0 - pad * 0.7), Vector2(W + 40.0, 280.0 - pad * 0.7),
			Vector2(W + 40.0, 790.0 + pad * 0.7), Vector2(1150.0 - pad, 810.0 + pad * 0.7),
		])
		home_scrim.draw_colored_polygon(pts, Color(INK, a))

	# 2. 主标题《断晓》下方精刻商业标题铭尺（破除左半纯黑空洞，建立 3A 发售版封面厚重感！）
	var lx := 112.0
	var ly := 696.0
	var lw := 470.0
	home_scrim.draw_line(Vector2(lx, ly), Vector2(lx + lw, ly), Color(WHITE, 0.24), 1.2, true)
	home_scrim.draw_line(Vector2(lx, ly), Vector2(lx + 118.0, ly), Color(accent, 0.92), 2.4, true)
	# 细微司辰刻度
	for ti in 19:
		var tx := lx + float(ti) * (lw / 18.0)
		var maj := ti % 6 == 0
		home_scrim.draw_line(Vector2(tx, ly), Vector2(tx, ly + (8.0 if maj else 4.0)), Color(WHITE, 0.36 if maj else 0.14), 1.0)
	var dm := Vector2(lx + 6.0, ly + 30.0)
	home_scrim.draw_colored_polygon(PackedVector2Array([dm + Vector2(-6, 0), dm + Vector2(0, -6), dm + Vector2(6, 0), dm + Vector2(0, 6)]), Color(accent.lerp(WHITE, 0.25), 0.96))
	home_scrim.draw_string(font_lat, Vector2(lx + 24.0, ly + 36.0), "NIGHTCROW   ·   05:59", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(WHITE, 0.76))
	var h_title := String(pal.get("title", "「夜鸦」朔"))
	home_scrim.draw_string(font_cn_med, Vector2(lx + 306.0, ly + 36.0), h_title, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(accent.lerp(WHITE, 0.32), 0.86))

	# 3. 主菜单每项左侧极细冷钢序号标（01 / 02 / 03，与右侧三维钟擒纵同步微呼吸）
	for i in home_items.size():
		var it: Dictionary = home_items[i]
		var pos: Vector2 = it["pos"]
		var on := i == home_idx
		var nx := pos.x - (68.0 if on else 52.0)
		var ny := pos.y + 8.0
		var num_s := "0%d" % (i + 1)
		home_scrim.draw_string(font_lat, Vector2(nx, ny), num_s, HORIZONTAL_ALIGNMENT_LEFT, -1, 17 if on else 14, Color(accent.lerp(WHITE, 0.35) if on else Color(WHITE, 0.34), 0.95 if on else 0.72))


func _play(n: String, vol_db: float = 0.0, pitch: float = 1.0) -> void:
	var p: AudioStreamPlayer = sfx.get(n)
	if p == null:
		return
	p.volume_db = vol_db
	p.pitch_scale = pitch
	p.play()


# ================================================================ 自绘高精度商业界面（章节纵轴 / 实景框 / 暗夜设置 / 四姝切换槽）
func _slanted_box(r: Rect2, slant: float = 14.0) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(r.position.x + slant, r.position.y),
		Vector2(r.end.x + slant, r.position.y),
		Vector2(r.end.x, r.end.y),
		Vector2(r.position.x, r.end.y),
	])


func _arc_pts(c: Vector2, r: float, a0: float, a1: float, n: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n + 1:
		var a := lerpf(a0, a1, float(i) / float(n))
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts


func _ring_poly(c: Vector2, r0: float, r1: float, a0: float, a1: float, n: int) -> PackedVector2Array:
	var outer := _arc_pts(c, r1, a0, a1, n)
	var inner := _arc_pts(c, r0, a1, a0, n)
	outer.append_array(inner)
	return outer


## 表冠：屏幕底边露出的半个表冠。外圈滚花、四个主角色色口（当前的那个在正上方、伸出来），
## 中间只写当前主角的一个大字；换人时表冠转一格「咔」，旧字跟着转走，新字砸进来
func _draw_hero_bar() -> void:
	var c := hero_bar
	var C := CROWN_C
	var R := CROWN_R
	var a0 := PI + 0.02
	var a1 := TAU - 0.02
	var rot := crown_cur * CROWN_STEP
	# 底盘
	c.draw_colored_polygon(_ring_poly(C, 0.0, R + 18.0, a0, a1, 48), Color(INK, 0.55))
	c.draw_colored_polygon(_ring_poly(C, 0.0, R, a0, a1, 48), Color(0.03, 0.028, 0.045, 0.94))
	c.draw_colored_polygon(_ring_poly(C, 0.0, R * 0.82, a0, a1, 48), Color((pal["deep"] as Color), 0.55))
	c.draw_arc(C, R * 0.82, a0, a1, 48, Color(accent, 0.35), 1.4, true)
	# 外圈滚花（随表冠转）
	c.draw_colored_polygon(_ring_poly(C, R, R + 15.0, a0, a1, 48), Color("#2a2833"))
	var kn := 60
	for i in kn:
		var a := float(i) / kn * TAU + rot * 0.5
		var aw := wrapf(a, 0.0, TAU)
		if aw < a0 + 0.03 or aw > a1 - 0.03:
			continue
		var d := Vector2(cos(aw), sin(aw))
		var lit := 0.55 + 0.45 * maxf(0.0, -d.y)
		c.draw_line(C + d * (R + 2.0), C + d * (R + 13.0), Color("#9a98a6") * Color(1, 1, 1, lit), 2.0, true)
	c.draw_arc(C, R + 15.0, a0, a1, 48, Color("#b9b7c4"), 1.6, true)
	# 内刻度
	for i in 49:
		var a := lerpf(a0, a1, float(i) / 48.0)
		var d := Vector2(cos(a), sin(a))
		var big := i % 6 == 0
		c.draw_line(C + d * (R - (14.0 if big else 8.0)), C + d * (R - 2.0), Color(WHITE, 0.42 if big else 0.18), 1.6 if big else 1.0, true)
	# 四个色口
	var cur_i := HERO_ORDER.find(hero)
	for i in HERO_ORDER.size():
		var dd := wrapf(float(i) - crown_cur, -2.0, 2.0)
		var a := -PI * 0.5 + dd * CROWN_STEP
		var vis := clampf((2.0 - absf(dd)) / 0.45, 0.0, 1.0)
		if vis <= 0.01:
			continue
		var on := i == cur_i
		var hp: Dictionary = HEROES[HERO_ORDER[i]]
		var col: Color = hp["ui"]
		var hw := (0.085 if on else 0.055)
		var rin := R - 4.0
		var rout := R + (30.0 if on else 19.0)
		var wedge := PackedVector2Array([
			C + Vector2(cos(a - hw), sin(a - hw)) * rin, C + Vector2(cos(a - hw * 0.7), sin(a - hw * 0.7)) * rout,
			C + Vector2(cos(a + hw * 0.7), sin(a + hw * 0.7)) * rout, C + Vector2(cos(a + hw), sin(a + hw)) * rin,
		])
		c.draw_colored_polygon(wedge, Color(col, (1.0 if on else 0.5) * vis))
		if on:
			c.draw_polyline(wedge, Color(WHITE, 0.85 * vis), 1.4, true)
	# 正上方的指针
	var tp := C + Vector2(0, -(R + 36.0))
	c.draw_colored_polygon(PackedVector2Array([tp + Vector2(-9, -12), tp + Vector2(9, -12), tp + Vector2(0, 2)]), WHITE)
	# 大字：旧字随表冠转走，新字砸进来
	var sp := clampf((t_scene - swap_t) / 0.32, 0.0, 1.0)
	var fs := 92
	var base := C + Vector2(0, -96)
	if sp < 1.0 and swap_from != "" and HEROES.has(swap_from):
		var ho: Dictionary = HEROES[swap_from]
		var ang := -float(swap_dir) * 0.9 * _in_out(sp)
		_draw_crown_char(String(ho["name"]), ho["ui"], base, ang, 1.0 - sp * 0.3, 1.0 - sp, fs)
	var hp_now: Dictionary = HEROES[hero]
	var ein := clampf(sp / 0.75, 0.0, 1.0)
	var sc := 1.0 + 0.4 * pow(1.0 - ein, 3.0) if sp < 1.0 else 1.0
	var ang_in := float(swap_dir) * 0.7 * pow(1.0 - ein, 3.0) if sp < 1.0 else 0.0
	_draw_crown_char(String(hp_now["name"]), hp_now["ui"], base, ang_in, sc, ein if sp < 1.0 else 1.0, fs)


func _draw_crown_char(ch: String, col: Color, at: Vector2, ang: float, sc: float, a: float, fs: int) -> void:
	if a <= 0.01:
		return
	var c := hero_bar
	var sz := font_cn.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	# 绕表冠中心转，所以把旋转原点放在表冠中心
	var piv := CROWN_C
	var local := at - piv
	c.draw_set_transform(piv + local.rotated(ang), ang, Vector2(sc, sc))
	var o := Vector2(-sz.x * 0.5, sz.y * 0.32)
	c.draw_string(font_cn, o + Vector2(5, 6), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(INK, 0.95 * a))
	c.draw_string_outline(font_cn, o, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(col.lerp(WHITE, 0.12), a))
	c.draw_string(font_cn, o, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(col.lerp(WHITE, 0.12), a))
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_flood() -> void:
	var p := clampf((t_scene - flood_t) / 0.55, 0.0, 1.0)
	if p >= 1.0:
		return
	# 首页机位下断缝在屏幕上的走向
	var A := Vector2(1236, -60)
	var B := Vector2(640, 1140)
	var n := (B - A).normalized().orthogonal()
	var e := 1.0 - pow(1.0 - p, 3.0)
	var wd := 30.0 + 1150.0 * e
	var al := 0.62 * pow(1.0 - p, 1.4)
	var ac := Color(accent, al)
	var z := Color(accent, 0.0)
	flood.draw_polygon(PackedVector2Array([A - n * wd, A, B, B - n * wd]), PackedColorArray([z, ac, ac, z]))
	flood.draw_polygon(PackedVector2Array([A, A + n * wd, B + n * wd, B]), PackedColorArray([ac, z, z, ac]))
	var core := 9.0 * (1.0 - p)
	var wc := Color(1, 1, 1, 0.9 * (1.0 - p))
	flood.draw_polygon(PackedVector2Array([A - n * core, A + n * core, B + n * core, B - n * core]), PackedColorArray([wc, wc, wc, wc]))


## 键帽贴图灰度化成银色（插件原图是深灰键帽 + 彩色 A/B，和这套哥特银不搭）
func _gray_mat() -> ShaderMaterial:
	if _gray_shader == null:
		_gray_shader = Shader.new()
		_gray_shader.code = """shader_type canvas_item;
varying vec4 vc;
void vertex() { vc = COLOR; }
void fragment() {
	vec4 t = texture(TEXTURE, UV);
	float l = smoothstep(0.12, 0.92, dot(t.rgb, vec3(0.299, 0.587, 0.114)));
	COLOR = vec4(vec3(l) * vc.rgb, t.a * vc.a);
}"""
	var m := ShaderMaterial.new()
	m.shader = _gray_shader
	return m


func _icon(path: String) -> Texture2D:
	if not _icon_cache.has(path):
		_icon_cache[path] = load("res://addons/controller_icons/assets/" + path + ".png")
	return _icon_cache[path]


func _hint_list() -> Array:
	var pad := last_pad
	var nav := ["xboxseries/dpad"] if pad else ["key/arrow_up", "key/arrow_down"]
	var nav_lr := ["xboxseries/dpad"] if pad else ["key/arrow_left", "key/arrow_right"]
	var ok := ["xboxseries/a"] if pad else ["key/enter_alt"]
	var bk := ["xboxseries/b"] if pad else ["key/esc"]
	match "home" if screen == "intro" else screen:
		"home": return [[nav, "选择"], [ok, "确认"]]
		"roster":
			if roster != null and roster.is_playable():
				return [[nav_lr, "切换主角"], [ok, "确认出战"], [bk, "返回"]]
			return [[nav_lr, "切换主角"], [bk, "返回"]]
		"quit": return [[nav, "选择"], [ok, "确认"], [bk, "取消"]]
		"select":
			if sel != null and sel.idx < sel.chapters.size() and bool(sel.chapters[sel.idx]["unlocked"]):
				return [[nav, "选章"], [ok, "开始出击"], [bk, "返回"]]
			return [[nav, "选章"], [bk, "返回"]]
		"settings": return [[nav, "选择"], [nav_lr, "调节"], [bk, "返回"]]
	return []


## 底边刻度尺：从右往左排键帽 + 字；刻度跟着擒纵每秒向右走一小格
func _hint_layout() -> Array:
	var out := []
	var x := W - 64.0
	var ic := 44.0
	var list := _hint_list()
	for k in range(list.size() - 1, -1, -1):
		var keys: Array = list[k][0]
		var txt: String = list[k][1]
		var tw := font_cn_med.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
		x -= tw
		var tx := x
		x -= 10.0
		var kx := []
		for j in range(keys.size() - 1, -1, -1):
			x -= ic
			kx.push_front(x)
			x -= 2.0
		out.push_front({"keys": keys, "kx": kx, "tx": tx, "txt": txt})
		x -= 46.0
	return out


func _draw_hint_bar() -> void:
	var c := hint_bar
	if hint_items.is_empty():
		return
	var x0 := float((hint_items[0]["kx"] as Array)[0]) - 74.0
	var y := 1060.0
	c.draw_colored_polygon(PackedVector2Array([Vector2(x0 - 44, 996), Vector2(W, 996), Vector2(W, H), Vector2(x0 - 86, H)]), Color(INK, 0.80))
	c.draw_line(Vector2(x0, y), Vector2(W - 28, y), Color(WHITE, 0.42), 1.4, true)
	var off := 14.0 * (float(posmod(tick_n, 5)) - 1.0 + (1.0 - tick_k * tick_k))
	var x := x0 + fposmod(off, 70.0) - 70.0
	var i := 0
	while x < W - 28:
		if x >= x0:
			var major := posmod(i, 5) == 0
			c.draw_line(Vector2(x, y), Vector2(x, y - (10.0 if major else 5.0)), Color(WHITE, 0.42 if major else 0.22), 1.2, true)
		x += 14.0
		i += 1
	for it in hint_items:
		var kx: Array = it["kx"]
		var mid := (float(kx[0]) + float(kx[kx.size() - 1]) + 44.0) * 0.5
		c.draw_line(Vector2(mid, y + 1), Vector2(mid, y - 15), accent, 2.6, true)
		c.draw_string(font_cn_med, Vector2(float(it["tx"]) + 2, 1039), String(it["txt"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(INK, 0.95))
		c.draw_string(font_cn_med, Vector2(float(it["tx"]), 1037), String(it["txt"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color("#eeeff6"))


func _draw_hint_keys() -> void:
	for it in hint_items:
		var keys: Array = it["keys"]
		var kx: Array = it["kx"]
		for j in keys.size():
			hint_keys.draw_texture_rect(_icon(String(keys[j])), Rect2(float(kx[j]), 1004.0, 44.0, 44.0), false, Color("#e2e2ea"))


func _set_value_text(key: String) -> String:
	match key:
		"master": return "%d" % (roundi(master_volume() * 10.0) * 10)
		"bgm": return "%d" % (roundi(bgm_volume() * 10.0) * 10)
		"fullscreen": return "开" if is_fullscreen() else "关"
		"vsync": return "开" if vsync_on() else "关"
		"supersample": return "开" if supersample_on() else "关"
		"scheme": return "纯键盘" if Factory.scheme() == Factory.SCHEME_KEYBOARD else "键鼠"
	return ""


# ================================================================ 布局刷新
func _layout_all(snap: bool = false) -> void:
	for i in home_items.size():
		var it: Dictionary = home_items[i]
		var on := i == home_idx
		it["goal_h"] = 104.0 if on else 74.0
		it["goal_pos"] = (home_pos[i] as Vector2) + Vector2(26 if on else 0, 0)
	for i in quit_items.size():
		var it: Dictionary = quit_items[i]
		var on := i == quit_idx
		it["goal_h"] = 98.0 if on else 72.0
		it["goal_pos"] = Vector2(1180, 562 + i * 134) + Vector2(26 if on else 0, 0)

	# 确保选中白刃在 quit 页也能垫在 quit_items 之下、dim 之上
	if screen == "quit":
		if blade["node"].get_parent() != page_quit:
			blade["node"].reparent(page_quit, false)
			page_quit.move_child(blade["node"], 4)
	else:
		if blade["node"].get_parent() != ui:
			blade["node"].reparent(ui, false)
			ui.move_child(blade["node"], page_home.get_index())

	hero_bar.queue_redraw()

	if snap:
		for arr in [home_items, quit_items]:
			for it in arr:
				it["pos"] = it["goal_pos"]
				it["h"] = it["goal_h"]


func _active_list() -> Array:
	match screen:
		"home": return home_items
		"quit": return quit_items
	return []


func _active_idx() -> int:
	match screen:
		"home": return home_idx
		"quit": return quit_idx
		"select": return ch_idx
		"settings": return set_idx
	return 0


# ================================================================ 每帧更新
func _process(delta: float) -> void:
	var dt := minf(delta, 1.0 / 20.0)
	_fit()
	_ss_watch()
	if hitstop > 0.0:
		hitstop -= dt
		_step_ui(dt * 0.15)
		if screen == "launch":
			clock.update(_launch_state(t_scene - launch_t))
		elif screen != "intro":
			clock.update(_live_state())
		sel.post_layout()
		return

	t_scene += dt
	pulse = maxf(0.0, pulse - dt * 3.4)
	_step_stuck()

	if screen == "intro":
		intro_t += dt
		_intro_sfx(intro_t)
		if intro_t >= T_END:
			_finish_intro()

	pointer = pointer.lerp(pointer_goal, minf(1.0, dt * 3.2))
	for k in amt:
		var goal := 1.0 if screen == k or (k == "home" and screen == "quit") else 0.0
		amt[k] = lerpf(amt[k], goal, minf(1.0, dt * (11.0 if goal > 0.5 else 17.0)))

	_step_cam(dt)
	_step_springs(dt)
	_step_rings(dt)
	_step_ui(dt)
	if queued_input != "" and not busy and screen in ["home", "roster", "select", "settings", "quit"]:
		var qi := queued_input
		queued_input = ""
		match qi:
			"accept": _accept()
			"back": _back()
			"up": _move(-1)
			"down": _move(1)
			"left": _adjust(-1)
			"right": _adjust(1)

	if screen == "intro":
		clock.update(_intro_state(intro_t))
	elif screen == "launch":
		clock.update(_launch_state(t_scene - launch_t))
	else:
		clock.update(_live_state())
	sel.post_layout()
	_step_cine_fx()

	var rv := clampf(intro_t / 0.7, 0.0, 1.0) if screen == "intro" else 1.0
	rain.volume_db = lerpf(-40.0, -16.0, rv) if screen != "launch" else lerpf(-16.0, -28.0, clampf((t_scene - launch_t) / 1.1, 0, 1))
	# 原创首页主题曲实时动态混音（主页晶莹敞开 / 选人选章聚焦 / 设置页白光闷化 / 进关倒卷下潜）
	if bgm != null:
		var bgm_gain := clampf(intro_t / 1.2, 0.0, 1.0) if screen == "intro" else (1.0 - clampf((t_scene - launch_t) / 1.15, 0.0, 1.0) if screen == "launch" else 1.0)
		var base_db := linear_to_db(maxf(_bgm_vol * bgm_gain, 0.0001)) - 4.5
		bgm.volume_db = lerpf(bgm.volume_db, base_db, minf(1.0, dt * 8.0))
		if bgm_lpf != null:
			var target_hz := 16000.0
			match screen:
				"roster": target_hz = 6400.0
				"select": target_hz = 5200.0
				"settings": target_hz = 1150.0
				"quit": target_hz = 2200.0
				"launch": target_hz = 620.0
			_bgm_cutoff = lerpf(_bgm_cutoff, target_hz, minf(1.0, dt * 6.0))
			bgm_lpf.cutoff_hz = _bgm_cutoff


func _step_cine_fx() -> void:
	if cine_rect == null or cine_mat == null:
		return
	var st: Dictionary = {}
	if sel != null and sel.state != "hidden" and sel.has_method("cine_state"):
		st = sel.cine_state()
	elif roster != null and roster.has_method("cine_state"):
		st = roster.cine_state()
	if st.is_empty():
		cine_rect.visible = false
		return
	var ca := float(st.get("chroma_amp", 0.0))
	var rb := float(st.get("radial_blur", 0.0))
	var imp := float(st.get("impact_k", 0.0))
	var lb := float(st.get("letterbox_ratio", 0.0))
	var vig := float(st.get("vignette_k", 0.0))
	cine_rect.visible = (ca > 0.0004 or rb > 0.0004 or imp > 0.005 or lb > 0.001 or vig > 0.002)
	if cine_rect.visible:
		cine_mat.set_shader_parameter("accent_col", st.get("accent_col", accent))
		cine_mat.set_shader_parameter("chroma_amp", ca)
		cine_mat.set_shader_parameter("radial_blur", rb)
		cine_mat.set_shader_parameter("impact_k", imp)
		cine_mat.set_shader_parameter("letterbox_ratio", lb)
		cine_mat.set_shader_parameter("vignette_k", vig)
		cine_mat.set_shader_parameter("focus_uv", st.get("focus_uv", Vector2(0.56, 0.48)))


func _fit() -> void:
	var vs := get_viewport().get_visible_rect().size
	var s := minf(vs.x / W, vs.y / H)
	ui.scale = Vector2(s, s)
	ui.position = (vs - Vector2(W, H) * s) * 0.5


func _step_cam(dt: float) -> void:
	if tween_cam.is_empty():
		return
	tween_cam["t"] = float(tween_cam["t"]) + dt
	var p := clampf(float(tween_cam["t"]) / float(tween_cam["dur"]), 0.0, 1.0)
	var e := 1.0 - (1.0 - p) * (1.0 - p) if float(tween_cam["dur"]) < 0.14 else 1.0 - pow(2.0, -11.5 * p) * (1.0 - p)
	var a: Dictionary = tween_cam["from"]
	var b: Dictionary = tween_cam["to"]
	for k in ["hx", "hy", "z", "r"]:
		cam[k] = lerpf(float(a[k]), float(b[k]), e)
	if p >= 1.0:
		var fn: Callable = tween_cam.get("then", Callable())
		tween_cam = {}
		if fn.is_valid():
			fn.call()


func _step_springs(dt: float) -> void:
	var n := maxi(1, ceili(dt / 0.004))
	var h := dt / n
	for i in n:
		dolly["v"] = float(dolly["v"]) + (-float(dolly["d"]) * 135.0 - float(dolly["v"]) * 17.0) * h
		dolly["d"] = float(dolly["d"]) + float(dolly["v"]) * h
		kick["v"] = (kick["v"] as Vector2) + (-(kick["p"] as Vector2) * 240.0 - (kick["v"] as Vector2) * 16.0) * h
		kick["p"] = (kick["p"] as Vector2) + (kick["v"] as Vector2) * h
		shake["v"] = (shake["v"] as Vector2) + (-(shake["p"] as Vector2) * 920.0 - (shake["v"] as Vector2) * 23.0) * h
		shake["p"] = (shake["p"] as Vector2) + (shake["v"] as Vector2) * h
		roll["v"] = float(roll["v"]) + (-float(roll["p"]) * 400.0 - float(roll["v"]) * 17.0) * h
		roll["p"] = float(roll["p"]) + float(roll["v"]) * h
		shock["v"] = float(shock["v"]) + (-float(shock["p"]) * 180.0 - float(shock["v"]) * 14.0) * h
		shock["p"] = float(shock["p"]) + float(shock["v"]) * h

	gear_extra += dial_kick * dt
	dial_kick *= exp(-dt * 5.5)
	var t := t_scene
	var goal: float
	if screen == "select":
		goal = float(VIEW["select"]["ang"][ch_idx]) * DEG - float(VIEW["select"]["r"]) + PI + 0.4
	else:
		goal = -0.35 + home_idx * 0.26 + pointer.x * 0.55 + sin(t * 0.35) * 0.16
	var da := wrapf(goal - float(light["a"]), -PI, PI)
	light["v"] = float(light["v"]) + (da * 30.0 - float(light["v"]) * 9.0) * dt
	light["a"] = float(light["a"]) + float(light["v"]) * dt

	# 剑形时针：首页停在 5:59 位，章节/设置页随选中项精确转动指向该行
	var hg: float = clock.REST
	if screen == "select":
		hg = float(VIEW["select"]["ang"][ch_idx]) * DEG - float(VIEW["select"]["r"])
	var dh := wrapf(hg - float(hand["a"]), -PI, PI)
	var hs := minf(dt, 1.0 / 30.0)
	hand["v"] = float(hand["v"]) + (dh * 340.0 - float(hand["v"]) * 21.0) * hs
	hand["a"] = float(hand["a"]) + float(hand["v"]) * hs
	var mg: float = clock.TWELVE - clock.GAP
	var dm := wrapf(mg - float(min_hand["a"]), -PI, PI)
	min_hand["v"] = float(min_hand["v"]) + (dm * 300.0 - float(min_hand["v"]) * 19.0) * hs
	min_hand["a"] = float(min_hand["a"]) + float(min_hand["v"]) * hs


## 钟的机械：每整秒擒纵走一格（分钟圈顺走、花窗圈逆走、中心机芯一颤、几圈前后一震），
## 选中项变化时外两圈像拨号盘一样转到位，确认时五圈由外到内依次咔地回正（开锁）
func _clack(pitch: float, db: float) -> void:
	_play("h3_parry_lock" if sfx.has("h3_parry_lock") else "ui_move", db, pitch)


func _unlocking() -> bool:
	return unlock_t0 > -5.0


func _unlock(full: bool, then: Callable) -> void:
	unlock_t0 = t_scene
	unlock_full = full
	unlock_then = then
	unlock_from = []
	for i in 5:
		unlock_from.append(wrapf(float(ring_rot[i]), -PI, PI))
	_sfx_done.erase("unl0")
	for j in 5:
		_sfx_done.erase("unl%d" % j)


func _step_rings(dt: float) -> void:
	var n := int(floorf(t_scene))
	var idle := screen in ["home", "quit", "settings"] and not _unlocking() and not busy
	if n != tick_n:
		tick_n = n
		if idle:
			tick_k = 1.0
			ring_esc[1] = wrapf(float(ring_esc[1]) + 1.5 * DEG, -PI, PI)
			ring_esc[2] = wrapf(float(ring_esc[2]) - 0.9 * DEG, -PI, PI)
			ring_vel[0] = float(ring_vel[0]) + 0.32
			ring_dzv[0] = float(ring_dzv[0]) - 300.0
			ring_dzv[2] = float(ring_dzv[2]) + 160.0
			ring_dzv[4] = float(ring_dzv[4]) - 90.0
			light["v"] = float(light["v"]) + 0.6
			_play("ui_move", -27.0, 2.15)
	tick_k = maxf(0.0, tick_k - dt * 4.5)

	if _unlocking():
		var u := t_scene - unlock_t0
		var count := 5 if unlock_full else 2
		var step := 0.055 if unlock_full else 0.05
		for j in 5:
			var i := 4 - j
			if j >= count:
				continue
			var st := float(j) * step
			var p := clampf((u - st) / 0.075, 0.0, 1.0)
			var e := _out_back(p, 2.6)
			ring_rot[i] = lerpf(float(unlock_from[i]), 0.0, e)
			ring_vel[i] = 0.0
			if p >= 1.0 and not _sfx_done.has("unl%d" % j):
				_sfx_done["unl%d" % j] = true
				_clack(1.32 - j * 0.09, -8.0 - j * 0.6)
				ring_dzv[i] = float(ring_dzv[i]) - 420.0
				shake["v"] = (shake["v"] as Vector2) + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 140.0
				light["v"] = float(light["v"]) + 1.6
		var total := float(count - 1) * step + 0.075
		if u >= total + 0.02:
			unlock_t0 = -10.0
			for j in count:
				var i := 4 - j
				ring_esc[i] = 0.0
				ring_rot[i] = 0.0
			pulse = maxf(pulse, 0.7)
			var fn := unlock_then
			unlock_then = Callable()
			if fn.is_valid():
				fn.call()
	else:
		var dial_i := 0
		if screen in ["home", "quit"]:
			dial_i = home_idx
		elif screen == "settings":
			dial_i = -set_idx
		var hold_zero := screen in ["select", "launch"]
		var nn := maxi(1, ceili(dt / 0.004))
		var h := dt / nn
		for i in 5:
			var goal := 0.0 if hold_zero else float(ring_esc[i]) + float(DIAL_STEP[i]) * float(dial_i)
			for s in nn:
				ring_vel[i] = float(ring_vel[i]) + (wrapf(goal - float(ring_rot[i]), -PI, PI) * 720.0 - float(ring_vel[i]) * 22.0) * h
				ring_rot[i] = float(ring_rot[i]) + float(ring_vel[i]) * h
	# 前后震动（每圈自己的弹簧）
	var nz := maxi(1, ceili(dt / 0.004))
	var hz := dt / nz
	for i in 5:
		for s in nz:
			ring_dzv[i] = float(ring_dzv[i]) + (-float(ring_dz[i]) * 420.0 - float(ring_dzv[i]) * 15.0) * hz
			ring_dz[i] = float(ring_dz[i]) + float(ring_dzv[i]) * hz


func _step_ui(dt: float) -> void:
	var k := 1.0 - exp(-dt * 18.0)
	var show := {
		"home": amt["home"] * (1.0 - amt["quit"]),
		"quit": amt["quit"],
		"select": amt["select"],
		"settings": amt["settings"],
	}
	if screen == "intro":
		show["home"] = clampf((intro_t - T_MENU) / 0.42, 0.0, 1.0)

	page_home.modulate.a = show["home"]
	page_quit.modulate.a = show["quit"]
	page_settings.modulate.a = show["settings"]
	page_home.visible = show["home"] > 0.01
	if page_home.visible and home_scrim != null:
		home_scrim.queue_redraw()
	page_quit.visible = show["quit"] > 0.01
	page_select.visible = sel.visible
	page_settings.visible = show["settings"] > 0.01

	# 独立「刀裂四分」角色选择页已接管四姝切换，左下角彻底隐去突兀的半圆表冠
	hero_bar.visible = false
	flood.visible = t_scene - flood_t < 0.56
	if flood.visible:
		flood.queue_redraw()

	# 角色选择：刀裂四分
	if roster != null:
		roster.update(dt, pointer)
		page_roster.visible = roster.visible

	# 设置页：白光定格
	if page_settings.visible:
		setm.update(dt)

	sel.update(dt, pointer, kick["p"])

	for arr in [home_items, quit_items]:
		var idx := home_idx if arr == home_items else quit_idx
		for i in arr.size():
			var it: Dictionary = arr[i]
			it["pos"] = (it["pos"] as Vector2).lerp(it["goal_pos"], k)
			it["h"] = lerpf(it["h"], it["goal_h"], k)
			it["on"] = lerpf(it["on"], 1.0 if i == idx else 0.0, minf(1.0, dt * 30.0))
			it["punch"] = float(it["punch"]) * exp(-dt * 11.0)
			var enter := 1.0
			if screen == "intro" and arr == home_items:
				# 刀光扫到这一行的那一刻，字从右边被带出来
				var at := T_MENU - 0.03 + clampf((float((home_pos[i] as Vector2).y) - 300.0) / 530.0, 0.0, 1.0) * 0.22
				enter = clampf((intro_t - at) / 0.13, 0.0, 1.0)
				enter = 1.0 - pow(1.0 - enter, 3.0)
			var h: float = float(it["h"]) * (1.0 + float(it["punch"]) * 0.13)
			var w: float = h * float(it["aspect"])
			var root: Control = it["root"]
			root.position = (it["pos"] as Vector2) + Vector2((1.0 - enter) * 220.0, -h * 0.5)
			if arr == home_items:
				# 进选章：菜单顺着甩镜方向整体滑出（逐项错开一点），不画刀口
				var hl: float = clampf(sel.home_leave() * 1.25 - i * 0.06, 0.0, 1.0)
				root.position += Vector2(980.0, 160.0) * hl * hl
				enter *= 1.0 - hl
			root.modulate.a = clampf(enter * 1.4, 0.0, 1.0)
			var im: TextureRect = it["img"]
			var sh: TextureRect = it["sh"]
			im.size = Vector2(w, h)
			sh.size = Vector2(w, h)
			var on: float = it["on"]
			var idle_col := Color("#c6c8d8")
			idle_col = idle_col.lerp(WHITE, 0.28 * tick_k)
			# 选中项字标改为极锐骨白亮银，落于黑曜锻钢刀锋上与三维选角/选章视觉 100% 一体化！
			im.modulate = idle_col.lerp(Color(1.06, 1.05, 1.08), on)
			sh.modulate.a = lerpf(0.88, 0.98, on)

	_step_blade(dt)

	# 开场的白闪和菜单刀光
	cut_flash.color.a = maxf(0.0, cut_flash.color.a - dt * 9.0)
	cut_flash.visible = cut_flash.color.a > 0.004
	var ms := _seg(intro_t, T_MENU - 0.03, T_MENU + 0.19) if screen == "intro" else 1.0
	menu_streak.visible = ms > 0.0 and ms < 1.0
	if menu_streak.visible:
		# [YG-MARK] 一道两头尖、中段最粗的刀光，外面裹一层主角色
		var cy := lerpf(260.0, 860.0, 1.0 - pow(1.0 - ms, 1.6))
		var sl := tan(-7.0 * DEG)
		var x0 := 1040.0
		var xm := 1560.0
		var x1 := 2000.0
		var th := 15.0 * (1.0 - ms * 0.5)
		var yy := func(x: float) -> float: return cy + (x - 1500.0) * sl
		var core := PackedVector2Array([
			Vector2(x0, yy.call(x0)), Vector2(xm, yy.call(xm) - th), Vector2(x1, yy.call(x1) - th * 0.6),
			Vector2(x1, yy.call(x1) + th * 0.6), Vector2(xm, yy.call(xm) + th),
		])
		menu_streak.polygon = core
		menu_streak.color = Color(1.0, 1.0, 1.0, 0.98 * (1.0 - ms * ms))
		var glow: Polygon2D = menu_streak.get_child(0)
		var g3 := th * 3.4
		glow.polygon = PackedVector2Array([
			Vector2(x0 - 60, yy.call(x0 - 60)), Vector2(xm, yy.call(xm) - g3), Vector2(x1, yy.call(x1) - g3 * 0.7),
			Vector2(x1, yy.call(x1) + g3 * 0.7), Vector2(xm, yy.call(xm) + g3),
		])
		glow.color = Color(accent.lerp(WHITE, 0.2), 0.42 * (1.0 - ms))

	hint_items = _hint_layout()
	var hint_a := 1.0 if screen != "intro" else clampf((intro_t - T_MENU - 0.2) / 0.3, 0.0, 1.0)
	hint_bar.modulate.a = hint_a
	hint_keys.modulate.a = hint_a
	hint_bar.visible = hint_a > 0.01 and not hint_items.is_empty()
	hint_keys.visible = hint_bar.visible
	if hint_bar.visible:
		hint_bar.queue_redraw()
		hint_keys.queue_redraw()
	skip_lb.visible = screen == "intro" and intro_t > 0.22 and intro_t < T_MENU
	flash_ui = maxf(0.0, flash_ui - dt * 3.2)


func _step_blade(dt: float) -> void:
	var on_blade_page := screen in ["home", "quit"] or (screen == "intro" and intro_t > T_MENU + 0.18)
	var target_a := 1.0 if on_blade_page and not busy else 0.0
	blade["a"] = lerpf(blade["a"], target_a, minf(1.0, dt * 18.0))
	var pos := Vector2.ZERO
	var size := Vector2.ZERO
	var note := ""
	var it: Dictionary = {}
	if screen == "intro":
		it = home_items[0]
	else:
		var list := _active_list()
		if not list.is_empty():
			it = list[_active_idx()]
			if screen == "home" and home_idx < home_actions.size() and String(home_actions[home_idx]) == "continue" and not has_save:
				note = "暂无存档"
	if not it.is_empty():
		pos = (it["goal_pos"] as Vector2) + Vector2(-48, -float(it["goal_h"]) * 0.5 - 16)
		var base_w := float(it["goal_h"]) * float(it["aspect"]) + 124.0 + (190.0 if note != "" else 0.0)
		if screen == "quit":
			base_w = maxf(420.0, base_w)
		size = Vector2(base_w, float(it["goal_h"]) + 32)
		var k := 1.0 - exp(-dt * 28.0)
		blade["pos"] = (blade["pos"] as Vector2).lerp(pos, k)
		blade["size"] = (blade["size"] as Vector2).lerp(size, k)
	if note != "":
		blade["note"] = note
	blade["note_a"] = lerpf(float(blade["note_a"]), 1.0 if note != "" else 0.0, minf(1.0, dt * 14.0))
	_spring_blade(blade, dt)


## 拔刀：刀身从刀镡里弹出来（带一点过冲），随后刃口跑一道光
func _spring_blade(b: Dictionary, dt: float) -> void:
	var n := maxi(1, ceili(dt / 0.004))
	for i in n:
		b["vsx"] = float(b["vsx"]) + ((1.0 - float(b["sx"])) * 440.0 - float(b["vsx"]) * 25.0) * (dt / n)
		b["sx"] = float(b["sx"]) + float(b["vsx"]) * (dt / n)
	b["glint"] = minf(9.0, float(b["glint"]) + dt / 0.3)
	b["deny"] = float(b["deny"]) * exp(-dt * 6.5)
	var node: Node2D = b["node"]
	var inner: Node2D = b["inner"]
	node.position = b["pos"]
	node.modulate.a = b["a"]
	node.visible = float(b["a"]) > 0.01
	inner.position = Vector2(sin(t_scene * 74.0) * 10.0 * float(b["deny"]), 0.0)
	inner.queue_redraw()


func _new_blade(node: Node2D, inner: Node2D, size: Vector2) -> Dictionary:
	return {
		"node": node, "inner": inner,
		"pos": Vector2(1200, 390), "size": size,
		"sx": 1.0, "vsx": 0.0, "a": 0.0,
		"glint": 9.0, "deny": 0.0, "note": "", "note_a": 0.0,
	}


## 刀身上一点：x 沿刀身，y 从刀背（0）到刃口（h），整体向右倾 8°
func _bp(x: float, y: float, h: float) -> Vector2:
	return Vector2(x + (h - y) * 0.1405, y)


func _draw_blade(b: Dictionary) -> void:
	var c: Node2D = b["inner"]
	var s: Vector2 = b["size"]
	var hh := s.y
	var sx := clampf(float(b["sx"]), 0.0, 1.25)
	var x0 := 4.0
	var xr := maxf(x0 + 2.0, s.x * sx)
	var tip := minf(hh * 0.46, xr - x0)
	var xb := xr - tip
	var ys := hh * 0.13
	var ye := hh * 0.85
	var xs := lerpf(xr, xb, 0.13)
	var xe := lerpf(xr, xb, 0.85)
	var ac := accent
	var tk := tick_k
	# 墨影
	var body := PackedVector2Array([_bp(x0, 0, hh), _bp(xr, 0, hh), _bp(xb, hh, hh), _bp(x0, hh, hh)])
	var shp := PackedVector2Array()
	for p in body:
		shp.append(p + Vector2(11, 13))
	c.draw_colored_polygon(shp, Color(INK, 0.92))
	# 斩口露出的冷钢厚边
	c.draw_colored_polygon(PackedVector2Array([
		_bp(xr - 1, 0, hh), _bp(xr + 8, 5, hh), _bp(xb + 8, hh + 2, hh), _bp(xb - 1, hh, hh),
	]), Color(ac.lerp(WHITE, 0.35), 0.72))
	# 奢华黑曜锻钢刀面（透出背后三维铸铁齿轮呼吸感 + 银白刀脊 + 主色流光刃口！）
	var spine_a := Color("#232534", 0.92)
	var spine_b := Color("#131420", 0.92)
	c.draw_polygon(PackedVector2Array([_bp(x0, 0, hh), _bp(xr, 0, hh), _bp(xs, ys, hh), _bp(x0, ys, hh)]),
		PackedColorArray([spine_a, spine_a, spine_b, spine_b]))
	var face_a := Color("#0c0d16", 0.88)
	var face_b := Color("#171426", 0.88).lerp(ac.darkened(0.68), 0.24)
	c.draw_polygon(PackedVector2Array([_bp(x0, ys, hh), _bp(xs, ys, hh), _bp(xe, ye, hh), _bp(x0, ye, hh)]),
		PackedColorArray([face_a, face_a, face_b, face_b]))
	var bev_a := ac.darkened(0.28)
	bev_a.a = 0.94
	var bev_b := ac.lerp(WHITE, 0.42)
	bev_b.a = 0.98
	c.draw_polygon(PackedVector2Array([_bp(x0, ye, hh), _bp(xe, ye, hh), _bp(xb, hh, hh), _bp(x0, hh, hh)]),
		PackedColorArray([bev_a, bev_a, bev_b, bev_b]))
	# 细微常驻流光扫掠（让首页待机自带 3A 呼吸质感）
	var amb_p := fmod(t_scene * 0.48, 1.0)
	var amb_x := lerpf(x0 + 10.0, xb - 10.0, amb_p)
	var amb_a := sin(amb_p * PI) * 0.16
	c.draw_line(_bp(amb_x, 2, hh), _bp(amb_x - 36.0, hh - 2, hh), Color(1, 1, 1, amb_a), 22.0, true)
	c.draw_line(_bp(x0, 1.0, hh), _bp(xr, 1.0, hh), Color(WHITE, 0.56), 1.4, true)
	c.draw_line(_bp(x0 + 4, ys, hh), _bp(xs - 2, ys, hh), Color(WHITE, 0.18), 1.2, true)
	c.draw_line(_bp(x0, hh - 1.5, hh), _bp(xb, hh - 1.5, hh), ac.lerp(WHITE, 0.28 + 0.52 * tk), 3.4, true)
	c.draw_line(_bp(xr, 0, hh), _bp(xb, hh, hh), Color(WHITE, 0.92), 1.8, true)
	# 牌上写着的「暂无存档」
	var na := float(b["note_a"]) * clampf((sx - 0.75) / 0.25, 0.0, 1.0)
	if na > 0.01 and String(b["note"]) != "":
		var nx := s.x - 214.0
		var dn := float(b["deny"])
		c.draw_line(_bp(nx - 16, hh * 0.3, hh), _bp(nx - 16, hh * 0.72, hh), Color(WHITE, 0.28 * na), 2.0, true)
		var ncol := Color(WHITE, 0.68).lerp(ac.lightened(0.25), clampf(dn * 1.6, 0.0, 1.0))
		ncol.a *= na
		c.draw_string(font_cn, _bp(nx, hh * 0.5 + 11.0, hh), String(b["note"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 30, ncol)
	# 刀镡（冷钢黑曜底座 + 主色精镶菱钻）
	var gd := PackedVector2Array([_bp(-24, -9, hh), _bp(6, -9, hh), _bp(6, hh + 9, hh), _bp(-24, hh + 9, hh)])
	var gsh := PackedVector2Array()
	for p in gd:
		gsh.append(p + Vector2(8, 10))
	c.draw_colored_polygon(gsh, Color(INK, 0.92))
	c.draw_colored_polygon(gd, ac.darkened(0.18))
	c.draw_line(_bp(-24, -9, hh), _bp(6, -9, hh), ac.lerp(WHITE, 0.65), 2.2, true)
	c.draw_line(_bp(-9, -3, hh), _bp(-9, hh + 3, hh), Color(INK, 0.55), 2.6, true)
	var gc := _bp(-9.0, hh * 0.5, hh)
	c.draw_colored_polygon(PackedVector2Array([gc + Vector2(-6, 0), gc + Vector2(0, -6), gc + Vector2(6, 0), gc + Vector2(0, 6)]), Color(WHITE, 0.94))
	# 拔出后一道光沿刃口跑到刀尖，在刀尖迸一下
	var g := float(b["glint"])
	if g > 0.0 and g < 1.35:
		var e := 1.0 - pow(1.0 - clampf(g, 0.0, 1.0), 2.0)
		var gx := lerpf(x0, xb, e)
		var fade := clampf((1.35 - g) / 0.35, 0.0, 1.0)
		c.draw_line(_bp(gx - 150, hh - 1.5, hh), _bp(gx + 20, hh - 1.5, hh), Color(ac.lerp(WHITE, 0.4), 0.45 * fade), 11.0, true)
		c.draw_polyline_colors(PackedVector2Array([_bp(gx - 170, hh - 1.5, hh), _bp(gx, hh - 1.5, hh), _bp(gx + 26, hh - 1.5, hh)]),
			PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, fade), Color(1, 1, 1, 0)]), 4.5, true)
		var sp := clampf(sin(clampf((g - 0.8) / 0.55, 0.0, 1.0) * PI), 0.0, 1.0)
		if sp > 0.01:
			var cp := _bp(xb, hh, hh)
			var r1 := 46.0 * sp
			var r2 := 4.0 * sp
			c.draw_colored_polygon(PackedVector2Array([cp + Vector2(-r1, 0), cp + Vector2(0, -r2), cp + Vector2(r1, 0), cp + Vector2(0, r2)]), Color(1, 1, 1, 0.95))
			c.draw_colored_polygon(PackedVector2Array([cp + Vector2(-r2, 0), cp + Vector2(0, -r1 * 0.6), cp + Vector2(r2, 0), cp + Vector2(0, r1 * 0.6)]), Color(1, 1, 1, 0.95))
			c.draw_circle(cp, 9.0 * sp, Color(ac.lerp(WHITE, 0.5), 0.5))


func _draw_scratches(n: Node2D) -> void:
	var sz: Vector2 = n.get_meta("sz", Vector2.ZERO)
	if sz == Vector2.ZERO:
		return
	var lines := [
		[Vector2(0.03, 0.66), Vector2(0.56, 0.28)],
		[Vector2(0.34, 0.88), Vector2(0.97, 0.42)],
		[Vector2(0.55, 0.70), Vector2(0.80, 0.55)],
		[Vector2(0.12, 0.40), Vector2(0.30, 0.31)],
	]
	for l in lines:
		var a: Vector2 = (l[0] as Vector2) * sz
		var b: Vector2 = (l[1] as Vector2) * sz
		_scratch_line(n, a, b)


func _scratch_line(n: Node2D, a: Vector2, b: Vector2) -> void:
	n.draw_line(a, b, Color(INK, 0.85), 2.6, true)
	n.draw_line(a + Vector2(0.8, 2.0), b + Vector2(0.8, 2.0), Color(1, 1, 1, 0.22), 1.0, true)


# ================================================================ 三维钟状态与 5:59 卡针物理
func _live_state() -> Dictionary:
	var t := t_scene
	var orbit := Vector2(sin(t / 5.1) * 1.65, cos(t / 5.9) * 1.08)
	var lean := Vector2((home_idx - 1.5) * 0.34, 0.0) if screen in ["home", "quit"] else Vector2.ZERO
	var tick := floorf(t) + minf(1.0, fmod(t, 1.0) / 0.12)
	# 在设置页压低右侧裂口亮度，保证左侧 72% 绝对纯黑安静
	var violet_vis := 0.2 if screen == "settings" else 1.0
	var home_vis: float = float(amt["home"]) * (0.28 if screen == "quit" else 1.0)
	var d := {
		"t": 40.0 + t,
		"view": _shaken(cam),
		"parallax": pointer + orbit + lean,
		"dolly": float(dolly["d"]) + (-85.0 if screen == "quit" else 0.0),
		"home_a": home_vis,
		"hour_angle": hand["a"],
		"light_a": light["a"],
		"light_k": 1.0 + absf(float(light["v"])) * 0.12,
		"gear_spin": 0.0 if screen == "quit" else t * 0.11 + gear_extra,
		"dial_spin": -float(amt["select"]) * float(sel.wheel_p) * float(sel.STEP),   # 钟盘与画片轮咬合同转
		"ink_tint": Color("#8d8f96"), "ink_tint_k": float(amt["select"]) * 0.7,   # 选章时钟面压成中性冷灰（环境不用紫）
		"dial_face_a": 1.0 - 0.45 * float(amt["select"]),
		"esc": 0.0 if screen == "quit" else tick * (PI / 15.0),
		"pallet": 0.0 if screen == "quit" else sin(tick * PI) * 10.0,
		"fall": tick * 24.0,
		"flood": 0.0,
		# 进出设置页时字标不再飞向镜头，原地淡掉
		"mark": [1.0, 1.0, 1.0] if amt["settings"] > 0.01 or screen == "settings" else [amt["home"], amt["home"], amt["home"]],
		"mark_a": clampf(1.0 - float(amt["settings"]) * 3.0, 0.0, 1.0),
		"mark_split": 1.0,
		"glint": amt["home"],
		"readout_a": amt["home"],
		"kick": kick["p"],
		"flash": flash_ui * 0.5,
		"pulse": pulse,
		"violet": violet_vis,
		"dial_reveal": 1.0, "dial_a": 0.45 if screen == "settings" else (1.0 - 0.25 * float(amt["select"])),
		"burst": 1.0 + float(shock["p"]), "debris": 1.0 - 0.85 * float(amt["settings"]),
		"hour_a": 1.0 - 0.75 * float(amt["settings"]), "minute_a": 1.0 - 0.75 * float(amt["settings"]), "hub_a": 1.0 - 0.6 * float(amt["settings"]),   # [YG-MARK] 白光定格：指针压暗退到背景
		"seam_a": 0.0 if screen == "settings" else 1.0,
		"hour_thrust": 0.0,
		"minute_angle": float(min_hand["a"]) + _stuck_bump(),
		"split": 0.0,
		"smear": clampf(absf(float(dolly["v"])) / 850.0, 0.0, 3.6),
		"rain_a": 0.65 if screen == "settings" else 1.0,
		"motes_a": 0.45 if screen == "settings" else 1.0,
		# 两半跟着擒纵一起错动一下：紫半边每一下往斩缝方向多滑一点、往后多沉一点，再弹回
		"slip": 44.0 + tick_k * tick_k * 9.0, "slip_z": -140.0 - tick_k * tick_k * 40.0,
		"ring_rot": ring_rot.duplicate(), "ring_dz": ring_dz.duplicate(),
		"ring_tilt": [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO],
		"ring_a": [1.0, 1.0, 1.0, 1.0, 1.0], "half_tilt": 0.0, "mark_half": [1.0, 1.0],
	}
	d["light_k"] = float(d["light_k"]) + tick_k * 0.2
	if sel.state != "hidden":
		var cs: Dictionary = sel.clock_state()
		for k in cs:
			d[k] = cs[k]
	elif roster != null and roster.has_method("clock_state"):
		var rs: Dictionary = roster.clock_state()
		for k in rs:
			d[k] = rs[k]
	return d


func _step_stuck() -> void:
	if screen == "home" and not busy and t_scene >= stuck_next:
		stuck_t0 = t_scene
		stuck_next = t_scene + randf_range(4.8, 7.2)
		stuck_hit = false
	if not stuck_hit and t_scene - stuck_t0 >= 0.12:
		stuck_hit = true
		flash_ui = maxf(flash_ui, 0.48)
		pulse = maxf(pulse, 0.65)
		shock["p"] = maxf(float(shock["p"]), 0.16)
		shake["p"] = Vector2(6.0, -3.5)
		light["v"] = float(light["v"]) + 2.2
		_play("h3_parry_lock" if sfx.has("h3_parry_lock") else "ui_move", -13.0, 1.08)


## 分针试图往前挤，死死卡在 05:59 被裂口弹回（严格遵照总纲：绝不跳到 06:00！）
func _stuck_bump() -> float:
	var ts := t_scene - stuck_t0
	if screen != "launch" and screen != "intro":
		for lb in clock._readout:
			(lb as Label3D).text = "05:59"
	if ts < 0.0 or ts > 1.5:
		return 0.0
	if ts < 0.12:
		return clock.GAP * 0.78 * pow(ts / 0.12, 3.0)
	var u := ts - 0.12
	return clock.GAP * 0.78 * exp(-u * 42.0) - 0.18 * exp(-u * 5.8) * sin(u * 18.0)


func _shaken(v: Dictionary) -> Dictionary:
	var o := v.duplicate()
	o["hx"] = float(o["hx"]) + (shake["p"] as Vector2).x
	o["hy"] = float(o["hy"]) + (shake["p"] as Vector2).y
	o["r"] = float(o["r"]) + float(roll["p"])
	return o


func _hit(px: float, rr: float, sk: float) -> void:
	var a := randf_range(0.0, TAU)
	shake["p"] = Vector2(cos(a), sin(a)) * px
	shake["v"] = Vector2(cos(a + 2.2), sin(a + 2.2)) * px * 18.0
	roll["p"] = rr * (1.0 if randf() > 0.5 else -1.0)
	roll["v"] = 0.0
	shock["p"] = sk
	shock["v"] = 0.0


static func _seg(t: float, a: float, b: float) -> float:
	return clampf((t - a) / (b - a), 0.0, 1.0)


static func _out_expo(t: float) -> float:
	return 1.0 if t >= 1.0 else 1.0 - pow(2.0, -10.0 * t)


static func _in_out(t: float) -> float:
	return 4.0 * t * t * t if t < 0.5 else 1.0 - pow(-2.0 * t + 2.0, 3.0) / 2.0


static func _out_back(t: float, s: float = 1.7) -> float:
	return 1.0 + (s + 1.0) * pow(t - 1.0, 3.0) + s * pow(t - 1.0, 2.0)


# ================================================================ 2.45 秒紧凑开场与 5:59 倒卷入夜进关演出
func _intro_state(t: float) -> Dictionary:
	var cut := t >= T_CUT
	var since := t - T_CUT
	# ---- 镜头：侧面贴近 → 转到正面 → 分针扫动时后拉 → 斩后被震回主菜单构图
	var view: Dictionary
	var par := Vector2.ZERO
	var speed := 0.0
	if not cut:
		var a := _in_out(_seg(t, 0.0, 0.82))
		var pull := _in_out(_seg(t, T_MIN0, T_MIN1))
		var hold := _seg(t, T_MIN1, T_CUT)
		view = {
			"hx": lerpf(1010.0, 962.0, a), "hy": lerpf(500.0, 546.0, a),
			"z": lerpf(1.62, 1.5, a) * lerpf(1.0, 0.8, pull) * (1.0 + hold * 0.025),
			"r": lerpf(-16.0, 1.5, a) * DEG,
		}
		par = Vector2(lerpf(-13.0, -1.0, a), lerpf(5.0, 0.4, a)) * (1.0 - pull)
		speed = sin(PI * _seg(t, T_MIN0, T_MIN1)) * 1.4
	else:
		var q := _seg(t, T_CUT, T_CUT + 0.55)
		var e := _out_back(_out_expo(q), 0.7)
		var drift := _seg(t, T_CUT + 0.55, T_END)
		view = {"hx": lerpf(962.0, 950.0, e), "hy": lerpf(546.0, 540.0, e), "z": lerpf(1.2, 1.0, e) * (1.0 + drift * 0.008), "r": lerpf(1.5, 0.0, e) * DEG}
		speed = exp(-since * 6.0) * 1.8
	view = _shaken(view)

	# ---- 五圈：散在纵深里慢慢漂，到自己那一声「咔」之前 0.16 秒加速落位，落定带一点颤
	var r_rot: Array = []
	var r_dz: Array = []
	var r_tl: Array = []
	var r_a: Array = []
	for i in 5:
		var at: float = T_ASM[RING_GROUP[i]]
		var p := _seg(t, at - 0.17, at)
		var e := p * p * p
		var drift_rot := float(RING_SCATTER_ROT[i]) * (1.0 + 0.25 * (1.0 - _seg(t, 0.0, at - 0.17)))
		var after := t - at
		var wob := exp(-after * 26.0) * sin(after * 70.0) * 0.05 if after > 0.0 else 0.0
		r_rot.append(lerpf(drift_rot, 0.0, e) + wob)
		r_dz.append(lerpf(float(RING_SCATTER_Z[i]), 0.0, e) + (exp(-after * 18.0) * -60.0 if after > 0.0 else 0.0))
		r_tl.append((RING_SCATTER_TILT[i] as Vector2) * (1.0 - e))
		r_a.append(clampf(t / 0.22, 0.0, 1.0) * lerpf(0.55, 1.0, e))
	var gears_in := _seg(t, T_ASM[2] - 0.12, T_ASM[2])

	# ---- 指针：时针在第三声跟着中心机芯捅进来；分针 0.8 秒出现，越扫越快撞上 5:59
	var hp := _out_expo(_seg(t, T_ASM[2] - 0.1, T_ASM[2] + 0.12))
	var mp := _seg(t, T_MIN0, T_MIN1)
	var minute: float = clock.TWELVE - clock.GAP - (1.0 - mp * mp * mp) * 3.1
	if t > T_MIN1:
		minute += exp(-(t - T_MIN1) * 30.0) * sin((t - T_MIN1) * 72.0) * 0.04

	# ---- 斩：两半先被劈开再合回，紫半边往外翻、往后沉，再弹回静止位
	var fl := 0.0
	var split := 0.0
	var htilt := 0.0
	var slip_z := -140.0
	if cut:
		fl = exp(-since * 7.0) * (1.0 if since < 0.04 else 0.85)
		split = 190.0 * _seg(since, 0.0, 0.05) * exp(-maxf(since - 0.05, 0.0) * 5.5)
		htilt = 0.26 * exp(-since * 4.2) * cos(since * 13.0)
		slip_z = -140.0 - 230.0 * exp(-since * 5.0) * cos(since * 10.0)
	var hold_dark := _seg(t, T_MIN1, T_CUT) if not cut else 0.0
	var la: float = lerpf(2.4, 1.1, _in_out(_seg(t, 0.0, T_CUT))) if not cut else lerpf(1.1, -0.35, 1.0 - pow(1.0 - _seg(t, T_CUT, T_SETTLE), 3.0))
	var lk: float = lerpf(1.7, 0.35, hold_dark) if not cut else 1.0 + fl * 2.4
	var tick := floorf(t * 3.0) + minf(1.0, fmod(t * 3.0, 1.0) / 0.14)
	var home_a := _seg(t, T_CUT + 0.12, T_SETTLE)
	var orbit := Vector2(sin(t_scene / 5.1) * 1.65, cos(t_scene / 5.9) * 1.08) * _seg(t, T_SETTLE, T_END)
	var mk := 1.0 if t >= T_MARK_L - 0.02 else 0.0

	return {
		"t": 40.0 + t, "view": view, "dolly": float(dolly["d"]), "parallax": par + orbit,
		"violet": _out_expo(_seg(t, T_CUT, T_CUT + 0.2)) if cut else 0.0,
		"slip": 44.0 * _out_back(_seg(t, T_CUT, T_CUT + 0.3), 2.2), "slip_z": slip_z,
		"split": split, "half_tilt": htilt,
		"dial_reveal": 1.0, "dial_a": 1.0,
		"ring_rot": r_rot, "ring_dz": r_dz, "ring_tilt": r_tl, "ring_a": r_a,
		"hour_a": clampf(hp * 3.0, 0, 1), "hour_thrust": (1.0 - hp) * 640.0, "hour_angle": clock.REST,
		"minute_a": _seg(t, T_MIN0 - 0.05, T_MIN0 + 0.04), "minute_angle": minute,
		"hub_a": gears_in,
		"seam_a": 1.0 if cut else 0.0, "flash": fl, "pulse": exp(-since * 4.0) if cut else 0.0,
		"debris": 1.0 if cut else 0.0, "burst": _out_expo(_seg(t, T_CUT, T_CUT + 0.5)) if cut else 0.0,
		"mark": [mk, mk, mk], "mark_half": [_seg(t, T_MARK_L, T_MARK_L + 0.17), _seg(t, T_MARK_R, T_MARK_R + 0.17)],
		"mark_split": _out_back(_seg(t, T_MARK_R + 0.2, T_MARK_R + 0.4), 2.1),
		"rain_a": 0.5 + 0.5 * _seg(t, 0.0, 0.5), "fall": tick * 18.0, "smear": speed * 2.2,
		"motes_a": 0.35 + 0.65 * home_a, "light_a": la, "light_k": lk,
		"glint": _seg(t, T_SETTLE, T_END), "home_a": home_a,
		"gear_spin": 4.4 + t * 0.11 + tick * 0.02 + (1.0 - gears_in) * 3.0, "esc": tick * (PI / 15.0), "pallet": sin(tick * PI) * 10.0,
		"readout_a": _seg(t, T_MIN1 - 0.02, T_MIN1 + 0.04) * (1.0 if cut else 0.7),
		"kick": Vector2.ZERO, "flood": 0.0,
	}


## 开场的音和「打击」：三声咔、分针扫、撞停、斩、两半字落地、刀光划过菜单
func _intro_sfx(t: float) -> void:
	for k in 3:
		var key := "asm%d" % k
		if t >= float(T_ASM[k]) and not _sfx_done.has(key):
			_sfx_done[key] = true
			_clack(1.22 - k * 0.14, -5.0)
			_play("ult_impact", -15.0 + k * 2.0, 1.4 - k * 0.15)
			_hit(7.0 + k * 3.0, 0.006, 0.1)
			light["v"] = float(light["v"]) + 2.0
	var specs := [
		["sweep", T_MIN0, "ult_push", -7.0, 1.15],
		["lock", T_MIN1, "h3_parry_lock" if sfx.has("h3_parry_lock") else "ult_sheathe", -3.0, 0.9],
		["cut", T_CUT - 0.012, "h3_slash_heavy" if sfx.has("h3_slash_heavy") else "ult_cut_0", -0.5, 1.0],
		["imp", T_CUT, "ult_impact", -1.5, 0.92],
		["mkl", T_MARK_L + 0.15, "ult_impact", -7.0, 1.3],
		["mkr", T_MARK_R + 0.15, "ult_impact", -6.0, 1.12],
		["menu", T_MENU, "h3_slash_fast" if sfx.has("h3_slash_fast") else "ult_push", -9.0, 1.2],
	]
	for spec in specs:
		if t >= float(spec[1]) and not _sfx_done.has(spec[0]):
			_sfx_done[spec[0]] = true
			_play(spec[2], spec[3], spec[4])
			match String(spec[0]):
				"lock":
					_hit(6.0, 0.004, 0.05)
				"cut":
					cut_flash.color.a = 1.0
					hitstop = 0.085
					_hit(30.0, 0.032, 0.7)
				"mkl", "mkr":
					_hit(14.0, 0.012, 0.2)
					pulse = maxf(pulse, 0.6)
				"menu":
					blade["sx"] = 0.0
					blade["vsx"] = 0.0
					blade["glint"] = -0.4


func _finish_intro() -> void:
	intro_t = T_END
	for k in ["asm0", "asm1", "asm2", "sweep", "lock", "cut", "imp", "mkl", "mkr", "menu"]:
		_sfx_done[k] = true
	if cut_flash != null:
		cut_flash.color.a = 0.0
	screen = "home"
	amt["home"] = 1.0
	cam = (VIEW["home"] as Dictionary).duplicate()
	stuck_next = t_scene + 2.6
	_layout_all(true)


## 进关卡演出：严格遵守《剧情与主题规划.md》——
## 0.00~0.16s 分针猛顶 05:59 临界极限（绝不跳 06:00！）→ 0.16s 一刀逆斩劈扩裂口，
## 双剑指针与全套齿轮疯狂逆时针倒卷回「18:00 入夜」、悬停雨珠倒吸升空 → 镜头扎进深渊裂口无缝切入暗夜雨街！
func _launch_state(t: float) -> Dictionary:
	var s := _live_state()
	var c := _in_out(_seg(t, 0.0, 0.34))
	var v := {}
	for k in ["hx", "hy", "z", "r"]:
		v[k] = lerpf(float(launch_cam[k]), float(LAUNCH_VIEW[k] if k != "r" else 0.0), c)

	var snap := t >= 0.16
	var rw := pow(_seg(t, 0.16, 0.92), 1.65)
	# 分针先顶在 05:59 震颤，0.16s 起逆时针疯转三圈半倒卷回入夜
	var minute: float = clock.TWELVE - clock.GAP * (0.25 if not snap else 1.0) - rw * (TAU * 3.5)
	s["minute_angle"] = minute
	s["hour_angle"] = float(s["hour_angle"]) - rw * (TAU * 0.5)

	var tb: float = 40.0 + launch_t
	s["t"] = tb - rw * 9.5
	s["gear_spin"] = float(s["gear_spin"]) - rw * 9.0
	s["esc"] = float(s["esc"]) - rw * 36.0
	s["fall"] = float(s["fall"]) - rw * 3100.0 # 雨丝倒吸飞向夜空

	var mins := 359 if not snap else posmod(359 - int(round(rw * 719.0)), 1440)
	if rw >= 0.99:
		mins = 18 * 60
	var txt := "%02d:%02d" % [mins / 60, mins % 60]
	s["readout_text"] = txt
	s["readout_a"] = _seg(t, 0.0, 0.06) * (1.0 - _seg(t, 0.72, 0.98))

	# 0.16s 一刀劈开裂口，两半巨钟猛烈撕裂，镜头一头冲进深渊暗缝
	var sp := _out_expo(_seg(t, 0.16, 0.96))
	s["split"] = sp * 540.0
	s["flash"] = exp(-(t - 0.16) * 9.0) * 0.85 if snap else 0.0
	s["pulse"] = exp(-(t - 0.16) * 3.2) if snap else 0.4
	s["light_k"] = 1.0 + (3.6 * exp(-(t - 0.16) * 4.5) if snap else 0.5)
	s["burst"] = 1.0 + float(shock["p"])

	var push := pow(_seg(t, 0.34, 1.16), 2.1)
	v["z"] = float(v["z"]) * (1.0 + push * 2.9)
	v["r"] = float(v["r"]) + push * 0.12
	s["view"] = _shaken(v)
	s["smear"] = minf(1.5, sin(PI * rw) * 1.2 + push * 1.5)
	s["home_a"] = 0.0
	# 镜头由 zz_select 接管：先拉远看钟倒卷回入夜，再一头穿进画片
	return s


# ================================================================ 交互动作与一镜到底三维甩镜转场
func _beat_select(list_name: String) -> void:
	_play("ui_move", -6.0, randf_range(0.96, 1.06))
	hitstop = 0.036
	pulse = maxf(pulse, 0.36)
	if list_name != "settings":
		blade["sx"] = 0.12
		blade["vsx"] = 0.0
		blade["glint"] = -0.35
	light["v"] = float(light["v"]) + 2.8
	kick["v"] = (kick["v"] as Vector2) + Vector2(0.8829476, 0.4694716) * 210.0 * (1.0 if randf() > 0.5 else -1.0)
	if list_name in ["home", "quit"]:
		var arr: Array = home_items if list_name == "home" else quit_items
		if not arr.is_empty():
			arr[_active_idx()]["punch"] = 1.0
	_layout_all()


## 废除旧版紫潮巨字 PPT 遮罩：采用反收蓄力 75ms → 真三维高速甩镜 Whip-Pan 280ms
func _go(next: String) -> void:
	if busy or next == screen:
		return
	busy = true
	if next in ["home", "roster"]:
		_go_now(next)
		return
	# 选章或设置前极快开锁（0.14s 干脆利落，绝不拖泥带水）
	_play("ult_push", -12.0, 1.3)
	dolly["v"] = float(dolly["v"]) - 420.0
	if screen == "roster":
		_go_now(next)
	else:
		_unlock(next == "select", _go_now.bind(next))


func _go_now(next: String) -> void:
	if screen == "settings" and next != "settings":
		setm.leave()
	# [YG-MARK] 三维裂时殿堂一镜到底转场（Home <-> 3D Roster <-> 3D Stage，零刷新跳转！）
	if next == "roster" and roster.has_method("clock_state"):
		var from_sel := screen == "select"
		var prev_xf: Transform3D = (clock.camera as Camera3D).global_transform
		if from_sel:
			if sel.has_method("leave_to_roster"):
				sel.leave_to_roster()
			else:
				sel.leave()
		screen = "roster"
		page_t0 = t_scene
		if from_sel and roster.has_method("enter_from_select"):
			roster.enter_from_select(hero, prev_xf)
		else:
			roster.enter(hero)
		_layout_all(true)
		return
	if screen == "roster" and next == "select" and roster.has_method("confirm_to_select"):
		roster.confirm_to_select(func(handoff_xf: Transform3D) -> void:
			screen = "select"
			page_t0 = t_scene
			if sel.has_method("enter_from_roster"):
				sel.enter_from_roster(ch_idx, handoff_xf)
			else:
				sel.enter(ch_idx)
			_layout_all()
			get_tree().create_timer(0.55).timeout.connect(func() -> void:
				if screen == "select":
					busy = false))
		return
	if screen == "roster" and next == "home" and roster.has_method("leave_to_home"):
		roster.leave_to_home(func() -> void:
			screen = "home"
			page_t0 = t_scene
			cam = (VIEW["home"] as Dictionary).duplicate()
			busy = false
			_layout_all(true))
		return
	if screen == "roster" and next != "roster":
		roster.leave()
	if next == "select":
		screen = "select"
		page_t0 = t_scene
		sel.enter(ch_idx)
		hand["v"] = float(hand["v"]) - 7.5
		dolly["v"] = 760.0
		_play("ult_push", -9.0, 1.12)
		_layout_all()
		get_tree().create_timer(0.55).timeout.connect(func() -> void:
			if screen == "select":
				busy = false)
		return
	var from := cam.duplicate()
	var to: Dictionary = VIEW[next]
	var back := next == "home" or (screen == "select" and next == "roster")
	if screen == "select":
		sel.leave()
	_play("h3_unsheathe" if (back and sfx.has("h3_unsheathe")) else ("h3_slash_fast" if sfx.has("h3_slash_fast") else "ult_push"), -5.5 if back else -3.5, 1.08 if back else 1.0)

	var pre := {
		"hx": lerpf(float(from["hx"]), float(to["hx"]), -0.06),
		"hy": lerpf(float(from["hy"]), float(to["hy"]), -0.06),
		"z": float(from["z"]) * (1.04 if back else 0.94),
		"r": float(from["r"]) - (float(to["r"]) - float(from["r"])) * 0.08,
	}
	tween_cam = {
		"t": 0.0, "dur": 0.055, "from": from, "to": pre,
		"then": func() -> void:
			screen = next
			page_t0 = t_scene
			page_d0 = 0.04
			if next == "roster":
				roster.enter(hero)
			if next == "settings":
				setm.enter()
			if next == "select":
				sel.enter(ch_idx)
				dial_kick = 7.0
			_layout_all(true)
			blade["sx"] = 0.15
			blade["vsx"] = 0.0
			pulse = 0.95
			flash_ui = 0.55
			dolly["v"] = 1350.0 if back else -1850.0
			_hit(14.0 if back else 22.0, 0.012 if back else 0.02, 0.22 if back else 0.32)
			hitstop = 0.025 if back else 0.035
			tween_cam = {
				"t": 0.0, "dur": 0.24, "from": cam.duplicate(), "to": to,
				"then": func() -> void:
					busy = false
			}
	}


## 《拨钟选章》时间轴事件（由 zz_select 在对应帧回调）
func _sel_event(name: String) -> void:
	match name:
		"slash":
			_play("h3_slash_heavy" if sfx.has("h3_slash_heavy") else "ult_cut_2", -2.0, 1.0)
			pulse = 0.95
			flash_ui = 0.5
			light["v"] = float(light["v"]) + 5.0
		"freeze":
			hitstop = 0.045
			_hit(16.0, 0.014, 0.32)
			_play("ult_impact", -5.0, 1.1)
		"whoosh":
			_play("h3_slash_fast" if sfx.has("h3_slash_fast") else "ult_push", -7.0, 0.82)
		"land":
			_play("h3_parry_lock" if sfx.has("h3_parry_lock") else "ult_impact", -6.0, 0.9)
			_hit(9.0, 0.006, 0.18)
			dial_kick = 6.0
		"ready":
			busy = false
		"click":
			_play("ui_move", -7.0, 0.78)
		"bell":   # 机关舞台：钟卡进钟楼，钟响
			hitstop = maxf(hitstop, 0.06)
			_hit(14.0, 0.012, 0.34)
			_play("h3_anvil_bell" if sfx.has("h3_anvil_bell") else "ult_impact", -3.0, 0.82)
			_play("ult_impact", -8.0, 0.7)
		"pass":   # 机关舞台：镜头穿过一圈钟环
			_play("h3_slash_fast" if sfx.has("h3_slash_fast") else "ult_push", -15.0, randf_range(1.15, 1.45))
		"bolt":   # 机关舞台：闪电亮场
			_play("ult_impact", -9.0, 0.6)
		"ignite":
			_play("ui_move", -13.0, 1.5)
		"lock":
			hitstop = maxf(hitstop, 0.03)
			_play("h3_parry_lock" if sfx.has("h3_parry_lock") else "ui_move", -12.0, 1.25)
			shake["p"] = Vector2(0.0, 5.0)


func _select_to(i: int) -> void:
	if i == ch_idx:
		return
	var d := 1 if i > ch_idx else -1
	ch_idx = i
	sel.set_index(ch_idx, d)
	dial_kick = 4.5 * float(d)
	_play("h3_slash_fast" if sfx.has("h3_slash_fast") else "ult_push", -13.0, 1.25)
	_beat_select("select")


func _launch(i: int) -> void:
	if busy:
		return
	var ch: Dictionary = CHAPTERS[i]
	if not bool(ch["unlocked"]):
		# 未解锁章节：沉重铁砧封锁反馈
		_play("h3_anvil_bell" if sfx.has("h3_anvil_bell") else "ui_back", -5.0, 0.72)
		kick["v"] = (kick["v"] as Vector2) + Vector2(-420.0, 0.0)
		_hit(14.0, 0.01, 0.18)
		sel.locked_bump()
		return

	busy = true
	sel.launch()
	screen = "launch"
	launch_t = t_scene
	launch_cam = cam.duplicate()
	launch_scene = String(ch["scene"])
	if ResourceLoader.load_threaded_get_status(launch_scene) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		ResourceLoader.load_threaded_request(launch_scene)

	# 0.00s：5:59 临界撞针清鸣
	_play("h3_parry_lock" if sfx.has("h3_parry_lock") else "ult_push", -2.5, 1.0)
	hitstop = 0.06
	# 0.16s：真钢重斩劈开裂口 + 倒拧棘轮加速回溯入夜
	get_tree().create_timer(0.16).timeout.connect(func() -> void:
		_play("h3_slash_heavy" if sfx.has("h3_slash_heavy") else "ult_cut_2", -0.5, 0.98)
		_play("ult_impact", -2.0)
		kick["v"] = (kick["v"] as Vector2) + Vector2(0.0, -820.0)
		_hit(36.0, 0.04, 0.85))
	for k in 6:
		var at: float = 0.18 + 0.56 * pow(float(k + 1) / 6.0, 0.68)
		var pitch := 0.82 + k * 0.15
		get_tree().create_timer(at).timeout.connect(func() -> void: _play("ui_move", -7.0 + k * 0.8, pitch))

	var tw := create_tween()
	tw.tween_interval(1.2)
	tw.tween_property(veil, "color:a", 1.0, 0.34).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_interval(0.04)
	tw.tween_callback(_enter_game)


func _enter_game() -> void:
	if OS.has_environment("ZZ_CAPTURE"):
		return
	var packed: PackedScene = null
	var st := ResourceLoader.load_threaded_get_status(launch_scene)
	if st == ResourceLoader.THREAD_LOAD_LOADED or st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		packed = ResourceLoader.load_threaded_get(launch_scene) as PackedScene
	if packed == null:
		packed = load(launch_scene) as PackedScene
	# 从深邃暗夜墨色淡入影街（严格废除旧版违背设定的白屏淡入！）
	var cl := CanvasLayer.new()
	cl.layer = 120
	cl.process_mode = Node.PROCESS_MODE_ALWAYS
	var rect := ColorRect.new()
	rect.color = Color(0.025, 0.024, 0.04, 1.0)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	cl.add_child(rect)
	get_tree().root.add_child(cl)
	var tw := cl.create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_interval(0.06)
	tw.tween_property(rect, "color:a", 0.0, 0.58).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_callback(cl.queue_free)
	print("[zz_title] 进入 ", launch_scene)
	get_tree().change_scene_to_packed(packed)


func _accept() -> void:
	match screen:
		"home":
			var act := String(home_actions[home_idx]) if home_idx < home_actions.size() else "start"
			match act:
				"start": _go("roster")
				"continue": _go("select")
				"settings": _go("settings")
				"exit":
					_play("ui_move", -5.5, 0.88)
					screen = "quit"
					quit_idx = 0
					_layout_all()
		"roster":
			if roster.is_playable():
				_go("select")
			else:
				_play("h3_anvil_bell" if sfx.has("h3_anvil_bell") else "ui_back", -6.0, 0.78)
				roster.bump_locked()
				_hit(10.0, 0.008, 0.14)
		"quit":
			if quit_idx == 0:
				_play("ui_back", -6.0)
				screen = "home"
				_layout_all()
			else:
				get_tree().quit()
		"select":
			if sel.state == "in":
				sel.snap_in()
			_launch(ch_idx)
		"settings":
			_adjust(1)


func _back() -> void:
	match screen:
		"roster", "settings": _go("home")
		"select": _go("roster")
		"quit":
			_play("ui_back", -6.0)
			screen = "home"
			_layout_all()


func _move(dir: int) -> void:
	match screen:
		"home":
			home_idx = wrapi(home_idx + dir, 0, home_items.size())
			dial_kick = 5.0 * float(dir)
			ring_vel[0] = float(ring_vel[0]) - 0.9 * float(dir)
			ring_dzv[4] = float(ring_dzv[4]) - 380.0
			ring_dzv[3] = float(ring_dzv[3]) + 220.0
			_clack(1.12 + 0.05 * float(dir), -10.0)
			_beat_select("home")
		"roster":
			roster.select_index(roster.idx + dir)
		"quit":
			quit_idx = wrapi(quit_idx + dir, 0, 2)
			_beat_select("quit")
		"select":
			_select_to(wrapi(ch_idx - dir, 0, CHAPTERS.size()))
		"settings":
			_settings_pick(wrapi(set_idx + dir, 0, SET_ITEMS.size()))


func _adjust(dir: int) -> void:
	if screen == "roster":
		roster.select_index(roster.idx + dir)
		return
	if screen != "settings":
		return
	match String(SET_ITEMS[set_idx]["key"]):
		"master": _set_master(master_volume() + 0.1 * dir)
		"bgm": _set_bgm(bgm_volume() + 0.1 * dir)
		"fullscreen": _set_fullscreen(not is_fullscreen())
		"vsync": _set_vsync(not vsync_on())
		"supersample": _set_supersample(not supersample_on())
		"scheme":
			var next_s := Factory.SCHEME_MOUSE if Factory.scheme() == Factory.SCHEME_KEYBOARD else Factory.SCHEME_KEYBOARD
			Factory.set_scheme(next_s, DisplayServer.get_name() != "headless")
	_save_settings()
	var akey := String(SET_ITEMS[set_idx]["key"])
	setm.on_adjust()
	if akey != "master" and akey != "bgm":
		shake["v"] = (shake["v"] as Vector2) + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 90.0
	if akey == "master" or akey == "bgm":
		var v_now := bgm_volume() if akey == "bgm" else master_volume()
		_clack(0.85 + v_now * 0.6, -9.0)
	else:
		_clack(1.05, -8.0)
		_play("ui_move", -9.0, 1.15)
	pulse = maxf(pulse, 0.25)


## [YG-MARK] 设置页换选中项：整列滚过白光，进光的那项定格一下（快门似的一声）
func _settings_pick(i: int) -> void:
	if i == set_idx:
		return
	var prev := set_idx
	set_idx = i
	setm.on_move(prev)
	dial_kick = -3.0 * float(signi(i - prev))
	_clack(1.32, -11.0)
	_beat_select("settings")


# ================================================================ 四姝主色切换
func _init_hero(s: ConfigFile) -> void:
	var h := ""
	if OS.has_environment("ZZ_HERO"):
		h = OS.get_environment("ZZ_HERO")
	elif s.has_section_key("profile", "hero"):
		h = str(s.get_value("profile", "hero", ""))
	if not HEROES.has(h):
		var tc := ConfigFile.new()
		tc.load(TITLE_CFG)
		h = str(tc.get_value("title", "hero", "shuo"))
		if not HEROES.has(h):
			h = "shuo"
	_apply_hero(h, false)


func _cycle_hero(step: int) -> void:
	var cur := HERO_ORDER.find(hero)
	var nxt: String = HERO_ORDER[wrapi(cur + step, 0, HERO_ORDER.size())]
	_apply_hero(nxt, true)


func _apply_hero(h: String, feedback: bool) -> void:
	if not HEROES.has(h):
		return
	var old_i := HERO_ORDER.find(hero)
	var new_i := HERO_ORDER.find(h)
	if feedback and h != hero:
		# 表冠转一格（取最短方向），旧字转走、新字砸进来，新颜色从断缝涌出，钟最外圈也跟着走一格
		var d := wrapi(new_i - old_i, -2, 2)
		crown_goal += float(d)
		swap_from = hero
		swap_dir = 1 if d > 0 else -1
		swap_t = t_scene
		if screen in ["home", "quit"]:
			flood_t = t_scene
		ring_esc[4] = wrapf(float(ring_esc[4]) - float(swap_dir) * 12.0 * DEG, -PI, PI)
		ring_vel[4] = float(ring_vel[4]) - float(swap_dir) * 1.2
		ring_dzv[4] = float(ring_dzv[4]) - 360.0
		_clack(0.95, -9.0)
	elif not feedback:
		crown_cur = float(new_i)
		crown_goal = crown_cur
		crown_v = 0.0
	hero = h
	pal = HEROES[hero]
	accent = pal["ui"]
	if clock != null:
		clock.set_palette(pal)
	if quit_band_edge != null:
		quit_band_edge.color = accent
	if hero_bar != null:
		hero_bar.queue_redraw()
	if feedback:
		var tc := ConfigFile.new()
		tc.load(TITLE_CFG)
		tc.set_value("title", "hero", hero)
		tc.save(TITLE_CFG)
		_play("h3_parry_lock" if sfx.has("h3_parry_lock") else "ult_cut_0", -6.5, 1.12)
		pulse = 1.0
		flash_ui = 0.45
		hitstop = 0.03
		_hit(12.0, 0.01, 0.2)


# ================================================================ 输入处理（键盘 + 鼠标 + 手柄全适配）
func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventJoypadButton or ev is InputEventJoypadMotion:
		last_pad = true
	elif ev is InputEventKey or ev is InputEventMouseButton:
		last_pad = false

	if screen == "intro":
		var pressed: bool = (ev is InputEventKey and ev.pressed and not ev.echo) or (ev is InputEventJoypadButton and ev.pressed) or (ev is InputEventMouseButton and ev.pressed)
		if pressed and intro_t > 0.15:
			_finish_intro()
			get_viewport().set_input_as_handled()
		return

	if (ev is InputEventMouseMotion or ev is InputEventMouseButton) and (OS.has_environment("ZZ_CAPTURE") or OS.has_environment("ZZ_DEMO")):
		return

	if ev is InputEventMouseMotion:
		var first := mouse_last.x < -1e8
		var still: bool = ev.position.distance_to(mouse_last) < 3.0
		if first or still:
			if first:
				mouse_last = ev.position
			return
		mouse_last = ev.position
		var vs := get_viewport().get_visible_rect().size
		pointer_goal = Vector2(ev.position.x / vs.x * 2.0 - 1.0, ev.position.y / vs.y * 2.0 - 1.0)
		_hover((ev.position - ui.position) / ui.scale.x)
		return

	if screen == "launch":
		return
	if busy:
		# 演出没完时按的键记下来，演完立刻执行（以前会直接丢掉）
		if ev.is_action_pressed("ui_cancel") or (ev is InputEventJoypadButton and ev.pressed and ev.button_index == JOY_BUTTON_B) or (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT):
			queued_input = "back"
		elif ev.is_action_pressed("ui_accept"):
			queued_input = "accept"
		elif ev.is_action_pressed("ui_up"):
			queued_input = "up"
		elif ev.is_action_pressed("ui_down"):
			queued_input = "down"
		elif ev.is_action_pressed("ui_left"):
			queued_input = "left"
		elif ev.is_action_pressed("ui_right"):
			queued_input = "right"
		return

	# 快捷键换角色主色（Tab / 手柄 LB RB）
	if ev is InputEventKey and ev.pressed and not ev.echo and ev.keycode == KEY_TAB and screen in ["home", "roster", "select"]:
		if screen == "roster":
			roster.select_index(roster.idx + (-1 if ev.shift_pressed else 1))
		else:
			_cycle_hero(-1 if ev.shift_pressed else 1)
		get_viewport().set_input_as_handled()
		return
	if ev is InputEventJoypadButton and ev.pressed:
		if ev.button_index == JOY_BUTTON_LEFT_SHOULDER and screen in ["home", "roster", "select"]:
			if screen == "roster":
				roster.select_index(roster.idx - 1)
			else:
				_cycle_hero(-1)
			get_viewport().set_input_as_handled()
			return
		elif ev.button_index == JOY_BUTTON_RIGHT_SHOULDER and screen in ["home", "roster", "select"]:
			if screen == "roster":
				roster.select_index(roster.idx + 1)
			else:
				_cycle_hero(1)
			get_viewport().set_input_as_handled()
			return
		elif ev.button_index == JOY_BUTTON_B:
			# player_factory.register_input 会将手柄 B 从 ui_cancel 移除，菜单内单独认 B 为返回
			_back()
			get_viewport().set_input_as_handled()
			return

	if ev is InputEventMouseButton and ev.pressed:
		var upos: Vector2 = (ev.position - ui.position) / ui.scale.x
		if ev.button_index == MOUSE_BUTTON_LEFT:
			if screen == "roster":
				if roster.hit_cta(upos):
					_accept()
					get_viewport().set_input_as_handled()
					return
				var si: int = roster.hit_slice(upos)
				if si >= 0:
					if si != roster.idx:
						roster.select_index(si)
					else:
						_accept()
					get_viewport().set_input_as_handled()
					return
			if screen == "settings" and _click_settings(upos):
				get_viewport().set_input_as_handled()
				return
			if screen == "select":
				var hi: int = sel.hit_card(upos)
				if hi >= 0 and hi != ch_idx:
					_select_to(hi)
					get_viewport().set_input_as_handled()
					return
				if hi == ch_idx:
					_accept()
					get_viewport().set_input_as_handled()
					return
			if _hover(upos):
				_accept()
				get_viewport().set_input_as_handled()
				return
		elif ev.button_index == MOUSE_BUTTON_RIGHT:
			_back()
			get_viewport().set_input_as_handled()
		elif ev.button_index == MOUSE_BUTTON_WHEEL_UP or ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_move(-1 if ev.button_index == MOUSE_BUTTON_WHEEL_UP else 1)
			get_viewport().set_input_as_handled()
		return

	if ev is InputEventJoypadMotion:
		var m := ev as InputEventJoypadMotion
		if m.axis == JOY_AXIS_LEFT_Y and absf(m.axis_value) > 0.6 and not _sfx_done.get("stick", false):
			_sfx_done["stick"] = true
			_move(1 if m.axis_value > 0 else -1)
		elif m.axis == JOY_AXIS_LEFT_X and absf(m.axis_value) > 0.6 and not _sfx_done.get("stick", false):
			_sfx_done["stick"] = true
			_adjust(1 if m.axis_value > 0 else -1)
		elif absf(m.axis_value) < 0.3 and (m.axis == JOY_AXIS_LEFT_Y or m.axis == JOY_AXIS_LEFT_X):
			_sfx_done["stick"] = false
		return

	if ev.is_action_pressed("ui_up"):
		_move(-1)
	elif ev.is_action_pressed("ui_down"):
		_move(1)
	elif ev.is_action_pressed("ui_left"):
		_adjust(-1)
	elif ev.is_action_pressed("ui_right"):
		_adjust(1)
	elif ev.is_action_pressed("ui_accept"):
		_accept()
	elif ev.is_action_pressed("ui_cancel") or (ev is InputEventKey and ev.pressed and ev.keycode == KEY_BACKSPACE):
		_back()
	else:
		return
	get_viewport().set_input_as_handled()


func _click_hero_bar(p: Vector2) -> bool:
	if not (screen in ["home", "select"]):
		return false
	var C := CROWN_C + hero_bar.position
	var v := p - C
	if v.length() > CROWN_R + 40.0 or v.y > 0.0:
		return false
	# 点在色口附近就换成那位；点在表冠中间就往下转一格
	var a := atan2(v.y, v.x)
	if v.length() > CROWN_R - 30.0:
		var best := -1
		var best_d := 0.12
		for i in HERO_ORDER.size():
			var dd := wrapf(float(i) - crown_cur, -2.0, 2.0)
			var ai := -PI * 0.5 + dd * CROWN_STEP
			var diff := absf(wrapf(a - ai, -PI, PI))
			if diff < best_d:
				best_d = diff
				best = i
		if best >= 0:
			_apply_hero(HERO_ORDER[best], true)
			return true
	_cycle_hero(1)
	return true


func _click_settings(p: Vector2) -> bool:
	var r: Dictionary = setm.hit(p)
	if r.has("pick"):
		_settings_pick(int(r["pick"]))
		return true
	if r.has("volume"):
		var steps := roundi(float(r["volume"]) * 10.0)
		if String(r.get("key", "master")) == "bgm":
			_set_bgm(steps / 10.0)
		else:
			_set_master(steps / 10.0)
		_save_settings()
		setm.on_adjust()
		_clack(0.85 + steps * 0.06, -9.0)
		return true
	if r.has("adjust"):
		_adjust(1)
		return true
	return false


func _hover(p: Vector2) -> bool:
	if busy:
		return false
	if screen == "roster":
		return roster.set_hover(p)
	if screen == "settings":
		return setm.set_hover(p)   # 只提示可点，不随鼠标滚动换项（整列会在鼠标下面滚走）
	if screen == "select":
		var hc: int = sel.hit_card(p)
		sel.hover = hc == ch_idx
		return hc >= 0
	var list := _active_list()
	for i in list.size():
		var it: Dictionary = list[i]
		var h: float = it["h"]
		if Rect2((it["pos"] as Vector2) + Vector2(-24, -h * 0.5), Vector2(h * float(it["aspect"]) + 70, h)).has_point(p):
			if i != _active_idx():
				if screen == "home":
					home_idx = i
				elif screen == "quit":
					quit_idx = i
				_beat_select(screen)
			return true
	return false


# ================================================================ 设置读写（与暂停菜单共享 settings.cfg / graphics.cfg / controls.cfg）
func _load_settings() -> void:
	var s := ConfigFile.new()
	if s.load(SHARED_CFG) == OK:
		if s.has_section_key("audio", "master"):
			_set_master(float(s.get_value("audio", "master", 1.0)))
		if s.has_section_key("audio", "bgm"):
			_bgm_vol = clampf(snappedf(float(s.get_value("audio", "bgm", 0.85)), 0.1), 0.0, 1.0)
		if s.has_section_key("display", "fullscreen") and DisplayServer.get_name() != "headless":
			_set_fullscreen(bool(s.get_value("display", "fullscreen", false)))
		if s.has_section_key("display", "vsync"):
			_set_vsync(bool(s.get_value("display", "vsync", true)))


func _save_settings() -> void:
	var s := ConfigFile.new()
	s.load(SHARED_CFG)
	s.set_value("audio", "master", master_volume())
	s.set_value("audio", "bgm", bgm_volume())
	s.set_value("display", "fullscreen", is_fullscreen())
	s.set_value("display", "vsync", vsync_on())
	s.save(SHARED_CFG)


func master_volume() -> float:
	if AudioServer.is_bus_mute(0):
		return 0.0
	return clampf(db_to_linear(AudioServer.get_bus_volume_db(0)), 0.0, 1.0)


func _set_master(v: float) -> void:
	v = clampf(snappedf(v, 0.1), 0.0, 1.0)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(v, 0.0001)))
	AudioServer.set_bus_mute(0, v <= 0.0)


func bgm_volume() -> float:
	return _bgm_vol


func _set_bgm(v: float) -> void:
	_bgm_vol = clampf(snappedf(v, 0.1), 0.0, 1.0)
	_apply_bgm_vol()


func _apply_bgm_vol() -> void:
	if bgm_bus_idx >= 0 and bgm_bus_idx < AudioServer.bus_count:
		AudioServer.set_bus_mute(bgm_bus_idx, _bgm_vol <= 0.0)


func vsync_on() -> bool:
	return _vsync_pref


func _set_vsync(on: bool) -> void:
	_vsync_pref = on
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if on else DisplayServer.VSYNC_DISABLED)


func is_fullscreen() -> bool:
	var m := DisplayServer.window_get_mode()
	return m == DisplayServer.WINDOW_MODE_FULLSCREEN or m == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN


func _set_fullscreen(on: bool) -> void:
	if on == is_fullscreen():
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)


func supersample_on() -> bool:
	return ss_pref


## [YG-MARK] Supersample 自动加载是 2D 专用（2 倍画布 disable_3d、不透明铺满），开着时首页的 3D 钟整个被盖掉。
## 首页里先把它挂起，偏好改成给 3D 钟 2 倍渲染（scaling_3d_scale 2.0 = 3D 超采样）；离开首页按偏好交回去。
func _ss_enter() -> void:
	var ss := get_tree().root.get_node_or_null("Supersample")
	var cfg := ConfigFile.new()
	cfg.load(GRAPHICS_CFG)
	ss_pref = bool(cfg.get_value("graphics", "supersample", false)) or (ss != null and bool(ss.get("enabled")))
	if ss != null and bool(ss.get("enabled")):
		ss.call("set_enabled", false)
	_ss_apply_3d()


func _ss_leave() -> void:
	if not is_inside_tree():
		return
	var root := get_tree().root
	root.scaling_3d_scale = 1.0
	var ss := root.get_node_or_null("Supersample")
	if ss != null and ss_pref and not bool(ss.get("enabled")):
		ss.call("set_enabled", true)


## F7（Supersample 自己的快捷键）在首页按下时：记成偏好，再挂起 2D 那套
func _ss_watch() -> void:
	var ss := get_tree().root.get_node_or_null("Supersample")
	if ss != null and bool(ss.get("enabled")):
		ss_pref = true
		ss.call("set_enabled", false)
		_ss_apply_3d()


func _ss_apply_3d() -> void:
	var root := get_tree().root
	root.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	root.scaling_3d_scale = 2.0 if ss_pref else 1.0


func _set_supersample(on: bool) -> void:
	ss_pref = on
	_ss_apply_3d()
	var cfg := ConfigFile.new()
	cfg.load(GRAPHICS_CFG)
	cfg.set_value("graphics", "supersample", on)
	cfg.save(GRAPHICS_CFG)


# ================================================================ 原生 Forward+ 全流程自动巡检截图（ZZ_CAPTURE=输出目录）
func _shot(dir: String, name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_jpg(dir.path_join(name + ".jpg"), 0.92)


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _key(k: String) -> void:
	var ev := InputEventAction.new()
	ev.action = k
	ev.pressed = true
	Input.parse_input_event(ev)
	await get_tree().process_frame
	var up := InputEventAction.new()
	up.action = k
	up.pressed = false
	Input.parse_input_event(up)


## 60 帧视频样片脚本：配合 --write-movie --fixed-fps 60 使用（ZZ_DEMO=1）
func _demo_run() -> void:
	_apply_hero("shuo", false)
	if OS.get_environment("ZZ_DEMO") in ["enter", "switch", "back"]:
		# 让片头自然播完（跳过片头会把白光留在画面上）
		while screen == "intro":
			await get_tree().process_frame
		stuck_next = 1e9
	else:
		_finish_intro()
	stuck_next = 1e9
	if OS.get_environment("ZZ_DEMO") == "roster3d_flow":
		# 60fps 商业发售版全流程一镜到底实机演示（升级黑曜锻钢首页切项 → 52°绕钟掠齿进四象异镜 → 四姝异构登场 → 希区柯克锁眼巨钟入塔 → 垂直登天五章零条码 → 倒飞合钟）
		await _wait(0.55)
		await _key("ui_down")         # 演示升级版首页黑曜锻钢白刃拨钟切项
		await _wait(0.32)
		await _key("ui_up")           # 回「开始游戏」
		await _wait(0.35)
		await _key("ui_accept")       # 首页 → 52°绕钟掠齿 + 剑针实体擦镜进《四象异镜》
		await _wait(1.12)
		await _key("ui_right")        # 朔 → 萤（高空俯冲镜像反构图 + 0%紫 + 零武器压字）
		await _wait(0.95)
		await _key("ui_right")        # 萤 → 薇（贴地仰拍巨剑 + 0%紫）
		await _wait(0.95)
		await _key("ui_right")        # 薇 → 曜（对称圣坛 + 暗玻璃托底清晰指标 + 0%紫）
		await _wait(0.95)
		await _key("ui_right")        # 曜 → 朔
		await _wait(0.85)
		await _key("ui_accept")       # 确认出战：希区柯克变焦 → 双紫斩 → 零黑档直入月夜钟楼！
		await _wait(1.70)
		await _key("ui_up")           # 真三维垂直登天（零竖条码 + 钟体绑定随降）→ 第二章 归晓大教堂
		await _wait(0.85)
		await _key("ui_up")           # 垂直登天 → 第三章 浮空白城
		await _wait(0.85)
		await _key("ui_up")           # 垂直登天 → 第四章 天顶裂口
		await _wait(0.85)
		await _key("ui_up")           # 演武：试剑回廊
		await _wait(0.75)
		await _key("ui_up")           # 回到第一章 影街
		await _wait(0.65)
		await _key("ui_cancel")       # 一镜到底倒飞回三维裂钟心殿
		await _wait(0.85)
		await _key("ui_cancel")       # 倒穿五层铸铁钟环合拢回首页
		await _wait(0.80)
		get_tree().quit()
		return
	if OS.get_environment("ZZ_DEMO") == "atlus_flow":
		# 60fps 全流程一镜到底实机演示录屏（首页 → 刀裂四分切四姝 → 爆散直切选章切三幕 → 甩镜设置调项 → 返回）
		await _wait(0.75)
		await _key("ui_accept")       # 首页 → 刀裂四分（28° 斜刃擦除 + 四格斜轨砸入）
		await _wait(0.75)
		await _key("ui_right")        # 朔 → 萤（青色切刃 + 0%紫）
		await _wait(0.55)
		await _key("ui_right")        # 萤 → 薇（烈红切刃）
		await _wait(0.55)
		await _key("ui_right")        # 薇 → 曜（流金切刃）
		await _wait(0.55)
		await _key("ui_right")        # 曜 → 朔
		await _wait(0.50)
		await _key("ui_accept")       # 确认出战：Persona 斩裂爆散直露第一章影街！
		await _wait(0.85)
		await _key("ui_up")           # 刀光快切第二章 归晓大教堂
		await _wait(0.65)
		await _key("ui_up")           # 刀光快切第三章 浮空白城
		await _wait(0.65)
		await _key("ui_cancel")       # 返回选角
		await _wait(0.50)
		await _key("ui_cancel")       # 返回首页
		await _wait(0.50)
		await _key("ui_down")         # 选中「设置」
		await _wait(0.28)
		await _key("ui_accept")       # 3D 钟 32° 甩镜微距 + 12° 撕裂白跨页设置！
		await _wait(0.65)
		await _key("ui_down")         # 切到音乐音量
		await _wait(0.45)
		await _key("ui_left")         # 实时调音量看大字冲撞
		await _wait(0.30)
		await _key("ui_right")
		await _wait(0.35)
		await _key("ui_down")         # 全屏
		await _wait(0.40)
		await _key("ui_down")         # 垂直同步
		await _wait(0.40)
		await _key("ui_down")         # 超采样
		await _wait(0.40)
		await _key("ui_down")         # 操作方式
		await _wait(0.65)
		await _key("ui_cancel")       # 返回首页
		await _wait(0.65)
		get_tree().quit()
		return
	if OS.get_environment("ZZ_DEMO") == "enter":
		# 只录「首页 → 机关舞台装出影街」一段
		await _wait(1.4)
		await _key("ui_accept")
		await _wait(5.2)
		get_tree().quit()
		return
	if OS.get_environment("ZZ_DEMO") == "back":
		await _wait(1.0)
		await _key("ui_accept")
		await _wait(3.4)
		await _key("ui_down")
		await _wait(1.2)
		await _key("ui_up")
		await _wait(1.2)
		await _key("ui_cancel")
		await _wait(1.8)
		get_tree().quit()
		return
	if OS.get_environment("ZZ_DEMO") == "switch":
		await _wait(1.0)
		await _key("ui_accept")
		await _wait(3.2)
		await _key("ui_up")
		await _wait(1.6)
		await _key("ui_up")
		await _wait(1.6)
		get_tree().quit()
		return
	await _wait(1.3)
	await _key("ui_accept")       # 首页 → 选章
	await _wait(2.6)
	await _key("ui_up")           # 第二章
	await _wait(1.0)
	await _key("ui_accept")       # 未开放：铁砧封锁反馈
	await _wait(0.9)
	await _key("ui_up")           # 第三章
	await _wait(1.2)
	await _key("ui_up")           # 连按两下：终章 → 演武
	await _wait(0.18)
	await _key("ui_up")
	await _wait(1.6)
	await _key("ui_up")           # 绕回第一章（首尾相接，只转一格）
	await _wait(1.6)
	await _key("ui_cancel")       # 返回首页
	await _wait(1.5)
	await _key("ui_accept")       # 再进选章
	await _wait(2.2)
	get_tree().create_timer(3.4).timeout.connect(get_tree().quit)
	await _key("ui_accept")       # 开始 → 进关


func _capture_run(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	_apply_hero("shuo", false)
	while screen == "intro":
		await get_tree().process_frame
	stuck_next = 1e9
	await _wait(0.45)
	await _shot(dir, "01_home_shuo")

	# 1. 进入《三维裂时殿堂》角色选择并逐一展示四姝展开态（朔紫 / 萤青 / 薇红 / 曜金）
	await _key("ui_accept")
	await _wait(0.95)
	await _shot(dir, "02_roster_shuo")
	for hk in ["ying", "wei", "yao"]:
		await _key("ui_right")
		await _wait(0.70)
		await _shot(dir, "02_roster_" + hk)
	await _key("ui_right") # 回到「夜鸦」朔
	await _wait(0.65)

	# 2. 确认出战 → 机关舞台选章（完整等 1.55s 落定，零半截帧！）
	await _key("ui_accept")
	await _wait(1.60)
	await _shot(dir, "03_select_ch1")
	for cname in ["ch2_cathedral", "ch3_whitecity", "ch4_zenith", "ch5_training"]:
		await _key("ui_up")
		await _wait(0.75)
		await _shot(dir, "03_select_" + cname)
	await _key("ui_up") # 回到第一章
	await _wait(0.65)

	# 3. 返回选人 → 返回首页 → 进入 6 项「白光定格」设置页逐项截屏
	await _key("ui_cancel")
	await _wait(0.55)
	await _key("ui_cancel")
	await _wait(0.55)
	# 选中「设置」（无存档时索引 1，有存档时索引 2）
	await _key("ui_down")
	if has_save:
		await _wait(0.12)
		await _key("ui_down")
	await _wait(0.20)
	await _key("ui_accept")
	await _wait(0.65)
	var set_names := ["00_master", "01_bgm", "02_fullscreen", "03_vsync", "04_supersample", "05_scheme"]
	for si in set_names.size():
		await _shot(dir, "04_settings_" + set_names[si])
		if si < set_names.size() - 1:
			await _key("ui_down")
			await _wait(0.42)

	# 4. 返回首页 → 退出确认页
	await _key("ui_cancel")
	await _wait(0.55)
	await _key("ui_down")
	await _wait(0.22)
	await _key("ui_accept")
	await _wait(0.38)
	await _shot(dir, "05_quit_confirm")
	await _key("ui_cancel")
	await _wait(0.35)

	# 5. 快速校验进关卡 5:59 倒卷入夜
	home_idx = 0
	_layout_all(true)
	await _wait(0.15)
	await _key("ui_accept") # -> roster
	await _wait(0.45)
	await _key("ui_accept") # -> select
	await _wait(1.55)
	await _key("ui_accept") # -> launch 5:59 rewind
	for i in 8:
		await _wait(0.14)
		await _shot(dir, "06_launch_rewind_%02d" % i)
	print("ZZ_CAPTURE_DONE")
	get_tree().quit()
