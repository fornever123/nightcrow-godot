extends SceneTree
## 开发工具（大招线）：在雨夜河岸街截大招开场用的素材板（Remotion 合成开场用）。需要真实渲染，不要加 --headless：
##   engine/Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/dev/ult_opening_plates.gd --resolution 1280x720 --fixed-fps 60
## 输出到环境变量 SHOT_DIR：pre.png（发动前、无界面）、u01.png（发动第 1 帧，居合架势，颜色未褪）、
## u01_noher.png（同一帧去掉她）、u02～u08.png；终端打印她在屏幕上的位置（META）。
## 之后跑 tools/art/make_ult_opening_plates.py 生成 bg / her / 轮廓线，放进 E:/00game/ult-slash-remotion/public/opening/。
## 摆法照 tests/dev/fx_shot.gd：钟楼广场左半，她在 c0-1180、四只影卒。发动大招要在物理帧开头注入按键、重试几次。
const Buffer := preload("res://scripts/core/input_buffer.gd")
const Shade := preload("res://scripts/night/shade.gd")
var stage
var p
var c0 := 0.0
var dir := ""
var perf: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func fr(actions: Array[StringName] = [], edges: Array[StringName] = [], axis := Vector2.ZERO) -> Buffer.Frame:
	var f := Buffer.Frame.new()
	f.actions = actions
	f.pressed_this_frame = edges
	f.axis = axis
	return f


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, name])
	print("SHOT ", name)


func frames(n: int, f: Buffer.Frame = null) -> void:
	for i in n:
		p.set_injected_frame(f if f != null else fr())
		await physics_frame


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
	dir = OS.get_environment("SHOT_DIR")
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
	await place(-1180, 580, 1)
	for k in [[Shade.Kind.GRUNT, -1000, 580], [Shade.Kind.GRUNT, -900, 580], [Shade.Kind.BRUTE, -1450, 580], [Shade.Kind.ARCHER, -1050, 305]]:
		shade(k[0], k[1], k[2], -1 if k[1] > -1180 else 1)
	await frames(20)
	p.ult_energy = p.ult_max
	await frames(10)
	stage.hud.visible = false
	for n in stage.find_children("*", "CanvasLayer", true, false):
		if n.layer >= 10 and n != stage.ult_fx._movie_layer:
			n.visible = false
	await frames(2)
	await shot("pre")
	var ct: Transform2D = root.get_viewport().get_canvas_transform()
	print("META player=", ct * p.global_position, " foot=", p.foot_offset, " zoom=", stage.camera.zoom)
	print("META ready=", p.ult_ready(), " en=", p.ult_energy, "/", p.ult_max, " state=", p.state)
	for tries in 4:
		await physics_frame
		p.set_injected_frame(fr([&"attack_light", &"attack_ranged"], [&"attack_light", &"attack_ranged"]))
		await physics_frame
		p.set_injected_frame(fr())
		if p.ult_frame >= 0:
			break
	print("META after press ult_frame=", p.ult_frame, " state=", p.state)
	stage.ult_fx._mono_mat.set_shader_parameter("amount", 0.0)
	stage.ult_fx._ui.visible = false
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("%s/u01.png" % dir)
	ct = root.get_viewport().get_canvas_transform()
	print("META f1 player=", ct * p.global_position, " zoom=", stage.camera.zoom)
	stage.ult_fx.set_process(false)
	p.set_physics_process(false)
	p.set_process(false)
	for s in stage.get_tree().get_nodes_in_group(&"shade"):
		s.set_physics_process(false)
		s.set_process(false)
	var keep_vis: bool = p.visible
	p.visible = false
	stage.ult_fx._top.visible = false
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("%s/u01_noher.png" % dir)
	print("META noher saved")
	quit()
	return
	var done := {}
	for i in 60:
		p.set_injected_frame(fr())
		await physics_frame
		var f: int = p.ult_frame
		if f >= 0 and f <= 8 and not done.has(f):
			done[f] = true
			await shot("u%02d" % f)
			ct = root.get_viewport().get_canvas_transform()
			print("META f", f, " player=", ct * p.global_position)
		if f > 8:
			break
	quit()
