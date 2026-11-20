extends SceneTree
## 即梦 Seedance 2.0 (v2) 主角动作补齐与角色一致性 · 原生 Forward+ 实机抓拍与 60fps 演武录制脚本
## 铁律：严禁加 --headless，保持战斗 HUD 显示，确保 Panku 隐藏，100% 原生 Forward+ 雨夜街画面。

const Buffer := preload("res://scripts/core/input_buffer.gd")
const Config := preload("res://scripts/core/configuration.gd")
const Move := preload("res://scripts/core/move_definition.gd")

var stage: Node2D
var p: CharacterBody2D
var view: Sprite2D
var moves: Dictionary
var seq_idx := 0
var seq_dir := ""
var record_seq := false
const MAX_SEQ_FRAMES := 510


func _initialize() -> void:
	Engine.max_physics_steps_per_frame = 1
	call_deferred("run")


func make_frame(held: Array[StringName] = [], edges: Array[StringName] = [], axis := Vector2.ZERO) -> Buffer.Frame:
	var f := Buffer.Frame.new()
	f.actions = held
	f.pressed_this_frame = edges
	f.axis = axis
	return f


func hide_debug_overlays() -> void:
	for child in root.get_children():
		if String(child.name).to_lower().contains("panku"):
			if "visible" in child:
				child.visible = false
			for sub in child.get_children():
				if sub is CanvasLayer or sub is Control:
					sub.visible = false


func save_png(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("SHOT ", path.get_file(), " -> state=", p.state, " clip=", view.clip_name, " frame=", view.frame_index)


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
	p.invuln_frames = 0
	p.reset_state(Vector2(x, stage.floor_y - p.foot_offset + y_off))
	p.hp = p.max_hp
	p._set_facing(facing_dir)
	view.reset_presentation()
	view.stance_initialized = true
	view.stance_drawn = true
	view.stance_clip = ""
	stage.camera.global_position = Vector2(x + 35.0, stage.CAM_Y)
	var old_rec := record_seq
	record_seq = false
	await tick_n(2)
	record_seq = old_rec


func make_enemy_hit(dmg: float, kx: float, ly: float, force_launch := false) -> Resource:
	var m := Move.new()
	m.id = &"test_enemy_hit"
	m.damage = dmg
	var vec := Vector2(kx, ly)
	m.knockback = vec.length()
	# MoveDefinition.knockback_velocity 用 -sin(rad)，正角度 = 向上击退（对齐 shade.gd 的 14°/24°/58°）
	m.knockback_angle = rad_to_deg(atan2(ly, kx))
	m.forces_launch = force_launch
	m.launch_speed = ly
	m.victim_hitstop_frames = 0
	m.squash = Vector2(0.92, 1.08)
	return m


func wait_anim_frame(expected_clip: String, target_idx: int, max_ticks := 60, held_f: Buffer.Frame = null) -> void:
	if view.clip_name == expected_clip and view.frame_index >= target_idx:
		return
	for _i in max_ticks:
		await tick_n(1, held_f)
		if view.clip_name == expected_clip and view.frame_index >= target_idx:
			return


func run() -> void:
	var folder := OS.get_environment("SHOT_DIR")
	if folder.is_empty():
		folder = ProjectSettings.globalize_path("res://docs/视觉设计/角色动作/动作补齐_即梦v2_20261117/实机验收")
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
	hide_debug_overlays()

	stage.set_physics_process(false)
	stage.encounter.set_physics_process(false)
	stage.encounter.set_process(false)
	stage.hud.help_visible = false
	stage.hud._banner = ""
	stage.hud._banner_life = 0.0

	p = stage.player
	view = p.get_node("Visual/ActorSprite")

	var hit_light := make_enemy_hit(6.0, 165.0, 65.0, false)
	var hit_heavy := make_enemy_hit(12.0, 305.0, 95.0, false)
	var hit_launch := make_enemy_hit(18.0, 290.0, 410.0, true)

	# =========================================================================
	# Phase A: 旧动作基线 + 11 套新动作实机同机位抓拍（验证角色一致性）
	# =========================================================================
	record_seq = false

	# 00a. 旧动作基线 idle
	await reset_actor(1410.0, 0.0, 1)
	await tick_n(4)
	await save_png(folder + "/00_old_idle.png")

	# 00b. 旧动作基线 attack_1 (R3)
	await reset_actor(1410.0, 0.0, 1)
	p._start_move(moves["light_1"], false)
	await wait_anim_frame("attack_1", 5, 25)
	await save_png(folder + "/00_old_attack1.png")

	# 01. hurt_light
	await reset_actor(1410.0, 0.0, 1)
	p.take_hit(hit_light, -1, p.global_position)
	await wait_anim_frame("hurt_light", 2, 20)
	await save_png(folder + "/01_after_hurt_light.png")

	# 02. hurt_heavy
	await reset_actor(1440.0, 0.0, 1)
	p.take_hit(hit_heavy, -1, p.global_position)
	await wait_anim_frame("hurt_heavy", 4, 24)
	await save_png(folder + "/02_after_hurt_heavy.png")

	# 03. hurt_launch -> 04. down -> 05. getup
	await reset_actor(1460.0, 0.0, 1)
	p.take_hit(hit_launch, -1, p.global_position)
	await wait_anim_frame("hurt_launch", 4, 24)
	await save_png(folder + "/03_after_hurt_launch.png")
	for _k in 90:
		await tick_n(1)
		if p.state == p.State.DOWN:
			break
	await tick_n(3)
	await save_png(folder + "/04_after_down.png")
	for _k in 30:
		await tick_n(1)
		if view.clip_name == "getup" and view.frame_index >= 4:
			break
	await save_png(folder + "/05_after_getup.png")

	# 06. ranged_cast (空翻蓄势 + 新月斩发波)
	await reset_actor(1380.0, 0.0, 1)
	p._start_move(moves["ranged_1"], false)
	await wait_anim_frame("ranged_cast", 2, 20)
	await save_png(folder + "/06a_after_ranged_flip.png")
	await wait_anim_frame("ranged_cast", 7, 25)
	await save_png(folder + "/06b_after_ranged_slash.png")

	# 07. air_plunge_slam (空中双手举剑急坠 + 触地满月劈地插剑)
	await reset_actor(1410.0, -190.0, 1)
	p.finisher_intent = &"slam"
	p.velocity = Vector2(30.0, 520.0)
	p._start_move(moves["air_plunge"], false)
	await tick_n(4)
	await save_png(folder + "/07a_after_plunge_dive.png")
	for _k in 40:
		await tick_n(1)
		if p.is_on_floor():
			break
	await tick_n(2)
	await save_png(folder + "/07b_after_plunge_slam.png")

	# 08. attack_1_settle
	await reset_actor(1410.0, 0.0, 1)
	p._start_move(moves["light_1"], false)
	for _k in 45:
		await tick_n(1)
		if view.clip_name == "attack_1_settle" and view.frame_index >= 3:
			break
	await save_png(folder + "/08_after_attack1_settle.png")

	# 09. attack_2_settle
	await reset_actor(1410.0, 0.0, 1)
	p._start_move(moves["light_2"], false)
	for _k in 45:
		await tick_n(1)
		if view.clip_name == "attack_2_settle" and view.frame_index >= 4:
			break
	await save_png(folder + "/09_after_attack2_settle.png")

	# 10. run_stop
	await reset_actor(1300.0, 0.0, 1)
	await tick_n(14, make_frame([&"move_right"], [], Vector2.RIGHT))
	for _k in 15:
		await tick_n(1)
		if view.clip_name == "run_stop" and view.frame_index >= 2:
			break
	await save_png(folder + "/10_after_run_stop.png")

	# 11. guard_hold
	await reset_actor(1410.0, 0.0, 1)
	await tick_n(1, make_frame([&"parry"], [&"parry"]))
	await tick_n(26, make_frame([&"parry"]))
	await save_png(folder + "/11_after_guard_hold.png")

	# =========================================================================
	# Phase B: 改前 (Before) 同机位同物理帧真实对照抓拍
	# =========================================================================
	var full_anims: Dictionary = view.setup.animations.duplicate(true)
	var new_keys := [
		"hurt_light", "hurt_heavy", "hurt_launch", "down", "getup",
		"ranged_cast", "air_plunge_slam", "attack_1_settle", "attack_2_settle", "run_stop"
	]
	for nk in new_keys:
		view.setup.animations.erase(nk)

	# Before 01: 轻受击（旧版无受击帧，挨刀直接播普通起跳 jump）
	await reset_actor(1410.0, 0.0, 1)
	p.take_hit(hit_light, -1, p.global_position)
	await tick_n(3)
	await save_png(folder + "/before_01_hurt_light.png")

	# Before 02: 重受击（旧版无受击帧，被击退时播普通下落 fall）
	await reset_actor(1440.0, 0.0, 1)
	p.take_hit(hit_heavy, -1, p.global_position)
	await tick_n(8)
	await save_png(folder + "/before_02_hurt_heavy.png")

	# Before 04: 倒地 DOWN（旧版把站立 idle 压扁成 1.25x0.72 矮胖纸片）
	await reset_actor(1460.0, 0.0, 1)
	p.take_hit(hit_launch, -1, p.global_position)
	for _k in 90:
		await tick_n(1)
		if p.state == p.State.DOWN:
			break
	await tick_n(3)
	await save_png(folder + "/before_04_down_squished_idle.png")

	# Before 06: K 远程剑气（旧版直接照搬普通 J 键 attack_1 斜劈）
	await reset_actor(1380.0, 0.0, 1)
	p._start_move(moves["ranged_1"], false)
	await tick_n(15)
	await save_png(folder + "/before_06_ranged_reused_attack1.png")

	# Before 07: 空中 S+J 急坠下劈（旧版直接复用空中斜挥 air_slash/air_attack_1）
	await reset_actor(1410.0, -190.0, 1)
	p.finisher_intent = &"slam"
	p.velocity = Vector2(30.0, 520.0)
	p._start_move(moves["air_plunge"], false)
	for _k in 40:
		await tick_n(1)
		if p.is_on_floor():
			break
	await tick_n(2)
	await save_png(folder + "/before_07_plunge_reused_air1.png")

	# Before 10: 跑步松键急停（旧版无刹步，直接硬切 idle）
	await reset_actor(1300.0, 0.0, 1)
	await tick_n(14, make_frame([&"move_right"], [], Vector2.RIGHT))
	await tick_n(7)
	await save_png(folder + "/before_10_run_hardcut_idle.png")

	# 恢复全量新动画以录制连贯 60fps 实战演武
	view.setup.animations = full_anims

	# =========================================================================
	# Phase C: 一镜到底 60fps 新旧动作无缝混编实战演武（证明 100% 同一角色）
	# =========================================================================
	await reset_actor(1180.0, 0.0, 1)
	record_seq = true
	seq_idx = 0

	# 1) 待机(旧) -> 奔跑(旧) -> 松键自然急停刹步 run_stop(新) -> 待机
	await tick_n(16)
	await tick_n(26, make_frame([&"move_right"], [], Vector2.RIGHT))
	await tick_n(22)

	# 2) 普攻1段(旧·R3) -> 普攻1收招 attack_1_settle(新)
	p._start_move(moves["light_1"], false)
	await tick_n(44)

	# 3) 普攻1 -> 普攻2(旧·R3) -> 普攻2收招 attack_2_settle(新)
	p._start_move(moves["light_1"], false)
	await tick_n(18)
	p._start_move(moves["light_2"], false)
	await tick_n(46)

	# 4) K 键远程空翻新月剑气 ranged_cast(新) + 真实飞行剑气波
	p.ranged_cooldown = 0
	await tick_n(1, make_frame([&"attack_ranged"], [&"attack_ranged"]))
	await tick_n(44)

	# 5) 起跳 jump(旧) -> 空中 S+J 急坠竖劈跪地插剑 air_plunge_slam(新)
	await tick_n(1, make_frame([&"jump"], [&"jump"]))
	await tick_n(16, make_frame([&"jump"]))
	p.finisher_intent = &"slam"
	p.velocity = Vector2(35.0, 540.0)
	p._start_move(moves["air_plunge"], false)
	await tick_n(44)

	# 6) 持刀格挡呼吸 guard_hold(新)
	await tick_n(1, make_frame([&"parry"], [&"parry"]))
	await tick_n(36, make_frame([&"parry"]))
	await tick_n(4)

	# 7) 实战吃轻刀 hurt_light(新) -> 吃重刀犁地 hurt_heavy(新)
	p.invuln_frames = 0
	p.take_hit(hit_light, -1, p.global_position)
	await tick_n(24)
	p.invuln_frames = 0
	p.take_hit(hit_heavy, -1, p.global_position)
	await tick_n(30)

	# 8) 实战吃重挑飞 hurt_launch(新) -> 倒地 down(新) -> 单膝拄剑起身 getup(新) -> R3 终结斩收尾(旧)
	p.invuln_frames = 0
	p.take_hit(hit_launch, -1, p.global_position)
	for _k in 95:
		await tick_n(1)
		if p.state == p.State.NEUTRAL and p.is_on_floor():
			break
	await tick_n(6)
	p._start_move(moves["light_3"], false)
	await tick_n(36)

	record_seq = false
	print("SUPPLEMENT_V2_SHOWCASE_OK: seq_frames=", seq_idx, " dir=", folder)
	stage.free()
	await process_frame
	quit(0)
