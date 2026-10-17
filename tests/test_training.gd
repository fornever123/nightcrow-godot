extends SceneTree
const Config := preload("res://scripts/core/configuration.gd")
const Buffer := preload("res://scripts/core/input_buffer.gd")
var stage: Node2D
var p: CharacterBody2D
var d: CharacterBody2D
var failures: Array[String] = []
var checks: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		print("FAIL: ", label)

func frame(actions: Array[StringName] = [], edges: Array[StringName] = [], axis := Vector2.ZERO) -> Buffer.Frame:
	var f := Buffer.Frame.new()
	f.actions = actions
	f.pressed_this_frame = edges
	f.axis = axis
	return f

func step(count: int, input: Buffer.Frame = null) -> void:
	p.set_injected_frame(frame() if input == null else input)
	var target: int = p.tick_count + count
	while p.tick_count < target:
		await process_frame

func reset() -> void:
	stage._reset()
	await step(4)

func wait_move(id: StringName, limit: int = 80) -> bool:
	for tick in limit:
		if p.current_move != null and p.current_move.id == id:
			return true
		await step(1)
	return false

func run() -> void:
	stage = load("res://scenes/training.tscn").instantiate()
	root.add_child(stage)
	current_scene = stage
	p = stage.player
	d = stage.dummy
	stage.config.runtime.autoReload = false
	await step(8)
	check(p.is_on_floor(),"角色脚底落在地面")
	check(d.is_on_floor(),"木桩脚底落在地面")
	check(p.foot_offset == 84,"角色默认 168 高")
	var view := p.get_node("Visual/ActorSprite")
	check(view.texture != null and view.visible,"E 盘待机图片可见")
	var raw := Config.read()
	for id in ["light_1","light_2","light_3","charge_1"]:
		var m: Resource = stage.moves[id]
		var clip: Dictionary = raw.characters[0].sprite.animations[m.animation]
		check(absf(float(m.total_frames())/60-float(clip.frames.size())/m.animation_fps)<=1.0/60+0.00001,id+" 按完整动作时长出招")
	var faster: Dictionary = raw.duplicate(true)
	faster.moves[0].animationSpeed = 1.5
	var sped: Resource = Config.moves(faster).light_1
	check(sped.total_frames() < stage.moves.light_1.total_frames(),"动作加速会同步缩短战斗窗口")
	check(absf(float(sped.total_frames())/60-float(raw.characters[0].sprite.animations.attack_1.frames.size())/sped.animation_fps)<0.02,"加速后的动作与判定同步")
	var x: float = p.position.x
	await step(12, frame([&"move_right"],[],Vector2.RIGHT))
	check(p.position.x > x+30,"跑步实际移动")
	check(view.clip_name == "run","跑步使用 E 盘动作")
	await reset()
	await step(1,frame([&"jump"],[&"jump"]))
	await step(3)
	check(p.velocity.y<0 and p.position.y<496,"第一跳")
	# The inherited C-drive coyote interval treats a very early second press as a ground jump.
	await step(p.coyote_frames)
	await step(1,frame([&"jump"],[&"jump"]))
	await step(2)
	check(p._air_jumps_left==0 and p.velocity.y<0,"第二跳")
	await reset()
	await step(1,frame([&"attack_light"],[&"attack_light"]))
	check(p.current_move != null and p.current_move.id==&"light_1","点按开始第一刀")
	var start_hp: float = d.hp
	for tick in 40:
		if d.hp < start_hp:
			break
		await step(1)
	check(d.hp<start_hp,"剑挥到时木桩扣血")
	check(p.hitstop_frames>0,"真实命中启动角色自身顿帧")
	var hp_after: float = d.hp
	var cursor: int=p.move_frame
	await step(2)
	var drawn: int=view.frame_index
	await step(1,frame([&"attack_light"],[&"attack_light"]))
	await step(2)
	check(p.move_frame==cursor and view.frame_index==drawn,"真实命中停顿同时冻结动作与战斗")
	await step(6)
	check(stage.total_hits==1 and d.last_hit_damage==start_hp-hp_after,"一刀只结算一次近战命中，撞击伤害另计")
	check(await wait_move(&"light_2"),"顿帧中提前输入能衔接第二刀")
	for tick in 40:
		if p.last_swing_hit:
			break
		await step(1)
	await step(1,frame([&"attack_light"],[&"attack_light"]))
	check(await wait_move(&"light_3"),"第二刀能够衔接第三刀")
	await reset()
	p.position.x = d.position.x - 60
	await step(3)
	await step(1,frame([&"aim_up",&"attack_light"],[&"attack_light"]))
	check(p.current_move != null and p.current_move.id==&"up_strike","上挑采用 C 盘指令")
	await step(28)
	check(d.state==2 or d.position.y<512,"上挑能击飞木桩")
	await reset()
	await step(1,frame([&"attack_light"],[&"attack_light"]))
	await step(65,frame([&"attack_light"]))
	check(p.is_charging() or p.last_charge_frames>0,"长按进入蓄力")
	await step(30)
	check(p.last_charge_frames>0,"蓄力释放")
	await reset()
	start_hp=d.hp
	await step(1,frame([&"attack_ranged"],[&"attack_ranged"]))
	await step(30)
	check(d.hp<start_hp,"远程弹丸能够命中")
	await reset()
	await step(1,frame([&"parry"],[&"parry"]))
	for tick in stage.moves.parry_1.startup_frames + 2:
		if p.is_parrying():
			break
		await step(1)
	var hp: float = p.hp
	var parried: bool = p.take_hit(stage.moves.light_1,-1,p.global_position,0,false,1,d)
	check(parried and p.hp==hp,"弹刀阻止本次伤害")
	check(d.state==4,"弹刀让来袭者进入硬直")
	await reset()
	d.position.x=1220
	p.position.x=1070
	await step(4)
	p._start_move(stage.moves.light_3,false)
	await step(50)
	check(d.wall_slam_count>0 and d.last_wall_damage>0,"击飞撞墙产生二次伤害")
	await reset()
	p._start_move(stage.moves.light_3,false)
	await step(12)
	check(is_instance_valid(view.overlay) and view.overlay.visible and not is_instance_valid(view.trail),"第三刀同步显示新分层刀光且不叠加旧刀光")
	await step(stage.moves.light_3.total_frames() + 30)
	check(view.clip_name != stage.moves.light_3.animation and not is_instance_valid(view.trail),"第三刀结束后退出攻击特效且无旧刀光残留")
	await reset()
	check(d.hp==d.max_hp and stage.total_hits==0,"重置恢复血量及计数")
	print("TRAINING_TESTS: %d checks / %d failures" %[checks,failures.size()])
	stage.free()
	# WAV playback is released asynchronously by the real-time audio thread.
	OS.delay_msec(100)
	await process_frame
	quit(0 if failures.is_empty() else 1)
