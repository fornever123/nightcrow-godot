extends Node2D
## 大招「千刃」的全屏表现（2026-10-23 重做，取代 §16.12 的“月下斩”分镜版）。
## 时间轴跟着主角的 ult_frame（60 帧 / 秒，见 player.gd 的 ult_* 参数）：
##   ① 起手（0～ult_charge_frames）：时间停住——背景褪色压暗（fx_ult_grade）；四周集中线往主角收；刀尖一闪；HUD 藏起来
##   ② 千刃（每次 ult_pass）：主角瞬移穿过下一只影——沿路一串残影 + 一道硬边斩线（白芯紫边，两头尖，约 10 帧收细消失）；
##      被穿过的影身上留一道斜刀痕，刀痕一直挂着、越积越多；连斩越来越快，斩线交错成网
##   ③ 收刀（ult_click_frame）：背对敌人“咔”一声（sheathed），刀痕全部一亮
##   ④ 一齐爆开（burst，ult_hit 那一帧）：白闪 + 重击冲击帧；每只影身上的刀痕炸开成放射斩线 + 命中爆闪
##   ⑤ 收尾：颜色恢复、HUD 回来
## 斩线 / 刀痕都是自己画的硬边多边形（不进像素特效画布，不糊）；命中爆闪、残影、冲击帧借 impact_fx。

signal sheathed(point: Vector2)      ## ③ 收刀“咔”

const ImpactFX := preload("res://scripts/presentation/impact_fx.gd")
const GRADE_SHADER := preload("res://assets/shaders/fx_ult_grade.gdshader")
const VIEW := Vector2(2560.0, 1440.0)    ## 镜头 ZOOM 0.5 → 世界里一屏的大小
const WHITE := ImpactFX.WHITE
const VIO_L := ImpactFX.VIO_L
const VIO := ImpactFX.VIO
const VIO_D := ImpactFX.VIO_D

const HIDE_HUD := true       ## 大招期间把 HUD 藏起来
const TRAIL_LIFE := 11.0     ## 一道斩线留多久（帧）
const TRAIL_W := 13.0        ## 斩线最宽处（屏幕像素）
const MARK_LEN := 46.0       ## 刀痕长度（屏幕像素）
const FLASH_LIFE := 9.0      ## 爆开那一下白闪多久（帧）
const BURST_LIFE := 16.0     ## 刀痕炸开的放射斩线留多久（帧）

var fx: Node2D               ## ImpactFX
var player: Node2D
var hud: Control             ## CombatHud（藏起来 / 静音提示字）
var rng := RandomNumberGenerator.new()

var _phase: int = 0          ## 0 没在放 / 1 起手 + 千刃 / 2 爆开之后
var _f: float = 0.0          ## 起手后第几帧（跟主角 ult_frame 对齐）
var _since_burst: float = 0.0
var _grade_k: float = 0.0
var _hud_k: float = 1.0
var _clicked: bool = false
var _glinted: bool = false
var _flash: float = 0.0
var _trails: Array = []      ## {a, b, born, w, tilt}
var _marks: Array = []       ## {node, off, ang, len, born}
var _bursts: Array = []      ## {pt, born, rays: [[ang, len]]}

var _grade_copy: BackBufferCopy
var _grade: Node2D
var _grade_mat: ShaderMaterial
var _lo: Node2D              ## 角色身后：斩线
var _hi: Node2D              ## 角色前面：刀痕、炸开的放射斩线
var _ui: CanvasLayer         ## 屏幕坐标：集中线、白闪
var _ui_draw: Node2D


func _ready() -> void:
	z_index = 20
	process_priority = 10
	rng.randomize()
	_grade_copy = BackBufferCopy.new()
	_grade_copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	_grade_copy.z_as_relative = false
	_grade_copy.z_index = -3
	_grade_copy.visible = false
	add_child(_grade_copy)
	_grade = Node2D.new()
	_grade.z_as_relative = false
	_grade.z_index = -3              # 地形（−70）之后、斩线（−2）/ 残影（−1）/ 角色（0）之前
	_grade.visible = false
	_grade_mat = ShaderMaterial.new()
	_grade_mat.shader = GRADE_SHADER
	_grade.material = _grade_mat
	add_child(_grade)
	_grade.draw.connect(func(): _grade.draw_rect(Rect2(-VIEW * 0.6, VIEW * 1.2), Color.WHITE))
	_lo = _world(-2)
	_lo.draw.connect(_draw_lo)
	_hi = _world(18)                  # 角色之上、伤害数字（35）之下
	_hi.draw.connect(_draw_hi)
	_ui = CanvasLayer.new()
	_ui.layer = 11                    # HUD 是 10
	add_child(_ui)
	_ui_draw = Node2D.new()
	_ui.add_child(_ui_draw)
	_ui_draw.draw.connect(_draw_ui)


func _world(z: int) -> Node2D:
	var n := Node2D.new()
	n.top_level = true
	n.z_as_relative = false
	n.z_index = z
	add_child(n)
	return n


# ---------------------------------------------------------------- 对外

## ① 起手（主角 ult_started）
func begin() -> void:
	clear()
	_phase = 1
	if _ok() and is_instance_valid(fx):
		fx.spawn_launch(_feet())


func clear() -> void:
	_phase = 0
	_f = 0.0
	_since_burst = 0.0
	_grade_k = 0.0
	_clicked = false
	_glinted = false
	_flash = 0.0
	_trails.clear()
	_marks.clear()
	_bursts.clear()
	_grade.visible = false
	_grade_copy.visible = false
	_hud_k = 1.0
	_apply_hud()


func busy() -> bool:
	return _phase != 0


## ② 第 k 斩（共 n 斩）：主角从 from 瞬移到 to；穿过的影在 point（没有影 = Vector2.INF）
func cut(from: Vector2, to: Vector2, point: Vector2, node: Node2D, k: int, n: int) -> void:
	var px := _px()
	var dir := signf(to.x - from.x) if not is_equal_approx(to.x, from.x) else 1.0
	# 斩线：在胸口高度上下错开一点，每刀都略斜，连起来交错成网
	var y0 := -54.0 * px + rng.randf_range(-16.0, 16.0) * px
	var tilt := rng.randf_range(-24.0, 24.0) * px
	var a := from + Vector2(-dir * 40.0 * px, y0 - tilt * 0.5)
	var b := to + Vector2(dir * 30.0 * px, y0 + tilt * 0.5)
	var late := float(k) / float(maxi(n - 1, 1))
	_trails.append({"a": a, "b": b, "born": _f, "w": TRAIL_W * (0.85 + 0.4 * late)})
	if not is_instance_valid(fx):
		return
	var spr: Sprite2D = player.get_node_or_null("Visual/ActorSprite") if _ok() else null
	if spr != null:
		fx.ghost_line(spr, from, to, clampi(int(absf(to.x - from.x) / (70.0 * px)), 3, 7), VIO_L)
	if point != Vector2.INF and node != null:
		var ang := rng.randf_range(0.45, 1.1) * (1.0 if rng.randf() < 0.5 else -1.0)
		_marks.append({"node": node, "off": point - node.global_position + Vector2(rng.randf_range(-10, 10), rng.randf_range(-16, 16)) * px,
			"ang": ang, "len": MARK_LEN * rng.randf_range(0.8, 1.25), "born": _f})
		fx.spawn_hit(point, 0.45 + 0.35 * late, false, Vector2(dir, 0), true, &"dash_slash")


## ④ 一齐爆开（主角 ult_hit）。hit = [{node, pt, cuts}]
func burst(hit: Array) -> void:
	_phase = 2
	_since_burst = 0.0
	_flash = FLASH_LIFE
	if is_instance_valid(fx):
		fx.impact_frame(1.0)
	var px := _px()
	for h in hit:
		var pt: Vector2 = h.pt
		var rays: Array = []
		var cuts: int = clampi(int(h.get("cuts", 1)), 1, 6)
		for m in _marks:
			if m.node == h.node:
				rays.append([float(m.ang), float(m.len) * 2.6 * px])
		for i in 3:
			rays.append([rng.randf_range(-PI, PI), rng.randf_range(60.0, 110.0) * px])
		_bursts.append({"pt": pt, "born": 0.0, "rays": rays})
		if is_instance_valid(fx):
			var dir := Vector2(signf(pt.x - player.global_position.x) if _ok() else 1.0, 0.0)
			fx.spawn_hit(pt, 1.1 + 0.12 * float(cuts), true, dir, false, &"charge_1")
	_marks.clear()


# ---------------------------------------------------------------- 每帧

func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		global_position = cam.get_screen_center_position()
	var df := delta * 60.0
	if _phase != 0:
		if _ok() and player.has_method("is_ult") and player.is_ult():
			_f = float(player.ult_frame)
		elif _phase == 1 and _f > 2.0:
			clear()          # 大招被打断（重开 / 死了）
			return
		else:
			_f += df
	if _phase == 2:
		_since_burst += df
	_tick_cues()
	_flash = maxf(_flash - df, 0.0)
	_trails = _trails.filter(func(t): return _f - float(t.born) < TRAIL_LIFE)
	_bursts = _bursts.filter(func(bs): return _since_burst - float(bs.born) < BURST_LIFE)
	_marks = _marks.filter(func(m): return is_instance_valid(m.node))
	_update_grade(df)
	_update_hud(df)
	if _phase == 2 and _since_burst > 30.0 and _bursts.is_empty() and not (_ok() and player.is_ult()):
		var keep := _hud_k
		clear()
		_hud_k = keep
		_apply_hud()
	_lo.queue_redraw()
	_hi.queue_redraw()
	_ui_draw.queue_redraw()


## 刀尖一闪（起手末）、收刀“咔”
func _tick_cues() -> void:
	if not _ok() or _phase == 0:
		return
	var charge := float(player.get("ult_charge_frames")) if player.get("ult_charge_frames") != null else 16.0
	if not _glinted and _f >= charge - 5.0:
		_glinted = true
		if is_instance_valid(fx):
			fx.spawn_parry(player.global_position + Vector2(float(player.facing) * 70.0, -70.0) * _px(), Vector2(player.facing, 0))
	var click := float(player.get("ult_click_frame")) if player.get("ult_click_frame") != null else 89.0
	if not _clicked and _f >= click:
		_clicked = true
		var hp := player.global_position + Vector2(-float(player.facing) * 10.0, -40.0) * _px()
		sheathed.emit(hp)
		if is_instance_valid(fx):
			fx.spawn_block(hp, Vector2(-player.facing, 0))


func _update_grade(df: float) -> void:
	var want := 0.0
	if _phase == 1:
		want = 1.0
	elif _phase == 2:
		want = 1.0 - smoothstep(4.0, 22.0, _since_burst)
	_grade_k = move_toward(_grade_k, want, df * (0.14 if want > _grade_k else 1.0))
	var on := _grade_k > 0.002
	_grade.visible = on
	_grade_copy.visible = on
	if on:
		_grade_mat.set_shader_parameter("amount", _grade_k)
		_grade.queue_redraw()


func _update_hud(df: float) -> void:
	var want := 1.0
	if _phase == 1 or (_phase == 2 and _since_burst < 10.0):
		want = 0.0
	_hud_k = move_toward(_hud_k, want, df * (1.0 / 6.0 if want < _hud_k else 1.0 / 12.0))
	_apply_hud()


func _apply_hud() -> void:
	if not is_instance_valid(hud):
		return
	if HIDE_HUD:
		hud.modulate.a = _hud_k
	if hud.get("muted") != null:
		hud.muted = _phase != 0


# ---------------------------------------------------------------- 画

## 斩线：两头尖的硬边长条，三层（深紫外边 / 紫 / 白芯）；出现 2 帧最宽，之后从尾巴往刀尖收细消失
func _draw_lo() -> void:
	var px := _px()
	for t in _trails:
		var age := _f - float(t.born)
		var k := clampf(age / TRAIL_LIFE, 0.0, 1.0)
		var w: float = float(t.w) * px * (1.0 if age < 2.0 else 1.0 - k * 0.85)
		var a: Vector2 = t.a
		var b: Vector2 = t.b
		a = a.lerp(b, smoothstep(0.15, 1.0, k))     # 尾巴往刀尖收
		for layer in [[VIO_D, 1.0], [VIO, 0.7], [WHITE, 0.32]]:
			var c: Color = layer[0]
			c.a = 1.0 if age < 3.0 else 1.0 - smoothstep(0.55, 1.0, k)
			_lens(_lo, a, b, w * float(layer[1]), c)


## 刀痕（挂在影身上，越积越多）+ 爆开时的放射斩线
func _draw_hi() -> void:
	var px := _px()
	var bright := 1.0 if not _clicked else 1.6
	for m in _marks:
		var node: Node2D = m.node
		var c: Vector2 = node.global_position + (m.off as Vector2)
		var age := _f - float(m.born)
		var grow := clampf((age + 1.0) / 3.0, 0.0, 1.0)            # 2 帧内划开
		var half := Vector2.from_angle(float(m.ang)) * float(m.len) * px * 0.5 * grow
		var w := (5.0 if age < 3.0 else 3.0) * px * bright
		_lens(_hi, c - half, c + half, w * 1.8, Color(VIO, 0.85))
		_lens(_hi, c - half, c + half, w, Color(WHITE, 1.0))
	for bs in _bursts:
		var age := _since_burst - float(bs.born)
		var k := clampf(age / BURST_LIFE, 0.0, 1.0)
		var p: Vector2 = bs.pt
		for r in bs.rays:
			var dir := Vector2.from_angle(float(r[0]))
			var l: float = float(r[1]) * (0.35 + 0.65 * smoothstep(0.0, 0.25, k))
			var a := p + dir * l * smoothstep(0.3, 1.0, k)               # 从里往外收
			var b := p + dir * l
			var w := 7.0 * px * (1.0 - k * 0.8)
			_lens(_hi, a, b, w * 1.7, Color(VIO, 1.0 - smoothstep(0.6, 1.0, k)))
			_lens(_hi, a, b, w, Color(WHITE, 1.0 - smoothstep(0.5, 1.0, k)))
			_lens(_hi, p - dir * l * 0.6 * (1.0 - k), p - dir * l * 0.3 * (1.0 - k), w * 0.6, Color(VIO_L, 1.0 - k))


## 屏幕层：起手时四周集中线往主角收（每 2 帧换一组 = 闪）；爆开那一下白闪
func _draw_ui() -> void:
	var vs := get_viewport().get_visible_rect().size
	if _phase == 1 and _ok():
		var charge := float(player.get("ult_charge_frames")) if player.get("ult_charge_frames") != null else 16.0
		var k := clampf(_f / charge, 0.0, 1.0)
		var fade := 1.0 - smoothstep(charge, charge + 10.0, _f)
		if fade > 0.0:
			var c: Vector2 = player.get_global_transform_with_canvas().origin + Vector2(0.0, -40.0)
			var r := RandomNumberGenerator.new()
			r.seed = int(_f / 2.0) * 7919 + 13
			var outer := vs.length() * 0.6
			var inner := lerpf(outer * 0.75, 170.0, k)
			for i in 34:
				var ang := r.randf_range(-PI, PI)
				var d := Vector2.from_angle(ang)
				var w := r.randf_range(2.0, 7.0)
				var p0 := c + d * outer
				var p1 := c + d * (inner + r.randf_range(0.0, 140.0))
				var n := d.orthogonal() * w
				_ui_draw.draw_colored_polygon(PackedVector2Array([p0 - n, p0 + n, p1]), Color(0.92, 0.9, 1.0, 0.5 * fade * k))
	if _flash > 0.0:
		var a := (_flash / FLASH_LIFE)
		_ui_draw.draw_rect(Rect2(Vector2.ZERO, vs), Color(1.0, 0.98, 1.0, 0.55 * a * a))


## 两头尖的细长菱形（a → b，中间最宽 w）
func _lens(cv: CanvasItem, a: Vector2, b: Vector2, w: float, col: Color) -> void:
	if col.a <= 0.003 or w <= 0.05 or a.distance_squared_to(b) < 1.0:
		return
	var d := (b - a)
	var n := d.normalized().orthogonal() * w * 0.5
	var m1 := a + d * 0.35
	var m2 := a + d * 0.7
	cv.draw_colored_polygon(PackedVector2Array([a, m1 + n, m2 + n * 0.8, b, m2 - n * 0.8, m1 - n]), col)


# ---------------------------------------------------------------- 工具

func _ok() -> bool:
	return is_instance_valid(player)


func _px() -> float:
	var cam := get_viewport().get_camera_2d()
	return 1.0 / maxf(cam.zoom.x, 0.01) if cam != null else 2.0


func _feet() -> Vector2:
	var fo: Variant = player.get("foot_offset")
	return player.global_position + Vector2(0.0, float(fo) if fo != null else 84.0)
