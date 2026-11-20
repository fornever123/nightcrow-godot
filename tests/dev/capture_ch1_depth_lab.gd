extends SceneTree
## 大纵深双路线实机评测脚本（原生 Forward+ 窗口，严禁 --headless！）
## 用法：
##   $env:DEPTH_LAB_MODE="base" | "r1" | "r2"
##   .\engine\Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/dev/capture_ch1_depth_lab.gd

const TRIAL_SCENE := "res://scenes/rain_trial.tscn"
const R1Script := preload("res://scripts/night/ch1_depth_lab/depth_r1_2d.gd")
const R2Script := preload("res://scripts/night/ch1_depth_lab/depth_r2_hd2d.gd")


func _initialize() -> void:
	call_deferred("_run")


func _hide_debug_overlays() -> void:
	for child in root.get_children():
		var nm := String(child.name)
		if nm.begins_with("Panku") or nm.to_lower().contains("panku") or nm.to_lower().contains("console"):
			if child is CanvasLayer:
				child.visible = false
			for sub in child.get_children():
				if sub is CanvasItem or sub is CanvasLayer:
					sub.visible = false


func _wait_frames(n: int) -> void:
	for _i in n:
		await physics_frame
		await process_frame


func _save_shot(full_path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(full_path)


func _run() -> void:
	var mode := OS.get_environment("DEPTH_LAB_MODE").to_lower()
	if mode == "":
		mode = "r1"
	var base_out := ProjectSettings.globalize_path("res://docs/_当前分支草稿/背景线/大纵深重构_20261118/实机_" + mode)
	DirAccess.make_dir_recursive_absolute(base_out)
	var walk_dir := base_out.path_join("walk_frames")
	DirAccess.make_dir_recursive_absolute(walk_dir)

	var stage: Node = load(TRIAL_SCENE).instantiate()
	stage.set_meta("ch1_shadow_street", true)
	stage.set_meta("ch1_slot0_code", "1-1A")
	root.add_child(stage)
	current_scene = stage
	_hide_debug_overlays()
	await _wait_frames(8)
	_hide_debug_overlays()

	if stage.has_method("_on_wanxiang_opening_confirmed"):
		stage.call("_on_wanxiang_opening_confirmed", "core_rift", "talent_free_roll")
	else:
		paused = false

	if stage.hud != null:
		stage.hud.help_visible = false
		if "_banner_t" in stage.hud:
			stage.hud._banner_t = 0.0
			stage.hud.queue_redraw()
	for hk in [&"move", &"floors", &"drop", &"parry", &"knockback", &"brute", &"archer", &"bomber", &"blast", &"air", &"chain", &"guard", &"ult"]:
		stage._hints_done[hk] = true
	stage._hint_queue.clear()

	# 关掉封印刷怪，纯粹评测实机场景画面与走动立体感
	stage.encounter.clear_shades()
	stage.encounter.running = false
	stage._unlock_arena()
	stage.phase = stage.Phase.EXPLORE
	stage.encounter_index = 99

	# 若为 R1 / R2 模式，隐藏旧背景层（保留实时雨滴、主角、HUD 与灯光系统），挂上全新样板节点
	if mode == "r1" or mode == "r2":
		if stage.backdrop != null:
			if stage.backdrop.get("_layered") != null:
				stage.backdrop.get("_layered").visible = false
			if stage.backdrop.get("_water") != null:
				stage.backdrop.get("_water").visible = false
			if stage.backdrop.get("_ground") != null:
				stage.backdrop.get("_ground").visible = false
			if stage.backdrop.get("_fog_near") != null:
				stage.backdrop.get("_fog_near").visible = false
			if stage.backdrop.get("_soft_glow") != null:
				stage.backdrop.get("_soft_glow").visible = false
			if stage.backdrop.get("_ledge_wet") != null:
				stage.backdrop.get("_ledge_wet").visible = false
		# 去掉旧夜色后期偏蓝滤镜（色调 3 中性微暖）
		if stage.post != null and stage.post.get("mat") != null:
			var pm: ShaderMaterial = stage.post.get("mat")
			pm.set_shader_parameter("grade_amt", 0.0)
			pm.set_shader_parameter("vig_bottom", 0.04)
			pm.set_shader_parameter("bloom_amt", 0.42)
			pm.set_shader_parameter("bloom_th", 0.62)

		var lab: Node2D = R1Script.new() if mode == "r1" else R2Script.new()
		lab.call("setup", stage.camera, stage.player)
		stage.add_child(lab)

	var p: CharacterBody2D = stage.player
	var cam_y: float = stage._cam_y_for(stage.floor_y)

	# 1. 三个典型机位静帧截图（x2800 / x3500 / x4200）
	for x_pos in [2800.0, 3500.0, 4200.0]:
		p.reset_state(Vector2(x_pos, stage.floor_y - p.foot_offset))
		stage.camera.global_position = Vector2(x_pos, cam_y)
		await _wait_frames(12)
		await _save_shot(base_out.path_join("x%04d.png" % int(x_pos)))

	# 2. 72 帧实机横向走动录像帧（x = 2650 -> 4450，每帧前进 25 世界单位，充分展示视差、桥洞深渊与 3D 透视！）
	var total_f := 72
	for fi in total_f:
		var u := float(fi) / float(total_f - 1)
		var x_now := lerpf(2650.0, 4450.0, u)
		p.global_position = Vector2(x_now, stage.floor_y - p.foot_offset)
		p.velocity = Vector2(460.0, 0.0)
		stage.camera.global_position = Vector2(x_now, cam_y)
		await process_frame
		await _save_shot(walk_dir.path_join("f_%03d.png" % fi))

	print("DEPTH_LAB_CAPTURE_DONE:", mode, "->", base_out)
	stage.queue_free()
	await _wait_frames(3)
	quit()
