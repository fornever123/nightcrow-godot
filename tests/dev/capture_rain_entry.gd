extends SceneTree
## 开发工具：正式游戏（rain_trial + 第一章影街布局）开局入口街的固定实机截图，从最左的新近景一路走到第一章影街接缝。
## 需要真实渲染（不要加 --headless）：
##   engine/Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/dev/capture_rain_entry.gd --resolution 1280x720
## 截图目录：环境变量 SHOT_DIR（默认 res://.runtime/shots_rain_entry）；RAIN_OLD_BG=1 拍 11-12 旧版做对比。
const Buffer := preload("res://scripts/core/input_buffer.gd")
var stage
var p


func _initialize() -> void:
	call_deferred("run")


func fr() -> Buffer.Frame:
	return Buffer.Frame.new()


func _dir() -> String:
	var d := OS.get_environment("SHOT_DIR")
	if d == "":
		d = ProjectSettings.globalize_path("res://.runtime/shots_rain_entry")
	DirAccess.make_dir_recursive_absolute(d)
	return d


func shot(name: String) -> void:
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(_dir() + "/%s.png" % name)
	print("SHOT %s player=(%.0f, %.0f)" % [name, p.global_position.x, p.global_position.y + p.foot_offset])


func frames(n: int) -> void:
	for i in n:
		p.set_injected_frame(fr())
		await physics_frame


func place(x: float, feet: float, settle: int = 70) -> void:
	if stage.encounter != null:
		stage.encounter.clear_shades()
		stage.encounter.running = false
	p.reset_state(Vector2(x, feet - p.foot_offset))
	stage.camera.global_position.x = x
	stage.camera.reset_smoothing()
	await frames(settle)


func run() -> void:
	stage = load("res://scenes/rain_trial.tscn").instantiate()
	stage.enable_ch1_shadow_street(true)
	root.add_child(stage)
	await process_frame
	p = stage.player
	if stage.get("hud") != null:
		stage.hud.help_visible = false
	await frames(5)
	var spots := [
		[-2600.0, 580.0, "00_far_left"], [-1500.0, 580.0, "01_n2_left"], [-700.0, 580.0, "02_n2_arch"],
		[300.0, 580.0, "03_spawn"], [900.0, 580.0, "04_n1_left"], [1520.0, 580.0, "05_arch"],
		[1520.0, 137.7, "06_balcony"], [2000.0, 580.0, "07_seam"], [2500.0, 580.0, "08_ch1"],
	]
	for spot in spots:
		await place(spot[0], spot[1])
		if stage.get("hud") != null:
			stage.hud._banner = ""
		await shot(spot[2])
	print("RAIN_ENTRY_CAPTURE_DONE ", _dir())
	quit()
