extends SceneTree
const Buffer := preload("res://scripts/core/input_buffer.gd")
var stage: Node2D
var p: CharacterBody2D
var view: Sprite2D
var records: Array = []
func _initialize() -> void:
	call_deferred("run")
func ticks(count: int) -> void:
	var target: int = p.tick_count + count
	while p.tick_count < target:
		await process_frame
func shot(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/desktop-actions-visual/"+label+".png")
	records.append({"label":label,"clip":view.clip_name,"frame":view.frame_index,
		"position":str(p.position),"spriteScale":str(view.scale),"facing":p.facing})
func run() -> void:
	root.content_scale_size=Vector2i(1280,720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://docs/desktop-actions-visual"))
	stage=load("res://scenes/training.tscn").instantiate()
	root.add_child(stage)
	current_scene=stage
	stage.config.runtime.autoReload=false
	p=stage.player
	view=p.get_node("Visual/ActorSprite")
	await ticks(15)
	await shot("draw")
	await ticks(125)
	await shot("idle")
	p._start_move(stage.moves.light_1,false)
	await ticks(1)
	await shot("light_1_prepare")
	for key in ["light_1","light_2","light_3","up_strike","dash_slash","dash_slash_left"]:
		stage._reset()
		p.position.x=430
		p._set_facing(-1 if key=="dash_slash_left" else 1)
		p._start_move(stage.moves[key], key=="up_strike")
		await ticks(stage.moves[key].startup_frames+2)
		await shot(key)
	stage._reset()
	var input:=Buffer.Frame.new()
	input.actions=[&"jump"]
	input.pressed_this_frame=[&"jump"]
	p.set_injected_frame(input)
	await ticks(1)
	p.set_injected_frame(Buffer.Frame.new())
	await ticks(10)
	await shot("jump")
	await ticks(28)
	await shot("fall")
	stage._reset()
	input=Buffer.Frame.new()
	input.axis=Vector2.RIGHT
	p.set_injected_frame(input)
	await ticks(10)
	await shot("run")
	input=Buffer.Frame.new()
	input.axis=Vector2.LEFT
	p.set_injected_frame(input)
	await ticks(20)
	await shot("turn")
	stage._reset()
	input=Buffer.Frame.new()
	input.actions=[&"parry"]
	input.pressed_this_frame=[&"parry"]
	p.set_injected_frame(input)
	await ticks(5)
	await shot("guard_start")
	input=Buffer.Frame.new()
	input.actions=[&"parry"]
	p.set_injected_frame(input)
	await ticks(40)
	await shot("guard_hold")
	stage._reset()
	p.set_injected_frame(Buffer.Frame.new())
	for key in ["air_light_1","air_light_2","air_light_3"]:
		p._end_attack()
		p.position=Vector2(500,280)
		p.velocity=Vector2.ZERO
		p._start_move(stage.moves[key],false)
		await ticks(stage.moves[key].startup_frames+2)
		await shot(key)
	stage._reset()
	p.set_injected_frame(Buffer.Frame.new())
	await ticks(500)
	await shot("sheathe")
	for key in ["parry_react_1","parry_react_2","parry_react_3"]:
		stage._reset()
		p._start_move(stage.moves[key],false)
		await ticks(12)
		await shot(key)
	p._die()
	await ticks(150)
	await shot("death")
	await ticks(175)
	await shot("death_last")
	var record:=FileAccess.open("res://docs/desktop-actions-visual.json",FileAccess.WRITE)
	record.store_string(JSON.stringify(records,"  "))
	stage.free()
	OS.delay_msec(100)
	await process_frame
	print("DESKTOP_CAPTURE_COMPLETE: ",records.size())
	quit()
