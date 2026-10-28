extends SceneTree
## 开发工具：雨夜河岸街阶段一的自动检查 + 截图。
## 需要真实渲染（不要加 --headless）：
##   engine/Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/dev/capture_rain_street.gd --resolution 1280x720
## 做的事：走进第一处竞技场 → 原地起跳上二层、再上三层（检查真的站上去了）→ 机器人打一会儿 → 各处截图。
## 截图目录：环境变量 SHOT_DIR（默认 res://.runtime/shots_rain）
const Buffer := preload("res://scripts/core/input_buffer.gd")
const Shade := preload("res://scripts/night/shade.gd")
var stage
var p
var tick := 0
var log_lines: PackedStringArray = []


func _initialize() -> void:
	call_deferred("run")


func fr(actions: Array[StringName] = [], edges: Array[StringName] = [], axis := Vector2.ZERO) -> Buffer.Frame:
	var f := Buffer.Frame.new()
	f.actions = actions
	f.pressed_this_frame = edges
	f.axis = axis
	return f


func _shot_dir() -> String:
	var d := OS.get_environment("SHOT_DIR")
	if d == "":
		d = ProjectSettings.globalize_path("res://.runtime/shots_rain")
	DirAccess.make_dir_recursive_absolute(d)
	return d


func shot(name: String) -> void:
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(_shot_dir() + "/%s.png" % name)
	log_lines.append("SHOT %s  player=(%.0f, feet %.0f)  cam=(%.0f, %.0f)" % [name, p.global_position.x, feet(), stage.camera.global_position.x, stage.camera.global_position.y])


func feet() -> float:
	return p.global_position.y + p.foot_offset


func step(f: Buffer.Frame, n: int = 1) -> void:
	for i in n:
		p.set_injected_frame(f)
		await physics_frame
		tick += 1


## 走到 x（地面上），到了停住
func walk_to(x: float, limit: int = 900) -> void:
	for i in limit:
		var dx: float = x - p.global_position.x
		if absf(dx) < 12.0:
			break
		var mv: StringName = &"move_right" if dx > 0 else &"move_left"
		await step(fr([mv], [], Vector2(signf(dx), 0)))
	await step(fr(), 20)


## 原地跳一下（按住 18 帧 = 满跳），等落地，返回落地后的脚底高度
func jump_up() -> float:
	await step(fr([&"jump"], [&"jump"]), 1)
	await step(fr([&"jump"]), 17)
	for i in 120:
		await step(fr())
		if p.is_on_floor() and i > 6:
			break
	await step(fr(), 30)
	print("  jump_up -> feet %.0f state %s" % [feet(), str(p.state)])
	return feet()


func alive() -> Array:
	return get_nodes_in_group(&"shade").filter(func(s): return s.state != Shade.State.DEAD and s.spawn_frames <= 0)


## 很笨的机器人：朝最近的影走过去砍
func brawl(frames: int) -> void:
	for i in frames:
		var shades := alive()
		if shades.is_empty():
			await step(fr())
			continue
		var near = shades[0]
		for s in shades:
			if absf(s.global_position.x - p.global_position.x) < absf(near.global_position.x - p.global_position.x):
				near = s
		var dx: float = near.global_position.x - p.global_position.x
		var mv: StringName = &"move_right" if dx > 0 else &"move_left"
		if absf(dx) > 150.0:
			await step(fr([mv], [], Vector2(signf(dx), 0)))
		elif i % 10 == 0:
			await step(fr([&"attack_light", mv], [&"attack_light"], Vector2(signf(dx), 0)))
		else:
			await step(fr())


func run() -> void:
	stage = load("res://scenes/rain_street.tscn").instantiate()
	root.add_child(stage)
	await process_frame
	p = stage.player
	await step(fr(), 40)
	await shot("01_start")
	var c0: float = stage._center_of(0)
	# 走进第一处竞技场（封印会合上）
	await walk_to(c0 - 1900.0, 1400)
	log_lines.append("phase after entering = %d (1 = FIGHT)" % stage.phase)
	await shot("02_arena_enter")
	# 攀爬测试先清场（敌人贴身会打断起跳），测完再开打
	stage.encounter.clear_shades()
	stage.encounter.running = false
	# 二层阳台 [-1400, -750] @300 正上方还有三层屋檐 @20：原地连跳两次
	await walk_to(c0 - 1080.0)
	var f1 := await jump_up()
	var f2 := await jump_up()
	log_lines.append("jump 1 -> feet %.0f (want 300), jump 2 -> feet %.0f (want 20)" % [f1, f2])
	await shot("03_on_f3")
	# 往下穿回地面：S + 跳，两次
	for k in 2:
		await step(fr([&"move_down", &"jump"], [&"jump"], Vector2(0, 1)), 2)
		for i in 120:
			await step(fr())
			if p.is_on_floor() and i > 10:
				break
	log_lines.append("drop down -> feet %.0f (want 580)" % feet())
	# 屋顶：左边二层阳台一路连到 -2350，上面是三层阳台 [-2300,-1750]@20，再上面是屋脊 [-2200,-1850]@-260
	await walk_to(c0 - 1080.0)
	await jump_up()
	await walk_to(c0 - 2020.0)
	var r1 := await jump_up()
	var r2 := await jump_up()
	log_lines.append("left side: f3 %.0f (want 20), roof %.0f (want -260)" % [r1, r2])
	await shot("05_on_roof")
	stage.debug_boxes = true
	await shot("06_debug_lines")
	stage.debug_boxes = false
	for k in 3:
		await step(fr([&"move_down", &"jump"], [&"jump"], Vector2(0, 1)), 2)
		for i in 120:
			await step(fr())
			if p.is_on_floor() and i > 10:
				break
	stage.encounter.start()
	await brawl(420)
	await shot("07_brawl")
	await brawl(600)
	await shot("08_brawl_later")
	log_lines.append("shades alive %d, wave %d, hp %.0f" % [alive().size(), stage.encounter.wave_index, p.hp])
	for l in log_lines:
		print(l)
	print("RAIN_CAPTURE_DONE ", _shot_dir())
	quit()
