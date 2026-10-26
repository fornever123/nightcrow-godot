extends SceneTree
const Buffer := preload("res://scripts/core/input_buffer.gd")
const Move := preload("res://scripts/core/move_definition.gd")
var p
var checks := 0
var failures: Array[String] = []
class Attacker extends Node:
	var parried := 0
	func on_parried(_cause: Node) -> void:
		parried += 1

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		print("FAIL: ", label)

func input(actions: Array[StringName] = [], edges: Array[StringName] = [], axis := Vector2.ZERO) -> Buffer.Frame:
	var f := Buffer.Frame.new()
	f.actions = actions
	f.pressed_this_frame = edges
	f.axis = axis
	return f

func step(n: int, f: Buffer.Frame = null) -> void:
	p.set_injected_frame(input() if f == null else f)
	var until: int = p.tick_count + n
	while p.tick_count < until:
		await process_frame

func move(id: String, air := false) -> Resource:
	var m := Move.new()
	m.id = StringName(id)
	m.is_air = air
	m.startup_frames = 1
	m.active_frames = 1
	m.recovery_frames = 12
	m.cancel_frame = 1
	m.hitstop_frames = 0
	return m

func reset_at(pos := Vector2(0, 316)) -> void:
	p.reset_state(pos)
	await step(4)

func run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	var floor_body := StaticBody2D.new()
	var floor_shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(4000, 40)
	floor_shape.shape = rect
	floor_body.add_child(floor_shape)
	floor_body.position = Vector2(0, 420)
	world.add_child(floor_body)
	p = load("res://scenes/actors/player.tscn").instantiate()
	world.add_child(p)
	var has_air := false
	for prop in p.get_property_list():
		if prop.name == "air_combo": has_air = true
	check(has_air, "independent air combo is available")
	if not has_air:
		world.free()
		quit(1)
		return
	p.light_combo = [move("ground1"), move("ground2"), move("ground3")]
	p.air_combo = [move("air1", true), move("air2", true), move("air3", true)]
	for m in p.air_combo:
		m.air_suspend_frames = 12
		m.air_gravity_scale = 0.1
	var frames: Array = []
	for i in 6: frames.append({"durationTicks": 1})
	p.set_meta("character", {"sprite": {"locomotion": {"enabled": true, "turnLeft": {"animation": "turn_left", "flipFrame": 2, "cancelFrame": 1}}, "animations": {"turn_left": {"fps": 30, "frames": frames}}, "airCombo": {"maxSuspendFrames": 20}}, "guard": {"enabled": true, "parryWindowFrames": 3}})
	await reset_at()
	await step(10, input([&"move_right"], [], Vector2.RIGHT))
	await step(1, input([&"move_left"], [], Vector2.LEFT))
	check(p.locomotion_animation == "turn_left" and p.facing == 1, "reverse run starts turn before facing flip")
	var clock: float = p.locomotion_clock
	await step(2, input([&"move_left"], [], Vector2.LEFT))
	check(p.locomotion_clock > clock, "held reverse direction does not restart turn")
	await step(5, input([&"move_left"], [], Vector2.LEFT))
	check(p.facing == -1, "turn flips at configured source frame")
	var character: Dictionary = p.get_meta("character").duplicate(true)
	character.sprite.locomotion.turnLeft.cancelFrame = 3
	character.sprite.locomotion.turnRight = {"animation": "turn_right", "flipFrame": 2, "cancelFrame": 3}
	character.sprite.animations.turn_right = {"fps": 30, "frames": frames}
	character.sprite.animations.guard_start = {"fps": 30, "frames": [{"durationTicks": 2}, {"durationTicks": 5}]}
	character.sprite.guard = {"enabled": true, "parryWindowFrames": 8, "startupAnimation": "guard_start", "holdAnimation": "guard_hold"}
	p.set_meta("character", character)
	await reset_at()
	p._set_facing(1)
	await step(10, input([&"move_right"], [], Vector2.RIGHT))
	await step(1, input([&"move_left"], [], Vector2.LEFT))
	await step(1, input([&"move_right"], [], Vector2.RIGHT))
	check(p.locomotion_animation == "turn_left" and p.input_direction == 1, "latest direction is retained before turn cancel point")
	await step(5, input([&"move_right"], [], Vector2.RIGHT))
	check(p.locomotion_animation == "turn_right", "cancel point redirects turn to newest input without waiting for full old clip")
	await step(5, input([&"move_right"], [], Vector2.RIGHT))
	check(p.facing == 1 and p.velocity.x >= 0, "redirected turn faces and accelerates toward newest direction")
	# No artificial hover remains: give this no-restart test enough fall distance.
	await reset_at(Vector2(0, -1800))
	await step(8)
	var press := input([&"attack_light"], [&"attack_light"])
	await step(5, press)
	check(p.current_move != null and p.current_move.id == &"air1", "one J edge starts only first air attack")
	await step(1, input([&"attack_light"], [&"attack_light"]))
	check(p.current_move.id == &"air2" and p.combo_index == 0, "new edge chains independent second air attack")
	await step(4)
	await step(1, input([&"attack_light"], [&"attack_light"]))
	check(p.current_move.id == &"air3", "third J edge starts air finisher")
	await step(20)
	await step(1, input([&"attack_light"], [&"attack_light"]))
	check(not p.is_on_floor() and p.current_move == p.air_combo[0], "air combo restarts at the first attack without requiring landing")
	check(p.air_suspend_used == 0, "legacy suspend settings cannot pause an ordinary airborne attack")
	await step(100)
	check(p.is_on_floor() and p.air_combo_index == 0, "air combo truly lands and resets")
	await step(1, input([&"attack_light"], [&"attack_light"]))
	check(p.current_move.id == &"ground1", "landing returns J to ground first attack")
	await reset_at(Vector2(0, -1800))
	p.ranged_move = move("ranged")
	p.ranged_move.command = &"ranged"
	await step(8)
	await step(1, input([&"attack_light"], [&"attack_light"]))
	await step(4)
	for i in 20:
		await step(1, input([&"attack_ranged"], [&"attack_ranged"]))
	check(p.current_move == null and p.air_combo_index == 1, "K cannot freeze or refund independent air combo")
	await reset_at()
	var reaction := move("parry_success")
	p.parry_reactions = [reaction]
	await step(1, input([&"parry"], [&"parry"]))
	await step(1)
	check(p.is_parrying() and p.is_guarding(), "quick L release retains the remaining precise window")
	await step(6)
	check(p.is_parrying(), "released L remains precise through frame seven")
	await step(1)
	check(not p.is_parrying() and not p.is_guarding(), "released L exits exactly when eight-frame precise window expires")
	await reset_at()
	await step(1, input([&"parry"], [&"parry"]))
	check(p.is_guarding() and p.is_parrying() and p.current_move == null, "L enters guard without playing successful parry")
	await step(9, input([&"parry"]))
	check(not p.is_parrying() and p.guard_animation == "guard_start", "precise window ends while cumulative startup animation continues")
	await step(6, input([&"parry"]))
	check(p.guard_animation == "guard_hold", "startup changes to held pose after its full durationTicks timeline")
	var before: float = p.hp
	check(p.take_hit(p.light_combo[0], -p.facing, p.global_position) and p.hp == before, "held guard blocks after precise parry window")
	await step(5)
	check(not p.is_guarding(), "releasing L exits guard")
	var attacker := Attacker.new()
	world.add_child(attacker)
	p.parry_reactions = [move("parry1"), move("parry2"), move("parry3")]
	for variant in 3:
		await reset_at()
		await step(1, input([&"parry"], [&"parry"]))
		before = p.hp
		check(p.take_hit(p.light_combo[0], -p.facing, p.global_position, 0, false, 1, attacker) and p.hp == before, "precise guard parries actual incoming attack")
		check(p.current_move == p.parry_reactions[variant] and not p.is_parrying(), "successful parry selects variant without reopening parry window")
	check(attacker.parried == 3, "each precise parry calls actual attacker once")
	p.guard_reactions = [move("guard_hit1"), move("guard_hit2")]
	await reset_at()
	await step(1, input([&"parry"], [&"parry"]))
	await step(9, input([&"parry"]))
	before = p.hp
	check(p.take_hit(p.light_combo[0], -p.facing, p.global_position, 0, false, 1, attacker), "first sustained guard hit enters block reaction")
	check(p.take_hit(p.light_combo[0], -p.facing, p.global_position, 0, false, 1, attacker) and p.hp == before, "holding L blocks a second real hit during block reaction")
	await step(1)
	check(not p.take_hit(p.light_combo[0], -p.facing, p.global_position, 0, false, 1, attacker) and p.hp < before, "released L does not guard during reaction")
	await reset_at()
	await step(1, input([&"parry"], [&"parry"]))
	before = p.hp
	var prior_parries := attacker.parried
	p.take_hit(p.light_combo[0], -p.facing, p.global_position, 0, false, 1, attacker)
	check(p.take_hit(p.light_combo[0], -p.facing, p.global_position, 0, false, 1, attacker) and p.hp == before and attacker.parried == prior_parries + 1, "holding L during successful parry reaction blocks next hit without second parry")
	check(not p.take_hit(p.light_combo[0], p.facing, p.global_position, 0, false, 1, attacker) and p.hp < before, "reaction guard does not protect attacks from behind")
	await reset_at()
	await step(1, input([&"parry"], [&"parry"]))
	await step(9, input([&"parry"]))
	p.take_hit(p.light_combo[0], -p.facing, p.global_position, 0, false, 1, attacker)
	p.hitstop_frames = 0
	await step(1, input([&"parry", &"attack_light"], [&"attack_light"]))
	check(p.guard_reactions.has(p.current_move) and p.is_guarding(), "held guard rejects attack input during its success reaction")
	await reset_at()
	var dash := move("dash")
	dash.dash_distance = 200
	dash.movement_timeline = [{"time": 0.0, "distance": 0.0}, {"time": 1.0, "distance": 200.0}]
	p.dash_move = dash
	p._set_facing(1)
	var x: float = p.position.x
	await step(1, input([&"dash_modifier", &"attack_light"], [&"attack_light"], Vector2.RIGHT))
	check(p.current_move == dash, "Shift J selects dash")
	await step(8, input([&"move_left"], [], Vector2.LEFT))
	check(p.position.x > x + 80 and p.facing == 1, "dash timeline moves in fixed direction despite reverse input")
	var wall := StaticBody2D.new()
	var wall_shape := CollisionShape2D.new()
	var wall_rect := RectangleShape2D.new()
	wall_rect.size = Vector2(40, 800)
	wall_shape.shape = wall_rect
	wall.add_child(wall_shape)
	wall.position = Vector2(160, 0)
	world.add_child(wall)
	await reset_at()
	await step(1, input([&"dash_modifier", &"attack_light"], [&"attack_light"], Vector2.RIGHT))
	await step(20)
	check(p.position.x < 116, "dash displacement uses physical wall collision")
	p.dash_left_move = move("dash_left")
	p.dash_left_move.recovery_frames = 5
	p.dash_left_move.dash_distance = 80
	await reset_at()
	await step(1, input([&"dash_modifier", &"attack_light"], [&"attack_light"], Vector2.LEFT))
	check(p.current_move == p.dash_left_move, "left dash uses independent source move and duration")
	await step(10)
	check(p.current_move == null and p.position.x < -60, "left dash completes its own timeline")
	await reset_at()
	p._set_facing(1)
	p.hitstop_frames = 3
	await step(1, input([&"dash_modifier", &"attack_light"], [&"attack_light"], Vector2.LEFT))
	await step(3)
	check(p.current_move == p.dash_left_move and p.facing == -1, "hitstop buffers Shift J modifier and direction after release")
	await reset_at()
	p.hitstop_frames = 3
	await step(1, input([&"attack_light"], [&"attack_light"]))
	await step(3, input([&"dash_modifier"]))
	check(p.current_move == p.light_combo[0], "later Shift cannot change buffered ordinary J into dash")
	# Removing the new configuration restores the original single-air-move path.
	p.set_meta("character", {})
	p.air_combo = []
	p.air_up_move = move("legacy_air", true)
	p.parry_move = move("legacy_parry")
	p.parry_move.is_parry = true
	await reset_at(Vector2(0, -400))
	await step(8)
	await step(1, input([&"attack_light"], [&"attack_light"]))
	check(p.current_move == p.air_up_move, "old configs retain single air_up fallback")
	await reset_at()
	await step(1, input([&"parry"], [&"parry"]))
	check(p.current_move == p.parry_move and not p.is_guarding(), "old configs retain timed parry move")
	print("ACTION_FLOW_TESTS: %d checks / %d failures" % [checks, failures.size()])
	world.free()
	quit(0 if failures.is_empty() else 1)
