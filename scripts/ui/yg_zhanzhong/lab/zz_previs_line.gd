extends Node3D
## 《斩钟》进选章 · 线条一镜到底预演 v3「拆成线 → 锁成影街线稿」（只出帧，不进正式流程）
## 用户 11-16：3D 展开结束后再拆；除指针外的东西一直拆到变成线；线要好看、不要太多；线最后组成影街的框架（直接由插画处理出来）。
## 流程：斩 → 沿轴拆开（3D，沿用 v1）→ 各圈裂成弧段（贴图褪去，只剩发光弧）→ 弧段一边飞一边拉直，按从左到右的顺序锁进影街线稿
##       → 两根实体剑针全程倒转，随钟飞进钟楼落 5:59 → 颜色由远到近填满，线褪去。
## 用法：ZZ_PREVIS=<输出目录> ZZ_PREVIS_SET=line [ZZ_PREVIS_FPS=60] [ZZ_PREVIS_T=0.5,1.2]
## 数据：scratchpad/line/lineart.json（line/lineart.py：三层景片 LSD 直线检测 + 合并，约 300 根；另加钟面与大齿轮的圆）

const DEG := PI / 180.0
const W := 1920.0
const H := 1080.0
const DATA := "C:/Users/MECHREVO/AppData/Local/Temp/claude/bad2dff93b2b5945/0fddf7d5-af25-4d6b-a51b-6b04d824eebd/scratchpad/line/portal.json"
const MP := 72                 # 截面框 / 圆的采样点
const C0 := Vector2(960, 540)  # 钟轴在终机位画面上的位置
const TOWER_PX := Vector2(1690, 245)   # 钟楼钟心（画面像素）
const T_RM := 1.5              # 剑针开始缩进钟楼
const RZ := [-640.0, -400.0, -180.0, 40.0, 240.0]
const RING_PX := [327.0, 386.0, 484.0, 623.0, 728.0]
const KP := 14                 # 每根线的采样点
const T_CRACK := 0.85          # 3D 结束，开始拆
const T_FLY0 := 1.05           # 第一根线起飞
const T_SWEEP := 0.45          # 起飞从左扫到右的总时长
const T_FLYD := 0.45           # 单根飞行时长
const DT := 1800.0
const LAYER_D := {1: 2250.0, 2: 1850.0, 3: 1500.0}   # 影街三层线稿各自的玻璃片深度（远 / 中 / 近），终机位看去与插画重合
const LAYER_RINGS := {1: [0, 1], 2: [2, 3], 3: [4]}  # 内圈→远景（含钟楼），中圈→中景，外圈→近景
const LAYER_T := {3: 1.1, 2: 1.2, 1: 1.3}            # 外层先旋开
const LAYER_SW := {1: 1.0, 2: -1.0, 3: 1.0}          # 相邻层反向旋（像咬合的齿轮）
const T_SWD := 0.75
const T_LAND := 2.2            # 指针落 5:59
const T_FILL := 2.5
const T_WAVE := 2.26           # 落针后从钟楼钟心荡开的表盘波：波里是插画
const T_WAVED := 1.0
const T_END := 3.6
const SILVER := Color(0.8, 0.86, 1.0)
const WARM := Color(1.0, 0.86, 0.66)

var T: Node
var C: Node
var S: Node
var cam: Camera3D
var out := ""
var tv := 0.0
var running := false
var line_mi: MeshInstance3D
var home_xf := Transform3D.IDENTITY
var hub_w := Vector3.ZERO
var min0 := 0.0
var hour0 := 0.0
var spin_tab := PackedFloat32Array()
var path_keys: Array = []
var R_loc: Array = []
var far_c := Vector3.ZERO
var far_w := 1.0
var far_h := 1.0
var pieces: Array = []        # {ring, r, th, span, tgt: PackedVector3Array, len, tf, warm}


func _ready() -> void:
	T = get_parent()
	C = T.clock
	cam = C.camera
	cam.far = 90000.0
	process_priority = 1000
	out = OS.get_environment("ZZ_PREVIS")
	DirAccess.make_dir_recursive_absolute(out)
	_build_line_mesh()
	_run.call_deferred()


# ================================================================ 发光线（屏幕恒宽）
func _build_line_mesh() -> void:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled, fog_disabled;
varying float inten;
varying float head;
void vertex() { inten = UV2.x; head = UV2.y; }
void fragment() {
	float y = UV.y;
	float core = exp(-y * y * 40.0);
	float body = exp(-y * y * 7.0);
	float halo = 0.13 * exp(-y * y * 0.75);
	float hl = head >= 0.0 ? exp(-pow((UV.x - head) * 16.0, 2.0)) : 0.0;
	vec3 c = COLOR.rgb * (body * 0.85 + halo) + vec3(1.0, 0.97, 0.93) * core * 0.6;
	ALBEDO = c * inten * (1.0 + 2.6 * hl);
	ALPHA = 1.0;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.render_priority = 10
	line_mi = MeshInstance3D.new()
	line_mi.material_override = m
	line_mi.extra_cull_margin = 16384.0
	line_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(line_mi)


## L: {p: PackedVector3Array, w, k, c, r1}
func _rebuild(L_all: Array, X: Transform3D, fov: float) -> void:
	var f := 540.0 / tan(deg_to_rad(fov) * 0.5)
	var inv := X.affine_inverse()
	var V := PackedVector3Array()
	var CC := PackedColorArray()
	var U := PackedVector2Array()
	var U2 := PackedVector2Array()
	var I := PackedInt32Array()
	for L: Dictionary in L_all:
		var P: PackedVector3Array = L["p"]
		var n := P.size()
		var w: float = L["w"]
		var wpx := maxf(w, 1.35)
		var k: float = float(L["k"]) * minf(1.0, w / 1.35)
		if k < 0.004:
			continue
		var col: Color = L["c"]
		var r1: float = L.get("r1", 1.0)
		var hd: float = L.get("h", -1.0)
		var nw: bool = L.get("nw", false)
		var nn := n
		if r1 < 1.0:
			nn = clampi(int(ceil(r1 * (n - 1))) + 1, 0, n)
		if nn < 2:
			continue
		var base := V.size()
		for i in nn:
			var p := P[i]
			var tu := float(i) / float(maxi(n - 1, 1))
			var tap := pow(maxf(sin(PI * tu), 0.0), 0.45)
			var tng := P[mini(i + 1, n - 1)] - P[maxi(i - 1, 0)]
			var dep := -(inv * p).z
			var vis := smoothstep(20.0, 80.0, dep)
			var side := tng.cross(X.origin - p)
			if side.length() < 1e-5:
				side = Vector3.UP
			side = side.normalized()
			var hw := 3.2 * wpx * 0.5 * maxf(dep, 20.0) / f * (0.25 + 0.75 * tap)
			var inten := k * vis * (0.45 + 0.55 * tap)
			if wave_R >= 0.0 and not nw:
				var q := inv * p
				var sp := Vector2(960.0 + q.x / maxf(-q.z, 1.0) * f, 540.0 - q.y / maxf(-q.z, 1.0) * f)
				var dd := sp.distance_to(tower_px)
				inten *= smoothstep(wave_R - 80.0, wave_R - 6.0, dd) + 1.8 * exp(-pow((dd - wave_R) / 30.0, 2.0))
			V.append(p + side * hw)
			V.append(p - side * hw)
			U.append(Vector2(tu, 3.2))
			U.append(Vector2(tu, -3.2))
			U2.append(Vector2(inten, hd))
			U2.append(Vector2(inten, hd))
			CC.append(col)
			CC.append(col)
		for i in nn - 1:
			var a := base + i * 2
			I.append_array([a, a + 1, a + 2, a + 1, a + 3, a + 2])
	if V.is_empty():
		line_mi.mesh = null
		return
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = V
	arr[Mesh.ARRAY_COLOR] = CC
	arr[Mesh.ARRAY_TEX_UV] = U
	arr[Mesh.ARRAY_TEX_UV2] = U2
	arr[Mesh.ARRAY_INDEX] = I
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	line_mi.mesh = am


# ================================================================ 缓动
static func _seg(t: float, a: float, d: float) -> float:
	return clampf((t - a) / d, 0.0, 1.0)


static func _io(t: float) -> float:
	return 4.0 * t * t * t if t < 0.5 else 1.0 - pow(-2.0 * t + 2.0, 3.0) / 2.0


static func _o3(t: float) -> float:
	return 1.0 - pow(1.0 - t, 3.0)


static func _lock(t: float) -> float:
	if t >= 1.0:
		return 1.0
	var s := 2.2
	return 1.0 + (s + 1.0) * pow(t - 1.0, 3.0) + s * pow(t - 1.0, 2.0)


static func _hash(i: int, salt: int) -> float:
	return fposmod(sin(float(i) * 12.9898 + float(salt) * 78.233) * 43758.5453, 1.0)


## 回弹缓动（像弹簧锁住）
static func _back(x: float) -> float:
	var c1 := 1.25
	var c3 := c1 + 1.0
	return 1.0 + c3 * pow(x - 1.0, 3.0) + c1 * pow(x - 1.0, 2.0)


# ================================================================ 指针：全程实体，疯狂倒转，落钟楼停 5:59
func _build_spin() -> void:
	spin_tab.resize(401)
	var acc := 0.0
	for i in 401:
		var t := i / 100.0
		acc += smoothstep(0.3, 0.95, t) * (1.0 - smoothstep(1.55, T_LAND, t))
		spin_tab[i] = acc
	var tot := spin_tab[400]
	for i in 401:
		spin_tab[i] /= tot


func _spin(t: float) -> float:
	var x := clampf(t * 100.0, 0.0, 400.0)
	var i := int(x)
	return lerpf(spin_tab[i], spin_tab[mini(i + 1, 400)], x - i)


func _hands(t: float) -> Array:
	var dm := fposmod(96.0 * DEG - min0, TAU) + TAU * 9.0
	var dh := fposmod(-89.0 * DEG - hour0, TAU) + TAU * 1.0
	var s := _spin(t)
	var m := min0 + dm * s
	var h := hour0 + dh * s
	if t >= T_LAND:
		var k := t - T_LAND
		m += 5.0 * DEG * exp(-k * 18.0) * sin(k * 60.0)
	return [m, h]


# ================================================================ 钟体（沿用 zz_select 的分解钟零件）
func _part_order(P: Dictionary) -> int:
	match String(P["kind"]):
		"ring":
			return 4 - int(P["i"])
		"gear_main", "gear_escape", "pallet_fork":
			return 5
		"rosette":
			return 6
	return 0


func _sep(P: Dictionary, t: float) -> float:
	# 缩进钟楼时各层合回一张（否则偏轴后层间深度会错位）
	return _lock(_seg(t, 0.2 + 0.045 * _part_order(P), 0.14)) * (1.0 - _io(_seg(t, T_RM, 0.45)))


## 零件化成线：外圈先褪，越往里越晚；落进钟楼后表盘重新浮现
func _tex_a(P: Dictionary, t: float) -> float:
	var t0 := T_CRACK + 0.035 * _part_order(P)
	var a := 1.0 - _seg(t, t0 + 0.03, 0.2)
	return maxf(a, _io(_seg(t, T_WAVE, 0.12)))


func _ring_xf(P: Dictionary, t: float) -> Transform3D:
	var kind := String(P["kind"])
	var pos0: Vector3 = P["pos0"]
	var e := _sep(P, t)
	match kind:
		"ring":
			var i: int = P["i"]
			var alt := 1.0 if i % 2 == 0 else -1.0
			var steps := clampf((t - 0.2) / 0.11, 0.0, 5.0)
			var st := floorf(steps) + smoothstep(0.55, 1.0, fposmod(steps, 1.0))
			var rot := alt * (i + 1) * 4.0 * DEG * st
			return Transform3D(Basis(Vector3.BACK, rot), pos0 + Vector3(0, 0, float(RZ[i]) * e))
		"gear_main", "gear_escape", "pallet_fork":
			return Transform3D(Basis(Vector3.BACK, -float(C.TILT) - t * 1.4), Vector3(pos0.x, pos0.y, lerpf(pos0.z, -760.0, e)))
		"rosette":
			return Transform3D(Basis(Vector3.BACK, t * 0.3), Vector3(pos0.x, pos0.y, lerpf(pos0.z, -520.0, e)))
	return Transform3D(Basis.IDENTITY, pos0)


func _part_by_ring(i: int) -> Dictionary:
	for P: Dictionary in S.rig_parts:
		if String(P["kind"]) == "ring" and int(P["i"]) == i and float(P["side"]) <= 0.0:
			return P
	return {}


func _fly(t: float) -> float:
	return _io(_seg(t, T_RM, 0.6))


func _rig_update(t: float) -> void:
	var rig: Node3D = S.rig
	var fr := _fly(t)
	var tc: Vector3 = S.t_c
	var col := _io(_seg(t, 1.0, 0.36))
	var em := _back(_seg(t, T_RM, 0.6))
	var p_px := C0.lerp(tower_px, em)
	var pw := _pw(p_px)
	rig.position = Vector3(pw.x, pw.y, lerpf(hub_w.z, S.o_e.z - DP, col))
	rig.basis = Basis(Vector3.BACK, lerpf(-float(C.TILT), 0.0, em)).scaled(Vector3.ONE * lerpf(1.0, s_eq, em))
	var nw := rig.basis.x.normalized()
	var hs := _hands(t)
	var spd := smoothstep(0.3, 0.95, t) * (1.0 - smoothstep(1.55, T_LAND, t))
	for P: Dictionary in S.rig_parts:
		var mi: MeshInstance3D = P["mi"]
		var m: ShaderMaterial = P["m"]
		var kind := String(P["kind"])
		var a := 1.0
		var gl := float(P["g0"])
		if kind.begins_with("hand"):
			var is_m := kind == "hand_minute"
			var pos0: Vector3 = P["pos0"]
			mi.transform = Transform3D(Basis(Vector3.BACK, hs[0] if is_m else hs[1]), pos0 + Vector3(0, 0, (150.0 if is_m else 90.0) * _seg(t, 0.2, 0.3) * (1.0 - fr)))
			gl *= 1.0 + 2.2 * spd + 1.5 * exp(-maxf(t - T_LAND, 0.0) * 10.0) * float(t >= T_LAND)
		else:
			mi.transform = _ring_xf(P, t)
			a = _tex_a(P, t)
		var side: float = P["side"]
		var clip := Vector4.ZERO
		if side != 0.0:
			var n := nw * side
			clip = Vector4(n.x, n.y, n.z, -n.dot(rig.position))
		m.set_shader_parameter("clip_plane", clip)
		m.set_shader_parameter("opacity", a)
		m.set_shader_parameter("glow", gl)
		for tm: ShaderMaterial in P["thick"]:
			tm.set_shader_parameter("clip_plane", clip)
			tm.set_shader_parameter("opacity", a)
		mi.visible = a > 0.003
		for g: Dictionary in P["ghosts"]:
			(g["mi"] as MeshInstance3D).visible = false
	S._env_vis(0.0)


# ================================================================ 景片：线稿阶段全隐，最后由远到近浮现
func _fill(_n: int, _t: float) -> float:
	return 0.0      # 线由表盘波吃掉（见 _rebuild 的 wave_R）


var wave_R := -1.0


func _wave_r(t: float) -> float:
	if t < T_WAVE:
		return -1.0
	var x := _seg(t, T_WAVE, T_WAVED)
	return 24.0 + 2500.0 * (1.0 - pow(1.0 - x, 2.2))


## 钟楼钟心在某张景片 UV 里的位置（终机位视线与景片平面求交）
func _layer_uv(L: Dictionary, px: Vector2) -> Vector2:
	var mi: MeshInstance3D = L["mi"]
	var X := mi.global_transform
	var oe: Vector3 = S.o_e
	var dir := Vector3((px.x - 960.0) / FPX, -(px.y - 540.0) / FPX, -1.0)
	var nrm := X.basis.z.normalized()
	var den := nrm.dot(dir)
	if absf(den) < 1e-6:
		return Vector2(0.5, 0.5)
	var tt := nrm.dot(X.origin - oe) / den
	var lp := X.affine_inverse() * (oe + dir * tt)
	return Vector2(lp.x / float(L["w"]) + 0.5, 0.5 - lp.y / float(L["h"]))


func _stage_update(t: float) -> void:
	S.stage_root.visible = t >= T_WAVE
	var R := _wave_r(t)
	for L: Dictionary in S.layers:
		var piv: Node3D = L["piv"]
		piv.position = L["hinge"]
		piv.rotation = Vector3.ZERO
		(L["mi"] as MeshInstance3D).rotation = Vector3.ZERO
		var m: ShaderMaterial = L["mat"]
		m.set_shader_parameter("opacity", 1.0)
		m.set_shader_parameter("lit", 1.0)
		m.set_shader_parameter("glow_front", lerpf(-0.05, 1.05, _seg(t, T_WAVE + 0.15, 0.6)))
		var wc := _layer_uv(L, tower_px)
		# 每张景片各自的 UV 尺度：用钟心右侧 R 像素那一点量出来，保证揭开边与线环严丝合缝
		var ruv := -1.0
		if R >= 0.0:
			ruv = ((_layer_uv(L, tower_px + Vector2(R, 0.0)) - wc) * Vector2(1.7778, 1.0)).length()
		m.set_shader_parameter("wave_c", wc)
		m.set_shader_parameter("reveal_r", ruv if R < 2500.0 else 99.0)
		m.set_shader_parameter("wave_k", 0.3 * (1.0 - _seg(t, T_WAVE + 0.5, 0.4)))
		m.set_shader_parameter("glow_on", 1.0)
		m.set_shader_parameter("outline", 0.0)
		m.set_shader_parameter("rim", 0.0)
		m.set_shader_parameter("flash", 0.0)
		m.set_shader_parameter("sky_flash", 0.0)
		m.set_shader_parameter("wave_r", ruv if R < 2500.0 else -1.0)
	for g: Dictionary in S.near_ghosts:
		(g["mi"] as MeshInstance3D).visible = false
	var rk := _seg(t, T_WAVE + 0.6, 0.4)
	var rm: MultiMeshInstance3D = S.rain_mmi
	rm.visible = rk > 0.01
	(rm.material_override as ShaderMaterial).set_shader_parameter("opacity", 0.3 * rk)


# ================================================================ 数据：影街线稿 + 钟圈切出的弧段，一一配对
func _px(p: Vector2) -> Vector3:
	return far_c + Vector3((p.x / W - 0.5) * far_w, (0.5 - p.y / H) * far_h, 0.0)


func _wrap(a: float) -> float:
	return fposmod(a + PI, TAU) - PI


func _polar(v: Vector3) -> Vector3:
	var d := Vector2(v.x - hub_w.x, v.y - hub_w.y)
	return Vector3(d.length(), atan2(d.y, d.x), v.z)


var DP := 2256.0
var vp_px := Vector2(1636, 1004)
var fz := 6036.0


const FPX := 540.0 / 0.26794919243   # 终机位 fov 30 的焦距（像素）
var tex_s := 1.08                      # 景片贴图坐标 → 屏幕坐标的放大（出血）
var tower_px := Vector2(1690, 245)
var tower_rpx := 128.0
var s_eq := 0.17


func _pw(p: Vector2) -> Vector3:
	var oe: Vector3 = S.o_e
	return oe + Vector3((p.x - 960.0) / FPX * DP, -(p.y - 540.0) / FPX * DP, -DP)


func _t2s(q: Array) -> Vector2:
	return C0 + (Vector2(q[0], q[1]) - C0) * tex_s


func _ring_center(ring: int, t: float) -> Vector3:
	var P: Dictionary = _part_by_ring(ring)
	var pos0: Vector3 = P["pos0"]
	return (home_xf * _ring_xf(P, t) * Transform3D(Basis.IDENTITY, -pos0)) * Vector3.ZERO


func _load_data() -> void:
	var js: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	for L: Dictionary in S.layers:
		if String(L["kind"]) == "far":
			far_c = S.o_e + Vector3(0, 0, -float(L["z"]))
			far_w = L["w"]
			far_h = L["h"]
	fz = far_c.distance_to(S.o_e)
	var inv := home_xf.affine_inverse()
	for r: float in RING_PX:
		var q: Vector3 = inv * C.to_world(C.HUB.x + r, C.HUB.y, S.DIAL_Z)
		R_loc.append(Vector2(q.x, q.y).length())
	var kpx: float = float(R_loc[4]) / float(RING_PX[4])     # 世界单位 / 像素（在线稿平面上）
	DP = kpx * FPX
	tex_s = far_w / (2.0 * fz * 0.26794919243 * W / H)
	var tc: Vector3 = S.t_c
	var dep: float = S.o_e.z - tc.z
	tower_px = Vector2(960.0 + (tc.x - S.o_e.x) / dep * FPX, 540.0 - (tc.y - S.o_e.y) / dep * FPX)
	tower_rpx = float(R_loc[4]) * float(S.s_t) / dep * FPX
	s_eq = float(S.s_t) * DP / dep
	var VP := _t2s(js["vp"])
	var U := PackedVector2Array()
	for q: Array in js["U"]:
		U.append(_t2s(q))
	var lams: Array = js["lams"]
	# 十道圆：每圈外沿 + 圈中线
	var src: Array = []
	for i in 5:
		var ro: float = R_loc[i]
		var ri: float = R_loc[i - 1] if i > 0 else ro * 0.4
		src.append([i, 0, ro])
		src.append([i, 1, (ro + ri) * 0.5])
	var tcs: Array = js["tower_c"]
	var por_src: Array = []
	for S_: Array in src:
		var ring: int = S_[0]
		var tc_i := -1
		if ring == 4:
			tc_i = int(S_[1])
		elif ring == 0 and int(S_[1]) == 1:
			tc_i = 2
		var A := {"ring": ring, "r": float(S_[2]), "rpx": float(S_[2]) / kpx, "t_col": 1.0 + 0.05 * ring}
		if tc_i >= 0:
			A["kind"] = "tc"
			if tc_i < 2:
				A["c1"] = tower_px
				A["r1"] = tower_rpx * (1.0 if tc_i == 0 else 0.8)
			else:
				A["c1"] = Vector2(1748, 692)
				A["r1"] = 140.0
				A["gear"] = true
			A["t_m"] = T_RM if ring == 4 else 1.52
			A["n"] = 1
			pieces.append(A)
		else:
			por_src.append(A)
	# 大圆配大框：半径从大到小 ↔ λ 从大到小
	por_src.sort_custom(func(u: Dictionary, v: Dictionary) -> bool: return float(u["r"]) > float(v["r"]))
	for j in por_src.size():
		var A: Dictionary = por_src[j]
		var lam: float = lams[j]
		var poly := PackedVector2Array()
		for q: Vector2 in U:
			poly.append(VP + (q - VP) * lam)
		A["kind"] = "por"
		A["tgt"] = _resample(poly, MP)
		A["corners"] = poly
		A["t_m"] = 1.38 + 0.035 * j
		A["n"] = 2
		pieces.append(A)
	# 射线：截面框成形后从灭点向外画出，按方位扫过去
	var rays: Array = js["rays"]
	rays.sort_custom(func(u: Array, v: Array) -> bool: return atan2(-(float(u[1][1]) - VP.y), float(u[1][0]) - VP.x) > atan2(-(float(v[1][1]) - VP.y), float(v[1][0]) - VP.x))
	for j in rays.size():
		var R: Array = rays[j]
		pieces.append({"kind": "draw", "a": _t2s(R[0]), "b": _t2s(R[1]), "t0": 1.74 + 0.22 * float(j) / (rays.size() - 1), "dur": 0.24, "n": 2, "warm": false, "w": 1.5})
	var bays: Array = js["bays"]
	for j in bays.size():
		var R: Array = bays[j]
		pieces.append({"kind": "draw", "a": _t2s(R[0]), "b": _t2s(R[1]), "t0": 1.86 + 0.035 * j, "dur": 0.2, "n": 2, "warm": false, "w": 1.5})
	var tl: Array = js["tower_l"]
	tl.sort_custom(func(u: Array, v: Array) -> bool: return float(u[0]) < float(v[0]))
	for j in tl.size():
		var R: Array = tl[j]
		var a := _t2s([R[0], R[1]])
		var b := _t2s([R[2], R[3]])
		if a.y < b.y:
			var tmp := a
			a = b
			b = tmp
		pieces.append({"kind": "draw", "a": a, "b": b, "t0": 1.9 + 0.012 * j, "dur": 0.2, "n": 1, "warm": true, "w": 2.2 if a.distance_to(b) > 250.0 else 1.7})
	vp_px = VP
	# 钟楼钟面 60 刻度：钟面成形后逆时针（倒着走）一格格刻出
	for j in 60:
		var an := PI * 0.5 + TAU * float(j) / 60.0
		var dv := Vector2(cos(an), -sin(an))
		var hr := j % 5 == 0
		var r_a := tower_rpx * (0.82 if hr else 0.9)
		pieces.append({"kind": "draw", "a": tower_px + dv * tower_rpx * 0.985, "b": tower_px + dv * r_a, "t0": 2.0 + 0.2 * float(j) / 60.0, "dur": 0.05, "n": 1, "warm": true, "w": 1.6 if hr else 1.0})
	print("pieces ", pieces.size(), " DP ", DP, " tex_s ", tex_s, " tower ", tower_px, " r ", tower_rpx)


func _resample(P: PackedVector2Array, M: int) -> PackedVector2Array:
	var cum := PackedFloat32Array([0.0])
	for i in range(1, P.size()):
		cum.append(cum[i - 1] + P[i].distance_to(P[i - 1]))
	var out := PackedVector2Array()
	var tot := cum[P.size() - 1]
	var k := 0
	for m in M:
		var v := tot * float(m) / (M - 1)
		while k < P.size() - 2 and cum[k + 1] < v:
			k += 1
		var u := (v - cum[k]) / maxf(cum[k + 1] - cum[k], 1e-5)
		out.append(P[k].lerp(P[k + 1], clampf(u, 0.0, 1.0)))
	return out


# ================================================================ 线
func _arc_pts(A: Dictionary, t: float) -> PackedVector3Array:
	var ring: int = A["ring"]
	var P: Dictionary = _part_by_ring(ring)
	var pos0: Vector3 = P["pos0"]
	var X := home_xf * _ring_xf(P, t) * Transform3D(Basis.IDENTITY, -pos0)
	var order := 4 - ring
	var c := _o3(_seg(t, T_CRACK + 0.035 * order, 0.25))
	var sg: float = A["sg"]
	var span: float = float(A["span"]) * (1.0 - 0.14 * c)
	var r: float = float(A["r"]) * (1.0 + 0.03 * c * sg)
	var th: float = A["th"]
	var Q := PackedVector3Array()
	for i in KP:
		var an := th + span * (float(i) / (KP - 1) - 0.5)
		Q.append(X * Vector3(cos(an) * r, sin(an) * r, 30.0 * c * sg))
	return Q


func _lines_update(t: float) -> Array:
	var res: Array = []
	if t < T_CRACK:
		return res
	var oe: Vector3 = S.o_e
	var z_plane := oe.z - DP
	for A: Dictionary in pieces:
		var kind := String(A["kind"])
		var fade := 1.0 - _fill(int(A["n"]), t)
		if kind == "draw":
			var x := _seg(t, float(A["t0"]), float(A["dur"]))
			if x <= 0.0:
				continue
			var Pd := PackedVector3Array()
			for i in KP:
				Pd.append(_pw((A["a"] as Vector2).lerp(A["b"], float(i) / (KP - 1))))
			var kd := (0.95 + 0.7 * exp(-maxf(t - float(A["t0"]) - float(A["dur"]), 0.0) * 7.0)) * fade
			if kd > 0.004:
				res.append({"p": Pd, "w": float(A["w"]), "k": kd * (1.25 if A["warm"] else 0.85), "c": WARM if A["warm"] else SILVER, "r1": _o3(x), "h": _o3(x) if x < 1.0 else -1.0})
			continue
		var ring: int = A["ring"]
		var appear := _seg(t, T_CRACK + 0.035 * (4 - ring), 0.16)
		if appear <= 0.0:
			continue
		var r: float = A["r"]
		var rpx: float = A["rpx"]
		var tm: float = A["t_m"]
		var Pts := PackedVector3Array()
		var Pin := PackedVector3Array()
		var hd := -1.0
		var k := 1.0
		var gap := 0.0 if kind == "tc" else 0.55 * _io(_seg(t, 1.22 + 0.03 * ring, 0.2))
		if t < tm:
			# 圆：在本圈的 3D 层里，随后沿钟轴滑进线稿平面（叠成一张）
			var c := _ring_center(ring, minf(t, 1.0 + 0.05 * ring))
			var col := _io(_seg(t, float(A["t_col"]), 0.36))
			var z := lerpf(c.z, z_plane, col)
			for m in MP:
				var an := PI * 0.5 + gap * 0.5 + (TAU - gap) * float(m) / (MP - 1)
				Pts.append(Vector3(hub_w.x + cos(an) * r, hub_w.y + sin(an) * r, z))
			k = 0.95 + 0.35 * sin(PI * col)
		else:
			# 线稿平面里的二维形变：圆从斩缝断开 → 一层街道截面框；钟楼两圈 / 大齿轮：圆 → 圆
			var x := _seg(t, tm, 0.5 if kind == "por" else 0.6)
			var e := _back(x)
			for m in MP:
				var u := float(m) / (MP - 1)
				var an := PI * 0.5 + gap * 0.5 + (TAU - gap) * u
				var s0 := C0 + Vector2(cos(an), -sin(an)) * rpx
				var p1: Vector2
				if kind == "por":
					p1 = (A["tgt"] as PackedVector2Array)[m]
				else:
					var a1 := PI * 0.5 + TAU * u
					var rr1 := float(A["r1"])
					if A.get("gear", false):
						rr1 *= 0.955 + 0.045 * smoothstep(-0.3, 0.3, sin(a1 * 24.0))
					p1 = (A["c1"] as Vector2) + Vector2(cos(a1), -sin(a1)) * rr1
				Pts.append(_pw(s0.lerp(p1, e)))
				if kind == "por":
					Pin.append(_pw(vp_px + (s0.lerp(p1, e) - vp_px) * 0.982))
			k = 0.95 + 0.4 * sin(PI * x) + 0.5 * exp(-maxf(t - tm - 0.45, 0.0) * 8.0) * float(t > tm + 0.45)
			hd = x if x < 1.0 else -1.0
			if kind == "por":
				# 内侧一道细线（框有厚度）+ 四个角钉
				res.append({"p": Pin, "w": 1.0, "k": k * 0.5 * smoothstep(0.25, 1.0, x), "c": WARM, "r1": appear})
				if x > 0.8:
					var kc := (0.7 + 1.2 * exp(-maxf(t - tm - 0.42, 0.0) * 7.0)) * smoothstep(0.8, 1.0, x)
					for cn: Vector2 in (A["corners"] as PackedVector2Array):
						if cn.x < -20.0 or cn.x > W + 20.0 or cn.y < -20.0 or cn.y > H + 20.0:
							continue
						var Pc := PackedVector3Array()
						for m2 in 13:
							var ac := TAU * float(m2) / 12.0
							Pc.append(_pw(cn + Vector2(cos(ac), sin(ac)) * 5.0))
						res.append({"p": Pc, "w": 1.3, "k": kc, "c": WARM})
		k *= fade
		if k < 0.004:
			continue
		res.append({"p": Pts, "w": 2.4, "k": k * 1.2, "c": WARM, "r1": appear, "h": hd})
	# 表盘波：落针那一下从钟心荡开的一圈刻度环，环里就是插画
	var R := _wave_r(t)
	if R >= 0.0 and R < 2550.0:
		var kx := _seg(t, T_WAVE, T_WAVED)
		var kw := 1.5 * (1.0 - smoothstep(0.55, 1.0, kx)) * smoothstep(0.0, 0.05, kx)
		for ring in 2:
			var rr := R * (1.0 if ring == 0 else 0.86)
			var Pw := PackedVector3Array()
			for m in 121:
				var an := TAU * float(m) / 120.0
				Pw.append(_pw(tower_px + Vector2(cos(an), sin(an)) * rr))
			res.append({"p": Pw, "w": 2.6 if ring == 0 else 1.1, "k": kw * (1.0 if ring == 0 else 0.45), "c": WARM, "nw": true})
		for j in 60:
			var an := PI * 0.5 - TAU * float(j) / 60.0
			var dv := Vector2(cos(an), -sin(an))
			var ln := (28.0 if j % 5 == 0 else 13.0) * (1.0 + R / 900.0)
			var Pk := PackedVector3Array()
			for i in 4:
				Pk.append(_pw(tower_px + dv * (R + ln * float(i) / 3.0)))
			res.append({"p": Pk, "w": 1.6 if j % 5 == 0 else 1.0, "k": kw * 0.9, "c": WARM, "nw": true})
	wave_R = R
	return res


# ================================================================ 一镜到底机位
func _build_path() -> void:
	var hb := hub_w
	var oe: Vector3 = S.o_e
	path_keys = [
		[0.0, Vector3(0, 0, 2015), hb, 0.0, 30.0],
		[0.2, Vector3(-120, 90, 1380), hb, 0.22, 33.0],
		[0.5, hb + Vector3(2350, -980, 1650), hb + Vector3(-40, 60, -260), -0.06, 23.0],
		[0.68, hb + Vector3(1300, -650, 1150), hb + Vector3(0, 0, -250), 0.12, 40.0],
		[0.92, hb + Vector3(1500, -450, 1500), hb + Vector3(0, 0, -300), 0.08, 40.0],
		[1.18, hb + Vector3(700, -200, 1600), hb + Vector3(0, 0, -2600), 0.04, 40.0],
		[1.5, oe + Vector3(140, -50, 700), oe + Vector3(0, 0, -fz), 0.0, 33.0],
		[1.85, oe, oe + Vector3(0, 0, -fz), 0.0, 30.0],
		[T_END, oe, oe + Vector3(0, 0, -fz), 0.0, 30.0],
	]


func _look(pos: Vector3, at: Vector3, roll := 0.0) -> Transform3D:
	var X := Transform3D.IDENTITY.looking_at(at - pos, Vector3.UP)
	X.origin = pos
	if roll != 0.0:
		X.basis = X.basis * Basis(Vector3.BACK, roll)
	return X


func _cr(a: Vector3, b: Vector3, c: Vector3, d: Vector3, u: float) -> Vector3:
	var u2 := u * u
	var u3 := u2 * u
	return 0.5 * ((2.0 * b) + (-a + c) * u + (2.0 * a - 5.0 * b + 4.0 * c - d) * u2 + (-a + 3.0 * b - 3.0 * c + d) * u3)


func _path(t: float) -> Array:
	var n := path_keys.size()
	if t <= float(path_keys[0][0]):
		return [path_keys[0][1], path_keys[0][2], path_keys[0][3], path_keys[0][4]]
	if t >= float(path_keys[n - 1][0]):
		return [path_keys[n - 1][1], path_keys[n - 1][2], path_keys[n - 1][3], path_keys[n - 1][4]]
	var i := 0
	while i < n - 2 and t > float(path_keys[i + 1][0]):
		i += 1
	var k0: Array = path_keys[maxi(i - 1, 0)]
	var k1: Array = path_keys[i]
	var k2: Array = path_keys[i + 1]
	var k3: Array = path_keys[mini(i + 2, n - 1)]
	var u := (t - float(k1[0])) / (float(k2[0]) - float(k1[0]))
	var ue := u * u * (3.0 - 2.0 * u) * 0.35 + u * 0.65
	if i == n - 2:
		ue = _o3(u)
	return [_cr(k0[1], k1[1], k2[1], k3[1], ue), _cr(k0[2], k1[2], k2[2], k3[2], ue), lerpf(k1[3], k2[3], ue), lerpf(k1[4], k2[4], ue)]


func _hide_home() -> void:
	C._ink_bg.visible = false
	C._ink_vig.visible = false
	C._violet_plane.visible = false
	for d: Dictionary in C._debris:
		(d["g"] as Node3D).visible = false
	for hh: Dictionary in C._mark_halves:
		for ly: Dictionary in hh["layers"]:
			(ly["mi"] as Node3D).visible = false
	for lb in C._readout:
		lb.visible = false


func _cam_update(t: float) -> Array:
	var p := _path(t)
	var X := _look(p[0], p[1], p[2])
	cam.global_transform = X
	cam.fov = p[3]
	return [X, p[3]]


func _process(_dt: float) -> void:
	if not running:
		return
	S.t_state = S.now - minf(tv, 2.7) + 1.0 / 60.0
	_hide_home()
	if tv > 0.25:
		C._seam.visible = false
	_rig_update(tv)
	_stage_update(tv)
	var cx := _cam_update(tv)
	_rebuild(_lines_update(tv), cx[0], cx[1])


func _run() -> void:
	T._finish_intro()
	T.stuck_next = 1e9
	for c in T.get_children():
		if c is CanvasLayer:
			c.visible = false
	for i in 20:
		await get_tree().process_frame
	S = T.sel
	hub_w = C.to_world(C.HUB.x, C.HUB.y, S.DIAL_Z)
	home_xf = Transform3D(Basis(Vector3.BACK, -float(C.TILT)), hub_w)
	_build_spin()
	T._go("select")
	for i in 6:
		await get_tree().process_frame
	min0 = -(float(C.TWELVE) - float(C.GAP) + 0.55) + float(C.TILT)
	hour0 = -float(T.hand["a"]) + float(C.TILT)
	_load_data()
	_build_path()
	running = true
	var times: Array = []
	if OS.has_environment("ZZ_PREVIS_T"):
		for x in OS.get_environment("ZZ_PREVIS_T").split(","):
			times.append(float(x))
	else:
		var fps := int(OS.get_environment("ZZ_PREVIS_FPS")) if OS.has_environment("ZZ_PREVIS_FPS") else 60
		for i in int(T_END * fps) + 1:
			times.append(float(i) / fps)
	var k := 0
	for x: float in times:
		tv = x
		for i in 3:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var nm := "f%04d.png" % k if not OS.has_environment("ZZ_PREVIS_T") else "t%04d.png" % int(round(x * 1000.0))
		get_viewport().get_texture().get_image().save_png(out.path_join(nm))
		k += 1
	get_tree().quit()
