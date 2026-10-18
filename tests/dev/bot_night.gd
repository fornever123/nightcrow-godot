extends SceneTree
## 开发工具（不是回归测试）：自动试玩机器人跑整轮，打印用时/死亡/伤害来源，用来调难度。
## 用法：SEED=7 SKILL=0.6 BOT_ENC=3 godot --headless --fixed-fps 60 --path . --script res://tests/dev/bot_night.gd
const Buffer := preload("res://scripts/core/input_buffer.gd")
const Shade := preload("res://scripts/night/shade.gd")
var stage
var p
var tick := 0
var plan: Array = []
var last_j := -100
var parry_cd := 0
var rng := RandomNumberGenerator.new()
var skill := 0.8
var deaths := [0]
var enc_clear: Array = []
var snap: Dictionary = {}   ## 上一帧的评价统计（关卡在整轮结束时会先重置统计，再轮到这里的回调）
var dmg_by := {}
func _initialize() -> void:
	call_deferred("run")
func fr(actions: Array[StringName] = [], edges: Array[StringName] = [], axis := Vector2.ZERO) -> Buffer.Frame:
	var f := Buffer.Frame.new()
	f.actions = actions; f.pressed_this_frame = edges; f.axis = axis
	return f
func tap(actions: Array[StringName], axis := Vector2.ZERO, n := 3) -> void:
	plan.append(fr(actions, actions, axis))
	for i in n - 1:
		plan.append(fr(actions, [], axis))
func alive() -> Array:
	return get_nodes_in_group(&"shade").filter(func(s): return s.state != Shade.State.DEAD and s.spawn_frames <= 0)
func decide() -> Buffer.Frame:
	if not plan.is_empty():
		return plan.pop_front()
	var shades := alive()
	if shades.is_empty():
		return fr([&"move_right"], [], Vector2(1, 0))
	var px: float = p.global_position.x
	var nearest = shades[0]
	for s in shades:
		if absf(s.global_position.x - px) < absf(nearest.global_position.x - px):
			nearest = s
	var dx: float = nearest.global_position.x - px
	var dir := 1.0 if dx > 0 else -1.0
	var mv: StringName = &"move_right" if dir > 0 else &"move_left"
	var on_floor: bool = p.is_on_floor()
	parry_cd -= 1
	# 1) 弹刀：看到橙光、离得近 → 转向它并按住 L 12 帧（skill 决定成功率）
	for s in shades:
		var sdx: float = s.global_position.x - px
		if s.state == Shade.State.WINDUP and absf(sdx) < float(s.spec.range) + 50.0 and parry_cd <= 0 and on_floor:
			var remain: int = int(s.spec.windup) - s.state_frames
			if remain <= 8 and remain >= 2:
				parry_cd = 40
				if rng.randf() < skill:
					var d := 1.0 if sdx > 0 else -1.0
					if p.facing != int(d):
						plan.append(fr([&"move_right" if d > 0 else &"move_left"], [], Vector2(d, 0)))
					tap([&"parry"], Vector2.ZERO, 12)
					return plan.pop_front()
	# 2) 空中追击
	var launched: Array = shades.filter(func(s): return s.state == Shade.State.LAUNCHED)
	if not launched.is_empty():
		var t = launched[0]
		var tdx: float = t.global_position.x - px
		var tdir := 1.0 if tdx > 0 else -1.0
		if on_floor:
			if absf(tdx) < 240 and p.state == 0:
				tap([&"jump", &"aim_up"], Vector2(tdir, -1), 3)
				plan.append(fr([], [], Vector2(tdir * 0.5, 0)))
				for i in 8:
					plan.append(fr([], [], Vector2(tdir * 0.5, 0)))
				tap([&"jump", &"aim_up"], Vector2(tdir, -1), 3)
				return plan.pop_front()
			if p.state == 0 or absf(tdx) > 60:
				return fr([&"move_right" if tdir > 0 else &"move_left"], [], Vector2(tdir, 0))
			return fr()
		if tick - last_j > 12:
			last_j = tick
			if p.air_combo_index >= 1:
				# 离墙近 → 横扫撞墙；否则下砸
				var wall_dist: float = (t.arena_right - t.global_position.x) if p.facing > 0 else (t.global_position.x - t.arena_left)
				if wall_dist < 500 or rng.randf() < 0.3:
					tap([&"attack_light", &"move_right" if p.facing > 0 else &"move_left"], Vector2(p.facing, 0), 3)
				else:
					tap([&"attack_light", &"move_down"], Vector2(0, 1), 3)
			else:
				tap([&"attack_light"], Vector2(tdir * 0.3, 0), 3)
			return plan.pop_front()
		return fr([], [], Vector2(tdir * 0.4, 0))
	# 3) 眩晕 → W+J 挑飞
	if nearest.state == Shade.State.STUNNED and absf(dx) < 170:
		if p.facing != int(dir):
			return fr([mv], [], Vector2(dir, 0))
		if tick - last_j > 10:
			last_j = tick
			tap([&"aim_up", &"jump", &"attack_light"], Vector2(0, -1), 4)
			return plan.pop_front()
		return fr()
	if absf(dx) > 120:
		return fr([mv], [], Vector2(dir, 0))
	if p.facing != int(dir):
		return fr([mv], [], Vector2(dir, 0))
	if tick - last_j > 14:
		last_j = tick
		# 对甲影偶尔蓄力
		if nearest.kind == Shade.Kind.BRUTE and not nearest.is_armored() and rng.randf() < 0.25:
			tap([&"attack_light"], Vector2.ZERO, 34)
		else:
			tap([&"attack_light"], Vector2.ZERO, 3)
		return plan.pop_front()
	return fr()
func run() -> void:
	rng.seed = int(OS.get_environment("SEED") if OS.get_environment("SEED") != "" else "7")
	skill = float(OS.get_environment("SKILL") if OS.get_environment("SKILL") != "" else "0.8")
	stage = load("res://scenes/night_trial.tscn").instantiate()
	root.add_child(stage)
	await process_frame
	p = stage.player
	p.died.connect(func(): deaths[0] += 1; plan.clear())
	stage.encounter.cleared.connect(func(): enc_clear.append(["%.1fs" % (tick / 60.0), int(p.hp), deaths[0], "stun%d launch%d slam%d wall%d chain%d parry%d hit%d dmg%d" % [snap.stun, snap.launch, snap.slam, snap.wall, snap.chain, snap.parry, snap.times_hit, snap.damage_taken], dmg_by.duplicate()]))
	stage.encounter.shade_spawned.connect(func(s): s.strike_landed.connect(func(_pt): dmg_by[s.display_name()] = dmg_by.get(s.display_name(), 0) + 1))
	var max_frames := int(OS.get_environment("BOT_FRAMES")) if OS.get_environment("BOT_FRAMES") != "" else 18000
	var want := int(OS.get_environment("BOT_ENC")) if OS.get_environment("BOT_ENC") != "" else 3
	var best := 0
	while tick < max_frames and enc_clear.size() < want:
		tick += 1
		snap = stage.style.stats.duplicate()
		p.set_injected_frame(decide())
		await physics_frame
		best = maxi(best, stage.style.rank_index())
	# 录屏用：打完后继续空跑 BOT_TAIL 帧，把结算面板录进去
	var tail := int(OS.get_environment("BOT_TAIL")) if OS.get_environment("BOT_TAIL") != "" else 0
	for _i in tail:
		tick += 1
		p.set_injected_frame(fr())
		await physics_frame
	for c in enc_clear:
		print("ENC ", c)
	print("RESULT frames ", tick, " (", "%.1f" % (tick / 60.0), "s) deaths ", deaths[0], " clears ", enc_clear, " hp ", int(p.hp))
	print("STATS ", stage.style.stats, " max_combo ", stage.style.max_combo, " best_rank ", best)
	quit()
