extends SceneTree
## 开发工具：首页帧率粗测（真实渲染）。
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var t: Control = load("res://scenes/title_cut.tscn").instantiate()
	root.add_child(t)
	current_scene = t
	for i in 30:
		await process_frame
	var start := Time.get_ticks_usec()
	var n := 240
	for i in n:
		await process_frame
	var ms := (Time.get_ticks_usec() - start) / 1000.0
	print("FPS ~= %.1f  avg_frame_ms=%.2f" % [float(n) * 1000.0 / ms, ms / float(n)])
	quit()
