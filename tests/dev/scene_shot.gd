extends SceneTree
## 开发工具：夜景静帧截图（需要真实渲染：DISPLAY=:99 godot --path . --script res://tests/dev/scene_shot.gd --resolution 1280x720）
## 环境变量 SHOT_DIR（默认 res://.runtime/shots）；XS="300,900,1500" 依次把角色放到这些 x 截图；NOLIGHT=1 关掉角色环境光（对比用）；
## SHADES="-150,160" 在角色左右放静止影卒；FACE=-1 角色朝左；
## POSE="attack_up:10" 定格某招式某帧。
## 第三轮：NOPIX=1 关掉背景像素化（只留退后调色）；NOQ=1 只关调色板量化；RAW=1 背景原样（不退后不像素化）；
## BG=1 只拍背景（藏起角色，算调色板用）。NOPOST=1 关掉光影后期（night_light.gd）。
## 多层地形：三段地形全部预先生成；ONTOP=1 把角色和影卒放到脚下最高的面上（平台 / 石台）。
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
	var pm: ShaderMaterial = stage.backdrop.pixel_mat if stage.backdrop else null
	if pm:
		if OS.get_environment("NOPIX") == "1":
			pm.set_shader_parameter("pixelate", false)
			pm.set_shader_parameter("quantize", false)
		if OS.get_environment("NOQ") == "1":
			pm.set_shader_parameter("quantize", false)
		if OS.get_environment("RAW") == "1":
			stage.backdrop._pix.visible = false
	if OS.get_environment("NOPOST") == "1" and stage.post:   # 光影后期关掉（对比用）
		stage.post.set_enabled(false)
	# POSTP="rays_amt=0.3,contrast=1.2" / PIXP="dim=0.2"：临时改光影后期 / 背景调色的参数（调参用）
	for pair in [["POSTP", stage.post.mat if stage.post else null], ["PIXP", pm]]:
		if pair[1] != null and OS.get_environment(pair[0]) != "":
			for kv in OS.get_environment(pair[0]).split(","):
				var a := kv.split("=")
				pair[1].set_shader_parameter(a[0], float(a[1]))
	if OS.get_environment("BG") == "1":
		p.visible = false
		p.state = p.State.DEAD
		stage.hud.get_parent().visible = false
	if stage.terrain:
		for i in 3:
			stage.terrain.ensure_section(i, stage._center_of(i))
	var ontop := OS.get_environment("ONTOP") == "1" and stage.terrain != null
	var xs := (OS.get_environment("XS") if OS.get_environment("XS") != "" else "300,1000").split(",")
	var idle := Buffer.Frame.new()
	for sx in xs:
		var x := float(sx)
		stage.set_physics_process(false)
		var py: float = stage.terrain.top_at(x, 20.0) if ontop else stage.floor_y
		p.reset_state(Vector2(x, py - p.foot_offset))
		if OS.get_environment("FACE") == "-1":   # FACE=-1：角色朝左
			p._set_facing(-1)
		p.set_injected_frame(idle)
		stage.camera.global_position = Vector2(x, stage.CAM_Y)
		for d in (OS.get_environment("SHADES").split(",") if OS.get_environment("SHADES") != "" else []):
			var sh: Node2D = Node2D.new()   # SHADES="-150,160"：在角色左右这些距离放静止影卒（看光照用）
			sh.set_script(Shade)
			sh.setup(0, p, stage.floor_y, 1.0)
			var sy: float = stage.terrain.top_at(x + float(d), 12.0) if ontop else stage.floor_y
			sh.position = Vector2(x + float(d), sy - 60.0)
			sh.terrain = stage.terrain
			stage.add_child(sh)
			sh.ui_scale = 1.0 / stage.ZOOM
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
