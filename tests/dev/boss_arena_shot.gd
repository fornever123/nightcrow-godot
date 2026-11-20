extends SceneTree
## 开发工具：Boss 单屏决斗台截图（不加 --headless）。镜头在左 / 中 / 右各一张，再截一张二阶段。
##   engine/Godot_v4.7.2-stable_win64_console.exe --fixed-fps 60 --path . --script res://tests/dev/boss_arena_shot.gd
const Scene := preload("res://scripts/boss_sample/boss_sample.gd")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var stage = Scene.new()
	root.add_child(stage)
	await process_frame
	var d := OS.get_environment("SHOT_DIR")
	if d == "":
		d = ProjectSettings.globalize_path("res://.runtime/arena")
	DirAccess.make_dir_recursive_absolute(d)
	var boss = stage.boss
	var p = stage.player
	boss.skip_intro()
	boss.active = false
	stage.hud.banner("", "", 0.01)
	var half: float = stage.FIGHT_HALF
	for spot: Array in [["l", -half * 0.7], ["m", 0.0], ["r", half * 0.7]]:
		await _shot(stage, float(spot[1]), d + "/p1_%s.png" % spot[0])
	if stage.backdrop != null and stage.backdrop.has_method(&"trigger_phase2_shatter"):
		stage.backdrop.trigger_phase2_shatter()
		for f in 90:
			await physics_frame
		await _shot(stage, 0.0, d + "/p2_m.png")
	quit()


func _shot(stage, off: float, path: String) -> void:
	var boss = stage.boss
	var p = stage.player
	var x: float = stage.arena_center + off
	p.reset_state(Vector2(x - 220.0, stage.floor_y - p.foot_offset))
	boss.position = Vector2(x + 220.0, boss.ground_y())
	boss.facing = -1
	p._set_facing(1)
	stage.camera.global_position = Vector2(x, stage.camera.lock_y)
	for f in 40:
		await physics_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(path)
	print("SHOT ", path)
