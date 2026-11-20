extends SceneTree
## 开发工具：进雨街，按住右键跑一段，隔几帧截一张，专门看新的跑步帧接入效果。
## 需要真实渲染（不能用 --headless）：
##   engine/Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/dev/run_shot.gd
## 截图目录：环境变量 SHOT_DIR，默认 res://docs/视觉设计/角色动作/跑步重做_20261102/实机
const Buffer := preload("res://scripts/core/input_buffer.gd")
var stage
var p
var view
var tick := 0
var shot_at := {}
var dir := ""
var names := ["跑_01", "跑_02", "跑_03", "跑_04", "跑_05", "跑_06", "跑_07", "跑_08"]

func _initialize() -> void:
	call_deferred("run")

func fr(actions: Array[StringName] = [], edges: Array[StringName] = [], axis := Vector2.ZERO) -> Buffer.Frame:
	var f := Buffer.Frame.new()
	f.actions = actions
	f.pressed_this_frame = edges
	f.axis = axis
	return f

func shot(name: String) -> void:
	dir = OS.get_environment("SHOT_DIR")
	if dir.is_empty():
		dir = ProjectSettings.globalize_path("res://docs/视觉设计/角色动作/跑步重做_20261102/实机")
	DirAccess.make_dir_recursive_absolute(dir)
	var img := get_root().get_texture().get_image()
	var path := dir.path_join(name + ".png")
	img.save_png(path)
	print("SHOT ", path)

func run() -> void:
	var scene: PackedScene = load("res://scenes/rain_trial.tscn")
	stage = scene.instantiate()
	get_root().add_child(stage)
	current_scene = stage
	await process_frame
	await process_frame
	p = stage.player
	view = p.get_node("Visual/ActorSprite")
	p.global_position = Vector2(float(stage.spawn_x if stage.get("spawn_x") != null else 1000), p.global_position.y)
	# 先站定几帧
	for i in 20:
		p.set_injected_frame(fr([], [], Vector2.ZERO))
		await physics_frame
	# 按住右键（冲刺斩）/方向跑：这里只按方向，看纯跑步循环
	for i in 8:
		shot_at[i] = 2 + i * 3
	for i in 120:
		p.set_injected_frame(fr([&"move_right"], [], Vector2.RIGHT))
		await physics_frame
		tick += 1
		for k in 8:
			if shot_at[k] == tick:
				shot(names[k])
	print("DONE clip=", view.clip_name, " frame=", view.frame_index)
	quit()


