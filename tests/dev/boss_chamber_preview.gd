extends SceneTree
## 开发工具：把「钟室」整屏样板临时塞进 Boss 小样当背景，按实机比例截图（不加 --headless，不改游戏文件）。
##   engine/Godot_v4.7.2-stable_win64_console.exe --fixed-fps 60 --path . --script res://tests/dev/boss_chamber_preview.gd
## 环境变量：SAMPLE（样板图绝对路径）、SHOT_DIR、STAND_ROW（样板里人站的那一行，默认 760）、SCALE（默认 1.22）、CAM_UP（镜头上移，默认 55）
const Scene := preload("res://scripts/boss_sample/boss_sample.gd")


func _initialize() -> void:
	call_deferred("run")


func _env_f(k: String, dflt: float) -> float:
	var v := OS.get_environment(k)
	return float(v) if v != "" else dflt


func run() -> void:
	var stage = Scene.new()
	root.add_child(stage)
	await process_frame
	var d := OS.get_environment("SHOT_DIR")
	if d == "":
		d = ProjectSettings.globalize_path("res://.runtime/arena/chamber")
	DirAccess.make_dir_recursive_absolute(d)
	var img := Image.load_from_file(OS.get_environment("SAMPLE"))
	var tex := ImageTexture.create_from_image(img)
	var clear := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	var clear_tex := ImageTexture.create_from_image(clear)

	var bd = stage.backdrop
	bd._tex_far = clear_tex
	bd._tex_causeway = clear_tex
	bd._tex_pillar_l = clear_tex
	bd._tex_pillar_r = clear_tex
	bd._clock_canvas.visible = false
	bd._suspended_drops.clear()
	bd._water.visible = false
	var s := _env_f("SCALE", 1.22)
	var stand := _env_f("STAND_ROW", 760.0)
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.centered = false
	spr.scale = Vector2(s, s)
	spr.position = Vector2(stage.arena_center - img.get_width() * s * 0.5, stage.floor_y - stand * s)
	bd._sky.add_child(spr)

	var boss = stage.boss
	var p = stage.player
	boss.skip_intro()
	boss.active = false
	stage.hud.banner("", "", 0.01)
	stage.camera.lock_y -= _env_f("CAM_UP", 55.0)
	await _shot(stage, 0.0, 0.0, d + "/ground.png")
	await _shot(stage, 0.0, -330.0, d + "/air.png")
	await _shot(stage, 200.0, 0.0, d + "/right.png")
	quit()


func _shot(stage, off: float, boss_up: float, path: String) -> void:
	var boss = stage.boss
	var p = stage.player
	var x: float = stage.arena_center + off
	p.reset_state(Vector2(x - 240.0, stage.floor_y - p.foot_offset))
	boss.position = Vector2(x + 240.0, boss.ground_y() + boss_up)
	boss.facing = -1
	p._set_facing(1)
	stage.camera.global_position = Vector2(x, stage.camera.lock_y)
	for f in 40:
		if boss_up != 0.0:
			boss.position.y = boss.ground_y() + boss_up
			boss.velocity = Vector2.ZERO
		await physics_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(path)
	print("SHOT ", path)
