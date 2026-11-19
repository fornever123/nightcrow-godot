extends SceneTree
## 开发工具（背景线 11-18 立体感试验）：1-1A 街面从左往右走一段，逐帧存图，拼成走路视频看视差 / 前景 / 灯影。
## 需要真实渲染（不要加 --headless）：
##   SHOT_DIR=... RAIN_DEPTH=0|A|B engine/Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/dev/capture_relief_walk.gd --resolution 1280x720
## WALK_FROM / WALK_FRAMES 可改起点和帧数；每 2 个物理帧存一张（30fps 成片）。
const Buffer := preload("res://scripts/core/input_buffer.gd")
var stage
var p


func _initialize() -> void:
	call_deferred("run")


func fr(ax: float) -> Buffer.Frame:
	var f := Buffer.Frame.new()
	f.axis = Vector2(ax, 0.0)
	return f


func run() -> void:
	var d := OS.get_environment("SHOT_DIR")
	DirAccess.make_dir_recursive_absolute(d)
	stage = load("res://scenes/rain_trial.tscn").instantiate()
	stage.enable_ch1_shadow_street(true)
	root.add_child(stage)
	await process_frame
	p = stage.player
	if stage.get("hud") != null:
		stage.hud.help_visible = false
	if stage.encounter != null:
		stage.encounter.clear_shades()
		stage.encounter.running = false
	var x0 := float(OS.get_environment("WALK_FROM")) if OS.get_environment("WALK_FROM") != "" else 2700.0
	var n := int(OS.get_environment("WALK_FRAMES")) if OS.get_environment("WALK_FRAMES") != "" else 240
	p.reset_state(Vector2(x0, 580.0 - p.foot_offset))
	stage.camera.global_position.x = x0
	stage.camera.reset_smoothing()
	for i in 40:
		p.set_injected_frame(fr(0.0))
		await physics_frame
	for i in n:
		if stage.encounter != null:
			stage.encounter.running = false
		p.set_injected_frame(fr(1.0))
		await physics_frame
		if i % 2 == 0:
			if stage.get("hud") != null:
				stage.hud._banner = ""
			root.get_viewport().get_texture().get_image().save_jpg(d + "/f%04d.jpg" % (i / 2), 0.9)
	print("WALK_DONE x=", p.global_position.x, " ", d)
	quit()
