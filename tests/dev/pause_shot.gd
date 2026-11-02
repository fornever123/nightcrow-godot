extends SceneTree
## 开发工具（UI 会话 10-31）：暂停菜单实机截图（打开过程 / 主菜单 / 银线划过 / 操作说明 / 设置）。
## 需要真实渲染（不加 --headless）：engine/Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/dev/pause_shot.gd --resolution 1280x720 --fixed-fps 60
## 截图目录：环境变量 SHOT_DIR。
var dir := ""


func _initialize() -> void:
	call_deferred("run")


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, name])
	print("SHOT ", name)


func wait_ms(ms: int) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		await process_frame


func run() -> void:
	dir = OS.get_environment("SHOT_DIR")
	DirAccess.make_dir_recursive_absolute(dir)
	var stage = load("res://scenes/rain_trial.tscn").instantiate()
	root.add_child(stage)
	current_scene = stage
	await process_frame
	var p = stage.player
	p.reset_state(Vector2(stage._center_of(0) - 1180.0, 580.0 - p.foot_offset))
	for i in 200:
		await physics_frame
	await shot("暂停_0_打开前")
	var m = stage.pause_menu
	m.open()
	await wait_ms(150)
	await shot("暂停_1_打开中")
	await wait_ms(700)
	await shot("暂停_2_主菜单")
	m._move(1)
	await wait_ms(90)
	await shot("暂停_3_银线划过")
	await wait_ms(400)
	m._select(2)
	m._activate()
	await wait_ms(600)
	await shot("暂停_4_操作说明")
	m._back()
	m._select(3)
	m._activate()
	await wait_ms(600)
	await shot("暂停_5_设置")
	print("CAP_DONE")
	quit()
