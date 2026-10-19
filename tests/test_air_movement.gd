extends SceneTree
## Normal airborne J must leave jump motion unchanged; deliberate finishers are excluded.
const Buffer := preload("res://scripts/core/input_buffer.gd")
const Training := preload("res://scenes/training.tscn")

var stage: Node2D
var p: CharacterBody2D
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		print("FAIL: ", label)

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

func capture_jump(attack_at: int = -1, move_right: bool = true) -> Array[Dictionary]:
	stage._reset()
	p.clear_input_queue()
	p.position.x = 300.0
	stage.dummy.position = Vector2(10000, stage.config.stage.bounds.floorY - 68)
	await step()
	var origin_y := p.global_position.y
	var initial_actions: Array[StringName] = []
	initial_actions.append(&"jump")
	if move_right:
		initial_actions.append(&"move_right")
	await step(frame(initial_actions, [&"jump"], Vector2.RIGHT if move_right else Vector2.ZERO))
	var samples: Array[Dictionary] = [{"x": p.global_position.x, "y": p.global_position.y,
		"vx": p.velocity.x, "vy": p.velocity.y, "move": p.current_move, "origin_y": origin_y}]
	var n := 1
	while n < 240 and not p.is_on_floor():
		n += 1
		var actions: Array[StringName] = []
		if move_right:
			actions.append(&"move_right")
		var axis := Vector2.RIGHT if move_right else Vector2.ZERO
		var input := frame(actions, [], axis)
		if n - 1 == attack_at:
			actions.append(&"attack_light")
			input = frame(actions, [&"attack_light"], axis)
		await step(input)
		samples.append({"x": p.global_position.x, "y": p.global_position.y,
			"vx": p.velocity.x, "vy": p.velocity.y, "move": p.current_move})
	return samples

func capture_air_combo(attack_at: int) -> Dictionary:
	stage._reset()
	p.clear_input_queue()
	p.position.x = 300.0
	stage.dummy.position = Vector2(10000, stage.config.stage.bounds.floorY - 68)
	await step()
	var origin_y := p.global_position.y
	await step(frame([&"jump"], [&"jump"]))
	var samples: Array[Dictionary] = [{"x": p.global_position.x, "y": p.global_position.y,
		"vx": p.velocity.x, "vy": p.velocity.y, "move": p.current_move, "origin_y": origin_y}]
	var ids: Array[String] = []
	var on_move := func(move: Resource, _index: int) -> void:
		if p.air_combo.has(move):
			ids.append(String(move.get("id")))
	p.move_started.connect(on_move)
	var n := 1
	while n < 240 and not p.is_on_floor():
		n += 1
		var input := frame()
		if n - 1 == attack_at:
			input = frame([&"attack_light"], [&"attack_light"])
		elif p.current_move != null and p.air_combo.has(p.current_move) and ids.size() > 0 and ids.size() < 3:
			var mv: Resource = p.current_move
			var chain_at: int = mv.startup_frames + mv.active_frames + mv.cancel_frame - 1
			if p.move_frame == chain_at:
				input = frame([&"attack_light"], [&"attack_light"])
		await step(input)
		samples.append({"x": p.global_position.x, "y": p.global_position.y,
			"vx": p.velocity.x, "vy": p.velocity.y, "move": p.current_move})
	p.move_started.disconnect(on_move)
	return {"samples": samples, "ids": ids}

func phase_frame(samples: Array[Dictionary], phase: String) -> int:
	var best := -1
	var score := INF
	var peak := samples.size() - 1
	for i in range(samples.size()):
		if float(samples[i].y) < float(samples[peak].y):
			peak = i
	var end := peak if phase == "apex" else samples.size()
	for i in range(8, end):
		var vy := float(samples[i].vy)
		if phase == "rise" and vy < -200.0:
			return i
		if phase == "apex" and absf(vy) < score:
			score = absf(vy)
			best = i
		if phase == "fall" and vy > 180.0:
			return i
	return best

func compare_trajectory(base: Array[Dictionary], attacked: Array[Dictionary], phase: String) -> void:
	var same := base.size() == attacked.size()
	var first_bad := -1
	for i in range(mini(base.size(), attacked.size())):
		var a: Dictionary = base[i]
		var b: Dictionary = attacked[i]
		if absf(float(a.y) - float(b.y)) > 0.01 or absf(float(a.vy) - float(b.vy)) > 0.01 \
				or absf(float(a.x) - float(b.x)) > 0.01 or absf(float(a.vx) - float(b.vx)) > 0.01:
			same = false
			first_bad = i
			break
	check(same, "%s attack keeps jump x/y and velocity trajectory (first differing tick %d; lengths %d/%d)" %
		[phase, first_bad, base.size(), attacked.size()])

func run() -> void:
	stage = Training.instantiate()
	root.add_child(stage)
	current_scene = stage
	stage.config.runtime.autoReload = false
	p = stage.player
	await process_frame
	await process_frame
	check(is_equal_approx(p.speed, 680.0), "player run speed is doubled to 680")
	check(is_equal_approx(p.jump_height, 340.0), "jump height is doubled to 340")
	check(is_equal_approx(p.max_fall_speed, 1105.0), "fall terminal speed is reduced to 1105")
	check(is_equal_approx(p._fall_gravity, 2.0 * 170.0 / (0.26 * 0.26) * 0.85),
		"fall acceleration is reduced by 15 percent despite the doubled jump height")
	check(is_equal_approx(p.acceleration, 12000.0) and is_equal_approx(p.deceleration, 14400.0),
		"acceleration and braking double with run speed")

	var base := await capture_jump()
	var peak_i := 0
	for i in range(base.size()):
		if float(base[i].y) < float(base[peak_i].y):
			peak_i = i
	var height := float(base[0].origin_y) - float(base[peak_i].y)
	check(height >= p.jump_height * 0.93 and height <= p.jump_height * 1.06,
		"uninterrupted jump reaches the configured height (measured %.1f / %.1f)" % [height, p.jump_height])

	for phase in ["rise", "apex", "fall"]:
		var at := phase_frame(base, phase)
		var attacked := await capture_jump(at)
		var attack_move: Variant = attacked[at].move if at >= 0 and at < attacked.size() else null
		var attack_id := String(attack_move.get("id")) if attack_move is Resource else ""
		check(attack_id == "air_light_1",
			"normal J actually starts an airborne attack during %s" % phase)
		compare_trajectory(base, attacked, phase)

	var neutral_base: Array[Dictionary] = await capture_jump(-1, false)
	var chain_at: int = phase_frame(neutral_base, "rise")
	var chained: Dictionary = await capture_air_combo(chain_at)
	check(chained.ids == ["air_light_1", "air_light_2", "air_light_3"],
		"normal J still completes the three-stage aerial chain: %s" % [chained.ids])
	compare_trajectory(neutral_base, chained.samples, "three-stage neutral-axis chain")

	stage.queue_free()
	await process_frame
	# Allow the real audio thread to finish releasing the test's short WAV voices.
	OS.delay_msec(100)
	await process_frame
	print("AIR_MOVEMENT_TESTS: %d checks / %d failures" % [checks, failures.size()])
	quit(1 if not failures.is_empty() else 0)
