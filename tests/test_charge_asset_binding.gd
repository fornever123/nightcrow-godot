extends SceneTree
## Imported charge frames must drive the actual sprite and hit timings.
const Config := preload("res://scripts/core/configuration.gd")
const Timeline := preload("res://scripts/core/animation_timeline.gd")
const Buffer := preload("res://scripts/core/input_buffer.gd")
var checks := 0
var failures: Array[String] = []
var stage: Node2D
var p: CharacterBody2D

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		print("FAIL: ", label)

func step(count: int, held := true) -> void:
	var f := Buffer.Frame.new()
	if held:
		f.actions = [&"attack_light"]
	p.set_injected_frame(f)
	var until: int = p.tick_count + count
	while p.tick_count < until:
		await process_frame

func run() -> void:
	var data := Config.read()
	var sprite: Dictionary = Config.character(data, "player").sprite
	var hold: Dictionary = sprite.animations.get("charge_hold", {})
	var release: Dictionary = sprite.animations.get("charge_slash", {})
	check(hold.get("frames", []).size() == 24, "charging uses only the 24 spinning frames")
	check(release.get("frames", []).size() == 85, "new release uses all 85 source frames")
	check(sprite.get("chargeAnimation", "") == "charge_hold", "charging selects its own clip instead of uppercut")
	if hold.is_empty() or release.get("frames", []).size() != 85:
		finish()
		return
	check(hold.frames[0].get("sourceFrame", 0) == 37 and hold.frames[-1].get("sourceFrame", 0) == 60,
		"charge excludes standing and preparation source frames 1 to 36")
	check(bool(hold.get("loop", false)) and int(hold.get("loopFrame", -1)) == 0,
		"the entire spinning section loops without replaying preparation")
	check(is_equal_approx(Timeline.ticks_before(hold.frames, hold.frames.size()) / float(hold.fps), 1.0), "spin preserves its one second original timing")
	check(is_equal_approx(Timeline.ticks_before(release.frames, 85) / float(release.fps), 212.0/60.0), "release preserves original 212 physics ticks")
	check(hold.frames[0].durationTicks == 3 and hold.frames[1].durationTicks == 2, "alternating original long/short frames preserved")
	check(hold.get("effectsBaked", false) and release.get("effectsBaked", false), "baked source effects are used without duplicate trails")
	check(release.get("sourceFacing", 0) == 1 and release.rootMotionX.size() == 85 and release.rootMotionY.size() == 85, "release has calibrated facing and complete body motion")
	var cm: Resource = Config.moves(data).charge_1
	check(cm.animation == "charge_slash" and cm.direction == 0, "release binds to charge action rather than rising uppercut")
	check(cm.total_frames() == 212 and cm.startup_frames == 48, "release and impact clock match actual imported action")
	check(cm.max_charge_frames == 150, "charge power timing stays 2.5 seconds independently of visual looping")
	stage = load("res://scenes/training.tscn").instantiate()
	root.add_child(stage)
	current_scene = stage
	stage.config.runtime.autoReload = false
	p = stage.player
	stage.dummy.position.x = 10000
	await step(3)
	p._start_charge()
	await step(1)
	var view: Sprite2D = p.get_node("Visual/ActorSprite")
	check(int(hold.frames[view.frame_index].get("sourceFrame", 0)) == 37,
		"charging immediately displays the first spin frame without an idle lead-in")
	await step(19)
	check(view.clip_name == "charge_hold" and view.frame_index > 0, "real charging view plays frames rather than freezing first pose")
	var before: int = view.frame_index
	view._on_jumped(false)
	await step(8)
	check(view.clip_name == "charge_hold" and view.frame_index >= before, "jump event does not restart charge visual clock")
	view._on_landed()
	await step(8)
	check(view.clip_name == "charge_hold" and view.frame_index >= before, "landing event does not restart charge visual clock")
	await step(140)
	check(p.is_charging() and view.frame_index >= 0 and view.frame_index < 24,
		"full charge stays held and continues looping only spinning frames")
	await step(1, false)
	check(p.current_move == p.charge_move, "release selects new attack clip")
	await step(4, false)
	check(view.clip_name == "charge_slash" and view.frame_index > 0, "real release view advances through source attack")
	stage._reset()
	p.clear_input_queue()
	stage.dummy.position.x = 10000
	await step(3, false)
	var floor_y: float = p.global_position.y
	var start_x: float = p.global_position.x
	p._start_charge()
	p.charge_frames = p.charge_move.max_charge_frames
	p._release_charge()
	var peak_y := floor_y
	for i in 80:
		await step(1, false)
		peak_y = minf(peak_y, p.global_position.y)
	check(peak_y < floor_y - 70.0, "ground release moves the real body through the authored short hop")
	check(p.global_position.x > start_x + 200.0, "release advances actual body rather than leaving collision behind its pixels")
	check(absf(p.global_position.y - floor_y) < 3.0, "authored hop returns to the actual floor before recovery")
	stage._reset()
	p.clear_input_queue()
	stage.dummy.position.x = 10000
	p.position.y -= 180
	p.velocity.y = -900
	await step(1, false)
	p._start_charge()
	p.charge_frames = p.charge_move.max_charge_frames
	var air_vy: float = p.velocity.y
	p._release_charge()
	await step(3, false)
	check(p.velocity.y > air_vy and p.velocity.y < 0.0, "air release keeps the existing ascent and normal gravity")
	stage._reset()
	p.clear_input_queue()
	await step(3, false)
	stage.dummy.set_physics_process(false)
	stage.dummy.position = Vector2(p.position.x + 460.0, p.position.y + p.foot_offset - 68.0)
	var dummy_hp: float = stage.dummy.hp
	p._start_charge()
	p.charge_frames = p.charge_move.max_charge_frames
	p._release_charge()
	await step(p.charge_move.startup_frames - 1, false)
	check(stage.dummy.hp == dummy_hp, "new release windup does not damage before authored impact")
	await step(12, false)
	check(stage.dummy.hp < dummy_hp and p.hitstop_frames > 0, "new release collision deals real damage and hitstop at impact")
	stage.free()
	finish()

func finish() -> void:
	print("CHARGE_ASSET_BINDING_TESTS: ",checks," checks / ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
