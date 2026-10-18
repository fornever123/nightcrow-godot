extends SceneTree
const Config := preload("res://scripts/core/configuration.gd")
const Timeline := preload("res://scripts/core/animation_timeline.gd")
const Buffer := preload("res://scripts/core/input_buffer.gd")
const Art := preload("res://scripts/presentation/art_cache.gd")
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
	var cache_setup := {
		"animations": {
			"idle": {"frames": [{"asset": "cache_idle.png"}], "overlayEffect": "idle_fx"},
			"library": {"frames": [{"asset": "cache_library.png"}]},
			"cached_library": {"frames": [{"asset": "cache_retained.png"}]}
		},
		"effects": {
			"idle_fx": {"frames": [{"asset": "cache_overlay.png"}]},
			"unused_fx": {"frames": [{"asset": "cache_unused_fx.png"}]}
		},
		"preloadAnimations": ["idle"]
	}
	var cached_texture := ImageTexture.new()
	Art.textures["cache_retained.png"] = cached_texture
	Art.reset(cache_setup)
	check(Art.pending.has("cache_idle.png") and Art.pending.has("cache_overlay.png"), "指定预加载动作包含同步特效")
	check(not Art.pending.has("cache_library.png") and not Art.pending.has("cache_unused_fx.png"), "未绑定动作库与特效不进入预加载队列")
	check(Art.textures.get("cache_retained.png") == cached_texture, "按需加载的可选动作缓存仍被保留")
	check(Art.get_texture("cache_retained.png") == cached_texture, "非预加载动作仍可按需取纹理")
	cache_setup.preloadAnimations = []
	Art.reset(cache_setup)
	check(Art.pending.has("cache_library.png") and Art.pending.has("cache_unused_fx.png"), "空预加载列表保留全部预热行为")
	cache_setup.erase("preloadAnimations")
	Art.reset(cache_setup)
	check(Art.pending.has("cache_library.png") and Art.pending.has("cache_overlay.png"), "旧配置缺省仍预加载全部动作")
	Art.reset({})
	var config := Config.read().duplicate(true)
	var sprite: Dictionary = Config.character(config, "player").sprite
	var original: Dictionary = sprite.animations.attack_1.frames[0]
	var frames: Array = []
	for ticks in [2.0, 3.0, 1.0]:
		var f := original.duplicate(true)
		f.durationTicks = ticks
		frames.append(f)
	sprite.animations.attack_1 = {"fps": 10.0, "frames": frames}
	for k in ["startupSpeed","activeSpeed","recoverySpeed","tailSpeed","moveCancelDelay"]:
		config.moves[0].erase(k)
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
	# A separate actor enters the tree with an explicit idle overlay fixture.
	# This exercises _ready ordering even when production idle has no effect.
	var fixture: CharacterBody2D = load("res://scenes/actors/player.tscn").instantiate()
	fixture.set_meta("character", {"sprite": {
		"animations": {"idle": {"fps": 24.0, "frames": [original.duplicate(true)], "overlayEffect": "fixture_fx"}},
		"effects": {"fixture_fx": {"fps": 24.0, "frames": [original.duplicate(true)]}}
	}})
	root.add_child(fixture)
	fixture.set_physics_process(false)
	var fixture_view: Sprite2D = fixture.get_node("Visual/ActorSprite")
	fixture_view.set_physics_process(false)
	await process_frame
	check(is_instance_valid(fixture_view.overlay) and fixture_view.overlay.get_parent() == fixture_view.get_parent(), "初始待机同步层在节点就绪后成功挂载")
	fixture.free()
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
	# Presentation options use only this in-memory setup, never the saved config.
	var pose_frames: Array = [original.duplicate(true), original.duplicate(true), original.duplicate(true)]
	for f in pose_frames:
		f.durationTicks = 1.0
	sprite.animations.test_loop = {"fps": 10.0, "frames": pose_frames, "loop": true, "loopFrame": 1, "overlayEffect": "test_loop_fx"}
	sprite.effects.test_loop_fx = {"fps": 10.0, "frames": pose_frames}
	p.state = p.State.NEUTRAL
	p.current_move = null
	p.charge_frames = -1
	view.clip_name = "test_loop"
	for cycle_time in [0.35, 0.55]:
		view.clock = cycle_time
		view._draw_frame()
		check(view.frame_index == 1 and view.overlay_frame_index == 1 and view.overlay.visible, "循环第二三轮特效保留相同片段位置")
	sprite.animations.test_parry = {"fps": 10.0, "frames": pose_frames, "playDuringParry": true}
	var parry: Resource = p.parry_move.duplicate()
	parry.animation = "test_parry"
	parry.animation_fps = 10.0
	p.charge_frames = -1
	p.hitstop_frames = 0
	p._start_move(parry, false)
	p.move_frame = 7
	view._physics_process(0.0)
	check(view.clip_name == "test_parry" and view.frame_index == 1, "独立格挡动画按招式时间推进")
	sprite.animations.test_parry.erase("playDuringParry")
	view._draw_frame()
	check(view.frame_index == 0, "未配置独立格挡播放时保留旧首帧姿态")
	sprite.effects.test_charge_fx = {"fps": 10.0, "frames": pose_frames}
	sprite.animations.test_charge = {"fps": 10.0, "frames": pose_frames, "overlayEffect": "test_charge_fx"}
	sprite.chargeAnimation = "test_charge"
	sprite.chargeFrame = 1
	p.state = p.State.NEUTRAL
	p.current_move = null
	p.charge_frames = 1
	view._physics_process(0.0)
	check(view.clip_name == "test_charge" and view.frame_index == 1, "蓄力使用配置的动作与准备帧")
	view.clock = 20.0
	view._draw_frame()
	check(view.overlay.visible and view.overlay_frame_index == 1, "长时间蓄力的特效停留在角色准备帧")
	sprite.erase("chargeAnimation")
	sprite.erase("chargeFrame")
	view._physics_process(0.0)
	check(view.clip_name == "attack_3" and view.frame_index == 2, "旧配置保持第三刀第三帧蓄力姿态")
	sprite.animations.death = {"fps": 10.0, "frames": pose_frames, "loop": true}
	p.set_meta("character", {"sprite": sprite})
	p._die()
	view._physics_process(0.0)
	check(view.clip_name == "death" and view.frame_index == 0, "死亡状态切换并从首帧开始")
	check(p.get_node("Visual").scale.is_equal_approx(Vector2(p.facing, 1.0)), "独立死亡动画不被旧剪影压扁")
	view._physics_process(0.15)
	check(view.frame_index == 1, "死亡动画继续推进")
	view._physics_process(1.0)
	check(view.frame_index == 2, "死亡动画即使标记循环也只播放一次并保持末帧")
	sprite.animations.erase("death")
	p._die()
	check(absf(p.get_node("Visual").scale.y - 1.0) > 0.01, "无死亡动画时保留旧死亡形变")
	print("FRAMEBAKER_RUNTIME_TESTS: %d checks / %d failures" % [checks, failures.size()])
	stage.free()
	OS.delay_msec(100)
	await process_frame
	quit(0 if failures.is_empty() else 1)
