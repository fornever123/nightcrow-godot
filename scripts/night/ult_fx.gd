extends Node2D
## 大招「月下斩」的全屏表现。第四轮 §16.12 改成“动画分镜”，约 2 秒。时间轴跟着主角的 ult_frame（60 帧 / 秒）：
##   ① 蓄力（0～29 帧）：时间停住——背景褪色压暗（fx_ult_grade）；四周集中线往主角收（每 2 帧换一组 = 闪）；
##      刀身从柄到尖亮起来；脚下风压一圈圈往外推；镜头临时推近一点（CAM_PUSH，0 = 关；平时镜头不变）
##   ② 切入（30～53 帧）：屏幕中间斜着闪进一条带子：主角剪影特写（fx_ult_sil）+ 眼里一道光 + 速度线
##      （剪影是占位：以后有了眼睛特写图，换掉 _draw_ui_sil 就行）
##   ③ 拔刀：白屏 1 帧（54）→ 黑屏 1 帧（55 = 出刀：主角瞬间冲过敌人，player.ult_dash_by；关卡算伤害）
##   ④ 一闪：身后留一道巨大的赛璐璐刀光（白 / 浅紫 / 紫 / 深紫硬分层，两头尖、刃口在外沿），
##      一拍二换形：尖细 → 最宽 → 三张抖动的变体轮流；光晕只垫在外圈；最多两根细残影线；冲刺路上一串残影
##   ⑤ 定格：白底墨剪影 / 黑底白剪影 / 彩色 交替闪 3 次（fx_ult_ink）；画面沿刀痕裂开错位（fx_ult_split），碎片悬空
##   ⑥ 收刀：刀光碎成几段往下掉、碎屑飘落；主角背对着收刀“咔”（sheathed）→ 被砍中的影由近到远一个接一个爆：
##      尖角星形爆炸一拍二变形 → 白 → 紫 → 深紫烟团（popped：关卡出伤害数字、刀声、大震屏）
##   ⑦ 收尾：颜色恢复、HUD 回来
## 大招期间 HUD 藏起来、不弹提示字（hud.muted）。刀光 / 爆炸 / 切入都是自己画的硬边多边形（不进像素特效画布，不糊）。
signal popped(target: Node2D, point: Vector2)   ## ⑥ 某只影爆开了
signal sheathed(point: Vector2)                 ## ⑥ 收刀“咔”

const ImpactFX := preload("res://scripts/presentation/impact_fx.gd")
const PixelFx := preload("res://scripts/presentation/pixel_fx.gd")
const K := PixelFx.K
const INK_SHADER := preload("res://assets/shaders/fx_ult_ink.gdshader")
const SPLIT_SHADER := preload("res://assets/shaders/fx_ult_split.gdshader")
const GRADE_SHADER := preload("res://assets/shaders/fx_ult_grade.gdshader")
const SIL_SHADER := preload("res://assets/shaders/fx_ult_sil.gdshader")
const VIEW := Vector2(2560.0, 1440.0)    ## 镜头 ZOOM 0.5 → 世界里一屏的大小
const WHITE := ImpactFX.WHITE
const VIO_L := ImpactFX.VIO_L
const VIO := ImpactFX.VIO
const VIO_D := ImpactFX.VIO_D
const INK := ImpactFX.INK
const SMOKE := Color(0.2, 0.14, 0.33)
const SMOKE_D := Color(0.11, 0.08, 0.19)
const PAPER := Color(0.95, 0.94, 0.98)   ## 黑白定格的纸色（fx_ult_ink 的 paper 要一致）

# ---- 开关 ----
const CAM_PUSH := 0.1        ## 蓄力时镜头临时推近多少（0.1 = 10%；0 = 关）。白屏那一帧弹回原样
const HIDE_HUD := true       ## 大招期间把 HUD 藏起来
const BOOM_SCALE := 0.6      ## 收刀后每只影爆炸的大小
# ---- 切入带（屏幕像素）----
const CUT_H := 170.0
const CUT_TILT := 0.11
const CUT_Y := 0.4
const SIL_SCALE := 2.3       ## 特写放大多少（屏幕像素 / 贴图像素）：眼睛 + 刀正好塞满带子
const EYE_7 := Vector2(1036.0, 491.0)    ## charge_slash 第 7 帧（切入时停住的姿势）里眼睛的贴图像素
# ---- 刀光 ----
const BLADE_W := 62.0        ## 最宽处（屏幕像素）
const N := 72                ## 沿刀光的采样段数
const SPLIT_PX := 10.0
## 一层一层：[颜色, 从刃口往里占最宽的几成, 有没有缺口]；后画的在上面
const LAYERS := [[VIO_D, 1.0, 0], [VIO, 0.8, 1], [VIO_L, 0.56, 1], [WHITE, 0.3, 0]]
const LAYERS_THIN := [[VIO, 1.0, 0], [VIO_L, 0.72, 0], [WHITE, 0.46, 0]]
# ---- 出刀后的节奏（帧；出刀那一帧 = 黑屏 = 0）----
const S_THIN := 1            ## 1～2：尖细
const S_WIDE := 3            ## 3～4：最宽
const S_FREEZE := 5          ## 5～24：定格（变体轮流抖）
const S_SHATTER := 25        ## 刀光碎开
const NEG := {7: 0, 8: 0, 13: 1, 14: 1, 19: 0, 20: 0}   ## 黑白帧：0 = 白底墨剪影，1 = 黑底白剪影
const POP_GAP := 5           ## 一只一只爆的间隔

var fx: Node2D               ## ImpactFX
var player: Node2D
var hud: Control             ## CombatHud（藏起来 / 静音提示字）
var rng := RandomNumberGenerator.new()

var _phase: int = 0          ## 0 没在放 / 1 蓄力 + 切入 / 2 出刀之后
var _f: float = 0.0          ## 起手后第几帧
var _s: float = 0.0          ## 出刀后第几帧
var _s_run: bool = false
var _dir: float = 1.0
var _grade_k: float = 0.0
var _hud_k: float = 1.0
var _cam: Camera2D
var _zoom0 := Vector2.ZERO
var _star_done: bool = false
var _boost_after: float = 0.0
var _ring_next: float = 0.0
var _rings: Array = []       ## 风压圈：[第几帧出现, 脚下位置]
var _ink_on: bool = false
# 节点
var _grade_copy: BackBufferCopy
var _grade: Node2D
var _grade_mat: ShaderMaterial
var _lo: Node2D              ## 角色身后：风压圈、刀光、刀光碎块
var _hi: Node2D              ## 角色前面：斩痕、爆炸、悬空碎片、碎屑、收刀亮光
var _paper: Node2D
var _ink_copy: BackBufferCopy
var _ink: Node2D
var _ink_mat: ShaderMaterial
var _split_copy: BackBufferCopy
var _split: Node2D
var _split_mat: ShaderMaterial
var _ui: CanvasLayer         ## 屏幕坐标、盖在 HUD 上面：集中线、切入带、白屏 / 黑屏
var _ui_back: Node2D
var _ui_sil: Node2D
var _ui_front: Node2D
# 刀光：一段大圆弧（圆心、半径、起止角）+ 三个抖动变体
var _arc_c := Vector2.ZERO
var _arc_r: float = 1.0
var _arc_a0: float = 0.0
var _arc_a1: float = 0.0
var _vn: Array = []
var _shattered: bool = false
var _pieces: Array = []      ## 碎开的刀光段：{u0, u1, v, spin, born}
var _flakes: Array = []      ## 碎屑：{p, v, born, life, size, a, spin, col, sway}
var _shards: Array = []      ## 定格时悬空的碎片
var _targets: Array = []     ## {node, pt, ang, pop, done, sc}
var _booms: Array = []       ## {pt, born, seed, sc}
var _glints: Array = []      ## 收刀亮光：[位置, 第几帧]
var _click: int = 38
var _clicked: bool = false


func _ready() -> void:
	z_index = 20
	process_priority = 10           # 在像素特效之后跑：黑白那几帧要压住辉光
	rng.randomize()
	_grade_copy = _copy(-3)
	_grade = _layer(-3, GRADE_SHADER)     # 地形（−70）之后、刀光（−2）/ 残影（−1）/ 角色（0）之前
	_grade_mat = _grade.material as ShaderMaterial
	_grade.draw.connect(func(): _grade.draw_rect(Rect2(-VIEW * 0.6, VIEW * 1.2), Color.WHITE))
	_lo = _world(-2)
	_lo.draw.connect(_draw_lo)
	_hi = _world(18)                      # 角色之上、伤害数字（35）之下
	_hi.draw.connect(_draw_hi)
	_paper = _layer(-74)                  # 夜景像素化（−75）之上、地形（−70）之下：地形也变墨色剪影
	_paper.draw.connect(func(): _paper.draw_rect(Rect2(-VIEW * 0.6, VIEW * 1.2), PAPER))
	_ink_copy = _copy(39)
	_ink = _layer(40, INK_SHADER)
	_ink_mat = _ink.material as ShaderMaterial
	_ink.draw.connect(func(): _ink.draw_rect(Rect2(-VIEW * 0.6, VIEW * 1.2), Color.WHITE))
	_split_copy = _copy(44)
	_split = _layer(45, SPLIT_SHADER)
	_split_mat = _split.material as ShaderMaterial
	_split.draw.connect(func(): _split.draw_rect(Rect2(-VIEW * 0.6, VIEW * 1.2), Color.WHITE))
	_ui = CanvasLayer.new()
	_ui.layer = 11                        # HUD 是 10
	add_child(_ui)
	_ui_back = Node2D.new()
	_ui.add_child(_ui_back)
	_ui_back.draw.connect(_draw_ui_back)
	_ui_sil = Node2D.new()
	var sm := ShaderMaterial.new()
	sm.shader = SIL_SHADER
	_ui_sil.material = sm
	_ui_sil.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_ui.add_child(_ui_sil)
	_ui_sil.draw.connect(_draw_ui_sil)
	_ui_front = Node2D.new()
	_ui.add_child(_ui_front)
	_ui_front.draw.connect(_draw_ui_front)


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


## 直接用世界坐标画的层（不跟着本节点挪）
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


# ---------------------------------------------------------------- 对外

## 起手（主角 ult_started）
func begin() -> void:
	clear()
	_phase = 1
	_f = 0.0
	_dir = 1.0
	if _okp() and player.get("facing") != null:
		_dir = 1.0 if int(player.facing) >= 0 else -1.0
	_cam = get_viewport().get_camera_2d()
	_zoom0 = _cam.zoom if _cam != null else Vector2.ZERO
	_ring_next = 0.0
	_windup_burst()


func clear() -> void:
	_restore_zoom()
	_phase = 0
	_f = 0.0
	_s = 0.0
	_grade_k = 0.0
	_boost_after = 0.0
	_star_done = false
	_rings.clear()
	_pieces.clear()
	_flakes.clear()
	_shards.clear()
	_targets.clear()
	_booms.clear()
	_glints.clear()
	_vn.clear()
	_shattered = false
	_set_ink(false, false)
	_split.visible = false
	_split_copy.visible = false
	_grade.visible = false
	_grade_copy.visible = false
	_hud_k = 1.0
	_apply_hud()
	if is_instance_valid(fx):
		fx.blade_boost = 0.0
		fx.blade_seg = Vector4.ZERO


## 第 i 个被砍中的影（按离主角远近排）出刀后多久爆开；click = 主角的 ult_click_frame（收刀“咔”在出刀后第几帧）
static func pop_delay(i: int, click: int = 38) -> float:
	return float(click + 2 + POP_GAP * i) / 60.0


## 出刀（黑屏那一帧）。center_y = 主角胸口高度；dir = 朝向；targets = [{node, pt}]（近的在前）；
## from_x = 冲刺之前主角站在哪（刀光从那儿身后一直拉到现在身前）
func slash(center_y: float, dir: int, targets: Array = [], from_x: float = NAN) -> void:
	_restore_zoom()
	_phase = 2
	_s = 0.0
	_s_run = false
	_dir = 1.0 if dir >= 0 else -1.0
	_boost_after = 1.0
	_shattered = false
	_pieces.clear()
	_flakes.clear()
	_booms.clear()
	_glints.clear()
	_rings.clear()
	_clicked = false
	_click = int(player.get("ult_click_frame")) if _okp() and player.get("ult_click_frame") != null else 38
	var w := _px()
	var to_x: float = player.global_position.x if _okp() else global_position.x
	if is_nan(from_x):
		from_x = to_x
	# 刀光的圆弧：起点身后 → 终点身前，往前微微上扬，往上拱一点
	var a := Vector2(from_x - _dir * 330.0 * w, center_y + 34.0 * w)
	var b := Vector2(to_x + _dir * 430.0 * w, center_y - 52.0 * w)
	var chord := b - a
	var L := maxf(chord.length(), 1.0)
	var t := chord / L
	var up := Vector2(t.y, -t.x) * _dir
	var sag := 0.045 * L
	_arc_r = (L * L * 0.25 + sag * sag) / (2.0 * sag)
	_arc_c = (a + b) * 0.5 + up * (sag - _arc_r)
	_arc_a0 = (a - _arc_c).angle()
	_arc_a1 = _arc_a0 + wrapf((b - _arc_c).angle() - _arc_a0, -PI, PI)
	# 三个抖动变体（定格时一拍二轮流换，像手绘的线在“呼吸”）
	_vn.clear()
	for v in 3:
		var e := PackedFloat32Array()
		var tm := PackedFloat32Array()
		var ph := [rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU]
		for i in N + 1:
			var u := float(i) / float(N)
			e.append(0.8 * sin(u * TAU * 3.0 + ph[0]) + 0.6 * sin(u * TAU * 7.0 + ph[1]))
			tm.append(1.0 + 0.08 * sin(u * TAU * 2.0 + ph[2]) + 0.05 * sin(u * TAU * 5.0 + ph[3]))
		var notches := []
		for k in 3:
			notches.append(Vector2(rng.randf_range(0.14, 0.86), rng.randf_range(0.35, 0.6)))
		_vn.append({"e": e, "t": tm, "n": notches, "ph": rng.randf() * TAU})
	# 冲刺路上一串残影（身体轮廓，越靠起点越淡）
	if _ok() and absf(to_x - from_x) > 40.0 and fx.has_method("ghost_line"):
		var spr := player.get_node_or_null("Visual/ActorSprite") as Sprite2D
		if spr != null:
			var dv := Vector2(to_x - from_x, 0.0)
			fx.ghost_line(spr, spr.global_position - dv, spr.global_position - dv * 0.12, 6, VIO_L)
	# 悬空碎片：刀痕两边，定格时几乎不动，碎开后往下掉
	_shards.clear()
	for i in 14:
		var u := rng.randf_range(0.08, 0.95)
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var p := _ap(u) - _up(u) * _thick(u, 0, 1.0) * 0.5 + _up(u) * side * (_thick(u, 0, 1.0) * 0.5 + rng.randf_range(6.0, 44.0) * w)
		_shards.append({"p": p, "v": Vector2(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.35, 0.1)) * w,
			"size": rng.randf_range(4.0, 12.0), "a": rng.randf() * TAU, "spin": rng.randf_range(-0.12, 0.12),
			"col": [WHITE, VIO_L, INK, VIO_L, INK][rng.randi() % 5]})
	# 被砍中的影：出刀后身上一道斩痕，收刀“咔”之后由近到远一个接一个爆
	_targets.clear()
	var i := 0
	for tg in targets:
		var pt: Vector2 = tg.pt
		var node = tg.get("node")
		var sc := 1.0
		if node is Node2D and is_instance_valid(node) and node.get("half_h") != null:
			sc = clampf(float(node.half_h) / 62.0, 0.9, 1.3)
		var u := _u_at(pt.x)
		_targets.append({"node": node, "pt": pt, "ang": _tangent(u).angle() + rng.randf_range(0.35, 0.6) * (1.0 if rng.randf() < 0.5 else -1.0),
			"pop": float(_click + 2 + POP_GAP * i), "done": false, "sc": sc})
		i += 1


func busy() -> bool:
	return _phase != 0


# ---------------------------------------------------------------- 每帧

func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		global_position = cam.get_screen_center_position()
	var df := delta * 60.0
	if _phase == 1:
		_tick_charge(df)
	elif _phase == 2:
		_tick_after(df)
	_tick_blade_glow(delta)
	_update_grade(df)
	_update_hud(df)
	_lo.queue_redraw()
	_hi.queue_redraw()
	_ui_back.queue_redraw()
	_ui_sil.queue_redraw()
	_ui_front.queue_redraw()


func _tick_charge(df: float) -> void:
	if _okp() and player.has_method("is_ult"):
		if player.is_ult():
			_f = float(player.ult_frame)
		elif _f > 2.0:
			clear()          # 大招被打断（重开 / 死了）
			return
		else:
			_f += df
	else:
		_f += df
	var cf := float(_charge_f())
	if CAM_PUSH > 0.0 and is_instance_valid(_cam) and _zoom0 != Vector2.ZERO:
		var k := clampf(_f / cf, 0.0, 1.0)
		_cam.zoom = _zoom0 * (1.0 + CAM_PUSH * (1.0 - pow(1.0 - k, 3.0))) if _f < float(_hit_f() - 1) else _zoom0
	while _f >= _ring_next and _ring_next < cf - 4.0:
		_rings.append([_ring_next, _feet() if _okp() else global_position])
		_ring_next += 6.0
	if _f < cf:
		_windup_particles(clampf(_f / cf, 0.0, 1.0))


func _tick_after(df: float) -> void:
	if _s_run:
		_s += df
	_s_run = true
	var si := int(_s)
	var ng: int = int(NEG.get(si, -1))
	_set_ink(ng >= 0, ng == 1)
	# 画面沿刀痕错开：定格时错开 → 碎开时合上
	var k := smoothstep(5.0, 8.0, _s) * (1.0 - smoothstep(float(S_SHATTER), float(S_SHATTER) + 7.0, _s))
	var on := k > 0.02
	_split.visible = on
	_split_copy.visible = on
	if on:
		_split_mat.set_shader_parameter("center", _arc_c)
		_split_mat.set_shader_parameter("radius", _arc_r - _thick(0.6, 0, 1.0) * 0.35)
		_split_mat.set_shader_parameter("amount", SPLIT_PX * k)
		_split_mat.set_shader_parameter("dir", _dir)
		_split_mat.set_shader_parameter("seam", 2.0 * _px() * k)
		_split.queue_redraw()
	if not _shattered and _s >= float(S_SHATTER):
		_shatter()
	# 碎块掉完了变碎屑
	var keep: Array = []
	for pc in _pieces:
		if _s - float(pc.born) < 16.0:
			keep.append(pc)
		elif _ok():
			for j in 3:
				_flake(_ap(rng.randf_range(float(pc.u0), float(pc.u1))) + _piece_off(pc, 16.0), 0.0)
	_pieces = keep
	_flakes = _flakes.filter(func(fl): return _s - float(fl.born) < float(fl.life))
	if not _clicked and _s >= float(_click):
		_clicked = true
		var hp := _hip()
		_glints.append([hp, _s])
		sheathed.emit(hp)
	for tg in _targets:
		if not tg.done and _s >= float(tg.pop):
			tg.done = true
			_pop(tg)
	if _s > 72.0 and _targets.all(func(t): return t.done) and _flakes.is_empty() \
			and _booms.all(func(b): return _s - float(b.born) > 26.0):
		var keep_hud := _hud_k
		clear()
		_hud_k = keep_hud
		_apply_hud()


func _update_grade(df: float) -> void:
	var want := 0.0
	if _phase == 1:
		want = 1.0
	elif _phase == 2:
		want = 1.0 - smoothstep(44.0, 80.0, _s)
	_grade_k = move_toward(_grade_k, want, df * (0.12 if want > _grade_k else 1.0))
	if _phase == 2:
		_grade_k = want
	var on := _grade_k > 0.002 and not _ink_on
	_grade.visible = on
	_grade_copy.visible = on
	if on:
		_grade_mat.set_shader_parameter("amount", _grade_k)
		_grade.queue_redraw()


func _update_hud(df: float) -> void:
	var want := 1.0
	if _phase == 1 or (_phase == 2 and _s < 42.0):
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


func _set_ink(on: bool, inv: bool) -> void:
	_ink_on = on
	_paper.visible = on
	_ink.visible = on
	_ink_copy.visible = on
	if on:
		_ink_mat.set_shader_parameter("invert", inv)
		_paper.queue_redraw()
		_ink.queue_redraw()
		if is_instance_valid(fx):
			fx.pfx.bloom.visible = false
			fx._impact.visible = false


func _restore_zoom() -> void:
	if is_instance_valid(_cam) and _zoom0 != Vector2.ZERO:
		_cam.zoom = _zoom0
	_zoom0 = Vector2.ZERO


# ---------------------------------------------------------------- ① 蓄力

func _windup_burst() -> void:
	if not _ok():
		return
	var feet := _feet()
	var w := _px()
	for side: float in [-1.0, 1.0]:
		for i in 3:
			var q := feet + Vector2(side * _r(6.0, 40.0), -_r(1.0, 12.0)) * w
			# 只有贴地往两边冲的风线（§16.12 去掉了地面扬尘）
			fx._streak(q, _r(30.0, 70.0), _r(1.6, 2.6), 0.0 if side > 0.0 else PI,
				VIO_L, WHITE, _r(0.22, 0.34), _r(0.0, 0.06),
				0.0, Vector2(side * _r(300.0, 520.0), 0.0))


func _windup_particles(k: float) -> void:
	if not _ok():
		return
	var w := _px()
	var b := _blade()
	var target: Vector2 = (b[0] as Vector2).lerp(b[1], 0.35) if not b.is_empty() else player.global_position
	# 光丝往刀上聚（比 §16.11 少很多：主角是集中线）
	if k < 0.86 and rng.randf() < 0.25 + 0.5 * k:
		var f = fx.pfx.add(K.WISP, target, _r(0.2, 0.32) * (1.0 - 0.35 * k))
		f.a = _r(46.0, 120.0) * w
		f.b = _r(1.4, 2.4) * w
		f.c = _r(0.0, TAU)
		f.d = _r(1.2, 2.6) * (1.0 if rng.randf() < 0.5 else -1.0)
		f.squash = _r(0.12, 0.3)
		f.c1 = VIO if rng.randf() < 0.6 else VIO_L
		f.c0 = WHITE
	# 刀尖“叮”
	if k >= 0.8 and not _star_done and not b.is_empty():
		_star_done = true
		var along: float = ((b[1] as Vector2) - (b[0] as Vector2)).angle()
		fx._star(b[1], 40.0, along, 2.6, VIO_L, WHITE, 0.24, 0.0, 0.5)
		fx._disc(b[1], 6.0, WHITE, 0.06)


## 刀身从柄到尖点亮（fx_glow_sprite 的 blade / sweep / boost）；出刀后很快退掉
func _tick_blade_glow(delta: float) -> void:
	if not _ok():
		return
	var boost := 0.0
	var sweep := 1.0
	if _phase == 1:
		var k := clampf(_f / float(_charge_f()), 0.0, 1.0)
		var b := _blade()
		if not b.is_empty():
			fx.blade_seg = b[2]
			sweep = smoothstep(0.08, 0.78, k)
			boost = 2.4 * smoothstep(0.0, 0.45, k)
	elif _boost_after > 0.0:
		_boost_after = maxf(_boost_after - delta * 6.0, 0.0)
		boost = 2.4 * _boost_after
		if _boost_after <= 0.0:
			fx.blade_seg = Vector4.ZERO
	fx.blade_sweep = sweep
	fx.blade_boost = boost


# ---------------------------------------------------------------- 刀光几何

func _ap(u: float) -> Vector2:
	return _arc_c + Vector2.from_angle(lerpf(_arc_a0, _arc_a1, u)) * _arc_r


## 刃口朝外那一侧（往上）
func _up(u: float) -> Vector2:
	return Vector2.from_angle(lerpf(_arc_a0, _arc_a1, u))


## 沿刀光往前（主角冲的方向）
func _tangent(u: float) -> Vector2:
	var n := _up(u)
	var t := Vector2(-n.y, n.x)
	return t if t.x * _dir >= 0.0 else -t


## 世界 x 在刀光的哪儿（0..1）
func _u_at(x: float) -> float:
	var x0 := _ap(0.0).x
	var x1 := _ap(1.0).x
	return clampf((x - x0) / (x1 - x0) if absf(x1 - x0) > 1.0 else 0.5, 0.0, 1.0)


## 粗细的形状：尾巴细长、前头稍短，最宽在 0.6
static func _shape(u: float) -> float:
	if u <= 0.0 or u >= 1.0:
		return 0.0
	return pow(u, 1.3) * pow(1.0 - u, 0.85) / (pow(0.605, 1.3) * pow(0.395, 0.85))


static func _vs(a: PackedFloat32Array, u: float) -> float:
	var x := clampf(u, 0.0, 1.0) * float(a.size() - 1)
	var i := mini(int(x), a.size() - 2)
	return lerpf(a[i], a[i + 1], x - float(i))


func _thick(u: float, v: int, m: float) -> float:
	var t := 1.0
	if v < _vn.size():
		t = _vs(_vn[v].t, u)
	return BLADE_W * _px() * m * _shape(u) * t


## 第 li 层往里占多少（缺口：浅紫 / 紫两层的里沿有几个 V 形豁口，像手绘）
func _lay(vn: Dictionary, u: float, li: int, notchy: bool) -> float:
	var k := 1.0 + 0.06 * sin(u * TAU * 4.0 + float(vn.ph) + float(li) * 1.7)
	if notchy:
		for nt: Vector2 in vn.n:
			k *= 1.0 - nt.y * maxf(0.0, 1.0 - absf(u - nt.x - 0.01 * float(li)) / 0.028)
	return k


# ---------------------------------------------------------------- ④ 一闪 / ⑤ 定格 / ⑥ 碎开

func _draw_lo() -> void:
	var w := _px()
	# 风压圈（蓄力时脚下一圈圈往外推）
	if _phase == 1:
		for rg in _rings:
			var age := floorf((_f - float(rg[0])) / 2.0) * 2.0
			if age < 0.0 or age > 18.0:
				continue
			var k := age / 18.0
			var e := 1.0 - pow(1.0 - k, 2.2)
			var rx := (26.0 + 250.0 * e) * w
			var col := Color(VIO_L if int(rg[0]) % 12 == 0 else WHITE, 0.85 * (1.0 - k))
			_ellipse(_lo, rg[1], rx, rx * 0.17, col, (4.0 - 3.0 * k) * w)
			if age < 5.0:
				_ellipse(_lo, rg[1], rx * 0.6, rx * 0.1, Color(WHITE, 0.7), 2.0 * w)
		return
	if _phase != 2 or _vn.is_empty():
		return
	var si := int(_s)
	if si < S_THIN:
		return
	if si < S_WIDE:
		# 尖细：一根细长的亮线，两头的白针伸得更长
		_band(_lo, 0.0, 1.0, 0.24, 0, LAYERS_THIN, 0.5, Transform2D.IDENTITY)
		_needles(0.12, 2.4)
	elif si < S_SHATTER:
		var v := 0 if si < S_FREEZE else (si / 2) % 3
		var m := 1.0 if si < S_FREEZE else lerpf(1.0, 0.86, float(si - S_FREEZE) / float(S_SHATTER - S_FREEZE))
		_band(_lo, 0.0, 1.0, m, v, LAYERS, 1.0, Transform2D.IDENTITY)
		_needles(0.06, 1.8)
		_residual(si)
	for pc in _pieces:
		var age := floorf((_s - float(pc.born)) / 2.0) * 2.0      # 一拍二
		var m := 0.84 * (1.0 - age / 16.0)
		if m <= 0.05:
			continue
		var g := 0.004 + 0.003 * age
		var u0: float = float(pc.u0) + g
		var u1: float = float(pc.u1) - g
		if u1 <= u0:
			continue
		var c := _ap((u0 + u1) * 0.5)
		var xf := Transform2D(float(pc.spin) * age, c + _piece_off(pc, age)) * Transform2D(0.0, -c)
		_band(_lo, u0, u1, m, (int(pc.born) + int(age / 2.0)) % 3, LAYERS, 0.5 * m, xf)


## 一段刀光（赛璐璐硬分层）：u0..u1，粗细倍数 m，第 v 个变体；xf = 碎块的位移 / 旋转
func _band(cv: CanvasItem, u0: float, u1: float, m: float, v: int, layers: Array, glow: float, xf: Transform2D) -> void:
	var w := _px()
	var vn: Dictionary = _vn[v]
	var n := maxi(int(ceil((u1 - u0) * float(N))), 2)
	var ed := PackedVector2Array()
	var nr := PackedVector2Array()
	var th := PackedFloat32Array()
	var us := PackedFloat32Array()
	for i in n + 1:
		var u := lerpf(u0, u1, float(i) / float(n))
		var up := _up(u)
		ed.append(xf * (_ap(u) + up * _vs(vn.e, u) * w))
		nr.append(xf.basis_xform(up))
		th.append(_thick(u, v, m))
		us.append(u)
	# 光晕：外沿往外一层浅紫、最里沿往里一层深紫，都往外淡；不压在刃口上
	if glow > 0.0:
		var co := Color(VIO_L, 0.3 * glow)
		var co0 := Color(VIO_L, 0.0)
		var ci := Color(VIO_D, 0.42 * glow)
		var ci0 := Color(VIO_D, 0.0)
		for i in n:
			var h0 := 4.0 * w * minf(th[i] / w, 1.0) + 0.14 * th[i]
			var h1 := 4.0 * w * minf(th[i + 1] / w, 1.0) + 0.14 * th[i + 1]
			_quad(cv, ed[i], ed[i + 1], ed[i + 1] + nr[i + 1] * h1, ed[i] + nr[i] * h0, co, co, co0, co0)
			var b0 := ed[i] - nr[i] * th[i]
			var b1 := ed[i + 1] - nr[i + 1] * th[i + 1]
			var g0 := 10.0 * w * minf(th[i] / w, 1.0) + 0.3 * th[i]
			var g1 := 10.0 * w * minf(th[i + 1] / w, 1.0) + 0.3 * th[i + 1]
			_quad(cv, b0, b1, b1 - nr[i + 1] * g1, b0 - nr[i] * g0, ci, ci, ci0, ci0)
	for li in layers.size():
		var lay: Array = layers[li]
		var col: Color = lay[0]
		var fr: float = lay[1]
		var notchy: bool = int(lay[2]) == 1
		for i in n:
			var d0 := th[i] * fr * _lay(vn, us[i], li, notchy)
			var d1 := th[i + 1] * fr * _lay(vn, us[i + 1], li, notchy)
			if d0 < 0.2 and d1 < 0.2:
				continue
			_quad(cv, ed[i], ed[i + 1], ed[i + 1] - nr[i + 1] * d1, ed[i] - nr[i] * d0, col, col, col, col)


## 两头伸出去的白针（刃口最尖的那一点）
func _needles(ext: float, px: float) -> void:
	var w := _px()
	for side in 2:
		var ua := -ext if side == 0 else 0.93
		var ub := 0.07 if side == 0 else 1.0 + ext * 0.8
		var n := 10
		for i in n:
			var t0 := float(i) / float(n)
			var t1 := float(i + 1) / float(n)
			var q0 := lerpf(ua, ub, t0)
			var q1 := lerpf(ua, ub, t1)
			var d0 := px * w * (t0 if side == 0 else 1.0 - t0)
			var d1 := px * w * (t1 if side == 0 else 1.0 - t1)
			var e0 := _ap(q0)
			var e1 := _ap(q1)
			_quad(_lo, e0, e1, e1 - _up(q1) * d1, e0 - _up(q0) * d0, WHITE, WHITE, WHITE, WHITE)


## 最多两根细残影线：刃口外面平行的细线，往外漂、变淡
func _residual(si: int) -> void:
	if si < S_WIDE or si > 16:
		return
	var w := _px()
	var k := float(si - S_WIDE) / 13.0
	for j in 2:
		var off := (10.0 + 13.0 * float(j) + 10.0 * k) * w
		var ua := 0.2 + 0.14 * float(j)
		var ub := 0.97 - 0.06 * float(j)
		var lw := (2.4 - 0.8 * float(j)) * w * (1.0 - 0.5 * k)
		var col := Color(WHITE if j == 0 else VIO_L, 1.0 - k)
		var n := 30
		for i in n:
			var q0 := lerpf(ua, ub, float(i) / float(n))
			var q1 := lerpf(ua, ub, float(i + 1) / float(n))
			var s0 := sin(PI * float(i) / float(n))
			var s1 := sin(PI * float(i + 1) / float(n))
			var e0 := _ap(q0) + _up(q0) * off
			var e1 := _ap(q1) + _up(q1) * off
			_quad(_lo, e0, e1, e1 - _up(q1) * lw * s1, e0 - _up(q0) * lw * s0, col, col, col, col)


func _shatter() -> void:
	_shattered = true
	var u := 0.0
	while u < 1.0:
		var u1 := minf(u + _r(0.08, 0.16), 1.0)
		if 1.0 - u1 < 0.05:
			u1 = 1.0
		_pieces.append({"u0": u, "u1": u1, "born": _s, "spin": _r(-0.012, 0.012),
			"v": Vector2(_dir * _r(-0.6, 1.2), _r(-0.4, 0.3)) * _px()})
		u = u1
	if _ok():
		for i in 30:
			var q := rng.randf_range(0.05, 0.97)
			_flake(_ap(q) - _up(q) * _thick(q, 0, 1.0) * rng.randf(), rng.randf_range(0.0, 8.0))


func _piece_off(pc: Dictionary, age: float) -> Vector2:
	return (pc.v as Vector2) * age + Vector2(0.0, 0.05 * age * age * _px())


func _flake(p: Vector2, delay: float) -> void:
	var w := _px()
	_flakes.append({"p": p, "v": Vector2(_r(-0.5, 0.5), _r(0.2, 0.9)) * w, "born": _s + delay, "life": _r(36.0, 70.0),
		"size": _r(3.0, 7.0), "a": _r(0.0, TAU), "spin": _r(-0.2, 0.2), "sway": _r(4.0, 12.0) * w,
		"col": [WHITE, VIO_L, VIO_L, VIO][rng.randi() % 4]})


func _hip() -> Vector2:
	if not _okp():
		return global_position
	return player.global_position + Vector2(-_dir * 8.0, float(player.foot_offset) * 0.22)


# ---------------------------------------------------------------- 角色前面：斩痕 / 爆炸 / 碎片 / 碎屑 / 收刀亮光

func _draw_hi() -> void:
	if _phase != 2:
		return
	var w := _px()
	var si := int(_s)
	# 斩痕：出刀后每只影身上一道斜的白缝，撑到它爆开
	if si >= S_WIDE:
		for tg in _targets:
			if tg.done:
				continue
			var a: float = tg.ang
			var L: float = 54.0 * w * float(tg.sc)
			var h := (3.2 + (0.8 if (si / 2) % 2 == 0 else 0.0)) * w
			_diamond(_hi, tg.pt, a, L * 1.15, h * 2.4, VIO_D)
			_diamond(_hi, tg.pt, a, L, h, WHITE)
	# 悬空碎片：定格时慢慢漂，碎开后往下掉、变小
	for sh in _shards:
		var age := floorf(_s / 2.0) * 2.0
		var fall := maxf(age - float(S_SHATTER), 0.0)
		var size: float = float(sh.size) * (1.0 - clampf(fall / 36.0, 0.0, 1.0))
		if size < 1.0 or si < S_WIDE:
			continue
		var p: Vector2 = (sh.p as Vector2) + (sh.v as Vector2) * age + Vector2(0.0, 0.06 * fall * fall * w)
		_tri(_hi, p, float(sh.a) + float(sh.spin) * age, size * w, sh.col)
	for fl in _flakes:
		var age := floorf((_s - float(fl.born)) / 2.0) * 2.0
		if age < 0.0:
			continue
		var k := age / float(fl.life)
		var p: Vector2 = (fl.p as Vector2) + (fl.v as Vector2) * age + Vector2(sin(age * 0.12 + float(fl.a)) * float(fl.sway), 0.0)
		_tri(_hi, p, float(fl.a) + float(fl.spin) * age, float(fl.size) * w * (1.0 - 0.6 * k), Color(fl.col, 1.0 - k * k))
	for gl in _glints:
		var k := int((_s - float(gl[1])) / 2.0)
		if k > 4:
			continue
		var p: Vector2 = gl[0]
		var g := [0.7, 1.25, 1.0, 0.7, 0.4][k] as float
		_diamond(_hi, p, 0.0, 50.0 * w * g, 9.0 * w * g, Color(VIO_L, 0.8))
		_diamond(_hi, p, 0.0, 34.0 * w * g, 3.0 * w * g, WHITE)
		_diamond(_hi, p, PI * 0.5, 16.0 * w * g, 2.6 * w * g, WHITE)
		if k >= 1 and k <= 3:
			_hi.draw_arc(p, (10.0 + 9.0 * float(k)) * w, 0.0, TAU, 24, Color(WHITE, 0.9 - 0.25 * float(k)), (2.2 - 0.4 * float(k)) * w)
	for b in _booms:
		_draw_boom(b)


## ⑥ 爆开：白闪 → 尖角星形（白 / 浅紫 / 紫 / 深紫）一拍二变形 → 紫 → 深紫烟团
func _pop(tg: Dictionary) -> void:
	var pt: Vector2 = tg.pt
	_booms.append({"pt": pt, "born": _s, "seed": rng.randi(), "sc": float(tg.sc)})
	if _ok():
		fx._sparks(pt, 4, float(tg.ang), PI, 260.0, 640.0, 0.14, 0.28, [WHITE, VIO_L, VIO], 400.0, 2.5)
		fx.glow_hit(1.0)
	var node = tg.get("node")
	if node is Node2D and is_instance_valid(node):
		if node.get("flash") != null:
			node.set("flash", 5)
		popped.emit(node, pt)
	else:
		popped.emit(null, pt)


func _draw_boom(b: Dictionary) -> void:
	var age := _s - float(b.born)
	var k := int(age / 2.0)
	if k > 12:
		return
	var w := _px() * float(b.sc) * BOOM_SCALE
	var p: Vector2 = b.pt
	var r := RandomNumberGenerator.new()
	r.seed = int(b.seed) + k * 7919
	if k <= 2:
		var sp := _spikes(r, 9)
		if k == 0:
			_hi.draw_circle(p, 30.0 * w, WHITE)
			_star(p, sp, 86.0 * w, 30.0 * w, 0.0, WHITE)
			_hi.draw_arc(p, 46.0 * w, 0.0, TAU, 32, WHITE, 5.0 * w)
		else:
			var g := 1.0 if k == 1 else 1.18
			_star(p, sp, 140.0 * w * g, 60.0 * w * g, 0.0, VIO_D)
			_star(p, sp, 116.0 * w * g, 48.0 * w * g, 0.05, VIO)
			_star(p, sp, (84.0 if k == 1 else 66.0) * w * g, 36.0 * w * g, 0.1, VIO_L)
			_star(p, sp, (54.0 if k == 1 else 28.0) * w, 22.0 * w * (1.0 if k == 1 else 0.6), 0.15, WHITE)
			_hi.draw_arc(p, (104.0 + 44.0 * float(k - 1)) * w * g, 0.0, TAU, 40, Color(WHITE, 0.9 - 0.3 * float(k)), (3.6 - 1.2 * float(k)) * w)
	else:
		# 烟团：位置每只固定（用 seed），一拍二长大 → 变暗 → 缩没
		var q := float(k - 3)
		var r2 := RandomNumberGenerator.new()
		r2.seed = int(b.seed)
		var grow := (1.0 + 0.12 * q) if q <= 3.0 else 1.36 * (1.0 - (q - 3.0) / 6.5)
		for j in 6:
			var ang := TAU * (float(j) + r2.randf_range(-0.3, 0.3)) / 6.0
			var dist := (24.0 + r2.randf_range(0.0, 20.0) + q * (4.0 + r2.randf_range(0.0, 4.0))) * w
			var rad := (36.0 + r2.randf_range(-8.0, 10.0)) * w * grow
			if rad <= 2.0 * w:
				continue
			var c := p + Vector2.from_angle(ang) * dist + Vector2(0.0, -q * 5.0 * w)
			var base := VIO
			var shade := VIO_D
			if q >= 5.0:
				base = SMOKE
				shade = SMOKE_D
			elif q >= 2.0:
				base = VIO_D
				shade = SMOKE
			_hi.draw_circle(c, rad, shade)
			_hi.draw_circle(c + Vector2(-0.2, -0.22) * rad, rad * 0.8, base)
			if q < 2.0:
				_hi.draw_circle(c + Vector2(-0.4, -0.42) * rad, rad * 0.26, VIO_L)
		if q < 2.0:
			_star(p, _spikes(r, 7), 54.0 * w, 22.0 * w, 0.0, VIO_L)
	# 几片白色尖碎片往外飞
	if k <= 5:
		var r3 := RandomNumberGenerator.new()
		r3.seed = int(b.seed) + 17
		for j in 5:
			var a := r3.randf_range(0.0, TAU)
			var d := (30.0 + 26.0 * float(k) + r3.randf_range(0.0, 16.0)) * w
			_tri(_hi, p + Vector2.from_angle(a) * d, a, (15.0 - 2.2 * float(k)) * w, WHITE)


## 星形的尖：[角度, 外尖倍数, 内凹角度, 内凹倍数] × n
func _spikes(r: RandomNumberGenerator, n: int) -> Array:
	var a0 := r.randf() * TAU
	var out := []
	for i in n:
		out.append([a0 + TAU * (float(i) + r.randf_range(-0.18, 0.18)) / float(n), r.randf_range(0.7, 1.12),
			a0 + TAU * (float(i) + 0.5 + r.randf_range(-0.1, 0.1)) / float(n), r.randf_range(0.8, 1.15)])
	return out


func _star(p: Vector2, sp: Array, ro: float, ri: float, twist: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for s in sp:
		pts.append(p + Vector2.from_angle(float(s[0]) + twist) * ro * float(s[1]))
		pts.append(p + Vector2.from_angle(float(s[2]) + twist) * ri * float(s[3]))
	_hi.draw_colored_polygon(pts, col)


# ---------------------------------------------------------------- ①② 屏幕层：集中线 / 切入带 / 白屏黑屏

func _draw_ui_back() -> void:
	if _phase != 1:
		return
	var cf := float(_charge_f())
	if _f < cf + 4.0 and _okp():
		var pc := get_viewport().get_canvas_transform() * (player.global_position + Vector2(0.0, -20.0))
		_conc_lines(pc, clampf(_f / cf, 0.0, 1.0), 1.0 - clampf((_f - cf) / 4.0, 0.0, 1.0))
	var g := _cut_geom()
	if g.is_empty():
		return
	var vs: Vector2 = g.vs
	var c: float = g.c
	_ui_back.draw_rect(Rect2(Vector2.ZERO, vs), Color(INK, 0.5 * minf((c + 1.0) / 3.0, 1.0)))
	var cen: Vector2 = g.cen
	var tx: Vector2 = g.tx
	var ny: Vector2 = g.ny
	var h: float = g.h
	var L: float = g.L
	var ex: float = (g.eye as Vector2 - cen).dot(tx)
	# 带子：两头深紫 → 脸后面亮（浅紫）
	var segs := 18
	for i in segs:
		var x0 := lerpf(-L, L, float(i) / float(segs))
		var x1 := lerpf(-L, L, float(i + 1) / float(segs))
		var c0 := _cut_col(x0 - ex)
		var c1 := _cut_col(x1 - ex)
		_quad(_ui_back, cen + tx * x0 - ny * h * 0.5, cen + tx * x1 - ny * h * 0.5, cen + tx * x1 + ny * h * 0.5, cen + tx * x0 + ny * h * 0.5, c0, c1, c1, c0)
	# 速度线：往主角背后飞
	var r := RandomNumberGenerator.new()
	r.seed = 4242
	for i in 30:
		var y := r.randf_range(-0.46, 0.46) * h
		var len := r.randf_range(140.0, 420.0)
		var spd := r.randf_range(50.0, 110.0)
		var x := wrapf(r.randf_range(-L, L) - _dir * c * spd, -L - len, L)
		var th := r.randf_range(1.5, 3.5) * minf(h / CUT_H, 1.0)
		var col := Color(WHITE, r.randf_range(0.3, 0.75)) if r.randf() < 0.7 else Color(VIO_D, 0.7)
		var p0 := cen + tx * x + ny * y
		_quad(_ui_back, p0 - ny * th * 0.5, p0 + tx * len - ny * th * 0.2, p0 + tx * len + ny * th * 0.2, p0 + ny * th * 0.5, col, col, col, col)


func _cut_col(dx: float) -> Color:
	var t := clampf(1.0 - absf(dx) / 760.0, 0.0, 1.0)
	return VIO_D.lerp(VIO, t).lerp(VIO_L, pow(t, 3.0))


## 剪影：主角这一帧的贴图（只取形状，填墨色），按眼睛对到带子里，放大 SIL_SCALE 倍；带子外面不画（贴图坐标直接按带子四角算）
func _draw_ui_sil() -> void:
	if _phase != 1 or not _okp():
		return
	var g := _cut_geom()
	if g.is_empty():
		return
	var spr := player.get_node_or_null("Visual/ActorSprite") as Sprite2D
	if spr == null or spr.texture == null or String(spr.get("clip_name")) != "charge_slash" or int(spr.get("frame_index")) != 7:
		return
	var tex := spr.texture
	var size := tex.get_size()
	var mirrored := (spr.get_global_transform().x.x < 0.0) != spr.flip_h
	var dimg := -1.0 if mirrored else 1.0
	var cen: Vector2 = g.cen
	var tx: Vector2 = g.tx
	var ny: Vector2 = g.ny
	var h: float = g.h
	var L: float = g.L
	var eye: Vector2 = g.eye
	var ang := tx.angle()
	var pts := PackedVector2Array([cen - tx * L - ny * h * 0.5, cen + tx * L - ny * h * 0.5, cen + tx * L + ny * h * 0.5, cen - tx * L + ny * h * 0.5])
	var uvs := PackedVector2Array()
	for q in pts:
		var v := (q - eye).rotated(-ang) / SIL_SCALE
		uvs.append(Vector2(EYE_7.x + v.x * dimg, EYE_7.y + v.y) / size)
	_ui_sil.draw_polygon(pts, PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE]), uvs, tex)


func _draw_ui_front() -> void:
	var vs := _ui_front.get_viewport_rect().size
	if _phase == 2:
		if int(_s) < S_THIN:
			_ui_front.draw_rect(Rect2(Vector2.ZERO, vs), INK)       # 黑屏
		return
	if _phase != 1:
		return
	if _f >= float(_hit_f() - 1):
		_ui_front.draw_rect(Rect2(Vector2.ZERO, vs), WHITE)         # 白屏
		return
	var g := _cut_geom()
	if g.is_empty():
		return
	var c: float = g.c
	var cen: Vector2 = g.cen
	var tx: Vector2 = g.tx
	var ny: Vector2 = g.ny
	var h: float = g.h
	var L: float = g.L
	var eye: Vector2 = g.eye
	var ang := tx.angle()
	# 眼睛里的光：4 帧后亮起（先冒大一点再回落），之后一拍二微微闪
	if c >= 4.0:
		var ci := int(c)
		var gk := 1.0
		if ci == 4:
			gk = 0.45
		elif ci == 5:
			gk = 1.3
		elif (ci / 2) % 2 == 1:
			gk = 0.9
		gk *= minf(h / CUT_H, 1.0)
		_diamond(_ui_front, eye, ang, 210.0 * gk, 30.0 * gk, Color(VIO, 0.55))
		_diamond(_ui_front, eye, ang, 150.0 * gk, 15.0 * gk, VIO_L)
		_diamond(_ui_front, eye, ang, 104.0 * gk, 7.0 * gk, WHITE)
		_ui_front.draw_line(eye - tx * 560.0 * gk, eye + tx * 560.0 * gk, Color(WHITE, 0.55), 1.5)
		_diamond(_ui_front, eye, ang + PI * 0.5, (70.0 if ci >= 5 and ci <= 8 else 34.0) * gk, 5.0 * gk, WHITE)
	# 带子的边：外面一道墨色粗线、里面一道白细线
	for sgn: float in [-1.0, 1.0]:
		var a := cen - tx * L + ny * h * 0.5 * sgn
		var b := cen + tx * L + ny * h * 0.5 * sgn
		_ui_front.draw_line(a + ny * 3.0 * sgn, b + ny * 3.0 * sgn, INK, 6.0)
		_ui_front.draw_line(a, b, WHITE, 2.5)


## 切入带的位置 / 大小（还没到切入或已经过了 → 空）
func _cut_geom() -> Dictionary:
	var cf := float(_charge_f())
	var end := float(_hit_f() - 1)
	if _phase != 1 or _f < cf or _f >= end:
		return {}
	var vs := _ui_back.get_viewport_rect().size
	var c := _f - cf
	var dur := end - cf
	var h := CUT_H
	if c < 3.0:
		h *= (floorf(c) + 1.0) / 3.0
	elif c >= dur - 4.0:
		h *= clampf((dur - floorf(c)) / 4.0, 0.0, 1.0) * 0.9
	var tx := Vector2.from_angle(-CUT_TILT * _dir)
	var ny := Vector2(-tx.y, tx.x)
	var cen := Vector2(vs.x * 0.5, vs.y * CUT_Y)
	var eye := cen - tx * _dir * (150.0 - 1.2 * c) + ny * 24.0
	return {"vs": vs, "c": c, "cen": cen, "tx": tx, "ny": ny, "h": maxf(h, 2.0), "L": vs.x * 0.8, "eye": eye}


## 集中线：从屏幕四周往主角收的尖三角，每 2 帧换一组（= 闪）；越到后面越多、越往里
func _conc_lines(pc: Vector2, k: float, fade: float) -> void:
	if fade <= 0.0:
		return
	var r := RandomNumberGenerator.new()
	r.seed = 1000 + int(_f / 2.0)
	var n := int(lerpf(30.0, 64.0, k))
	var rin := lerpf(560.0, 330.0, k)
	# 四周压暗一圈
	var segs := 36
	var e0 := Color(INK, 0.0)
	var e1 := Color(INK, 0.5 * fade * (0.4 + 0.6 * k))
	for i in segs:
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		var d0 := Vector2.from_angle(a0)
		var d1 := Vector2.from_angle(a1)
		_quad(_ui_back, pc + Vector2(d0.x * rin * 1.3, d0.y * rin * 0.8), pc + Vector2(d1.x * rin * 1.3, d1.y * rin * 0.8), pc + d1 * 1700.0, pc + d0 * 1700.0, e0, e0, e1, e1)
	for i in n:
		var a := TAU * (float(i) + r.randf()) / float(n)
		var d := Vector2.from_angle(a)
		var ri := rin * r.randf_range(0.9, 1.5)
		var tip := pc + Vector2(d.x * ri, d.y * ri * 0.66)
		var far := pc + d * 1700.0
		var side := Vector2(-d.y, d.x) * r.randf_range(2.0, 9.0) * (0.7 + 0.6 * k)
		var col := Color(WHITE if r.randf() < 0.75 else VIO_L, fade * r.randf_range(0.35, 0.85) * (0.5 + 0.5 * k))
		_ui_back.draw_colored_polygon(PackedVector2Array([tip, far + side, far - side]), col)


# ---------------------------------------------------------------- 小零件

func _quad(cv: CanvasItem, a: Vector2, b: Vector2, c: Vector2, d: Vector2, ca: Color, cb: Color, cc: Color, cd: Color) -> void:
	cv.draw_primitive(PackedVector2Array([a, b, c, d]), PackedColorArray([ca, cb, cc, cd]), PackedVector2Array())


func _diamond(cv: CanvasItem, p: Vector2, a: float, len: float, h: float, col: Color) -> void:
	var t := Vector2.from_angle(a)
	var n := Vector2(-t.y, t.x)
	cv.draw_primitive(PackedVector2Array([p - t * len * 0.5, p - n * h * 0.5, p + t * len * 0.5, p + n * h * 0.5]),
		PackedColorArray([col, col, col, col]), PackedVector2Array())


func _tri(cv: CanvasItem, p: Vector2, a: float, s: float, col: Color) -> void:
	cv.draw_primitive(PackedVector2Array([p + Vector2.from_angle(a) * s, p + Vector2.from_angle(a + 2.4) * s * 0.45,
		p + Vector2.from_angle(a - 2.4) * s * 0.45]), PackedColorArray([col, col, col]), PackedVector2Array())


func _ellipse(cv: CanvasItem, c: Vector2, rx: float, ry: float, col: Color, lw: float) -> void:
	var pts := PackedVector2Array()
	for i in 41:
		var a := TAU * float(i) / 40.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	cv.draw_polyline(pts, col, lw)


func _px() -> float:
	return fx._w() if is_instance_valid(fx) else 2.0


func _ok() -> bool:
	return is_instance_valid(fx) and _okp() and bool(fx.enabled)


func _okp() -> bool:
	return is_instance_valid(player)


func _hit_f() -> int:
	return int(player.ult_hit_frame) if _okp() and player.get("ult_hit_frame") != null else 55


func _charge_f() -> int:
	return maxi(int(player.ult_charge_frames), 1) if _okp() and player.get("ult_charge_frames") != null else 30


func _r(a: float, b: float) -> float:
	return rng.randf_range(a, b)


func _feet() -> Vector2:
	return player.global_position + Vector2(0.0, float(player.foot_offset))


## 这一帧刀柄 / 刀尖的世界坐标（没量过的帧返回空）；顺手算好贴图像素版给辉光着色器
func _blade() -> Array:
	var v := player.get_node_or_null("Visual/ActorSprite") as Sprite2D
	if v == null or v.texture == null:
		return []
	var table: Dictionary = BLADE.get(String(v.get("clip_name")), {})
	var e = table.get(int(v.get("frame_index")), null)
	if e == null:
		return []
	var size := v.texture.get_size()
	var h := Vector2(float(e[0]), float(e[1]))
	var t := Vector2(float(e[2]), float(e[3]))
	var lh := v.offset + (Vector2(size.x - h.x, h.y) if v.flip_h else h)
	var lt := v.offset + (Vector2(size.x - t.x, t.y) if v.flip_h else t)
	return [v.global_transform * lh, v.global_transform * lt, Vector4(h.x, h.y, t.x, t.y)]


## 起手那几帧里刀的位置：动画名 → 帧号 → [刀柄 x, y, 刀尖 x, y]（贴图像素，tools/art 里用颜色 + 连通块量出来的）
const BLADE := {
	"charge_slash": {0: [705, 510, 542, 506], 1: [719, 506, 564, 519], 2: [737, 476, 608, 484], 3: [769, 448, 620, 447],
		4: [815, 442, 654, 429], 5: [844, 446, 665, 421], 6: [974, 458, 792, 445], 7: [1039, 473, 865, 451],
		8: [1039, 473, 865, 451]},
}
