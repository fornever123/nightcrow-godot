extends SceneTree
const Buffer := preload("res://scripts/core/input_buffer.gd")
const Timeline := preload("res://scripts/core/animation_timeline.gd")
var stage: Node2D
var p: CharacterBody2D
var view: Sprite2D
var checks := 0
var failures: Array[String] = []
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		print("FAIL: ", label)
func frame(held: Array[StringName] = [], edges: Array[StringName] = [], axis := Vector2.ZERO) -> Buffer.Frame:
	var value := Buffer.Frame.new()
	value.actions=held
	value.pressed_this_frame=edges
	value.axis=axis
	return value
func step(count: int, input: Buffer.Frame = null) -> void:
	p.set_injected_frame(frame() if input==null else input)
	var until: int=p.tick_count+count
	while p.tick_count<until:
		await process_frame
func wait_move(id: String, limit: int) -> bool:
	for i in limit:
		if p.current_move!=null and str(p.current_move.id)==id:
			return true
		await step(1)
	return false
func run() -> void:
	stage=load("res://scenes/training.tscn").instantiate()
	root.add_child(stage)
	current_scene=stage
	stage.config.runtime.autoReload=false
	p=stage.player
	view=p.get_node("Visual/ActorSprite")
	await step(5)
	var clips: Dictionary=view.setup.animations
	var source_count := 0
	var source_frames := 0
	for key in clips:
		if str(key).begins_with("source_"):
			source_count+=1
			source_frames+=clips[key].frames.size()
	check(source_count==24 and source_frames==734,"24套完整原片734帧全部保留可预览")
	check(p.foot_offset==84 and view.setup.worldScale==1,"源图缩放不缩小角色物理身高")
	check(clips.run.fps==4 and clips.turn_left_right.fps==4,"源工程慢帧率得到保留")
	check(clips.air_attack_1.frames.size()==18 and clips.air_attack_2.frames.size()==12 and clips.air_attack_3.frames.size()==26,"空中56帧完整分为18/12/26三段")
	check(p.air_combo.size()==3 and p.dash_left_move!=null and p.dash_move!=null,"新招式资源注入真实玩家")
	check(p.dash_left_move.total_frames()!=p.dash_move.total_frames(),"左右冲刺使用各自动作时长")
	await step(1,frame([&"jump"],[&"jump"]))
	await step(12)
	await step(1,frame([&"attack_light"],[&"attack_light"]))
	check(await wait_move("air_light_1",3),"实际跳跃J起手空中第一刀")
	await step(3)
	check(view.clip_name=="air_attack_1","空中第一刀显示自己的素材")
	var boundary: int=stage.moves.air_light_1.startup_frames+stage.moves.air_light_1.active_frames+stage.moves.air_light_1.cancel_frame
	while p.move_frame<boundary-2:
		await step(1)
	await step(1,frame([&"attack_light"],[&"attack_light"]))
	check(await wait_move("air_light_2",12),"再次输入在接招点进入第二刀")
	await step(3)
	check(view.clip_name=="air_attack_2" and not p.is_on_floor(),"第二刀保持空中并使用第二段素材")
	boundary=stage.moves.air_light_2.startup_frames+stage.moves.air_light_2.active_frames+stage.moves.air_light_2.cancel_frame
	while p.move_frame<boundary-2:
		await step(1)
	await step(1,frame([&"attack_light"],[&"attack_light"]))
	check(await wait_move("air_light_3",12),"第三次输入进入空中终结刀")
	await step(3)
	check(view.clip_name=="air_attack_3" and p.air_combo_index==3,"空中第三刀与独立连段计数一致")
	await step(stage.moves.air_light_3.total_frames()+120)
	check(p.is_on_floor() and p.air_combo_index==0,"停止输入后正常落地并重置空连")
	await step(1,frame([&"attack_light"],[&"attack_light"]))
	check(p.current_move!=null and p.current_move.id==&"light_1","落地后J从地面第一刀重新开始")
	stage._reset()
	await step(8,frame([],[],Vector2.RIGHT))
	await step(1,frame([],[],Vector2.LEFT))
	check(p.locomotion_animation=="turn_right_left","反向跑触发右转左片段")
	await step(5,frame([],[],Vector2.LEFT))
	check(view.clip_name=="turn_right_left","转身实际使用 authored 转身素材")
	check(absf(p.get_node("Visual").scale.x*view.scale.x)>0.0,"转身没有无效翻面倍率")
	stage._reset()
	await step(4)
	await step(1,frame([&"dash_modifier",&"attack_light"],[&"attack_light"],Vector2.RIGHT))
	check(p.current_move==p.dash_move,"Shift+J真实输入启动右冲刺")
	var x: float=p.position.x
	await step(20)
	check(p.position.x>x and view.clip_name=="dash_right","冲刺位移和右向素材同步推进")
	stage._reset()
	await step(1,frame([&"parry"],[&"parry"]))
	await step(36,frame([&"parry"]))
	check(p.is_guarding() and not p.is_parrying() and view.clip_name=="guard_hold","持续L进入持防且不延长精准弹刀窗口")
	check(stage.total_hits==0,"空按防守不生成攻击命中")
	var hp: float=p.hp
	p.take_hit(stage.moves.light_1,-1,p.global_position,0,false,1,stage.dummy)
	check(p.hp<=hp and p.state!=p.State.LAUNCHED and str(p.current_move.id).begins_with("guard_hit_"),"真实来袭触发格挡反馈而不是正常受击")
	stage._reset()
	await step(4)
	await step(1,frame([&"parry"],[&"parry"]))
	hp=p.hp
	var parried: bool=p.take_hit(stage.moves.light_1,-1,p.global_position,0,false,1,stage.dummy)
	check(parried and p.hp==hp and str(p.current_move.id).begins_with("parry_react_"),"精准弹刀仅在真实来袭时触发成功动画")
	check(not stage.training_attacks,"木桩测试来袭默认关闭")
	# Actual Area2D overlaps must damage a target, not just select a new clip.
	stage._reset()
	p.position=Vector2(460,280)
	p.velocity=Vector2.ZERO
	await step(8)
	stage.dummy.set_physics_process(false)
	for key in ["air_light_1","air_light_2","air_light_3"]:
		p._end_attack()
		p.hitstop_frames=0
		p.position=Vector2(460,280)
		p.velocity=Vector2.ZERO
		stage.dummy.hp=stage.dummy.max_hp
		stage.dummy.position=p.position+Vector2(95,0)
		p._set_facing(1)
		p._start_move(stage.moves[key],false)
		for i in stage.moves[key].startup_frames+5:
			if stage.dummy.hp<stage.dummy.max_hp:
				break
			await step(1)
		check(stage.dummy.hp<stage.dummy.max_hp and p.hitstop_frames>0,key+"真实空中碰撞造成伤害与顿帧")
	stage.dummy.set_physics_process(true)
	print("DESKTOP_INTEGRATION_TESTS: ",checks," checks / ",failures.size()," failures")
	stage.free()
	OS.delay_msec(100)
	await process_frame
	quit(0 if failures.is_empty() else 1)
