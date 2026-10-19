extends SceneTree
## 第二轮手感大改（节点 11）：跑速/急停、快跳快落、小跳、最大下落速度、轻重落地、
## 招式分段变速、后摇 跳/冲刺/弹刀/方向键 取消。
const Buffer := preload("res://scripts/core/input_buffer.gd")
const Timeline := preload("res://scripts/core/animation_timeline.gd")
var stage: Node2D
var p: CharacterBody2D
var view: Sprite2D
var failures: Array[String] = []
var checks: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		print("FAIL: ", label)

func frame(actions: Array[StringName] = [], edges: Array[StringName] = [], axis := Vector2.ZERO) -> Buffer.Frame:
	var f := Buffer.Frame.new()
	f.actions = actions; f.pressed_this_frame = edges; f.axis = axis
	return f

func step(count: int, input: Buffer.Frame = null) -> void:
	p.set_injected_frame(frame() if input == null else input)
	var target: int = p.tick_count + count
	while p.tick_count < target:
		await process_frame

func fresh() -> void:
	stage._reset()
	p.clear_input_queue()
	await step(6)

## 按一次跳（只给一帧），记录最高点、到顶帧数、滞空帧数
func measure_jump() -> Dictionary:
	var y0: float = p.position.y
	var peak := y0
	var peak_f := 0
	var max_vy := 0.0
	await step(1, frame([&"jump"], [&"jump"]))
	var n := 1
	while n < 240:
		await step(1)
		n += 1
		max_vy = maxf(max_vy, p.velocity.y)
		if p.position.y < peak:
			peak = p.position.y
			peak_f = n
		if p.is_on_floor() and n > 3:
			break
	await step(1)
	return {"height": y0 - peak, "peak": peak_f, "air": n, "max_vy": max_vy}

func run() -> void:
	stage = load("res://scenes/training.tscn").instantiate()
	root.add_child(stage)
	current_scene = stage
	stage.config.runtime.autoReload = false
	p = stage.player
	view = p.get_node("Visual/ActorSprite")
	await step(10)

	# ---- 跑：快起步、急停
	check(p.speed >= 300.0, "跑速提到 300 以上")
	var n := 0
	while absf(p.velocity.x) < p.speed * 0.95 and n < 60:
		await step(1, frame([&"move_right"], [], Vector2.RIGHT))
		n += 1
	check(n <= 6, "起步 6 帧内到 95%% 跑速（实际 %d 帧）" % n)
	await step(12, frame([&"move_right"], [], Vector2.RIGHT))
	n = 0
	var x0: float = p.position.x
	while absf(p.velocity.x) > 1.0 and n < 60:
		await step(1)
		n += 1
	check(n <= 5 and p.position.x - x0 < 20.0, "松手 5 帧内停住、滑步不超过 20px")
	check(view.clip_name != "run", "停下后不再播跑步")

	# ---- 跳：快跳快落，跳高保持
	await fresh()
	var j: Dictionary = await measure_jump()
	check(j.height > p.jump_height * 0.93 and j.height < p.jump_height * 1.05, "满跳达到配置高度（目标 %.0f / 实际 %.0f）" % [p.jump_height, j.height])
	check(j.peak <= 24, "0.4 秒内到顶（实际 %d 帧）" % j.peak)
	check(j.air <= 60, "加高并减慢下落后整跳不超过 1 秒（实际 %d 帧）" % j.air)
	check(j.max_vy <= p.max_fall_speed + 0.5 and p.max_fall_speed <= 1400.0, "下落速度有上限")
	check(not p.last_landing_heavy and view.landing_speed > 1.0, "普通落地是轻落地：落地动作快放")

	# 注入输入只给一帧也必须是满跳（机器人/测试不会被误判成松键小跳）
	check(not p._keyboard_frame, "注入输入不算真实按键")

	# ---- 真实按键：按 3 帧就松 = 小跳
	await fresh()
	p._sticky_frame = null
	var y0: float = p.position.y
	var peak := y0
	Input.action_press(&"jump")
	for i in 3:
		await physics_frame
	Input.action_release(&"jump")
	for i in 120:
		await physics_frame
		peak = minf(peak, p.position.y)
		if p.is_on_floor() and i > 3:
			break
	check(y0 - peak < j.height * 0.6 and y0 - peak > 30.0, "真实按键早松 = 小跳（%.0f / %.0f）" % [y0 - peak, j.height])

	# ---- 二段跳落下 = 重落地
	await fresh()
	await step(1, frame([&"jump"], [&"jump"]))
	await step(16)
	await step(1, frame([&"jump"], [&"jump"]))
	for i in 200:
		await step(1)
		if p.is_on_floor():
			break
	await step(1)
	check(p.last_landing_heavy and p.last_fall_height > 260.0, "高处落下记为重落地")
	check(is_equal_approx(view.landing_speed, 1.0) and view.landing_heavy, "重落地按原速播完整落地动作")
	check(p._landing_lag > 0, "重落地有短暂落地硬直")
	await step(1, frame([&"jump"], [&"jump"]))
	check(p.velocity.y < 0.0, "落地硬直可以直接跳起取消")

	# ---- 招式分段变速：动画播满、整招更短、命中帧不变
	var l1: Resource = stage.moves.light_1
	var clip: Dictionary = view.setup.animations[l1.animation]
	var clip_s: float = Timeline.ticks_before(clip.frames, clip.frames.size()) / l1.animation_fps
	check(l1.phase_timed and l1.total_frames() < roundi(clip_s * 60.0), "第一刀整招比原片短")
	check(absf(l1.anim_seconds(float(l1.total_frames())) - clip_s) < 0.0001, "第一刀动画仍然完整播完（不删帧）")
	var src: Dictionary = {}
	for s in stage.config.moves:
		if s.id == "light_1":
			src = s
	check(Timeline.frame_at(clip, l1.anim_seconds(float(l1.startup_frames)), l1.animation_fps) == int(src.activeFrameStart), "判定开始那一帧正好是配置的出刀图")
	var d_slash: Resource = stage.moves.dash_slash
	check(absf(d_slash.anim_progress(float(d_slash.total_frames())) - 1.0) < 0.0001, "冲刺位移曲线按动画进度走满")

	# ---- 后摇取消
	await fresh()
	await step(1, frame([&"attack_light"], [&"attack_light"]))
	while p.current_move == l1 and p.move_frame < l1.startup_frames + l1.active_frames:
		await step(1)
	check(p.current_move == l1 and l1.phase_at(p.move_frame) == &"recovery", "进入第一刀后摇")
	await step(1, frame([&"parry"], [&"parry"]))
	check(p.current_move == null and p.is_guarding(), "后摇一开始就能弹刀取消")

	await fresh()
	await step(1, frame([&"attack_light"], [&"attack_light"]))
	while p.current_move == l1 and p.move_frame < l1.startup_frames + l1.active_frames:
		await step(1)
	await step(1, frame([&"dash_modifier", &"attack_light"], [&"attack_light"], Vector2.RIGHT))
	check(p.current_move == p.dash_move, "后摇里 Shift+J 冲刺取消")

	await fresh()
	await step(1, frame([&"attack_light"], [&"attack_light"]))
	while p.current_move == l1 and p.move_frame < l1.startup_frames + l1.active_frames:
		await step(1)
	await step(1, frame([&"jump"], [&"jump"]))
	check(p.current_move == null and p.velocity.y < 0.0, "后摇里跳跃取消")

	# 收招尾巴：方向键直接跑开
	await fresh()
	await step(1, frame([&"attack_light"], [&"attack_light"]))
	var open_at: int = l1.startup_frames + l1.active_frames + l1.cancel_frame + l1.move_cancel_delay
	while p.current_move == l1 and p.move_frame < open_at - 1:
		await step(1)
	check(p.current_move == l1, "方向键取消窗口之前还在招式里")
	await step(2, frame([&"move_right"], [], Vector2.RIGHT))
	check(p.current_move == null and p.velocity.x > 0.0, "接招点之后按方向键直接收招跑开")
	check(p.current_move == null and open_at < l1.total_frames(), "方向键取消早于招式自然结束")

	# 冲刺斩：后摇可以跳取消（带着冲刺的速度起跳）
	await fresh()
	await step(1, frame([&"dash_modifier", &"attack_light"], [&"attack_light"], Vector2.RIGHT))
	var dm: Resource = p.dash_move
	while p.current_move == dm and p.move_frame < dm.startup_frames + dm.active_frames + 1:
		await step(1)
	await step(1, frame([&"jump"], [&"jump"], Vector2.RIGHT))
	check(p.current_move == null and p.velocity.y < 0.0, "冲刺斩后摇跳跃取消")

	print("FEEL_TESTS: %d checks / %d failures" % [checks, failures.size()])
	quit(1 if failures.size() > 0 else 0)
