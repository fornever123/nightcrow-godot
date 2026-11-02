extends SceneTree
## Real rain_trial scene, real player physics, native GPU screenshots.
const Buffer := preload("res://scripts/core/input_buffer.gd")
var stage
var p
var center := 0.0
var failures: Array[String] = []
var checks := 0
var output := "E:/00game/work/rain-background-chat/20261028_game_delivery_v001"

func _initialize() -> void:
	call_deferred("run")

func frame(jump := false, hold := false) -> Buffer.Frame:
	var f := Buffer.Frame.new()
	if jump or hold:
		f.actions = [&"jump"]
	if jump:
		f.pressed_this_frame = [&"jump"]
	return f

func step(n: int, f: Buffer.Frame = null) -> void:
	for i in n:
		p.set_injected_frame(frame() if f == null else f)
		await physics_frame
		# Keep the injected edge until the player has consumed this physics tick.
		await process_frame

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		print("FAIL ", label)

func feet() -> float:
	return p.global_position.y + p.foot_offset

func shot(name_: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name_ + ".png"))

func place(x: float, y: float) -> void:
	p.reset_state(Vector2(center + x, y - p.foot_offset))
	await step(65)

func run() -> void:
	stage = load("res://scenes/rain_trial.tscn").instantiate()
	root.add_child(stage)
	await process_frame
	p = stage.player
	center = stage._center_of(0)
	stage._lock_arena()
	stage.encounter.set_physics_process(false)
	stage.encounter.running = false
	stage.encounter.clear_shades()
	stage.hud.help_visible = false
	await step(20)
	stage.encounter.running = false
	stage.encounter.clear_shades()
	var sec: Dictionary = stage.layout.sections[0]
	if OS.get_cmdline_user_args().has("--ship-only"):
		await place(1220,217.76)
		var peak := feet()
		for tick in 200:
			await step(1,frame(tick==0,tick<40))
			peak = minf(peak,feet())
			if tick%10==0:
				print("TRACE ",tick," feet=",feet()," vy=",p.velocity.y," floor=",p.is_on_floor()," state=",p.state)
		print("PEAK ",peak)
		quit()
		return
	for surface in sec.platforms + sec.blocks:
		if float(surface[0]) < 300 or float(surface[0]) > 2450:
			continue
		var x := (float(surface[0]) + float(surface[1])) * 0.5
		var y := float(surface[2])
		await place(x, y - 38.0)
		check(p.is_on_floor() and absf(feet() - y) < 2.0, "real landing x=%.0f y=%.2f got %.2f" % [x,y,feet()])
	# Two consecutive actual jumps, from pawnshop street to both balconies.
	await place(860, 580)
	for target in [269.63, 15.16]:
		await step(1, frame(true))
		await step(29, frame(false, true))
		await step(130)
		check(p.is_on_floor() and absf(feet()-target)<2, "pawnshop real jump to %.2f got %.2f" % [target,feet()])
	await shot("01_真实跳上当铺三层")
	await place(1220, 217.76)
	await shot("02_船具行实际檐板")
	await step(1,frame(true))
	await step(29,frame(false,true))
	await step(130)
	check(p.is_on_floor() and absf(feet()+64.26)<2, "ship eave to actual roof got %.2f" % feet())
	await shot("03_真实跳上船具屋顶")
	await place(1810, 293.94)
	await step(1,frame(true))
	await step(29,frame(false,true))
	await step(130)
	check(p.is_on_floor() and absf(feet()-10.3)<2, "police actual upper balcony got %.2f" % feet())
	await shot("04_真实跳上警署阳台")
	await place(420,580)
	await shot("05_钟楼接缝和真实水面")
	await place(2100,580)
	await shot("06_住宅街面")
	await place(1570,580)
	await shot("07_右段街面")
	var f := FileAccess.open(output.path_join("real_game_verification.json"),FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks":checks,"failures":failures,"scene":"res://scenes/rain_trial.tscn","native_gpu":DisplayServer.get_name()!="headless"},"  "))
	print("RIGHT_ART_CHECKS ",checks," failures ",failures.size())
	quit(0 if failures.is_empty() else 1)
