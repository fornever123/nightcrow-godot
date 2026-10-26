extends RefCounted
## Read original source images, including newly imported files, without an editor import step.
static var textures: Dictionary = {}
static var pending: Array[String] = []
## 资源路径 -> [[x, y, w, h], ...]：加载时抹成透明（源视频带进来的横线，见 tools/art/clean_lines.py）
static var cleanup: Dictionary = {}
## 资源路径 -> 修复帧路径（节点 10，tools/art/fix_frames.py 输出的 webp base64 文本）：
## 加载原路径时换成修复帧（同尺寸，已经抹过 cleanup，所以不再抹）；修复帧读不出来就退回原图。
static var overrides: Dictionary = {}
## 高清采样（节点 10）：贴图加载时预乘透明度，所有用序列帧的精灵默认挂 char_hq 材质
## （预乘混合 + 按屏幕像素超采样 + 轻锐化）。夜景玩家另挂 char_light，里面也包含同一套采样。
const HQ_SHADER_PATH := "res://assets/shaders/char_hq.gdshader"
static var premultiply: bool = true
static var _hq_mat: ShaderMaterial

static func hq_material() -> ShaderMaterial:
	if _hq_mat == null:
		_hq_mat = ShaderMaterial.new()
		_hq_mat.shader = load(HQ_SHADER_PATH)
	return _hq_mat

static func reset(sprite: Dictionary) -> void:
	pending.clear()
	direct_textures.clear()
	var new_cleanup: Dictionary = sprite.get("assetCleanup", {})
	if new_cleanup.hash() != cleanup.hash():
		for path in new_cleanup:
			textures.erase(path)
		for path in cleanup:
			textures.erase(path)
		cleanup = new_cleanup.duplicate(true)
	var new_overrides: Dictionary = sprite.get("assetOverride", {})
	if new_overrides.hash() != overrides.hash():
		for path in new_overrides:
			textures.erase(path)
		for path in overrides:
			textures.erase(path)
		overrides = new_overrides.duplicate(true)
	var used: Dictionary = {}
	var animations: Dictionary = sprite.get("animations", {})
	var effects: Dictionary = sprite.get("effects", {})
	var preload_keys: Array = sprite.get("preloadAnimations", [])
	var preload_effects: Dictionary = {}
	for key in preload_keys:
		var effect_key := String(animations.get(key, {}).get("overlayEffect", ""))
		if not effect_key.is_empty():
			preload_effects[effect_key] = true
	for group_index in 2:
		var group: Dictionary = animations if group_index == 0 else effects
		for key in group:
			var clip: Dictionary = group[key]
			var should_preload := preload_keys.is_empty() or (preload_keys.has(key) if group_index == 0 else preload_effects.has(key))
			for f in clip.get("frames", []):
				var path := String(f.get("asset", ""))
				used[path] = true
				if should_preload and not path.is_empty() and not textures.has(path) and not pending.has(path):
					pending.append(path)
	for path in textures.keys():
		if not used.has(path):
			textures.erase(path)

## Paths whose Texture2D came straight from ResourceLoader (no CPU Image / premultiply).
static var direct_textures: Dictionary = {}

static func get_texture(path: String) -> Texture2D:
	if path.is_empty() or path.contains("..") or path.is_absolute_path():
		return null
	if textures.has(path):
		return textures[path]
	pending.erase(path)
	var image := _load_override(String(overrides.get(path, "")))
	var rects: Array = []
	if image == null:
		image = _load_source_image(path)
		if image == null or image.is_empty():
			# Export often ships only .ctex. get_image() can be empty for VRAM textures,
			# so fall back to the remapped Texture2D itself (skip cleanup / premultiply).
			var direct := _load_direct_texture(path)
			if direct != null:
				textures[path] = direct
				direct_textures[path] = true
				return direct
			push_error("ART_CACHE_MISS " + path + " bytes=" + str(FileAccess.get_file_as_bytes("res://assets/" + path).size()) + " exists=" + str(ResourceLoader.exists("res://assets/" + path)) + " import=" + str(FileAccess.file_exists("res://assets/" + path + ".import")))
			textures[path] = null
			return null
		rects = cleanup.get(path, [])
	if (premultiply or not rects.is_empty()) and image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	for r in rects:
		image.fill_rect(Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3])), Color(0, 0, 0, 0))
	if premultiply:
		image.premultiply_alpha()
	var texture := ImageTexture.create_from_image(image)
	textures[path] = texture
	direct_textures.erase(path)
	return texture

static func _load_source_image(path: String) -> Image:
	var res_path := "res://assets/" + path
	var bytes := FileAccess.get_file_as_bytes(res_path)
	if not bytes.is_empty():
		var image := Image.new()
		var error := image.load_png_from_buffer(bytes) if path.get_extension().to_lower() == "png" else image.load_jpg_from_buffer(bytes)
		if error == OK and not image.is_empty():
			return image
	# Exported builds keep the imported .ctex. Chinese source paths may not remap, so
	# read the .import sidecar and load that ASCII dest path instead.
	var from_import := _load_imported_texture(res_path)
	if from_import != null:
		return from_import
	var tex := ResourceLoader.load(res_path) as Texture2D
	if tex != null:
		var from_tex := tex.get_image()
		if from_tex != null and not from_tex.is_empty():
			return from_tex.duplicate()
	return null

static func _load_direct_texture(path: String) -> Texture2D:
	var res_path := "res://assets/" + path
	if ResourceLoader.exists(res_path):
		var tex := ResourceLoader.load(res_path) as Texture2D
		if tex != null:
			return tex
	var import_path := res_path + ".import"
	if not FileAccess.file_exists(import_path):
		return null
	var cfg := ConfigFile.new()
	if cfg.load(import_path) != OK:
		return null
	var ctex_path := String(cfg.get_value("remap", "path", ""))
	if ctex_path.is_empty():
		return null
	return ResourceLoader.load(ctex_path) as Texture2D

static func _load_imported_texture(res_path: String) -> Image:
	var import_path := res_path + ".import"
	if not FileAccess.file_exists(import_path):
		return null
	var cfg := ConfigFile.new()
	if cfg.load(import_path) != OK:
		return null
	var ctex_path := String(cfg.get_value("remap", "path", ""))
	if ctex_path.is_empty():
		return null
	var tex := ResourceLoader.load(ctex_path) as Texture2D
	if tex == null:
		return null
	var image := tex.get_image()
	if image == null or image.is_empty():
		return null
	return image.duplicate()

static func _load_override(fixed: String) -> Image:
	if fixed.is_empty() or fixed.contains("..") or fixed.is_absolute_path():
		return null
	var text := FileAccess.get_file_as_string("res://assets/" + fixed)
	if text.is_empty():
		return null
	var image := Image.new()
	if image.load_webp_from_buffer(Marshalls.base64_to_raw(text.strip_edges())) != OK or image.is_empty():
		push_warning("修复帧读取失败，退回原图：" + fixed)
		return null
	return image

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
	if premultiply and view.material == null and not bool(direct_textures.get(String(frame.get("asset", "")), false)):
		view.material = hq_material()
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
