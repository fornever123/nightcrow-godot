extends SceneTree
## 截弦 · 机器人：从头打到「弦尽」，验证四折、截弦、夺招、放招、破朱、断幕、结算。
## engine/Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://dsh/tests/bot_chord.gd

var scene: Node = null


func _initialize() -> void:
	call_deferred("run")


func _log(msg: String) -> void:
	print(msg)


func run() -> void:
	scene = load("res://dsh/scenes/chord_trial.tscn").instantiate()
	root.add_child(scene)
	for i in 8:
		await physics_frame
	scene._started = true
	scene._start_act(0)
	var frames := 0
	var last_phase := ""
	while frames < 9000:
		await physics_frame
		frames += 1
		if not is_instance_valid(scene):
			break
		# 调试：不让机器人死，专测流程
		scene.player.hearts = scene.player.max_hearts
		scene.hearts = scene.player.hearts
		var alive: Array = scene.enemies_alive()
		if alive.size() > 0:
			var e = alive[0]
			scene.player.pos = Vector2(e.pos.x - 190.0, scene.ground_y)
			scene.player.vel = Vector2.ZERO
			scene.player.facing = 1
			if frames % 11 == 0:
				scene.player._start_attack(1 + (frames / 11) % 3)
			if scene.arts.size() > 0 and frames % 83 == 0:
				scene.release_art(0)
			if scene.meter >= 100.0 and frames % 47 == 0:
				scene.try_ult()
		if String(scene.phase) != last_phase:
			last_phase = String(scene.phase)
			_log("f%d phase=%s act=%d enemy=%d threads=%d arts=%d meter=%.0f" % [
				frames, last_phase, int(scene.act_index), alive.size(),
				scene.threads.size(), scene.arts.size(), float(scene.meter)])
		if frames % 420 == 0:
			_log("  f%d act=%d/%s enemies=%d 绝%d 截%d 断%d 夺%d 破朱%d" % [
				frames, int(scene.act_index) + 1, String(scene.phase), alive.size(),
				int(scene.stat_jue), int(scene.stat_jie), int(scene.stat_duan),
				int(scene.stat_arts), int(scene.stat_broke)])
		if String(scene.phase) == "result":
			_log("RESULT rank=%s 绝%d 截%d 断%d 夺%d 破朱%d frames=%d" % [
				String(scene.rank), int(scene.stat_jue), int(scene.stat_jie),
				int(scene.stat_duan), int(scene.stat_arts), int(scene.stat_broke), frames])
			break
		if String(scene.phase) == "dead":
			_log("BOT DIED")
			break
	_log("BOT END frames=%d phase=%s act=%d" % [frames, String(scene.phase), int(scene.act_index)])
	quit()
