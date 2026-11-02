extends Node2D
## 大招 ④ 地图斩 + ⑤ 收刀里画在世界上面的东西（10-31，照 Remotion UltMapSlashV3 / V4 移过来，整段预览 13 那一版；
## 11-01 用户看完预览 22c 说“可以，进游戏”：换成 UltMapSlashV5——刀尖出画后的时停 16 → 6 帧，断开后镜头推到她身上看收刀；
## 同日用户：“大招尾部改成预览21样子”：换成 UltMapSlashV6——时停保持 6 帧，断开后回到 v4 的广角收尾，不推近）。
## 坐标用样片的画面坐标（“样片单位”：她脚下 (280, 446)，身高 73），由 ult_fx 把整个节点摆到世界里：
## 原点对到她脚下、按敌群在哪边左右翻、1 样片单位 = 平常镜头下 1.5 屏幕像素（样片镜头 1.5 倍 = 游戏平常镜头）。
## 世界本身（压暗、沿线错开、退潮）在 fx_ult_world.gdshader；冲击帧 / 时停 / 甩镜头模糊在 fx_ult_post.gdshader。
## 帧号 m = 地图斩开始后第几帧（60fps）：
##   0～12   贴脸切进（2.4 倍），斩线从她刀尖往前射出，镜头甩着追刀尖、拉远到整条街；她身前一道横向弧光
##   12～14  刀尖出画：冲击帧两张
##   14～20  时停：雨和墨点停在半空，斩线发着光，镜头极慢地往前压
##   20～23  断开：冲击帧三张（白底剪影 → 反相 → 纯黑只剩一道白线）
##   23～    整条街沿线错开，线缝爆开再收窄，两道余波，石屑墨点碎羽落下，震屏
##   38～60  收刀：游戏里现成的收刀动作帧（广角里看，不推近）
##   60      “咔”：换成低身按刀柄；刀柄一点白光；两半世界一下合回去；斩线碎成鸦羽
##   62～104 影子退潮，颜色恢复，镜头回到平常（ult_fx 接）
##   ～114   结束

const FRAMES := 114
const STOP := 12
const SPLIT := 20
const CALM := 38
const CLICK := 60
const W := 1280.0
const H := 720.0
const STREET := 446.0
const HER := Vector3(280.0, 84.0, 73.0)      ## x, 宽, 高
const SLOPE := -0.07
const PIVOT := Vector2(280.0, 418.0)
const RIM := Color("eef0ff")
const VIOLET := Color("9a64ff")
## 收刀姿势（游戏里现成的收刀动作帧，裁过边）：[文件, 腿部中心在宽里的比例]
const POSES := [["pose_002", 0.614], ["pose_003", 0.465], ["pose_004", 0.438], ["pose_005", 0.452],
	["pose_006", 0.418], ["pose_007", 0.407], ["pose_008", 0.406]]
const POSE_DIR := "res://assets/image/ult/sheathe/"
const PAD := 10                                   ## 贴图四周补的透明边（给描边和紫辉留地方）

var m := 0.0
var side := 1.0
var _tex := {}
var _her: Sprite2D
var _her_mat: ShaderMaterial
var _arc: Node2D
var _fx: Node2D
var _chips: Array = []
var _spray: Array = []
var _crow: Array = []
var _rain: Array = []


static func ramp(t: float, a: float, b: float) -> float:
	return clampf((t - a) / (b - a), 0.0, 1.0)


static func ease_out(k: float) -> float:
	return 1.0 - pow(1.0 - k, 3.0)


static func ease_in_out(k: float) -> float:
	return 4.0 * k * k * k if k < 0.5 else 1.0 - pow(-2.0 * k + 2.0, 3.0) / 2.0


static func line_y(x: float) -> float:
	return PIVOT.y + (x - PIVOT.x) * SLOPE


static func dir() -> Vector2:
	return Vector2(1.0, SLOPE).normalized()


static func normal() -> Vector2:
	var d := dir()
	return Vector2(-d.y, d.x)        # 指向线的下方


## 错开量：一下冲到 70，回弹停在 46；“咔”一下合回去，带一点回弹
static func slide(f: float) -> float:
	if f < SPLIT:
		return 0.0
	if f >= CLICK:
		var k := f - CLICK
		if k >= 10.0:
			return 0.0
		var at := 46.0 + 24.0 * exp(-(CLICK - SPLIT - 4.0) / 5.0) * cos((CLICK - SPLIT - 4.0) * 0.5)
		return at * (1.0 - ease_out(k / 3.0)) if k < 3.0 else -5.0 * sin(PI * (k - 3.0) / 7.0)
	var t := f - SPLIT
	if t < 4.0:
		return 70.0 * ease_out(t / 4.0)
	return 46.0 + 24.0 * exp(-(t - 4.0) / 5.0) * cos((t - 4.0) * 0.5)


## 一半世界的位移：沿线滑 s，再沿法线张开一点露出线缝（样片单位）
static func offset(s: float, above: bool) -> Vector2:
	var sg := 1.0 if above else -1.0
	var gap := 4.0 + 0.2 * s if s > 0.0 else 0.0
	return dir() * sg * s - normal() * sg * gap


## 震屏（屏幕像素）
static func shake(f: float) -> Vector2:
	var c := f - CLICK
	if c >= 0.0 and c <= 10.0:
		var a := 5.0 * pow(1.0 - c / 10.0, 2.0)
		return Vector2(sin(c * 3.1) * a, cos(c * 4.3) * a * 0.6)
	var k := f - SPLIT
	if k < 0.0 or k > 26.0:
		return Vector2.ZERO
	var a2 := 20.0 * pow(1.0 - k / 26.0, 2.0)
	return Vector2(sin(k * 2.7) * a2, cos(k * 3.9) * a2 * 0.7)


## 镜头：中心 (x, y) + 倍数 z（样片单位），w = 甩镜头模糊（像素）。贴脸切进 → 甩着追刀尖、拉远 → 时停里极慢地压 → 断开时猛推再回
## “咔”之后的推回由 ult_fx 接到游戏平常的镜头上，这里只给“咔”那一刻的机位
static func camera(f: float) -> Vector4:
	var w := ease_in_out(ramp(f, 1.0, STOP))
	var sc := 2.4 + (1.12 - 2.4) * w
	var cx := HER.x + 20.0 + (700.0 - HER.x - 20.0) * w
	var cy := 405.0 + (360.0 - 405.0) * w
	if f >= STOP:
		sc = 1.12 + 0.05 * ramp(f, STOP, SPLIT)
	if f >= SPLIT:
		var f2 := minf(f, CLICK)
		sc = 1.17 + 0.09 * exp(-(f2 - SPLIT - 3.0) / 5.0) * ((f2 - SPLIT) / 3.0 if f2 < SPLIT + 3 else 1.0) - 0.03 * ramp(f2, SPLIT, SPLIT + 20)
	var blur := 3.2 * sin(PI * ramp(f, 1.0, STOP)) if f < STOP else 0.0
	return Vector4(cx, cy, sc, blur)


## 影子退潮的半径（样片单位）：先快后慢地缩回她脚下
static func tide_r(f: float) -> float:
	return 1150.0 * (1.0 - ease_out(ramp(f, CLICK + 2, CLICK + 36)))


## 冲击帧：0 没有 / 1 白底黑剪影 / 2 反相 / 3 纯黑只剩白线
static func impact(f: int) -> int:
	if f == STOP or f == SPLIT:
		return 1
	if f == STOP + 1 or f == SPLIT + 1:
		return 2
	if f == SPLIT + 2:
		return 3
	return 0


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261031
	for i in 30:
		var x := HER.x + 50.0 + (W - 30.0 - HER.x - 50.0) * rng.randf()
		_chips.append({"x": x, "y": line_y(x), "s": 2.0 + 3.5 * rng.randf(), "vx": (rng.randf() - 0.5) * 2.4, "spin": (rng.randf() - 0.5) * 30.0})
	for i in 46:
		var x := -40.0 + (W + 80.0) * rng.randf()
		var far := absf(x - PIVOT.x) / (PIVOT.x + 80.0 if x < PIVOT.x else W + 80.0 - PIVOT.x)
		var sd := 1.0 if rng.randf() > 0.35 else -1.0
		_spray.append({"x": x, "born": STOP * pow(far, 1.6), "vx": (rng.randf() - 0.5) * 3.0, "vn": sd * (1.5 + 3.5 * rng.randf()),
			"r": 1.2 + 2.6 * rng.randf(), "feather": i % 5 == 0, "spin": (rng.randf() - 0.5) * 24.0})
	for i in 54:
		_crow.append({"x": -30.0 + (W + 60.0) * rng.randf(), "delay": absf(rng.randf() - 0.5) * 6.0, "vx": (rng.randf() - 0.5) * 2.2,
			"up": 2.0 + 3.0 * rng.randf(), "L": 9.0 + 9.0 * rng.randf(), "ph": rng.randf() * TAU, "sw": 4.0 + 7.0 * rng.randf()})
	for i in 150:
		_rain.append({"x": -400.0 + 2080.0 * rng.randf(), "sp": 26.0 + 14.0 * rng.randf(), "y": rng.randf() * 1300.0})
	for p in POSES:
		_tex[p[0]] = _load_padded(POSE_DIR + p[0] + ".png")
	_tex["sheathed"] = _load_padded(POSE_DIR + "sheathed.png")
	_tex["idle"] = _load_padded(POSE_DIR + "idle.png")
	_fx = Node2D.new()
	add_child(_fx)
	_fx.draw.connect(_draw_fx)
	_her = Sprite2D.new()
	_her.centered = false
	_her.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_her_mat = ShaderMaterial.new()
	_her_mat.shader = preload("res://assets/shaders/fx_ult_her.gdshader")
	_her_mat.set_shader_parameter("rim_px", 1.0)
	_her_mat.set_shader_parameter("glow_px", 4.0)
	_her_mat.set_shader_parameter("rim_a", 0.9)
	_her_mat.set_shader_parameter("glow_a", 0.7)
	_her.material = _her_mat
	add_child(_her)
	_arc = Node2D.new()
	add_child(_arc)
	_arc.draw.connect(_draw_arc)


## 读 PNG 并在四周补 PAD 像素透明边
static func _load_padded(path: String) -> Texture2D:
	var img := Image.new()
	if FileAccess.file_exists(path):
		if img.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
			return null
	elif ResourceLoader.exists(path):
		var t := load(path) as Texture2D
		if t == null:
			return null
		img = t.get_image()
	else:
		return null
	img.convert(Image.FORMAT_RGBA8)
	var out := Image.create(img.get_width() + PAD * 2, img.get_height() + PAD * 2, false, Image.FORMAT_RGBA8)
	out.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(PAD, PAD))
	out.generate_mipmaps()
	return ImageTexture.create_from_image(out)


## 每帧：m 帧号，sc 当前镜头倍数（给描边算粗细），flash 冲击帧时她涂成的颜色
func update(frame: float, sc: float, flash: Color) -> void:
	m = frame
	var lo := offset(slide(m), false)
	_her.position = lo
	_arc.position = lo
	_update_her(sc, flash)
	_fx.queue_redraw()
	_arc.queue_redraw()


func _update_her(sc: float, flash: Color) -> void:
	var key := "idle"
	var cx := 0.5
	var k := HER.z / 409.0
	var glint := 0.0
	if m >= CLICK:
		key = "sheathed"
		cx = 0.501
		k = HER.z * 0.72 / 199.0
		glint = 1.0 - ramp(m, CLICK, CLICK + 8)
	elif m >= CALM:
		var i := mini(POSES.size() - 1, int(floor((m - CALM) / float(CLICK - CALM) * POSES.size())))
		key = POSES[i][0]
		cx = POSES[i][1]
		k = HER.z / 335.0
	var tex: Texture2D = _tex.get(key)
	_her.visible = tex != null
	if tex == null:
		return
	_her.texture = tex
	var w := tex.get_width() - PAD * 2
	var h := tex.get_height() - PAD * 2
	_her.scale = Vector2(k, k)
	_her.offset = Vector2(-PAD - w * cx, -PAD - h)
	_her.position += Vector2(HER.x, STREET)
	_her_mat.set_shader_parameter("bright", 0.85 if m < CALM else 0.9)
	_her_mat.set_shader_parameter("px_scale", k * sc)
	_her_mat.set_shader_parameter("flat_col", flash)
	_her.set_meta("glint", glint)
	_her.set_meta("glint_y", h * k * 0.52)


# ---------------------------------------------------------------- 画

func _draw_fx() -> void:
	_draw_chips()
	_draw_rain()
	_draw_spray()
	_draw_slash()
	_draw_shock()
	_draw_tip()
	if m >= CLICK:
		_draw_crow_feathers()


## 断口掉下来的石屑：从斩线穿过房子的那一段往下掉
func _draw_chips() -> void:
	var t := m - SPLIT
	if t < 0.0:
		return
	for c in _chips:
		var p := Vector2(c.x + c.vx * t, c.y + 0.14 * t * t)
		if p.y > STREET + 21.0:
			continue
		var s: float = c.s
		var q := PackedVector2Array([Vector2(-s, -s * 0.4), Vector2(s * 0.3, -s), Vector2(s, s * 0.2), Vector2(-s * 0.2, s * 0.8)])
		var xf := Transform2D(deg_to_rad(c.spin * t), p)
		_fx.draw_set_transform_matrix(xf)
		_fx.draw_colored_polygon(_shift(q, Vector2(-0.5, -1.0)), Color(RIM, 0.8))
		_fx.draw_colored_polygon(q, Color("14141c"))
	_fx.draw_set_transform_matrix(Transform2D.IDENTITY)


## 雨：停一拍的时候停在半空
func _draw_rain() -> void:
	var t := m if m < STOP else (float(STOP) if m < SPLIT else STOP + (m - SPLIT))
	var col := Color("c8ccdd")
	col.a = 0.22
	for r in _rain:
		var y: float = fposmod(r.y + t * r.sp, 1300.0) - 300.0
		var x: float = r.x - y * 0.18
		_fx.draw_line(Vector2(x, y), Vector2(x - 3.0, y + 16.0), col, 1.0, true)


## 沿线溅出的墨点和碎羽：刀尖经过的那一帧冒出来；时停时悬在半空，断开后再落
func _draw_spray() -> void:
	var tt := minf(m, STOP + 3.0) if m < SPLIT else STOP + 3.0 + (m - SPLIT) * 0.8
	var out := ramp(m, SPLIT + 14, SPLIT + 40)
	if out >= 1.0:
		return
	var n := normal()
	for p in _spray:
		var t: float = tt - p.born
		if t < 0.0:
			continue
		var g := 0.0 if m < SPLIT else 0.05 * pow(tt - STOP - 3.0, 2.0)
		var pos := Vector2(p.x + p.vx * t + n.x * p.vn * t, line_y(p.x) + n.y * p.vn * t + g)
		if pos.y > H:
			continue
		if p.feather:
			var L: float = 9.0 + p.r * 2.0
			_fx.draw_set_transform(pos, deg_to_rad(-20.0 + p.spin * t))
			var fe := _feather_poly(L, 0.28, 0.2)
			_fx.draw_colored_polygon(fe, Color(0.02, 0.02, 0.03, 1.0 - out))
			_fx.draw_polyline(_close(fe), Color(RIM, 1.0 - out), 0.7, true)
			_fx.draw_set_transform_matrix(Transform2D.IDENTITY)
			continue
		var r: float = p.r * (1.0 - 0.5 * out)
		_fx.draw_circle(pos + Vector2(-0.5, -1.0), r, Color(RIM, 0.85))
		_fx.draw_circle(pos, r, Color.BLACK)


## 斩线：刀痕。白芯两头尖，外面一圈黑墨边，再外面一层淡紫辉光
func _blade(xl: float, xr: float, half: float, n := 48) -> PackedVector2Array:
	var top := PackedVector2Array()
	var bot := PackedVector2Array()
	var nn := normal()
	for i in n + 1:
		var u := float(i) / float(n)
		var x := xl + (xr - xl) * u
		var k := (x - xl) / maxf(1.0, PIVOT.x - xl) if x < PIVOT.x else (xr - x) / maxf(1.0, xr - PIVOT.x)
		var w := half * pow(clampf(k, 0.0, 1.0), 0.45)
		var y := line_y(x)
		top.append(Vector2(x, y) - nn * w)
		bot.append(Vector2(x, y) + nn * w)
	bot.reverse()
	top.append_array(bot)
	return top


func _draw_slash() -> void:
	var draw := 1.0 - pow(1.0 - ramp(m, 0.0, STOP), 1.4)
	var xl := PIVOT.x - (PIVOT.x + 80.0) * ease_out(ramp(m, 0.0, 4.0))
	var xr := PIVOT.x + (W + 80.0 - PIVOT.x) * draw
	var hold := m < SPLIT
	var fade := 1.0 if hold else 1.0 - ramp(m, SPLIT + 3, SPLIT + 12)
	if fade <= 0.0 or xr - xl < 2.0:
		return
	var core := (3.6 + 0.4 * sin(m * 0.9) if hold else 2.4) * fade
	var flare := 1.0 - ramp(m, STOP, STOP + 6)
	for g in 8:      # 紫辉：一层层叠出来的软边（样片里是 7 像素高斯模糊）
		_fx.draw_colored_polygon(_blade(xl, xr, 4.0 + 8.0 * flare + 2.2 * g), Color(0.56, 0.36, 1.0, 0.5 * fade * 0.11))
	_fx.draw_colored_polygon(_shift(_blade(xl, xr, core + 2.6 + 3.0 * flare), Vector2(0, 1.5)), Color.BLACK)
	_fx.draw_colored_polygon(_blade(xl, xr, core + 2.5 * flare), Color.WHITE)


## 断开后的余波：两道细白线沿斩线往外推开、淡掉
func _draw_shock() -> void:
	var t := m - SPLIT - 3.0
	if t < 0.0 or t > 18.0:
		return
	var d := 10.0 + 9.0 * t
	var o := 1.0 - t / 18.0
	var n := normal()
	for sg in [1.0, -1.0]:
		var a: Vector2 = Vector2(-200.0, line_y(-200.0)) + n * d * sg
		var b: Vector2 = Vector2(W + 200.0, line_y(W + 200.0)) + n * d * sg
		_fx.draw_line(a, b, Color(RIM, 0.8 * o), 2.2 * o + 0.4, true)


## 刀尖那一团白光：跟着斩线往前冲，出画就没了
func _draw_tip() -> void:
	if m >= STOP:
		return
	var draw := 1.0 - pow(1.0 - ramp(m, 0.0, STOP), 1.4)
	var x := PIVOT.x + (W + 80.0 - PIVOT.x) * draw
	var c := Vector2(x, line_y(x))
	_fx.draw_set_transform(c, atan(SLOPE))
	for i in 6:
		var k := 1.0 - float(i) / 6.0
		var col := Color("7b4dff").lerp(Color.WHITE, float(i) / 5.0)
		col.a = 0.18 + 0.12 * float(i)
		_fx.draw_colored_polygon(_ellipse(34.0 * k, 10.0 * k), col)
	_fx.draw_circle(Vector2.ZERO, 3.5, Color.WHITE)
	_fx.draw_set_transform_matrix(Transform2D.IDENTITY)


## 斩线碎成鸦羽：“咔”那一刻沿线冒出来，先弹起，再左右摆着慢慢落
func _draw_crow_feathers() -> void:
	var o := 1.0 - ramp(m, CLICK + 34, FRAMES)
	for c in _crow:
		var t: float = m - CLICK - c.delay
		if t < 0.0:
			continue
		var tu := minf(t, 10.0)
		var y: float = line_y(c.x) - c.up * (tu - tu * tu / 20.0) + maxf(0.0, t - 10.0) * 0.9
		var x: float = c.x + c.vx * t + c.sw * sin(t * 0.11 + c.ph)
		var rot: float = 70.0 + 35.0 * cos(t * 0.11 + c.ph)
		var flip := 0.4 + 0.6 * absf(cos(t * 0.07 + c.ph))
		var L: float = c.L
		_fx.draw_set_transform(Vector2(x, y), deg_to_rad(rot), Vector2(1.0, flip))
		var fe := PackedVector2Array([Vector2(-L / 2.0, 0)])
		fe.append_array(_quad(Vector2(-L / 2.0, 0), Vector2(-L * 0.1, -L * 0.24), Vector2(L / 2.0, -L * 0.04)))
		fe.append_array(_quad(Vector2(L / 2.0, -L * 0.04), Vector2(-L * 0.05, L * 0.16), Vector2(-L / 2.0, 0)))
		fe.remove_at(fe.size() - 1)
		_fx.draw_colored_polygon(fe, Color(0.027, 0.027, 0.043, o))
		_fx.draw_polyline(_close(fe), Color(RIM, o), 0.6, true)
		_fx.draw_line(Vector2(-L / 2.0 - 2.0, 0), Vector2(L / 2.0, -L * 0.03), Color(RIM, 0.75 * o), 0.45, true)
	_fx.draw_set_transform_matrix(Transform2D.IDENTITY)


## 她身前那道刚挥完的横向弧光：白芯紫边，9 帧散掉；“咔”时刀柄一点白光
func _draw_arc() -> void:
	var glint: float = _her.get_meta("glint", 0.0)
	if glint > 0.0:
		var gy: float = STREET - float(_her.get_meta("glint_y", 30.0))
		_arc.draw_circle(Vector2(HER.x + 4.0, gy), 10.0 * glint, Color(1, 1, 1, glint))
		_arc.draw_line(Vector2(HER.x + 4.0 - 26.0 * glint, gy), Vector2(HER.x + 4.0 + 26.0 * glint, gy), Color(1, 1, 1, glint), 1.4, true)
	if m > 9.0:
		return
	var k := ramp(m, 0.0, 9.0)
	var c := Vector2(HER.x + 6.0, STREET - HER.z * 0.55)
	var rx := 62.0 + 10.0 * k
	var ry := 16.0 + 3.0 * k
	var a0 := PI * 0.95
	var a1 := PI * (2.05 + 0.1 * k)
	var band := func(th: float) -> PackedVector2Array:
		var o := PackedVector2Array()
		var inn := PackedVector2Array()
		for i in 25:
			var a := a0 + (a1 - a0) * (float(i) / 24.0)
			var w := th * pow(sin(PI * (float(i) / 24.0)), 0.7) * (float(i) / 24.0)
			o.append(c + Vector2(cos(a) * (rx + w), sin(a) * (ry + w * 0.4)))
			inn.append(c + Vector2(cos(a) * (rx - w), sin(a) * (ry - w * 0.4)))
		inn.reverse()
		o.append_array(inn)
		return o
	for g in 6:
		_arc.draw_colored_polygon(band.call(6.0 + 2.0 * g), Color(VIOLET, (1.0 - k) * 0.16))
	_arc.draw_colored_polygon(band.call(5.0), Color(1, 1, 1, 1.0 - k))


# ---------------------------------------------------------------- 小工具

static func _shift(q: PackedVector2Array, d: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for v in q:
		out.append(v + d)
	return out


static func _close(q: PackedVector2Array) -> PackedVector2Array:
	var out := q.duplicate()
	if q.size() > 0:
		out.append(q[0])
	return out


static func _quad(a: Vector2, c: Vector2, b: Vector2, n := 6) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(1, n + 1):
		var t := float(i) / float(n)
		out.append(a.lerp(c, t).lerp(c.lerp(b, t), t))
	return out


static func _ellipse(rx: float, ry: float, n := 20) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n:
		var a := TAU * float(i) / float(n)
		out.append(Vector2(cos(a) * rx, sin(a) * ry))
	return out


static func _feather_poly(L: float, up: float, down: float) -> PackedVector2Array:
	var fe := PackedVector2Array([Vector2(-L / 2.0, 0)])
	fe.append_array(_quad(Vector2(-L / 2.0, 0), Vector2(0, -L * up), Vector2(L / 2.0, 0)))
	fe.append_array(_quad(Vector2(L / 2.0, 0), Vector2(0, L * down), Vector2(-L / 2.0, 0)))
	fe.remove_at(fe.size() - 1)
	return fe
