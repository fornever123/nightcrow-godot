extends SceneTree
## 第四轮敌人回归测试（设计见 docs/HANDOFF-试玩版.md §16）。
## 覆盖：连续命中让击退变远、举刀格挡 / 重招破防、翻滚无敌、误伤同伴、
## 影弓的箭能打回去、影爆的炸弹会炸到同伴、远程影保持距离。
## 运行：godot --headless --fixed-fps 60 --path . --script res://tests/test_shades_v4.gd
const Buffer := preload("res://scripts/core/input_buffer.gd")
const Shade := preload("res://scripts/night/shade.gd")
const Player := preload("res://scripts/gameplay/player.gd")

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


func hold(n: int, x: Buffer.Frame = null) -> void:
	p.set_injected_frame(x if x != null else fr())
	for i in n:
		await physics_frame


func make_shade(kind: int, x: float, active := false) -> Node2D:
	var s: Node2D = Node2D.new()
	s.set_script(Shade)
	s.setup(kind, p, stage.floor_y, 1.0)
	s.position = Vector2(x, stage.floor_y - 60.0)
	stage.add_child(s)
	s.spawn_frames = 0
	s.active = active
	s.arena_left = 100.0
	s.arena_right = 1800.0
	stage._on_shade_spawned(s)
	return s


func count(s: Object, sig: String) -> Dictionary:
	var ev := {"n": 0}
	s.connect(sig, func(_a = null, _b = null, _c = null): ev.n += 1)
	return ev


func fresh(x := 600.0) -> void:
	for s in get_nodes_in_group(&"shade"):
		s.queue_free()
	for s in get_nodes_in_group(&"shade_projectile"):
		s.queue_free()
	await physics_frame
	p.reset_state(Vector2(x, stage.floor_y - p.foot_offset))
	p._set_facing(1)
	p.hp = p.max_hp
	stage.style.reset_all()
	await hold(4)


func move_named(id: StringName) -> Resource:
	for m in p.light_combo:
		if m != null and m.id == id:
			return m
	return null


func run() -> void:
	stage = load("res://scenes/night_trial.tscn").instantiate()
	root.add_child(stage)
	await process_frame
	p = stage.player
	stage.set_physics_process(false)
	await test_percent_knock()
	await test_guard()
	await test_roll()
	await test_friendly()
	await test_bolt()
	await test_bomb()
	await test_keep_distance()
	await test_soft_knock()
	await test_ult()
	print("SHADES_V4_TESTS: ", checks, " checks / ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)


func test_percent_knock() -> void:
	# 连续击退（2026-10-21 起取代失衡/伤害%）：第一下就有基础推力，同一套连段每多挨一下推得更远
	await fresh(300.0)
	var a := make_shade(Shade.Kind.GRUNT, 700.0)
	var b := make_shade(Shade.Kind.GRUNT, 1300.0)
	b.combo_taken = 5
	check(is_equal_approx(a.knock_mul(), 1.0) and b.knock_mul() > 1.9, "连续命中越多越容易飞（第1下=%.2f，第5下=%.2f）" % [a.knock_mul(), b.knock_mul()])
	b.combo_taken = 4
	var mv: Resource = p.light_combo[0]
	a.take_hit(mv, 1, a.global_position, 0.0, false, 1.0, p)
	b.take_hit(mv, 1, b.global_position, 0.0, false, 1.0, p)
	check(b.velocity.x > a.velocity.x * 1.4 and a.velocity.x > 0.0, "同一刀：连段第5下比第1下推得更远（%d vs %d）" % [int(b.velocity.x), int(a.velocity.x)])
	check(a.combo_taken == 1 and b.combo_taken == 5, "挨打后连续命中数增加（%d / %d）" % [a.combo_taken, b.combo_taken])
	check(a.poise == 0.0 and a.state != Shade.State.STUNNED, "不再积累失衡、不会眩晕")
	var heavy := make_shade(Shade.Kind.BRUTE, 1000.0)
	check(heavy.knock_mul() < a.knock_mul(), "甲影更重、更难打飞")


func test_guard() -> void:
	await fresh(600.0)
	var s := make_shade(Shade.Kind.GRUNT, 700.0)
	var g := count(s, "guarded")
	var gb := count(s, "guard_broken")
	await hold(2)
	s._begin_guard()
	check(s.state == Shade.State.GUARD and s.facing == -1, "举刀格挡并面向玩家")
	var hp0: float = s.hp
	var blocked: bool = s.take_hit(p.light_combo[0], 1, s.global_position, 0.0, false, 1.0, p)
	check(blocked and g.n == 1 and is_equal_approx(s.hp, hp0), "轻击被挡住、不掉血")
	check(s.state == Shade.State.GUARD, "挡完仍在举刀")
	var heavy := move_named(&"light_3")
	check(heavy != null, "找到第三刀 light_3")
	if heavy != null:
		s.take_hit(heavy, 1, s.global_position, 0.0, false, 1.0, p)
		check(gb.n == 1 and s.hp < hp0, "第三刀砸开格挡并打中")
	# 背后挨刀不挡
	var s2 := make_shade(Shade.Kind.GRUNT, 1100.0)
	await hold(1)
	s2._begin_guard()
	s2.facing = 1
	var hp1: float = s2.hp
	s2.take_hit(p.light_combo[0], 1, s2.global_position, 0.0, false, 1.0, p)
	check(s2.hp < hp1, "背后挨刀挡不住")
	# 挡完立刻反击
	await fresh(600.0)
	var s3 := make_shade(Shade.Kind.GRUNT, 720.0, true)
	await hold(2)
	s3._begin_guard()
	var struck := false
	for i in 50:
		await hold(1)
		if s3.state == Shade.State.WINDUP:
			struck = true
			break
	check(struck, "放下刀马上反击（50 帧内出招）")


func test_roll() -> void:
	await fresh(600.0)
	var s := make_shade(Shade.Kind.GRUNT, 720.0)
	await hold(2)
	var x0: float = s.global_position.x
	s._begin_roll()
	check(s.is_dodging(), "翻滚开始有无敌")
	var hp0: float = s.hp
	var r: bool = s.take_hit(p.light_combo[0], 1, s.global_position, 0.0, false, 1.0, p)
	check(r and is_equal_approx(s.hp, hp0), "无敌帧里砍不中")
	await hold(Shade.ROLL_FRAMES + 2)
	check(s.global_position.x - x0 > 150.0, "往后滚开（%d px）" % int(s.global_position.x - x0))
	check(not s.is_dodging() and s.state != Shade.State.ROLL, "滚完恢复")
	# 背后贴墙：从玩家身边滚过去
	var w := make_shade(Shade.Kind.GRUNT, 760.0)
	w.arena_right = 820.0
	await hold(1)
	w._begin_roll()
	check(w.roll_dir == -1, "背后没地方 → 往玩家那边穿过去")


func test_friendly() -> void:
	await fresh(300.0)
	var a := make_shade(Shade.Kind.GRUNT, 700.0)
	var b := make_shade(Shade.Kind.GRUNT, 790.0)
	var fh := count(a, "friendly_hit")
	await hold(2)
	a.facing = 1
	var hp0: float = b.hp
	a._friendly_strike()
	var lost: float = hp0 - b.hp
	check(fh.n == 1 and lost > 0.0, "影卒的刀砍到身前同伴（掉 %.1f）" % lost)
	check(lost <= float(a.strike_move.damage) * 0.55, "误伤打折")
	check(stage.style.stats.get("friendly", 0) >= 1, "评价系统记到误伤")
	var c := make_shade(Shade.Kind.GRUNT, 600.0)
	var hp_c: float = c.hp
	a._friendly_strike()
	check(is_equal_approx(c.hp, hp_c), "身后的同伴不会被砍")


func test_bolt() -> void:
	await fresh(600.0)
	var archer := make_shade(Shade.Kind.ARCHER, 1100.0)
	await hold(2)
	archer.facing = -1
	archer._update_aim()
	var spawned := []
	archer.projectile_spawned.connect(func(n): spawned.append(n))
	archer._fire_bolt()
	check(spawned.size() == 1, "影弓射出影矢")
	var hp0: float = p.hp
	for i in 60:
		await hold(1)
		if p.hp < hp0:
			break
	check(p.hp < hp0, "影矢射中玩家（掉 %.1f）" % (hp0 - p.hp))
	# 打回去
	await fresh(600.0)
	archer = make_shade(Shade.Kind.ARCHER, 1100.0)
	await hold(2)
	archer.facing = -1
	archer._update_aim()
	spawned.clear()
	archer.projectile_spawned.connect(func(n): spawned.append(n))
	archer._fire_bolt()
	var bolt: Node2D = spawned[0]
	var defl := count(bolt, "deflected")
	await hold(6)
	bolt.take_hit(p.light_combo[0], 1, bolt.global_position, 0.0, false, 1.0, p)
	check(defl.n == 1 and bolt.friendly and bolt.velocity.x > 0.0, "玩家一刀把影矢打回去")
	var ahp: float = archer.hp
	for i in 60:
		await hold(1)
		if archer.hp < ahp:
			break
	check(archer.hp < ahp, "打回去的影矢射中影弓（掉 %.1f）" % (ahp - archer.hp))
	check(stage.style.stats.get("reflect", 0) >= 1, "评价系统记到反弹")


func test_bomb() -> void:
	await fresh(200.0)
	var bomber := make_shade(Shade.Kind.BOMBER, 1300.0)
	var g := make_shade(Shade.Kind.GRUNT, 900.0)
	await hold(2)
	bomber.facing = -1
	bomber.aim = Vector2(g.global_position.x - bomber.global_position.x, 60.0)
	var spawned := []
	bomber.projectile_spawned.connect(func(n): spawned.append(n))
	bomber._throw_bomb()
	check(spawned.size() == 1, "影爆扔出炸弹")
	var ex := count(spawned[0], "exploded")
	var hp0: float = g.hp
	var php: float = p.hp
	for i in 150:
		await hold(1)
		if ex.n > 0:
			break
	await hold(3)
	check(ex.n == 1, "炸弹落地后爆炸")
	check(g.hp < hp0, "炸弹炸到旁边的影卒（掉 %.1f）" % (hp0 - g.hp))
	check(g.state == Shade.State.LAUNCHED or g.state == Shade.State.DOWN or g.state == Shade.State.DEAD, "被炸飞")
	check(is_equal_approx(p.hp, php), "离得远的玩家没被炸到")


func test_keep_distance() -> void:
	await fresh(600.0)
	var archer := make_shade(Shade.Kind.ARCHER, 720.0, true)
	await hold(60)
	var d: float = absf(archer.global_position.x - p.global_position.x)
	check(d >= 250.0, "影弓被贴身会后撤拉开距离（%d px）" % int(d))
	await fresh(600.0)
	var bomber := make_shade(Shade.Kind.BOMBER, 1500.0, true)
	await hold(90)
	d = absf(bomber.global_position.x - p.global_position.x)
	check(d < 900.0, "影爆太远会靠近（%d px）" % int(d))


## 玩家被小兵轻击：落地站稳不倒地；被甲影/炸弹重击：倒地
func knock_trial(kind: int) -> Dictionary:
	await fresh(600.0)
	var s := make_shade(kind, 900.0)
	await hold(2)
	p.invuln_frames = 0
	p.take_hit(s.strike_move, -1, p.global_position, 0.0, false, 1.0, s)
	var r := {"down": false, "free_at": -1}
	for i in 90:
		await hold(1)
		if p.state == Player.State.DOWN:
			r.down = true
		if r.free_at < 0 and p.state == Player.State.NEUTRAL:
			r.free_at = i
	return r


func test_soft_knock() -> void:
	var g := await knock_trial(Shade.Kind.GRUNT)
	check(not g.down and g.free_at >= 0 and g.free_at <= 40, "影卒轻击：落地直接站稳（%d 帧后能动）" % g.free_at)
	var b := await knock_trial(Shade.Kind.BRUTE)
	check(b.down, "甲影重击：会被打倒")
	check(b.free_at >= 0, "倒地后能站起来（%d 帧）" % b.free_at)


func ult_press(first: StringName, second: StringName, gap: int) -> void:
	await hold(1, fr([first], [first]))
	if gap > 0:
		await hold(gap, fr([first]))
	await hold(1, fr([first, second], [second]))
	await hold(1, fr())


func test_ult() -> void:
	await fresh(600.0)
	check(p.ult_enabled, "试玩关卡开启大招")
	p.ult_energy = 40.0
	await ult_press(&"attack_light", &"attack_ranged", 0)
	check(not p.is_ult(), "能量不满：J+K 不出大招")
	await hold(40)
	# 能量满 + 先 J 后 K（隔 3 帧）
	await fresh(600.0)
	var g := make_shade(Shade.Kind.GRUNT, 820.0)
	var b := make_shade(Shade.Kind.BRUTE, 420.0)
	var r := make_shade(Shade.Kind.GRUNT, 1000.0)
	var far := make_shade(Shade.Kind.GRUNT, 600.0 + 3000.0)
	far.arena_right = 5000.0
	var archer := make_shade(Shade.Kind.ARCHER, 1250.0)
	await hold(2)
	archer.facing = -1
	archer._update_aim()
	archer._fire_bolt()
	var hits := {"start": 0, "reveal": 0, "arrive": 0, "strike": 0}
	p.ult_started.connect(func(): hits.start += 1)
	p.ult_reveal.connect(func(): hits.reveal += 1)
	p.ult_arrive.connect(func(): hits.arrive += 1)
	p.ult_strike.connect(func(_k, _n): hits.strike += 1)
	var g_dmg := {"n": 0.0}
	g.damaged.connect(func(a, _t, _pt): g_dmg.n += a)
	var r_dmg := {"n": 0.0}
	r.damaged.connect(func(a, _t, _pt): r_dmg.n += a)
	p.ult_energy = p.ult_max
	check(p.ult_ready(), "能量满了")
	r._begin_roll()
	var hp := {"g": g.hp, "b": b.hp, "r": r.hp, "far": far.hp}
	await ult_press(&"attack_light", &"attack_ranged", 3)
	check(p.is_ult() and hits.start == 1, "先 J 后 K（隔 3 帧）→ 出大招")
	check(p.ult_energy == 0.0, "放大招清空能量")
	var bolt_left := get_nodes_in_group(&"shade_projectile").size()
	p.invuln_frames = maxi(p.invuln_frames, 1)
	var php: float = p.hp
	var ok_inv: bool = p.take_hit(g.strike_move, -1, p.global_position, 0.0, false, 1.0, g) == false and is_equal_approx(p.hp, php)
	check(ok_inv, "大招中无敌")
	var brute_flew := false
	var hidden_seen := false
	var g_alive_at_reveal := true
	var freeze_held := true
	for i in p.ult_total_frames + 10:
		await hold(1)
		hidden_seen = hidden_seen or bool(p.ult_hidden)
		if p.is_ult() and p.ult_frame == p.ult_final_frame + 2:
			g_alive_at_reveal = is_instance_valid(g) and g.is_alive()
		if p.is_ult() and p.ult_frame > p.ult_final_frame + 8 and p.ult_frame < p.ult_final_frame + p.ult_freeze_frames - 1:
			freeze_held = freeze_held and (not is_instance_valid(b) or b.state != Shade.State.LAUNCHED)
		brute_flew = brute_flew or (is_instance_valid(b) and b.state == Shade.State.LAUNCHED)
	await hold(2)
	check(hits.strike == 3 and hits.arrive == 1, "三刀 + 站定（strike %d / arrive %d）" % [hits.strike, hits.arrive])
	check(hits.reveal == 1, "终结横断一次")
	check(hidden_seen, "三刀之间她会消失（瞬身）")
	check(g_alive_at_reveal and freeze_held, "终结那一刀后先定格，影还没断开、甲影还没被震飞")
	check(g_dmg.n >= 80.0 and b.hp < hp.b, "屏幕里的影卒和甲影都被砍中（霸体扛不住；影卒 %.0f）" % g_dmg.n)
	check(not is_instance_valid(g) or not g.is_alive(), "影卒被斩开")
	check(is_instance_valid(b) and b.is_alive() and brute_flew, "甲影扛住终结，被震飞")
	check(r_dmg.n > 0.0, "翻滚中的影也躲不开大招")
	check(is_equal_approx(far.hp, hp.far), "屏幕外的影不受影响（镜头 x=%d，far hp %.0f→%.0f）" % [int(stage.camera.get_screen_center_position().x), hp.far, far.hp])
	check(bolt_left >= 1 and get_nodes_in_group(&"shade_projectile").is_empty(), "飞行中的影矢被斩碎")
	check(not p.is_ult() and p.state == Player.State.NEUTRAL, "大招结束恢复")
	check(stage.style.stats.get("ult", 0) >= 1, "评价系统记到大招")
	# 先 K 后 J 也行；不会多冒出一发远射 / 一刀
	await fresh(600.0)
	p.ult_energy = p.ult_max
	var shots := {"n": 0}
	p.ranged_fired.connect(func(_x): shots.n += 1)
	await ult_press(&"attack_ranged", &"attack_light", 2)
	check(p.is_ult(), "先 K 后 J（隔 2 帧）→ 出大招")
	for i in p.ult_total_frames + 6:
		await hold(1)
	check(p.state == Player.State.NEUTRAL and p.current_move == null, "大招后没有多出一刀普攻")
	# 能量来源
	await fresh(600.0)
	var e0: float = p.ult_energy
	var s2 := make_shade(Shade.Kind.GRUNT, 700.0)
	await hold(2)
	for k in 3:
		await hold(1, fr([&"attack_light"], [&"attack_light"]))
		await hold(16)
	check(p.ult_energy > e0, "打中敌人攒能量（%.0f）" % p.ult_energy)
