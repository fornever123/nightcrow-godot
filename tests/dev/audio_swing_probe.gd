extends SceneTree
## 开发工具（音效线 11-01）：雨街里打两遍地面三连（先挥空、再打两只影卒），录下画面和声音，核对三刀各响一次。
## 需要真实渲染（不加 --headless）：
## engine/Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/dev/audio_swing_probe.gd --resolution 1280x720 --fixed-fps 60 --write-movie .runtime/audio-pg3/swing.avi
const Buffer := preload("res://scripts/core/input_buffer.gd")
const Shade := preload("res://scripts/night/shade.gd")
var stage
var p
var c0 := 0.0
var heard: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func fr(actions: Array[StringName] = [], edges: Array[StringName] = []) -> Buffer.Frame:
	var f := Buffer.Frame.new()
	f.actions = actions
	f.pressed_this_frame = edges
	return f


func frames(n: int, f: Buffer.Frame = null) -> void:
	for i in n:
		p.set_injected_frame(f if f != null else fr())
		await physics_frame
		var ev: String = stage.audio.last_event
		if ev.begins_with("swing_") and (heard.is_empty() or heard.back() != ev):
			heard.append(ev)
		stage.audio.last_event = ""


func combo(with_shades: bool) -> void:
	stage.encounter.clear_shades()
	stage.encounter.running = false
	p.reset_state(Vector2(c0 - 1180.0, 580.0 - p.foot_offset))
	p._set_facing(1)
	if with_shades:
		for x in [-1100.0, -1050.0]:
			var sh: Node2D = Node2D.new()
			sh.set_script(Shade)
			sh.setup(Shade.Kind.GRUNT, p, stage.floor_y, 1.0)
			sh.position = Vector2(c0 + x, 520.0)
			sh.terrain = stage.terrain
			stage.add_child(sh)
			sh.spawn_frames = 0
			sh.active = false
			sh.facing = -1
			stage._on_shade_spawned(sh)
	await frames(40)
	for hit in 3:
		await frames(1, fr([&"attack_light"], [&"attack_light"]))
		await frames(14)
	await frames(70)


func run() -> void:
	stage = load("res://scenes/rain_street.tscn").instantiate()
	root.add_child(stage)
	await process_frame
	p = stage.player
	stage.hud.help_visible = false
	await frames(30)
	c0 = stage._center_of(0)
	await combo(false)
	await combo(true)
	print("SWING_EVENTS ", heard)
	var ok := heard == ["swing_l1", "swing_l2", "swing_l3", "swing_l1", "swing_l2", "swing_l3"]
	print("SWING_PROBE ", "OK" if ok else "MISMATCH")
	quit(0 if ok else 1)
