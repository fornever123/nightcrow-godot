extends SceneTree
## 开发工具：把影卒/甲影各状态摆一排截图，检查程序绘制效果（需要真实渲染，同上）。
const Shade := preload("res://scripts/night/shade.gd")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.18, 0.3, 0.55)
	bg.size = Vector2(1280, 720)
	root.add_child(bg)
	var dark := ColorRect.new()
	dark.color = Color(0.06, 0.07, 0.12)
	dark.position = Vector2(0, 360)
	dark.size = Vector2(1280, 360)
	root.add_child(dark)
	var states := [Shade.State.APPROACH, Shade.State.WINDUP, Shade.State.STRIKE, Shade.State.STUNNED, Shade.State.LAUNCHED, Shade.State.HITSTUN]
	var list := []
	for row in 2:
		for i in states.size():
			var s = Shade.new()
			s.setup(Shade.Kind.GRUNT if row == 0 else Shade.Kind.BRUTE, null, 300.0 + row * 340.0)
			root.add_child(s)
			s.set_physics_process(false)
			s.position = Vector2(110 + i * 210, 300.0 + row * 340.0 - (60.0 if row == 0 else 76.0))
			s.spawn_frames = 0
			s.state = states[i]
			s.facing = 1 if i % 2 == 0 else -1
			s.anim_t = 1.3 + i
			s.state_frames = int(s.spec.windup) - 4 if states[i] == Shade.State.WINDUP else 2
			s.poise = s.max_poise * 0.6
			s.hp = s.max_hp * 0.7
			list.append(s)
	for k in 3:
		for s in list:
			s.queue_redraw()
		await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://.runtime") + "/shade_gallery.png")
	quit()
