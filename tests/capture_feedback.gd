extends SceneTree
const Buffer := preload("res://scripts/core/input_buffer.gd")
var stage: Node2D
var p: CharacterBody2D
var proof: Dictionary = {}
func _initialize() -> void:
	call_deferred("capture")
func ticks(count: int) -> void:
	var target: int = p.tick_count+count
	while p.tick_count<target:
		await process_frame
func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/"+name+".png")
	proof[name] = {"moveFrame":p.move_frame,"imageFrame":p.get_node("Visual/ActorSprite").frame_index,"playerHitstop":p.hitstop_frames,"dummyHitstop":stage.dummy.hitstop_frames,"shake":stage.camera.offset,"sound":stage.audio.last_event}
func hit() -> void:
	for tick in 60:
		if stage.total_hits>0:
			return
		await ticks(1)
func capture() -> void:
	root.content_scale_size=Vector2i(1280,720)
	stage=load("res://scenes/training.tscn").instantiate()
	root.add_child(stage)
	current_scene=stage
	stage.config.runtime.autoReload=false
	p=stage.player
	p.set_injected_frame(Buffer.Frame.new())
	await ticks(12)
	await shot("feedback-idle")
	p._start_move(stage.moves.light_1,false)
	await hit()
	await shot("feedback-light")
	await ticks(2)
	await shot("feedback-light-hold")
	stage._reset()
	await ticks(4)
	p._charge_t=1.0
	p._start_move(stage.moves.charge_1,false)
	await hit()
	await shot("feedback-charge")
	var file:=FileAccess.open("res://docs/combat-feedback-proof.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(proof,"  "))
	file.close()
	print("FEEDBACK_CAPTURE_COMPLETE")
	stage.free()
	OS.delay_msec(100)
	quit()
