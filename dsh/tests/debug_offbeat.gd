extends SceneTree
## 调试：为什么命中会停住。

func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var scene: Node = load("res://dsh/scenes/offbeat_trial.tscn").instantiate()
	root.add_child(scene)
	for i in 1200:
		await physics_frame
		scene.player.hp = 100.0
		var alive: Array = scene.shades_alive()
		if alive.size() > 0:
			var s = alive[0]
			scene.player.position = Vector2(s.logic_pos.x - 162.0, 580.0)
			scene.player.facing = 1
			scene.player.vel = Vector2.ZERO
			if i % 42 == 0:
				scene.player._start_attack(1)
		if i % 60 == 0:
			var info := "f%d wave=%d/%s hits=%d delay=%.2f alive=%d" % [
				i, int(scene.wave_index), String(scene.wave_state), int(scene.hit_count),
				float(scene.delay), alive.size()]
			for s in alive:
				info += " | %s st=%d hp=%.0f x=%.0f lx=%.0f" % [
					s.kind, int(s.state), float(s.hp), s.position.x, s.logic_pos.x]
			print(info)
			print("   player x=%.0f mode=%d atk=%d mt=%.2f" % [
				scene.player.position.x, int(scene.player.mode), int(scene.player.attack_index),
				float(scene.player.mode_t)])
	quit()
