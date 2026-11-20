extends Control
## [YG-MARK] 字成城（11-08）：新首页的原型。字标是立在河里的建筑，菜单是岸上四盏灯。
## 节拍见 docs/视觉设计/首页/字成城_20261108/TREATMENT.md。全部用 delta 推进，录视频时定步长。
## 现在是单独的场景 scenes/yg_gc_title.tscn，不是启动场景。操作说明和设置面板还没接。
## 环境变量 GC_DEMO=1：按固定时刻自动操作，录完自动退出。

const GAME_SCENE := "res://scenes/rain_trial.tscn"
const DIR_IMG := "res://assets/image/yg_glyphcity/"
const SH_SCENE := preload("res://assets/shaders/yg_glyphcity/yg_gc_scene.gdshader")
const SH_FINAL := preload("res://assets/shaders/yg_glyphcity/yg_gc_final.gdshader")
const SH_BLUR := preload("res://assets/shaders/yg_glyphcity/yg_gc_blur.gdshader")
const SH_RAIN := preload("res://assets/shaders/yg_glyphcity/yg_gc_rain.gdshader")
const FONT_FILE := "res://assets/fonts/yg_title/NotoSerifSC-VF.ttf"

const DESIGN := Vector2(1920.0, 1080.0)
const WL := 770.0
const CUT0 := Vector2(1000.0, 372.0)
const ANG := -14.0
const MENU := ["开始游戏", "操作说明", "设置", "退出"]
const LAMP_X := [380.0, 720.0, 1060.0, 1400.0]
const MENU_Y := 992.0
const LAMP_REACH := 222.0

# 节拍（秒）
const T_SLOW := 1.0
const T_DRAW := 1.46
const T_HIT := 1.60
const T_RESUME := 2.30
const T_LAMPS := 2.50
const T_LUX := 3.05

const N_STREAK := 760
const N_DROP := 340
const FREEZE_BAND := 92.0

var D := Vector2(cos(deg_to_rad(ANG)), sin(deg_to_rad(ANG)))
var N := Vector2(-D.y, D.x)

var _vp_scene: SubViewport
var _vp_a: SubViewport
var _vp_b: SubViewport
var _vp_final: SubViewport
var _m_scene: ShaderMaterial
var _m_final: ShaderMaterial
var _m_a: ShaderMaterial
var _m_b: ShaderMaterial
var _m_rain: ShaderMaterial
var _mm: MultiMesh
var _display: TextureRect
var _ui: Control

var t := 0.0
var sel := 0
var ui_on := false
var _rng := RandomNumberGenerator.new()
var _streak: Array = []
var _drop: Array = []
var _drop_next := 0
var _hit_done := false
var _rain_speed := 1.0

var _lamp := [0.0, 0.0, 0.0, 0.0]
var _lamp_flare := [0.0, 0.0, 0.0, 0.0]
var _lamp_len := [0.0, 0.0, 0.0, 0.0]
var _word := [0.0, 0.0, 0.0, 0.0]     # 字浮出来的进度
var _word_sel := [0.0, 0.0, 0.0, 0.0] # 选中的大小，弹簧
var _word_vel := [0.0, 0.0, 0.0, 0.0]
var _ring_t := -1.0
var _ring_x := 0.0
var _sweep_t := -100.0
var _mouse := Vector2.ZERO
var _cam := Vector2.ZERO
var _confirm_t := -1.0
var _skip := false
var _demo := false
var _demo_i := 0
var _font: FontFile
var _black: SystemFont

var _bed: AudioStreamPlayer
var _near: AudioStreamPlayer
var _lp: AudioEffectLowPassFilter
var _bus := "YgGcRain"
var _sfx := {}
var _played := {}

const DEMO := [[5.0, "right"], [5.9, "right"], [7.0, "left2"], [7.7, "ok"]]


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.seed = 20261108
	_demo = OS.get_environment("GC_DEMO") == "1"
	_font = load(FONT_FILE)
	_black = SystemFont.new()
	_black.font_names = PackedStringArray(["Old English Text MT", "UnifrakturMaguntia", "Noto Serif SC", "serif"])
	_build()
	_init_rain()
	_init_audio()


func _exit_tree() -> void:
	var i := AudioServer.get_bus_index(_bus)
	if i >= 0:
		AudioServer.remove_bus(i)


func _render_size() -> Vector2i:
	var k := get_tree().root.get_final_transform().x.length()
	var s := get_viewport_rect().size * k
	return Vector2i(maxi(2, int(s.x)), maxi(2, int(s.y)))


func _mk_vp(sz: Vector2i, content := Vector2i.ZERO) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = sz
	if content != Vector2i.ZERO:
		vp.size_2d_override = content
		vp.size_2d_override_stretch = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	vp.handle_input_locally = false
	vp.gui_disable_input = true
	add_child(vp)
	return vp


func _mk_rect(vp: SubViewport, sh: Shader, sz: Vector2) -> ShaderMaterial:
	var r := ColorRect.new()
	r.size = sz
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = sh
	r.material = m
	vp.add_child(r)
	return m


func _build() -> void:
	var rs := _render_size()
	var di := Vector2i(1920, 1080)
	var noise: Texture2D = load(DIR_IMG + "gc_noise.png")
	_vp_scene = _mk_vp(rs, di)
	_m_scene = _mk_rect(_vp_scene, SH_SCENE, DESIGN)
	_m_scene.set_shader_parameter("uCity", load(DIR_IMG + "gc_city.png"))
	_m_scene.set_shader_parameter("uWin", load(DIR_IMG + "gc_win.png"))
	_m_scene.set_shader_parameter("uLogo", load(DIR_IMG + "gc_logo.png"))
	_m_scene.set_shader_parameter("uLogoN", load(DIR_IMG + "gc_logo_n.png"))
	_m_scene.set_shader_parameter("uNoise", noise)
	_m_scene.set_shader_parameter("uCut0", CUT0)
	_m_scene.set_shader_parameter("uD", D)
	_m_scene.set_shader_parameter("uN", N)
	_m_scene.set_shader_parameter("uLampX", _lamp_x())

	_vp_a = _mk_vp(Vector2i(480, 270))
	_m_a = _mk_rect(_vp_a, SH_BLUR, Vector2(480, 270))
	_m_a.set_shader_parameter("uSrc", _vp_scene.get_texture())
	_m_a.set_shader_parameter("uTexel", Vector2(1.5 / 480.0, 1.5 / 270.0))
	_m_a.set_shader_parameter("uThr", 0.72)
	_vp_b = _mk_vp(Vector2i(160, 90))
	_m_b = _mk_rect(_vp_b, SH_BLUR, Vector2(160, 90))
	_m_b.set_shader_parameter("uSrc", _vp_a.get_texture())
	_m_b.set_shader_parameter("uTexel", Vector2(2.2 / 160.0, 2.2 / 90.0))
	_m_b.set_shader_parameter("uThr", 0.0)

	_vp_final = _mk_vp(rs, di)
	_m_final = _mk_rect(_vp_final, SH_FINAL, DESIGN)
	_m_final.set_shader_parameter("uScene", _vp_scene.get_texture())
	_m_final.set_shader_parameter("uBloomA", _vp_a.get_texture())
	_m_final.set_shader_parameter("uBloomB", _vp_b.get_texture())
	_m_final.set_shader_parameter("uNoise", noise)
	_m_final.set_shader_parameter("uFore", load(DIR_IMG + "gc_fore.png"))
	_m_final.set_shader_parameter("uLampX", _lamp_x())

	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_2D
	_mm.use_custom_data = true
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	_mm.mesh = q
	_mm.instance_count = N_STREAK + N_DROP
	var inst := MultiMeshInstance2D.new()
	inst.multimesh = _mm
	_m_rain = ShaderMaterial.new()
	_m_rain.shader = SH_RAIN
	_m_rain.set_shader_parameter("uCut0", CUT0)
	_m_rain.set_shader_parameter("uN", N)
	_m_rain.set_shader_parameter("uLampX", _lamp_x())
	inst.material = _m_rain
	_vp_final.add_child(inst)

	_display = TextureRect.new()
	_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_display.set_anchors_preset(Control.PRESET_FULL_RECT)
	_display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_display.stretch_mode = TextureRect.STRETCH_SCALE
	_display.texture = _vp_final.get_texture()
	add_child(_display)

	_ui = Control.new()
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.draw.connect(_draw_ui)
	add_child(_ui)


func _lamp_x() -> Vector4:
	return Vector4(LAMP_X[0], LAMP_X[1], LAMP_X[2], LAMP_X[3])


# ---------------------------------------------------------------- 雨
func _spawn_streak(s: Dictionary, anywhere: bool) -> void:
	var r := _rng.randf()
	var depth := 0 if r < .62 else (1 if r < .93 else 2)
	s["depth"] = depth
	s["x"] = _rng.randf_range(-60.0, DESIGN.x + 60.0)
	s["y"] = _rng.randf_range(-260.0, DESIGN.y) if anywhere else _rng.randf_range(-320.0, -40.0)
	s["k"] = _rng.randf_range(.55, 1.0)
	match depth:
		0:
			s["sp"] = _rng.randf_range(820.0, 1020.0)
			s["len"] = 30.0
			s["w"] = 1.3
			s["a"] = .15
			s["end"] = WL - 2.0
		1:
			s["sp"] = _rng.randf_range(1350.0, 1700.0)
			s["len"] = 78.0
			s["w"] = 1.7
			s["a"] = .23
			s["end"] = _rng.randf_range(WL + 10.0, WL + 120.0)
		_:
			s["sp"] = _rng.randf_range(2300.0, 2800.0)
			s["len"] = 300.0
			s["w"] = 3.5
			s["a"] = .05
			s["end"] = DESIGN.y + 320.0


func _init_rain() -> void:
	_streak.resize(N_STREAK)
	for i in N_STREAK:
		var s := {}
		_spawn_streak(s, true)
		_streak[i] = s
	_drop.resize(N_DROP)
	for i in N_DROP:
		_drop[i] = {"on": false, "x": 0.0, "y": 0.0, "r": 0.0, "a": 0.0, "born": 0.0, "ph": _rng.randf() * TAU}


func _sd(x: float, y: float) -> float:
	return (x - CUT0.x) * N.x + (y - CUT0.y) * N.y


func _ud(x: float, y: float) -> float:
	return (x - CUT0.x) * D.x + (y - CUT0.y) * D.y


func _add_drop(x: float, y: float, born: float) -> void:
	if y > WL - 6.0:
		return
	var d: Dictionary = _drop[_drop_next % N_DROP]
	_drop_next += 1
	d["on"] = true
	d["x"] = x
	d["y"] = y
	var big := absf(_rng.randfn(0.0, 1.0))
	d["r"] = 1.0 + big * 1.5
	d["a"] = exp(-absf(_sd(x, y)) / 90.0) * .75 + .25
	d["born"] = born


func _seed_drops_at_hit() -> void:
	# 刀过之处的雨全部停住：刀尖经过的时刻，水珠才出现
	for i in 300:
		var u := _rng.randf_range(-1050.0, 1050.0)
		var lap := _rng.randf_range(0.001, 1.0)
		var s := -log(lap) * 30.0 * (1.0 if _rng.randf() < .5 else -1.0)
		var p := CUT0 + D * u + N * s
		if p.x < 0.0 or p.x > DESIGN.x or p.y < 0.0:
			continue
		_add_drop(p.x, p.y, T_DRAW + (u + 1040.0) / 2080.0 * (T_HIT - T_DRAW))


func _step_rain(dt: float) -> void:
	for s in _streak:
		var sp: float = s["sp"]
		var dy := sp * _rain_speed * dt
		s["y"] += dy
		s["x"] -= dy * .10
		if float(s["y"]) - float(s["len"]) > float(s["end"]) or float(s["x"]) < -80.0:
			_spawn_streak(s, false)
			continue
		if _hit_done and int(s["depth"]) < 2 and absf(_sd(s["x"], s["y"])) < FREEZE_BAND * float(s["k"]):
			# 掉进光里的雨就停住，后面的雨接着下
			if _rng.randf() < .16:
				_add_drop(s["x"], s["y"], t)
			_spawn_streak(s, false)


func _write_rain() -> void:
	var ln := .10 + .90 * _rain_speed
	for i in N_STREAK:
		var s: Dictionary = _streak[i]
		var l: float = float(s["len"]) * ln * float(s["k"])
		var w: float = s["w"]
		var pos := Vector2(float(s["x"]) + l * .05, float(s["y"]) - l * .5)
		var a: float = float(s["a"]) * float(s["k"]) * ui_rain_alpha()
		var xf := Transform2D(0.0, Vector2(w, l), 0.0, pos)
		xf = xf.rotated_local(.0996)
		_mm.set_instance_transform_2d(i, xf)
		_mm.set_instance_custom_data(i, Color(a, 0.0, 0.0, 0.0))
	for i in N_DROP:
		var d: Dictionary = _drop[i]
		var age := t - float(d["born"])
		if not bool(d["on"]) or age < 0.0:
			_mm.set_instance_transform_2d(i + N_STREAK, Transform2D(0.0, Vector2.ZERO, 0.0, Vector2(-100, -100)))
			_mm.set_instance_custom_data(i + N_STREAK, Color(0, 0, 0, 0))
			continue
		var e := clampf(age / .16, 0.0, 1.0)
		var k := 1.0 - pow(1.0 - e, 3.0)
		var rr: float = float(d["r"]) * 2.0 * k
		var ph: float = d["ph"]
		var tr := Vector2(sin(t * 1.1 + ph), cos(t * .8 + ph * 1.7)) * .7
		_mm.set_instance_transform_2d(i + N_STREAK, Transform2D(0.0, Vector2(rr, rr * 1.2), 0.0, Vector2(d["x"], d["y"]) + tr))
		_mm.set_instance_custom_data(i + N_STREAK, Color(float(d["a"]) * .95, 1.0, 0.0, 0.0))


func ui_rain_alpha() -> float:
	return 1.0


# ---------------------------------------------------------------- 声音
func _init_audio() -> void:
	if AudioServer.get_bus_index(_bus) < 0:
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, _bus)
		AudioServer.set_bus_send(i, "Master")
		_lp = AudioEffectLowPassFilter.new()
		_lp.cutoff_hz = 20000.0
		AudioServer.add_bus_effect(i, _lp)
	_bed = _loop("res://assets/audio/yg_title/rain_bed.ogg")
	_near = _loop("res://assets/audio/yg_title/rain_near.ogg")
	_sfx = {
		"eye": ["res://assets/audio/ult/ult_eye.ogg", -8.0],
		"slash": ["res://assets/audio/ult/ult_cut_2.ogg", -3.0],
		"impact": ["res://assets/audio/ult/ult_impact.ogg", 0.0],
		"ring": ["res://assets/audio/ult/ult_eye.ogg", -17.0],
		"lamp": ["res://assets/audio/ult/ult_push.ogg", -20.0],
		"tick": ["res://assets/audio/yg_title/ui_move.ogg", -13.0],
		"ok": ["res://assets/audio/ult/ult_cut_3.ogg", -4.0],
	}


func _loop(path: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	var st: AudioStream = load(path)
	if st is AudioStreamOggVorbis:
		(st as AudioStreamOggVorbis).loop = true
	p.stream = st
	p.bus = _bus
	p.volume_db = -14.0
	add_child(p)
	p.play()
	return p


func _play(name: String) -> void:
	if not _sfx.has(name):
		return
	var p := AudioStreamPlayer.new()
	p.stream = load(str(_sfx[name][0]))
	p.volume_db = float(_sfx[name][1])
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


func _once(key: String, name: String, when: float) -> void:
	if t >= when and not _played.has(key):
		_played[key] = true
		_play(name)


func _audio_step(dt: float) -> void:
	# 雨声跟着雨速：慢下来时抽空，斩后闷着回来
	var target := 1.0
	var cutoff := 20000.0
	if t > T_SLOW and t < T_RESUME:
		target = 0.0
	elif t >= T_RESUME and _confirm_t < 0.0:
		target = clampf((t - T_RESUME) / 1.0, 0.0, 1.0)
		cutoff = lerpf(1400.0, 16000.0, clampf((t - T_RESUME) / 2.4, 0.0, 1.0))
	if _confirm_t >= 0.0:
		target = clampf(1.0 - _confirm_t / 1.4, 0.0, 1.0)
		cutoff = 600.0
	var g := -80.0 if target < .01 else linear_to_db(target) - 13.0
	var rate := 6.0 if target < .5 else 3.0
	_bed.volume_db = lerpf(_bed.volume_db, g, clampf(dt * rate, 0.0, 1.0))
	_near.volume_db = _bed.volume_db - 4.0
	if _lp != null:
		_lp.cutoff_hz = lerpf(_lp.cutoff_hz, cutoff, clampf(dt * 5.0, 0.0, 1.0))
	_once("eye", "eye", T_SLOW + .02)
	_once("slash", "slash", T_DRAW - .05)
	_once("impact", "impact", T_HIT - .03)
	_once("ring", "ring", T_HIT + .22)
	_once("lamp", "lamp", T_LAMPS)


# ---------------------------------------------------------------- 输入
func _input(ev: InputEvent) -> void:
	if _demo:
		return
	if ev is InputEventMouseMotion:
		var k := get_viewport_rect().size
		_mouse = ((ev as InputEventMouseMotion).position / k - Vector2(.5, .5)) * 2.0
		if ui_on and _confirm_t < 0.0:
			_hover((ev as InputEventMouseMotion).position)
		return
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		if not ui_on:
			_skip_intro()
		elif _confirm_t < 0.0:
			_hover((ev as InputEventMouseButton).position)
			_confirm()
		return
	if ev is InputEventKey and (ev as InputEventKey).pressed and not (ev as InputEventKey).echo:
		var c := (ev as InputEventKey).keycode
		if not ui_on:
			_skip_intro()
		elif c == KEY_LEFT or c == KEY_A or c == KEY_UP or c == KEY_W:
			_move(-1)
		elif c == KEY_RIGHT or c == KEY_D or c == KEY_DOWN or c == KEY_S:
			_move(1)
		elif c == KEY_ENTER or c == KEY_KP_ENTER or c == KEY_SPACE or c == KEY_J:
			_confirm()
		return
	if ev is InputEventJoypadButton and (ev as InputEventJoypadButton).pressed:
		var b := (ev as InputEventJoypadButton).button_index
		if not ui_on:
			_skip_intro()
		elif b == JOY_BUTTON_DPAD_LEFT or b == JOY_BUTTON_DPAD_UP:
			_move(-1)
		elif b == JOY_BUTTON_DPAD_RIGHT or b == JOY_BUTTON_DPAD_DOWN:
			_move(1)
		elif b == JOY_BUTTON_A:
			_confirm()


func _hover(pos: Vector2) -> void:
	var k := get_viewport_rect().size.x / DESIGN.x
	var p := pos / k
	if p.y < MENU_Y - 60.0 or p.y > MENU_Y + 60.0:
		return
	for i in MENU.size():
		if absf(p.x - float(LAMP_X[i])) < 150.0 and i != sel:
			_set_sel(i)
			return


func _skip_intro() -> void:
	if t < T_DRAW:
		t = T_DRAW
	elif t < T_LAMPS:
		t = T_LAMPS


func _move(d: int) -> void:
	if _confirm_t >= 0.0:
		return
	_set_sel(posmod(sel + d, MENU.size()))


func _set_sel(i: int) -> void:
	sel = i
	_lamp_flare[i] = 1.0
	_lamp_len[i] = 0.0
	_ring_t = -.22
	_ring_x = float(LAMP_X[i])
	_play("tick")


func _confirm() -> void:
	if _confirm_t >= 0.0:
		return
	if sel == 0:
		_confirm_t = 0.0
		_lamp_flare[0] = 1.6
		_play("ok")
	elif sel == 3:
		get_tree().quit()


# ---------------------------------------------------------------- 每帧
static func _ease_out(x: float, p := 3.0) -> float:
	var c := clampf(x, 0.0, 1.0)
	return 1.0 - pow(1.0 - c, p)


static func _ss(a: float, b: float, x: float) -> float:
	var c := clampf((x - a) / (b - a), 0.0, 1.0)
	return c * c * (3.0 - 2.0 * c)


func _process(dt: float) -> void:
	t += dt
	if _demo:
		_demo_step()
	_step(dt)


func _demo_step() -> void:
	while _demo_i < DEMO.size() and t >= float(DEMO[_demo_i][0]):
		var a: String = DEMO[_demo_i][1]
		match a:
			"right":
				_move(1)
			"left2":
				_set_sel(0)
			"ok":
				_confirm()
		_demo_i += 1
	if t >= 10.0:
		get_tree().quit()


func _step(dt: float) -> void:
	# 雨速
	if t < T_SLOW:
		_rain_speed = 1.0
	elif t < T_HIT:
		_rain_speed = lerpf(1.0, .16, _ss(T_SLOW, T_DRAW, t))
	elif t < T_RESUME:
		_rain_speed = 0.0
	else:
		_rain_speed = _ss(T_RESUME, T_RESUME + .7, t)
	if not _hit_done and t >= T_HIT:
		_hit_done = true
		_seed_drops_at_hit()
	if t >= T_DRAW and _drop_next == 0:
		_seed_drops_at_hit()
	_step_rain(dt)
	_write_rain()

	# 刀
	var tip := -5000.0
	var blade := 0.0
	if t >= T_DRAW:
		var k := clampf((t - T_DRAW) / (T_HIT - T_DRAW), 0.0, 1.0)
		tip = lerpf(-1060.0, 1100.0, k * k) if k < 1.0 else 5000.0
		blade = 1.0 if t < T_HIT else clampf(1.0 - (t - T_HIT) / .12, 0.0, 1.0)
	var pre := _ss(T_SLOW + .05, T_DRAW - .02, t) * (1.0 if t < T_DRAW else 0.0)
	var since := t - T_HIT
	var light := 0.0
	var over := 0.0
	var front := 0.0
	var slide := 0.0
	var crack := 0.0
	if since >= 0.0:
		light = lerpf(1.35, 1.0, _ease_out(since / .8))
		over = exp(-since / .13) * 1.0
		front = _ease_out(since / .34, 2.6) * 1300.0
		# 错开：一拍之后才滑动（居合：动作和结果隔一拍），冲出去再略收
		var sl := clampf((since - .10) / .7, 0.0, 1.0)
		slide = _ease_out(sl, 4.0) * 13.0
		crack = _ease_out((since - .06) / .75, 2.2) * 760.0
	var breathe := 1.0 + sin(t * .7) * .035 + sin(t * 2.3) * .012
	if since > .8:
		light *= breathe

	# 扫光：落定后每 6.5 秒一次
	var sweep_u := -5000.0
	var sweep_a := 0.0
	if t > 3.3:
		var ph := fmod(t - 3.3, 6.5)
		if ph < 1.8:
			sweep_u = lerpf(-900.0, 1000.0, ph / 1.8)
			sweep_a = sin(ph / 1.8 * PI)

	# 确认
	var open := 0.0
	var flood := 0.0
	var fade := 0.0
	if _confirm_t >= 0.0:
		_confirm_t += dt
		var c := _confirm_t
		open = pow(clampf(c / 1.05, 0.0, 1.0), 2.4) * 620.0
		flood = _ss(.72, 1.25, c)
		fade = _ss(1.32, 1.9, c)
		if c >= 2.0 and not _demo:
			get_tree().change_scene_to_file(GAME_SCENE)
			set_process(false)

	# 灯
	if t >= T_LAMPS and not ui_on:
		ui_on = true
	for i in MENU.size():
		var on_t := T_LAMPS + i * .15
		var want := 0.0
		if t >= on_t:
			want = 1.0 if i == sel else .22
			if not _played.has("lit%d" % i):
				_played["lit%d" % i] = true
				_lamp_flare[i] = 1.0 if i == sel else .5
		var rate := 14.0 if want > float(_lamp[i]) else 6.5
		_lamp[i] = lerpf(_lamp[i], want, clampf(dt * rate, 0.0, 1.0))
		_lamp_flare[i] = maxf(0.0, float(_lamp_flare[i]) - dt * 3.4)
		if t >= on_t:
			_lamp_len[i] = minf(LAMP_REACH + 40.0, float(_lamp_len[i]) + dt * 1100.0)
			if t >= on_t + .13:
				_word[i] = minf(1.0, float(_word[i]) + dt * 3.0)
		# 字的大小：弹簧
		var target := 1.0 if i == sel else 0.0
		var acc := (target - float(_word_sel[i])) * 340.0 - float(_word_vel[i]) * 30.0
		_word_vel[i] = float(_word_vel[i]) + acc * dt
		_word_sel[i] = float(_word_sel[i]) + float(_word_vel[i]) * dt
	if _ring_t > -1.0:
		_ring_t += dt / 1.1
		if _ring_t >= 1.0:
			_ring_t = -2.0

	# 镜头：开场极慢地后退；鼠标给一点视差
	var zoom := lerpf(1.035, 1.0, _ease_out(t / 3.2, 2.0))
	if since >= 0.0 and since < .3:
		zoom += exp(-since / .07) * .006
	var want_cam := -_mouse * Vector2(16.0, 9.0) + Vector2(sin(t * .17) * 3.0, sin(t * .13) * 1.6)
	_cam = _cam.lerp(want_cam, clampf(dt * 3.0, 0.0, 1.0))
	var lamp_v := Vector4(_lk(0), _lk(1), _lk(2), _lk(3))
	var ls := _m_scene
	ls.set_shader_parameter("uT", t)
	ls.set_shader_parameter("uCam", _cam)
	ls.set_shader_parameter("uZoom", zoom)
	ls.set_shader_parameter("uTip", tip)
	ls.set_shader_parameter("uBlade", blade)
	ls.set_shader_parameter("uLight", light)
	ls.set_shader_parameter("uFront", front)
	ls.set_shader_parameter("uOver", over)
	ls.set_shader_parameter("uSlide", slide)
	ls.set_shader_parameter("uOpen", open)
	ls.set_shader_parameter("uFlood", flood)
	ls.set_shader_parameter("uCrack", crack)
	ls.set_shader_parameter("uSweepU", sweep_u)
	ls.set_shader_parameter("uSweepA", sweep_a)
	ls.set_shader_parameter("uPrePoint", pre)
	ls.set_shader_parameter("uLamp", lamp_v)
	var f := _m_final
	f.set_shader_parameter("uT", t)
	f.set_shader_parameter("uCam", _cam)
	f.set_shader_parameter("uShock", since)
	f.set_shader_parameter("uBoost", exp(-maxf(since, 0.0) / .45) * (1.0 if since >= 0.0 else 0.0))
	f.set_shader_parameter("uLamp", lamp_v)
	f.set_shader_parameter("uLampLen", Vector4(_lamp_len[0], _lamp_len[1], _lamp_len[2], _lamp_len[3]))
	f.set_shader_parameter("uRingT", _ring_t if _ring_t >= 0.0 else -1.0)
	f.set_shader_parameter("uRingCx", _ring_x)
	f.set_shader_parameter("uBand", _ss(T_LAMPS, T_LAMPS + .5, t))
	f.set_shader_parameter("uFade", fade)
	_m_rain.set_shader_parameter("uLight", light)
	_m_rain.set_shader_parameter("uLamp", lamp_v)
	_audio_step(dt)
	_ui.queue_redraw()


func _lk(i: int) -> float:
	return float(_lamp[i]) + float(_lamp_flare[i]) * .85


# ---------------------------------------------------------------- 字
func _text_c(c: Control, s: String, font: Font, fs: int, col: Color, cx: float, cy: float, tr: float) -> void:
	var w := 0.0
	for i in s.length():
		w += font.get_string_size(s.substr(i, 1), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + tr
	w -= tr
	var x := cx - w * .5
	for i in s.length():
		var ch := s.substr(i, 1)
		c.draw_string(font, Vector2(x, cy + fs * .36), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		x += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + tr


func _draw_ui() -> void:
	var k := get_viewport_rect().size.x / DESIGN.x
	var c := _ui
	var a0 := 1.0
	if _confirm_t >= 0.0:
		a0 = clampf(1.0 - _confirm_t / .4, 0.0, 1.0)
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2(k, k))
	for i in MENU.size():
		var e: float = _word[i]
		if e <= .001:
			continue
		var pop := _ease_out(e, 3.0)
		var ws: float = _word_sel[i]
		var fs := int(round(lerpf(30.0, 50.0, ws)))
		var col := Color(.69, .72, .81).lerp(Color(.965, .91, .815), clampf(ws, 0.0, 1.0))
		col.a = pop * a0
		var y := MENU_Y + (1.0 - pop) * 16.0
		_text_c(c, MENU[i], _font, fs, col, LAMP_X[i], y, lerpf(9.0, 12.0, ws))
	var la := _ss(T_LUX, T_LUX + .7, t) * a0
	if la > .001:
		_text_c(c, "Lux Scissa", _black, 44, Color(.78, .81, .90, la), 1640.0, 700.0 + (1.0 - la) * 7.0, 2.0)
		var hint_col := Color(.62, .65, .74, la)
		_text_c(c, "← →  选择      Enter  确认", _font, 20, hint_col, 1660.0, 1046.0, 1.0)
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
