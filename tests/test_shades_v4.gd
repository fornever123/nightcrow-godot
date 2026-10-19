extends SceneTree
## 第四轮敌人回归测试（设计见 docs/HANDOFF-试玩版.md §16）。
## 覆盖：伤害% 让击退变远、举刀格挡 / 重招破防、翻滚无敌、误伤同伴、
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
	print("SHADES_V4_TESTS: ", checks, " checks / ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)


func test_percent_knock() -> void:
	await fresh(300.0)
	var a := make_shade(Shade.Kind.GRUNT, 700.0)
	var b := make_shade(Shade.Kind.GRUNT, 1300.0)
	b.pct = 100.0
	check(is_equal_approx(a.knock_mul(), 1.0) and b.knock_mul() > 1.55, "伤害%% 越高越容易飞（0%%=%.2f，100%%=%.2f）" % [a.knock_mul(), b.knock_mul()])
	var mv: Resource = p.light_combo[0]
	a.take_hit(mv, 1, a.global_position, 0.0, false, 1.0, p)
	b.take_hit(mv, 1, b.global_position, 0.0, false, 1.0, p)
	check(b.velocity.x > a.velocity.x * 1.4 and a.velocity.x > 0.0, "同一刀：100%% 的影被推得更远（%d vs %d）" % [int(b.velocity.x), int(a.velocity.x)])
	check(a.pct > 0.0, "挨打后伤害%% 增加（%.0f%%）" % a.pct)
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
	check(d > 300.0, "影弓被贴身会后撤拉开距离（%d px）" % int(d))
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
