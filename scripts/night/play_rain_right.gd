extends SceneTree
## Convenience entry: the normal finite rain trial, starting beside the new art.
func _initialize() -> void:
	call_deferred("start")

func start() -> void:
	var stage = load("res://scenes/rain_trial.tscn").instantiate()
	root.add_child(stage)
	current_scene = stage
	await process_frame
	stage.player.reset_state(Vector2(stage._center_of(0) + 450.0, stage.floor_y - stage.player.foot_offset))
