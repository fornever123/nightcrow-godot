extends SceneTree
## 试玩关卡「月下堤岸」战斗回归测试（设计见 docs/HANDOFF-试玩版.md §7）。
## 覆盖：主场景设置、连段主线（连续击退→挑飞→浮空→下砸 / 横扫撞墙；2026-10-21 起不再有失衡/眩晕）、
## 连锁击飞、12 帧弹刀窗口、评价系统、封印波次流程。
## 运行：godot --headless --fixed-fps 60 --path . --script res://tests/test_night_combat.gd
const Buffer := preload("res://scripts/core/input_buffer.gd")
const Shade := preload("res://scripts/night/shade.gd")
const Style := preload("res://scripts/night/style_meter.gd")
const PlayerScript := preload("res://scripts/gameplay/player.gd")
const Factory := preload("res://scripts/night/player_factory.gd")

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


## 地面先砍两刀开连段（连续击退：第一下就有推力）；返回实际命中次数
func open_combo(s: Node2D, ev: Dictionary) -> int:
	var hp0: float = s.hp
	await tap([&"attack_light"], Vector2.ZERO, 3, 13)
	await tap([&"attack_light"], Vector2.ZERO, 3, 13)
	return s.combo_taken if s.hp < hp0 else 0


## 挑飞 → 起跳 → 空中两刀，返回挑飞瞬间记录到的最高上升速度。
## 跳高加倍后不再追加旧的固定二段跳，否则会直接跳过目标。
func launch_and_juggle(s: Node2D, ev: Dictionary) -> float:
	var vmin := [0.0]
	var probe := func():
		if is_instance_valid(s) and s.state == Shade.State.LAUNCHED:
			vmin[0] = minf(vmin[0], s.velocity.y)
	await hold(10, fr(), probe)
	await tap([&"aim_up", &"jump", &"attack_light"], Vector2(0, -1), 4, 0, probe)
	var t0 := 0
	while not (is_instance_valid(s) and s.state == Shade.State.LAUNCHED) and t0 < 60:
		await hold(1, fr(), probe)
		t0 += 1
	await hold(10, fr(), probe)
	var t1 := 0
	while p.is_on_floor() and t1 < 12:
		await tap([&"jump", &"aim_up"], Vector2(0, -1), 3, 2, probe)
		t1 += 1
	await hold(7, fr(), probe)
	await tap([&"attack_light"], Vector2.ZERO, 3, 14, probe)
	await tap([&"attack_light"], Vector2.ZERO, 3, 14, probe)
	return vmin[0]


func run() -> void:
	# --- 项目设置 ---
	check(String(ProjectSettings.get_setting("application/run/main_scene")) == "res://scenes/rain_trial.tscn", "主场景是雨街试玩关卡")
	check(not String(ProjectSettings.get_setting("application/config/name")).contains("夜鸦"), "项目名不使用“夜鸦”")
	stage = load("res://scripts/night/night_trial.gd").new()   # 战斗基类（不带背景），测通用机制；雨街本身见 test_rain_trial
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
	await test_launch_rules()
	test_control_schemes()
	await test_dash_input()
	await test_air_jump_refund()
	await test_charge_feel()
	await test_air_dash()
	test_style_meter()
	await test_encounter_flow()
	print("NIGHT_COMBAT_TESTS: ", checks, " checks / ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)


## 月下堤岸背景已删（2026-10-30），基类不带背景：确认没有背景也能照常开打。雨街背景的检查在 test_rain_trial。
func test_backdrop() -> void:
	check(stage.backdrop == null and stage.terrain != null and p != null, "战斗基类不带背景也能搭好地形和角色")


func test_slam_route() -> void:
	await fresh_player()
	var s := make_shade(Shade.Kind.GRUNT, 700.0)
	var ev := record(s)
	await hold(4, fr())
	var hits := await open_combo(s, ev)
	check(hits >= 2 and ev.broken == 0 and s.state != Shade.State.STUNNED, "地面两刀都打中，不再进入眩晕（连击 %d）" % hits)
	var vmin := await launch_and_juggle(s, ev)
	check(vmin <= -900.0, "W+J 挑飞够高（vy=%d）" % int(vmin))
	check(s.juggle_count >= 2, "空中连斩接上了（托起 %d 次）" % s.juggle_count)
	await tap([&"attack_light", &"move_down"], Vector2(0, 1), 3, 40)
	await hold(50, fr())
	check(ev.slam_impact >= 1, "S+J 下砸砸地")
	var st: Dictionary = stage.style.stats
	check(st.launch >= 1 and st.slam >= 1, "评价系统记到 挑飞/下砸")
	check(stage.style.max_combo >= 6, "整套连段连击数 ≥ 6（实际 %d）" % stage.style.max_combo)
	check(stage.style.rank_index() >= 2, "一套下砸连段至少到 B（实际 %s）" % stage.style.rank_letter())


func test_drive_route() -> void:
	await fresh_player()
	var s := make_shade(Shade.Kind.GRUNT, 700.0)
	s.arena_right = 1250.0
	s.hp = 400.0   # 连段伤害递增后影卒会在半路被打死；这里要测的是活着撞墙
	var ev := record(s)
	await hold(4, fr())
	await open_combo(s, ev)
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
	check(ec.chain_hit >= 1 and c.state == Shade.State.LAUNCHED, "甲影不出刀时也会被连锁撞飞（11-01 只在出刀时霸体）")
	check(stage.style.stats.chain >= 1, "评价系统记到连锁")


func parry_trial(lead: int, kind: int = Shade.Kind.GRUNT) -> Dictionary:
	await fresh_player()
	var s := make_shade(kind, 700.0, true)
	var ev := record(s)
	await hold(4, fr())
	s.cooldown = 0
	s._begin_windup()
	var windup: int = int(s.spec.windup)
	var pressed := false
	var hp0: float = p.hp
	var blast := Vector2.ZERO
	var launched := false
	for i in windup + 40:
		var remain: int = windup - s.state_frames
		if not pressed and s.state == Shade.State.WINDUP and remain <= lead:
			pressed = true
			await hold(1, fr([&"parry"], [&"parry"]))
			continue
		await hold(1, fr([&"parry"]) if pressed else fr())
		if is_instance_valid(s) and s.state == Shade.State.LAUNCHED:
			launched = true
			blast.x = maxf(blast.x, absf(s.velocity.x))
			blast.y = minf(blast.y, s.velocity.y)
	return {"parried": ev.parried, "landed": ev.strike_landed, "hp_lost": hp0 - p.hp, "state": p.state,
			"launched": launched, "blast": blast, "broken": ev.broken}


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
	# 11-01：弹刀直接把敌人炸飞（不再原地硬直）；甲影出刀被弹 = 霸体被炸破
	check(on_cue.launched and on_cue.blast.x >= 800.0 and on_cue.blast.y <= -700.0,
			"弹刀把影卒炸飞（vx %d / vy %d）" % [int(on_cue.blast.x), int(on_cue.blast.y)])
	check(early.launched == false, "只是格挡（没弹到）不会把它炸飞")
	var brute := await parry_trial(cue, Shade.Kind.BRUTE)
	check(brute.parried == 1 and brute.broken == 1 and brute.launched and brute.blast.x >= 900.0,
			"弹刀炸破甲影霸体（vx %d，broken %d）" % [int(brute.blast.x), brute.broken])


## 11-01：所有敌人都能挑飞，甲影只在前摇 + 出刀时霸体；击退越连越远、越连越高
func test_launch_rules() -> void:
	await fresh_player()
	var b := make_shade(Shade.Kind.BRUTE, 700.0)
	b.hp = 600.0
	var eb := record(b)
	await hold(4, fr())
	await tap([&"aim_up", &"jump", &"attack_light"], Vector2(0, -1), 4, 0)
	var vy := [0.0]
	await hold(30, fr(), func():
		if is_instance_valid(b) and b.state == Shade.State.LAUNCHED:
			vy[0] = minf(vy[0], b.velocity.y))
	check(eb.launched_high >= 1 and vy[0] <= -Shade.LAUNCH_MIN_SPEED + 1.0, "甲影不出刀时 W+J 照样挑飞（vy %d）" % int(vy[0]))
	await fresh_player()
	var a := make_shade(Shade.Kind.BRUTE, 700.0)
	a.hp = 600.0
	await hold(4, fr())
	a._begin_windup()
	var hp0: float = a.hp
	await tap([&"aim_up", &"jump", &"attack_light"], Vector2(0, -1), 4, 0)
	await hold(8, fr())
	check(a.hp < hp0 and a.state != Shade.State.LAUNCHED and a.state != Shade.State.HITSTUN,
			"甲影出刀时霸体：照样掉血，但挑不飞、打不断（%s）" % a.debug_state_name())
	var g := make_shade(Shade.Kind.GRUNT, 1000.0)
	g.combo_taken = 1
	var k1: float = g.knock_mul()
	g.combo_taken = 11
	var k11: float = g.knock_mul()
	g.combo_taken = 30
	check(is_equal_approx(k1, 1.0) and is_equal_approx(k11, Shade.COMBO_KNOCK_MAX) and is_equal_approx(g.knock_mul(), k11),
			"连续命中击退倍率：第 1 下 1 倍 → 第 11 下封顶 %.1f 倍" % k11)



func _bound(action: StringName) -> Array:
	var out := []
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			out.append(e.physical_keycode)
		elif e is InputEventMouseButton:
			out.append("mouse%d" % e.button_index)
	return out


## 11-01 用户：“键鼠和键盘要二选一，默认键盘”
func test_control_schemes() -> void:
	check(Factory.scheme() == Factory.SCHEME_KEYBOARD, "默认键位方案是键盘")
	check(_bound(&"attack_light") == [KEY_J] and _bound(&"parry") == [KEY_L] and _bound(&"attack_ranged") == [KEY_K]
			and _bound(&"dash_modifier") == [KEY_SHIFT], "键盘方案：J / K / L / Shift，没有鼠标键 %s" % [_bound(&"attack_light")])
	Factory.set_scheme(Factory.SCHEME_MOUSE, false)
	stage.apply_control_scheme()
	check(_bound(&"attack_light") == ["mouse%d" % MOUSE_BUTTON_LEFT] and _bound(&"parry") == [KEY_E]
			and _bound(&"attack_ranged") == [KEY_Q] and _bound(&"dash_modifier").has(KEY_SHIFT)
			and _bound(&"dash_modifier").has("mouse%d" % MOUSE_BUTTON_RIGHT), "键鼠方案：左键 / Q / E / 右键 + Shift，J / K / L 不起作用")
	check(String(stage.hud.help_text).contains("左键 攻击") and not String(stage.hud.help_text).contains("J 攻击"), "键鼠方案的底部提示写左键")
	var pad_ok := false
	for e in InputMap.action_get_events(&"attack_light"):
		pad_ok = pad_ok or e is InputEventJoypadButton
	Factory.set_scheme(Factory.SCHEME_KEYBOARD, false)
	stage.apply_control_scheme()
	check(pad_ok and _bound(&"attack_light") == [KEY_J] and String(stage.hud.help_text).contains("J 攻击"), "切回键盘；手柄两种方案下都在")

## 11-01（第二版）：Shift / 右键 / 手柄 B 单按 = 冲刺斩（按着 A / D 朝那边，否则朝面向）；
## A / D + J 回到普通三连；W+J 仍是上挑；R 单按放大招
func test_dash_input() -> void:
	await fresh_player()
	await tap([&"move_left", &"dash_modifier"], Vector2(-1, 0), 3)
	check(p.current_move == p.dash_left_move and p.facing == -1, "按住 A 再按 Shift → 向左冲刺斩")
	await hold(70, fr())
	await fresh_player()
	await tap([&"dash_modifier"], Vector2.ZERO, 3)
	check(p.current_move == p.dash_move and p.facing == 1, "不按方向的 Shift → 朝面向冲刺斩")
	await hold(70, fr())
	await fresh_player()
	await tap([&"move_right", &"attack_light"], Vector2(1, 0), 3)
	check(p.current_move == p.light_combo[0], "按着 D 的 J → 普通第一刀，不再是冲刺斩")
	await hold(40, fr())
	await fresh_player()
	await tap([&"move_right", &"aim_up", &"attack_light"], Vector2(1, -1), 3)
	check(p.current_move == p.up_strike_move, "按着 D 的 W+J 仍是上挑")
	await hold(90, fr())
	await fresh_player()
	await tap([&"attack_light"], Vector2.ZERO, 3, 13)
	await tap([&"move_right", &"dash_modifier"], Vector2(1, 0), 3)
	var t := 0
	while p.current_move != p.dash_move and t < 20:
		await hold(1, fr([&"move_right"], [], Vector2(1, 0)))
		t += 1
	check(p.current_move == p.dash_move, "连段里按 Shift 也出冲刺斩")
	await hold(70, fr())
	# 只加速中间那段大冲刺（burstFrameStart～End），起步和收尾原速；按动画时间变速，总距离不变
	check(p.dash_move.total_frames() <= 49 and p.dash_left_move.total_frames() <= 46 and p.dash_move.startup_frames == 3,
			"冲刺斩只加速中段：整招 %d / %d 帧（原 55 / 53）" % [p.dash_move.total_frames(), p.dash_left_move.total_frames()])
	var whole := 0.0
	var root_x: Array = p.dash_move.root_motion_x
	await fresh_player()
	var x0: float = p.global_position.x
	await tap([&"dash_modifier"], Vector2.ZERO, 1)
	await hold(70, fr())
	whole = p.global_position.x - x0
	check(absf(whole - float(root_x[-1])) < 20.0, "冲刺斩总距离不变（%.0f，动画根位移 %.0f）" % [whole, float(root_x[-1])])
	await fresh_player()
	p.ult_energy = 0.0
	await tap([&"ult"], Vector2.ZERO, 3)
	check(not p.is_ult(), "能量没满按 R 不放大招")
	p.ult_energy = p.ult_max
	await tap([&"ult"], Vector2.ZERO, 3)
	check(p.is_ult() and p.ult_energy == 0.0, "能量满按 R → 放大招")
	t = 0
	while p.is_ult() and t < 600:
		await hold(1, fr())
		t += 1
	check(not p.is_ult(), "R 放的大招正常放完（%d 帧）" % t)


## 11-01：冲刺斩 / W+J / 空中 J 每打中敌人 2 次 → +1 次空中跳（最多存 2 次，落地清零）
func test_air_jump_refund() -> void:
	await fresh_player()
	var a := make_shade(Shade.Kind.GRUNT, 700.0)
	var b := make_shade(Shade.Kind.GRUNT, 760.0)
	a.hp = 400.0
	b.hp = 400.0
	await hold(4, fr())
	var refunds := [0]
	var cb := func(_n: int): refunds[0] += 1
	p.air_jump_refunded.connect(cb)
	await tap([&"move_right", &"dash_modifier"], Vector2(1, 0), 3)
	await hold(50, fr())
	check(refunds[0] == 1 and p.bonus_air_jumps == 1, "冲刺斩连穿两只 → 返还 1 次空中跳（%d）" % p.bonus_air_jumps)
	await tap([&"jump"], Vector2.ZERO, 3, 6)
	await tap([&"jump"], Vector2.ZERO, 3, 6)
	var air_before: bool = not p.is_on_floor()
	check(air_before and p._can_jump(), "二段跳用完还能用返还的那一跳")
	var t := 0
	while not p.is_on_floor() and t < 180:
		await hold(1, fr())
		t += 1
	await hold(2, fr())   # is_on_floor 在 move_and_slide 之后才变，落地结算在下一帧开头
	check(p.is_on_floor() and p.bonus_air_jumps == 0, "落地清零返还的空中跳")
	p.bonus_air_jumps = p.air_jump_refund_max
	p._refund_hits = 0
	p._count_air_jump_refund(p.dash_move)
	p._count_air_jump_refund(p.dash_move)
	check(p.bonus_air_jumps == p.air_jump_refund_max, "返还的空中跳最多存 %d 次" % p.air_jump_refund_max)
	p._count_air_jump_refund(p.light_combo[0])
	p._count_air_jump_refund(p.light_combo[0])
	check(p._refund_hits == 0, "地面普通三连不算返还")
	p.bonus_air_jumps = 0
	p.air_jump_refunded.disconnect(cb)


## 11-01：按住 J 就能蓄力（不用等普攻的接招点、松早了也出蓄力斩）；蓄力 / 蓄力斩霸体；出招减速；前摇快一倍
func test_charge_feel() -> void:
	await fresh_player()
	var held := 0
	await hold(1, fr([&"attack_light"], [&"attack_light"]))
	while p.charge_frames < 0 and held < 30:
		await hold(1, fr([&"attack_light"]))
		held += 1
	check(p.charge_frames >= 0 and held <= p.hold_to_charge_frames + 1, "按住 J %d 帧就进蓄力（不用等第一刀收招）" % (held + 1))
	await hold(2, fr([&"attack_light"]))
	await hold(1, fr())
	check(p.current_move == p.charge_move, "刚进蓄力就松手 → 照样出蓄力斩，不会退回普攻")
	check(p.charge_move.startup_frames <= 26, "蓄力斩前摇 %d 帧（原 48，快一倍）" % p.charge_move.startup_frames)
	check(is_equal_approx(p.charge_attack_movement_scale, 0.3), "蓄力斩出招移速倍率 %.2f" % p.charge_attack_movement_scale)
	var g := make_shade(Shade.Kind.GRUNT, 900.0)
	var hp0: float = p.hp
	p.take_hit(g.strike_move, -1, p.global_position, 0.0, false, 1.0, g)
	check(p.hp < hp0 and p.state == PlayerScript.State.ATTACK and p.current_move == p.charge_move, "蓄力斩出招时霸体：掉血但不被打断")
	var w := 0
	while p.current_move == p.charge_move and p.charge_move.phase_at(p.move_frame) != &"recovery" and w < 120:
		await hold(1, fr([&"move_right"], [], Vector2(1, 0)))
		w += 1
	check(absf(p.velocity.x) <= p.speed * 0.35 + 1.0 or p.current_move != p.charge_move, "蓄力斩判定段走得很慢")
	await hold(8, fr([&"move_right"], [], Vector2(1, 0)))
	check(p.current_move == p.charge_move and absf(p.velocity.x) > p.speed * 0.9,
			"蓄力斩后摇不减速（%.0f / %.0f）" % [absf(p.velocity.x), p.speed])
	await hold(150, fr())
	await fresh_player()
	await hold(1, fr([&"attack_light"], [&"attack_light"]))
	await hold(20, fr([&"attack_light"]))
	g = make_shade(Shade.Kind.GRUNT, 900.0)
	hp0 = p.hp
	p.take_hit(g.strike_move, -1, p.global_position, 0.0, false, 1.0, g)
	await hold(1, fr([&"attack_light"]))
	check(p.hp < hp0 and p.charge_frames >= 0 and p.state != PlayerScript.State.LAUNCHED, "蓄力中霸体：掉血但继续蓄")
	await hold(1, fr())
	await hold(150, fr())
	await fresh_player()
	await tap([&"attack_light"], Vector2.ZERO, 3)
	check(p.current_move == p.light_combo[0] and p.charge_frames < 0, "点按 J 仍是普攻第一刀")
	g = make_shade(Shade.Kind.GRUNT, 900.0)
	p.take_hit(g.strike_move, -1, p.global_position, 0.0, false, 1.0, g)
	check(p.state == PlayerScript.State.LAUNCHED, "普攻没有霸体，照样被打断")
	await hold(120, fr())
	# 空中蓄力：按住 J 直接进蓄力，中间不出空中普攻
	await fresh_player()
	await tap([&"jump"], Vector2.ZERO, 3, 6)
	var swung := [false]
	var probe := func():
		if p.air_combo.has(p.current_move):
			swung[0] = true
	await hold(1, fr([&"attack_light"], [&"attack_light"]), probe)
	held = 0
	while p.charge_frames < 0 and held < 30:
		await hold(1, fr([&"attack_light"]), probe)
		held += 1
	check(not p.is_on_floor() and p.charge_frames >= 0 and not swung[0], "空中按住 J → 直接蓄力，没先出普攻（%d 帧）" % (held + 1))
	await hold(3, fr([&"attack_light"]))
	await hold(1, fr())
	check(p.current_move == p.charge_move, "空中松手 → 蓄力斩")
	await hold(200, fr())
	await fresh_player()
	await tap([&"jump"], Vector2.ZERO, 3, 6)
	await tap([&"attack_light"], Vector2.ZERO, 3)
	await hold(1, fr())
	check(p.air_combo.has(p.current_move) and p.charge_frames < 0, "空中点按 J → 松手就出空中普攻")
	await hold(120, fr())


## 11-01：空中也能冲刺斩，每次腾空 1 次，冲刺段平着冲出去，落地回满
func test_air_dash() -> void:
	await fresh_player()
	await tap([&"jump"], Vector2.ZERO, 3, 14)
	check(not p.is_on_floor(), "起跳离地")
	await tap([&"dash_modifier"], Vector2.ZERO, 1)
	check(p.current_move == p.dash_move and p._dash_in_air, "空中按 Shift → 冲刺斩")
	var y0: float = p.global_position.y
	var drift := 0.0
	while p.current_move == p.dash_move and p.dash_move.phase_at(p.move_frame) != &"recovery":
		await hold(1, fr())
		drift = maxf(drift, absf(p.global_position.y - y0))
	check(drift < 2.0, "空中冲刺段不往下掉（偏 %.1f）" % drift)
	await hold(70, fr())
	await fresh_player()
	await tap([&"jump"], Vector2.ZERO, 3, 10)
	await tap([&"dash_modifier"], Vector2.ZERO, 1, 70)
	check(not p.is_on_floor() or p._air_dash_left == p.air_dash_uses, "第一次空中冲刺斩放完")
	if not p.is_on_floor():
		await tap([&"dash_modifier"], Vector2.ZERO, 1)
		check(p.current_move != p.dash_move, "同一次腾空第二下 Shift 不出冲刺斩")
	var t := 0
	while not p.is_on_floor() and t < 180:
		await hold(1, fr())
		t += 1
	await hold(2, fr())
	check(p._air_dash_left == p.air_dash_uses, "落地回满空中冲刺斩")
	await hold(20, fr())


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
