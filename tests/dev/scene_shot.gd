extends SceneTree
## 开发工具：夜景静帧截图（需要真实渲染：DISPLAY=:99 godot --path . --script res://tests/dev/scene_shot.gd --resolution 1280x720）
## 环境变量 SHOT_DIR（默认 res://.runtime/shots）；XS="300,900,1500" 依次把角色放到这些 x 截图；NOLIGHT=1 关掉角色环境光（对比用）；
## SHADES="-150,160" 在角色左右放静止影卒；FACE=-1 角色朝左；
## POSE="attack_up:10" 定格某招式某帧。
const Buffer := preload("res://scripts/core/input_buffer.gd")
const Shade := preload("res://scripts/night/shade.gd")
const Art := preload("res://scripts/presentation/art_cache.gd")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var dir := OS.get_environment("SHOT_DIR")
	if dir == "":
		dir = ProjectSettings.globalize_path("res://.runtime/shots")
	DirAccess.make_dir_recursive_absolute(dir)
	var stage = load("res://scenes/night_trial.tscn").instantiate()
	root.add_child(stage)
	await process_frame
	if OS.get_environment("NOLIGHT") == "1":   # 对比用：关掉角色环境光
		stage.light_mat = null
		stage.player.get_node("Visual/ActorSprite").material = null
	var p = stage.player
	var xs := (OS.get_environment("XS") if OS.get_environment("XS") != "" else "300,1000").split(",")
	var idle := Buffer.Frame.new()
	for sx in xs:
		var x := float(sx)
		stage.set_physics_process(false)
		p.reset_state(Vector2(x, stage.floor_y - p.foot_offset))
		if OS.get_environment("FACE") == "-1":   # FACE=-1：角色朝左
			p._set_facing(-1)
		p.set_injected_frame(idle)
		stage.camera.global_position = Vector2(x, 360)
		for d in (OS.get_environment("SHADES").split(",") if OS.get_environment("SHADES") != "" else []):
			var sh: Node2D = Node2D.new()   # SHADES="-150,160"：在角色左右这些距离放静止影卒（看光照用）
			sh.set_script(Shade)
			sh.setup(0, p, stage.floor_y, 1.0)
			sh.position = Vector2(x + float(d), stage.floor_y - 60.0)
			stage.add_child(sh)
			sh.spawn_frames = 0
			sh.active = false
		for i in 40:
			await process_frame
		if OS.get_environment("POSE") != "":   # POSE="attack_up:10"：把角色定格在某个招式的某一帧
			var parts := OS.get_environment("POSE").split(":")
			var view: Sprite2D = p.get_node("Visual/ActorSprite")
			var setup: Dictionary = view.setup
			view.set_physics_process(false)
			Art.apply(view, setup.animations[parts[0]].frames[int(parts[1])], float(setup.get("displayScale", 1.0)))
			view.scale.x *= float(setup.animations[parts[0]].get("sourceFacing", 1))
			await process_frame
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_viewport().get_texture().get_image().save_png("%s/scene_x%d.png" % [dir, int(x)])
		print("shot ", x)
	quit()
