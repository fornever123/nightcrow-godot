extends Node2D
## 背景线 11-18 · 影街「影 2 影流向钟楼」（用户 11-18 选定：“影 2 中间亮度”）。11-19 随 D2 设为默认（用户：“设为默认”）；RAIN_LOOK=OLD 关掉。
## 目标图：docs/_当前分支草稿/背景线/立体感_20261118/方向图/S2m_影流向钟楼_中间亮度.jpg
## 世界观：白光驱逐时间——远处母钟楼背后透着天顶白光；被赶出来的流动时间在暗处积成墨黑狂影，贴着墙、顺着天往母钟楼汇流。
## 做了四件事：
##   1. 远景：Codex 新画的天空（右上云缝透白光）+ 母钟楼侧影（齿轮、尖顶、无钟盘），白光柔光在塔后；旧天际线钟楼藏起来。
##   2. 天上的狂影流：几条墨烟河从左往右汇向钟楼（z −96，夹在远城和中城之间）。
##   3. 墙上的狂影：每张站立层叠一层同图同裁切的墨影（凹处、近街面最浓，灯照处没有），往右流。街面以下换成翻卷的墨烟。
##   4. 去蓝调色：站立层之后、角色之前一层调色（偏蓝推回中性炭灰，暖灯不动），后期的冷色月光 / 暗部偏蓝改中性。

const ART := "res://assets/image/rain_street/ying2/"
const GradeSh := preload("res://scripts/night/redesign/ying_grade.gdshader")
var grade_mat: ShaderMaterial
var focus_uv := Vector2(0.5, 0.72)


static func _envf_yl(k: String, d: float) -> float:
	var s := OS.get_environment(k)
	return float(s) if s != "" else d

const InkSh := preload("res://scripts/night/redesign/ying_ink.gdshader")
const SmokeSh := preload("res://scripts/night/redesign/ying_smoke.gdshader")
const StreamSh := preload("res://scripts/night/redesign/ying_streams.gdshader")
const RibbonSh := preload("res://scripts/night/redesign/ying_ribbon.gdshader")
const WALL_X0 := 2650.0          ## 1-1A 世界 x 范围（墙上墨烟带在这里循环往右漂）
const WALL_X1 := 6950.0

const TOWER_XS := 250.0          ## 样板屏坐标（见 street_layered.rd_x）：1-1A 一路上钟楼都在屏幕右半
const TOWER_YS := -330.0         ## 世界 y：塔尖在屏幕上沿外一点
const TOWER_F := 0.04
const TOWER_H := 1180.0          ## 世界高度
const SKY_TINT := Color(0.88, 0.92, 1.0)    ## 夜空微冷（色调 3）

var sl                            ## street_layered
var mats: Array = []              ## 每帧要喂 t 的材质
var smoke: Sprite2D
var smoke_mat: ShaderMaterial
var streams_mat: ShaderMaterial
var tower_w := 0.0
var t := 0.0
var wall_rb: Array = []           ## 墙上墨烟带：{sp, x, y, v, w}
var sky_rb: Array = []            ## 天上墨烟带：{sp, s, y0, v, w}
var _cam_x := NAN
var rng := RandomNumberGenerator.new()


func build(street) -> void:
	sl = street
	rng.seed = 1118
	_build_far()
	_build_ribbons()
	if wall_rb.is_empty() and not sl.d2_on:
		_build_streams()    # 没有手绘墨烟带素材时退回程序烟河
	_build_ink()
	# _build_smoke()    # 11-18 用户否掉地面那坨影子
	_build_grade()


func _tex(name: String) -> Texture2D:
	var p := ART + name + ".png"
	if ResourceLoader.exists(p) or FileAccess.file_exists(p):
		return sl.tex_at(p)
	return null


func _build_far() -> void:
	var sky := _tex("sky")
	if sky != null and sl.rd_sky != null:
		sl.rd_sky.texture = sky
		sl.rd_sky.modulate = SKY_TINT
		if OS.get_environment("YG_SKY") != "":    # 开发对比用
			var c := OS.get_environment("YG_SKY").split_floats(",")
			sl.rd_sky.modulate = Color(c[0], c[1], c[2])
	var tower_t := _tex("tower")
	if tower_t == null or sl.d2_on:    # D2 远景长条里自带母钟楼
		return
	var old: Texture2D = sl.tex("sky_tower")
	for it in sl.items:
		if it.node is Sprite2D and (it.node as Sprite2D).texture == old:
			(it.node as Sprite2D).visible = false
	var s: float = TOWER_H / float(tower_t.get_height())
	tower_w = float(tower_t.get_width()) * s
	var sp: Sprite2D = sl.add(tower_t, sl.rd_x(TOWER_XS, TOWER_F), sl.rd_y(TOWER_YS), s / sl.bg_k, TOWER_F, -98)
	var tm: ShaderMaterial = sl._rd_depth(0.5, 1.0)    # 远、逆光：往淡灰雾里推一点
	tm.set_shader_parameter("fog_color", Color(0.5, 0.51, 0.53))
	sp.material = tm
	# 塔背后的天顶白光（柔光，压在天空上、塔后面）
	var gx: float = sl.rd_x(TOWER_XS + tower_w * 0.5, TOWER_F)
	var gy: float = sl.rd_y(TOWER_YS + TOWER_H * 0.18)
	sl.add_glow(sl.glow_t, gx, gy, 1500.0 / sl.bg_k, 1100.0 / sl.bg_k, TOWER_F, -99, Color(0.92, 0.94, 0.97), 0.32)


func _ribbon(tex: Texture2D, w: float, z: int, a: float) -> Sprite2D:
	var sp := Sprite2D.new()
	sp.texture = tex
	sp.scale = Vector2.ONE * (w / float(tex.get_width()))
	sp.z_as_relative = false
	sp.z_index = z
	sp.modulate = Color(1, 1, 1, a)
	var m := ShaderMaterial.new()
	m.shader = RibbonSh
	m.set_shader_parameter("seed", rng.randf_range(0.0, 50.0))
	sp.material = m
	mats.append(m)
	add_child(sp)
	return sp


## Codex 手绘墨烟带：墙上（站立层前、角色后）一路往右漂；天上（远城和中城之间）汇向母钟楼
func _build_ribbons() -> void:
	var texs: Array = []
	for i in 4:
		var tx := _tex("ink_%d" % i)
		if tx != null:
			texs.append(tx)
	if texs.is_empty():
		return
	var n := 4    # 11-18 用户：“地面那坨影子不行”——贴街面的墨带全拿掉，只留楼上高处几缕
	if sl.s3d_u2:
		n = 0    # U2 3D 街：2D 墨带贴不进 3D 楼面，先不画（天上的几条照旧）
	if sl.d2_on:
		n = 0    # 11-19 用户看 D2 夜城版：“中间那坨黑色去掉”——楼中间那几道墨带不画
	for i in n:
		var w := rng.randf_range(1300.0, 2100.0)
		var x := lerpf(WALL_X0, WALL_X1, (float(i) + rng.randf()) / float(n))
		var y := rng.randf_range(150.0, 260.0)
		var sp := _ribbon(texs[i % texs.size()], w, -79, rng.randf_range(0.75, 0.95))
		sp.flip_v = rng.randf() < 0.5
		wall_rb.append({"sp": sp, "x": x, "y": y, "v": rng.randf_range(16.0, 30.0), "w": w})
	for i in 5:
		var w := rng.randf_range(700.0, 1200.0)
		var sp := _ribbon(texs[(i + 1) % texs.size()], w, -96, 0.0)
		sky_rb.append({"sp": sp, "s": rng.randf_range(-1500.0, 200.0), "y0": rng.randf_range(-320.0, -60.0), "v": rng.randf_range(22.0, 40.0), "w": w})


func _update_ribbons(dt: float, cam: Vector2) -> void:
	var dx := 0.0 if is_nan(_cam_x) else cam.x - _cam_x
	_cam_x = cam.x
	for r in wall_rb:
		r.x += float(r.v) * dt
		var span := WALL_X1 - WALL_X0
		if float(r.x) > WALL_X1:
			r.x -= span
		var k := (float(r.x) - WALL_X0) / span          # 两头淡入淡出
		var a := clampf(minf(k, 1.0 - k) * 8.0, 0.0, 1.0)
		var sp: Sprite2D = r.sp
		sp.global_position = Vector2(float(r.x), float(r.y))
		sp.self_modulate.a = a
	var tower_s: float = TOWER_XS + tower_w * 0.5 + TOWER_F * (sl.RD_SX0 - cam.x)
	var tower_y: float = TOWER_YS + TOWER_H * 0.2
	for r in sky_rb:
		r.s = float(r.s) + float(r.v) * dt - dx * 0.2       # 远：镜头走 1，它只错开 0.2
		if float(r.s) > tower_s - 40.0:
			r.s = -1500.0 - rng.randf() * 400.0
		var k := clampf((float(r.s) + 1500.0) / maxf(tower_s + 1500.0, 1.0), 0.0, 1.0)   # 0 远端 → 1 钟楼
		var sp: Sprite2D = r.sp
		var w: float = float(r.w) * lerpf(1.0, 0.25, k)
		sp.scale = Vector2.ONE * (w / float(sp.texture.get_width()))
		sp.global_position = Vector2(cam.x + float(r.s), lerpf(float(r.y0), tower_y, k * k))
		sp.modulate.a = clampf(k * 6.0, 0.0, 1.0) * (1.0 - smoothstep(0.75, 1.0, k)) * 0.8


func _build_streams() -> void:
	var q: Sprite2D = sl._white_quad(-96)
	streams_mat = ShaderMaterial.new()
	streams_mat.shader = StreamSh
	q.material = streams_mat
	sl.screen_fx.append({"node": q, "mat": null})
	mats.append(streams_mat)


func _build_ink() -> void:
	if sl.s3d_on:    # 3D 街体：原画已立进 3D，2D 墨影叠层对不上，先不画
		return
	for r in sl.rd_tiles:
		var sp: Sprite2D = r.sp
		var code: String = r.code
		var dp: String = sl.RD_1A_DIR + code + "_depth.png"
		if not (ResourceLoader.exists(dp) or FileAccess.file_exists(dp)):
			continue
		var src: Texture2D = sl.tex_at(sl.RD_1A_DIR + code + ".png")
		var ov := Sprite2D.new()
		ov.texture = src
		ov.centered = false
		ov.region_enabled = true
		ov.region_rect = sp.region_rect
		ov.z_as_relative = false
		ov.z_index = -79
		var m := ShaderMaterial.new()
		m.shader = InkSh
		m.set_shader_parameter("depth_tex", sl.tex_at(dp))
		m.set_shader_parameter("aspect", float(src.get_width()) / float(src.get_height()))
		m.set_shader_parameter("t", 0.0)
		ov.material = m
		sp.add_child(ov)
		mats.append(m)


func _build_smoke() -> void:
	smoke = sl._white_quad(-77)
	smoke.scale = Vector2(600.0, 150.0)       # 2400 × 600 世界单位
	smoke_mat = ShaderMaterial.new()
	smoke_mat.shader = SmokeSh
	smoke.material = smoke_mat
	mats.append(smoke_mat)


func _build_grade() -> void:
	var bb := BackBufferCopy.new()
	bb.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	bb.z_as_relative = false
	bb.z_index = -76
	sl.add_child(bb)
	var q: Sprite2D = sl._white_quad(-76)
	var m := ShaderMaterial.new()
	m.shader = GradeSh
	if sl.d2_on:    # D2 三层：11-19 先提亮 1.18，用户：“亮度太高，不像晚上”——退回夜色，亮只留给灯和窗
		m.set_shader_parameter("exposure", float(OS.get_environment("D2_EXPO")) if OS.get_environment("D2_EXPO") != "" else 1.04)
	# 开发对比用：YG_N（偏蓝推灰的程度）、YG_TINT（灰的色温 r,g,b）覆盖默认值
	if OS.get_environment("YG_N") != "":
		m.set_shader_parameter("neutral", float(OS.get_environment("YG_N")))
	if OS.get_environment("YG_TINT") != "":
		var c := OS.get_environment("YG_TINT").split_floats(",")
		m.set_shader_parameter("grey_tint", Vector3(c[0], c[1], c[2]))
	q.material = m
	sl.screen_fx.append({"node": q, "mat": null})
	if sl.d2_on:    # 11-19 主次：以角色为中心的背景压暗（见 ying_grade.gdshader）
		grade_mat = m
		m.set_shader_parameter("focus_amt", _envf_yl("D2_FOCUS", 0.16))
		m.set_shader_parameter("top_amt", _envf_yl("D2_TOP", 0.0))
		# 11-19 对照参照游戏：暗部抬成有颜色的暗、远处变雾、冷暗暖亮（见 ying_grade.gdshader）
		m.set_shader_parameter("shadow_lift", _envf_yl("D2_LIFT", 0.6))
		m.set_shader_parameter("haze_amt", _envf_yl("D2_GHAZE", 0.3))
		m.set_shader_parameter("split_amt", _envf_yl("D2_SPLIT", 1.0))
		m.set_shader_parameter("sat", _envf_yl("D2_SAT", 1.2))
		m.set_shader_parameter("haze_drift", _envf_yl("D2_DRIFT", 0.8))    # 11-19 到 8 分：雾成团缓慢飘，不再是一层不动的灰


func update(dt: float, cam: Vector2) -> void:
	t += dt
	if grade_mat != null and sl.bd != null and sl.bd.camera != null:
		var vs: Vector2 = sl.get_viewport_rect().size
		var zoom: Vector2 = sl.bd.camera.zoom
		var rel: Vector2 = (sl._player_pos() + Vector2(0.0, -60.0) - sl.bd.camera.get_screen_center_position()) * zoom
		var want := Vector2(0.5, 0.5) + rel / vs
		focus_uv = focus_uv.lerp(want, clampf(dt * 4.0, 0.0, 1.0))
		grade_mat.set_shader_parameter("cam_x", sl.bd.camera.get_screen_center_position().x)
		grade_mat.set_shader_parameter("focus", focus_uv)
		grade_mat.set_shader_parameter("aspect", vs.x / maxf(vs.y, 1.0))
	_update_ribbons(dt, cam)
	for m in mats:
		(m as ShaderMaterial).set_shader_parameter("t", t)
	if smoke != null:
		smoke.global_position = Vector2(cam.x, sl.FLOOR + 320.0)
		smoke_mat.set_shader_parameter("cam_x", cam.x - 1200.0)
	if streams_mat != null:
		# 钟楼在屏幕上的位置（世界，相对镜头）：xs + 塔宽/2 + f·(RD_SX0 − 镜头 x)
		var rel_x: float = TOWER_XS + tower_w * 0.5 + TOWER_F * (sl.RD_SX0 - cam.x)
		var foot_y: float = TOWER_YS + TOWER_H * 0.12 - cam.y
		streams_mat.set_shader_parameter("target", Vector2(0.5 + rel_x / 2400.0, 0.5 + foot_y / 1440.0))
		streams_mat.set_shader_parameter("scroll", cam.x * 0.0012)
	var pm: ShaderMaterial = sl._rd_post_mat
	if pm != null:    # 后期：月光光柱、暗部偏蓝改中性（角色身上也不再罩蓝）
		pm.set_shader_parameter("shadow_tint", Vector3(1.0, 1.0, 1.0))
		pm.set_shader_parameter("high_tint", Vector3(1.0, 1.0, 1.0))
		pm.set_shader_parameter("rays_col", Vector3(0.9, 0.91, 0.93))
		pm.set_shader_parameter("rays_amt", 0.12)
		pm.set_shader_parameter("sat", 1.0)
