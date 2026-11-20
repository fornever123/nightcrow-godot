extends Control
## 首页（标题画面）的动态层 ——「光弦断幕」。
## 全部用代码画，没有一张图片：昼光丝弦（Verlet 绳）、冻在光里的雨、黑羽、刀光，
## 外加一层后期（辉光 / 色散 / 冷色分离 / 颗粒 / 暗角 / 闪白）。
## 由 scripts/ui/title_screen.gd 驱动；整条动画只跟 clock 走，所以能用 seek() 定格截图。
## 设计说明见 docs/项目进程.md §3.8。

signal slashed        ## 刀光扫过画面中线（字标在这时被斩开）
signal slash_done     ## 刀光出画

# ------------------------------------------------------------------ 时间轴（秒）
const T_STRINGS := 0.30    ## 丝弦开始从上方长下来
const T_MARK := 2.25       ## 字标开始被光写出来
const T_SLASH := 3.50      ## 第一刀：斩断丝弦 + 斩开字标
const T_MENU := 4.35       ## 菜单浮入
const T_READY := 5.55      ## 进场结束，可以操作

const CUT_Y := 306.0           ## 刀线高度
const SLASH_SEC := 0.26        ## 刀光横过全屏的时间
const LIGHT_RADIUS := 190.0    ## 光标光团半径（光里的雨停住）

# ------------------------------------------------------------------ 色板（全项目一致）
const WARM := Color("fff2d2")
const WARM_MID := Color("ffd79a")
const SILVER := Color("dfe6f2")
const COLD := Color("9fb4d8")
const VIOLET := Color("9a6cff")
const VIOLET_HOT := Color("c8b0ff")

const STRAND_COUNT := 26
const DROP_COUNT := 540
const MOTE_COUNT := 110
const REFLECT_Y := 626.0


class Strand:
	var anchor := Vector2.ZERO
	var nodes: Array[Vector2] = []
	var prevs: Array[Vector2] = []
	var seg := 18.0
	var lit := 0.6
	var warm := 0.6
	var thick := 1.0
	var start := 0.0
	var phase := 0.0
	var beads: Array[float] = []
	var cut_at := -1
	var cut_t := 0.0
	var up: Array[Vector2] = []
	var up_prev: Array[Vector2] = []
	var low: Array[Vector2] = []
	var low_prev: Array[Vector2] = []
	var low_alpha := 1.0
	var up_seg := 18.0
	var recoil := 0.0
	var gone := false


class Feather:
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var rot := 0.0
	var spin := 0.0
	var size := 20.0
	var life := 1.0
	var max_life := 1.0
	var phase := 0.0
	var variant := 0
	var depth := 1.0


class Drop:
	var pos := Vector2.ZERO
	var fall := 200.0
	var length := 14.0
	var alpha := 0.2
	var frozen := 0.0
	var warm := 0.0
	var skew := -0.18


class Mote:
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var size := 1.0
	var alpha := 0.2


var clock := 0.0
var cut_done := false

var _strands: Array[Strand] = []
var _feathers: Array[Feather] = []
var _drops: Array[Drop] = []
var _motes: Array[Mote] = []
var _bokeh: Array = []
var _feather_tex: Array[ImageTexture] = []
var _soft_tex: ImageTexture

var _light := Vector2(760.0, 500.0)
var _light_energy := 0.0
var _mouse := Vector2.ZERO
var _mouse_idle := 99.0

var _slash_active := false
var _slash_x := -400.0
var _slash_fade := 0.0
var _slash_dir := 1.0
var _slash_signaled := false
var _intro_slashed := false

var _exit_at := -1.0
var _exit_fade := 0.0
var _flash := 0.0
var _shake := 0.0

var _rng := RandomNumberGenerator.new()

var _back: ColorRect
var _behind: Control
var _add: Control
var _front: Control
var _post: ColorRect
var _post_mat: ShaderMaterial
var mark: Control                       ## 字标（title_wordmark.gd）


func _ready() -> void:
	name = "Art"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.seed = 20261102
	_soft_tex = _make_soft_texture()
	_make_feather_textures()
	_build_layers()
	_seed_world()


func _build_layers() -> void:
	_back = ColorRect.new()
	_back.name = "Back"
	_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bm := ShaderMaterial.new()
	bm.shader = _back_shader()
	_back.material = bm
	add_child(_back)

	_behind = Control.new()
	_behind.name = "Behind"
	_behind.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_behind.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_behind.draw.connect(_draw_behind)
	add_child(_behind)

	_add = Control.new()
	_add.name = "Light"
	_add.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var cm := CanvasItemMaterial.new()
	cm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_add.material = cm
	_add.draw.connect(_draw_light)
	add_child(_add)

	_front = Control.new()
	_front.name = "Front"
	_front.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_front.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_front.draw.connect(_draw_front)
	add_child(_front)

	var Mark := preload("res://scripts/ui/title_wordmark.gd")
	mark = Mark.new()
	mark.name = "Wordmark"
	add_child(mark)

	_post = ColorRect.new()
	_post.name = "Post"
	_post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_post.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_post_mat = ShaderMaterial.new()
	_post_mat.shader = _post_shader()
	_post.material = _post_mat
	add_child(_post)


# ---------------------------------------------------------------- 贴图（一次生成）

func _make_soft_texture() -> ImageTexture:
	# 径向柔和光斑，辉光 / 散景 / 刀头都用它，比 draw_circle 干净得多
	var n := 96
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	var buf := PackedByteArray()
	buf.resize(n * n * 4)
	var c := (n - 1) * 0.5
	for y in n:
		for x in n:
			var r := Vector2(x - c, y - c).length() / c
			var a := clampf(1.0 - r, 0.0, 1.0)
			a = pow(a, 2.1)
			var i := (y * n + x) * 4
			buf[i] = 255
			buf[i + 1] = 255
			buf[i + 2] = 255
			buf[i + 3] = int(a * 255.0)
	img.set_data(n, n, false, Image.FORMAT_RGBA8, buf)
	return ImageTexture.create_from_image(img)


func _make_feather_textures() -> void:
	# 四张程序画的鸦羽：羽轴微弯、两侧羽片不对称、羽枝朝羽尖梳、根部绒羽、边缘冷紫蓝光泽
	var W := 72
	var H := 224
	for v in 4:
		var img := Image.create_empty(W, H, false, Image.FORMAT_RGBA8)
		var buf := PackedByteArray()
		buf.resize(W * H * 4)
		var skew := 0.06 + 0.03 * float(v)
		var asym := 0.86 + 0.10 * float(v % 2)
		var vane_gap := 0.0
		if v == 3:
			vane_gap = 0.07     # 一根开叉的
		for y in H:
			var t := float(y) / float(H - 1)
			# 沿羽轴：根部窄、靠 62% 最宽、羽尖收
			var prof := pow(sin(pow(clampf((t + 0.06) / 1.02, 0.0, 1.0), 0.78) * PI), 0.85)
			prof *= 1.0 - 0.18 * t
			var half := (W * 0.46) * prof
			var axis := W * 0.5 + sin(t * 2.4) * W * skew
			for x in W:
				var du := float(x) - axis
				var dist := absf(du)
				var a := 0.0
				if dist <= half:
					# 羽片：中间实、边缘毛
					var edge := clampf((half - dist) / maxf(1.0, half * 0.30), 0.0, 1.0)
					a = 0.55 + 0.45 * edge
					# 羽枝：斜着朝羽尖梳开
					var barb := sin((t * 74.0 + dist * 0.55 + float(v) * 9.0) * 1.7)
					a *= 0.70 + 0.30 * (0.5 + 0.5 * barb)
					if vane_gap > 0.0 and t > 0.55 and t < 0.55 + vane_gap:
						a *= 0.05
					if du < 0.0:
						a *= asym
				# 羽轴
				var spine := clampf(1.0 - dist / maxf(1.2, W * 0.022), 0.0, 1.0)
				a = maxf(a, spine * 0.95)
				var i := (y * W + x) * 4
				var shade := 1.0 - dist / maxf(1.0, half + 0.001)
				# 中间墨黑，边缘偏冷紫
				var r := lerpf(0.075, 0.30, clampf(shade, 0.0, 1.0))
				var g := lerpf(0.078, 0.24, clampf(shade, 0.0, 1.0))
				var b := lerpf(0.105, 0.46, clampf(shade, 0.0, 1.0))
				if spine > 0.45:
					r = 0.62
					g = 0.66
					b = 0.78
				buf[i] = int(clampf(r, 0.0, 1.0) * 255.0)
				buf[i + 1] = int(clampf(g, 0.0, 1.0) * 255.0)
				buf[i + 2] = int(clampf(b, 0.0, 1.0) * 255.0)
				buf[i + 3] = int(clampf(a, 0.0, 1.0) * 255.0)
		img.set_data(W, H, false, Image.FORMAT_RGBA8, buf)
		_feather_tex.append(ImageTexture.create_from_image(img))


# ---------------------------------------------------------------- 世界

func _seed_world() -> void:
	var vp := _size()
	for i in STRAND_COUNT:
		var s := Strand.new()
		var t := float(i) / float(STRAND_COUNT - 1)
		var x := -70.0 + t * 1420.0 + _rng.randf_range(-15.0, 15.0)
		s.anchor = Vector2(x, -34.0 - _rng.randf_range(0.0, 46.0))
		s.seg = _rng.randf_range(13.5, 20.5)
		s.lit = clampf(0.24 + 1.10 * exp(-pow((t - 0.52) * 1.9, 2.0)) + _rng.randf_range(-0.10, 0.15), 0.12, 1.0)
		s.warm = clampf(0.28 + 0.58 * _rng.randf(), 0.0, 1.0)
		s.thick = _rng.randf_range(0.8, 1.7)
		s.start = T_STRINGS + t * 0.62 + _rng.randf_range(0.0, 0.10)
		s.phase = _rng.randf_range(0.0, TAU)
		var length := _rng.randf_range(250.0, 500.0) * (0.70 + 0.58 * exp(-pow((t - 0.5) * 1.7, 2.0)))
		var n := maxi(6, int(length / s.seg))
		for j in n:
			var p := s.anchor + Vector2(0.0, s.seg * j)
			s.nodes.append(p)
			s.prevs.append(p)
		for k in _rng.randi_range(1, 3):
			s.beads.append(_rng.randf_range(0.22, 0.98))
		_strands.append(s)

	for i in DROP_COUNT:
		var d := Drop.new()
		d.pos = Vector2(_rng.randf_range(-40.0, vp.x + 40.0), _rng.randf_range(-vp.y, vp.y))
		d.fall = _rng.randf_range(150.0, 420.0)
		d.length = _rng.randf_range(7.0, 26.0) * (0.6 + d.fall / 420.0)
		d.alpha = _rng.randf_range(0.05, 0.24)
		d.skew = -0.16 - _rng.randf_range(0.0, 0.10)
		d.warm = _nearest_strand_warmth(d.pos.x)
		_drops.append(d)

	for i in MOTE_COUNT:
		var m := Mote.new()
		m.pos = Vector2(_rng.randf_range(0.0, vp.x), _rng.randf_range(60.0, vp.y))
		m.vel = Vector2(_rng.randf_range(-7.0, 7.0), _rng.randf_range(-16.0, -4.0))
		m.size = _rng.randf_range(0.5, 1.7)
		m.alpha = _rng.randf_range(0.05, 0.28)
		_motes.append(m)

	for i in 13:
		_bokeh.append({
			"pos": Vector2(_rng.randf_range(0.0, vp.x), _rng.randf_range(-20.0, vp.y * 0.92)),
			"r": _rng.randf_range(26.0, 92.0),
			"a": _rng.randf_range(0.010, 0.034),
			"ph": _rng.randf_range(0.0, TAU),
		})


func _size() -> Vector2:
	var r := get_viewport_rect().size
	return Vector2(maxf(r.x, 320.0), maxf(r.y, 240.0))


func _nearest_strand_warmth(x: float) -> float:
	var best := 9999.0
	var warm := 0.0
	for s in _strands:
		var d := absf(s.anchor.x - x)
		if d < best:
			best = d
			warm = s.warm
	return warm if best < 70.0 else 0.0


# ---------------------------------------------------------------- 对外

func skip_intro() -> void:
	if clock >= T_READY:
		return
	_settle(T_READY + 0.10)


func seek(t: float) -> void:
	clock = 0.0
	cut_done = false
	_slash_signaled = false
	_slash_active = false
	_slash_fade = 0.0
	_intro_slashed = false
	_exit_at = -1.0
	_exit_fade = 0.0
	_feathers.clear()
	for s in _strands:
		s.cut_at = -1
		s.gone = false
		s.up.clear()
		s.low.clear()
		var n := s.nodes.size()
		for i in n:
			s.nodes[i] = s.anchor + Vector2(0.0, s.seg * i)
			s.prevs[i] = s.nodes[i]
	_settle(t)


func _settle(target: float) -> void:
	var guard := 0
	while clock < target - 0.0001 and guard < 1200:
		_advance(0.0333)
		guard += 1
	_push_post()


func exit_slash() -> void:
	if _exit_at >= 0.0:
		return
	_exit_at = clock
	_slash_dir = -1.0
	_slash_active = true
	_slash_x = _size().x + 160.0
	_slash_fade = 0.0
	_flash = 0.85
	_shake = 1.3
	for s in _strands:
		if s.cut_at < 0:
			s.start = minf(s.start, clock - 1.0)
			_cut(s)


func exit_fade() -> float:
	if _exit_at < 0.0:
		return 0.0
	return clampf((clock - _exit_at - 0.32) / 1.05, 0.0, 1.0)


func set_light(pos: Vector2) -> void:
	_mouse = pos
	_mouse_idle = 0.0


# ---------------------------------------------------------------- 每帧

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_mouse_idle += delta
	_advance(minf(delta, 0.05))
	_behind.queue_redraw()
	_add.queue_redraw()
	_front.queue_redraw()


func _advance(dt: float) -> void:
	clock += dt
	if not _intro_slashed and clock >= T_SLASH:
		_intro_slashed = true
		_slash_dir = 1.0
		_slash_active = true
		_slash_x = -180.0
		_flash = 0.55
		_shake = 0.95
	_step_light(dt)
	_step_strands(dt)
	_step_beads(dt)
	_step_drops(dt)
	_step_motes(dt)
	_step_feathers(dt)
	_step_slash(dt)
	_flash = maxf(0.0, _flash - dt * 3.4)
	_shake = maxf(0.0, _shake - dt * 3.6)
	if _exit_at >= 0.0:
		_exit_fade = exit_fade()
	_push_post()


func _step_light(dt: float) -> void:
	var vp := _size()
	var target := _mouse
	if _mouse_idle > 3.0 or _mouse == Vector2.ZERO:
		var t := clock * 0.21
		target = Vector2(vp.x * (0.5 + 0.30 * sin(t * 1.13)), vp.y * (0.46 + 0.16 * sin(t * 0.77 + 1.7)))
	_light = _light.lerp(target, clampf(dt * 2.6, 0.0, 1.0))
	var appear := clampf((clock - T_SLASH - 0.55) / 1.8, 0.0, 1.0)
	_light_energy = appear * (0.85 + 0.15 * sin(clock * 1.7))


func _step_strands(dt: float) -> void:
	for s in _strands:
		if clock < s.start or s.gone:
			continue
		if s.cut_at < 0:
			_step_rope(s.nodes, s.prevs, s.seg, dt, s.anchor, true, s.phase, 0.0)
			continue
		var k := clampf((clock - s.cut_t) / 0.55, 0.0, 1.0)
		s.up_seg = s.seg * lerpf(1.0, 0.52, _ease_out(k))
		s.recoil = maxf(0.0, s.recoil - dt * 2.2)
		_step_rope(s.up, s.up_prev, s.up_seg, dt, s.anchor, true, s.phase, -1500.0 * s.recoil)
		_step_rope_free(s.low, s.low_prev, s.seg, dt, s.phase)
		s.low_alpha = maxf(0.0, 1.0 - clampf((clock - s.cut_t - 0.30) / 1.30, 0.0, 1.0))
		if s.low_alpha <= 0.0:
			s.gone = true
		elif _rng.randf() < dt * 5.0 and s.low.size() > 1:
			var q: Vector2 = s.low[_rng.randi_range(0, s.low.size() - 1)]
			_spawn_feather(q, Vector2(_rng.randf_range(-18.0, 18.0), _rng.randf_range(-30.0, 10.0)), 0.5)


func _step_rope(nodes: Array[Vector2], prevs: Array[Vector2], seg: float, dt: float, anchor: Vector2,
		anchored: bool, phase: float, extra_up: float) -> void:
	var n := nodes.size()
	if n < 2:
		return
	if anchored:
		nodes[0] = anchor
		prevs[0] = anchor
	var start_i := 1 if anchored else 0
	for i in range(start_i, n):
		var p: Vector2 = nodes[i]
		var v: Vector2 = (p - prevs[i]) * 0.972
		prevs[i] = p
		var t := float(i) / float(maxi(1, n - 1))
		var sway := sin(clock * 1.15 + t * 2.4 + phase) * (7.0 + 20.0 * t)
		nodes[i] = p + v * (dt * 60.0) + Vector2(sway, 620.0 + extra_up) * dt * dt
	for _it in 3:
		for i in range(1, n):
			var a: Vector2 = nodes[i - 1]
			var b: Vector2 = nodes[i]
			var dv := b - a
			var dist := dv.length()
			if dist < 0.001:
				dv = Vector2(0.0, 1.0)
				dist = 1.0
			var off := dv * ((dist - seg) / dist) * 0.5
			if anchored and i == 1:
				nodes[i] = b - off * 2.0
			else:
				nodes[i - 1] = a + off
				nodes[i] = b - off


func _step_rope_free(nodes: Array[Vector2], prevs: Array[Vector2], seg: float, dt: float, phase: float) -> void:
	var n := nodes.size()
	if n < 2:
		return
	for i in n:
		var p: Vector2 = nodes[i]
		var v: Vector2 = (p - prevs[i]) * 0.985
		prevs[i] = p
		var t := float(i) / float(maxi(1, n - 1))
		var sway := sin(clock * 0.9 + t * 3.0 + phase) * 26.0
		nodes[i] = p + v * (dt * 60.0) + Vector2(sway, 900.0) * dt * dt
	for _it in 2:
		for i in range(1, n):
			var a: Vector2 = nodes[i - 1]
			var b: Vector2 = nodes[i]
			var dv := b - a
			var dist := dv.length()
			if dist < 0.001:
				continue
			var off := dv * ((dist - seg) / dist) * 0.5
			nodes[i - 1] = a + off
			nodes[i] = b - off


func _grown_nodes(s: Strand) -> int:
	if s.cut_at >= 0:
		return s.up.size()
	var grow := clampf((clock - s.start) / 0.95, 0.0, 1.0)
	return int(round(grow * float(s.nodes.size())))


func _step_beads(dt: float) -> void:
	for s in _strands:
		if s.cut_at >= 0 or clock < s.start:
			continue
		var grown := _grown_nodes(s)
		if grown < 3:
			continue
		for i in s.beads.size():
			var p: float = s.beads[i] + dt * (0.030 + 0.018 * fmod(float(i) * 0.37, 1.0))
			if p > 0.985:
				var tip: Vector2 = s.nodes[mini(grown - 1, s.nodes.size() - 1)]
				_spawn_feather(tip + Vector2(_rng.randf_range(-6.0, 6.0), 4.0),
						Vector2(_rng.randf_range(-14.0, 14.0), 6.0), 0.65)
				p = _rng.randf_range(0.10, 0.35)
			s.beads[i] = p


func _step_drops(dt: float) -> void:
	var vp := _size()
	for d in _drops:
		var dist := d.pos.distance_to(_light)
		var want := clampf(1.0 - dist / LIGHT_RADIUS, 0.0, 1.0)
		want = pow(want, 1.5) * _light_energy
		d.frozen = move_toward(d.frozen, want, dt * (3.4 if want > d.frozen else 0.9))
		d.pos += Vector2(d.skew * d.fall, d.fall) * dt * (1.0 - d.frozen)
		if d.pos.y > vp.y + 26.0:
			d.pos = Vector2(_rng.randf_range(-40.0, vp.x + 40.0), _rng.randf_range(-90.0, -12.0))
			d.warm = _nearest_strand_warmth(d.pos.x)
			d.frozen = 0.0


func _step_motes(dt: float) -> void:
	var vp := _size()
	for m in _motes:
		m.pos += m.vel * dt
		m.pos.x += sin(clock * 0.7 + m.pos.y * 0.01) * 4.0 * dt
		if m.pos.y < -10.0:
			m.pos = Vector2(_rng.randf_range(0.0, vp.x), vp.y + 8.0)
		if m.pos.x < -10.0:
			m.pos.x = vp.x + 8.0
		elif m.pos.x > vp.x + 10.0:
			m.pos.x = -8.0


func _step_feathers(dt: float) -> void:
	var i := _feathers.size() - 1
	while i >= 0:
		var f := _feathers[i]
		f.life -= dt
		if f.life <= 0.0 or f.pos.y > _size().y + 60.0:
			_feathers.remove_at(i)
			i -= 1
			continue
		f.vel.y += 26.0 * dt
		f.vel.x += sin(clock * 1.9 + f.phase) * 26.0 * dt
		f.vel *= 1.0 - 0.55 * dt
		f.pos += f.vel * dt
		f.rot += f.spin * dt
		i -= 1


func _step_slash(dt: float) -> void:
	if _slash_active:
		_slash_x += _slash_dir * (_size().x + 320.0) / SLASH_SEC * dt
		for s in _strands:
			if s.cut_at >= 0 or s.gone:
				continue
			var passed := (_slash_x > s.anchor.x) if _slash_dir > 0.0 else (_slash_x < s.anchor.x)
			if passed:
				s.start = minf(s.start, clock - 1.0)
				_cut(s)
		if not _slash_signaled and _slash_dir > 0.0 and _slash_x > _size().x * 0.5:
			_slash_signaled = true
			slashed.emit()
		var out := (_slash_x > _size().x + 200.0) if _slash_dir > 0.0 else (_slash_x < -200.0)
		if out:
			_slash_active = false
			_slash_fade = 1.0
			slash_done.emit()
	_slash_fade = maxf(0.0, _slash_fade - dt * 2.2)


func _cut(s: Strand) -> void:
	if s.cut_at >= 0:
		return
	var n := s.nodes.size()
	if n < 6:
		s.cut_at = 0
		return
	var best_i := 0
	var best := 1.0e9
	for i in n:
		var d := absf(s.nodes[i].y - CUT_Y)
		if d < best:
			best = d
			best_i = i
	var ci := clampi(best_i, 2, n - 3)
	s.cut_at = ci
	s.cut_t = clock
	s.up.clear()
	s.up_prev.clear()
	s.low.clear()
	s.low_prev.clear()
	for i in range(0, ci + 1):
		s.up.append(s.nodes[i])
		s.up_prev.append(s.prevs[i])
	for i in range(ci, n):
		s.low.append(s.nodes[i])
		s.low_prev.append(s.prevs[i])
	s.recoil = 1.0
	s.beads.clear()
	cut_done = true
	var cut_pos: Vector2 = s.nodes[ci]
	_spawn_feather(cut_pos, Vector2(_rng.randf_range(-40.0, 40.0), _rng.randf_range(-60.0, -10.0)), 0.85)
	_spawn_feather(cut_pos, Vector2(_rng.randf_range(-30.0, 30.0), _rng.randf_range(-20.0, 20.0)), 0.7)


func _spawn_feather(pos: Vector2, vel: Vector2, size_k: float) -> void:
	if _feathers.size() > 150:
		return
	var f := Feather.new()
	f.pos = pos
	f.vel = vel
	f.rot = _rng.randf_range(0.0, TAU)
	f.spin = _rng.randf_range(-2.4, 2.4)
	f.size = _rng.randf_range(16.0, 32.0) * size_k
	f.max_life = _rng.randf_range(5.0, 9.0)
	f.life = f.max_life
	f.phase = _rng.randf_range(0.0, TAU)
	f.variant = _rng.randi_range(0, _feather_tex.size() - 1)
	f.depth = _rng.randf_range(0.55, 1.0)
	_feathers.append(f)


func _push_post() -> void:
	if _post_mat == null:
		return
	_post_mat.set_shader_parameter("flash", _flash)
	_post_mat.set_shader_parameter("aberr", 0.0022 + 0.030 * _flash)
	_post_mat.set_shader_parameter("time_s", clock)
	_post_mat.set_shader_parameter("fade_out", _exit_fade)


func _shake_offset() -> Vector2:
	if _shake <= 0.0:
		return Vector2.ZERO
	var a := _shake * _shake * 7.0
	return Vector2(_rng.randf_range(-a, a), _rng.randf_range(-a, a) * 0.8)


func _ease_out(t: float) -> float:
	var k := clampf(t, 0.0, 1.0)
	return 1.0 - pow(1.0 - k, 3.0)


func _blob(center: Vector2, radius: float, color: Color) -> void:
	_add.draw_texture_rect(_soft_tex, Rect2(center - Vector2(radius, radius), Vector2(radius, radius) * 2.0),
			false, color)


# ---------------------------------------------------------------- 背景层

func _draw_behind() -> void:
	var vp := _size()
	_behind.draw_set_transform(_shake_offset() * 0.35)
	for b in _bokeh:
		var p: Vector2 = b["pos"] + Vector2(sin(clock * 0.21 + b["ph"]) * 12.0, cos(clock * 0.17 + b["ph"]) * 8.0)
		var r: float = b["r"]
		var a: float = b["a"]
		_behind.draw_texture_rect(_soft_tex, Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0), false,
				Color(0.52, 0.60, 0.86, a))
		_behind.draw_texture_rect(_soft_tex, Rect2(p - Vector2(r, r) * 0.5, Vector2(r, r)), false,
				Color(0.72, 0.78, 0.98, a * 0.7))
	# 顶部往下泄的一点冷雾
	var g := PackedVector2Array([Vector2(0, 0), Vector2(vp.x, 0), Vector2(vp.x, vp.y * 0.40), Vector2(0, vp.y * 0.40)])
	var gc := PackedColorArray([Color(0.10, 0.12, 0.20, 0.15), Color(0.10, 0.12, 0.20, 0.15),
			Color(0.07, 0.09, 0.15, 0.0), Color(0.07, 0.09, 0.15, 0.0)])
	_behind.draw_polygon(g, gc)
	_behind.draw_set_transform(Vector2.ZERO)


# ---------------------------------------------------------------- 光层（叠加）

func _draw_light() -> void:
	_add.draw_set_transform(_shake_offset())
	_draw_shafts()
	for s in _strands:
		if clock < s.start:
			continue
		if s.cut_at < 0:
			var count := _grown_nodes(s)
			if count >= 2:
				_stroke(s.nodes, count, s.warm, s.lit, s.thick, 1.0, s.phase)
				_draw_bottom_glow(s.nodes[count - 1], s.lit * 0.55)
				_draw_mirror(s.nodes, count, s.warm, s.lit, s.thick)
		else:
			if s.up.size() >= 2:
				var k := clampf((clock - s.cut_t) / 0.6, 0.0, 1.0)
				_stroke(s.up, s.up.size(), s.warm, s.lit * (1.0 - 0.30 * k), s.thick * (1.0 - 0.25 * k), 1.0, s.phase)
			if s.low.size() >= 2 and s.low_alpha > 0.0:
				_stroke(s.low, s.low.size(), s.warm, s.lit * 0.9, s.thick * 0.9, s.low_alpha, s.phase)
				_draw_mirror(s.low, s.low.size(), s.warm, s.lit * 0.9 * s.low_alpha, s.thick * 0.9)
	_draw_beads()
	_draw_rain()
	for m in _motes:
		_add.draw_circle(m.pos, m.size, Color(SILVER, m.alpha))
	_draw_slash()
	_add.draw_set_transform(Vector2.ZERO)


func _draw_shafts() -> void:
	var vp := _size()
	var cols := [Color(WARM_MID, 0.030), Color(COLD, 0.026), Color(WARM, 0.018)]
	for i in 3:
		var x := vp.x * (0.24 + 0.27 * i) + sin(clock * 0.11 + i * 2.1) * 16.0
		var wide := 150.0 + 90.0 * i
		var p := PackedVector2Array([Vector2(x - 26.0, -20.0), Vector2(x + 26.0, -20.0),
				Vector2(x + wide, vp.y * 0.86), Vector2(x - wide, vp.y * 0.86)])
		var c: Color = cols[i]
		var pc := PackedColorArray([Color(c.r, c.g, c.b, c.a), Color(c.r, c.g, c.b, c.a),
				Color(c.r, c.g, c.b, 0.0), Color(c.r, c.g, c.b, 0.0)])
		_add.draw_polygon(p, pc)


func _stroke(nodes: Array[Vector2], count: int, warm: float, lit: float, thick: float, alpha: float, wig: float) -> void:
	if count < 2:
		return
	var pts := PackedVector2Array()
	var core := PackedColorArray()
	var mid := PackedColorArray()
	var soft := PackedColorArray()
	var base := WARM.lerp(SILVER, 1.0 - warm)
	for i in count:
		pts.append(nodes[i])
		var t := float(i) / float(count - 1)
		var shimmer := 0.70 + 0.30 * sin(clock * 2.2 + t * 8.0 + wig)
		var head := smoothstep(0.0, 0.08, t)
		var a := clampf(lit * shimmer * head * alpha, 0.0, 1.0)
		core.append(Color(base.r, base.g, base.b, a))
		mid.append(Color(base.r, base.g, base.b, a * 0.32))
		soft.append(Color(base.r, base.g, base.b, a * 0.085))
	_add.draw_polyline_colors(pts, soft, thick * 8.0, true)
	_add.draw_polyline_colors(pts, mid, thick * 2.6, true)
	_add.draw_polyline_colors(pts, core, thick, true)


func _draw_bottom_glow(pos: Vector2, k: float) -> void:
	var r := 9.0 + 4.0 * sin(clock * 3.0 + pos.x * 0.05)
	_blob(pos, r * 2.2, Color(WARM, 0.10 * k))
	_blob(pos, r * 0.9, Color(WARM, 0.30 * k))


func _draw_mirror(nodes: Array[Vector2], count: int, warm: float, lit: float, thick: float) -> void:
	if count < 2:
		return
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var base := WARM.lerp(SILVER, 1.0 - warm)
	for i in count:
		var p: Vector2 = nodes[i]
		var my := REFLECT_Y * 2.0 - p.y
		if my > _size().y + 40.0:
			continue
		var wob := sin(clock * 1.1 + p.y * 0.03) * 3.2
		pts.append(Vector2(p.x + wob, my))
		var t := float(i) / float(count - 1)
		var a := clampf(lit * 0.085 * (1.0 - t * 0.5), 0.0, 1.0)
		cols.append(Color(base.r, base.g, base.b, a))
	if pts.size() >= 2:
		_add.draw_polyline_colors(pts, cols, thick * 2.2, true)


func _draw_beads() -> void:
	for s in _strands:
		if s.cut_at >= 0 or clock < s.start:
			continue
		var grown := _grown_nodes(s)
		if grown < 3:
			continue
		for b in s.beads:
			if b > float(grown) / float(s.nodes.size()):
				continue
			var p := _sample(s.nodes, grown, b)
			var col := WARM.lerp(Color(0.82, 0.90, 1.0), 1.0 - s.warm)
			var tw := 0.7 + 0.3 * sin(clock * 4.0 + b * 30.0)
			_blob(p, 11.0, Color(col, 0.13 * s.lit * tw))
			_add.draw_circle(p, 1.85, Color(col, 0.72 * s.lit * tw))
			_add.draw_circle(p, 0.7, Color(1.0, 1.0, 1.0, 0.9 * s.lit))


func _sample(nodes: Array[Vector2], count: int, t: float) -> Vector2:
	var f := clampf(t, 0.0, 1.0) * float(count - 1)
	var i := int(f)
	var frac := f - float(i)
	if i >= count - 1:
		return nodes[count - 1]
	return nodes[i].lerp(nodes[i + 1], frac)


func _draw_rain() -> void:
	for d in _drops:
		var col := Color(0.72, 0.80, 0.96).lerp(WARM, d.warm * 0.85)
		var k := d.frozen
		if k < 0.62:
			_add.draw_line(d.pos, d.pos + Vector2(d.skew * d.length, d.length),
					Color(col, d.alpha * (1.0 - k)), 1.0, true)
		if k > 0.10:
			var r := 1.1 + 0.95 * k
			_blob(d.pos, r * 4.6, Color(col, 0.20 * k))
			_add.draw_circle(d.pos, r, Color(col, 0.85 * k))
			_add.draw_circle(d.pos + Vector2(-r * 0.30, -r * 0.42), r * 0.34, Color(1.0, 1.0, 1.0, 0.85 * k))
	if _light_energy > 0.02:
		var e := _light_energy
		_blob(_light, LIGHT_RADIUS, Color(WARM, 0.020 * e))
		_blob(_light, LIGHT_RADIUS * 0.52, Color(WARM, 0.030 * e))
		_blob(_light, 44.0, Color(WARM, 0.055 * e))


func _draw_slash() -> void:
	if _slash_active:
		var x0 := _size().x * -0.14 if _slash_dir > 0.0 else _size().x * 1.14
		var pts := PackedVector2Array()
		var core := PackedColorArray()
		var halo := PackedColorArray()
		var steps := 26
		for i in steps + 1:
			var t := float(i) / float(steps)
			var x := lerpf(x0, _slash_x, t)
			pts.append(Vector2(x, _slash_y(x)))
			var a := clampf(t * t * 1.4, 0.0, 1.0)
			core.append(Color(VIOLET_HOT, a))
			halo.append(Color(VIOLET, a * 0.26))
		if pts.size() >= 2:
			_add.draw_polyline_colors(pts, halo, 11.0, true)
			_add.draw_polyline_colors(pts, core, 2.4, true)
		var hp := Vector2(_slash_x, _slash_y(_slash_x))
		_blob(hp, 46.0, Color(VIOLET_HOT, 0.16))
		_blob(hp, 15.0, Color(1.0, 0.95, 1.0, 0.5))
		_add.draw_circle(hp, 2.6, Color(1.0, 1.0, 1.0, 0.95))
		_add.draw_line(hp + Vector2(-52, -3), hp + Vector2(52, 3), Color(VIOLET_HOT, 0.28), 1.0, true)
		_add.draw_line(hp + Vector2(-9, -30), hp + Vector2(9, 30), Color(VIOLET_HOT, 0.14), 1.0, true)
	if _slash_fade > 0.0:
		var a := _slash_fade * 0.5
		var pts2 := PackedVector2Array()
		var cols := PackedColorArray()
		for i in 13:
			var x := _size().x * float(i) / 12.0
			pts2.append(Vector2(x, _slash_y(x)))
			cols.append(Color(VIOLET, a * 0.45))
		_add.draw_polyline_colors(pts2, cols, 1.6, true)


func _slash_y(x: float) -> float:
	var t := clampf(x / maxf(1.0, _size().x), 0.0, 1.0)
	if _slash_dir > 0.0:
		return CUT_Y + 14.0 - t * 26.0
	return CUT_Y + 46.0 - t * 92.0


# ---------------------------------------------------------------- 前层（黑羽 / 断口）

func _draw_front() -> void:
	var off := _shake_offset() * 1.2
	for f in _feathers:
		var life_k := clampf(f.life / f.max_life, 0.0, 1.0)
		var a := clampf(life_k * 2.4, 0.0, 1.0) * (0.30 + 0.70 * f.depth)
		var sway := sin(clock * 1.6 + f.phase) * 0.24
		var h := f.size * 3.1
		var w := f.size
		_front.draw_set_transform(f.pos + off, f.rot + sway, Vector2(w, h) / Vector2(72.0, 224.0))
		_front.draw_texture_rect(_feather_tex[f.variant], Rect2(Vector2(-72.0, -112.0), Vector2(144.0, 224.0)),
				false, Color(1, 1, 1, a))
		_front.draw_set_transform(Vector2.ZERO)


# ---------------------------------------------------------------- 着色器

func _back_shader() -> Shader:
	var s := Shader.new()
	s.code = """shader_type canvas_item;
float hash(vec2 p) { return fract(sin(dot(p, vec2(41.3, 289.1))) * 24634.6345); }
void fragment() {
	vec2 uv = UV;
	float y = uv.y;
	vec3 top = vec3(0.014, 0.017, 0.028);
	vec3 mid = vec3(0.030, 0.038, 0.062);
	vec3 bot = vec3(0.012, 0.015, 0.024);
	vec3 c = mix(top, mid, smoothstep(0.0, 0.52, y));
	c = mix(c, bot, smoothstep(0.60, 1.0, y));
	c += vec3(0.018, 0.024, 0.040) * smoothstep(0.72, 1.0, y) * 0.8;
	float halo = exp(-pow((uv.x - 0.5) * 2.2, 2.0)) * exp(-pow((y - 0.02) * 3.2, 2.0));
	c += vec3(0.10, 0.082, 0.056) * halo * 0.6;
	c += (hash(FRAGCOORD.xy) - 0.5) / 255.0;
	COLOR = vec4(c, 1.0);
}"""
	return s


func _post_shader() -> Shader:
	var s := Shader.new()
	s.code = """shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float flash = 0.0;
uniform float aberr = 0.002;
uniform float time_s = 0.0;
uniform float fade_out = 0.0;
uniform float bloom = 0.95;
uniform float grain = 0.050;
uniform float vignette = 0.80;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 d = uv - vec2(0.5);
	vec2 ca = d * aberr;
	vec3 col;
	col.r = textureLod(screen_tex, uv + ca, 0.0).r;
	col.g = textureLod(screen_tex, uv, 0.0).g;
	col.b = textureLod(screen_tex, uv - ca, 0.0).b;
	vec3 b1 = textureLod(screen_tex, uv, 2.0).rgb;
	vec3 b2 = textureLod(screen_tex, uv, 3.4).rgb;
	vec3 glow = max(b1 - vec3(0.15), vec3(0.0)) * 0.62 + max(b2 - vec3(0.09), vec3(0.0)) * 0.50;
	glow *= vec3(1.02, 0.96, 1.12);
	col += glow * bloom;
	float l = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, col * vec3(0.88, 0.97, 1.16), (1.0 - smoothstep(0.0, 0.52, l)) * 0.55);
	col += flash * vec3(0.72, 0.62, 1.0) * 2.0;
	float v = smoothstep(0.30, 0.95, length(d * vec2(1.0, 0.80)));
	col *= 1.0 - v * vignette * 0.62;
	float n = hash(FRAGCOORD.xy + vec2(time_s * 37.0, time_s * 71.0));
	col += (n - 0.5) * grain;
	col *= 1.0 - fade_out;
	COLOR = vec4(max(col, vec3(0.0)), 1.0);
}"""
	return s
