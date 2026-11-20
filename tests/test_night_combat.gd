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
	for sig in ["broken", "shell_broken", "launched_high", "slam_impact", "wall_slam", "chain_hit", "died", "parried", "strike_landed", "guarded", "guard_broken", "momentum_blasted", "shell_clanged", "momentum_threshold_reached", "lethal_blow"]:
		ev[sig] = 0
		s.connect(sig, func(_a = null, _b = null, _c = null): ev[sig] += 1)
	return ev


func fresh_player(x := 600.0) -> void:
	for s in get_nodes_in_group(&"shade"):
		s.queue_free()
	stage.reset_time_scale()
	await physics_frame
	p.unlimited_dash = true
	p.shadow_cost_enabled = false
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
	# 11-03：首页线把默认入口接到了 yg_title_duanguang.tscn（他们在自己的首页任务里改的）。
	# 战斗线只要求"雨街试玩场景还在、能被当成入口"，不再钉死 main_scene 是哪一个。
	var entry := String(ProjectSettings.get_setting("application/run/main_scene"))
	check(entry == "res://scenes/rain_trial.tscn" or entry.ends_with("yg_title_duanguang.tscn") or entry.ends_with("yg_title_zhanzhong.tscn"),  # [YG-MARK] 11-17 首页线入口换成《斩钟》首页
		"默认入口是雨街试玩（或首页接管：%s）" % entry)
	check(ResourceLoader.exists("res://scenes/rain_trial.tscn"), "雨街试玩场景还在")
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
	await test_dash_double_tap()
	await test_air_jump_refund()
	await test_air_overlap_hit()
	await test_mash_cycles_combo()
	await test_charge_feel()
	await test_air_interrupts()
	await test_heavy_strike()
	await test_air_dash()
	await test_shadow_pool_and_short_dash()
	await test_armored_platinum_shell()
	await test_shadow_pursuit_1a()
	await test_perfect_dodge_and_flash_heavy()
	await test_overkill_body_persistence()
	await test_unlimited_dash_and_enhanced_a4()
	await test_combo_juggle_and_balance_exit()
	await test_interrupt_continues_combo_and_juicy_hitfeel()
	await test_air_enhanced_a4_and_combo_continuation()
	await test_light_nerf_jk_branching_and_keen_edge()
	await test_normal_light_float_nerf_and_enhanced_jump_refund()
	await test_hitstop_float_reduction_and_momentum_far_blast()
	await test_aggressive_hitfeel_overhaul()
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
	await tap([&"attack_heavy", &"move_right"], Vector2(1, 0), 3, 40, func():
		if is_instance_valid(s):
			vmax[0] = maxf(vmax[0], s.velocity.x))
	await hold(30, fr())
	check(vmax[0] >= 900.0, "空中按 K 横轰重斩把影打横飞（vx=%d）" % int(vmax[0]))
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


## A2 更新：甲影（ARMORED / BRUTE）自带白金凝壳（shell_hp > 0 时免疫正面轻击/上挑，正面只削 12）；
## 白壳归零后彻底失去霸体（即便正在前摇出刀也可被任意挑飞追斩）；连续命中击退倍率保持不变
func test_launch_rules() -> void:
	await fresh_player()
	var b := make_shade(Shade.Kind.BRUTE, 700.0)
	b.hp = 600.0
	var shell0: float = b.shell_hp
	await hold(4, fr())
	await tap([&"aim_up", &"jump", &"attack_light"], Vector2(0, -1), 4, 0)
	await hold(14, fr())
	check(b.shell_hp < shell0 and is_equal_approx(shell0 - b.shell_hp, Shade.SHELL_CHIP_BASE)
			and b.state != Shade.State.LAUNCHED,
			"甲影白金凝壳在身时免疫正面 W+J 挑飞，正面只削 %.0f 壳（%.0f → %.0f）" % [
				Shade.SHELL_CHIP_BASE, shell0, b.shell_hp])
	await fresh_player()
	var a := make_shade(Shade.Kind.BRUTE, 700.0)
	a.hp = 600.0
	a._break_shell()
	stage.reset_time_scale()
	var ea := record(a)
	await hold(4, fr())
	a._begin_windup()
	await tap([&"aim_up", &"jump", &"attack_light"], Vector2(0, -1), 4, 0)
	var vy := [0.0]
	await hold(26, fr(), func():
		if is_instance_valid(a) and a.state == Shade.State.LAUNCHED:
			vy[0] = minf(vy[0], a.velocity.y))
	check(ea.launched_high >= 1 and a.state == Shade.State.LAUNCHED and vy[0] <= -Shade.LAUNCH_MIN_SPEED + 1.0,
			"甲影破壳后彻底失去霸体：即便出刀中也能被 W+J 挑飞追斩（vy %d）" % int(vy[0]))
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


## 1A 键位重构：键盘 J 轻击 / K 重击 / Shift 瞬步 / L 弹刀 / U 远射；键鼠 左键 轻击 / 右键 重击 / Shift 瞬步 / E 弹刀 / Q 远射
func test_control_schemes() -> void:
	check(Factory.scheme() == Factory.SCHEME_KEYBOARD, "默认键位方案是键盘")
	check(_bound(&"attack_light") == [KEY_J] and _bound(&"attack_heavy") == [KEY_K]
			and _bound(&"parry") == [KEY_L] and _bound(&"attack_ranged").has(KEY_U)
			and _bound(&"dash_modifier") == [KEY_SHIFT],
			"1A 键盘方案：J 轻击 / K 重击 / L 弹刀 / U 远射 / Shift 瞬步，无鼠标串键 %s" % [_bound(&"attack_light")])
	Factory.set_scheme(Factory.SCHEME_MOUSE, false)
	stage.apply_control_scheme()
	check(_bound(&"attack_light") == ["mouse%d" % MOUSE_BUTTON_LEFT]
			and _bound(&"attack_heavy") == ["mouse%d" % MOUSE_BUTTON_RIGHT]
			and _bound(&"parry") == [KEY_E] and _bound(&"attack_ranged") == [KEY_Q]
			and _bound(&"dash_modifier").has(KEY_SHIFT),
			"1A 键鼠方案：左键 轻击 / 右键 重击 / E 弹刀 / Q 远射 / Shift+侧键 瞬步，不与 J/K/L 串键")
	check(String(stage.hud.help_text).contains("左键 攻击") and String(stage.hud.help_text).contains("右键 重击")
			and not String(stage.hud.help_text).contains("J 攻击"), "键鼠方案底部提示写左键攻击、右键重击")
	var pad_ok := false
	var pad_heavy_ok := false
	for e in InputMap.action_get_events(&"attack_light"):
		pad_ok = pad_ok or (e is InputEventJoypadButton and e.button_index == JOY_BUTTON_X)
	for e in InputMap.action_get_events(&"attack_heavy"):
		pad_heavy_ok = pad_heavy_ok or (e is InputEventJoypadButton and e.button_index == JOY_BUTTON_Y)
	Factory.set_scheme(Factory.SCHEME_KEYBOARD, false)
	stage.apply_control_scheme()
	check(pad_ok and pad_heavy_ok and _bound(&"attack_light") == [KEY_J]
			and String(stage.hud.help_text).contains("J 攻击") and String(stage.hud.help_text).contains("K 重击"),
			"切回键盘方案正常；手柄 X 轻击 / Y 重击在两种方案下常驻")

## 1A：双击 A / D 触发无敌穿身瞬步（+ J 免费派生冲刺斩）；空中冲刺斩砍中人 → 穿到敌人另一侧急停回头。
func test_dash_double_tap() -> void:
	await fresh_player()
	await tap([&"move_right"], Vector2(1, 0), 2, 6)
	check(not p.is_short_dashing() and p.current_move == null, "单点 D 只移动，不触发瞬步或冲刺斩")
	await hold(24, fr())
	# 双击 D：向右无敌瞬步；跟按 J 免费派生向右冲刺斩
	await fresh_player()
	await tap([&"move_right"], Vector2(1, 0), 2, 5)
	await hold(1, fr([&"move_right"], [&"move_right"], Vector2(1, 0)))
	check(p.is_short_dashing() and p.facing == 1 and p.invuln_frames >= p.step_dash_frames,
		"双击 D → 向右无敌穿身瞬步（无敌 %d 帧）" % p.invuln_frames)
	await hold(1, fr([&"attack_light"], [&"attack_light"], Vector2(1, 0)))
	check(p.current_move == p.dash_move and p.facing == 1 and p.unlimited_dash and p.shadow_charges == p.max_shadow_charges,
		"瞬步中按 J → 免费派生向右冲刺斩且无限闪零消耗（%s, 残影=%d）" % [str(p.current_move), p.shadow_charges])
	await hold(70, fr())
	# 双击 A + J：向左冲刺斩
	await fresh_player()
	await tap([&"move_left"], Vector2(-1, 0), 2, 5)
	await hold(1, fr([&"move_left", &"attack_light"], [&"move_left", &"attack_light"], Vector2(-1, 0)))
	check(p.current_move == p.dash_left_move and p.facing == -1, "双击 A + J → 向左冲刺斩（%s）" % str(p.current_move))
	await hold(70, fr())
	# 两次点得太开（超过双击窗口）不算双击
	await fresh_player()
	await tap([&"move_right"], Vector2(1, 0), 2, p.double_tap_frames + 6)
	await tap([&"move_right"], Vector2(1, 0), 2)
	check(not p.is_short_dashing() and p.current_move == null, "两次点间隔超过 %d 帧 → 不触发瞬步" % p.double_tap_frames)
	await hold(20, fr())

	# 空中双击 D + J：空中冲刺斩砍中人停在敌人另一侧并回头接空连
	await fresh_player()
	var e := make_shade(Shade.Kind.GRUNT, p.global_position.x + 160.0)
	e.hp = 900.0
	await hold(4, fr())
	var ex: float = e.global_position.x
	var hp0: float = e.hp
	await tap([&"jump"], Vector2.ZERO, 3, 3)
	await tap([&"move_right"], Vector2(1, 0), 2, 5)
	await tap([&"move_right", &"attack_light"], Vector2(1, 0), 2)
	check(p.current_move == p.air_dash_move and p._dash_in_air, "空中双击 D + J → 空中冲刺斩（独立招式）")
	var waited := 0
	while is_instance_valid(p) and p.is_dash_move(p.current_move) and waited < 90:
		await hold(1, fr())
		waited += 1
	var side := signf(p.global_position.x - ex)
	check(e.hp < hp0, "空中冲刺斩砍中了敌人（%.0f → %.0f）" % [hp0, e.hp])
	check(side > 0.0, "砍中后停在敌人另一侧（玩家 x=%.0f / 敌人 x=%.0f）" % [p.global_position.x, ex])
	check(absf(p.global_position.x - ex) < 220.0,
		"停住的位置贴着敌人（距 %.0f px），没有冲出去一整个身位" % absf(p.global_position.x - ex))
	# 11-03 用户：“空中冲刺斩能击飞然后……”：砍中要把它挑起来、急停后回头面对它，才好接空连
	check(e.state == Shade.State.LAUNCHED and e.velocity.y < -400.0,
		"空中冲刺斩把敌人挑飞（状态 %d，vy %.0f）" % [e.state, e.velocity.y])
	check(signf(e.global_position.x - p.global_position.x) == float(p.facing),
		"急停后回头面对敌人（敌人 x=%.0f / 玩家 x=%.0f / 朝向 %d）" % [
			e.global_position.x, p.global_position.x, p.facing])
	await hold(12, fr())
	await tap([&"attack_light"], Vector2.ZERO, 2, 3)
	check(p.air_combo.has(p.current_move), "急停之后能直接接空中连段（%s）" % str(p.current_move))
	await hold(60, fr())


## 1A：Shift 单按 = 7 帧无敌穿身瞬步（穿怪自动回身）；Shift + J = 突进冲刺斩；Shift + K = 冲刺破军重斩；R = 大招。
func test_dash_input() -> void:
	await fresh_player()
	await tap([&"move_left", &"dash_modifier", &"attack_light"], Vector2(-1, 0), 2)
	check(p.current_move == p.dash_left_move and p.facing == -1, "按住 A + Shift + J → 向左冲刺斩")
	await hold(70, fr())
	await fresh_player()
	await tap([&"dash_modifier", &"attack_light"], Vector2.ZERO, 2)
	check(p.current_move == p.dash_move and p.facing == 1, "Shift + J → 朝面向冲刺斩")
	await hold(70, fr())
	await fresh_player()
	await tap([&"dash_modifier", &"attack_heavy"], Vector2.ZERO, 2)
	check(p.current_move == p.charge_move and p._charge_t >= 0.75, "Shift + K → 免费派生高速冲刺破军重斩")
	await hold(80, fr())
	await fresh_player()
	await tap([&"move_right", &"attack_light"], Vector2(1, 0), 3)
	check(p.current_move == p.light_combo[0], "按着 D 的 J → 普通第一刀")
	await hold(40, fr())
	await fresh_player()
	await tap([&"move_right", &"aim_up", &"attack_light"], Vector2(1, -1), 3)
	check(p.current_move == p.up_strike_move, "按着 D 的 W+J 仍是上挑")
	await hold(90, fr())
	await fresh_player()
	await tap([&"attack_light"], Vector2.ZERO, 3, 4)
	await hold(1, fr([&"move_right", &"dash_modifier"], [&"dash_modifier"], Vector2(1, 0)))
	check(p.is_short_dashing() and p.invuln_frames >= p.step_dash_frames, "地面普攻任意帧按 Shift 立刻无敌瞬步取消")
	await hold(15, fr())
	check(p.dash_move.total_frames() <= 49 and p.dash_left_move.total_frames() <= 46 and p.dash_move.startup_frames == 3,
			"冲刺斩只加速中段：整招 %d / %d 帧（原 55 / 53）" % [p.dash_move.total_frames(), p.dash_left_move.total_frames()])
	var whole := 0.0
	var root_x: Array = p.dash_move.root_motion_x
	await fresh_player()
	var x0: float = p.global_position.x
	await tap([&"dash_modifier", &"attack_light"], Vector2.ZERO, 1)
	await hold(70, fr())
	whole = p.global_position.x - x0
	check(absf(whole - float(root_x[-1])) < 25.0, "冲刺斩总距离不变（%.0f，动画根位移 %.0f）" % [whole, float(root_x[-1])])
	await fresh_player()
	p.ult_energy = 0.0
	await tap([&"ult"], Vector2.ZERO, 3)
	check(not p.is_ult(), "能量没满按 R 不放大招")
	p.ult_energy = p.ult_max
	await tap([&"ult"], Vector2.ZERO, 3)
	check(p.is_ult() and p.ult_energy == 0.0, "能量满按 R → 放大招")
	var t := 0
	while p.is_ult() and t < 600:
		await hold(1, fr())
		t += 1
	check(not p.is_ult(), "R 放的大招正常放完（%d 帧）" % t)


## 11-02 定稿的规则（用户：“W+J 空中冲刺斩给”）：
##   · 空中招式（三连 / 空中上挑 / 下砸 / 横扫）每命中 1 下 → +1
##   · W+J 上挑 → 打中就给（它就是挑上天的招）
##   · 空中冲刺斩 → 打中就给
##   · 地面冲刺斩 → 不给（`airJumpRefundHits = 0`，改回 2 可恢复）
## 上限 3，落地清零；空中那一路和地面那一路分开计数。
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
	check(p.air_jump_refund_hits == 0 and p.launcher_refund_hits == 1,
		"默认：地面冲刺斩不给、W+J 上挑给（%d / %d）" % [p.air_jump_refund_hits, p.launcher_refund_hits])
	# 地面冲刺斩连穿两只：不给跳
	await tap([&"move_right", &"dash_modifier", &"attack_light"], Vector2(1, 0), 3)
	await hold(50, fr())
	check(refunds[0] == 0 and p.bonus_air_jumps == 0,
		"地面冲刺斩连穿两只 → 不给空中跳（%d）" % p.bonus_air_jumps)
	# 空中冲刺斩：给
	p._refund_hits = 0
	p._refund_hits_air = 0
	p.bonus_air_jumps = 0
	p._dash_in_air = true
	p._count_air_jump_refund(p.dash_move)
	check(p.bonus_air_jumps == 1, "空中冲刺斩打中 → +1 段跳")
	p._dash_in_air = false
	p.bonus_air_jumps = 0
	p._refund_hits_air = 0
	p._count_air_jump_refund(p.dash_move)
	check(p.bonus_air_jumps == 0, "落地后的冲刺斩不给跳")
	# W+J 上挑：给
	p._refund_hits = 0
	p._refund_hits_air = 0
	p.bonus_air_jumps = 0
	p._count_air_jump_refund(p.up_strike_move)
	check(p.bonus_air_jumps == 1, "W+J 上挑打中 → +1 段跳")
	# 11-12 重做：普通普攻（地面 light_1..3 与空中 air_light_1..3）命中绝不给跳，强化普攻（light_4 / air_light_4）命中才给跳
	p._refund_hits = 0
	p._refund_hits_air = 0
	p.bonus_air_jumps = 0
	p._count_air_jump_refund(p.air_combo[0])
	p._count_air_jump_refund(p.air_combo[1])
	p._count_air_jump_refund(p.air_combo[2])
	check(p.bonus_air_jumps == 0 and p._refund_hits_air == 0,
		"11-12 规则：空中普通普攻（空1/空2/空3）命中一律不给跳（bonus=%d）" % p.bonus_air_jumps)
	p._count_air_jump_refund(p.air_combo[3])
	check(p.bonus_air_jumps == 1, "空中强化普攻（air_light_4）命中 → +1 段跳")
	p._count_air_jump_refund(p.light_combo[3])
	check(p.bonus_air_jumps == 2, "地面强化普攻（light_4）命中 → +1 段跳")
	p._count_air_jump_refund(p.air_up_move)
	check(p.bonus_air_jumps == 3, "空中上挑也算（%d）" % p.bonus_air_jumps)
	p._count_air_jump_refund(p.air_combo[3])
	check(p.bonus_air_jumps == p.air_jump_refund_max, "返还的空中跳最多存 %d 次" % p.air_jump_refund_max)
	# 那一段跳真的能用（二段跳用完之后还能再跳）。reset_state 会把返还的跳清零，所以要重新给一段
	p.reset_state(Vector2(600.0, stage.floor_y - p.foot_offset))
	await hold(4, fr())
	p.bonus_air_jumps = 1
	await tap([&"jump"], Vector2.ZERO, 3, 6)
	await tap([&"jump"], Vector2.ZERO, 3, 6)
	check(not p.is_on_floor() and p._can_jump() and p.bonus_air_jumps > 0,
		"二段跳用完还能用返还的那一跳")
	var t := 0
	while not p.is_on_floor() and t < 240:
		await hold(1, fr())
		t += 1
	await hold(2, fr())   # is_on_floor 在 move_and_slide 之后才变，落地结算在下一帧开头
	check(p.is_on_floor() and p.bonus_air_jumps == 0, "落地清零返还的空中跳")
	# 地面普通三连不算
	p._refund_hits = 0
	p._refund_hits_air = 0
	p.bonus_air_jumps = 0
	p._count_air_jump_refund(p.light_combo[0])
	p._count_air_jump_refund(p.light_combo[1])
	p._count_air_jump_refund(p.light_combo[2])
	check(p._refund_hits == 0 and p._refund_hits_air == 0 and p.bonus_air_jumps == 0, "地面普通三连（light_1..3）不算返还")
	# 参数能关：上挑改 0 之后不给
	p.launcher_refund_hits = 0
	p._refund_hits_air = 0
	p.bonus_air_jumps = 0
	p._count_air_jump_refund(p.up_strike_move)
	check(p.bonus_air_jumps == 0, "launcherRefundHits 设 0 → W+J 不给跳")
	p.launcher_refund_hits = 1
	# 地面那半条打开后機制也还在
	p.air_jump_refund_hits = 2
	p._refund_hits = 0
	p.bonus_air_jumps = 0
	p._count_air_jump_refund(p.dash_move)
	p._count_air_jump_refund(p.dash_move)
	check(p.bonus_air_jumps == 1, "把 airJumpRefundHits 改回 2 就能恢复地面冲刺斩返还（%d）" % p.bonus_air_jumps)
	p.air_jump_refund_hits = 0
	p.bonus_air_jumps = 0
	p.air_jump_refunded.disconnect(cb)


## 1A：独立重击键（K / 右键）+ 消除轻击延迟 + 25 帧极速满蓄 + 点按快速重斩 + 蓄力闪斩 + 空中一键重击
func test_charge_feel() -> void:
	# 1. 地面轻击 J：按住也不会误入蓄力，第 1 帧干脆出普攻
	await fresh_player()
	await hold(1, fr([&"attack_light"], [&"attack_light"]))
	check(p.current_move == p.light_combo[0] and p.charge_frames < 0, "地面按下 J 第 1 帧即出普攻")
	await hold(14, fr([&"attack_light"]))
	check(p.charge_frames < 0, "1A 下按住 J 绝不会误进蓄力")
	var g := make_shade(Shade.Kind.GRUNT, 900.0)
	p.take_hit(g.strike_move, -1, p.global_position, 0.0, false, 1.0, g)
	check(p.state == PlayerScript.State.LAUNCHED, "普攻没有霸体，照样被打断")
	await hold(100, fr())

	# 2. 地面点按 K（<= 6 帧松手）→ 快速重斩（_charge_t >= 0.45）+ 出招霸体 + 后摇移动打断
	await fresh_player()
	await hold(1, fr([&"attack_heavy"], [&"attack_heavy"]))
	check(p.charge_frames == 0, "按下独立重击 K 第 1 帧直接进入霸体蓄力")
	await hold(3, fr([&"attack_heavy"]))
	await hold(1, fr())
	check(p.current_move == p.charge_move and p._charge_t >= 0.45,
		"点按 K（4 帧松手）直接释放快速重斩（charge_t=%.2f）" % p._charge_t)
	check(p.charge_move.startup_frames <= 26, "重斩前摇 %d 帧" % p.charge_move.startup_frames)
	check(is_equal_approx(p.charge_attack_movement_scale, 0.3), "重斩出招移速倍率 %.2f" % p.charge_attack_movement_scale)
	g = make_shade(Shade.Kind.GRUNT, 900.0)
	var hp0: float = p.hp
	p.take_hit(g.strike_move, -1, p.global_position, 0.0, false, 1.0, g)
	check(p.hp < hp0 and p.state == PlayerScript.State.ATTACK and p.current_move == p.charge_move, "重斩出招时霸体：掉血但不被打断")
	var w := 0
	while p.current_move == p.charge_move and p.charge_move.phase_at(p.move_frame) != &"recovery" and w < 120:
		await hold(1, fr([&"move_right"], [], Vector2(1, 0)))
		w += 1
	check(absf(p.velocity.x) <= p.speed * 0.35 + 1.0 or p.current_move != p.charge_move, "重斩判定段移速受控")
	await hold(8, fr([&"move_right"], [], Vector2(1, 0)))
	check(absf(p.velocity.x) > p.speed * 0.9,
		"重斩后摇可被移动打断满速走位（%.0f / %.0f）" % [absf(p.velocity.x), p.speed])
	await hold(60, fr())

	# 3. 按住 K 25 帧（0.42s）极速满蓄 + 蓄力全程霸体
	await fresh_player()
	await hold(1, fr([&"attack_heavy"], [&"attack_heavy"]))
	await hold(12, fr([&"attack_heavy"]))
	g = make_shade(Shade.Kind.GRUNT, 900.0)
	hp0 = p.hp
	p.take_hit(g.strike_move, -1, p.global_position, 0.0, false, 1.0, g)
	await hold(13, fr([&"attack_heavy"]))
	check(p.hp < hp0 and p.charge_frames >= p.heavy_full_charge_frames and p.state != PlayerScript.State.LAUNCHED,
		"蓄力中全程霸体且 25 帧即达满蓄（charge_frames=%d）" % p.charge_frames)
	await hold(1, fr())
	check(p.current_move == p.charge_move and is_equal_approx(p._charge_t, 1.0),
		"25 帧松开 K 释放满蓄重击（charge_t=%.2f）" % p._charge_t)
	await hold(80, fr())

	# 4. 蓄力闪斩：按住 K 蓄力中按 Shift 无敌穿身且保留蓄力进度，松开 K 即劈出重斩
	await fresh_player(600.0)
	await hold(1, fr([&"attack_heavy"], [&"attack_heavy"]))
	await hold(12, fr([&"attack_heavy"]))
	var x0: float = p.global_position.x
	await hold(1, fr([&"attack_heavy", &"dash_modifier", &"move_right"], [&"dash_modifier"], Vector2(1, 0)))
	check(p.is_short_dashing() and p.charge_frames >= 12 and p.invuln_frames > 0,
		"蓄力中按冲刺触发蓄力闪斩：进入无敌瞬步且保留蓄力进度（%d 帧）" % p.charge_frames)
	await hold(4, fr([&"attack_heavy", &"move_right"], [], Vector2(1, 0)))
	await hold(1, fr())
	check(p.global_position.x - x0 > 90.0 and p.current_move == p.charge_move and p._charge_t >= 0.65,
		"蓄力闪斩换位后松开 K 当场劈出高阶重斩（位移 %.0f px，charge_t=%.2f）" % [p.global_position.x - x0, p._charge_t])
	await hold(80, fr())

	# 5. 空中轻击零松手延迟 + 空中 K 一键横轰 drive / S+K 一键急坠 slam
	await fresh_player()
	await tap([&"jump"], Vector2.ZERO, 3, 6)
	await hold(1, fr([&"attack_light"], [&"attack_light"]))
	check(not p.is_on_floor() and p.air_combo.has(p.current_move) and p.charge_frames < 0,
		"1A 空中按下 J 第 1 帧直接干脆出空中普攻（无需等松手）")
	await hold(90, fr())

	await fresh_player()
	await tap([&"jump"], Vector2.ZERO, 3, 8)
	await hold(1, fr([&"attack_heavy"], [&"attack_heavy"]))
	check(p.finisher_intent == &"drive" and p.current_move == p.air_combo[2],
		"空中单按 K 直接释放横轰重斩 air_drive")
	await hold(90, fr())

	await fresh_player()
	await tap([&"jump"], Vector2.ZERO, 3, 8)
	await hold(1, fr([&"attack_heavy", &"move_down"], [&"attack_heavy"], Vector2(0, 1)))
	check(p.finisher_intent == &"slam" and p.current_move == p.air_plunge_move,
		"空中按 S+K 直接释放急坠重劈 air_slam")
	await hold(90, fr())


## 11-03 & 1A：空中招式互断 + 瞬步打断地面/空中普攻保命 + 空中第三刀低后摇
func test_air_interrupts() -> void:
	# 空中普攻 → Shift+J：当场换成空中冲刺斩
	await fresh_player()
	await tap([&"jump"], Vector2.ZERO, 3, 9)
	await tap([&"attack_light"], Vector2.ZERO, 2, 2)
	check(p.air_combo.has(p.current_move), "空中点 J 出了空中普攻")
	await tap([&"dash_modifier", &"attack_light"], Vector2(1, 0), 1)
	check(p.current_move == p.air_dash_move, "空中普攻能被 Shift+J 空中冲刺斩打断")
	await hold(60, fr())
	# 空中冲刺斩 → 点 J：当场换成空中普攻
	await fresh_player()
	await tap([&"jump"], Vector2.ZERO, 3, 9)
	await tap([&"dash_modifier", &"attack_light"], Vector2.ZERO, 1)
	check(p.current_move == p.air_dash_move, "空中冲刺斩起手")
	await tap([&"attack_light"], Vector2.ZERO, 2, 2)
	check(p.air_combo.has(p.current_move), "空中冲刺斩能被空中普攻打断")
	await hold(60, fr())
	# 空中攻击 × 空中攻击：不抢招（仍走接招窗口）
	await fresh_player()
	await tap([&"jump"], Vector2.ZERO, 3, 9)
	await tap([&"attack_light"], Vector2.ZERO, 2, 2)
	check(p.current_move == p.air_combo[0], "空中第 1 刀起手")
	await tap([&"attack_light"], Vector2.ZERO, 2, 2)
	check(p.current_move == p.air_combo[0],
		"连按 J 不会当场跳到第 2 刀（空中攻击不打断空中攻击，仍走接招窗口）")
	await hold(60, fr())
	# 1A：地面普攻硬直中按 Shift 能立即无敌瞬步打断保命
	await fresh_player()
	await tap([&"attack_light"], Vector2.ZERO, 2, 1)
	check(p.current_move == p.light_combo[0], "地面普攻起手")
	await tap([&"dash_modifier"], Vector2(-1, 0), 1)
	check(p.is_short_dashing() and p.invuln_frames > 0, "1A 地面普攻可被 Shift 无敌瞬步紧急打断")
	await hold(40, fr())
	# 空中第三刀后摇降低
	check(p.air_combo[2].recovery_frames <= 8,
		"空中第三刀后摇 %d 帧" % p.air_combo[2].recovery_frames)


## 11-03 重击（蓄力斩）：范围半个屏幕、伤害只在挥到底那一截结算、后摇能被移动打断、命中闪白 + 压暗。
func test_heavy_strike() -> void:
	await fresh_player()
	var cm: Resource = p.charge_move
	check(cm != null and float(cm.hitbox.size.x) >= 1000.0,
		"重击判定盒横向 %d px（半个屏幕）" % int(float(cm.hitbox.size.x)))
	# 一只甲影站在 1000 px 外（判定盒盖得住，平地上的极限距离）
	var far := make_shade(Shade.Kind.BRUTE, p.global_position.x + 1000.0)
	far.hp = 900.0
	await hold(4, fr())
	var hp0: float = far.hp
	p._charge_t = 1.0
	p.charge_frames = cm.max_charge_frames
	p._start_move(cm, false)
	var early: int = cm.startup_frames + int(float(cm.active_frames) * 0.3)
	await hold(early, fr())
	check(is_equal_approx(far.hp, hp0), "重击前面挥过去的判定帧不结算伤害")
	var waited := 0
	while is_equal_approx(far.hp, hp0) and waited < int(cm.active_frames) + 40:
		await hold(1, fr())
		waited += 1
	check(far.hp < hp0, "重击在最后一截判定里结算伤害（%.0f → %.0f，横距 1000 px）" % [hp0, far.hp])
	check(waited >= int(float(cm.active_frames) * 0.6),
		"伤害落在判定段的后半（等了 %d / %d 帧）" % [waited, int(cm.active_frames)])
	check(stage.fx.flash_alpha() <= 0.0, "重击不闪白（整屏白是大招的语言，11-03 方案 A 撤掉了）")
	check(stage.fx.impact_alpha() > 0.0, "重击命中会压暗（冲击帧）")
	# 后摇可以被移动打断
	var t := 0
	while p.current_move == cm and t < 80:
		await hold(1, fr([&"move_right"], [], Vector2(1, 0)))
		t += 1
	check(p.current_move != cm, "重击后摇可以被移动打断（%d 帧后）" % t)
	check(p.state == PlayerScript.State.NEUTRAL, "被打断后回到中立，能直接跑")
	await hold(60, fr())


## 11-01 & 1A：空中 Shift+J 也能冲刺斩，冲刺段平着冲出去，同次腾空不限次（仅受残影池约束），落地回满
func test_air_dash() -> void:
	await fresh_player()
	await tap([&"jump"], Vector2.ZERO, 3, 14)
	check(not p.is_on_floor(), "起跳离地")
	await tap([&"dash_modifier", &"attack_light"], Vector2.ZERO, 1)
	check(p.current_move == p.air_dash_move and p._dash_in_air, "空中按 Shift+J → 空中冲刺斩（独立招式）")
	# 11-03 用户：空中冲刺斩"上下范围加大两倍 + 前后摇大幅度缩短"
	var melee: Area2D = p.get_node("MeleeHitbox")
	var air_h: float = (melee.get_node("CollisionShape2D").shape as RectangleShape2D).size.y
	var af: Dictionary = p.air_dash_move.air_frames()
	check(float(af.active) == float(p.air_dash_move.active_frames),
		"空中冲刺斩判定段不变（%d 帧）" % int(af.active))
	check(int(af.startup) < p.dash_move.startup_frames and int(af.recovery) < p.dash_move.recovery_frames,
		"空中冲刺斩前摇 %d→%d、后摇 %d→%d" % [p.dash_move.startup_frames, int(af.startup),
			p.dash_move.recovery_frames, int(af.recovery)])
	check(int(af.total) <= int(p.dash_move.total_frames() * 0.7),
		"空中冲刺斩整招短了一大截（%d / %d 帧）" % [int(af.total), p.dash_move.total_frames()])
	check(air_h >= float(p.dash_move.hitbox.size.y) * 2.0,
		"空中冲刺斩上下判定至少 ×2（%.0f px，地面 %.0f px）" % [air_h, float(p.dash_move.hitbox.size.y)])
	var y0: float = p.global_position.y
	var drift := 0.0
	while is_instance_valid(p) and p.is_dash_move(p.current_move) and p._air_dash_phase(p.current_move, p.move_frame) != &"recovery":
		await hold(1, fr())
		drift = maxf(drift, absf(p.global_position.y - y0))
	check(drift < 2.0, "空中冲刺段不往下掉（偏 %.1f）" % drift)
	await hold(70, fr())
	await fresh_player()
	# 11-03 用户：“空中冲刺斩在空中能无限使用应该”——同一次腾空能连着放，不再限 1 次
	# （关闭残影消耗开关单独测腾空次数不受 air_dash_uses 限制；残影消耗与拦截在 test_shadow_pool_and_short_dash 中专测）
	p.shadow_cost_enabled = false
	check(p.air_dash_unlimited, "空中冲刺斩默认无限（airDashUnlimited）")
	await tap([&"jump"], Vector2.ZERO, 3, 10)
	await tap([&"dash_modifier", &"attack_light"], Vector2.ZERO, 1, 70)
	check(p.is_dash_move(p.current_move) or p.is_on_floor(), "空中第一次冲刺斩放完")
	var air_casts := 0
	for i in 3:
		if p.is_on_floor():
			await tap([&"jump"], Vector2.ZERO, 3, 10)
		await tap([&"dash_modifier", &"attack_light"], Vector2.ZERO, 1)
		if p.is_dash_move(p.current_move):
			air_casts += 1
		await hold(70, fr())
	check(air_casts == 3, "同一次腾空连续放 3 次空中冲刺斩（实际 %d 次）" % air_casts)
	var t := 0
	while not p.is_on_floor() and t < 180:
		await hold(1, fr())
		t += 1
	await hold(2, fr())
	check(p.is_on_floor() and p._air_dash_left == p.air_dash_uses, "落地后次数照旧回满")
	await hold(20, fr())


## 11-08 用户：“在空中很容易模型重合但是还是打不到人”。空中第一刀：敌人和她重合、在身后不到一个身位都要打中；
## 身后很远的不算（背对着的不能打）。
func air_hit_at(dx: float, dy := 0.0) -> bool:
	await fresh_player()
	p.reset_state(Vector2(600.0, stage.floor_y - p.foot_offset - 420.0))
	p._set_facing(1)
	await hold(8, fr())
	var s := make_shade(Shade.Kind.GRUNT, 600.0)
	s.hp = 9999.0
	s.state = Shade.State.LAUNCHED
	s.hitstop_frames = 999
	s.position = p.global_position + Vector2(dx, dy)
	var hp0: float = s.hp
	await hold(1, fr([&"attack_light"], [&"attack_light"]))
	for i in 24:
		await hold(1, fr())
		s.position = p.global_position + Vector2(dx, dy)
	var hit: bool = s.hp < hp0
	s.queue_free()
	return hit


## 11-08 用户：“现在一直a为什么是直接第三段攻击”——第三段后面再按 J 要回到第一段
func test_mash_cycles_combo() -> void:
	await fresh_player()
	p.reset_state(Vector2(600.0, stage.floor_y - p.foot_offset))
	p._set_facing(1)
	await hold(10, fr())
	var seq: Array[String] = []
	var cb := func(mv: Resource, _i: int) -> void: seq.append(String(mv.id))
	p.move_started.connect(cb)
	for i in 300:
		if i % 8 == 0:
			await hold(1, fr([&"attack_light"], [&"attack_light"]))
		else:
			await hold(1, fr())
	p.move_started.disconnect(cb)
	var repeat_l4 := false
	for i in range(1, seq.size()):
		if seq[i] == "light_4" and seq[i - 1] == "light_4":
			repeat_l4 = true
	check(seq.size() >= 6 and seq.slice(0, 5) == ["light_1", "light_2", "light_3", "light_4", "light_1"] and not repeat_l4,
			"一直按 J：1→2→3→强化4→1 四段循环，不会卡在最后一段（实际 %s）" % [seq])


func test_air_overlap_hit() -> void:
	var miss := []
	for dx in [0.0, -12.0, -40.0, 25.0]:
		if not await air_hit_at(dx):
			miss.append(dx)
	check(miss.is_empty(), "空中出刀：敌人和她重合 / 在身后不到一个身位也打得中（打空：%s）" % [miss])
	check(not await air_hit_at(-150.0), "身后很远的敌人打不中（不会背后挥刀）")
	# 11-08 刀光放大、判定包住她自己：贴在头顶 / 脚下 / 身后半个身位的也算
	var miss2 := []
	for off in [Vector2(0, -160), Vector2(-50, -120), Vector2(-50, 120), Vector2(0, 200)]:
		if not await air_hit_at(off.x, off.y):
			miss2.append(off)
	check(miss2.is_empty(), "空中出刀：判定包住她整个身体（打空：%s）" % [miss2])


## A1 & 1A：默认无限闪（零残影消耗）+ 可选残影池底层接口回归 + 7 帧无敌穿身瞬步（穿怪自动回身）+ 免费派生 J/K
func test_shadow_pool_and_short_dash() -> void:
	await fresh_player()
	check(p.unlimited_dash and not p.shadow_cost_enabled, "实战默认开启无限闪（unlimited_dash=true，零残影消耗）")
	# 临时切到残影消耗模式回归底层残影池充能/拦截接口
	p.unlimited_dash = false
	p.shadow_cost_enabled = true
	var events := [0]
	var on_shadow := func(_cur: int, _mx: int) -> void: events[0] += 1
	p.shadow_changed.connect(on_shadow)
	check(p.max_shadow_charges == 2 and p.shadow_charges == 2,
		"初始拥有 2 格残影池（%d / %d）" % [p.shadow_charges, p.max_shadow_charges])
	# 第 1 次 Shift+J 冲刺斩：耗 1 格残影（瞬步同帧派生 J 不重复扣第 2 格！）
	await tap([&"dash_modifier", &"attack_light"], Vector2.ZERO, 1)
	check(p.is_dash_move(p.current_move) and p.shadow_charges == 1,
		"Shift+J 冲刺斩只耗 1 格残影，不重复扣费（2 → %d）" % p.shadow_charges)
	await hold(55, fr())
	# 第 2 次瞬步 + 途中按 K 派生破军冲刺重斩：1 → 0（同样不重复扣费）
	await tap([&"dash_modifier"], Vector2(1, 0), 1)
	check(p.is_short_dashing() and p.shadow_charges == 0,
		"第 2 次瞬步消耗最后 1 格残影（1 → %d）" % p.shadow_charges)
	await tap([&"attack_heavy"], Vector2.ZERO, 1)
	check(p.current_move == p.charge_move and p.shadow_charges == 0,
		"瞬步途中按 K 免费派生冲刺重斩（%s，残影=%d）" % [str(p.current_move), p.shadow_charges])
	await hold(65, fr())
	# 0 格时拦截冲刺斩与瞬步
	await tap([&"dash_modifier", &"attack_light"], Vector2.ZERO, 2)
	check((p.current_move == null or not p.is_dash_move(p.current_move)) and p.shadow_charges == 0,
		"残影为 0 时 Shift+J 冲刺斩被拦截")
	await tap([&"short_dash"], Vector2(1, 0), 2)
	check(not p.is_short_dashing() and p.shadow_charges == 0, "残影为 0 时瞬步被拦截")
	# 自然慢速充能计时器
	var old_regen: float = p.shadow_regen_seconds
	p.shadow_regen_seconds = 0.25
	await hold(20, fr())
	p.shadow_regen_seconds = old_regen
	check(p.shadow_charges >= 1, "自然慢速充能计时器回充残影（0 → %d）" % p.shadow_charges)

	# 7 帧干脆无敌穿身瞬步 + 穿怪未按方向键自动回身面向敌背 + 自由取消手感
	await fresh_player(600.0)
	p.unlimited_dash = false
	p.shadow_cost_enabled = true
	var blocker := make_shade(Shade.Kind.ARMORED, 675.0)
	blocker.react_cool = 999
	await hold(2, fr())
	var x0: float = p.global_position.x
	await hold(1, fr([&"short_dash"], [&"short_dash"]))
	check(p.is_short_dashing() and p.shadow_charges == 1 and p.invuln_frames >= p.step_dash_frames,
		"按下瞬步耗 1 格残影并立即进入 7 帧无敌穿身瞬步")
	await hold(p.step_dash_frames, fr())
	check(not p.is_short_dashing() and absf(p.velocity.x) < 1.0,
		"瞬步到点干脆急停（vx=%.1f）" % p.velocity.x)
	check(p.global_position.x > blocker.global_position.x + 30.0 and p.global_position.x - x0 > 150.0,
		"瞬步无视身体阻挡穿到敌人背后（玩家 x=%.0f / 敌人 x=%.0f）" % [p.global_position.x, blocker.global_position.x])
	check(p.facing == -1,
		"1A 瞬步穿过敌人且未按方向键时自动回身面向敌背（朝向 %d）" % p.facing)
	# 瞬步中途按方向 + J 自由取消并转向出刀
	await hold(1, fr([&"short_dash", &"move_left"], [&"short_dash"], Vector2(-1, 0)))
	check(p.is_short_dashing() and p.shadow_charges == 0, "第 2 次瞬步耗尽残影")
	await hold(1, fr())
	await hold(1, fr([&"attack_light", &"move_right"], [&"attack_light"], Vector2(1, 0)))
	check(not p.is_short_dashing() and p.is_dash_move(p.current_move) and p.facing == 1,
		"瞬步中途按 J 免费派生突进冲刺斩并转向（%s，朝向 %d）" % [str(p.current_move), p.facing])
	await hold(55, fr())

	# 精准弹刀成功 → 立刻回满 max_shadow_charges
	await fresh_player()
	p.unlimited_dash = false
	p.shadow_cost_enabled = true
	var attacker := make_shade(Shade.Kind.GRUNT, 700.0, true)
	await hold(3, fr())
	p.consume_shadow(2)
	check(p.shadow_charges == 0, "弹刀前先耗空残影（0）")
	attacker.cooldown = 0
	attacker._begin_windup()
	var windup: int = int(attacker.spec.windup)
	var parried_ok := false
	for i in windup + 20:
		var remain: int = windup - attacker.state_frames
		if not parried_ok and attacker.state == Shade.State.WINDUP and remain <= Shade.PARRY_CUE:
			parried_ok = true
			await hold(1, fr([&"parry"], [&"parry"]))
		else:
			await hold(1, fr([&"parry"]) if parried_ok else fr())
		if p.shadow_charges == p.max_shadow_charges:
			break
	check(p.shadow_charges == p.max_shadow_charges,
		"精准弹刀成功立刻回满残影池（0 → %d）" % p.shadow_charges)

	# 敌人破壳 +1 格，敌人死亡 +1 格
	await fresh_player()
	p.unlimited_dash = false
	p.shadow_cost_enabled = true
	var arm := make_shade(Shade.Kind.ARMORED, 740.0)
	var fodder := make_shade(Shade.Kind.GRUNT, 900.0)
	await hold(2, fr())
	p.consume_shadow(2)
	check(p.shadow_charges == 0, "回格测试前清空残影（0）")
	arm._break_shell()
	stage.reset_time_scale()
	check(p.shadow_charges == 1, "敌人破壳返还 1 格残影（0 → %d）" % p.shadow_charges)
	fodder._die(1)
	check(p.shadow_charges == 2, "击杀敌人返还 1 格残影（1 → %d）" % p.shadow_charges)
	check(events[0] >= 6, "shadow_changed 信号正常派发（共 %d 次）" % events[0])
	p.shadow_changed.disconnect(on_shadow)
	p.unlimited_dash = true
	p.shadow_cost_enabled = false


## A2 & 1A：精英甲影「白金凝壳」—— 正面免疫轻击挑飞只削少量壳；四条快速碎壳正解（弹刀 / 绕背 / 同伴撞击 / 满蓄重击）
func test_armored_platinum_shell() -> void:
	# 正面轻击 / 挑飞：免疫挑飞，只削 12.0 白壳
	await fresh_player(600.0)
	var b := make_shade(Shade.Kind.ARMORED, 690.0)
	b.hp = 600.0
	b.facing = -1
	b.react_cool = 999
	var eb := record(b)
	await hold(3, fr())
	check(is_equal_approx(b.max_shell, Shade.SHELL_MAX) and is_equal_approx(b.shell_hp, 60.0),
		"精英甲影（Kind.ARMORED）初始 60 白金凝壳（%.0f / %.0f）" % [b.shell_hp, b.max_shell])
	await tap([&"attack_light"], Vector2.ZERO, 3, 14)
	check(is_equal_approx(b.shell_hp, 48.0) and b.state != Shade.State.LAUNCHED and b.state != Shade.State.HITSTUN,
		"正面平砍甲影只削 12 白壳且不造成硬直/挑飞（60 → %.0f）" % b.shell_hp)

	# 正解 ①：迎面被弹刀直接震碎全部白壳并炸飞 + 0.15s 慢放
	await fresh_player(600.0)
	var b1 := make_shade(Shade.Kind.ARMORED, 700.0, true)
	var eb1 := record(b1)
	await hold(3, fr())
	b1.on_parried(p)
	var slowmo_triggered := Engine.time_scale < 0.99
	check(is_equal_approx(b1.shell_hp, 0.0) and eb1.shell_broken == 1 and b1.state == Shade.State.LAUNCHED,
		"正解 ①：迎面弹刀直接一击震碎全部白壳并炸飞（shell=%.0f, state=%d）" % [b1.shell_hp, b1.state])
	check(slowmo_triggered, "白壳崩碎瞬间触发 0.15s 慢放反馈（time_scale=%.2f）" % Engine.time_scale)
	var wait_ms := Time.get_ticks_msec()
	while Engine.time_scale < 0.99 and Time.get_ticks_msec() - wait_ms < 500:
		await process_frame
	check(is_equal_approx(Engine.time_scale, 1.0), "0.15s 慢放结束后自动恢复常速（time_scale=%.2f）" % Engine.time_scale)

	# 正解 ②：绕背攻击造成 2.5 倍碎壳（轻击两刀破壳；快速重斩一刀秒破）
	await fresh_player(780.0)
	p._set_facing(-1)
	var b2 := make_shade(Shade.Kind.ARMORED, 690.0)
	b2.hp = 600.0
	b2.facing = -1   # 甲影面向左，玩家在右侧（x=780）从背后劈向它
	b2.react_cool = 999
	var eb2 := record(b2)
	await hold(3, fr())
	p.shadow_charges = 1
	var sh_before: int = p.shadow_charges
	await tap([&"attack_light"], Vector2.ZERO, 3, 15)
	check(is_equal_approx(b2.shell_hp, 30.0),
		"正解 ②：绕背第 1 刀造成 2.5 倍碎壳（60 → %.0f）" % b2.shell_hp)
	b2.facing = -1
	b2.react_cool = 999
	await tap([&"attack_light"], Vector2.ZERO, 3, 15)
	stage.reset_time_scale()
	check(is_equal_approx(b2.shell_hp, 0.0) and eb2.shell_broken == 1 and p.shadow_charges == sh_before + 1,
		"正解 ②：绕背第 2 刀直接击碎白壳并返还 1 格残影（shell=%.0f, 残影 %d→%d）" % [
			b2.shell_hp, sh_before, p.shadow_charges])
	# 破壳后彻底失去霸体，正面 W+J 随便挑飞
	b2.position = Vector2(690.0, b2.ground_y())
	b2.state = Shade.State.IDLE
	b2.facing = 1
	p.reset_state(Vector2(600.0, stage.floor_y - p.foot_offset))
	p._set_facing(1)
	await hold(4, fr())
	b2._begin_windup()
	await tap([&"aim_up", &"jump", &"attack_light"], Vector2(0, -1), 4, 0)
	await hold(16, fr())
	check(b2.state == Shade.State.LAUNCHED, "破壳后甲影彻底失去霸体，可被任意挑飞追斩")

	# 正解 ③：被击飞的其他影怪撞中（take_chain）直接一击砸碎全部白壳
	await fresh_player(450.0)
	var missile := make_shade(Shade.Kind.GRUNT, 650.0)
	var b3 := make_shade(Shade.Kind.ARMORED, 760.0)
	var eb3 := record(b3)
	await hold(2, fr())
	missile.state = Shade.State.LAUNCHED
	missile.chain_armed = true
	missile.velocity = Vector2(1100.0, -180.0)
	missile.position.y = stage.floor_y - 66.0
	await hold(18, fr())
	stage.reset_time_scale()
	check(is_equal_approx(b3.shell_hp, 0.0) and eb3.shell_broken == 1 and b3.state == Shade.State.LAUNCHED,
		"正解 ③：被击飞同伴撞中一击砸碎全部 60 白壳并连锁炸飞")

	# 正解 ④（1A 新增）：25 帧满蓄重击（或瞬发满蓄重击）正面一刀直接震碎全部 60 白壳并重炮击飞
	await fresh_player(560.0)
	var b4 := make_shade(Shade.Kind.ARMORED, 720.0)
	b4.hp = 600.0
	b4.facing = -1
	b4.react_cool = 999
	var eb4 := record(b4)
	await hold(2, fr())
	p._grant_flash_heavy(1.25)
	await tap([&"attack_heavy"], Vector2.ZERO, 1)
	for i in 55:
		await hold(1, fr())
		stage.reset_time_scale()
		if eb4.shell_broken >= 1:
			break
	check(is_equal_approx(b4.shell_hp, 0.0) and eb4.shell_broken == 1 and b4.state == Shade.State.LAUNCHED and b4.chain_armed,
		"正解 ④：1A 满蓄重击正面一刀震碎甲影全部 60 白壳并化作重炮弹体击飞")


## 1A 半空智能索敌「追影冲刺」（Shadow Pursuit）：半空浮空怪单按 Shift 6 帧斜向瞬移贴身滞空；按反方向键冲刺绝不强吸
func test_shadow_pursuit_1a() -> void:
	await fresh_player(520.0)
	var airborne := make_shade(Shade.Kind.GRUNT, 820.0)
	airborne.hp = 500.0
	airborne.react_cool = 999
	await hold(2, fr())
	airborne.position = Vector2(820.0, stage.floor_y - 210.0)
	airborne.state = Shade.State.LAUNCHED
	airborne.velocity = Vector2(40.0, -30.0)
	var pursuit_signals := [0]
	var on_pursuit := func(_t: Node, _from: Vector2) -> void: pursuit_signals[0] += 1
	p.shadow_pursuit_started.connect(on_pursuit)
	await hold(1, fr([&"dash_modifier"], [&"dash_modifier"]))
	check(p.is_shadow_pursuing() and pursuit_signals[0] == 1 and p.shadow_charges == p.max_shadow_charges,
		"1A 前方半空存在浮空怪时单按 Shift 触发 6 帧追影冲刺（无限闪零消耗）")
	await hold(p.pursuit_frames, fr())
	check(not p.is_on_floor() and p.global_position.distance_to(airborne.global_position) < 115.0,
		"追影冲刺 6 帧斜向瞬移贴至浮空怪身前（距离=%.1f px）" % p.global_position.distance_to(airborne.global_position))
	check(p.velocity.y < -80.0,
		"追影冲刺到位后赋予短暂滞空托举（vy=%.1f）" % p.velocity.y)
	var hp_before: float = airborne.hp
	await tap([&"attack_light"], Vector2.ZERO, 2, 12)
	check(airborne.hp < hp_before,
		"追影冲刺贴脸后点 J 直接稳定命中空中连段（%.0f → %.0f）" % [hp_before, airborne.hp])
	p.shadow_pursuit_started.disconnect(on_pursuit)
	await hold(80, fr())

	# 反方向撤离保护：前方有浮空怪，但玩家按住反方向 A + Shift → 向左后撤闪避，绝不强吸到怪身上
	await fresh_player(600.0)
	var front_air := make_shade(Shade.Kind.GRUNT, 860.0)
	front_air.hp = 500.0
	front_air.react_cool = 999
	await hold(2, fr())
	front_air.position = Vector2(860.0, stage.floor_y - 200.0)
	front_air.state = Shade.State.LAUNCHED
	front_air.velocity = Vector2(0.0, -60.0)
	var x_start: float = p.global_position.x
	await hold(1, fr([&"dash_modifier", &"move_left"], [&"dash_modifier"], Vector2(-1, 0)))
	check(p.is_short_dashing() and not p.is_shadow_pursuing(),
		"1A 按住反方向键冲刺时尊重后撤意图，绝不强吸浮空怪")
	await hold(p.step_dash_frames, fr())
	check(p.global_position.x < x_start - 100.0,
		"反方向冲刺干净向后撤离（%.0f → %.0f）" % [x_start, p.global_position.x])


## 1A 极限闪避「掠影闪」+ 弹刀/闪避激活 1.25s 瞬发满蓄重击窗口
func test_perfect_dodge_and_flash_heavy() -> void:
	await fresh_player(600.0)
	var slasher := make_shade(Shade.Kind.GRUNT, 705.0, true)
	await hold(3, fr())
	p.shadow_charges = 1
	check(p.shadow_charges == 1 and p.flash_heavy_timer <= 0.0, "极限闪避前残影设为 1 格且无瞬发窗口")
	var dodge_cnt := [0]
	var on_pd := func(_a: Node, _pos: Vector2) -> void: dodge_cnt[0] += 1
	p.perfect_dodge_triggered.connect(on_pd)
	slasher.cooldown = 0
	slasher._begin_windup()
	slasher.state_frames = maxi(int(slasher.spec.windup) - 6, 1)
	var hp0: float = p.hp
	await hold(1, fr([&"short_dash", &"move_right"], [&"short_dash"], Vector2(1, 0)))
	await hold(p.step_dash_frames, fr())
	p.perfect_dodge_triggered.disconnect(on_pd)
	check(dodge_cnt[0] == 1 and is_equal_approx(p.hp, hp0),
		"迎着敌人出刀帧瞬步穿过触发极限闪避「掠影闪」且全程无伤")
	check(p.shadow_charges == 2 and p.flash_heavy_timer > 0.8,
		"极限闪避当场回充残影（1 → %d）并激活 1.25s 瞬发满蓄重击窗口（%.2fs）" % [p.shadow_charges, p.flash_heavy_timer])
	# 点按 1 帧 K，无需蓄力等待直接瞬发满蓄重击（_charge_t == 1.0）
	await hold(1, fr([&"attack_heavy"], [&"attack_heavy"]))
	check(p.state == PlayerScript.State.ATTACK and p.current_move == p.charge_move and is_equal_approx(p._charge_t, 1.0) and p.flash_heavy_timer <= 0.0,
		"瞬发满蓄窗口内单点 K 0 帧等待直接劈出满蓄重击（charge_t=%.2f）" % p._charge_t)
	await hold(75, fr())

	# 精准弹刀同样激活瞬发满蓄重击窗口
	await fresh_player(600.0)
	var attacker := make_shade(Shade.Kind.GRUNT, 700.0, true)
	await hold(2, fr())
	attacker.on_parried(p)
	p._do_parry(attacker, p.global_position)
	check(p.flash_heavy_timer > 0.8, "精准弹刀成功同样开启 1.25s 瞬发满蓄重击窗口（%.2fs）" % p.flash_heavy_timer)


## A4：过杀躯体落地前不消失 —— 浮空/击飞致死标记 overkilled 继续飞、撞碎远处甲影白壳、落地才死且 died 只发 1 次
func test_overkill_body_persistence() -> void:
	await fresh_player(460.0)
	# x=620 放一只残血影卒，x=820 放一只满白壳精英甲影
	var corpse := make_shade(Shade.Kind.GRUNT, 620.0)
	corpse.hp = 6.0
	corpse.react_cool = 999
	var armored := make_shade(Shade.Kind.ARMORED, 820.0)
	armored.react_cool = 999
	var ec := record(corpse)
	var ea := record(armored)
	await hold(2, fr())
	# 把残血影卒打至 hp <= 0 并化作高速浮空过杀炮弹轰向甲影
	corpse.position = Vector2(620.0, stage.floor_y - 68.0)
	corpse.state = Shade.State.LAUNCHED
	corpse.velocity = Vector2(200.0, -80.0)
	corpse.take_hit(p.air_combo[2], 1, corpse.global_position, 0.0, false, 1.0, p)
	corpse.hitstop_frames = 0
	corpse.velocity = Vector2(1050.0, -140.0)
	corpse.chain_armed = true
	check(corpse.hp <= 0.0 and corpse.overkilled and corpse.state == Shade.State.LAUNCHED and ec.died == 0,
		"击飞致死时不立刻 _die()：标记 overkilled 继续保持 LAUNCHED 飞行（died=%d）" % ec.died)
	var hurtbox: Area2D = corpse.get_node("Hurtbox")
	check(hurtbox.monitorable, "过杀躯体飞行途中保留碰撞与受击盒可继续追影追斩")

	# 过杀躯体向右轰穿 x=820 满白壳甲影 → 一击砸碎全部 60 白壳并连锁炸飞！
	for i in 45:
		await hold(1, fr())
		stage.reset_time_scale()
		if ea.shell_broken >= 1 and corpse.state == Shade.State.DEAD:
			break
	var safety := 0
	while corpse.state != Shade.State.DEAD and safety < 120:
		await hold(1, fr())
		stage.reset_time_scale()
		safety += 1
	await hold(25, fr())
	check(ea.chain_hit >= 1 and ea.shell_broken == 1 and is_equal_approx(armored.shell_hp, 0.0),
		"高速飞行的过杀躯体撞中甲影，一击砸碎全部 60 白金凝壳（shell=%.0f）" % armored.shell_hp)
	check(corpse.state == Shade.State.DEAD and corpse._feathers.size() > 0,
		"过杀躯体落地后才正式执行 _die() 散成黑羽（黑羽 %d 片）" % corpse._feathers.size())
	check(ec.died == 1, "过杀躯体全生命周期 died 信号严格只发 1 次（实际 %d 次）" % ec.died)


## 新手感 ①：无限闪（连续瞬步零消耗不拦截）+ 地面四段普攻（A1→A2→A3→强化A4 更强震屏反馈并挑飞入空连）
func test_unlimited_dash_and_enhanced_a4() -> void:
	await fresh_player(520.0)
	check(p.unlimited_dash and p.light_combo.size() == 4 and p.light_combo[3].id == &"light_4",
		"实战开启无限闪且地面普攻扩展为 4 段（第 4 段 id=%s）" % String(p.light_combo[3].id))
	var m3: Resource = p.light_combo[2]
	var m4: Resource = p.light_combo[3]
	check(not m3.forces_launch and m4.forces_launch and float(m4.shake_amount) >= 28.0
			and int(m4.hitstop_frames) > int(m3.hitstop_frames) and float(m4.damage) > float(m3.damage),
		"第 3 段紧凑不提前挑飞，第 4 段强化 A 具备更强震屏（%.1f vs %.1f）、更强顿帧（%d vs %d）与挑飞能力" % [
			float(m4.shake_amount), float(m3.shake_amount), int(m4.hitstop_frames), int(m3.hitstop_frames)])
	# 地面连续瞬步 5 次全程零消耗不拦截
	var dashes := 0
	for i in 5:
		var dir := 1 if (i % 2 == 0) else -1
		await hold(1, fr([&"short_dash", &"move_right" if dir > 0 else &"move_left"], [&"short_dash"], Vector2(dir, 0)))
		if p.is_short_dashing():
			dashes += 1
		await hold(p.step_dash_frames + 1, fr())
	check(dashes == 5 and p.shadow_charges == p.max_shadow_charges,
		"无限闪：地面连续瞬步 5 次全部成功且残影满格不减（%d 次，残影=%d）" % [dashes, p.shadow_charges])

	# 实战四连 A1 → A2 → A3 → 强化 A4：前 3 刀平推喂招，第 4 刀强化 A 重震屏冲击帧挑飞并返还 1 段空中跳
	await fresh_player(600.0)
	var s := make_shade(Shade.Kind.GRUNT, 685.0)
	s.hp = 600.0
	s.react_cool = 999
	var ev := record(s)
	await hold(3, fr())
	var hit_ids: Array[String] = []
	var max_impact := [0.0]
	var min_vy := [0.0]
	var on_hit := func(_t: Node, mv: Resource, _pt: Vector2) -> void:
		hit_ids.append(String(mv.id))
	p.hit_confirmed.connect(on_hit)
	for i in 90:
		if i % 8 == 0 and hit_ids.size() < 4:
			await hold(1, fr([&"attack_light"], [&"attack_light"]))
		else:
			await hold(1, fr())
		max_impact[0] = maxf(max_impact[0], stage.fx.impact_alpha())
		if is_instance_valid(s) and s.state == Shade.State.LAUNCHED:
			min_vy[0] = minf(min_vy[0], s.velocity.y)
		if hit_ids.has("light_4"):
			break
	p.hit_confirmed.disconnect(on_hit)
	await hold(4, fr())
	check(hit_ids == ["light_1", "light_2", "light_3", "light_4"],
		"地面四连 A1→A2→A3→强化A4 四刀稳定衔接全中（实际 %s）" % [hit_ids])
	check(ev.launched_high >= 1 and s.state == Shade.State.LAUNCHED and min_vy[0] <= -900.0,
		"强化 A4 将敌人干脆挑飞开启浮空连段（vy=%d）" % int(min_vy[0]))
	check(max_impact[0] > 0.3 and p.bonus_air_jumps >= 1,
		"强化 A4 命中触发重击级冲击帧压暗（alpha=%.2f）并返还空中跳（+%d）" % [max_impact[0], p.bonus_air_jumps])


## 新手感 ②：核心主轴为「连段浮空」，而「高速撞墙 / 强制落地」作为防站桩无脑连与长连段饱和的平衡收口
func test_combo_juggle_and_balance_exit() -> void:
	# 1. 死站地面不起跳、无脑狂按 J：打完一套四连后若继续站桩平砍，触发平衡高速弹射撞墙/脱离，绝不能原地无限连死
	await fresh_player(600.0)
	var mash_target := make_shade(Shade.Kind.GRUNT, 680.0)
	mash_target.hp = 900.0
	mash_target.react_cool = 999
	mash_target.arena_right = 1120.0
	var em := record(mash_target)
	await hold(3, fr())
	var mash_ejected := false
	for i in 150:
		if i % 8 == 0:
			await hold(1, fr([&"attack_light"], [&"attack_light"]))
		else:
			await hold(1, fr())
		if is_instance_valid(mash_target) and (mash_target._balance_ejected or em.wall_slam >= 1):
			mash_ejected = true
			break
	await hold(50, fr())
	check(mash_ejected and (em.wall_slam >= 1 or mash_target.global_position.x - p.global_position.x > 260.0),
		"站桩无脑狂按 J 不起跳追击时，自动触发平衡高速横飞撞墙/脱离刀圈（wall_slam=%d, 间距=%.0f px）" % [
			em.wall_slam, mash_target.global_position.x - p.global_position.x])

	# 2. 核心主轴「挑飞 + 无限闪追影浮空连」：前中段稳稳空连，叠满平衡阈值后终结刀自动高速横飞轰墙并落地清零连击
	await fresh_player(460.0)
	var old_mask: int = p.collision_mask
	p.collision_mask = 1
	var jug := make_shade(Shade.Kind.GRUNT, 545.0)
	jug.terrain = null
	jug.hp = 1200.0
	jug.react_cool = 999
	jug.arena_right = 1620.0
	var ej := record(jug)
	await hold(3, fr())
	# 先用地面四连挑飞（4 hit，juggle_count = 1）
	for i in 90:
		if i % 8 == 0 and jug.state != Shade.State.LAUNCHED:
			await hold(1, fr([&"attack_light"], [&"attack_light"]))
		else:
			await hold(1, fr())
		if jug.state == Shade.State.LAUNCHED:
			break
	check(jug.state == Shade.State.LAUNCHED, "四连强化 A4 起手挑飞成功")
	var max_juggle := 0
	var max_vx := 0.0
	# 利用无限闪「追影冲刺 + 空中四连强普」连续两轮爽快空连，叠满平衡阈值后空中强普自动触发高速轰墙
	for cycle in 2:
		var hs_guard := 0
		while p.hitstop_frames > 0 and hs_guard < 30:
			await hold(1, fr())
			hs_guard += 1
		await hold(2, fr())
		await hold(1, fr([&"dash_modifier"], [&"dash_modifier"]))
		var dash_guard := 0
		while p.is_short_dashing() and dash_guard < 16:
			await hold(1, fr())
			dash_guard += 1
		var air4_hit := [false]
		var on_air_hit := func(_t: Node, mv: Resource, _pt: Vector2) -> void:
			if String(mv.id) == "air_light_4":
				air4_hit[0] = true
		p.hit_confirmed.connect(on_air_hit)
		for step in 105:
			var want_press: bool = (not air4_hit[0]) and p.hitstop_frames <= 0 \
					and (p.current_move == null or p.can_chain_cancel())
			if want_press:
				await hold(1, fr([&"attack_light"], [&"attack_light"]))
			else:
				await hold(1, fr())
			if is_instance_valid(jug):
				max_juggle = maxi(max_juggle, jug.juggle_count)
				max_vx = maxf(max_vx, jug.velocity.x)
			if air4_hit[0] and p.hitstop_frames <= 0:
				break
		p.hit_confirmed.disconnect(on_air_hit)
	for i in 120:
		await hold(1, fr())
		if is_instance_valid(jug):
			max_vx = maxf(max_vx, jug.velocity.x)
			if ej.wall_slam >= 1 and jug.on_ground() and jug.combo_taken == 0:
				break
	p.collision_mask = old_mask
	check(max_juggle >= 6,
		"主轴空连体验保留：挑飞后配合无限闪追影可流畅打出多段浮空连斩（最高托举 %d 次）" % max_juggle)
	check(max_vx >= 1250.0 and ej.wall_slam >= 1,
		"空连叠满平衡阈值后终结刀自动触发高速横飞撞墙（vx=%d, wall_slam=%d）" % [int(max_vx), ej.wall_slam])
	check(jug.on_ground() and jug.combo_taken == 0,
		"高速撞墙受身落地后清零连段计数重新立回（on_ground=%s, combo_taken=%d）" % [str(jug.on_ground()), jug.combo_taken])


## 新手感 ③：普攻连段被打断也继续（瞬步闪避 / 弹刀格挡 / 挨打受击倒地起身均续连下一刀）+ 四阶递进顿帧震屏与打击感演出
func test_interrupt_continues_combo_and_juicy_hitfeel() -> void:
	await fresh_player(560.0)
	var m1: Resource = p.light_combo[0]
	var m2: Resource = p.light_combo[1]
	var m3: Resource = p.light_combo[2]
	var m4: Resource = p.light_combo[3]
	check(int(m1.hitstop_frames) < int(m2.hitstop_frames)
			and int(m2.hitstop_frames) < int(m3.hitstop_frames)
			and int(m3.hitstop_frames) < int(m4.hitstop_frames)
			and int(m1.victim_hitstop_frames) < int(m2.victim_hitstop_frames)
			and int(m2.victim_hitstop_frames) < int(m3.victim_hitstop_frames)
			and int(m3.victim_hitstop_frames) < int(m4.victim_hitstop_frames),
		"四段普攻具备严格阶梯递进顿帧（攻方 %d<%d<%d<%d，受方 %d<%d<%d<%d）" % [
			int(m1.hitstop_frames), int(m2.hitstop_frames), int(m3.hitstop_frames), int(m4.hitstop_frames),
			int(m1.victim_hitstop_frames), int(m2.victim_hitstop_frames), int(m3.victim_hitstop_frames), int(m4.victim_hitstop_frames)])
	check(float(m1.shake_amount) < float(m2.shake_amount)
			and float(m2.shake_amount) < float(m3.shake_amount)
			and float(m3.shake_amount) < float(m4.shake_amount),
		"四段普攻具备严格阶梯递进震屏（%.1f < %.1f < %.1f < %.1f）" % [
			float(m1.shake_amount), float(m2.shake_amount), float(m3.shake_amount), float(m4.shake_amount)])

	# 全链路打断续连：A1 瞬步打断 → A2 格挡打断 → A3 挨打倒地打断 → 起身按 J 照样劈出强化 A4 → 再按 J 回 A1
	await fresh_player(600.0)
	# 1) 出 A1 第 2 帧按 Shift 瞬步打断（挥空未打中人），瞬步停稳后按 J → 直接出 A2
	await hold(1, fr([&"attack_light"], [&"attack_light"]))
	check(p.current_move == m1, "起手出第 1 段 light_1")
	await hold(1, fr())
	await hold(1, fr([&"short_dash", &"move_right"], [&"short_dash"], Vector2(1, 0)))
	check(p.is_short_dashing(), "light_1 前摇中被瞬步闪避打断")
	await hold(p.step_dash_frames + 1, fr())
	await hold(1, fr([&"attack_light"], [&"attack_light"]))
	check(p.current_move == m2,
		"瞬步闪避打断后按 J 不归零、不误出冲刺斩，直接续接第 2 段 light_2（实际 %s）" % (String(p.current_move.id) if p.current_move != null else "none"))

	# 2) light_2 后摇中按 L 格挡打断，松手后再按 J → 直接出 A3
	var g_wait := 0
	while p.current_move == m2 and not p.link_open and g_wait < 30:
		await hold(1, fr())
		g_wait += 1
	await hold(1, fr([&"parry"], [&"parry"]))
	await hold(4, fr())
	await hold(1, fr([&"attack_light"], [&"attack_light"]))
	check(p.current_move == m3,
		"格挡/弹刀穿插打断后再按 J 直接续接第 3 段 light_3（实际 %s）" % (String(p.current_move.id) if p.current_move != null else "none"))

	# 3) light_3 前摇中途被强敌重击砍飞并倒地，起身恢复后再按 J → 依然接着劈出第 4 段强化普攻 light_4！
	await hold(1, fr())
	var hitter := make_shade(Shade.Kind.BRUTE, 820.0)
	hitter.react_cool = 999
	p.invuln_frames = 0
	p.take_hit(hitter.strike_move, -1, p.global_position, 0.0, false, 1.0, hitter)
	check(p.state == PlayerScript.State.LAUNCHED, "light_3 出刀中途被敌人重击打飞打断")
	var rec_guard := 0
	while (p.state != PlayerScript.State.NEUTRAL or p.hitstop_frames > 0) and rec_guard < 160:
		await hold(1, fr())
		rec_guard += 1
	await hold(1, fr([&"attack_light"], [&"attack_light"]))
	check(p.current_move == m4,
		"挨打受击倒地起身后再按 J，依然接着断掉的地方劈出第 4 段强化普攻 light_4（实际 %s）" % (String(p.current_move.id) if p.current_move != null else "none"))
	var fin_guard := 0
	while p.current_move != null and fin_guard < 60:
		await hold(1, fr())
		fin_guard += 1
	await hold(1, fr([&"attack_light"], [&"attack_light"]))
	check(p.current_move == m1, "第 4 段强化 A4 打完后再按 J 正常循环回第 1 段 light_1")

	# 4) 超出续连保持窗口后自动重置回 light_1
	var end_guard := 0
	while p.current_move != null and end_guard < 50:
		await hold(1, fr())
		end_guard += 1
	for i in p.rework_combo_keep_frames + 8:
		await hold(1, fr())
	await hold(1, fr([&"attack_light"], [&"attack_light"]))
	check(p.current_move == m1, "超过连段保持窗口未出手后按 J 干净重置回 light_1")
	await hold(35, fr())

	# 5) 打击感实机验证：受击顿帧高频震颤 + 贯体刀口裂芒 + 前景破空激波环 + 镜头推镜脉冲与平滑回弹
	await fresh_player(600.0)
	var bag := make_shade(Shade.Kind.GRUNT, 680.0)
	bag.hp = 600.0
	bag.react_cool = 999
	await hold(3, fr())
	var saw_jitter := false
	var saw_wound := false
	var saw_shock := false
	var base_zoom: float = float(stage.zoom_level)
	var peak_zoom: float = base_zoom
	for i in 85:
		if i % 8 == 0:
			await hold(1, fr([&"attack_light"], [&"attack_light"]))
		else:
			await hold(1, fr())
		await process_frame
		if is_instance_valid(bag) and bag.hitstop_frames > 0 and bag._hit_jitter_frames > 0:
			saw_jitter = true
		if is_instance_valid(bag) and bag._hit_wound_frames > 0:
			saw_wound = true
		if (stage._impact_rings as Array).size() > 0:
			saw_shock = true
		peak_zoom = maxf(peak_zoom, float(stage.camera.zoom.x))
	check(saw_jitter and saw_wound,
		"命中顿帧期间敌人触发高频吃痛震颤与贯体刀口裂芒（jitter=%s, wound=%s）" % [str(saw_jitter), str(saw_wound)])
	check(saw_shock and peak_zoom > base_zoom + 0.01,
		"重刀命中触发前景破空激波环与镜头打击推镜脉冲（zoom %.3f → %.3f）" % [base_zoom, peak_zoom])
	for i in 45:
		await hold(1, fr())
		await process_frame
	check(is_equal_approx(float(stage.camera.zoom.x), base_zoom),
		"打击推镜脉冲结束后镜头缩放平滑回弹至基准值（%.3f）" % float(stage.camera.zoom.x))


## 空中四段普攻 + 空中强普（air_light_4）更强震屏顿帧 + 空中连段被打断也继续
func test_air_enhanced_a4_and_combo_continuation() -> void:
	await fresh_player(600.0)
	check(p.air_combo.size() == 4 and p.air_combo[3] != null and p.air_combo[3].id == &"air_light_4",
		"实战空中普攻升级为 4 段，第 4 段为空中强普 air_light_4（size=%d）" % p.air_combo.size())
	var am1: MoveDefinition = p.air_combo[0] as MoveDefinition
	var am2: MoveDefinition = p.air_combo[1] as MoveDefinition
	var am3: MoveDefinition = p.air_combo[2] as MoveDefinition
	var am4: MoveDefinition = p.air_combo[3] as MoveDefinition
	check(am1.hitstop_frames < am2.hitstop_frames and am2.hitstop_frames < am3.hitstop_frames \
			and am3.hitstop_frames < am4.hitstop_frames and am4.victim_hitstop_frames >= am3.victim_hitstop_frames + 7,
		"空中四连顿帧阶梯递进：空1(%d/%d) < 空2(%d/%d) < 空3(%d/%d) < 空4强普(%d/%d)" % [
			am1.hitstop_frames, am1.victim_hitstop_frames,
			am2.hitstop_frames, am2.victim_hitstop_frames,
			am3.hitstop_frames, am3.victim_hitstop_frames,
			am4.hitstop_frames, am4.victim_hitstop_frames])
	check(am1.shake_amount < am2.shake_amount and am2.shake_amount < am3.shake_amount \
			and am4.shake_amount >= am3.shake_amount * 1.5,
		"空中四连震屏阶梯递进且空中强普更猛（%.1f / %.1f / %.1f / %.1f）" % [
			am1.shake_amount, am2.shake_amount, am3.shake_amount, am4.shake_amount])

	# 1) 全程按住方向键追怪连按 J：不误触旧版 air_drive，完整打出 air_light_1 → 2 → 3 → 4 → 1 循环，且强普触发全套重打击反馈
	await fresh_player(560.0)
	p.reset_state(Vector2(560.0, stage.floor_y - p.foot_offset - 360.0))
	p._set_facing(1)
	await hold(3, fr())
	var target := make_shade(Shade.Kind.GRUNT, 635.0)
	target.hp = 1200.0
	target.state = Shade.State.LAUNCHED
	target.position = p.global_position + Vector2(65.0, -10.0)
	var air_seq: Array[String] = []
	var on_air_mv := func(mv: Resource, _idx: int) -> void:
		air_seq.append(String(mv.id))
	p.move_started.connect(on_air_mv)
	var base_zoom: float = float(stage.zoom_level)
	var peak_zoom: float = base_zoom
	var saw_a4_impact := false
	for step in 120:
		p.velocity.y = minf(p.velocity.y, 0.0)
		if is_instance_valid(target):
			target.state = Shade.State.LAUNCHED
			target.position = p.global_position + Vector2(68.0, -12.0)
		var press_j: bool = p.hitstop_frames <= 0 and (p.current_move == null or p.link_open)
		if press_j:
			await hold(1, fr([&"move_right", &"attack_light"], [&"attack_light"], Vector2(1, 0)))
		else:
			await hold(1, fr([&"move_right"], [], Vector2(1, 0)))
		await process_frame
		peak_zoom = maxf(peak_zoom, float(stage.camera.zoom.x))
		if float(stage.fx.impact_alpha()) > 0.3:
			for ring in (stage._impact_rings as Array):
				if ring is Dictionary and bool(ring.get("heavy", false)):
					saw_a4_impact = true
		if air_seq.size() >= 5 and p.hitstop_frames <= 0:
			break
	p.move_started.disconnect(on_air_mv)
	check(air_seq.size() >= 5 and air_seq.slice(0, 5) == ["air_light_1", "air_light_2", "air_light_3", "air_light_4", "air_light_1"],
		"空中按住方向键连按 J 顺畅打出 1→2→3→强普4→1 循环，不提前误跳横踢（%s）" % [air_seq])
	check(saw_a4_impact and peak_zoom >= base_zoom + 0.03,
		"空中强普 air_light_4 命中触发冲击帧压暗、重型激波环与强推镜脉冲（zoom %.3f → %.3f）" % [base_zoom, peak_zoom])
	if is_instance_valid(target):
		target.queue_free()

	# 2) 空中连段被打断也继续：空A1 → 空A2 → 追影冲刺打断 → 续接空A3 → 短暂落地再跳起（或受击恢复）→ 劈出空A4 强普
	await fresh_player(500.0)
	var flier := make_shade(Shade.Kind.GRUNT, 580.0)
	flier.hp = 1200.0
	flier.state = Shade.State.LAUNCHED
	flier.velocity = Vector2(0.0, -40.0)
	await tap([&"jump"], Vector2.ZERO, 3, 6)
	flier.position = p.global_position + Vector2(65.0, -15.0)
	await hold(1, fr([&"attack_light"], [&"attack_light"]))
	check(p.current_move != null and String(p.current_move.id) == "air_light_1", "空中续连起手：air_light_1")
	for i in 22:
		await hold(1, fr())
		flier.state = Shade.State.LAUNCHED
		flier.position = p.global_position + Vector2(65.0, -15.0)
		if p.hitstop_frames <= 0 and (p.current_move == null or p.link_open):
			break
	await hold(1, fr([&"attack_light"], [&"attack_light"]))
	check(p.current_move != null and String(p.current_move.id) == "air_light_2", "空中接第 2 刀：air_light_2")
	await hold(2, fr())
	# 将浮空怪拉开距离，按 Shift 触发半空追影冲刺打断空A2
	flier.state = Shade.State.LAUNCHED
	flier.position = p.global_position + Vector2(220.0, -30.0)
	await hold(1, fr([&"dash_modifier"], [&"dash_modifier"]))
	var dg := 0
	while p.is_short_dashing() and dg < 16:
		await hold(1, fr())
		dg += 1
	await hold(1, fr([&"attack_light"], [&"attack_light"]))
	check(p.current_move != null and String(p.current_move.id) == "air_light_3",
		"追影冲刺打断空中连段后按 J 直接续接第 3 刀 air_light_3（实际 %s）" % (
			String(p.current_move.id) if p.current_move != null else "null"))
	# 甚至让主角落地再重新跳起按 J，依然在续连窗口内劈出第 4 刀空中强普 air_light_4！
	var land_guard := 0
	while not p.is_on_floor() and land_guard < 120:
		await hold(1, fr())
		land_guard += 1
	await hold(3, fr())
	await tap([&"jump"], Vector2.ZERO, 3, 5)
	await hold(1, fr([&"attack_light"], [&"attack_light"]))
	check(p.current_move != null and String(p.current_move.id) == "air_light_4",
		"空中第 3 刀后即使短暂落地再起跳按 J，仍无缝续接劈出第 4 刀空中强普 air_light_4（实际 %s）" % (
			String(p.current_move.id) if p.current_move != null else "null"))
	if is_instance_valid(flier):
		flier.queue_free()
	await hold(40, fr())


## 三位一体深度重构：削弱基础普攻 + 活怪防复读架刀 + 方向1「J+K 三式轻重派生树」+ 方向2「紫电锋芒身法充能 & 影镖半空钉滞闭环」
func test_light_nerf_jk_branching_and_keen_edge() -> void:
	# 1) 基础普攻数值削弱与连续复读衰减 + 活怪正面连吃 3 刀普通平 A 后主动架刀弹反第 4 刀无脑 J
	await fresh_player(600.0)
	var m1: Resource = p.light_combo[0]
	var m2: Resource = p.light_combo[1]
	var m3: Resource = p.light_combo[2]
	var m4: Resource = p.light_combo[3]
	var ground_sum := float(m1.damage) + float(m2.damage) + float(m3.damage) + float(m4.damage)
	check(ground_sum <= 36.0 and float(m4.damage) <= 14.5,
		"基础普攻直伤大幅下调（四刀合计 %.1f，未带锋芒 light_4=%.1f），告别单键刮死全场" % [ground_sum, float(m4.damage)])

	var stale_bag := make_shade(Shade.Kind.GRUNT, 680.0)
	stale_bag.hp = 900.0
	stale_bag.react_cool = 999
	await hold(2, fr())
	var hit1_hp: float = float(stale_bag.hp)
	stale_bag.take_hit(m1, 1, stale_bag.global_position, 0.0, false, 1.0, p)
	var d1: float = hit1_hp - float(stale_bag.hp)
	stale_bag.combo_taken = 0
	for k in 6:
		stale_bag.combo_taken = 0
		stale_bag.take_hit(m1, 1, stale_bag.global_position, 0.0, false, 1.0, p)
	var hit8_hp: float = float(stale_bag.hp)
	stale_bag.combo_taken = 0
	stale_bag.take_hit(m1, 1, stale_bag.global_position, 0.0, false, 1.0, p)
	var d8: float = hit8_hp - float(stale_bag.hp)
	check(d8 < d1 * 0.62,
		"纯基础平 A 连续复读触发递减衰减（第 1 刀 %.2f → 第 8 刀 %.2f）" % [d1, d8])
	stale_bag.queue_free()

	# 活跃影怪（active=true）正面连吃 3 刀普通平 A 后主动架起防复读刀势，挡住第 4 刀普通 J！
	await fresh_player(600.0)
	var live_grunt := make_shade(Shade.Kind.GRUNT, 655.0, true)
	live_grunt.hp = 600.0
	live_grunt.cooldown = 999
	live_grunt.react_cool = 0
	live_grunt.state = Shade.State.HITSTUN
	live_grunt.state_frames = 12
	live_grunt.stun_frames = 4
	var eg := record(live_grunt)
	await hold(2, fr())
	for i in 125:
		if p.hitstop_frames <= 0 and (p.current_move == null or p.link_open):
			await hold(1, fr([&"attack_light", &"move_right"], [&"attack_light"], Vector2(1, 0)))
		else:
			await hold(1, fr([&"move_right"], [], Vector2(1, 0)))
		if eg.guarded >= 1:
			break
	check(eg.guarded >= 1 and live_grunt.state != Shade.State.LAUNCHED,
		"实战活怪正面连吃 3 刀普通平 A 后主动架刀挡住第 4 刀无脑 J（guarded=%d）" % eg.guarded)
	live_grunt.queue_free()

	# 2) 方向 1：J+K 三式轻重派生树（J→K 升龙挑月、JJ→K 穿云破阵、JJJ→K 断岳崩裂）
	# 2a) J → K「一式 · 升龙挑月」：破防挑飞且主角同步跃起直入空连
	await fresh_player(600.0)
	var g1 := make_shade(Shade.Kind.GRUNT, 675.0)
	g1.hp = 500.0
	g1.react_cool = 999
	await hold(2, fr())
	await hold(1, fr([&"attack_light"], [&"attack_light"]))
	for i in 32:
		await hold(1, fr())
		if p.last_swing_hit and p.hitstop_frames <= 0:
			break
	await hold(1, fr([&"attack_heavy"], [&"attack_heavy"]))
	check(p.current_move == p.combo_k_launch_move,
		"J → K 零蓄力瞬发派生「一式 · 升龙挑月」（实际 %s）" % (String(p.current_move.id) if p.current_move != null else "null"))
	for i in 24:
		await hold(1, fr())
		if g1.state == Shade.State.LAUNCHED and not p.is_on_floor():
			break
	check(g1.state == Shade.State.LAUNCHED and not p.is_on_floor(),
		"J → K 升龙挑月将敌人挑飞且主角同步腾空（敌状态=%d, 主角离地=%s）" % [g1.state, str(not p.is_on_floor())])
	# 空中 K 横轰终结高伤验证
	var hp_air_k: float = float(g1.hp)
	g1.position = p.global_position + Vector2(65.0, -10.0)
	await hold(1, fr([&"attack_heavy"], [&"attack_heavy"]))
	for i in 22:
		await hold(1, fr())
		if float(g1.hp) < hp_air_k:
			break
	check(hp_air_k - float(g1.hp) >= 14.0,
		"空中 K 横轰赋予 1.85x 终结爆发伤害（单击 %.1f）" % (hp_air_k - float(g1.hp)))
	g1.queue_free()

	# 2b) J → J → K「二式 · 穿云破阵」：长距贯穿群怪到背后 + 自动点亮紫电锋芒 + 自动回身面向敌背
	await fresh_player(560.0)
	var g2 := make_shade(Shade.Kind.GRUNT, 645.0)
	g2.hp = 600.0
	g2.react_cool = 999
	await hold(2, fr())
	for slash in 2:
		await hold(1, fr([&"attack_light"], [&"attack_light"]))
		for w in 36:
			await hold(1, fr())
			if p.hitstop_frames <= 0 and (p.link_open or p.current_move == null):
				break
	await hold(1, fr([&"attack_heavy"], [&"attack_heavy"]))
	check(p.current_move == p.combo_k_pierce_move,
		"J → J → K 派生「二式 · 穿云破阵」（实际 %s）" % (String(p.current_move.id) if p.current_move != null else "null"))
	var pierce_wait := 0
	while p.current_move != null and pierce_wait < 65:
		await hold(1, fr())
		pierce_wait += 1
	check(p.global_position.x > g2.global_position.x and p.keen_edge_timer > 0.5 and p.facing == -1,
		"穿云破阵贯穿至敌人身后、自动回身面向敌背并点亮紫电锋芒（x=%.0f>%.0f, 朝向=%d, 锋芒=%.2fs）" % [
			p.global_position.x, g2.global_position.x, p.facing, p.keen_edge_timer])
	g2.queue_free()

	# 2c) J → J → J → K「三式 · 断岳崩裂」：零蓄力霸体跃劈，正面一刀直接震碎甲影全部 60 白金凝壳！
	await fresh_player(580.0)
	var brute_jk := make_shade(Shade.Kind.ARMORED, 675.0)
	brute_jk.hp = 700.0
	brute_jk.facing = -1
	brute_jk.react_cool = 999
	var eb_jk := record(brute_jk)
	await hold(2, fr())
	for slash in 3:
		await hold(1, fr([&"attack_light"], [&"attack_light"]))
		for w in 38:
			await hold(1, fr())
			if p.hitstop_frames <= 0 and (p.link_open or p.current_move == null):
				break
	await hold(1, fr([&"attack_heavy"], [&"attack_heavy"]))
	check(p.current_move == p.combo_k_cleave_move and p.has_super_armor(),
		"J → J → J → K 派生霸体「三式 · 断岳崩裂」（实际 %s）" % (String(p.current_move.id) if p.current_move != null else "null"))
	for w in 55:
		await hold(1, fr())
		stage.reset_time_scale()
		if eb_jk.shell_broken >= 1:
			break
	check(eb_jk.shell_broken == 1 and is_equal_approx(brute_jk.shell_hp, 0.0) and brute_jk.state == Shade.State.LAUNCHED,
		"J → J → J → K 断岳崩裂正面一刀震碎甲影全部 60 白金凝壳并重炮击飞！")
	brute_jk.queue_free()

	# 3) 方向 2：「紫电锋芒」身法绕背直出真·强普 + 单目标 1.8s 防白嫖内置冷却
	await fresh_player(600.0)
	var brute_ke := make_shade(Shade.Kind.ARMORED, 675.0)
	brute_ke.hp = 700.0
	brute_ke.facing = -1
	brute_ke.react_cool = 999
	var eb_ke := record(brute_ke)
	await hold(2, fr())
	await hold(1, fr([&"short_dash"], [&"short_dash"]))
	await hold(p.step_dash_frames, fr())
	check(p.keen_edge_timer > 1.0 and p.facing == -1,
		"Shift 穿身绕到甲影背后点亮「紫电锋芒」（%.2fs）并自动回身" % p.keen_edge_timer)
	# 消耗紫电锋芒单按 J：跳过前 3 刀铺垫，0 前摇直接劈出 1.75x 真·锋芒强普 light_4，一刀秒破甲影 60 白壳！
	await hold(1, fr([&"attack_light"], [&"attack_light"]))
	check(p.current_move == p.light_combo[3] and p.is_keen_swing() and p.keen_edge_timer <= 0.0,
		"锋芒激活时单按 J 跳过前 3 刀，直接释放真·锋芒强普 light_4！")
	for w in 30:
		await hold(1, fr())
		stage.reset_time_scale()
		if eb_ke.shell_broken >= 1:
			break
	check(eb_ke.shell_broken == 1 and is_equal_approx(brute_ke.shell_hp, 0.0),
		"绕背真·锋芒强普（36×2.5=90 碎壳）一刀秒碎甲影满额 60 白壳！")
	var finish_ke := 0
	while p.current_move != null and finish_ke < 45:
		await hold(1, fr())
		finish_ke += 1
	# 防刷平衡锁：1.8s 内立刻对同一只怪反向横跳穿身，绝不重复点亮锋芒！
	brute_ke.position = Vector2(p.global_position.x - 75.0, brute_ke.ground_y())
	brute_ke.state = Shade.State.IDLE
	await hold(1, fr([&"short_dash", &"move_left"], [&"short_dash"], Vector2(-1, 0)))
	await hold(p.step_dash_frames, fr())
	check(p.keen_edge_timer <= 0.0,
		"防刷平衡锁生效：1.8s 内对同一目标反复穿身横跳不会重复白嫖紫电锋芒")
	brute_ke.queue_free()

	# 4) 影镖战术闭环：纵向瞄准半空浮空敌 → 触发「半空钉滞」+ 点亮紫电锋芒 + 超距追影贴脸 + 锋芒空强普破印引爆 + 1.1s 冷却防连射
	await fresh_player(460.0)
	var pinned_foe := make_shade(Shade.Kind.GRUNT, 890.0)   # 距离 430px（超出常规 380px 追影上限，需靠钉滞放大 1.45x 索敌！）
	pinned_foe.hp = 600.0
	pinned_foe.react_cool = 999
	await hold(2, fr())
	pinned_foe.position = Vector2(890.0, stage.floor_y - 230.0)
	pinned_foe.state = Shade.State.LAUNCHED
	pinned_foe.velocity = Vector2(0.0, 20.0)
	var pin_events := [0]
	var det_events := [0]
	pinned_foe.shadow_pinned.connect(func(_pt: Vector2): pin_events[0] += 1)
	pinned_foe.mark_detonated.connect(func(_pt: Vector2, _b: float): det_events[0] += 1)
	await hold(1, fr([&"attack_ranged"], [&"attack_ranged"]))
	check(p.ranged_cooldown >= p.rework_ranged_cooldown_frames - 1,
		"实战掷出影镖进入 1.1s 战术冷却（%d 帧）" % p.ranged_cooldown)
	# 冷却内连按 U 被拦截，不会无脑连射风筝
	var shots_extra := [0]
	var on_rf := func(_pr: Node): shots_extra[0] += 1
	p.ranged_fired.connect(on_rf)
	for w in 28:
		pinned_foe.position.y = minf(pinned_foe.position.y, stage.floor_y - 190.0)
		if w == 6:
			await hold(1, fr([&"attack_ranged"], [&"attack_ranged"]))
		else:
			await hold(1, fr())
		if pin_events[0] >= 1:
			break
	p.ranged_fired.disconnect(on_rf)
	check(shots_extra[0] == 0, "影镖冷却期间连按远射被干净拦截，杜绝无脑风筝")
	check(pin_events[0] == 1 and pinned_foe._pin_frames > 0 and pinned_foe._mark_frames > 0 and p.keen_edge_timer > 1.0,
		"影镖自动纵向微调命中远端浮空敌：触发半空钉滞悬停 + 挂破绽印记 + 点亮紫电锋芒！")
	# 借钉滞放大的 1.45x 追影距离（430px > 380px）按 Shift 远距追影贴脸，再单点 J 劈出空中真·锋芒强普引爆印记！
	await hold(1, fr([&"dash_modifier"], [&"dash_modifier"]))
	check(p.is_shadow_pursuing(), "半空钉滞将追影索敌范围放大 1.45x，430px 远距一键 Shift 追影贴脸！")
	while p.is_short_dashing():
		await hold(1, fr())
	var hp_pre_det: float = float(pinned_foe.hp)
	await hold(1, fr([&"attack_light"], [&"attack_light"]))
	check(p.current_move == p.air_combo[3] and p.is_keen_swing(),
		"追影到位后单按 J 直接消耗锋芒释放空中真·强普 air_light_4！")
	for w in 24:
		await hold(1, fr())
		if det_events[0] >= 1:
			break
	var burst_dmg: float = hp_pre_det - float(pinned_foe.hp)
	check(det_events[0] == 1 and burst_dmg >= 30.0,
		"空中锋芒强普命中引爆影钉破绽印记，打出高额处决爆发（单刀 %.1f 伤）！" % burst_dmg)
	pinned_foe.queue_free()
	await hold(45, fr())


## 11-12 重做验收：削弱普通普攻浮空能力 + 普通普攻命中不给跳、强化普攻命中才给跳
func test_normal_light_float_nerf_and_enhanced_jump_refund() -> void:
	# 1) 地面普通普攻（light_1..3）贴地平推不垫跳浮空、不给跳；地面强化普攻（light_4）挑飞并 +1 段跳
	await fresh_player(560.0)
	var g := make_shade(Shade.Kind.ARCHER, 640.0)
	g.hp = 900.0
	g.react_cool = 999
	g.arena_right = 1600.0
	await hold(3, fr())
	var normal_vy_min := [0.0]
	var normal_jump_max := [0]
	var ground_hits: Array[String] = []
	var on_gh := func(_t: Node, mv: Resource, _pt: Vector2) -> void:
		var mid := String(mv.id)
		ground_hits.append(mid)
		if mid in ["light_1", "light_2", "light_3"]:
			normal_vy_min[0] = minf(normal_vy_min[0], g.velocity.y)
			normal_jump_max[0] = maxi(normal_jump_max[0], p.bonus_air_jumps)
	p.hit_confirmed.connect(on_gh)
	for i in 90:
		if i % 8 == 0 and ground_hits.size() < 4:
			await hold(1, fr([&"attack_light"], [&"attack_light"]))
		else:
			await hold(1, fr())
		if ground_hits.has("light_4"):
			break
	p.hit_confirmed.disconnect(on_gh)
	check(ground_hits.slice(0, 3) == ["light_1", "light_2", "light_3"] and is_equal_approx(normal_vy_min[0], 0.0),
		"地面普通普攻 light_1..3 命中不再把怪垫跳浮空（最小 vy=%.1f）" % normal_vy_min[0])
	check(normal_jump_max[0] == 0 and p.bonus_air_jumps == 1,
		"地面普通普攻命中不给跳（%d），第 4 段强化普攻 light_4 命中才返还 +1 段跳（%d）" % [
			normal_jump_max[0], p.bonus_air_jumps])
	# 若死站地面不起跳不追影、就算把怪堵在墙边继续无脑按 J 打第 2 套普通四连，第 2 次普通 light_4 直接横向轰飞脱离
	var wait_down := 0
	while g.state != Shade.State.IDLE and wait_down < 140:
		await hold(1, fr())
		wait_down += 1
	g.arena_right = g.global_position.x + 120.0
	p.global_position.x = g.global_position.x - 75.0
	var second_ejected := false
	for i in 120:
		var want_g_press: bool = p.hitstop_frames <= 0 and (p.current_move == null or p.link_open)
		if want_g_press:
			await hold(1, fr([&"move_right", &"attack_light"], [&"attack_light"], Vector2(1, 0)))
		else:
			await hold(1, fr([&"move_right"], [], Vector2(1, 0)))
		if g._balance_ejected:
			second_ejected = true
			break
	check(second_ejected, "死站地面不起跳无脑复读第 2 套普通 J 四连时，直接触发横向弹射阻止地面无限挑飞")
	g.queue_free()

	# 2) 空中普通普攻（air_light_1..3）不给跳 + 浮空能力大幅削弱：跳起只无脑按 J（不按跳、不按追影）无法悬停，迅速落回地面
	await fresh_player(560.0)
	var old_mask: int = p.collision_mask
	p.collision_mask = 1
	var air_bag := make_shade(Shade.Kind.GRUNT, 635.0)
	air_bag.terrain = null
	air_bag.hp = 1200.0
	air_bag.react_cool = 999
	air_bag.arena_right = 760.0   # 故意贴近右墙，验证就算卡墙角无脑狂按 J 也会因重力下坠落地，不能挂在天上无限 A
	await hold(3, fr())
	# 先起跳并用二段跳耗光基础空中跳（_air_jumps_left == 0, bonus_air_jumps == 0）
	await tap([&"jump"], Vector2.ZERO, 3, 5)
	await tap([&"jump"], Vector2.ZERO, 3, 2)
	check(not p._can_jump() and p.bonus_air_jumps == 0, "二段跳耗尽后初始无剩余空中跳")
	air_bag.state = Shade.State.LAUNCHED
	air_bag.juggle_count = 1
	air_bag.position = p.global_position + Vector2(62.0, -8.0)
	air_bag.velocity = Vector2(0.0, -120.0)
	var air_normal_jumps := [0]
	var air_normal_min_vy := [0.0]
	var got_a4_refund := [false]
	var air_hits_mash: Array[String] = []
	var on_air_mash := func(_t: Node, mv: Resource, _pt: Vector2) -> void:
		var mid := String(mv.id)
		air_hits_mash.append(mid)
		if mid in ["air_light_1", "air_light_2", "air_light_3"]:
			air_normal_jumps[0] = maxi(air_normal_jumps[0], p.bonus_air_jumps)
			air_normal_min_vy[0] = minf(air_normal_min_vy[0], air_bag.velocity.y)
		elif mid == "air_light_4" and p.bonus_air_jumps >= 1:
			got_a4_refund[0] = true
	p.hit_confirmed.connect(on_air_mash)
	var landed_frame := -1
	for f in 95:
		var want_j: bool = p.hitstop_frames <= 0 and (p.current_move == null or p.link_open) and not p.is_on_floor()
		if want_j:
			await hold(1, fr([&"move_right", &"attack_light"], [&"attack_light"], Vector2(1, 0)))
		else:
			await hold(1, fr([&"move_right"], [], Vector2(1, 0)))
		if p.is_on_floor():
			landed_frame = f
			break
	p.hit_confirmed.disconnect(on_air_mash)
	check(air_hits_mash.has("air_light_1") and air_normal_jumps[0] == 0,
		"空中普通普攻命中绝不返还跳跃（普通空平 A 期间最大 bonus_air_jumps=%d）" % air_normal_jumps[0])
	check(air_normal_min_vy[0] >= -240.0,
		"空中普通普攻对敌托举力大幅削弱（最快上升仅 %.0f px/s，远低于旧版 -530 px/s）" % air_normal_min_vy[0])
	check(landed_frame >= 0 and landed_frame < 72,
		"即使把怪堵在墙角只无脑按 J（不按跳/追影），主角也会迅速下坠落地（%d 帧落地，杜绝无脑悬停无限 A）" % landed_frame)
	air_bag.queue_free()

	# 3) 正循环验证：耗尽二段跳后，打出强化空普 air_light_4（含锋芒直出）命中立刻返还 +1 段跳，按下跳跃即可消费奖励跳拔高续连！
	await fresh_player(560.0)
	p.collision_mask = 1
	var reward_foe := make_shade(Shade.Kind.GRUNT, 640.0)
	reward_foe.terrain = null
	reward_foe.hp = 1200.0
	reward_foe.react_cool = 999
	reward_foe.arena_right = 1600.0
	await hold(3, fr())
	await tap([&"jump"], Vector2.ZERO, 3, 5)
	await tap([&"jump"], Vector2.ZERO, 3, 2)
	check(not p._can_jump() and p.bonus_air_jumps == 0, "正循环起手：二段跳已耗尽")
	reward_foe.state = Shade.State.LAUNCHED
	reward_foe.juggle_count = 1
	reward_foe.position = p.global_position + Vector2(64.0, -10.0)
	reward_foe.velocity = Vector2(0.0, -80.0)
	p._grant_keen_edge(1.5)
	await hold(1, fr([&"attack_light"], [&"attack_light"]))
	for w in 20:
		await hold(1, fr())
		if p.bonus_air_jumps >= 1 and p.hitstop_frames <= 0:
			break
	check(p.bonus_air_jumps == 1 and p._can_jump() and reward_foe.velocity.y <= -400.0,
		"空中强化普攻 air_light_4 命中：返还 +1 段空中跳（bonus=%d）并将敌人重托拉高（vy=%.0f）！" % [
			p.bonus_air_jumps, reward_foe.velocity.y])
	# 立即按下跳跃消费强普返还跳，拔高追上敌人再砍一刀！
	var y_before_refund_jump: float = p.global_position.y
	await tap([&"jump", &"move_right"], Vector2(1, 0), 3, 4)
	check(p.bonus_air_jumps == 0 and p.velocity.y < -400.0 and p.global_position.y < y_before_refund_jump,
		"消费强化普攻返还的那一段跳成功二次拔高升空（vy=%.0f）！" % p.velocity.y)
	p.collision_mask = old_mask
	reward_foe.queue_free()
	await hold(45, fr())


## 11-13 重做验收：大幅削弱普通普攻顿帧防群怪叠滞空 + 蓄势动量（3 刀可轰重招主动远轰 + 一穿多连锁 + 满势强普自动远轰）
func test_hitstop_float_reduction_and_momentum_far_blast() -> void:
	# A) 普通普攻低顿帧 + hitstop_first_only 防群怪叠顿帧滞空 + 同轮不按跳/追影必落地
	await fresh_player(560.0)
	var m1: MoveDefinition = p.light_combo[0] as MoveDefinition
	var m2: MoveDefinition = p.light_combo[1] as MoveDefinition
	var m3: MoveDefinition = p.light_combo[2] as MoveDefinition
	var am1: MoveDefinition = p.air_combo[0] as MoveDefinition
	var am2: MoveDefinition = p.air_combo[1] as MoveDefinition
	var am3: MoveDefinition = p.air_combo[2] as MoveDefinition
	check(m1.hitstop_frames <= 4 and m2.hitstop_frames <= 4 and m3.hitstop_frames <= 4 \
			and am1.hitstop_frames <= 4 and am2.hitstop_frames <= 4 and am3.hitstop_frames <= 4 \
			and m1.hitstop_first_only and am1.hitstop_first_only,
		"普通地面/空中前 3 刀攻方顿帧已收紧且开启仅首目标顿帧（ground=%d/%d/%d, air=%d/%d/%d）" % [
			m1.hitstop_frames, m2.hitstop_frames, m3.hitstop_frames,
			am1.hitstop_frames, am2.hitstop_frames, am3.hitstop_frames])

	var old_mask: int = p.collision_mask
	p.collision_mask = 1
	var crowd: Array[Node2D] = []
	for idx in 3:
		var c := make_shade(Shade.Kind.GRUNT, 640.0 + float(idx) * 14.0)
		c.terrain = null
		c.hp = 1200.0
		c.react_cool = 999
		c.arena_right = 780.0
		crowd.append(c)
	await hold(3, fr())
	await tap([&"jump"], Vector2.ZERO, 3, 5)
	await tap([&"jump"], Vector2.ZERO, 3, 2)
	for c in crowd:
		c.state = Shade.State.LAUNCHED
		c.juggle_count = 1
		c.position = p.global_position + Vector2(64.0, -8.0)
		c.velocity = Vector2(0.0, -100.0)
	var max_crowd_hs := 0
	var crowd_landed := -1
	for f in 90:
		var want_j: bool = p.hitstop_frames <= 0 and (p.current_move == null or p.link_open) and not p.is_on_floor()
		if want_j:
			await hold(1, fr([&"move_right", &"attack_light"], [&"attack_light"], Vector2(1, 0)))
		else:
			await hold(1, fr([&"move_right"], [], Vector2(1, 0)))
		if p.current_move in [am1, am2, am3]:
			max_crowd_hs = maxi(max_crowd_hs, p.hitstop_frames)
		if p.is_on_floor():
			crowd_landed = f
			break
	check(max_crowd_hs <= 4, "一刀同时劈中 3 只浮空怪时普通空普顿帧不叠加（峰值 %d 帧）" % max_crowd_hs)
	check(crowd_landed >= 0 and crowd_landed < 72,
		"面对多只浮空怪只无脑狂按 J 也会迅速坠地（%d 帧落地）" % crowd_landed)
	for c in crowd:
		if is_instance_valid(c):
			c.queue_free()
	p.collision_mask = old_mask

	# B) 蓄势动量：3 刀蓄过「可轰」阈值 → J→J→J→K（或地面 K）主动远轰 + 贯穿多只怪破甲壳
	await fresh_player(460.0)
	var lead := make_shade(Shade.Kind.GRUNT, 540.0)
	lead.hp = 900.0
	lead.react_cool = 999
	lead.arena_right = 2400.0
	var el := record(lead)
	var mid_foe := make_shade(Shade.Kind.GRUNT, 1180.0)
	mid_foe.hp = 500.0
	mid_foe.react_cool = 999
	mid_foe.arena_right = 2400.0
	var emid := record(mid_foe)
	var back_armored := make_shade(Shade.Kind.ARMORED, 1460.0)
	back_armored.hp = 700.0
	back_armored.react_cool = 999
	back_armored.arena_right = 2400.0
	var earm := record(back_armored)
	await hold(3, fr())
	for slash in 3:
		await hold(1, fr([&"attack_light"], [&"attack_light"]))
		for w in 32:
			await hold(1, fr())
			if p.hitstop_frames <= 0 and (p.link_open or p.current_move == null):
				break
	check(lead.momentum >= Shade.MOMENTUM_READY,
		"普攻 3 刀即蓄过「可轰」阈值（momentum=%.1f >= %.1f）" % [lead.momentum, Shade.MOMENTUM_READY])
	var start_x: float = lead.global_position.x
	await hold(1, fr([&"attack_heavy"], [&"attack_heavy"]))
	var blast_vx := 0.0
	for i in 135:
		await hold(1, fr())
		stage.reset_time_scale()
		if is_instance_valid(lead):
			blast_vx = maxf(blast_vx, lead.velocity.x)
			if el.momentum_blasted >= 1 and lead.state == Shade.State.DOWN:
				break
	var dist_x: float = lead.global_position.x - start_x
	check(el.momentum_blasted >= 1 and is_equal_approx(lead.momentum, 0.0) and blast_vx >= 1300.0 and dist_x >= 680.0,
		"蓄势达标后按 K 断岳崩裂主动兑现远轰（vx=%.0f, 轰飞 %.0f px, 动量清零=%.0f）" % [
			blast_vx, dist_x, lead.momentum])
	check(emid.chain_hit >= 1 and earm.chain_hit >= 1 and is_equal_approx(back_armored.shell_hp, 0.0),
		"动量远轰如保龄球般一穿二连续撞飞后排两只影怪并震碎甲影白壳（mid_chain=%d, arm_shell=%.0f）" % [
			emid.chain_hit, back_armored.shell_hp])
	lead.queue_free()
	mid_foe.queue_free()
	back_armored.queue_free()

	# C) 地面 3 刀蓄势后，按 Shift+J 冲刺斩也能主动兑现远轰把敌直接轰飞远端
	await fresh_player(460.0)
	var dash_tgt := make_shade(Shade.Kind.GRUNT, 540.0)
	dash_tgt.hp = 900.0
	dash_tgt.react_cool = 999
	dash_tgt.arena_right = 2400.0
	var edt := record(dash_tgt)
	await hold(3, fr())
	for slash in 3:
		await hold(1, fr([&"attack_light"], [&"attack_light"]))
		for w in 32:
			await hold(1, fr())
			if p.hitstop_frames <= 0 and (p.link_open or p.current_move == null):
				break
	var dx0: float = dash_tgt.global_position.x
	await hold(1, fr([&"short_dash", &"move_right"], [&"short_dash"], Vector2(1, 0)))
	await hold(1, fr([&"short_dash", &"attack_light", &"move_right"], [&"attack_light"], Vector2(1, 0)))
	var dash_vx := 0.0
	for i in 75:
		await hold(1, fr())
		if is_instance_valid(dash_tgt):
			dash_vx = maxf(dash_vx, dash_tgt.velocity.x)
	check(edt.momentum_blasted >= 1 and dash_vx >= 1300.0 and dash_tgt.global_position.x - dx0 >= 620.0,
		"地面蓄势后 Shift+J 冲刺斩同样主动兑现远轰（vx=%.0f, 距离=%.0f px）" % [
			dash_vx, dash_tgt.global_position.x - dx0])
	dash_tgt.queue_free()

	# D) 满势（momentum >= 100.0）后连普通第 4 段强普 light_4 也会自动超远轰飞，起身恢复时动量清零
	await fresh_player(460.0)
	var full_tgt := make_shade(Shade.Kind.GRUNT, 540.0)
	full_tgt.hp = 1200.0
	full_tgt.react_cool = 999
	full_tgt.arena_right = 2600.0
	var eft := record(full_tgt)
	await hold(3, fr())
	full_tgt.momentum = Shade.MOMENTUM_MAX
	full_tgt.combo_taken = 4
	p._rework_next_light = 3
	p._rework_combo_timer = p.rework_combo_keep_frames
	await hold(1, fr([&"attack_light"], [&"attack_light"]))
	var full_vx := 0.0
	for i in 145:
		await hold(1, fr())
		if is_instance_valid(full_tgt):
			full_vx = maxf(full_vx, full_tgt.velocity.x)
			if eft.momentum_blasted >= 1 and full_tgt.state == Shade.State.IDLE:
				break
	check(eft.momentum_blasted >= 1 and full_vx >= 1750.0 and is_equal_approx(full_tgt.momentum, 0.0),
		"满势（100%%）后接第 4 段强化普攻 light_4 自动倾泻满额动量超远轰飞并在倒地起身清零（vx=%.0f）" % full_vx)
	full_tgt.queue_free()
	await hold(45, fr())


## 11-13 激进打击感升级验收：刀咬视觉反冲、反相纯白黑芯闪帧、解冻瞬爆、飙黑羽/冷白金火星、顺刀向挫镜与断魂一闪
func test_aggressive_hitfeel_overhaul() -> void:
	# 1) 切肉四连：主角 _visual.position 刀咬反冲并弹簧归零、敌人反相闪帧、飙黑羽、解冻瞬爆、顺刀向挫镜 + 归零、蓄势越 40 阈值提示
	await fresh_player(600.0)
	stage.camera.reset_shake()
	stage.camera.base_offset = Vector2.ZERO
	var foe := make_shade(Shade.Kind.GRUNT, 675.0)
	foe.hp = 600.0
	foe.react_cool = 999
	foe.arena_right = 790.0
	var ev := record(foe)
	await hold(4, fr())
	var vis := p.get_node_or_null("Visual") as Node2D
	var max_recoil := 0.0
	var max_invert := 0
	var max_jitter_p := 0.0
	var max_feathers := 0
	var saw_hitstop := false
	var saw_unfreeze := false
	var max_kick := 0.0
	var saw_a4_hit := false
	var on_a4 := func(_t: Node, mv: Resource, _pt: Vector2) -> void:
		if mv != null and StringName(mv.get(&"id")) == &"light_4":
			saw_a4_hit = true
	p.hit_confirmed.connect(on_a4)
	for i in 90:
		var want_j: bool = (not saw_a4_hit) and p.hitstop_frames <= 0 and (p.current_move == null or p.can_chain_cancel())
		if want_j:
			await hold(1, fr([&"move_right", &"attack_light"], [&"attack_light"], Vector2(1, 0)))
		else:
			await hold(1, fr([&"move_right"], [], Vector2(1, 0)))
		await process_frame
		if vis != null:
			max_recoil = maxf(max_recoil, absf(vis.position.x))
		if is_instance_valid(foe):
			max_invert = maxi(max_invert, foe._hit_invert_frames)
			max_jitter_p = maxf(max_jitter_p, foe._hit_jitter_power)
			max_feathers = maxi(max_feathers, foe._feathers.size())
			if foe.hitstop_frames > 0:
				saw_hitstop = true
			elif saw_hitstop and foe._unfreeze_snap_frames > 0:
				saw_unfreeze = true
		max_kick = maxf(max_kick, stage.camera.base_offset.length())
		if saw_a4_hit and saw_unfreeze and foe.hitstop_frames <= 0 and i >= 55:
			break
	p.hit_confirmed.disconnect(on_a4)
	for s in 45:
		await hold(1, fr())
		await process_frame
	check(max_recoil >= 8.0 and vis != null and absf(vis.position.x) < 0.25,
		"命中产生明显刀咬视觉反冲并在解冻后弹簧归零（峰值 %.1f px, 静止 %.2f）" % [max_recoil, absf(vis.position.x) if vis != null else -1.0])
	check(max_invert >= 2 and max_jitter_p >= 1.2 and saw_unfreeze and max_feathers >= 5,
		"重击命中触发反相闪帧、大幅度震颤、解冻瞬爆与黑羽飙射（invert=%d, jitter=%.2f, unfreeze=%s, feathers=%d）" % [
			max_invert, max_jitter_p, str(saw_unfreeze), max_feathers])
	check(max_kick >= 5.0 and stage.camera.base_offset == Vector2.ZERO and int(ev.momentum_threshold_reached) >= 1,
		"命中触发顺刀向挫镜并干净归零 + 蓄势跨过可轰阈值发信号（kick=%.1f, thr=%d）" % [max_kick, int(ev.momentum_threshold_reached)])

	# 2) 最后一刀斩杀触发断魂一闪（lethal_blow + 前景 lethal 裂屏斩线）
	foe.queue_free()
	await fresh_player(600.0)
	var kill_foe := make_shade(Shade.Kind.GRUNT, 675.0)
	kill_foe.hp = 5.0
	kill_foe.react_cool = 999
	var ek := record(kill_foe)
	await hold(3, fr())
	var saw_lethal_ring := false
	for i in 18:
		if i == 0:
			await hold(1, fr([&"attack_light"], [&"attack_light"]))
		else:
			await hold(1, fr())
		await process_frame
		for item in stage._impact_rings:
			if bool((item as Dictionary).get("lethal", false)):
				saw_lethal_ring = true
		if int(ek.lethal_blow) >= 1 and saw_lethal_ring:
			break
	check(int(ek.lethal_blow) >= 1 and saw_lethal_ring,
		"最后一刀斩杀触发 lethal_blow 断魂信号与前景横贯一闪斩线（signal=%d, ring=%s）" % [int(ek.lethal_blow), str(saw_lethal_ring)])
	if is_instance_valid(kill_foe):
		kill_foe.queue_free()

	# 3) 砍未破白金凝壳触发 shell_clanged + 冷白金硬火星 + 弹铁反冲
	await fresh_player(600.0)
	var arm := make_shade(Shade.Kind.ARMORED, 675.0)
	arm.react_cool = 999
	var earm := record(arm)
	await hold(3, fr())
	var arm_recoil := 0.0
	var saw_plat_spark := false
	for i in 14:
		if i == 0:
			await hold(1, fr([&"attack_light"], [&"attack_light"]))
		else:
			await hold(1, fr())
		await process_frame
		if vis != null:
			arm_recoil = maxf(arm_recoil, absf(vis.position.x))
		for ft in arm._feathers:
			if int((ft as Dictionary).get("kind", 0)) == 1:
				saw_plat_spark = true
	check(int(earm.shell_clanged) >= 1 and saw_plat_spark and arm_recoil >= 10.0,
		"砍中未破白金凝壳触发 shell_clanged 弹铁反馈、冷白金硬火星与强劲后坐反冲（clang=%d, spark=%s, recoil=%.1f）" % [
			int(earm.shell_clanged), str(saw_plat_spark), arm_recoil])
	arm.queue_free()
	for s in 40:
		await hold(1, fr())
		await process_frame


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
