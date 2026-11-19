extends SceneTree
## 开发工具（背景线 11-12）：真实游戏场景 rain_trial 里，从出生点往右走过分层入口街、进第 0 处封印竞技场，录视频自查。
## 不改任何东西，只注入“往右走 / 跳”的输入。需要真实渲染（不加 --headless）：
##   engine/Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/dev/capture_layered_entry.gd --resolution 1280x720 --fixed-fps 60 --write-movie <目录>/f.png
## 环境变量 STILL_DIR：设了就不走动，只在几个位置截图到这个目录。
const Buffer := preload("res://scripts/core/input_buffer.gd")

var stage
var p


func _initialize() -> void:
	call_deferred("run")


func fr(actions: Array[StringName] = [], axis := Vector2.ZERO, pressed: Array[StringName] = []) -> Buffer.Frame:
	var f := Buffer.Frame.new()
	f.actions = actions
	f.pressed_this_frame = pressed
	f.axis = axis
	return f


func frames(n: int, f: Buffer.Frame = null) -> void:
	for i in n:
		p.set_injected_frame(f if f != null else fr())
		await physics_frame


func run() -> void:
	stage = load("res://scenes/rain_trial.tscn").instantiate()
	root.add_child(stage)
	var panku = root.get_node_or_null("Panku")
	if panku != null:
		panku.visible = false
	await process_frame
	p = stage.player
	await frames(5)
	var lay = stage.backdrop.get_node_or_null("Layered")
	print("LAYERED ", lay != null, " anchor=", lay.anchor if lay else 0.0, " edge=", lay.edge_x if lay else 0.0, " start_x=", p.global_position.x)
	if OS.get_environment("PROBE") != "":    # 台面能不能站、跳不跳得上去
		for pl in stage.terrain.platforms:
			if pl.x1 < lay.edge_x and pl.x0 > -2500.0:
				p.reset_state(Vector2((pl.x0 + pl.x1) * 0.5, pl.y - p.foot_offset - 30.0))
				await frames(40)
				print("LEDGE x=%.0f..%.0f y=%.0f -> feet=%.0f floor=%s" % [pl.x0, pl.x1, pl.y, p.global_position.y + p.foot_offset, p.is_on_floor()])
		p.reset_state(Vector2(900.0, stage.floor_y - p.foot_offset))
		await frames(20)
		var top := 1e9
		await frames(1, fr([&"jump"], Vector2.ZERO, [&"jump"]))
		for i in 60:
			await frames(1, fr([&"jump"]))
			top = minf(top, p.global_position.y + p.foot_offset)
		print("JUMP top feet=%.0f (ground %.0f)" % [top, stage.floor_y])
		quit()
		return
	var still := OS.get_environment("STILL_DIR")
	if still != "":
		DirAccess.make_dir_recursive_absolute(still)
		var xs: Array = [300.0, 1100.0, lay.anchor, 2300.0, 3200.0, 5000.0, 9000.0]
		if OS.get_environment("STILL_XS") != "":    # 逗号分隔的世界 x，换一组截图位置
			xs = Array(OS.get_environment("STILL_XS").split(",")).map(func(s): return float(s))
		for x in xs:
			p.reset_state(Vector2(x, stage.floor_y - p.foot_offset))
			stage.camera.global_position.x = x
			stage.camera.reset_smoothing()
			await frames(40)
			await process_frame
			root.get_viewport().get_texture().get_image().save_png(still + "/x%d.png" % int(x))
			print("SHOT %d cam=%s" % [x, stage.camera.get_screen_center_position()])
		quit()
		return
	await frames(40)
	var go := fr([&"move_right"], Vector2(1, 0))
	var jump := fr([&"move_right", &"jump"], Vector2(1, 0), [&"jump"])
	var hold := fr([&"move_right", &"jump"], Vector2(1, 0))
	var n := 0
	var jumped := false
	while p.global_position.x < lay.edge_x + 900.0 and n < 1100:
		# 走到中间那座木阳台下面跳一下，看台面能不能站
		if not jumped and p.global_position.x > lay.anchor - 1130.0:
			jumped = true
			await frames(1, jump)
			await frames(12, hold)
			await frames(70, fr([&"jump"]))    # 松开方向，落在阳台上站一会儿，再往右走下去
			n += 83
			continue
		await frames(1, go)
		n += 1
	await frames(60)
	print("WALK frames=%d end_x=%.0f y=%.0f" % [n, p.global_position.x, p.global_position.y])
	quit()
