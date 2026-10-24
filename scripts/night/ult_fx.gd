extends Node2D
## 大招「千刃」的全屏表现（2026-10-23 商业级版 v2：按审核意见重做节奏、高潮、切入、UI）。
## 时间轴跟着主角的 ult_frame（60 帧 / 秒；各段边界读 player.gd 的 ult_* 参数，括号里是默认值）：
##   ① 起势（0～29）：时间停住——黑边滑入、背景褪色压暗、镜头推近到 1.15 倍并移向主角；56 根集中线汇向主角、缓慢旋转；
##      脚下光圈由外往里收、身上冒上升光粒；刀身辉光加强；末尾刀尖一闪
##   ② 切入（30～65）：一条长长的斜立绘带（深紫→亮紫渐变 + 流光 + 后面一条错开的副带）滑入 6 帧、缓慢漂移、
##      沿带子方向滑出 6 帧；立绘有 assets/image/ult/cutin.png 就用它，没有就用主角当前姿势放大做占位；
##      题字「千刃」左→右 8 帧显现，印章晚 4 帧 1.6 倍盖下来（带小抖）；题字和带子一起退场
##   ③ 千刃（66～109，十斩，越来越快）：镜头 1.18 倍跟着主角；每斩瞬移穿过一只影——3～4 个残影 + 宽斩线（交错成网）
##      + 全屏横向速度线 + 小色差冲击；影身上留刀痕（越积越多）；左侧 HIT 计数（深色底板）；最后三斩闪紫，最后一斩加重
##   ④ 残心（115～143）：主角背对敌群收刀；场景压到约三成亮度，只有刀痕自发光；镜头慢慢推向主角；140 收刀“咔”，刀痕一亮
##   ⑤ 刀缝（144～153）：全黑 10 帧，先出 X 的第一道刀缝（细→粗、带辉光），第 6 帧出第二道
##   ⑥ 全屏巨斩（154 = ult_hit）：X 斩就沿那两道刀缝炸开（交点 = 敌群中心，±24°）；纯白 2 帧 → 负片 3 帧 → 高对比回落；
##      画面沿斩线错开 20px 停 6 帧；径向模糊 + 色差 + 冲击波；敌人白剪影定格 10 帧后一齐爆开（碎片 + 放射斩线）被打飞；
##      总伤害数字 1.6 倍盖章落下
##   ⑦ 收尾：颜色恢复；计数淡出；黑边退出后 HUD 才回来
## 所有全屏调色 / 闪光都在黑边和大招 UI 之下（同一个 CanvasLayer 里先画），黑位保持纯黑。

signal sheathed(point: Vector2)      ## ④ 收刀“咔”
signal popped(target: Node2D)        ## ⑥ 定格结束、某只影爆开（关卡这时冒伤害数字）

const ImpactFX := preload("res://scripts/presentation/impact_fx.gd")
const GRADE_SHADER := preload("res://assets/shaders/fx_ult_grade.gdshader")
const SPLIT_SHADER := preload("res://assets/shaders/fx_ult_split.gdshader")
const SIL_SHADER := preload("res://assets/shaders/fx_ult_sil.gdshader")
const SHOCK_SHADER := preload("res://assets/shaders/fx_ult_shock.gdshader")
const TITLE_PATH := "res://assets/image/ult/title.png"
const SEAL_PATH := "res://assets/image/ult/seal.png"
const CUTIN_PATH := "res://assets/image/ult/cutin.png"
const VIEW := Vector2(2560.0, 1440.0)    ## 镜头 ZOOM 0.5 → 世界里一屏的大小
const WHITE := ImpactFX.WHITE
const VIO_L := ImpactFX.VIO_L
const VIO := ImpactFX.VIO
const VIO_D := ImpactFX.VIO_D
const INK := Color("120d1c")

const HIDE_HUD := true
const LETTERBOX := 78.0      ## 黑边高度（屏幕像素）
const ZOOM_IN := 0.25        ## 起势镜头推近
const ZOOM_PASS := 0.45      ## 连斩镜头推近（跟着敌群、压低到地面）
const ZOOM_STILL := 0.55     ## 残心镜头推近（慢慢推到）
const X_ANG := 0.42          ## 巨斩两臂的角度（弧度，约 24°）
const TRAIL_LIFE := 12.0
const TRAIL_W := 18.0        ## 斩线最宽处（屏幕像素）
const MARK_LEN := 46.0
const X_W := 70.0            ## 巨斩最宽处（屏幕像素）
const X_LIFE := 30.0
const BURST_HOLD := 10.0     ## 巨斩后定格多久（帧）再爆开（关卡同步给敌人 hitstop）
const BURST_LIFE := 20.0
const SLIT_FRAMES := 10.0    ## 巨斩前全黑刀缝多少帧
const TITLE_SCALE := 0.44
const CUT_H := 230.0         ## 切入带高度（屏幕像素）
const CUT_TILT := 0.12

var fx: Node2D               ## ImpactFX
var player: Node2D
var hud: Control
var anchor: Node2D           ## 关卡给的镜头钉子（千刃期间镜头跟它）
var rng := RandomNumberGenerator.new()

var _phase: int = 0          ## 0 没在放 / 1 起势～刀缝 / 2 巨斩之后
var _f: float = 0.0
var _since_burst: float = 0.0
var _grade_k: float = 0.0
var _hud_k: float = 1.0
var _clicked: bool = false
var _glinted: bool = false
var _turned: bool = false
var _flash: float = 0.0
var _vflash: float = 0.0
var _trails: Array = []      ## {a, b, born, w}
var _marks: Array = []       ## {node, off, ang, len, born}
var _bursts: Array = []      ## {pt, born, rays, node}
var _shards: Array = []      ## {p, v, born, life, size, rot, spin, col, g}
var _rings: Array = []       ## {p, born, life, r0, r1, f}
var _speed: Array = []
var _shock_pulses: Array = []
var _x_center := Vector2.INF
var _hits: int = 0
var _hit_pop: float = 0.0
var _dmg_total: float = 0.0
var _cam: Camera2D
var _zoom0 := Vector2.ZERO
var _center0 := Vector2.INF
var _crowd0 := Vector2.INF       ## 起手时屏幕里敌人的中心（连斩镜头跟它）
var _pass_zoom: float = 1.0      ## 连斩镜头推近倍数（按敌群宽度自适应，最多 1+ZOOM_PASS）
var _zoom_punch: float = 0.0
var _glow0: float = -1.0
var _title_tex: Texture2D
var _seal_tex: Texture2D
var _cutin_tex: Texture2D
var _cut_tex: Texture2D
var _cut_region := Rect2()
var _cut_flip := false

var _grade_copy: BackBufferCopy
var _grade: Node2D
var _grade_mat: ShaderMaterial
var _split_copy: BackBufferCopy
var _split: Node2D
var _split_mat: ShaderMaterial
var _lo: Node2D
var _hi: Node2D
var _hi_add: Node2D          ## 角色前面、加法混合：巨斩光晕、交点星芒、冲击环
var _ui: CanvasLayer
var _shock: ColorRect        ## 全屏后期：在 _ui 里最先画（黑边、UI 不受影响）
var _shock_mat: ShaderMaterial
var _ui_flash: Node2D        ## 全屏白闪 / 紫闪 / 全黑刀缝（后期之上、黑边之下）
var _ui_draw: Node2D         ## 集中线、切入带、速度线
var _ui_sil: Node2D          ## 立绘
var _ui_top: Node2D          ## 题字、印章、黑边、计数
var _font: Font


func _ready() -> void:
	z_index = 20
	process_priority = 10
	rng.randomize()
	_grade_copy = _copy(-3)
	_grade = _layer(-3, GRADE_SHADER)     # 地形（−70）之后、斩线（−2）/ 残影（−1）/ 角色（0）之前
	_grade_mat = _grade.material as ShaderMaterial
	_grade.draw.connect(func(): _grade.draw_rect(Rect2(-VIEW * 0.7, VIEW * 1.4), Color.WHITE))
	_split_copy = _copy(44)
	_split = _layer(45, SPLIT_SHADER)
	_split_mat = _split.material as ShaderMaterial
	_split.draw.connect(func(): _split.draw_rect(Rect2(-VIEW * 0.7, VIEW * 1.4), Color.WHITE))
	_lo = _world(-2)
	_lo.draw.connect(_draw_lo)
	_hi = _world(18)
	_hi.draw.connect(_draw_hi)
	_hi_add = _world(19)
	var am := CanvasItemMaterial.new()
	am.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_hi_add.material = am
	_hi_add.draw.connect(_draw_hi_add)
	_ui = CanvasLayer.new()
	_ui.layer = 11                        # HUD 是 10
	add_child(_ui)
	_shock = ColorRect.new()
	_shock.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shock_mat = ShaderMaterial.new()
	_shock_mat.shader = SHOCK_SHADER
	_shock.material = _shock_mat
	_shock.visible = false
	_ui.add_child(_shock)
	_ui_flash = Node2D.new()
	_ui.add_child(_ui_flash)
	_ui_flash.draw.connect(_draw_ui_flash)
	_ui_draw = Node2D.new()
	_ui.add_child(_ui_draw)
	_ui_draw.draw.connect(_draw_ui)
	_ui_sil = Node2D.new()
	var sm := ShaderMaterial.new()
	sm.shader = SIL_SHADER
	_ui_sil.material = sm
	_ui_sil.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_ui.add_child(_ui_sil)
	_ui_sil.draw.connect(_draw_ui_sil)
	_ui_top = Node2D.new()
	_ui_top.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_ui.add_child(_ui_top)
	_ui_top.draw.connect(_draw_ui_top)
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "PingFang SC", "sans-serif"])
	sf.font_weight = 900
	sf.font_italic = true
	_font = sf
	_title_tex = _load_png(TITLE_PATH)
	_seal_tex = _load_png(SEAL_PATH)
	_cutin_tex = _load_png(CUTIN_PATH)


func _layer(z: int, shader: Shader = null) -> Node2D:
	var n := Node2D.new()
	n.z_as_relative = false
	n.z_index = z
	n.visible = false
	if shader != null:
		var m := ShaderMaterial.new()
		m.shader = shader
		n.material = m
	add_child(n)
	return n


func _world(z: int) -> Node2D:
	var n := Node2D.new()
	n.top_level = true
	n.z_as_relative = false
	n.z_index = z
	add_child(n)
	return n


func _copy(z: int) -> BackBufferCopy:
	var b := BackBufferCopy.new()
	b.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	b.z_as_relative = false
	b.z_index = z
	b.visible = false
	add_child(b)
	return b


static func _load_png(path: String) -> Texture2D:
	if not FileAccess.file_exists(path):
		return null
	var img := Image.new()
	if img.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
		return null
	return ImageTexture.create_from_image(img)


# ---------------------------------------------------------------- 对外

## ① 起势（主角 ult_started；关卡先把 anchor 摆到当前镜头中心再调）
func begin() -> void:
	clear()
	_phase = 1
	_cam = get_viewport().get_camera_2d()
	_zoom0 = _cam.zoom if _cam != null else Vector2.ZERO
	_center0 = anchor.global_position if is_instance_valid(anchor) else Vector2.INF
	# 敌群中心和宽度：连斩时镜头跟着敌群、能装下所有人就尽量推近
	var xs: Array = []
	var sum := Vector2.ZERO
	for sh in get_tree().get_nodes_in_group(&"shade"):
		if sh.has_method("is_alive") and sh.is_alive() and _center0 != Vector2.INF and absf(sh.global_position.x - _center0.x) < VIEW.x * 0.5:
			xs.append(sh.global_position.x)
			sum += sh.global_position
	if _ok():
		xs.append(player.global_position.x)
	_crowd0 = sum / float(xs.size() - (1 if _ok() else 0)) if xs.size() > (1 if _ok() else 0) else (player.global_position if _ok() else _center0)
	var span: float = (xs.max() - xs.min()) if xs.size() > 1 else 0.0
	_pass_zoom = clampf(VIEW.x / maxf(span + 700.0, 1.0), 1.0, 1.0 + ZOOM_PASS)
	if is_instance_valid(fx):
		_glow0 = float(fx.glow_base)
		fx.glow_base = maxf(_glow0, 1.35)
		if _ok():
			fx.spawn_launch(_feet())
	if _ok():
		# 脚下光圈由外往里收（聚气）
		for i in 3:
			_rings.append({"p": _feet(), "born": float(i) * 8.0, "life": 20.0, "r0": 300.0, "r1": 24.0, "f": true})


func clear() -> void:
	_restore_camera()
	if is_instance_valid(fx) and _glow0 >= 0.0:
		fx.glow_base = _glow0
	_glow0 = -1.0
	_phase = 0
	_f = 0.0
	_since_burst = 0.0
	_grade_k = 0.0
	_clicked = false
	_glinted = false
	_turned = false
	_flash = 0.0
	_vflash = 0.0
	_trails.clear()
	_marks.clear()
	_bursts.clear()
	_shards.clear()
	_rings.clear()
	_speed.clear()
	_shock_pulses.clear()
	_x_center = Vector2.INF
	_hits = 0
	_hit_pop = 0.0
	_dmg_total = 0.0
	_zoom_punch = 0.0
	_cut_tex = null
	_split.visible = false
	_split_copy.visible = false
	_grade.visible = false
	_grade_copy.visible = false
	_shock.visible = false
	_hud_k = 1.0
	_apply_hud()


func busy() -> bool:
	return _phase != 0


## ③ 第 k 斩（共 n 斩）：主角从 from 瞬移到 to；穿过的影在 point（没有影 = Vector2.INF）
func cut(from: Vector2, to: Vector2, point: Vector2, node: Node2D, k: int, n: int) -> void:
	var px := _px()
	var dir := signf(to.x - from.x) if not is_equal_approx(to.x, from.x) else 1.0
	var last := k == n - 1
	# 斩线：穿过被砍的影（没有影就在路线中点），角度在 ±20° / ±55° 之间交替，越砍越交错
	var mid: Vector2 = point if point != Vector2.INF else (from + to) * 0.5 + Vector2(0, -54.0 * px)
	var steep := k % 2 == 1
	var ang := deg_to_rad(55.0 if steep else 20.0) * (1.0 if (k / 2) % 2 == 0 else -1.0)
	var tdir := Vector2(dir * cos(ang), sin(ang))
	var half_len := maxf(absf(to.x - from.x) * 0.55, 260.0 * px) * (0.7 if steep else 1.0)
	var a := mid - tdir * half_len
	var b := mid + tdir * half_len
	var late := float(k) / float(maxi(n - 1, 1))
	_trails.append({"a": a, "b": b, "born": _f, "w": TRAIL_W * (0.85 + 0.35 * late) * (1.5 if last else 1.0)})
	_speed.append({"born": _f, "dir": dir, "seed": rng.randi()})
	_hits += 1
	_hit_pop = 1.0
	_zoom_punch = 0.03 + 0.02 * late + (0.04 if last else 0.0)
	_shock_pulses.append({"born": _f, "s": 0.2 + 0.2 * late + (0.3 if last else 0.0), "c": _screen_uv(to + Vector2(0, -50.0 * px)), "life": 7.0})
	if k >= n - 3:
		_vflash = 2.0
	if not is_instance_valid(fx):
		return
	var spr: Sprite2D = player.get_node_or_null("Visual/ActorSprite") if _ok() else null
	if spr != null:
		# 5 个残影：离终点越远越暗（深蓝 → 紫 → 白）
		var p1 := from.lerp(to, 0.4)
		var p2 := from.lerp(to, 0.75)
		fx.ghost_line(spr, from, p1, 2, Color("3b3f9e"))
		fx.ghost_line(spr, p1, p2, 2, VIO)
		fx.ghost_line(spr, p2, to.lerp(p2, 0.12), 1, WHITE)
	if point != Vector2.INF and node != null:
		var mang := rng.randf_range(0.45, 1.1) * (1.0 if rng.randf() < 0.5 else -1.0)
		_marks.append({"node": node, "off": point - node.global_position + Vector2(rng.randf_range(-10, 10), rng.randf_range(-16, 16)) * px,
			"ang": mang, "len": MARK_LEN * rng.randf_range(0.8, 1.25), "born": _f})
		fx.spawn_hit(point, 0.55 + 0.4 * late + (0.4 if last else 0.0), false, Vector2(dir, 0), true, &"dash_slash")
		for i in 6:
			_shard(point, Vector2(dir * rng.randf_range(140, 420), rng.randf_range(-280, -60)) * px, rng.randf_range(14, 26), 0.0)


## ⑥ 全屏巨斩（主角 ult_hit）。hit = [{node, pt, cuts, dmg}]
func burst(hit: Array) -> void:
	_phase = 2
	_since_burst = 0.0
	_flash = 2.0
	if is_instance_valid(fx):
		fx.impact_frame(1.0)
	if _x_center == Vector2.INF:
		_x_center = _crowd_center()
	_shock_pulses.append({"born": _f, "s": 1.0, "c": _screen_uv(_x_center), "wave": true, "life": 28.0})
	_dmg_total = 0.0
	var px := _px()
	for h in hit:
		_dmg_total += float(h.get("dmg", 0.0))
		var pt: Vector2 = h.pt
		var rays: Array = []
		for m in _marks:
			if m.node == h.node:
				rays.append([float(m.ang), float(m.len) * 2.8 * px])
		for i in 4:
			rays.append([rng.randf_range(-PI, PI), rng.randf_range(70.0, 130.0) * px])
		_bursts.append({"pt": pt, "born": BURST_HOLD, "rays": rays, "node": h.node, "done": false, "cuts": int(h.get("cuts", 1))})
	for i in 2:
		var gp := Vector2(_x_center.x, _feet().y if _ok() else _x_center.y + 120.0 * px)
		_rings.append({"p": gp, "born": _f + BURST_HOLD + float(i) * 4.0, "life": 14.0, "r0": 40.0, "r1": 620.0 - 200.0 * float(i), "f": false})
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
	_tick_bursts()
	_flash = maxf(_flash - df, 0.0)
	_vflash = maxf(_vflash - df, 0.0)
	_hit_pop = maxf(_hit_pop - df / 6.0, 0.0)
	_zoom_punch = move_toward(_zoom_punch, 0.0, df * 0.012)
	_trails = _trails.filter(func(t): return _f - float(t.born) < TRAIL_LIFE)
	_bursts = _bursts.filter(func(bs): return _since_burst - float(bs.born) < BURST_LIFE)
	_marks = _marks.filter(func(m): return is_instance_valid(m.node))
	_speed = _speed.filter(func(s): return _f - float(s.born) < 5.0)
	_shock_pulses = _shock_pulses.filter(func(s): return _f - float(s.born) < float(s.life))
	_rings = _rings.filter(func(r): return _f - float(r.born) < float(r.life))
	_tick_shards(delta)
	_update_camera()
	_update_grade(df)
	_update_split()
	_update_shock()
	_update_hud(df)
	if _phase == 2 and _since_burst > 62.0 and _bursts.is_empty() and _shards.is_empty() and not (_ok() and player.is_ult()):
		var keep := _hud_k
		clear()
		_hud_k = keep
		_apply_hud()
	_lo.queue_redraw()
	_hi.queue_redraw()
	_hi_add.queue_redraw()
	_ui_flash.queue_redraw()
	_ui_draw.queue_redraw()
	_ui_sil.queue_redraw()
	_ui_top.queue_redraw()


func _tick_cues() -> void:
	if not _ok() or _phase == 0:
		return
	var px := _px()
	var charge := _pv("ult_charge_frames", 30.0)
	# 起势：身上冒上升光粒
	if _phase == 1 and _f < charge and int(_f) % 2 == 0 and _shards.size() < 160:
		for i in 3:
			var p := player.global_position + Vector2(rng.randf_range(-70, 70), rng.randf_range(-20, 80)) * px
			_shards.append({"p": p, "v": Vector2(rng.randf_range(-20, 20), rng.randf_range(-260, -140)) * px, "born": _f,
				"life": rng.randf_range(18, 28), "size": rng.randf_range(5.0, 9.0), "rot": 0.785, "spin": 0.0,
				"col": VIO_L if rng.randf() < 0.6 else WHITE, "g": -0.15})
	if not _glinted and _f >= charge - 6.0:
		_glinted = true
		if is_instance_valid(fx):
			fx.spawn_parry(player.global_position + Vector2(float(player.facing) * 70.0, -70.0) * px, Vector2(player.facing, 0))
	if _cut_tex == null and _f >= charge:
		var spr: Sprite2D = player.get_node_or_null("Visual/ActorSprite")
		if spr != null and spr.texture != null:
			_cut_tex = spr.texture
			_cut_region = spr.region_rect if spr.region_enabled else Rect2(Vector2.ZERO, spr.texture.get_size())
			var img := spr.texture.get_image()
			if img != null:
				var used := Rect2(img.get_used_rect())
				if used.size.x > 4.0 and used.size.y > 4.0:
					_cut_region = used.intersection(_cut_region) if spr.region_enabled else used
			_cut_flip = spr.global_transform.x.x < 0.0
	# 残心开始：背对敌群；记下巨斩交点
	var still0 := _pv_last_pass() + 6.0
	if not _turned and _f >= still0:
		_turned = true
		_x_center = _crowd_center()
		var away := 1 if player.global_position.x >= _x_center.x else -1
		if player.has_method("_set_facing"):
			player._set_facing(away)
		# 残心：别和敌人叠在一起——离最近的影太近就往外再闪一步
		var near := INF
		for m in _marks:
			if is_instance_valid(m.node):
				near = minf(near, absf((m.node as Node2D).global_position.x - player.global_position.x))
		if near < 150.0 * px and player.has_method("ult_dash_by"):
			player.ult_dash_by(float(away) * (170.0 * px - near))
	var click := _pv("ult_click_frame", 140.0)
	if not _clicked and _f >= click:
		_clicked = true
		var hp := player.global_position + Vector2(-float(player.facing) * 10.0, -40.0) * px
		sheathed.emit(hp)
		if is_instance_valid(fx):
			fx.spawn_block(hp, Vector2(-player.facing, 0))


## 巨斩后定格 BURST_HOLD 帧，然后每只影爆开：命中爆闪 + 碎片
func _tick_bursts() -> void:
	if _phase != 2:
		return
	var px := _px()
	for bs in _bursts:
		if bs.done or _since_burst < float(bs.born):
			continue
		bs.done = true
		var pt: Vector2 = bs.pt
		if is_instance_valid(bs.node):
			popped.emit(bs.node)
		if is_instance_valid(_cam) and _cam.has_method("add_shake"):
			_cam.add_shake(6.0)
		for i in 20:
			var ang := rng.randf_range(-PI, 0.2)
			_shard(pt, Vector2.from_angle(ang) * rng.randf_range(200, 680) * px, rng.randf_range(30, 60), 0.0)
		if is_instance_valid(fx):
			var dir := Vector2(signf(pt.x - _x_center.x), 0.0)
			fx.spawn_hit(pt, 1.3 + 0.1 * float(bs.cuts), true, dir, false, &"charge_1")


func _shard(p: Vector2, v: Vector2, life: float, delay: float) -> void:
	var cols := [WHITE, VIO_L, VIO, VIO_L, INK]
	_shards.append({"p": p, "v": v, "born": _f + delay, "life": life, "size": rng.randf_range(4.0, 12.0),
		"rot": rng.randf_range(0, TAU), "spin": rng.randf_range(-14.0, 14.0), "col": cols[rng.randi() % cols.size()], "g": 1.0})


func _tick_shards(delta: float) -> void:
	var px := _px()
	var keep: Array = []
	for s in _shards:
		var age := _f - float(s.born)
		if age < 0.0:
			keep.append(s)
			continue
		if age >= float(s.life):
			continue
		s.v = (s.v as Vector2) * pow(0.12, delta) + Vector2(0, 900.0 * px * float(s.g)) * delta
		s.p = (s.p as Vector2) + (s.v as Vector2) * delta
		s.rot = float(s.rot) + float(s.spin) * delta
		keep.append(s)
	_shards = keep


## 镜头：起势推近并移向主角 → 切入保持 → 连斩推近跟着主角 → 残心慢慢推向主角 → 巨斩回到敌群中心并拉远一下
func _update_camera() -> void:
	if not is_instance_valid(_cam) or _zoom0 == Vector2.ZERO or _phase == 0:
		return
	var charge := _pv("ult_charge_frames", 30.0)
	var ps := _pv("ult_pass_start", 66.0)
	var still0 := _pv_last_pass() + 6.0
	var slit0 := _pv("ult_hit_frame", 154.0) - SLIT_FRAMES
	var mult := 1.0
	var toward := 0.0
	var target := _center0
	if _phase == 1:
		if _f < ps:
			var k := clampf(_f / charge, 0.0, 1.0)
			mult = 1.0 + ZOOM_IN * (1.0 - pow(1.0 - k, 3.0))
			toward = 0.55 * k
		elif _f < still0:
			mult = _pass_zoom + _zoom_punch
			if _crowd0 != Vector2.INF:
				target.x = lerpf(_crowd0.x, player.global_position.x if _ok() else _crowd0.x, 0.25)
		elif _f < slit0:
			var k := clampf((_f - still0) / maxf(slit0 - still0, 1.0), 0.0, 1.0)
			mult = lerpf(_pass_zoom, 1.0 + ZOOM_STILL, smoothstep(0.0, 1.0, k))
			toward = 0.75
		else:
			mult = 1.0
			if _x_center != Vector2.INF and _center0 != Vector2.INF:
				target = Vector2(lerpf(_center0.x, _x_center.x, 0.5), _center0.y)
	else:
		mult = 1.0 - 0.06 * (1.0 - smoothstep(BURST_HOLD, BURST_HOLD + 18.0, _since_burst))
		if _x_center != Vector2.INF and _center0 != Vector2.INF:
			target = Vector2(lerpf(_center0.x, _x_center.x, 0.5), _center0.y)
	_cam.zoom = _zoom0 * mult
	# 推近时把镜头压低：脚底放到屏幕 78% 高度（不推近时 offset = 0）
	if _ok():
		var vs := get_viewport().get_visible_rect().size
		var z := _cam.zoom.y
		var want_c := _feet().y - 0.28 * vs.y / maxf(z, 0.01)
		var k := clampf((mult - 1.0) / 0.25, 0.0, 1.0)
		if _cam.get("base_offset") != null:
			_cam.base_offset = Vector2(0.0, (want_c - _cam.global_position.y) * k)
	if is_instance_valid(anchor) and _center0 != Vector2.INF:
		if toward > 0.0 and _ok():
			target.x = lerpf(_center0.x, player.global_position.x, toward)
		anchor.global_position = target


func _restore_camera() -> void:
	if is_instance_valid(_cam) and _zoom0 != Vector2.ZERO:
		_cam.zoom = _zoom0
		if _cam.get("base_offset") != null:
			_cam.base_offset = Vector2.ZERO
	_zoom0 = Vector2.ZERO
	if is_instance_valid(anchor) and _center0 != Vector2.INF:
		anchor.global_position = _center0
	_center0 = Vector2.INF


func _update_grade(df: float) -> void:
	var want := 0.0
	var dim := 0.0
	if _phase == 1:
		want = 1.0
		var still0 := _pv_last_pass() + 6.0
		dim = 0.6 * smoothstep(still0, still0 + 8.0, _f)
	elif _phase == 2:
		want = 1.0 - smoothstep(30.0, 48.0, _since_burst)
		dim = 0.35 * (1.0 - smoothstep(BURST_HOLD, 30.0, _since_burst))
	_grade_k = move_toward(_grade_k, want, df * (0.16 if want > _grade_k else 1.0))
	var on := _grade_k > 0.002
	_grade.visible = on
	_grade_copy.visible = on
	if on:
		_grade_mat.set_shader_parameter("amount", _grade_k)
		_grade_mat.set_shader_parameter("dim", dim)
		_grade.queue_redraw()


## 巨斩后画面沿 X 的第一道斩线错开 20px，停 6 帧再合上
func _update_split() -> void:
	var k := 0.0
	if _phase == 2 and _x_center != Vector2.INF:
		k = smoothstep(0.0, 2.0, _since_burst) * (1.0 - smoothstep(8.0, 12.0, _since_burst))
	var on := k > 0.02
	_split.visible = on
	_split_copy.visible = on
	if on:
		var nrm := Vector2.from_angle(-X_ANG).orthogonal()
		var big := 60000.0
		_split_mat.set_shader_parameter("center", _x_center + nrm * big)
		_split_mat.set_shader_parameter("radius", big)
		_split_mat.set_shader_parameter("amount", 20.0 * k)
		_split_mat.set_shader_parameter("dir", 1.0)
		_split_mat.set_shader_parameter("seam", 2.0 * _px() * k)
		_split.queue_redraw()


## 后期：色差冲击（每斩小、巨斩大 + 冲击波）；巨斩 2～5 帧负片，之后高对比回落
func _update_shock() -> void:
	var s := 0.0
	var c := Vector2(0.5, 0.5)
	var wave_r := -1.0
	var wave_amp := 0.0
	for p in _shock_pulses:
		var age := _f - float(p.born)
		var life := float(p.life)
		var v := float(p.s) * pow(1.0 - clampf(age / (18.0 if p.has("wave") else life), 0.0, 1.0), 2.0)
		if v > s:
			s = v
			c = p.c
		if p.has("wave"):
			wave_r = 0.05 + age / life * 1.3
			wave_amp = 0.024 * (1.0 - clampf(age / life, 0.0, 1.0))
			c = p.c
	var inv := 0.0
	var con := 1.0
	var tint := Vector3.ONE
	if _phase == 2:
		if _since_burst >= 2.0 and _since_burst < 5.0:
			inv = 1.0          # 双色：黑底 + 白剪影（着色器里按亮度阈值）
		else:
			con = lerpf(1.35, 1.0, smoothstep(5.0, 16.0, _since_burst))
	var on := s > 0.01 or wave_r > 0.0 or inv > 0.0 or absf(con - 1.0) > 0.01
	_shock.visible = on
	if on:
		var vs := get_viewport().get_visible_rect().size
		_shock_mat.set_shader_parameter("center", c)
		_shock_mat.set_shader_parameter("strength", s)
		_shock_mat.set_shader_parameter("wave_r", wave_r)
		_shock_mat.set_shader_parameter("wave_amp", wave_amp)
		_shock_mat.set_shader_parameter("aspect", vs.x / maxf(vs.y, 1.0))
		_shock_mat.set_shader_parameter("invert", inv)
		_shock_mat.set_shader_parameter("contrast", con)
		_shock_mat.set_shader_parameter("tint", tint)


func _update_hud(df: float) -> void:
	var want := 1.0
	if _phase == 1 or (_phase == 2 and _since_burst < 56.0):
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


# ---------------------------------------------------------------- 画（世界）

func _draw_lo() -> void:
	var px := _px()
	for t in _trails:
		var age := _f - float(t.born)
		var k := clampf(age / TRAIL_LIFE, 0.0, 1.0)
		var w: float = float(t.w) * px * (1.0 if age < 2.0 else 1.0 - k * 0.85)
		var a: Vector2 = t.a
		var b: Vector2 = t.b
		a = a.lerp(b, smoothstep(0.15, 1.0, k))
		for layer in [[VIO_D, 1.0], [VIO, 0.72], [VIO_L, 0.48], [WHITE, 0.26]]:
			var c: Color = layer[0]
			c.a = 1.0 if age < 3.0 else 1.0 - smoothstep(0.55, 1.0, k)
			_lens(_lo, a, b, w * float(layer[1]), c)
	for r in _rings:
		var age := _f - float(r.born)
		if age < 0.0:
			continue
		var k := clampf(age / float(r.life), 0.0, 1.0)
		var e := 1.0 - pow(1.0 - k, 3.0)
		var rad: float = lerpf(float(r.r0), float(r.r1), e) * px
		var w := (10.0 if not r.f else 7.0) * px * (1.0 - k * 0.7)
		# 发光环：三层（外宽淡、内细亮），紫白
		var base := Color(VIO_L if r.f else Color("d8ccff"))
		var a0 := (0.95 if r.f else 0.9) * (1.0 - k * k)
		_ellipse(_lo, r.p, rad, rad * 0.16, w * 3.2, Color(VIO, a0 * 0.25))
		_ellipse(_lo, r.p, rad, rad * 0.16, w * 1.8, Color(base, a0 * 0.5))
		_ellipse(_lo, r.p, rad, rad * 0.16, w * 0.7, Color(1, 1, 1, a0))


## 加法混合层：巨斩外圈辉光（70～90px 衰减）、交点四芒星 + 一圈径向光环
func _draw_hi_add() -> void:
	if _x_center == Vector2.INF or _phase != 2:
		return
	var px := _px()
	var age := _since_burst
	if age >= X_LIFE + 20.0:
		return
	var vlen := VIEW.x * 0.8
	var fade := 1.0 - smoothstep(10.0, X_LIFE + 20.0, age)
	for i in 2:
		var dir := Vector2.from_angle(-X_ANG if i == 0 else X_ANG)
		var a := _x_center - dir * vlen
		var b := _x_center + dir * vlen
		for g in [[90.0, 0.10], [62.0, 0.14], [40.0, 0.2]]:
			_lens(_hi_add, a, b, float(g[0]) * px, Color(VIO.r, VIO.g, VIO.b, float(g[1]) * fade))
	# 交点：四芒星（一拍二变形）+ 光环
	var k := clampf(age / 18.0, 0.0, 1.0)
	var star := (160.0 + 60.0 * float(int(age / 2.0) % 2)) * px * (1.0 - k * 0.6)
	var sa := 1.0 - smoothstep(6.0, 18.0, age)
	for j in 4:
		var d := Vector2.from_angle(float(j) * PI * 0.5 + 0.12)
		_lens(_hi_add, _x_center - d * star, _x_center + d * star, 14.0 * px * (1.0 - k * 0.5), Color(1.0, 0.97, 1.0, 0.9 * sa))
	var rr := lerpf(40.0, 420.0, 1.0 - pow(1.0 - clampf(age / 14.0, 0.0, 1.0), 3.0)) * px
	_hi_add.draw_arc(_x_center, rr, 0.0, TAU, 64, Color(0.8, 0.72, 1.0, 0.6 * (1.0 - clampf(age / 14.0, 0.0, 1.0))), 10.0 * px)


func _draw_hi() -> void:
	var px := _px()
	var click := _pv("ult_click_frame", 140.0)
	for m in _marks:
		var node: Node2D = m.node
		var c: Vector2 = node.global_position + (m.off as Vector2)
		var age := _f - float(m.born)
		var grow := clampf((age + 1.0) / 3.0, 0.0, 1.0)
		# 刀痕自发光：收刀“咔”时一亮，巨斩前 6 帧再脉动一次
		var pulse := 1.0
		if _f >= click:
			pulse += 0.8 * (1.0 - clampf((_f - click) / 8.0, 0.0, 1.0))
		var hit := _pv("ult_hit_frame", 154.0)
		pulse += 0.6 * (1.0 - clampf(absf(_f - (hit - 6.0)) / 3.0, 0.0, 1.0))
		var half := Vector2.from_angle(float(m.ang)) * float(m.len) * px * 0.5 * grow * (1.0 + 0.15 * (pulse - 1.0))
		var w := (5.0 if age < 3.0 else 3.2) * px * pulse
		_lens(_hi, c - half * 1.15, c + half * 1.15, w * 3.2, Color(VIO, 0.35))
		_lens(_hi, c - half, c + half, w * 1.9, Color(VIO, 0.9))
		_lens(_hi, c - half, c + half, w, Color(WHITE, 1.0))
	# 全屏巨斩（实体部分）：深紫边 + 淡紫 #C9B8FF 中层 + 3～4px 纯白芯；30 帧后留一道细残光
	if _x_center != Vector2.INF and _phase == 2 and _since_burst < X_LIFE + 20.0:
		var vlen := VIEW.x * 0.8
		for i in 2:
			var dir := Vector2.from_angle(-X_ANG if i == 0 else X_ANG)
			var age := _since_burst
			var a := _x_center - dir * vlen
			var b := _x_center + dir * vlen
			var grow := lerpf(0.5, 1.0, smoothstep(0.0, 2.0, age))
			var thin := 1.0 if age < 12.0 else lerpf(1.0, 0.3, smoothstep(12.0, X_LIFE, age))
			var fade := 1.0 - smoothstep(X_LIFE, X_LIFE + 20.0, age)
			_lens(_hi, a, b, 30.0 * px * grow * thin, Color(VIO_D, 0.85 * fade))
			_lens(_hi, a, b, 22.0 * px * grow * thin, Color("c9b8ff", fade))
			_lens(_hi, a, b, 4.0 * px * maxf(thin, 0.6), Color(1, 1, 1, fade))
	for bs in _bursts:
		if not bs.done:
			continue
		var age := _since_burst - float(bs.born)
		var k := clampf(age / BURST_LIFE, 0.0, 1.0)
		var p: Vector2 = bs.pt
		for r in bs.rays:
			var dir := Vector2.from_angle(float(r[0]))
			var l: float = float(r[1]) * (0.35 + 0.65 * smoothstep(0.0, 0.25, k))
			var a := p + dir * l * smoothstep(0.3, 1.0, k)
			var b := p + dir * l
			var w := 8.0 * px * (1.0 - k * 0.8)
			_lens(_hi, a, b, w * 1.7, Color(VIO, 1.0 - smoothstep(0.6, 1.0, k)))
			_lens(_hi, a, b, w, Color(WHITE, 1.0 - smoothstep(0.5, 1.0, k)))
			_lens(_hi, p - dir * l * 0.6 * (1.0 - k), p - dir * l * 0.3 * (1.0 - k), w * 0.6, Color(VIO_L, 1.0 - k))
	for s in _shards:
		var age := _f - float(s.born)
		if age < 0.0:
			continue
		var k := clampf(age / float(s.life), 0.0, 1.0)
		var sz: float = float(s.size) * px * (1.0 - k * 0.6)
		var rot: float = s.rot
		var p: Vector2 = s.p
		var pts := PackedVector2Array([p + Vector2.from_angle(rot) * sz, p + Vector2.from_angle(rot + 2.5) * sz * 0.5,
			p + Vector2.from_angle(rot + 3.6) * sz * 0.7])
		var col: Color = s.col
		col.a = 1.0 - smoothstep(0.6, 1.0, k)
		_hi.draw_colored_polygon(pts, col)


# ---------------------------------------------------------------- 画（屏幕）

## 全屏闪光层（后期之上、黑边和 UI 之下）：紫闪、巨斩纯白 2 帧、刀缝前全黑
func _draw_ui_flash() -> void:
	var vs := get_viewport().get_visible_rect().size
	if _vflash > 0.0:
		_ui_flash.draw_rect(Rect2(Vector2.ZERO, vs), Color(VIO, 0.18 * _vflash / 2.0))
	if _phase == 2 and _flash > 0.0:
		_ui_flash.draw_rect(Rect2(Vector2.ZERO, vs), Color(1, 1, 1, 1))
	# ⑤ 刀缝：全黑 + X 的两道刀缝（就是马上炸开的两臂）
	if _phase == 1:
		var d := _pv("ult_hit_frame", 154.0) - _f
		if d > 0.0 and d <= SLIT_FRAMES:
			_ui_flash.draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 1))
			if _x_center == Vector2.INF:
				_x_center = _crowd_center()
			var c := get_viewport().get_canvas_transform() * _x_center
			var t := SLIT_FRAMES - d          # 0 → 9
			var reach := vs.length()
			for i in 2:
				var t0 := 0.0 if i == 0 else 6.0
				if t < t0:
					continue
				var k := clampf((t - t0 + 1.0) / 4.0, 0.0, 1.0)
				var ang := -X_ANG if i == 0 else X_ANG
				var dir := Vector2.from_angle(ang)
				var half := reach * 0.5 * (0.35 + 0.65 * k)
				var w := lerpf(1.0, 3.0, k)
				_lens(_ui_flash, c - dir * half, c + dir * half, w * 7.0, Color(VIO, 0.5))
				_lens(_ui_flash, c - dir * half, c + dir * half, w * 3.0, Color(VIO_L, 0.9))
				_lens(_ui_flash, c - dir * half, c + dir * half, w, Color.WHITE)


func _draw_ui() -> void:
	var vs := get_viewport().get_visible_rect().size
	var charge := _pv("ult_charge_frames", 30.0)
	var ps := _pv("ult_pass_start", 66.0)
	# ① 集中线：56 根汇向主角，缓慢旋转，白紫两色、渐细
	if _phase == 1 and _f < charge + 8.0 and _ok():
		var k := clampf(_f / charge, 0.0, 1.0)
		var fade := 1.0 - smoothstep(charge, charge + 8.0, _f)
		if fade > 0.0:
			var c: Vector2 = get_viewport().get_canvas_transform() * (player.global_position + Vector2(0.0, -30.0 * _px()))
			var r := RandomNumberGenerator.new()
			r.seed = int(_f / 3.0) * 7919 + 13
			var outer := vs.length() * 0.75
			var inner := lerpf(outer * 0.7, 120.0, k)
			var spin := _f * 0.012
			for i in 56:
				var d := Vector2.from_angle(float(i) / 56.0 * TAU + r.randf_range(-0.05, 0.05) + spin)
				var w := r.randf_range(2.0, 6.0)
				var p0 := c + d * outer
				var p1 := c + d * (inner + r.randf_range(0.0, 160.0))
				var n := d.orthogonal() * w
				var col := Color(0.95, 0.94, 1.0) if i % 2 == 0 else VIO_L
				_ui_draw.draw_colored_polygon(PackedVector2Array([p0 - n, p0 + n, p1]), Color(col, 0.75 * fade * (0.3 + 0.7 * k)))
	# ② 切入带：副带（错开、亮紫）+ 主带（深紫→亮紫渐变）+ 流光 + 亮边
	var band := _band_rect(vs)
	if band.x > 0.0:
		_ui_draw.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.0, 0.0, 0.02, 0.8 * band.x))
		# 副带：在主带下方错开，反向慢慢滑
		var sub := _band_poly(vs, band.y, 40.0, CUT_H * 0.5 + 18.0)
		var sax := (sub[1] - sub[0]).normalized() * (-band.z * 1.6)
		for q in 4:
			sub[q] += sax
		_ui_draw.draw_colored_polygon(sub, Color(VIO, 0.85 * band.x))
		var sub2 := _band_poly(vs, band.y, 10.0, -CUT_H * 0.5 - 14.0)
		_ui_draw.draw_colored_polygon(sub2, Color(VIO_L, 0.7 * band.x))
		var poly := _band_poly(vs, band.y)
		var cols := PackedColorArray([Color("140b29"), Color("24154f"), Color("4a33a0"), Color("1a0f38")])
		_ui_draw.draw_polygon(poly, cols)
		var r2 := RandomNumberGenerator.new()
		r2.seed = 4242
		var axis := (poly[1] - poly[0]).normalized()
		# 网点纹理：带子下半部分一排排渐小的圆点（漫画网点）
		var dn := (poly[3] - poly[0]).normalized()
		for row in 6:
			var v := 0.62 + float(row) * 0.065
			var rad := lerpf(1.2, 4.2, float(row) / 5.0)
			var step := 16.0
			var start: Vector2 = poly[0].lerp(poly[3], v)
			var off := fmod(_f * 0.8, step)
			var count := int(vs.x * 1.3 / step)
			var p0 := start + axis * (vs.x * 1.6 - vs.x * 0.15 + off) - dn * 0.0
			for j in count:
				var c := p0 + axis * (float(j) * step + (step * 0.5 if row % 2 == 1 else 0.0))
				if c.x < -10.0 or c.x > vs.x + 10.0:
					continue
				_ui_draw.draw_circle(c, rad, Color(0.06, 0.03, 0.12, 0.55))
		# 流光：斜向长光条，沿带子流动，三层（宽淡 / 中 / 细亮）
		for i in 22:
			var v := r2.randf_range(0.06, 0.6)
			var speed := r2.randf_range(60.0, 140.0)
			var len := r2.randf_range(160.0, 520.0)
			var u := fmod(r2.randf() * 3000.0 - _f * speed, 3000.0) - 800.0
			var base: Vector2 = poly[0].lerp(poly[3], v) + axis * u
			var wv := r2.randf_range(3.0, 7.0)
			_lens(_ui_draw, base, base + axis * len, wv * 2.4, Color(VIO, 0.25))
			_lens(_ui_draw, base, base + axis * len, wv, Color(VIO_L, r2.randf_range(0.5, 0.85)))
			_lens(_ui_draw, base, base + axis * len * 0.8, wv * 0.35, Color(1, 1, 1, 0.8))
		_ui_draw.draw_line(poly[0], poly[1], Color(VIO_L, 0.95), 3.0)
		_ui_draw.draw_line(poly[3], poly[2], Color(VIO_L, 0.95), 3.0)
	# ③ 千刃：全屏横向速度线
	for s in _speed:
		var age := _f - float(s.born)
		var r3 := RandomNumberGenerator.new()
		r3.seed = int(s.seed)
		var a := 1.0 - age / 5.0
		for i in 34:
			var y := r3.randf_range(vs.y * 0.42, vs.y * 0.9)
			var len := r3.randf_range(180.0, 680.0)
			var x := r3.randf_range(-200.0, vs.x) + float(s.dir) * age * 280.0
			_lens(_ui_draw, Vector2(x, y), Vector2(x + len, y), r3.randf_range(1.5, 4.0), Color(0.95, 0.93, 1.0, 0.5 * a))


func _draw_ui_sil() -> void:
	var vs := get_viewport().get_visible_rect().size
	var band := _band_rect(vs)
	if band.x <= 0.0:
		return
	var poly := _band_poly(vs, band.y)
	var top := minf(poly[0].y, poly[1].y)
	var h := maxf(poly[2].y, poly[3].y) - top
	var mat := _ui_sil.material as ShaderMaterial
	mat.set_shader_parameter("band_a", poly[0])
	mat.set_shader_parameter("band_b", poly[1])
	mat.set_shader_parameter("band_h", poly[3].y - poly[0].y)
	mat.set_shader_parameter("screen_size", vs)
	mat.set_shader_parameter("paint", 1.0)
	mat.set_shader_parameter("levels", 64.0)
	var along := (poly[1] - poly[0]).normalized() * (band.z)
	if _cutin_tex != null:
		var tw := _cutin_tex.get_size()
		var sc := h * 1.25 / tw.y
		var dst := Rect2(Vector2(vs.x * 0.6 - tw.x * sc * 0.5, top - h * 0.12) + along, tw * sc)
		_ui_sil.draw_texture_rect(_cutin_tex, dst, false, Color(1, 1, 1, band.x))
	elif _cut_tex != null:
		var reg := _cut_region
		var sc := minf((poly[3].y - poly[0].y) * 0.92 / maxf(reg.size.y, 1.0), vs.x * 0.5 / maxf(reg.size.x, 1.0))
		var size := reg.size * sc
		var cx := vs.x * 0.64
		var cy := lerpf(poly[0].y, poly[1].y, cx / vs.x) + (poly[3].y - poly[0].y) * 0.5
		var dst := Rect2(Vector2(cx - size.x * 0.5, cy - size.y * 0.5) + along, size)
		if _cut_flip:
			dst = Rect2(dst.position + Vector2(size.x, 0), Vector2(-size.x, size.y))
		_ui_sil.draw_texture_rect_region(_cut_tex, dst, reg, Color(1, 1, 1, band.x))


## 题字、印章、黑边、HIT / 总伤害
func _draw_ui_top() -> void:
	var vs := get_viewport().get_visible_rect().size
	var charge := _pv("ult_charge_frames", 30.0)
	# 题字：跟着切入带；左→右 8 帧显现，印章晚 4 帧盖下来
	var band := _band_rect(vs)
	if _title_tex != null and band.x > 0.0:
		var t := _f - (charge + 6.0)
		if t >= 0.0:
			var poly := _band_poly(vs, band.y)
			var along := (poly[1] - poly[0]).normalized() * band.z
			var size := _title_tex.get_size() * TITLE_SCALE
			var center := Vector2(vs.x * 0.3, vs.y * 0.3) + along
			var reveal := clampf(t / 8.0, 0.0, 1.0)
			var src := Rect2(Vector2.ZERO, Vector2(_title_tex.get_width() * reveal, _title_tex.get_height()))
			var dst := Rect2(center - size * 0.5, Vector2(size.x * reveal, size.y))
			_ui_top.draw_texture_rect_region(_title_tex, dst, src, Color(1, 1, 1, band.x))
			if _seal_tex != null and t >= 12.0:
				var ks := clampf((t - 12.0) / 4.0, 0.0, 1.0)
				var ss := lerpf(1.6, 1.0, 1.0 - pow(1.0 - ks, 3.0)) * 130.0 / _seal_tex.get_width()
				var jit := Vector2(rng.randf_range(-4, 4), rng.randf_range(-4, 4)) if t >= 15.0 and t < 19.0 else Vector2.ZERO
				var sp := center + Vector2(size.x * 0.5, size.y * 0.3) + jit
				var sz := _seal_tex.get_size() * ss
				_ui_top.draw_texture_rect(_seal_tex, Rect2(sp - sz * 0.5, sz), false, Color(1, 1, 1, ks * band.x))
	# 黑边
	var lb := 0.0
	if _phase == 1:
		lb = smoothstep(0.0, 8.0, _f)
	elif _phase == 2:
		lb = 1.0 - smoothstep(44.0, 56.0, _since_burst)
	if lb > 0.0:
		var hh := LETTERBOX * lb
		_ui_top.draw_rect(Rect2(0, 0, vs.x, hh), Color.BLACK)
		_ui_top.draw_rect(Rect2(0, vs.y - hh, vs.x, hh), Color.BLACK)
	# HIT 计数（左中，深色底板）；白闪 / 双色定格 / 全黑刀缝时不画
	var slit := _phase == 1 and _pv("ult_hit_frame", 150.0) - _f <= SLIT_FRAMES
	var blanked := _phase == 2 and _since_burst < 5.0
	if _hits > 0 and not slit and not blanked and (_phase == 1 or _since_burst < 56.0):
		var a := 1.0 if _phase == 1 else 1.0 - smoothstep(40.0, 56.0, _since_burst)
		var pos := Vector2(vs.x * 0.05, vs.y * 0.44)
		var big := 78.0 * (1.0 + 0.35 * _hit_pop)
		var num := str(_hits)
		var nw := _font.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, int(big)).x
		var plate_w := maxf(nw + 120.0, 250.0)
		_ui_top.draw_colored_polygon(PackedVector2Array([pos + Vector2(-24, -76), pos + Vector2(plate_w, -76),
			pos + Vector2(plate_w - 26, 20), pos + Vector2(-50, 20)]), Color(0.04, 0.02, 0.08, 0.62 * a))
		_ui_top.draw_line(pos + Vector2(-24, -76), pos + Vector2(plate_w, -76), Color(VIO_L, 0.8 * a), 2.0)
		_ui_top.draw_string_outline(_font, pos, num, HORIZONTAL_ALIGNMENT_LEFT, -1, int(big), 10, Color(INK, a))
		_ui_top.draw_string(_font, pos, num, HORIZONTAL_ALIGNMENT_LEFT, -1, int(big), Color(WHITE, a))
		_ui_top.draw_string_outline(_font, pos + Vector2(nw + 10.0, 0), "HIT", HORIZONTAL_ALIGNMENT_LEFT, -1, 34, 8, Color(INK, a))
		_ui_top.draw_string(_font, pos + Vector2(nw + 10.0, 0), "HIT", HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color(VIO_L, a))
	# 总伤害：爆开那一下在画面中右 2.0 → 1.0 倍盖章落下（白字紫描边），15 帧后淡出
	if _phase == 2 and _dmg_total > 0.0 and _since_burst >= BURST_HOLD and _since_burst < 56.0:
		var a := 1.0 - smoothstep(40.0, 56.0, _since_burst)
		var s := "%d" % int(round(_dmg_total))
		var k := clampf((_since_burst - BURST_HOLD) / 5.0, 0.0, 1.0)
		var size := int(124.0 * lerpf(2.0, 1.0, 1.0 - pow(1.0 - k, 3.0)))
		var tw := _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var dp := Vector2(vs.x * 0.66 - tw * 0.5, vs.y * 0.36 + size * 0.35)
		_ui_top.draw_string_outline(_font, dp, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 16, Color(VIO_D, a))
		_ui_top.draw_string(_font, dp, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(WHITE.lerp(VIO_L, 0.2), a))
		var lw := _font.get_string_size("总伤害", HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
		_ui_top.draw_string_outline(_font, dp + Vector2(tw * 0.5 - lw * 0.5, -size * 0.82), "总伤害", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, 8, Color(INK, a * k))
		_ui_top.draw_string(_font, dp + Vector2(tw * 0.5 - lw * 0.5, -size * 0.82), "总伤害", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(VIO_L, a * k))


## 切入带：x = 显示程度，y = 竖直方向不用（0），z = 沿带子方向的滑动量（屏幕像素）
func _band_rect(vs: Vector2) -> Vector3:
	if _phase != 1:
		return Vector3.ZERO
	var charge := _pv("ult_charge_frames", 30.0)
	var ps := _pv("ult_pass_start", 66.0)
	if _f < charge or _f >= ps:
		return Vector3.ZERO
	var tin := smoothstep(charge, charge + 6.0, _f)
	var tout := smoothstep(ps - 6.0, ps, _f)
	var drift := -(_f - charge) * 1.5
	var slide := (1.0 - tin) * vs.x * 1.1 - tout * vs.x * 1.3 + drift
	return Vector3(minf(tin, 1.0 - tout) if tout > 0.0 else 1.0, 0.0, slide)


## 带子的四个角：沿带子方向很长（两头永远在屏幕外），slide 沿带子方向移动
func _band_poly(vs: Vector2, _unused: float, h: float = CUT_H, off: float = 0.0) -> PackedVector2Array:
	var band := _band_rect(vs)
	var axis := Vector2(1.0, -CUT_TILT).normalized()
	var nrm := Vector2(-axis.y, axis.x)          # 朝下
	var c := Vector2(vs.x * 0.5, vs.y * 0.53) + axis * band.z + nrm * off
	var L := vs.x * 1.6
	return PackedVector2Array([c - axis * L - nrm * h * 0.5, c + axis * L - nrm * h * 0.5,
		c + axis * L + nrm * h * 0.5, c - axis * L + nrm * h * 0.5])


# ---------------------------------------------------------------- 工具

func _lens(cv: CanvasItem, a: Vector2, b: Vector2, w: float, col: Color) -> void:
	if col.a <= 0.003 or w <= 0.05 or a.distance_squared_to(b) < 1.0:
		return
	var d := (b - a)
	var n := d.normalized().orthogonal() * w * 0.5
	var m1 := a + d * 0.35
	var m2 := a + d * 0.7
	cv.draw_colored_polygon(PackedVector2Array([a, m1 + n, m2 + n * 0.8, b, m2 - n * 0.8, m1 - n]), col)


func _ellipse(cv: CanvasItem, c: Vector2, rx: float, ry: float, w: float, col: Color) -> void:
	if col.a <= 0.003 or w <= 0.05:
		return
	var pts := PackedVector2Array()
	for i in 49:
		var t := TAU * float(i) / 48.0
		pts.append(c + Vector2(cos(t) * rx, sin(t) * ry))
	cv.draw_polyline(pts, col, w)


## 巨斩交点：挨过刀的影（刀痕挂着的）的中心；没有就主角前方
func _crowd_center() -> Vector2:
	var sum := Vector2.ZERO
	var n := 0
	var seen := {}
	for m in _marks:
		var node: Node2D = m.node
		if is_instance_valid(node) and not seen.has(node):
			seen[node] = true
			sum += node.global_position + Vector2(0, -float(node.get("half_h") if node.get("half_h") != null else 60.0) * 0.3)
			n += 1
	if n > 0:
		return sum / float(n)
	if _ok():
		return player.global_position + Vector2(float(player.facing) * 300.0, -40.0) * _px()
	return global_position


func _screen_uv(world: Vector2) -> Vector2:
	var vs := get_viewport().get_visible_rect().size
	var p := get_viewport().get_canvas_transform() * world
	return Vector2(p.x / maxf(vs.x, 1.0), p.y / maxf(vs.y, 1.0))


func _ok() -> bool:
	return is_instance_valid(player)


func _pv(name: String, fallback: float) -> float:
	if _ok() and player.get(name) != null:
		return float(player.get(name))
	return fallback


func _pv_last_pass() -> float:
	if _ok() and player.has_method("ult_pass_frames"):
		var pf: PackedInt32Array = player.ult_pass_frames()
		if pf.size() > 0:
			return float(pf[pf.size() - 1])
	return 109.0


func _px() -> float:
	var cam := get_viewport().get_camera_2d()
	return 1.0 / maxf(cam.zoom.x, 0.01) if cam != null else 2.0


func _feet() -> Vector2:
	var fo: Variant = player.get("foot_offset")
	return player.global_position + Vector2(0.0, float(fo) if fo != null else 84.0)
