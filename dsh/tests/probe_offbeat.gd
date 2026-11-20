extends SceneTree
## 探针：确认影身 / 本体的状态差与位置差。

func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var scene: Node = load("res://dsh/scenes/offbeat_trial.tscn").instantiate()
	root.add_child(scene)
	for i in 480:
		await physics_frame
		if i % 20 == 0 and i > 40:
			var line := "f%d delay=%.2f  " % [i, float(scene.delay)]
			for s in scene.shades_alive():
				line += "[%s logic=%d present=%d off=%.0f]" % [
					s.kind, int(s.state), int(s.present.get("state", -1)),
					(s.logic_pos - s.present_pos).length()]
			print(line)
	print("hp=", scene.player.hp, " combo=", scene.combo, " hits=", scene.hit_count)
	quit()
