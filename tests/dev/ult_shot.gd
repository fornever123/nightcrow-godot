extends SceneTree
## 开发工具：大招截图（第四轮）。四种影站一排 → 能量满 → J+K → 在 摆架势 / 出刀 / 出刀后 各截一张。
## DISPLAY=:99 godot --path . --script res://tests/dev/ult_shot.gd --resolution 1280x720 --fixed-fps 60
## 截图目录：环境变量 SHOT_DIR（默认 res://.runtime/shots）
const Buffer := preload("res://scripts/core/input_buffer.gd")
const Shade := preload("res://scripts/night/shade.gd")


func _initialize() -> void:
	call_deferred("run")


func fr(actions: Array[StringName] = [], edges: Array[StringName] = []) -> Buffer.Frame:
	var f := Buffer.Frame.new()
	f.actions = actions
	f.pressed_this_frame = edges
	return f


func shot(dir: String, name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, name])
	print("shot ", name)


func run() -> void:
	var dir := OS.get_environment("SHOT_DIR")
	if dir == "":
		dir = ProjectSettings.globalize_path("res://.runtime/shots")
	DirAccess.make_dir_recursive_absolute(dir)
	var stage = load("res://scenes/night_trial.tscn").instantiate()
	root.add_child(stage)
	await process_frame
	stage.set_physics_process(false)
	stage.hud.help_visible = false
	stage.hud._banner = ""        # 截图不要开场横幅
	stage.hud._banner_life = 0.0
	var p = stage.player
	var x := 1400.0
	p.reset_state(Vector2(x, stage.floor_y - p.foot_offset))
	p._set_facing(1)
	p.set_injected_frame(fr())
	stage.camera.global_position = Vector2(x + 200.0, stage.CAM_Y)
	var kinds := [[Shade.Kind.BRUTE, -330.0], [Shade.Kind.GRUNT, 260.0], [Shade.Kind.GRUNT, 420.0],
		[Shade.Kind.ARCHER, 760.0], [Shade.Kind.BOMBER, 980.0]]
	for k in kinds:
		var sh: Node2D = Node2D.new()
		sh.set_script(Shade)
		sh.setup(k[0], p, stage.floor_y, 1.0)
		sh.position = Vector2(x + float(k[1]), stage.floor_y - 60.0)
		sh.terrain = stage.terrain
		stage.add_child(sh)
		sh.spawn_frames = 0
		sh.active = false
		sh.facing = -1 if k[1] > 0 else 1
		stage._on_shade_spawned(sh)
		sh.pct = 35.0 if k[0] == Shade.Kind.GRUNT else 0.0
	for i in 30:
		await physics_frame
	p.ult_energy = p.ult_max
	for i in 20:
		await physics_frame
	await shot(dir, "ult_0_ready")
	await physics_frame   # 注入要在物理帧开头做，否则会被下一帧开头的注入盖掉
	p.set_injected_frame(fr([&"attack_light", &"attack_ranged"], [&"attack_light", &"attack_ranged"]))
	await physics_frame
	p.set_injected_frame(fr())
	print("ready=", p.ult_ready(), " ult=", p.ult_frame, " state=", p.state, " en=", p.ult_enabled)
	var want := {14: "ult_1_charge", 42: "ult_2_cutin", 57: "ult_3_slash", 62: "ult_4_freeze", 95: "ult_5_click", 110: "ult_6_pop"}
	for i in 130:
		await physics_frame
		var f: int = i + 1
		if i < 3: print("f", f, " ult=", p.ult_frame, " st=", p.state)
		if want.has(f):
			await shot(dir, want[f])
	quit()
