extends SceneTree
## 斜坡和“有没有、挡不挡”：真物理走一遍。只用 Tuning.test_values，不碰真实 tuning.json。
## 运行：godot --headless --fixed-fps 60 --path . --script res://tests/test_slopes.gd
const Tuning := preload("res://scripts/core/tuning.gd")
const Buffer := preload("res://scripts/core/input_buffer.gd")
const Shade := preload("res://scripts/night/shade.gd")

var stage
var p
var center := 0.0
var checks := 0
var failures: Array[String] = []


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		print("FAIL: ", label)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	await test_default_stairs()
	await test_slope_and_options()
	print("SLOPES_TESTS: ", checks, " checks / ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)


func frame(actions: Array[StringName] = [], edges: Array[StringName] = []) -> Buffer.Frame:
	var f := Buffer.Frame.new()
	f.actions = actions
	f.pressed_this_frame = edges
	return f


func move(dir: int) -> Buffer.Frame:
	var actions: Array[StringName] = []
	actions.append(&"move_right" if dir > 0 else &"move_left")
	var f := frame(actions)
	f.axis = Vector2(dir, 0)
	return f


func feet() -> float:
	return p.global_position.y + p.foot_offset


func x() -> float:
	return p.global_position.x - center


func build(section: int) -> void:
	if stage != null:
		stage.queue_free()
		await process_frame
	stage = load("res://scenes/rain_street.tscn").instantiate()
	root.add_child(stage)
	await process_frame
	p = stage.player
	stage.encounter.clear_shades()
	stage.encounter.running = false
	stage.encounter_index = section
	stage._ensure_terrain(section)
	stage.set_physics_process(false)   # 不让封印合上：这里只测地形
	center = stage._center_of(section)


func place(px: float, y: float, settle := 20) -> void:
	p.reset_state(Vector2(center + px, y - p.foot_offset - 2.0))
	p.velocity = Vector2.ZERO
	for i in settle:
		p.set_injected_frame(frame())
		await physics_frame


## 走 frames 帧，返回离地的帧数
func walk(dir: int, frames: int) -> int:
	var air := 0
	var f := move(dir)
	for i in frames:
		p.set_injected_frame(f)
		await physics_frame
		if not p.is_on_floor():
			air += 1
	return air


func jump_hold(frames: int) -> float:
	var hold: Array[StringName] = [&"jump"]
	p.set_injected_frame(frame(hold, hold))
	await physics_frame
	var top := feet()
	for i in frames:
		p.set_injected_frame(frame(hold))
		await physics_frame
		top = minf(top, feet())
	return top


func test_default_stairs() -> void:
	# 坐标从布局里读：背景线调楼时斜坡会跟着件走，这里不写死
	Tuning.test_values = {}
	var total := 0
	for section in 3:
		await build(section)
		var rows: Array = stage.terrain.layout(section).get("slopes", [])
		for i in rows.size():
			var r: Array = rows[i]
			var x0 := float(r[0])
			var y0 := float(r[1])
			var x1 := float(r[2])
			var y1 := float(r[3])
			var k := (y1 - y0) / (x1 - x0)
			var name_of := "第%d段斜坡%d" % [section, i]
			total += 1
			check(absf(k) < 1.0, name_of + " 不超过 45 度")
			# 从坡的上半段中间落下去能站住
			var mid := lerpf(x0, x1, 0.7)
			await place(mid, minf(y0, y1) - 60.0, 50)
			check(absf(feet() - (y0 + (x() - x0) * k)) < 5.0, name_of + " 从上面落下来能站住")
			# 朝高处走、朝低处走：走在坡上的这段路都贴地，脚贴着坡面
			for dir in [1, -1]:
				var start := lerpf(x0, x1, 0.8 if dir < 0 else 0.2)
				await place(start, y0 + (start - x0) * k)
				var frames := int(absf(x1 - x0) * 0.55 / 11.0)
				var air: int = await walk(dir, frames)
				check(air == 0, name_of + " 走%s全程贴地" % ("右" if dir > 0 else "左"))
				check(absf(feet() - (y0 + (x() - x0) * k)) < 5.0, name_of + " 脚贴着坡面")
	check(total >= 3, "默认的楼梯都是真斜坡")


func walk_from(px: float, y: float, dir: int, frames: int) -> int:
	await place(px, y)
	return await walk(dir, frames)


func test_slope_and_options() -> void:
	var sec := "钟楼广场"
	Tuning.test_values = {
		"layout/sections/%s/platforms" % sec: [
			[-3000, -2800, 300, "ring", {"off": true}],
			[1000, 1300, 400, "ring", {"solid": true}],
			[1400, 1700, 300, "ring", {"solid": true, "bottom": 580}],
		],
		"layout/sections/%s/blocks" % sec: [
			[1800, 1840, 300, "stone", {"bottom": 560}],
			[2300, 2500, 470, "steps", {"off": true}],
			[-2000, -1800, 470, "steps", {"pass": true}],
			[-1700, -1500, 470, "steps"],
		],
		"layout/sections/%s/slopes" % sec: [
			[-1000, 580, -500, 380, "steps"],
			[-500, 380, 0, 580, "steps"],
			[300, 580, 700, 400, "steps", {"solid": true}],
			[-2400, 580, -2200, 480, "steps", {"off": true}],
		],
		"layout/sections/%s/spawns" % sec: [[-750, 480], [1100, 400], [-200, 580]],
	}
	await build(0)

	var air: int = await walk_from(-1100.0, 580.0, 1, 90)
	check(air == 0, "走上坡再走下坡，全程不离地")
	check(x() > -300.0 and absf(feet() - (380.0 + (x() + 500.0) * 0.4)) < 4.0, "脚贴着下坡")

	await place(-250.0, 580.0)
	var top: float = await jump_hold(50)
	check(top < 478.0 and absf(feet() - 480.0) < 4.0, "从坡下能跳穿，落在坡上")
	await place(-750.0, 300.0)
	check(absf(feet() - 480.0) < 4.0, "落到坡上能站住")
	check(p.call("_try_drop_through"), "站在坡上能往下穿")
	for i in 40:
		p.set_injected_frame(frame())
		await physics_frame
	check(absf(feet() - 580.0) < 2.0, "下穿后回到地面")

	await place(200.0, 580.0)
	await walk(1, 22)
	check(feet() < 560.0, "实心坡能走上去")

	await place(1150.0, 580.0)
	top = await jump_hold(40)
	check(top > 400.0, "实心平台从下面跳不穿，头会撞到")
	await place(1150.0, 300.0)
	check(absf(feet() - 400.0) < 2.0, "实心平台上面能站")

	await walk_from(1300.0, 580.0, 1, 30)
	check(x() < 1400.0, "到地面的平台会挡路")

	await walk_from(1700.0, 480.0, 1, 30)
	check(x() < 1800.0, "只到某高度的墙也挡路")

	await place(-1450.0, 580.0)
	await walk(-1, 30)
	check(x() > -1500.0, "普通石台挡路")
	await place(-1780.0, 580.0)
	await walk(-1, 30)
	check(x() < -2000.0, "改成能跳穿的石台不挡路")
	await place(-1900.0, 580.0)
	top = await jump_hold(50)
	check(absf(feet() - 470.0) < 3.0, "能跳穿的石台可以跳上去站住")

	await place(2400.0, 300.0)
	check(absf(feet() - 580.0) < 2.0, "关掉的石台踩不到")
	await place(-2900.0, 200.0, 50)
	check(absf(feet() - 580.0) < 2.0, "关掉的平台踩不到")
	await place(-2300.0, 400.0, 30)
	check(absf(feet() - 580.0) < 2.0, "关掉的斜坡踩不到")

	var t: Node = stage.terrain
	check(absf(t.support_y(center - 750.0, 400.0) - 480.0) < 1.0, "查询：坡面高度按位置算")
	check(absf(float(t.one_way_at(center - 750.0, 480.0)) - 480.0) < 1.0, "查询：坡算单向面")

	var sh: Node2D = Node2D.new()
	sh.set_script(Shade)
	sh.setup(Shade.Kind.GRUNT, p, stage.floor_y, 1.0)
	sh.position = Vector2(center - 1100.0, 520.0)
	sh.terrain = t
	stage.add_child(sh)
	sh.spawn_frames = 0
	await place(-500.0, 380.0, 240)
	check(sh.position.y + sh.half_h < 500.0, "影卒能追上坡")
	Tuning.test_values = {}
	stage.queue_free()
	await process_frame
