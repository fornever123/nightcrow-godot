extends SceneTree
## 开发工具：夜景静帧截图（需要真实渲染：DISPLAY=:99 godot --path . --script res://tests/dev/scene_shot.gd --resolution 1280x720）
## 环境变量 SHOT_DIR（默认 res://.runtime/shots）；XS="300,900,1500" 依次把角色放到这些 x 截图。
const Buffer := preload("res://scripts/core/input_buffer.gd")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var dir := OS.get_environment("SHOT_DIR")
	if dir == "":
		dir = ProjectSettings.globalize_path("res://.runtime/shots")
	DirAccess.make_dir_recursive_absolute(dir)
	var stage = load("res://scenes/night_trial.tscn").instantiate()
	root.add_child(stage)
	await process_frame
	var p = stage.player
	var xs := (OS.get_environment("XS") if OS.get_environment("XS") != "" else "300,1000").split(",")
	var idle := Buffer.Frame.new()
	for sx in xs:
		var x := float(sx)
		stage.set_physics_process(false)
		p.reset_state(Vector2(x, stage.floor_y - p.foot_offset))
		p.set_injected_frame(idle)
		stage.camera.global_position = Vector2(x, 360)
		for i in 40:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_viewport().get_texture().get_image().save_png("%s/scene_x%d.png" % [dir, int(x)])
		print("shot ", x)
	quit()
