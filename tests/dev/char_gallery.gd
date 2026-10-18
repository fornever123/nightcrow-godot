extends SceneTree
## 开发工具：角色序列帧画质对比图（需要真实渲染）
##   DISPLAY=:99 MAT=hq FRAMES="idle:0,jump:4" godot --path . --script res://tests/dev/char_gallery.gd --resolution 1280x720
## MAT=none 用旧的普通双线性（对比用）；MAT=hq（默认）高清采样；SHARP/EDGE 临时改锐化/边缘参数；
## BG="#18202e" 背景色；SCALE=1.0 额外缩放；OUT 输出前缀（默认 res://.runtime/gallery/g），每 10 格一张 OUT_<页>.png。
const Art := preload("res://scripts/presentation/art_cache.gd")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/battle.json"))
	var setup: Dictionary = cfg.characters[0].sprite
	var mat := OS.get_environment("MAT")
	Art.premultiply = mat != "none"
	Art.reset(setup)
	if Art.premultiply:
		var m := Art.hq_material()
		if OS.get_environment("SHARP") != "":
			m.set_shader_parameter("hq_sharp", float(OS.get_environment("SHARP")))
		if OS.get_environment("EDGE") != "":
			m.set_shader_parameter("hq_edge", float(OS.get_environment("EDGE")))
	var out := OS.get_environment("OUT")
	if out == "":
		out = ProjectSettings.globalize_path("res://.runtime/gallery/g")
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	var bg := Color(OS.get_environment("BG")) if OS.get_environment("BG") != "" else Color("#18202e")
	var extra := float(OS.get_environment("SCALE")) if OS.get_environment("SCALE") != "" else 1.0
	var items: Array = []
	for it in OS.get_environment("FRAMES").split(",", false):
		var parts: PackedStringArray = it.split(":")
		items.append([parts[0], int(parts[1])])
	var page := 0
	var i := 0
	while i < items.size():
		var holder := Node2D.new()
		root.add_child(holder)
		var rect := ColorRect.new()
		rect.color = bg
		rect.size = Vector2(1280, 720)
		holder.add_child(rect)
		for k in 10:
			if i >= items.size():
				break
			var anim: String = items[i][0]
			var idx: int = items[i][1]
			var cx := 128.0 + 256.0 * float(k % 5)
			var cy := 330.0 + 360.0 * float(k / 5)
			var spr := Sprite2D.new()
			spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			holder.add_child(spr)
			var clip: Dictionary = setup.animations.get(anim, {})
			if idx < clip.get("frames", []).size():
				Art.apply(spr, clip.frames[idx], float(setup.get("displayScale", 1.0)) * extra)
				spr.scale.x *= float(clip.get("sourceFacing", 1))
			spr.position = Vector2(cx, cy)
			var label := Label.new()
			label.text = "%s:%d" % [anim, idx]
			label.position = Vector2(cx - 120, cy + 4)
			label.add_theme_font_size_override("font_size", 14)
			holder.add_child(label)
			i += 1
		for f in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_viewport().get_texture().get_image().save_png("%s_%d.png" % [out, page])
		print("page ", page)
		holder.queue_free()
		page += 1
	quit()
