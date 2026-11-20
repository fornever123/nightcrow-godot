extends SceneTree
## 雨街有限试玩：真实跨层跳跃、取景、完整封印流程、结果暂停与重玩。
const Buffer := preload("res://scripts/core/input_buffer.gd")
const Shade := preload("res://scripts/night/shade.gd")
const TRIAL := "res://scenes/rain_trial.tscn"
var stage
var p
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		print("FAIL: ", label)


func frame(actions: Array[StringName] = [], edges: Array[StringName] = [], axis := Vector2.ZERO) -> Buffer.Frame:
	var f := Buffer.Frame.new()
	f.actions = actions
	f.pressed_this_frame = edges
	f.axis = axis
	return f


func step(f: Buffer.Frame, ticks := 1) -> void:
	for i in ticks:
		p.set_injected_frame(f)
		await physics_frame


func feet() -> float:
	return p.global_position.y + p.foot_offset


func tap(edges: Array[StringName], axis := Vector2.ZERO, held := 3, gap := 0) -> void:
	await step(frame(edges, edges, axis))
	await step(frame(edges, [], axis), held - 1)
	if gap > 0:
		await step(frame(), gap)


func enemy(kind: int, x: float, active := false, surface := NAN) -> Node2D:
	var s := Node2D.new()
	s.set_script(Shade)
	s.setup(kind, p, stage.floor_y, 1.0)
	s.position = Vector2(x, (stage.floor_y if is_nan(surface) else surface) - float(Shade.KINDS[kind].half_h))
	s.terrain = stage.terrain
	s.arena_left = stage.arena_center - stage.arena_half
	s.arena_right = stage.arena_center + stage.arena_half
	stage.add_child(s)
	s.spawn_frames = 0
	s.active = active
	stage._on_shade_spawned(s)
	return s


func combat_route(c: float) -> void:
	p.reset_state(Vector2(c - 1770.0, -300.0 - p.foot_offset))
	p._set_facing(1)
	var s := enemy(Shade.Kind.GRUNT, p.global_position.x + 100.0, false, -300.0)
	s.hp = 600.0 # 保持目标存活，专项测完整空追，不代表试玩敌人生命。
	await step(frame(), 4)
	await tap([&"attack_light"], Vector2.ZERO, 3, 13)
	await tap([&"attack_light"], Vector2.ZERO, 3, 13)
	await step(frame(), 10)
	await tap([&"aim_up", &"jump", &"attack_light"], Vector2.UP, 4)
	for i in 60:
		if s.state == Shade.State.LAUNCHED:
			break
		await step(frame())
	check(s.state == Shade.State.LAUNCHED, "雨街实际碰撞命中可挑飞目标")
	await step(frame(), 10)
	for i in 12:
		if not p.is_on_floor():
			break
		await tap([&"jump", &"aim_up"], Vector2.UP, 3, 2)
	await step(frame(), 7)
	await tap([&"attack_light"], Vector2.ZERO, 3, 14)
	await tap([&"attack_light"], Vector2.ZERO, 3, 14)
	check(s.juggle_count >= 2, "雨街空中追击能连续命中（%d）" % s.juggle_count)
	check(int(stage.style.stats.launch) >= 1, "真实挑飞被计入本次结果")
	# 截图会等待渲染帧，也会推进物理；放在连段断言之后，不插入出招时序。
	await shot("03_air_chase")
	s.queue_free()
	await step(frame(), 2)
	p.reset_state(Vector2(c - 1700.0, stage.floor_y - p.foot_offset))
	await step(frame(), 20)
	var archer := enemy(Shade.Kind.ARCHER, c - 1100.0, true)
	archer._begin_windup()
	await step(frame(), 12)
	check(archer.state == Shade.State.WINDUP, "同层影弓进入有准备时间的瞄准状态")
	await shot("04_archer_warning")
	archer.queue_free()
	await step(frame(), 2)


func jump() -> float:
	await step(frame([&"jump"], [&"jump"]), 1)
	await step(frame([&"jump"]), 17)
	for i in 120:
		await step(frame())
		if p.is_on_floor() and i > 6:
			break
	await step(frame(), 20)
	return feet()


func shot(name: String) -> void:
	var out := OS.get_environment("SHOT_DIR")
	if out == "" or DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute(out)
	await process_frame
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(out.path_join(name + ".png"))
	check(error == OK, "保存真实渲染截图 " + name)
	print("RAIN_TRIAL_SHOT ", out.path_join(name + ".png"))


func finish() -> void:
	paused = false
	print("RAIN_TRIAL_TESTS: %d checks / %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func run() -> void:
	check(ResourceLoader.exists(TRIAL), "独立雨街试玩入口存在")
	if not ResourceLoader.exists(TRIAL):
		finish()
		return
	stage = load(TRIAL).instantiate()
	root.add_child(stage)
	current_scene = stage
	await process_frame
	p = stage.player
	check(p != null and not stage.trial_completed, "试玩可开始且没有提前结算")
	# 11-03：首页线把默认入口接去了 yg_title_duanguang.tscn；这里只要求雨街试玩场景还在、入口指向它或首页。
	var entry := String(ProjectSettings.get_setting("application/run/main_scene"))
	check(entry == "res://scenes/rain_trial.tscn" or entry.ends_with("yg_title_duanguang.tscn") or entry.ends_with("yg_title_zhanzhong.tscn"),  # [YG-MARK] 11-17 首页线入口换成《斩钟》首页
		"默认入口是雨街试玩（或首页接管：%s）" % entry)
	check(ResourceLoader.exists("res://scenes/rain_trial.tscn"), "雨街试玩场景还在")
	check(stage.round_waves.size() == 3, "沿用三处封印和既有波次")
	await step(frame(), 20)
	await shot("01_start")
	# 用实际移动跨过第一处触发线，而不是直接调用锁场。
	var c: float = stage._center_of(0)
	p.reset_state(Vector2(c - stage.trigger_before - 50.0, stage.floor_y - p.foot_offset))
	await step(frame([&"move_right"], [], Vector2.RIGHT), 30)
	check(stage.phase == stage.Phase.FIGHT and stage.seal_walls.size() == 2, "走入第一处封印会锁场开战")
	stage.encounter.clear_shades()
	stage.encounter.running = false
	stage.set_physics_process(false)
	# 使用当前实际布局中的连续同轴阳台，非过时的旧截图坐标。
	p.reset_state(Vector2(c - 1770.0, stage.floor_y - p.foot_offset))
	await step(frame(), 25)
	var levels: Array[float] = [285.0, 0.0, -300.0]
	for level in levels:
		var landed := await jump()
		check(absf(landed - level) < 3.0, "真实跳上 %.0f 层（实际 %.1f）" % [level, landed])
	var screen: Vector2 = p.get_global_transform_with_canvas().origin
	var view: Vector2 = stage.get_viewport_rect().size
	check(screen.y > 80.0 and screen.y < view.y - 80.0, "屋顶角色保持在可读画面内（y=%.1f，高=%.0f）" % [screen.y, view.y])
	check(absf(stage.camera.lock_y - stage._cam_y_for(feet())) < 3.0, "镜头在落地后对准当前楼层")
	await shot("02_roof")
	for i in 3:
		await step(frame(), 8)
		# 11-01：S 单按就下去；最后一次用老的 S + 跳，确认两种都行
		if i < 2:
			await step(frame([&"move_down"], [&"move_down"], Vector2.DOWN))
		else:
			await step(frame([&"move_down", &"jump"], [&"jump"], Vector2.DOWN))
		for tick in 140:
			await step(frame())
			if p.is_on_floor() and tick > 10:
				break
		print("RAIN_TRIAL_DROP ", i + 1, " feet=", feet())
	check(absf(feet() - stage.floor_y) < 3.0, "三次下穿回到地面（实际 %.1f）" % feet())
	await combat_route(c)
	# 跨过两处中途结算后再完成最后一处，测试不会中途结束/进入第四处。
	stage.set_physics_process(true)
	for i in 2:
		stage._on_encounter_cleared()
		check(not stage.trial_completed and not paused, "第%d处解除后仍可继续" % (i + 1))
		p.reset_state(Vector2(stage._next_center() - stage.trigger_before - 50.0, stage.floor_y - p.foot_offset))
		await step(frame([&"move_right"], [], Vector2.RIGHT), 30)
		check(stage.phase == stage.Phase.FIGHT, "后续封印仍由走入触发")
		stage.encounter.clear_shades()
		stage.encounter.running = false
	stage.style.add_event(&"launch")
	stage.style.add_event(&"wall")
	stage._on_encounter_cleared()
	check(stage.trial_completed and paused, "第三处结束后暂停战斗并进入结算")
	check(stage.encounter_index == 3 and stage.round_index == 0, "结束不会进入额外轮次或增加生命倍率")
	check(int(stage.trial_summary.launch) >= 1 and int(stage.trial_summary.wall) >= 1, "结算保留挑飞和撞墙统计")
	var summary: Dictionary = stage.trial_summary.duplicate(true)
	stage._on_encounter_cleared()
	check(stage.encounter_index == 3 and stage.trial_summary == summary, "重复完成回调不会重复结算")
	for i in 12:
		await process_frame
	var menu: CanvasLayer = stage.get_node("TrialResult")
	var retry: Button = menu.get_node("Screen/Center/Panel/Rows/Retry")
	check(menu.process_mode == Node.PROCESS_MODE_ALWAYS and retry.has_focus(), "暂停时结果面板可操作并聚焦重玩")
	await shot("05_complete")
	# 真正送入 F5（11-01 起 R 是大招，重开挪到 F5）：验证暂停时快捷键仍能启动新场景。
	var key := InputEventKey.new()
	key.physical_keycode = KEY_F5
	key.pressed = true
	Input.parse_input_event(key)
	for i in 8:
		await process_frame
	check(not paused and current_scene != stage, "F5 解除暂停并重新进入试玩")
	stage = current_scene
	check(stage != null and not stage.trial_completed and stage.encounter_index == 0, "重玩从首处封印开始")
	key.pressed = false
	Input.parse_input_event(key)
	if stage != null:
		stage.queue_free()
	await process_frame
	finish()
