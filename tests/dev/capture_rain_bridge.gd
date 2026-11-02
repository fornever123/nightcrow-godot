extends SceneTree
## 开发工具：雨夜河岸街廊桥段（第 2 处封印，素材包拼接）的固定实机截图。
## 需要真实渲染（不要加 --headless）：
##   engine/Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/dev/capture_rain_bridge.gd --resolution 1280x720
## 截图目录：环境变量 SHOT_DIR（默认 res://.runtime/shots_rain_bridge）
const Buffer := preload("res://scripts/core/input_buffer.gd")
const Shade := preload("res://scripts/night/shade.gd")
var stage
var p
var c1 := 0.0


func _initialize() -> void:
	call_deferred("run")


func fr(actions: Array[StringName] = [], edges: Array[StringName] = []) -> Buffer.Frame:
	var f := Buffer.Frame.new()
	f.actions = actions
	f.pressed_this_frame = edges
	return f


func _dir() -> String:
	var d := OS.get_environment("SHOT_DIR")
	if d == "":
		d = ProjectSettings.globalize_path("res://.runtime/shots_rain_bridge")
	DirAccess.make_dir_recursive_absolute(d)
	return d


func shot(name: String) -> void:
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(_dir() + "/%s.png" % name)
	print("SHOT %s player=(%.0f, %.0f)" % [name, p.global_position.x - c1, p.global_position.y + p.foot_offset])


func frames(n: int, f: Buffer.Frame = null) -> void:
	for i in n:
		p.set_injected_frame(f if f != null else fr())
		await physics_frame


func place(x: float, feet: float, settle: int = 90) -> void:
	stage.encounter.clear_shades()
	stage.encounter.running = false
	p.reset_state(Vector2(c1 + x, feet - p.foot_offset))
	stage.camera.global_position.x = c1 + x    # 瞬移很远，镜头平滑追不上：直接放过去
	stage.camera.reset_smoothing()
	await frames(settle)


func shade(kind: int, x: float, feet: float, facing: int) -> void:
	var sh: Node2D = Node2D.new()
	sh.set_script(Shade)
	sh.setup(kind, p, stage.floor_y, 1.0)
	sh.position = Vector2(c1 + x, feet - 60.0)
	sh.terrain = stage.terrain
	stage.add_child(sh)
	sh.spawn_frames = 0
	sh.active = false
	sh.facing = facing
	stage._on_shade_spawned(sh)


func run() -> void:
	stage = load("res://scenes/rain_street.tscn").instantiate()
	root.add_child(stage)
	await process_frame
	p = stage.player
	stage.hud.help_visible = false
	c1 = stage._center_of(1)
	# 直接把流程推进到第 2 处封印（走进去、封印、清场都跳过），镜头才会放到这一段
	await frames(5)
	stage.encounter_index = 1
	stage._ensure_terrain(1)
	stage.back_wall.position.x = c1 - 2600.0
	for spot in [[-2050.0, 580.0, "01_left_street"], [-600.0, 580.0, "02_center_street"], [-1017.0, 300.0, "03_pier_ledge"],
			[-1500.0, 20.0, "04_gallery"], [-100.0, -77.2, "05_tower_balcony"], [700.0, 580.0, "06_gate"], [2200.0, 580.0, "07_stairs"]]:
		await place(spot[0], spot[1])
		stage.hud._banner = ""
		await shot(spot[2])
	await place(-700.0, 580.0)
	shade(Shade.Kind.GRUNT, -520.0, 580.0, -1)
	shade(Shade.Kind.BRUTE, -950.0, 580.0, 1)
	shade(Shade.Kind.ARCHER, -1000.0, 20.0, 1)
	await frames(20)
	await frames(1, fr([&"attack_light"], [&"attack_light"]))
	await frames(9)
	await shot("08_combat")
	print("RAIN_BRIDGE_CAPTURE_DONE ", _dir())
	quit()
