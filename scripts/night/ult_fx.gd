extends Node2D
## 大招「绝影 · 鸦羽止」的表现（2026-10-26，样片 v4：tools/art/src/ult/feather/ult_full_mock_4s_v4.mp4，交接 docs/大招-鸦羽止-交接.md）。
## 基调：黑白世界，紫色只留在她身上、影子的边光、刀线和羽毛的断口。
## 时间轴跟着主角的 ult_frame（各段边界读 player.gd 的 ult_* 参数）：
##   发动（0～ult_vanish_frame）：世界褪成黑白、压暗；上下黑边收进来；她换成居合架势，镜头往她身上推一点
##   过场（ult_vanish_frame～ult_calm_start）：全屏播过场视频（推近眼睛 → 握剑 → 推开鲤口 → 白闪）
##   冲击（ult_calm_start 起 4 帧）：白底黑剪影 2 帧 → 反相 2 帧；她已在敌群背后低位收势
##   静（～ult_final_frame）：原地留下她的影子（黑剪影 + 紫边）；一道刀线横穿敌群胸口；刀线上的鸦羽被切成两半、慢慢错开；镜头极慢推近
##   咔（ult_final_frame）：跳切到收剑姿势，腰间一线白光，顿帧 ult_freeze_frames 帧
##   落：影子碎成鸦羽飞回她身上；影沿刀线裂开（关卡调 shade.ult_split_kill）；颜色从刀线往上下恢复；
##       羽毛按正常速度落下；黑边退出，镜头回到平常。“咔”之后画在世界里的东西一拍二（每张停 2 帧），镜头和颜色保持顺滑

const MONO_SHADER := preload("res://assets/shaders/fx_ult_mono.gdshader")
const FLAT_SHADER := preload("res://assets/shaders/fx_ult_flat.gdshader")
const VIOLET_SHADER := preload("res://assets/shaders/fx_ult_violet.gdshader")
const MOVIE_PATH := "res://assets/video/ult_cinematic.ogv"
## 大招音效（tools/audio/make_ult_sfx.py 用真实录音拼的）：在第几帧开始放（带小数时按小数部分从中间放），
## 放在 assets/audio/ult/<名字>.ogg。时间轴见那个脚本的说明
const SFX := {&"ult_start": 0.0, &"ult_eye": 44.0, &"ult_push": 90.6, &"ult_rise": 108.7,
	&"ult_impact": 124.0, &"ult_sheathe": 142.8, &"ult_burst": 174.0}
const SFX_BUS := &"SFX_Impact"
## 三张定格图在同一张画布上对齐（前脚脚尖 = ANCHOR），贴图 1 像素 = 世界 0.5 单位
const BODY_PATHS := {&"iai": "res://assets/image/ult/feather/iai.png",
	&"zanshin": "res://assets/image/ult/feather/zanshin.png",
	&"sheathed": "res://assets/image/ult/feather/sheathed.png"}
const ANCHOR := Vector2(519.0, 341.0)
const BODY_SCALE := 0.5
const FOOT_DX := 36.0                          ## 前脚脚尖在身体中心前方多远（世界单位）
const BAR_H := 56.0                            ## 上下黑边（屏幕像素）
const IMPACT := 4                              ## 冲击帧：白底黑剪影 2 帧 + 反相 2 帧
const CAM_Z := 1.5                             ## 静的时候镜头放大到平常的几倍（视野放不下起点和终点时自动缩小）
const CAM_DROP := 68.0                         ## 镜头中心比她脚底高多少（世界单位）
const VIOLET := Color("9b5cff")
const VIOLET_L := Color("b98cff")
const PAPER := Color("f4f4f6")
const FEATHER_INK := Color(0.055, 0.047, 0.078)
const SHADOW_RIM: Array[Vector2] = [Vector2(-3, 0), Vector2(3, 0), Vector2(0, -3), Vector2(0, 3),
	Vector2(-2, -2), Vector2(2, -2), Vector2(-2, 2), Vector2(2, 2), Vector2.ZERO]

var fx: Node2D               ## ImpactFX（没用到，保留接口）
var player: Node2D
var hud: Control
var anchor: Node2D           ## 关卡给的镜头钉子（大招期间镜头跟它）

var _phase: int = 0          ## 0 没在放 / 1 放的时候
var _f: float = 0.0
var _data: Dictionary = {}
var _total: float = 0.0
var _hud_k: float = 1.0
var _cam: Camera2D
var _zoom0 := Vector2.ONE
var _offset0 := Vector2.ZERO
var _center0 := Vector2.INF
var _start := Vector2.ZERO   ## 起手时她在哪
var _face0: int = 1
var _view: Sprite2D          ## 她平常的角色帧（character_view），大招期间藏起来
var _rng := RandomNumberGenerator.new()

var _white: Node2D           ## 世界里：冲击帧的白（黑）底，在地形之上、角色之下
var _mono_layer: CanvasLayer
var _mono_mat: ShaderMaterial
var _top: CanvasLayer        ## 跟着镜头走的世界层，盖在黑白层上面（她、影子、羽毛保住紫色）
var _shadow: Node2D
var _shadow_parts: Array[Sprite2D] = []
var _body: Sprite2D
var _body_violet: ShaderMaterial
var _flat_black: ShaderMaterial
var _flat_white: ShaderMaterial
var _flat_violet: ShaderMaterial
var _feathers: Node2D
var _ui: CanvasLayer
var _ui_front: Node2D        ## 刀线、腰间白光、上下黑边
var _movie_layer: CanvasLayer
var _movie: VideoStreamPlayer
var _tex := {}
var _sfx := {}               ## 名字 → AudioStream
var _sfx_done := {}
var _voices: Array[AudioStreamPlayer] = []

var _ambient: Array = []     ## {pos, ang, poly, top, depth, vx, spin}
var _cut: Array = []         ## {halves: [poly, poly], cut: [[a, b], [a, b]], spin}
var _shards: Array = []      ## 影子碎成的羽毛 {from, bend, poly, ang}
var _debris: Array = []      ## 影裂开时的黑色碎片 {pos, vel, size}


func _ready() -> void:
	process_priority = 10
	_rng.seed = 20261026
	_white = Node2D.new()
	_white.top_level = true
	_white.z_as_relative = false
	_white.z_index = -60
	_white.visible = false
	add_child(_white)
	_white.draw.connect(_draw_white)
	# 黑白层：全屏读屏幕纹理（光影后期是第 5 层，HUD 第 10 层）
	_mono_layer = CanvasLayer.new()
	_mono_layer.layer = 6
	add_child(_mono_layer)
	var b := BackBufferCopy.new()
	b.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	_mono_layer.add_child(b)
	var r := ColorRect.new()
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mono_mat = ShaderMaterial.new()
	_mono_mat.shader = MONO_SHADER
	r.material = _mono_mat
	_mono_layer.add_child(r)
	# 黑白层之上、UI 之下：跟着镜头走的世界层
	_top = CanvasLayer.new()
	_top.layer = 8
	_top.follow_viewport_enabled = true
	add_child(_top)
	_flat_black = _flat(Color.BLACK)
	_flat_white = _flat(Color.WHITE)
	_flat_violet = _flat(Color(VIOLET_L, 0.85))
	for k in BODY_PATHS:
		_tex[k] = _load_png(BODY_PATHS[k])
	_shadow = Node2D.new()
	_top.add_child(_shadow)
	# 影子：8 个方向各偏一点的紫色剪影当边光，最后一张黑剪影压在中间
	for d in SHADOW_RIM:
		var s := _body_sprite()
		s.texture = _tex[&"iai"]
		s.material = _flat_black if d == Vector2.ZERO else _flat_violet
		_shadow.add_child(s)
		_shadow_parts.append(s)
	_body = _body_sprite()
	_body_violet = ShaderMaterial.new()
	_body_violet.shader = VIOLET_SHADER
	_body.material = _body_violet
	_top.add_child(_body)
	_feathers = Node2D.new()
	_top.add_child(_feathers)
	_feathers.draw.connect(_draw_feathers)
	_ui = CanvasLayer.new()
	_ui.layer = 11
	add_child(_ui)
	_ui_front = Node2D.new()
	_ui.add_child(_ui_front)
	_ui_front.draw.connect(_draw_ui_front)
	# 过场视频：最上面一层，全屏
	_movie_layer = CanvasLayer.new()
	_movie_layer.layer = 12
	add_child(_movie_layer)
	_movie = VideoStreamPlayer.new()
	_movie.set_anchors_preset(Control.PRESET_FULL_RECT)
	_movie.expand = true
	_movie.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(MOVIE_PATH):
		_movie.stream = load(MOVIE_PATH)
	_movie_layer.add_child(_movie)
	for k in SFX:
		var st := _load_audio("res://assets/audio/ult/%s.ogg" % k)
		if st != null:
			_sfx[k] = st
	for i in 4:
		var v := AudioStreamPlayer.new()
		v.bus = SFX_BUS if AudioServer.get_bus_index(SFX_BUS) >= 0 else &"Master"
		add_child(v)
		_voices.append(v)
	_set_layers(false)


func _body_sprite() -> Sprite2D:
	var s := Sprite2D.new()
	s.centered = false
	s.scale = Vector2(BODY_SCALE, BODY_SCALE)
	s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return s


func _flat(col: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = FLAT_SHADER
	m.set_shader_parameter("tint", col)
	return m


func _set_layers(on: bool) -> void:
	_mono_layer.visible = on
	_top.visible = on
	_ui.visible = on
	_movie_layer.visible = false
	if not on and _movie.is_playing():
		_movie.stop()


## 先按原 PNG 读（编辑器里的新图不用导入）；导出版里只有导入后的贴图，就退回 ResourceLoader
static func _load_png(path: String) -> Texture2D:
	if FileAccess.file_exists(path):
		var img := Image.new()
		if img.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) == OK:
			img.generate_mipmaps()
			return ImageTexture.create_from_image(img)
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


static func _load_audio(path: String) -> AudioStream:
	var absolute := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(absolute):
		return AudioStreamOggVorbis.load_from_file(absolute)
	if ResourceLoader.exists(path):
		return load(path) as AudioStream
	return null


# ---------------------------------------------------------------- 对外（night_trial 调）

## 发动。data：final（刀线 {p, d}）、stand（站定位置）、side、shades、k（世界 / 屏幕像素）
func begin(data: Dictionary) -> void:
	clear()
	_phase = 1
	_data = data
	_cam = get_viewport().get_camera_2d()
	if is_instance_valid(_cam):
		_zoom0 = _cam.zoom
		_offset0 = _cam.get("base_offset") if _cam.get("base_offset") != null else Vector2.ZERO
	_center0 = anchor.global_position if is_instance_valid(anchor) else Vector2.INF
	_start = player.global_position if _ok() else global_position
	_face0 = int(player.get("facing")) if _ok() else 1
	_view = _find_view(player) if _ok() else null
	_set_layers(true)
	_sfx_done.clear()
	_build_feathers()
	_build_shards()
	_build_debris()
	_hud_k = 0.0          # 发动那一帧就藏 HUD（不渐隐，避免头几帧还看得到）
	_apply_hud()


func strike(_i: int) -> void:
	pass


func arrive() -> void:
	pass


## “咔”那一刻：总伤害（目前由伤害数字自己弹，留着接口）
func reveal(total: float) -> void:
	_total = total


## 大招里影砸地：不加东西
func spark(_point: Vector2) -> void:
	pass


func clear() -> void:
	_restore_view()
	for s in _data.get("shades", []):
		if is_instance_valid(s):
			s.ult_flat(Color(0, 0, 0, 0))
	if _center0 != Vector2.INF and is_instance_valid(anchor):
		anchor.global_position = _center0
	if _phase != 0 and is_instance_valid(_cam):
		_cam.zoom = _zoom0
		if _cam.get("base_offset") != null:
			_cam.base_offset = _offset0
	_phase = 0
	_f = 0.0
	_data = {}
	_total = 0.0
	_center0 = Vector2.INF
	_ambient.clear()
	_cut.clear()
	_shards.clear()
	_debris.clear()
	_white.visible = false
	_mono_mat.set_shader_parameter("amount", 0.0)
	_mono_mat.set_shader_parameter("dim", 0.0)
	_mono_mat.set_shader_parameter("reveal_r", 0.0)
	_set_layers(false)
	_hud_k = 1.0
	_apply_hud()


func busy() -> bool:
	return _phase != 0


# ---------------------------------------------------------------- 时间

func _calm() -> float:
	return _pv("ult_calm_start", 124.0)


func _ka() -> float:
	return _pv("ult_final_frame", 168.0) - _calm()


func _frz() -> float:
	return _pv("ult_freeze_frames", 6.0)


## 冲击帧之后第几帧（<0 = 还没回到游戏）
func _g() -> float:
	return _f - _calm()


## “咔”之后的时间：顿帧期间停在 0；之后 smooth 每帧走，step 一拍二
func _after(stepped: bool) -> float:
	var g := _g()
	var ka := _ka()
	if g < ka:
		return g - ka
	if g < ka + _frz():
		return 0.0
	var t := g - ka - _frz()
	return 1.0 + (floorf(t / 2.0) * 2.0 if stepped else t)


# ---------------------------------------------------------------- 每帧

func _process(_delta: float) -> void:
	if _phase == 0:
		return
	if not (_ok() and player.is_ult()):
		clear()
		return
	_f = float(player.ult_frame)
	var g := _g()
	var ts := _after(false)
	var total := _pv("ult_total_frames", 248.0)
	# 黑白：发动时褪色；收尾时颜色从刀线往上下恢复
	var amt := _ramp(_f, 0.0, 6.0)
	var reveal := _ramp(ts, 2.0, 42.0, true) * 1.3
	_mono_mat.set_shader_parameter("amount", amt)
	_mono_mat.set_shader_parameter("dim", 0.0 if _impact_kind() != 0 else 0.22 * amt)
	_mono_mat.set_shader_parameter("reveal_r", reveal)
	_mono_mat.set_shader_parameter("reveal_y", _line_screen().y / maxf(get_viewport().get_visible_rect().size.y, 1.0))
	_update_movie()
	_update_sfx()
	_update_impact()
	_update_body(reveal)
	_update_shadow(g)
	_update_camera(g, ts, total)
	_update_hud(ts)
	_white.queue_redraw()
	_feathers.queue_redraw()
	_ui_front.queue_redraw()


## 到点就放；跳帧（测试直接改帧号）时按落后的时间从中间放，太晚就不放了
func _update_sfx() -> void:
	if not (_ok() and player.is_ult()):
		return
	for k in SFX:
		if _sfx_done.has(k) or not _sfx.has(k):
			continue
		var t0: float = SFX[k]
		if _f < ceilf(t0):
			continue
		_sfx_done[k] = true
		var st: AudioStream = _sfx[k]
		var from := (_f - t0) / 60.0
		if from >= st.get_length() - 0.02:
			continue
		var v := _voices[0]
		for c in _voices:
			if not c.playing:
				v = c
				break
		v.stream = st
		v.play(maxf(from, 0.0))


func _impact_kind() -> int:
	var g := int(_g())
	if g < 0 or g >= IMPACT:
		return 0
	return 1 if g < 2 else 2


func _update_movie() -> void:
	var v0 := _pv("ult_vanish_frame", 8.0)
	var on := _f >= v0 and _f < _calm() and _movie.stream != null
	_movie_layer.visible = on
	if on:
		if not _movie.is_playing():
			_movie.play()
		_movie.modulate.a = _ramp(_f, v0, v0 + 4.0)
	elif _movie.is_playing():
		_movie.stop()


func _update_impact() -> void:
	var kind := _impact_kind()
	_white.visible = kind != 0
	for s in _data.get("shades", []):
		if is_instance_valid(s) and s.is_alive():
			s.ult_flat(Color.BLACK if kind == 1 else Color.WHITE if kind == 2 else Color(0, 0, 0, 0))


## 她：发动时居合架势、冲击帧起低位收势、“咔”起收剑；平常的角色帧藏起来
func _update_body(reveal: float) -> void:
	var key: StringName = player.get("ult_body") if _ok() else &""
	var hide_view := key != &"" or bool(player.get("ult_hidden"))
	if is_instance_valid(_view):
		var box := _view.get_parent() as CanvasItem
		if box != null:
			box.modulate.a = 0.0 if hide_view else 1.0
	_body.visible = key != &"" and _tex.get(key) != null
	if not _body.visible:
		return
	_body.texture = _tex[key]
	var face := int(player.get("facing"))
	_place(_body, player.global_position, face)
	var kind := _impact_kind()
	_body.material = _flat_black if kind == 1 else _flat_white if kind == 2 else _body_violet
	# 颜色恢复的波扫过她之前保持黑白留紫
	_body_violet.set_shader_parameter("amount", 1.0 if reveal < 0.12 else 0.0)


## 定格图按前脚脚尖对齐到身体位置；朝左时水平翻转
func _place(s: Sprite2D, body: Vector2, face: int) -> void:
	var fo: Variant = player.get("foot_offset") if _ok() else null
	var feet := body.y + (float(fo) if fo != null else 84.0)
	var w := s.texture.get_size().x if s.texture != null else ANCHOR.x
	s.flip_h = face < 0
	s.offset = Vector2(-(w - ANCHOR.x) if face < 0 else -ANCHOR.x, -ANCHOR.y)
	s.position = Vector2(body.x + float(face) * FOOT_DX, feet)


## 原地留下的影子：冲击帧起出现，轻轻闪；“咔”之后几帧散掉（碎成羽毛飞回她身上）
func _update_shadow(g: float) -> void:
	var t := _after(true)
	var on := g >= 0.0 and t < 6.0
	_shadow.visible = on
	if not on:
		return
	var kind := _impact_kind()
	var flick := 0.82 + 0.08 * sin(g * 0.9) + (0.06 if int(g) % 23 < 2 else 0.0)
	var a := flick if t <= 0.0 else flick * (1.0 - t / 6.0)
	if kind != 0:
		a = 1.0
	var last := _shadow_parts.size() - 1
	for i in _shadow_parts.size():
		var s := _shadow_parts[i]
		_place(s, _start, _face0)
		s.position += SHADOW_RIM[i]
		s.visible = kind == 0 or i == last
		if i == last:
			s.material = _flat_black if kind != 2 else _flat_white
		s.modulate.a = a
	_shadow.position = Vector2((2.0 if int(g) % 17 == 0 else 0.0), 0.0) if kind == 0 else Vector2.ZERO


## 镜头：发动时往她身上推一点；回到游戏后放大框住起点到终点，静的时候极慢推近，收尾回到平常
func _update_camera(g: float, ts: float, total: float) -> void:
	if not is_instance_valid(_cam):
		return
	var stand: Vector2 = _data.get("stand", _start)
	if is_instance_valid(anchor) and _center0 != Vector2.INF:
		# 发动时往她身上靠；回到游戏后对准影子和她的正中间
		if g < 0.0:
			anchor.global_position = _center0.lerp(Vector2(_start.x, _center0.y), _ramp(_f, 0.0, 8.0, true) * 0.5)
		else:
			anchor.global_position = Vector2((_start.x + stand.x) * 0.5, _center0.y)
	var z := 1.0
	var drop := 0.0
	if g < 0.0:
		z = lerpf(1.0, 1.12, _ramp(_f, 0.0, 8.0, true))
	else:
		var span := absf(stand.x - _start.x) + 520.0
		var zcap := maxf(1.0, get_viewport().get_visible_rect().size.x / (span * maxf(_zoom0.x, 0.01)))
		var zz := minf(CAM_Z, zcap)
		if ts <= 0.0:
			z = zz * lerpf(1.0, 1.053, _ramp(g, 4.0, _ka(), true))
		else:
			z = zz * lerpf(1.053, 0.933, _ramp(ts, 0.0, 24.0, true))
		var back := _ramp(_f, total - 34.0, total - 4.0, true)
		z = lerpf(z, 1.0, back)
		var fo: Variant = player.get("foot_offset")
		var feet := stand.y + (float(fo) if fo != null else 84.0)
		var lock: Variant = _cam.get("lock_y")
		var cy := float(lock) if lock != null and is_finite(float(lock)) else _cam.global_position.y
		drop = (feet - CAM_DROP - cy) * (1.0 - back)
	_cam.zoom = _zoom0 * z
	if _cam.get("base_offset") != null:
		_cam.base_offset = _offset0 + Vector2(0.0, drop)
	# 镜头自己的跟随在这之前已经跑过了：当帧就对准，冲击帧那一刻不能晚一帧
	if _cam.has_method("snap_to_target"):
		_cam.snap_to_target()


func _update_hud(ts: float) -> void:
	var want := 0.0 if ts < 50.0 else 1.0
	_hud_k = move_toward(_hud_k, want, 1.0 / 6.0 if want < _hud_k else 1.0 / 10.0)
	_apply_hud()


func _apply_hud() -> void:
	if not is_instance_valid(hud):
		return
	hud.modulate.a = _hud_k
	if hud.get("muted") != null:
		hud.muted = _phase != 0


func _restore_view() -> void:
	if is_instance_valid(_view):
		var box := _view.get_parent() as CanvasItem
		if box != null:
			box.modulate.a = 1.0
	_view = null


# ---------------------------------------------------------------- 羽毛 / 碎片（发动时一次算好）

## 一片鸦羽（局部坐标，羽轴沿 x，中心在原点）：poly 填充，top 上缘（画一线紫光）
func _feather(length: float) -> Dictionary:
	var w := length * _rng.randf_range(0.22, 0.3)
	var top := PackedVector2Array()
	var bot := PackedVector2Array()
	for i in range(1, 20):
		var u := float(i) / 20.0
		var prof := pow(sin(PI * u), 0.65)
		top.append(Vector2((u - 0.5) * length, -prof * w * 0.5))
		bot.append(Vector2((u - 0.5) * length, prof * w * 0.38))
	var poly := PackedVector2Array([Vector2(-0.5 * length, 0.0)])
	poly.append_array(top)
	poly.append(Vector2(0.5 * length, 0.0))
	bot.reverse()
	poly.append_array(bot)
	return {"poly": poly, "top": top}


static func _xf_poly(poly: PackedVector2Array, pos: Vector2, ang: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in poly:
		out.append(pos + p.rotated(ang))
	return out


func _line_y() -> float:
	var fp: Dictionary = _data.get("final", {"p": _start, "d": Vector2.RIGHT})
	return (fp.p as Vector2).y


func _build_feathers() -> void:
	var stand: Vector2 = _data.get("stand", _start + Vector2(640.0, 0.0))
	var cx := (_start.x + stand.x) * 0.5
	var ly := _line_y()
	var fo: Variant = player.get("foot_offset") if _ok() else null
	var feet := stand.y + (float(fo) if fo != null else 84.0)
	# 远近不同的悬停鸦羽
	for i in 50:
		var f := _feather(_rng.randf_range(12.0, 30.0))
		_ambient.append({"pos": Vector2(cx + _rng.randf_range(-950.0, 950.0), _rng.randf_range(ly - 560.0, feet + 60.0)),
			"ang": _rng.randf_range(0.0, TAU), "poly": f.poly, "top": f.top, "depth": 1.0,
			"vx": _rng.randf_range(-0.3, 0.3), "spin": _rng.randf_range(-2.5, 2.5), "alpha": 1.0})
	for i in 7:
		var f := _feather(_rng.randf_range(70.0, 110.0))
		_ambient.append({"pos": Vector2(cx + _rng.randf_range(-800.0, 800.0), _rng.randf_range(ly - 300.0, feet + 40.0)),
			"ang": _rng.randf_range(0.0, TAU), "poly": f.poly, "top": f.top, "depth": 1.6,
			"vx": _rng.randf_range(-0.3, 0.3), "spin": _rng.randf_range(-2.5, 2.5), "alpha": 0.55})
	# 刀线上被切成两半的鸦羽（世界坐标，按刀线切）
	var x0 := minf(_start.x, stand.x) + 60.0
	var x1 := maxf(_start.x, stand.x) - 60.0
	var above := PackedVector2Array([Vector2(-1.0e5, -1.0e5), Vector2(1.0e5, -1.0e5), Vector2(1.0e5, ly), Vector2(-1.0e5, ly)])
	var below := PackedVector2Array([Vector2(-1.0e5, ly), Vector2(1.0e5, ly), Vector2(1.0e5, 1.0e5), Vector2(-1.0e5, 1.0e5)])
	for i in 11:
		var x := lerpf(x0, x1, (float(i) + _rng.randf_range(-0.3, 0.3)) / 10.0)
		var f := _feather(_rng.randf_range(36.0, 52.0))
		var wp := _xf_poly(f.poly, Vector2(x, ly + _rng.randf_range(-6.0, 6.0)), deg_to_rad(_rng.randf_range(-40.0, 40.0)))
		var up := Geometry2D.intersect_polygons(wp, above)
		var dn := Geometry2D.intersect_polygons(wp, below)
		if up.is_empty() or dn.is_empty():
			continue
		_cut.append({"halves": [up[0], dn[0]], "spin": _rng.randf_range(-2.5, 2.5), "vx": _rng.randf_range(-0.3, 0.3)})


func _build_shards() -> void:
	var tex: Texture2D = _tex.get(&"iai")
	if tex == null:
		return
	var img := tex.get_image()
	if img == null or img.is_empty():
		return
	if img.is_compressed():
		img.decompress()
	var fo: Variant = player.get("foot_offset") if _ok() else null
	var feet := _start.y + (float(fo) if fo != null else 84.0)
	var origin := Vector2(_start.x + float(_face0) * FOOT_DX, feet)
	var tries := 0
	while _shards.size() < 26 and tries < 4000:
		tries += 1
		var px := _rng.randi_range(0, img.get_width() - 1)
		var py := _rng.randi_range(0, img.get_height() - 1)
		if img.get_pixel(px, py).a < 0.5:
			continue
		var lx := (float(px) - ANCHOR.x) * BODY_SCALE
		if _face0 < 0:
			lx = -lx
		var f := _feather(_rng.randf_range(18.0, 32.0))
		_shards.append({"from": origin + Vector2(lx, (float(py) - ANCHOR.y) * BODY_SCALE),
			"bend": _rng.randf_range(-120.0, -20.0), "poly": f.poly, "top": f.top, "ang": _rng.randf_range(0.0, TAU)})


func _build_debris() -> void:
	var ly := _line_y()
	var shades: Array = _data.get("shades", [])
	if shades.is_empty():
		return
	for i in 70:
		var s = shades[i % shades.size()]
		if not is_instance_valid(s):
			continue
		_debris.append({"pos": Vector2(s.global_position.x + _rng.randf_range(-40.0, 40.0), ly + _rng.randf_range(-12.0, 12.0)),
			"vel": Vector2(_rng.randf_range(-8.0, 8.0), _rng.randf_range(-10.0, 2.0)), "size": _rng.randf_range(4.0, 10.0)})


# ---------------------------------------------------------------- 画

func _draw_feathers() -> void:
	var g := _g()
	if g < IMPACT:
		return
	var k := maxf(_after(true), 0.0)
	# 悬停的鸦羽：静的时候定住，咔之后按正常速度落下
	for a in _ambient:
		var pos: Vector2 = a.pos + Vector2(float(a.vx) * k * 6.0, (0.06 * k * k + 0.6 * k) * float(a.depth) * 2.0)
		_draw_one(a.poly, a.top, pos, float(a.ang) + deg_to_rad(float(a.spin) * k), float(a.alpha))
	# 刀线上被切开的：两半慢慢错开，断口一线紫
	var sep := (_ramp(g, 4.0, 48.0, true) * 4.0 + k * 0.4) * 2.0
	for c in _cut:
		for h in 2:
			var sgn := -1.0 if h == 0 else 1.0
			var poly: PackedVector2Array = c.halves[h]
			var off := Vector2(float(c.vx) * k * 6.0 + sgn * sep * 0.6, sgn * sep + (0.06 * k * k + 0.6 * k) * 2.0)
			var ctr := _centroid(poly)
			var rot := deg_to_rad(float(c.spin) * k * sgn)
			var moved := PackedVector2Array()
			for p in poly:
				moved.append(ctr + off + (p - ctr).rotated(rot))
			if moved.size() >= 3:
				_feathers.draw_colored_polygon(moved, FEATHER_INK)
				var edge := _cut_edge(poly, _line_y())
				if edge.size() == 2:
					var ea: Vector2 = ctr + off + (edge[0] - ctr).rotated(rot)
					var eb: Vector2 = ctr + off + (edge[1] - ctr).rotated(rot)
					_feathers.draw_line(ea, eb, Color(0.78, 0.6, 1.0, 1.0), 2.0)
	# 影子碎成的羽毛飞回她身上
	var t := _after(true)
	if t >= 0.0 and t < 46.0 and _g() >= _ka():
		var u := _ramp(t, 0.0, 40.0, true)
		var fo: Variant = player.get("foot_offset")
		var to := player.global_position + Vector2(0.0, (float(fo) if fo != null else 84.0) - 72.0)
		for s in _shards:
			var from: Vector2 = s.from
			var mid := (from + to) * 0.5 + Vector2(0.0, minf(from.y, to.y) - (from.y + to.y) * 0.5 + float(s.bend) - 80.0)
			var p := from * (1.0 - u) * (1.0 - u) + mid * 2.0 * (1.0 - u) * u + to * u * u
			_draw_one(s.poly, s.top, p, float(s.ang) + deg_to_rad(t * 12.0), 1.0 - maxf(0.0, u - 0.75) / 0.25)
	# 影裂开时的黑色碎片
	var kd := _after(true) - 6.0
	if kd >= 0.0:
		var alpha := maxf(0.0, 1.0 - kd * 6.0 / 255.0)
		if alpha > 0.0:
			for d in _debris:
				var p: Vector2 = d.pos + (d.vel as Vector2) * kd + Vector2(0.0, 0.24 * kd * kd)
				var sz := float(d.size)
				_feathers.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -sz), p + Vector2(sz * 0.6, 0), p + Vector2(0, sz * 0.4)]), Color(0.04, 0.03, 0.06, alpha))


func _draw_one(poly: PackedVector2Array, top: PackedVector2Array, pos: Vector2, ang: float, alpha: float) -> void:
	if alpha <= 0.01:
		return
	_feathers.draw_set_transform(pos, ang, Vector2.ONE)
	_feathers.draw_colored_polygon(poly, Color(FEATHER_INK, alpha))
	_feathers.draw_polyline(top, Color(VIOLET_L, 0.66 * alpha), 1.5)
	_feathers.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func _centroid(poly: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for p in poly:
		c += p
	return c / maxf(float(poly.size()), 1.0)


## 半片羽毛贴着刀线的那条边（两端点）
static func _cut_edge(poly: PackedVector2Array, y: float) -> PackedVector2Array:
	var lo := INF
	var hi := -INF
	for p in poly:
		if absf(p.y - y) < 0.6:
			lo = minf(lo, p.x)
			hi = maxf(hi, p.x)
	if hi - lo < 1.0:
		return PackedVector2Array()
	return PackedVector2Array([Vector2(lo, y), Vector2(hi, y)])


## 冲击帧的底（在地形之上、角色之下）
func _draw_white() -> void:
	if not is_instance_valid(_cam):
		return
	var kind := _impact_kind()
	if kind == 0:
		return
	var c := _cam.get_screen_center_position()
	var size := get_viewport().get_visible_rect().size / _cam.zoom * 1.4
	_white.draw_rect(Rect2(c - size * 0.5, size), PAPER if kind == 1 else Color.BLACK)


func _line_screen() -> Vector2:
	return get_viewport().get_canvas_transform() * Vector2(_start.x, _line_y())


func _draw_ui_front() -> void:
	var vs := get_viewport().get_visible_rect().size
	var g := _g()
	var kind := _impact_kind()
	var ts := _after(false)
	var y := _line_screen().y
	# 刀线：冲击帧上黑 / 白一道；静的时候白芯紫光，慢慢变淡；咔之后褪掉
	if g >= 0.0:
		if kind == 1:
			_ui_front.draw_line(Vector2(0.0, y), Vector2(vs.x, y), Color.BLACK, 3.0)
		elif kind == 2:
			_ui_front.draw_line(Vector2(0.0, y), Vector2(vs.x, y), Color.WHITE, 3.0)
		else:
			var la := 1.0 if g < 10.0 else maxf(0.35, 1.0 - (g - 10.0) / 30.0)
			var t := _after(true)
			if t >= 0.0:
				la *= maxf(0.0, 1.0 - t / 20.0)
			if la > 0.01:
				var core := 2.0 if g < 30.0 else 1.0
				var glow := 14.0 if g < 30.0 else 8.0
				for i in 4:
					var w := glow * (1.0 - float(i) * 0.22)
					_ui_front.draw_line(Vector2(0.0, y), Vector2(vs.x, y), Color(0.63, 0.43, 1.0, 0.16 * la), w)
				_ui_front.draw_line(Vector2(0.0, y), Vector2(vs.x, y), Color(1, 1, 1, la), core)
	# 咔：腰间一线白光
	var t2 := _after(true)
	if g >= _ka() and t2 < 8.0 and _ok():
		var a := 1.0 - maxf(t2, 0.0) / 8.0
		var xf := get_viewport().get_canvas_transform()
		var face := float(player.get("facing"))
		var fo: Variant = player.get("foot_offset")
		var waist := player.global_position + Vector2(-face * 6.0, (float(fo) if fo != null else 84.0) - 64.0)
		var p0 := xf * (waist - Vector2(36.0, 0.0))
		var p1 := xf * (waist + Vector2(36.0, 0.0))
		_ui_front.draw_line(p0, p1, Color(1, 1, 1, a), 2.0)
	# 上下黑边（最上面）：发动时收进来，咔之后退出
	var bars := _ramp(_f, 0.0, 7.0, true) * (1.0 - _ramp(ts, 0.0, 20.0, true))
	if bars > 0.001:
		_ui_front.draw_rect(Rect2(0.0, 0.0, vs.x, BAR_H * bars), Color.BLACK)
		_ui_front.draw_rect(Rect2(0.0, vs.y - BAR_H * bars, vs.x, BAR_H * bars), Color.BLACK)


# ---------------------------------------------------------------- 工具

static func _ramp(x: float, a: float, b: float, ease_out: bool = false) -> float:
	var t := clampf((x - a) / maxf(b - a, 0.0001), 0.0, 1.0)
	return 1.0 - pow(1.0 - t, 3.0) if ease_out else t


static func _find_view(root: Node) -> Sprite2D:
	for c in root.get_children():
		if c is Sprite2D and c.get_script() != null and String(c.get_script().resource_path).ends_with("character_view.gd"):
			return c
		var r := _find_view(c)
		if r != null:
			return r
	return null


func _ok() -> bool:
	return is_instance_valid(player)


func _pv(name: String, fallback: float) -> float:
	if _ok() and player.get(name) != null:
		return float(player.get(name))
	return fallback
