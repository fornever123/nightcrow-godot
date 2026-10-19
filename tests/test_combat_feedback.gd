extends SceneTree
## Real collision/input regressions for the feedback lost during the migration.
const Config := preload("res://scripts/core/configuration.gd")
const Buffer := preload("res://scripts/core/input_buffer.gd")
const Timeline := preload("res://scripts/core/animation_timeline.gd")
var stage: Node2D
var p: CharacterBody2D
var d: CharacterBody2D
var view: Sprite2D
var failures: Array[String] = []
var checks: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		print("FAIL: ",label)

func input(held: Array[StringName], edges: Array[StringName], axis: Vector2) -> Buffer.Frame:
	var value := Buffer.Frame.new()
	value.actions = held
	value.pressed_this_frame = edges
	value.axis = axis
	return value

func step(count: int, held: Array[StringName] = [], edges: Array[StringName] = [], axis := Vector2.ZERO) -> void:
	# A held button produces exactly one edge, matching a physical keyboard.
	p.set_injected_frame(input(held,[],axis))
	if not edges.is_empty():
		p.queue_input(input(held,edges,axis))
	var until: int = p.tick_count+count
	while p.tick_count < until:
		await process_frame

func reset() -> void:
	stage._reset()
	await step(4)

func wait_hit(previous: float, limit: int = 40) -> bool:
	for tick in limit:
		if d.hp < previous:
			return true
		await step(1)
	return false

func has_text(prefix: String) -> bool:
	for node in stage.fx.get_children():
		if node is Label and node.text.begins_with(prefix):
			return true
	return false

func run() -> void:
	stage = load("res://scenes/training.tscn").instantiate()
	root.add_child(stage)
	current_scene = stage
	stage.config.runtime.autoReload = false
	p = stage.player
	d = stage.dummy
	view = p.get_node("Visual/ActorSprite")
	await step(6)
	check(stage.audio._clips.size()==13 and stage.audio.bank_size()>=20,"13 个旧音效槽兜底 + 新音效库加载")
	var expected_filter := CanvasItem.TEXTURE_FILTER_NEAREST if view.setup.get("filter", "linear") == "nearest" else CanvasItem.TEXTURE_FILTER_LINEAR
	check(view.texture_filter==expected_filter,"角色遵循配置的图片显示方式")
	var parry_source: Dictionary = {}
	for source in stage.config.moves:
		if source.id == "parry_1":
			parry_source = source
	var parry_clip: Dictionary = view.setup.animations[parry_source.animation]
	var parry_fps: float = parry_clip.fps * parry_source.animationSpeed
	var expected_start := ceili(Timeline.ticks_before(parry_clip.frames, parry_source.activeFrameStart) / parry_fps * 60.0 - 0.0001)
	var expected_end := ceili(Timeline.ticks_before(parry_clip.frames, parry_source.activeFrameEnd + 1) / parry_fps * 60.0 - 0.0001)
	check(stage.moves.parry_1.startup_frames==expected_start and stage.moves.parry_1.active_frames==expected_end-expected_start,"招架窗口匹配配置的逐帧时长")
	check(stage.moves.parry_1.cancel_frame < stage.moves.parry_1.recovery_frames,"招架后摇可及时接招")
	check(stage.moves.charge_1.cancel_frame < stage.moves.charge_1.recovery_frames,"蓄力收刀恢复提前接招窗口")
	check(stage.moves.up_strike.direction==1 and stage.moves.air_up.direction==1,"地面/空中上挑方向恢复")
	check(stage.moves.light_1.movement_scale<=0.35 and stage.moves.light_1.root_motion_x.size()>0,"轻攻击前冲交给根位移，按方向只做小幅走位")
	await reset()
	var before: float = d.hp
	await step(1,[&"attack_light"],[&"attack_light"])
	await step(stage.moves.light_1.startup_frames-2)
	check(d.hp==before and p.hitstop_frames==0,"蓄势尚未挥到木桩时不提前命中或顿帧")
	check(await wait_hit(before),"点按 J 真实命中木桩")
	check(p.hitstop_frames==stage.moves.light_1.hitstop_frames and p.hitstop_frames==6,"轻击恢复 C 盘参考的 6 帧顿帧")
	check(d.hitstop_frames>=p.hitstop_frames and stage.moves.light_1.victim_hitstop_frames>stage.moves.light_1.hitstop_frames,"木桩使用独立受击停顿（受方比攻方多停一帧）")
	check(stage.camera._trauma>5,"普通轻击也有清楚的命中震屏")
	check(stage.audio.last_event=="hit_light" and not stage.audio._voices.is_empty(),"刀刃命中事件真正开始播放")
	check(stage.fx.last_hit_plan.size()==6 and stage.fx.get_child_count()>=6,"实际生成六层错时命中反馈")
	var first_source: Dictionary = {}
	for source in stage.config.moves:
		if source.id == "light_1":
			first_source = source
	check(view.frame_index==int(first_source.activeFrameStart),"第一刀真实碰撞停在配置的起始命中图片")
	check(has_text("-8"),"浮动数字使用实际结算伤害")
	var cursor: int = p.move_frame
	var image_frame: int = view.frame_index
	var pos: Vector2 = p.position
	var victim_pos: Vector2 = d.position
	await step(1)
	check(p.move_frame==cursor and view.frame_index==image_frame,"真实命中时动画和战斗游标都冻结")
	check(p.position==pos and d.position==victim_pos,"角色和木桩的位移都冻结")
	var visual: Node2D = p.get_node("Visual")
	check(is_equal_approx(visual.position.y+p.foot_offset*visual.scale.y,p.foot_offset),"变形以脚底为固定点")
	await step(1,[&"attack_light"],[&"attack_light"])
	check(p.move_frame==cursor,"顿帧中接受输入而不提前推进招式")
	var linked := false
	for tick in 50:
		if p.current_move!=null and p.current_move.id==&"light_2":
			linked=true
			break
		await step(1)
	check(linked,"真实顿帧期间按的下一刀没有丢失")
	await reset()
	var quiet := Config.read().duplicate(true)
	quiet.feedback.hitstopMultiplier=0
	quiet.feedback.shakeMultiplier=0
	var no_pause: Resource = Config.moves(quiet).light_1
	p._start_move(no_pause,false)
	check(await wait_hit(d.hp),"关闭反馈时攻击仍命中")
	check(p.hitstop_frames==0 and d.hitstop_frames==0,"修改器顿帧倍率 0 能关闭两边顿帧")
	check(stage.camera._trauma==0,"修改器震屏倍率 0 能关闭命中震屏")
	await reset()
	await step(1,[&"attack_light"],[&"attack_light"])
	for tick in 60:
		if p.is_charging():
			break
		await step(1,[&"attack_light"])
	check(p.is_charging(),"真实按住 J 能在后摇进入蓄力")
	d.reset_state()
	p.position.x=d.position.x-120
	for tick in 90:
		if p.last_charge_frames>0:
			break
		await step(1,[&"attack_light"])
	check(p.last_charge_frames==72,"满蓄力自动释放沿用 C 盘时长")
	check(await wait_hit(d.max_hp),"满蓄力真实命中")
	check(p.hitstop_frames==stage.moves.charge_1.hitstop_frames+stage.moves.charge_1.charge_hitstop_bonus,"满蓄力为角色停顿添加 6 帧重量")
	check(stage.camera._trauma>0,"蓄力重击才震屏")
	var charge_source: Dictionary = {}
	for source in stage.config.moves:
		if source.id == "charge_1":
			charge_source = source
	check(view.frame_index==int(charge_source.activeFrameStart),"重击实际停在当前素材配置的起始命中图片")
	check(d.last_hit_damage>26,"满蓄力造成加成伤害")
	check(stage.audio.last_event=="hit_finisher","重击使用终结档命中声音")
	p._start_move(stage.moves.light_1,false)
	check(p._charge_t==0,"普通攻击不继承上一次蓄力加成")
	await reset()
	p.position.x=d.position.x-60
	await step(2)
	await step(1,[&"aim_up",&"attack_light"],[&"attack_light"])
	check(await wait_hit(d.max_hp),"W + J 真实上挑命中")
	check(d.velocity.y<0 and d.state==2,"上挑将木桩击向空中")
	check(stage.camera._shake_dir.y < -0.9,"上挑震屏方向向上")
	# A second actual melee collision against the airborne target increases its juggle damage.
	p.position=d.position-Vector2(60,0)
	p.hitstop_frames=0
	p._start_move(stage.moves.air_up,true)
	before=d.hp
	check(await wait_hit(before),"空中追击再次实际命中")
	check(d.juggle_count>0 and d.last_hit_damage>stage.moves.air_up.damage,"浮空追击伤害递增仍生效")
	await reset()
	await step(1,[&"parry"],[&"parry"])
	for tick in stage.moves.parry_1.startup_frames + 2:
		if p.is_parrying():
			break
		await step(1)
	check(p.is_parrying() and view.frame_index==Timeline.frame_at(parry_clip, float(p.move_frame)/60.0, parry_fps),"弹刀判定期间播放同步防守动作")
	var hp: float = p.hp
	var parried: bool = p.take_hit(stage.moves.light_1,-1,p.global_position,0,false,1,d)
	check(parried and p.hp==hp and d.state==4,"弹刀零伤害并让来袭者后仰硬直")
	check(p.hitstop_frames==9,"弹刀成功强化为 9 帧停顿")
	check(stage.audio.last_event=="parry" and stage.fx.last_kind=="parry","弹刀声音和画面反馈单独路由")
	check(stage.total_hits==0 and has_text("弹刀"),"弹刀不冒充一次伤害命中")
	await reset()
	d.position.x=1220
	p.position.x=1070
	await step(4)
	p._start_move(stage.moves.light_3,false)
	for tick in 180:
		if d.wall_slam_count>0:
			break
		await step(1)
	check(d.wall_slam_count>0 and d.last_wall_damage>0,"实际击飞撞击产生二次伤害")
	check(stage.fx.last_kind=="wall" and has_text("撞击"),"撞击有独立特效和真实伤害数字")
	check(stage.audio.last_event=="wall" and stage.camera._trauma>0,"撞击音效和震屏均触发")
	await reset()
	await step(1,[&"attack_ranged"],[&"attack_ranged"])
	check(stage.audio.last_event=="shuriken_throw","K 远射发出自己的声音")
	check(await wait_hit(d.max_hp),"远射真实命中")
	check(stage.audio.last_event=="shuriken_hit" and p.hitstop_frames==0,"远射轻反馈保留不打断走位的规则")
	check(stage.camera._trauma<3,"远射震屏明显轻于近战")
	stage._reset()
	check(stage.fx.get_child_count()==0 and stage.audio._voices.is_empty(),"重置清理特效和声音")
	check(stage.camera.offset==Vector2.ZERO and stage.total_hits==0,"重置清理镜头和命中统计")
	print("COMBAT_FEEDBACK_TESTS: %d checks / %d failures" % [checks,failures.size()])
	stage.free()
	OS.delay_msec(100)
	await process_frame
	quit(0 if failures.is_empty() else 1)
