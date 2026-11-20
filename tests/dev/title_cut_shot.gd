extends SceneTree
## 开发工具：首页（scenes/title_cut.tscn）关键帧截图。需要真实渲染（不加 --headless）：
##   engine/Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/dev/title_cut_shot.gd --resolution 1280x720
## 截图目录：环境变量 SHOT_DIR，默认 .runtime/cut-shots。

var dir := ""
var t: Control


func _initialize() -> void:
	call_deferred("run")


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, name])
	print("SHOT ", name)


func run() -> void:
	dir = OS.get_environment("SHOT_DIR")
	if dir == "":
		dir = ProjectSettings.globalize_path("res://.runtime/cut-shots")
	DirAccess.make_dir_recursive_absolute(dir)
	t = load("res://scenes/title_cut.tscn").instantiate()
	root.add_child(t)
	current_scene = t
	await process_frame
	await process_frame
	var times := [0.55, 1.20, 1.85, 2.40, 2.58, 2.63, 2.70, 2.86, 3.30, 4.20, 5.40]
	for tt in times:
		t.seek(tt)
		await process_frame
		await process_frame
		await shot("首页_%05.2f" % tt)
	t.seek(5.40)
	await process_frame
	t._select(1)
	await process_frame
	await shot("首页_菜单_选中二")
	t._go_page(t.Page.HELP, 0)
	t._page_ms = Time.get_ticks_msec() - 2000
	await process_frame
	await shot("首页_操作说明")
	t._go_page(t.Page.SETTINGS, 0)
	t._page_ms = Time.get_ticks_msec() - 2000
	await process_frame
	await shot("首页_设置")
	t._go_page(t.Page.MAIN, 0)
	t.seek(5.40)
	t.phase = t.Phase.GO
	t.go_t = 0.06
	t._apply(5.40)
	await process_frame
	await shot("首页_开始_二刀")
	t.go_t = 0.40
	t._apply(5.40)
	await process_frame
	await shot("首页_开始_收黑")
	print("CAP_DONE")
	quit()
