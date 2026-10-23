extends CanvasLayer
## 光影后期（光影第一版）：整屏后期一层，盖在夜景 + 地形 + 角色上面、界面（layer 10）下面。
## 着色器见 assets/shaders/night_post.gdshader（辉光、月光光柱、调色、角色光、暗角）。
## 每帧把月亮和主角的屏幕位置、时间传给着色器。

const PostShader := preload("res://assets/shaders/night_post.gdshader")

var stage: Node                  ## night_trial（取 player / backdrop）
var mat: ShaderMaterial
var _rect: ColorRect
var _time: float = 0.0
var _hero := Vector2(640.0, 520.0)


func _ready() -> void:
	layer = 5
	_rect = ColorRect.new()
	_rect.name = "Post"
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	mat = ShaderMaterial.new()
	mat.shader = PostShader
	_rect.material = mat
	add_child(_rect)


func set_enabled(on: bool) -> void:
	mat.set_shader_parameter("enabled", on)


func _process(delta: float) -> void:
	_time += delta
	mat.set_shader_parameter("t", _time)
	if stage == null:
		return
	var b = stage.get("backdrop")
	if b != null and b.ok:
		mat.set_shader_parameter("moon", b.moon_screen())
	var p = stage.get("player")
	if p != null and is_instance_valid(p):
		var target: Vector2 = (p as Node2D).get_global_transform_with_canvas().origin + Vector2(0.0, -24.0)
		# 跟一点点延迟，冲刺时光不会硬跟
		_hero = _hero.lerp(target, clampf(delta * 10.0, 0.0, 1.0))
		mat.set_shader_parameter("hero", _hero)
