extends RefCounted
## Read original source images, including newly imported files, without an editor import step.
static var textures: Dictionary = {}
static var pending: Array[String] = []

static func reset(sprite: Dictionary) -> void:
	pending.clear()
	var used: Dictionary = {}
	for group in [sprite.get("animations", {}), sprite.get("effects", {})]:
		for clip in group.values():
			for f in clip.get("frames", []):
				var path := String(f.get("asset", ""))
				used[path] = true
				if not path.is_empty() and not textures.has(path) and not pending.has(path):
					pending.append(path)
	for path in textures.keys():
		if not used.has(path):
			textures.erase(path)

static func get_texture(path: String) -> Texture2D:
	if path.is_empty() or path.contains("..") or path.is_absolute_path():
		return null
	if textures.has(path):
		return textures[path]
	pending.erase(path)
	var image := Image.new()
	var bytes := FileAccess.get_file_as_bytes("res://assets/" + path)
	var error := image.load_png_from_buffer(bytes) if path.get_extension().to_lower() == "png" else image.load_jpg_from_buffer(bytes)
	if error != OK or image.is_empty():
		textures[path] = null
		return null
	var texture := ImageTexture.create_from_image(image)
	textures[path] = texture
	return texture

static func warm() -> void:
	var start := Time.get_ticks_usec()
	while not pending.is_empty() and Time.get_ticks_usec() - start < 2500:
		get_texture(pending[0])

static func apply(view: Sprite2D, frame: Dictionary, display_scale: float = 1.0) -> void:
	if frame.get("blank", false):
		view.visible = false
		return
	var texture := get_texture(String(frame.get("asset", "")))
	if texture == null:
		view.visible = false
		return
	view.texture = texture
	view.centered = false
	var region: Dictionary = frame.get("region", {})
	view.region_enabled = not region.is_empty()
	if view.region_enabled:
		view.region_rect = Rect2(region.get("x", 0), region.get("y", 0), region.get("width", texture.get_width()), region.get("height", texture.get_height()))
		view.region_filter_clip_enabled = true
	var source_size := view.region_rect.size if view.region_enabled else texture.get_size()
	var width := float(frame.get("width", source_size.x))
	var height := float(frame.get("height", source_size.y))
	view.scale = Vector2(width / source_size.x, height / source_size.y) * display_scale
	view.offset = -Vector2(float(frame.get("pivotX", width / 2)) * source_size.x / width, float(frame.get("pivotY", height)) * source_size.y / height)
	view.visible = true
