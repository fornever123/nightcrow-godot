extends Control
## [YG-MARK] 设置页「白光定格」（6 项商业完整版：总音量 / 音乐音量 / 全屏 / 垂直同步 / 超采样 / 操作方式）

const W := 1920.0
const H := 1080.0
const INK := Color("#08070c")
const WHITE := Color("#f5f2eb")
const IMG := "res://assets/image/yg_zhanzhong/"
const BAND_SHADER := preload("res://scripts/ui/yg_zhanzhong/zz_light_band.gdshader")
const Factory := preload("res://scripts/night/player_factory.gd")

const BAND_TOP := 200.0
const BAND_BOT := 760.0
const LINE_Y := 548.0
const WORD_H := 156.0
const WORD_MAXW := 500.0
const WORD_X := 64.0
const WORD_CY := 462.0
const GHOST_X := 156.0
const GHOST_FS := 56
const CONTENT_X0 := 600.0
const CONTENT_X1 := 1800.0
const MOVE_H := 206.0
const SIL_SRC_H := 359.0

var T: Node = null
var ITEMS: Array = []
var ACTS: Array = []
var font_cn: Font
var font_lat: Font

var veil: ColorRect
var band: ColorRect
var band_mat: ShaderMaterial
var back: Control
var content: Control
var keys: Control
var front: Control

var words := {}
var moves: Array = []

var now := 0.0
var t_enter := -10.0
var t_leave := -10.0
var t_sel := -10.0
var shown := false
var reel := 0.0
var reel_v := 0.0
var expo := 0.0
var smear: Array = []
var fill := 1.0
var fill_goal := 1.0
var vol_shown := 1.0
var bgm_shown := 0.9
var fs_k := 0.0
var fs_v := 0.0
var vs_k := 1.0
var ss_k := 0.0
var adj_kick := 0.0
var ghost_rects: Array = []
var hover_i := -1


func setup(title: Node, items: Array, acts: Array) -> void:
	T = title
	ITEMS = items
	ACTS = acts
	font_cn = T.font_cn
	font_lat = T.font_lat
	size = Vector2(W, H)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for it in ITEMS:
		var k := String(it["key"])
		var p := IMG + "set_w_" + k + ".png"
		words[k] = load(p) if ResourceLoader.exists(p) else null
		smear.append(0.0)
	for i in 7:
		var p := IMG + "set_move_%d.png" % i
		moves.append(load(p) if ResourceLoader.exists(p) else null)

	veil = ColorRect.new()
	veil.color = Color(INK, 0.0)
	veil.size = Vector2(W * 1.4, H * 1.4)
	veil.position = Vector2(-W * 0.2, -H * 0.2)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(veil)

	back = _canvas(_draw_back)

	band = ColorRect.new()
	band.position = Vector2(0, BAND_TOP)
	band.size = Vector2(W, BAND_BOT - BAND_TOP)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band_mat = ShaderMaterial.new()
	band_mat.shader = BAND_SHADER
	band_mat.set_shader_parameter("rect_size", band.size)
	band_mat.set_shader_parameter("line_v", (LINE_Y - BAND_TOP) / (BAND_BOT - BAND_TOP))
	band.material = band_mat
	add_child(band)

	content = _canvas(_draw_content)
	keys = _canvas(_draw_keys)
	keys.material = T._gray_mat()
	front = _canvas(_draw_front)


func _canvas(cb: Callable) -> Control:
	var c := Control.new()
	c.size = Vector2(W, H)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(cb)
	add_child(c)
	return c


func enter() -> void:
	shown = true
	t_enter = now
	t_sel = now
	reel = float(T.set_idx)
	reel_v = 0.0
	expo = 1.0
	fill = _fill_target() if _cur_key() in ["master", "bgm"] else 1.0
	vol_shown = T.master_volume()
	bgm_shown = T.bgm_volume()
	fs_k = 1.0 if T.is_fullscreen() else 0.0
	vs_k = 1.0 if T.vsync_on() else 0.0
	ss_k = 1.0 if T.supersample_on() else 0.0
	for i in smear.size():
		smear[i] = 0.0


func leave() -> void:
	shown = false
	t_leave = now


func on_move(prev_idx: int) -> void:
	t_sel = now
	expo = 1.0
	if prev_idx >= 0 and prev_idx < smear.size():
		smear[prev_idx] = 1.0


func on_adjust() -> void:
	adj_kick = 1.0
	expo = maxf(expo, 0.45)


func _cur_key() -> String:
	return String(ITEMS[T.set_idx]["key"]) if T != null and not ITEMS.is_empty() else "master"


func update(dt: float) -> void:
	now += dt
	var idx: int = T.set_idx
	var n := float(ITEMS.size())
	var h := minf(dt, 1.0 / 30.0)
	var goal := reel + wrapf(float(idx) - reel, -n * 0.5, n * 0.5)
	reel_v += ((goal - reel) * 280.0 - reel_v * 27.0) * h
	reel += reel_v * h
	expo = maxf(0.0, expo - dt * 3.4)
	adj_kick = maxf(0.0, adj_kick - dt * 4.2)
	for i in smear.size():
		smear[i] = maxf(0.0, float(smear[i]) - dt * 1.8)

	var ck := _cur_key()
	fill_goal = _fill_target() if ck in ["master", "bgm"] else 1.0
	fill = lerpf(fill, fill_goal, 1.0 - exp(-dt * 14.0))
	vol_shown = lerpf(vol_shown, T.master_volume(), 1.0 - exp(-dt * 14.0))
	bgm_shown = lerpf(bgm_shown, T.bgm_volume(), 1.0 - exp(-dt * 14.0))
	var fs_goal := 1.0 if T.is_fullscreen() else 0.0
	fs_v += ((fs_goal - fs_k) * 420.0 - fs_v * 24.0) * h
	fs_k += fs_v * h
	vs_k = lerpf(vs_k, 1.0 if T.vsync_on() else 0.0, 1.0 - exp(-dt * 10.0))
	ss_k = lerpf(ss_k, 1.0 if T.supersample_on() else 0.0, 1.0 - exp(-dt * 8.0))

	var op := _open()
	veil.color = Color(INK, 0.8 * op)
	band_mat.set_shader_parameter("open", op)
	band_mat.set_shader_parameter("intensity", 1.0 + 0.25 * adj_kick)
	band_mat.set_shader_parameter("fill", fill)
	band_mat.set_shader_parameter("flash", expo * expo * 0.6)
	band_mat.set_shader_parameter("t", now)
	band_mat.set_shader_parameter("tint", Color(0.86, 0.9, 1.0).lerp(Color(T.accent), 0.06))
	back.queue_redraw()
	content.queue_redraw()
	keys.queue_redraw()
	front.queue_redraw()


func _open() -> float:
	if shown:
		var p := clampf((now - t_enter - 0.06) / 0.42, 0.0, 1.0)
		return 1.0 - pow(1.0 - p, 3.0) + sin(p * PI) * 0.06
	var q := clampf((now - t_leave) / 0.22, 0.0, 1.0)
	return 1.0 - q * q


func _intro() -> float:
	var p := clampf((now - t_enter - 0.12) / 0.5, 0.0, 1.0)
	return 1.0 - pow(1.0 - p, 3.0) if shown else 1.0


func _fill_target() -> float:
	var v: float = T.bgm_volume() if _cur_key() == "bgm" else T.master_volume()
	return (CONTENT_X0 + v * (CONTENT_X1 - CONTENT_X0)) / W


func _since_sel() -> float:
	return now - t_sel


func _ghost_y(k: float) -> float:
	if k < 0.0:
		return lerpf(WORD_CY, 286.0, minf(-k, 1.0)) - maxf(-k - 1.0, 0.0) * 92.0
	return lerpf(WORD_CY, 796.0, minf(k, 1.0)) + maxf(k - 1.0, 0.0) * 90.0


func _k(i: int) -> float:
	var n := float(ITEMS.size())
	var lo := -2.2 if n >= 5.0 else -1.5
	return wrapf(float(i) - reel, lo, lo + n)


func _edge_a(k: float) -> float:
	var n := float(ITEMS.size())
	var lo := -2.2 if n >= 5.0 else -1.5
	var hi := lo + n
	return clampf((k - lo) * 2.0, 0.0, 1.0) * clampf((hi - k) * 2.0, 0.0, 1.0)


func _draw_back() -> void:
	var c := back
	var op := _open()
	if op <= 0.001:
		return
	var a0 := op
	var hd: Texture2D = T._tex("df_settings")
	var hh := 60.0
	var hw := hh * hd.get_width() / hd.get_height()
	c.draw_texture_rect(hd, Rect2(56, 46, hw, hh), false, Color(1, 1, 1, a0))
	var lx0 := 56.0 + hw + 22.0
	var lx1 := lerpf(lx0, 1640.0, op)
	c.draw_line(Vector2(lx0, 80), Vector2(lx1, 80), Color(WHITE, 0.32 * a0), 1.4, true)
	_diamond(c, Vector2(lx0, 80), 5.0, Color(WHITE, 0.6 * a0))
	_diamond(c, Vector2(lx1, 80), 5.0, Color(WHITE, 0.6 * a0))
	c.draw_string(font_lat, Vector2(1864 - font_lat.get_string_size("05:59", HORIZONTAL_ALIGNMENT_LEFT, -1, 46).x, 96), "05:59",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 46, Color(WHITE, 0.82 * a0))

	ghost_rects.clear()
	var intro := _intro()
	for i in ITEMS.size():
		var k := _k(i)
		var ak := absf(k)
		if ak < 0.02:
			continue
		var key := String(ITEMS[i]["key"])
		var name := String(ITEMS[i]["name"])
		var val: String = T._set_value_text(key)
		var y := lerpf(WORD_CY, _ghost_y(k), intro)
		var dist_a := clampf(ak, 0.0, 1.0) * (1.0 if ak <= 1.05 else 0.72) * _edge_a(k)
		var base_a := 0.84 * dist_a * a0
		if hover_i == i:
			base_a = minf(1.0, base_a + 0.18)
		var nw := font_cn.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, GHOST_FS).x
		var x := GHOST_X
		var by := y + GHOST_FS * 0.36
		var sm := 0.55 + 2.4 * float(smear[i]) + 0.9 * clampf(1.0 - ak, 0.0, 1.0)
		for g in range(3, 0, -1):
			var gf := float(g)
			var wob := sin(now * (1.1 + 0.13 * gf) + gf * 1.7 + float(i) * 2.3)
			var off := Vector2(-gf * (5.5 + 2.2 * wob) * sm, wob * 1.4)
			var sx := 1.0 + 0.025 * gf * sm
			var ga := base_a * (0.09 + 0.14 * float(smear[i])) * (1.0 - gf / 4.0)
			c.draw_set_transform(Vector2(x, by) + off, 0.0, Vector2(sx, 1.0))
			c.draw_string(font_cn, Vector2.ZERO, name, HORIZONTAL_ALIGNMENT_LEFT, -1, GHOST_FS, Color(0.78, 0.8, 0.88, ga))
			c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var tc := Color(0.86, 0.87, 0.92, base_a)
		c.draw_string(font_cn, Vector2(x + 2, by + 2), name, HORIZONTAL_ALIGNMENT_LEFT, -1, GHOST_FS, Color(INK, base_a * 0.85))
		c.draw_string(font_cn, Vector2(x, by), name, HORIZONTAL_ALIGNMENT_LEFT, -1, GHOST_FS, tc)
		c.draw_string(font_cn, Vector2(x + nw + 24.0, by), val, HORIZONTAL_ALIGNMENT_LEFT, -1, 36, Color(tc, base_a * 0.86))
		var vw := font_cn.get_string_size(val, HORIZONTAL_ALIGNMENT_LEFT, -1, 38).x
		ghost_rects.append([i, Rect2(x - 30.0, y - 44.0, nw + vw + 90.0, 88.0)])


func _draw_content() -> void:
	var op := _open()
	if op <= 0.05:
		return
	var idx := posmod(roundi(reel), ITEMS.size())
	var settle := clampf(1.0 - absf(reel - roundf(reel)) * 3.0, 0.0, 1.0)
	var a := settle * clampf((op - 0.4) / 0.6, 0.0, 1.0)
	if a <= 0.01:
		return
	match String(ITEMS[idx]["key"]):
		"master": _content_volume(a, false)
		"bgm": _content_volume(a, true)
		"fullscreen": _content_fullscreen(a)
		"vsync": _content_vsync(a)
		"supersample": _content_supersample(a)
		"scheme": _content_scheme(a)


func _content_volume(a: float, is_bgm: bool) -> void:
	var c := content
	var x0 := CONTENT_X0
	var x1 := CONTENT_X1
	var cur_v: float = T.bgm_volume() if is_bgm else T.master_volume()
	var shown_v: float = bgm_shown if is_bgm else vol_shown
	var steps := roundi(cur_v * 10.0)
	if is_bgm:
		var bars := 28
		for b in bars:
			var frac := (float(b) + 0.5) / float(bars)
			var bx := lerpf(x0 + 14.0, x1 - 14.0, frac)
			var active := frac <= shown_v + 0.015
			var env := sin(frac * PI)
			var wave := 0.35 + 0.65 * absf(sin(now * (2.6 + float(b % 5) * 0.45) + float(b) * 0.62))
			var bh := (20.0 + 132.0 * env * wave * maxf(0.15, shown_v)) if active else 12.0
			var bcol := Color(INK, 0.78 * a) if active else Color(INK, 0.18 * a)
			c.draw_rect(Rect2(bx - 5.0, LINE_Y - 12.0 - bh, 10.0, bh), bcol)
			if active and b % 4 == 0:
				c.draw_rect(Rect2(bx - 5.0, LINE_Y - 16.0 - bh, 10.0, 3.0), Color(T.accent, 0.85 * a))
	for i in 11:
		var x := lerpf(x0, x1, i / 10.0)
		var major := i % 5 == 0
		var lit := i <= steps
		var th := 30.0 if major else 16.0
		c.draw_line(Vector2(x, LINE_Y - th), Vector2(x, LINE_Y - 2), Color(INK, (0.85 if lit else 0.35) * a), 4.0 if major else 2.5, true)
		var s := str(i)
		var fs := 30 if major else 24
		var sw := font_lat.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		c.draw_string(font_lat, Vector2(x - sw * 0.5, LINE_Y + 46), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			Color(WHITE, (0.85 if lit else 0.3) * a))
	var mx := lerpf(x0, x1, shown_v)
	var kick := adj_kick
	c.draw_rect(Rect2(x0, LINE_Y - 6.0, mx - x0, 5.0), Color(INK, 0.88 * a))
	c.draw_rect(Rect2(mx - 2.0, LINE_Y - 196.0 - 18.0 * kick, 4.0, 196.0 + 18.0 * kick), Color(INK, 0.94 * a))
	_diamond(c, Vector2(mx, LINE_Y - 2.0), 11.0, Color(INK, 0.96 * a))
	_diamond(c, Vector2(mx, LINE_Y - 2.0), 5.5, Color(T.accent, a))
	_diamond(c, Vector2(mx, LINE_Y - 202.0 - 18.0 * kick), 7.5, Color(T.accent, 0.96 * a))
	var num := "%d" % (steps * 10)
	var nfs := 82
	var nw := font_lat.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, nfs).x
	var on_left := (mx - 22.0 - nw) >= x0
	var nx := (mx - 22.0 - nw) if on_left else (mx + 22.0)
	var ny := LINE_Y - (146.0 if is_bgm else 62.0)
	if on_left:
		c.draw_string(font_lat, Vector2(nx + 2.0, ny + 2.0), num, HORIZONTAL_ALIGNMENT_LEFT, -1, nfs, Color(WHITE, 0.45 * a))
		c.draw_string(font_lat, Vector2(nx, ny), num, HORIZONTAL_ALIGNMENT_LEFT, -1, nfs, Color(INK, 0.92 * a))
	else:
		c.draw_string(font_lat, Vector2(nx + 3.0, ny + 3.0), num, HORIZONTAL_ALIGNMENT_LEFT, -1, nfs, Color(INK, 0.92 * a))
		c.draw_string(font_lat, Vector2(nx, ny), num, HORIZONTAL_ALIGNMENT_LEFT, -1, nfs, Color(WHITE, 0.94 * a))


func _content_fullscreen(a: float) -> void:
	var c := content
	var small := Rect2(1010.0, LINE_Y - 216.0, 390.0, 200.0)
	var big := Rect2(CONTENT_X0 + 24.0, BAND_TOP + 86.0, CONTENT_X1 - CONTENT_X0 - 48.0, LINE_Y - BAND_TOP - 96.0)
	var k := fs_k
	var r := Rect2(small.position.lerp(big.position, k), small.size.lerp(big.size, k))
	c.draw_rect(r, Color(INK, lerpf(0.76, 0.42, k) * a))
	c.draw_rect(r, Color(INK, 0.94 * a), false, 3.0)
	c.draw_rect(r.grow(-10.0), Color(WHITE, lerpf(0.26, 0.42, k) * a), false, 1.2)
	var mid := r.get_center()
	c.draw_line(mid + Vector2(-24, 0), mid + Vector2(24, 0), Color(WHITE, 0.32 * a), 1.2, true)
	c.draw_line(mid + Vector2(0, -18), mid + Vector2(0, 18), Color(WHITE, 0.32 * a), 1.2, true)
	_diamond(c, mid, 6.0, Color(T.accent, 0.92 * a))
	var col := Color(INK, 0.96 * a)
	var L := 46.0 + 34.0 * k
	var wdt := 6.0
	for cx in [0, 1]:
		for cy in [0, 1]:
			var p := Vector2(r.position.x + r.size.x * cx, r.position.y + r.size.y * cy)
			var sx := 1.0 if cx == 0 else -1.0
			var sy := 1.0 if cy == 0 else -1.0
			c.draw_line(p, p + Vector2(L * sx, 0), col, wdt, true)
			c.draw_line(p, p + Vector2(0, L * sy), col, wdt, true)
	if k > 0.02:
		for cx in [0, 1]:
			for cy in [0, 1]:
				var p0 := Vector2(small.position.x + small.size.x * cx, small.position.y + small.size.y * cy)
				var p1 := Vector2(r.position.x + r.size.x * cx, r.position.y + r.size.y * cy)
				c.draw_line(p0, p1, Color(T.accent, 0.55 * a * k), 1.8, true)
	var mode_tag := "BORDERLESS FULLSCREEN · 16:9" if T.is_fullscreen() else "WINDOWED · 16:9"
	var mtw := font_lat.get_string_size(mode_tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	c.draw_string(font_lat, Vector2(mid.x - mtw * 0.5, r.end.y - 18.0), mode_tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(WHITE, 0.82 * a))
	var lab := "无边框全屏" if T.is_fullscreen() else "桌面窗口"
	var lw := font_cn.get_string_size(lab, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
	c.draw_string(font_cn, Vector2(r.position.x + r.size.x * 0.5 - lw * 0.5, LINE_Y + 46.0), lab, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(WHITE, 0.88 * a))


func _content_vsync(a: float) -> void:
	var c := content
	var cx := (CONTENT_X0 + CONTENT_X1) * 0.5
	var top_y := BAND_TOP + 132.0
	var arm := 166.0
	var locked := vs_k
	var ph_a := sin(now * 2.4) * 0.36
	var ph_b := lerpf(sin(now * 3.5 + 1.1) * 0.42, ph_a, locked)
	c.draw_arc(Vector2(cx, top_y), arm, PI * 0.28, PI * 0.72, 64, Color(INK, 0.62 * a), 4.0, true)
	c.draw_arc(Vector2(cx, top_y), arm, PI * 0.28, PI * 0.72, 64, Color(WHITE, 0.55 * a), 1.4, true)
	for ti in range(-4, 5):
		var ang := PI * 0.5 + float(ti) * 0.095
		var r0 := arm - (18.0 if ti == 0 else 10.0)
		var r1 := arm + 8.0
		c.draw_line(Vector2(cx + cos(ang) * r0, top_y + sin(ang) * r0),
			Vector2(cx + cos(ang) * r1, top_y + sin(ang) * r1), Color(INK, (0.94 if ti == 0 else 0.65) * a), 4.0 if ti == 0 else 2.2, true)
	var sep := lerpf(62.0, 0.0, locked)
	for side in [-1, 1]:
		var ox := cx + float(side) * sep
		var ph := ph_a if side < 0 else ph_b
		var tip := Vector2(ox + sin(ph) * arm, top_y + cos(ph) * arm)
		var opa := 0.96 if side < 0 else lerpf(0.55, 0.96, locked)
		c.draw_line(Vector2(ox, top_y), tip, Color(INK, opa * a), 6.0, true)
		c.draw_line(Vector2(ox, top_y), tip, Color(WHITE, 0.82 * opa * a), 2.0, true)
		_diamond(c, tip, 18.0, Color(INK, opa * a))
		_diamond(c, tip, 11.0, Color(WHITE, 0.90 * opa * a))
		if locked > 0.5 and side < 0:
			_diamond(c, tip, 6.5, Color(T.accent, locked * a))
	_diamond(c, Vector2(cx, top_y), 11.0, Color(INK, 0.96 * a))
	_diamond(c, Vector2(cx, top_y), 5.5, Color(WHITE, 0.92 * a))
	var badge := "PHASE LOCKED · V-SYNC ON" if T.vsync_on() else "UNLOCKED · LOW LATENCY"
	var bw := font_lat.get_string_size(badge, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x + 28.0
	c.draw_rect(Rect2(cx - bw * 0.5, top_y - 40.0, bw, 28.0), Color(INK, 0.78 * a))
	c.draw_string(font_lat, Vector2(cx - bw * 0.5 + 14.0, top_y - 20.0), badge, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(T.accent.lightened(0.28) if T.vsync_on() else WHITE, 0.92 * a))
	var hint := "锁相防撕裂（刷新率同步）" if T.vsync_on() else "解锁延迟（不限刷新率）"
	var hw := font_cn.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x
	c.draw_string(font_cn, Vector2(cx - hw * 0.5, LINE_Y + 46.0), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(WHITE, 0.90 * a))


func _content_supersample(a: float) -> void:
	var c := content
	var p0 := Vector2(CONTENT_X0 + 48.0, LINE_Y - 26.0)
	var p1 := Vector2(CONTENT_X1 - 48.0, BAND_TOP + 114.0)
	var center := (p0 + p1) * 0.5
	var dir := (p1 - p0).normalized()
	var nrm := Vector2(-dir.y, dir.x)
	var k := ss_k
	c.draw_line(p0, p1, Color(INK, 0.36 * a), 2.4, true)
	var R := 114.0
	c.draw_circle(center, R, Color(INK, 0.88 * a))
	c.draw_arc(center, R, 0.0, TAU, 96, Color(INK, 0.96 * a), 6.0, true)
	c.draw_arc(center, R - 8.0, 0.0, TAU, 96, Color(WHITE, 0.45 * a), 1.6, true)
	for ti in 24:
		var ang := float(ti) * TAU / 24.0
		var r0 := R - (15.0 if ti % 6 == 0 else 8.0)
		c.draw_line(center + Vector2(cos(ang), sin(ang)) * r0, center + Vector2(cos(ang), sin(ang)) * (R - 2.0),
			Color(WHITE, (0.72 if ti % 6 == 0 else 0.28) * a), 1.6, true)
	var seg_a := center - dir * (R - 18.0)
	var seg_b := center + dir * (R - 18.0)
	if k < 0.99:
		var blk := lerpf(16.0, 4.0, k)
		var steps := int(seg_a.distance_to(seg_b) / blk)
		for i in steps:
			var t0 := float(i) / float(maxi(steps, 1))
			var pt := seg_a.lerp(seg_b, t0)
			var q := Vector2(floorf(pt.x / blk) * blk, floorf(pt.y / blk) * blk)
			if q.distance_to(center) < R - 16.0:
				c.draw_rect(Rect2(q - Vector2(blk, blk) * 0.5, Vector2(blk - 1.5, blk - 1.5)), Color(WHITE, 0.90 * a * (1.0 - k)))
	if k > 0.01:
		c.draw_line(seg_a, seg_b, Color(WHITE, 0.98 * a * k), 6.0, true)
		c.draw_line(seg_a + nrm * 6.5, seg_b + nrm * 6.5, Color(T.accent, 0.92 * a * k), 2.4, true)
		var gl := fmod(now * 0.85, 1.0)
		var gp := seg_a.lerp(seg_b, gl)
		_diamond(c, gp, 10.0 * sin(gl * PI), Color(WHITE, 0.96 * a * k))
	var tag_m := "2.0× SSAA" if T.supersample_on() else "1.0× NATIVE"
	var mw := font_lat.get_string_size(tag_m, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	c.draw_string(font_lat, Vector2(center.x - mw * 0.5, center.y + R - 26.0), tag_m, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(T.accent.lightened(0.28) if T.supersample_on() else WHITE, 0.88 * a))
	var lab := "×2  200% 锐利超采" if T.supersample_on() else "×1  原生分辨率"
	var lw := font_cn.get_string_size(lab, HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x
	c.draw_string(font_cn, Vector2(center.x - lw * 0.5, LINE_Y + 46.0), lab, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(WHITE, 0.90 * a))


func _move_cells() -> Array:
	var out := []
	var acts: Array = ACTS
	var cw := (CONTENT_X1 - CONTENT_X0) / acts.size()
	for i in acts.size():
		out.append({"i": i, "cx": CONTENT_X0 + (i + 0.5) * cw, "cw": cw, "act": acts[i]})
	return out


func _content_scheme(a: float) -> void:
	var c := content
	var ss := _since_sel()
	var cells := _move_cells()
	var sc := MOVE_H / SIL_SRC_H
	for cell in cells:
		var i: int = cell["i"]
		var cx: float = cell["cx"]
		var pi := clampf((ss - 0.02 - i * 0.022) / 0.07, 0.0, 1.0)
		if pi <= 0.0:
			continue
		var tex: Texture2D = moves[i] if i < moves.size() else null
		if tex != null:
			var w := tex.get_width() * sc
			var grow := 1.0 + 0.08 * (1.0 - pi)
			var r := Rect2(cx - w * 0.5 * grow, LINE_Y + 6.0 - MOVE_H * grow, w * grow, MOVE_H * grow)
			c.draw_texture_rect(tex, r, false, Color(0.015, 0.013, 0.03, a * pi))
		var name := String((cell["act"] as Array)[0])
		var nw := font_cn.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x
		var ncol := Color(WHITE, 0.95 * a * pi)
		c.draw_string_outline(font_cn, Vector2(cx - nw * 0.5, LINE_Y + 52.0), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, 2, ncol)
		c.draw_string(font_cn, Vector2(cx - nw * 0.5, LINE_Y + 52.0), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, ncol)
		if i > 0:
			_diamond(c, Vector2(cx - float(cell["cw"]) * 0.5, LINE_Y + 70.0), 4.0, Color(WHITE, 0.35 * a))
	if cells.size() >= 7:
		var pa := clampf((ss - 0.5) / 0.25, 0.0, 1.0)
		if pa > 0.0:
			var s0 := Vector2(float(cells[2]["cx"]) + 70.0, LINE_Y - 66.0)
			var s1 := Vector2(float(cells[6]["cx"]) + 60.0, LINE_Y - MOVE_H + 4.0)
			var e := s0.lerp(s1, pa)
			var acc: Color = T.accent
			c.draw_line(s0, e, Color(acc, 0.85 * a), 2.0, true)
			c.draw_line(s0, e, Color(acc.lerp(WHITE, 0.6), 0.6 * a), 0.8, true)


func _draw_keys() -> void:
	var op := _open()
	var idx := posmod(roundi(reel), ITEMS.size())
	if op <= 0.4 or String(ITEMS[idx]["key"]) != "scheme":
		return
	var settle := clampf(1.0 - absf(reel - roundf(reel)) * 3.0, 0.0, 1.0)
	var a := settle * clampf((op - 0.4) / 0.6, 0.0, 1.0)
	var ss := _since_sel()
	var c := keys
	var is_kb: bool = Factory.scheme() == Factory.SCHEME_KEYBOARD
	for cell in _move_cells():
		var i: int = cell["i"]
		var pi := clampf((ss - 0.05 - i * 0.022) / 0.08, 0.0, 1.0) * a
		if pi <= 0.0:
			continue
		var act: Array = cell["act"]
		var cx: float = cell["cx"]
		var kb: Array = act[1] if is_kb else act[2]
		var pad: Array = act[3]
		var sz := 54.0
		var gap := 8.0
		var kb_a := pi * (0.58 if T.last_pad else 1.0)
		var pad_a := pi * (1.0 if T.last_pad else 0.58)
		var w := kb.size() * sz + (kb.size() - 1) * gap
		for j in kb.size():
			c.draw_texture_rect(T._icon(String(kb[j])), Rect2(cx - w * 0.5 + j * (sz + gap), LINE_Y + 68.0, sz, sz), false, Color(1.25, 1.25, 1.3, kb_a))
		w = pad.size() * sz + (pad.size() - 1) * gap
		for j in pad.size():
			c.draw_texture_rect(T._icon(String(pad[j])), Rect2(cx - w * 0.5 + j * (sz + gap), LINE_Y + 128.0, sz, sz), false, Color(1.8, 1.8, 1.9, pad_a))


func _draw_front() -> void:
	var c := front
	var op := _open()
	if op <= 0.02:
		return
	var intro := _intro()
	for i in ITEMS.size():
		var k := _k(i)
		var ak := absf(k)
		if ak >= 1.0:
			continue
		var inside := 1.0 - ak
		var key := String(ITEMS[i]["key"])
		var tex: Texture2D = words.get(key)
		var dy := (_ghost_y(k) - WORD_CY) * 0.85
		var a := inside * inside * op * intro
		var pop := 1.0 + 0.05 * expo * (1.0 if i == int(T.set_idx) else 0.0)
		var hgt := WORD_H * pop
		var w := 0.0
		var rect := Rect2()
		if tex != null:
			hgt = minf(hgt, WORD_MAXW * pop * tex.get_height() / tex.get_width())
			w = hgt * tex.get_width() / tex.get_height()
			rect = Rect2(WORD_X, WORD_CY + dy - hgt * 0.5, w, hgt)
			for d in [Vector2(-2.5, -2.5), Vector2(2.5, -2.5), Vector2(-2.5, 2.5), Vector2(2.5, 2.5)]:
				c.draw_texture_rect(tex, Rect2(rect.position + d, rect.size), false, Color(INK, 0.72 * a))
			c.draw_texture_rect(tex, Rect2(rect.position + Vector2(5, 6), rect.size), false, Color(INK, 0.90 * a))
			c.draw_texture_rect(tex, rect, false, Color(WHITE, a))
			if expo > 0.01 and i == int(T.set_idx):
				c.draw_texture_rect(tex, rect.grow(6.0 * expo), false, Color(1, 1, 1, 0.35 * expo * a))
		else:
			var nm := String(ITEMS[i]["name"])
			c.draw_string(font_cn, Vector2(WORD_X, WORD_CY + dy + 50), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 140, Color(WHITE, a))
			w = font_cn.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 140).x
		var val: String = T._set_value_text(key)
		var vfs := 42
		var vw := font_cn.get_string_size(val, HORIZONTAL_ALIGNMENT_LEFT, -1, vfs).x
		var px := WORD_X + minf(w * 0.42, 220.0)
		var py := LINE_Y + 8.0 + dy
		var pw := vw + 74.0
		var ph := 66.0
		var kick := adj_kick if i == int(T.set_idx) else 0.0
		var poly := PackedVector2Array([
			Vector2(px + 18, py), Vector2(px + pw + 26, py), Vector2(px + pw, py + ph), Vector2(px - 8, py + ph)])
		var sh := PackedVector2Array()
		for p in poly:
			sh.append(p + Vector2(6, 7))
		c.draw_colored_polygon(sh, Color(INK, 0.6 * a))
		c.draw_colored_polygon(poly, Color(WHITE.lerp(Color.WHITE, kick), a))
		c.draw_line(Vector2(px - 8, py + ph), Vector2(px + pw, py + ph), Color(T.accent, 0.9 * a), 3.0, true)
		c.draw_string(font_cn, Vector2(px + 32 + 6.0 * kick, py + 47), val, HORIZONTAL_ALIGNMENT_LEFT, -1, vfs, Color(INK, a))


func _diamond(c: CanvasItem, p: Vector2, r: float, col: Color) -> void:
	c.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0)]), col)


func hit(p: Vector2) -> Dictionary:
	for e in ghost_rects:
		if (e[1] as Rect2).has_point(p):
			return {"pick": int(e[0])}
	var idx: int = T.set_idx
	if p.y > BAND_TOP + 60.0 and p.y < LINE_Y + 170.0:
		var ck := String(ITEMS[idx]["key"])
		if (ck == "master" or ck == "bgm") and p.x >= CONTENT_X0 - 30.0 and p.x <= CONTENT_X1 + 30.0:
			return {"volume": clampf((p.x - CONTENT_X0) / (CONTENT_X1 - CONTENT_X0), 0.0, 1.0), "key": ck}
		return {"adjust": 1}
	return {}


func set_hover(p: Vector2) -> bool:
	hover_i = -1
	for e in ghost_rects:
		if (e[1] as Rect2).has_point(p):
			hover_i = int(e[0])
			return true
	return p.y > BAND_TOP + 60.0 and p.y < LINE_Y + 170.0
