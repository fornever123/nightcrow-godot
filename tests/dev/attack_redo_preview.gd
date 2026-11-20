extends SceneTree
## 开发工具（普攻重做 11-06）：不改 battle.json，只在内存里把 attack_1 换成新姿势，录第一刀逐帧截图做对比。
## 需要真实渲染（不加 --headless）：engine/Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/dev/attack_redo_preview.gd --resolution 1280x720 --fixed-fps 60
## 环境变量：SHOT_DIR 截图目录；NEW_DIR 切图目录（p1.png…），不设就录现有动作；POSE_H 新姿势在世界里的身高（像素，默认 169，和旧第一刀第 1 帧相同）。
## TORSO 是每个姿势躯干中心相对切图左边的 x，FRAMES 是 13 帧分别用哪个姿势（第 5～7 帧是判定帧）。
const Art := preload("res://scripts/presentation/art_cache.gd")
const Buffer := preload("res://scripts/core/input_buffer.gd")
const Shade := preload("res://scripts/night/shade.gd")
const TORSO := {"p1": 245.0, "p2": 197.0, "p3": 230.0, "p4": 196.0}
const FRAMES := ["p1", "p1", "p1", "p1", "p1", "p2", "p3", "p3", "p3", "p3", "p4", "p4", "p4"]
var stage
var p
var c0 := 0.0
var dir := ""


func _initialize() -> void:
	call_deferred("run")


func fr(actions: Array[StringName] = [], edges: Array[StringName] = []) -> Buffer.Frame:
	var f := Buffer.Frame.new()
	f.actions = actions
	f.pressed_this_frame = edges
	f.axis = Vector2.ZERO
	return f


func frames(n: int, f: Buffer.Frame = null) -> void:
	for i in n:
		p.set_injected_frame(f if f != null else fr())
		await physics_frame


func swap_in(new_dir: String) -> void:
	var sprite: Dictionary = p.get_meta("character").sprite
	var clip: Dictionary = sprite.animations.attack_1
	var world_h := float(OS.get_environment("POSE_H")) if OS.has_environment("POSE_H") else 169.0
	var scale_to_authored := 0.0
	var built := {}
	for key in TORSO:
		var img := Image.load_from_file("%s/%s.png" % [new_dir, key])
		img.convert(Image.FORMAT_RGBA8)
		if key == "p1":
			scale_to_authored = world_h / float(sprite.displayScale) / img.get_height()
		var w := img.get_width() * scale_to_authored
		var h := img.get_height() * scale_to_authored
		if Art.premultiply:
			img.premultiply_alpha()
		Art.textures["__redo/" + key] = ImageTexture.create_from_image(img)
		built[key] = {"asset": "__redo/" + key, "width": w, "height": h, "pivotX": TORSO[key] * scale_to_authored, "pivotY": h, "durationTicks": 1}
	var list: Array = []
	for key in FRAMES:
		list.append(built[key].duplicate())
	clip.frames = list
	clip.rootMotionX = 0


func run() -> void:
	dir = OS.get_environment("SHOT_DIR")
	DirAccess.make_dir_recursive_absolute(dir)
	stage = load("res://scenes/rain_street.tscn").instantiate()
	root.add_child(stage)
	await process_frame
	p = stage.player
	stage.hud.help_visible = false
	stage.hud._banner = ""
	stage.hud._banner_life = 0.0
	await frames(30)
	if OS.has_environment("NEW_DIR"):
		swap_in(OS.get_environment("NEW_DIR"))
	c0 = stage._center_of(0)
	p.reset_state(Vector2(c0 - 1900.0, stage.floor_y - p.foot_offset))
	await frames(90, fr([&"move_right"]))
	stage.encounter.clear_shades()
	stage.encounter.running = false
	p.reset_state(Vector2(c0 - 1180.0, 580.0 - p.foot_offset))
	p._set_facing(1)
	await frames(40)
	stage.fx.rng.seed = 7
	for x in [-1040.0, -990.0]:
		var sh: Node2D = Node2D.new()
		sh.set_script(Shade)
		sh.setup(Shade.Kind.GRUNT, p, stage.floor_y, 1.0)
		sh.position = Vector2(c0 + x, 580.0 - 60.0)
		sh.terrain = stage.terrain
		stage.add_child(sh)
		sh.spawn_frames = 0
		sh.active = false
		sh.facing = -1
		stage._on_shade_spawned(sh)
	await frames(10)
	var J: StringName = &"attack_light"
	var k := 0
	var feet: Vector2 = p.get_global_transform_with_canvas().origin
	print("SCREEN_POS ", feet)
	p.set_injected_frame(fr([J], [J]))
	for i in 50:
		await physics_frame
		p.set_injected_frame(fr())
		await RenderingServer.frame_post_draw
		root.get_viewport().get_texture().get_image().save_png("%s/f_%03d.png" % [dir, k])
		k += 1
	print("DONE ", k)
	quit()
