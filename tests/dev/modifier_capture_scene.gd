extends SceneTree
## 开发工具：截修改器场景改动后的雨街实机画面（要真实渲染，不加 --headless）。
##   NIGHTCROW_TUNING=1 SHOT_DIR=<目录> engine/Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/dev/modifier_capture_scene.gd --resolution 1280x720
## NIGHTCROW_TUNING=0 截默认画面作对照。
const Buffer := preload("res://scripts/core/input_buffer.gd")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var dir := OS.get_environment("SHOT_DIR")
	if dir == "":
		dir = ProjectSettings.globalize_path("res://.runtime/shots_modifier_scene")
	DirAccess.make_dir_recursive_absolute(dir)
	var stage: Node = load("res://scenes/rain_street.tscn").instantiate()
	root.add_child(stage)
	await process_frame
	var p: Node2D = stage.player
	stage.hud.help_visible = false
	for i in 5:
		p.set_injected_frame(Buffer.Frame.new())
		await physics_frame
	var center: float = stage._center_of(0)
	stage.encounter_index = 0
	stage._ensure_terrain(0)
	for spot in [[-1600.0, 580.0, "a_left"], [300.0, 580.0, "b_clock"], [300.0, 300.0, "c_clock_balcony"], [1900.0, 580.0, "d_right"]]:
		stage.encounter.clear_shades()
		stage.encounter.running = false
		p.reset_state(Vector2(center + spot[0], spot[1] - p.foot_offset))
		stage.camera.global_position.x = center + spot[0]
		stage.camera.reset_smoothing()
		for i in 60:
			p.set_injected_frame(Buffer.Frame.new())
			await physics_frame
		stage.hud._banner = ""
		await process_frame
		await process_frame
		root.get_viewport().get_texture().get_image().save_png(dir + "/%s.png" % spot[2])
		print("SHOT %s feet=%.1f" % [spot[2], p.global_position.y + p.foot_offset])
	print("MODIFIER_SCENE_CAPTURE_DONE ", dir)
	quit()
