extends SceneTree
## 手感测量（开发用，不进测试集）：跑速/起步/急停、跳跃高度和滞空、小跳、各招式帧数。
const Buffer := preload("res://scripts/core/input_buffer.gd")
var stage: Node2D
var p: CharacterBody2D

func _initialize() -> void:
	call_deferred("run")

func frame(actions: Array[StringName] = [], edges: Array[StringName] = [], axis := Vector2.ZERO) -> Buffer.Frame:
	var f := Buffer.Frame.new()
	f.actions = actions; f.pressed_this_frame = edges; f.axis = axis
	return f

func step(count: int, input: Buffer.Frame = null) -> void:
	p.set_injected_frame(frame() if input == null else input)
	var target: int = p.tick_count + count
	while p.tick_count < target:
		await process_frame

func run() -> void:
	stage = load("res://scenes/training.tscn").instantiate()
	root.add_child(stage)
	current_scene = stage
	stage.config.runtime.autoReload = false
	p = stage.player
	await step(10)
	print("speed=", p.speed, " accel=", p.acceleration, " decel=", p.deceleration, " g_up=", p._gravity, " g_down=", p._fall_gravity, " v0=", p._jump_velocity)
	# 起步
	var n := 0
	while absf(p.velocity.x) < p.speed * 0.95 and n < 60:
		await step(1, frame([&"move_right"], [], Vector2.RIGHT)); n += 1
	print("frames_to_95%=", n)
	await step(20, frame([&"move_right"], [], Vector2.RIGHT))
	var x0: float = p.position.x
	n = 0
	while absf(p.velocity.x) > 1.0 and n < 60:
		await step(1); n += 1
	print("stop_frames=", n, " stop_dist=", snappedf(p.position.x - x0, 0.1))
	await step(30)
	# 满跳
	var y0: float = p.position.y
	var peak := y0
	var peak_f := 0
	await step(1, frame([&"jump"], [&"jump"]))
	n = 1
	while n < 200:
		await step(1)
		n += 1
		if p.position.y < peak:
			peak = p.position.y; peak_f = n
		if p.is_on_floor() and n > 3:
			break
	await step(1)
	print("full_jump height=", snappedf(y0 - peak, 0.1), " peak_frame=", peak_f, " air_frames=", n, " heavy=", p.last_landing_heavy, " fall_h=", snappedf(p.last_fall_height, 0.1))
	await step(30)
	# 二段跳
	y0 = p.position.y; peak = y0
	await step(1, frame([&"jump"], [&"jump"]))
	await step(16)
	await step(1, frame([&"jump"], [&"jump"]))
	n = 18
	while n < 300:
		await step(1); n += 1
		peak = minf(peak, p.position.y)
		if p.is_on_floor():
			break
	await step(1)
	print("double_jump height=", snappedf(y0 - peak, 0.1), " air_frames=", n, " heavy=", p.last_landing_heavy, " fall_h=", snappedf(p.last_fall_height, 0.1))
	await step(30)
	# 真实键盘小跳：按 3 帧就松
	p.clear_input_queue()
	p._sticky_frame = null
	y0 = p.position.y; peak = y0
	Input.action_press(&"jump")
	for i in 3:
		await physics_frame
	Input.action_release(&"jump")
	for i in 120:
		await physics_frame
		peak = minf(peak, p.position.y)
		if p.is_on_floor() and i > 3:
			break
	print("short_hop height=", snappedf(y0 - peak, 0.1))
	for id in ["light_1","light_2","light_3","charge_1","up_strike","air_up","air_light_1","air_light_2","air_light_3","dash_slash","dash_slash_left","guard_hit_1","guard_hit_2","guard_hit_3","parry_react_1","parry_react_3","parry_1","ranged_1"]:
		var m: Resource = stage.moves[id]
		print(id, " S", m.startup_frames, " A", m.active_frames, " R", m.recovery_frames, " link@", m.startup_frames + m.active_frames + m.cancel_frame, " total", m.total_frames(), " (", snappedf(m.total_frames() / 60.0, 0.01), "s) timed=", m.phase_timed)
	quit(0)
