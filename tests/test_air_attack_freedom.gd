extends SceneTree
## Real keyboard regressions for repeatable aerial attacks and a finite jump budget.
var stage: Node2D
var p: CharacterBody2D
var checks := 0
var failures: Array[String] = []
var jumps: Array[bool] = []
var moves: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		print("FAIL: ", label)

func key(code: Key, down: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = down
	Input.parse_input_event(event)

func ticks(n: int = 1) -> void:
	var target: int = p.tick_count+n
	while p.tick_count < target:
		await process_frame

func fresh() -> void:
	for code in [KEY_W,KEY_J,KEY_SPACE]:
		key(code,false)
	stage._reset()
	p.clear_input_queue()
	p.set_injected_frame(null)
	stage.dummy.position.x = 10000
	await ticks(3)
	jumps.clear()
	moves.clear()

func wait_air_move(limit: int = 40) -> bool:
	for i in limit:
		if p.current_move != null and p.air_combo.has(p.current_move):
			return true
		await ticks()
	return false

func run() -> void:
	stage = load("res://scenes/training.tscn").instantiate()
	root.add_child(stage)
	current_scene = stage
	stage.config.runtime.autoReload = false
	p = stage.player
	p.jumped.connect(func(is_double: bool) -> void: jumps.append(is_double))
	p.move_started.connect(func(move: Resource, _index: int) -> void: moves.append(String(move.id)))

	# Releasing/repressing J while W remains down must not spend the second jump.
	await fresh()
	key(KEY_W,true)
	key(KEY_J,true)
	await ticks()
	check(jumps.size()==1 and p.velocity.y<0,"W+J takes off immediately, like a W-first rising uppercut")
	for i in 40:
		if not p.is_on_floor(): break
		await ticks()
	key(KEY_J,false)
	await ticks(2)
	var budget_before: int = p._air_jumps_left
	key(KEY_J,true)
	await ticks()
	check(await wait_air_move(),"W+J can link into aerial normal J while W is still held")
	check(jumps.size()==1 and p._air_jumps_left==budget_before,"Aerial normal J never spends a jump or re-launches the uppercut")
	check(moves.count("up_strike")==1,"Holding W does not turn every later J into another uppercut")

	# A normal J buffered after the launcher active phase must not be consumed and lost.
	await fresh()
	key(KEY_W,true)
	key(KEY_J,true)
	await ticks()
	for i in 40:
		if not p.is_on_floor(): break
		await ticks()
	key(KEY_W,false)
	key(KEY_J,false)
	await ticks(2)
	p._air_jumps_left=0
	key(KEY_J,true)
	await ticks()
	check(await wait_air_move(),"Uppercut recovery accepts normal aerial J with no jumps left")
	check(p._air_jumps_left==0,"Uppercut-to-air-normal transition leaves exhausted jump budget unchanged")

	# Start high enough to exercise two complete 3-hit loops without a landing reset.
	await fresh()
	p.global_position.y=-15000
	p.velocity=Vector2(0,100)
	p.ground_frames=0
	p.air_frames=p.coyote_frames+1
	p._air_jumps_left=0
	await ticks()
	# Teleporting off the test floor needs one physics tick to update is_on_floor().
	p._air_jumps_left=0
	for attack in 6:
		key(KEY_J,true)
		await ticks()
		key(KEY_J,false)
		var expected := "air_light_%d" % (attack%3+1)
		var found := false
		for i in 24:
			if moves.size()>attack and moves[attack]==expected:
				found=true
				break
			await ticks()
		check(found,"Repeated airborne normal %d starts %s" % [attack+1,expected])
		if not found: break
		for i in 100:
			if p.current_move == null: break
			var mv: Resource=p.current_move
			if p.move_frame>=mv.startup_frames+mv.active_frames+mv.cancel_frame-1: break
			await ticks()
	check(moves.size()>=6,"Aerial three-hit combo repeats without landing, hits or ranged refresh")
	check(jumps.is_empty() and p._air_jumps_left==0,"Repeated aerial attacks never replenish or consume jumps")
	check(p.velocity.y>0,"Whiffed aerial attacks retain ordinary falling motion")

	# Neutral recovery must also permit another J, including after a directional finisher.
	p._end_attack()
	await ticks(2)
	var before: int=moves.size()
	key(KEY_J,true)
	await ticks()
	key(KEY_J,false)
	check(moves.size()==before+1 and p.air_combo.has(p.current_move),"Neutral airborne J can resume a previously started combo")
	p._start_air_finisher(&"slam")
	p._end_attack()
	await ticks(2)
	key(KEY_J,true)
	await ticks()
	key(KEY_J,false)
	check(p.current_move==p.air_combo[0],"Aerial J can restart after a finisher without landing")

	# Three rapid jump presses must still produce only two launches, even during coyote time.
	await fresh()
	key(KEY_SPACE,true)
	await ticks()
	key(KEY_SPACE,false)
	await ticks()
	key(KEY_SPACE,true)
	await ticks()
	check(jumps.size()==2 and jumps[1] and p._air_jumps_left==0,"Early second press consumes the normal double jump")
	key(KEY_SPACE,false)
	await ticks()
	key(KEY_SPACE,true)
	await ticks()
	check(jumps.size()==2,"Coyote time cannot grant a third rapid jump")
	key(KEY_SPACE,false)

	# Measured full jump: preserve height, but remove the very fast ascent / slow descent split.
	await fresh()
	var start_y: float=p.global_position.y
	key(KEY_SPACE,true)
	await ticks()
	var peak_y: float=p.global_position.y
	var rise:=0
	while p.velocity.y<0 and rise<120:
		await ticks()
		rise+=1
		peak_y=minf(peak_y,p.global_position.y)
	var fall:=0
	while not p.is_on_floor() and fall<120:
		await ticks()
		fall+=1
	check(start_y-peak_y>=p.jump_height*0.93 and start_y-peak_y<=p.jump_height*1.06,"Retuned jump retains authored height")
	check(rise>=22 and rise<=25,"Full jump has a less abrupt ascent (%d frames)" % rise)
	check(fall<=rise+2,"Descent is not markedly slower than ascent (%d up / %d down)" % [rise,fall])
	check(p.jump_cut_gravity_scale<=2.0,"Releasing jump uses a gentler short-hop transition")
	for code in [KEY_W,KEY_J,KEY_SPACE]: key(code,false)
	stage.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	print("AIR_ATTACK_FREEDOM_TESTS: %d checks / %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
