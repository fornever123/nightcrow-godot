extends "res://scripts/night/rain_street.gd"
## C6 终极原创首领战：【断晷天井 · 斜切巨钟残环】×【司晷 · 错时残影体】
##
## 四大原创核心升级：
##   1. 彻底去蓝去金的 G03 惨白蚀光 × 漆黑玄武岩薄镜 × 冷银生铁极致无彩美学（全屏唯主角刀光独享电光紫）；
##   2. Blender 5.2 Cycles 真三维同源法线/高光贴图 (`CanvasTexture`) + 实时 `PointLight2D` 刀火与拼刀受光 + 左高 `XI` (`y=297`) / 右低 `V` (`y=344`) 不对称罗马字碑立体跳台；
##   3. 双向【时间倒流】硬核动作交互：
##      - 逆晷双斩倒带抽刀（弹反倒带刃触发 1.8s 崩针大硬直）；
##      - 5:59 过去残影锚点（玩家一刀劈碎过去锚点 -> 首领回溯瞬间触发「时间断轨自爆」炸空整管棱壳！）；
##      - 逆时捉影倒拽玩家（将玩家强行倒流回 2 秒前白影，瞬步扯断或借倒拽冲力打出「超音速迎面崩刃」一击碎壳！）；
##      - 登碑悬针逆流拔刺 & 弹针奉还（精准弹反钟针原路钉穿高碑首领胸口，当场将其从罗马石碑轰坠砸地！）。

const BossShade := preload("res://scripts/boss_sample/boss_shade.gd")
const BossBackdrop := preload("res://scripts/boss_sample/boss_backdrop.gd")
const CrimsonClockRig := preload("res://scripts/boss_sample/crimson_clock_rig.gd")
const BossBar := preload("res://scripts/boss_sample/boss_bar.gd")
const Dodge := preload("res://scripts/boss_sample/dodge.gd")
const AirRules := preload("res://scripts/boss_sample/air_rules.gd")
const FrozenHpRig := preload("res://scripts/boss_sample/frozen_hp_rig.gd")
const DeathRewindFx := preload("res://scripts/boss_sample/death_rewind_fx.gd")
const BossResultPanel := preload("res://scripts/boss_sample/boss_result.gd")
const BossFonts := preload("res://scripts/boss_sample/boss_fonts.gd")

const BOSS_NAME := "司辰母钟楼"
const ARENA_TITLE := "钟前校时天廊 · 5:59"
const FIGHT_HALF := 2400.0
const XI_MONUMENT_Y := 223.4
const V_MONUMENT_Y := 286.4
const BALCONY_Y := 223.4
const TOUCH_GAP := 64.0
const RESULT_DELAY := 1.65
const SHELL_BREAK_SLOWMO := 0.15

const VFX_TEX_PATH := "res://assets/image/boss_duanchao/sigui_vfx_atlas.png"

var stage_showcase_only: bool = false
var _bar_layer_ref: CanvasLayer = null

var boss: Node2D = null
var dodge: Node = null
var air_rules: Node = null
var frozen_rig: Node = null
var death_rewind: CanvasLayer = null

var won: bool = false
var fight_time: float = 0.0
var hits_taken: int = 0
var _result: CanvasLayer = null
var _restart_pending: bool = false

var shell_break_slowmo_count: int = 0
var last_slowmo_duration: float = 0.0

var _fx_layer: Node2D = null
var _duel_cam_anchor: Node2D = null
var _cam_focus_boost: float = 0.0
var _vfx_tex: Texture2D = null

var _early_note_at: float = -99.0
var _armor_note_at: float = -99.0
var _backstab_note_at: float = -99.0
var _nail_note_shown: bool = false
var _kill_yanks: int = 0
var _kill_cores: int = 0
var _kill_purple_rifts: int = 0
var _slowmo_token: int = 0


func _init() -> void:
	super()
	arena_half = FIGHT_HALF
	first_arena_x = 3200.0
	arena_spacing = 7200.0
	trigger_before = FIGHT_HALF + 800.0
	round_waves = [[{"label": ARENA_TITLE, "spawns": [], "max_attackers": 1}]]
	stage_title = PackedStringArray([BOSS_NAME, ARENA_TITLE])
	layout = {
		"arenaHalf": FIGHT_HALF,
		"arenaSpacing": 7200.0,
		"sections": [
			{
				"name": ARENA_TITLE,
				"blocks": [],
				"platforms": [
					[-2383.0, -1836.5, XI_MONUMENT_Y, "slab", {"ch1_hidden": true}],
					[-2220.0, -2050.0, 402.7, "slab", {"ch1_hidden": true}],
					[1813.0, 2398.0, V_MONUMENT_Y, "slab", {"ch1_hidden": true}],
				],
				"slopes": [
					[-2050.0, 402.7, -1714.7, 580.0, "stone", {"ch1_hidden": true}],
					[1409.4, 580.0, 1813.0, V_MONUMENT_Y, "stone", {"ch1_hidden": true}],
				],
				"spawns": [[240.0, 580.0], [-240.0, 580.0]],
			},
		],
	}


func _make_backdrop() -> Node2D:
	var b := BossBackdrop.new()
	b.cam_ref = _cam_y_for(580.0)
	return b


func _stage_ready() -> void:
	super()
	if ResourceLoader.exists(VFX_TEX_PATH):
		_vfx_tex = load(VFX_TEX_PATH) as Texture2D

	var custom_font: Font = BossFonts.chinese_serif()
	if hud != null and custom_font != null:
		hud._font = custom_font
		hud.wave_text = ""
	if _arrows != null:
		_arrows.visible = false

	if post != null:
		# 0% 假蓝调色与暖光污染，保持纯正黑白蚀光 + 主角独享电光紫高锐度对比！
		post.mat.set_shader_parameter("bloom_amt", 0.42)
		post.mat.set_shader_parameter("bloom_th", 0.62)
		post.mat.set_shader_parameter("rays_amt", 0.14)
		post.mat.set_shader_parameter("vig_bottom", 0.08)

	for s in get_tree().get_nodes_in_group(&"shade"):
		if is_instance_valid(s):
			s.free()
	if encounter != null and "shades" in encounter:
		encounter.shades.clear()

	if not InputMap.has_action(Dodge.ACTION):
		InputMap.add_action(Dodge.ACTION)
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_SHIFT
		InputMap.action_add_event(Dodge.ACTION, ev)
		var b_btn := InputEventJoypadButton.new()
		b_btn.device = -1
		b_btn.button_index = JOY_BUTTON_B
		InputMap.action_add_event(Dodge.ACTION, b_btn)

	dodge = Dodge.new()
	dodge.name = "Dodge"
	dodge.player = player
	add_child(dodge)
	dodge.heavy_armed.connect(_on_heavy_armed)
	dodge.heavy_landed.connect(_on_heavy_landed)

	air_rules = AirRules.new()
	air_rules.name = "AirRules"
	air_rules.player = player
	air_rules.dodge = dodge
	add_child(air_rules)
	air_rules.judged.connect(_on_air_judged)
	air_rules.whiffed.connect(_on_air_whiffed)
	air_rules.jump_given.connect(_on_jump_given)
	air_rules.jump_denied.connect(_on_jump_denied)

	apply_control_scheme()

	_fx_layer = Node2D.new()
	_fx_layer.name = "BossStageFx"
	_fx_layer.z_index = 6
	add_child(_fx_layer)

	_duel_cam_anchor = Node2D.new()
	_duel_cam_anchor.name = "DuelCamAnchor"
	add_child(_duel_cam_anchor)

	_setup_duel_arena()
	var px := arena_center - 320.0
	player.global_position = Vector2(px, floor_y - player.foot_offset)
	_spawn_boss(arena_center + 270.0)

	_duel_cam_anchor.global_position = Vector2(arena_center, _cam_y_for(floor_y))
	camera.follow_target = _duel_cam_anchor
	camera.follow_smoothing = 9.5
	camera.lock_y = _cam_y_for(floor_y)
	camera.global_position = _duel_cam_anchor.global_position

	var bar_layer := CanvasLayer.new()
	bar_layer.name = "BossBarLayer"
	bar_layer.layer = 10
	add_child(bar_layer)
	_bar_layer_ref = bar_layer
	var bar: Control = BossBar.new()
	bar.name = "BossBar"
	bar.stage = self
	bar_layer.add_child(bar)

	frozen_rig = FrozenHpRig.new()
	frozen_rig.name = "FrozenHpRig"
	bar_layer.add_child(frozen_rig)
	frozen_rig.setup(self, player, dodge)

	death_rewind = DeathRewindFx.new()
	death_rewind.name = "DeathRewindFx"
	death_rewind.rewind_completed.connect(_on_death_rewind_completed)
	add_child(death_rewind)

	var is_headless := DisplayServer.get_name() == "headless"
	var want_showcase_only := OS.get_cmdline_user_args().has("--stage-showcase")
	if not is_headless and want_showcase_only and get_tree().current_scene == self:
		set_stage_showcase_mode(true)
		player.global_position = Vector2(arena_center - 180.0, floor_y - player.foot_offset)
		_duel_cam_anchor.global_position = Vector2(arena_center - 90.0, _cam_y_for(floor_y))
		camera.global_position = _duel_cam_anchor.global_position
		hud.banner("司辰母钟楼  ·  5 : 59", "钟前校时天廊  |  按键 1~5 切换红钟五重动效  |  F6 唤出首领", 2.8)
	else:
		boss.begin_intro()
		_play_aaa_sfx("draw", 0.0, -2.0)
		hud.banner(BOSS_NAME, ARENA_TITLE, 2.0)
	print("BOSS_SAMPLE_READY")


func set_stage_showcase_mode(on: bool) -> void:
	stage_showcase_only = on
	if boss != null and is_instance_valid(boss):
		if on:
			boss.skip_intro()
			boss.active = false
			boss.visible = false
			boss.process_mode = Node.PROCESS_MODE_DISABLED
			boss.position = Vector2(arena_center + 9999.0, floor_y - boss.half_h)
			if _fx_layer != null:
				for c in _fx_layer.get_children():
					c.free()
		else:
			boss.process_mode = Node.PROCESS_MODE_INHERIT
			boss.visible = true
			boss.position = Vector2(arena_center + 280.0, floor_y - boss.half_h)
			boss.active = true
	if _bar_layer_ref != null:
		_bar_layer_ref.visible = not on


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var kev := event as InputEventKey
	if not kev.pressed or kev.echo:
		return
	if backdrop == null or backdrop.clock_rig == null:
		return
	var rig = backdrop.clock_rig
	match kev.keycode:
		KEY_1:
			backdrop.reset_phase()
			rig.trigger_manual_heartbeat_burst()
			camera.add_shake(7.0)
			_boss_callout("5:59  超载心跳 · 擒纵死卡回弹", Color(0.96, 0.34, 0.28), 30)
		KEY_2:
			backdrop.phase2_cracked = false
			rig.crack_amt = 0.0
			rig.shatter_amt = 0.0
			backdrop.set_rewind_visual(1.0)
			camera.add_shake(12.0)
			_play_aaa_sfx("draw", -0.18, -1.5)
			_boss_callout("时间倒流 · 炽红狂转与百雨倒升", Color(1.0, 0.42, 0.30), 32)
		KEY_3:
			backdrop.set_rewind_visual(0.0)
			backdrop.trigger_phase2_shatter()
			camera.add_shake(18.0)
			_play_aaa_sfx("deflect", -0.24, -1.0)
			_boss_callout("朱红钟窗崩裂 · 二十四残片悬停", Color(1.0, 0.30, 0.22), 32)
		KEY_4:
			backdrop.trigger_phase2_shatter()
			rig.shatter_amt = 1.0
			backdrop.set_rewind_visual(1.0)
			camera.add_shake(16.0)
			_play_aaa_sfx("draw", 0.12, -1.0)
			_boss_callout("逆时重拼 · 碎钟螺旋倒吸归位", Color(1.0, 0.52, 0.34), 32)
		KEY_5:
			backdrop.trigger_victory_dawn()
			camera.add_shake(22.0)
			_play_aaa_sfx("deflect", 0.28, -0.5)
			_boss_callout("六点整 · 一剑贯通破晓", Color(0.84, 0.92, 1.0), 34)
		KEY_F6:
			set_stage_showcase_mode(not stage_showcase_only)


func apply_control_scheme() -> void:
	super()
	# 确保 sample_dodge 仅使用 Shift / 手柄 B（LB 专用于按住时缓搓招）
	if InputMap.has_action(Dodge.ACTION):
		var stale_lb: Array[InputEvent] = []
		var has_b := false
		for ev in InputMap.action_get_events(Dodge.ACTION):
			if ev is InputEventJoypadButton:
				var jb := ev as InputEventJoypadButton
				if jb.button_index == JOY_BUTTON_LEFT_SHOULDER:
					stale_lb.append(ev)
				elif jb.button_index == JOY_BUTTON_B:
					has_b = true
		for ev in stale_lb:
			InputMap.action_erase_event(Dodge.ACTION, ev)
		if not has_b:
			var b_btn := InputEventJoypadButton.new()
			b_btn.device = -1
			b_btn.button_index = JOY_BUTTON_B
			InputMap.action_add_event(Dodge.ACTION, b_btn)
	if hud != null:
		hud.help_text = ""
		hud.queue_redraw()


func _queue_hint(_id: StringName, _text: String, _seconds: float, _urgent: bool = false) -> void:
	pass


func _play_aaa_sfx(bank_key: String, pitch_off: float = 0.0, db_off: float = 0.0, fallback_clip: StringName = &"parry") -> void:
	if audio == null:
		return
	if audio.has_method(&"_play_bank") and bool(audio.call(&"_play_bank", bank_key, pitch_off, db_off)):
		return
	audio._play_clip(fallback_clip, pitch_off, db_off)


func arena_name() -> String:
	if won:
		return "钟前校时天廊 · 6:00"
	return "钟前校时天廊 · 朱红崩裂" if (boss != null and is_instance_valid(boss) and boss.is_phase2) else ARENA_TITLE


func _setup_duel_arena() -> void:
	encounter_index = 0
	arena_center = _center_of(0)
	if terrain != null:
		terrain.sections = layout.get("sections", [])
		for c in terrain.get_children():
			c.free()
		terrain._built.clear()
		terrain.platforms.clear()
		terrain.blocks.clear()
		terrain.ensure_section(0, arena_center)
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
	camera.arena_min = Vector2(left - 60.0, _cam_y_for(floor_y) - 620.0)
	camera.arena_max = Vector2(right + 60.0, _cam_y_for(floor_y) + 460.0)
	phase = Phase.FIGHT
	seal_alpha = 0.0
	if backdrop != null:
		backdrop.cam_ref = _cam_y_for(floor_y)
		backdrop.configure_duel_arena(arena_center, FIGHT_HALF)
	if post != null:
		post.mat.set_shader_parameter("rays_amt", 0.20)
	if boss != null and is_instance_valid(boss):
		boss.arena_left = left
		boss.arena_right = right
		boss.release_nail()


func _update_duel_camera(delta: float) -> void:
	if camera == null or _duel_cam_anchor == null or player == null or not is_instance_valid(player):
		return
	if ult_fx != null and "active" in ult_fx and bool(ult_fx.active):
		return
	if camera.follow_target != _duel_cam_anchor:
		camera.follow_target = _duel_cam_anchor

	_cam_focus_boost = move_toward(_cam_focus_boost, 0.0, delta * 0.14)

	var px: float = player.global_position.x
	var py: float = player.global_position.y + float(player.foot_offset)
	var mid_x := px
	var highest_feet := py
	var want_z := 0.65

	if not stage_showcase_only and boss != null and is_instance_valid(boss) and boss.visible:
		var bx: float = boss.global_position.x
		var by: float = float(boss.feet_y())
		mid_x = lerpf(px, bx, 0.42)
		highest_feet = minf(py, by)
		var sep := absf(px - bx)
		var close_k := 1.0 - clampf((sep - 220.0) / 760.0, 0.0, 1.0)
		# 对标商业动作游戏近景压迫感：近身对峙推近至 0.84x，拉开远距平滑回退至 0.72x
		want_z = lerpf(0.72, 0.84, close_k) + _cam_focus_boost
		if boss._string_id == &"horizon_cut":
			want_z = 0.71

	# 4800u 全宽平滑取景：允许镜头横跨左翼登顶阶(S1)、钟前主桥(S2)至右翼断链台(S3)，同时绝不拍穿天廊左右外边界
	mid_x = clampf(mid_x, arena_center - 1520.0, arena_center + 1520.0)

	var high_ratio := clampf((floor_y - highest_feet - 60.0) / 280.0, 0.0, 1.0)
	var zoom_lift := maxf(want_z - 0.65, 0.0) * 320.0
	var base_cy := _cam_y_for(floor_y) + zoom_lift - high_ratio * 115.0
	_duel_cam_anchor.global_position = Vector2(mid_x, base_cy)
	camera.lock_y = base_cy

	want_z = clampf(want_z - high_ratio * 0.04, 0.64, 0.88)
	var next_z := move_toward(camera.zoom.x, want_z, delta * 0.42)
	camera.zoom = Vector2(next_z, next_z)
	camera.shake_world_scale = 1.0 / next_z


func _spawn_boss(x: float) -> void:
	boss = Node2D.new()
	boss.name = "BossSiGui"
	boss.set_script(BossShade)
	boss.setup(Shade.Kind.BRUTE, player, floor_y, 1.0)
	boss.arena_left = seal_x.x
	boss.arena_right = seal_x.y
	boss.max_attackers = 1
	boss.terrain = terrain
	boss.position = Vector2(x, floor_y - boss.half_h)
	boss.facing = -1
	boss.dodge = dodge
	boss.air_rules = air_rules
	add_child(boss)
	_on_shade_spawned(boss)
	boss.apply_boss_stats(floor_y, 1.0)
	boss.position = Vector2(x, floor_y - boss.half_h)

	boss.wall_slam.connect(_on_boss_pillar_slam)
	boss.clashed.connect(_on_clashed)
	boss.clash_canceled.connect(_on_clash_canceled)
	boss.dodged_through.connect(_on_dodged_through)
	boss.armor_held.connect(_on_armor_held)
	boss.shell_damaged.connect(_on_shell_damaged)
	boss.shell_shattered.connect(_on_shell_shattered)
	boss.shell_reforged_wave.connect(_on_shell_reforged_wave)
	boss.volley_flung.connect(_on_volley_flung)
	boss.pursuit_slashed.connect(_on_pursuit_slashed)
	boss.armor_severed.connect(_on_armor_severed)
	boss.phase2_started.connect(_on_phase2_started)
	boss.rift_opened.connect(_on_rift_opened)
	boss.rift_dyed_exploded.connect(_on_rift_dyed_exploded)
	boss.apex_reached.connect(_on_boss_apex)
	boss.nail_aimed.connect(_on_nail_aimed)
	boss.nail_landed.connect(_on_nail_landed)
	boss.tether_slam.connect(_on_tether_slam)
	boss.horizon_telegraphed.connect(_on_horizon_telegraphed)
	boss.horizon_slashed.connect(_on_horizon_slashed)
	boss.rain_needles_summoned.connect(_on_rain_needles_summoned)
	boss.rain_needle_cut.connect(_on_rain_needle_cut)
	boss.needle_reflected_hit.connect(_on_needle_reflected_hit)
	boss.water_wave_spawned.connect(_on_water_wave_spawned)
	boss.spire_perched.connect(_on_spire_perched)
	boss.anchor_spawned.connect(_on_anchor_spawned)
	boss.anchor_derailed.connect(_on_anchor_derailed)
	boss.player_snare_stamped.connect(_on_player_snare_stamped)
	boss.player_snare_severed.connect(_on_player_snare_severed)
	boss.supersonic_rewind_parried.connect(_on_supersonic_rewind_parried)
	boss.intro_slammed.connect(_on_intro_slammed)
	boss.intro_done.connect(_on_intro_done)
	boss.died.connect(_on_boss_killed)


func _physics_process(delta: float) -> void:
	if boss != null and is_instance_valid(boss) and boss.intro_frames > 0:
		var saved: float = fight_time
		super(delta)
		fight_time = saved
		return
	if phase == Phase.FIGHT and not won:
		fight_time += delta
	super(delta)
	_check_player_hits_chrono_anchor()
	_separate_touch()


func _check_player_hits_chrono_anchor() -> void:
	if boss == null or not is_instance_valid(boss) or player == null or not is_instance_valid(player):
		return
	if not boss.chrono_anchor_active:
		return
	# 实战生成前 14 帧给予视觉显形与冲出保护期，避免贴身 0 帧未见残影即误爆
	if boss.active and (boss.ANCHOR_HOLD_FRAMES - boss.chrono_anchor_timer) < 14:
		return
	var is_guard_or_parry := (player.has_method(&"is_guarding") and bool(player.call(&"is_guarding"))) or (player.has_method(&"is_parrying") and bool(player.call(&"is_parrying")))
	var p_attacking := int(player.get(&"state")) == int(player.State.ATTACK) and not is_guard_or_parry
	var p_dodging := (dodge != null and bool(dodge.call(&"counts_as_dodge"))) or (player.has_method(&"is_short_dashing") and bool(player.call(&"is_short_dashing")))
	if not p_attacking and not p_dodging:
		return
	var pf := float(player.facing)
	var anchor_ground := Vector2(boss.chrono_anchor_pos.x, player.global_position.y)
	var slash_pt := player.global_position + Vector2(pf * 62.0, 0.0)
	if absf(slash_pt.x - anchor_ground.x) <= 135.0 and absf((player.global_position.y + player.foot_offset) - boss.chrono_anchor_pos.y) <= 115.0:
		boss.shatter_chrono_anchor(player)


func _player_sword_slash_rain() -> void:
	if backdrop == null or not backdrop.has_method(&"slash_rain_at"):
		return
	if player != null and is_instance_valid(player) and int(player.get(&"state")) == int(player.State.ATTACK):
		var dir := Vector2(float(player.facing), -0.25).normalized()
		backdrop.slash_rain_at(player.global_position + Vector2(float(player.facing) * 75.0, -52.0), 185.0, dir)


func _separate_touch() -> void:
	if stage_showcase_only or boss == null or not is_instance_valid(boss) or not boss.visible or boss.state == Shade.State.DEAD:
		return
	if boss.intro_frames > 0 or player == null or player.state == player.State.DEAD:
		return
	if (dodge != null and dodge.is_dodging()) or (player.has_method(&"is_short_dashing") and bool(player.call(&"is_short_dashing"))):
		return
	if absf((player.global_position.y + player.foot_offset) - boss.feet_y()) > 84.0:
		return
	var dx: float = player.global_position.x - boss.global_position.x
	var need: float = boss.half_w + TOUCH_GAP * 0.5
	if absf(dx) >= need:
		return
	var side := 1.0 if dx > 0.0 else (-1.0 if dx < 0.0 else -float(boss.facing))
	var want: float = boss.global_position.x + side * need
	if want < seal_x.x + 30.0 or want > seal_x.y - 30.0:
		boss.position.x = player.global_position.x - side * need
	else:
		player.global_position.x = want


func _update_crimson_clock_char_light() -> void:
	if light_mat == null or backdrop == null or backdrop.clock_rig == null or player == null or not is_instance_valid(player):
		return
	var rig = backdrop.clock_rig
	var p_pos := player.global_position + Vector2(0.0, player.foot_offset - 68.0)
	var lamp_vec: Vector3 = _lamp_at(p_pos)
	var clock_pos: Vector2 = rig.global_position
	var to_clock := (clock_pos - p_pos)
	var dist_x := absf(p_pos.x - arena_center)
	var clock_zone := 1.0 - clampf((dist_x - 620.0) / 1150.0, 0.0, 1.0)
	var crim_strength := clock_zone * (0.42 + 0.44 * float(rig.pulse_val) + 0.36 * float(rig.rewind_amt)) * (1.0 - float(rig.dawn_calm) * 0.85)

	if lamp_vec.x > crim_strength * 0.85:
		light_mat.set_shader_parameter("warm_col", Vector3(1.0, 0.82, 0.52))
	else:
		var c_dir := to_clock.normalized() if to_clock.length() > 1.0 else Vector2(0.0, -1.0)
		light_mat.set_shader_parameter("warm_col", Vector3(0.96, 0.22, 0.16))
		light_mat.set_shader_parameter("warm", clampf(crim_strength, 0.0, 0.92))
		light_mat.set_shader_parameter("warm_dir", c_dir)


func _process(delta: float) -> void:
	super(delta)
	_player_sword_slash_rain()
	_update_crimson_clock_char_light()
	if backdrop != null:
		backdrop.cam_ref = _cam_y_for(floor_y)
	_update_duel_camera(delta)
	if seal_alpha != 0.0:
		seal_alpha = 0.0
		queue_redraw()
	var p_atk := player != null and is_instance_valid(player) and int(player.get(&"state")) == int(player.State.ATTACK)
	var p_pos := player.global_position if (player != null and is_instance_valid(player)) else Vector2.ZERO
	if backdrop != null:
		if not stage_showcase_only and boss != null and is_instance_valid(boss):
			backdrop.boss_hp_ratio = clampf(float(boss.hp) / maxf(float(boss.max_hp), 1.0), 0.0, 1.0)
			backdrop.update_combat_lights(p_pos, p_atk, boss.global_position, boss.is_rewinding_visual())
			var red_dim := 0.0
			if (boss.state == Shade.State.WINDUP or boss.state == Shade.State.STRIKE) and boss.blade_kind() in [boss.Blade.RED, boss.Blade.RIFT]:
				red_dim = boss.telegraph()
			elif boss.rift_state == boss.Rift.ACTIVE:
				red_dim = 0.45
			backdrop.set_boss_red_telegraph(red_dim)
			if backdrop.has_method(&"set_eclipse_dim"):
				backdrop.set_eclipse_dim(boss.eclipse_want)
		else:
			backdrop.update_combat_lights(p_pos, p_atk, Vector2(arena_center, floor_y), false)
	if hud != null:
		hud.wave_text = ""


func _ground_slam_at(pt: Vector2, power: float) -> void:
	if _fx_layer == null:
		return
	var support: float = float(terrain.support_y(pt.x, pt.y)) if terrain != null else floor_y
	var slam := _GroundShockFx.new()
	slam.setup(Vector2(pt.x, support), power)
	_fx_layer.add_child(slam)


func _spawn_prism_shatter_burst(pt: Vector2) -> void:
	if _fx_layer == null or _vfx_tex == null:
		return
	var burst := _PrismBurstFx.new()
	burst.setup(pt, _vfx_tex)
	_fx_layer.add_child(burst)


func _boss_callout(text: String, col: Color, sz: int = 38) -> void:
	if hud == null:
		return
	if "_callouts" in hud:
		hud._callouts.clear()
	hud.callout(text, col, sz)


# ---------------------------------------------------------------- 战斗与双向时间倒流反馈信号响应

func _on_shell_damaged(amount: float, _remain: float, is_backstab: bool, point: Vector2) -> void:
	if is_backstab and fight_time - _backstab_note_at > 0.45:
		_backstab_note_at = fight_time
		fx.spawn_text(point + Vector2(0.0, -150.0), "背刺 -%d" % int(round(amount)))
		_play_aaa_sfx("deflect", 0.18, -3.5)


func _on_shell_shattered(point: Vector2) -> void:
	shell_break_slowmo_count += 1
	last_slowmo_duration = SHELL_BREAK_SLOWMO
	_cam_focus_boost = 0.048
	style.add_event(&"parry")
	_ground_slam_at(point, 0.95)
	_spawn_prism_shatter_burst(point + Vector2(0.0, -88.0))
	if backdrop != null:
		backdrop.pulse_normal_light(point + Vector2(0.0, -90.0), Color(0.95, 0.98, 1.0), 2.4, 6.2)
	fx.spawn_text(point + Vector2(0.0, -175.0), "碎壳！")
	if boss == null or boss.rift_state != boss.Rift.PURPLE:
		_boss_callout("驻时碎壳！", Color("eef4ff"), 48)
	camera.add_shake(22.0 * shake_mul)
	_play_aaa_sfx("guard_break", 0.0, 0.0)
	audio.play_slam(0.82)
	_spawn_ring_fx(point, Color(0.95, 0.97, 1.0, 0.95), 270.0, 0.28)
	_trigger_shell_break_slowmo()


func _trigger_shell_break_slowmo() -> void:
	if won:
		return
	_slowmo_token += 1
	var my_token := _slowmo_token
	Engine.time_scale = 0.22
	await get_tree().create_timer(SHELL_BREAK_SLOWMO, true, false, true).timeout
	if is_inside_tree() and _slowmo_token == my_token and not won:
		Engine.time_scale = 1.0


func _on_shell_reforged_wave(point: Vector2) -> void:
	_ground_slam_at(Vector2(point.x, floor_y), 1.1)
	_spawn_ring_fx(point, Color(0.94, 0.96, 1.0, 0.92), 340.0, 0.34)
	if backdrop != null:
		backdrop.pulse_normal_light(point, Color(0.92, 0.94, 1.0), 1.8, 5.5)
	_boss_callout("棱壳逆流重铸！", Color("eef2f8"), 38)
	camera.add_shake(18.0 * shake_mul)
	audio.play_slam(0.75)


func _on_anchor_spawned(pos: Vector2) -> void:
	_spawn_ring_fx(pos, Color(0.92, 0.95, 1.0, 0.88), 165.0, 0.26)
	if backdrop != null:
		backdrop.pulse_normal_light(pos, Color(0.90, 0.94, 1.0), 1.4, 4.0)
	_boss_callout("过去锚点 · 斩碎它！", Color("f0f4ff"), 34)


func _on_anchor_derailed(pos: Vector2) -> void:
	_cam_focus_boost = 0.055
	style.add_event(&"parry")
	_spawn_prism_shatter_burst(pos)
	_spawn_ring_fx(pos, Color(0.82, 0.45, 1.0, 0.96), 340.0, 0.34)
	if backdrop != null:
		backdrop.pulse_normal_light(pos, Color(0.78, 0.38, 1.0), 2.6, 6.8)
	fx.spawn_text(pos + Vector2(0.0, -140.0), "断轨自爆！", 0.0, true)
	_boss_callout("时间断轨 · 全壳崩碎！", Color("d896ff"), 48)
	camera.add_shake(26.0 * shake_mul)
	_play_aaa_sfx("guard_break", 0.08, 1.0)


func _on_player_snare_stamped(pos: Vector2) -> void:
	_spawn_ring_fx(pos + Vector2(0.0, -45.0), Color(0.94, 0.96, 1.0, 0.85), 140.0, 0.24)
	_boss_callout("时痕锁位 · 准备瞬步或迎面弹刀！", Color("e8eeff"), 32)
	_play_aaa_sfx("draw", 0.22, -2.5)


func _on_player_snare_severed(pos: Vector2) -> void:
	style.add_event(&"parry")
	_spawn_ring_fx(pos + Vector2(0.0, -48.0), Color(0.72, 0.35, 1.0, 0.92), 185.0, 0.22)
	fx.spawn_text(pos + Vector2(0.0, -135.0), "扯断时痕！")
	_play_aaa_sfx("deflect", 0.24, -1.5)


func _on_supersonic_rewind_parried(pos: Vector2) -> void:
	_cam_focus_boost = 0.06
	style.add_event(&"parry")
	if frozen_rig != null:
		frozen_rig.rally_full_on_parry()
	_spawn_prism_shatter_burst(pos)
	_spawn_ring_fx(pos, Color(1.0, 1.0, 1.0, 0.98), 380.0, 0.32)
	if backdrop != null:
		backdrop.pulse_normal_light(pos, Color(1.0, 1.0, 1.0), 2.8, 7.5)
	fx.spawn_text(pos + Vector2(0.0, -165.0), "超音速崩刃！", 0.0, true)
	_boss_callout("超音速迎面崩刃！", Color("ffffff"), 50)
	camera.add_shake(28.0 * shake_mul)
	_play_aaa_sfx("guard_break", 0.12, 1.5)


func _on_needle_reflected_hit(pos: Vector2, knocked_off_monument: bool) -> void:
	style.add_event(&"parry")
	if frozen_rig != null:
		frozen_rig.rally_full_on_parry()
	if player != null and is_instance_valid(player) and player.has_method(&"refund_shadow"):
		player.call(&"refund_shadow", 1)
	_spawn_ring_fx(pos, Color(0.96, 0.98, 1.0, 0.94), 220.0, 0.26)
	if backdrop != null:
		backdrop.pulse_normal_light(pos, Color(0.95, 0.98, 1.0), 2.0, 5.2)
	if knocked_off_monument:
		_cam_focus_boost = 0.045
		fx.spawn_text(pos + Vector2(0.0, -150.0), "弹针坠碑！", 0.0, true)
		_boss_callout("弹针奉还 · 轰下石碑！", Color("ffffff"), 44)
		camera.add_shake(22.0 * shake_mul)
		_play_aaa_sfx("guard_break", 0.15, 0.5)
	else:
		fx.spawn_text(pos + Vector2(0.0, -120.0), "奉还！")
		_play_aaa_sfx("deflect", 0.20, -1.0)


func _on_volley_flung(volley: int, _speed: float) -> void:
	camera.add_shake((13.0 + float(volley) * 3.0) * shake_mul, Vector2(player.facing, -0.15))
	_play_aaa_sfx("deflect", 0.08 + float(volley) * 0.05, -2.0)


func _on_pursuit_slashed(point: Vector2, count: int) -> void:
	style.add_event(&"parry")
	fx.spawn_text(point + Vector2(0.0, -155.0), "追斩 ×%d" % count)
	camera.add_shake(12.0 * shake_mul)
	_play_aaa_sfx("deflect", 0.14 + float(mini(count, 4)) * 0.05, -2.0)


func _on_armor_severed(point: Vector2, total_cores: int) -> void:
	style.add_event(&"wall")
	_cam_focus_boost = 0.045
	_spawn_prism_shatter_burst(point + Vector2(0.0, -70.0))
	fx.spawn_text(point + Vector2(0.0, -195.0), "断壳爆核 +12%攻", 0.0, true)
	_boss_callout("断壳爆核！攻击永久提升（×%d）" % total_cores, Color("ffffff"), 44)
	_spawn_ring_fx(point, Color(0.96, 0.98, 1.0, 0.95), 310.0, 0.36)
	camera.add_shake(25.0 * shake_mul)
	_play_aaa_sfx("guard_break", 0.08, 0.5)


func _on_phase2_started() -> void:
	if backdrop != null and backdrop.has_method(&"trigger_phase2_shatter"):
		backdrop.trigger_phase2_shatter()
		if backdrop.has_method(&"notify_boss_clock_cue"):
			backdrop.notify_boss_clock_cue("burst", boss.global_position, 1.55)
	hud.banner("五点五十九  ·  逆时失序", "巨钟碎裂 · 雨幕倒流 · 逆序三连开启", 1.75)
	_spawn_ring_fx(boss.global_position + Vector2(0.0, -80.0), Color(0.96, 0.32, 0.28, 0.95), 420.0, 0.42)
	camera.add_shake(28.0 * shake_mul)
	_play_aaa_sfx("guard_break", -0.12, 1.0)
	audio.play_slam(0.95)


func _on_rift_opened(point: Vector2) -> void:
	_spawn_ring_fx(point, Color(0.94, 0.24, 0.20, 0.88), 185.0, 0.26)
	if backdrop != null:
		backdrop.pulse_normal_light(point, Color(0.96, 0.24, 0.20), 1.9, 5.2)
		if backdrop.has_method(&"notify_boss_clock_cue"):
			backdrop.notify_boss_clock_cue("windup", point, 1.25)
	_boss_callout("逆时裂隙 · 重斩染紫！", Color("ff584c"), 38)


func _on_rift_dyed_exploded(point: Vector2, damage: float) -> void:
	style.add_event(&"parry")
	style.add_event(&"wall")
	_cam_focus_boost = 0.055
	fx.spawn_text(point + Vector2(0.0, -150.0), "紫裂逆爆", damage, true)
	_boss_callout("染紫逆爆！", Color("c878ff"), 50)
	_spawn_ring_fx(point, Color(0.72, 0.30, 1.0, 0.96), 370.0, 0.38)
	if backdrop != null:
		backdrop.pulse_normal_light(point, Color(0.76, 0.32, 1.0), 2.8, 7.2)
		if backdrop.has_method(&"notify_boss_clock_cue"):
			backdrop.notify_boss_clock_cue("burst", point, 1.35)
		if backdrop.has_method(&"slash_rain_at"):
			backdrop.slash_rain_at(point, 480.0, Vector2.UP)
	camera.add_shake(28.0 * shake_mul)
	_play_aaa_sfx("guard_break", 0.16, 1.0)
	audio.play_slam(0.95)


func _on_horizon_telegraphed(_from_x: float, _to_x: float) -> void:
	if backdrop != null and boss != null and backdrop.has_method(&"notify_boss_clock_cue"):
		backdrop.notify_boss_clock_cue("windup", boss.global_position, 1.30)
	_boss_callout("断晷一线 · 看剑星弹刀！", Color("f2f6ff"), 38)
	_play_aaa_sfx("draw", -0.06, 0.0)


func _on_horizon_slashed(from_x: float, to_x: float) -> void:
	var mid_x := (from_x + to_x) * 0.5
	if backdrop != null:
		backdrop.pulse_normal_light(Vector2(mid_x, floor_y - 140.0), Color(0.96, 0.98, 1.0), 2.0, 6.5)
		if backdrop.has_method(&"notify_boss_clock_cue"):
			backdrop.notify_boss_clock_cue("impact", Vector2(mid_x, floor_y - 140.0), 1.40)
		if backdrop.has_method(&"slash_rain_at"):
			backdrop.slash_rain_at(Vector2(mid_x, floor_y - 160.0), 620.0, Vector2(signf(to_x - from_x), -0.3))
	camera.add_shake(19.0 * shake_mul, Vector2(1.0, 0.0))
	_play_aaa_sfx("deflect", 0.22, -0.5)


func _on_rain_needles_summoned(_count: int) -> void:
	if backdrop != null and boss != null and backdrop.has_method(&"notify_boss_clock_cue"):
		backdrop.notify_boss_clock_cue("windup", boss.global_position, 1.15)
	_boss_callout("坠针逆流 · 弹针奉还！", Color("eef4ff"), 34)
	_play_aaa_sfx("draw", 0.18, -2.0)


func _on_rain_needle_cut(point: Vector2, _total_cut: int) -> void:
	_spawn_ring_fx(point, Color(0.96, 0.98, 1.0, 0.88), 76.0, 0.16)
	_play_aaa_sfx("deflect", 0.28, -3.5)


func _on_water_wave_spawned(pos: Vector2, dir: int) -> void:
	_ground_slam_at(pos, 0.65)
	if backdrop != null and backdrop.has_method(&"slash_rain_at"):
		backdrop.slash_rain_at(pos + Vector2(0.0, -90.0), 240.0, Vector2(float(dir), -0.4))
	camera.add_shake(12.0 * shake_mul)


func _on_spire_perched(side: int, perch_pos: Vector2) -> void:
	_spawn_ring_fx(perch_pos + Vector2(0.0, 40.0), Color(0.94, 0.96, 1.0, 0.82), 150.0, 0.22)
	var label := "登 XI 高碑！" if side < 0 else "登 V 石碑！"
	_boss_callout(label, Color("eef4ff"), 36)
	_play_aaa_sfx("draw", 0.12, -1.5)


func _on_boss_pillar_slam(_impact_or_side: float, damage: float, point: Vector2) -> void:
	var side: int = -1 if point.x < arena_center else 1
	style.add_event(&"wall")
	_cam_focus_boost = 0.038
	fx.spawn_text(point + Vector2(float(-side) * 40.0, -140.0), "撞碑", damage, true)
	_ground_slam_at(Vector2(point.x, floor_y), 0.78)
	_boss_callout("轰撞字碑！", Color("ffffff"), 42)
	camera.add_shake(23.0 * shake_mul, Vector2(side, 0))
	audio.play_slam(0.92)
	_play_aaa_sfx("guard_break", -0.05, -1.5)
	if backdrop != null and backdrop.has_method(&"notify_pillar_impact"):
		backdrop.notify_pillar_impact(side, clampf(damage / 95.0, 0.65, 1.7))
	if boss != null and is_instance_valid(boss):
		boss.reward_air_control(3)
	if player.bonus_air_jumps < player.air_jump_refund_max:
		player.bonus_air_jumps += 1
		player.air_jump_refunded.emit(player.bonus_air_jumps)


func _on_boss_apex(point: Vector2) -> void:
	fx.spawn_text(point, "顶")


func _on_clashed(n: int, is_final: bool) -> void:
	style.add_event(&"parry")
	_cam_focus_boost = 0.045 if is_final else 0.025
	if frozen_rig != null:
		frozen_rig.rally_full_on_parry()
	var spark_pt := (player.global_position + boss.global_position) * 0.5 + Vector2(0.0, -76.0)
	if backdrop != null:
		backdrop.pulse_normal_light(spark_pt, Color(0.98, 0.99, 1.0), 2.2 if is_final else 1.45, 5.5)
	if is_final:
		_boss_callout("崩针大硬直！", Color("ffffff"), 46)
		camera.add_shake(18.0 * shake_mul)
		_play_aaa_sfx("deflect", 0.14, 0.8)
	else:
		_boss_callout("叮！×%d" % n if n > 1 else "叮！", Color("f2f6ff"), 38)
		camera.add_shake(10.0 * shake_mul)
		_play_aaa_sfx("deflect", 0.05 * float(n - 1), 0.0)


func _on_clash_canceled(point: Vector2) -> void:
	_spawn_ring_fx(point, Color(0.94, 0.96, 1.0, 0.88), 160.0, 0.22)
	_boss_callout("错时瞬步变招！", Color("f0f4ff"), 40)
	_play_aaa_sfx("draw", 0.16, -1.0)


func _on_intro_slammed() -> void:
	camera.add_shake(20.0 * shake_mul)
	audio.play_slam(0.85)
	_play_aaa_sfx("deflect", -0.10, -2.0)
	var impact_pt := Vector2(boss.global_position.x, boss.feet_y())
	_ground_slam_at(impact_pt, 1.0)
	if backdrop != null:
		backdrop.pulse_normal_light(impact_pt + Vector2(0.0, -60.0), Color(0.96, 0.98, 1.0), 2.2, 6.0)
		if backdrop.has_method(&"slash_rain_at"):
			backdrop.slash_rain_at(Vector2(boss.global_position.x, floor_y - 200.0), 420.0, Vector2.DOWN)


func _on_intro_done() -> void:
	pass


func _on_nail_aimed() -> void:
	if _nail_note_shown:
		return
	_nail_note_shown = true
	_boss_callout("锁链钉影", Color("e6ecf8"), 32)


func _on_nail_landed(point: Vector2) -> void:
	camera.add_shake(10.0 * shake_mul)
	audio.play_slam(0.5)
	_ground_slam_at(point, 0.55)


func _on_tether_slam(damage: float, point: Vector2) -> void:
	style.add_event(&"wall")
	fx.spawn_text(point + Vector2(0.0, -160.0), "拽回", damage, true)
	_ground_slam_at(point, 0.9)
	_boss_callout("断链重摔！", Color("ffffff"), 40)
	camera.add_shake(20.0 * shake_mul)
	audio.play_slam(0.9)
	if boss != null and is_instance_valid(boss):
		boss.reward_air_control(3)
	if player.bonus_air_jumps < player.air_jump_refund_max:
		player.bonus_air_jumps += 1
		player.air_jump_refunded.emit(player.bonus_air_jumps)


func _on_dodged_through(point: Vector2) -> void:
	if dodge != null:
		dodge.arm_heavy()
	fx.spawn_text(point + Vector2(0.0, -140.0), "掠影")
	camera.add_shake(6.0 * shake_mul)


func _on_armor_held() -> void:
	if fight_time - _armor_note_at < 2.2:
		return
	_armor_note_at = fight_time
	fx.spawn_text(boss.global_position + Vector2(0.0, -165.0), "驻时棱壳")
	_boss_callout("弹倒带刃 / 斩碎过去锚点破壳！", Color("dce4f2"), 28)
	_play_aaa_sfx("deflect", -0.22, -4.5)


func _on_air_judged(on_beat: bool, point: Vector2) -> void:
	if on_beat:
		_play_aaa_sfx("deflect", 0.24, -6.5)
		return
	fx.spawn_text(point + Vector2(0.0, -150.0), "早")
	if fight_time - _early_note_at > 6.0:
		_early_note_at = fight_time
		_boss_callout("到顶再斩", Color("aeb6c8"), 28)


func _on_jump_given(source: StringName, _point: Vector2, high: bool) -> void:
	var src_name: String = AirRules.SOURCE_NAME.get(source, "")
	if not high:
		fx.spawn_text(player.global_position + Vector2(0.0, -230.0), src_name)
		return
	if boss != null and is_instance_valid(boss):
		boss.reward_air_control(3)
	fx.spawn_text(player.global_position + Vector2(0.0, -230.0), "%s托举" % src_name)
	_boss_callout("%s托举！" % src_name, Color("ffffff"), 34)
	camera.add_shake(9.0 * shake_mul)
	_play_aaa_sfx("deflect", 0.20, -5.5)


func _on_jump_denied(source: StringName, _point: Vector2) -> void:
	fx.spawn_text(player.global_position + Vector2(0.0, -200.0), "%s不给跳" % AirRules.SOURCE_NAME.get(source, ""))
	if fight_time - _early_note_at > 6.0:
		_early_note_at = fight_time
		_boss_callout("换招续跳", Color("aeb6c8"), 26)


func _on_air_whiffed(point: Vector2) -> void:
	fx.spawn_text(point + Vector2(0.0, -140.0), "空")


func _on_heavy_armed() -> void:
	_boss_callout("闪身重刃！", Color("d29eff"), 34)


func _on_heavy_landed(_target: Node2D, _point: Vector2) -> void:
	_boss_callout("重斩！", Color("ffffff"), 48)
	camera.add_shake(18.0 * shake_mul, Vector2(player.facing, 0))


func _on_player_hurt(dmg: float, point: Vector2, shake: float = 3.0, dir: Vector2 = Vector2.ZERO, heavy: bool = false) -> void:
	hits_taken += 1
	if frozen_rig != null and dmg > 0.0:
		frozen_rig.notify_damage_taken(dmg)
	super(dmg, point, shake, dir, heavy)


# ---------------------------------------------------------------- 胜负结算与重开

func _on_boss_killed() -> void:
	won = true
	_slowmo_token += 1
	_cam_focus_boost = 0.045
	if hud != null and "_callouts" in hud:
		hud._callouts.clear()
	if backdrop != null and backdrop.has_method(&"trigger_victory_dawn"):
		backdrop.trigger_victory_dawn()
	hud.banner("六点整  ·  断晓", "错时归正 · 蚀光散尽 · 悬雨倾落", 1.8)
	_slowmo(0.2, 0.9)
	camera.add_shake(30.0 * shake_mul)
	_kill_yanks = int(boss.yanks)
	_kill_cores = int(boss.core_drops)
	_kill_purple_rifts = int(boss.dyed_rift_count)
	print("BOSS_SAMPLE_WIN seconds=%d hits=%d cores=%d purple_rifts=%d" % [
		int(fight_time), hits_taken, _kill_cores, _kill_purple_rifts
	])
	await get_tree().create_timer(RESULT_DELAY, true, false, true).timeout
	if is_inside_tree() and won:
		_show_result()


func grade() -> String:
	if hits_taken <= 1:
		return "S"
	if hits_taken <= 3:
		return "A"
	if hits_taken <= 6:
		return "B"
	if hits_taken <= 10:
		return "C"
	return "D"


func _show_result() -> void:
	if _result != null:
		return
	Engine.time_scale = 1.0
	_result = BossResultPanel.new()
	_result.name = "BossResult"
	_result.result_font = hud._font if hud != null else null
	_result.summary = {
		"name": BOSS_NAME,
		"grade": grade(),
		"seconds": fight_time,
		"hits": hits_taken,
		"parry": int(style.stats.get("parry", 0)),
		"wall": int(style.stats.get("wall", 0)),
		"yanks": _kill_yanks,
		"cores": _kill_cores,
		"purple_rifts": _kill_purple_rifts,
	}
	_result.restart_requested.connect(_restart_trial)
	if _result.has_signal(&"new_run_requested"):
		_result.connect(&"new_run_requested", _start_new_street_run)
	add_child(_result)
	get_tree().paused = true


func _on_player_died() -> void:
	_slowmo_token += 1
	Engine.time_scale = 1.0
	phase = Phase.FALLEN
	fallen_frames = 600
	if boss != null and is_instance_valid(boss):
		boss.active = false
	var hp_pct := int(100.0 * boss.hp / maxf(boss.max_hp, 1.0)) if (boss != null and is_instance_valid(boss)) else 0
	print("BOSS_SAMPLE_LOSE seconds=%d boss_hp=%d" % [int(fight_time), int(boss.hp) if (boss != null and is_instance_valid(boss)) else 0])
	if death_rewind != null:
		death_rewind.trigger_rewind([player, boss, _fx_layer], hp_pct, audio)
	else:
		audio.play_die()
		camera.add_shake(12.0 * shake_mul)
		hud.banner("5 : 59", "时间触底回溯 · 马上重来", 1.4)
		fallen_frames = 80


func _on_death_rewind_completed() -> void:
	if phase == Phase.FALLEN:
		_revive()


func _revive() -> void:
	_restart_trial()


func _start_new_street_run() -> void:
	if _restart_pending:
		return
	_restart_pending = true
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file("res://scenes/rain_trial.tscn")


func _restart_trial() -> void:
	if _restart_pending:
		return
	_restart_pending = true
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file("res://scenes/boss_sample.tscn")


func _spawn_ring_fx(pt: Vector2, col: Color, max_r: float, dur: float) -> void:
	if _fx_layer == null:
		return
	var ring := _RingPulseFx.new()
	ring.setup(pt, col, max_r, dur)
	_fx_layer.add_child(ring)


# ---------------------------------------------------------------- 舞台冲击特效子类

class _GroundShockFx extends Node2D:
	var power: float = 1.0
	var t: float = 0.0
	var dur: float = 0.34

	func setup(world_pt: Vector2, p: float) -> void:
		global_position = world_pt
		power = p
		dur = 0.28 + 0.10 * p

	func _process(delta: float) -> void:
		t += delta
		if t >= dur:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var k := t / dur
		var a := 1.0 - k
		var w := lerpf(40.0, 290.0 * power, pow(k, 0.35))
		var h := lerpf(78.0 * power, 4.0, k)
		draw_line(Vector2(-w, -2.0), Vector2(w, -2.0), Color(0.96, 0.97, 1.0, 0.85 * a), 4.0 * a + 1.0)
		for side_val: float in [-1.0, 1.0]:
			var bx: float = side_val * w * 0.72
			draw_colored_polygon(PackedVector2Array([
				Vector2(bx - side_val * 22.0, 0.0),
				Vector2(bx, -h),
				Vector2(bx + side_val * 14.0, 0.0),
			]), Color(0.90, 0.92, 0.96, 0.56 * a))


class _PrismBurstFx extends Node2D:
	var tex: Texture2D = null
	var t: float = 0.0
	var dur: float = 0.32

	func setup(world_pt: Vector2, vfx_atlas: Texture2D) -> void:
		global_position = world_pt
		tex = vfx_atlas

	func _process(delta: float) -> void:
		t += delta
		if t >= dur:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		if tex == null:
			return
		var k := clampf(t / dur, 0.0, 1.0)
		var a := 1.0 - k * k
		var sz := 512.0 * lerpf(0.68, 1.38, pow(k, 0.42))
		var src := Rect2(1024.0 + 3.0, 3.0, 506.0, 506.0)
		draw_texture_rect_region(tex, Rect2(Vector2(-sz * 0.5, -sz * 0.5), Vector2(sz, sz)), src, Color(1.08, 1.08, 1.10, a))


class _RingPulseFx extends Node2D:
	var col := Color.WHITE
	var max_r: float = 240.0
	var dur: float = 0.3
	var t: float = 0.0

	func setup(world_pt: Vector2, c: Color, r: float, d: float) -> void:
		global_position = world_pt
		col = c
		max_r = r
		dur = maxf(d, 0.08)

	func _process(delta: float) -> void:
		t += delta
		if t >= dur:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var k := clampf(t / dur, 0.0, 1.0)
		var r := lerpf(24.0, max_r, pow(k, 0.42))
		var a := (1.0 - k) * col.a
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 56, Color(col.r, col.g, col.b, a), lerpf(7.0, 1.2, k))
