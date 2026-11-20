extends SceneTree
## 开发工具：首页真实流程（进场定格 → 按“开始游戏” → 切到雨街试玩）。需要真实渲染：
##   engine/Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/dev/title_cut_flow.gd --resolution 1280x720

func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var dir := ProjectSettings.globalize_path("res://.runtime/cut-flow")
	DirAccess.make_dir_recursive_absolute(dir)
	var t: Control = load("res://scenes/title_cut.tscn").instantiate()
	root.add_child(t)
	current_scene = t
	await process_frame
	await process_frame
	t.seek(5.4)
	t.seek_mode = false
	t.clock = 5.4
	t.phase = t.Phase.IDLE
	await process_frame
	t._activate()
	var switched := false
	for i in 240:
		await process_frame
		if current_scene != null and current_scene.scene_file_path != "res://scenes/title_cut.tscn":
			switched = true
			break
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(dir + "/flow_after_start.png")
	print("SWITCHED ", switched, " SCENE ", current_scene.scene_file_path if current_scene != null else "none")
	print("FLOW_DONE")
	quit()
