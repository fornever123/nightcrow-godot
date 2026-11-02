extends SceneTree
## 开发工具：大招截图。四种影站一排 → 能量满 → J+K → 按「绝影」时间轴在几个关键帧各截一张。
## DISPLAY=:99 godot --path . --script res://tests/dev/ult_shot.gd --resolution 1280x720 --fixed-fps 60
## 截图目录：环境变量 SHOT_DIR（默认 res://.runtime/shots）
const Buffer := preload("res://scripts/core/input_buffer.gd")
const Shade := preload("res://scripts/night/shade.gd")


func _initialize() -> void:
	call_deferred("run")


func fr(actions: Array[StringName] = [], edges: Array[StringName] = [], axis := Vector2.ZERO) -> Buffer.Frame:
	var f := Buffer.Frame.new()
	f.actions = actions
	f.pressed_this_frame = edges
	f.axis = axis
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
	var stage = load("res://scenes/rain_street.tscn").instantiate()
	root.add_child(stage)
	await process_frame
	stage.set_physics_process(false)
	stage.hud.help_visible = false
	stage.hud._banner = ""        # 截图不要开场横幅
	stage.hud._banner_life = 0.0
	var p = stage.player
	var x := float(OS.get_environment("ULT_X")) if OS.get_environment("ULT_X") != "" else 1400.0   # 换个地方试（不同的街段）
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
	# 绝影（11-01 整段预览 22）：开场 / 视频 / 地图斩切进 / 刀尖出画 / 时停 / 断开 / 错开 / 推近收刀 / 咔 / 退回 / 收。SHOTS="12,27,..." 可改
	var want := {2: "ult_00_open", 10: "ult_01_rise", 18: "ult_02_fold", 26: "ult_03_spread", 36: "ult_04_crows", 48: "ult_05_fade", 110: "ult_06_movie", 156: "ult_06b_burn", 162: "ult_07_white", 164: "ult_08_whip", 168: "ult_08b_cutin", 174: "ult_09_tip", 179: "ult_10_stop", 183: "ult_11_split", 189: "ult_12_apart", 209: "ult_13_sheathe", 223: "ult_14_click", 236: "ult_15_tide", 256: "ult_16_back", 273: "ult_17_end"}
	p.ult_reveal.connect(func(): print("reveal at f=", p.ult_frame))
	if OS.get_environment("SHOTS") != "":
		want = {}
		for v in OS.get_environment("SHOTS").split(","):
			want[int(v)] = "ult_f%03d" % int(v)    # 负数 = 大招结束后第几帧（-1 是结束后第 0 帧）
	# 按主角的 ult_frame 截（截图本身会多走物理帧，不能按循环次数算）
	var done := {}
	var tail := int(OS.get_environment("TAIL")) if OS.get_environment("TAIL") != "" else 0   ## 大招结束后再录多少帧（看结束后接的收刀）
	for i in 400:
		await physics_frame
		var f: int = p.ult_frame
		if f < 0 and i > 10:
			for k in tail:
				await physics_frame
				if want.has(-1 - k) and not done.has(-1 - k):
					done[-1 - k] = true
					await shot(dir, "ult_after_%02d" % k)
			break
		if want.has(f) and not done.has(f):
			done[f] = true
			if OS.get_environment("STATES") == "1":
				for sh in stage.get_tree().get_nodes_in_group(&"shade"):
					print("f", f, " shade ", sh.kind, " state=", sh.state, " hs=", sh.hitstop_frames, " pos=", sh.global_position.round(), " hp=", sh.hp)
			await shot(dir, want[f])
	quit()
