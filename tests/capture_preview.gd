extends SceneTree
var stage: Node2D
var p: CharacterBody2D
func _initialize() -> void:
	call_deferred("capture")
func ticks(count: int) -> void:
	var target: int = p.tick_count + count
	while p.tick_count < target:
		await physics_frame
	await process_frame
func shot(filename: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/"+filename)
func capture() -> void:
	root.content_scale_size = Vector2i(1280,720)
	stage = load("res://scenes/training.tscn").instantiate()
	root.add_child(stage)
	current_scene=stage
	p=stage.player
	stage.config.runtime.autoReload=false
	await ticks(15)
	await shot("game-idle.png")
	p._start_move(stage.moves.light_3,false)
	while p.move_frame<15:
		await physics_frame
	await shot("game-slash.png")
	await ticks(18)
	await shot("game-trail.png")
	print("CAPTURE_COMPLETE")
	quit()
