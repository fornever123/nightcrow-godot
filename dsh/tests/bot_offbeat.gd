extends SceneTree
## 机器人：验证三波能打完、结算能出来、整个循环没有运行时错误。

func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var scene: Node = load("res://dsh/scenes/offbeat_trial.tscn").instantiate()
	root.add_child(scene)
	for i in 3600:
		await physics_frame
		if not is_instance_valid(scene):
			break
		scene.player.hp = 100.0
		var alive: Array = scene.shades_alive()
		if alive.size() > 0:
			var s = alive[0]
			scene.player.position = Vector2(s.logic_pos.x - 162.0, 580.0)
			scene.player.facing = 1
			scene.player.vel = Vector2.ZERO
			if i % 42 == 0:
				scene.player._start_attack(1)
		if i % 180 == 0:
			print("f%d wave=%d/%s delay=%.2f combo=%d hits=%d" % [
				i, int(scene.wave_index), String(scene.wave_state), float(scene.delay),
				int(scene.combo), int(scene.hit_count)])
		if String(scene.wave_state) == "done":
			print("DONE hits=%d max_combo=%d beat=%.2f" % [
				int(scene.hit_count), int(scene.max_combo), float(scene.beat_ratio())])
			break
	quit()
