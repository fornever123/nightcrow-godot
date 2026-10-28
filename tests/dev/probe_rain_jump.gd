extends SceneTree
## 开发工具：在雨夜河岸街的指定位置原地起跳，逐帧打印脚底高度和状态（查“这里跳不上去”）。
## engine/Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/dev/probe_rain_jump.gd
const Buffer := preload("res://scripts/core/input_buffer.gd")
var stage
var p


func _initialize() -> void:
	call_deferred("run")


func fr(actions: Array[StringName] = [], edges: Array[StringName] = [], axis := Vector2.ZERO) -> Buffer.Frame:
	var f := Buffer.Frame.new()
	f.actions = actions
	f.pressed_this_frame = edges
	f.axis = axis
	return f


func probe(x: float, stand_feet: float) -> void:
	p.reset_state(Vector2(x, stand_feet - p.foot_offset))
	for i in 40:
		p.set_injected_frame(fr())
		await physics_frame
	var top := 1.0e9
	var trace: PackedStringArray = []
	for i in 80:
		var f := fr()
		if i == 0:
			f = fr([&"jump"], [&"jump"])
		elif i < 18:
			f = fr([&"jump"])
		p.set_injected_frame(f)
		await physics_frame
		var feet: float = p.global_position.y + p.foot_offset
		top = minf(top, feet)
		if i % 6 == 0:
			trace.append("%d:%.0f/%s" % [i, feet, str(p.state)])
	print("x=%.0f from %.0f -> peak %.0f, end %.0f  %s" % [x, stand_feet, top, p.global_position.y + p.foot_offset, " ".join(trace)])


func run() -> void:
	stage = load("res://scenes/rain_street.tscn").instantiate()
	root.add_child(stage)
	await process_frame
	p = stage.player
	stage.encounter.running = false
	var c0: float = stage._center_of(0)
	await probe(c0 - 1080.0, 300.0)   # 二层阳台 → 三层屋檐（失败的那处）
	await probe(c0 - 2020.0, 300.0)   # 左边二层阳台 → 三层阳台（成功的那处）
	await probe(c0 - 1080.0, 580.0)   # 地面 → 二层
	await probe(c0 - 1770.0, 0.0)     # 错落版：角楼三层环形阳台 → 塔帽石檐（高差 300，最难的一跳）
	await probe(c0 - 770.0, 580.0)    # 错落版：地面 → 店面雨棚（400）
	# 进竞技场（封印合上、战斗阶段）后再测一遍
	p.reset_state(Vector2(c0 - 1900.0, 580.0 - p.foot_offset))
	for i in 20:
		p.set_injected_frame(fr())
		await physics_frame
	print("phase ", stage.phase)
	stage.encounter.clear_shades()
	stage.encounter.running = false
	# 和录制脚本同样的顺序：地面起跳上二层，落地等 30 帧再跳三层
	for x in [c0 - 1080.0, c0 - 2020.0]:
		p.reset_state(Vector2(x, 580.0 - p.foot_offset))
		for i in 30:
			p.set_injected_frame(fr())
			await physics_frame
		var res: PackedStringArray = []
		for leg in 2:
			for i in 18:
				p.set_injected_frame(fr([&"jump"], [&"jump"]) if i == 0 else fr([&"jump"]))
				await physics_frame
			for i in 150:
				p.set_injected_frame(fr())
				await physics_frame
			res.append("%.0f" % (p.global_position.y + p.foot_offset))
		print("ground-chain x=%.0f -> %s (want 300, 20)" % [x, ", ".join(res)])
	# 落地后隔几帧再跳（玩家连着往上跳的手感）：二层 → 三层 → 屋脊
	for wait in [4, 10, 20]:
		p.reset_state(Vector2(c0 - 2020.0, 300.0 - p.foot_offset))
		for i in 30:
			p.set_injected_frame(fr())
			await physics_frame
		for leg in 2:
			for i in 18:
				p.set_injected_frame(fr([&"jump"], [&"jump"]) if i == 0 else fr([&"jump"]))
				await physics_frame
			var landed := 0
			for i in 120:
				p.set_injected_frame(fr())
				await physics_frame
				if p.is_on_floor():
					landed += 1
					if landed >= wait:
						break
		print("chain wait=%d -> feet %.0f (want -260) state %s" % [wait, p.global_position.y + p.foot_offset, str(p.state)])
	quit()
