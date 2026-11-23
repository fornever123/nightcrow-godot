extends "res://scripts/night/rain_street.gd"
## 独立测试版首领战关卡：「司辰母钟楼 · 血色玫瑰桥」（boss_clocktower_test.gd）
##
## 完全独立于现有关卡（rain_trial.tscn / boss_sample.tscn），不改动原版关卡任何逻辑。
## 首领外观当前沿用既有 BossShade（见 _spawn_boss 换皮钩子，后续可直接替换为专属司辰首领贴图/骨骼）。
##
## 核心机制（对齐设计构想）：
##   1. 血量阶段联动母钟拨针（背景巨型司辰母钟的指针物理拨动，同步对玩家与首领施加 Buff/Debuff）：
##      - 一阶段（100%–70% · Ⅲ:00 凝晷序幕）：
##          · 我方 Buff【时隙洞察】：技能解锁档位 +1、凝晷冷却 -22%、弹刀额外碎壳
##          · 首领技能【时隙残影斩】：斩击后留下 0.65s 延迟回放的时空残影斩（可弹刀/短闪）
##      - 二阶段（70%–35% · Ⅸ:00 逆时潮汐）：
##          · 我方 Debuff【时滞】：移速 -14%、回复效率 -35%
##          · 我方 Buff【裂时增幅】：搓招技能伤害 +35%、搓招破壳 +45%、技能解锁档位 +2
##          · 首领 Buff【回溯护壳】：凝壳完整时每秒缓充 +5.5
##          · 首领控制时间技【时间倒流】：咏唱 2.6s 回溯 3 秒前的血量与站位；可用弹刀/搓招技能/重击打断并触发「时流反噬」瞬间破壳！
##      - 三阶段（35%–0% · Ⅻ:00 拔针裁昼）：
##          · 母钟指针狂转至 12:00 后轰然震裂 —— 首领亲手将背景母钟的巨型指针拔下作为武器！
##          · 背景母钟指针消失并裂开炽红玫瑰窗；首领手中实机渲染巨型暗铁绯红指针战戟
##          · 全局狂潮【破晓狂锋 / 脆时烙印】：我方移速 +8%（解除时滞）、全攻 +30%、技能伤害 +40%、档位 +3，但所受伤害 +25%
##          · 首领拔针三式：「时针横扫」「分针穿刺（留时空裂痕）」「十二刻钟轮斩（插地 12 道钟辐震荡波）」

const BossShade := preload("res://scripts/boss_sample/boss_shade.gd")
const Dodge := preload("res://scripts/boss_sample/dodge.gd")
const AirRules := preload("res://scripts/boss_sample/air_rules.gd")
const ResultPanel := preload("res://scripts/boss_sample/boss_result.gd")
const ClocktowerBackdrop := preload("res://scripts/boss_clocktower/clocktower_backdrop.gd")
const ClocktowerBossBar := preload("res://scripts/boss_clocktower/clocktower_boss_bar.gd")
const GothicFonts := preload("res://scripts/ui/gothic_fonts.gd")

const ARENA_LAYOUT := "res://assets/data/boss_arena_layout.json"
const SCENE := "res://scenes/boss_clocktower_test.tscn"

const FIGHT_HALF := 1120.0
const BOSS_NAME := "司辰 · 母钟守望（测试）"
const ARENA_TITLE := "司辰母钟楼 · 血色玫瑰桥"
const BOSS_MAX_HP := 2400.0
const PHASE2_HP_RATIO := 0.70
const PHASE3_HP_RATIO := 0.35
const REWIND_CHANNEL_DUR := 2.6
const REWIND_COOLDOWN := 10.5
const RESULT_DELAY := 1.6

var boss: Node2D = null
var boss_bar: Control = null
var dodge: Node = null
var air_rules: Node = null
var boss_visual_profile: String = "boss_shade_placeholder"

## 时钟阶段与时间操控状态（供 HUD 与 E2E 测试读取）
var clock_phase: int = 1
var boss_wields_clock_hand: bool = false
var rewind_channel_active: bool = false
var rewind_channel_progress: float = 0.0
var rewinds_interrupted: int = 0
var rewinds_completed: int = 0
var clock_hand_attacks_used: int = 0
var last_clock_hand_attack: StringName = &""

var won: bool = false
var hits_taken: int = 0
var fight_time: float = 0.0

var _base_player_speed: float = 450.0
var _incoming_dmg_mul: float = 1.0
var _heal_efficiency: float = 1.0
var _restart_pending: bool = false
var _result: Node = null
var _slowmo_token: int = 0

## 内部计时器与特效队列
var _history_samples: Array[Dictionary] = []
var _history_accum: float = 0.0
var _rewind_cd: float = 6.0
var _rewind_timer: float = 0.0
var _rewind_anchor_hp: float = 0.0
var _rewind_anchor_pos: Vector2 = Vector2.ZERO
var _last_boss_state: int = -1

var _echo_slashes: Array[Dictionary] = []
var _echo_cd: float = 3.2
var _hand_attack_cd: float = 2.4
var _hand_attack_idx: int = 0
var _hand_attack_state: Dictionary = {}       ## {active, kind, phase, t, windup, strike_done, dir, origin}
var _temporal_rifts: Array[Dictionary] = []  ## [{pos, half_w, ttl, max_ttl, tick_t}]
var _ring_waves: Array[Dictionary] = []      ## [{pos, col, max_r, t, dur}]

var _arena_fx: Node2D = null
var _weapon_overlay: Node2D = null
var _mv_clock_sweep: MoveDefinition = null
var _mv_clock_thrust: MoveDefinition = null
var _mv_clock_wheel: MoveDefinition = null
var _mv_echo_slash: MoveDefinition = null


func _init() -> void:
	super()
	zoom_level = 0.62
	stage_title = PackedStringArray([BOSS_NAME, ARENA_TITLE])
	var f := FileAccess.open(ARENA_LAYOUT, FileAccess.READ)
	if f != null:
		var d: Variant = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			layout = d


func _exit_tree() -> void:
	Engine.time_scale = 1.0
	super()


func _make_backdrop() -> Node2D:
	var b: Node2D = ClocktowerBackdrop.new()
	b.layout = layout
	b.first_x = first_arena_x
	b.spacing = arena_spacing
	b.actors = func() -> Array:
		var out: Array = [player]
		out.append_array(get_tree().get_nodes_in_group(&"shade"))
		return out
	return b


func _make_terrain() -> Node2D:
	var t: Node2D = Terrain.new()
	t.sections = layout.get("sections", [])
	return t


func _build_clock_moves() -> void:
	_mv_echo_slash = _make_boss_move(&"clock_echo_slash", 14.0, 260.0, 4)
	_mv_clock_sweep = _make_boss_move(&"clock_hand_sweep", 22.0, 420.0, 6)
	_mv_clock_thrust = _make_boss_move(&"clock_hand_thrust", 20.0, 360.0, 5)
	_mv_clock_wheel = _make_boss_move(&"clock_wheel_cleave", 26.0, 500.0, 7)


static func _make_boss_move(mid: StringName, dmg: float, kb: float, hitstop: int) -> MoveDefinition:
	var mv := MoveDefinition.new()
	mv.id = mid
	mv.damage = dmg
	mv.knockback = kb
	mv.hitstop_frames = hitstop
	mv.victim_hitstop_frames = hitstop
	return mv


func _stage_ready() -> void:
	super()
	_hint_queue.clear()
	_build_clock_moves()
	_base_player_speed = float(player.speed)

	# Shift / RB 短闪绕背；B 专用于时缓搓招，LB 专用于弹刀
	Factory.register_input({"dash_modifier": [], Dodge.ACTION: [KEY_SHIFT]})
	var has_rb := false
	for ev in InputMap.action_get_events(Dodge.ACTION):
		if ev is InputEventJoypadButton and (ev as InputEventJoypadButton).button_index == JOY_BUTTON_RIGHT_SHOULDER:
			has_rb = true
			break
	if not has_rb:
		var rbb := InputEventJoypadButton.new()
		rbb.device = -1
		rbb.button_index = JOY_BUTTON_RIGHT_SHOULDER
		InputMap.action_add_event(Dodge.ACTION, rbb)

	dodge = Dodge.new()
	dodge.name = "Dodge"
	dodge.player = player
	add_child(dodge)

	air_rules = AirRules.new()
	air_rules.name = "AirRules"
	air_rules.player = player
	air_rules.dodge = dodge
	add_child(air_rules)

	apply_control_scheme()

	_arena_fx = _ClocktowerArenaFx.new()
	_arena_fx.name = "ClocktowerArenaFx"
	_arena_fx.stage = self
	_arena_fx.z_index = 6
	add_child(_arena_fx)

	_setup_bridge_arena()
	var px := arena_center - 360.0
	player.global_position = Vector2(px, terrain.solid_top(px, 30.0) - player.foot_offset)
	camera.global_position = Vector2(arena_center, camera.lock_y)

	_spawn_boss(arena_center + 300.0)

	# 连接玩家弹刀与搓招技能信号，用于一阶段强化 & 二阶段打断「时间倒流」
	if player != null and not player.parry_success.is_connected(_on_clock_player_parry):
		player.parry_success.connect(_on_clock_player_parry)
	if combo_skills != null and not combo_skills.skill_cast.is_connected(_on_clock_skill_cast):
		combo_skills.skill_cast.connect(_on_clock_skill_cast)

	var bar_layer := CanvasLayer.new()
	bar_layer.name = "ClocktowerBossBarLayer"
	bar_layer.layer = 10
	add_child(bar_layer)
	boss_bar = ClocktowerBossBar.new()
	boss_bar.name = "ClocktowerBossBar"
	boss_bar.stage = self
	bar_layer.add_child(boss_bar)

	# 初始进入一阶段 Ⅲ:00
	_enter_clock_phase(1, true)
	boss.begin_intro()
	hud.banner(BOSS_NAME, "Ⅲ:00 凝晷序幕 · 观察背景母钟指针与时间法则变化", 2.6)
	print("CLOCKTOWER_BOSS_READY")


func apply_control_scheme() -> void:
	super()
	if not InputMap.has_action(Dodge.ACTION):
		InputMap.add_action(Dodge.ACTION)
	var stale: Array[InputEvent] = []
	var has_shift := false
	var has_rb := false
	for ev in InputMap.action_get_events(Dodge.ACTION):
		if ev is InputEventKey and ((ev as InputEventKey).physical_keycode == KEY_SHIFT or (ev as InputEventKey).keycode == KEY_SHIFT):
			has_shift = true
		elif ev is InputEventJoypadButton:
			var jb := ev as InputEventJoypadButton
			if jb.button_index == JOY_BUTTON_RIGHT_SHOULDER:
				has_rb = true
			elif jb.button_index == JOY_BUTTON_LEFT_SHOULDER or jb.button_index == JOY_BUTTON_B:
				stale.append(ev)
	for ev in stale:
		InputMap.action_erase_event(Dodge.ACTION, ev)
	if not has_shift:
		var sk := InputEventKey.new()
		sk.physical_keycode = KEY_SHIFT
		InputMap.action_add_event(Dodge.ACTION, sk)
	if not has_rb:
		var rbb := InputEventJoypadButton.new()
		rbb.device = -1
		rbb.button_index = JOY_BUTTON_RIGHT_SHOULDER
		InputMap.action_add_event(Dodge.ACTION, rbb)
	if hud != null:
		if GamepadManager.is_using_gamepad():
			hud.help_text = "左摇杆 移动   RB 短闪绕背   按住 B 时缓 + 十字键搓招   LB 弹刀/打断时间倒流   RT 绝影   Back 重战   Start 暂停"
		else:
			var sc := Factory.scheme()
			hud.help_text = "A/D 移动   Shift 短闪   按住 Tab/Ctrl 时缓 + 方向键搓招   %s 弹刀/打断时间倒流   R 绝影   F5 重战   Esc 暂停" % [
				CombatControls.key_label(sc, "parry"),
			]
		hud.queue_redraw()


func _queue_hint(_id: StringName, _text: String, _seconds: float, _urgent: bool = false) -> void:
	pass


func _setup_bridge_arena() -> void:
	encounter_index = 0
	arena_center = _center_of(0)
	_ensure_terrain(0)
	var left := arena_center - FIGHT_HALF
	var right := arena_center + FIGHT_HALF
	seal_x = Vector2(left, right)
	if seal_walls.is_empty():
		seal_walls = [_make_wall(left - 20.0), _make_wall(right + 20.0)]
	else:
		seal_walls[0].position.x = left - 20.0
		seal_walls[1].position.x = right + 20.0
	back_limit = left
	back_wall.position.x = left - 20.0
	camera.arena_min = Vector2(left - 180.0, camera.arena_min.y)
	camera.arena_max = Vector2(right + 180.0, camera.arena_max.y)
	phase = Phase.FIGHT
	seal_alpha = 0.0
	if backdrop != null:
		backdrop.cam_ref = camera.lock_y
		backdrop.configure_duel_arena(arena_center, FIGHT_HALF)
	if post != null:
		post.mat.set_shader_parameter("rays_amt", 0.22)


## 首领生成与外观挂载点（当前复用 BossShade；未来更换专属 Boss 贴图/骨骼仅需替换此处节点装配）
func _spawn_boss(x: float) -> void:
	boss = Node2D.new()
	boss.name = "BossClocktowerWarden"
	boss.set_script(BossShade)
	boss.setup(Shade.Kind.BRUTE, player, floor_y, 1.0)
	boss.arena_left = seal_x.x
	boss.arena_right = seal_x.y
	boss.max_attackers = 1
	boss.terrain = terrain
	boss.position = Vector2(x, floor_y - 200.0)
	boss.facing = -1
	boss.dodge = dodge
	boss.air_rules = air_rules
	add_child(boss)
	# 在 BossShade._ready() 之后覆盖测试首领三阶段血量上限
	boss.max_hp = BOSS_MAX_HP
	boss.hp = BOSS_MAX_HP
	boss.max_shell = 120.0
	boss.shell = 120.0
	_on_shade_spawned(boss)

	_weapon_overlay = _ClockHandWeaponOverlay.new()
	_weapon_overlay.name = "ClockHandWeaponOverlay"
	_weapon_overlay.stage = self
	_weapon_overlay.z_index = 4
	boss.add_child(_weapon_overlay)

	boss.wall_slam.connect(_on_pillar_slam)
	boss.shell_shattered.connect(_on_shell_shattered)
	boss.damaged.connect(_on_boss_damaged)
	boss.died.connect(_on_boss_killed)


# ---------------------------------------------------------------- 三阶段母钟拨针与 Buff/Debuff 联动

func get_active_clock_effects() -> Array[Dictionary]:
	match clock_phase:
		1:
			return [
				{"target": "player", "debuff": false, "label": "我方·时隙洞察（技录+1 冷却-22%）"},
				{"target": "boss", "debuff": false, "label": "首领·时隙残影斩"},
			]
		2:
			return [
				{"target": "player", "debuff": true, "label": "我方·时滞（移速-14% 回复-35%）"},
				{"target": "player", "debuff": false, "label": "我方·裂时增幅（技伤+35% 破壳+45%）"},
				{"target": "boss", "debuff": false, "label": "首领·回溯护壳 & 时间倒流"},
			]
		_:
			return [
				{"target": "player", "debuff": false, "label": "我方·破晓狂锋（攻+30% 技伤+40% 移速+8%）"},
				{"target": "player", "debuff": true, "label": "我方·脆时烙印（受伤+25%）"},
				{"target": "boss", "debuff": false, "label": "首领·拔针裁昼（巨型指针武器）"},
			]


func _enter_clock_phase(new_phase: int, instant: bool = false) -> void:
	clock_phase = clampi(new_phase, 1, 3)
	if rewind_channel_active and clock_phase != 2:
		_finish_rewind_channel(false)

	match clock_phase:
		1:
			boss_wields_clock_hand = false
			_incoming_dmg_mul = 1.0
			_heal_efficiency = 1.0
			player.speed = _base_player_speed
			player.attack_damage_mul = 1.0
			if combo_skills != null:
				combo_skills.stage_rank_bonus = 1
				combo_skills.stage_cd_mul = 0.78
				combo_skills.stage_dmg_mul = 1.0
				combo_skills.stage_shell_mul = 1.15
			if backdrop != null:
				backdrop.set_phase_visual(1)
				backdrop.set_clock_dial(90.0, 0.0, instant)
				backdrop.set_rewind_glow(0.0)
		2:
			boss_wields_clock_hand = false
			_incoming_dmg_mul = 1.0
			_heal_efficiency = 0.65
			player.speed = _base_player_speed * 0.86
			player.attack_damage_mul = 1.0
			if combo_skills != null:
				combo_skills.stage_rank_bonus = 2
				combo_skills.stage_cd_mul = 0.85
				combo_skills.stage_dmg_mul = 1.35
				combo_skills.stage_shell_mul = 1.45
			if backdrop != null:
				backdrop.set_phase_visual(2)
				backdrop.set_clock_dial(270.0, 0.0, instant)
			_rewind_cd = 4.2
			if not instant:
				_spawn_ring_wave(boss.global_position, Color(0.76, 0.34, 1.0, 0.92), 420.0, 0.45)
				camera.add_shake(24.0 * shake_mul)
				audio.play_seal()
				hud.banner("Ⅸ:00 · 逆时潮汐", "母钟逆拨！我方【时滞 + 裂时增幅】· 警惕首领咏唱「时间倒流」", 2.8)
		3:
			boss_wields_clock_hand = true
			_incoming_dmg_mul = 1.25
			_heal_efficiency = 0.85
			player.speed = _base_player_speed * 1.08
			player.attack_damage_mul = 1.30
			if combo_skills != null:
				combo_skills.stage_rank_bonus = 3
				combo_skills.stage_cd_mul = 0.72
				combo_skills.stage_dmg_mul = 1.40
				combo_skills.stage_shell_mul = 1.50
			if boss != null and is_instance_valid(boss):
				boss.max_shell = 72.0
				boss.shell = minf(boss.shell, boss.max_shell)
			if backdrop != null:
				backdrop.set_phase_visual(3)
				backdrop.set_clock_dial(0.0, 0.0, true)
				backdrop.set_rewind_glow(0.0)
				backdrop.detach_clock_hands()
			_hand_attack_cd = 1.6
			if not instant:
				_spawn_ring_wave(backdrop.get_clock_center_world() if backdrop != null else boss.global_position, Color(1.0, 0.28, 0.20, 0.95), 620.0, 0.55)
				_spawn_ring_wave(boss.global_position, Color(1.0, 0.78, 0.38, 0.92), 360.0, 0.42)
				camera.add_shake(36.0 * shake_mul)
				audio.play_seal()
				audio.play_slam(1.0)
				_trigger_phase_slowmo(0.24, 0.34)
				hud.banner("Ⅻ:00 · 拔针裁昼", "首领拔下母钟巨型指针！全局【破晓狂锋 + 脆时烙印】· 迎接指针三式！", 3.2)


func _check_phase_thresholds() -> void:
	if boss == null or not is_instance_valid(boss) or not boss.is_alive():
		return
	var ratio := clampf(float(boss.hp) / maxf(float(boss.max_hp), 1.0), 0.0, 1.0)
	if clock_phase < 3 and ratio <= PHASE3_HP_RATIO:
		_enter_clock_phase(3, false)
	elif clock_phase < 2 and ratio <= PHASE2_HP_RATIO:
		_enter_clock_phase(2, false)


func _trigger_phase_slowmo(scale_val: float, real_dur: float) -> void:
	if won:
		return
	_slowmo_token += 1
	var tok := _slowmo_token
	Engine.time_scale = scale_val
	await get_tree().create_timer(real_dur, true, false, true).timeout
	if is_inside_tree() and not won and tok == _slowmo_token:
		if combo_skills == null or not combo_skills.stance_active:
			Engine.time_scale = 1.0


# ---------------------------------------------------------------- 二阶段时间操控：可打断「时间倒流」

func start_rewind_channel() -> bool:
	if boss == null or not is_instance_valid(boss) or not boss.is_alive() or rewind_channel_active:
		return false
	if boss.state == Shade.State.LAUNCHED or boss.state == Shade.State.DOWN:
		return false
	rewind_channel_active = true
	_rewind_timer = 0.0
	rewind_channel_progress = 0.0
	# 取 ~3 秒前历史锚点（若历史不足则按当前位置 + 额外回溯量兜底）
	var anchor := {"hp": minf(boss.hp + boss.max_hp * 0.10, boss.max_hp * 0.69), "pos": boss.global_position}
	if not _history_samples.is_empty():
		anchor = _history_samples[0]
	_rewind_anchor_hp = minf(float(anchor["hp"]), boss.max_hp * 0.69)
	_rewind_anchor_pos = anchor["pos"]
	boss.cooldown = maxi(int(boss.cooldown), 150)
	boss.velocity = Vector2.ZERO
	if backdrop != null:
		backdrop.set_rewind_glow(1.0)
	_spawn_ring_wave(boss.global_position, Color(0.74, 0.36, 1.0, 0.90), 320.0, 0.40)
	audio.play_seal()
	hud.callout("时间倒流咏唱！弹刀或搓招技能立刻打断！", Color("df9eff"), 40)
	return true


func interrupt_rewind_channel(source_label: String = "时流反噬") -> bool:
	if not rewind_channel_active or boss == null or not is_instance_valid(boss):
		return false
	rewind_channel_active = false
	rewind_channel_progress = 0.0
	_rewind_timer = 0.0
	_rewind_cd = REWIND_COOLDOWN
	rewinds_interrupted += 1
	if backdrop != null:
		backdrop.set_rewind_glow(0.0)
	# 打断惩罚：瞬间破壳 + 140 真实反噬伤害 + 僵直
	var pdir := int(player.facing) if player != null else 1
	boss.damage_shell(999.0, boss.global_position, pdir, false)
	boss.hp = maxf(1.0, boss.hp - 140.0)
	boss.damaged.emit(140.0, boss.hp, boss.global_position)
	boss.flash = 10
	boss.flash_color = Color(0.84, 0.52, 1.0)
	_spawn_ring_wave(boss.global_position, Color(0.70, 0.96, 1.0, 0.96), 440.0, 0.42)
	fx.spawn_ground_slam(boss.global_position, 1.0)
	fx.spawn_text(boss.global_position + Vector2(0.0, -175.0), "%s -140" % source_label, 140.0, true)
	hud.callout("打断时间倒流！%s · 白金凝壳碎裂！" % source_label, Color("92f0ff"), 50)
	camera.add_shake(26.0 * shake_mul)
	audio.play_slam(0.95)
	if style != null:
		style.add_event(&"parry")
	_check_phase_thresholds()
	return true


func _finish_rewind_channel(apply_rewind: bool) -> void:
	rewind_channel_active = false
	rewind_channel_progress = 0.0
	_rewind_timer = 0.0
	_rewind_cd = REWIND_COOLDOWN
	if backdrop != null:
		backdrop.set_rewind_glow(0.0)
	if not apply_rewind or boss == null or not is_instance_valid(boss) or not boss.is_alive():
		return
	rewinds_completed += 1
	var target_hp := maxf(boss.hp, minf(_rewind_anchor_hp, boss.hp + boss.max_hp * 0.10))
	target_hp = minf(target_hp, boss.max_hp * 0.69)
	var healed := maxf(0.0, target_hp - boss.hp)
	boss.hp = target_hp
	boss.global_position.x = clampf(_rewind_anchor_pos.x, seal_x.x + 110.0, seal_x.y - 110.0)
	_spawn_ring_wave(boss.global_position, Color(0.86, 0.36, 1.0, 0.95), 480.0, 0.45)
	fx.spawn_text(boss.global_position + Vector2(0.0, -170.0), "时间倒流 +%d" % int(round(healed)))
	hud.callout("时间倒流完成！首领血量与位置已回溯", Color("e48cff"), 42)
	camera.add_shake(18.0 * shake_mul)
	audio.play_seal()


# ---------------------------------------------------------------- 三阶段拔针武器招式：时针横扫 / 分针穿刺 / 十二刻钟轮斩

func trigger_clock_hand_attack(kind: StringName = &"") -> bool:
	if not boss_wields_clock_hand or boss == null or not is_instance_valid(boss) or not boss.is_alive():
		return false
	if not _hand_attack_state.is_empty() and bool(_hand_attack_state.get("active", false)):
		return false
	if boss.state == Shade.State.LAUNCHED or boss.state == Shade.State.DOWN:
		return false
	var chosen := kind
	if chosen == &"":
		var cycle: Array[StringName] = [&"hand_sweep", &"hand_thrust", &"clock_wheel"]
		chosen = cycle[_hand_attack_idx % cycle.size()]
		_hand_attack_idx += 1
	var fdir := 1 if player.global_position.x >= boss.global_position.x else -1
	boss.facing = fdir
	var windup := 0.56 if chosen == &"hand_sweep" else (0.50 if chosen == &"hand_thrust" else 0.68)
	_hand_attack_state = {
		"active": true,
		"kind": chosen,
		"t": 0.0,
		"windup": windup,
		"dur": windup + 0.34,
		"strike_done": false,
		"dir": fdir,
		"origin": boss.global_position,
	}
	last_clock_hand_attack = chosen
	clock_hand_attacks_used += 1
	boss.cooldown = maxi(int(boss.cooldown), 78)
	boss.velocity.x = 0.0
	var call_title := "时针横扫！" if chosen == &"hand_sweep" else ("分针穿刺！" if chosen == &"hand_thrust" else "十二刻钟轮斩！")
	hud.callout(call_title, Color("ff6458"), 38)
	audio._play_clip("parry", 0.35, -8.0)
	return true


func _tick_clock_hand_attack(delta: float) -> void:
	if _hand_attack_state.is_empty() or not bool(_hand_attack_state.get("active", false)):
		return
	if boss == null or not is_instance_valid(boss) or not boss.is_alive() or boss.state == Shade.State.LAUNCHED:
		_hand_attack_state.clear()
		return
	var t := float(_hand_attack_state["t"]) + delta
	_hand_attack_state["t"] = t
	var windup := float(_hand_attack_state["windup"])
	var dur := float(_hand_attack_state["dur"])
	var kind: StringName = _hand_attack_state["kind"]
	var fdir := int(_hand_attack_state["dir"])

	if not bool(_hand_attack_state["strike_done"]) and t >= windup:
		_hand_attack_state["strike_done"] = true
		_execute_clock_hand_strike(kind, fdir)
	if t >= dur:
		_hand_attack_state.clear()
		_hand_attack_cd = 4.2


func _execute_clock_hand_strike(kind: StringName, fdir: int) -> void:
	if boss == null or not is_instance_valid(boss):
		return
	var bp := boss.global_position
	var pp := player.global_position
	var dodging := dodge != null and bool(dodge.call(&"counts_as_dodge"))
	match kind:
		&"hand_sweep":
			camera.add_shake(22.0 * shake_mul, Vector2(float(fdir), 0.0))
			audio.play_slam(0.85)
			_spawn_ring_wave(bp + Vector2(float(fdir) * 140.0, -30.0), Color(1.0, 0.28, 0.22, 0.92), 360.0, 0.30)
			if backdrop != null:
				backdrop.slash_rain_at(bp + Vector2(float(fdir) * 180.0, -60.0), 320.0, Vector2(float(fdir), 0.15))
			var dx := (pp.x - bp.x) * float(fdir)
			if not dodging and dx >= -65.0 and dx <= 415.0 and absf(pp.y - bp.y) <= 175.0:
				_hit_player_with_clock_move(_mv_clock_sweep, fdir, pp)
		&"hand_thrust":
			var start_x := bp.x
			var end_x := clampf(bp.x + float(fdir) * 340.0, seal_x.x + 110.0, seal_x.y - 110.0)
			boss.global_position.x = end_x
			camera.add_shake(20.0 * shake_mul, Vector2(float(fdir), 0.0))
			audio._play_clip("parry", 0.55, -5.0)
			# 在穿刺路径留下持续 1.4s 的血紫时空裂隙
			var mid_x := (start_x + end_x) * 0.5
			_temporal_rifts.append({
				"pos": Vector2(mid_x, floor_y - 36.0),
				"half_w": maxf(130.0, absf(end_x - start_x) * 0.52),
				"ttl": 1.4,
				"max_ttl": 1.4,
				"tick_t": 0.45,
			})
			var lo := minf(start_x, end_x) - 55.0
			var hi := maxf(start_x, end_x) + 55.0
			if not dodging and pp.x >= lo and pp.x <= hi and absf(pp.y - bp.y) <= 155.0:
				_hit_player_with_clock_move(_mv_clock_thrust, fdir, pp)
		&"clock_wheel":
			camera.add_shake(30.0 * shake_mul, Vector2.DOWN)
			audio.play_slam(1.0)
			var ground_pt := Vector2(bp.x, floor_y)
			fx.spawn_ground_slam(ground_pt, 1.15)
			_spawn_ring_wave(ground_pt, Color(1.0, 0.30, 0.18, 0.96), 440.0, 0.38)
			_spawn_ring_wave(ground_pt, Color(1.0, 0.84, 0.44, 0.88), 320.0, 0.32)
			var player_on_ground := absf((player.global_position.y + player.foot_offset) - floor_y) <= 95.0
			if not dodging and player_on_ground and absf(pp.x - bp.x) <= 345.0:
				var hit_dir := 1 if pp.x >= bp.x else -1
				_hit_player_with_clock_move(_mv_clock_wheel, hit_dir, pp)


func _hit_player_with_clock_move(mv: MoveDefinition, from_facing: int, point: Vector2) -> void:
	if player == null or not is_instance_valid(player) or float(player.hp) <= 0.0:
		return
	var hp_before := float(player.hp)
	var parried_or_blocked: bool = player.take_hit(mv, from_facing, point, 0.0, false, _incoming_dmg_mul, boss)
	if not parried_or_blocked:
		var lost := maxf(0.0, hp_before - float(player.hp))
		if lost > 0.01:
			_on_player_hurt(lost, point, 10.0, Vector2(float(from_facing), 0.0), true)


# ---------------------------------------------------------------- 主循环推进

func _physics_process(delta: float) -> void:
	if boss != null and is_instance_valid(boss) and boss.intro_frames > 0:
		if Input.is_action_just_pressed(&"attack_light") or Input.is_action_just_pressed(&"jump"):
			boss.skip_intro()
	elif not won and phase == Phase.FIGHT:
		fight_time += delta

	super(delta)
	_push_out_of_boss()

	if boss != null and is_instance_valid(boss) and boss.is_alive() and boss.intro_frames <= 0 and not won:
		_check_phase_thresholds()
		_tick_boss_history(delta)
		_tick_clock_phase_mechanics(delta)
	_tick_echo_slashes(delta)
	_tick_temporal_rifts(delta)
	_tick_ring_waves(delta)


func _tick_boss_history(delta: float) -> void:
	_history_accum += delta
	if _history_accum < 0.25:
		return
	_history_accum = 0.0
	_history_samples.append({"hp": float(boss.hp), "pos": boss.global_position})
	while _history_samples.size() > 14:
		_history_samples.pop_front()


func _tick_clock_phase_mechanics(delta: float) -> void:
	# 一阶段：检测首领出招结束或在冷却到点时留下「时隙残影斩」
	if clock_phase == 1:
		_echo_cd = maxf(0.0, _echo_cd - delta)
		if _last_boss_state == Shade.State.STRIKE and int(boss.state) != Shade.State.STRIKE and _echo_cd <= 0.0:
			_spawn_echo_slash(boss.global_position, int(boss.facing))
			_echo_cd = 5.5
		elif _echo_cd <= 0.0 and absf(player.global_position.x - boss.global_position.x) < 520.0:
			_spawn_echo_slash(boss.global_position, 1 if player.global_position.x >= boss.global_position.x else -1)
			_echo_cd = 7.2
	_last_boss_state = int(boss.state)

	# 二阶段：回溯护壳缓充 + 定期咏唱「时间倒流」
	if clock_phase == 2:
		if not boss.is_shell_broken and boss.shell < boss.max_shell:
			boss.shell = minf(boss.max_shell, boss.shell + 5.5 * delta)
		if rewind_channel_active:
			_rewind_timer += delta
			rewind_channel_progress = clampf(_rewind_timer / REWIND_CHANNEL_DUR, 0.0, 1.0)
			if backdrop != null:
				backdrop.set_rewind_glow(0.65 + 0.35 * sin(fight_time * 14.0))
			if _rewind_timer >= REWIND_CHANNEL_DUR:
				_finish_rewind_channel(true)
		else:
			_rewind_cd -= delta
			if _rewind_cd <= 0.0 and boss.hp < boss.max_hp * 0.67:
				start_rewind_channel()

	# 三阶段：拔针武器三式轮替
	if clock_phase == 3:
		_tick_clock_hand_attack(delta)
		if _hand_attack_state.is_empty():
			_hand_attack_cd -= delta
			if _hand_attack_cd <= 0.0:
				trigger_clock_hand_attack()


func _spawn_echo_slash(pos: Vector2, fdir: int) -> void:
	_echo_slashes.append({
		"pos": pos,
		"dir": fdir,
		"t": 0.0,
		"delay": 0.68,
		"done": false,
		"ttl": 0.98,
	})


func _tick_echo_slashes(delta: float) -> void:
	var i := _echo_slashes.size() - 1
	while i >= 0:
		var e: Dictionary = _echo_slashes[i]
		e["t"] = float(e["t"]) + delta
		if not bool(e["done"]) and float(e["t"]) >= float(e["delay"]):
			e["done"] = true
			var ep: Vector2 = e["pos"]
			var fdir: int = int(e["dir"])
			var dodging := dodge != null and bool(dodge.call(&"counts_as_dodge"))
			var dx := (player.global_position.x - ep.x) * float(fdir)
			if not dodging and dx >= -40.0 and dx <= 280.0 and absf(player.global_position.y - ep.y) <= 155.0:
				_hit_player_with_clock_move(_mv_echo_slash, fdir, player.global_position)
			audio._play_clip("parry", 0.22, -10.0)
		if float(e["t"]) >= float(e["ttl"]):
			_echo_slashes.remove_at(i)
		i -= 1


func _tick_temporal_rifts(delta: float) -> void:
	var i := _temporal_rifts.size() - 1
	while i >= 0:
		var r: Dictionary = _temporal_rifts[i]
		r["ttl"] = float(r["ttl"]) - delta
		r["tick_t"] = float(r["tick_t"]) - delta
		if float(r["tick_t"]) <= 0.0:
			r["tick_t"] = 0.55
			var rp: Vector2 = r["pos"]
			var dodging := dodge != null and bool(dodge.call(&"counts_as_dodge"))
			if not dodging and absf(player.global_position.x - rp.x) <= float(r["half_w"]) and absf((player.global_position.y + player.foot_offset) - floor_y) <= 85.0:
				var fdir := 1 if player.global_position.x >= rp.x else -1
				_hit_player_with_clock_move(_mv_echo_slash, fdir, player.global_position)
		if float(r["ttl"]) <= 0.0:
			_temporal_rifts.remove_at(i)
		i -= 1


func _tick_ring_waves(delta: float) -> void:
	var i := _ring_waves.size() - 1
	while i >= 0:
		_ring_waves[i]["t"] = float(_ring_waves[i]["t"]) + delta
		if float(_ring_waves[i]["t"]) >= float(_ring_waves[i]["dur"]):
			_ring_waves.remove_at(i)
		i -= 1


func _spawn_ring_wave(pos: Vector2, col: Color, max_r: float, dur: float) -> void:
	_ring_waves.append({"pos": pos, "col": col, "max_r": max_r, "t": 0.0, "dur": dur})


func _push_out_of_boss() -> void:
	if boss == null or not is_instance_valid(boss) or not boss.is_alive() or (dodge != null and dodge.is_dodging()) or boss.intro_frames > 0:
		return
	if boss.state == Shade.State.LAUNCHED or boss.state == Shade.State.DOWN:
		return
	if not player.is_on_floor() or absf(boss.feet_y() - (player.global_position.y + player.foot_offset)) > 44.0:
		return
	var dx: float = player.global_position.x - boss.global_position.x
	var need: float = boss.half_w + boss.PLAYER_HALF_W
	if absf(dx) >= need:
		return
	var side := 1.0 if dx >= 0.0 else -1.0
	var want: float = boss.global_position.x + side * need
	if want < seal_x.x + 30.0 or want > seal_x.y - 30.0:
		boss.position.x = player.global_position.x - side * need
	else:
		player.global_position.x = want


func _process(delta: float) -> void:
	super(delta)
	if seal_alpha != 0.0:
		seal_alpha = 0.0
		queue_redraw()
	if _arena_fx != null:
		_arena_fx.queue_redraw()
	if _weapon_overlay != null:
		_weapon_overlay.queue_redraw()
	if hud != null:
		var time_lbl := "Ⅲ:00" if clock_phase == 1 else ("Ⅸ:00" if clock_phase == 2 else "Ⅻ:00")
		hud.wave_text = "%s · %s · %d 秒" % [BOSS_NAME, time_lbl, int(fight_time)]


# ---------------------------------------------------------------- 信号响应与胜负结算

func _on_clock_player_parry(attacker: Node, point: Vector2) -> void:
	if clock_phase == 1 and player.has_method(&"refund_shadow"):
		player.refund_shadow(1)
	if boss != null and is_instance_valid(boss) and attacker == boss:
		boss.damage_shell(42.0 if clock_phase == 1 else 36.0, point, int(player.facing), false)
		if rewind_channel_active:
			interrupt_rewind_channel("弹刀破时")


func _on_clock_skill_cast(_skill_id: String, _rank_idx: int) -> void:
	if rewind_channel_active:
		interrupt_rewind_channel("搓招断时")


func _on_boss_damaged(amount: float, _hp_left: float, _point: Vector2) -> void:
	if rewind_channel_active and amount >= 35.0:
		interrupt_rewind_channel("重创破时")
	_check_phase_thresholds()


func _on_shell_shattered(point: Vector2) -> void:
	style.add_event(&"parry")
	fx.spawn_ground_slam(point, 0.9)
	fx.spawn_text(point + Vector2(0.0, -170.0), "破壳！")
	hud.callout("白金凝壳碎裂！全输出窗口！", Color("8ef0ff"), 50)
	camera.add_shake(22.0 * shake_mul)
	audio.play_slam(0.85)
	_spawn_ring_wave(point, Color(0.76, 0.96, 1.0, 0.95), 280.0, 0.30)


func _on_pillar_slam(speed: float, damage: float, point: Vector2) -> void:
	if won:
		return
	var side := 1 if point.x > arena_center else -1
	if backdrop != null and backdrop.has_method(&"notify_pillar_impact"):
		backdrop.notify_pillar_impact(side, clampf(speed / 900.0, 0.7, 1.8))
	fx.spawn_ground_slam(point, 1.0)
	fx.spawn_text(point + Vector2(-float(side) * 40.0, -150.0), "轰柱", damage, true)
	camera.add_shake(24.0 * shake_mul, Vector2(side, 0))
	audio.play_slam(0.95)


func _on_player_hurt(dmg: float, point: Vector2, shake: float = 3.0, dir: Vector2 = Vector2.ZERO, heavy: bool = false) -> void:
	hits_taken += 1
	super(dmg, point, shake, dir, heavy)


func _on_boss_killed() -> void:
	won = true
	if rewind_channel_active:
		_finish_rewind_channel(false)
	_hand_attack_state.clear()
	_slowmo_token += 1
	_slowmo(0.2, 0.9)
	camera.add_shake(32.0 * shake_mul)
	print("CLOCKTOWER_BOSS_WIN seconds=%d hits=%d rewinds_interrupted=%d" % [int(fight_time), hits_taken, rewinds_interrupted])
	await get_tree().create_timer(RESULT_DELAY, true, false, true).timeout
	if is_inside_tree() and won:
		_show_result()


func grade() -> String:
	if hits_taken <= 2:
		return "S"
	if hits_taken <= 5:
		return "A"
	if hits_taken <= 9:
		return "B"
	if hits_taken <= 14:
		return "C"
	return "D"


func _show_result() -> void:
	if _result != null:
		return
	Engine.time_scale = 1.0
	_result = ResultPanel.new()
	_result.name = "ClocktowerBossResult"
	_result.result_font = GothicFonts.serif(600)
	_result.summary = {
		"name": BOSS_NAME,
		"grade": grade(),
		"seconds": fight_time,
		"hits": hits_taken,
		"parry": int(style.stats.get("parry", 0)),
		"wall": int(style.stats.get("wall", 0)),
		"yanks": rewinds_interrupted,
		"cores": clock_hand_attacks_used,
		"purple_rifts": rewinds_interrupted,
	}
	_result.restart_requested.connect(_restart_trial)
	add_child(_result)
	get_tree().paused = true


func _on_player_died() -> void:
	phase = Phase.FALLEN
	fallen_frames = 80
	if boss != null and is_instance_valid(boss):
		boss.active = false
	audio.play_die()
	camera.add_shake(12.0 * shake_mul)
	var hp_pct := int(100.0 * boss.hp / maxf(boss.max_hp, 1.0)) if (boss != null and is_instance_valid(boss)) else 0
	hud.banner("倒下了", "母钟守望还剩 %d%% · 马上重来" % hp_pct, 1.4)


func _revive() -> void:
	_restart_trial()


func _restart_trial() -> void:
	if _restart_pending:
		return
	_restart_pending = true
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file.call_deferred(SCENE)


# ---------------------------------------------------------------- 首领三阶段「巨型指针武器」覆层渲染

class _ClockHandWeaponOverlay extends Node2D:
	var stage = null

	func _draw() -> void:
		if stage == null or stage.boss == null or not is_instance_valid(stage.boss):
			return
		var boss: Node2D = stage.boss
		if not boss.is_alive():
			return
		# 二阶段倒流咏唱时，在首领身后画逆转紫金钟盘光环
		if bool(stage.rewind_channel_active):
			var p: float = float(stage.rewind_channel_progress)
			var col := Color(0.82, 0.40, 1.0, 0.85)
			draw_arc(Vector2(0.0, -70.0), 118.0, -PI * 0.5, -PI * 0.5 - TAU * p, 48, col, 6.0)
			draw_arc(Vector2(0.0, -70.0), 94.0, 0.0, TAU, 36, Color(1.0, 0.36, 0.54, 0.55), 2.5)
			for k in 12:
				var a: float = -float(stage.fight_time) * 3.5 + TAU * float(k) / 12.0
				draw_line(Vector2(0.0, -70.0) + Vector2(cos(a), sin(a)) * 84.0, Vector2(0.0, -70.0) + Vector2(cos(a), sin(a)) * 102.0, col, 2.2)

		# 三阶段「拔针裁昼」：首领手持从背景母钟拔下的巨型哥特暗铁绯红指针战戟！
		if not bool(stage.boss_wields_clock_hand):
			return
		var f := float(boss.facing) if int(boss.facing) != 0 else -1.0
		var grip := Vector2(f * 36.0, -78.0)
		var base_angle := -0.45 if f > 0.0 else (PI + 0.45)

		# 根据拔针三式的蓄力/挥斩阶段动态驱动巨型指针角度
		var hs: Dictionary = stage._hand_attack_state
		if not hs.is_empty() and bool(hs.get("active", false)):
			var t := float(hs["t"])
			var w := maxf(float(hs["windup"]), 0.01)
			var k := clampf(t / w, 0.0, 1.0)
			var kind: StringName = hs["kind"]
			if kind == &"hand_sweep":
				if t < w:
					base_angle = lerpf(-0.5, -2.05, k) if f > 0.0 else lerpf(PI + 0.5, PI + 2.05, k)
				else:
					var sk := clampf((t - w) / 0.18, 0.0, 1.0)
					base_angle = lerpf(-2.05, 0.55, sk) if f > 0.0 else lerpf(PI + 2.05, PI - 0.55, sk)
			elif kind == &"hand_thrust":
				base_angle = 0.0 if f > 0.0 else PI
				grip += Vector2(-f * 45.0 * (1.0 - k) if t < w else f * 58.0, 6.0)
			elif kind == &"clock_wheel":
				if t < w:
					base_angle = -PI * 0.5
					grip += Vector2(0.0, -54.0 * k)
				else:
					base_angle = PI * 0.5
					grip += Vector2(0.0, 42.0)
		else:
			base_angle += sin(float(stage.fight_time) * 3.8) * 0.07

		var dir := Vector2(cos(base_angle), sin(base_angle))
		var perp := Vector2(-dir.y, dir.x)
		var blade_len := 258.0
		var tail_len := 64.0
		var hw := 18.0
		var poly := PackedVector2Array([
			grip - dir * tail_len,
			grip - dir * (tail_len * 0.35) + perp * (hw * 0.8),
			grip + dir * (blade_len * 0.25) + perp * hw,
			grip + dir * (blade_len * 0.72) + perp * (hw * 0.45),
			grip + dir * blade_len,
			grip + dir * (blade_len * 0.72) - perp * (hw * 0.45),
			grip + dir * (blade_len * 0.25) - perp * hw,
			grip - dir * (tail_len * 0.35) - perp * (hw * 0.8),
		])
		# 炽红灼光外焰 + 黑铁指针本体 + 银白锋刃 + 猩红核心符纹线
		draw_line(grip - dir * tail_len, grip + dir * (blade_len + 12.0), Color(1.0, 0.22, 0.16, 0.42), 34.0)
		draw_colored_polygon(poly, Color(0.07, 0.06, 0.09, 0.98))
		var loop := poly.duplicate()
		loop.append(poly[0])
		draw_polyline(loop, Color(0.95, 0.78, 0.68, 0.92), 2.4, true)
		draw_line(grip + dir * 16.0, grip + dir * (blade_len * 0.90), Color(1.0, 0.34, 0.22, 0.95), 3.6)
		# 握柄处原母钟轴环
		draw_circle(grip, 22.0, Color(0.10, 0.08, 0.12, 0.98))
		draw_arc(grip, 22.0, 0.0, TAU, 24, Color(1.0, 0.66, 0.36, 0.95), 2.8)
		draw_circle(grip, 9.0, Color(1.0, 0.24, 0.18, 0.96))


# ---------------------------------------------------------------- 场地级时间技能预警与特效画布

class _ClocktowerArenaFx extends Node2D:
	var stage = null

	func _draw() -> void:
		if stage == null:
			return
		# 1. 一阶段「时隙残影斩」预警与延迟斩光
		for e: Dictionary in stage._echo_slashes:
			var ep: Vector2 = e["pos"]
			var fdir: int = int(e["dir"])
			var t := float(e["t"])
			var delay := float(e["delay"])
			if t < delay:
				var k := clampf(t / maxf(delay, 0.01), 0.0, 1.0)
				# 虚影轮廓 + 蓄力斩弧预警
				draw_circle(ep + Vector2(0.0, -70.0), 48.0 * (1.0 - 0.15 * k), Color(0.75, 0.88, 1.0, 0.22 + 0.28 * k))
				draw_arc(ep + Vector2(float(fdir) * 55.0, -70.0), 195.0, -0.7 if fdir > 0 else (PI - 0.7), 0.7 if fdir > 0 else (PI + 0.7), 24, Color(1.0, 0.42, 0.46, 0.35 + 0.55 * k), 3.0 + 4.0 * k)
			else:
				var fade := clampf(1.0 - (t - delay) / maxf(float(e["ttl"]) - delay, 0.01), 0.0, 1.0)
				draw_line(ep + Vector2(0.0, -110.0), ep + Vector2(float(fdir) * 280.0, -35.0), Color(1.0, 0.34, 0.42, fade * 0.92), 14.0 * fade)
				draw_line(ep + Vector2(0.0, -110.0), ep + Vector2(float(fdir) * 280.0, -35.0), Color(1.0, 0.95, 0.90, fade), 4.0 * fade)

		# 2. 三阶段拔针三式红金预警区
		var hs: Dictionary = stage._hand_attack_state
		if not hs.is_empty() and bool(hs.get("active", false)) and stage.boss != null and is_instance_valid(stage.boss):
			var bp: Vector2 = stage.boss.global_position
			var t := float(hs["t"])
			var w := maxf(float(hs["windup"]), 0.01)
			var fdir: int = int(hs["dir"])
			var kind: StringName = hs["kind"]
			if t < w:
				var k := clampf(t / w, 0.0, 1.0)
				match kind:
					&"hand_sweep":
						var rect_x := bp.x - 40.0 if fdir > 0 else bp.x - 415.0
						draw_rect(Rect2(rect_x, bp.y - 165.0, 455.0, 185.0), Color(1.0, 0.18, 0.18, 0.12 + 0.24 * k))
						draw_rect(Rect2(rect_x, bp.y - 165.0, 455.0, 185.0), Color(1.0, 0.48, 0.36, 0.55 + 0.40 * k), false, 2.5)
					&"hand_thrust":
						var tip := bp + Vector2(float(fdir) * 380.0, -68.0)
						draw_line(bp + Vector2(0.0, -68.0), tip, Color(1.0, 0.22, 0.28, 0.35 + 0.55 * k), 26.0 * (1.0 - 0.55 * k) + 6.0)
						draw_line(bp + Vector2(0.0, -68.0), tip, Color(1.0, 0.90, 0.78, 0.85 * k), 3.0)
					&"clock_wheel":
						var gp := Vector2(bp.x, float(stage.floor_y))
						draw_arc(gp, 345.0 * k, 0.0, TAU, 48, Color(1.0, 0.30, 0.20, 0.78), 4.0)
						for spk in 12:
							var a := TAU * float(spk) / 12.0
							draw_line(gp, gp + Vector2(cos(a) * 345.0 * k, sin(a) * 78.0 * k), Color(1.0, 0.62, 0.30, 0.62 * k), 2.5)

		# 3. 分针穿刺遗留血紫时空裂隙带
		for r: Dictionary in stage._temporal_rifts:
			var rp: Vector2 = r["pos"]
			var hw := float(r["half_w"])
			var a := clampf(float(r["ttl"]) / maxf(float(r["max_ttl"]), 0.01), 0.0, 1.0)
			draw_rect(Rect2(rp.x - hw, rp.y - 18.0, hw * 2.0, 36.0), Color(0.76, 0.16, 0.52, 0.28 * a))
			draw_line(Vector2(rp.x - hw, rp.y), Vector2(rp.x + hw, rp.y), Color(1.0, 0.42, 0.86, 0.92 * a), 4.5)

		# 4. 环形冲击波
		for rw: Dictionary in stage._ring_waves:
			var k := clampf(float(rw["t"]) / maxf(float(rw["dur"]), 0.01), 0.0, 1.0)
			var col: Color = rw["col"]
			col.a *= (1.0 - k)
			var rad := lerpf(32.0, float(rw["max_r"]), 1.0 - pow(1.0 - k, 2.4))
			draw_arc(rw["pos"] as Vector2, rad, 0.0, TAU, 56, col, 8.0 * (1.0 - k) + 1.5)
