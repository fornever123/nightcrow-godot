extends SceneTree

const Configuration = preload("res://scripts/core/configuration.gd")

func _initialize() -> void:
	var result := {}
	var definitions: Dictionary = Configuration.moves(Configuration.read())
	for id in definitions:
		var move = definitions[id]
		result[String(id)] = {
			"startup_frames": move.startup_frames,
			"active_frames": move.active_frames,
			"recovery_frames": move.recovery_frames,
			"cancel_frame": move.cancel_frame,
		}
	print("MODIFIER_MOVES_JSON:" + JSON.stringify(result))
	quit()
