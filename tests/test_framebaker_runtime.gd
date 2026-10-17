extends SceneTree
const Config := preload("res://scripts/core/configuration.gd")
const Timeline := preload("res://scripts/core/animation_timeline.gd")
const Buffer := preload("res://scripts/core/input_buffer.gd")
var stage: Node2D
var p: CharacterBody2D
var failures: Array[String] = []
var checks := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		print("FAIL: ", label)

func _initialize() -> void:
	call_deferred("run")

func step(count: int, attack: bool = false) -> void:
	var input := Buffer.Frame.new()
	if attack:
		input.actions = [&"attack_light"]
		input.pressed_this_frame = [&"attack_light"]
	p.set_injected_frame(input)
	var until: int = p.tick_count + count
	while p.tick_count < until:
		await process_frame

func run() -> void:
	var config := Config.read().duplicate(true)
	var sprite: Dictionary = Config.character(config, "player").sprite
	var original: Dictionary = sprite.animations.attack_1.frames[0]
	var frames: Array = []
	for ticks in [2.0, 3.0, 1.0]:
		var f := original.duplicate(true)
		f.durationTicks = ticks
		frames.append(f)
	sprite.animations.attack_1 = {"fps": 10.0, "frames": frames}
	config.moves[0].animationSpeed = 2.0
	config.moves[0].activeFrameStart = 1
	config.moves[0].activeFrameEnd = 1
	config.moves[0].chainFrame = 2
	var move: Resource = Config.moves(config).light_1
	check(move.startup_frames == 6, "累计首帧时长决定命中起点并应用动作速度")
	check(move.active_frames == 9, "非等长第二帧决定完整命中窗口")
	check(move.total_frames() == 18, "非等长三帧总长为18个物理帧")
	check(move.startup_frames + move.active_frames + move.cancel_frame == 15, "接招位置按累计帧时长推导")
	var clip: Dictionary = sprite.animations.attack_1
	check(Timeline.frame_at(clip, 0.099, 20.0) == 0, "非等长帧边界之前保留首帧")
	check(Timeline.frame_at(clip, 0.1, 20.0) == 1, "边界时进入第二帧")
	check(Timeline.frame_at(clip, 0.25, 20.0) == 2, "累计5tick时进入第三帧")
	check(Timeline.frame_at(clip, 0.3, 20.0, false) == -1, "特效耗尽返回隐藏状态")
	check(Timeline.frame_at(clip, 0.3, 20.0) == 2, "非循环角色动作保持最终姿态")
	clip.loop = true
	clip.loopFrame = 1
	check(Timeline.frame_at(clip, 0.3, 20.0) == 1, "非等长loopFrame回到循环片段")
	check(Timeline.frame_at(clip, 0.45, 20.0) == 2, "循环片段保留自身帧时长")
	clip.loop = false
	for invalid in [0, -1, INF, NAN, "2", null]:
		check(Timeline.duration_ticks({"durationTicks": invalid}) == 1.0, "非法时长回退旧帧默认: " + str(invalid))
	check(Timeline.duration_ticks({}) == 1.0, "旧帧默认一tick")

	stage = load("res://scenes/training.tscn").instantiate()
	root.add_child(stage)
	current_scene = stage
	stage.config.runtime.autoReload = false
	p = stage.player
	await step(6)
	var view: Sprite2D = p.get_node("Visual/ActorSprite")
	var dummy: CharacterBody2D = stage.dummy
	view.setup = sprite
	# Two effect frames have their own 3/2 tick timing, sped up with the move.
	var effects: Array = [original.duplicate(true), original.duplicate(true)]
	effects[0].durationTicks = 3.0
	effects[1].durationTicks = 2.0
	sprite.effects.framebaker_test = {"fps": 20.0, "frames": effects, "loop": true}
	clip.overlayEffect = "framebaker_test"
	move.effect = "feather_slash"
	p._start_move(move, false)
	p.move_frame = 3
	view.clip_name = "attack_1"
	view._draw_frame()
	check(view.frame_index == 0 and view.overlay_frame_index == 0, "角色与独立时长overlay共享动作时间")
	check(view.overlay.visible and not is_instance_valid(view.trail), "overlay抑制旧刀光避免重复")
	p.move_frame = 5
	view._draw_frame()
	check(view.frame_index == 0 and view.overlay_frame_index == 1, "overlay按自己的durationTicks选帧")
	check(view.overlay.get_parent() == view.get_parent() and view.overlay.position == view.position, "overlay继承相同Visual变形翻向与脚底原点")
	p.move_frame = 8
	view._draw_frame()
	check(not view.overlay.visible and view.overlay_frame_index == -1, "overlay耗尽隐藏且忽略循环标志")
	clip.effectsBaked = true
	p._start_move(move, false)
	view._draw_frame()
	check(not view.overlay.visible and not is_instance_valid(view.trail), "烘焙效果优先抑制overlay和旧刀光")
	clip.effectsBaked = false
	clip.erase("overlayEffect")
	p._start_move(move, false)
	check(is_instance_valid(view.trail), "未选择FrameBaker特效时仍生成旧羽刃腐蚀刀光")
	clip.effectsBaked = true
	p._start_move(move, false)
	check(view.trail == null, "烘焙动作清除之前招式遗留刀光")
	clip.effectsBaked = false
	clip.overlayEffect = "framebaker_test"

	# A real collision, rather than a manually assigned pause, must freeze both clocks.
	stage._reset()
	await step(4)
	view.setup = sprite
	stage.moves.light_1 = move
	var hp: float = dummy.hp
	p._start_move(move, false)
	await step(5)
	check(dummy.hp == hp, "累计前摇结束之前真实碰撞不提前造成伤害")
	for tick in 10:
		if dummy.hp < hp:
			break
		await step(1)
	check(dummy.hp < hp and p.hitstop_frames > 0, "非等长动作在累计命中窗口真实碰撞并启动停顿")
	check(p.move_frame == move.startup_frames, "真实命中时刻匹配累计时长物理帧")
	var cursor: int = p.move_frame
	var pose: int = view.frame_index
	var overlay_pose: int = view.overlay_frame_index
	check(is_instance_valid(view.overlay) and view.overlay.visible, "真实命中瞬间overlay仍处于有效帧")
	await step(1, true)
	await step(2)
	check(p.move_frame == cursor and view.frame_index == pose and view.overlay_frame_index == overlay_pose, "真实命中停顿冻结角色及overlay时轴")
	var linked := false
	for tick in 35:
		if p.current_move != null and p.current_move.id == &"light_2":
			linked = true
			break
		await step(1)
	check(linked, "非等长动作真实停顿期间输入仍缓冲并接下一招")
	clip.frames = []
	view.clip_name = "attack_1"
	view._draw_frame()
	check(not view.visible and not view.overlay.visible, "空角色片段不会残留上一层特效")
	print("FRAMEBAKER_RUNTIME_TESTS: %d checks / %d failures" % [checks, failures.size()])
	stage.free()
	OS.delay_msec(100)
	await process_frame
	quit(0 if failures.is_empty() else 1)
