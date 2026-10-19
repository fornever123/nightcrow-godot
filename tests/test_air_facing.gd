extends SceneTree

const Buffer := preload("res://scripts/core/input_buffer.gd")

var stage: Node2D
var player: CharacterBody2D
var view: Sprite2D
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		print("FAIL: ", label)

func step(count: int, axis := Vector2.ZERO, jump := false) -> void:
	var input := Buffer.Frame.new()
	input.axis = axis
	if jump:
		input.actions = [&"jump"]
		input.pressed_this_frame = [&"jump"]
	player.set_injected_frame(input)
	var until: int = player.tick_count + count
	while player.tick_count < until:
		await process_frame

func check_air_clip_facing(key: String, direction: int) -> void:
	# Read from the actual source PNGs: rise faces left, descent faces right.
	var native_facing := -1 if key == "jump" else 1
	var actual_facing := int(signf(player.get_node("Visual").scale.x * view.scale.x * float(native_facing)))
	check(actual_facing == direction,
		"%s art faces movement direction %d (render transform resolves %d)" % [key, direction, actual_facing])

func run() -> void:
	stage = load("res://scenes/training.tscn").instantiate()
	root.add_child(stage)
	current_scene = stage
	stage.config.runtime.autoReload = false
	player = stage.player
	view = player.get_node("Visual/ActorSprite")
	await step(3)
	await step(1, Vector2.RIGHT, true)
	await step(3, Vector2.RIGHT)
	check(view.clip_name == "jump", "rising uses jump clip")
	check_air_clip_facing("jump", 1)
	await step(1, Vector2.LEFT)
	check(player.facing == -1, "airborne left input changes logical facing left")
	check_air_clip_facing("jump", -1)
	for i in 70:
		if player.velocity.y > 0.0 and not player.is_on_floor():
			break
		await step(1, Vector2.LEFT)
	check(view.clip_name == "fall", "descent uses fall clip")
	check_air_clip_facing("fall", -1)
	await step(1, Vector2.RIGHT)
	check(player.facing == 1, "airborne right input changes logical facing right")
	check_air_clip_facing("fall", 1)
	print("AIR_FACING_TESTS: ", checks, " checks / ", failures.size(), " failures")
	stage.queue_free()
	await process_frame
	OS.delay_msec(100)
	quit(0 if failures.is_empty() else 1)
