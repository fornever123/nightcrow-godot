extends SceneTree
## [YG-MARK] 由 YG 新增（首页「断晓 · 断光」移植自查用截图脚本）。
## engine/Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/dev/yg_title_shot.gd --resolution 1280x720
## 截图目录：环境变量 SHOT_DIR，默认 .runtime/yg-title-shots。
## 用 fast_forward(秒) 定步快进，和网页版的 ?at=秒 逐帧对齐。

var dir := ""
var title: Control

const STEPS := [
	[0.9, "01_进场_雨"],
	[2.1, "02_光升"],
	[3.0, "03_字成"],
	[3.72, "04_出刀"],
	[3.90, "05_冲击帧"],
	[4.30, "06_斩后"],
	[5.10, "07_菜单进"],
	[6.60, "08_待机"],
]


func _initialize() -> void:
	call_deferred("run")


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, name])
	print("SHOT ", name)


func run() -> void:
	dir = OS.get_environment("SHOT_DIR")
	if dir == "":
		dir = ProjectSettings.globalize_path("res://.runtime/yg-title-shots")
	DirAccess.make_dir_recursive_absolute(dir)
	title = load("res://scenes/yg_title_duanguang.tscn").instantiate()
	root.add_child(title)
	current_scene = title
	await process_frame
	await process_frame
	for step in STEPS:
		title.fast_forward(float(step[0]))
		await process_frame
		await process_frame
		await shot(step[1])
	# 菜单选择 / 操作说明 / 设置 / 确认（[YG-MARK] 11-05：「继续」换成「操作说明」，加手柄提示）
	title.ui.sel = 1
	await process_frame
	await process_frame
	await shot("09_选中操作说明")
	title._menu_confirm()
	await process_frame
	await process_frame
	await shot("09b_操作说明")
	title._close_help()
	title.ui.sel = 2
	title._menu_confirm()
	title.ui.rsel = 3
	await process_frame
	await process_frame
	await shot("10_设置")
	title.ui.pad_mode = true
	await process_frame
	await process_frame
	await shot("10b_设置_手柄提示")
	title.ui.pad_mode = false
	title._close_settings()
	title.ui.sel = 3
	title._menu_confirm()
	await process_frame
	await process_frame
	await shot("11_确认离开")
	title._close_confirm()
	title.sim.player_slash(300.0, 540.0, 1000.0, 380.0)
	title.fast_forward(title.sim.now + 0.10)
	await process_frame
	await process_frame
	await shot("12_玩家挥刀")
	print("CAP_DONE")
	quit()
