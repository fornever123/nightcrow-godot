extends SceneTree
## 开发工具：第一章 1-1A「灯影空轿街」两层街样板角实机截图（街面、步廊、阳台、接缝）。
## 需要真实渲染（不要加 --headless）：
##   engine/Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/dev/capture_rain_entry.gd --resolution 1280x720
## 截图目录：环境变量 SHOT_DIR（默认 res://.runtime/shots_ch1_1a）；RAIN_OLD_BG=1 拍 11-12 旧版做对比。
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
		d = ProjectSettings.globalize_path("res://.runtime/shots_ch1_1a")
	DirAccess.make_dir_recursive_absolute(d)
	return d


func shot(name: String) -> void:
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(_dir() + "/%s.png" % name)
	print("SHOT %s player=(%.0f, %.0f) cam=%s max=%s seal=%d" % [name, p.global_position.x, p.global_position.y + p.foot_offset, stage.camera.get_screen_center_position(), stage.camera.arena_max, stage.seal_walls.size()])


func frames(n: int) -> void:
	for i in n:
		p.set_injected_frame(fr())
		await physics_frame


func place(x: float, feet: float, settle: int = 70) -> void:
	if stage.encounter != null:
		stage.encounter.clear_shades()
		stage.encounter.running = false
	if x > 6800.0:    # 拍 J1：先解开 1-1A 封印墙和镜头右边界
		if stage.seal_walls.size() > 0:
			stage._unlock_arena()
			stage.encounter_index += 1    # 当作 1-1A 已封印，免得走回触发线又锁上
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
		[1700.0, 580.0, "00_entry_to_1a"], [2250.0, 580.0, "01_stairs"], [2750.0, 580.0, "02_carriage"],
		[3000.0, 288.4, "03_deck"], [3000.0, 106.7, "04_balcony_b1"], [3863.0, 580.0, "05_seam_b1b2"],
		[4020.0, 580.0, "06_gap_street"], [3900.0, 288.4, "07_gap_deck"], [4500.0, 88.0, "08_balcony_b2"],
		[4816.0, 580.0, "09_seam_b2b3"], [5200.0, 123.0, "10_balcony_b3"], [5700.0, 580.0, "11_arch_b3"],
		[6400.0, 580.0, "12_gate"], [6840.0, 580.0, "13_seam_j1"],
		[7200.0, 580.0, "14_j1_stairs"], [6950.0, 323.2, "15_j1_landing"], [7600.0, 113.0, "16_j1_high_road"],
		[7700.0, 580.0, "17_j1_low_arch"], [8250.0, 580.0, "18_j1_to_next"],
	]
	if OS.get_environment("SPOTS_X") != "":    # 和改前扫图同一批 x（街面），做并排对比
		spots = []
		for xs in OS.get_environment("SPOTS_X").split(","):
			spots.append([float(xs), 580.0, "x%05d" % int(float(xs))])
	for spot in spots:
		await place(spot[0], spot[1])
		if stage.get("hud") != null:
			stage.hud._banner = ""
		await shot(spot[2])
	print("RAIN_ENTRY_CAPTURE_DONE ", _dir())
	quit()
