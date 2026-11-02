extends SceneTree
## 开发工具（UI 会话 10-31）：左上“剑”HUD 动效逐帧录制（寒光 → 鸦羽一根根灌满 → 满了发光 → 连续挨打崩碎片 → 低血心跳 → 放大招羽毛四散）。
## 需要真实渲染（不加 --headless）：engine/Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/dev/hud_reel.gd --resolution 1280x720 --fixed-fps 60
## 每 2 帧存一张（30fps）到环境变量 SHOT_DIR，再用 ffmpeg 拼视频。
const Buffer := preload("res://scripts/core/input_buffer.gd")
var dir := ""
var stage
var p
var n := 0


func _initialize() -> void:
	call_deferred("run")


func tick(frames: int, each: Callable = Callable()) -> void:
	for i in frames:
		if each.is_valid():
			each.call()
		p.set_injected_frame(Buffer.Frame.new())
		await physics_frame
		if i % 2 == 0:
			await RenderingServer.frame_post_draw
			root.get_viewport().get_texture().get_image().save_png("%s/f_%04d.png" % [dir, n])
			n += 1


func run() -> void:
	dir = OS.get_environment("SHOT_DIR")
	DirAccess.make_dir_recursive_absolute(dir)
	stage = load("res://scenes/rain_trial.tscn").instantiate()
	root.add_child(stage)
	current_scene = stage
	await process_frame
	p = stage.player
	stage.encounter.clear_shades()
	stage.encounter.running = false
	p.reset_state(Vector2(stage._center_of(0) + 450.0, stage.floor_y - p.foot_offset))
	stage.hud.help_visible = false
	for i in 30:
		p.set_injected_frame(Buffer.Frame.new())
		await physics_frame
	stage.hud._banner_life = 0.0
	stage.hud._hint_t = 0.0
	stage._hint_queue.clear()
	p.ult_energy = 0.0
	var hold := func():
		stage.encounter.running = false
		stage._hint_queue.clear()
		stage.hud._hint_t = 0.0
	await tick(80, hold)                                   # 静止，等第一道寒光
	var t := [0]
	await tick(150, func():                                # 2.5 秒灌满
		hold.call()
		t[0] += 1
		p.ult_energy = p.ult_max * clampf(t[0] / 150.0, 0.0, 1.0))
	await tick(120, hold)                                  # 满了
	for hp in [72.0, 41.0, 18.0]:                          # 连续挨打
		p.hp = hp
		stage.hud.hurt()
		await tick(42, hold)
	await tick(60, hold)                                   # 低血心跳
	p.ult_energy = 0.0                                     # 放大招
	await tick(80, hold)
	print("REEL_DONE ", n)
	quit()
