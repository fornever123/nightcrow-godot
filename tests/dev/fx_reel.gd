extends SceneTree
## 开发工具：角色特效样片。几只影站在主角前面不动，按一串固定输入出招，每帧截图（jpg），之后用 ffmpeg 拼视频。
## DISPLAY=:99 godot --path . --script res://tests/dev/fx_reel.gd --resolution 1280x720 --fixed-fps 60
## 环境变量：SHOT_DIR 截图目录；REEL=动作串（默认全套）；EVERY=每几帧截一张（默认 1）
const Buffer := preload("res://scripts/core/input_buffer.gd")
const Shade := preload("res://scripts/night/shade.gd")
var stage
var p
var seq := 0

func _initialize() -> void:
	call_deferred("run")

func fr(actions: Array[StringName] = [], edges: Array[StringName] = [], axis := Vector2.ZERO) -> Buffer.Frame:
	var f := Buffer.Frame.new()
	f.actions = actions
	f.pressed_this_frame = edges
	f.axis = axis
	return f

## 一段输入：[帧数, 按住的键, 这一帧刚按下的键(只在第 1 帧), 方向]
func plan_of(name: String) -> Array:
	var J: StringName = &"attack_light"
	match name:
		"light":   # 地面三连
			return [[1, [J], [J]], [14, [], []], [1, [J], [J]], [16, [], []], [1, [J], [J]], [40, [], []]]
		"charge":  # 按住蓄力再放
			return [[1, [J], [J]], [46, [J], []], [50, [], []]]
		"launch":  # W+J 挑飞 → 跳 → 空中连斩 → 下砸
			return [[1, [&"aim_up", J], [&"aim_up", J]], [18, [], []], [1, [&"jump"], [&"jump"]], [8, [&"jump"], []],
				[1, [J], [J]], [12, [], []], [1, [J], [J]], [12, [], []], [1, [J], [J]], [12, [], []],
				[1, [&"move_down", J], [&"move_down", J], Vector2(0, 1)], [50, [], []]]
		"dash":    # Shift+J 冲刺斩
			return [[1, [&"dash_modifier", J], [&"dash_modifier", J]], [55, [], []]]
		"ranged":
			return [[1, [&"attack_ranged"], [&"attack_ranged"]], [40, [], []]]
		"fx":      # 不走输入，直接触发各种事件特效：弹刀 / 格挡 / 挨打 / 破防 / 下砸 / 炸弹 / 撞墙 / 击杀
			return [[1, [], [], Vector2.ZERO, "parry"], [34, [], []], [1, [], [], Vector2.ZERO, "block"], [30, [], []],
				[1, [], [], Vector2.ZERO, "hurt"], [34, [], []], [1, [], [], Vector2.ZERO, "break"], [34, [], []],
				[1, [], [], Vector2.ZERO, "slam"], [44, [], []], [1, [], [], Vector2.ZERO, "bomb"], [50, [], []],
				[1, [], [], Vector2.ZERO, "wall"], [40, [], []], [1, [], [], Vector2.ZERO, "kill"], [80, [], []]]
		"fx":      # 不走输入，直接触发各种事件特效：弹刀 / 格挡 / 挨打 / 破防 / 下砸 / 炸弹 / 撞墙 / 击杀
			return [[1, [], [], Vector2.ZERO, "parry"], [34, [], []], [1, [], [], Vector2.ZERO, "block"], [30, [], []],
				[1, [], [], Vector2.ZERO, "hurt"], [34, [], []], [1, [], [], Vector2.ZERO, "break"], [34, [], []],
				[1, [], [], Vector2.ZERO, "slam"], [44, [], []], [1, [], [], Vector2.ZERO, "bomb"], [50, [], []],
				[1, [], [], Vector2.ZERO, "wall"], [40, [], []], [1, [], [], Vector2.ZERO, "kill"], [80, [], []]]
		"jump":    # 跳、二段跳、落地
			return [[1, [&"jump"], [&"jump"]], [10, [&"jump"], []], [10, [], []], [1, [&"jump"], [&"jump"]], [10, [&"jump"], []], [60, [], []]]
	return [[30, [], []]]

func trigger_event(ev: String, x: float) -> void:
	var sh: Array = get_nodes_in_group(&"shade")
	var front: Vector2 = p.global_position + Vector2(56, -36)
	match ev:
		"parry": stage._on_parry(sh[0], front)
		"block": stage._on_shade_guarded(front + Vector2(40, 0), sh[0])
		"hurt": stage._on_player_hurt(14.0, p.global_position + Vector2(14, -40), 3.0, Vector2(-1, 0), true)
		"break": stage._on_shade_broken(sh[2].global_position + Vector2(-20, -30), sh[2])
		"slam": stage._on_slam_impact(Vector2(x + 200.0, stage.floor_y), 1.0)
		"bomb": stage._on_bomb_exploded(Vector2(x + 300.0, stage.floor_y - 12.0), false)
		"wall": stage._on_shade_wall(900.0, 12.0, Vector2(x + 470.0, stage.floor_y - 60.0), sh[2])
		"kill":
			sh[0]._die(1)
			sh[1]._die(1)

func shot(dir: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_jpg("%s/f%04d.jpg" % [dir, seq], 0.92)
	seq += 1

func place_shades(x: float) -> void:
	for s in get_nodes_in_group(&"shade"):
		s.queue_free()
	var kinds := [[Shade.Kind.GRUNT, 150.0], [Shade.Kind.GRUNT, 250.0], [Shade.Kind.BRUTE, 380.0]]
	for k in kinds:
		var sh: Node2D = Node2D.new()
		sh.set_script(Shade)
		sh.setup(k[0], p, stage.floor_y, 1.0)
		sh.position = Vector2(x + float(k[1]), stage.floor_y - 60.0)
		sh.terrain = stage.terrain
		stage.add_child(sh)
		sh.spawn_frames = 0
		sh.active = false
		sh.facing = -1
		stage._on_shade_spawned(sh)

func run() -> void:
	var dir := OS.get_environment("SHOT_DIR")
	if dir == "":
		dir = ProjectSettings.globalize_path("res://.runtime/shots")
	DirAccess.make_dir_recursive_absolute(dir)
	var reel := OS.get_environment("REEL")
	if reel == "":
		reel = "light,charge,launch,dash,ranged,jump,fx"
	var every := maxi(1, int(OS.get_environment("EVERY")) if OS.get_environment("EVERY") != "" else 1)
	stage = load("res://scenes/night_trial.tscn").instantiate()
	root.add_child(stage)
	await process_frame
	stage.set_physics_process(false)
	stage.hud.help_visible = false
	stage.hud._banner = ""
	stage.hud._banner_life = 0.0
	p = stage.player
	var x := 1400.0
	var n := 0
	for part in reel.split(","):
		p.reset_state(Vector2(x, stage.floor_y - p.foot_offset))
		p._set_facing(1)
		p.set_injected_frame(fr())
		place_shades(x)
		stage.camera.global_position = Vector2(x + 160.0, stage.CAM_Y)
		for i in 20:
			await physics_frame
		for step in plan_of(part):
			var axis: Vector2 = step[3] if step.size() > 3 else Vector2.ZERO
			var hold: Array[StringName] = []
			hold.assign(step[1])
			var edge: Array[StringName] = []
			edge.assign(step[2])
			if step.size() > 4:
				trigger_event(step[4], x)
			for i in int(step[0]):
				await physics_frame
				p.set_injected_frame(fr(hold, edge if i == 0 else ([] as Array[StringName]), axis))
				n += 1
				if n % every == 0:
					await shot(dir)
	print("frames ", seq)
	quit()
