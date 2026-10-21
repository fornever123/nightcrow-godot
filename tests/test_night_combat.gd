extends SceneTree
## 试玩关卡「月下堤岸」战斗回归测试（设计见 docs/HANDOFF-试玩版.md §7）。
## 覆盖：主场景设置、眩晕连段主线（失衡→眩晕→挑飞→浮空→下砸 / 横扫撞墙）、
## 连锁击飞、12 帧弹刀窗口、评价系统、封印波次流程。
## 运行：godot --headless --fixed-fps 60 --path . --script res://tests/test_night_combat.gd
const Buffer := preload("res://scripts/core/input_buffer.gd")
const Shade := preload("res://scripts/night/shade.gd")
const Style := preload("res://scripts/night/style_meter.gd")

var stage
var p
var checks := 0
var failures: Array[String] = []


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		print("FAIL: ", label)


func _initialize() -> void:
	call_deferred("run")


func fr(actions: Array[StringName] = [], edges: Array[StringName] = [], axis := Vector2.ZERO) -> Buffer.Frame:
	var x := Buffer.Frame.new()
	x.actions = actions
	x.pressed_this_frame = edges
	x.axis = axis
	return x


func hold(n: int, x: Buffer.Frame, probe: Callable = Callable()) -> void:
	p.set_injected_frame(x)
	for i in n:
		await physics_frame
		if probe.is_valid():
			probe.call()


func tap(edges: Array[StringName], axis := Vector2.ZERO, n := 3, gap := 0, probe: Callable = Callable()) -> void:
	await hold(1, fr(edges, edges, axis), probe)
	await hold(n - 1, fr(edges, [], axis), probe)
	if gap > 0:
		await hold(gap, fr([], [], axis), probe)


## 在玩家右边放一只不会主动进攻的影（只测玩家对它的连段）
func make_shade(kind: int, x: float, active := false) -> Node2D:
	var s: Node2D = Node2D.new()
	s.set_script(Shade)
	s.setup(kind, p, stage.floor_y, 1.0)
	s.position = Vector2(x, stage.floor_y - 60.0)
	stage.add_child(s)
	s.spawn_frames = 0
	s.active = active
	stage._on_shade_spawned(s)
	return s


func record(s: Node2D) -> Dictionary:
	var ev := {}
	for sig in ["broken", "launched_high", "slam_impact", "wall_slam", "chain_hit", "died", "parried", "strike_landed"]:
		ev[sig] = 0
		s.connect(sig, func(_a = null, _b = null, _c = null): ev[sig] += 1)
	return ev


func fresh_player(x := 600.0) -> void:
	for s in get_nodes_in_group(&"shade"):
		s.queue_free()
	await physics_frame
	p.reset_state(Vector2(x, stage.floor_y - p.foot_offset))
	p._set_facing(1)
	p.hp = p.max_hp
	stage.style.reset_all()
	await hold(4, fr())


## 地面连打 J 直到眩晕；返回用了几下
func pound_until_stun(ev: Dictionary) -> int:
	var taps := 0
	while ev.broken == 0 and taps < 12:
		await tap([&"attack_light"], Vector2.ZERO, 3, 13)
		taps += 1
	return taps


## 挑飞 → 起跳 → 二段跳 → 空中两刀，返回挑飞瞬间记录到的最高上升速度
func launch_and_juggle(s: Node2D, ev: Dictionary) -> float:
	var vmin := [0.0]
	var probe := func():
		if is_instance_valid(s) and s.state == Shade.State.LAUNCHED:
			vmin[0] = minf(vmin[0], s.velocity.y)
	await hold(10, fr(), probe)
	await tap([&"aim_up", &"jump", &"attack_light"], Vector2(0, -1), 4, 0, probe)
	var t0 := 0
	while ev.launched_high == 0 and t0 < 60:
		await hold(1, fr(), probe)
		t0 += 1
	await hold(10, fr(), probe)
	var t1 := 0
	while p.is_on_floor() and t1 < 12:
		await tap([&"jump", &"aim_up"], Vector2(0, -1), 3, 2, probe)
		t1 += 1
	await hold(10, fr(), probe)
	await tap([&"jump", &"aim_up"], Vector2(0, -1), 3, 3, probe)
	await tap([&"attack_light"], Vector2.ZERO, 3, 14, probe)
	await tap([&"attack_light"], Vector2.ZERO, 3, 14, probe)
	return vmin[0]


func run() -> void:
	# --- 项目设置 ---
	check(String(ProjectSettings.get_setting("application/run/main_scene")) == "res://scenes/night_trial.tscn", "主场景是试玩关卡")
	check(not String(ProjectSettings.get_setting("application/config/name")).contains("夜鸦"), "项目名不使用“夜鸦”")
	stage = load("res://scenes/night_trial.tscn").instantiate()
	root.add_child(stage)
	await process_frame
	p = stage.player
	check(p != null and p.can_die, "试玩关卡的角色可以倒下")
	check(p.launcher_cancel and String(p.root_motion_block_group) == "shade", "试玩关卡开启挑飞取消与贴身刹车")
	check(int(p._guard_config().get("parryWindowFrames", 0)) == stage.PARRY_WINDOW, "弹刀窗口 = 试玩关卡设置")
	test_backdrop()
	stage.set_physics_process(false)   # 先不触发封印，单独测战斗
	await test_slam_route()
	await test_drive_route()
	await test_chain()
	await test_parry_window()
	test_style_meter()
	await test_encounter_flow()
	print("NIGHT_COMBAT_TESTS: ", checks, " checks / ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)


func test_backdrop() -> void:
	var b: Node2D = stage.backdrop
	check(b != null and b.ok, "夜景图层加载成功（webp + 着色器）")
	if b == null:
		return
	check(b.tex.sky.get_width() >= 1376 and b.tex.moon.get_width() == int(b.meta.moon.size[0]), "星空比一屏宽（镜像接缝不进画面）、月亮单独一层")
	var same := true
	for n in ["clouds_low", "clouds", "sea", "mountains", "castle", "bridge", "near"]:
		same = same and b.tex[n].get_width() == int(b.meta[n].period)
	check(same, "云/海/山/城堡/桥/近景：贴图宽 = 无缝周期")
	var order := [b._scroll("sky", -1), b._scroll("clouds_low", -1), b._scroll("clouds", -1), b._scroll("mountains", -1), b._scroll("castle", -1), b._scroll("bridge", -1)]
	var inc := true
	for i in range(1, order.size()):
		inc = inc and order[i - 1] < order[i]
	check(inc and order[-1] < 1.0, "视差由远到近递增：星空 < 下层云 < 上层云 < 山 < 城堡 < 桥 < 步道")
	check(is_equal_approx(b.near_top() + b.NEAR_STAND_ROW, stage.floor_y), "近景石板顶面对齐脚下地面")
	var lan: Vector2 = b.nearest_lantern(p.global_position.x)
	check(is_finite(lan.x) and absf(lan.x - p.global_position.x) <= float(b.meta.near.period) * 0.5 + 1.0, "能找到最近的灯笼")
	check(stage.get_child(0) == b, "夜景在最底层")
	var spr: Sprite2D = p.get_node("Visual/ActorSprite")
	check(stage.light_mat != null and spr.material == stage.light_mat, "角色挂上环境光材质（只在试玩关卡）")
	var lan0: Vector2 = b.nearest_lantern(600.0)
	var lit: Vector3 = b.lantern_light(lan0 + Vector2(-80.0, 20.0))
	var dark: Vector3 = b.lantern_light(Vector2(lan0.x + float(b.meta.near.period) * 0.5, 520.0))
	check(lit.x > 0.3 and lit.y > 0.9 and dark.x == 0.0, "灯笼暖光：近处强、方向朝灯，两灯中间为 0")


func test_slam_route() -> void:
	await fresh_player()
	var s := make_shade(Shade.Kind.GRUNT, 700.0)
	var ev := record(s)
	await hold(4, fr())
	var taps := await pound_until_stun(ev)
	check(ev.broken == 1 and taps <= 8, "影卒 8 下以内打满失衡（实际 %d 下）" % taps)
	check(s.state == Shade.State.STUNNED, "失衡后进入眩晕")
	var vmin := await launch_and_juggle(s, ev)
	check(ev.launched_high >= 1, "眩晕中 W+J 挑飞成功")
	check(vmin <= -1008.0, "眩晕挑飞够高（vy=%d）" % int(vmin))
	check(s.juggle_count >= 2, "空中连斩接上了（托起 %d 次）" % s.juggle_count)
	await tap([&"attack_light", &"move_down"], Vector2(0, 1), 3, 40)
	await hold(50, fr())
	check(ev.slam_impact >= 1, "S+J 下砸砸地")
	var st: Dictionary = stage.style.stats
	check(st.stun >= 1 and st.launch >= 1 and st.slam >= 1, "评价系统记到 眩晕/挑飞/下砸")
	check(stage.style.max_combo >= 6, "整套连段连击数 ≥ 6（实际 %d）" % stage.style.max_combo)
	check(stage.style.rank_index() >= 2, "一套下砸连段至少到 B（实际 %s）" % stage.style.rank_letter())


func test_drive_route() -> void:
	await fresh_player()
	var s := make_shade(Shade.Kind.GRUNT, 700.0)
	s.arena_right = 1250.0
	s.hp = 400.0   # 连段伤害递增后影卒会在半路被打死；这里要测的是活着撞墙
	var ev := record(s)
	await hold(4, fr())
	await pound_until_stun(ev)
	await launch_and_juggle(s, ev)
	var vmax := [0.0]
	await tap([&"attack_light", &"move_right"], Vector2(1, 0), 3, 40, func():
		if is_instance_valid(s):
			vmax[0] = maxf(vmax[0], s.velocity.x))
	await hold(30, fr())
	check(vmax[0] >= 900.0, "按住前方+J 横扫把影打横飞（vx=%d）" % int(vmax[0]))
	check(ev.wall_slam >= 1, "横扫撞上封印墙")
	check(stage.style.stats.wall >= 1, "评价系统记到撞墙")


func test_chain() -> void:
	await fresh_player(300.0)
	var a := make_shade(Shade.Kind.GRUNT, 700.0)
	var b := make_shade(Shade.Kind.GRUNT, 860.0)
	var c := make_shade(Shade.Kind.BRUTE, 1180.0)
	var eb := record(b)
	var ec := record(c)
	await hold(2, fr())
	a.state = Shade.State.LAUNCHED
	a.chain_armed = true
	a.velocity = Vector2(1150.0, -160.0)
	a.position.y = stage.floor_y - 60.0 - 6.0
	await hold(40, fr())
	check(eb.chain_hit >= 1, "高速飞出的影撞到别的影 → 连锁击飞")
	check(b.state == Shade.State.LAUNCHED or b.state == Shade.State.DOWN or b.state == Shade.State.DEAD, "被连锁的影卒被撞飞")
	check(c.state != Shade.State.LAUNCHED, "甲影不会被普通连锁撞飞")
	check(stage.style.stats.chain >= 1, "评价系统记到连锁")


func parry_trial(lead: int) -> Dictionary:
	await fresh_player()
	var s := make_shade(Shade.Kind.GRUNT, 700.0, true)
	var ev := record(s)
	await hold(4, fr())
	s.cooldown = 0
	s._begin_windup()
	var windup: int = int(s.spec.windup)
	var pressed := false
	var hp0: float = p.hp
	for i in windup + 40:
		var remain: int = windup - s.state_frames
		if not pressed and s.state == Shade.State.WINDUP and remain <= lead:
			pressed = true
			await hold(1, fr([&"parry"], [&"parry"]))
			continue
		await hold(1, fr([&"parry"]) if pressed else fr())
	return {"parried": ev.parried, "landed": ev.strike_landed, "hp_lost": hp0 - p.hp, "state": p.state}


func test_parry_window() -> void:
	# 刀尖白星在出刀前 PARRY_CUE 帧亮起：这时按 L 一定要能弹开
	var cue := Shade.PARRY_CUE
	var on_cue := await parry_trial(cue)
	check(on_cue.parried == 1, "白星刚亮时按 L → 弹刀成功")
	var late := await parry_trial(1)
	check(late.parried == 1, "出刀前 1 帧按 L → 仍能弹刀")
	var early := await parry_trial(cue + 14)
	check(early.parried == 0, "太早按 L → 不算弹刀（只是格挡）")
	check(early.hp_lost > 0.0 and early.hp_lost < 4.0, "太早按 L 仍然格挡减伤（掉血 %.1f）" % early.hp_lost)
	var none := await parry_trial(-100)
	check(none.landed == 1 and none.hp_lost >= 6.0, "不防御会被砍中（掉血 %.1f）" % none.hp_lost)


func test_style_meter() -> void:
	var m: Variant = Style.new()
	m.add_hit(&"light_1")
	check(m.combo == 1 and m.rank_letter() == "D", "评价：初始 D")
	var g1: float = m.add_hit(&"light_1")
	var g2: float = m.add_hit(&"light_1")
	check(g2 < g1, "评价：同一招连续用收益递减")
	m.add_event(&"stun")
	m.add_event(&"launch")
	m.add_event(&"slam")
	check(m.rank_index() >= 1, "评价：眩晕+挑飞+下砸 → 至少 C（实际 %s）" % m.rank_letter())
	m.add_event(&"wall")
	m.add_event(&"chain")
	check(m.rank_index() >= 2, "评价：再加撞墙+连锁 → 至少 B（实际 %s）" % m.rank_letter())
	check(m.combo == 6, "评价：撞墙/下砸/连锁也算连击数（%d）" % m.combo)
	var before: float = m.points
	m.take_damage(10.0)
	check(m.combo == 0 and m.points <= before * 0.5, "评价：挨打清零连击、分数减半")
	m.add_hit(&"light_2")
	for i in 200:
		m.tick(1.0 / 60.0, false)
	check(m.combo == 0, "评价：超过连击窗口清零")
	m.add_hit(&"light_3")
	for i in 200:
		m.tick(1.0 / 60.0, true)
	check(m.combo == 1, "评价：有敌人浮空/眩晕时连击计时变慢")


func test_encounter_flow() -> void:
	await fresh_player(stage.START_X)
	stage.style.reset_all()
	stage.set_physics_process(true)
	var log := {"started": 0, "cleared_wave": 0, "cleared": 0}
	stage.encounter.wave_started.connect(func(_i, _n, _l): log.started += 1)
	stage.encounter.wave_cleared.connect(func(_i, _n): log.cleared_wave += 1)
	stage.encounter.cleared.connect(func(): log.cleared += 1)
	check(stage.phase == stage.Phase.EXPLORE, "开场是探索阶段")
	p.reset_state(Vector2(stage._next_center() - stage.TRIGGER_BEFORE + 10.0, stage.floor_y - p.foot_offset))
	await hold(3, fr())
	check(stage.phase == stage.Phase.FIGHT, "走到封印前 → 封印合上进入战斗")
	var spawned := 0
	for i in 1500:
		await physics_frame
		p.hp = p.max_hp
		for s in get_nodes_in_group(&"shade"):
			if s.state != Shade.State.DEAD and s.spawn_frames <= 0:
				s._die(1)
				spawned += 1
		if log.cleared > 0:
			break
	var waves: Array = stage.ROUND[0]
	var expected := 0
	for w in waves:
		expected += (w.get("spawns", []) as Array).size() + (w.get("reinforce", []) as Array).size()
	check(log.started == waves.size(), "第一处封印 %d 波都出来了（%d）" % [waves.size(), log.started])
	check(log.cleared_wave == waves.size() and log.cleared == 1, "清完所有波 → 封印解除")
	check(spawned == expected, "第一处封印共 %d 只影（含增援，实际 %d）" % [expected, spawned])
	await hold(2, fr())
	check(stage.phase == stage.Phase.EXPLORE and stage.encounter_index == 1, "解除后可以继续往右走")
	check(stage.back_limit > stage.START_X, "身后的路被封住（不能往回走）")
