extends SceneTree
## Physical-key order tests for the jump-integrated uppercut command.
## Run: godot --headless --fixed-fps 60 --path . --script res://tests/test_uppercut_jump.gd

const Config := preload("res://scripts/core/configuration.gd")
const Buffer := preload("res://scripts/core/input_buffer.gd")
const Player := preload("res://scripts/gameplay/player.gd")

var stage: Node2D
var p: CharacterBody2D
var d: CharacterBody2D
var counts := {"jumps": 0, "uppercuts": 0, "lights": 0}
var checks := 0
var failures: Array[String] = []
var on_jumped: Callable
var on_move_started: Callable


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		print("FAIL: ", label)


func input_frame() -> Buffer.Frame:
	return Buffer.Frame.new()


func key_event(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)


func release_keys() -> void:
	key_event(KEY_W, false)
	key_event(KEY_J, false)
	key_event(KEY_SPACE, false)


func ticks(count: int) -> void:
	var target: int = p.tick_count + count
	while p.tick_count < target:
		await process_frame


func fresh_case() -> void:
	release_keys()
	p.clear_input_queue()
	p.set_injected_frame(null)
	stage._reset()
	d.position = Vector2(10000.0, stage.config.stage.bounds.floorY - 68.0)
	counts["jumps"] = 0
	counts["uppercuts"] = 0
	counts["lights"] = 0
	await ticks(2)
	p.clear_input_queue()
	p.set_injected_frame(null)


func press_w() -> void:
	key_event(KEY_W, true)


func press_j() -> void:
	key_event(KEY_J, true)


func press_space() -> void:
	key_event(KEY_SPACE, true)


func setup_signals() -> void:
	on_jumped = func(_is_double: bool) -> void:
		counts["jumps"] = int(counts["jumps"]) + 1
	on_move_started = func(move: Resource, _index: int) -> void:
		if move == stage.moves.up_strike or move == stage.moves.air_up:
			counts["uppercuts"] = int(counts["uppercuts"]) + 1
		elif move == stage.moves.light_1:
			counts["lights"] = int(counts["lights"]) + 1
	p.jumped.connect(on_jumped)
	p.move_started.connect(on_move_started)


func run() -> void:
	stage = load("res://scenes/training.tscn").instantiate()
	root.add_child(stage)
	current_scene = stage
	stage.config.runtime.autoReload = false
	p = stage.player
	d = stage.dummy
	setup_signals()
	await fresh_case()

	var air: Dictionary = Config.character(Config.read(), "player").get("airCombat", {})
	check(int(air.get("uppercutInputFrames", -1)) == 12,
			"uppercut order window is configurable at twelve physical frames")
	check(int(air.get("launcherJumpBonus", 0)) == 0 and int_prop(p, &"_bonus_air_jumps") == 0,
			"uppercut no longer creates bonus air jumps")

	# W then J: W starts the ordinary jump; J within the order window turns that
	# same jump into one uppercut without spending a second jump.
	await fresh_case()
	press_w()
	await ticks(1)
	var first_jump_velocity: float = p.velocity.y
	check(int(counts["jumps"]) == 1 and first_jump_velocity < 0.0,
			"W alone starts one normal jump before the uppercut follow-up")
	press_j()
	await ticks(1)
	check(p.current_move == stage.moves.up_strike and int(counts["uppercuts"]) == 1,
			"W then J within twelve frames converts into one ground uppercut")
	check(int(counts["jumps"]) == 1 and p.velocity.y < 0.0 and int_prop(p, &"_air_jumps_left") == p.extra_air_jumps,
			"W then J reuses the initial jump velocity and spends no extra jump")
	await ticks(16)
	check(int(counts["jumps"]) == 1 and int(counts["uppercuts"]) == 1,
			"holding W and J does not repeat the uppercut or jump")

	# J then W: a ground light attack can become the uppercut during the same
	# order window, with exactly one upward launch.
	await fresh_case()
	press_j()
	await ticks(1)
	check(p.current_move == stage.moves.light_1 and int(counts["lights"]) == 1,
			"J first starts the normal light attack")
	press_w()
	await ticks(1)
	check(p.current_move == stage.moves.up_strike and int(counts["uppercuts"]) == 1,
			"J then W within twelve frames converts the light into an uppercut")
	await ticks(stage.moves.up_strike.startup_frames + 1)
	check(int(counts["jumps"]) == 1 and p.velocity.y < 0.0 and int_prop(p, &"_air_jumps_left") == p.extra_air_jumps,
			"J then W performs one jump and preserves the normal second-jump budget")
	await ticks(16)
	check(int(counts["jumps"]) == 1 and int(counts["uppercuts"]) == 1,
			"holding the converted J+W chord does not retrigger it")

	# Simultaneous presses should resolve as one uppercut jump, not a normal jump
	# followed by a second launch.
	await fresh_case()
	press_w()
	press_j()
	await ticks(1)
	check(p.current_move == stage.moves.up_strike and int(counts["uppercuts"]) == 1,
			"simultaneous W+J resolves to one uppercut")
	await ticks(stage.moves.up_strike.startup_frames + 1)
	check(int(counts["jumps"]) == 1 and p.velocity.y < 0.0 \
			and int_prop(p, &"_air_jumps_left") == p.extra_air_jumps,
			"simultaneous W+J launches once without granting an extra jump")
	await ticks(16)
	check(int(counts["jumps"]) == 1 and int(counts["uppercuts"]) == 1,
			"holding simultaneous keys does not retrigger")

	# Pressing Space while W remains held is a new physical jump edge. It cancels
	# the uppercut and spends the ordinary second jump, even though the composite
	# jump action was already down from W.
	await fresh_case()
	press_w()
	await ticks(1)
	press_j()
	await ticks(1)
	await ticks(p.coyote_frames + 1)
	var jumps_before_space: int = int(counts["jumps"])
	press_space()
	await ticks(1)
	check(int(counts["jumps"]) == jumps_before_space + 1 and p.current_move == null \
			and int_prop(p, &"_air_jumps_left") == 0,
			"Space adds a distinct jump edge while W is held and cancels the uppercut")
	await fresh_case()
	press_w()
	press_j()
	await ticks(1)
	press_space()
	await ticks(1)
	check(p.current_move == null and int(counts["jumps"]) == 1,
			"Space can cancel uppercut windup before its scheduled takeoff")
	await ticks(stage.moves.up_strike.startup_frames + 4)
	check(int(counts["jumps"]) == 1, "cancelled uppercut never adds a delayed takeoff")

	# A jump outside the 12-frame conversion window still cancels the ordinary
	# attack as a regular jump, without turning it into an uppercut.
	await fresh_case()
	press_j()
	await ticks(1)
	await ticks(13)
	press_w()
	await ticks(1)
	check(int(counts["lights"]) == 1 and int(counts["uppercuts"]) == 0 \
			and int(counts["jumps"]) == 1 and p.velocity.y < 0.0,
			"late W cancels a basic attack with a normal jump after the uppercut window")

	await fresh_case()
	press_j()
	await ticks(1)
	press_space()
	await ticks(1)
	check(p.current_move == null and p.velocity.y < 0.0 and int(counts["jumps"]) == 1,
			"physical Space immediately cancels ordinary J startup")
	await fresh_case()
	press_j()
	await ticks(1)
	p.hitstop_frames = 6
	press_space()
	await ticks(1)
	check(p.current_move == null and p.hitstop_frames == 0 and int(counts["jumps"]) == 1,
			"physical Space cancels a basic attack's own hitstop")

	await fresh_case()
	press_w()
	await ticks(p.coyote_frames + 3)
	p._air_jumps_left = 0
	key_event(KEY_W, false)
	await ticks(1)
	var exhausted_jump_count: int = int(counts["jumps"])
	press_w()
	press_j()
	await ticks(stage.moves.up_strike.startup_frames + 3)
	check(int(counts["jumps"]) == exhausted_jump_count and p._air_jumps_left == 0,
			"uppercut input cannot create a free jump after the air budget is exhausted")

	# A hit reaction owns its state and hitstop: W cannot cancel it or queue a jump
	# that fires after the incoming freeze.
	for reaction in [Player.State.LAUNCHED, Player.State.DOWN]:
		await fresh_case()
		p.state = reaction
		p.position.y -= 220.0
		p.velocity = Vector2(0.0, 0.0)
		p.hitstop_frames = 3
		press_w()
		await ticks(1)
		check(p.hitstop_frames > 0 and int(counts["jumps"]) == 0,
				"jump input is rejected during incoming-hit hitstop in reaction state %d" % reaction)
		await ticks(8)
		check(int(counts["jumps"]) == 0 and p.velocity.y >= 0.0,
				"rejected reaction-state jump does not fire after hitstop (%d)" % reaction)
		await ticks(50)
		check(int(counts["jumps"]) == 0, "held jump is not replayed after damage recovery (%d)" % reaction)

	release_keys()
	p.jumped.disconnect(on_jumped)
	p.move_started.disconnect(on_move_started)
	stage.queue_free()
	await process_frame
	print("UPPERCUT_JUMP_TESTS: %d checks / %d failures" % [checks, failures.size()])
	OS.delay_msec(100)
	quit(1 if not failures.is_empty() else 0)


func int_prop(object: Object, key: StringName, fallback: int = 0) -> int:
	var value = object.get(key)
	return fallback if value == null else int(value)
