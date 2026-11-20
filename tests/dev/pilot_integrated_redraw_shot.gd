extends SceneTree
## 原帧 1:1 角色+高颜值特效一体重画样板（attack_1 全 13 帧 + parry_react_1 全 16 帧）实机同帧对比抓取脚本
## 严禁加 --headless，Panku 默认保持隐藏，100% 原生 Forward+ 雨夜光影与水面反射。

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
		if record_seq and seq_idx < 96:
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


func wait_anim_frame(expected_clip: String, target_idx: int, max_ticks := 90) -> void:
	if view.clip_name == expected_clip and view.frame_index == target_idx:
		return
	for _i in max_ticks:
		await tick_n(1)
		if view.clip_name == expected_clip and view.frame_index >= target_idx:
			return


func run() -> void:
	var folder := OS.get_environment("SHOT_DIR")
	if folder.is_empty():
		folder = ProjectSettings.globalize_path("res://.runtime/pilot_redraw_shots")
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
	var use_backup := OS.get_environment("USE_BACKUP_ANIMS") == "1"
	if use_backup:
		var bpath := ProjectSettings.globalize_path("res://docs/视觉设计/角色动作/全动作精修与张力升级_20261114/backup_animations_before_overhaul.json")
		var btxt := FileAccess.get_file_as_string(bpath)
		var banims = JSON.parse_string(btxt)
		if banims is Dictionary:
			view.setup["animations"] = banims

	# 1. 普攻1段 (attack_1: f4 起势钩光 -> f5 爆发大满月 -> f6 飞白满月 -> f7 弯钩消散 -> f10 低姿收剑)
	await reset_actor(1410.0, 0.0, 1)
	p._start_move(moves["light_1"], false)
	await wait_anim_frame("attack_1", 4, 20)
	await save_png(folder + "/01_attack1_f4_windup.png")
	await wait_anim_frame("attack_1", 5, 10)
	await save_png(folder + "/02_attack1_f5_slash_peak.png")
	await wait_anim_frame("attack_1", 6, 10)
	await save_png(folder + "/03_attack1_f6_slash_split.png")
	await wait_anim_frame("attack_1", 7, 10)
	await save_png(folder + "/04_attack1_f7_slash_tail.png")
	await wait_anim_frame("attack_1", 10, 14)
	await save_png(folder + "/05_attack1_f10_follow.png")

	# 2. 弹刀1 (parry_react_1: f2 刀光反击 -> f6 迎刃格架 -> f8 修复半身坏帧 -> f9 修复断腰+甩剑残弧 -> f12 亮剑定势)
	await reset_actor(1440.0, 0.0, 1)
	p._start_move(moves["parry_react_1"], false)
	await wait_anim_frame("parry_react_1", 2, 16)
	await save_png(folder + "/06_parry1_f2_slash.png")
	await wait_anim_frame("parry_react_1", 6, 16)
	await save_png(folder + "/07_parry1_f6_clash.png")
	await wait_anim_frame("parry_react_1", 8, 16)
	await save_png(folder + "/08_parry1_f8_repaired.png")
	await wait_anim_frame("parry_react_1", 9, 12)
	await save_png(folder + "/09_parry1_f9_repaired_arc.png")
	await wait_anim_frame("parry_react_1", 12, 16)
	await save_png(folder + "/10_parry1_f12_pose.png")

	# 3. 连续 90 帧 60fps 演武录制（普攻1段 -> 弹刀1 全流程）
	await reset_actor(1390.0, 0.0, 1)
	record_seq = true
	seq_idx = 0
	p._start_move(moves["light_1"], false)
	await tick_n(38)
	await tick_n(6)
	p._start_move(moves["parry_react_1"], false)
	await tick_n(48)
	record_seq = false

	print("PILOT_CAPTURE_OK: seq_frames=", seq_idx, " dir=", folder)
	stage.free()
	await process_frame
	quit(0)
