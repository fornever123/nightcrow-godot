extends SceneTree
## Focused regression tests for hitstop and camera feedback in the night trial.
## Run: godot --headless --fixed-fps 60 --path . --script res://tests/test_strong_feedback.gd

const Config := preload("res://scripts/core/configuration.gd")
const Factory := preload("res://scripts/night/player_factory.gd")
const Shade := preload("res://scripts/night/shade.gd")
const Night := preload("res://scripts/night/night_trial.gd")
const Player := preload("res://scripts/gameplay/player.gd")
const Buffer := preload("res://scripts/core/input_buffer.gd")
const Bolt := preload("res://scripts/night/shade_bolt.gd")
const Bomb := preload("res://scripts/night/shade_bomb.gd")

var stage: Node2D
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		print("FAIL: ", label)


func close(a: float, b: float, epsilon := 0.001) -> bool:
	return absf(a - b) <= epsilon


func make_config(hitstop_mul: float, shake_mul: float) -> Dictionary:
	var cfg := Config.read().duplicate(true)
	cfg.feedback.hitstopMultiplier = hitstop_mul
	cfg.feedback.shakeMultiplier = shake_mul
	return cfg


func input_frame(actions: Array[StringName] = [], edges: Array[StringName] = []) -> Buffer.Frame:
	var frame := Buffer.Frame.new()
	frame.actions = actions
	frame.pressed_this_frame = edges
	return frame


func test_input_time_contract() -> void:
	var ring := Buffer.new()
	var attack := input_frame([&"attack_light"], [&"attack_light"])
	ring.push(attack)
	for i in 16:
		ring.push(input_frame())
	check(ring.logic_age_at(16) == 16, "normal input edge ages at real actionable-frame rate")
	ring.push(input_frame())
	check(ring.logic_age_at(17) == 17, "normal 16-frame input window expires on the next frame")
	var frozen := Buffer.new()
	frozen.push(input_frame([&"attack_light"], [&"attack_light"]))
	for i in 20:
		frozen.push(input_frame(), false)
	check(frozen.logic_age_at(20) == 0, "hitstop samples do not age buffered inputs")
	var chord := Buffer.new()
	chord.push(input_frame([&"attack_light"], [&"attack_light"]))
	for i in 5:
		chord.push(input_frame())
	check(chord.pressed_within(&"attack_light", 6), "attack chord remains valid through six real frames")
	chord.push(input_frame())
	check(not chord.pressed_within(&"attack_light", 6), "attack chord expires after six real frames despite paused logic clock")


func run() -> void:
	test_input_time_contract()
	stage = load("res://scenes/night_trial.tscn").instantiate()
	root.add_child(stage)
	current_scene = stage
	await physics_frame
	await process_frame

	# Config-derived move timings are physical 60 Hz frames. The per-move values
	# remain the single source for ground, air, dash, and ranged hit feedback.
	var moves: Dictionary = Config.moves(Config.read())
	var expected := {
		"light_1": [6, 7, 5.5], "light_2": [6, 8, 6.5], "light_3": [11, 15, 12.0],
		"charge_1": [13, 16, 15.0], "up_strike": [9, 11, 10.0], "air_up": [6, 7, 6.0],
		"air_light_1": [6, 7, 5.5], "air_light_2": [6, 8, 6.5], "air_light_3": [10, 13, 11.0],
		"dash_slash": [11, 14, 12.0], "ranged_1": [3, 5, 3.5],
	}
	const REFERENCE_SHAKE_MULTIPLIER := 1.55
	for id in expected:
		var m: Resource = moves.get(id)
		var e: Array = expected[id]
		check(m != null, "%s exists in runtime move config" % id)
		if m != null:
			check(m.hitstop_frames == e[0] and m.victim_hitstop_frames == e[1], "%s attacker/victim hitstop frames" % id)
			check(close(m.shake_amount, e[2] * REFERENCE_SHAKE_MULTIPLIER), "%s shake amount uses the C-drive global multiplier" % id)
	check(moves.ranged_1.hitstop_frames == 3, "ranged shot is not stopped on attacker hit")
	check(moves.charge_1.charge_hitstop_bonus == 6, "full charge adds six hitstop frames")

	# Global modifier endpoints exercise conversion and player factory injection.
	for multiplier in [0.0, 2.0]:
		var cfg := make_config(multiplier, multiplier)
		var scaled: Dictionary = Config.moves(cfg)
		var expected_frame := roundi(6.0 * multiplier)
		check(scaled.light_1.hitstop_frames == expected_frame, "hitstop config multiplier %s" % multiplier)
		check(close(scaled.light_1.shake_amount, 5.5 * multiplier), "shake config multiplier %s" % multiplier)
		check(scaled.charge_1.charge_hitstop_bonus == roundi(6.0 * multiplier), "charge bonus config multiplier %s" % multiplier)
		var built: CharacterBody2D = Factory.build(cfg, scaled, Vector2.ZERO)
		check(built.get("hitstop_multiplier") != null and close(float(built.get("hitstop_multiplier")), multiplier),
				"player factory injects hitstop multiplier %s" % multiplier)
		built.free()

	# The view samples real noise and returns to a clean origin. Pixel snapping is
	# checked in world space because the night camera is zoomed out.
	check(close(stage.camera.shake_world_scale, 1.0 / Night.ZOOM), "night camera converts screen shake to world units")
	check(close(stage.camera.shake_decay, 7.0), "night camera retains seven-per-second decay")
	check(close(stage.camera.max_shake, 42.0), "night camera retains 42-pixel trauma cap")
	check(close(stage.camera.pixel_snap, 2.0), "night shake snaps to two screen pixels")
	stage.camera.reset_shake()
	stage.camera.add_shake(18.0, Vector2.RIGHT)
	var saw_shake := false
	var all_snapped := true
	for i in 60:
		stage.camera._update_shake(1.0 / 60.0)
		if stage.camera.offset.length_squared() > 0.0:
			saw_shake = true
		var snap_step: float = stage.camera.pixel_snap / maxf(stage.camera.zoom.x, 0.01)
		all_snapped = all_snapped and close(stage.camera.offset.x / snap_step, roundf(stage.camera.offset.x / snap_step)) \
				and close(stage.camera.offset.y / snap_step, roundf(stage.camera.offset.y / snap_step))
	check(saw_shake, "camera noise produces visible shake after impact")
	check(all_snapped, "shake offset stays on the zoom-adjusted pixel grid")
	for i in 240:
		stage.camera._update_shake(1.0 / 60.0)
	check(stage.camera.offset == Vector2.ZERO and stage.camera.rotation == 0.0, "camera shake decays fully to zero")
	stage.camera.add_shake(4.0)
	stage.camera.reset_shake()
	check(stage.camera.offset == Vector2.ZERO and stage.camera._trauma == 0.0, "camera reset clears pending shake")

	# Instantiate through Encounter._add so the production injection path is covered.
	var enemy := Node2D.new()
	enemy.set_script(Shade)
	enemy.setup(Shade.Kind.GRUNT, stage.player, stage.floor_y, 1.0)
	stage.encounter.setup([], 0.0, 1000.0, stage.floor_y, stage.player, stage, 1.0)
	stage.encounter._add(enemy)
	await physics_frame
	check(enemy.get("hitstop_multiplier") != null and close(float(enemy.get("hitstop_multiplier")), 1.0),
			"encounter injects default hitstop multiplier into shade")
	for multiplier in [0.0, 2.0]:
		stage.player.hitstop_multiplier = multiplier
		var scaled_enemy := Node2D.new()
		scaled_enemy.set_script(Shade)
		scaled_enemy.setup(Shade.Kind.GRUNT, stage.player, stage.floor_y, 1.0)
		stage.encounter._add(scaled_enemy)
		check(scaled_enemy.strike_move.hitstop_frames == roundi(8 * multiplier)
				and scaled_enemy.strike_move.victim_hitstop_frames == roundi(10 * multiplier),
				"encounter applies multiplier %s before enemy move creation" % multiplier)
		scaled_enemy.free()
	stage.player.hitstop_multiplier = 1.0
	var expected_strikes := {
		Shade.Kind.GRUNT: [8, 10], Shade.Kind.BRUTE: [10, 14],
		Shade.Kind.ARCHER: [-1, 8], Shade.Kind.BOMBER: [-1, 16],
	}
	for kind in expected_strikes:
		var s := Node2D.new()
		s.set_script(Shade)
		s.setup(kind, stage.player, stage.floor_y, 1.0)
		stage.add_child(s)
		await physics_frame
		var e: Array = expected_strikes[kind]
		check((e[0] < 0 or s.strike_move.hitstop_frames == e[0]) and s.strike_move.victim_hitstop_frames == e[1],
				"shade kind %d strike hitstop timing" % kind)
		s.queue_free()
	await physics_frame

	# Player-side parry and block use configured frame counts; ranged hits stop
	# only the recipient. This uses direct combat calls to avoid timing-sensitive
	# full AI / recording playback.
	var player: CharacterBody2D = stage.player
	check(player.parry_hitstop_frames == 9, "night parry hitstop is nine frames")
	check(int(player._guard_config().get("blockHitstopFrames", 0)) == 8, "night guard block hitstop is eight frames")
	player.hitstop_frames = 0
	var parry_target := enemy
	enemy.hitstop_multiplier = 2.0
	player._do_parry(parry_target, player.global_position)
	check(player.hitstop_frames == 9, "successful parry applies configured hitstop")
	check(enemy.hitstop_frames >= 28, "parried attacker receives fourteen hitstop frames times its modifier")
	player.hitstop_frames = 0
	var ranged: Resource = moves.ranged_1
	player.take_hit(ranged, -1, player.global_position, 0.0, false, 1.0, enemy)
	check(player.hitstop_frames == 5, "ranged hit stops victim without changing ranged attacker timing")
	var bolt := Node2D.new()
	bolt.set_script(Bolt)
	bolt.setup(enemy, enemy.global_position, Vector2.LEFT, enemy.strike_move, 1.0)
	check(bolt.reflect_move.victim_hitstop_frames == 10 and bolt.reflect_move.hitstop_frames == 0,
			"reflected arrow transfers ten-frame hitstop to its enemy victim")
	var bomb := Node2D.new()
	bomb.set_script(Bomb)
	bomb.setup(enemy, enemy.global_position, enemy.global_position + Vector2(100, 0),
			enemy.strike_move, null, stage.floor_y, 0.0, 1000.0, 1.0)
	check(bomb.blast_move.victim_hitstop_frames == 12 and bomb.blast_move.hitstop_frames == 0,
			"bomb blast gives twelve-frame victim hitstop without stopping its source")
	bolt.free()
	bomb.free()

	# A guard event is distinct from a successful hit: it pauses the attacker and
	# gets its own screen shake tier. Breaking the guard has a stronger tier.
	player.hitstop_frames = 0
	enemy.hitstop_frames = 0
	enemy.hitstop_multiplier = 1.0
	player.hitstop_multiplier = 1.0
	enemy.poise = 0.0
	enemy.state = Shade.State.GUARD
	enemy.facing = -1
	stage.camera.reset_shake()
	enemy.take_hit(moves.light_1, 1, enemy.global_position, 0.0, false, 1.0, player)
	check(enemy.hitstop_frames == 8 and player.hitstop_frames == 6,
			"enemy guard pauses its defender for eight frames and attacker for six (got %d/%d)" % [enemy.hitstop_frames, player.hitstop_frames])
	check(stage.camera._trauma >= 5.0, "enemy guard event produces its dedicated shake")
	stage.camera.reset_shake()
	enemy.guard_broken.emit(enemy.global_position)
	check(stage.camera._trauma >= 10.0, "guard-break event produces stronger shake than a normal guard")
	player.hitstop_frames = 0
	player._do_block(enemy, player.global_position)
	check(player.hitstop_frames == 8, "player block uses the configured eight-frame pause")

	# An airborne neutral player's velocity is preserved through hitstop; this
	# catches regressions hidden by LAUNCHED's older special case.
	player.hitstop_frames = 0
	player.state = Player.State.NEUTRAL
	player.position.y = stage.floor_y - player.foot_offset - 100.0
	player.velocity = Vector2(120.0, -420.0)
	await physics_frame
	check(not player.is_on_floor(), "neutral player is airborne for momentum regression")
	var vertical_speed := player.velocity.y
	player.hitstop_frames = 2
	await physics_frame
	check(close(player.velocity.y, vertical_speed), "airborne neutral hitstop preserves vertical velocity")
	player.hitstop_frames = 0
	player.state = Player.State.NEUTRAL
	player.reset_state(Vector2(600.0, stage.floor_y - player.foot_offset))
	player.invuln_frames = 5
	player.hitstop_frames = 2
	await physics_frame
	check(player.invuln_frames == 5, "invulnerability timer pauses during hitstop")
	player.hitstop_frames = 0
	await physics_frame
	check(player.invuln_frames == 4, "invulnerability timer resumes after hitstop")
	player.reset_state(Vector2(600.0, stage.floor_y - player.foot_offset))
	player._start_move(stage.moves.charge_1, false)
	player.move_frame = stage.moves.charge_1.startup_frames
	player.hitstop_frames = 19
	player.set_injected_frame(input_frame())
	for i in 3:
		await physics_frame
	player.set_injected_frame(input_frame([&"attack_light"], [&"attack_light"]))
	await physics_frame
	player.set_injected_frame(input_frame([&"attack_light"], []))
	for i in 15:
		await physics_frame
	player.set_injected_frame(input_frame())
	var buffered_followup := false
	for i in 45:
		await physics_frame
		if player.current_move != null and player.light_combo.has(player.current_move):
			buffered_followup = true
			break
	var current_name: StringName = StringName("none") if player.current_move == null else player.current_move.id
	check(buffered_followup, "early follow-up pressed during 19-frame charge active hitstop is buffered (move=%s frame=%d stop=%d age=%d)" %
			[String(current_name), player.move_frame, player.hitstop_frames, player.input_buffer.logic_age_at(0)])

	# Drive the real enemy-side events directly. Each event must scale local
	# hitstop and the night scene's shake tier with its respective modifiers.
	player.hitstop_frames = 0
	player.hitstop_multiplier = 1.0
	enemy.active = false
	enemy.state = Shade.State.IDLE
	enemy.hp = enemy.max_hp
	enemy.poise = 0.0
	for multiplier in [0.0, 2.0]:
		enemy.hitstop_multiplier = multiplier
		stage.shake_mul = multiplier
		stage.camera.reset_shake()
		enemy.hitstop_frames = 0
		enemy.arena_left = -10000.0
		enemy.arena_right = 1000.0
		enemy.position.x = enemy.arena_right - enemy.half_w + 1.0
		enemy.velocity = Vector2(400.0, 0.0)
		enemy._wall_check()
		check(enemy.hitstop_frames == roundi(12 * multiplier), "wall impact hitstop scales at modifier %s" % multiplier)
		check((multiplier == 0.0 and stage.camera._trauma == 0.0) or (multiplier == 2.0 and stage.camera._trauma > 0.0),
				"wall impact shake scales at modifier %s" % multiplier)

		enemy.hitstop_frames = 0
		enemy.state = Shade.State.IDLE
		enemy.hp = enemy.max_hp
		enemy.poise = 0.0
		enemy.slammed = true
		enemy.position.y = enemy.ground_y()
		enemy.velocity = Vector2(0.0, 1400.0)
		stage.camera.reset_shake()
		enemy._floor_impact()
		check(enemy.hitstop_frames == roundi(12 * multiplier), "slam impact hitstop scales at modifier %s" % multiplier)
		check((multiplier == 0.0 and stage.camera._trauma == 0.0) or (multiplier == 2.0 and stage.camera._trauma > 0.0),
				"slam impact shake scales at modifier %s" % multiplier)

		enemy.hitstop_frames = 0
		enemy.state = Shade.State.IDLE
		enemy.hp = enemy.max_hp
		enemy.poise = 0.0
		stage.camera.reset_shake()
		enemy.take_chain(player, Vector2(450.0, -400.0), 1, false)
		check(enemy.hitstop_frames == roundi(10 * multiplier), "chain impact hitstop scales at modifier %s" % multiplier)
		check((multiplier == 0.0 and stage.camera._trauma == 0.0) or (multiplier == 2.0 and stage.camera._trauma > 0.0),
				"chain impact shake scales at modifier %s" % multiplier)

		enemy.hitstop_frames = 0
		enemy.state = Shade.State.IDLE
		enemy.poise = 0.0
		stage.camera.reset_shake()
		enemy._break()
		check(enemy.hitstop_frames == roundi(16 * multiplier), "guard break hitstop scales at modifier %s" % multiplier)

	# The reflected arrow's real combat path gives its enemy target ten frames.
	# 千刃 (HANDOFF §20): the start freezes every on-screen enemy until the
	# burst and never freezes the attacker; the burst damages them, and a
	# burst with nobody on screen freezes nobody.
	stage.shake_mul = 2.0
	var reflected_bolt := Node2D.new()
	reflected_bolt.set_script(Bolt)
	reflected_bolt.setup(enemy, enemy.global_position, Vector2.LEFT, moves.ranged_1, 2.0)
	stage.add_child(reflected_bolt)
	await physics_frame
	stage._on_projectile(reflected_bolt)
	stage.camera.reset_shake()
	reflected_bolt.take_hit(moves.light_1, player.facing, reflected_bolt.global_position, 0.0, false, 1.0, player)
	stage._on_player_hit(reflected_bolt, moves.light_1, reflected_bolt.global_position)
	check(reflected_bolt.friendly and reflected_bolt.reflect_move.victim_hitstop_frames == 20,
			"real arrow deflection reflects the projectile and scales its victim hitstop")
	check(stage.camera._trauma > 0.0, "reflected projectile event produces camera feedback")
	reflected_bolt.queue_free()
	await physics_frame

	player.hitstop_multiplier = 2.0
	enemy.hitstop_multiplier = 2.0
	enemy.state = Shade.State.IDLE
	enemy.spawn_frames = 0
	enemy.hp = enemy.max_hp
	enemy.global_position = player.global_position + Vector2(100.0, 0.0)
	player.hitstop_frames = 0
	stage._on_ult_started()
	check(player.hitstop_frames == 0 and enemy.hitstop_frames >= player.ult_total_frames,
			"千刃 start holds on-screen enemies (%d) without freezing the attacker" % enemy.hitstop_frames)
	var ult_hp_before: float = enemy.hp
	stage._on_ult_hit()
	check(player.hitstop_frames == 0 and enemy.hp < ult_hp_before, "千刃 burst damages the held enemy without freezing the attacker")
	stage.ult_fx.clear()
	enemy.state = Shade.State.DEAD
	player.hitstop_frames = 0
	stage._on_ult_started()
	stage._on_ult_hit()
	check(player.hitstop_frames == 0, "missed ultimate does not freeze its attacker")
	stage.ult_fx.clear()
	stage.camera.reset_shake()
	stage._on_shade_died(enemy)
	check(stage.camera._trauma > 0.0, "enemy kill event produces its dedicated shake")
	stage.shake_mul = 1.55
	stage.camera.reset_shake()
	stage.camera.add_shake(10000.0)
	check(close(stage.camera._trauma, stage.camera.max_shake), "simultaneous strong impacts remain capped")
	# Invulnerable targets are misses, even though take_hit returns false.
	player.reset_state(Vector2(600.0, stage.floor_y - player.foot_offset))
	player.invuln_frames = 10
	enemy.state = Shade.State.STRIKE
	enemy.hitstop_frames = 0
	enemy.global_position = player.global_position - Vector2(70.0, 0.0)
	enemy.facing = 1
	var hp_before: float = player.hp
	enemy._strike_check()
	check(enemy.hitstop_frames == 0 and close(player.hp, hp_before), "enemy whiff against invulnerability does not pause attacker")
	player.invuln_frames = 0
	enemy._strike_check()
	check(enemy.hitstop_frames == enemy.strike_move.hitstop_frames and player.hp < hp_before,
			"real enemy strike pauses attacker as well as victim")

	print("STRONG_FEEDBACK_TESTS: %d checks / %d failures" % [checks, failures.size()])
	stage.queue_free()
	await process_frame
	OS.delay_msec(100)
	await process_frame
	quit(0 if failures.is_empty() else 1)
