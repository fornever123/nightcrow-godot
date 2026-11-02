extends ColorRect
## 大招眼睛分格（2026-10-29 原型，取代过场视频 ult_cinematic.ogv；方案见对话里四个子智能体的汇总）：
## 发动后一道刀缝从画面中间长出来、上下张开成斜着的平行四边形分格，里面是整张眼睛特写（不全屏，四角露出冻结的游戏）。
## 她在格子里“活着”：慢推、深度视差、发丝和羽毛发饰摆动、前景虚焦鸦羽飘过；第 FLARE 帧瞳孔收缩、紫光爆亮、
## 左眼拉出横向眼光；寒光沿左下银边走过；蓄力后一道刀线沿银边的延长线斩开格子，两半错开滑出，露出冲击帧。
## 图和遮罩：tools/art/make_ult_eye_masks.py。画法全在 assets/shaders/fx_ult_eye.gdshader，这里只按帧算参数。
## 时间 t = 过场开始后第几帧（ult_fx 传入 ult_frame - ult_vanish_frame）。

const SHADER := preload("res://assets/shaders/fx_ult_eye.gdshader")
const EYE_PATH := "res://assets/image/ult/eye/closeup_eye.png"
const MASK_PATH := "res://assets/image/ult/eye/eye_masks.png"
const FEATHER_PATH := "res://assets/image/ult/feather_2.png"
const IMG := Vector2(1672.0, 941.0)
const GLINT_A := Vector2(480.0, 672.0)        ## 左下银边两端（图像素）：寒光沿它走；刀线和它同一个角度
const GLINT_B := Vector2(1100.0, 941.0)
const CUT_AT := Vector2(950.0, 610.0)         ## 刀线经过的点（图像素）：鼻尖下方，从左眼下面、高领上面斜着过，不切到眼睛
const TILT := -0.026
## 节拍（t，帧）
const OPEN := 12.0                            ## 张开用多久
const FLARE := 36.0                           ## 睁眼：瞳孔收缩、紫光爆亮（对齐音效 ult_eye 第 44 帧）
const GLINT := Vector2(82.0, 92.0)            ## 寒光走过银边（对齐 ult_push 第 90.6 帧）
const BUILD := Vector2(92.0, 104.0)           ## 蓄：一切静止，只有眼光越来越亮
const CUT := 104.0                            ## 刀线
const SPLIT := Vector2(106.0, 124.0)          ## 两半滑出
const END := 126.0
## 前景鸦羽：起点（屏幕像素）、每帧位移、起始角、每帧转、长度
## 路线都绕开双眼那一带（屏幕约 x 400～900、y 260～440）
const FEATHERS := [
	[Vector2(-220, 70), Vector2(7.0, 0.7), 0.35, 0.004, 560.0],
	[Vector2(1320, -110), Vector2(-2.4, 5.2), 2.0, -0.006, 420.0],
	[Vector2(-320, 700), Vector2(8.5, -0.6), -0.2, 0.003, 640.0],
	[Vector2(1420, 640), Vector2(-4.5, 1.2), 2.9, 0.008, 380.0],
]
const FEATHER_START := [6.0, 30.0, 58.0, 74.0]

var _mat: ShaderMaterial


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	material = _mat
	_mat.set_shader_parameter("eye_tex", _load(EYE_PATH, true))
	_mat.set_shader_parameter("mask_tex", _load(MASK_PATH, false))
	_mat.set_shader_parameter("feather_tex", _load(FEATHER_PATH, true))
	_mat.set_shader_parameter("img_size", IMG)
	_mat.set_shader_parameter("tilt", TILT)
	visible = false


func active(t: float) -> bool:
	return t >= -4.0 and t < END


## 每帧调。t 见文件头
func update(t: float) -> void:
	visible = active(t)
	if not visible:
		return
	var sz := get_viewport_rect().size
	position = Vector2.ZERO
	size = sz
	var m := _mat
	m.set_shader_parameter("screen", sz)
	var c := sz * 0.5
	var half := Vector2(sz.x * 0.46, sz.y * 0.45)
	var scale := maxf(half.x * 2.0 / IMG.x, half.y * 2.0 / IMG.y)
	m.set_shader_parameter("center", c)
	m.set_shader_parameter("half_size", half)
	m.set_shader_parameter("img_scale", scale)
	# 刀缝 → 张开（ease-out），图入场时略大、略转，回正
	m.set_shader_parameter("slit", _ramp(t, -4.0, 1.0, true))
	var op := _ramp(t, 0.0, OPEN, true)
	m.set_shader_parameter("open", op)
	var settle := 1.0 - _ramp(t, 0.0, 16.0, true)
	var zoom := 1.0 + 0.1 * settle + 0.07 * _smooth(_ramp(t, 0.0, CUT))
	var turn := -0.035 * settle
	m.set_shader_parameter("zoom", zoom)
	m.set_shader_parameter("turn", turn)
	var pan := Vector2(10.0, 4.0) * _smooth(_ramp(t, 0.0, CUT))
	m.set_shader_parameter("pan", pan)
	# 蓄的时候一切静止：视差、摆动停在那一刻
	var tm := minf(t, BUILD.x)
	m.set_shader_parameter("parallax", Vector2(-7.0, -3.0) * _smooth(_ramp(tm, 0.0, BUILD.x)) + Vector2(4.0, 1.5) * settle)
	m.set_shader_parameter("sway_t", tm / 60.0)
	# 睁眼
	var hit := _ramp(t, FLARE - 2.0, FLARE + 1.0)
	var decay := 1.0 - _ramp(t, FLARE + 1.0, FLARE + 22.0, true)
	var build := _ramp(t, BUILD.x, BUILD.y)
	m.set_shader_parameter("pupil", 0.26 * hit + 0.06 * build)
	m.set_shader_parameter("glow", hit * (0.08 + 0.3 * decay) + 0.25 * build)
	m.set_shader_parameter("iris", hit * (0.2 + 0.6 * decay) + 0.5 * build)
	m.set_shader_parameter("streak", hit * decay * 1.4 + build * 0.4)
	m.set_shader_parameter("glint_pos", _ramp(t, GLINT.x, GLINT.y) if t >= GLINT.x and t < GLINT.y + 4.0 else -1.0)
	# 前景鸦羽（蓄的时候也停住）
	var fs: Array[Vector4] = []
	for i in FEATHERS.size():
		var f: Array = FEATHERS[i]
		var k := tm - float(FEATHER_START[i])
		if k < 0.0:
			fs.append(Vector4(0, 0, 0, 0))
			continue
		var pos: Vector2 = f[0] + f[1] * k
		fs.append(Vector4(pos.x, pos.y, float(f[2]) + float(f[3]) * k, float(f[4])))
	m.set_shader_parameter("feathers", fs)
	# 刀线：和左下银边同一个角度，从鼻尖下方斜着过；先亮再斩开，两半沿刀线错开滑出
	var a := _to_screen(GLINT_A, c, scale * zoom, turn, pan)
	var b := _to_screen(GLINT_B, c, scale * zoom, turn, pan)
	m.set_shader_parameter("cut_p", _to_screen(CUT_AT, c, scale * zoom, turn, pan))
	m.set_shader_parameter("cut_d", (b - a).normalized())
	var line := _ramp(t, CUT, CUT + 2.0) * (1.0 - _ramp(t, SPLIT.x + 2.0, SPLIT.x + 10.0))
	m.set_shader_parameter("cut_line", line)
	var sp := _ramp(t, SPLIT.x, SPLIT.y)
	m.set_shader_parameter("split", 6.0 * _ramp(t, CUT, SPLIT.x) + sz.x * 0.9 * sp * sp)
	m.set_shader_parameter("alpha", 1.0)


func _to_screen(img: Vector2, c: Vector2, s: float, turn: float, pan: Vector2) -> Vector2:
	return c + ((img - IMG * 0.5 - pan) * s).rotated(turn).rotated(TILT)


static func _load(path: String, mips: bool) -> Texture2D:
	if FileAccess.file_exists(path):
		var img := Image.new()
		if img.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) == OK:
			if mips:
				img.generate_mipmaps()
			return ImageTexture.create_from_image(img)
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


static func _ramp(x: float, a: float, b: float, ease_out: bool = false) -> float:
	var k := clampf((x - a) / (b - a), 0.0, 1.0)
	return 1.0 - (1.0 - k) * (1.0 - k) if ease_out else k


static func _smooth(k: float) -> float:
	return k * k * (3.0 - 2.0 * k)
