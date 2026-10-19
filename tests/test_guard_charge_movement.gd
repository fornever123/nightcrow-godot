extends SceneTree
## Charge and guard are defensive/committed stances, not movement locks.
const Buffer := preload("res://scripts/core/input_buffer.gd")
const Training := preload("res://scenes/training.tscn")
const Config := preload("res://scripts/core/configuration.gd")

var stage: Node2D
var p: CharacterBody2D
var failures: Array[String] = []
var checks := 0
var ranged_fires := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		print("FAIL: ", label)

func _on_ranged_fired(_projectile: Node) -> void:
	ranged_fires += 1

func frame(actions: Array[StringName] = [], edges: Array[StringName] = [], axis := Vector2.ZERO) -> Buffer.Frame:
	var f := Buffer.Frame.new()
	f.actions = actions
	f.pressed_this_frame = edges
	f.axis = axis
	return f

func step(input: Buffer.Frame = null) -> void:
	p.set_injected_frame(frame() if input == null else input)
	var target: int = p.tick_count + 1
	while p.tick_count < target:
		await process_frame

func reset_stage() -> void:
	stage._reset()
	p.clear_input_queue()
	stage.dummy.position = Vector2(10000, stage.config.stage.bounds.floorY - 68)
	await step()

func add_one_way_platform(top_y: float) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 32
	var collider := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(500.0, 10.0)
	collider.shape = shape
	collider.one_way_collision = true
	body.add_child(collider)
	body.position = Vector2(450.0, top_y + 5.0)
	stage.add_child(body)
	p.one_way_mask = 32
	p.collision_mask |= p.one_way_mask

func run() -> void:
	stage = Training.instantiate()
	root.add_child(stage)
	current_scene = stage
	stage.config.runtime.autoReload = false
	p = stage.player
	p.ranged_fired.connect(_on_ranged_fired)
	await process_frame
	await process_frame

	var character: Dictionary = p.get_meta("character", {})
	var guard: Dictionary = character.get("sprite", {}).get("guard", character.get("guard", {}))
	var charge_scale: Variant = p.get("charge_movement_scale")
	check(charge_scale != null and is_equal_approx(float(charge_scale), 0.85), "charge movement scale is 85 percent")
	check(is_equal_approx(float(guard.get("movementScale", 0.0)), 0.85), "guard movement scale is 85 percent")
	check(is_equal_approx(float(guard.get("startupAnimationSpeed", 0.0)), 5.0), "guard startup animation is compressed fivefold")
	var tuned_config: Dictionary = stage.config.duplicate(true)
	tuned_config.characters[0].chargeMovementScale = 0.55
	var tuned_charge: Resource = Config.moves(tuned_config).charge_1
	check(is_equal_approx(tuned_charge.movement_scale, 0.55)
		and is_equal_approx(tuned_charge.startup_movement_scale, 0.55)
		and is_equal_approx(tuned_charge.recovery_movement_scale, 0.55),
		"one modifier charge-speed setting also tunes every release phase")
	await reset_stage()
	p._start_guard(true)
	var guard_x := p.global_position.x
	for i in 30:
		await step(frame([&"parry", &"move_right"], [], Vector2.RIGHT))
	var guard_distance := p.global_position.x - guard_x
	check(guard_distance > p.speed * 0.85 * 0.25,
		"guard startup and hold keep moving near 85 percent speed (distance %.1f)" % guard_distance)
	var guard_right_x := p.global_position.x
	for i in 20:
		await step(frame([&"parry", &"move_left"], [], Vector2.LEFT))
	check(p.facing == -1 and p.global_position.x < guard_right_x,
		"guard steering turns normally while L remains held")
	await reset_stage()
	p._start_guard(true)
	var startup_ticks := 0
	while startup_ticks < 8 and p.guard_animation != String(guard.get("holdAnimation", "guard_hold")):
		startup_ticks += 1
		await step(frame([&"parry"]))
	check(startup_ticks <= 8 and p.guard_animation == String(guard.get("holdAnimation", "guard_hold")),
		"guard raise reaches held pose within eight physics ticks")

	# Charge begins without deleting momentum, then keeps moving at the configured scale.
	await reset_stage()
	p.velocity.x = 400.0
	p._start_charge()
	check(p.charge_frames >= 0 and p.velocity.x > 0.0, "starting charge preserves existing horizontal momentum")
	var charge_x := p.global_position.x
	for i in 24:
		await step(frame([&"attack_light", &"move_right"], [], Vector2.RIGHT))
	var charge_distance := p.global_position.x - charge_x
	check(charge_distance > p.speed * 0.85 * 0.18 and p.charge_frames >= 0,
		"sustained charge moves near 85 percent speed (distance %.1f)" % charge_distance)
	var charge_right_x := p.global_position.x
	for i in 10:
		await step(frame([&"attack_light", &"move_left"], [], Vector2.LEFT))
	check(p.facing == -1 and p.global_position.x < charge_right_x,
		"charge steering turns normally without ending the charge")
	var jump_y := p.global_position.y
	await step(frame([&"attack_light", &"move_right", &"jump"], [&"jump"], Vector2.RIGHT))
	check(p.charge_frames >= 0 and p.global_position.y < jump_y,
		"jumping during charge keeps charging and uses normal upward movement")
	var vy_after_jump := p.velocity.y
	for i in 5:
		await step(frame([&"attack_light", &"move_right", &"jump"], [], Vector2.RIGHT))
	check(p.charge_frames >= 0 and p.velocity.y > vy_after_jump and p.velocity.y < 0.0,
		"charge jump follows ordinary gravity instead of freezing vertical speed")
	var release_x := p.global_position.x
	var release_y := p.global_position.y
	await step(frame([&"move_right"], [], Vector2.RIGHT))
	check(p.charge_frames < 0 and p.current_move == p.charge_move,
		"releasing charge enters the release move without losing its action tick")
	check(p.global_position.x > release_x and p.global_position.y != release_y,
		"charge release tick still advances horizontal and vertical physics")
	await reset_stage()
	p._start_charge()
	var auto_cap: int = p.charge_move.max_charge_frames
	for i in auto_cap - 1:
		await step(frame([&"attack_light", &"move_right"], [], Vector2.RIGHT))
	var auto_release_x := p.global_position.x
	await step(frame([&"attack_light", &"move_right"], [], Vector2.RIGHT))
	check(p.charge_frames < 0 and p.current_move == p.charge_move,
		"full charge auto-releases into the charge move")
	check(p.global_position.x > auto_release_x and p.velocity.x > 0.0,
		"auto-release preserves momentum and advances movement on its release tick")

	# Guard allows normal jump and second jump, with L still active.
	await reset_stage()
	p._start_guard(true)
	var ground_y := p.global_position.y
	await step(frame([&"parry", &"jump"], [&"jump"]))
	check(p.is_guarding() and p.velocity.y < 0.0 and p.global_position.y < ground_y,
		"guard remains active through a normal first jump")
	for i in p.coyote_frames + 1:
		await step(frame([&"parry"]))
	await step(frame([&"parry", &"jump"], [&"jump"]))
	check(p.is_guarding() and p._air_jumps_left == 0 and p.velocity.y < 0.0,
		"guard remains active through the normal double jump")
	await reset_stage()
	var platform_top: float = stage.config.stage.bounds.floorY - 120.0
	add_one_way_platform(platform_top)
	p.reset_state(Vector2(450.0, platform_top - p.foot_offset))
	for i in 8:
		await step()
	check(p.standing_on_one_way(), "drop-through setup lands on a real one-way physics platform")
	p._start_guard(true)
	await step(frame([&"parry", &"jump"], [&"jump"], Vector2.DOWN))
	check(p.is_guarding() and p.is_dropping_through(),
		"held guard preserves normal down+jump platform drop-through")

	# Guard blocks J, K, and dash even when edges arrive during hitstop.
	await reset_stage()
	p._start_guard(true)
	p.hitstop_frames = 3
	ranged_fires = 0
	await step(frame([&"parry", &"attack_light", &"attack_ranged", &"dash_modifier"],
		[&"attack_light", &"attack_ranged"], Vector2.RIGHT))
	await step(frame([&"parry", &"attack_light", &"attack_ranged", &"dash_modifier"], [], Vector2.RIGHT))
	await step(frame([&"parry", &"attack_light", &"attack_ranged", &"dash_modifier"], [], Vector2.RIGHT))
	await step(frame([&"parry", &"attack_light", &"attack_ranged", &"dash_modifier"], [], Vector2.RIGHT))
	check(p.is_guarding() and p.current_move == null and p.charge_frames < 0 and ranged_fires == 0,
		"held guard consumes buffered J/K/dash presses without attacking after hitstop")

	# A hit during startup swaps the sprite to its success reaction immediately.
	await reset_stage()
	p._start_guard(true)
	await step(frame([&"parry"]))
	var hp_before: float = p.hp
	var blocked: bool = p.take_hit(p.light_combo[0], -p.facing, p.global_position)
	var view: Node = p.get_node("Visual/ActorSprite")
	var block_move: Resource = p.guard_reactions[0]
	var blocked_damage: float = p.light_combo[0].damage * float(guard.get("damageMultiplier", 0.2))
	check(blocked and is_equal_approx(p.hp, hp_before - blocked_damage) and p.current_move == block_move,
		"incoming hit during raise immediately selects block-success reaction")
	check(view.clip_name == block_move.animation,
		"view switches from guard raise to block-success pose on the same tick")

	# A precise parry has a single configured window; the success reaction isn't another window.
	await reset_stage()
	p._start_guard(true)
	await step(frame([&"parry"]))
	await step(frame([&"parry"]))
	var parried: bool = p.take_hit(p.light_combo[0], -p.facing, p.global_position, 0.0, false, 1.0, stage.dummy)
	check(parried and p.current_move == p.parry_reactions[0] and not p.is_parrying(),
		"startup hit selects parry-success reaction without reopening precise parry")
	var vx0 := p.velocity.x
	var y0 := p.global_position.y
	for i in 4:
		await step(frame([&"parry", &"move_right"], [], Vector2.RIGHT))
	check(p.is_guarding() and p.velocity.x > vx0 and p.global_position.x > 450.0,
		"held guard-success reaction allows 85-percent movement")
	check(p.current_move == p.parry_reactions[0], "held L does not restart guard raise after success reaction")

	# The ultimate consumes J+K before normal combat dispatch, so test it enabled.
	await reset_stage()
	p.ult_enabled = true
	p.ult_energy = p.ult_max
	await step(frame([&"parry", &"attack_light", &"attack_ranged"],
		[&"parry", &"attack_light", &"attack_ranged"]))
	check(p.is_guarding() and not p.is_ult() and is_equal_approx(p.ult_energy, p.ult_max),
		"held guard blocks an otherwise-ready J+K ultimate without spending energy")
	await step()
	check(not p.is_ult() and p.current_move == null,
		"guarded J+K does not become a buffered ultimate on release")
	p.ult_enabled = false
	await reset_stage()
	await step(frame([&"parry", &"jump"], [&"parry", &"jump"]))
	check(p.is_guarding() and p.is_parrying() and p.velocity.y < 0.0,
		"L plus jump defends immediately on the very first input tick")

	stage.queue_free()
	await process_frame
	OS.delay_msec(100)
	await process_frame
	print("GUARD_CHARGE_MOVEMENT_TESTS: %d checks / %d failures" % [checks, failures.size()])
	quit(1 if not failures.is_empty() else 0)
