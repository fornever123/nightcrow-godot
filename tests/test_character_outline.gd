extends SceneTree
## Requires actual rendering (do not use --headless). Outputs a diagnostic PNG under .runtime.
var checks := 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Outline test requires an OpenGL window; run without --headless.")
		quit(2)
		return
	var vp := SubViewport.new()
	vp.size = Vector2i(400, 110)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var material := ShaderMaterial.new()
	material.shader = load("res://assets/shaders/char_light.gdshader")
	material.set_shader_parameter("ambient", Vector3.ONE)
	material.set_shader_parameter("desat", 0.0)
	material.set_shader_parameter("shadow_lift", Vector3.ZERO)
	material.set_shader_parameter("moon_amt", 0.0)
	material.set_shader_parameter("warm", 0.0)
	material.set_shader_parameter("ol_width", 1.1)
	material.set_shader_parameter("hq_sharp", 0.5)
	material.set_shader_parameter("hq_edge", 1.03)
	var origins: Array[Vector2i] = []
	for i in 6:
		var factor: int = [1, 2, 4, 4, 1, 4][i]
		var image := Image.create(32*factor, 32*factor, false, Image.FORMAT_RGBA8)
		image.fill(Color(0,0,0,0))
		var fill := Color(0.2, 0.65, 0.3, 1.0) if i != 5 else Color(0.7, 0.2, 1.0, 1.0)
		# Case 4 touches the texture boundaries; its inner border must still be black.
		image.fill_rect(Rect2i(0,0,32*factor,32*factor) if i == 4 else Rect2i(6*factor,6*factor,20*factor,20*factor), fill)
		if i == 0:
			image.fill_rect(Rect2i(13,13,6,6), Color.WHITE)
		image.premultiply_alpha()
		var sprite := Sprite2D.new()
		sprite.texture = ImageTexture.create_from_image(image)
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		sprite.centered = false
		sprite.scale = Vector2.ONE/float(factor)
		var origin := Vector2i(12+i*64, 34)
		origins.append(origin)
		sprite.position = origin
		if i == 3:
			sprite.scale.x *= -1
			sprite.position.x += 32
		sprite.material = material
		vp.add_child(sprite)
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var output := vp.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.runtime/outline-test"))
	output.save_png("res://.runtime/outline-test/render.png")
	for i in 4:
		var origin := origins[i]
		var edge := output.get_pixelv(origin+Vector2i(6,16))
		var interior := output.get_pixelv(origin+Vector2i(10,16))
		check(edge.r < 0.08 and edge.g < 0.08 and edge.a > 0.7, "Black border at source scale/flip %d" % i)
		check(interior.g > 0.5 and interior.a > 0.95, "Interior detail preserved at scale/flip %d" % i)
		check(output.get_pixelv(origin+Vector2i(1,1)).a < 0.01, "Transparent corners remain empty %d" % i)
	var ref := output.get_region(Rect2i(origins[1], Vector2i(32,32)))
	for i in [2,3]:
		var diff := 0.0
		for y in 32:
			for x in 32:
				var a := ref.get_pixel(x,y)
				var b := output.get_pixelv(origins[i]+Vector2i(x,y))
				diff = maxf(diff,maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.a-b.a))))
		check(diff < 0.06, "Screen stroke independent of source resolution/flip %d (max difference %.3f)" % [i,diff])
	var white := output.get_pixelv(origins[0]+Vector2i(15,15))
	check(white.r > 0.95 and white.g > 0.95, "Internal white clothing is not treated as a silhouette edge")
	var cut := output.get_pixelv(origins[4]+Vector2i(0,16))
	check(cut.r < 0.08 and cut.g < 0.08 and cut.a > 0.9, "Texture-boundary silhouette retains black inner border")
	var glow := output.get_pixelv(origins[5]+Vector2i(6,16))
	check(glow.b > 0.4 and glow.r > 0.25, "Bright purple trail is not blackened as body")
	print("CHARACTER_OUTLINE_TESTS: %d checks / %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
