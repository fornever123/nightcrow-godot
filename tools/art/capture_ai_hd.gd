extends SceneTree
## Short actual-render probes, no full automated playthrough. AI_HD_SCENE=night/training.
const HD := preload("res://scripts/presentation/ai_hd_visuals.gd")
const Buffer := preload("res://scripts/core/input_buffer.gd")
var stage: Node2D
var player: CharacterBody2D
var view: Sprite2D
var records: Array = []
var directory: String

func _initialize() -> void:
	call_deferred("run")

func shot(label: String, clip: String, index: int, facing: int) -> void:
	player._set_facing(facing)
	view.clip_name = clip
	view.clock = float(index) / float(view.setup.animations[clip].get("fps", 24))
	view._draw_frame()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var path := directory.path_join(label + ".png")
	var result := root.get_texture().get_image().save_png(path)
	records.append({"label": label, "clip": clip, "sourceIndex": view.frame_index, "hd": view.hd_active, "facing": facing, "material": str(view.material), "scale": str(view.scale), "offset": str(view.offset), "path": path, "saveError": result})

func run() -> void:
	HD.initialize()
	if HD.clips.is_empty():
		push_error("AI HD manifest unavailable; prepare assets first")
		quit(1)
		return
	HD.enabled = true
	var scene := "night" if OS.get_environment("AI_HD_SCENE") == "night" else "training"
	directory = "res://docs/ai-hd-visual/" + scene
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	root.content_scale_size = Vector2i(1280, 720)
	stage = load("res://scenes/night_trial.tscn" if scene == "night" else "res://scenes/training.tscn").instantiate()
	root.add_child(stage)
	current_scene = stage
	stage.config.runtime.autoReload = false
	player = stage.player
	player.set_injected_frame(Buffer.Frame.new())
	for i in 25:
		await process_frame
	stage.set_physics_process(false)
	player.set_physics_process(false)
	view = player.get_node("Visual/ActorSprite")
	view.set_physics_process(false)
	view.stance_clip = ""
	player.state = player.State.NEUTRAL
	player.current_move = null
	player.velocity = Vector2.ZERO
	# Same rendering path/material as normal play, frozen at a short set of poses.
	await shot("idle_right", "idle", 0, 1)
	await shot("idle_left", "idle", 0, -1)
	await shot("attack_right", "attack_1", 12, 1)
	await shot("attack_left", "attack_1", 12, -1)
	player.position.y -= 100
	await shot("airborne_right", "jump", 3, 1)
	await shot("air_attack_left", "air_attack_1", 12, -1)
	player.position.y += 100
	await shot("guard_right", "guard_hold", 0, 1)
	HD.enabled = false
	for child in view.get_children():
		if child.get_script() == HD:
			child._update_caption()
	await shot("original_idle", "idle", 0, 1)
	var file := FileAccess.open(directory.path_join("capture.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(records, "  "))
	file.close()
	print("AI_HD_CAPTURE: ", scene, " / ", records.size(), " screenshots")
	stage.free()
	await process_frame
	quit()
