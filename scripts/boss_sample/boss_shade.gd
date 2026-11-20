extends "res://scripts/night/shade.gd"
## C6 原创首领：【司晷 · 错时残影体】（MiniMax-H3 24fps 真视频连续动作图集 × 双向时间倒流硬核博弈）
##
## 五大核心视觉与战斗机制：
##   1. 80 帧（8×10，`4096×5120`）`24fps` `MiniMax-H3` 真视频连续动作图集 + 常态双层「快门错时重影」；
##   2. 【逆晷双斩 · 倒带抽刀】(`triple` / `rewind_slash`)：突进直刺沿途留下银白快门塑像 -> 2 倍速顺原轨迹倒带抽刀回斩，弹反倒带刃直接打出 1.8s「崩针大硬直」；
##   3. 【5:59 过去锚点 · 斩断反噬】(`chrono_anchor`)：原地留银白过去残影锚点（银丝连体），玩家趁其出击一刀劈碎锚点 -> 触发「时间断轨自爆」直接炸空整管棱壳跪地破防；
##   4. 【逆时捉影 · 倒流玩家位置】(`player_rewind_snare`)：在玩家脚下烙印 2 秒前纯白时痕剪影并蓄力重刺，倒计时归零将玩家强行倒流拽回白影！瞬步可扯断时痕，或顺势迎面弹刀触发「超音速迎面崩刃」一击碎壳；
##   5. 【登碑悬针 · 逆流拔刺 & 弹针轰坠】(`spire_dive`)：真抛物线跃上左 `XI` (`y=297`) / 右 `V` (`y=344`) 罗马字碑俯射钟针，落地钟针逆流倒飞回天；玩家精准弹刀可将钟针超音速反钉回首领胸口，将其从字碑高台直接轰坠砸地！

const BossFonts := preload("res://scripts/boss_sample/boss_fonts.gd")

const ATLAS_TEX_PATH := "res://assets/image/boss_duanchao/sigui_c6_atlas.png"
const ATLAS_NORM_PATH := "res://assets/image/boss_duanchao/sigui_c6_normal.png"
const ATLAS_EDGE_PATH := "res://assets/image/boss_duanchao/sigui_c6_edge.png"
const ATLAS_SIL_PATH := "res://assets/image/boss_duanchao/sigui_c6_sil.png"
const VFX_TEX_PATH := "res://assets/image/boss_duanchao/sigui_vfx_atlas.png"

const ATLAS_CELL := 512.0
const RIM_CELL := 256.0
const VFX_CELL := 512.0
const ATLAS_COLS := 8
const VFX_COLS := 3
const ATLAS_FOOT_Y := 468.0
const ATLAS_AIR_Y := 262.0
const SPRITE_SCALE := 1.20

const XI_MONUMENT_Y := 223.4
const V_MONUMENT_Y := 286.4
const BALCONY_Y := 223.4

signal clashed(index: int, is_final: bool)
signal clash_canceled(point: Vector2)
signal dodged_through(point: Vector2)
signal armor_held()
signal shell_damaged(amount: float, remain: float, is_backstab: bool, point: Vector2)
signal shell_shattered(point: Vector2)
signal shell_reforged_wave(point: Vector2)
signal volley_flung(volley: int, speed: float)
signal pursuit_slashed(point: Vector2, count: int)
signal armor_severed(point: Vector2, total_cores: int)
signal phase2_started()
signal rift_opened(point: Vector2)
signal rift_dyed_exploded(point: Vector2, damage: float)
signal rift_exploded_red(point: Vector2)
signal apex_reached(point: Vector2)
signal nail_aimed()
signal nail_landed(point: Vector2)
signal tether_slam(damage: float, point: Vector2)
signal intro_slammed()
signal intro_done()
signal horizon_telegraphed(from_x: float, to_x: float)
signal horizon_slashed(from_x: float, to_x: float)
signal water_wave_spawned(pos: Vector2, dir: int)
signal rain_needles_summoned(count: int)
signal rain_needle_cut(point: Vector2, total_cut: int)
signal needle_reflected_hit(point: Vector2, knocked_off_monument: bool)
signal spire_perched(side: int, perch_pos: Vector2)
signal anchor_spawned(pos: Vector2)
signal anchor_derailed(pos: Vector2)
signal player_snare_stamped(pos: Vector2)
signal player_snare_severed(pos: Vector2)
signal supersonic_rewind_parried(pos: Vector2)

enum Blade { WHITE, RED, NAIL, RIFT, HORIZON, NEEDLES, BACKSTEP, PERCH, ANCHOR, SNARE }
enum Nail { NONE, AIM, STUCK }
enum Rift { NONE, ACTIVE, PURPLE }

# 数值规格
const MAX_HP := 2000.0
const PHASE2_HP_RATIO := 0.50

const MAX_SHELL := 100.0
const SHELL_PARRY := 38.0
const SHELL_PARRY_REWIND := 58.0
const SHELL_PARRY_HORIZON := 68.0
const SHELL_PARRY_METEOR := 72.0
const SHELL_BACKSTAB := 45.0
const SHELL_BACKSTAB_HEAVY := 58.0
const SHELL_CHIP_LIGHT := 4.0
const SHELL_CHIP_HEAVY := 11.0
const SHELL_FRONT_DMG_MUL := 0.35
const SHELL_BACK_DMG_MUL := 0.72
const BREACH_GROUND_FRAMES := 180
const REFORGE_PUSH_SPEED := 860.0

const VOLLEY_SPEEDS: Array[float] = [920.0, 1280.0, 1660.0]
const PILLAR_SLAM_BASE := 42.0
const PILLAR_SLAM_SCALE := 0.088
const REPEAT_PILLAR_MUL := 0.78
const ARMOR_SEVER_RATIO := 0.35
const CORE_ATTACK_BONUS := 0.12

const RIFT_LIFE_FRAMES := 210
const RIFT_PURPLE_FX_FRAMES := 26
const RIFT_RED_RADIUS := 230.0
const RIFT_RED_DAMAGE := 24.0
const RIFT_PURPLE_DAMAGE := 330.0
const RIFT_INTERACT_RADIUS := 240.0

const HORIZON_SCAR_DELAY := 15
const HORIZON_DAMAGE := 25.0
const HORIZON_CUT_HEIGHT := 190.0

const WAVE_SPEED := 720.0
const WAVE_HALF_W := 66.0
const WAVE_HEIGHT := 124.0
const WAVE_DAMAGE := 19.0

const NEEDLE_COUNT_P1 := 5
const NEEDLE_COUNT_P2 := 7
const NEEDLE_SPEED := 980.0
const NEEDLE_REFLECT_SPEED := 9600.0
const NEEDLE_DAMAGE := 14.0
const NEEDLE_CUT_RADIUS := 122.0

const ANCHOR_HOLD_FRAMES := 195
const SNARE_LOCK_FRAMES := 56

const WALK_SPEED := 198.0
const CHASE_SPEED := 420.0
const CHASE_FROM := 365.0
const IDLE_RANGE := 290.0
const PLAYER_HALF_W := 30.0
const CLASH_LEAD := 6
const CLASH_GRACE := 4
const BLINK_BEHIND_DIST := 128.0

const INTRO_FRAMES := 88
const INTRO_SKY_HEIGHT := 640.0
const NAIL_RADIUS := 86.0
const NAIL_TRACK := 12
const NAIL_HOLD := 360
const NAIL_COOL := 420
const NAIL_HIGH := 110.0
const TETHER_LEN := 460.0
const YANK_SPEED := 1500.0
const YANK_DAMAGE_MUL := 1.25

# 司晷招式表（融合双向时间倒流、快门倒带回斩、过去锚点、时痕捉影与罗马字碑登高）
const STRINGS: Dictionary = {
	# 1. 主力招牌【逆晷双斩 · 倒带抽刀】：突进直刺留下银白快门残像 -> 2 倍速顺残像倒带退回并倒抽满弓斩 -> 腾空大满月劈！
	&"triple": {"recover": 50, "steps": [
		{"blade": Blade.WHITE, "windup": 22, "strike": 8, "range": 330.0, "lunge": 380.0, "damage": 12.0, "knock": 420.0, "height": 235.0, "leave_echoes": true, "anim": &"lunge_thrust"},
		{"blade": Blade.WHITE, "windup": 18, "strike": 9, "range": 360.0, "lunge": -320.0, "damage": 15.0, "knock": 520.0, "height": 240.0, "rewind_draw": true, "anim": &"rewind_slash"},
		{"blade": Blade.WHITE, "windup": 26, "strike": 10, "range": 375.0, "lunge": 420.0, "damage": 20.0, "knock": 660.0, "height": 260.0, "leap_cleave": true, "anim": &"moon_leap"},
	]},
	# 2. 【5:59 过去锚点 · 狂袭】（原地留可砍碎的银白过去塑像，冲出压制）
	&"chrono_anchor": {"recover": 44, "steps": [
		{"blade": Blade.ANCHOR, "windup": 14, "strike": 6, "range": 0.0, "lunge": 0.0, "damage": 0.0, "knock": 0.0, "height": 0.0, "anim": &"anchor_set"},
		{"blade": Blade.WHITE, "windup": 18, "strike": 9, "range": 355.0, "lunge": 460.0, "damage": 15.0, "knock": 520.0, "height": 240.0, "anim": &"lunge_thrust"},
		{"blade": Blade.WHITE, "windup": 22, "strike": 10, "range": 370.0, "lunge": 360.0, "damage": 18.0, "knock": 620.0, "height": 250.0, "leap_cleave": true, "anim": &"moon_leap"},
	]},
	# 3. 独创机制【逆时捉影 · 倒流玩家 2 秒前位置！】
	&"player_snare": {"recover": 54, "steps": [
		{"blade": Blade.SNARE, "windup": 16, "strike": 6, "range": 0.0, "lunge": 0.0, "damage": 0.0, "knock": 0.0, "height": 0.0, "anim": &"snare_mark"},
		{"blade": Blade.WHITE, "windup": 34, "strike": 10, "range": 420.0, "lunge": 320.0, "damage": 22.0, "knock": 680.0, "height": 240.0, "snare_pull": true, "anim": &"lunge_thrust"},
	]},
	# 4. 格斗差合技【错时退步 · 双针返刺】
	&"backstep_pierce": {"recover": 42, "steps": [
		{"blade": Blade.BACKSTEP, "windup": 10, "strike": 6, "range": 0.0, "lunge": 0.0, "damage": 0.0, "knock": 0.0, "height": 0.0, "anim": &"backstep"},
		{"blade": Blade.WHITE, "windup": 18, "strike": 9, "range": 410.0, "lunge": 540.0, "damage": 18.0, "knock": 590.0, "height": 240.0, "pincer": true, "anim": &"lunge_thrust"},
	]},
	# 5. 立体石碑技【登碑悬针 · 陨星俯冲】（真抛物线跃上 XI/V 罗马字碑 -> 俯射逆流针 -> 跨场陨星重劈）
	&"spire_dive": {"recover": 52, "steps": [
		{"blade": Blade.PERCH, "windup": 44, "strike": 16, "range": 0.0, "lunge": 0.0, "damage": 0.0, "knock": 0.0, "height": 0.0, "anim": &"perch"},
		{"blade": Blade.WHITE, "windup": 54, "strike": 10, "range": 380.0, "lunge": 0.0, "damage": 22.0, "knock": 700.0, "height": 300.0, "meteor": true, "anim": &"moon_leap"},
	]},
	# 6. 全屏极速居合【断晷一线 · 瞬狱绝影】
	&"horizon_cut": {"recover": 56, "steps": [
		{"blade": Blade.HORIZON, "windup": 34, "strike": 10, "range": 960.0, "lunge": 0.0, "damage": HORIZON_DAMAGE, "knock": 660.0, "height": HORIZON_CUT_HEIGHT, "anim": &"iai"},
	]},
	# 7. 红光危招【逆摆满月 · 黑银钟波】
	&"sweep": {"recover": 54, "steps": [
		{"blade": Blade.RED, "windup": 38, "strike": 12, "range": 440.0, "lunge": 520.0, "damage": 24.0, "knock": 720.0, "height": 165.0, "spawn_wave": true, "anim": &"iai_flourish"},
	]},
	# 8. 【坠针凝滞 · 逆流拔刺】
	&"rain_needles": {"recover": 48, "steps": [
		{"blade": Blade.NEEDLES, "windup": 30, "strike": 10, "range": 0.0, "lunge": 0.0, "damage": NEEDLE_DAMAGE, "knock": 420.0, "height": 180.0, "anim": &"needles"},
	]},
	&"counter": {"recover": 26, "steps": [
		{"blade": Blade.WHITE, "windup": 18, "strike": 8, "range": 350.0, "lunge": 350.0, "damage": 14.0, "knock": 520.0, "height": 240.0, "anim": &"rewind_slash"},
	]},
	&"anti_air": {"recover": 40, "steps": [
		{"blade": Blade.WHITE, "windup": 20, "strike": 10, "range": 345.0, "lunge": 230.0, "damage": 17.0, "knock": 560.0, "height": 460.0, "leap": true, "anti_air": true, "anim": &"moon_leap"},
	]},
	&"white_red": {"recover": 54, "steps": [
		{"blade": Blade.WHITE, "windup": 24, "strike": 8, "range": 335.0, "lunge": 330.0, "damage": 11.0, "knock": 420.0, "height": 240.0, "anim": &"lunge_thrust"},
		{"blade": Blade.WHITE, "windup": 18, "strike": 8, "range": 335.0, "lunge": 330.0, "damage": 12.0, "knock": 420.0, "height": 240.0, "blink": true, "anim": &"rewind_slash"},
		{"blade": Blade.RED, "windup": 32, "strike": 12, "range": 415.0, "lunge": 540.0, "damage": 24.0, "knock": 720.0, "height": 170.0, "leap": true, "tear_rift_p2": true, "anim": &"iai_flourish"},
	]},
	&"nail": {"recover": 78, "steps": [
		{"blade": Blade.NAIL, "windup": 38, "strike": 8, "range": 0.0, "lunge": 0.0, "damage": 22.0, "knock": 620.0, "height": 170.0, "anim": &"nail"},
	]},
	&"red_rift": {"recover": 64, "steps": [
		{"blade": Blade.RIFT, "windup": 34, "strike": 10, "range": 380.0, "lunge": 220.0, "damage": 22.0, "knock": 620.0, "height": 220.0, "leap": true, "anim": &"rift_tear"},
	]},
	&"sever_tide": {"recover": 60, "steps": [
		{"blade": Blade.WHITE, "windup": 22, "strike": 6, "range": 365.0, "lunge": 370.0, "damage": 14.0, "knock": 460.0, "height": 240.0, "blink": true, "leave_echoes": true, "anim": &"lunge_thrust"},
		{"blade": Blade.WHITE, "windup": 16, "strike": 6, "range": 365.0, "lunge": 370.0, "damage": 14.0, "knock": 460.0, "height": 240.0, "blink": true, "rewind_draw": true, "anim": &"rewind_slash"},
		{"blade": Blade.RIFT, "windup": 30, "strike": 10, "range": 425.0, "lunge": 470.0, "damage": 26.0, "knock": 740.0, "height": 250.0, "leap_cleave": true, "anim": &"moon_leap"},
	]},
}

const PLANS: Array = [
	[&"triple", &"chrono_anchor", &"player_snare", &"spire_dive", &"horizon_cut", &"sweep"],
	[&"chrono_anchor", &"triple", &"spire_dive", &"player_snare", &"backstep_pierce", &"rain_needles"],
	[&"sever_tide", &"chrono_anchor", &"player_snare", &"spire_dive", &"horizon_cut", &"red_rift"],
]

var _atlas_tex: Texture2D
var _atlas_edge_tex: Texture2D
var _atlas_sil_tex: Texture2D
var _vfx_tex: Texture2D

var state_chart: StateChart
var _sc_phase1: AtomicState
var _sc_phase2: AtomicState
var _sc_shell_intact: AtomicState
var _sc_shell_broken: AtomicState
var _sc_rift_idle: AtomicState
var _sc_rift_active: AtomicState
var _sc_rift_purple: AtomicState

var _tail_anchor: Node2D
var wiggly_tail: WigglyAppendage2D

var dodge: Node = null
var air_rules: Node = null
var is_phase2: bool = false
var shell: float = MAX_SHELL
var is_shell_broken: bool = false
var breach_ground_frames: int = 0
var _breach_was_launched: bool = false
var breach_damage_dealt: float = 0.0
var _breach_severed: bool = false
var core_drops: int = 0
var breach_volley_count: int = 0
var last_fling_speed: float = 0.0
var pursuit_slashes: int = 0
var _breach_pillar_slams: int = 0
var _turn_lock_frames: int = 0

var rift_state: int = Rift.NONE
var rift_pos: Vector2 = Vector2.ZERO
var rift_timer: int = 0
var dyed_rift_count: int = 0
var _rift_consumed_serial: int = -1
var _parrying_rift_only: bool = false
var _parrying_horizon_only: bool = false

# 双向时间倒流核心运行态
var chrono_anchor_active: bool = false
var chrono_anchor_pos: Vector2 = Vector2.ZERO
var chrono_anchor_facing: int = -1
var chrono_anchor_frame: int = 70
var chrono_anchor_timer: int = 0

var player_snare_active: bool = false
var player_snare_pos: Vector2 = Vector2.ZERO
var player_snare_facing: int = 1
var player_snare_timer: int = 0
var _snare_just_pulled_frames: int = 0

var _shutter_history: Array[Dictionary] = []  ## 常态错时快门重影队列 [{pos, frame, facing}]
var _rewind_Origin_x: float = 0.0
var _rewinding_step_frames: int = 0

# 真抛物线登碑与陨星俯冲运行态
var _perch_jumping: bool = false
var _perch_jump_from := Vector2.ZERO
var _perch_jump_to := Vector2.ZERO
var _perch_side: int = 0
var _meteor_dive_from := Vector2.ZERO
var _meteor_dive_to := Vector2.ZERO
var _meteor_diving: bool = false

var eclipse_want: float = 0.0
var _horizon_aim_to_x: float = 0.0
var _horizon_scar: Dictionary = {}
var _waves: Array = []
var _rain_needles: Array = []
var needles_cut: int = 0
var _afterimages: Array = []
var _clash_sparks: Array = []
var _wall_slam_pose_frames: int = 0
var _reforge_pose_frames: int = 0
var _parry_stagger_frames: int = 0
var _evade_frames: int = 0
var _anti_air_cool: int = 0
var _spire_dive_cool: int = 0
var _anchor_cool: int = 0
var _snare_cool: int = 0
var _clash_cancel_cool: int = 0
var _recent_strings: Array[StringName] = []

var strings_finished: int = 0
var _plan_index: int = 0
var _string_id: StringName = &""
var _steps: Array = []
var _step: int = 0
var _cur: Dictionary = {}
var _clashes: int = 0
var _blade_age: int = 999
var _countered: bool = false
var early_hits: int = 0
var _prev_vy: float = 0.0
var _pre_vy: float = 0.0

var intro_frames: int = 0
var _intro_ground: float = 0.0
var _intro_land_slammed: bool = false
var nail_phase: int = Nail.NONE
var nail_point: Vector2 = Vector2.ZERO
var nail_frames: int = 0
var yanking: bool = false
var yanks: int = 0
var _yank_side: float = 0.0
var _nail_cool: int = 0

func apply_boss_stats(fy: float, hp_mul: float = 1.0) -> void:
	spawn_frames = 0
	max_hp = MAX_HP * hp_mul
	hp = max_hp
	max_shell = MAX_SHELL
	shell = MAX_SHELL
	shell_hp = 0.0
	is_shell_broken = false
	half_w = 50.0
	half_h = 140.0
	position.y = fy - half_h
	spec.speed = WALK_SPEED
	spec.range = IDLE_RANGE
	spec.armor = true
	spec.hue = Color(0.06, 0.06, 0.08)
	spec.eye = Color(0.96, 0.98, 1.0)
	_wall_factor = 1.0


func setup(k: int, tgt: Node2D, fy: float, hp_mul: float = 1.0) -> void:
	super(k, tgt, fy, hp_mul)
	apply_boss_stats(fy, hp_mul)
	_load_sprite_atlas()
	_setup_state_chart()
	_setup_wiggly_tail()


func _load_img_tex(path: String) -> Texture2D:
	var gpath := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(gpath):
		var img := Image.load_from_file(gpath)
		if img != null and not img.is_empty():
			return ImageTexture.create_from_image(img)
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


func _load_sprite_atlas() -> void:
	var diff := _load_img_tex(ATLAS_TEX_PATH)
	var norm := _load_img_tex(ATLAS_NORM_PATH)
	if diff != null and norm != null:
		var ct := CanvasTexture.new()
		ct.diffuse_texture = diff
		ct.normal_texture = norm
		ct.specular_color = Color(0.95, 0.56, 0.50)
		ct.specular_shininess = 0.58
		_atlas_tex = ct
	else:
		_atlas_tex = diff
	_atlas_edge_tex = _load_img_tex(ATLAS_EDGE_PATH)
	_atlas_sil_tex = _load_img_tex(ATLAS_SIL_PATH)
	_vfx_tex = _load_img_tex(VFX_TEX_PATH)


func has_hd_sprite_atlas() -> bool:
	return _atlas_tex != null and _atlas_edge_tex != null


func is_rewinding_visual() -> bool:
	return _rewinding_step_frames > 0 or _snare_just_pulled_frames > 0


func _setup_state_chart() -> void:
	if state_chart != null:
		return
	state_chart = StateChart.new()
	state_chart.name = "BossStateChart"
	state_chart.track_in_editor = false
	add_child(state_chart)

	var root_par := ParallelState.new()
	root_par.name = "BossBrain"
	state_chart.add_child(root_par)

	var phase_comp := CompoundState.new()
	phase_comp.name = "PhaseTrack"
	root_par.add_child(phase_comp)
	_sc_phase1 = AtomicState.new()
	_sc_phase1.name = "Phase1"
	phase_comp.add_child(_sc_phase1)
	_sc_phase2 = AtomicState.new()
	_sc_phase2.name = "Phase2"
	phase_comp.add_child(_sc_phase2)
	phase_comp.initial_state = phase_comp.get_path_to(_sc_phase1)
	_add_sc_transition(_sc_phase1, _sc_phase2, &"enter_phase2")
	_add_sc_transition(_sc_phase2, _sc_phase1, &"reset_boss")

	var shell_comp := CompoundState.new()
	shell_comp.name = "ShellTrack"
	root_par.add_child(shell_comp)
	_sc_shell_intact = AtomicState.new()
	_sc_shell_intact.name = "ShellIntact"
	shell_comp.add_child(_sc_shell_intact)
	_sc_shell_broken = AtomicState.new()
	_sc_shell_broken.name = "ShellBroken"
	shell_comp.add_child(_sc_shell_broken)
	shell_comp.initial_state = shell_comp.get_path_to(_sc_shell_intact)
	_add_sc_transition(_sc_shell_intact, _sc_shell_broken, &"shatter_shell")
	_add_sc_transition(_sc_shell_broken, _sc_shell_intact, &"reforge_shell")
	_add_sc_transition(_sc_shell_broken, _sc_shell_intact, &"shell_reforged")
	_add_sc_transition(_sc_shell_broken, _sc_shell_intact, &"reset_boss")

	var rift_comp := CompoundState.new()
	rift_comp.name = "RiftTrack"
	root_par.add_child(rift_comp)
	_sc_rift_idle = AtomicState.new()
	_sc_rift_idle.name = "RiftIdle"
	rift_comp.add_child(_sc_rift_idle)
	_sc_rift_active = AtomicState.new()
	_sc_rift_active.name = "RiftActive"
	rift_comp.add_child(_sc_rift_active)
	_sc_rift_purple = AtomicState.new()
	_sc_rift_purple.name = "PurpleRiftBurst"
	rift_comp.add_child(_sc_rift_purple)
	rift_comp.initial_state = rift_comp.get_path_to(_sc_rift_idle)
	_add_sc_transition(_sc_rift_idle, _sc_rift_active, &"open_red_rift")
	_add_sc_transition(_sc_rift_active, _sc_rift_purple, &"dye_purple")
	_add_sc_transition(_sc_rift_active, _sc_rift_idle, &"close_rift")
	_add_sc_transition(_sc_rift_purple, _sc_rift_idle, &"close_rift")
	_add_sc_transition(_sc_rift_active, _sc_rift_idle, &"reset_boss")
	_add_sc_transition(_sc_rift_purple, _sc_rift_idle, &"reset_boss")


func _add_sc_transition(from_st: StateChartState, to_st: StateChartState, event_name: StringName) -> void:
	var tr := Transition.new()
	tr.name = String(event_name)
	tr.event = event_name
	from_st.add_child(tr)
	tr.to = tr.get_path_to(to_st)


func _setup_wiggly_tail() -> void:
	if wiggly_tail != null:
		return
	_tail_anchor = Node2D.new()
	_tail_anchor.name = "RibbonAnchor"
	add_child(_tail_anchor)
	wiggly_tail = WigglyAppendage2D.new()
	wiggly_tail.name = "WigglyInkRibbon"
	wiggly_tail.only_process_when_visible = false
	wiggly_tail.segment_count = 7
	wiggly_tail.segment_length = 28.0
	wiggly_tail.curvature = -0.18
	wiggly_tail.curvature_exponent = 1.15
	wiggly_tail.stiffness = 14.0
	wiggly_tail.damping = 4.2
	wiggly_tail.max_angular_momentum = 10.0
	wiggly_tail.additional_start_segment = true
	wiggly_tail.subdivision = 2
	wiggly_tail.width = 14.0
	wiggly_tail.default_color = Color(0.02, 0.02, 0.03, 0.0)
	_tail_anchor.add_child(wiggly_tail)
	_sync_tail_pose()


func _sync_tail_pose() -> void:
	if _tail_anchor == null or wiggly_tail == null:
		return
	var f := float(facing)
	_tail_anchor.position = Vector2(-f * half_w * 0.55, -half_h * 0.35)
	_tail_anchor.rotation = -0.85 if facing < 0 else (PI + 0.85)
	wiggly_tail.default_color = Color(0.02, 0.02, 0.03, 0.0)


func is_breach_severed() -> bool:
	return _breach_severed


func is_armored() -> bool:
	if is_shell_broken:
		return false
	return bool(spec.armor) and is_attacking()


func is_open() -> bool:
	return is_shell_broken and state in [State.RECOVER, State.IDLE, State.APPROACH, State.HITSTUN] and spawn_frames <= 0 and intro_frames <= 0


func blade_kind() -> int:
	return int(_cur.get("blade", Blade.WHITE))


func _combat_target_ok() -> bool:
	if intro_frames > 0 or target == null or not is_instance_valid(target):
		return false
	var st = target.get(&"state")
	return st == null or int(st) != 4


func reset_boss_state() -> void:
	release_nail()
	spawn_frames = 0
	is_phase2 = false
	max_hp = MAX_HP
	hp = max_hp
	max_shell = MAX_SHELL
	shell = MAX_SHELL
	shell_hp = 0.0
	is_shell_broken = false
	spec.armor = true
	breach_ground_frames = 0
	_breach_was_launched = false
	breach_damage_dealt = 0.0
	_breach_severed = false
	core_drops = 0
	breach_volley_count = 0
	last_fling_speed = 0.0
	pursuit_slashes = 0
	_breach_pillar_slams = 0
	_turn_lock_frames = 0
	rift_state = Rift.NONE
	rift_timer = 0
	dyed_rift_count = 0
	_rift_consumed_serial = -1
	_parrying_rift_only = false
	_parrying_horizon_only = false
	chrono_anchor_active = false
	chrono_anchor_timer = 0
	player_snare_active = false
	player_snare_timer = 0
	_snare_just_pulled_frames = 0
	_shutter_history.clear()
	_rewinding_step_frames = 0
	_perch_jumping = false
	_perch_side = 0
	_meteor_diving = false
	eclipse_want = 0.0
	_horizon_scar.clear()
	_waves.clear()
	_rain_needles.clear()
	needles_cut = 0
	_afterimages.clear()
	_clash_sparks.clear()
	_wall_slam_pose_frames = 0
	_reforge_pose_frames = 0
	_parry_stagger_frames = 0
	_evade_frames = 0
	_anti_air_cool = 0
	_spire_dive_cool = 0
	_anchor_cool = 0
	_snare_cool = 0
	_clash_cancel_cool = 0
	_recent_strings.clear()
	_countered = false
	early_hits = 0
	if state_chart != null:
		state_chart.send_event(&"reset_boss")
	_sync_tail_pose()


func _physics_process(delta: float) -> void:
	if spawn_frames > 0:
		spawn_frames = 0
	if intro_frames > 0:
		_process_intro(delta)
		_sync_tail_pose()
		return
	if _turn_lock_frames > 0:
		_turn_lock_frames -= 1
	if _wall_slam_pose_frames > 0:
		_wall_slam_pose_frames -= 1
	if _reforge_pose_frames > 0:
		_reforge_pose_frames -= 1
	if _parry_stagger_frames > 0:
		_parry_stagger_frames -= 1
	if _evade_frames > 0:
		_evade_frames -= 1
	if _rewinding_step_frames > 0:
		_rewinding_step_frames -= 1
	if _snare_just_pulled_frames > 0:
		_snare_just_pulled_frames -= 1
	if _anti_air_cool > 0:
		_anti_air_cool -= 1
	if _spire_dive_cool > 0:
		_spire_dive_cool -= 1
	if _anchor_cool > 0:
		_anchor_cool -= 1
	if _snare_cool > 0:
		_snare_cool -= 1
	if _clash_cancel_cool > 0:
		_clash_cancel_cool -= 1
	_nail_cool = maxi(_nail_cool - 1, 0)

	_record_shutter_echo()
	_update_perch_and_meteor_motion()
	_update_chrono_anchor()
	_update_player_snare()
	_update_nail()
	_update_rift()
	_update_horizon_scar()
	_update_waves(delta)
	_update_rain_needles(delta)
	_update_afterimages(delta)
	_update_clash_sparks(delta)
	_update_eclipse_want()
	_track_blade()

	if state == State.LAUNCHED:
		_breach_was_launched = true
		if hitstop_frames <= 0:
			if _prev_vy < 0.0 and velocity.y >= 0.0 and air_rules != null and bool(air_rules.rules.beat_check):
				flash = maxi(flash, 3)
				flash_color = Color(1.0, 1.0, 1.0)
				apex_reached.emit(global_position + Vector2(0.0, -half_h))
			_prev_vy = velocity.y
	else:
		early_hits = 0
		_prev_vy = 0.0
		if is_shell_broken and not _breach_was_launched and state != State.DOWN and state != State.DEAD and hitstop_frames <= 0:
			breach_ground_frames -= 1
			if breach_ground_frames <= 0:
				_reforge_shell()

	super(delta)
	_sync_tail_pose()


func _record_shutter_echo() -> void:
	if state == State.DEAD:
		return
	_shutter_history.push_back({
		"pos": position,
		"frame": _pick_atlas_frame(),
		"facing": facing,
	})
	if _shutter_history.size() > 16:
		_shutter_history.pop_front()


func _update_eclipse_want() -> void:
	if state == State.WINDUP and (_string_id == &"horizon_cut" or _string_id == &"sever_tide"):
		eclipse_want = clampf(0.24 + 0.32 * telegraph(), 0.0, 0.52)
	elif state == State.STRIKE and (_string_id == &"horizon_cut" or _string_id == &"sever_tide"):
		eclipse_want = 0.45
	elif not _horizon_scar.is_empty() and bool(_horizon_scar.get("active", false)):
		eclipse_want = 0.35
	else:
		eclipse_want = 0.0


func _push_afterimage(pos: Vector2, frame_idx: int, face_dir: int, tint_col := Color(0.92, 0.95, 1.0, 0.46), dur := 0.26) -> void:
	_afterimages.append({
		"pos": pos,
		"frame": frame_idx,
		"facing": face_dir,
		"life": 0.0,
		"max_life": dur,
		"tint": tint_col,
	})


func _update_afterimages(delta: float) -> void:
	var i := _afterimages.size() - 1
	while i >= 0:
		var g: Dictionary = _afterimages[i]
		g.life = float(g.life) + delta
		if float(g.life) >= float(g.max_life):
			_afterimages.remove_at(i)
		i -= 1


func spawn_clash_spark(world_pt: Vector2, sc: float = 0.72) -> void:
	_clash_sparks.append({
		"pos": world_pt,
		"life": 0.0,
		"max_life": 0.16,
		"rot": randf_range(-0.35, 0.35),
		"sc": sc,
	})
	queue_redraw()


func _update_clash_sparks(delta: float) -> void:
	if _clash_sparks.is_empty():
		return
	var i := _clash_sparks.size() - 1
	while i >= 0:
		var sp: Dictionary = _clash_sparks[i]
		sp.life = float(sp.life) + delta
		if float(sp.life) >= float(sp.max_life):
			_clash_sparks.remove_at(i)
		i -= 1
	queue_redraw()


# ---------------------------------------------------------------- 破顶天降贯刃登场

func begin_intro() -> void:
	spawn_frames = 0
	intro_frames = INTRO_FRAMES
	_intro_land_slammed = false
	state = State.IDLE
	velocity = Vector2.ZERO
	_intro_ground = floor_y - half_h
	position.y = _intro_ground - INTRO_SKY_HEIGHT


func skip_intro() -> void:
	if intro_frames <= 0:
		return
	intro_frames = 1
	_process_intro(0.0)


func _process_intro(delta: float) -> void:
	intro_frames -= 1
	anim_t += delta
	var t := 1.0 - float(intro_frames) / float(INTRO_FRAMES)
	if t < 0.28:
		var u := t / 0.28
		position.y = _intro_ground - INTRO_SKY_HEIGHT - sin(u * PI * 0.5) * 24.0
	elif t < 0.62:
		var u := clampf((t - 0.28) / 0.34, 0.0, 1.0)
		position.y = _intro_ground - INTRO_SKY_HEIGHT - 24.0 + (INTRO_SKY_HEIGHT + 24.0) * (u * u * u)
		if int(intro_frames) % 3 == 0:
			_push_afterimage(position, 72, facing, Color(0.95, 0.97, 1.0, 0.40), 0.18)
	else:
		position.y = _intro_ground
		if not _intro_land_slammed:
			_intro_land_slammed = true
			squash = Vector2(1.22, 0.80)
			intro_slammed.emit()
		else:
			squash = squash.lerp(Vector2.ONE, 0.22)

	if _target_ok():
		facing = 1 if target.global_position.x > global_position.x else -1
	if intro_frames <= 0:
		position.y = _intro_ground
		squash = Vector2.ONE
		cooldown = 20
		if not _intro_land_slammed:
			_intro_land_slammed = true
			intro_slammed.emit()
		intro_done.emit()
	queue_redraw()


# ---------------------------------------------------------------- 双向时间倒流机制一：5:59 过去锚点 & 斩断断轨自爆！

func spawn_chrono_anchor() -> void:
	chrono_anchor_active = true
	chrono_anchor_pos = Vector2(global_position.x, feet_y())
	chrono_anchor_facing = facing
	chrono_anchor_frame = 70
	chrono_anchor_timer = ANCHOR_HOLD_FRAMES
	_anchor_cool = 360
	anchor_spawned.emit(chrono_anchor_pos)
	queue_redraw()


func shatter_chrono_anchor(attacker: Node = null) -> bool:
	if not chrono_anchor_active or state == State.DEAD:
		return false
	var a_pos := chrono_anchor_pos
	chrono_anchor_active = false
	chrono_anchor_timer = 0
	# 时间断轨自爆：首领被银线逆向扯动撞进碎裂虚空，当场炸空整管驻时棱壳并跪地破防！
	_rewinding_step_frames = 18
	_push_afterimage(position, _pick_atlas_frame(), facing, Color(0.84, 0.48, 1.0, 0.58), 0.30)
	position.x = lerpf(position.x, a_pos.x, 0.45)
	var dir := 1
	if attacker != null and is_instance_valid(attacker) and attacker is Node2D:
		dir = 1 if global_position.x > (attacker as Node2D).global_position.x else -1
	_finish_string()
	if not is_shell_broken:
		_shatter_shell(global_position, dir)
	else:
		_apply_damage(110.0)
	_parry_stagger_frames = 54
	state = State.HITSTUN
	state_frames = 54
	spec.recover = 54
	anchor_derailed.emit(global_position + Vector2(0.0, -half_h * 0.4))
	queue_redraw()
	return true


func _update_chrono_anchor() -> void:
	if not chrono_anchor_active:
		return
	if state == State.DEAD or state == State.LAUNCHED:
		chrono_anchor_active = false
		return
	chrono_anchor_timer -= 1
	if chrono_anchor_timer <= 0:
		# 未被玩家斩碎：发动时间倒流瞬移回过去锚点并倒流修复 32 点棱壳！
		chrono_anchor_active = false
		_rewinding_step_frames = 20
		for k in 4:
			var u := float(k) / 4.0
			_push_afterimage(position.lerp(Vector2(chrono_anchor_pos.x, position.y), u), 70, facing, Color(0.94, 0.97, 1.0, 0.45), 0.24)
		position.x = clampf(chrono_anchor_pos.x, arena_left + 90.0, arena_right - 90.0)
		if not is_shell_broken:
			shell = minf(MAX_SHELL, shell + 32.0)
		queue_redraw()


# ---------------------------------------------------------------- 双向时间倒流机制二：逆时捉影（将玩家倒流回 2 秒前白影！）

func stamp_player_rewind_snare() -> void:
	if not _combat_target_ok():
		return
	player_snare_active = true
	player_snare_pos = target.global_position
	player_snare_facing = int(target.get(&"facing")) if target.get(&"facing") != null else 1
	player_snare_timer = SNARE_LOCK_FRAMES
	_snare_cool = 420
	player_snare_stamped.emit(player_snare_pos)
	queue_redraw()


func _player_has_dodge_iframes() -> bool:
	if dodge != null and bool(dodge.call(&"counts_as_dodge")):
		return true
	if _combat_target_ok() and target.has_method(&"is_short_dashing") and bool(target.call(&"is_short_dashing")):
		return true
	return false


func _update_player_snare() -> void:
	if not player_snare_active:
		return
	if state == State.DEAD or is_shell_broken or not _combat_target_ok():
		player_snare_active = false
		return
	player_snare_timer -= 1
	# 玩家在最后 16 帧窗口按 Shift 瞬步或双击 A/D 短闪可直接扯断时间银线！
	if player_snare_timer <= 16 and _player_has_dodge_iframes():
		player_snare_active = false
		if dodge != null and dodge.has_method(&"arm_heavy"):
			dodge.call(&"arm_heavy")
		player_snare_severed.emit(target.global_position)
		queue_redraw()
		return
	if player_snare_timer <= 0:
		_execute_player_rewind_pull()


func _execute_player_rewind_pull() -> void:
	player_snare_active = false
	if not _combat_target_ok():
		return
	_snare_just_pulled_frames = 16
	_rewinding_step_frames = 16
	target.global_position = Vector2(
		clampf(player_snare_pos.x, arena_left + 50.0, arena_right - 50.0),
		player_snare_pos.y
	)
	# 若玩家迎着倒流冲力按下弹刀 (L)，或正处于近身交锋碰刀帧 -> 触发「超音速迎面崩刃」！
	var is_parry_stance := target.has_method(&"is_parrying") and bool(target.call(&"is_parrying"))
	var close_clash := _blade_age <= CLASH_GRACE and absf(target.global_position.x - global_position.x) <= 440.0
	if is_parry_stance or close_clash:
		trigger_supersonic_rewind_parry()
	queue_redraw()


func trigger_supersonic_rewind_parry() -> void:
	var clash_pt := (global_position + (target.global_position if _combat_target_ok() else global_position)) * 0.5 + Vector2(0.0, -68.0)
	player_snare_active = false
	_finish_string()
	spawn_clash_spark(clash_pt, 1.15)
	var dir := 1
	if _combat_target_ok():
		dir = 1 if global_position.x > target.global_position.x else -1
	if not is_shell_broken:
		_shatter_shell(clash_pt, dir)
	_apply_damage(95.0)
	_parry_stagger_frames = 64
	state = State.HITSTUN
	state_frames = 64
	hitstop_frames = maxi(hitstop_frames, 10)
	supersonic_rewind_parried.emit(clash_pt)
	queue_redraw()


# ---------------------------------------------------------------- 驻时棱壳：碎壳与重铸气浪

func is_backstab_from(from_facing: int, attacker: Node) -> bool:
	if attacker != null and is_instance_valid(attacker) and attacker is Node2D:
		var dx := (attacker as Node2D).global_position.x - global_position.x
		return dx * float(facing) < -6.0
	return from_facing == facing


func is_heavy_slash(mv: MoveDefinition, charge_t: float, damage_mul: float, attacker: Node = null) -> bool:
	if charge_t > 0.15 or damage_mul > 1.25:
		return true
	if dodge != null and dodge.has_method(&"is_heavy") and bool(dodge.call(&"is_heavy")):
		return true
	if attacker != null and attacker.has_method(&"is_charging") and bool(attacker.call(&"is_charging")):
		return true
	if mv == null:
		return false
	if mv.id in [&"dash_slash", &"dash_slash_left", &"air_dash_slash", &"air_dash_slash_left", &"charge_slash", &"plunge", &"ult", &"light_3", &"air_light_3"]:
		return true
	return mv.damage >= 24.0 or mv.knockback >= 460.0


func damage_shell(amount: float, point: Vector2, from_facing: int, is_backstab: bool = false) -> bool:
	if is_shell_broken or state == State.DEAD:
		return false
	shell = maxf(0.0, shell - amount)
	armor_flash = 10
	shell_damaged.emit(amount, shell, is_backstab, point)
	if shell <= 0.0:
		_shatter_shell(point, from_facing)
		return true
	return false


func _shatter_shell(point: Vector2, from_facing: int) -> void:
	shell = 0.0
	shell_hp = 0.0
	is_shell_broken = true
	spec.armor = false
	chrono_anchor_active = false
	player_snare_active = false
	breach_ground_frames = BREACH_GROUND_FRAMES
	_breach_was_launched = false
	breach_damage_dealt = 0.0
	_breach_severed = false
	breach_volley_count = 0
	pursuit_slashes = 0
	_breach_pillar_slams = 0
	_meteor_diving = false
	_perch_jumping = false
	_parry_stagger_frames = 36

	flash = 9
	flash_color = Color(0.96, 0.98, 1.0)
	squash = Vector2(0.76, 1.26)
	hitstop_frames = maxi(hitstop_frames, roundi(12 * hitstop_multiplier))
	_finish_string()
	state = State.HITSTUN
	state_frames = 46
	spec.recover = 46
	velocity = Vector2(float(from_facing) * 230.0, 0.0)
	if state_chart != null:
		state_chart.send_event(&"shatter_shell")
	shell_shattered.emit(point)


func _reforge_shell() -> void:
	if not is_shell_broken or state == State.DEAD:
		return
	is_shell_broken = false
	max_shell = MAX_SHELL
	shell = MAX_SHELL
	shell_hp = 0.0
	spec.armor = true
	breach_ground_frames = 0
	_breach_was_launched = false
	breach_volley_count = 0
	_reforge_pose_frames = 30
	_rewinding_step_frames = 20
	flash = 6
	flash_color = Color(0.95, 0.97, 1.0)
	squash = Vector2(1.24, 0.80)
	if state_chart != null:
		state_chart.send_event(&"reforge_shell")

	var wave_origin := global_position + Vector2(0.0, -half_h * 0.3)
	if _combat_target_ok():
		var dx := target.global_position.x - global_position.x
		if absf(dx) < 350.0:
			var push_dir := 1.0 if dx >= 0.0 else -1.0
			if dx == 0.0:
				push_dir = -float(facing)
			if "velocity" in target:
				target.velocity.x = push_dir * REFORGE_PUSH_SPEED
				if target.has_method(&"is_on_floor") and bool(target.call(&"is_on_floor")):
					target.velocity.y = minf(target.velocity.y, -190.0)
			var target_nx := clampf(global_position.x + push_dir * 270.0, arena_left + 48.0, arena_right - 48.0)
			if absf(dx) < 220.0:
				target.global_position.x = target_nx
	shell_reforged_wave.emit(wave_origin)


func _floor_impact() -> void:
	super()
	if is_shell_broken and state != State.DEAD and state == State.DOWN:
		_reforge_shell()


# ---------------------------------------------------------------- 二阶段觉醒与逆时裂隙（重斩染紫反杀）

func _apply_damage(amount: float) -> void:
	if amount <= 0.0 or state == State.DEAD:
		return
	var prev_hp := hp
	super(amount)
	var actual := maxf(0.0, prev_hp - hp)
	if is_shell_broken and actual > 0.0:
		breach_damage_dealt += actual
		if not _breach_severed and breach_damage_dealt >= max_hp * ARMOR_SEVER_RATIO:
			_trigger_armor_sever()
	if not is_phase2 and hp > 0.0 and hp <= max_hp * PHASE2_HP_RATIO:
		_enter_phase2()


func _trigger_armor_sever() -> void:
	_breach_severed = true
	core_drops += 1
	flash = 10
	flash_color = Color(1.0, 1.0, 1.0)
	squash = Vector2(0.72, 1.32)
	hitstop_frames = maxi(hitstop_frames, roundi(14 * hitstop_multiplier))
	armor_severed.emit(global_position + Vector2(0.0, -half_h * 0.5), core_drops)


func _enter_phase2() -> void:
	is_phase2 = true
	_plan_index = 2
	_reforge_pose_frames = 30
	_rewinding_step_frames = 28
	spec.hue = Color(0.05, 0.05, 0.07)
	spec.eye = Color(0.96, 0.28, 0.24)
	flash = 10
	flash_color = Color(0.96, 0.34, 0.30)
	squash = Vector2(1.28, 0.76)
	if is_shell_broken:
		_reforge_shell()
	else:
		shell = MAX_SHELL
	if state_chart != null:
		state_chart.send_event(&"enter_phase2")
	phase2_started.emit()


func open_red_rift(world_pos: Vector2) -> void:
	var rx := clampf(world_pos.x, arena_left + 130.0, arena_right - 130.0)
	var ry := clampf(world_pos.y, floor_y - 240.0, floor_y - 108.0)
	rift_pos = Vector2(rx, ry)
	rift_state = Rift.ACTIVE
	rift_timer = RIFT_LIFE_FRAMES
	_rift_consumed_serial = -1
	if state_chart != null:
		state_chart.send_event(&"open_red_rift")
	rift_opened.emit(rift_pos)
	queue_redraw()


func dye_rift_purple(attacker: Node = null) -> bool:
	if rift_state != Rift.ACTIVE or state == State.DEAD:
		return false
	rift_state = Rift.PURPLE
	rift_timer = RIFT_PURPLE_FX_FRAMES
	dyed_rift_count += 1
	if state_chart != null:
		state_chart.send_event(&"dye_purple")

	var dir := -facing
	if attacker != null and is_instance_valid(attacker) and attacker is Node2D:
		dir = 1 if global_position.x > (attacker as Node2D).global_position.x else -1

	if not is_shell_broken:
		_shatter_shell(rift_pos, dir)

	var mul := 1.0 + float(core_drops) * CORE_ATTACK_BONUS
	var boom_dmg := RIFT_PURPLE_DAMAGE * mul
	_apply_damage(boom_dmg)
	last_hit_damage = boom_dmg
	damaged.emit(boom_dmg, hp, rift_pos)

	if hp <= 0.0:
		rift_dyed_exploded.emit(rift_pos, boom_dmg)
		_die(dir)
		return true

	state = State.LAUNCHED
	_breach_was_launched = true
	driven_frames = 14
	chain_armed = true
	velocity = Vector2(float(dir) * 860.0, -540.0)
	hitstop_frames = maxi(hitstop_frames, roundi(14 * hitstop_multiplier))
	flash = 10
	flash_color = Color(0.76, 0.34, 1.0)
	rift_dyed_exploded.emit(rift_pos, boom_dmg)
	queue_redraw()
	return true


func _update_rift() -> void:
	if rift_state == Rift.NONE:
		return
	if state == State.DEAD:
		if rift_state == Rift.PURPLE and rift_timer > 0:
			rift_timer -= 1
			if rift_timer <= 0:
				_close_rift()
			queue_redraw()
			return
		_close_rift()
		return
	if rift_state == Rift.ACTIVE:
		if _check_player_interacts_rift():
			return
		rift_timer -= 1
		if rift_timer <= 0:
			_detonate_red_rift()
	elif rift_state == Rift.PURPLE:
		rift_timer -= 1
		if rift_timer <= 0:
			_close_rift()
	queue_redraw()


func _check_player_interacts_rift() -> bool:
	if not _combat_target_ok():
		return false
	var p_center := target.global_position + Vector2(0.0, -48.0)
	var dist := p_center.distance_to(rift_pos)
	if target.has_method(&"is_parrying") and bool(target.call(&"is_parrying")) and dist <= RIFT_INTERACT_RADIUS:
		_trigger_rift_parry(rift_pos)
		return true
	if int(target.get(&"state")) == int(target.State.ATTACK):
		var mv: MoveDefinition = target.get(&"current_move")
		var mf: int = int(target.get(&"move_frame"))
		var serial_v = target.get(&"action_serial")
		var serial: int = int(serial_v) if serial_v != null else int(target.get(&"move_frame"))
		if mv != null and serial != _rift_consumed_serial and mv.phase_at(mf) == &"active":
			var pf := float(target.get(&"facing"))
			var reach_pt := p_center + Vector2(pf * 80.0, 0.0)
			if dist <= RIFT_INTERACT_RADIUS or reach_pt.distance_to(rift_pos) <= RIFT_INTERACT_RADIUS * 0.85:
				var ch_v = target.get(&"_charge_t")
				var ch_t: float = float(ch_v) if ch_v != null else 0.0
				if is_heavy_slash(mv, ch_t, 1.0, target):
					_rift_consumed_serial = serial
					dye_rift_purple(target)
					return true
	return false


func _trigger_rift_parry(pt: Vector2) -> void:
	if target != null and is_instance_valid(target) and target.has_method(&"_do_parry"):
		_parrying_rift_only = true
		target.call(&"_do_parry", self, pt)
		_parrying_rift_only = false
	else:
		dye_rift_purple(target)


func _detonate_red_rift() -> void:
	var pos := rift_pos
	_close_rift()
	rift_exploded_red.emit(pos)
	if not _combat_target_ok() or not target.has_method(&"take_hit"):
		return
	var p_center := target.global_position + Vector2(0.0, -48.0)
	if p_center.distance_to(pos) <= RIFT_RED_RADIUS:
		if dodge != null and bool(dodge.call(&"counts_as_dodge")):
			dodged_through.emit(target.global_position)
			return
		var burst_mv := strike_move.duplicate() as MoveDefinition
		burst_mv.damage = RIFT_RED_DAMAGE
		burst_mv.knockback = 660.0
		burst_mv.launch_speed = 250.0
		var dir := 1 if target.global_position.x >= pos.x else -1
		target.call(&"take_hit", burst_mv, dir, pos, 0.0, false, 1.0, null)


func _close_rift() -> void:
	rift_state = Rift.NONE
	rift_timer = 0
	if state_chart != null:
		state_chart.send_event(&"close_rift")
	queue_redraw()


# ---------------------------------------------------------------- 真抛物线登 XI/V 罗马字碑、全屏居合、逆流针与弹针轰坠

func _execute_backstep() -> void:
	var retreat_dir := -float(facing)
	var dest_x := clampf(position.x + retreat_dir * 230.0, arena_left + 115.0, arena_right - 115.0)
	if absf(dest_x - position.x) < 70.0:
		dest_x = clampf(position.x - retreat_dir * 260.0, arena_left + 115.0, arena_right - 115.0)
	_rewinding_step_frames = 12
	_push_afterimage(position, 70, facing, Color(0.94, 0.97, 1.0, 0.45), 0.22)
	position.x = dest_x
	_evade_frames = 10
	if _combat_target_ok():
		facing = 1 if target.global_position.x > global_position.x else -1


func _execute_spire_perch() -> void:
	var arena_mid := (arena_left + arena_right) * 0.5
	var side := 1
	if _combat_target_ok():
		side = -1 if target.global_position.x > arena_mid else 1
	_perch_side = side
	var mon_y := XI_MONUMENT_Y if side < 0 else V_MONUMENT_Y
	var perch_x := (arena_left + 145.0) if side < 0 else (arena_right - 145.0)
	var perch_y := mon_y - half_h
	_perch_jump_from = position
	_perch_jump_to = Vector2(perch_x, perch_y)
	_perch_jumping = true
	# 首帧先就位支撑测试断言同时用 10 帧抛物线平滑视觉残像过渡！
	for k in 3:
		var u := float(k + 1) / 4.0
		var arc := _perch_jump_from.lerp(_perch_jump_to, u) + Vector2(0.0, -95.0 * sin(u * PI))
		_push_afterimage(arc, 40, facing, Color(0.94, 0.97, 1.0, 0.36), 0.22)
	position = _perch_jump_to
	velocity = Vector2.ZERO
	facing = 1 if side < 0 else -1
	spire_perched.emit(side, position)
	_summon_perch_fan_needles(side)


func is_perched_on_monument() -> bool:
	return feet_y() <= V_MONUMENT_Y + 12.0


func _summon_perch_fan_needles(side: int) -> void:
	var base_tx := (arena_left + arena_right) * 0.5
	if _combat_target_ok():
		base_tx = target.global_position.x
	for idx in 5:
		var spread := (float(idx) - 2.0) * 105.0
		var tx := clampf(base_tx + spread, arena_left + 95.0, arena_right - 95.0)
		var spos := global_position + Vector2(float(-side) * 45.0, -35.0)
		var tpos := Vector2(tx, floor_y)
		_rain_needles.append({
			"pos": spos,
			"start_pos": spos,
			"target_pos": tpos,
			"dir": (tpos - spos).normalized(),
			"delay": 10 + idx * 4,
			"phase": "falling",
			"stuck_timer": 0,
			"reflected": false,
		})
	rain_needles_summoned.emit(5)
	queue_redraw()


func _update_perch_and_meteor_motion() -> void:
	if not _meteor_diving:
		return
	if state != State.WINDUP and state != State.STRIKE:
		_meteor_diving = false
		return
	if state == State.WINDUP:
		var t := telegraph()
		if t < 0.77 and _combat_target_ok():
			_meteor_dive_to = Vector2(
				clampf(target.global_position.x - float(facing) * 95.0, arena_left + 120.0, arena_right - 120.0),
				floor_y - half_h
			)
		if t >= 0.78:
			var u := clampf((t - 0.78) / 0.22, 0.0, 1.0)
			position = _meteor_dive_from.lerp(_meteor_dive_to, u * u)
			if state_frames % 2 == 0:
				_push_afterimage(position, 46, facing, Color(0.95, 0.97, 1.0, 0.38), 0.18)
	elif state == State.STRIKE:
		position = _meteor_dive_to
		_meteor_diving = false


func _compute_horizon_dest_x() -> float:
	var dir := float(facing)
	var dest := global_position.x + dir * 720.0
	if _combat_target_ok():
		dest = target.global_position.x + dir * 360.0
		if dest < arena_left + 135.0 or dest > arena_right - 135.0:
			dest = clampf(global_position.x + dir * 680.0, arena_left + 135.0, arena_right - 135.0)
	return clampf(dest, arena_left + 135.0, arena_right - 135.0)


func _execute_horizon_cut() -> void:
	var start_x := global_position.x
	var end_x := _compute_horizon_dest_x()
	if absf(end_x - start_x) < 220.0:
		var alt_dir := -float(facing)
		end_x = clampf(start_x + alt_dir * 660.0, arena_left + 135.0, arena_right - 135.0)
	var old_face := 1 if end_x >= start_x else -1

	for k in 5:
		var u := float(k + 1) / 6.0
		_push_afterimage(Vector2(lerpf(start_x, end_x, u), position.y), 66, old_face, Color(0.94, 0.96, 1.0, 0.42 - 0.05 * float(k)), 0.24)

	position.x = end_x
	if _combat_target_ok():
		facing = 1 if target.global_position.x > global_position.x else -1
	else:
		facing = -old_face

	var min_x := minf(start_x, end_x)
	var max_x := maxf(start_x, end_x)
	var cut_y := feet_y() - 122.0
	_horizon_scar = {
		"active": true,
		"x0": min_x,
		"x1": max_x,
		"y": cut_y,
		"dir": old_face,
		"timer": HORIZON_SCAR_DELAY,
		"max_timer": HORIZON_SCAR_DELAY + 8,
		"detonated": false,
	}
	horizon_slashed.emit(start_x, end_x)

	if _combat_target_ok():
		var px := target.global_position.x
		var gap := feet_y() - _target_feet()
		if px >= min_x - 45.0 and px <= max_x + 45.0 and gap <= HORIZON_CUT_HEIGHT and gap >= -80.0:
			if (target.has_method(&"is_parrying") and bool(target.call(&"is_parrying"))) or _blade_age <= CLASH_GRACE:
				_trigger_horizon_parry(Vector2(px, cut_y))
				return
			if dodge != null and bool(dodge.call(&"counts_as_dodge")):
				_horizon_scar["detonated"] = true
				dodged_through.emit(target.global_position)
				return


func _trigger_horizon_parry(pt: Vector2) -> void:
	if not _horizon_scar.is_empty():
		_horizon_scar["detonated"] = true
	spawn_clash_spark(pt, 0.92)
	if target != null and is_instance_valid(target) and target.has_method(&"_do_parry"):
		_parrying_horizon_only = true
		target.call(&"_do_parry", self, pt)
		_parrying_horizon_only = false
	else:
		_apply_horizon_parry_break(target, pt)


func _apply_horizon_parry_break(cause: Node, pt: Vector2) -> void:
	_clashes += 1
	_parry_stagger_frames = 44
	var dir := -facing
	if cause != null and is_instance_valid(cause) and cause is Node2D:
		dir = 1 if global_position.x > (cause as Node2D).global_position.x else -1
	if not is_shell_broken:
		damage_shell(SHELL_PARRY_HORIZON, pt, dir, false)
	_finish_string()
	if is_shell_broken:
		super.on_parried(cause)
		_breach_was_launched = true
		velocity *= 0.82
	else:
		flash = 6
		flash_color = Color(0.96, 0.98, 1.0)
		squash = Vector2(0.82, 1.18)
		hitstop_frames = maxi(hitstop_frames, roundi(11 * hitstop_multiplier))
		state = State.RECOVER
		state_frames = 0
		spec.recover = 46
		velocity.x = float(dir) * 260.0
		_strike_done = true
		parried.emit(cause, global_position)
	clashed.emit(_clashes, true)


func _update_horizon_scar() -> void:
	if _horizon_scar.is_empty() or not bool(_horizon_scar.get("active", false)):
		return
	var t := int(_horizon_scar.get("timer", 0)) - 1
	_horizon_scar["timer"] = t
	var detonated := bool(_horizon_scar.get("detonated", false))

	if not detonated and _combat_target_ok():
		var px := target.global_position.x
		var x0 := float(_horizon_scar.get("x0", 0.0))
		var x1 := float(_horizon_scar.get("x1", 0.0))
		var cut_y := float(_horizon_scar.get("y", feet_y() - 122.0))
		var gap := feet_y() - _target_feet()
		if px >= x0 - 40.0 and px <= x1 + 40.0 and gap <= HORIZON_CUT_HEIGHT and gap >= -80.0:
			if target.has_method(&"is_parrying") and bool(target.call(&"is_parrying")):
				_trigger_horizon_parry(Vector2(px, cut_y))
				return
			if t <= 0:
				_horizon_scar["detonated"] = true
				if dodge != null and bool(dodge.call(&"counts_as_dodge")):
					dodged_through.emit(target.global_position)
				else:
					var h_dir := int(_horizon_scar.get("dir", facing))
					_deal_boss_projectile_hit(HORIZON_DAMAGE, 660.0, h_dir, Vector2(px, cut_y), true)
	elif not detonated and t <= 0:
		_horizon_scar["detonated"] = true

	if t <= -8:
		_horizon_scar.clear()
	queue_redraw()


func spawn_water_wave() -> void:
	var spawn_x := global_position.x + float(facing) * 115.0
	var wpos := Vector2(spawn_x, feet_y())
	_waves.append({
		"pos": wpos,
		"dir": facing,
		"life": 0.0,
		"max_life": 2.4,
		"hit_done": false,
		"dodged_done": false,
	})
	water_wave_spawned.emit(wpos, facing)


func _update_waves(delta: float) -> void:
	if _waves.is_empty():
		return
	var i := _waves.size() - 1
	while i >= 0:
		var w: Dictionary = _waves[i]
		w.life = float(w.life) + delta
		var pos: Vector2 = w.pos
		var d: int = int(w.dir)
		pos.x += float(d) * WAVE_SPEED * delta
		w.pos = pos
		if float(w.life) >= float(w.max_life) or pos.x < arena_left - 40.0 or pos.x > arena_right + 40.0 or state == State.DEAD:
			_waves.remove_at(i)
			i -= 1
			continue
		if not bool(w.hit_done) and _combat_target_ok():
			var dx := absf(target.global_position.x - pos.x)
			var gap := pos.y - _target_feet()
			if dx <= WAVE_HALF_W + PLAYER_HALF_W and gap <= WAVE_HEIGHT and gap >= -60.0:
				if dodge != null and bool(dodge.call(&"counts_as_dodge")):
					if not bool(w.dodged_done):
						w.dodged_done = true
						dodged_through.emit(target.global_position)
				else:
					w.hit_done = true
					_deal_boss_projectile_hit(WAVE_DAMAGE, 560.0, d, pos + Vector2(0.0, -54.0), false)
		i -= 1
	queue_redraw()


func summon_rain_needles() -> void:
	var cnt := NEEDLE_COUNT_P2 if is_phase2 else NEEDLE_COUNT_P1
	var center_x := global_position.x + float(facing) * 340.0
	if _combat_target_ok():
		center_x = target.global_position.x
	center_x = clampf(center_x, arena_left + 160.0, arena_right - 160.0)
	var fy := floor_y
	for idx in cnt:
		var spread := (float(idx) - float(cnt - 1) * 0.5) * 92.0
		var tx := clampf(center_x + spread, arena_left + 85.0, arena_right - 85.0)
		var sx := clampf(tx - float(facing) * 145.0, arena_left + 60.0, arena_right - 60.0)
		var sy := fy - 540.0 - float(idx % 3) * 38.0
		var spos := Vector2(sx, sy)
		var tpos := Vector2(tx, fy)
		_rain_needles.append({
			"pos": spos,
			"start_pos": spos,
			"target_pos": tpos,
			"dir": (tpos - spos).normalized(),
			"delay": 14 + idx * 5,
			"phase": "falling",
			"stuck_timer": 0,
			"reflected": false,
		})
	rain_needles_summoned.emit(cnt)
	queue_redraw()


func _player_is_parrying_now() -> bool:
	return _combat_target_ok() and target.has_method(&"is_parrying") and bool(target.call(&"is_parrying"))


func _player_sword_can_cut_needle() -> bool:
	if not _combat_target_ok():
		return false
	if _player_is_parrying_now():
		return true
	if int(target.get(&"state")) == int(target.State.ATTACK):
		var mv: MoveDefinition = target.get(&"current_move")
		var mf: int = int(target.get(&"move_frame"))
		if mv != null and (mv.phase_at(mf) == &"active" or _blade_age <= 2):
			return true
	return _blade_age == 0


func _update_rain_needles(delta: float) -> void:
	if _rain_needles.is_empty():
		return
	var is_parry := _player_is_parrying_now()
	var can_cut := _player_sword_can_cut_needle()
	var cut_origin := Vector2.ZERO
	if can_cut and _combat_target_ok():
		var pf := float(target.get(&"facing")) if target.get(&"facing") != null else 1.0
		cut_origin = target.global_position + Vector2(pf * 55.0, -48.0)

	var i := _rain_needles.size() - 1
	while i >= 0:
		var nd: Dictionary = _rain_needles[i]
		if state == State.DEAD:
			_rain_needles.remove_at(i)
			i -= 1
			continue

		# 已被玩家弹刀奉还的刻度钟针：超音速钉向首领胸口（若首领高踞罗马石碑则直接轰坠下台！）
		if bool(nd.get("reflected", false)):
			var r_pos: Vector2 = nd.pos
			var boss_chest := global_position + Vector2(0.0, -half_h * 0.45)
			var to_boss := boss_chest - r_pos
			var dist_b := to_boss.length()
			if dist_b <= 56.0:
				_on_reflected_needle_hit_boss(boss_chest)
				_rain_needles.remove_at(i)
				i -= 1
				continue
			var r_dir := to_boss / maxf(dist_b, 0.01)
			nd.dir = r_dir
			nd.pos = r_pos + r_dir * NEEDLE_REFLECT_SPEED * delta
			i -= 1
			continue

		var dly := int(nd.delay)
		if dly > 0:
			nd.delay = dly - 1
			i -= 1
			continue

		var ph := String(nd.get("phase", "falling"))
		var pos: Vector2 = nd.pos
		var dir: Vector2 = nd.dir

		if ph == "stuck":
			var st_rem := int(nd.get("stuck_timer", 0)) - 1
			nd.stuck_timer = st_rem
			if st_rem <= 0:
				# 发动【逆流拔刺】：插在青石板里的钟针时间倒流，顺原弹道倒飞回天上！
				nd.phase = "rewinding"
				_rewinding_step_frames = maxi(_rewinding_step_frames, 18)
				var s_origin: Vector2 = nd.get("start_pos", global_position + Vector2(0.0, -240.0))
				nd.dir = (s_origin - pos).normalized()
			i -= 1
			continue

		var spd := NEEDLE_SPEED * (1.18 if ph == "rewinding" else 1.0)
		pos += dir * spd * delta
		nd.pos = pos

		if can_cut and pos.distance_to(cut_origin) <= NEEDLE_CUT_RADIUS:
			needles_cut += 1
			spawn_clash_spark(pos, 0.56)
			rain_needle_cut.emit(pos, needles_cut)
			if is_parry:
				# 精准弹刀 -> 触发「弹针奉还」！
				nd.reflected = true
				nd.dir = ((global_position + Vector2(0.0, -half_h * 0.45)) - pos).normalized()
				i -= 1
				continue
			_rain_needles.remove_at(i)
			i -= 1
			continue

		if _combat_target_ok():
			var p_center := target.global_position + Vector2(0.0, -44.0)
			if absf(pos.x - p_center.x) <= 42.0 and absf(pos.y - p_center.y) <= 74.0:
				if dodge != null and bool(dodge.call(&"counts_as_dodge")):
					dodged_through.emit(target.global_position)
				else:
					var hit_dir := 1 if dir.x >= 0.0 else -1
					_deal_boss_projectile_hit(NEEDLE_DAMAGE, 380.0, hit_dir, pos, true)
				_rain_needles.remove_at(i)
				i -= 1
				continue

		if ph == "falling" and pos.y >= floor_y - 2.0:
			# 落地不消失！先钉在黑镜石地里蓄势，随即逆流拔刺倒飞！
			nd.pos = Vector2(pos.x, floor_y - 2.0)
			nd.phase = "stuck"
			nd.stuck_timer = 14
			i -= 1
			continue
		elif ph == "rewinding" and pos.y <= floor_y - 560.0:
			_rain_needles.remove_at(i)
			i -= 1
			continue
		i -= 1
	queue_redraw()


func _on_reflected_needle_hit_boss(hit_pt: Vector2) -> void:
	spawn_clash_spark(hit_pt, 0.90)
	var was_perched := is_perched_on_monument()
	var dir := 1
	if _combat_target_ok():
		dir = 1 if global_position.x > target.global_position.x else -1
	if was_perched:
		# 从 XI / V 罗马字碑高台硬生生轰坠回地面大硬直！
		_meteor_diving = false
		_finish_string()
		position.y = floor_y - half_h
		position.x = clampf(position.x - float(_perch_side) * 160.0, arena_left + 120.0, arena_right - 120.0)
		if not is_shell_broken:
			damage_shell(68.0, hit_pt, dir, false)
		_apply_damage(45.0)
		_parry_stagger_frames = 58
		state = State.HITSTUN
		state_frames = 58
		spec.recover = 58
	else:
		if not is_shell_broken:
			damage_shell(34.0, hit_pt, dir, false)
		_apply_damage(26.0)
	needle_reflected_hit.emit(hit_pt, was_perched)


func _deal_boss_projectile_hit(dmg: float, knock: float, dir: int, pt: Vector2, guardable: bool) -> void:
	if not _combat_target_ok() or not target.has_method(&"take_hit"):
		return
	var pmv := strike_move.duplicate() as MoveDefinition
	pmv.damage = dmg
	pmv.knockback = knock
	pmv.launch_speed = 210.0
	if not guardable and target.has_method(&"is_guarding") and bool(target.call(&"is_guarding")):
		target.call(&"_stop_guard")
	target.call(&"take_hit", pmv, dir, pt, 0.0, false, 1.0, self if guardable else null)


# ---------------------------------------------------------------- 锁链钉影与拽回

func release_nail() -> void:
	nail_phase = Nail.NONE
	nail_frames = 0
	yanking = false


func _support_at(x: float, probe_y: float) -> float:
	return float(terrain.support_y(x, probe_y)) if terrain != null else floor_y


func _nail_target_point() -> Vector2:
	var x := global_position.x + float(facing) * 240.0
	if _target_ok():
		x = target.global_position.x
	x = clampf(x, arena_left + 80.0, arena_right - 80.0)
	return Vector2(x, _support_at(x, floor_y))


func _update_nail() -> void:
	if nail_phase == Nail.NONE:
		return
	if nail_phase == Nail.AIM:
		if state == State.WINDUP:
			if state_frames < int(spec.windup) - NAIL_TRACK:
				nail_point = _nail_target_point()
		elif state != State.STRIKE:
			release_nail()
		return
	if hitstop_frames > 0:
		return
	if yanking:
		if state != State.LAUNCHED:
			release_nail()
			return
		velocity = Vector2(_yank_side * YANK_SPEED, -40.0)
		if (nail_point.x - global_position.x) * _yank_side <= 40.0:
			_yank_land()
		return
	if state != State.LAUNCHED:
		nail_frames -= 1
		if nail_frames <= 0 or state in [State.IDLE, State.APPROACH, State.WINDUP, State.DOWN]:
			release_nail()
		return
	var off := global_position.x - nail_point.x
	if absf(off) >= TETHER_LEN and off * velocity.x > 0.0:
		_yank(-signf(off))


func _yank(side: float) -> void:
	yanking = true
	_yank_side = side
	driven_frames = 0
	chain_armed = false
	velocity = Vector2(side * YANK_SPEED, -40.0)
	hitstop_frames = maxi(hitstop_frames, 4)
	flash = 3
	flash_color = Color(0.96, 0.98, 1.0)
	squash = Vector2(1.3, 0.75)


func _yank_land() -> void:
	var dmg := YANK_SPEED * _wall_factor * WALL_DAMAGE_SCALE * YANK_DAMAGE_MUL
	_apply_damage(dmg)
	yanks += 1
	flash = 5
	flash_color = Color(1.0, 1.0, 1.0)
	squash = Vector2(0.7, 1.3)
	hitstop_frames = maxi(hitstop_frames, roundi(12 * hitstop_multiplier))
	velocity = Vector2(0.0, -640.0)
	var point := Vector2(global_position.x, nail_point.y)
	var side := int(signf(_yank_side))
	release_nail()
	tether_slam.emit(dmg, point)
	if hp <= 0.0:
		_die(side if side != 0 else facing)


func _nail_impact() -> void:
	nail_phase = Nail.STUCK
	nail_frames = NAIL_HOLD
	nail_landed.emit(nail_point)
	if not _combat_target_ok() or not target.has_method(&"take_hit"):
		return
	var dx: float = target.global_position.x - nail_point.x
	if absf(dx) > NAIL_RADIUS + PLAYER_HALF_W or nail_point.y - _target_feet() > NAIL_HIGH:
		return
	if dodge != null and bool(dodge.call(&"counts_as_dodge")):
		dodged_through.emit(target.global_position)
		return
	if target.has_method(&"is_guarding") and target.call(&"is_guarding"):
		target.call(&"_stop_guard")
	var side: int = 1 if dx >= 0.0 else -1
	target.call(&"take_hit", strike_move, side, nail_point, 0.0, false, 1.0, null)


func _target_feet() -> float:
	return target.global_position.y + float(target.get(&"foot_offset"))


# ---------------------------------------------------------------- 破口期横轰加速、空中续拍与罗马石碑撞击

func is_pursuit_move(mv: MoveDefinition, attacker: Node) -> bool:
	if mv == null:
		return false
	if mv.id in [&"dash_slash", &"dash_slash_left", &"air_dash_slash", &"air_dash_slash_left"]:
		return true
	if attacker != null:
		var st = attacker.get(&"state")
		if st != null and int(st) == 2 and absf(mv.lunge_speed) >= 500.0:
			return true
	return false


func _is_volley_finisher(mv: MoveDefinition, charge_t: float, intent: StringName) -> bool:
	if intent == &"drive":
		return true
	if charge_t > 0.2:
		return true
	if dodge != null and dodge.has_method(&"is_heavy") and bool(dodge.call(&"is_heavy")):
		return true
	if mv == null:
		return false
	return mv.id in [&"light_3", &"air_light_3", &"air_light_4", &"charge_slash", &"dash_slash", &"dash_slash_left"] or mv.knockback >= 460.0


func _apply_escalating_fling(from_facing: int, intent: StringName) -> void:
	var idx := mini(breach_volley_count, VOLLEY_SPEEDS.size() - 1)
	var spd: float = VOLLEY_SPEEDS[idx]
	if intent == &"drive":
		spd *= 1.12
	breach_volley_count += 1
	last_fling_speed = spd
	state = State.LAUNCHED
	_breach_was_launched = true
	driven_frames = 14 + mini(breach_volley_count * 2, 8)
	chain_armed = true
	velocity = Vector2(float(from_facing) * spd, -240.0 - float(idx) * 35.0)
	squash = Vector2(1.36, 0.72)
	volley_flung.emit(breach_volley_count, spd)


func on_beat() -> bool:
	if state != State.LAUNCHED or air_rules == null:
		return true
	var band: float = float(air_rules.rules.get("apex_band", -float(air_rules.rules.get("beat_vy", -150.0))))
	return _pre_vy >= -band


func reward_air_control(frames_back: int = 3) -> void:
	juggle_count = maxi(0, juggle_count - frames_back)


func _juggle(mv: MoveDefinition, from_facing: int, from_up: bool, intent: StringName = &"") -> void:
	if air_rules != null and bool(air_rules.rules.beat_check):
		var band: float = float(air_rules.rules.get("apex_band", -float(air_rules.rules.get("beat_vy", -150.0))))
		var ok := _pre_vy >= -band
		air_rules.on_judged(ok, global_position)
		if not ok:
			early_hits += 1
			bounces = 0
			velocity = Vector2(float(from_facing) * float(air_rules.rules.early_slide), _pre_vy * float(air_rules.rules.early_keep))
			flash = 4
			flash_color = Color(0.65, 0.68, 0.75)
			squash = Vector2(0.9, 1.1)
			return
	super(mv, from_facing, from_up, intent)
	if breach_volley_count > 0:
		velocity.x += float(from_facing) * (32.0 * float(mini(breach_volley_count, 4)))


# ---------------------------------------------------------------- 自适应双向时间倒流立回 AI

func _track_blade() -> void:
	_blade_age = mini(_blade_age + 1, 999)
	if _player_blade_live():
		_blade_age = 0


func _player_blade_live() -> bool:
	if target == null or not is_instance_valid(target) or not target.has_method(&"is_parrying"):
		return false
	if target.call(&"is_parrying"):
		return true
	return _player_swinging()


func _player_swinging() -> bool:
	if int(target.get(&"state")) != int(target.State.ATTACK):
		return false
	var mv: MoveDefinition = target.get(&"current_move")
	if mv == null:
		return false
	var f: int = int(target.get(&"move_frame"))
	return mv.phase_at(f) == &"active" or (mv.phase_at(f) == &"startup" and f >= mv.startup_frames - CLASH_LEAD)


func _record_string_pick(id: StringName) -> StringName:
	_recent_strings.append(id)
	if _recent_strings.size() > 3:
		_recent_strings.pop_front()
	_plan_index += 1
	return id


func _pick_non_repeat(candidates: Array[StringName]) -> StringName:
	var last_id: StringName = _recent_strings.back() if not _recent_strings.is_empty() else &""
	for idx in candidates.size():
		var cand := candidates[(_plan_index + idx) % candidates.size()]
		if cand == &"nail" and _nail_cool > 0:
			continue
		if cand == &"spire_dive" and _spire_dive_cool > 0:
			continue
		if cand == &"chrono_anchor" and (_anchor_cool > 0 or chrono_anchor_active):
			continue
		if cand == &"player_snare" and (_snare_cool > 0 or player_snare_active):
			continue
		if cand != last_id or candidates.size() == 1:
			return _record_string_pick(cand)
	return _record_string_pick(candidates[0])


func _choose_reactive_string() -> StringName:
	if not _combat_target_ok():
		var fallback_row: Array = PLANS[2 if is_phase2 else 0]
		return _record_string_pick(fallback_row[_plan_index % fallback_row.size()])

	var dx := absf(target.global_position.x - global_position.x)
	var air_gap := feet_y() - _target_feet()

	if air_gap >= 145.0 and dx <= 330.0 and _anti_air_cool <= 0:
		_anti_air_cool = 140
		return _record_string_pick(&"anti_air")

	# 1. 近身白刃压制与过去锚点/退步博弈 (< 235px)
	if dx < 235.0:
		if _player_swinging() and (_plan_index % 2 == 0):
			return _pick_non_repeat([&"backstep_pierce", &"chrono_anchor", &"triple"])
		if is_phase2:
			return _pick_non_repeat([&"triple", &"chrono_anchor", &"backstep_pierce", &"white_red", &"sweep"])
		return _pick_non_repeat([&"triple", &"chrono_anchor", &"backstep_pierce", &"sweep"])

	# 2. 中距离时间倒流核心立回区 (235px .. 480px)
	if dx < 480.0:
		if is_phase2:
			if rift_state == Rift.NONE:
				return _pick_non_repeat([&"player_snare", &"red_rift", &"chrono_anchor", &"triple", &"spire_dive"])
			return _pick_non_repeat([&"player_snare", &"white_red", &"triple", &"sweep"])
		return _pick_non_repeat([&"triple", &"player_snare", &"chrono_anchor", &"sweep"])

	# 3. 远距离全屏居合与登罗马字碑博弈区 (> 480px)
	if is_phase2:
		var pick_far_p2 := _pick_non_repeat([&"horizon_cut", &"spire_dive", &"player_snare", &"sever_tide"])
		if pick_far_p2 == &"spire_dive":
			_spire_dive_cool = 260
		return pick_far_p2

	var pick_far_p1 := _pick_non_repeat([&"spire_dive", &"horizon_cut", &"player_snare", &"rain_needles"])
	if pick_far_p1 == &"spire_dive":
		_spire_dive_cool = 280
	return pick_far_p1


func _begin_windup() -> void:
	_start_string(_choose_reactive_string())


func _answer_string() -> void:
	if is_phase2 and rift_state == Rift.NONE and (_plan_index == 0 or not _countered):
		_countered = true
		_start_string(&"sever_tide")
		_plan_index = 1
		return
	if _countered:
		_begin_windup()
	else:
		_start_string(&"counter")


func reset_combo() -> void:
	juggle_count = 0
	combo_taken = 0
	_countered = false


func _process_ai(delta: float) -> void:
	var saved_facing := facing
	if _anti_air_cool <= 0 and cooldown <= 0 and on_ground() and _combat_target_ok():
		var air_gap := feet_y() - _target_feet()
		var h_dist := absf(target.global_position.x - global_position.x)
		if air_gap >= 155.0 and h_dist <= 325.0:
			_anti_air_cool = 145
			_start_string(&"anti_air")
			return
	var far: bool = _target_ok() and absf(target.global_position.x - global_position.x) > CHASE_FROM
	spec.speed = CHASE_SPEED if far else WALK_SPEED
	if far and cooldown <= 0 and on_ground() and _target_ok():
		_start_string(_choose_reactive_string())
		return
	super(delta)
	if _turn_lock_frames > 0:
		facing = saved_facing


func _start_string(id: StringName) -> void:
	if id == &"counter":
		_countered = true
	_string_id = id
	_steps = STRINGS[id].steps
	_step = 0
	_clashes = 0
	_meteor_diving = false
	_perch_jumping = false
	if id == &"nail":
		_nail_cool = NAIL_COOL
	_begin_step()


func _begin_step() -> void:
	_cur = _steps[_step]
	var bk := blade_kind()
	if bool(_cur.get("leave_echoes", false)):
		_rewind_Origin_x = position.x
	if bool(_cur.get("blink", false)):
		_try_blink_behind_target()
	elif bk == Blade.PERCH:
		_execute_spire_perch()
	elif bk == Blade.BACKSTEP:
		_execute_backstep()
	elif bk == Blade.ANCHOR:
		spawn_chrono_anchor()
	elif bk == Blade.SNARE:
		stamp_player_rewind_snare()
	elif bool(_cur.get("snare_pull", false)) and player_snare_active:
		facing = 1 if player_snare_pos.x >= global_position.x else -1
	elif bool(_cur.get("rewind_draw", false)):
		# 发动【逆晷倒带】：提示即将沿残影 2 倍速倒退抽刀！
		_rewinding_step_frames = 26
	elif _combat_target_ok() and active and _turn_lock_frames <= 0:
		facing = 1 if target.global_position.x > global_position.x else -1

	spec.windup = int(_cur.windup)
	spec.strike = int(_cur.strike)
	spec.recover = int(STRINGS[_string_id].recover)
	spec.range = float(_cur.range)
	spec.lunge = float(_cur.lunge)
	strike_move.damage = float(_cur.damage)
	strike_move.knockback = float(_cur.knock)
	super._begin_windup()

	if bool(_cur.get("meteor", false)):
		_meteor_diving = true
		_meteor_dive_from = position
		var dest_x := (arena_left + arena_right) * 0.5
		if _combat_target_ok():
			dest_x = clampf(target.global_position.x - float(facing) * 90.0, arena_left + 120.0, arena_right - 120.0)
		_meteor_dive_to = Vector2(dest_x, floor_y - half_h)
	elif bk == Blade.NAIL:
		nail_phase = Nail.AIM
		nail_point = _nail_target_point()
		nail_aimed.emit()
	elif bk == Blade.HORIZON:
		_horizon_aim_to_x = _compute_horizon_dest_x()
		horizon_telegraphed.emit(global_position.x, _horizon_aim_to_x)


func _process_strike(delta: float) -> void:
	if bool(_cur.get("leave_echoes", false)) and state_frames % 2 == 0:
		_push_afterimage(position, _pick_atlas_frame(), facing, Color(0.94, 0.97, 1.0, 0.50), 0.45)
	elif bool(_cur.get("rewind_draw", false)) and state_frames == 1:
		# 2 倍速沿刚才留下的残影倒退抽回分针长太刀！
		_rewinding_step_frames = 20
		var dest_rx := clampf(_rewind_Origin_x, arena_left + 100.0, arena_right - 100.0)
		for k in 3:
			var u := float(k + 1) / 4.0
			_push_afterimage(Vector2(lerpf(position.x, dest_rx, u), position.y), 29 + k, facing, Color(0.95, 0.98, 1.0, 0.44), 0.24)
		position.x = lerpf(position.x, dest_rx, 0.65)
	super(delta)
	if state != State.RECOVER:
		return
	if _step + 1 < _steps.size():
		_step += 1
		_begin_step()
	else:
		_finish_string()


func _finish_string() -> void:
	if _string_id != &"counter":
		reset_combo()
	strings_finished += 1
	spec.range = IDLE_RANGE
	_meteor_diving = false
	_perch_jumping = false
	_cur = {}


func _strike_check() -> void:
	var kind_b := blade_kind()
	if kind_b in [Blade.BACKSTEP, Blade.PERCH, Blade.ANCHOR, Blade.SNARE]:
		return
	if bool(_cur.get("snare_pull", false)) and player_snare_active:
		_execute_player_rewind_pull()
		if _cur.is_empty() or state != State.STRIKE:
			return
	if kind_b == Blade.NAIL:
		_nail_impact()
		return
	if kind_b == Blade.HORIZON:
		_execute_horizon_cut()
		return
	if kind_b == Blade.NEEDLES:
		summon_rain_needles()
		return
	if bool(_cur.get("spawn_wave", false)):
		spawn_water_wave()
	if kind_b == Blade.RIFT:
		var rpos := global_position + Vector2(float(facing) * 215.0, -half_h * 0.35)
		open_red_rift(rpos)
		if _combat_target_ok() and target.has_method(&"is_parrying") and bool(target.call(&"is_parrying")):
			var dx_r := absf(target.global_position.x - rift_pos.x)
			if dx_r <= RIFT_INTERACT_RADIUS + 60.0:
				_trigger_rift_parry(rift_pos)
				return
		return

	if bool(_cur.get("tear_rift_p2", false)) and is_phase2 and rift_state == Rift.NONE:
		open_red_rift(global_position + Vector2(float(facing) * 240.0, -half_h * 0.35))

	if target == null or not is_instance_valid(target) or not target.has_method(&"take_hit"):
		return
	var dx := target.global_position.x - global_position.x
	var gap := feet_y() - _target_feet()
	var reach := float(_cur.range) + PLAYER_HALF_W
	var high := gap > float(_cur.height) or gap < -85.0
	var dodging := _player_has_dodge_iframes()
	if dodging and not high and absf(dx) <= reach + 160.0:
		dodged_through.emit(target.global_position)
		return
	# 倒带抽刀 (rewind_draw) 覆盖身前与退步路径双向剑域！
	var is_rewind_cut := bool(_cur.get("rewind_draw", false))
	if high or absf(dx) > reach or (not is_rewind_cut and absf(dx) > 2.0 and signf(dx) != float(facing)):
		return
	var point := global_position + Vector2(float(facing) * minf(absf(dx), float(_cur.range)) * 0.6, -half_h * 0.4)
	var white: bool = (kind_b == Blade.WHITE)
	if white and _blade_age <= CLASH_GRACE and target.has_method(&"_do_parry"):
		target.call(&"_do_parry", self, point)
		return
	if not white and target.has_method(&"is_guarding") and target.call(&"is_guarding"):
		target.call(&"_stop_guard")
	var hp_before: float = float(target.get(&"hp"))
	var blocked: bool = bool(target.call(&"take_hit", strike_move, facing, point, 0.0, false, 1.0, self if white else null))
	if blocked:
		return
	if is_equal_approx(float(target.get(&"hp")), hp_before):
		return
	if _string_id != &"sever_tide":
		hitstop_frames = maxi(hitstop_frames, strike_move.hitstop_frames)
	strike_landed.emit(point)
	if _string_id != &"sever_tide":
		_step = _steps.size() - 1


func on_parried(cause: Node = null) -> void:
	if state == State.DEAD:
		return
	if _parrying_rift_only:
		dye_rift_purple(cause)
		return
	if _parrying_horizon_only:
		_apply_horizon_parry_break(cause, global_position + Vector2(0.0, -half_h * 0.4))
		return
	if _snare_just_pulled_frames > 0:
		trigger_supersonic_rewind_parry()
		return

	var spark_pt := global_position + Vector2(float(facing) * 85.0, -half_h * 0.45)
	if cause != null and is_instance_valid(cause) and cause is Node2D:
		spark_pt = ((cause as Node2D).global_position + global_position) * 0.5 + Vector2(0.0, -76.0)
	spawn_clash_spark(spark_pt, 0.86)

	var was_meteor := _meteor_diving or bool(_cur.get("meteor", false))
	var was_anti_air := bool(_cur.get("anti_air", false))
	var was_rewind_cut := bool(_cur.get("rewind_draw", false))
	var is_last := _steps.is_empty() or _step + 1 >= _steps.size()
	_clashes += 1

	if was_anti_air and cause != null and is_instance_valid(cause) and "bonus_air_jumps" in cause:
		var r_max: int = int(cause.get(&"air_jump_refund_max")) if cause.get(&"air_jump_refund_max") != null else 2
		if int(cause.bonus_air_jumps) < r_max:
			cause.bonus_air_jumps = int(cause.bonus_air_jumps) + 1
			if cause.has_signal(&"air_jump_refunded"):
				cause.emit_signal(&"air_jump_refunded", cause.bonus_air_jumps)

	var dir := -facing
	if cause != null and is_instance_valid(cause) and cause is Node2D:
		dir = 1 if global_position.x > (cause as Node2D).global_position.x else -1

	if not is_shell_broken:
		var parry_sh := SHELL_PARRY_METEOR if was_meteor else (SHELL_PARRY_REWIND if was_rewind_cut else (48.0 if was_anti_air else SHELL_PARRY))
		var shattered_now := damage_shell(parry_sh, spark_pt, dir, false)
		if shattered_now:
			if is_last:
				state = State.LAUNCHED
				_breach_was_launched = true
				bounces = 0
				juggle_count = 1
				velocity = Vector2(float(dir) * 380.0, -680.0)
			clashed.emit(_clashes, true)
			return

	# 二阶段「错时瞬步变招」：首段白刀被弹反时化作快门重影闪到玩家身后反劈！
	if is_phase2 and not is_last and not was_meteor and not was_rewind_cut and _clash_cancel_cool <= 0 and not is_shell_broken:
		_clash_cancel_cool = 210
		_rewinding_step_frames = 14
		flash = 5
		flash_color = Color(0.96, 0.98, 1.0)
		hitstop_frames = maxi(hitstop_frames, roundi(6 * hitstop_multiplier))
		_try_blink_behind_target()
		clash_canceled.emit(global_position)
		_step += 1
		_begin_step()
		clashed.emit(_clashes, false)
		return

	if not is_last and not was_meteor and not was_rewind_cut:
		flash = 4
		flash_color = Color(0.94, 0.96, 1.0)
		squash = Vector2(0.84, 1.16)
		hitstop_frames = maxi(hitstop_frames, roundi(8 * hitstop_multiplier))
		velocity.x = -float(facing) * 200.0
		_step += 1
		_begin_step()
		parried.emit(cause, global_position)
		clashed.emit(_clashes, false)
		return

	# 弹反倒带回斩 / 收尾重劈 / 陨星俯冲 -> 触发长达 1.8s 的「崩针大硬直」（姿态 75）！
	_finish_string()
	if is_shell_broken:
		super(cause)
		_breach_was_launched = true
		velocity *= 0.85
	else:
		_parry_stagger_frames = 108 if was_rewind_cut else (68 if is_last else 38)
		flash = 7
		flash_color = Color(1.0, 1.0, 1.0)
		squash = Vector2(0.80, 1.22)
		hitstop_frames = maxi(hitstop_frames, roundi(12 * hitstop_multiplier))
		state = State.RECOVER
		state_frames = 0
		spec.recover = 108 if was_rewind_cut else (68 if is_last else 42)
		velocity.x = float(dir) * 270.0
		_strike_done = true
		parried.emit(cause, global_position)
	clashed.emit(_clashes, true)


func _try_blink_behind_target() -> void:
	if not _combat_target_ok():
		return
	var pf := 1
	if "facing" in target:
		pf = int(target.facing)
	if pf == 0:
		pf = 1
	var behind_x := target.global_position.x - float(pf) * BLINK_BEHIND_DIST
	if behind_x < arena_left + 72.0 or behind_x > arena_right - 72.0:
		behind_x = target.global_position.x + float(pf) * BLINK_BEHIND_DIST
	behind_x = clampf(behind_x, arena_left + 72.0, arena_right - 72.0)
	_push_afterimage(position, _pick_atlas_frame(), facing, Color(0.94, 0.97, 1.0, 0.48), 0.28)
	position.x = behind_x
	facing = 1 if target.global_position.x > global_position.x else -1


func take_hit(mv: MoveDefinition, from_facing: int, point: Vector2, charge_t: float = 0.0, from_up: bool = false, damage_mul: float = 1.0, attacker: Node = null) -> bool:
	if state == State.DEAD or intro_frames > 0:
		return false

	if _evade_frames > 0:
		dodged_through.emit(global_position)
		return false

	# 若场上存在过去锚点且玩家挥击覆盖到了锚点，一并引爆锚点断轨！
	if chrono_anchor_active and point.distance_to(chrono_anchor_pos) <= 145.0:
		shatter_chrono_anchor(attacker)
		return true

	if rift_state == Rift.ACTIVE and is_heavy_slash(mv, charge_t, damage_mul, attacker):
		if absf(global_position.x - rift_pos.x) <= 440.0 or point.distance_to(rift_pos) <= 320.0:
			dye_rift_purple(attacker)
			return false

	var is_ult := mv != null and mv.id == &"ult"
	if is_ult and not is_shell_broken:
		_shatter_shell(point, from_facing)

	var core_mul := 1.0 + float(core_drops) * CORE_ATTACK_BONUS
	var eff_dmg_mul := damage_mul * core_mul

	if not is_shell_broken:
		var backstab := is_backstab_from(from_facing, attacker)
		var heavy := is_heavy_slash(mv, charge_t, eff_dmg_mul, attacker)
		var sh_dmg := 0.0
		if backstab:
			sh_dmg = SHELL_BACKSTAB_HEAVY if heavy else SHELL_BACKSTAB
			_turn_lock_frames = maxi(_turn_lock_frames, 26)
		else:
			sh_dmg = SHELL_CHIP_HEAVY if heavy else SHELL_CHIP_LIGHT

		var just_shattered := damage_shell(sh_dmg, point, from_facing, backstab)
		if not just_shattered:
			var hp_mul := SHELL_BACK_DMG_MUL if backstab else SHELL_FRONT_DMG_MUL
			var dealt := mv.damage * (1.0 + (mv.charge_damage_bonus - 1.0) * charge_t) * eff_dmg_mul * hp_mul
			hitstop_frames = maxi(hitstop_frames, roundi(float(mv.victim_hitstop_frames) * (0.85 if backstab else 0.55)))
			_apply_damage(dealt)
			last_hit_damage = dealt
			armor_flash = 8
			flash = 4 if backstab else 2
			flash_color = Color(0.92, 0.96, 1.0)
			squash = Vector2(0.94, 1.06) if not backstab else Vector2(1.12, 0.90)
			damaged.emit(dealt, hp, point)
			if hp <= 0.0:
				_die(from_facing)
				return false
			if from_up or mv.forces_launch:
				armor_held.emit()
			return false

	var was_air := (state == State.LAUNCHED)
	var pre_vx := velocity.x
	_pre_vy = velocity.y
	var intent: StringName = &""
	if attacker != null and attacker.has_method(&"combat_intent"):
		intent = attacker.call(&"combat_intent")

	var result := super(mv, from_facing, point, charge_t, from_up, eff_dmg_mul, attacker)
	if state == State.DEAD:
		return result

	if state == State.LAUNCHED:
		_breach_was_launched = true

	if is_pursuit_move(mv, attacker) and state != State.DOWN:
		pursuit_slashes += 1
		var near_right := from_facing > 0 and (arena_right - global_position.x) < 350.0
		var near_left := from_facing < 0 and (global_position.x - arena_left) < 350.0
		if near_right or near_left or intent == &"drive":
			state = State.LAUNCHED
			_breach_was_launched = true
			driven_frames = 16
			chain_armed = true
			velocity = Vector2(float(from_facing) * maxf(990.0, absf(pre_vx) + 270.0), -220.0)
		else:
			state = State.LAUNCHED
			_breach_was_launched = true
			driven_frames = 0
			juggle_count = maxi(1, juggle_count - 2)
			velocity = Vector2(float(from_facing) * 145.0, -_cap_juggle_rise(460.0))
		pursuit_slashed.emit(point, pursuit_slashes)
		return result

	if state != State.DOWN and _is_volley_finisher(mv, charge_t, intent) and not from_up:
		_apply_escalating_fling(from_facing, intent)

	return result


func _launch(mv: MoveDefinition, from_facing: int, from_up: bool, stunned: bool, charge_t: float) -> void:
	if state == State.DOWN or not is_shell_broken:
		if not is_shell_broken:
			armor_held.emit()
		return
	super(mv, from_facing, from_up, stunned, charge_t)
	_breach_was_launched = true


func _wall_check() -> void:
	var side := 0
	if position.x - half_w < arena_left:
		position.x = arena_left + half_w
		side = -1
	elif position.x + half_w > arena_right:
		position.x = arena_right - half_w
		side = 1
	else:
		side = int(_terrain_push().y)
	if side == 0:
		return
	var speed := absf(velocity.x)
	if speed >= 300.0 and float(side) * velocity.x > 0.0:
		var repeat_mul := 1.0 if _breach_pillar_slams == 0 else REPEAT_PILLAR_MUL
		var drive_bonus := 1.25 if driven_frames > 0 or chain_armed else 1.0
		var dmg := (PILLAR_SLAM_BASE + speed * PILLAR_SLAM_SCALE) * drive_bonus * repeat_mul
		_breach_pillar_slams += 1
		_wall_slam_pose_frames = 20
		_apply_damage(dmg)
		flash = 6
		flash_color = Color(1.0, 1.0, 1.0)
		squash = Vector2(0.68, 1.32)
		hitstop_frames = maxi(hitstop_frames, roundi((9 if speed < 900.0 else 13) * hitstop_multiplier))
		var bounce := clampf(speed * (0.48 if driven_frames > 0 else 0.42), 300.0, 560.0)
		velocity = Vector2(-float(side) * bounce, minf(velocity.y - 160.0, -390.0))
		driven_frames = 0
		chain_armed = false
		bounces += 1
		wall_slam.emit(side, dmg, global_position)
		if hp <= 0.0:
			_die(-side)
	else:
		velocity.x = 0.0


func _die(from_facing: int) -> void:
	release_nail()
	chrono_anchor_active = false
	player_snare_active = false
	_horizon_scar.clear()
	_waves.clear()
	_rain_needles.clear()
	_afterimages.clear()
	_clash_sparks.clear()
	if rift_state == Rift.ACTIVE:
		_close_rift()
	super(from_facing)


# ---------------------------------------------------------------- 80 帧 24fps MiniMax-H3 视频动作索引映射与快门重影绘制

func _span_frame(f_start: int, f_end: int, ratio: float) -> int:
	var n := f_end - f_start + 1
	return clampi(f_start + int(floor(clampf(ratio, 0.0, 0.999) * float(n))), f_start, f_end)


func _pick_atlas_frame() -> int:
	if intro_frames > 0:
		var ti := 1.0 - float(intro_frames) / float(INTRO_FRAMES)
		if ti < 0.28:
			return 74
		elif ti < 0.62:
			return 72
		elif ti < 0.85:
			return 73
		return _span_frame(0, 4, (ti - 0.85) / 0.15)

	match state:
		State.DEAD:
			return 79
		State.DOWN:
			return 77
		State.LAUNCHED:
			if _wall_slam_pose_frames > 0 or absf(velocity.x) > 640.0:
				return 77
			return 76
		State.HITSTUN:
			return 75
		State.APPROACH:
			# H3 Video 1 [8..15]: 24fps 连续压低重心疾步追猎帧
			return 8 + (int(anim_t * 18.0) % 8)
		State.WINDUP:
			var w_ratio := telegraph()
			var anim_tag := StringName(_cur.get("anim", &""))
			match anim_tag:
				&"lunge_thrust":
					return _span_frame(16, 20, w_ratio)
				&"rewind_slash":
					return _span_frame(26, 29, w_ratio)
				&"moon_leap":
					return _span_frame(36, 43, w_ratio)
				&"iai":
					return _span_frame(64, 69, w_ratio)
				&"iai_flourish":
					return _span_frame(54, 58, w_ratio)
				&"perch", &"needles", &"nail":
					return 74
				&"anchor_set", &"snare_mark":
					return _span_frame(60, 64, w_ratio)
				&"backstep":
					return _span_frame(12, 15, w_ratio)
				&"rift_tear":
					return 78
			return _span_frame(16, 20, w_ratio)
		State.STRIKE:
			var s_denom := maxf(float(spec.strike), 1.0)
			var s_ratio := clampf(float(state_frames) / s_denom, 0.0, 1.0)
			var anim_tag := StringName(_cur.get("anim", &""))
			match anim_tag:
				&"lunge_thrust":
					return _span_frame(21, 25, s_ratio)
				&"rewind_slash":
					return _span_frame(30, 35, s_ratio)
				&"moon_leap":
					return _span_frame(44, 51, s_ratio)
				&"iai":
					return _span_frame(21, 25, s_ratio)
				&"iai_flourish":
					return _span_frame(59, 63, s_ratio)
				&"perch", &"needles", &"nail":
					return 74
				&"rift_tear":
					return 78
			return _span_frame(21, 25, s_ratio)
		State.RECOVER:
			if _parry_stagger_frames > 0:
				return 75
			if _reforge_pose_frames > 0:
				return 78
			var r_denom := maxf(float(spec.recover), 1.0)
			var r_ratio := clampf(float(state_frames) / r_denom, 0.0, 1.0)
			if _string_id in [&"triple", &"spire_dive", &"chrono_anchor"]:
				return _span_frame(50, 53, r_ratio)
			return _span_frame(64, 69, r_ratio)
		_:
			if _reforge_pose_frames > 0:
				return 78
			# H3 Video 1 [0..7]: 24fps 丝滑呼吸与悬浮日晷微旋待机循环
			return int(anim_t * 12.0) % 8


func _is_airborne_atlas_frame(idx: int) -> bool:
	return idx in [40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 54, 55, 56, 72, 76]


func _draw_vfx_cell(cv: CanvasItem, vfx_idx: int, dest_rect: Rect2, mod: Color = Color.WHITE) -> void:
	if _vfx_tex == null:
		return
	var col := vfx_idx % VFX_COLS
	var row := vfx_idx / VFX_COLS
	var inset := 3.0
	var src := Rect2(float(col) * VFX_CELL + inset, float(row) * VFX_CELL + inset, VFX_CELL - inset * 2.0, VFX_CELL - inset * 2.0)
	cv.draw_texture_rect_region(_vfx_tex, dest_rect, src, mod)


func _draw_atlas_pose(cv: CanvasItem, tex: Texture2D, cell_px: float, frame_idx: int, dest_rect: Rect2, mod: Color) -> void:
	var col := frame_idx % ATLAS_COLS
	var row := frame_idx / ATLAS_COLS
	var inset := 2.0 if cell_px >= 400.0 else 1.0
	var src := Rect2(float(col) * cell_px + inset, float(row) * cell_px + inset, cell_px - inset * 2.0, cell_px - inset * 2.0)
	var pad := dest_rect.size * (inset / cell_px)
	var dst := Rect2(dest_rect.position + pad, dest_rect.size - pad * 2.0)
	cv.draw_texture_rect_region(tex, dst, src, mod)


func _paint(cv: CanvasItem) -> void:
	var fade := 1.0
	if state == State.DEAD:
		fade = clampf(1.0 - float(dead_frames - 115) / 45.0, 0.0, 1.0)

	var s := squash
	var t := anim_t
	var h := half_h
	var w := half_w
	var draw_w := ATLAS_CELL * SPRITE_SCALE

	# 接地浓墨暗影
	var air := clampf((ground_y() - position.y) / 340.0, 0.0, 1.0)
	_draw_ellipse(cv, Vector2(0.0, h + 3.0), Vector2(w * 1.55 * (1.0 - air * 0.5), 7.5), Color(0.0, 0.0, 0.0, 0.62 * fade * (1.0 - air * 0.7)))

	# 0. 司晷独有视觉灵魂：常态「快门错时重影」（身后永远拖着 0.12s 与 0.24s 前的半透银白快门残影！）
	if cv == self and _atlas_edge_tex != null and _shutter_history.size() >= 10 and state != State.DEAD and intro_frames <= 0:
		for lag_idx: int in [5, 11]:
			var rec_i := _shutter_history.size() - 1 - lag_idx
			if rec_i < 0:
				continue
			var rec: Dictionary = _shutter_history[rec_i]
			var r_pos: Vector2 = (rec.pos as Vector2) - position
			# 即使原地站立，快门重影也有轻微的错时水平偏振（像失灵的高速黑白快门！）
			var jitter_off := Vector2(-float(facing) * (9.0 if lag_idx == 5 else 18.0) + sin(t * 14.0 + float(lag_idx)) * 2.5, 0.0)
			var l_pos := r_pos + jitter_off
			var r_face := int(rec.facing)
			var r_flip := 1.0 if r_face < 0 else -1.0
			var r_frame := int(rec.frame)
			var r_air := _is_airborne_atlas_frame(r_frame)
			var r_piv := l_pos + (Vector2(0.0, -h * 0.08) if r_air else Vector2(0.0, h))
			var r_ay := ATLAS_AIR_Y if r_air else ATLAS_FOOT_Y
			var r_rect := Rect2(-draw_w * 0.5, -r_ay * SPRITE_SCALE, draw_w, draw_w)
			var echo_a := (0.24 if lag_idx == 5 else 0.13) * (1.55 if _rewinding_step_frames > 0 else 1.0) * fade
			cv.draw_set_transform(r_piv, 0.0, Vector2(r_flip, 1.0))
			_draw_atlas_pose(cv, _atlas_edge_tex, RIM_CELL, r_frame, r_rect, Color(0.92, 0.95, 1.0, echo_a))
		cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 1. 高速瞬步与倒带轨迹残像
	var ghost_tex := _atlas_sil_tex if _atlas_sil_tex != null else _atlas_edge_tex
	if cv == self and ghost_tex != null and not _afterimages.is_empty():
		for g: Dictionary in _afterimages:
			var gk := 1.0 - float(g.life) / maxf(float(g.max_life), 0.01)
			var g_pos: Vector2 = (g.pos as Vector2) - position
			var g_face := int(g.facing)
			var g_flip := 1.0 if g_face < 0 else -1.0
			var g_frame := int(g.frame)
			var g_air := _is_airborne_atlas_frame(g_frame)
			var g_pivot := g_pos + (Vector2(0.0, -h * 0.08) if g_air else Vector2(0.0, h))
			var g_ay := ATLAS_AIR_Y if g_air else ATLAS_FOOT_Y
			var g_rect := Rect2(-draw_w * 0.5, -g_ay * SPRITE_SCALE, draw_w, draw_w)
			var gt: Color = g.tint
			cv.draw_set_transform(g_pivot, 0.0, Vector2(g_flip, 1.0))
			_draw_atlas_pose(cv, ghost_tex, RIM_CELL, g_frame, g_rect, Color(gt.r, gt.g, gt.b, gt.a * gk * fade * 0.65))
		cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 2. 司晷主体 80 帧高清连续图集绘制
	if _atlas_tex != null:
		var frame_idx := _pick_atlas_frame()
		var air_pose := _is_airborne_atlas_frame(frame_idx)
		var flip_x := 1.0 if facing < 0 else -1.0
		var pivot := Vector2(0.0, -h * 0.08 if air_pose else h)
		var anchor_y := ATLAS_AIR_Y if air_pose else ATLAS_FOOT_Y
		var dest := Rect2(-draw_w * 0.5, -anchor_y * SPRITE_SCALE, draw_w, draw_w)

		cv.draw_set_transform(pivot, 0.0, Vector2(flip_x * s.x, s.y))

		var body_mod := Color(1.04, 1.05, 1.08, fade)
		_draw_atlas_pose(cv, _atlas_tex, ATLAS_CELL, frame_idx, dest, body_mod)

		# 常驻暗血珀红钟逆光轮廓边（把冷银锻钢首领从背后红钟前立体抠出，告别平涂纸片感！）
		if _atlas_edge_tex != null and state != State.DEAD:
			var rim_pulse := 0.24 + 0.12 * sin(t * 3.7)
			_draw_atlas_pose(cv, _atlas_edge_tex, RIM_CELL, frame_idx, dest, Color(0.96, 0.22, 0.15, rim_pulse * fade))

		if (state == State.WINDUP or state == State.STRIKE) and blade_kind() in [Blade.RED, Blade.RIFT] and _atlas_edge_tex != null:
			_draw_atlas_pose(cv, _atlas_edge_tex, RIM_CELL, frame_idx, dest, Color(1.0, 0.22, 0.18, 0.92 * fade))

		if not is_shell_broken and armor_flash > 0 and _atlas_edge_tex != null:
			var rim_a := clampf(float(armor_flash) / 8.0, 0.0, 1.0) * 0.62 * fade
			_draw_atlas_pose(cv, _atlas_edge_tex, RIM_CELL, frame_idx, dest, Color(0.96, 0.98, 1.0, rim_a))

		if flash > 0:
			var fk := clampf(float(flash) / 9.0, 0.25, 0.85) * fade
			if _atlas_edge_tex != null:
				_draw_atlas_pose(cv, _atlas_edge_tex, RIM_CELL, frame_idx, dest, Color(flash_color.r, flash_color.g, flash_color.b, fk))
			if _atlas_sil_tex != null:
				_draw_atlas_pose(cv, _atlas_sil_tex, RIM_CELL, frame_idx, dest, Color(flash_color.r, flash_color.g, flash_color.b, fk * 0.16))

		# 破壳期胸口暴露脉动的银白/朱砂逆时日晷核
		if is_shell_broken and state != State.DEAD:
			var core_local := Vector2(-8.0, -218.0 if not air_pose else -18.0)
			var pulse := 0.72 + 0.28 * sin(t * 22.0)
			var c_col := Color(1.0, 1.0, 1.0, 0.95 * fade) if _breach_severed else Color(0.88, 0.94, 1.0, 0.92 * fade)
			cv.draw_circle(core_local, 15.0 * pulse, Color(c_col, 0.28 * fade))
			cv.draw_circle(core_local, 6.5 * pulse, c_col)

		# 白刀/倒带刃/居合出刀前冷银十字剑星提示
		if state == State.WINDUP and blade_kind() in [Blade.WHITE, Blade.HORIZON]:
			var remain := int(spec.windup) - state_frames
			if remain <= PARRY_CUE:
				var k := 1.0 - float(remain) / float(PARRY_CUE)
				var tip_local := Vector2(-175.0, -140.0) if bool(_cur.get("rewind_draw", false)) else Vector2(-160.0, -215.0)
				_draw_star(cv, tip_local, 12.0 + 18.0 * k, Color(1.0, 1.0, 1.0, fade * (0.72 + 0.28 * k)))
				cv.draw_circle(tip_local, 16.0 + 18.0 * k, Color(0.94, 0.97, 1.0, 0.28 * fade))

		cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return

	cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ---------------------------------------------------------------- 过去锚点、玩家时痕剪影、逆时裂隙与钟针特效绘制

func _draw_chrono_anchor() -> void:
	if not chrono_anchor_active:
		return
	var foot_local := to_local(chrono_anchor_pos)
	var dial_c := foot_local + Vector2(0.0, -145.0)
	var ratio := clampf(float(chrono_anchor_timer) / float(ANCHOR_HOLD_FRAMES), 0.0, 1.0)
	var pulse := 0.78 + 0.22 * sin(anim_t * 16.0)

	# 连接首领真身与「过去残影锚点」的高反差双层时间银链（黑墨描边 + 纯白发光芯）
	var boss_chest := Vector2(0.0, -half_h * 0.35)
	draw_line(boss_chest, dial_c, Color(0.02, 0.02, 0.04, 0.82), 6.0)
	draw_line(boss_chest, dial_c, Color(0.98, 0.99, 1.0, 0.92 * pulse), 2.4)

	# 过去残影银白塑像（浓墨背衬剪影 + 骨白驻时塑像 + 冷银锋锐轮廓，任何亮/暗背景下皆一目了然！）
	if _atlas_sil_tex != null:
		var draw_w := ATLAS_CELL * SPRITE_SCALE * 0.96
		var flip := 1.0 if chrono_anchor_facing < 0 else -1.0
		var rect := Rect2(-draw_w * 0.5, -ATLAS_FOOT_Y * SPRITE_SCALE * 0.96, draw_w, draw_w)
		draw_set_transform(foot_local + Vector2(4.0, 0.0), 0.0, Vector2(flip * 1.03, 1.02))
		_draw_atlas_pose(self, _atlas_sil_tex, RIM_CELL, chrono_anchor_frame, rect, Color(0.02, 0.02, 0.04, 0.78))
		draw_set_transform(foot_local, 0.0, Vector2(flip, 1.0))
		_draw_atlas_pose(self, _atlas_sil_tex, RIM_CELL, chrono_anchor_frame, rect, Color(0.94, 0.97, 1.0, 0.82 * pulse))
		if _atlas_tex != null:
			_draw_atlas_pose(self, _atlas_tex, ATLAS_CELL, chrono_anchor_frame, rect, Color(1.15, 1.18, 1.24, 0.58 * pulse))
		if _atlas_edge_tex != null:
			_draw_atlas_pose(self, _atlas_edge_tex, RIM_CELL, chrono_anchor_frame, rect, Color(1.0, 1.0, 1.0, 0.96))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 塑像胸口逆时针倒计时日晷星环
	draw_arc(dial_c, 74.0, 0.0, TAU, 40, Color(0.02, 0.02, 0.04, 0.75), 6.0)
	draw_arc(dial_c, 74.0, -PI * 0.5, -PI * 0.5 + TAU * ratio, 40, Color(1.0, 1.0, 1.0, 0.96), 3.4)
	draw_arc(dial_c, 56.0, 0.0, TAU, 32, Color(0.90, 0.94, 1.0, 0.55), 1.6)


func _draw_player_rewind_snare() -> void:
	if not player_snare_active or not _combat_target_ok():
		return
	var p_past := to_local(player_snare_pos)
	var p_now := to_local(target.global_position)
	var ratio := clampf(float(player_snare_timer) / float(SNARE_LOCK_FRAMES), 0.0, 1.0)
	var urgent := 1.0 - ratio
	var f_off := float(target.get(&"foot_offset")) if target.get(&"foot_offset") != null else 80.0
	var past_waist := p_past + Vector2(0.0, f_off - 72.0)
	var now_waist := p_now + Vector2(0.0, f_off - 72.0)

	# 连接玩家当前位置与「2 秒前纯白时痕剪影」的紧绷双层时间银弦（严守冷银无彩，绝不染紫！）
	draw_line(now_waist, past_waist, Color(0.02, 0.02, 0.04, 0.80), 6.2)
	draw_line(now_waist, past_waist, Color(0.95, 0.97, 1.0, 0.78 + 0.22 * urgent), 2.4 + 1.8 * urgent)

	# 直接提取主角 ActorSprite 渲染「2 秒前纯白快门残影塑像」（浓墨背衬 + 纯白高亮重影）！
	var actor_spr: Sprite2D = target.get_node_or_null("Visual/ActorSprite")
	if actor_spr != null and actor_spr.texture != null:
		var tex := actor_spr.texture
		var src_rect := Rect2(Vector2.ZERO, tex.get_size())
		if actor_spr.region_enabled:
			src_rect = actor_spr.region_rect
		elif actor_spr.hframes > 1 or actor_spr.vframes > 1:
			var cw := tex.get_width() / float(maxi(actor_spr.hframes, 1))
			var ch := tex.get_height() / float(maxi(actor_spr.vframes, 1))
			var fc := actor_spr.frame % maxi(actor_spr.hframes, 1)
			var fr := actor_spr.frame / maxi(actor_spr.hframes, 1)
			src_rect = Rect2(float(fc) * cw, float(fr) * ch, cw, ch)
		var g_scale := actor_spr.global_scale.abs()
		var dst_sz := src_rect.size * g_scale
		var flip_s := -1.0 if player_snare_facing < 0 else 1.0
		var spr_foot := p_past + Vector2(0.0, f_off)
		draw_set_transform(spr_foot + Vector2(-3.0, 0.0), 0.0, Vector2(flip_s * 1.05, 1.03))
		draw_texture_rect_region(tex, Rect2(-dst_sz.x * 0.5, -dst_sz.y + 8.0, dst_sz.x, dst_sz.y), src_rect, Color(0.02, 0.02, 0.04, 0.84))
		draw_set_transform(spr_foot, 0.0, Vector2(flip_s, 1.0))
		draw_texture_rect_region(tex, Rect2(-dst_sz.x * 0.5, -dst_sz.y + 8.0, dst_sz.x, dst_sz.y), src_rect, Color(1.85, 1.92, 2.08, 0.80))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		draw_circle(past_waist, 28.0, Color(0.98, 0.99, 1.0, 0.85))

	# 2 秒前时痕外围逆时针收缩锁环与地面十字刻针
	var ring_r := 66.0 * (0.58 + 0.42 * ratio)
	draw_arc(past_waist, ring_r, 0.0, TAU, 36, Color(0.02, 0.02, 0.04, 0.78), 5.6)
	draw_arc(past_waist, ring_r, -PI * 0.5, -PI * 0.5 + TAU * ratio, 36, Color(1.0, 1.0, 1.0, 0.96), 3.2)
	draw_line(past_waist + Vector2(-ring_r - 12.0, 0.0), past_waist + Vector2(-ring_r + 8.0, 0.0), Color.WHITE, 2.2)
	draw_line(past_waist + Vector2(ring_r - 8.0, 0.0), past_waist + Vector2(ring_r + 12.0, 0.0), Color.WHITE, 2.2)


func _draw_tail_tether(tip: Vector2, sag: float, col: Color) -> void:
	var from := Vector2(-float(facing) * half_w * 0.45, -half_h * 0.12)
	var mid := (from + tip) * 0.5 + Vector2(0.0, sag)
	var pts := PackedVector2Array()
	for i in 17:
		var u := float(i) / 16.0
		pts.append(from.lerp(mid, u).lerp(mid.lerp(tip, u), u))
	draw_polyline(pts, Color(0.04, 0.04, 0.06, 0.95), 9.0)
	draw_polyline(pts, Color(col, 0.85), 2.4)


func _draw_nail() -> void:
	var col := Color(0.92, 0.95, 1.0)
	var p := to_local(nail_point)
	var y := p.y - 3.0
	if nail_phase == Nail.AIM:
		var t := telegraph()
		var locked: bool = state_frames >= int(spec.windup) - NAIL_TRACK
		var a := 0.3 + 0.6 * t
		draw_line(Vector2(p.x - NAIL_RADIUS, y), Vector2(p.x + NAIL_RADIUS, y), Color(col, a), 7.0 if locked else 4.0)
		draw_line(Vector2(p.x, y - 84.0), Vector2(p.x, y), Color(col, a * 0.65), 2.4)
		return
	var off := absf(nail_point.x - global_position.x)
	var taut := clampf(off / TETHER_LEN, 0.0, 1.0)
	_draw_tail_tether(p + Vector2(0.0, -6.0), 65.0 * (1.0 - taut), col)
	draw_line(Vector2(p.x - 42.0, y), Vector2(p.x + 42.0, y), Color(col, 0.85), 4.0)


func _draw_rift() -> void:
	if rift_state == Rift.NONE:
		return
	var p := to_local(rift_pos)
	if rift_state == Rift.ACTIVE:
		var pulse := 0.5 + 0.5 * sin(anim_t * 22.0)
		if _vfx_tex != null:
			var sc := 0.86 + 0.06 * pulse
			var sz := Vector2(VFX_CELL * sc, VFX_CELL * sc)
			_draw_vfx_cell(self, 4, Rect2(p - sz * 0.5, sz), Color(1.08, 1.02, 1.02, 0.98))
		else:
			draw_circle(p, 42.0, Color(0.92, 0.20, 0.18, 0.65))
	elif rift_state == Rift.PURPLE:
		var k := 1.0 - float(rift_timer) / float(RIFT_PURPLE_FX_FRAMES)
		var alpha := clampf(1.0 - pow(k, 1.65), 0.0, 1.0)
		if _vfx_tex != null:
			var sc := lerpf(0.92, 1.42, pow(k, 0.42))
			var sz := Vector2(VFX_CELL * sc, VFX_CELL * sc)
			_draw_vfx_cell(self, 5, Rect2(p - sz * 0.5, sz), Color(1.14, 1.06, 1.18, alpha))


func _draw_tapered_cut_beam(a: Vector2, b: Vector2, glow_col: Color, core_col: Color, half_thick: float) -> void:
	var span := b - a
	var length := span.length()
	if length < 8.0:
		return
	var dir := span / length
	var n := Vector2(-dir.y, dir.x)
	var taper := minf(110.0, length * 0.18)
	var a_in := a + dir * taper
	var b_in := b - dir * taper
	draw_colored_polygon(PackedVector2Array([
		a, a_in + n * half_thick, b_in + n * half_thick,
		b, b_in - n * half_thick, a_in - n * half_thick,
	]), glow_col)
	var inner_h := maxf(1.2, half_thick * 0.32)
	draw_colored_polygon(PackedVector2Array([
		a, a_in + n * inner_h, b_in + n * inner_h,
		b, b_in - n * inner_h, a_in - n * inner_h,
	]), core_col)


func _draw_horizon_effects() -> void:
	if state == State.WINDUP and blade_kind() == Blade.HORIZON:
		var t := telegraph()
		var p0 := Vector2(float(facing) * 42.0, half_h - 122.0)
		var p1 := to_local(Vector2(_horizon_aim_to_x, feet_y() - 122.0))
		_draw_tapered_cut_beam(
			p0, p1,
			Color(0.90, 0.93, 0.98, 0.25 + 0.40 * t),
			Color(1.0, 1.0, 1.0, 0.60 + 0.40 * t),
			5.0 * (1.0 - 0.32 * t)
		)

	if not _horizon_scar.is_empty() and bool(_horizon_scar.get("active", false)):
		var x0 := float(_horizon_scar.get("x0", 0.0))
		var x1 := float(_horizon_scar.get("x1", 0.0))
		var wy := float(_horizon_scar.get("y", feet_y() - 122.0))
		var a := to_local(Vector2(x0, wy))
		var b := to_local(Vector2(x1, wy))
		var t_rem := int(_horizon_scar.get("timer", 0))
		if t_rem > 0:
			var pulse := 1.0 - float(t_rem) / float(HORIZON_SCAR_DELAY)
			_draw_tapered_cut_beam(a, b, Color(0.92, 0.95, 1.0, 0.45 + 0.45 * pulse), Color(1.0, 1.0, 1.0, 0.98), 7.0)
		else:
			var fade := clampf(1.0 - float(-t_rem) / 8.0, 0.0, 1.0)
			_draw_tapered_cut_beam(a, b, Color(0.95, 0.97, 1.0, 0.72 * fade), Color(1.0, 1.0, 1.0, fade), 16.0 * fade)


func _draw_water_waves() -> void:
	for w: Dictionary in _waves:
		var p := to_local(w.pos as Vector2)
		var d := float(int(w.dir))
		var k := clampf(1.0 - float(w.life) / maxf(float(w.max_life), 0.01), 0.0, 1.0)
		if _vfx_tex != null:
			var flip := 1.0 if d < 0.0 else -1.0
			var draw_sz := Vector2(285.0, 218.0)
			draw_set_transform(p + Vector2(0.0, 8.0), 0.0, Vector2(flip, 1.0))
			_draw_vfx_cell(self, 0, Rect2(Vector2(-draw_sz.x * 0.44, -draw_sz.y), draw_sz), Color(1.06, 1.06, 1.08, 0.98 * k))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			draw_line(p + Vector2(-d * 60.0, -6.0), p + Vector2(d * 35.0, -80.0), Color(0.95, 0.97, 1.0, k), 8.0)


func _draw_rain_needles() -> void:
	for nd: Dictionary in _rain_needles:
		var pos := to_local(nd.pos as Vector2)
		var tpos := to_local(nd.target_pos as Vector2)
		var dir: Vector2 = nd.dir
		var dly := int(nd.delay)
		var reflected := bool(nd.get("reflected", false))
		var ph := String(nd.get("phase", "falling"))
		if dly > 0 and not reflected:
			var aim_k := 1.0 - float(dly) / 30.0
			draw_line(pos, tpos, Color(0.92, 0.95, 1.0, 0.16 + 0.26 * aim_k), 1.4)
			draw_line(tpos + Vector2(-18.0, -2.0), tpos + Vector2(18.0, -2.0), Color(0.98, 0.99, 1.0, 0.45 + 0.35 * aim_k), 2.8)
			draw_circle(pos, 5.0 + 2.5 * sin(anim_t * 18.0), Color(1.0, 1.0, 1.0, 0.90))
		else:
			if _vfx_tex != null:
				var ang := dir.angle() - PI
				var mod_c := Color(0.84, 0.48, 1.0, 1.0) if reflected else (Color(1.08, 1.08, 1.12, 0.98) if ph == "rewinding" else Color(1.0, 1.0, 1.02, 0.96))
				draw_set_transform(pos, ang, Vector2.ONE)
				_draw_vfx_cell(self, 1, Rect2(Vector2(-86.0, -48.0), Vector2(180.0, 96.0)), mod_c)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			else:
				draw_line(pos - dir * 82.0, pos + dir * 24.0, Color.WHITE, 3.2)


func _draw_clash_sparks() -> void:
	if _vfx_tex == null or _clash_sparks.is_empty():
		return
	for sp: Dictionary in _clash_sparks:
		var k := clampf(float(sp.life) / maxf(float(sp.max_life), 0.01), 0.0, 1.0)
		var a := 1.0 - k * k
		var p := to_local(sp.pos as Vector2)
		var sz := VFX_CELL * float(sp.sc) * lerpf(0.76, 1.22, k)
		draw_set_transform(p, float(sp.rot), Vector2.ONE)
		_draw_vfx_cell(self, 3, Rect2(Vector2(-sz * 0.5, -sz * 0.5), Vector2(sz, sz)), Color(1.12, 1.12, 1.14, a))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw() -> void:
	super()
	draw_set_transform(Vector2.ZERO)
	_draw_chrono_anchor()
	_draw_player_rewind_snare()
	if nail_phase != Nail.NONE:
		_draw_nail()
	if rift_state != Rift.NONE:
		_draw_rift()
	_draw_horizon_effects()
	_draw_water_waves()
	_draw_rain_needles()
	_draw_clash_sparks()

	if state == State.LAUNCHED and air_rules != null and bool(air_rules.rules.beat_check):
		if on_beat():
			draw_arc(Vector2(0.0, -half_h * 0.2), half_h * 0.98, 0.0, TAU, 40, Color(0.96, 0.98, 1.0, 0.68), 4.2)
	if state == State.WINDUP:
		var b_kind := blade_kind()
		if b_kind not in [Blade.NAIL, Blade.HORIZON, Blade.NEEDLES, Blade.BACKSTEP, Blade.PERCH, Blade.ANCHOR, Blade.SNARE]:
			var col := Color(0.96, 0.24, 0.20) if b_kind in [Blade.RED, Blade.RIFT] else Color(0.95, 0.97, 1.0)
			var t := telegraph()
			var reach := float(_cur.get("range", 0.0)) * float(facing)
			var y := half_h - 3.0
			draw_line(Vector2(0.0, y), Vector2(reach, y), Color(col, 0.14 + 0.26 * t), 2.4)
			draw_line(Vector2(reach, y - 14.0), Vector2(reach, y + 2.0), Color(col, 0.34 + 0.42 * t), 2.4)
