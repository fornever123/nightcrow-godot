extends SceneTree
## 截弦 · 实机截图。
## engine/Godot_v4.7.2-stable_win64_console.exe --path . --script res://dsh/tests/shot_chord.gd --resolution 1280x720

var dir := "res://.runtime/chord"
var scene: Node = null


func _initialize() -> void:
	call_deferred("run")


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("%s/%s.png" % [dir, name]))
	print("SHOT ", name)


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _wait_thread(min_t: float = 0.70, limit: int = 900) -> bool:
	for i in limit:
		await physics_frame
		for th in scene.threads:
			if is_instance_valid(th) and not th.dead and th.t >= min_t:
				return true
	return false


func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	scene = load("res://dsh/scenes/chord_trial.tscn").instantiate()
	root.add_child(scene)
	await _frames(24)
	await _shot("01_title")

	scene._started = true
	scene._start_act(0)
	await _frames(36)
	await _shot("02_act0_start")

	# 停在「弦绷紧」的一瞬
	var got := await _wait_thread(0.72)
	await _shot("03_thread_taut")
	print("thread taut: ", got)

	# 截断（完美）
	if scene.threads.size() > 0:
		var th = scene.threads[0]
		scene.player.pos = Vector2(th.end.x - 150.0, scene.ground_y)
		scene.player.facing = 1
		await _frames(2)
		scene.cut_thread(th, 0.98, 9999)
		await _frames(2)
		await _shot("04_cut_jue")
		await _frames(16)
		await _shot("05_after_cut")

	# 刷满刀鞘：直接给三张符，看 HUD
	scene.arts = ["jian", "zhang", "gu"]
	scene.meter = 100.0
	await _frames(4)
	await _shot("06_sheath_full")

	# 进一折：伞影
	for e in scene.enemies:
		if is_instance_valid(e):
			e.take_hit(999.0, 0.0)
	await _frames(190)
	scene.player.pos = Vector2(scene.acts[1].spawnX + 260.0, scene.ground_y)
	await _frames(30)
	await _shot("07_act1_san")

	var got2 := await _wait_thread(0.80)
	await _shot("08_act1_fan")
	print("fan taut: ", got2)

	# 进二折：鼓台
	for e in scene.enemies:
		if is_instance_valid(e):
			e.take_hit(999.0, 0.0)
	await _frames(190)
	await _shot("09_act2_gu")
	var got3 := await _wait_thread(0.80)
	await _shot("10_act2_threat")

	# 进三折：判官
	for e in scene.enemies:
		if is_instance_valid(e):
			e.take_hit(999.0, 0.0)
	await _frames(200)
	await _shot("11_boss")
	var got4 := await _wait_thread(0.78)
	await _shot("12_boss_thread")
	print("boss taut: ", got4)

	# 断幕
	scene.meter = 100.0
	scene.try_ult()
	await _frames(3)
	await _shot("13_ult")
	await _frames(20)

	# 结算
	for e in scene.enemies:
		if is_instance_valid(e):
			e.take_hit(9999.0, 0.0)
	await _frames(260)
	await _shot("14_result")
	print("phase=", scene.phase, " rank=", scene.rank)
	quit()
