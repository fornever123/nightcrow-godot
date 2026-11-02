extends SceneTree
## 开发工具（音效线 11-01）：雨街里地面三连打两只影卒，再放主角受击轻 / 重各一下，录下画面和声音，
## 核对命中 / 受击都走 Bloody Blade 原声（hit_light ×2、hit_finisher、hurt、hurt_heavy）。
## 主角受击直接调 audio.play_hurt（游戏里被打时走的就是它）。需要真实渲染（不加 --headless）：
## engine/Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/dev/audio_hit_probe.gd --resolution 1280x720 --fixed-fps 60 --write-movie .runtime/audio-hit/hit.avi
const Buffer := preload("res://scripts/core/input_buffer.gd")
const Shade := preload("res://scripts/night/shade.gd")
var stage
var p
var heard: Array[String] = []
var all_events: Array[String] = []   ## 所有事件和帧号，方便对照录屏里的响度
var frame_no := 0


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
		frame_no += 1
		var ev: String = stage.audio.last_event
		if not ev.is_empty():
			all_events.append("%d:%s" % [frame_no, ev])
		if (ev.begins_with("hit_") or ev.begins_with("hurt") or ev.begins_with("swing_")) \
				and (heard.is_empty() or heard.back() != ev):
			heard.append(ev)
		stage.audio.last_event = ""


func run() -> void:
	stage = load("res://scenes/rain_street.tscn").instantiate()
	root.add_child(stage)
	await process_frame
	p = stage.player
	stage.hud.help_visible = false
	await frames(30)
	var c0: float = stage._center_of(0)
	stage.encounter.clear_shades()
	stage.encounter.running = false
	p.reset_state(Vector2(c0 - 1180.0, 580.0 - p.foot_offset))
	p._set_facing(1)
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
	stage.audio.play_hurt(0.4)
	await frames(45)
	stage.audio.play_hurt(0.8)
	await frames(60)
	print("HIT_EVENTS ", heard)
	print("ALL_EVENTS ", all_events)
	var ok := heard == ["swing_l1", "hit_light", "swing_l2", "hit_light", "swing_l3", "hit_finisher", "hurt", "hurt_heavy"]
	print("HIT_PROBE ", "OK" if ok else "MISMATCH")
	quit(0 if ok else 1)
