extends Node2D
## 雨夜河岸街的灯光补充层（光线线 2026-10-30，见 docs 交接 / 会话笔记 光影诊断）。rain_street.gd 挂进场景。
## 不改背景线的文件，只读 street_backdrop 的灯列表（_lamps：p 灯头 / base 底座 / street / art，和 _flicker）。
##   1) 灯头光晕：成图里的灯只画了一个小亮点，补一圈平滑的高斯光晕（非成图灯 street_backdrop 自己画）；
##   2) 灯下雨丝：灯光照得到的地方，雨丝被照成暖色（light_rain_streaks.gdshader）；
##   3) 接地：主角脚下一小块软暗影，离地越高越淡越小；
##   4) 湿街面倒影：主角在街面那条湿带里的短倒影（light_wet_reflect.gdshader）。

const StreakShader := preload("res://assets/shaders/light_rain_streaks.gdshader")
const ReflectShader := preload("res://assets/shaders/light_wet_reflect.gdshader")

const HALO_COL := Color(1.0, 0.66, 0.36)
const HALO_IN := Vector2(26.0, 0.42)       ## 灯头光晕：内圈半径（世界单位）、强度
const HALO_OUT := Vector2(120.0, 0.13)     ## 外圈
const STREAK_HALF := 250.0                 ## 路灯雨丝矩形的半宽（世界单位）
const STREAK_TOP := 30.0                   ## 灯头上方留多少
const WALL_STREAK_R := 130.0               ## 壁灯雨丝那一团的半径
const SHADOW_SIZE := Vector2(46.0, 9.0)    ## 脚下暗影半宽 / 半高（世界单位）
const SHADOW_A := Vector2(0.42, 0.62)      ## 暗处 / 灯下的不透明度
const SHADOW_FADE_H := 220.0               ## 离地多高时暗影消失
const WET_BAND := 26.0                     ## 湿街面那一条（和 rain_ground 一样从 floor_y 往下）
const REFLECT_A := Vector2(0.45, 0.65)     ## 倒影：暗处 / 灯下
const REFLECT_SQUASH := 0.3                ## 倒影竖向压扁：湿带只有 ~16 屏幕像素，真实比例只照得到一双黑靴子，压扁才放得下小腿到腰

var stage: Node                            ## rain_street（取 backdrop / player / terrain / _light）

var _halo: Node2D
var _streaks: Node2D
var _shadow: Node2D
var _reflect: Sprite2D
var _reflect_mat: ShaderMaterial
var _halo_tex: Texture2D
var _shadow_tex: Texture2D
var _white: Texture2D


func _ready() -> void:
	_halo_tex = _radial(128, [[0.0, 1.0], [0.08, 0.62], [0.2, 0.3], [0.4, 0.1], [0.7, 0.02], [1.0, 0.0]])
	_shadow_tex = _radial(64, [[0.0, 1.0], [0.45, 0.75], [0.8, 0.2], [1.0, 0.0]])
	var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	_white = ImageTexture.create_from_image(img)

	_halo = Node2D.new()
	_halo.z_as_relative = false
	_halo.z_index = -8                     # 成图和地形之上、角色之后：光晕是空气里的，楼面前面
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_halo.material = add
	_halo.draw.connect(_draw_halo)
	add_child(_halo)

	_streaks = Node2D.new()
	_streaks.z_as_relative = false
	_streaks.z_index = 19                  # 和雨（20）同一深度，在角色前面
	var sm := ShaderMaterial.new()
	sm.shader = StreakShader
	_streaks.material = sm
	_streaks.draw.connect(_draw_streaks)
	add_child(_streaks)

	_reflect = Sprite2D.new()
	_reflect.z_as_relative = false
	_reflect.z_index = -4                  # 湿街面涟漪（−5）之上、脚下暗影之下
	_reflect.top_level = true
	_reflect_mat = ShaderMaterial.new()
	_reflect_mat.shader = ReflectShader
	_reflect_mat.set_shader_parameter("band", WET_BAND)
	_reflect.material = _reflect_mat
	add_child(_reflect)

	_shadow = Node2D.new()
	_shadow.z_as_relative = false
	_shadow.z_index = -3
	_shadow.draw.connect(_draw_shadow)
	add_child(_shadow)


## 径向渐变贴图：stops = [[位置 0..1, 不透明度]]
static func _radial(size: int, stops: Array) -> Texture2D:
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for s in stops:
		offs.append(float(s[0]))
		cols.append(Color(1, 1, 1, float(s[1])))
	var g := Gradient.new()
	g.offsets = offs
	g.colors = cols
	var t := GradientTexture2D.new()
	t.width = size
	t.height = size
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.gradient = g
	return t


func _process(_delta: float) -> void:
	_halo.queue_redraw()
	_streaks.queue_redraw()
	_shadow.queue_redraw()
	_update_reflect()


func _backdrop() -> Node:
	return stage.get("backdrop") if stage != null else null


func _lamps() -> Array:
	var b := _backdrop()
	if b == null or b.get("_lamps") == null:
		return []
	return b.get("_lamps")


func _flicker(x: float) -> float:
	var b := _backdrop()
	return float(b.call("_flicker", x)) if b != null else 1.0


func _light() -> float:
	var l = stage.get("_light") if stage != null else null
	return float(l) if l != null else 0.0


func _player() -> Node2D:
	var p = stage.get("player") if stage != null else null
	return p if p != null and is_instance_valid(p) else null


# ---------------------------------------------------------------- 灯头光晕 / 灯下雨丝

func _draw_halo() -> void:
	for l in _lamps():
		if not bool(l.art):
			continue
		var f := _flicker(l.p.x)
		var k := 1.0 if bool(l.street) else 0.75
		for ring in [HALO_OUT, HALO_IN]:
			var r: float = ring.x * k
			_halo.draw_texture_rect(_halo_tex, Rect2(l.p - Vector2(r, r), Vector2(r, r) * 2.0), false,
				Color(HALO_COL, ring.y * f))


func _draw_streaks() -> void:
	for l in _lamps():
		var f := _flicker(l.p.x)
		if bool(l.street):
			var top: float = l.p.y - STREAK_TOP
			var h: float = l.base.y - top
			# 顶点色 g = 灯头在矩形里的高度（0 = 顶），着色器按它画光锥
			_streaks.draw_texture_rect(_white, Rect2(l.p.x - STREAK_HALF, top, STREAK_HALF * 2.0, h), false, Color(1, STREAK_TOP / h, 1, f))
		else:
			var r := WALL_STREAK_R
			_streaks.draw_texture_rect(_white, Rect2(l.p - Vector2(r, r * 0.6), Vector2(r * 2.0, r * 2.0)), false, Color(0, 1, 1, f * 0.7))


# ---------------------------------------------------------------- 接地：脚下暗影 + 湿街面倒影

func _feet() -> Vector2:
	var p := _player()
	return p.global_position + Vector2(0, float(p.get("foot_offset"))) if p != null else Vector2.INF


func _draw_shadow() -> void:
	var p := _player()
	var t = stage.get("terrain")
	if p == null or t == null:
		return
	var feet := _feet()
	var ground: float = t.support_y(feet.x, feet.y)
	var air := clampf((ground - feet.y) / SHADOW_FADE_H, 0.0, 1.0)
	if air >= 1.0:
		return
	var a := lerpf(SHADOW_A.x, SHADOW_A.y, _light()) * (1.0 - air)
	var s := SHADOW_SIZE * (1.0 - 0.45 * air)
	_shadow.draw_texture_rect(_shadow_tex, Rect2(Vector2(feet.x - s.x, ground - s.y * 0.7), s * 2.0), false, Color(0.0, 0.0, 0.02, a))


func _update_reflect() -> void:
	var p := _player()
	var spr: Sprite2D = p.get_node_or_null("Visual/ActorSprite") if p != null else null
	if spr == null or not spr.is_visible_in_tree() or spr.texture == null:
		_reflect.visible = false
		return
	var floor_y := float(stage.get("floor_y"))
	_reflect.visible = true
	_reflect.texture = spr.texture
	_reflect.centered = spr.centered
	_reflect.offset = spr.offset
	_reflect.flip_h = spr.flip_h
	_reflect.flip_v = spr.flip_v
	_reflect.hframes = spr.hframes
	_reflect.vframes = spr.vframes
	_reflect.frame = spr.frame
	_reflect.region_enabled = spr.region_enabled
	_reflect.region_rect = spr.region_rect
	_reflect.texture_filter = spr.texture_filter
	# 沿街面（y = floor_y）上下翻转并压扁
	_reflect.global_transform = Transform2D(Vector2(1, 0), Vector2(0, -REFLECT_SQUASH), Vector2(0, (1.0 + REFLECT_SQUASH) * floor_y)) * spr.get_global_transform()
	_reflect_mat.set_shader_parameter("street_y", floor_y)
	_reflect_mat.set_shader_parameter("strength", lerpf(REFLECT_A.x, REFLECT_A.y, _light()))
