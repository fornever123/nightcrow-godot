extends SceneTree
## R3 满弓月华流光斩 · 主角「朔」全部 16 套战斗挥斩招式 Forward+ 雨夜河岸街实机验收抓拍脚本
## 铁律：严禁加 --headless，Panku 默认保持隐藏，100% 原生 Forward+ 灯光、积水倒影与雨丝。
## Phase A) 精确锁帧抓拍全部 16 套招式的峰值刀光帧 (1280x720 PNG)；
## Phase B) 连续录制 300 帧 (5.0s @ 60fps) 全招式实战连招视频序列 (seq/f_000.png .. f_299.png)。

const Buffer := preload("res://scripts/core/input_buffer.gd")
const Config := preload("res://scripts/core/configuration.gd")

var stage: Node2D
var p: CharacterBody2D
var view: Sprite2D
var moves: Dictionary
var seq_idx := 0
var seq_dir := ""
var record_seq := false
const MAX_SEQ_FRAMES := 300


func _initialize() -> void:
	Engine.max_physics_steps_per_frame = 1
	call_deferred("run")


func make_frame(held: Array[StringName] = [], edges: Array[StringName] = [], axis := Vector2.ZERO) -> Buffer.Frame:
	var f := Buffer.Frame.new()
	f.actions = held
	f.pressed_this_frame = edges
	f.axis = axis
	return f


func save_png(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("SHOT ", path.get_file(), " -> clip=", view.clip_name, " frame=", view.frame_index)


func tick_n(count: int, f: Buffer.Frame = null) -> void:
	var inf := make_frame() if f == null else f
	for _i in count:
		p.set_injected_frame(inf)
		await physics_frame
		stage.camera.global_position = Vector2(clampf(p.global_position.x + 35.0, 900.0, 2600.0), stage.CAM_Y)
		await process_frame
		if record_seq and seq_idx < MAX_SEQ_FRAMES:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("%s/f_%03d.png" % [seq_dir, seq_idx])
			seq_idx += 1


func reset_actor(x := 1410.0, y_off := 0.0, facing_dir := 1) -> void:
	p._end_attack()
	p._stop_guard()
	p.hitstop_frames = 0
	p.reset_state(Vector2(x, stage.floor_y - p.foot_offset + y_off))
	p._set_facing(facing_dir)
	view.stance_initialized = true
	view.stance_drawn = true
	view.stance_clip = ""
	stage.camera.global_position = Vector2(x + 35.0, stage.CAM_Y)
	var old_rec := record_seq
	record_seq = false
	await tick_n(2)
	record_seq = old_rec


func wait_anim_frame(expected_clip: String, target_idx: int, max_ticks := 60, held_f: Buffer.Frame = null) -> void:
	if view.clip_name == expected_clip and view.frame_index == target_idx:
		return
	for _i in max_ticks:
		await tick_n(1, held_f)
		if view.clip_name == expected_clip and view.frame_index >= target_idx:
			return


func run() -> void:
	var folder := OS.get_environment("SHOT_DIR")
	if folder.is_empty():
		folder = ProjectSettings.globalize_path("res://.runtime/r3_all_moves_shots")
	seq_dir = folder + "/seq"
	DirAccess.make_dir_recursive_absolute(folder)
	DirAccess.make_dir_recursive_absolute(seq_dir)

	var cfg := Config.read()
	moves = Config.moves(cfg)

	root.content_scale_size = Vector2i(1280, 720)
	stage = load("res://scenes/rain_street.tscn").instantiate()
	root.add_child(stage)
	current_scene = stage
	await process_frame

	stage.set_physics_process(false)
	stage.encounter.set_physics_process(false)
	stage.encounter.set_process(false)
	stage.hud.help_visible = false
	stage.hud._banner = ""
	stage.hud._banner_life = 0.0

	p = stage.player
	view = p.get_node("Visual/ActorSprite")

	# =========================================================================
	# Phase A: 16 套战斗挥斩招式峰值帧逐一实机抓拍
	# =========================================================================
	record_seq = false

	# 01. attack_1 (f05)
	await reset_actor(1400.0, 0.0, 1)
	p._start_move(moves["light_1"], false)
	await wait_anim_frame("attack_1", 5, 30)
	await save_png(folder + "/01_attack_1.png")

	# 02. attack_2 (f04)
	await reset_actor(1400.0, 0.0, 1)
	p._start_move(moves["light_2"], false)
	await wait_anim_frame("attack_2", 4, 30)
	await save_png(folder + "/02_attack_2.png")

	# 03. attack_3 (f04 上撩 + f10 重劈，主峰值取 f04)
	await reset_actor(1400.0, 0.0, 1)
	p._start_move(moves["light_3"], false)
	await wait_anim_frame("attack_3", 4, 30)
	await save_png(folder + "/03_attack_3.png")

	# 04. attack_up (f09)
	await reset_actor(1400.0, 0.0, 1)
	p._start_move(moves["up_strike"], true)
	await wait_anim_frame("attack_up", 9, 36)
	await save_png(folder + "/04_attack_up.png")

	# 05. air_attack_1 (f12)
	await reset_actor(1400.0, -150.0, 1)
	p.velocity = Vector2(20.0, -40.0)
	p._start_move(moves["air_light_1"], false)
	await wait_anim_frame("air_attack_1", 12, 36)
	await save_png(folder + "/05_air_attack_1.png")

	# 06. air_attack_2 (f08)
	await reset_actor(1400.0, -155.0, 1)
	p.velocity = Vector2(20.0, -40.0)
	p._start_move(moves["air_light_2"], false)
	await wait_anim_frame("air_attack_2", 8, 30)
	await save_png(folder + "/06_air_attack_2.png")

	# 07. air_attack_3 (f00)
	await reset_actor(1400.0, -150.0, 1)
	p.velocity = Vector2(20.0, -40.0)
	p._start_move(moves["air_light_3"], false)
	await wait_anim_frame("air_attack_3", 0, 12)
	await save_png(folder + "/07_air_attack_3.png")

	# 08. dash_right_video (f12)
	await reset_actor(1340.0, 0.0, 1)
	p._start_move(moves["dash_slash"], false)
	await wait_anim_frame("dash_right_video", 12, 36)
	await save_png(folder + "/08_dash_right_video.png")

	# 09. dash_left_video (f11)
	await reset_actor(1480.0, 0.0, -1)
	p._start_move(moves["dash_slash_left"], false)
	await wait_anim_frame("dash_left_video", 11, 36)
	await save_png(folder + "/09_dash_left_video.png")

	# 10. parry (f08)
	await reset_actor(1420.0, 0.0, 1)
	if moves.has("parry_1"):
		p._start_move(moves["parry_1"], false)
		await wait_anim_frame("parry", 8, 30)
	if view.clip_name != "parry" or view.frame_index < 8:
		var parry_fps := float(view.setup.get("animations", {}).get("parry", {}).get("fps", 36.0))
		p._end_attack()
		p._stop_guard()
		view.clip_name = "parry"
		view.clock = 8.4 / maxf(parry_fps, 1.0)
		view._draw_frame()
	await save_png(folder + "/10_parry.png")

	# 11. guard_hit_1 (f01)
	await reset_actor(1420.0, 0.0, 1)
	p._start_move(moves["guard_hit_1"], false)
	await wait_anim_frame("guard_hit_1", 1, 20)
	await save_png(folder + "/11_guard_hit_1.png")

	# 12. guard_hit_2 (f05)
	await reset_actor(1420.0, 0.0, 1)
	p._start_move(moves["guard_hit_2"], false)
	await wait_anim_frame("guard_hit_2", 5, 24)
	await save_png(folder + "/12_guard_hit_2.png")

	# 13. guard_hit_3 (f10)
	await reset_actor(1420.0, 0.0, 1)
	p._start_move(moves["guard_hit_3"], false)
	await wait_anim_frame("guard_hit_3", 10, 32)
	await save_png(folder + "/13_guard_hit_3.png")

	# 14. parry_react_1 (f02)
	await reset_actor(1420.0, 0.0, 1)
	p._start_move(moves["parry_react_1"], false)
	await wait_anim_frame("parry_react_1", 2, 20)
	await save_png(folder + "/14_parry_react_1.png")

	# 15. parry_react_2 (f09)
	await reset_actor(1420.0, 0.0, 1)
	p._start_move(moves["parry_react_2"], false)
	await wait_anim_frame("parry_react_2", 9, 30)
	await save_png(folder + "/15_parry_react_2.png")

	# 16. parry_react_3 (f09)
	await reset_actor(1420.0, 0.0, 1)
	p._start_move(moves["parry_react_3"], false)
	await wait_anim_frame("parry_react_3", 9, 30)
	await save_png(folder + "/16_parry_react_3.png")

	# =========================================================================
	# Phase B: 连续录制 300 帧 (5.0s @ 60fps) 全招式雨夜实战连招演武视频
	# =========================================================================
	if OS.get_environment("SKIP_SEQ") != "1":
		var hold_parry := make_frame([&"parry"])
		await reset_actor(1340.0, 0.0, 1)
		record_seq = true
		seq_idx = 0

		# 地面四连：普1 -> 普2 -> 普3 -> 上挑强普
		p._start_move(moves["light_1"], false)
		await tick_n(20)
		p._start_move(moves["light_2"], false)
		await tick_n(20)
		p._start_move(moves["light_3"], false)
		await tick_n(30)
		p._start_move(moves["up_strike"], true)
		await tick_n(26)

		# 空中三连：空1 -> 空2 -> 空3
		p.position.y = stage.floor_y - p.foot_offset - 155.0
		p.velocity = Vector2(20.0, -50.0)
		p._start_move(moves["air_light_1"], false)
		await tick_n(26)
		p.position.y = stage.floor_y - p.foot_offset - 155.0
		p.velocity = Vector2(20.0, -40.0)
		p._start_move(moves["air_light_2"], false)
		await tick_n(22)
		p.position.y = stage.floor_y - p.foot_offset - 150.0
		p.velocity = Vector2(15.0, -30.0)
		p._start_move(moves["air_light_3"], false)
		await tick_n(22)

		# 左右双向冲刺斩
		await reset_actor(1310.0, 0.0, 1)
		p._start_move(moves["dash_slash"], false)
		await tick_n(30)
		await reset_actor(1540.0, 0.0, -1)
		p._start_move(moves["dash_slash_left"], false)
		await tick_n(30)

		# 格挡 -> 格挡受击 -> 弹刀反击 1/2/3
		await reset_actor(1420.0, 0.0, 1)
		p._start_guard(false)
		await tick_n(16, hold_parry)
		p._start_move(moves["guard_hit_1"], false)
		await tick_n(12)
		p._start_move(moves["parry_react_1"], false)
		await tick_n(18)
		p._start_move(moves["parry_react_2"], false)
		await tick_n(22)
		p._start_move(moves["parry_react_3"], false)
		await tick_n(26)

		record_seq = false
	print("R3_ALL_MOVES_SHOWCASE_OK: seq_frames=", seq_idx, " dir=", folder)
	stage.free()
	await process_frame
	quit(0)
