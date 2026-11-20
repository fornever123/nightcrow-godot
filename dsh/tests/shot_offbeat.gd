extends SceneTree
## 开发工具：错拍试炼场截图。
## engine/Godot_v4.7.2-stable_win64_console.exe --path . --script res://dsh/tests/shot_offbeat.gd --resolution 1280x720

var dir := "res://.runtime/offbeat"


func _initialize() -> void:
	call_deferred("run")


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("%s/%s.png" % [dir, name]))
	print("SHOT ", name)


func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var scene: Node = load("res://dsh/scenes/offbeat_trial.tscn").instantiate()
	root.add_child(scene)
	for i in 90:
		await physics_frame
	await _shot("01_start")
	for i in 60:
		await physics_frame
	await _shot("02_approach")
	for i in 45:
		await physics_frame
	await _shot("03_windup")

	# 把玩家挪到第一个敌人的影身旁边，打一刀，截「命中影身」的瞬间
	var alive: Array = scene.shades_alive()
	if alive.size() > 0:
		var s = alive[0]
		scene.player.position = Vector2(s.logic_pos.x - 96.0, 580.0)
		scene.player.facing = 1
		for i in 4:
			await physics_frame
		scene.player._start_attack(1)
		for i in 17:
			await physics_frame
		await _shot("05_hit_ghost")
		for i in 30:
			await physics_frame
		await _shot("06_after")
	quit()
