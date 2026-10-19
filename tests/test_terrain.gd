extends SceneTree
## 第三轮节点 17：多层地形回归测试（scripts/night/terrain.gd）。
## 覆盖：地形查询（脚下的面 / 石台挡路 / 单向平台判断）、玩家跳上木台 / S+空格往下穿 / 石台挡路与跳上石台、
## 影卒站平台、追上平台、从平台下穿、被打飞落在平台上、撞石台侧面算撞墙、只和同一层互推、
## 封印竞技场按布局生成地形、影卒从平台上的出生点出来。
## 运行：godot --headless --fixed-fps 60 --path . --script res://tests/test_terrain.gd
const Buffer := preload("res://scripts/core/input_buffer.gd")
const Shade := preload("res://scripts/night/shade.gd")
const Terrain := preload("res://scripts/night/terrain.gd")

var stage
var p
var t
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


func hold(n: int, x: Buffer.Frame) -> void:
	p.set_injected_frame(x)
	for i in n:
		await physics_frame


func tap(edges: Array[StringName], axis := Vector2.ZERO, n := 3) -> void:
	await hold(1, fr(edges, edges, axis))
	await hold(n - 1, fr(edges, [], axis))


func feet() -> float:
	return p.global_position.y + p.foot_offset


func put_player(x: float, surface: float) -> void:
	p.reset_state(Vector2(x, surface - p.foot_offset))
	p._set_facing(1)
	p.hp = p.max_hp
	await hold(6, fr())


func clear_shades() -> void:
	for s in get_nodes_in_group(&"shade"):
		s.queue_free()
	await physics_frame


func make_shade(x: float, surface: float, active := false, kind := 0) -> Node2D:
	var s: Node2D = Node2D.new()
	s.set_script(Shade)
	s.setup(kind, p, stage.floor_y, 1.0)
	s.terrain = t
	s.position = Vector2(x, surface - float(Shade.KINDS[kind].half_h))
	stage.add_child(s)
	s.spawn_frames = 0
	s.active = active
	return s


func run() -> void:
	stage = load("res://scenes/night_trial.tscn").instantiate()
	root.add_child(stage)
	await process_frame
	p = stage.player
	t = stage.terrain
	stage.set_physics_process(false)   # 不触发封印，单独测地形
	test_layout()
	test_queries()
	await test_player_platform()
	await test_player_block()
	await test_shade_platform()
	await test_shade_chase()
	await test_shade_launch()
	await test_shade_block_wall()
	await test_separate_levels()
	await test_arena_spawns()
	print("TERRAIN_TESTS: ", checks, " checks / ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)


# ---------------------------------------------------------------- 布局 / 查询

func test_layout() -> void:
	check(t != null and t.z_index > stage.backdrop.PIXEL_Z, "地形画在背景像素化那层之后（不被像素化）")
	check(Terrain.SECTIONS.size() == stage.ROUND.size(), "每处封印一段地形布局")
	check(stage.ARENA_HALF >= 1100.0, "竞技场变宽（半宽 %d）" % int(stage.ARENA_HALF))
	var ok_reach := true
	var ok_inside := true
	for i in Terrain.SECTIONS.size():
		var lay: Dictionary = Terrain.SECTIONS[i]
		for pl in lay.platforms + lay.blocks:
			if float(pl[2]) < stage.floor_y - 300.0:   # 二段跳最高约 314
				ok_reach = false
		for sp in lay.spawns:
			if absf(float(sp[0])) > stage.ARENA_HALF - 60.0:
				ok_inside = false
	check(ok_reach, "所有平台 / 石台都在二段跳够得着的高度")
	check(ok_inside, "出生点都在竞技场里")
	check(p.collision_mask & Terrain.ONE_WAY_LAYER != 0 and p.one_way_mask == Terrain.ONE_WAY_LAYER, "玩家会撞单向平台层")
	check(Terrain.ONE_WAY_LAYER != 16 and Terrain.ONE_WAY_LAYER != 2, "单向平台层不和弹丸 / 玩家自己的层冲突")


func test_queries() -> void:
	var tt: Node2D = Terrain.new()
	tt.floor_y = 580.0
	root.add_child(tt)
	tt.add_platform(100.0, 300.0, 440.0)
	tt.add_block(500.0, 700.0, 470.0)
	check(tt.support_y(200.0, 580.0) == 580.0, "平台下面站着：脚下是地面")
	check(tt.support_y(200.0, 430.0) == 440.0, "平台上方：脚下是平台")
	check(tt.support_y(200.0, 444.0) == 440.0, "脚底比平台低一点点（台阶容差内）也算站在平台上")
	check(tt.support_y(200.0, 440.0, 10.0, 440.0) == 580.0, "正在往下穿的平台被忽略")
	check(tt.support_y(95.0, 430.0, 10.0) == 440.0 and tt.support_y(85.0, 430.0, 10.0) == 580.0, "平台边缘按脚宽判断")
	check(tt.top_at(600.0) == 470.0 and tt.solid_top(200.0) == 580.0, "最高面 / 实心面查询")
	var po: Vector2 = tt.push_out(520.0, 24.0, 580.0)
	check(po.x == 476.0 and po.y == 1.0, "从左边撞石台 → 推回左侧，撞右墙")
	po = tt.push_out(690.0, 24.0, 580.0)
	check(po.x == 724.0 and po.y == -1.0, "从右边撞石台 → 推回右侧，撞左墙")
	check(tt.push_out(600.0, 24.0, 470.0).y == 0.0, "站在石台上不被推")
	check(is_finite(tt.one_way_at(200.0, 440.0)) and not is_finite(tt.one_way_at(600.0, 470.0)), "单向平台能下穿、石台不能")
	tt.queue_free()


# ---------------------------------------------------------------- 玩家

func test_player_platform() -> void:
	var c: float = stage._center_of(0)
	var x := c - 570.0                    # 第 1 处左边的木栈道（中心 −760 ~ −380，高 440）
	await put_player(x, stage.floor_y)
	check(absf(feet() - stage.floor_y) < 2.0, "木台下面能站在地上（单向平台不挡）")
	await tap([&"jump"], Vector2.ZERO, 3)
	await hold(70, fr())
	check(p.is_on_floor() and absf(feet() - 440.0) < 3.0, "一段跳从下面穿上木台并站住（脚底 %.0f）" % feet())
	check(p.standing_on_one_way(), "站在单向平台上能被识别")
	await tap([&"jump"], Vector2(0, 1), 3)
	check(p.is_dropping_through(), "按住 S 再按跳 → 开始往下穿")
	await hold(70, fr())
	check(p.is_on_floor() and absf(feet() - stage.floor_y) < 3.0, "穿过木台落回地面（脚底 %.0f）" % feet())
	check(not p.is_dropping_through() and p.collision_mask & t.ONE_WAY_LAYER != 0, "穿过去后恢复平台碰撞")
	# 穿下去后马上再跳：还能二段跳回到平台上
	await put_player(x, 440.0)
	await tap([&"jump"], Vector2(0, 1), 2)
	await hold(4, fr())
	var left: int = p._air_jumps_left
	await tap([&"jump"], Vector2.ZERO, 3)
	await hold(70, fr())
	check(left >= 1 and p.is_on_floor() and absf(feet() - 440.0) < 3.0, "下穿后立刻二段跳能跳回平台")
	# 在平台上普通起跳（不按 S）不会穿下去
	await tap([&"jump"], Vector2.ZERO, 3)
	await hold(70, fr())
	check(absf(feet() - 440.0) < 3.0, "平台上普通起跳落回平台")
	# 走出平台边缘 → 掉到地上
	await hold(80, fr([], [], Vector2(-1, 0)))
	await hold(40, fr())
	check(absf(feet() - stage.floor_y) < 3.0, "走出平台边缘掉回地面")
	# 下砸不会穿平台
	await put_player(x, 440.0)
	await tap([&"jump"], Vector2.ZERO, 3)
	await hold(14, fr())
	await tap([&"attack_light"], Vector2.ZERO, 3)
	await tap([&"attack_light"], Vector2(0, 1), 3)
	await hold(90, fr())
	check(absf(feet() - 440.0) < 3.0, "在平台上空下砸落回平台（不穿过去）")


func test_player_block() -> void:
	var c: float = stage._center_of(1)
	t.ensure_section(1, c)
	var bx0: float = c - 1200.0           # 第 2 处左石台：−1200 ~ −700，高 472
	await put_player(bx0 - 140.0, stage.floor_y)
	await hold(60, fr([], [], Vector2(1, 0)))
	check(p.global_position.x < bx0 - 10.0, "石台侧面挡路（x %.0f）" % p.global_position.x)
	await tap([&"jump"], Vector2(1, 0), 3)
	# Navigate onto the platform, rather than running off it at the new speed.
	for i in 90:
		if p.global_position.x >= bx0 + 200.0:
			break
		await hold(1, fr([], [], Vector2(1, 0)))
	await hold(90, fr())
	check(p.is_on_floor() and absf(feet() - 472.0) < 3.0, "跳上石台（脚底 %.0f）" % feet())
	await tap([&"jump"], Vector2(0, 1), 3)
	check(not p.is_dropping_through(), "石台上 S+跳 = 普通起跳")
	await hold(70, fr())
	check(absf(feet() - 472.0) < 3.0, "石台上 S+跳 不会穿下去（脚底 %.0f）" % feet())


# ---------------------------------------------------------------- 影卒

func test_shade_platform() -> void:
	await clear_shades()
	var c: float = stage._center_of(0)
	await put_player(c - 1100.0, stage.floor_y)
	var s := make_shade(c - 600.0, 440.0)
	for i in 30:
		await physics_frame
	check(s.on_ground() and absf(s.feet_y() - 440.0) < 1.0, "影卒能站在木台上")
	s.position.x = c - 300.0              # 挪出平台 → 掉下去
	for i in 40:
		await physics_frame
	check(s.on_ground() and absf(s.feet_y() - stage.floor_y) < 1.0, "影卒走出平台掉回地面")


func test_shade_chase() -> void:
	await clear_shades()
	var c: float = stage._center_of(0)
	await put_player(c - 570.0, 440.0)
	p.invuln_frames = 100000
	var s := make_shade(c - 900.0, stage.floor_y, true)
	var reached := false
	for i in 300:
		await physics_frame
		p.hp = p.max_hp
		if s.on_ground() and absf(s.feet_y() - 440.0) < 2.0:
			reached = true
			break
	check(reached, "玩家在木台上 → 影卒跳上去追（脚底 %.0f）" % s.feet_y())
	# 玩家在下面 → 影卒从木台往下穿
	await put_player(c - 480.0, stage.floor_y)
	p.invuln_frames = 100000
	s.position = Vector2(c - 640.0, 440.0 - s.half_h)
	s.velocity = Vector2.ZERO
	var down := false
	for i in 200:
		await physics_frame
		p.hp = p.max_hp
		if s.on_ground() and absf(s.feet_y() - stage.floor_y) < 2.0:
			down = true
			break
	check(down, "玩家在下面 → 影卒从单向平台往下穿")
	# 玩家在石台上 → 影卒跳上石台
	await clear_shades()
	var c1: float = stage._center_of(1)
	await put_player(c1 - 900.0, 472.0)
	p.invuln_frames = 100000
	var s2 := make_shade(c1 - 560.0, stage.floor_y, true)
	var up := false
	for i in 300:
		await physics_frame
		p.hp = p.max_hp
		if s2.on_ground() and absf(s2.feet_y() - 472.0) < 2.0:
			up = true
			break
	check(up, "玩家在石台上 → 影卒跳上石台")
	# 同一层但中间隔着石台 → 翻过去
	await clear_shades()
	var c2: float = stage._center_of(2)
	t.ensure_section(2, c2)
	await put_player(c2 + 420.0, stage.floor_y)
	p.invuln_frames = 100000
	var s3 := make_shade(c2 - 420.0, stage.floor_y, true)
	var over := false
	for i in 400:
		await physics_frame
		p.hp = p.max_hp
		if s3.position.x > c2 + 220.0:
			over = true
			break
	check(over, "中间隔着石台 → 影卒翻过去追")
	p.invuln_frames = 0
	await clear_shades()


func test_shade_launch() -> void:
	await clear_shades()
	var c: float = stage._center_of(0)
	await put_player(c - 1100.0, stage.floor_y)
	var s := make_shade(c - 600.0, 440.0)
	await physics_frame
	s.state = Shade.State.LAUNCHED
	s.velocity = Vector2(0, -700)
	var landed := false
	for i in 120:
		await physics_frame
		if s.state == Shade.State.DOWN:
			landed = true
			break
	check(landed and absf(s.feet_y() - 440.0) < 1.0, "在平台上被挑飞 → 落回平台（脚底 %.0f）" % s.feet_y())
	# 从地面挑飞穿过平台往上：上升时不被平台截住
	s.position = Vector2(c - 600.0, stage.floor_y - s.half_h)
	s.state = Shade.State.LAUNCHED
	s.velocity = Vector2(0, -1100)
	var peak := 9999.0
	for i in 90:
		await physics_frame
		peak = minf(peak, s.feet_y())
	check(peak < 400.0, "上升时直接穿过单向平台（最高脚底 %.0f）" % peak)
	check(absf(s.feet_y() - 440.0) < 1.0, "落下时接在平台上")


func test_shade_block_wall() -> void:
	await clear_shades()
	var c: float = stage._center_of(1)
	await put_player(c, stage.floor_y)
	var s := make_shade(c - 600.0, stage.floor_y)   # 左石台右边缘 −700
	var slams := [0]
	s.wall_slam.connect(func(_sp, dmg, _pt): if dmg > 0.0: slams[0] += 1)
	await physics_frame
	var hp0: float = s.hp
	s.state = Shade.State.LAUNCHED
	s.velocity = Vector2(-1100, -200)
	for i in 60:
		await physics_frame
	check(slams[0] >= 1 and s.hp < hp0, "被横扫打进石台侧面 → 撞墙伤害")
	check(s.position.x - s.half_w >= c - 700.0 - 1.0, "撞完没有嵌进石台里")


func test_separate_levels() -> void:
	await clear_shades()
	var c: float = stage._center_of(0)
	await put_player(c - 1100.0, stage.floor_y)
	var a := make_shade(c - 600.0, 440.0)
	var b := make_shade(c - 600.0, stage.floor_y)
	for i in 20:
		await physics_frame
	check(absf(a.position.x - b.position.x) < 2.0, "不同层的影卒互不推挤")
	var b2 := make_shade(c - 600.0, stage.floor_y)
	for i in 30:
		await physics_frame
	check(absf(b2.position.x - b.position.x) > 20.0, "同一层的影卒照样互相推开")
	await clear_shades()


func test_arena_spawns() -> void:
	await clear_shades()
	stage.set_physics_process(true)
	stage.encounter_index = 0
	await put_player(stage._next_center() - stage.TRIGGER_BEFORE + 10.0, stage.floor_y)
	await hold(3, fr())
	check(stage.phase == stage.Phase.FIGHT, "进入第 1 处封印")
	check(not stage.encounter.spawn_points.is_empty() and stage.encounter.terrain == t, "封印用了地形的出生点")
	p.invuln_frames = 100000
	var on_platform := 0
	var bad := 0
	for i in 600:
		await physics_frame
		p.hp = p.max_hp
		for s in get_nodes_in_group(&"shade"):
			if s.state == Shade.State.DEAD or s.spawn_frames > 30:
				continue
			if s.spawn_frames == 30:
				if s.feet_y() < stage.floor_y - 50.0:
					on_platform += 1
				if absf(s.level_y() - s.feet_y()) > 1.0:
					bad += 1
			if s.spawn_frames <= 0:
				s._die(1)
		if stage.encounter.finished:
			break
	check(on_platform >= 1, "有影卒从平台上的出生点出来（%d 只）" % on_platform)
	check(bad == 0, "出生时脚正好踩在面上")
	p.invuln_frames = 0
