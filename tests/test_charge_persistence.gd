extends SceneTree
## Charging remains a persistent stance through voluntary movement and jumps.
const Buffer := preload("res://scripts/core/input_buffer.gd")
const Training := preload("res://scenes/training.tscn")

var stage: Node2D
var p: CharacterBody2D
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		print("FAIL: ", label)

func frame(actions: Array[StringName] = [], edges: Array[StringName] = [], axis := Vector2.ZERO) -> Buffer.Frame:
	var f := Buffer.Frame.new()
	f.actions = actions
	f.pressed_this_frame = edges
	f.axis = axis
	return f

func step(input: Buffer.Frame = null) -> void:
	p.set_injected_frame(frame() if input == null else input)
	var target: int = p.tick_count + 1
	while p.tick_count < target:
		await process_frame

func key(code: Key, down: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = down
	Input.parse_input_event(event)

func ticks(count: int) -> void:
	var until: int = p.tick_count + count
	while p.tick_count < until:
		await process_frame

func run() -> void:
	stage = Training.instantiate()
	root.add_child(stage)
	current_scene = stage
	stage.config.runtime.autoReload = false
	p = stage.player
	await process_frame
	await process_frame
	stage._reset()
	p.clear_input_queue()
	stage.dummy.position = Vector2(10000, stage.config.stage.bounds.floorY - 68)
	await step()

	# W+jump and Space/jump both leave the charge timer alive; then release still slashes.
	p._start_charge()
	p.charge_frames = 8
	await step(frame([&"attack_light", &"jump"], [&"jump"]))
	check(p.charge_frames >= 0 and p.velocity.y < 0.0,
		"jumping with the charge button held preserves charge and starts a normal jump")
	var accrued: int = p.charge_frames
	await step(frame([&"attack_light", &"jump"]))
	check(p.charge_frames > accrued and p.velocity.y < 0.0,
		"airborne charging continues accumulating without hover")

	# Explicit W+J while charging is steering/jump input, not an uppercut takeover.
	p.set_injected_frame(frame([&"attack_light", &"jump", &"aim_up"], [&"attack_light", &"aim_up", &"jump"]))
	var target: int = p.tick_count + 1
	while p.tick_count < target:
		await process_frame
	check(p.charge_frames >= 0 and p.current_move == null,
		"W+J while charging does not replace the charge with an uppercut")
	while p.charge_frames < p.charge_move.min_charge_frames - 1:
		await step(frame([&"attack_light", &"jump"]))
	var before_release: int = p.charge_frames
	await step(frame())
	check(p.charge_frames < 0 and p.current_move == p.charge_move and p.last_charge_frames >= before_release,
		"releasing after a charge jump emits the accumulated charge attack")

	# Grounding does not clear the persistent stance either.
	stage._reset()
	p.clear_input_queue()
	stage.dummy.position = Vector2(10000, stage.config.stage.bounds.floorY - 68)
	await step()
	p._start_charge()
	p.charge_frames = p.charge_move.min_charge_frames
	p.velocity = Vector2.ZERO
	p.position.y = stage.config.stage.bounds.floorY - p.foot_offset
	await step(frame([&"attack_light"]))
	var before_landing_release: int = p.charge_frames
	check(p.charge_frames >= 0 and p.is_on_floor(), "landing while charging keeps the stance active")
	await step(frame())
	check(p.current_move == p.charge_move and p.last_charge_frames >= before_landing_release,
		"release after landing uses the charge accumulated before contact")

	# Actual W then Space while J is held (not only injected action edges).
	stage._reset()
	p.clear_input_queue()
	p.set_injected_frame(null)
	stage.dummy.position.x = 10000
	await ticks(3)
	key(KEY_J, true)
	p._start_charge()
	await ticks(22)
	var physical_before: int = p.charge_frames
	key(KEY_W, true)
	await ticks(2)
	check(p.is_charging() and p.velocity.y < 0 and p.charge_frames > physical_before,
		"physical W while J held jumps without losing accumulated charge")
	key(KEY_SPACE, true)
	await ticks(2)
	check(p.is_charging() and p.velocity.y < 0 and p._air_jumps_left == 0,
		"physical Space while W held spends second jump and preserves charge")
	key(KEY_SPACE, false)
	key(KEY_W, false)
	await ticks(p.charge_move.max_charge_frames + 30)
	check(p.is_charging() and p.is_on_floor(), "full charge stays held through descent and real landing")
	var fully_held: int = p.charge_frames
	key(KEY_D, true)
	var move_start: float = p.position.x
	await ticks(20)
	check(p.position.x > move_start + 100 and p.charge_frames > fully_held,
		"movement after landing preserves full charge and keeps accumulating")
	key(KEY_D, false)
	key(KEY_J, false)
	await ticks(2)
	check(p.current_move == p.charge_move and p.last_charge_frames >= fully_held,
		"physical J release after landing emits the preserved full charge")
	stage._reset()
	p.clear_input_queue()
	await ticks(3)
	key(KEY_J, true)
	p._start_charge()
	await ticks(5)
	p.invuln_frames = 0
	p.take_hit(p.light_combo[0], -p.facing, p.global_position)
	check(not p.is_charging(), "real incoming damage still interrupts charge; no accidental armor")
	key(KEY_J, false)
	stage._reset()
	check(not p.is_charging(), "reset clears charge normally")

	print("Charge persistence: %d checks, %d failures" % [checks, failures.size()])
	stage.free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
