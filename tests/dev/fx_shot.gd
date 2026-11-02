extends SceneTree
## 开发工具：角色特效线（Forward+ 特效）的固定机位截图 + GPU 帧时间，用来出改前 / 改后对比。
## 需要真实渲染（不要加 --headless）：
##   engine/Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/dev/fx_shot.gd --resolution 1280x720 --fixed-fps 60
## 雨夜河岸街钟楼广场左半（成图段）同一处：普通三连打中影卒、大招后段几帧。命中变体固定、随机数固定。
## 截图目录：环境变量 SHOT_DIR（默认 res://.runtime/shots_fx）；帧时间写进 perf.txt。
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


## 连续 n 帧取平均 GPU / CPU 渲染时间（毫秒）
func measure(label: String, n: int = 90) -> void:
	var vps: Array[RID] = [root.get_viewport().get_viewport_rid()]
	var ss := root.get_node_or_null("Supersample")
	if ss != null and ss.view() != null:
		vps.append(ss.view().get_viewport_rid())   # 超采样开着时，真正的画面画在 2 倍画布上
	for vp in vps:
		RenderingServer.viewport_set_measure_render_time(vp, true)
	await frames(10)
	var gpu := 0.0
	var cpu := 0.0
	for i in n:
		p.set_injected_frame(fr())
		await RenderingServer.frame_post_draw
		for vp in vps:
			gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
			cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp)
	var line := "%s gpu=%.3fms cpu=%.3fms" % [label, gpu / n, cpu / n]
	perf.append(line)
	print("PERF ", line)


func run() -> void:
	dir = OS.get_environment("SHOT_DIR")
	if dir == "":
		dir = ProjectSettings.globalize_path("res://.runtime/shots_fx")
	DirAccess.make_dir_recursive_absolute(dir)
	# 环境变量 FX_MSAA=0..3 临时覆盖 2D MSAA（关 / 2x / 4x / 8x），不改项目设置就能对比
	var msaa := OS.get_environment("FX_MSAA")
	if msaa != "":
		root.msaa_2d = int(msaa) as Viewport.MSAA
	# FX_SSAA_MODE=0..2 临时覆盖屏幕空间抗锯齿（关 / FXAA / SMAA）
	var ssaa_mode := OS.get_environment("FX_SSAA_MODE")
	if ssaa_mode != "":
		root.screen_space_aa = int(ssaa_mode) as Viewport.ScreenSpaceAA
	var ss := root.get_node_or_null("Supersample")
	perf.append("msaa_2d=%d screen_space_aa=%d size=%s supersample=%s" % [root.msaa_2d, root.screen_space_aa,
		root.get_visible_rect().size, "missing" if ss == null else str(ss.enabled)])
	stage = load("res://scenes/rain_street.tscn").instantiate()
	root.add_child(stage)
	await process_frame
	p = stage.player
	stage.hud.help_visible = false
	stage.fx.debug_variant = 0
	await frames(30)
	c0 = stage._center_of(0)
	p.reset_state(Vector2(c0 - 1900.0, stage.floor_y - p.foot_offset))
	await frames(90, fr([&"move_right"], [], Vector2(1, 0)))
	stage.hud._banner = ""
	stage.hud._banner_life = 0.0

	await place(-1180, 580, 1)
	await shot("00_idle")
	await measure("idle")

	# ---- 普通三连：前面两只影卒，楼上一只影弓
	await place(-1180, 580, 1)
	stage.fx.rng.seed = 7
	shade(Shade.Kind.GRUNT, -1095, 580, -1)
	shade(Shade.Kind.GRUNT, -1040, 580, -1)
	shade(Shade.Kind.ARCHER, -1050, 305, -1)
	await frames(20)
	await frames(1, fr([&"attack_light"], [&"attack_light"]))
	await frames(5)
	await shot("01_slash1_a")
	await frames(3)
	await shot("01_slash1_b")
	await frames(1, fr([&"attack_light"], [&"attack_light"]))
	await frames(8)
	await shot("02_slash2")
	await frames(1, fr([&"attack_light"], [&"attack_light"]))
	await frames(10)
	await shot("03_slash3")
	await frames(4)
	await shot("03_slash3_b")

	# ---- 大招
	await place(-1180, 580, 1)
	for k in [[Shade.Kind.GRUNT, -1000, 580], [Shade.Kind.GRUNT, -900, 580], [Shade.Kind.BRUTE, -1450, 580], [Shade.Kind.ARCHER, -1050, 305]]:
		shade(k[0], k[1], k[2], -1 if k[1] > -1180 else 1)
	await frames(20)
	p.ult_energy = p.ult_max
	await frames(10)
	await frames(1, fr([&"attack_light", &"attack_ranged"], [&"attack_light", &"attack_ranged"]))
	var want := {150: "10_ult_f150", 170: "10_ult_f170", 190: "10_ult_f190", 205: "10_ult_f205", 215: "10_ult_f215", 240: "10_ult_f240"}
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
	await place(-1180, 580, 1)
	await measure("after_ult")
	var fa := FileAccess.open(dir + "/perf.txt", FileAccess.WRITE)
	fa.store_string("\n".join(perf) + "\n")
	fa.close()
	print("FX_SHOT_DONE ", dir)
	quit()
