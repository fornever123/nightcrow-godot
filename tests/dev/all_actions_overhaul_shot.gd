extends SceneTree
## 全动作精修前后原生实机同帧对比抓取脚本（配合 --fixed-fps 60 严禁加 --headless，Panku 默认隐藏）。
## 通过环境变量 SHOT_DIR 指定输出目录，USE_BACKUP_ANIMS=1 切换原版动画：
## Phase A) 零掉帧精确锁帧抓拍 17 张代表性动作原生 1280x720 雨夜河岸街关键帧截图（带真实水面反射、雨丝与夜景打光）；
## Phase B) 连续录制 180 帧 (3.0 秒 @ 60fps) 全动作演武序列帧 (seq/f_000.png .. f_179.png)，用于合成同屏对比视频。

const Buffer := preload("res://scripts/core/input_buffer.gd")
const Config := preload("res://scripts/core/configuration.gd")

var stage: Node2D
var p: CharacterBody2D
var view: Sprite2D
var moves: Dictionary
var seq_idx := 0
var seq_dir := ""
var record_seq := false


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
		stage.camera.global_position = Vector2(clampf(p.global_position.x + 45.0, 900.0, 2600.0), stage.CAM_Y)
		await process_frame
		if record_seq and seq_idx < 180:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("%s/f_%03d.png" % [seq_dir, seq_idx])
			seq_idx += 1


func reset_actor(x := 1420.0, y_off := 0.0, facing_dir := 1) -> void:
	p._end_attack()
	p._stop_guard()
	p.hitstop_frames = 0
	p.reset_state(Vector2(x, stage.floor_y - p.foot_offset + y_off))
	p._set_facing(facing_dir)
	view.stance_initialized = true
	view.stance_drawn = true
	view.stance_clip = ""
	stage.camera.global_position = Vector2(x + 45.0, stage.CAM_Y)
	var old_rec := record_seq
	record_seq = false
	await tick_n(2)
	record_seq = old_rec


func wait_anim_frame(expected_clip: String, target_idx: int, max_ticks := 90, held_f: Buffer.Frame = null) -> void:
	if view.clip_name == expected_clip and view.frame_index == target_idx:
		return
	for _i in max_ticks:
		await tick_n(1, held_f)
		if view.clip_name == expected_clip and view.frame_index >= target_idx:
			return


func run() -> void:
	var folder := OS.get_environment("SHOT_DIR")
	if folder.is_empty():
		folder = ProjectSettings.globalize_path("res://.runtime/overhaul_shots")
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

	# 冻结刷怪与横幅干扰，保持纯净雨街光影、积水倒影与雨丝
	stage.set_physics_process(false)
	stage.encounter.set_physics_process(false)
	stage.encounter.set_process(false)
	stage.hud.help_visible = false
	stage.hud._banner = ""
	stage.hud._banner_life = 0.0

	p = stage.player
	view = p.get_node("Visual/ActorSprite")
	var use_backup := OS.get_environment("USE_BACKUP_ANIMS") == "1"
	if use_backup:
		var bpath := ProjectSettings.globalize_path("res://docs/视觉设计/角色动作/全动作精修与张力升级_20261114/backup_animations_before_overhaul.json")
		var btxt := FileAccess.get_file_as_string(bpath)
		var banims = JSON.parse_string(btxt)
		if banims is Dictionary:
			view.setup["animations"] = banims

	# =========================================================================
	# Phase A: 17 张关键帧精确锁帧抓拍 (record_seq = false, 1 tick = 1/60s)
	# =========================================================================
	record_seq = false
	await reset_actor(1400.0, 0.0, 1)

	# 1. 跑步 -> 急停右转左
	await tick_n(12, make_frame([&"move_right"], [], Vector2.RIGHT))
	await wait_anim_frame("turn_right_left", 2, 16, make_frame([&"move_left"], [], Vector2.LEFT))
	await save_png(folder + "/01_turn_right_left.png")

	# 2. 起跳纵向拉伸
	await reset_actor(1400.0, 0.0, 1)
	await tick_n(1, make_frame([&"jump"], [&"jump"], Vector2.RIGHT))
	await wait_anim_frame("jump", 3, 18)
	await save_png(folder + "/02_jump_stretch.png")

	# 3. 空中二段（原全项目最模糊动作 sharp=43 -> 现高清紫月牙）
	p.position.y = stage.floor_y - p.foot_offset - 155.0
	p.velocity = Vector2(40.0, -60.0)
	p._start_move(moves["air_light_2"], false)
	await wait_anim_frame("air_attack_2", 3, 20)
	await save_png(folder + "/03_air_attack_2_slash.png")

	# 4. 空中三段终结大弧 (峰值在 f0)
	p._end_attack()
	p.position.y = stage.floor_y - p.foot_offset - 145.0
	p.velocity = Vector2(30.0, -40.0)
	p._start_move(moves["air_light_3"], false)
	await wait_anim_frame("air_attack_3", 0, 10)
	await save_png(folder + "/04_air_attack_3_finisher.png")

	# 5. 自然下坠与落地缓冲挤压
	p._end_attack()
	for _k in 60:
		if p.is_on_floor():
			break
		await tick_n(1)
	await wait_anim_frame("land", 2, 12)
	await save_png(folder + "/05_land_squash.png")

	# 6. 地面普攻 1 段满月书法弧 (f5)
	await reset_actor(1380.0, 0.0, 1)
	p._start_move(moves["light_1"], false)
	await wait_anim_frame("attack_1", 5, 30)
	await save_png(folder + "/06_attack_1_cleave.png")

	# 7. 地面普攻 2 段突进横扫 (f5)
	await reset_actor(1380.0, 0.0, 1)
	p._start_move(moves["light_2"], false)
	await wait_anim_frame("attack_2", 5, 30)
	await save_png(folder + "/07_attack_2_sweep.png")

	# 8. 地面普攻 3 段终结重劈 (f4)
	await reset_actor(1380.0, 0.0, 1)
	p._start_move(moves["light_3"], false)
	await wait_anim_frame("attack_3", 4, 30)
	await save_png(folder + "/08_attack_3_finisher.png")

	# 9. 上挑重击 (f9)
	await reset_actor(1380.0, 0.0, 1)
	p._start_move(moves["up_strike"], true)
	await wait_anim_frame("attack_up", 9, 34)
	await save_png(folder + "/09_attack_up_launcher.png")

	# 10 & 11. 冲刺斩（AI 破风紫芒楔形流线 f5 + 大弧斩切 f12）
	await reset_actor(1320.0, 0.0, 1)
	p._start_move(moves["dash_slash"], false)
	await wait_anim_frame("dash_right_video", 5, 28)
	await save_png(folder + "/10_dash_slash_wedges.png")
	await wait_anim_frame("dash_right_video", 12, 32)
	await save_png(folder + "/11_dash_slash_cleave.png")

	# 12. 持续格挡呼吸 + 剑脊流光星芒 (直接进入持续防御状态并保持按住 parry)
	await reset_actor(1450.0, 0.0, 1)
	p._start_guard(false)
	var hold_parry := make_frame([&"parry"])
	if use_backup:
		await tick_n(32, hold_parry)
	else:
		await wait_anim_frame("guard_hold", 6, 48, hold_parry)
	await save_png(folder + "/12_guard_hold_shimmer.png")

	# 13 & 14. 弹刀反击 1（f6 交锋星闪 + f8 修复拦腰斩断坏帧）
	await reset_actor(1450.0, 0.0, 1)
	p._start_move(moves["parry_react_1"], false)
	await wait_anim_frame("parry_react_1", 6, 26)
	await save_png(folder + "/13_parry_react_1_clash.png")
	await wait_anim_frame("parry_react_1", 8, 16)
	await save_png(folder + "/14_parry_react_1_repaired_f8.png")

	# 15 & 16. 弹刀反击 3（f6 修复吞身黄块坏帧 + f8 冷紫书法反击弧）
	await reset_actor(1450.0, 0.0, 1)
	p._start_move(moves["parry_react_3"], false)
	await wait_anim_frame("parry_react_3", 6, 26)
	await save_png(folder + "/15_parry_react_3_repaired_f6.png")
	await wait_anim_frame("parry_react_3", 8, 16)
	await save_png(folder + "/16_parry_react_3_counter.png")

	# 17. 满蓄力释放巨弧 (charge_slash f19)
	await reset_actor(1380.0, 0.0, 1)
	p._start_charge()
	p.charge_frames = p.charge_move.max_charge_frames
	p._release_charge()
	await wait_anim_frame("charge_slash", 19, 75)
	await save_png(folder + "/17_charge_slash_release.png")

	# =========================================================================
	# Phase B: 连续录制 180 帧 (3.0s @ 60fps) 雨街实战连招对比视频序列
	# =========================================================================
	await reset_actor(1340.0, 0.0, 1)
	record_seq = true
	seq_idx = 0
	p._start_move(moves["light_1"], false)
	await tick_n(18)
	p._start_move(moves["light_2"], false)
	await tick_n(18)
	p._start_move(moves["light_3"], false)
	await tick_n(24)
	p._start_move(moves["up_strike"], true)
	await tick_n(22)
	p.position.y = stage.floor_y - p.foot_offset - 150.0
	p.velocity = Vector2(30.0, -50.0)
	p._start_move(moves["air_light_2"], false)
	await tick_n(18)
	await reset_actor(1310.0, 0.0, 1)
	p._start_move(moves["dash_slash"], false)
	await tick_n(28)
	await reset_actor(1440.0, 0.0, 1)
	p._start_move(moves["parry_react_1"], false)
	await tick_n(26)
	p._start_move(moves["parry_react_3"], false)
	await tick_n(26)
	record_seq = false

	print("ALL_ACTIONS_CAPTURE_OK: seq_frames=", seq_idx, " dir=", folder)
	stage.free()
	await process_frame
	quit(0)
