extends SceneTree
## 原生 Vulkan Forward+（严禁 --headless！）实机多机位截图与动态帧导出器
## 完整检验 4800u【司辰母钟楼 · 钟前校时天廊】与【5:59 暗朱红母钟】五重光学动效。

const StageScene := preload("res://scenes/boss_sample.tscn")

var stage: Node = null
var out_dir: String = ""
var mode_movie: bool = false


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = "E:/00game/nightcrow-godot/docs/视觉设计/Boss战/母钟天廊成图_20261117/实机验收截图"
	for i in args.size():
		if args[i] == "--out-dir" and i + 1 < args.size():
			out_dir = args[i + 1]
		elif args[i] == "--movie-tour":
			mode_movie = true
	DirAccess.make_dir_recursive_absolute(out_dir)
	call_deferred("_run")


func _hide_debug_overlays() -> void:
	for n in root.get_children():
		if n.name.contains("Panku") or n.get_class().contains("Panku"):
			if "visible" in n:
				n.visible = false
			for c in n.get_children():
				if c is CanvasLayer or c is Control:
					c.visible = false


func _wait_frames(n: int) -> void:
	for _i in n:
		await process_frame


func _save_shot(filename: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(out_dir.path_join(filename))
	print("SAVED_SHOT: ", filename)


func _run() -> void:
	_hide_debug_overlays()
	stage = StageScene.instantiate()
	root.add_child(stage)
	current_scene = stage
	await _wait_frames(6)
	_hide_debug_overlays()

	stage.set_stage_showcase_mode(true)
	if stage.hud != null:
		stage.hud.visible = false

	if mode_movie:
		await _run_movie_choreography()
	else:
		await _run_8_shots()

	stage.queue_free()
	await _wait_frames(3)
	quit(0)


func _snap_cam(world_x: float, feet_y: float = 580.0) -> void:
	var cy: float = stage._cam_y_for(feet_y)
	stage._duel_cam_anchor.global_position = Vector2(world_x, cy)
	stage.camera.lock_y = cy
	stage.camera.global_position = Vector2(world_x, cy)


func _run_8_shots() -> void:
	var p = stage.player
	var back = stage.backdrop
	var rig = back.clock_rig
	var cx: float = stage.arena_center
	var fy: float = stage.floor_y

	# Shot 1: 中枢钟前主决斗桥 (S2) —— 5:59 超载炉心心跳与擒纵死卡回弹瞬间（铁花飞溅 + 60° 朱红光束 + 湿石红钟倒影）
	back.reset_phase()
	p.reset_state(Vector2(cx - 210.0, fy - p.foot_offset))
	p._set_facing(1)
	_snap_cam(cx - 40.0, fy)
	rig.trigger_manual_heartbeat_burst()
	await _wait_frames(8)
	await _save_shot("shot01_center_559_heartbeat.png")

	# Shot 2: 紫刀光 vs 暗朱红母钟 —— 主角挥出纯紫快剑刀弧照亮湿青石板法线与薄镜倒影
	p.reset_state(Vector2(cx - 120.0, fy - p.foot_offset))
	p._set_facing(1)
	_snap_cam(cx, fy)
	p._start_move(p.light_combo[1], false)
	await _wait_frames(5)
	await _save_shot("shot02_purple_slash_vs_crimson_clock.png")

	# Shot 3: 左翼盘旋登顶阶 (S1) —— 煤气暖白风灯 + 塔内配重齿轮拱洞剖面 + 0.26x 视差暗朱红巨钟
	p.reset_state(Vector2(cx - 1890.0, 492.0 - p.foot_offset))
	p._set_facing(1)
	_snap_cam(cx - 1465.0, 492.0)
	await _wait_frames(12)
	await _save_shot("shot03_left_wing_gaslamp_stairs.png")

	# Shot 4: 右翼断链飞扶壁台 (S3) —— 暗朱红侧逆光石阶 + 悬吊青铜配重断链 + 音簧管剖面
	p.reset_state(Vector2(cx + 1650.0, 415.0 - p.foot_offset))
	p._set_facing(-1)
	_snap_cam(cx + 1465.0, 415.0)
	await _wait_frames(12)
	await _save_shot("shot04_right_wing_broken_chains.png")

	# Shot 5: 动效三【时间倒流 · 炽红狂转与百雨倒升】
	p.reset_state(Vector2(cx - 240.0, fy - p.foot_offset))
	p._set_facing(1)
	_snap_cam(cx, fy)
	back.set_rewind_visual(1.0)
	await _wait_frames(24)
	await _save_shot("shot05_vfx_rewind_overdrive.png")

	# Shot 6: 动效四【二阶段 · 暗朱红钟窗崩裂 24 残片低重力悬停】
	back.set_rewind_visual(0.0)
	back.trigger_phase2_shatter()
	await _wait_frames(34)
	await _save_shot("shot06_vfx_shattered_24_shards.png")

	# Shot 7: 组合奇观【碎钟态时间倒流 · 24 块红玻璃残片螺旋倒吸重拼瞬间】
	back.set_rewind_visual(1.0)
	await _wait_frames(15)
	await _save_shot("shot07_vfx_rewind_spiral_reassembly.png")

	# Shot 8: 动效五【终局破晓 · 一剑贯通 6:00】
	back.trigger_victory_dawn()
	p._start_move(p.up_strike_move, false)
	await _wait_frames(22)
	await _save_shot("shot08_vfx_cleaved_600_dawn.png")


func _run_movie_choreography() -> void:
	# 600 帧（10.0s @ 60fps）一镜到底实机运镜与母钟五重动效完整实录！
	var p = stage.player
	var back = stage.backdrop
	var rig = back.clock_rig
	var cx: float = stage.arena_center
	var fy: float = stage.floor_y

	# 段 1 (0..135 帧 = 2.25s)：从左翼煤气灯石阶一路疾跑冲上中枢钟前主桥，头顶 5:59 母钟两次超载心跳崩弹爆铁花！
	back.reset_phase()
	p.reset_state(Vector2(cx - 1780.0, fy - p.foot_offset))
	p._set_facing(1)
	_snap_cam(cx - 1420.0, fy)
	for f in 135:
		p.velocity.x = 560.0 if p.global_position.x < cx - 180.0 else 0.0
		if f == 45 or f == 108:
			rig.trigger_manual_heartbeat_burst()
		if f == 112:
			p._start_move(p.light_combo[0], false)
		await process_frame

	# 段 2 (135..255 帧 = 2.0s)：触发【时间倒流 · 炽红狂转与百雨倒升】，十米分针扇形红弧逆旋、满屏暴雨倒流升空！
	p.velocity.x = 0.0
	back.set_rewind_visual(1.0)
	for f in 120:
		if f == 35:
			p._start_move(p.light_combo[1], false)
		await process_frame

	# 段 3 (255..375 帧 = 2.0s)：触发【暗朱红钟窗崩裂 · 24 残片低重力悬停】，主角向右侧断链石阶冲刺！
	back.set_rewind_visual(0.0)
	back.trigger_phase2_shatter()
	for f in 120:
		if f >= 50 and f < 105:
			p.velocity.x = 520.0
			p._set_facing(1)
		else:
			p.velocity.x = 0.0
		await process_frame

	# 段 4 (375..495 帧 = 2.0s)：主角回身面朝巨钟，触发【碎钟时间倒流螺旋重拼 -> 再炸开】高潮奇观！
	p.velocity.x = 0.0
	p._set_facing(-1)
	back.set_rewind_visual(1.0)
	for f in 75:
		await process_frame
	back.set_rewind_visual(0.0)
	for f in 45:
		await process_frame

	# 段 5 (495..600 帧 = 1.75s)：主角跃至钟心正下方挥出紫电挑斩，母钟冲破死点贯通【6:00】！
	p.global_position = Vector2(cx - 60.0, fy - p.foot_offset)
	p._set_facing(1)
	_snap_cam(cx, fy)
	p._start_move(p.up_strike_move, false)
	back.trigger_victory_dawn()
	for _f in 105:
		await process_frame
