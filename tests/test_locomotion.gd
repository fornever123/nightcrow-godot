extends SceneTree
const Buffer := preload("res://scripts/core/input_buffer.gd")
var stage: Node2D
var p: CharacterBody2D
var view: Sprite2D
var checks := 0
var failures: Array[String] = []
var evidence: Array = []

func shot(label: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args():
		return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/first4-" + label + ".png")
	evidence.append({"label": label, "clip": view.clip_name, "frame": view.frame_index,
		"asset": view.setup.animations[view.clip_name].frames[view.frame_index].asset,
		"velocity": str(p.velocity), "onFloor": p.is_on_floor()})

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		print("FAIL: ", label)

func step(count: int, jump := false, run_right := false) -> void:
	var input := Buffer.Frame.new()
	if jump:
		input.actions = [&"jump"]
		input.pressed_this_frame = [&"jump"]
	if run_right:
		input.axis = Vector2.RIGHT
	p.set_injected_frame(input)
	var until: int = p.tick_count + count
	while p.tick_count < until:
		await process_frame

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	stage = load("res://scenes/training.tscn").instantiate()
	root.add_child(stage)
	current_scene = stage
	stage.config.runtime.autoReload = false
	p = stage.player
	view = p.get_node("Visual/ActorSprite")
	await step(10)
	for key in ["run", "jump", "fall", "land"]:
		check(view.setup.animations[key].get("source", {}).get("animation", "") == "mmh3_前4秒_试跑", key + " uses first-four-second source")
	await step(6, false, true)
	check(view.clip_name == "run", "movement plays running")
	await shot("run")
	await step(1, true)
	await step(3)
	check(view.clip_name == "jump", "rise plays jump")
	await shot("jump")
	for i in 60:
		if p.velocity.y > 0 and not p.is_on_floor():
			break
		await step(1)
	await step(1)
	check(view.clip_name == "fall", "descent switches to fall")
	await shot("fall")
	await step(1, true)
	await step(2)
	check(p.velocity.y < 0 and view.clip_name == "jump", "double jump restarts rise")
	for i in 90:
		if p.is_on_floor():
			break
		await step(1, false, true)
	await step(1, false, true)
	check(view.clip_name == "land", "landing plays even with movement held")
	await shot("land")
	await step(12, false, true)
	check(view.clip_name == "run", "running resumes after landing")
	await step(20)
	check(view.clip_name == "idle", "release returns to idle")
	view.setup.animations.jump.fullSequence = true
	await step(1, true)
	await step(22)
	check(p.velocity.y > 0 and view.clip_name == "jump", "legacy full jump keeps its continuous clock")
	if not evidence.is_empty():
		var record := FileAccess.open("res://docs/first4-locomotion-visual.json", FileAccess.WRITE)
		record.store_string(JSON.stringify(evidence, "  "))
	print("LOCOMOTION_TESTS: ", checks, " checks / ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
