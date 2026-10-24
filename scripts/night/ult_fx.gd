extends Node2D
## 大招「千刃」的全屏表现（2026-10-23 商业级版，取代 §16.12 “月下斩”分镜）。
## 时间轴跟着主角的 ult_frame（60 帧 / 秒；各段长度读 player.gd 的 ult_* 参数，默认值写在括号里）：
##   ① 起势（0～21）：时间停住——上下黑边滑入、背景褪色压暗、镜头往主角推近；四周集中线往里收；
##      脚下两圈风压；刀身辉光加强；末尾刀尖一闪
##   ② 切入（22～37）：屏幕中间斜着闪进一条立绘带（有 assets/image/ult/cutin.png 就用它，没有就用主角当前姿势放大
##      做占位）+ 带内速度线；招式名「千刃」题字盖章落下（assets/image/ult/title.png）；第 37 帧白闪、镜头弹回
##   ③ 千刃（38～81，十斩，越来越快）：每斩主角瞬移穿过一只影——沿路残影 + 硬边斩线（交错成网）+ 全屏横向速度线
##      + 小色差冲击 + 镜头小顶一下；影身上留一道刀痕（一直挂着，越积越多）；右侧 HIT 计数逐个跳；最后三斩闪紫
##   ④ 残心（82～111）：主角背对敌人收刀，全场静默压暗、镜头慢慢推向主角；106 收刀“咔”（sheathed），刀痕全部亮起；
##      108～111 全黑，只剩一道横贯屏幕的白色刀缝（拔刀前的一瞬）
##   ⑤ 全屏巨斩（112 = ult_hit）：一个横贯全屏的巨大 X 斩，白闪，画面沿斩线错开（fx_ult_split），
##      径向模糊 + 色差 + 往外扩的折射冲击波（fx_ult_shock），每只影的刀痕炸成放射斩线 + 命中爆闪 + 紫白碎片，
##      地面两圈冲击环；HIT 计数换成总伤害
##   ⑥ 收尾：颜色恢复、黑边退出、镜头回原样、HUD 回来
## 斩线 / 刀痕 / 巨斩 / 碎片都是自己画的硬边多边形（不进像素特效画布，不糊）；命中爆闪、残影、冲击帧借 impact_fx。

signal sheathed(point: Vector2)      ## ④ 收刀“咔”

const ImpactFX := preload("res://scripts/presentation/impact_fx.gd")
const GRADE_SHADER := preload("res://assets/shaders/fx_ult_grade.gdshader")
const INK_SHADER := preload("res://assets/shaders/fx_ult_ink.gdshader")
const SPLIT_SHADER := preload("res://assets/shaders/fx_ult_split.gdshader")
const SIL_SHADER := preload("res://assets/shaders/fx_ult_sil.gdshader")
const SHOCK_SHADER := preload("res://assets/shaders/fx_ult_shock.gdshader")
const TITLE_PATH := "res://assets/image/ult/title.png"
const CUTIN_PATH := "res://assets/image/ult/cutin.png"
const VIEW := Vector2(2560.0, 1440.0)    ## 镜头 ZOOM 0.5 → 世界里一屏的大小
const WHITE := ImpactFX.WHITE
const VIO_L := ImpactFX.VIO_L
const VIO := ImpactFX.VIO
const VIO_D := ImpactFX.VIO_D
const GOLD := ImpactFX.GOLD
const INK := Color("120d1c")
const PAPER := Color(0.95, 0.94, 0.98)   ## 黑白定格的纸色（fx_ult_ink 的 paper 要一致）

const HIDE_HUD := true
const LETTERBOX := 78.0      ## 黑边高度（屏幕像素）
const ZOOM_IN := 0.16        ## 起势镜头推近多少（0.16 = 16%）
const ZOOM_STILL := 0.07     ## 残心时再推近多少
const TRAIL_LIFE := 11.0     ## 一道斩线留多久（帧）
const TRAIL_W := 13.0        ## 斩线最宽处（屏幕像素）
const MARK_LEN := 46.0       ## 刀痕长度（屏幕像素）
const X_W := 64.0            ## 巨斩最宽处（屏幕像素）
const X_LIFE := 26.0
const BURST_LIFE := 18.0     ## 刀痕炸开的放射斩线留多久（帧）
const TITLE_SCALE := 0.44    ## 题字在 1280×720 屏幕上的缩放
const CUT_H := 210.0         ## 切入带高度（屏幕像素）
const CUT_TILT := 0.12

var fx: Node2D               ## ImpactFX
var player: Node2D
var hud: Control             ## CombatHud（藏起来 / 静音提示字）
var anchor: Node2D           ## 关卡给的镜头钉子（千刃期间镜头跟它）
var rng := RandomNumberGenerator.new()

var _phase: int = 0          ## 0 没在放 / 1 起势～残心 / 2 巨斩之后
var _f: float = 0.0          ## 起手后第几帧（跟主角 ult_frame 对齐）
var _since_burst: float = 0.0
var _grade_k: float = 0.0
var _hud_k: float = 1.0
var _clicked: bool = false
var _glinted: bool = false
var _flash: float = 0.0      ## 白闪剩余帧
var _flash_col := Color.WHITE
var _vflash: float = 0.0     ## 紫闪剩余帧
var _trails: Array = []      ## {a, b, born, w}
var _marks: Array = []       ## {node, off, ang, len, born}
var _bursts: Array = []      ## {pt, born, rays}
var _shards: Array = []      ## {p, v, born, life, size, rot, spin, col}
var _rings: Array = []       ## {p, born, life, r0, r1}
var _speed: Array = []       ## 屏幕横向速度线：{born, dir, seed}
var _shock_pulses: Array = []   ## {born, s, c(屏幕 uv)}
var _x_center := Vector2.INF
var _x_angs := [0.0, 0.0]
var _hits: int = 0
var _hit_pop: float = 0.0
var _dmg_total: float = 0.0
var _cam: Camera2D
var _zoom0 := Vector2.ZERO
var _center0 := Vector2.INF
var _zoom_punch: float = 0.0
var _glow0: float = -1.0
var _title_tex: Texture2D
var _cutin_tex: Texture2D
var _cut_tex: Texture2D      ## 占位立绘：切入那一刻主角的贴图
var _cut_region := Rect2()
var _cut_flip := false

var _grade_copy: BackBufferCopy
var _grade: Node2D
var _grade_mat: ShaderMaterial
var _paper: Node2D
var _ink_copy: BackBufferCopy
var _ink: Node2D
var _ink_mat: ShaderMaterial
var _split_copy: BackBufferCopy
var _split: Node2D
var _split_mat: ShaderMaterial
var _lo: Node2D              ## 角色身后：斩线、巨斩外圈
var _hi: Node2D              ## 角色前面：刀痕、巨斩、放射斩线、碎片、冲击环
var _ui: CanvasLayer         ## 屏幕坐标：黑边、切入带、题字、速度线、HIT、闪光
var _ui_draw: Node2D
var _ui_sil: Node2D
var _ui_top: Node2D
var _post: CanvasLayer
var _shock: ColorRect
var _shock_mat: ShaderMaterial
var _font: Font


func _ready() -> void:
	z_index = 20
	process_priority = 10
	rng.randomize()
	_grade_copy = _copy(-3)
	_grade = _layer(-3, GRADE_SHADER)     # 地形（−70）之后、斩线（−2）/ 残影（−1）/ 角色（0）之前
	_grade_mat = _grade.material as ShaderMaterial
	_grade.draw.connect(func(): _grade.draw_rect(Rect2(-VIEW * 0.7, VIEW * 1.4), Color.WHITE))
	_paper = _layer(-74)                  # 夜景像素化（−75）之上、地形（−70）之下：地形也变墨色剪影
	_paper.draw.connect(func(): _paper.draw_rect(Rect2(-VIEW * 0.7, VIEW * 1.4), PAPER))
	_ink_copy = _copy(39)
	_ink = _layer(40, INK_SHADER)
	_ink_mat = _ink.material as ShaderMaterial
	_ink.draw.connect(func(): _ink.draw_rect(Rect2(-VIEW * 0.7, VIEW * 1.4), Color.WHITE))
	_split_copy = _copy(44)
	_split = _layer(45, SPLIT_SHADER)
	_split_mat = _split.material as ShaderMaterial
	_split.draw.connect(func(): _split.draw_rect(Rect2(-VIEW * 0.7, VIEW * 1.4), Color.WHITE))
	_lo = _world(-2)
	_lo.draw.connect(_draw_lo)
	_hi = _world(18)                      # 角色之上、伤害数字（35）之下
	_hi.draw.connect(_draw_hi)
	_ui = CanvasLayer.new()
	_ui.layer = 11                        # HUD 是 10
	add_child(_ui)
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
	_post = CanvasLayer.new()
	_post.layer = 12
	add_child(_post)
	_shock = ColorRect.new()
	_shock.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shock_mat = ShaderMaterial.new()
	_shock_mat.shader = SHOCK_SHADER
	_shock.material = _shock_mat
	_shock.visible = false
	_post.add_child(_shock)
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "PingFang SC", "sans-serif"])
	sf.font_weight = 900
	sf.font_italic = true
	_font = sf
	_title_tex = _load_png(TITLE_PATH)
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


## 运行时直接读 PNG 字节（和 art_cache 一样，不依赖 Godot 导入；文件不存在返回 null）
static func _load_png(path: String) -> Texture2D:
	if not FileAccess.file_exists(path):
		return null
	var bytes := FileAccess.get_file_as_bytes(path)
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK:
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
	if is_instance_valid(fx):
		_glow0 = float(fx.glow_base)
		fx.glow_base = maxf(_glow0, 1.25)
		if _ok():
			fx.spawn_launch(_feet())
	if _ok():
		for i in 2:
			_rings.append({"p": _feet(), "born": float(i) * 7.0, "life": 22.0, "r0": 20.0, "r1": 260.0, "f": true})


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
	_set_ink(false, false)
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
	var y0 := -54.0 * px + rng.randf_range(-18.0, 18.0) * px
	var tilt := rng.randf_range(-26.0, 26.0) * px
	var a := from + Vector2(-dir * 40.0 * px, y0 - tilt * 0.5)
	var b := to + Vector2(dir * 30.0 * px, y0 + tilt * 0.5)
	var late := float(k) / float(maxi(n - 1, 1))
	_trails.append({"a": a, "b": b, "born": _f, "w": TRAIL_W * (0.85 + 0.45 * late)})
	_speed.append({"born": _f, "dir": dir, "seed": rng.randi()})
	_hits += 1
	_hit_pop = 1.0
	_zoom_punch = 0.035 + 0.02 * late
	_shock_pulses.append({"born": _f, "s": 0.22 + 0.2 * late, "c": _screen_uv(to + Vector2(0, -50.0 * px))})
	if k >= n - 3:
		_vflash = 2.0
	if not is_instance_valid(fx):
		return
	var spr: Sprite2D = player.get_node_or_null("Visual/ActorSprite") if _ok() else null
	if spr != null:
		fx.ghost_line(spr, from, to, clampi(int(absf(to.x - from.x) / (70.0 * px)), 3, 7), VIO_L)
	if point != Vector2.INF and node != null:
		var ang := rng.randf_range(0.45, 1.1) * (1.0 if rng.randf() < 0.5 else -1.0)
		_marks.append({"node": node, "off": point - node.global_position + Vector2(rng.randf_range(-10, 10), rng.randf_range(-16, 16)) * px,
			"ang": ang, "len": MARK_LEN * rng.randf_range(0.8, 1.25), "born": _f})
		fx.spawn_hit(point, 0.5 + 0.4 * late, false, Vector2(dir, 0), true, &"dash_slash")
		for i in 5:
			_shard(point, Vector2(dir * rng.randf_range(120, 380), rng.randf_range(-260, -60)) * px, rng.randf_range(14, 24), 0.0)


## ⑤ 全屏巨斩（主角 ult_hit）。hit = [{node, pt, cuts, dmg}]
func burst(hit: Array) -> void:
	_phase = 2
	_since_burst = 0.0
	_flash = 7.0
	_flash_col = Color.WHITE
	_set_ink(false, false)
	var px := _px()
	if is_instance_valid(fx):
		fx.impact_frame(1.0)
	# 巨斩交叉点：被砍中的影的中心；没有就屏幕中心
	var c := Vector2.ZERO
	for h in hit:
		c += h.pt
	_x_center = c / float(hit.size()) if hit.size() > 0 else (_center0 if _center0 != Vector2.INF else global_position) + Vector2(0, 40.0 * px)
	var f := float(player.facing) if _ok() else 1.0
	_x_angs = [-0.32 * f, 0.36 * f]
	_shock_pulses.append({"born": _f, "s": 1.0, "c": _screen_uv(_x_center), "wave": true})
	_dmg_total = 0.0
	for h in hit:
		_dmg_total += float(h.get("dmg", 0.0))
		var pt: Vector2 = h.pt
		var rays: Array = []
		var cuts: int = clampi(int(h.get("cuts", 1)), 1, 8)
		for m in _marks:
			if m.node == h.node:
				rays.append([float(m.ang), float(m.len) * 2.8 * px])
		for i in 3:
			rays.append([rng.randf_range(-PI, PI), rng.randf_range(60.0, 120.0) * px])
		_bursts.append({"pt": pt, "born": 0.0, "rays": rays})
		for i in 10 + cuts * 2:
			var ang := rng.randf_range(-PI, 0.0)
			_shard(pt, Vector2.from_angle(ang) * rng.randf_range(180, 620) * px, rng.randf_range(30, 60), rng.randf_range(0.0, 2.0))
		if is_instance_valid(fx):
			var dir := Vector2(signf(pt.x - player.global_position.x) if _ok() else 1.0, 0.0)
			fx.spawn_hit(pt, 1.2 + 0.12 * float(cuts), true, dir, false, &"charge_1")
	for i in 2:
		var gp := Vector2(_x_center.x, _feet().y if _ok() else _x_center.y + 120.0 * px)
		_rings.append({"p": gp, "born": _f + float(i) * 4.0, "life": 26.0, "r0": 40.0, "r1": 900.0 - 260.0 * float(i), "f": false})
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
	_vflash = maxf(_vflash - df, 0.0)
	_hit_pop = maxf(_hit_pop - df / 6.0, 0.0)
	_zoom_punch = move_toward(_zoom_punch, 0.0, df * 0.012)
	_trails = _trails.filter(func(t): return _f - float(t.born) < TRAIL_LIFE)
	_bursts = _bursts.filter(func(bs): return _since_burst - float(bs.born) < BURST_LIFE)
	_marks = _marks.filter(func(m): return is_instance_valid(m.node))
	_speed = _speed.filter(func(s): return _f - float(s.born) < 5.0)
	_shock_pulses = _shock_pulses.filter(func(s): return _f - float(s.born) < (26.0 if s.has("wave") else 7.0))
	_rings = _rings.filter(func(r): return _f - float(r.born) < float(r.life))
	_tick_shards(delta)
	_update_camera()
	_update_grade(df)
	_update_ink_split()
	_update_shock()
	_update_hud(df)
	if _phase == 2 and _since_burst > 40.0 and _bursts.is_empty() and _shards.is_empty() and not (_ok() and player.is_ult()):
		var keep := _hud_k
		clear()
		_hud_k = keep
		_apply_hud()
	_lo.queue_redraw()
	_hi.queue_redraw()
	_ui_draw.queue_redraw()
	_ui_sil.queue_redraw()
	_ui_top.queue_redraw()


## 刀尖一闪、切入时抓主角贴图、收刀“咔”
func _tick_cues() -> void:
	if not _ok() or _phase == 0:
		return
	var charge := _pv("ult_charge_frames", 22.0)
	if not _glinted and _f >= charge - 5.0:
		_glinted = true
		if is_instance_valid(fx):
			fx.spawn_parry(player.global_position + Vector2(float(player.facing) * 70.0, -70.0) * _px(), Vector2(player.facing, 0))
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
		_flash = maxf(_flash, 2.0)
		_flash_col = Color(0.85, 0.8, 1.0)
	var ps := _pv("ult_pass_start", 38.0)
	if _f >= ps - 1.0 and _f < ps and _flash <= 0.0:
		_flash = 3.0
		_flash_col = Color.WHITE
	var click := _pv("ult_click_frame", 106.0)
	if not _clicked and _f >= click:
		_clicked = true
		var hp := player.global_position + Vector2(-float(player.facing) * 10.0, -40.0) * _px()
		sheathed.emit(hp)
		if is_instance_valid(fx):
			fx.spawn_block(hp, Vector2(-player.facing, 0))


func _shard(p: Vector2, v: Vector2, life: float, delay: float) -> void:
	var cols := [WHITE, VIO_L, VIO, VIO_L]
	_shards.append({"p": p, "v": v, "born": _f + delay, "life": life, "size": rng.randf_range(4.0, 11.0),
		"rot": rng.randf_range(0, TAU), "spin": rng.randf_range(-14.0, 14.0), "col": cols[rng.randi() % cols.size()]})


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
		s.v = (s.v as Vector2) * pow(0.12, delta) + Vector2(0, 900.0 * px) * delta
		s.p = (s.p as Vector2) + (s.v as Vector2) * delta
		s.rot = float(s.rot) + float(s.spin) * delta
		keep.append(s)
	_shards = keep


## 镜头：起势推近（往主角那边挪一点）→ 切入末弹回 → 每斩小顶 → 残心慢慢推向主角 → 巨斩一下拉远再回来
func _update_camera() -> void:
	if not is_instance_valid(_cam) or _zoom0 == Vector2.ZERO or _phase == 0:
		return
	var charge := _pv("ult_charge_frames", 22.0)
	var ps := _pv("ult_pass_start", 38.0)
	var still0 := _pv_last_pass() + 6.0
	var hit := _pv("ult_hit_frame", 112.0)
	var mult := 1.0
	var toward := 0.0
	if _phase == 1:
		if _f < ps - 1.0:
			var k := clampf(_f / charge, 0.0, 1.0)
			mult = 1.0 + ZOOM_IN * (1.0 - pow(1.0 - k, 3.0))
			toward = 0.55 * k
		elif _f < still0:
			mult = 1.0 + _zoom_punch
		else:
			var k := clampf((_f - still0) / maxf(hit - still0, 1.0), 0.0, 1.0)
			mult = 1.0 + ZOOM_STILL * smoothstep(0.0, 1.0, k)
			toward = 0.4 * smoothstep(0.0, 1.0, k)
	else:
		mult = 1.0 - 0.05 * (1.0 - smoothstep(0.0, 16.0, _since_burst))
	_cam.zoom = _zoom0 * mult
	if is_instance_valid(anchor) and _center0 != Vector2.INF:
		var target := _center0
		if toward > 0.0 and _ok():
			target.x = lerpf(_center0.x, player.global_position.x, toward)
		anchor.global_position = target


func _restore_camera() -> void:
	if is_instance_valid(_cam) and _zoom0 != Vector2.ZERO:
		_cam.zoom = _zoom0
	_zoom0 = Vector2.ZERO
	if is_instance_valid(anchor) and _center0 != Vector2.INF:
		anchor.global_position = _center0
	_center0 = Vector2.INF


func _update_grade(df: float) -> void:
	var want := 0.0
	if _phase == 1:
		want = 1.0
	elif _phase == 2:
		want = 1.0 - smoothstep(6.0, 28.0, _since_burst)
	_grade_k = move_toward(_grade_k, want, df * (0.16 if want > _grade_k else 1.0))
	var on := _grade_k > 0.002 and not _ink.visible
	_grade.visible = on
	_grade_copy.visible = on
	if on:
		_grade_mat.set_shader_parameter("amount", _grade_k)
		_grade.queue_redraw()


## 收刀后黑白定格（两帧白底墨剪影 + 两帧反色），巨斩后画面沿第一道斩线错开再合上
func _update_ink_split() -> void:
	var hit := _pv("ult_hit_frame", 112.0)
	var k := 0.0
	if _phase == 2 and _x_center != Vector2.INF:
		k = smoothstep(1.0, 3.0, _since_burst) * (1.0 - smoothstep(12.0, 20.0, _since_burst))
	var on := k > 0.02
	_split.visible = on
	_split_copy.visible = on
	if on:
		var a: float = _x_angs[0]
		var nrm := Vector2.from_angle(a).orthogonal()
		var big := 60000.0
		_split_mat.set_shader_parameter("center", _x_center + nrm * big)
		_split_mat.set_shader_parameter("radius", big)
		_split_mat.set_shader_parameter("amount", 16.0 * k)
		_split_mat.set_shader_parameter("dir", 1.0)
		_split_mat.set_shader_parameter("seam", 3.0 * _px() * k)
		_split.queue_redraw()


func _set_ink(on: bool, inv: bool) -> void:
	_paper.visible = on
	_ink.visible = on
	_ink_copy.visible = on
	if on:
		_ink_mat.set_shader_parameter("invert", inv)
		_paper.queue_redraw()
		_ink.queue_redraw()


func _update_shock() -> void:
	var s := 0.0
	var c := Vector2(0.5, 0.5)
	var wave_r := -1.0
	var wave_amp := 0.0
	for p in _shock_pulses:
		var age := _f - float(p.born)
		var life := 26.0 if p.has("wave") else 7.0
		var v := float(p.s) * pow(1.0 - clampf(age / (18.0 if p.has("wave") else life), 0.0, 1.0), 2.0)
		if v > s:
			s = v
			c = p.c
		if p.has("wave"):
			wave_r = 0.05 + age / life * 1.3
			wave_amp = 0.022 * (1.0 - clampf(age / life, 0.0, 1.0))
			c = p.c
	var on := s > 0.01 or wave_r > 0.0
	_shock.visible = on
	if on:
		var vs := get_viewport().get_visible_rect().size
		_shock_mat.set_shader_parameter("center", c)
		_shock_mat.set_shader_parameter("strength", s)
		_shock_mat.set_shader_parameter("wave_r", wave_r)
		_shock_mat.set_shader_parameter("wave_amp", wave_amp)
		_shock_mat.set_shader_parameter("aspect", vs.x / maxf(vs.y, 1.0))


func _update_hud(df: float) -> void:
	var want := 1.0
	if _phase == 1 or (_phase == 2 and _since_burst < 22.0):
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
		for layer in [[VIO_D, 1.0], [VIO, 0.7], [WHITE, 0.32]]:
			var c: Color = layer[0]
			c.a = 1.0 if age < 3.0 else 1.0 - smoothstep(0.55, 1.0, k)
			_lens(_lo, a, b, w * float(layer[1]), c)
	# 地面风压 / 冲击环（扁椭圆）
	for r in _rings:
		var age := _f - float(r.born)
		if age < 0.0:
			continue
		var k := clampf(age / float(r.life), 0.0, 1.0)
		var rad: float = lerpf(float(r.r0), float(r.r1), 1.0 - pow(1.0 - k, 3.0)) * px
		var w := (10.0 if not r.f else 6.0) * px * (1.0 - k)
		var col := Color(VIO_L if r.f else WHITE, 0.85 * (1.0 - k))
		_ellipse(_lo, r.p, rad, rad * 0.16, w, col)


func _draw_hi() -> void:
	var px := _px()
	var bright := 1.0 if not _clicked else 1.7
	for m in _marks:
		var node: Node2D = m.node
		var c: Vector2 = node.global_position + (m.off as Vector2)
		var age := _f - float(m.born)
		var grow := clampf((age + 1.0) / 3.0, 0.0, 1.0)
		var half := Vector2.from_angle(float(m.ang)) * float(m.len) * px * 0.5 * grow * (1.15 if _clicked else 1.0)
		var w := (5.0 if age < 3.0 else 3.0) * px * bright
		_lens(_hi, c - half, c + half, w * 1.9, Color(VIO, 0.85))
		_lens(_hi, c - half, c + half, w, Color(WHITE, 1.0))
	# 全屏巨斩：两道交叉的超长斩线，3 帧内从一端划到另一端，停一下，再从中间往两头收细消失
	if _x_center != Vector2.INF and _since_burst < X_LIFE:
		var vlen := VIEW.x * 0.75 * (1.0 / maxf(_cam.zoom.x / 0.5, 0.5) if is_instance_valid(_cam) else 1.0)
		for i in 2:
			var t0 := float(i) * 2.0
			var age := _since_burst - t0
			if age < 0.0:
				continue
			var dir := Vector2.from_angle(float(_x_angs[i]))
			var draw_k := clampf((age + 1.0) / 3.0, 0.0, 1.0)
			var fade := 1.0 - smoothstep(10.0, X_LIFE - t0, age)
			var a := _x_center - dir * vlen
			var b := a.lerp(_x_center + dir * vlen, draw_k)
			var w := X_W * px * (1.0 if age < 6.0 else lerpf(1.0, 0.25, smoothstep(6.0, X_LIFE, age)))
			_lens(_hi, a, b, w * 1.35, Color(VIO_D, 0.9 * fade))
			_lens(_hi, a, b, w, Color(VIO, fade))
			_lens(_hi, a, b, w * 0.62, Color(VIO_L, fade))
			_lens(_hi, a, b, w * 0.3, Color(WHITE, fade))
	for bs in _bursts:
		var age := _since_burst - float(bs.born)
		var k := clampf(age / BURST_LIFE, 0.0, 1.0)
		var p: Vector2 = bs.pt
		for r in bs.rays:
			var dir := Vector2.from_angle(float(r[0]))
			var l: float = float(r[1]) * (0.35 + 0.65 * smoothstep(0.0, 0.25, k))
			var a := p + dir * l * smoothstep(0.3, 1.0, k)
			var b := p + dir * l
			var w := 7.0 * px * (1.0 - k * 0.8)
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

func _draw_ui() -> void:
	var vs := get_viewport().get_visible_rect().size
	var charge := _pv("ult_charge_frames", 22.0)
	var ps := _pv("ult_pass_start", 38.0)
	# 集中线（起势）
	if _phase == 1 and _f < ps and _ok():
		var k := clampf(_f / charge, 0.0, 1.0)
		var fade := 1.0 - smoothstep(charge - 2.0, charge + 4.0, _f)
		if fade > 0.0:
			var c: Vector2 = player.get_global_transform_with_canvas().origin + Vector2(0.0, -40.0)
			var r := RandomNumberGenerator.new()
			r.seed = int(_f / 2.0) * 7919 + 13
			var outer := vs.length() * 0.6
			var inner := lerpf(outer * 0.75, 170.0, k)
			for i in 40:
				var d := Vector2.from_angle(r.randf_range(-PI, PI))
				var w := r.randf_range(2.0, 8.0)
				var p0 := c + d * outer
				var p1 := c + d * (inner + r.randf_range(0.0, 140.0))
				var n := d.orthogonal() * w
				_ui_draw.draw_colored_polygon(PackedVector2Array([p0 - n, p0 + n, p1]), Color(0.92, 0.9, 1.0, 0.55 * fade * k))
	# 切入带的底（压暗 + 斜带 + 带内速度线）
	var band := _band_rect(vs)
	if band.x > 0.0:
		_ui_draw.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.0, 0.0, 0.02, 0.45 * band.x))
		var poly := _band_poly(vs, band.y)
		var bc := Color(0.1, 0.06, 0.2, 0.96)
		_ui_draw.draw_colored_polygon(poly, bc)
		var r2 := RandomNumberGenerator.new()
		r2.seed = int(_f) * 31 + 7
		for i in 22:
			var y := lerpf(poly[0].y, poly[3].y, r2.randf())
			var x0 := fmod(r2.randf() * vs.x * 1.6 - _f * 70.0, vs.x * 1.6) - vs.x * 0.3 + band.y
			_ui_draw.draw_rect(Rect2(x0, y, r2.randf_range(80, 340), r2.randf_range(1.5, 4.0)), Color(VIO_L, 0.3))
		# 带的上下亮边
		_ui_draw.draw_line(poly[0], poly[1], Color(VIO_L, 0.95), 4.0)
		_ui_draw.draw_line(poly[3], poly[2], Color(VIO_L, 0.95), 4.0)
	# 千刃：全屏横向速度线
	for s in _speed:
		var age := _f - float(s.born)
		var r3 := RandomNumberGenerator.new()
		r3.seed = int(s.seed)
		var a := 1.0 - age / 5.0
		for i in 30:
			var y := r3.randf_range(vs.y * 0.12, vs.y * 0.88)
			var len := r3.randf_range(180.0, 620.0)
			var x := r3.randf_range(-200.0, vs.x) + float(s.dir) * age * 260.0
			_ui_draw.draw_rect(Rect2(x, y, len, r3.randf_range(1.0, 3.0)), Color(0.95, 0.93, 1.0, 0.45 * a))


## 立绘：有 cutin.png 用它；没有就把切入那一刻主角的贴图放大（色阶化）当占位
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
	if _cutin_tex != null:
		mat.set_shader_parameter("paint", 1.0)
		mat.set_shader_parameter("levels", 64.0)
		var tw := _cutin_tex.get_size()
		var sc := h * 1.25 / tw.y
		var dst := Rect2(Vector2(vs.x * 0.56 + band.y - tw.x * sc * 0.5, top - h * 0.12), tw * sc)
		_ui_sil.draw_texture_rect(_cutin_tex, dst, false, Color(1, 1, 1, band.x))
	elif _cut_tex != null:
		# 占位：主角当前姿势原色放大（等 cutin.png 立绘）
		mat.set_shader_parameter("paint", 1.0)
		mat.set_shader_parameter("levels", 64.0)
		var reg := _cut_region
		var sc := minf((h - CUT_H * 0.1) * 0.9 / maxf(reg.size.y, 1.0), vs.x * 0.5 / maxf(reg.size.x, 1.0))
		var size := reg.size * sc
		var cy := (poly[0].y + poly[3].y + poly[1].y + poly[2].y) * 0.25
		var dst := Rect2(Vector2(vs.x * 0.66 + band.y - size.x * 0.5, cy - size.y * 0.5), size)
		if _cut_flip:
			dst = Rect2(dst.position + Vector2(size.x, 0), Vector2(-size.x, size.y))
		_ui_sil.draw_texture_rect_region(_cut_tex, dst, reg, Color(1, 1, 1, band.x))


## 黑边、题字、HIT 计数、闪光（最上层）
func _draw_ui_top() -> void:
	var vs := get_viewport().get_visible_rect().size
	var charge := _pv("ult_charge_frames", 22.0)
	var ps := _pv("ult_pass_start", 38.0)
	# 黑边
	var lb := 0.0
	if _phase == 1:
		lb = smoothstep(0.0, 8.0, _f)
	elif _phase == 2:
		lb = 1.0 - smoothstep(20.0, 34.0, _since_burst)
	if lb > 0.0:
		var hh := LETTERBOX * lb
		_ui_top.draw_rect(Rect2(0, 0, vs.x, hh), Color.BLACK)
		_ui_top.draw_rect(Rect2(0, vs.y - hh, vs.x, hh), Color.BLACK)
	# 题字：切入时盖章落下（大 → 正常，带一点抖），千刃开始后淡出
	if _title_tex != null and _phase == 1:
		var t := _f - (charge + 2.0)
		if t >= 0.0 and _f < ps + 12.0:
			var k := clampf(t / 4.0, 0.0, 1.0)
			var sc := TITLE_SCALE * lerpf(1.7, 1.0, 1.0 - pow(1.0 - k, 3.0))
			var a := k * (1.0 - smoothstep(ps + 2.0, ps + 12.0, _f))
			var jit := Vector2(rng.randf_range(-3, 3), rng.randf_range(-3, 3)) if t < 6.0 else Vector2.ZERO
			var size := _title_tex.get_size() * sc
			var center := Vector2(vs.x * 0.3, vs.y * 0.3) + jit
			_ui_top.draw_texture_rect(_title_tex, Rect2(center - size * 0.5, size), false, Color(1, 1, 1, a))
	# HIT 计数 / 总伤害
	if _hits > 0 and (_phase == 1 or _since_burst < 60.0):
		var a := 1.0 if _phase == 1 else 1.0 - smoothstep(44.0, 60.0, _since_burst)
		var pos := Vector2(vs.x * 0.72, vs.y * 0.3)
		var big := 74.0 * (1.0 + 0.35 * _hit_pop)
		var num := str(_hits)
		_ui_top.draw_string_outline(_font, pos, num, HORIZONTAL_ALIGNMENT_LEFT, -1, int(big), 10, Color(INK, a))
		_ui_top.draw_string(_font, pos, num, HORIZONTAL_ALIGNMENT_LEFT, -1, int(big), Color(WHITE.lerp(VIO_L, 0.3), a))
		var nw := _font.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, int(big)).x
		_ui_top.draw_string_outline(_font, pos + Vector2(nw + 10.0, 0), "HIT", HORIZONTAL_ALIGNMENT_LEFT, -1, 34, 8, Color(INK, a))
		_ui_top.draw_string(_font, pos + Vector2(nw + 10.0, 0), "HIT", HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color(VIO_L, a))
		if _phase == 2 and _dmg_total > 0.0:
			var s := "%d" % int(round(_dmg_total))
			var k := clampf(_since_burst / 5.0, 0.0, 1.0)
			var size := int(lerpf(110.0, 64.0, k))
			var dp := pos + Vector2(0, 74.0)
			_ui_top.draw_string_outline(_font, dp, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 10, Color(INK, a))
			_ui_top.draw_string(_font, dp, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(GOLD, a))
	# 巨斩前一瞬：全黑 + 一道刀缝（从中间往两边拉开）
	if _phase == 1:
		var d := _pv("ult_hit_frame", 112.0) - _f
		if d > 0.0 and d <= 4.0:
			_ui_top.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.0, 0.0, 0.01, 1.0))
			var k := clampf((4.0 - d + 1.0) / 4.0, 0.0, 1.0)
			var cy := vs.y * 0.5
			if _x_center == Vector2.INF and _ok():
				cy = (get_viewport().get_canvas_transform() * (player.global_position + Vector2(0, -40.0 * _px()))).y
			var half := vs.x * 0.5 * k
			var c := Vector2(vs.x * 0.5, cy)
			_lens(_ui_top, c - Vector2(half, -half * 0.06), c + Vector2(half, -half * 0.06), 10.0 * k, Color(VIO, 1.0))
			_lens(_ui_top, c - Vector2(half, -half * 0.06), c + Vector2(half, -half * 0.06), 4.0 * k, Color.WHITE)
	# 紫闪 / 白闪
	if _vflash > 0.0:
		_ui_top.draw_rect(Rect2(Vector2.ZERO, vs), Color(VIO, 0.16 * _vflash / 2.0))
	if _flash > 0.0:
		var a := clampf(_flash / 7.0, 0.0, 1.0)
		_ui_top.draw_rect(Rect2(Vector2.ZERO, vs), Color(_flash_col, 0.75 * a * a))


## 切入带：x = 显示程度（0～1），y = 横向滑动量（屏幕像素）
func _band_rect(vs: Vector2) -> Vector2:
	if _phase != 1:
		return Vector2.ZERO
	var charge := _pv("ult_charge_frames", 22.0)
	var ps := _pv("ult_pass_start", 38.0)
	if _f < charge or _f >= ps:
		return Vector2.ZERO
	var tin := smoothstep(charge, charge + 3.0, _f)
	var tout := smoothstep(ps - 4.0, ps, _f)
	return Vector2(minf(tin, 1.0 - tout), (1.0 - tin) * vs.x * 0.8 - tout * vs.x * 0.8)


func _band_poly(vs: Vector2, slide: float) -> PackedVector2Array:
	var cy := vs.y * 0.52
	var h := CUT_H
	var dy := vs.x * CUT_TILT * 0.5
	return PackedVector2Array([Vector2(-20 + slide, cy - h * 0.5 + dy), Vector2(vs.x + 20 + slide, cy - h * 0.5 - dy),
		Vector2(vs.x + 20 + slide, cy + h * 0.5 - dy), Vector2(-20 + slide, cy + h * 0.5 + dy)])


# ---------------------------------------------------------------- 工具

## 两头尖的细长菱形（a → b，中间最宽 w）
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
	return 81.0


func _px() -> float:
	var cam := get_viewport().get_camera_2d()
	return 1.0 / maxf(cam.zoom.x, 0.01) if cam != null else 2.0


func _feet() -> Vector2:
	var fo: Variant = player.get("foot_offset")
	return player.global_position + Vector2(0.0, float(fo) if fo != null else 84.0)
