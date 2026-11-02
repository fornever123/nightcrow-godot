extends SceneTree
## 临时截图：走廊（门楼 + 廊桥起点）实机（真实渲染，不加 --headless）。只摆位置，不改任何参数。
const Buffer := preload("res://scripts/core/input_buffer.gd")
var stage
var p
var c0 := 0.0
var out := ""


func _initialize() -> void:
	out = OS.get_environment("SHOT_DIR")
	DirAccess.make_dir_recursive_absolute(out)
	call_deferred("run")


func fr(actions: Array[StringName] = [], edges: Array[StringName] = [], axis := Vector2.ZERO) -> Buffer.Frame:
	var f := Buffer.Frame.new()
	f.actions = actions
	f.pressed_this_frame = edges
	f.axis = axis
	return f


func frames(n: int, f: Buffer.Frame = null) -> void:
	for i in n:
		p.set_injected_frame(f if f != null else fr())
		await physics_frame


func place(x: float, feet: float, facing: int = 1, settle: int = 70) -> void:
	stage.encounter.clear_shades()
	stage.encounter.running = false
	stage.camera.arena_max = Vector2(c0 + 6000.0, stage.camera.arena_max.y)
	p.reset_state(Vector2(c0 + x, feet - p.foot_offset))
	p._set_facing(facing)
	await frames(settle)


func shot(name: String) -> void:
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(out + "/%s.png" % name)
	print("SHOT %s player=(%.0f, %.0f) cam=(%.0f, %.0f)" % [name, p.global_position.x - c0, p.global_position.y, stage.camera.global_position.x - c0, stage.camera.global_position.y])


func run() -> void:
	stage = load("res://scenes/rain_street.tscn").instantiate()
	root.add_child(stage)
	await process_frame
	p = stage.player
	stage.hud.help_visible = false
	await frames(30)
	c0 = stage._center_of(0)
	p.reset_state(Vector2(c0 - 1900.0, stage.floor_y - p.foot_offset))
	await frames(90, fr([&"move_right"], [], Vector2(1, 0)))
	stage.hud._banner = ""
	stage.hud._banner_life = 0.0
	var spots := [
		["C1_seam_street", 2450, 580, 1],
		["C2_gate_street", 2820, 580, 1],
		["C3_arch_street", 3330, 580, 1],
		["C4_gate_balcony", 2810, 293.06, 1],
		["C5_gate_roof", 2810, -262.8, 1],
		["C6_gallery", 3500, 15.8, 1],
		["C7_gallery_end", 3900, 15.8, -1],
	]
	for s in spots:
		await place(s[1], s[2], s[3])
		await shot(s[0])
	print("CAP_DONE ", out)
	quit()
