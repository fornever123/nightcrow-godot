extends SceneTree
## 12 种高帅度刀光特效样板（D01..D12）+ 原版 + 初版样板 实机雨夜街同帧对比抓取脚本
## 严禁加 --headless，Panku 默认保持隐藏，100% 原生 Forward+ 灯光、暖门洞对比与积水倒影。

const Buffer := preload("res://scripts/core/input_buffer.gd")
const Config := preload("res://scripts/core/configuration.gd")

var stage: Node2D
var p: CharacterBody2D
var view: Sprite2D
var moves: Dictionary


func _initialize() -> void:
	Engine.max_physics_steps_per_frame = 1
	call_deferred("run")


func make_frame() -> Buffer.Frame:
	var f := Buffer.Frame.new()
	f.actions = []
	f.pressed_this_frame = []
	f.axis = Vector2.ZERO
	return f


func save_png(path: String, tag: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("SHOT ", tag, " -> ", path.get_file(), " clip=", view.clip_name, " frame=", view.frame_index)


func tick_n(count: int) -> void:
	var inf := make_frame()
	for _i in count:
		p.set_injected_frame(inf)
		await physics_frame
		stage.camera.global_position = Vector2(clampf(p.global_position.x + 45.0, 900.0, 2600.0), stage.CAM_Y)
		await process_frame


func reset_actor(x := 1410.0) -> void:
	p._end_attack()
	p._stop_guard()
	p.hitstop_frames = 0
	p.reset_state(Vector2(x, stage.floor_y - p.foot_offset))
	p._set_facing(1)
	view.stance_initialized = true
	view.stance_drawn = true
	view.stance_clip = ""
	stage.camera.global_position = Vector2(x + 45.0, stage.CAM_Y)
	await tick_n(2)


func capture_f5_shot(out_path: String, tag: String) -> void:
	await reset_actor(1410.0)
	p._start_move(moves["light_1"], false)
	for _i in 30:
		if view.clip_name == "attack_1" and view.frame_index == 5:
			break
		await tick_n(1)
	await save_png(out_path, tag)


func run() -> void:
	var folder := OS.get_environment("SHOT_DIR")
	if folder.is_empty():
		folder = ProjectSettings.globalize_path("res://.runtime/vfx_12styles_shots")
	DirAccess.make_dir_recursive_absolute(folder)

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

	# 1. 先拍当前 battle.json 里的初版一体重画样板 (pilot f05)
	var pilot_f5: Dictionary = view.setup["animations"]["attack_1"]["frames"][5].duplicate(true)
	await capture_f5_shot(folder + "/00_pilot_f5.png", "PILOT")

	# 2. 拍原始未重画版本 (orig f05)
	var bpath := ProjectSettings.globalize_path("res://docs/视觉设计/角色动作/全动作精修与张力升级_20261114/backup_animations_before_overhaul.json")
	var banims = JSON.parse_string(FileAccess.get_file_as_string(bpath))
	if banims is Dictionary:
		view.setup["animations"]["attack_1"]["frames"][5] = banims["attack_1"]["frames"][5].duplicate(true)
		await capture_f5_shot(folder + "/00_orig_f5.png", "ORIG")

	# 3. 逐一注入 D01..D12 抓拍完全同机位同帧实机画面
	var mpath := ProjectSettings.globalize_path("res://docs/视觉设计/角色动作/特效样板12方向_20261115/manifest_12styles.json")
	var manifest = JSON.parse_string(FileAccess.get_file_as_string(mpath))
	for st in manifest["styles"]:
		var code := String(st["code"])
		var fd := pilot_f5.duplicate(true)
		fd["asset"] = String(st["asset"])
		fd["width"] = float(st["width"])
		fd["height"] = float(st["height"])
		fd["pivotX"] = float(st["pivotX"])
		fd["pivotY"] = float(st["pivotY"])
		view.setup["animations"]["attack_1"]["frames"][5] = fd
		await capture_f5_shot("%s/%s_rain.png" % [folder, code.to_lower()], code)

	# 恢复原样
	view.setup["animations"]["attack_1"]["frames"][5] = pilot_f5
	print("VFX_12STYLES_CAPTURE_OK dir=", folder)
	stage.free()
	await process_frame
	quit(0)
