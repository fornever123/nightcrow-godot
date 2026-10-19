extends SceneTree
## Regressions for jump-cancelling combat actions and airborne hit slowdown.
## Run: godot --headless --fixed-fps 60 --path . --script res://tests/test_jump_combat_mobility.gd

const Config := preload("res://scripts/core/configuration.gd")
const Buffer := preload("res://scripts/core/input_buffer.gd")
const Player := preload("res://scripts/gameplay/player.gd")
const DummyScene := preload("res://scenes/actors/dummy.tscn")

var stage: Node2D
var p: CharacterBody2D
var d: CharacterBody2D
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		print("FAIL: ", label)


func int_prop(object: Object, key: StringName, fallback: int = -1) -> int:
	var value = object.get(key)
	return fallback if value == null else int(value)


func frame(actions: Array[StringName] = [], edges: Array[StringName] = [], axis := Vector2.ZERO) -> Buffer.Frame:
	var result := Buffer.Frame.new()
	result.actions = actions
	result.pressed_this_frame = edges
	result.axis = axis
	return result


func step(input: Buffer.Frame = null) -> void:
	p.set_injected_frame(frame() if input == null else input)
	var target: int = p.tick_count + 1
	while p.tick_count < target:
		await process_frame


func reset() -> void:
	stage._reset()
	p.clear_input_queue()
	p.set_injected_frame(frame())
	d.position = Vector2(10000.0, stage.config.stage.bounds.floorY - 68.0)
	await step()
	await step()


func place_dummy_near_player(offset := Vector2(60.0, 0.0)) -> void:
	d.position = p.position + offset
	d.velocity = Vector2.ZERO


func jump_edge(actions: Array[StringName] = [&"jump"], axis := Vector2.ZERO) -> void:
	await step(frame(actions, [&"jump"], axis))


func key_event(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)


func do_ground_cancel(move: Resource, phase: String, with_hitstop: bool = false) -> bool:
	await reset()
	p._start_move(move, false)
	match phase:
		"startup":
			p.move_frame = 0
		"active":
			p.move_frame = move.startup_frames
		"recovery":
			p.move_frame = move.startup_frames + move.active_frames + 1
	if with_hitstop:
		p.hitstop_frames = 5
	await jump_edge()
	return p.velocity.y < 0.0 and p.current_move == null and p.hitstop_frames == 0 \
			and p.charge_frames < 0


func run() -> void:
	stage = load("res://scenes/training.tscn").instantiate()
	root.add_child(stage)
	current_scene = stage
	stage.config.runtime.autoReload = false
	p = stage.player
	d = stage.dummy
	await reset()

	var cfg: Dictionary = Config.character(Config.read(), "player")
	var air: Dictionary = cfg.get("airCombat", {})
	check(int(air.get("launcherJumpBonus", -1)) == 1, "air-combat config grants one launcher jump")
	check(int(air.get("hitFallSlowFrames", -1)) == 12 and absf(float(air.get("hitFallSpeedScale", -1.0)) - 0.45) < 0.001 \
			and absf(float(air.get("hitFallGravityScale", -1.0)) - 0.35) < 0.001,
			"air-hit slow config keeps the 12-frame, 0.45-speed, 0.35-gravity contract")

	var light: Resource = stage.moves.light_1
	check(await do_ground_cancel(light, "startup"), "jump cancels attack startup on the input tick")
	check(await do_ground_cancel(light, "active"), "jump cancels attack active phase on the input tick")
	check(await do_ground_cancel(light, "recovery"), "jump cancels attack recovery on the input tick")
	check(await do_ground_cancel(stage.moves.dash_slash, "active"), "jump cancels dash attack")
	check(await do_ground_cancel(light, "active", true), "jump cancels its own hitstop and clears the old move")

	# Charge, turn, hit-reaction, down, and successful block cover action states
	# that do not necessarily have a current MoveDefinition.
	await reset()
	p.charge_frames = 7
	p._charge_accum = 0.5
	await jump_edge()
	check(p.velocity.y < 0.0 and p.charge_frames < 0 and p.current_move == null,
			"jump cancels charge and clears its accumulated release state")
	await reset()
	p.locomotion_animation = "turn_left"
	p._turn_target = -1
	await jump_edge()
	check(p.velocity.y < 0.0 and p.locomotion_animation.is_empty(), "jump cancels a turn animation")
	await reset()
	p.state = Player.State.LAUNCHED
	p.velocity = Vector2(100.0, 120.0)
	await jump_edge()
	check(p.velocity.y < 0.0 and p.state != Player.State.LAUNCHED, "jump cancels hit-launch reaction")
	await reset()
	p.state = Player.State.DOWN
	p.down_frames = 20
	await jump_edge()
	check(p.velocity.y < 0.0 and p.state != Player.State.DOWN, "jump cancels a knockdown recovery")
	await reset()
	p._do_block(d, p.global_position)
	var block_stop: int = p.hitstop_frames
	await jump_edge()
	check(block_stop > 0 and p.velocity.y < 0.0 and p.hitstop_frames == 0,
			"jump cancels successful block feedback including its hitstop")

	# A failed extra jump must preserve the current action and not grant movement.
	await reset()
	p.position.y -= 100.0
	p.velocity = Vector2.ZERO
	await step()
	p.ground_frames = 0
	p.air_frames = p.coyote_frames + 2
	p.set("_air_jumps_left", 0)
	p._start_move(light, false)
	var move_before: Resource = p.current_move
	await jump_edge()
	check(p.velocity.y >= 0.0 and p.current_move == move_before,
			"an exhausted airborne jump neither cancels an action nor changes trajectory")

	# Ultimate is the one protected action, and jump pressed in it must not fire
	# after the ultimate finishes.
	await reset()
	p.ult_enabled = true
	p.ult_energy = p.ult_max
	p._start_ult()
	p.ult_frame = 8
	var before_ult: int = p.ult_frame
	await jump_edge()
	check(p.ult_frame > before_ult and p.velocity.y >= 0.0, "jump cannot cancel an active ultimate")
	await reset()
	p.ult_enabled = true
	p.ult_energy = p.ult_max
	p._start_ult()
	p.ult_frame = p.ult_total_frames - 2
	await jump_edge()
	for i in 4:
		await step()
	check(p.ult_frame < 0 and p.velocity.y >= 0.0, "jump pressed during ultimate does not trigger after it ends")
	p.ult_enabled = false

	# A W+J chord still selects the ground launcher; explicit jump can be tested
	# separately by its injected action when supported by the runtime mapping.
	await reset()
	await step(frame([&"jump", &"aim_up", &"attack_light"], [&"jump", &"attack_light"]))
	check(p.current_move == stage.moves.up_strike and p.velocity.y >= 0.0,
			"W+J remains an up-strike rather than being consumed as a jump")
	await reset()
	p.clear_input_queue()
	key_event(KEY_W, true)
	key_event(KEY_J, true)
	key_event(KEY_SPACE, true)
	var keyboard_tick: int = p.tick_count + 1
	while p.tick_count < keyboard_tick:
		await process_frame
	check(p.velocity.y < 0.0 and p.current_move == null,
			"explicit Space overrides the W+J up-strike chord and jumps")
	key_event(KEY_W, false)
	key_event(KEY_J, false)
	key_event(KEY_SPACE, false)
	await reset()
	p._guard_active = true
	p._guard_frames = 10
	var x_before: float = p.position.x
	await step(frame([&"jump", &"parry", &"move_right"], [&"jump"], Vector2.RIGHT))
	check(p.velocity.y < 0.0 and p._guard_active and p.position.x > x_before,
			"holding guard while jumping preserves guard and 85-percent movement")
	await reset()
	p.state = Player.State.DEAD
	p.can_die = true
	p.hp = 0.0
	await jump_edge()
	check(p.state == Player.State.DEAD and p.hp == 0.0 and p.velocity.y >= 0.0,
			"jump never revives a dead player")

	# One real ground launcher hit grants exactly one reusable extra air jump;
	# misses and projectiles must not create phantom bonuses.
	await reset()
	d.position = Vector2(stage.config.stage.spawn.enemies[0].x, stage.config.stage.spawn.enemies[0].y - 68.0)
	d.velocity = Vector2.ZERO
	var second_dummy: CharacterBody2D = DummyScene.instantiate()
	stage.add_child(second_dummy)
	second_dummy.position = d.position + Vector2(40.0, 0.0)
	second_dummy.velocity = Vector2.ZERO
	p.position.x = d.position.x - 60.0
	await step()
	await step(frame([&"aim_up", &"attack_light"], [&"attack_light"]))
	var hp_before: float = d.hp
	var second_hp_before: float = second_dummy.hp
	for i in 40:
		await step()
		if d.hp < hp_before and second_dummy.hp < second_hp_before:
			break
	var granted := int(p.get("_bonus_air_jumps")) if p.get("_bonus_air_jumps") != null else -1
	check(d.hp < hp_before and second_dummy.hp < second_hp_before and granted == 1,
			"one real up-strike hitting two enemies grants only one bonus jump")
	second_dummy.queue_free()
	await process_frame
	if d.hp < hp_before:
		await jump_edge()
		check(p.velocity.y < 0.0 and int_prop(p, &"_bonus_air_jumps") == 1,
				"ground launcher bonus remains available after the following takeoff")
		for i in p.coyote_frames + 2:
			await step()
		await jump_edge()
		check(int_prop(p, &"_air_jumps_left") == 0 and int_prop(p, &"_bonus_air_jumps") == 1,
				"the ordinary extra jump is consumed before launcher bonus")
		for i in p.coyote_frames + 2:
			await step()
		await jump_edge()
		check(int_prop(p, &"_bonus_air_jumps") == 0, "the launcher bonus jump is consumed once")
		for i in 180:
			if p.is_on_floor():
				break
			await step()
		check(int_prop(p, &"_bonus_air_jumps") == 0, "landing clears the consumed launcher bonus")

	# Force the real melee overlap path against the wooden dummy while falling.
	# Verify immediate velocity scaling, active-frame countdown, and that a
	# projectile/miss cannot start the slow-fall window.
	await reset()
	await jump_edge()
	for i in 18:
		await step()
	place_dummy_near_player(Vector2(50.0, 0.0))
	var air_second_dummy: CharacterBody2D = DummyScene.instantiate()
	stage.add_child(air_second_dummy)
	air_second_dummy.position = d.position + Vector2(28.0, 0.0)
	air_second_dummy.velocity = Vector2.ZERO
	await step()
	p.velocity.y = 220.0
	var air_hp_before: float = d.hp
	var air_second_hp_before: float = air_second_dummy.hp
	await step(frame([&"attack_light"], [&"attack_light"]))
	var air_hit_vy := INF
	var air_pre_hit_vy := INF
	var air_slow_at_hit := -1
	for i in 24:
		var vy_before_tick: float = p.velocity.y
		await step()
		if d.hp < air_hp_before and air_second_dummy.hp < air_second_hp_before:
			air_hit_vy = p.velocity.y
			air_pre_hit_vy = vy_before_tick
			air_slow_at_hit = int_prop(p, &"_air_hit_slow_frames")
			break
	var slow_left := int(p.get("_air_hit_slow_frames")) if p.get("_air_hit_slow_frames") != null else -1
	check(d.hp < air_hp_before and air_second_dummy.hp < air_second_hp_before and air_slow_at_hit == 12 \
			and absf(air_hit_vy - air_pre_hit_vy * 0.45) < 2.0 and slow_left > 0,
			"same-tick hits on two enemies apply one 0.45 fall-speed scale and start the slow window")
	if slow_left > 0:
		await jump_edge()
		check(int_prop(p, &"_air_hit_slow_frames") == 0, "jump cancellation clears the active hit-fall window")
	air_second_dummy.queue_free()
	await process_frame
	if slow_left > 0:
		await reset()
		# Keep an airborne character and consume part of the configured window.
		p.position.y -= 200.0
		p.velocity.y = 0.0
		await step()
		p.velocity.y = 200.0
		p.set("_air_hit_slow_frames", 3)
		var before_fall: float = p.velocity.y
		await step()
		check(p.velocity.y > 0.0 and p.velocity.y < before_fall + p._fall_gravity * p.hit_fall_gravity_scale / 60.0 + 0.1 \
				and int_prop(p, &"_air_hit_slow_frames") == 2,
				"hit-fall gravity stays reduced while the remaining active frames tick down")
		p.set("_air_hit_slow_frames", 0)

	# The same hit window may begin during ascent, but it must not pull upward
	# velocity toward zero; only the later downward phase uses reduced gravity.
	await reset()
	await jump_edge()
	for i in 10:
		await step()
	place_dummy_near_player(Vector2(50.0, 0.0))
	var rising_hp_before: float = d.hp
	await step(frame([&"attack_light"], [&"attack_light"]))
	var rising_hit_vy := 0.0
	var rising_pre_hit_vy := 0.0
	var rising_slow := 0
	for i in 24:
		var vy_before_tick: float = p.velocity.y
		await step()
		if d.hp < rising_hp_before:
			rising_hit_vy = p.velocity.y
			rising_pre_hit_vy = vy_before_tick
			rising_slow = int_prop(p, &"_air_hit_slow_frames")
			break
	check(d.hp < rising_hp_before and rising_pre_hit_vy < 0.0 and rising_hit_vy < 0.0 \
			and absf(rising_hit_vy - rising_pre_hit_vy) < p._gravity / 30.0 and rising_slow == 12,
			"an ascending air-melee hit starts the window without scaling upward velocity")

	await reset()
	await jump_edge()
	for i in 18:
		await step()
	var vy_before_miss: float = p.velocity.y
	p._air_light_left = 1
	# Move the target away so a whiff follows the normal air trajectory.
	d.position = Vector2(10000.0, stage.config.stage.bounds.floorY - 68.0)
	p.set_injected_frame(frame([&"attack_light"], [&"attack_light"]))
	await step()
	for i in 12:
		await step()
	check(p.velocity.y > vy_before_miss and (p.get("_air_hit_slow_frames") == null or int(p.get("_air_hit_slow_frames")) == 0),
			"air attack whiff keeps normal gravity and does not start hit-fall slowdown")

	stage.queue_free()
	await process_frame
	print("JUMP_COMBAT_MOBILITY_TESTS: %d checks / %d failures" % [checks, failures.size()])
	OS.delay_msec(100)
	await process_frame
	quit(1 if not failures.is_empty() else 0)
