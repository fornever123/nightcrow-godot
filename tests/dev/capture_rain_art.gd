extends SceneTree
## 开发工具：雨夜河岸街成图段（钟楼广场左半，标杆 v9.2）的固定实机截图。
## 需要真实渲染（不要加 --headless）：
##   engine/Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/dev/capture_rain_art.gd --resolution 1280x720
## 三组固定画面（M3 要求）：普通战斗 / 大招 / 跨层追击；另有几张取景和视差对照。不改任何战斗参数，只摆位置。
## 截图目录：环境变量 SHOT_DIR（默认 res://.runtime/shots_rain_art）
const Buffer := preload("res://scripts/core/input_buffer.gd")
const Shade := preload("res://scripts/night/shade.gd")
var stage
var p
var c0 := 0.0


func _initialize() -> void:
	call_deferred("run")


func fr(actions: Array[StringName] = [], edges: Array[StringName] = [], axis := Vector2.ZERO) -> Buffer.Frame:
	var f := Buffer.Frame.new()
	f.actions = actions
	f.pressed_this_frame = edges
	f.axis = axis
	return f


func _dir() -> String:
	var d := OS.get_environment("SHOT_DIR")
	if d == "":
		d = ProjectSettings.globalize_path("res://.runtime/shots_rain_art")
	DirAccess.make_dir_recursive_absolute(d)
	return d


func shot(name: String) -> void:
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(_dir() + "/%s.png" % name)
	print("SHOT %s player=(%.0f, %.0f) cam=(%.0f, %.0f)" % [name, p.global_position.x - c0, p.global_position.y, stage.camera.global_position.x - c0, stage.camera.global_position.y])


func frames(n: int, f: Buffer.Frame = null) -> void:
	for i in n:
		p.set_injected_frame(f if f != null else fr())
		await physics_frame


## 把主角放到 (相对封印中心 x, 脚底 y)，清场，等镜头跟稳
func place(x: float, feet: float, facing: int = 1, settle: int = 60) -> void:
	stage.encounter.clear_shades()
	stage.encounter.running = false
	p.reset_state(Vector2(c0 + x, feet - p.foot_offset))
	p._set_facing(facing)
	await frames(settle)


func shade(kind: int, x: float, feet: float, facing: int) -> Node2D:
	var sh: Node2D = Node2D.new()
	sh.set_script(Shade)
	sh.setup(kind, p, stage.floor_y, 1.0)
	sh.position = Vector2(c0 + x, feet - 60.0)
	sh.terrain = stage.terrain
	stage.add_child(sh)
	sh.spawn_frames = 0
	sh.active = false
	sh.facing = facing
	stage._on_shade_spawned(sh)
	return sh


func run() -> void:
	stage = load("res://scenes/rain_street.tscn").instantiate()
	root.add_child(stage)
	await process_frame
	p = stage.player
	stage.hud.help_visible = false
	await frames(30)
	c0 = stage._center_of(0)
	# 走进竞技场让封印和镜头进入战斗状态，然后清场摆位
	p.reset_state(Vector2(c0 - 1900.0, stage.floor_y - p.foot_offset))
	await frames(90, fr([&"move_right"], [], Vector2(1, 0)))
	stage.hud._banner = ""
	stage.hud._banner_life = 0.0

	# ---- 取景：三处街面 + 屋顶，看分层和光
	await place(-2000, 580, 1)
	await shot("00_view_left")
	await place(-1180, 580, 1)
	await shot("00_view_mid")
	await place(-420, 580, -1)
	await shot("00_view_right")
	await place(-1770, -300, 1, 90)
	await shot("00_view_roof")

	# ---- ① 普通战斗：街面，商住楼前；楼上有影弓
	await place(-1180, 580, 1)
	shade(Shade.Kind.GRUNT, -1000, 580, -1)
	shade(Shade.Kind.GRUNT, -880, 580, -1)
	shade(Shade.Kind.BRUTE, -1460, 580, 1)
	shade(Shade.Kind.ARCHER, -1050, 305, -1)
	shade(Shade.Kind.ARCHER, -760, 40, -1)
	await frames(20)
	await frames(1, fr([&"attack_light"], [&"attack_light"]))
	await frames(9)
	await shot("01_combat_a")
	await frames(1, fr([&"attack_light"], [&"attack_light"]))
	await frames(12)
	await shot("01_combat_b")

	# ---- ② 大招：同一处
	await place(-1180, 580, 1)
	for k in [[Shade.Kind.GRUNT, -1000, 580], [Shade.Kind.GRUNT, -900, 580], [Shade.Kind.BRUTE, -1450, 580], [Shade.Kind.ARCHER, -1050, 305]]:
		shade(k[0], k[1], k[2], -1 if k[1] > -1180 else 1)
	await frames(20)
	p.ult_energy = p.ult_max
	await frames(10)
	await frames(1, fr([&"attack_light", &"attack_ranged"], [&"attack_light", &"attack_ranged"]))
	# 大招前段是全屏立绘看不到场景；后段在场景里（黑白、拉近）
	var want := {46: "02_ult_cut1", 150: "02_ult_f150", 170: "02_ult_f170", 190: "02_ult_f190", 215: "02_ult_f215", 240: "02_ult_f240"}
	var done := {}
	for i in 400:
		p.set_injected_frame(fr())
		await physics_frame
		var f: int = p.ult_frame
		if f < 0 and i > 10:
			break
		if want.has(f) and not done.has(f):
			done[f] = true
			await shot(want[f])

	# ---- ③ 跨层追击：从街面跳上会馆二层阳台追影弓，二层还有影卒；空中、落上阳台各一张
	await place(-1640, 580, -1)
	shade(Shade.Kind.ARCHER, -1880, 285, 1)
	shade(Shade.Kind.GRUNT, -1450, 305, -1)
	shade(Shade.Kind.GRUNT, -2150, 580, 1)
	await frames(10)
	await frames(1, fr([&"jump", &"move_left"], [&"jump"], Vector2(-1, 0)))
	await frames(13, fr([&"jump", &"move_left"], [], Vector2(-1, 0)))
	await shot("03_chase_air")
	await frames(40, fr([&"move_left"], [], Vector2(-1, 0)))
	await frames(20)
	await shot("03_chase_balcony")

	# ---- 视差对照：同一镜头高度，横向挪 300
	await place(-1500, 580, 1)
	await shot("04_parallax_a")
	await place(-1200, 580, 1)
	await shot("04_parallax_b")
	# 水面动起来：同一机位连拍 40 张（每 3 帧一张），拼成动图看流动
	await place(-1180, 580, 1)
	DirAccess.make_dir_recursive_absolute(_dir() + "/water_seq")
	for i in 40:
		await frames(3)
		await process_frame
		root.get_viewport().get_texture().get_image().save_png(_dir() + "/water_seq/%02d.png" % i)
	print("RAIN_ART_CAPTURE_DONE ", _dir())
	quit()
