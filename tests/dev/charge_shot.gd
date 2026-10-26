extends SceneTree
## Actual native gameplay captures for the imported charge and persistent jump.
const Buffer := preload("res://scripts/core/input_buffer.gd")

func _initialize() -> void:
	call_deferred("run")

func frame(held := true, jump := false) -> Buffer.Frame:
	var f := Buffer.Frame.new()
	if held:
		f.actions = [&"attack_light"]
	if jump:
		f.actions.append(&"jump")
		f.pressed_this_frame = [&"jump"]
	return f

func save_shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)

func run() -> void:
	var folder := OS.get_environment("SHOT_DIR")
	if folder.is_empty():
		folder = ProjectSettings.globalize_path("res://.runtime/charge-20261026/shots")
	DirAccess.make_dir_recursive_absolute(folder)
	var stage = load("res://scenes/night_trial.tscn").instantiate()
	root.add_child(stage)
	current_scene = stage
	await process_frame
	stage.set_physics_process(false)
	stage.encounter.set_physics_process(false)
	stage.encounter.set_process(false)
	stage.hud.help_visible = false
	stage.hud._banner = ""
	stage.hud._banner_life = 0.0
	var p = stage.player
	p.reset_state(Vector2(1400, stage.floor_y-p.foot_offset))
	p._set_facing(1)
	p.set_injected_frame(frame(false))
	stage.camera.global_position = Vector2(1550, stage.CAM_Y)
	for i in 20:
		await physics_frame
	p._start_charge()
	var hold_shots := {0:"01_开始蓄力",38:"02_跳跃中保持蓄力",100:"03_落地后继续蓄力",160:"04_蓄满保持"}
	for i in 180:
		p.set_injected_frame(frame(true, i == 20 or i == 30))
		await physics_frame
		if hold_shots.has(i):
			await save_shot(folder+"/"+hold_shots[i]+".png")
	assert(p.is_charging() and p.charge_frames >= 150, "Full charge must still be held")
	p.set_injected_frame(frame(false))
	while p.current_move != p.charge_move:
		await physics_frame
	var release_shots := {10:"05_释放起手",26:"06_起跳下劈",40:"07_下劈轨迹",52:"08_落地冲击",60:"09_冲击余波",130:"10_收招"}
	var saved := {}
	for i in 260:
		await physics_frame
		var cursor: int = p.move_frame
		for desired in release_shots:
			if cursor >= desired and not saved.has(desired):
				saved[desired] = true
				await save_shot(folder+"/"+release_shots[desired]+".png")
		if p.current_move == null:
			break
	print("CHARGE_NATIVE_CAPTURE_OK: hold/jump/land/release; ",saved.size()," release shots")
	stage.free()
	await process_frame
	quit()
