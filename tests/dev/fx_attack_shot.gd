extends SceneTree
## 开发工具（光线 / 特效会话 10-31）：攻击特效现状截图。雨街钟楼广场左半，普通三连 / 冲刺斩 / 挑飞 / 蓄力逐帧，再直接触发弹刀 / 格挡 / 击杀 / 挨打。
## 需要真实渲染（不加 --headless）：engine/Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/dev/fx_attack_shot.gd --resolution 1280x720 --fixed-fps 60
## 截图目录：环境变量 SHOT_DIR。
const Buffer := preload("res://scripts/core/input_buffer.gd")
const Shade := preload("res://scripts/night/shade.gd")
var stage
var p
var c0 := 0.0
var dir := ""


func _initialize() -> void:
	call_deferred("run")


func fr(actions: Array[StringName] = [], edges: Array[StringName] = [], axis := Vector2.ZERO) -> Buffer.Frame:
	var f := Buffer.Frame.new()
	f.actions = actions
	f.pressed_this_frame = edges
	f.axis = axis
	return f


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, name])
	print("SHOT ", name)


func frames(n: int, f: Buffer.Frame = null) -> void:
	for i in n:
		p.set_injected_frame(f if f != null else fr())
		await physics_frame


func place(x: float, feet: float, facing: int = 1, settle: int = 40) -> void:
	stage.encounter.clear_shades()
	stage.encounter.running = false
	p.reset_state(Vector2(c0 + x, feet - p.foot_offset))
	p._set_facing(facing)
	await frames(settle)


func shade(kind: int, x: float, feet: float, facing: int) -> Node2D:
	var sh: Node2D = Node2D.new()
	sh.set_script(Shade)
	sh.setup(kind, p, stage.floor_y, 1.0)
	sh.position = Vector2(c0 + x, feet - 60.0)
	sh.terrain = stage.terrain
	stage.add_child(sh)
	sh.spawn_frames = 0
	sh.active = false
	sh.facing = facing
	stage._on_shade_spawned(sh)
	return sh


## 按一次 edges，然后每隔 step 帧截一张，共 n 张
func strike(tag: String, held: Array[StringName], edges: Array[StringName], n: int, step: int, axis := Vector2.ZERO) -> void:
	await place(-1180, 580, 1)
	stage.fx.rng.seed = 7
	shade(Shade.Kind.GRUNT, -1100, 580, -1)
	shade(Shade.Kind.GRUNT, -1050, 580, -1)
	await frames(20)
	await frames(1, fr(held, edges, axis))
	for i in n:
		await frames(step)
		await shot("%s_%02d" % [tag, i])


func run() -> void:
	dir = OS.get_environment("SHOT_DIR")
	DirAccess.make_dir_recursive_absolute(dir)
	stage = load("res://scenes/rain_street.tscn").instantiate()
	root.add_child(stage)
	await process_frame
	p = stage.player
	stage.hud.help_visible = false
	stage.fx.debug_variant = 0
	await frames(30)
	c0 = stage._center_of(0)
	p.reset_state(Vector2(c0 - 1900.0, stage.floor_y - p.foot_offset))
	await frames(90, fr([&"move_right"], [], Vector2(1, 0)))
	stage.hud._banner = ""
	stage.hud._banner_life = 0.0
	var J: StringName = &"attack_light"

	# 普通三连（连续截）
	await place(-1180, 580, 1)
	stage.fx.rng.seed = 7
	shade(Shade.Kind.GRUNT, -1100, 580, -1)
	shade(Shade.Kind.GRUNT, -1050, 580, -1)
	await frames(20)
	var k := 0
	for hit in 3:
		await frames(1, fr([J], [J]))
		for i in 6:
			await frames(2)
			await shot("light_%02d" % k)
			k += 1
		await frames(2)
	# 冲刺斩
	await strike("dash", [&"dash_modifier", J], [&"dash_modifier", J], 8, 2)
	# 挑飞
	await strike("up", [&"aim_up", J], [&"aim_up", J], 6, 2)
	# 蓄力斩：按住 46 帧再放
	await place(-1180, 580, 1)
	shade(Shade.Kind.GRUNT, -1100, 580, -1)
	await frames(20)
	await frames(1, fr([J], [J]))
	for i in 46:
		p.set_injected_frame(fr([J], []))
		await physics_frame
		if i == 30:
			await shot("charge_hold")
	for i in 8:
		await frames(2)
		await shot("charge_%02d" % i)
	# 事件特效（直接调）
	await place(-1180, 580, 1)
	var pt: Vector2 = p.global_position + Vector2(60, -40)
	for ev in ["parry", "block", "kill", "hurt", "slam"]:
		match ev:
			"slam": stage.fx.spawn_ground_slam(Vector2(pt.x, p.global_position.y + p.foot_offset), 1.0)
			"parry": stage.fx.spawn_parry(pt, Vector2.LEFT)
			"block": stage.fx.spawn_block(pt, Vector2.RIGHT)
			"kill": stage.fx.spawn_kill(pt)
			"hurt": stage.fx.spawn_hurt(pt, Vector2.LEFT)
		for i in 4:
			await frames(2)
			await shot("%s_%02d" % [ev, i])
		await frames(30)
	print("CAP_DONE")
	quit()
