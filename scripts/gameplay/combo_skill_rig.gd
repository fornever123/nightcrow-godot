extends Node2D
## 断晓 · 评分渐进解锁「按住时缓 + 十字键/方向键搓招」技能系统（ComboSkillRig）
##
## 核心机制：
##   1. 按住 LB（手柄）或 Tab / Ctrl（键盘）维持定时时缓（0.08x，默认最长 2.6 秒真实时间）；
##      松开触发键立即退出时缓恢复流速；若已输入半段指令后松开或输错方向，触发沉浸式「指令碎裂」失败特效与音效。
##   2. 时缓期间使用手柄十字键（不与移动关联）或键盘方向键（↑↓←→）输入指令搓出技能：
##      - 每次按下方向键，在人物身侧实时绽放对应方向粒子束、哥特方向符纹与递增音高钢锁音效（墙钟 60fps 流畅演播）；
##      - 搓招成功立刻退出时缓并绽放双层 5:59 圣印、径向刃芒粒子与真钢出鞘/重斩/钟鸣多层音效。
##   3. 8 套强度递增技能按战斗评分 D / C / B / A / S 渐进解锁，且 8 组指令严格前缀无冲突：
##      - D 档：↑↑ 鸦闪·穿影 / ↓↓ 凝晷·震步
##      - C 档：↓↑→ 裂隙·挑月 / ←→→ 断潮·穿云
##      - B 档：↑↓→ 星陨·断岳 / →←↑ 千羽·追猎
##      - A 档：↑→↓← 司辰·裂界
##      - S 档：↓←↑→ 断晓·终焉裁夜
##   4. 时缓开启时默认显示「已解锁技能按键操作提示」哥特浮层，可在设置页关闭。

const GamepadManager := preload("res://scripts/core/gamepad_manager.gd")
const GothicFonts := preload("res://scripts/ui/gothic_fonts.gd")
const Shade := preload("res://scripts/night/shade.gd")
const SpatialRiftScript := preload("res://scripts/gameplay/spatial_rift.gd")

signal stance_changed(active: bool)
signal skill_cast(skill_id: String, rank_idx: int)
signal skill_failed(reason: String)

const SLOWMO_SCALE := 0.08
const BASE_STANCE_DURATION := 2.6
const CAST_COOLDOWN := 1.8
const CANCEL_COOLDOWN := 0.35
const S_SKILL_COOLDOWN := 8.0
const AUD_DIR := "res://assets/audio/yg_zhanzhong/"

const RANK_LETTERS: Array[String] = ["D", "C", "B", "A", "S"]
const DIR_GLYPHS := {"U": "↑", "D": "↓", "L": "←", "R": "→"}
const DIR_VECS := {
	"U": Vector2(0.0, -1.0),
	"D": Vector2(0.0, 1.0),
	"L": Vector2(-1.0, 0.0),
	"R": Vector2(1.0, 0.0),
}

const COL_INK := Color(0.032, 0.028, 0.058, 0.94)
const COL_SILVER := Color("e6e9ef")
const COL_BONE := Color("f0ece2")
const COL_STEEL := Color("8b95a8")
const COL_VIOLET := Color("9a6cff")
const COL_VIOLET_LIGHT := Color("d4bcff")
const COL_GOLD := Color("f5dfa3")
const COL_CYAN := Color("b8dcff")
const COL_FAIL := Color("f06c88")
const COL_FAIL_DARK := Color("7a223a")

## 8 套技能指令严格满足「前缀自由（Prefix-Free）」：任意两条的前两键完全不同，绝无误触发冲突
const SKILLS: Array[Dictionary] = [
	{"id": "crow_flash",    "rank": 0, "seq": ["U", "U"],           "name": "鸦闪·穿影",     "desc": "瞬影穿斩 + 回1残影",   "accent": Color("b8dcff")},
	{"id": "chrono_pulse",  "rank": 0, "seq": ["D", "D"],           "name": "凝晷·震步",     "desc": "环震击退 + 净化弹幕",  "accent": Color("eef6ff")},
	{"id": "rift_moon",     "rank": 1, "seq": ["D", "U", "R"],      "name": "裂隙·挑月",     "desc": "升龙挑飞 + 空间裂口",  "accent": Color("c8b0ff")},
	{"id": "tide_breaker",  "rank": 1, "seq": ["L", "R", "R"],      "name": "断潮·穿云",     "desc": "穿透剑波 + 重创凝壳",  "accent": Color("b678ff")},
	{"id": "star_cleave",   "rank": 2, "seq": ["U", "D", "R"],      "name": "星陨·断岳",     "desc": "重劈震地 + 强力破甲",  "accent": Color("d5a8ff")},
	{"id": "feather_hunt",  "rank": 2, "seq": ["R", "L", "U"],      "name": "千羽·追猎",     "desc": "6道追踪紫羽飞刃",      "accent": Color("c99bff")},
	{"id": "chrono_domain", "rank": 3, "seq": ["U", "R", "D", "L"], "name": "司辰·裂界",     "desc": "5:59定身 + 十字四连斩","accent": Color("eef6ff")},
	{"id": "dawn_judgment", "rank": 4, "seq": ["D", "L", "U", "R"], "name": "断晓·终焉裁夜", "desc": "天穹裁决巨刃 + 裂隙终结","accent": Color("f5dfa3")},
]

var stage: Node = null
var player: CharacterBody2D = null
var unlock_all_override: bool = false

## 状态（全墙钟计时，绝不受 Engine.time_scale 干扰）
var stance_active: bool = false
var input_seq: Array[String] = []
var stance_cooldown: float = 0.0
var s_skill_cooldown: float = 0.0
var cast_count: int = 0
var last_cast_id: String = ""

## 沉浸反馈计数（供测试与调试观测）
var key_particle_burst_count: int = 0
var success_fx_count: int = 0
var fail_fx_count: int = 0
var last_sfx_event: String = ""

var _entered_via_input: bool = false
var _require_release_before_reenter: bool = false
var _stance_rem: float = 0.0
var _stance_max: float = BASE_STANCE_DURATION
var _last_us: int = 0
var _wrong_flash: float = 0.0
var _success_flash: float = 0.0
var _success_flash_col: Color = COL_VIOLET_LIGHT
var _fail_toast: String = ""
var _fail_toast_timer: float = 0.0
var _banner_text: String = ""
var _banner_sub: String = ""
var _banner_col: Color = COL_VIOLET_LIGHT
var _banner_timer: float = 0.0
var _vfx_time: float = 0.0
var _ambient_mote_accum: float = 0.0
var _rng := RandomNumberGenerator.new()

## 合成招式模板
var _mv_light: MoveDefinition
var _mv_launch: MoveDefinition
var _mv_wave: MoveDefinition
var _mv_heavy: MoveDefinition
var _mv_feather: MoveDefinition
var _mv_finale: MoveDefinition

## 战斗物理投射物队列（跟随世界流速）
var _waves: Array[Dictionary] = []
var _feathers: Array[Dictionary] = []
var _sky_blades: Array[Dictionary] = []
var _delayed_slashes: Array[Dictionary] = []
var _rings: Array[Dictionary] = []
var _lines: Array[Dictionary] = []
var _flashes: Array[Dictionary] = []

## 墙钟 60fps 沉浸粒子与符纹队列（时缓 0.08x 期间依然丝滑绽放）
var _particles: Array[Dictionary] = []
var _dir_glyphs: Array[Dictionary] = []
var _success_seals: Array[Dictionary] = []
var _fail_cracks: Array[Dictionary] = []

## 独立多层真钢/钟鸣/碎裂音频池（不受 time_scale 拖拽变调）
var _sfx_players: Dictionary = {}

## 屏幕 HUD 浮层（时缓暗角 + 5:59 钟盘进度 + 已解锁技能按键提示）
var _ui_layer: CanvasLayer = null
var _ui_canvas: Control = null
var _font_serif: Font = null
var _font_bold: Font = null
var _font_cinzel: Font = null
var _font_blackletter: Font = null


func _ready() -> void:
	name = "ComboSkillRig"
	z_index = 12
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	GamepadManager.ensure_skill_actions()
	_font_serif = GothicFonts.serif(500)
	_font_bold = GothicFonts.serif(800)
	_font_cinzel = GothicFonts.cinzel(700, false, 800)
	_font_blackletter = GothicFonts.blackletter(700)
	_build_moves()
	_build_sfx_pool()
	_ensure_ui()
	_last_us = Time.get_ticks_usec()


func _exit_tree() -> void:
	if stance_active:
		stance_active = false
		Engine.time_scale = 1.0
	for k in _sfx_players.keys():
		var ap: AudioStreamPlayer = _sfx_players[k]
		if ap != null and is_instance_valid(ap):
			ap.stop()
			ap.stream = null
	_sfx_players.clear()


func setup(p_stage: Node, p_player: CharacterBody2D) -> void:
	stage = p_stage
	player = p_player
	GamepadManager.ensure_skill_actions()
	if _ui_canvas != null:
		_ui_canvas.queue_redraw()


func _build_sfx_pool() -> void:
	var files := {
		"sheathe": AUD_DIR + "ult_sheathe.ogg",
		"ui_move": AUD_DIR + "ui_move.ogg",
		"ui_back": AUD_DIR + "ui_back.ogg",
		"cut_0": AUD_DIR + "ult_cut_0.ogg",
		"cut_2": AUD_DIR + "ult_cut_2.ogg",
		"impact": AUD_DIR + "ult_impact.ogg",
		"parry_lock": AUD_DIR + "h3_parry_lock.wav",
		"unsheathe": AUD_DIR + "h3_unsheathe.wav",
		"slash_fast": AUD_DIR + "h3_slash_fast.wav",
		"slash_heavy": AUD_DIR + "h3_slash_heavy.wav",
		"anvil_bell": AUD_DIR + "h3_anvil_bell.wav",
	}
	for k in files.keys():
		var p_str: String = files[k]
		if not ResourceLoader.exists(p_str):
			continue
		var ap := AudioStreamPlayer.new()
		ap.name = "ComboSfx_" + k
		ap.process_mode = Node.PROCESS_MODE_ALWAYS
		ap.stream = load(p_str)
		ap.bus = "Master"
		add_child(ap)
		_sfx_players[k] = ap


func _play_pool(key: String, vol_db: float = -4.0, pitch: float = 1.0) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var ap: AudioStreamPlayer = _sfx_players.get(key)
	if ap == null or not is_instance_valid(ap):
		return
	ap.volume_db = vol_db
	ap.pitch_scale = clampf(pitch, 0.35, 2.2)
	ap.play()


func _build_moves() -> void:
	_mv_light = _make_move(&"combo_crow_flash", 22.0, 260.0, false, 2)
	_mv_launch = _make_move(&"combo_rift_moon", 26.0, 320.0, true, 3)
	_mv_launch.launch_speed = 640.0
	_mv_wave = _make_move(&"combo_tide_breaker", 30.0, 480.0, false, 3)
	_mv_heavy = _make_move(&"combo_star_cleave", 38.0, 560.0, true, 4)
	_mv_heavy.launch_speed = 520.0
	_mv_feather = _make_move(&"combo_feather_hunt", 11.0, 120.0, false, 0)
	_mv_finale = _make_move(&"combo_dawn_judgment", 34.0, 440.0, true, 3)
	_mv_finale.launch_speed = 580.0


func _make_move(mid: StringName, dmg: float, kb: float, launch: bool, hitstop: int) -> MoveDefinition:
	var mv := MoveDefinition.new()
	mv.id = mid
	mv.damage = dmg
	mv.knockback = kb
	mv.forces_launch = launch
	mv.hitstop_frames = hitstop
	mv.victim_hitstop_frames = hitstop
	mv.startup_frames = 0
	mv.active_frames = 4
	mv.recovery_frames = 0
	return mv


# ---------------------------------------------------------------- 评分与 Buff 查询

func _get_perk_rig() -> Node:
	if stage == null:
		return null
	var rig: Variant = stage.get("perk_rig")
	if rig != null and is_instance_valid(rig):
		return rig as Node
	return stage.get_node_or_null("PerkRig")


func current_style_rank() -> int:
	if stage != null and stage.get("style") != null:
		return clampi(int(stage.style.rank_index()), 0, 4)
	return 0


func effective_unlock_rank() -> int:
	if unlock_all_override:
		return 4
	var rig := _get_perk_rig()
	if rig != null and bool(rig.get("skill_unlock_all")):
		return 4
	var cur := current_style_rank()
	var discount := int(rig.get("skill_rank_discount")) if rig != null else 0
	var early := int(rig.get("skill_early_unlocks")) if rig != null else 0
	return clampi(cur + discount + early, 0, 4)


func is_skill_unlocked(skill: Dictionary) -> bool:
	return int(skill.get("rank", 0)) <= effective_unlock_rank()


func get_unlocked_skills() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for sk in SKILLS:
		if is_skill_unlocked(sk):
			out.append(sk)
	return out


func _get_slowmo_bonus() -> float:
	var rig := _get_perk_rig()
	return float(rig.get("skill_slowmo_bonus")) if rig != null else 0.0


func _get_cd_mul() -> float:
	var rig := _get_perk_rig()
	return clampf(float(rig.get("skill_cd_mul")), 0.20, 1.5) if rig != null else 1.0


func _get_skill_dmg_mul() -> float:
	var rig := _get_perk_rig()
	var bonus := float(rig.get("skill_dmg_mul")) if rig != null else 1.0
	var p_atk := float(player.attack_damage_mul) if player != null and is_instance_valid(player) else 1.0
	return bonus * p_atk


# ---------------------------------------------------------------- 按住维持时缓生命周期（安全防卡死）

func _is_blocked_context() -> bool:
	if get_tree() == null or get_tree().paused:
		return true
	if player == null or not is_instance_valid(player):
		return true
	if float(player.hp) <= 0.0:
		return true
	if player.has_method(&"is_ult") and bool(player.call(&"is_ult")):
		return true
	if stage != null:
		if stage.get("trial_completed") == true:
			return true
		var fork: Variant = stage.get("fork_overlay")
		if fork != null and is_instance_valid(fork) and bool(fork.get("is_open")):
			return true
		var pm: Variant = stage.get("pause_menu")
		if pm != null and is_instance_valid(pm) and bool(pm.get("opened")):
			return true
	return false


func can_enter_stance() -> bool:
	if stance_active or stance_cooldown > 0.0 or _require_release_before_reenter:
		return false
	return not _is_blocked_context()


func enter_stance(via_input: bool = false) -> bool:
	if not can_enter_stance():
		return false
	stance_active = true
	_entered_via_input = via_input
	input_seq.clear()
	_wrong_flash = 0.0
	_ambient_mote_accum = 0.0
	_stance_max = BASE_STANCE_DURATION + _get_slowmo_bonus()
	_stance_rem = _stance_max
	_last_us = Time.get_ticks_usec()
	Engine.time_scale = SLOWMO_SCALE
	_play_sfx_cue("enter")
	_spawn_stance_enter_particles()
	GamepadManager.rumble(0.18, 0.09, 0.07)
	stance_changed.emit(true)
	queue_redraw()
	if _ui_canvas != null:
		_ui_canvas.queue_redraw()
	return true


func exit_stance(cd_seconds: float = CANCEL_COOLDOWN) -> void:
	var was_active := stance_active
	stance_active = false
	_entered_via_input = false
	input_seq.clear()
	if stage != null and stage.has_method(&"reset_time_scale"):
		stage.call(&"reset_time_scale")
	else:
		Engine.time_scale = 1.0
	if cd_seconds > 0.0:
		stance_cooldown = maxf(stance_cooldown, cd_seconds * _get_cd_mul())
	if was_active:
		stance_changed.emit(false)
	queue_redraw()
	if _ui_canvas != null:
		_ui_canvas.queue_redraw()


# ---------------------------------------------------------------- 按住维持输入处理与搓招匹配

func _input(event: InputEvent) -> void:
	if _is_blocked_context():
		if stance_active:
			exit_stance(0.0)
		return

	# 1. 松开时缓键：立刻结束维持时缓（若已输入未完成指令则触发失败碎裂演出）
	if event.is_action_released(&"skill_stance"):
		_require_release_before_reenter = false
		if stance_active:
			if not input_seq.is_empty():
				_trigger_fail_feedback("指令中断")
			else:
				_play_sfx_cue("cancel")
			exit_stance(CANCEL_COOLDOWN)
			get_viewport().set_input_as_handled()
		return

	if event.is_echo():
		return

	# 2. 按下并按住时缓键：进入维持时缓
	if event.is_action_pressed(&"skill_stance"):
		_require_release_before_reenter = false
		if can_enter_stance():
			enter_stance(true)
			get_viewport().set_input_as_handled()
		return

	if not stance_active:
		return

	# 时缓期间：按 B 或 Esc 也可紧急取消
	var is_cancel_btn := false
	if event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed and (event as InputEventJoypadButton).button_index == JOY_BUTTON_B:
		is_cancel_btn = true
	elif event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		is_cancel_btn = true
	if is_cancel_btn:
		if not input_seq.is_empty():
			_trigger_fail_feedback("指令中断")
		else:
			_play_sfx_cue("cancel")
		_require_release_before_reenter = true
		exit_stance(CANCEL_COOLDOWN)
		get_viewport().set_input_as_handled()
		return

	# 3. 按住时缓期间：读取十字键 / 方向键输入
	var dir := ""
	if event.is_action_pressed(&"skill_up"):
		dir = "U"
	elif event.is_action_pressed(&"skill_down"):
		dir = "D"
	elif event.is_action_pressed(&"skill_left"):
		dir = "L"
	elif event.is_action_pressed(&"skill_right"):
		dir = "R"
	if dir != "":
		get_viewport().set_input_as_handled()
		feed_direction(dir)


func feed_direction(dir: String) -> String:
	if not stance_active or dir == "":
		return ""
	input_seq.append(dir)
	var unlocked := get_unlocked_skills()
	var step_idx := input_seq.size()

	# 1. 检查是否完全命中某个已解锁且未在独立 CD 的技能 -> 立即成功释放！
	for sk in unlocked:
		if String(sk["id"]) == "dawn_judgment" and s_skill_cooldown > 0.0:
			continue
		var seq: Array = sk["seq"]
		if seq.size() == step_idx and _matches_prefix(seq, input_seq):
			var sid := String(sk["id"])
			_spawn_key_particles(dir, step_idx, true)
			_trigger_success_feedback(sk)
			_cast_skill(sk)
			_require_release_before_reenter = Input.is_action_pressed(&"skill_stance")
			exit_stance(CAST_COOLDOWN)
			return sid

	# 2. 检查是否仍是某已解锁技能的合法前缀 -> 在人物边绽放方向粒子束 + 递增钢锁音
	if _has_matching_prefix(unlocked, input_seq):
		_spawn_key_particles(dir, step_idx, false)
		_play_sfx_cue("tick", step_idx)
		GamepadManager.rumble(0.08 + 0.03 * float(step_idx), 0.04, 0.035)
		queue_redraw()
		if _ui_canvas != null:
			_ui_canvas.queue_redraw()
		return ""

	# 3. 输错方向（或尝试施放未解锁/冷却中的技能）：在人物边绽放碎裂失败粒子 + 裂纹 + 碎音
	_spawn_key_particles(dir, step_idx, false, true)
	_trigger_fail_feedback("指令碎裂")
	input_seq.clear()
	queue_redraw()
	if _ui_canvas != null:
		_ui_canvas.queue_redraw()
	return ""


func _matches_prefix(seq: Array, prefix: Array[String]) -> bool:
	if prefix.size() > seq.size():
		return false
	for i in prefix.size():
		if String(seq[i]) != prefix[i]:
			return false
	return true


func _has_matching_prefix(skills: Array[Dictionary], prefix: Array[String]) -> bool:
	for sk in skills:
		if String(sk["id"]) == "dawn_judgment" and s_skill_cooldown > 0.0:
			continue
		if _matches_prefix(sk["seq"], prefix):
			return true
	return false


# ---------------------------------------------------------------- 人物边按键粒子、成功圣印与失败碎裂特效

func _player_center() -> Vector2:
	if player != null and is_instance_valid(player):
		return player.global_position + Vector2(0.0, -44.0)
	return Vector2.ZERO


func _spawn_stance_enter_particles() -> void:
	if player == null or not is_instance_valid(player):
		return
	var c := _player_center()
	for i in 16:
		var ang := float(i) * (TAU / 16.0)
		var dir_v := Vector2(cos(ang), sin(ang))
		_particles.append({
			"pos": c + dir_v * 68.0,
			"vel": -dir_v * _rng.randf_range(120.0, 200.0),
			"col": COL_VIOLET_LIGHT if i % 2 == 0 else COL_SILVER,
			"size": _rng.randf_range(3.2, 5.5),
			"ttl": 0.28,
			"max_ttl": 0.28,
			"gravity": 0.0,
			"shape": "diamond",
		})


## 每次按下方向搓招键时在人物身侧绽放对应方向粒子束与哥特符纹
func _spawn_key_particles(dir: String, step_idx: int, is_final: bool, is_wrong: bool = false) -> void:
	key_particle_burst_count += 1
	if player == null or not is_instance_valid(player):
		return
	var c := _player_center()
	var dv: Vector2 = DIR_VECS.get(dir, Vector2.UP)
	var base_ang := dv.angle()
	var burst_origin := c + dv * 34.0
	var count := 20 if is_final else 16

	for i in count:
		var spread := _rng.randf_range(-0.62, 0.62)
		var spd := _rng.randf_range(140.0, 360.0 if is_final else 280.0)
		var vel := Vector2(cos(base_ang + spread), sin(base_ang + spread)) * spd
		var col := COL_FAIL if is_wrong else (
			COL_GOLD if (is_final or step_idx >= 3 or i % 3 == 0) else (
				COL_SILVER if i % 2 == 0 else COL_VIOLET_LIGHT
			)
		)
		_particles.append({
			"pos": burst_origin + Vector2(_rng.randf_range(-10.0, 10.0), _rng.randf_range(-10.0, 10.0)),
			"vel": vel,
			"col": col,
			"size": _rng.randf_range(3.5, 7.2 if is_final else 5.8),
			"ttl": _rng.randf_range(0.24, 0.42),
			"max_ttl": 0.42,
			"gravity": 180.0 if is_wrong else -30.0,
			"shape": "shard" if (is_wrong or i % 3 == 0) else "diamond",
		})

	# 人物旁悬浮方向符纹（↑ ↓ ← →）与微光环
	_dir_glyphs.append({
		"pos": c + dv * 54.0,
		"vel": dv * 52.0,
		"glyph": String(DIR_GLYPHS.get(dir, dir)),
		"col": COL_FAIL if is_wrong else (COL_GOLD if is_final or step_idx >= 3 else COL_SILVER),
		"ring_col": COL_FAIL if is_wrong else COL_VIOLET_LIGHT,
		"ttl": 0.44,
		"max_ttl": 0.44,
	})


## 搓招成功：人物双层 5:59 圣印展开 + 32 颗径向刃芒粒子 + 屏边微光 + 多层真钢/钟鸣音效
func _trigger_success_feedback(sk: Dictionary) -> void:
	success_fx_count += 1
	var ridx := int(sk.get("rank", 0))
	var acc: Color = sk.get("accent", COL_VIOLET_LIGHT)
	_success_flash = 0.30 + 0.05 * float(ridx)
	_success_flash_col = acc
	_play_sfx_cue("success", ridx)

	if player == null or not is_instance_valid(player):
		return
	var c := _player_center()
	_success_seals.append({
		"pos": c,
		"max_r": 125.0 + float(ridx) * 26.0,
		"col": acc,
		"ttl": 0.42 + 0.05 * float(ridx),
		"max_ttl": 0.42 + 0.05 * float(ridx),
		"rot": _rng.randf_range(0.0, TAU),
	})
	var p_cnt := 28 + ridx * 6
	for i in p_cnt:
		var ang := (float(i) / float(p_cnt)) * TAU + _rng.randf_range(-0.08, 0.08)
		var spd := _rng.randf_range(220.0, 520.0 + float(ridx) * 60.0)
		var col := COL_GOLD if i % 4 == 0 else (COL_SILVER if i % 2 == 0 else acc)
		_particles.append({
			"pos": c + Vector2(cos(ang), sin(ang)) * 18.0,
			"vel": Vector2(cos(ang), sin(ang)) * spd,
			"col": col,
			"size": _rng.randf_range(4.2, 8.5),
			"ttl": _rng.randf_range(0.32, 0.56),
			"max_ttl": 0.56,
			"gravity": 90.0,
			"shape": "shard" if i % 2 == 0 else "diamond",
		})


## 搓招失败 / 指令中断：人物周身裂纹 + 22 枚下坠碎晶粒子 + 红灰暗幕脉冲 + 碎裂音效与双震
func _trigger_fail_feedback(reason: String) -> void:
	fail_fx_count += 1
	_wrong_flash = 0.42
	_fail_toast = reason
	_fail_toast_timer = 0.72
	_play_sfx_cue("fail")
	_shake_camera(5.5)
	GamepadManager.rumble(0.36, 0.28, 0.14)
	skill_failed.emit(reason)

	if player == null or not is_instance_valid(player):
		return
	var c := _player_center()
	# 6 条哥特钟盘碎裂折线
	for i in 6:
		var ang := float(i) * (TAU / 6.0) + _rng.randf_range(-0.22, 0.22)
		var mid := c + Vector2(cos(ang + 0.16), sin(ang + 0.16)) * _rng.randf_range(36.0, 58.0)
		var tip := c + Vector2(cos(ang - 0.10), sin(ang - 0.10)) * _rng.randf_range(76.0, 112.0)
		_fail_cracks.append({
			"pts": PackedVector2Array([c + Vector2(cos(ang), sin(ang)) * 14.0, mid, tip]),
			"ttl": 0.36,
			"max_ttl": 0.36,
		})
	# 22 枚带重力下坠的绯灰碎晶
	for i in 22:
		var ang := _rng.randf_range(0.0, TAU)
		var spd := _rng.randf_range(90.0, 260.0)
		_particles.append({
			"pos": c + Vector2(cos(ang), sin(ang)) * _rng.randf_range(12.0, 42.0),
			"vel": Vector2(cos(ang) * spd, sin(ang) * spd - 65.0),
			"col": COL_FAIL if i % 2 == 0 else Color("a89fb5"),
			"size": _rng.randf_range(3.8, 6.8),
			"ttl": _rng.randf_range(0.34, 0.56),
			"max_ttl": 0.56,
			"gravity": 680.0,
			"shape": "shard",
		})


# ---------------------------------------------------------------- 8 套技能实战执行

func _cast_skill(sk: Dictionary) -> void:
	if player == null or not is_instance_valid(player):
		return
	var sid := String(sk["id"])
	var ridx := int(sk["rank"])
	var fdir := int(player.facing) if int(player.facing) != 0 else 1
	var origin := player.global_position + Vector2(0.0, -38.0)
	var dmg_mul := _get_skill_dmg_mul()

	cast_count += 1
	last_cast_id = sid
	_banner_text = "【%s】" % String(sk["name"])
	_banner_sub = "%s 阶技 · %s" % [RANK_LETTERS[ridx], String(sk["desc"])]
	_banner_col = sk.get("accent", COL_VIOLET_LIGHT)
	_banner_timer = 1.45

	# 瞬息演武等 Buff 回评与绝影充能
	var rig := _get_perk_rig()
	if rig != null:
		var bonus_style := float(rig.get("skill_cast_style_bonus"))
		if bonus_style > 0.0 and stage != null and stage.get("style") != null:
			if stage.style.has_method(&"add_raw_points"):
				stage.style.call(&"add_raw_points", bonus_style)
			else:
				stage.style.add_event(&"chain", 1.0)
		var bonus_ult := float(rig.get("skill_cast_ult_bonus"))
		if bonus_ult > 0.0 and player.has_method(&"add_ult_energy"):
			var ult_mul := float(rig.get("ult_gain_mul")) if rig.get("ult_gain_mul") != null else 1.0
			player.call(&"add_ult_energy", bonus_ult * ult_mul)

	player.invuln_frames = maxi(int(player.invuln_frames), 14 + ridx * 4)
	if stage != null and stage.get("style") != null:
		stage.style.add_hit(StringName("skill_" + sid))

	match sid:
		"crow_flash":
			_exec_crow_flash(origin, fdir, dmg_mul)
		"chrono_pulse":
			_exec_chrono_pulse(origin, dmg_mul)
		"rift_moon":
			_exec_rift_moon(origin, fdir, dmg_mul)
		"tide_breaker":
			_exec_tide_breaker(origin, fdir, dmg_mul)
		"star_cleave":
			_exec_star_cleave(origin, fdir, dmg_mul)
		"feather_hunt":
			_exec_feather_hunt(origin, fdir, dmg_mul)
		"chrono_domain":
			_exec_chrono_domain(origin, fdir, dmg_mul)
		"dawn_judgment":
			s_skill_cooldown = S_SKILL_COOLDOWN * _get_cd_mul()
			_exec_dawn_judgment(origin, fdir, dmg_mul)

	_shake_camera(7.0 + float(ridx) * 4.5)
	GamepadManager.rumble(0.32 + 0.11 * ridx, 0.24 + 0.15 * ridx, 0.14 + 0.04 * ridx)
	skill_cast.emit(sid, ridx)


func _exec_crow_flash(origin: Vector2, fdir: int, dmg_mul: float) -> void:
	var start_pos := player.global_position
	var dash_dist := 240.0
	var bounds := _arena_bounds()
	var target_x := clampf(start_pos.x + float(fdir) * dash_dist, bounds.x + 40.0, bounds.y - 40.0)
	player.global_position.x = target_x
	var end_center := player.global_position + Vector2(0.0, -38.0)
	_spawn_line(origin, end_center, COL_CYAN, 0.24, 9.0)
	_spawn_line(origin + Vector2(0, -8), end_center + Vector2(0, -8), COL_SILVER, 0.20, 3.0)
	_spawn_flash(end_center, 72.0, COL_CYAN, 0.20)
	var min_x := minf(start_pos.x, target_x) - 80.0
	var max_x := maxf(start_pos.x, target_x) + 80.0
	for t in _collect_targets():
		if t.global_position.x >= min_x and t.global_position.x <= max_x and absf(t.global_position.y - player.global_position.y) <= 160.0:
			_hit_target(t, _mv_light, fdir, t.global_position + Vector2(0, -36), dmg_mul)
			_damage_shell(t, 16.0 * dmg_mul, t.global_position)
	if player.get("shadow_charges") != null and player.get("max_shadow_charges") != null:
		player.shadow_charges = mini(int(player.max_shadow_charges), int(player.shadow_charges) + 1)


func _exec_chrono_pulse(origin: Vector2, dmg_mul: float) -> void:
	_spawn_ring(origin, 300.0, COL_SILVER, 0.30, false)
	_spawn_ring(origin, 220.0, COL_VIOLET_LIGHT, 0.26, false)
	_clear_projectiles(origin, 340.0)
	for t in _collect_targets():
		if t.global_position.distance_to(origin) <= 300.0:
			var push_dir := 1 if t.global_position.x >= origin.x else -1
			_hit_target(t, _mv_light, push_dir, origin, 0.9 * dmg_mul)
			_damage_shell(t, 20.0 * dmg_mul, origin)


func _exec_rift_moon(origin: Vector2, fdir: int, dmg_mul: float) -> void:
	var slash_pt := origin + Vector2(float(fdir) * 110.0, -48.0)
	_spawn_line(origin + Vector2(0, 32), slash_pt + Vector2(float(fdir) * 60.0, -140.0), COL_VIOLET, 0.28, 12.0)
	_spawn_line(origin + Vector2(0, 24), slash_pt + Vector2(float(fdir) * 60.0, -140.0), COL_SILVER, 0.24, 4.0)
	_spawn_flash(slash_pt, 105.0, COL_VIOLET_LIGHT, 0.24)
	_spawn_spatial_rift(slash_pt + Vector2(float(fdir) * 35.0, -35.0), Vector2(float(fdir) * 0.65, -0.76), 24.0 * dmg_mul)
	for t in _collect_targets():
		if absf(t.global_position.x - slash_pt.x) <= 210.0 and absf(t.global_position.y - origin.y) <= 190.0:
			_hit_target(t, _mv_launch, fdir, slash_pt, 1.05 * dmg_mul)
			_damage_shell(t, 26.0 * dmg_mul, slash_pt)
			if stage != null and stage.get("style") != null:
				stage.style.add_event(&"launch", 0.7)


func _exec_tide_breaker(origin: Vector2, fdir: int, dmg_mul: float) -> void:
	_waves.append({
		"pos": origin + Vector2(float(fdir) * 52.0, 0.0),
		"dir": fdir,
		"speed": 1380.0,
		"ttl": 0.56,
		"max_ttl": 0.56,
		"dmg_mul": 1.15 * dmg_mul,
		"hit_ids": {},
	})
	_spawn_flash(origin + Vector2(float(fdir) * 48.0, 0.0), 86.0, COL_VIOLET, 0.20)


func _exec_star_cleave(origin: Vector2, fdir: int, dmg_mul: float) -> void:
	var impact := origin + Vector2(float(fdir) * 160.0, 30.0)
	_spawn_line(impact + Vector2(float(-fdir) * 80.0, -280.0), impact, COL_VIOLET, 0.30, 16.0)
	_spawn_line(impact + Vector2(float(-fdir) * 80.0, -280.0), impact, COL_SILVER, 0.25, 5.0)
	_spawn_ring(impact, 360.0, COL_VIOLET_LIGHT, 0.34, true)
	_clear_projectiles(impact, 360.0)
	for t in _collect_targets():
		if t.global_position.distance_to(impact) <= 340.0:
			_hit_target(t, _mv_heavy, fdir, impact, 1.25 * dmg_mul)
			_damage_shell(t, 45.0 * dmg_mul, impact)
			if stage != null and stage.get("style") != null:
				stage.style.add_event(&"slam", 0.8)


func _exec_feather_hunt(origin: Vector2, fdir: int, dmg_mul: float) -> void:
	_spawn_flash(origin, 88.0, COL_VIOLET_LIGHT, 0.22)
	for i in 6:
		var ang := -1.15 + float(i) * (2.30 / 5.0)
		var init_dir := Vector2(cos(ang) * float(fdir), sin(ang) - 0.35).normalized()
		_feathers.append({
			"pos": origin + init_dir * 34.0,
			"vel": init_dir * 1120.0,
			"ttl": 1.15,
			"dmg_mul": 1.05 * dmg_mul,
		})


func _exec_chrono_domain(origin: Vector2, fdir: int, dmg_mul: float) -> void:
	_spawn_ring(origin, 540.0, COL_SILVER, 0.45, true)
	_spawn_ring(origin, 480.0, COL_VIOLET, 0.42, false)
	_clear_projectiles(origin, 580.0)
	for t in _collect_targets():
		if t.global_position.distance_to(origin) <= 560.0:
			if t.get("hitstop_frames") != null:
				t.set("hitstop_frames", maxi(int(t.get("hitstop_frames")), 42))
	for step in 4:
		_delayed_slashes.append({
			"delay": float(step) * 0.09,
			"center": origin,
			"radius": 560.0,
			"fdir": fdir if step % 2 == 0 else -fdir,
			"dmg_mul": (0.85 + 0.15 * float(step)) * dmg_mul,
			"angle": -0.75 + float(step) * 0.52,
		})
	if stage != null and stage.get("style") != null:
		stage.style.add_event(&"parry", 0.9)


func _exec_dawn_judgment(origin: Vector2, fdir: int, dmg_mul: float) -> void:
	var bounds := _arena_bounds()
	var span := maxf(640.0, bounds.y - bounds.x - 160.0)
	var gy := float(stage.get("floor_y")) if stage != null and stage.get("floor_y") != null else (player.global_position.y + 44.0)
	var blade_n := 8
	for i in blade_n:
		var ratio := float(i) / float(blade_n - 1)
		var bx := bounds.x + 80.0 + span * ratio
		_sky_blades.append({
			"x": bx,
			"ground_y": gy,
			"delay": float(i) * 0.055,
			"ttl": 0.44,
			"max_ttl": 0.44,
			"struck": false,
			"dmg_mul": 1.35 * dmg_mul,
		})
	_spawn_spatial_rift(origin + Vector2(float(fdir) * 180.0, -70.0), Vector2(0.75, -0.66), 32.0 * dmg_mul)
	_spawn_spatial_rift(origin + Vector2(float(fdir) * 180.0, -70.0), Vector2(-0.75, -0.66), 32.0 * dmg_mul)
	_spawn_ring(origin, 720.0, COL_GOLD, 0.50, true)
	_clear_projectiles(origin, 900.0)
	if stage != null and stage.get("style") != null:
		stage.style.add_event(&"ult", 0.8)


# ---------------------------------------------------------------- 帧推进（墙钟推时缓/冷却/按键粒子 + 物理帧推技能实体）

func _process(_delta: float) -> void:
	var now_us := Time.get_ticks_usec()
	var real_dt := clampf(float(now_us - _last_us) / 1000000.0, 0.0, 0.08)
	_last_us = now_us
	_vfx_time += real_dt

	if stance_cooldown > 0.0:
		stance_cooldown = maxf(0.0, stance_cooldown - real_dt)
	if s_skill_cooldown > 0.0:
		s_skill_cooldown = maxf(0.0, s_skill_cooldown - real_dt)
	if _wrong_flash > 0.0:
		_wrong_flash = maxf(0.0, _wrong_flash - real_dt)
	if _success_flash > 0.0:
		_success_flash = maxf(0.0, _success_flash - real_dt)
	if _fail_toast_timer > 0.0:
		_fail_toast_timer = maxf(0.0, _fail_toast_timer - real_dt)
	if _banner_timer > 0.0:
		_banner_timer = maxf(0.0, _banner_timer - real_dt)

	if _require_release_before_reenter and not Input.is_action_pressed(&"skill_stance"):
		_require_release_before_reenter = false

	if stance_active:
		if _is_blocked_context():
			exit_stance(0.0)
		elif _entered_via_input and not Input.is_action_pressed(&"skill_stance"):
			if not input_seq.is_empty():
				_trigger_fail_feedback("指令中断")
			else:
				_play_sfx_cue("cancel")
			exit_stance(CANCEL_COOLDOWN)
		else:
			_stance_rem -= real_dt
			if _stance_rem <= 0.0:
				if not input_seq.is_empty():
					_trigger_fail_feedback("时缓耗尽")
				else:
					_play_sfx_cue("cancel")
				_require_release_before_reenter = Input.is_action_pressed(&"skill_stance")
				exit_stance(CANCEL_COOLDOWN)
			else:
				if Engine.time_scale > SLOWMO_SCALE + 0.02:
					Engine.time_scale = SLOWMO_SCALE
				# 时缓维持期间人物周身悬浮银紫时砂粒子
				_ambient_mote_accum += real_dt
				if _ambient_mote_accum >= 0.055 and player != null and is_instance_valid(player):
					_ambient_mote_accum = 0.0
					var c := _player_center()
					var ang := _rng.randf_range(0.0, TAU)
					var rad := _rng.randf_range(28.0, 62.0)
					_particles.append({
						"pos": c + Vector2(cos(ang) * rad, sin(ang) * rad),
						"vel": Vector2(-sin(ang) * 34.0, cos(ang) * 34.0 - 24.0),
						"col": COL_VIOLET_LIGHT if _rng.randf() < 0.65 else COL_SILVER,
						"size": _rng.randf_range(2.2, 4.0),
						"ttl": 0.36,
						"max_ttl": 0.36,
						"gravity": 0.0,
						"shape": "diamond",
					})

	_tick_realtime_vfx(real_dt)
	if stance_active or not _particles.is_empty() or not _dir_glyphs.is_empty() or not _success_seals.is_empty() or not _fail_cracks.is_empty():
		queue_redraw()
	if _ui_canvas != null:
		_ui_canvas.queue_redraw()


func _tick_realtime_vfx(dt: float) -> void:
	var pi := _particles.size() - 1
	while pi >= 0:
		var pt: Dictionary = _particles[pi]
		var vel: Vector2 = pt["vel"]
		vel.y += float(pt["gravity"]) * dt
		vel *= maxf(0.0, 1.0 - 2.6 * dt)
		pt["vel"] = vel
		pt["pos"] = (pt["pos"] as Vector2) + vel * dt
		pt["ttl"] = float(pt["ttl"]) - dt
		if float(pt["ttl"]) <= 0.0:
			_particles.remove_at(pi)
		pi -= 1

	var gi := _dir_glyphs.size() - 1
	while gi >= 0:
		var dg: Dictionary = _dir_glyphs[gi]
		dg["pos"] = (dg["pos"] as Vector2) + (dg["vel"] as Vector2) * dt
		dg["vel"] = (dg["vel"] as Vector2) * maxf(0.0, 1.0 - 5.0 * dt)
		dg["ttl"] = float(dg["ttl"]) - dt
		if float(dg["ttl"]) <= 0.0:
			_dir_glyphs.remove_at(gi)
		gi -= 1

	var si := _success_seals.size() - 1
	while si >= 0:
		_success_seals[si]["ttl"] = float(_success_seals[si]["ttl"]) - dt
		_success_seals[si]["rot"] = float(_success_seals[si]["rot"]) + dt * 2.2
		if float(_success_seals[si]["ttl"]) <= 0.0:
			_success_seals.remove_at(si)
		si -= 1

	var ci := _fail_cracks.size() - 1
	while ci >= 0:
		_fail_cracks[ci]["ttl"] = float(_fail_cracks[ci]["ttl"]) - dt
		if float(_fail_cracks[ci]["ttl"]) <= 0.0:
			_fail_cracks.remove_at(ci)
		ci -= 1


func _physics_process(delta: float) -> void:
	if get_tree().paused:
		return
	_tick_waves(delta)
	_tick_feathers(delta)
	_tick_sky_blades(delta)
	_tick_delayed_slashes(delta)
	_tick_vfx(delta)
	queue_redraw()


func _tick_waves(delta: float) -> void:
	var i := _waves.size() - 1
	while i >= 0:
		var w: Dictionary = _waves[i]
		var pos: Vector2 = w["pos"] + Vector2(float(w["dir"]) * float(w["speed"]) * delta, 0.0)
		w["pos"] = pos
		w["ttl"] = float(w["ttl"]) - delta
		var hits: Dictionary = w["hit_ids"]
		_clear_projectiles(pos, 120.0)
		for t in _collect_targets():
			var tid := t.get_instance_id()
			if hits.has(tid):
				continue
			if absf(t.global_position.x - pos.x) <= 110.0 and absf(t.global_position.y - pos.y) <= 150.0:
				hits[tid] = true
				_hit_target(t, _mv_wave, int(w["dir"]), pos, float(w["dmg_mul"]))
				_damage_shell(t, 36.0 * float(w["dmg_mul"]), pos)
				_spawn_flash(pos, 72.0, COL_VIOLET_LIGHT, 0.18)
		if float(w["ttl"]) <= 0.0:
			_waves.remove_at(i)
		i -= 1


func _tick_feathers(delta: float) -> void:
	var i := _feathers.size() - 1
	while i >= 0:
		var fb: Dictionary = _feathers[i]
		var pos: Vector2 = fb["pos"]
		var vel: Vector2 = fb["vel"]
		var target := _nearest_target(pos)
		if target != null:
			var want := (target.global_position + Vector2(0.0, -36.0) - pos).normalized() * 1240.0
			vel = vel.lerp(want, minf(1.0, delta * 15.0))
		pos += vel * delta
		fb["pos"] = pos
		fb["vel"] = vel
		fb["ttl"] = float(fb["ttl"]) - delta
		var hit := false
		for t in _collect_targets():
			if t.global_position.distance_to(pos) <= 78.0:
				var fdir := 1 if vel.x >= 0.0 else -1
				_hit_target(t, _mv_feather, fdir, pos, float(fb["dmg_mul"]))
				_damage_shell(t, 12.0 * float(fb["dmg_mul"]), pos)
				_spawn_flash(pos, 38.0, COL_VIOLET_LIGHT, 0.14)
				hit = true
				break
		if hit or float(fb["ttl"]) <= 0.0:
			_feathers.remove_at(i)
		i -= 1


func _tick_sky_blades(delta: float) -> void:
	var i := _sky_blades.size() - 1
	while i >= 0:
		var b: Dictionary = _sky_blades[i]
		if float(b["delay"]) > 0.0:
			b["delay"] = float(b["delay"]) - delta
			i -= 1
			continue
		if not bool(b["struck"]):
			b["struck"] = true
			var bx := float(b["x"])
			var gy := float(b["ground_y"])
			var impact := Vector2(bx, gy - 40.0)
			_clear_projectiles(impact, 180.0)
			_spawn_flash(impact, 110.0, COL_GOLD, 0.24)
			for t in _collect_targets():
				if absf(t.global_position.x - bx) <= 155.0:
					var fdir := 1 if (player == null or t.global_position.x >= player.global_position.x) else -1
					_hit_target(t, _mv_finale, fdir, impact, float(b["dmg_mul"]))
					_damage_shell(t, 38.0 * float(b["dmg_mul"]), impact)
		b["ttl"] = float(b["ttl"]) - delta
		if float(b["ttl"]) <= 0.0:
			_sky_blades.remove_at(i)
		i -= 1


func _tick_delayed_slashes(delta: float) -> void:
	var i := _delayed_slashes.size() - 1
	while i >= 0:
		var ds: Dictionary = _delayed_slashes[i]
		ds["delay"] = float(ds["delay"]) - delta
		if float(ds["delay"]) <= 0.0:
			var center: Vector2 = ds["center"]
			var rad: float = float(ds["radius"])
			var ang: float = float(ds["angle"])
			var fdir: int = int(ds["fdir"])
			var dmul: float = float(ds["dmg_mul"])
			var hit_any := false
			for t in _collect_targets():
				if t.global_position.distance_to(center) <= rad:
					hit_any = true
					var tp := t.global_position + Vector2(0.0, -36.0)
					var dir_v := Vector2(cos(ang), sin(ang)) * 165.0
					_spawn_line(tp - dir_v, tp + dir_v, COL_VIOLET, 0.22, 8.0)
					_spawn_line(tp - dir_v * 0.9, tp + dir_v * 0.9, COL_SILVER, 0.20, 3.0)
					_hit_target(t, _mv_wave, fdir, tp, dmul)
					_damage_shell(t, 20.0 * dmul, tp)
			if not hit_any:
				var dv := Vector2(cos(ang), sin(ang)) * 240.0
				_spawn_line(center - dv, center + dv, COL_VIOLET_LIGHT, 0.22, 6.0)
				_spawn_line(center - dv * 0.85, center + dv * 0.85, COL_SILVER, 0.20, 2.5)
			_play_pool("slash_fast", -5.0, 1.08)
			_delayed_slashes.remove_at(i)
		i -= 1


func _tick_vfx(delta: float) -> void:
	for arr in [_rings, _lines, _flashes]:
		var i: int = arr.size() - 1
		while i >= 0:
			arr[i]["ttl"] = float(arr[i]["ttl"]) - delta
			if float(arr[i]["ttl"]) <= 0.0:
				arr.remove_at(i)
			i -= 1


# ---------------------------------------------------------------- 战斗辅助与沉浸音效调度

func _collect_targets() -> Array[Node2D]:
	var out: Array[Node2D] = []
	if not is_inside_tree():
		return out
	for n in get_tree().get_nodes_in_group(&"shade"):
		var s := n as Node2D
		if s != null and is_instance_valid(s) and int(s.get("state")) != Shade.State.DEAD:
			out.append(s)
	if stage != null:
		var dum: Variant = stage.get("dummy")
		if dum is Node2D and is_instance_valid(dum) and not out.has(dum):
			out.append(dum as Node2D)
	return out


func _nearest_target(origin: Vector2) -> Node2D:
	var best: Node2D = null
	var best_d := INF
	for t in _collect_targets():
		var d := t.global_position.distance_squared_to(origin)
		if d < best_d:
			best_d = d
			best = t
	return best


func _hit_target(target: Node2D, mv: MoveDefinition, fdir: int, point: Vector2, mul: float) -> void:
	if target == null or not is_instance_valid(target) or not target.has_method(&"take_hit"):
		return
	target.call(&"take_hit", mv, fdir if fdir != 0 else 1, point, 0.0, false, mul, player)
	var rig := _get_perk_rig()
	if rig != null and rig.has_method(&"on_combo_skill_hit"):
		rig.call(&"on_combo_skill_hit", float(mv.damage) * mul, point)


func _damage_shell(target: Node2D, amount: float, point: Vector2) -> void:
	if target == null or not is_instance_valid(target) or amount <= 0.0:
		return
	var rig := _get_perk_rig()
	if rig != null and rig.get("shell_shred_bonus") != null:
		amount *= (1.0 + float(rig.get("shell_shred_bonus")))
	var fdir := int(player.facing) if player != null and int(player.facing) != 0 else 1
	if target.has_method(&"damage_shell"):
		target.call(&"damage_shell", amount, point, fdir, false)
		return
	if target.get("shell_hp") != null and float(target.get("shell_hp")) > 0.0:
		var next_sh := maxf(0.0, float(target.get("shell_hp")) - amount)
		target.set("shell_hp", next_sh)
		if next_sh <= 0.0 and target.has_method(&"_break_shell"):
			target.call(&"_break_shell")


func _clear_projectiles(center: Vector2, radius: float) -> void:
	if not is_inside_tree():
		return
	var r2 := radius * radius
	for b in get_tree().get_nodes_in_group(&"shade_projectile"):
		if b is Node2D and is_instance_valid(b):
			if (b as Node2D).global_position.distance_squared_to(center) <= r2:
				b.queue_free()


func _spawn_spatial_rift(world_pos: Vector2, axis_dir: Vector2, dmg: float) -> void:
	if stage == null or not is_inside_tree():
		return
	var existing := get_tree().get_nodes_in_group(&"spatial_rift")
	while existing.size() >= 4:
		var oldest := existing.pop_front() as Node2D
		if oldest != null and is_instance_valid(oldest) and oldest.has_method(&"dismiss"):
			oldest.call(&"dismiss")
	var rift: Node2D = SpatialRiftScript.new()
	stage.add_child(rift)
	rift.call(&"setup", world_pos, axis_dir, 130.0, player, dmg, &"combo_skill_rift")


func _arena_bounds() -> Vector2:
	if stage != null:
		var seal: Variant = stage.get("seal_x")
		if seal is Vector2 and (seal as Vector2).y > (seal as Vector2).x + 50.0:
			return seal as Vector2
		if stage.get("arena_center") != null and stage.get("arena_half") != null:
			var c := float(stage.get("arena_center"))
			var h := float(stage.get("arena_half"))
			if h > 50.0:
				return Vector2(c - h, c + h)
	var px := player.global_position.x if player != null and is_instance_valid(player) else 640.0
	return Vector2(px - 760.0, px + 760.0)


func _shake_camera(amount: float) -> void:
	if stage != null and stage.get("camera") != null and stage.camera.has_method(&"add_shake"):
		stage.camera.call(&"add_shake", amount, Vector2.RIGHT)


func _play_sfx_cue(kind: String, param: int = 0) -> void:
	last_sfx_event = kind
	match kind:
		"enter":
			_play_pool("sheathe", -5.5, 0.85)
			_play_pool("anvil_bell", -16.0, 1.32)
		"cancel":
			_play_pool("ui_back", -9.0, 1.05)
		"tick":
			var p := 1.00 + 0.17 * float(maxi(param - 1, 0))
			_play_pool("parry_lock", -6.0, p)
			_play_pool("ui_move", -10.0, p + 0.06)
		"fail":
			_play_pool("ui_back", -3.0, 0.58)
			_play_pool("parry_lock", -5.0, 0.46)
			if stage != null and stage.get("audio") != null and stage.audio.has_method(&"play_block"):
				stage.audio.call(&"play_block")
		"success":
			if param >= 4:
				_play_pool("anvil_bell", -2.5, 0.94)
				_play_pool("cut_2", -2.5, 1.02)
				_play_pool("impact", -3.0, 0.98)
			elif param >= 2:
				_play_pool("unsheathe", -3.5, 1.05)
				_play_pool("slash_heavy", -3.0, 1.02)
				_play_pool("cut_0", -6.0, 1.08)
			else:
				_play_pool("unsheathe", -4.5, 1.12)
				_play_pool("slash_fast", -3.5, 1.06)


func _spawn_ring(pos: Vector2, max_r: float, col: Color, ttl: float, grand: bool) -> void:
	_rings.append({"pos": pos, "max_r": max_r, "col": col, "ttl": ttl, "max_ttl": ttl, "grand": grand})


func _spawn_line(a: Vector2, b: Vector2, col: Color, ttl: float, w: float) -> void:
	_lines.append({"a": a, "b": b, "col": col, "ttl": ttl, "max_ttl": ttl, "w": w})


func _spawn_flash(pos: Vector2, r: float, col: Color, ttl: float) -> void:
	_flashes.append({"pos": pos, "r": r, "col": col, "ttl": ttl, "max_ttl": ttl})


# ---------------------------------------------------------------- 世界空间几何特效与人物边实时粒子渲染

func _draw() -> void:
	# 0. 时缓维持期间人物周身 5:59 银紫召唤阵环
	if stance_active and player != null and is_instance_valid(player):
		var pc := to_local(_player_center())
		var rem_ratio := clampf(_stance_rem / maxf(_stance_max, 0.1), 0.0, 1.0)
		var ring_col := COL_FAIL if _wrong_flash > 0.0 else COL_VIOLET_LIGHT
		draw_arc(pc, 64.0, 0.0, TAU, 40, Color(ring_col, 0.34), 2.0, true)
		draw_arc(pc, 54.0, -PI * 0.5, -PI * 0.5 + TAU * rem_ratio, 36, Color(COL_SILVER, 0.85), 2.6, true)
		for ti in 12:
			var ang := _vfx_time * 0.8 + float(ti) * (TAU / 12.0)
			var p0 := pc + Vector2(cos(ang), sin(ang)) * 58.0
			var p1 := pc + Vector2(cos(ang), sin(ang)) * 66.0
			draw_line(p0, p1, Color(COL_SILVER, 0.48 if ti % 3 == 0 else 0.22), 1.6 if ti % 3 == 0 else 1.0, true)

	# 1. 搓招成功：人物双层 5:59 圣印扩散环
	for seal in _success_seals:
		var u := 1.0 - clampf(float(seal["ttl"]) / maxf(0.05, float(seal["max_ttl"])), 0.0, 1.0)
		var a := 1.0 - u
		var sp := to_local(seal["pos"])
		var r := lerpf(26.0, float(seal["max_r"]), 1.0 - pow(1.0 - u, 3.0))
		var col: Color = seal["col"]
		var rot := float(seal["rot"])
		draw_arc(sp, r, 0.0, TAU, 48, Color(col.r, col.g, col.b, 0.92 * a), 5.5 * a + 1.5, true)
		draw_arc(sp, r * 0.78, 0.0, TAU, 36, Color(COL_SILVER, 0.82 * a), 2.2 * a + 0.8, true)
		for ti in 12:
			var ang := rot + float(ti) * (TAU / 12.0)
			draw_line(sp + Vector2(cos(ang), sin(ang)) * (r * 0.78), sp + Vector2(cos(ang), sin(ang)) * r, Color(COL_GOLD, 0.78 * a), 2.0, true)

	# 2. 搓招失败：人物周身钟盘碎裂折线
	for cr in _fail_cracks:
		var a := clampf(float(cr["ttl"]) / maxf(0.04, float(cr["max_ttl"])), 0.0, 1.0)
		var raw_pts: PackedVector2Array = cr["pts"]
		var loc_pts := PackedVector2Array()
		for pt in raw_pts:
			loc_pts.append(to_local(pt))
		draw_polyline(loc_pts, Color(COL_FAIL, 0.95 * a), 3.6 * a + 0.8, true)
		draw_polyline(loc_pts, Color(COL_SILVER, 0.85 * a), 1.4 * a, true)

	# 3. 实时墙钟粒子（方向按键粒子束 / 悬空时砂 / 成功刃芒 / 失败碎晶）
	for pt in _particles:
		var a := clampf(float(pt["ttl"]) / maxf(0.04, float(pt["max_ttl"])), 0.0, 1.0)
		var lp := to_local(pt["pos"])
		var col: Color = pt["col"]
		var sz: float = float(pt["size"]) * (0.45 + 0.55 * a)
		var draw_c := Color(col.r, col.g, col.b, a * 0.95)
		if String(pt["shape"]) == "shard":
			var vel_n := (pt["vel"] as Vector2).normalized()
			if vel_n.length_squared() < 0.01:
				vel_n = Vector2.UP
			var orth := vel_n.orthogonal()
			var poly := PackedVector2Array([
				lp + vel_n * (sz * 2.1),
				lp + orth * (sz * 0.55),
				lp - vel_n * (sz * 1.1),
				lp - orth * (sz * 0.55),
			])
			draw_colored_polygon(poly, draw_c)
		else:
			var poly2 := PackedVector2Array([
				lp + Vector2(0.0, -sz * 1.3),
				lp + Vector2(sz, 0.0),
				lp + Vector2(0.0, sz * 1.3),
				lp + Vector2(-sz, 0.0),
			])
			draw_colored_polygon(poly2, draw_c)

	# 4. 人物身侧按键方向符纹（↑ ↓ ← →）
	for dg in _dir_glyphs:
		var a := clampf(float(dg["ttl"]) / maxf(0.04, float(dg["max_ttl"])), 0.0, 1.0)
		var lp := to_local(dg["pos"])
		var r_cur := lerpf(10.0, 26.0, 1.0 - a)
		var rc: Color = dg["ring_col"]
		var gc: Color = dg["col"]
		draw_arc(lp, r_cur, 0.0, TAU, 20, Color(rc.r, rc.g, rc.b, 0.72 * a), 2.0, true)
		if _font_cinzel != null:
			draw_string(_font_cinzel, lp + Vector2(-11.0, 8.0), String(dg["glyph"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(gc.r, gc.g, gc.b, a))

	# 5. 技能战斗实体（剑波 / 追踪飞刃 / 天穹巨刃 / 震波环 / 斩线 / 闪光）
	for w in _waves:
		var wp := to_local(w["pos"])
		var dir := float(w["dir"])
		var u := clampf(float(w["ttl"]) / maxf(0.05, float(w["max_ttl"])), 0.0, 1.0)
		var a0 := -1.15 if dir > 0.0 else PI - 1.15
		var a1 := 1.15 if dir > 0.0 else PI + 1.15
		var c := wp - Vector2(dir * 52.0, 0.0)
		draw_arc(c, 134.0, a0, a1, 26, Color(0.05, 0.03, 0.10, 0.85 * u), 24.0)
		draw_arc(c, 134.0, a0, a1, 26, Color(COL_VIOLET, 0.94 * u), 14.0)
		draw_arc(c, 134.0, a0 * 0.9, a1 * 0.9, 22, Color(COL_SILVER, 0.98 * u), 4.5)

	for fb in _feathers:
		var fp := to_local(fb["pos"])
		var fv := (fb["vel"] as Vector2).normalized()
		draw_line(fp - fv * 26.0, fp + fv * 18.0, Color(COL_VIOLET, 0.95), 5.5)
		draw_line(fp - fv * 14.0, fp + fv * 18.0, Color(COL_SILVER, 0.98), 2.2)

	for b in _sky_blades:
		if float(b["delay"]) > 0.0:
			continue
		var u := clampf(float(b["ttl"]) / maxf(0.05, float(b["max_ttl"])), 0.0, 1.0)
		var gp := to_local(Vector2(float(b["x"]), float(b["ground_y"])))
		var top := gp + Vector2(0.0, -640.0)
		var hw := 30.0 * u
		var poly := PackedVector2Array([top, gp + Vector2(hw, -46.0), gp, gp + Vector2(-hw, -46.0)])
		draw_colored_polygon(poly, Color(COL_GOLD if u > 0.55 else COL_VIOLET, 0.82 * u))
		draw_line(top, gp, Color(COL_SILVER, 0.98 * u), 6.0 * u)

	for ring in _rings:
		var u := 1.0 - clampf(float(ring["ttl"]) / maxf(0.04, float(ring["max_ttl"])), 0.0, 1.0)
		var alpha := 1.0 - u
		var cur_r := lerpf(30.0, float(ring["max_r"]), 1.0 - pow(1.0 - u, 3.0))
		var col: Color = ring["col"]
		var is_grand := bool(ring["grand"])
		draw_arc(to_local(ring["pos"]), cur_r, 0.0, TAU, 44, Color(col.r, col.g, col.b, alpha * 0.9), (11.0 if is_grand else 6.0) * alpha + 1.5)

	for ln in _lines:
		var u := clampf(float(ln["ttl"]) / maxf(0.04, float(ln["max_ttl"])), 0.0, 1.0)
		var col: Color = ln["col"]
		draw_line(to_local(ln["a"]), to_local(ln["b"]), Color(col.r, col.g, col.b, u * 0.95), float(ln["w"]) * u + 0.8)

	for fl in _flashes:
		var u := clampf(float(fl["ttl"]) / maxf(0.04, float(fl["max_ttl"])), 0.0, 1.0)
		var col: Color = fl["col"]
		var r_cur := float(fl["r"]) * (1.0 - 0.5 * u)
		draw_arc(to_local(fl["pos"]), r_cur, 0.0, TAU, 28, Color(col.r, col.g, col.b, u * 0.88), 5.0 * u + 1.2)


# ---------------------------------------------------------------- 屏幕 HUD：时缓 5:59 结界、成败全屏瞬闪与搓招操作提示面板

func _ensure_ui() -> void:
	if _ui_layer != null:
		return
	_ui_layer = CanvasLayer.new()
	_ui_layer.name = "ComboSkillPromptLayer"
	_ui_layer.layer = 24
	_ui_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_ui_layer)

	_ui_canvas = Control.new()
	_ui_canvas.name = "ComboSkillPromptCanvas"
	_ui_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_canvas.draw.connect(_draw_ui)
	_ui_layer.add_child(_ui_canvas)


func is_prompt_panel_visible() -> bool:
	return stance_active and GamepadManager.is_skill_hints_enabled()


func _draw_ui() -> void:
	if _ui_canvas == null or _font_serif == null:
		return
	var vp := _ui_canvas.get_viewport_rect().size
	var cx := vp.x * 0.5

	# 0. 成功释放的屏边辉光瞬闪 & 失败碎裂的屏边绯红震闪
	if _success_flash > 0.0:
		var sa := clampf(_success_flash / 0.30, 0.0, 1.0)
		_ui_canvas.draw_rect(Rect2(Vector2.ZERO, vp), Color(_success_flash_col, 0.14 * sa))
		_ui_canvas.draw_rect(Rect2(4.0, 4.0, vp.x - 8.0, vp.y - 8.0), Color(COL_SILVER, 0.72 * sa), false, 4.0 * sa + 1.0)
	if _wrong_flash > 0.0 and not stance_active:
		var fa := clampf(_wrong_flash / 0.42, 0.0, 1.0)
		_ui_canvas.draw_rect(Rect2(Vector2.ZERO, vp), Color(COL_FAIL_DARK, 0.18 * fa))
		_ui_canvas.draw_rect(Rect2(5.0, 5.0, vp.x - 10.0, vp.y - 10.0), Color(COL_FAIL, 0.68 * fa), false, 3.0)

	# 1. 施放技能成功后的哥特横幅
	if _banner_timer > 0.0 and _banner_text != "":
		var a := clampf(_banner_timer / 0.35, 0.0, 1.0)
		var by := 124.0
		var bw := 380.0
		var bar := PackedVector2Array([
			Vector2(cx - bw * 0.5 + 14.0, by - 30.0),
			Vector2(cx + bw * 0.5 + 14.0, by - 30.0),
			Vector2(cx + bw * 0.5 - 14.0, by + 26.0),
			Vector2(cx - bw * 0.5 - 14.0, by + 26.0),
		])
		_ui_canvas.draw_colored_polygon(bar, Color(0.03, 0.025, 0.055, 0.86 * a))
		_ui_canvas.draw_line(bar[0], bar[1], Color(_banner_col, 0.90 * a), 2.0, true)
		_ui_canvas.draw_line(bar[2], bar[3], Color(_banner_col, 0.50 * a), 1.2, true)
		_ui_canvas.draw_string(_font_bold, Vector2(cx - 190.0, by - 2.0), _banner_text, HORIZONTAL_ALIGNMENT_CENTER, 380.0, 22, Color(_banner_col, a))
		_ui_canvas.draw_string(_font_serif, Vector2(cx - 190.0, by + 18.0), _banner_sub, HORIZONTAL_ALIGNMENT_CENTER, 380.0, 13, Color(COL_SILVER, 0.88 * a))

	# 1.5 搓招失败轻浮标
	if _fail_toast_timer > 0.0 and _fail_toast != "":
		var fa2 := clampf(_fail_toast_timer / 0.30, 0.0, 1.0)
		_ui_canvas.draw_string(_font_bold, Vector2(cx - 140.0, 118.0), "✕ " + _fail_toast, HORIZONTAL_ALIGNMENT_CENTER, 280.0, 18, Color(COL_FAIL, fa2))

	# 2. 非时缓态：右下角轻量状态徽章
	if not stance_active:
		if not _is_blocked_context():
			_draw_ready_badge(vp)
		return

	# 3. 时缓维持态：全屏冷紫暗角 + 5:59 残时条 + 实时指令槽
	var rem_ratio := clampf(_stance_rem / maxf(_stance_max, 0.1), 0.0, 1.0)
	_ui_canvas.draw_rect(Rect2(Vector2.ZERO, vp), Color(0.035, 0.022, 0.075, 0.34))
	var border_col := Color(COL_FAIL, 0.82) if _wrong_flash > 0.0 else Color(COL_VIOLET, 0.58)
	_ui_canvas.draw_rect(Rect2(6.0, 6.0, vp.x - 12.0, vp.y - 12.0), border_col, false, 2.2)

	var top_y := 64.0
	var bar_w := 350.0
	var bar_bg := Rect2(cx - bar_w * 0.5, top_y, bar_w, 6.0)
	_ui_canvas.draw_rect(bar_bg, Color(0.10, 0.08, 0.16, 0.92))
	_ui_canvas.draw_rect(Rect2(bar_bg.position, Vector2(bar_w * rem_ratio, 6.0)), COL_FAIL if _wrong_flash > 0.0 else COL_VIOLET_LIGHT)
	_ui_canvas.draw_arc(Vector2(cx, top_y - 18.0), 14.0, -PI * 0.5, -PI * 0.5 + TAU * rem_ratio, 24, COL_SILVER, 2.0)

	var hold_lbl := "按住 LB 维持 · 松开退出" if GamepadManager.is_using_gamepad() else "按住 Tab/Ctrl 维持 · 松开退出"
	var dir_lbl := "十字键搓招" if GamepadManager.is_using_gamepad() else "方向键搓招"
	var head_txt := "5:59 凝晷时缓 · %s · %s" % [dir_lbl, hold_lbl]
	_ui_canvas.draw_string(_font_serif, Vector2(cx - 250.0, top_y - 12.0), head_txt, HORIZONTAL_ALIGNMENT_CENTER, 500.0, 14, Color(COL_SILVER, 0.94))

	var seq_str := ""
	for d in input_seq:
		seq_str += String(DIR_GLYPHS.get(d, d)) + "  "
	if seq_str == "":
		seq_str = "等待方向指令…"
	_ui_canvas.draw_string(_font_cinzel, Vector2(cx - 180.0, top_y + 34.0), seq_str.strip_edges(), HORIZONTAL_ALIGNMENT_CENTER, 360.0, 22, COL_GOLD if not input_seq.is_empty() else Color(COL_STEEL, 0.85))

	# 4. 已解锁技能按键操作提示面板（可在设置中关闭）
	if not GamepadManager.is_skill_hints_enabled():
		return

	var unlocked := get_unlocked_skills()
	var panel_w := 408.0
	var row_h := 34.0
	var panel_h := 56.0 + float(unlocked.size()) * row_h + 14.0
	var px := vp.x - panel_w - 28.0
	var py := clampf(vp.y * 0.5 - panel_h * 0.5, 118.0, vp.y - panel_h - 40.0)
	var rect := Rect2(px, py, panel_w, panel_h)

	var pts := PackedVector2Array([
		Vector2(rect.position.x + 12.0, rect.position.y),
		Vector2(rect.end.x, rect.position.y),
		Vector2(rect.end.x - 12.0, rect.end.y),
		Vector2(rect.position.x, rect.end.y),
	])
	_ui_canvas.draw_colored_polygon(pts, COL_INK)
	var left_bar := PackedVector2Array([pts[0], pts[0] + Vector2(5.0, 0.0), pts[3] + Vector2(5.0, 0.0), pts[3]])
	_ui_canvas.draw_colored_polygon(left_bar, COL_VIOLET)
	for pi in 4:
		_ui_canvas.draw_line(pts[pi], pts[(pi + 1) % 4], Color(COL_VIOLET_LIGHT, 0.55), 1.4, true)

	var eff_rank := effective_unlock_rank()
	var title_str := "已解锁技录（至 %s 档）" % RANK_LETTERS[eff_rank]
	_ui_canvas.draw_string(_font_bold, Vector2(px + 22.0, py + 28.0), title_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, COL_BONE)
	_ui_canvas.draw_string(_font_serif, Vector2(px + panel_w - 132.0, py + 28.0), "设置可关闭提示", HORIZONTAL_ALIGNMENT_RIGHT, 116.0, 12, Color(COL_STEEL, 0.78))
	_ui_canvas.draw_line(Vector2(px + 18.0, py + 38.0), Vector2(rect.end.x - 20.0, py + 38.0), Color(COL_SILVER, 0.22), 1.0)

	var ry := py + 62.0
	for sk in unlocked:
		var ridx := int(sk["rank"])
		var seq: Array = sk["seq"]
		var on_cd := (String(sk["id"]) == "dawn_judgment" and s_skill_cooldown > 0.0)
		var is_match := (not on_cd) and (input_seq.is_empty() or _matches_prefix(seq, input_seq))
		var row_alpha := 0.35 if (on_cd or not is_match) else 1.0
		var acc: Color = sk.get("accent", COL_VIOLET_LIGHT)

		if not input_seq.is_empty() and is_match:
			_ui_canvas.draw_rect(Rect2(px + 14.0, ry - 20.0, panel_w - 30.0, 28.0), Color(COL_VIOLET, 0.20))

		_ui_canvas.draw_string(_font_blackletter, Vector2(px + 24.0, ry), RANK_LETTERS[ridx], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(acc, row_alpha))
		_ui_canvas.draw_string(_font_bold, Vector2(px + 48.0, ry), String(sk["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(COL_BONE, row_alpha))

		var ax := px + 186.0
		for si in seq.size():
			var ch := String(DIR_GLYPHS.get(String(seq[si]), String(seq[si])))
			var matched_step := (not input_seq.is_empty()) and is_match and (si < input_seq.size())
			var kcol := Color(COL_GOLD, 1.0) if matched_step else Color(COL_SILVER, row_alpha)
			_ui_canvas.draw_string(_font_cinzel, Vector2(ax, ry), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, kcol)
			ax += 22.0

		var tail_txt := ("冷却 %.1fs" % s_skill_cooldown) if on_cd else String(sk["desc"])
		var tail_col := Color(COL_STEEL, 0.72) if on_cd else Color(COL_STEEL, 0.85 * row_alpha)
		_ui_canvas.draw_string(_font_serif, Vector2(px + 280.0, ry), tail_txt, HORIZONTAL_ALIGNMENT_LEFT, 120.0, 12, tail_col)
		ry += row_h


func _draw_ready_badge(vp: Vector2) -> void:
	var pad := GamepadManager.is_using_gamepad()
	var eff_rank := effective_unlock_rank()
	var key_str := "按住 LB" if pad else "按住 Tab/Ctrl"
	var msg := ""
	var col := COL_VIOLET_LIGHT
	if stance_cooldown > 0.0:
		msg = "凝晷冷却 %.1fs" % stance_cooldown
		col = COL_STEEL
	else:
		msg = "%s 凝晷搓招 · 至 %s 档" % [key_str, RANK_LETTERS[eff_rank]]
	var bw := 256.0
	var rect := Rect2(vp.x - bw - 20.0, vp.y - 86.0, bw, 30.0)
	_ui_canvas.draw_rect(rect, Color(0.04, 0.035, 0.075, 0.72))
	_ui_canvas.draw_rect(rect, Color(col, 0.45), false, 1.2)
	_ui_canvas.draw_string(_font_serif, rect.position + Vector2(10.0, 20.0), msg, HORIZONTAL_ALIGNMENT_LEFT, bw - 16.0, 13, col)
