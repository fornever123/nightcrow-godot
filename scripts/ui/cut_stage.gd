extends ColorRect
## 首页舞台：把 cut_stage.gdshader 的参数推给 GPU。
## 时间轴、字体、菜单都不在这里；本节点只管“光和影”。

const SHADER := preload("res://assets/shaders/cut_stage.gdshader")

var clock := 0.0
var fade := 1.0
var reveal := 0.0
var dust := 0.0
var gap := 0.0
var cut_y := 304.0
var up_shift := 0.0
var down_shift := 0.0
var upper_amt := 1.0
var lower_amt := 1.0
var leak := 0.0
var slash_x := -9999.0
var slash_alpha := 0.0
var flash := 0.0
var shock := -2.0
var shock_amt := 0.0
var ink := 0.0
var cx_off := 0.0
var drift := 0.0
var breathe := 0.0

var _mat: ShaderMaterial


func _ready() -> void:
	name = "Stage"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	color = Color(0.006, 0.007, 0.014, 1.0)
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	material = _mat
	push()


func push() -> void:
	if _mat == null:
		return
	var vp := get_viewport_rect().size
	_mat.set_shader_parameter("res", vp)
	_mat.set_shader_parameter("t", clock)
	_mat.set_shader_parameter("fade", fade)
	_mat.set_shader_parameter("reveal", reveal)
	_mat.set_shader_parameter("dust_amt", dust)
	_mat.set_shader_parameter("gap", gap)
	_mat.set_shader_parameter("cut_y", cut_y)
	_mat.set_shader_parameter("up_shift", up_shift)
	_mat.set_shader_parameter("down_shift", down_shift)
	_mat.set_shader_parameter("upper_amt", upper_amt)
	_mat.set_shader_parameter("lower_amt", lower_amt)
	_mat.set_shader_parameter("leak", leak)
	_mat.set_shader_parameter("slash_x", slash_x)
	_mat.set_shader_parameter("slash_alpha", slash_alpha)
	_mat.set_shader_parameter("flash", flash)
	_mat.set_shader_parameter("shock", shock)
	_mat.set_shader_parameter("shock_amt", shock_amt)
	_mat.set_shader_parameter("ink", ink)
	_mat.set_shader_parameter("cx_off", cx_off)
	_mat.set_shader_parameter("drift", drift)
	_mat.set_shader_parameter("breathe", breathe)
