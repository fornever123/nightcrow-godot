extends SceneTree
## 画面重构样板屏实机截图 / 录帧（原生窗口跑，不加 --headless）
## 环境变量：RD_OUT 输出目录；RD_MODE = shots | video

var stage: Node2D
var out := ""


func _initialize() -> void:
	call_deferred("_run")


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _save(fname: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	if img.get_format() == Image.FORMAT_RGBAH:
		# HDR 2D：存线性半精度原始数据，交给 tools/art/rain_redesign_raw2png.py 转 sRGB
		var f := FileAccess.open(out.path_join(fname.get_basename() + ".rawh"), FileAccess.WRITE)
		f.store_32(img.get_width())
		f.store_32(img.get_height())
		f.store_buffer(img.get_data())
		f.close()
	else:
		img.save_png(out.path_join(fname))
	print("SHOT ", fname)


func _put(x: float) -> void:
	var p: CharacterBody2D = stage.player
	p.global_position = Vector2(x, stage.FLOOR - p.foot_offset)
	p.velocity = Vector2.ZERO
	stage.camera.position = Vector2(x, stage.CAM_Y)
	stage.camera.reset_smoothing()


func _run() -> void:
	out = OS.get_environment("RD_OUT")
	DirAccess.make_dir_recursive_absolute(out)
	stage = load("res://scenes/dev/rain_redesign_sample.tscn").instantiate()
	root.add_child(stage)
	current_scene = stage
	await _wait(20)
	var mode := OS.get_environment("RD_MODE")
	if mode == "" or mode == "shots":
		var xs := [200.0, 760.0, 1500.0, 2300.0, 3000.0, 3900.0, 5200.0]
		for i in xs.size():
			_put(xs[i])
			await _wait(150 if i == 0 else 90)
			await _save("rd_%02d_x%05d.png" % [i, int(xs[i])])
	if mode == "video":
		_put(-600.0)
		await _wait(120)
		stage.auto_run = true
		for f in 420:
			await process_frame
			if f % 2 == 0:
				await _save("v_%04d.png" % (f / 2))
		stage.auto_run = false
	print("RD_DONE")
	quit()
