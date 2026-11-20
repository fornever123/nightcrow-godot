extends SceneTree
## 开发工具：首页（scenes/title.tscn）实机截图。需要真实渲染（不加 --headless）：
## engine/Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/dev/title_shot.gd --resolution 1280x720
## 截图目录：环境变量 SHOT_DIR，默认 .runtime/title-shots。
var dir := ""
var title: Control


func _initialize() -> void:
	call_deferred("run")


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, name])
	print("SHOT ", name)


func run() -> void:
	dir = OS.get_environment("SHOT_DIR")
	if dir == "":
		dir = ProjectSettings.globalize_path("res://.runtime/title-shots")
	DirAccess.make_dir_recursive_absolute(dir)
	title = load("res://scenes/title.tscn").instantiate()
	root.add_child(title)
	current_scene = title
	await process_frame
	for t in [0.9, 2.0, 2.9, 3.45, 3.72, 4.1, 5.9]:
		title.seek(t)
		await process_frame
		await process_frame
		await shot("首页_%04.2f" % t)
	title.seek(6.0)
	await process_frame
	await shot("首页_6.00_待机")
	title._select(1)
	await process_frame
	await shot("首页_6.01_选中第二项")
	title._select(2)
	title._activate()
	await process_frame
	await shot("首页_6.02_设置")
	title._back()
	title._select(1)
	title._activate()
	await process_frame
	await shot("首页_6.03_操作说明")
	title._back()
	title._select(0)
	title._activate()
	await process_frame
	title.art.clock = title._start_at + 0.10
	await process_frame
	await shot("首页_7.00_开始_出刀")
	title.art.clock = title._start_at + 0.55
	await process_frame
	await shot("首页_7.01_开始_收黑")
	print("CAP_DONE")
	quit()
