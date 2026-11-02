extends Node2D
## 大招「绝影 · 鸦羽止」的表现（10-31 用户说“干活”：照整段预览 13 做进游戏；同日看完预览 17 说“可以进游戏先”，换成预览 17，又删掉光痕拉出换成预览 18；
## 旧的 v4 过场版留在 ult_fx.gd.bak-v4-20261031；11-01 用户看完预览 22c 说“可以，进游戏”：地图斩换成 v5，时停缩短、推近看收刀；
## 同日用户：“大招尾部改成预览21样子”：换成 v6，时停仍缩短，断开后回到广角收尾、不推近；
## 同日用户选 26×2b 做进游戏：挥刀转地图“刀光白屏”——剑挥到底慢放 2 倍甩出 12 帧一路烧白，甩出最后一帧和地图斩第一帧整屏白，爆发 5 帧退掉）。
## 样片：tools/art/src/ult/feather/大招整段预览_26x2b_烧白从甩出开始.mp4（Remotion UltFullPreview26x2），细节见 docs/大招-全程过场-规划.md。
## 时间轴跟着主角的 ult_frame（60fps，边界读 player.gd 的 ult_* 参数）：
##   0～ult_vanish_frame（66）      ① 开场领域展开：镜头升起成墙角，墨从她脚下铺满地面、折上墙、折下立面，鸦式神破墨而出，黑屏。
##                                  用当前游戏画面实时做（fx_ult_domain.gdshader + ult_opening.gd），任何地图都能用
##   ～ult_calm_start（162）        ② 睁眼 + ③ 挥刀：全屏放 assets/video/ult_eyes_swing.ogv（这段和地图无关，预渲染；最后 12 帧横向甩出、烧白，最后一帧整屏白）
##   ～ult_total_frames（276）      ④ 地图斩 + ⑤ 收刀：回到游戏世界，第一帧整屏白，横向糊着甩进来、提亮爆发退掉、抖一下；
##                                  斩线射出、时停、整条街沿线错开（第 20 帧影全部斩开）、收刀、
##                                  “咔”（第 60 帧）合回去、斩线碎成鸦羽、影子退潮、镜头回到平常。
##                                  世界用 fx_ult_world.gdshader，斩线 / 她 / 羽毛用 ult_map_slash.gd，冲击帧 / 时停用 fx_ult_post.gdshader
## 声音：整段一条混音 assets/audio/ult/ult_full.ogg（26×2b，同预览 23 = 22c 的声音：开场音效路线 B、鸦鸣和翻翅压小，睁眼心跳越来越快，冲击帧重击，收刀拖尾），第 0 帧开始放。
## 媒体由 tools/art/export_ult_game_media.sh 从 Remotion 导出。

const DOMAIN_SHADER := preload("res://assets/shaders/fx_ult_domain.gdshader")
const WORLD_SHADER := preload("res://assets/shaders/fx_ult_world.gdshader")
const POST_SHADER := preload("res://assets/shaders/fx_ult_post.gdshader")
const HER_SHADER := preload("res://assets/shaders/fx_ult_her.gdshader")
const Opening := preload("res://scripts/night/ult_opening.gd")
const MapSlash := preload("res://scripts/night/ult_map_slash.gd")
const MOVIE_PATH := "res://assets/video/ult_eyes_swing.ogv"
const AUDIO_PATH := "res://assets/audio/ult/ult_full.ogg"
const SFX_BUS := &"SFX_Impact"
const BAR_H := 56.0                 ## 开场的上下黑边（屏幕像素）
const NORMAL_SC := 1.5              ## 样片镜头 1.5 倍 = 游戏平常镜头（她约 110 屏幕像素高）
const WHIP_IN := 5.0                ## 挥刀甩进地图斩：横向模糊退掉的帧数
const WHIP_PX := 30.0               ## 横向模糊最大值（屏幕像素）
const MOVIE_LEAD := 2.0             ## 视频 play() 后要约 2 帧才出画面：提前这么多帧在黑场底下开始放，不然最后几帧（甩出）会被地图斩切掉
const WHITE := Color(0.984, 0.976, 1.0)   ## 刀光白屏的白（#fbf9ff，偏一点冷紫）

var fx: Node2D               ## ImpactFX（没用到，保留接口）
var player: Node2D
var hud: Control
var anchor: Node2D           ## 关卡给的镜头钉子（大招期间镜头跟它）

var _phase: int = 0          ## 0 没在放 / 1 放的时候
var _f: float = 0.0
var _data: Dictionary = {}
var _total: float = 0.0
var _cam: Camera2D
var _zoom0 := Vector2.ONE
var _offset0 := Vector2.ZERO
var _center0 := Vector2.INF  ## 发动时镜头中心（世界）
var _anchor0 := Vector2.INF
var _feet := Vector2.ZERO    ## 她脚下（世界）
var _side := 1.0             ## 斩线往哪边（敌群那边）
var _view: Sprite2D          ## 她平常的角色帧（character_view），大招期间藏起来，另画一份

var _world_layer: CanvasLayer
var _domain_rect: ColorRect
var _domain_mat: ShaderMaterial
var _world_rect: ColorRect
var _world_mat: ShaderMaterial
var _top: CanvasLayer        ## 跟着镜头走：斩线、她、羽毛
var _slash: Node2D
var _scr: CanvasLayer        ## 屏幕空间：开场的纸片和她、黑场、原画面、黑边；地图斩的后期和纯黑冲击帧
var _open_back: Node2D
var _open_front: Node2D
var _open_her: Sprite2D
var _open_her_mat: ShaderMaterial
var _fade: ColorRect
var _snap: TextureRect
var _bars: Array[ColorRect] = []
var _post_copy: BackBufferCopy
var _post_rect: ColorRect
var _post_mat: ShaderMaterial
var _scr_fx: Node2D
var _movie_layer: CanvasLayer
var _movie: VideoStreamPlayer
var _voice: AudioStreamPlayer
var _black_line := PackedVector2Array()   ## 纯黑冲击帧那条白线（屏幕）
var _floaters: Array = []    ## 断开后被震起来再慢慢落的羽毛（屏幕空间）
var _hidden_layers: Array[CanvasLayer] = []   ## 关卡自己画在上面的层（屏幕外敌人箭头等），大招期间藏起来


func _ready() -> void:
	process_priority = 10
	# 世界层：全屏读屏幕（光影后期第 5 层，HUD 第 10 层）
	_world_layer = CanvasLayer.new()
	_world_layer.layer = 6
	add_child(_world_layer)
	var b := BackBufferCopy.new()
	b.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	_world_layer.add_child(b)
	_domain_mat = _mat(DOMAIN_SHADER)
	_domain_rect = _full_rect(_domain_mat)
	_world_layer.add_child(_domain_rect)
	_world_mat = _mat(WORLD_SHADER)
	_world_rect = _full_rect(_world_mat)
	_world_layer.add_child(_world_rect)
	_top = CanvasLayer.new()
	_top.layer = 8
	_top.follow_viewport_enabled = true
	add_child(_top)
	_slash = MapSlash.new()
	_top.add_child(_slash)
	_scr = CanvasLayer.new()
	_scr.layer = 9
	add_child(_scr)
	_open_back = Opening.new()
	_scr.add_child(_open_back)
	_open_her = Sprite2D.new()
	_open_her_mat = _mat(HER_SHADER)
	_open_her.material = _open_her_mat
	_scr.add_child(_open_her)
	_open_front = Opening.new()
	_open_front.front = true
	_scr.add_child(_open_front)
	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.size = Vector2(1280, 720)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scr.add_child(_fade)
	_snap = TextureRect.new()
	_snap.size = Vector2(1280, 720)
	_snap.stretch_mode = TextureRect.STRETCH_SCALE
	_snap.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_snap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scr.add_child(_snap)
	for i in 2:
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_scr.add_child(bar)
		_bars.append(bar)
	_post_copy = BackBufferCopy.new()
	_post_copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	_scr.add_child(_post_copy)
	_post_mat = _mat(POST_SHADER)
	_post_rect = _full_rect(_post_mat)
	_scr.add_child(_post_rect)
	_scr_fx = Node2D.new()
	_scr.add_child(_scr_fx)
	_scr_fx.draw.connect(_draw_scr_fx)
	# 睁眼 + 挥刀视频：最上面一层，全屏
	_movie_layer = CanvasLayer.new()
	_movie_layer.layer = 12
	add_child(_movie_layer)
	# 垫黑底：play() 的那一帧视频还没解出画面，不垫会露出底下的斩图世界闪一下
	var movie_back := ColorRect.new()
	movie_back.color = Color.BLACK
	movie_back.set_anchors_preset(Control.PRESET_FULL_RECT)
	movie_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_movie_layer.add_child(movie_back)
	_movie = VideoStreamPlayer.new()
	_movie.set_anchors_preset(Control.PRESET_FULL_RECT)
	_movie.expand = true
	_movie.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(MOVIE_PATH):
		_movie.stream = load(MOVIE_PATH)
	_movie_layer.add_child(_movie)
	_voice = AudioStreamPlayer.new()
	_voice.bus = SFX_BUS if AudioServer.get_bus_index(SFX_BUS) >= 0 else &"Master"
	_voice.stream = _load_audio(AUDIO_PATH)
	add_child(_voice)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1031
	for i in 26:
		_floaters.append({"x": rng.randf() * 1380.0 - 50.0, "y": rng.randf() * 900.0 - 100.0, "L": 14.0 + 22.0 * rng.randf(),
			"sp": 0.9 + 1.4 * rng.randf(), "ph": rng.randf() * TAU, "sw": 10.0 + 24.0 * rng.randf(), "near": rng.randf() < 0.25})
	_set_layers(false)


static func _mat(sh: Shader) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = sh
	return m


static func _full_rect(m: ShaderMaterial) -> ColorRect:
	var r := ColorRect.new()
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.material = m
	return r


static func _load_audio(path: String) -> AudioStream:
	var absolute := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(absolute):
		return AudioStreamOggVorbis.load_from_file(absolute)
	if ResourceLoader.exists(path):
		return load(path) as AudioStream
	return null


func _set_layers(on: bool) -> void:
	_world_layer.visible = on
	_top.visible = on
	_scr.visible = on
	_movie_layer.visible = false
	if not on and _movie.is_playing():
		_movie.stop()


# ---------------------------------------------------------------- 对外（night_trial 调）

## 发动。data：side（敌群在哪边）、shades
func begin(data: Dictionary) -> void:
	clear()
	_phase = 1
	_data = data
	_side = float(data.get("side", 1))
	_cam = get_viewport().get_camera_2d()
	if is_instance_valid(_cam):
		_zoom0 = _cam.zoom
		_offset0 = _cam.get("base_offset") if _cam.get("base_offset") != null else Vector2.ZERO
		_center0 = _cam.get_screen_center_position()
	else:
		_center0 = get_viewport().get_visible_rect().size * 0.5
	_anchor0 = anchor.global_position if is_instance_valid(anchor) else Vector2.INF
	var fo: Variant = player.get("foot_offset") if _ok() else null
	_feet = (player.global_position if _ok() else global_position) + Vector2(0.0, float(fo) if fo != null else 84.0)
	_view = _find_view(player) if _ok() else null
	# 开场：发动前那一帧的画面（带着她），开头 8 帧盖在上面淡掉
	# 无窗口（测试用的空渲染器）读不出画面，跳过
	var img: Image = null
	if DisplayServer.get_name() != "headless":
		img = get_viewport().get_texture().get_image()
	_snap.texture = ImageTexture.create_from_image(img) if img != null else null
	var fs := _to_screen(_feet)
	_domain_mat.set_shader_parameter("base", fs.y - 10.0)
	_domain_mat.set_shader_parameter("hx", fs.x)
	for o in [_open_back, _open_front]:
		o.setup(fs.y - 10.0, fs.x)
	_set_layers(true)
	_hide_view(true)
	_hide_stage_layers()
	if is_instance_valid(hud):
		hud.modulate.a = 0.0
		if hud.get("muted") != null:
			hud.muted = true
	if _voice.stream != null:
		_voice.play()
	_update(0.0)


func strike(_i: int) -> void:
	pass


func arrive() -> void:
	pass


## “咔”那一刻：总伤害（伤害数字由关卡在斩开时弹，留着接口）
func reveal(total: float) -> void:
	_total = total


func spark(_point: Vector2) -> void:
	pass


## 关卡斩开第 i 只影：影闪白一下（地图斩的整条街错开已经在画）
func slice(s: Node2D, _i: int) -> void:
	if _phase == 0 or not is_instance_valid(s):
		return
	if s.get("flash") != null:
		s.flash = 4
		s.flash_color = Color.WHITE


func clear() -> void:
	_hide_view(false)
	for l in _hidden_layers:
		if is_instance_valid(l):
			l.visible = true
	_hidden_layers.clear()
	_view = null
	if _anchor0 != Vector2.INF and is_instance_valid(anchor):
		anchor.global_position = _anchor0
	if _phase != 0 and is_instance_valid(_cam):
		_cam.zoom = _zoom0
		if _cam.get("base_offset") != null:
			_cam.base_offset = _offset0
		_cam.offset = _offset0
	if _voice.playing:
		_voice.stop()
	_phase = 0
	_f = 0.0
	_data = {}
	_total = 0.0
	_center0 = Vector2.INF
	_anchor0 = Vector2.INF
	_snap.texture = null
	_set_layers(false)
	if is_instance_valid(hud):
		hud.modulate.a = 1.0
		if hud.get("muted") != null:
			hud.muted = false


func busy() -> bool:
	return _phase != 0


# ---------------------------------------------------------------- 时间

func _open_end() -> float:
	return _pv("ult_vanish_frame", 66.0)


func _map_at() -> float:
	return _pv("ult_calm_start", 162.0)


func _process(_delta: float) -> void:
	if _phase == 0:
		return
	if not (_ok() and player.is_ult()):
		clear()
		return
	_update(float(player.ult_frame))


func _update(frame: float) -> void:
	_f = frame
	var open := _f < _open_end()
	var movie := not open and _f < _map_at()
	var movie_run := _f >= _open_end() - MOVIE_LEAD and _f < _map_at()
	_domain_rect.visible = open
	_open_back.visible = open
	_open_front.visible = open
	_open_her.visible = open
	_fade.visible = open
	_snap.visible = open
	for bar in _bars:
		bar.visible = open
	_world_rect.visible = not open
	_top.visible = not open
	_post_copy.visible = not open
	_post_rect.visible = not open
	_scr_fx.visible = not open
	_update_movie(movie, movie_run)
	if open:
		_update_opening()
	else:
		_update_map(maxf(_f - _map_at(), 0.0))
	var total := _pv("ult_total_frames", 276.0)
	if is_instance_valid(hud):    # 最后 12 帧 HUD 回来
		hud.modulate.a = clampf((_f - (total - 12.0)) / 12.0, 0.0, 1.0)


## 提前 MOVIE_LEAD 帧开始放（层先藏着），到点再显示；跳帧（测试直接改帧号）时视频从头放，不追
func _update_movie(show: bool, run: bool) -> void:
	run = run and _movie.stream != null
	_movie_layer.visible = show and run
	if run and not _movie.is_playing():
		_movie.play()
	elif not run and _movie.is_playing():
		_movie.stop()


# ---------------------------------------------------------------- ① 开场

func _update_opening() -> void:
	var real := _f
	var step := floorf(real / 2.0) * 2.0           # 墨、式神一拍二；镜头、她的亮度逐帧
	_domain_mat.set_shader_parameter("f", step)
	_domain_mat.set_shader_parameter("real", real)
	for o in [_open_back, _open_front]:
		o.real = real
		o.f = step
		o.queue_redraw()
	_fade.color.a = Opening.ease_in_out(Opening.ramp(real, 46.0, 60.0))
	_snap.modulate.a = 1.0 - Opening.ease_out(Opening.ramp(real, 0.0, 8.0))
	var bar := BAR_H * Opening.ease_out(Opening.ramp(real, 2.0, 8.0))
	_bars[0].position = Vector2.ZERO
	_bars[0].size = Vector2(1280, bar)
	_bars[1].position = Vector2(0, 720.0 - bar)
	_bars[1].size = Vector2(1280, bar)
	_update_open_her(real)


## 她：站在地面上离墙 HER_Z，跟着镜头一起透视；影子铺开时一点点暗下去，紫边也一起收
func _update_open_her(real: float) -> void:
	var src := _view
	_open_her.visible = src != null and src.texture != null
	if not _open_her.visible:
		return
	_copy_sprite(src, _open_her)
	var base: float = _open_back.base
	var c := Opening.cam(base, real)
	var s := Opening.P / (Opening.P - (Opening.HER_Z + c.z))
	var o := Vector2(640.0, c.x)
	var proj := Transform2D(0.0, Vector2(s, s), 0.0, o - o * s + Vector2(0.0, c.y * s))
	_open_her.transform = proj * get_viewport().get_canvas_transform() * src.get_global_transform()
	var cover := pow(clampf((Opening.reach(real) - Opening.HER_Z) / (1100.0 - Opening.HER_Z), 0.0, 1.0), 0.8)
	var lit := 1.0 - 0.88 * cover
	var glow := Opening.ramp(real, 6.0, 14.0)
	_open_her_mat.set_shader_parameter("sat", 0.4 + 0.6 * lit)
	_open_her_mat.set_shader_parameter("bright", (0.9 + 0.3 * glow) * lit)
	_open_her_mat.set_shader_parameter("rim_a", 0.95 * glow * lit)
	_open_her_mat.set_shader_parameter("glow_a", 0.55 * glow * lit)
	_open_her_mat.set_shader_parameter("rim_px", 1.5)
	_open_her_mat.set_shader_parameter("glow_px", 6.0)
	_open_her_mat.set_shader_parameter("px_scale", absf(_open_her.transform.get_scale().x))
	_open_her_mat.set_shader_parameter("flat_col", Color(0, 0, 0, 0))


static func _copy_sprite(src: Sprite2D, dst: Sprite2D) -> void:
	dst.texture = src.texture
	dst.centered = src.centered
	dst.offset = src.offset
	dst.flip_h = src.flip_h
	dst.flip_v = src.flip_v
	dst.region_enabled = src.region_enabled
	dst.region_rect = src.region_rect
	dst.hframes = src.hframes
	dst.vframes = src.vframes
	dst.frame = src.frame
	dst.texture_filter = src.texture_filter


# ---------------------------------------------------------------- ④ 地图斩 + ⑤ 收刀

## 样片单位 → 世界：原点对到她脚下，按敌群那边左右翻，1 样片单位 = 平常镜头下 NORMAL_SC 屏幕像素
func _u() -> float:
	return NORMAL_SC / maxf(_zoom0.x, 0.01)


func _v3(p: Vector2) -> Vector2:
	return _feet + Vector2((p.x - MapSlash.HER.x) * _side, p.y - MapSlash.STREET) * _u()


func _update_map(m: float) -> void:
	var cam := MapSlash.camera(m)
	var center := _v3(Vector2(cam.x, cam.y))
	var zoom := _zoom0 * (cam.z / NORMAL_SC)
	var sc := cam.z
	if m >= MapSlash.CLICK:
		# “咔”之后镜头推回游戏平常的机位（样片里是推到 1.5 倍、对准她）
		var k := MapSlash.ease_in_out(MapSlash.ramp(m, MapSlash.CLICK + 2, MapSlash.CLICK + 44))
		center = center.lerp(_center0, k)
		zoom = zoom.lerp(_zoom0, k)
		sc = lerpf(cam.z, NORMAL_SC, k)
	var shake := MapSlash.shake(m) + _whip_shake(m)
	center -= shake / maxf(zoom.x, 0.01)
	_apply_camera(center, zoom)
	# 斩线节点：样片坐标摆进世界
	var u := _u()
	_slash.transform = Transform2D(0.0, Vector2(_side * u, u), 0.0, _feet - Vector2(MapSlash.HER.x * _side * u, MapSlash.STREET * u))
	var kind := MapSlash.impact(int(m))
	var flash := Color.BLACK if kind == 1 else (Color.WHITE if kind == 2 else Color(0, 0, 0, 0))
	_slash.update(m, sc, flash if kind == 1 or kind == 2 else Color(0, 0, 0, 0))
	# 世界：压暗、沿线错开、退潮
	var s := MapSlash.slide(m)
	var to_scr := func(p: Vector2) -> Vector2: return (p - center) * zoom + Vector2(640, 360)
	var piv: Vector2 = to_scr.call(_v3(MapSlash.PIVOT))
	var d := MapSlash.dir()
	var dscr := Vector2(d.x * _side, d.y).normalized()
	var flip := func(v: Vector2) -> Vector2: return Vector2(v.x * _side, v.y) * sc
	var dark := 1.0 - 0.3 * MapSlash.ramp(m, MapSlash.STOP, MapSlash.STOP + 4) + 0.15 * MapSlash.ramp(m, MapSlash.SPLIT, MapSlash.SPLIT + 10)
	_world_mat.set_shader_parameter("dark", dark)
	_world_mat.set_shader_parameter("pivot", piv)
	_world_mat.set_shader_parameter("dir", dscr)
	_world_mat.set_shader_parameter("off_above", flip.call(MapSlash.offset(s, true)))
	_world_mat.set_shader_parameter("off_below", flip.call(MapSlash.offset(s, false)))
	var split := m >= MapSlash.SPLIT and m < MapSlash.CLICK + 3
	_world_mat.set_shader_parameter("split", 1.0 if split else 0.0)
	_world_mat.set_shader_parameter("seam_w", (2.0 + 0.12 * s) * sc)
	_world_mat.set_shader_parameter("seam_glow", (8.0 + 0.25 * s) * sc)
	_world_mat.set_shader_parameter("seam_a", 1.0 - MapSlash.ramp(m, MapSlash.CLICK, MapSlash.CLICK + 3) if m >= MapSlash.CLICK else 1.0)
	var lit := m >= MapSlash.CLICK + 3
	_world_mat.set_shader_parameter("lit", 1.0 if lit else 0.0)
	_world_mat.set_shader_parameter("tide_c", to_scr.call(_v3(Vector2(MapSlash.HER.x, MapSlash.STREET))))
	_world_mat.set_shader_parameter("tide_r", MapSlash.tide_r(m) * sc)
	# 圆里也一起淡回去：游戏的街本来就暗，影子世界几乎全黑，只缩圆会在她脚下剩一块黑（11-01 用户：“怎么最后多出一块”）
	_world_mat.set_shader_parameter("tide_fade", MapSlash.ease_out(MapSlash.ramp(m, MapSlash.CLICK + 2, MapSlash.CLICK + 36)))
	# 退潮完了就把世界层整个关掉（影子已经缩回她脚下）
	_world_rect.visible = not (lit and MapSlash.tide_r(m) <= 0.5)
	# 后期：冲击帧、时停、甩镜头模糊
	var mode := 0
	if kind == 1 or kind == 2:
		mode = kind
	elif m >= MapSlash.STOP + 2 and m < MapSlash.SPLIT:
		mode = 3
	_post_mat.set_shader_parameter("mode", mode)
	_post_mat.set_shader_parameter("blur", cam.w * sc)
	# 挥刀甩进来：第一帧整屏白（视频最后一帧已经是白的），前 WHIP_IN 帧横向糊着进来，提亮爆发 5 帧退掉
	var hb := WHIP_PX * pow(1.0 - clampf(m / WHIP_IN, 0.0, 1.0), 1.5)
	var b := _burst(int(m))
	var white := 1.0 if int(m) == 0 else 0.0
	_post_mat.set_shader_parameter("hblur", hb)
	_post_mat.set_shader_parameter("gain", 1.0 + 3.2 * b)
	_post_mat.set_shader_parameter("con", 1.0 + 0.15 * b)
	_post_mat.set_shader_parameter("white", white)
	_post_mat.set_shader_parameter("white_color", WHITE)
	var need_post := mode != 0 or cam.w * sc > 0.3 or hb > 0.3 or b > 0.0 or white > 0.0
	_post_copy.visible = need_post
	_post_rect.visible = need_post
	# 纯黑冲击帧那条白线
	_black_line = PackedVector2Array()
	if kind == 3:
		_black_line = PackedVector2Array([to_scr.call(_v3(Vector2(-200.0, MapSlash.line_y(-200.0)))),
			to_scr.call(_v3(Vector2(MapSlash.W + 200.0, MapSlash.line_y(MapSlash.W + 200.0))))])
	_scr_fx.set_meta("m", m)
	_scr_fx.queue_redraw()


## 地图斩开头的爆发帧：地图本来就暗，拉反差会压成全黑，所以主要靠提亮（预览 17）；
## 26×2b 白屏退掉也靠它（不用半透明白往下淡，会把黑抬成灰雾）：1 / 1 / 0.55 / 0.25 / 0.08
static func _burst(m: int) -> float:
	return 1.0 if m <= 1 else (0.55 if m == 2 else (0.25 if m == 3 else (0.08 if m == 4 else 0.0)))


## 甩进来那一下的抖：12 帧，按 (1 − m/12)² 衰减（屏幕像素）
static func _whip_shake(m: float) -> Vector2:
	if m < 0.0 or m >= 12.0:
		return Vector2.ZERO
	var a := 12.0 * pow(1.0 - m / 12.0, 2.0)
	var i := floorf(m)
	return Vector2(sin(i * 12.9898) * 43758.5453, sin(i * 78.233) * 12345.6789).posmod(1.0) * 2.0 * a - Vector2(a, a)


## 镜头钉子不动，靠偏移把画面中心摆到 center（镜头会按关卡范围钳制钉子，偏移不受钳制）
func _apply_camera(center: Vector2, zoom: Vector2) -> void:
	if not is_instance_valid(_cam):
		return
	if is_instance_valid(anchor) and _anchor0 != Vector2.INF:
		anchor.global_position = _anchor0
	_cam.zoom = zoom
	var off := center - _cam.global_position
	if _cam.get("base_offset") != null:
		_cam.base_offset = off
	_cam.offset = off


func _to_screen(p: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * p


## 屏幕空间：断开后被震起来、再慢慢落的羽毛（半透明，在斩线后面那层）；纯黑冲击帧
func _draw_scr_fx() -> void:
	var m: float = _scr_fx.get_meta("m", 0.0)
	if _black_line.size() == 2:
		_scr_fx.draw_rect(Rect2(0, 0, 1280, 720), Color.BLACK)
		_scr_fx.draw_line(_black_line[0], _black_line[1], Color.WHITE, 6.0, true)
		return
	var t0 := m - MapSlash.SPLIT - 3.0
	if t0 < 0.0:
		return
	var a := 0.5 * clampf(t0 / 6.0, 0.0, 1.0) * (1.0 - MapSlash.ramp(m, MapSlash.CLICK - 6, MapSlash.CLICK + 6))
	if a <= 0.0:
		return
	var lift := 260.0 * (1.0 - MapSlash.ease_out(clampf(t0 / 18.0, 0.0, 1.0)))
	for p in _floaters:
		var t := t0 + 48.0
		var y: float = fposmod(p.y + t * p.sp, 900.0) - 100.0 + lift
		var x: float = p.x + p.sw * sin(t * 0.04 + p.ph)
		var L: float = p.L * (1.6 if p.near else 1.0)
		_scr_fx.draw_set_transform(Vector2(x, y), 0.9 + 0.5 * sin(t * 0.03 + p.ph), Vector2(1.0, 0.5 + 0.5 * absf(cos(t * 0.05 + p.ph))))
		var fe := MapSlash._feather_poly(L, 0.26, 0.18)
		_scr_fx.draw_colored_polygon(fe, Color(0.05, 0.045, 0.07, a * (0.7 if p.near else 1.0)))
		_scr_fx.draw_line(Vector2(-L * 0.55, 0), Vector2(L * 0.5, 0), Color(0.93, 0.94, 1.0, a * 0.5), 0.8, true)
	_scr_fx.draw_set_transform_matrix(Transform2D.IDENTITY)


# ---------------------------------------------------------------- 杂

func _hide_view(on: bool) -> void:
	if not is_instance_valid(_view):
		return
	var box := _view.get_parent() as CanvasItem
	if box != null:
		box.modulate.a = 0.0 if on else 1.0


## 关卡挂在第 7 层以上的东西（屏幕外敌人的箭头等）会盖在大招画面上：大招期间藏起来（HUD 所在的层除外，HUD 自己淡出淡入）
func _hide_stage_layers() -> void:
	var stage := get_parent()
	if stage == null:
		return
	for c in stage.get_children():
		if c is CanvasLayer and c.visible and c.layer >= 7 and not (is_instance_valid(hud) and c.is_ancestor_of(hud)):
			c.visible = false
			_hidden_layers.append(c)


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
	if not _ok():
		return fallback
	var v: Variant = player.get(name)
	return float(v) if v != null else fallback
