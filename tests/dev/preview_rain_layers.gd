extends SceneTree
## 开发工具（分层试验 11-08）：只在内存里把雨街第 0 段换成 5 层分层背景，让主角走过去录视频。不改任何游戏文件。
## 素材先跑 tools/art/rain_layer_test_prep.py。需要真实渲染（不加 --headless）：
##   engine/Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/dev/preview_rain_layers.gd --resolution 1280x720 --fixed-fps 60 --write-movie <目录>/f.png
## 环境变量 STILL_DIR：设了就不走动，只在几个位置截图到这个目录（调参用）。
const Buffer := preload("res://scripts/core/input_buffer.gd")
const DIR := "res://source-art/rain-layer-test-20261108/"
const PX := 1.62                  ## 成图 1 像素 = 多少世界单位（和现有近景同比例）
const WALK_FROM := 1500.0          ## 相对第 0 段中心：这一截街面上没有实心石台
const WALK_TO := 3420.0
const STAND_PX0 := 700.0          ## 站立层左边缘（相对第 0 段中心）
const STREET_PX := 800.0          ## 站立层成图里脚踩的那一行
const CAM_Y := 272.3              ## 走在街面上时镜头中心的 y
const SKY_TOWER := Vector2(100.0, -630.0)    ## 天际线钟楼左上角（容器坐标，相对 anchor）
const SKY_TOWER_S := 0.6
const SKY_DROP := 260.0          ## 远景和中景整体往下压多少（容器坐标）
const FAR_HAZE := 0.5            ## 远近明暗阶梯：越往后越接近雾色
const MID_HAZE := 0.42
const ROW2_HAZE := 0.36
const ROW1_HAZE := 0.26
const FLOOR := 580.0             ## 脚踩的那条线：背景以它和门洞中心为支点整体缩放
const C_LIGHT := Color(1.0, 0.93, 0.78)
const C_LAMP := Color(1.0, 0.9, 0.72)
const RAIN_TILT := 0.1            ## 雨的斜度：每往下 1，往左 0.1
const LEDGES := [[75, 282, 526], [345, 780, 606], [788, 1452, 468]]    ## 站立层上能站的台面（成图 x0, x1, y），和素材脚本一致
const FOG_SHADER := """shader_type canvas_item;
uniform sampler2D n : repeat_enable, filter_linear;
uniform vec4 col : source_color;
uniform float k = 1.0;
uniform float spd = 0.01;
uniform float y0 = 0.3;
uniform float y1 = 0.9;
uniform float strength = 0.5;
uniform float cam_x = 0.0;
uniform float t = 0.0;
uniform sampler2D screen : hint_screen_texture;
void fragment() {
	vec2 p = SCREEN_UV * vec2(1.78, 1.0) * 1.1 + vec2(cam_x * k / 1280.0, 0.0);
	float a = texture(n, p + vec2(t * spd, t * spd * 0.2)).r * texture(n, p * 1.9 - vec2(t * spd * 1.4, 0.0)).r * 2.2;
	float mask = smoothstep(y0, y1, SCREEN_UV.y);
	float ign = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
	COLOR = vec4(col.rgb + (ign - 0.5) / 96.0, clamp(a * mask * strength + (ign - 0.5) / 64.0, 0.0, 1.0));
}
"""
const GLOW_SHADER := """shader_type canvas_item;
render_mode blend_add;
uniform float gain = 1.0;
void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	float ign = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
	COLOR = vec4(c.rgb * c.a * gain + (ign - 0.5) / 96.0 * step(0.004, c.a), 1.0);
}
"""
## 中景（11-12 用户“1–5 都做”）：每层往后更亮、更冷、对比更弱、更虚；楼脚压雾；远处暖窗；月光勾边；闪电时轮廓亮一下
const DEPTH_SHADER := """shader_type canvas_item;
uniform vec3 tint = vec3(1.0);
uniform vec3 haze_col = vec3(0.13, 0.16, 0.25);
uniform float haze = 0.3;
uniform float contrast = 1.0;
uniform float blur_px = 0.0;
uniform float fog_y0 = 300.0;
uniform float fog_y1 = 540.0;
uniform float fog_amt = 0.0;
uniform vec3 fog_col = vec3(0.2, 0.25, 0.36);
uniform vec2 rim_dir = vec2(0.35, -0.94);
uniform float rim_px = 4.0;
uniform float rim_amt = 0.0;
uniform vec3 rim_col = vec3(0.6, 0.7, 0.9);
uniform vec4 win[8];
uniform float win_on[8];
uniform vec3 win_col = vec3(1.0, 0.68, 0.38);
uniform float win_gain = 1.0;
uniform float glass_lo = 0.06;
uniform float glass_hi = 0.095;
uniform float flash = 0.0;
varying float wy;
void vertex() {
	wy = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).y;
}
void fragment() {
	vec2 ps = TEXTURE_PIXEL_SIZE;
	vec4 c = texture(TEXTURE, UV);
	if (blur_px > 0.0) {
		vec4 acc = vec4(c.rgb * c.a, c.a);
		for (int i = 0; i < 8; i++) {
			float an = float(i) * 0.785398;
			vec4 s = texture(TEXTURE, UV + vec2(cos(an), sin(an)) * blur_px * ps);
			acc += vec4(s.rgb * s.a, s.a);
		}
		c = vec4(acc.rgb / max(acc.a, 0.001), acc.a / 9.0);
	}
	float lum = dot(c.rgb, vec3(0.3, 0.5, 0.2));
	vec3 col = c.rgb * tint;
	vec2 px = UV / ps;
	float wl = 0.0;
	for (int i = 0; i < 8; i++) {
		if (win_on[i] > 0.001) {
			vec4 r = win[i];
			vec2 d = max(r.xy - px, px - r.zw);
			float v = clamp((px.y - r.y) / max(r.w - r.y, 1.0), 0.0, 1.0);
			wl += (1.0 - smoothstep(-5.0, 0.5, max(d.x, d.y))) * win_on[i] * (0.45 + 0.55 * v);    // 屋里的灯在下面：窗下半截更亮
		}
	}
	float glass = pow(1.0 - smoothstep(glass_lo, glass_hi, lum), 2.0);    // 只有玻璃亮，窗框和窗棂留暗
	float a2 = texture(TEXTURE, UV + rim_dir * rim_px * ps).a;
	float rim = c.a * (1.0 - a2);
	col = (col - haze_col) * contrast + haze_col;
	col += rim_col * rim * rim_amt;
	col = mix(col, haze_col, haze);
	col = mix(col, fog_col, clamp(smoothstep(fog_y0, fog_y1, wy) * fog_amt, 0.0, 1.0));
	col += win_col * wl * glass * win_gain * 0.5 * (1.0 - 0.5 * haze);
	col += vec3(0.5, 0.56, 0.75) * flash * (0.1 + rim * 0.7);
	COLOR = vec4(col, c.a);    // fragment 里的 COLOR 已经乘过贴图，不能再乘一次
}
"""
## 远处的雨幕：屏幕上一列列细雨线，比近处的雨慢、淡，随镜头按视差平移
const CURTAIN_SHADER := """shader_type canvas_item;
uniform float cam_x = 0.0;
uniform float t = 0.0;
uniform float k = 0.3;
uniform float cell = 9.0;
uniform float density = 0.35;
uniform float speed = 500.0;
uniform float seg = 60.0;
uniform float period = 420.0;
uniform float alpha = 0.12;
uniform float y0 = 0.0;
uniform float y1 = 1.0;
uniform vec4 col : source_color = vec4(0.6, 0.68, 0.85, 1.0);
uniform float tilt = 0.1;
uniform float flash = 0.0;
float h(float n) { return fract(sin(n * 127.1) * 43758.5453); }
void fragment() {
	vec2 p = SCREEN_UV * vec2(1280.0, 720.0);
	p.x += cam_x * k * 0.65 + p.y * tilt;
	float ci = floor(p.x / cell);
	float hh = h(ci);
	float on = step(1.0 - density, hh);
	float fx = abs(fract(p.x / cell) - 0.5) * cell;
	float line = 1.0 - smoothstep(0.25, 0.85, fx);
	float y = p.y - t * speed * (0.75 + 0.5 * h(ci + 7.0)) + hh * period;
	float s = fract(y / period) * period;
	float st = smoothstep(0.0, seg * 0.25, s) * (1.0 - smoothstep(seg * 0.25, seg, s));
	float m = smoothstep(y0, y0 + 0.1, SCREEN_UV.y) * (1.0 - smoothstep(y1 - 0.1, y1, SCREEN_UV.y));
	COLOR = vec4(col.rgb + vec3(0.4) * flash, (alpha + flash * 0.25) * on * line * st * m);
}
"""
## 中景三栋楼上的窗（成图像素：玻璃那块的左上、右下）和烟囱口、屋脊（给乌鸦站）
const WINS := {
	"near_a": [[113, 275, 145, 368], [160, 275, 193, 368], [80, 462, 116, 578], [157, 462, 193, 578], [360, 410, 389, 468], [370, 556, 404, 652], [454, 556, 489, 652], [78, 728, 118, 848], [158, 728, 198, 848], [357, 748, 398, 858], [452, 748, 493, 858]],
	"near_b": [[167, 266, 197, 343], [54, 410, 94, 518], [150, 410, 189, 518], [324, 460, 354, 528], [444, 460, 474, 528], [70, 600, 109, 718], [152, 600, 189, 718], [340, 656, 384, 798], [430, 656, 471, 798]],
	"near_c": [[54, 348, 84, 403], [152, 348, 182, 403], [64, 500, 102, 598], [124, 500, 162, 598], [307, 486, 348, 588], [457, 560, 496, 643], [47, 710, 92, 838], [127, 710, 169, 838], [302, 686, 347, 828], [460, 745, 503, 858]],
}
const CHIMNEYS := {
	"near_a": [[100, 60], [128, 68], [237, 140], [446, 268]],
	"near_b": [[86, 128], [298, 278], [447, 364], [530, 256]],
	"near_c": [[122, 192], [152, 176], [305, 300], [514, 170]],
}
var stage
var p
var c0 := 0.0
var anchor := 0.0                 ## 镜头在这里时各层按设计对齐（门洞中心）
var items: Array = []             ## {node, x, y, f}
var fogs: Array = []              ## {node, mat}
var lamps: Array = []             ## {node, a, sp}
var chain: Sprite2D
var halo: Sprite2D
var beads: Array = []
var bead_tex: Texture2D
var bead_back: Node2D
var bead_front: Node2D
var time := 0.0
var bg_k := 0.75                  ## 背景整体缩放（11-12 用户：建筑有些大）；人物、地面高度、水线不变。环境变量 BG_K 可覆盖
var bgw: Node2D                   ## 所有背景件的容器，按 bg_k 缩放
var refl: Node2D
var refl_src: Array = []
var lit_node: Node2D
var lit_src: Array = []
var lit_rain: Array = []
var ledge_node: Node2D
var drip_node: Node2D
var ledges: Array = []
var drips: Array = []
var mid_sprites: Array = []
var house_info := {}              ## 中景专属楼：窗、烟囱口、乌鸦落脚点（素材脚本出的 mid_houses.json）
var depth_mats: Array = []
var win_anim: Array = []
var smoke_src: Array = []
var puffs: Array = []
var smoke_nodes := {}
var crows: Array = []
var crow_nodes := {}
var curtains: Array = []
var flash_sky: Sprite2D
var flash_all: Sprite2D
var bolt_t := 2.6                 ## 第一道闪电在开场后几秒，录像里看得到
var bolt_age := 99.0


func _initialize() -> void:
	call_deferred("run")


func fr(actions: Array[StringName] = [], axis := Vector2.ZERO) -> Buffer.Frame:
	var f := Buffer.Frame.new()
	f.actions = actions
	f.pressed_this_frame = []
	f.axis = axis
	return f


func frames(n: int, f: Buffer.Frame = null) -> void:
	for i in n:
		p.set_injected_frame(f if f != null else fr())
		await physics_frame


func tex(name: String) -> Texture2D:
	var img := Image.load_from_file(ProjectSettings.globalize_path(DIR + name + ".png"))
	return ImageTexture.create_from_image(img)


## 加一层 / 一件：x、y 是镜头在 anchor 时的左上角世界坐标（相对 anchor 的 x），f 是视差（1 = 站立层）
func add(t: Texture2D, x: float, y: float, s: float, f: float, z: int, flip := false, mod := Color.WHITE) -> Sprite2D:
	var sp := Sprite2D.new()
	sp.texture = t
	sp.centered = false
	sp.flip_h = flip
	sp.scale = Vector2(s, s)
	sp.z_as_relative = false
	sp.z_index = z
	sp.modulate = mod
	bgw.add_child(sp)
	items.append({"node": sp, "x": anchor + x, "y": y, "f": f})
	return sp


func add_fog(z: int, c: Color, k: float, spd: float, y0: float, y1: float, strength: float, noise: Texture2D) -> void:
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = FOG_SHADER
	m.shader = sh
	m.set_shader_parameter("n", noise)
	m.set_shader_parameter("col", c)
	m.set_shader_parameter("k", k)
	m.set_shader_parameter("spd", spd)
	m.set_shader_parameter("y0", y0)
	m.set_shader_parameter("y1", y1)
	m.set_shader_parameter("strength", strength)
	var sp := Sprite2D.new()
	var w := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	w.fill(Color.WHITE)
	sp.texture = ImageTexture.create_from_image(w)
	sp.scale = Vector2(400, 240)
	sp.material = m
	sp.z_as_relative = false
	sp.z_index = z
	stage.add_child(sp)
	fogs.append({"node": sp, "mat": m})


func glow_tex() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.add_point(0.45, Color(1, 1, 1, 0.32))
	g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 512
	t.height = 512
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	return t


## 一束从上往下的光：中间亮、两边软，上下都淡出
func beam_tex() -> Texture2D:
	var im := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for yy in 64:
		var v := yy / 63.0
		var fade := smoothstep(0.0, 0.25, v) * (1.0 - smoothstep(0.7, 1.0, v))
		for xx in 64:
			im.set_pixel(xx, yy, Color(1, 1, 1, (1.0 - absf(xx / 31.5 - 1.0)) * fade))
	return ImageTexture.create_from_image(im)


func add_glow(t: Texture2D, x: float, y: float, sx: float, sy: float, f: float, z: int, c: Color, gain: float) -> Sprite2D:
	var sp := add(t, x, y, 1.0, f, z, false, c)
	sp.centered = true
	sp.scale = Vector2(sx / 512.0, sy / 512.0)
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = GLOW_SHADER
	m.shader = sh
	m.set_shader_parameter("gain", gain)
	sp.material = m
	return sp


func build() -> void:
	c0 = stage._center_of(0)
	var x0 := c0 + STAND_PX0
	anchor = x0 + 1248.0 * PX     # 门洞中心
	if OS.get_environment("BG_K") != "":
		bg_k = float(OS.get_environment("BG_K"))
	bgw = Node2D.new()
	bgw.scale = Vector2(bg_k, bg_k)
	bgw.position = Vector2(anchor, FLOOR) * (1.0 - bg_k)
	stage.add_child(bgw)
	var lamp_at := [[STAND_PX0 + 637.0 * PX, 580.0 + (645.0 - STREET_PX) * PX, 0.22, 420.0], [STAND_PX0 + 1428.0 * PX, 580.0 + (610.0 - STREET_PX) * PX, 0.18, 340.0]]
	var bd = stage.backdrop
	# 只动内存里的布局：不要旧近景、旧平台的雨遮挡；灯换成站立层画上的两盏
	var s: Dictionary = bd.layout.sections[0]
	s.art = {}
	s.buildings = []
	s.platforms = []
	s.blocks = []
	s.foreground = []
	s.lamps = []
	for l in lamp_at:
		var wp := to_world(Vector2(c0 + float(l[0]), float(l[1])))
		s.lamps.append([wp.x - c0, wp.y, "wall", 0])
	bd._occ_key = ""
	bd.self_modulate = Color(1, 1, 1, 0)
	bd._sky.visible = false
	bd._glow.visible = false
	bd._fg.visible = false
	stage.terrain.visible = false
	stage.hud.visible = false
	if stage._arrows != null:
		stage._arrows.visible = false

	var top := 580.0 - STREET_PX * PX
	var sky := add(load("res://assets/image/rain_street/sky.png"), -1800.0, -900.0, 1.0, 0.05, -100, false, Color(0.5, 0.52, 0.6))
	sky.scale = Vector2(3600.0 / sky.texture.get_width(), 1700.0 / sky.texture.get_height())
	add_glow(glow_tex(), 0.0, -60.0, 3000.0, 760.0, 0.05, -99, Color(0.42, 0.5, 0.68), 0.42)
	var far_sp := add(tex("far"), -1500.0, top - 470.0 * PX + SKY_DROP, PX, 0.10, -98)    # 中远景往下压：给天际线钟楼留出天空
	# 天际线钟楼：比远景屋顶高出一大截，几乎钉在画面上（视差很小），走动时在近处楼缝里时隐时现；钟室透月光，侧面表盘只一点暗红
	add(tex("sky_tower"), SKY_TOWER.x, SKY_TOWER.y, SKY_TOWER_S, 0.12, -97)
	add_glow(glow_tex(), SKY_TOWER.x + 275.0 * SKY_TOWER_S, SKY_TOWER.y + 525.0 * SKY_TOWER_S, 420.0 * SKY_TOWER_S, 300.0 * SKY_TOWER_S, 0.12, -97, Color(0.7, 0.8, 1.0), 0.12)
	add_glow(glow_tex(), SKY_TOWER.x + 482.0 * SKY_TOWER_S, SKY_TOWER.y + 670.0 * SKY_TOWER_S, 140.0 * SKY_TOWER_S, 200.0 * SKY_TOWER_S, 0.12, -97, Color(0.9, 0.3, 0.18), 0.05)
	var mid_sp := add(tex("mid"), -1450.0, top - 300.0 * PX + SKY_DROP, PX, 0.35, -96)
	depth(far_sp, Color.WHITE, FAR_HAZE, 0.7, 0.0, 0.0, 0.0)
	depth(mid_sp, Color.WHITE, MID_HAZE, 0.75, 0.0, 0.35, 0.45)
	var noise := NoiseTexture2D.new()
	noise.seamless = true
	noise.width = 512
	noise.height = 512
	var fn := FastNoiseLite.new()
	fn.frequency = 0.008
	fn.fractal_octaves = 4
	noise.noise = fn
	await noise.changed
	add_fog(-95, Color(0.14, 0.18, 0.28), 0.25, 0.012, 0.05, 0.85, 0.42, noise)
	add_curtain(-95, 0.3, 7.0, 0.32, 380.0, 40.0, 0.09, 0.0, 0.8, Color(0.55, 0.62, 0.8))    # 最远的一层雨幕：细、慢、淡
	flash_sky = screen_quad(-99, true)    # 闪电照亮天：远处的楼都成黑剪影
	flash_all = screen_quad(40, true)

	# 门洞里那条街：两排小楼往里收，中间留缝给昼光
	var b := tex("near_b")
	var c := tex("near_c")
	var a := tex("near_a")
	var dark := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	dark.fill(Color(0.07, 0.085, 0.14))
	var back := add(ImageTexture.create_from_image(dark), -260.0, 130.0, 1.0, 0.9, -87)    # 门洞里自成一层：盖住后排的楼，走动时它们不会滑进来挡光
	back.scale = Vector2(130.0, 125.0)
	add(a, -130.0, 280.0, 0.36, 0.93, -87, false, Color(0.5, 0.53, 0.62))
	add(tex("arch_b"), -400.0, 150.0, 0.62, 0.86, -86, false, Color(0.4, 0.42, 0.5))
	add(tex("arch_c"), 53.0, 150.0, 0.62, 0.86, -86, true, Color(0.4, 0.42, 0.5))
	var g := glow_tex()
	# 昼光在楼后面：两排小楼压成剪影，缝里越往深处越亮
	add_glow(g, 0.0, 440.0, 520.0, 620.0, 0.9, -87, C_LIGHT, 0.62)
	add_glow(g, 0.0, 570.0, 300.0, 300.0, 0.9, -87, C_LIGHT, 0.5)
	var shaft := add_glow(beam_tex(), 0.0, 340.0, 300.0, 520.0, 0.9, -87, C_LIGHT, 0.24)
	shaft.scale = Vector2(380.0 / 64.0, 520.0 / 64.0)
	shaft.rotation = -0.1
	add_glow(g, 0.0, 470.0, 420.0, 480.0, 0.9, -86, C_LIGHT, 0.12)

	# 中近景：门洞背后留空，其余按楼拆开放在不同深度
	var ny := top + 60.0 * PX
	var ns := PX * 0.9
	var mr := RandomNumberGenerator.new()
	mr.seed = 1112
	var tint2 := Color(0.72, 0.74, 0.82)
	# 中景两排换成专属楼（11-12 生成）：六栋各有身份，不再复制站立层的三栋
	house_info = JSON.parse_string(FileAccess.get_file_as_string(DIR + "mid_houses.json"))
	mid_put("mh_a3", -2300.0, ny - 60.0, ns, 0.52, -91, false, tint2, ROW2_HAZE, 0.75, 1.4, 0.55, 0.5, 1, 1, mr)
	mid_put("mh_b2", -1200.0, ny - 40.0, ns, 0.52, -91, false, tint2, ROW2_HAZE, 0.75, 1.4, 0.55, 0.5, 1, 1, mr)
	mid_put("mh_b1", 560.0, ny - 50.0, ns, 0.52, -91, true, tint2, ROW2_HAZE, 0.75, 1.4, 0.55, 0.5, 2, 1, mr)
	add_fog(-90, Color(0.2, 0.25, 0.36), 0.55, 0.018, 0.0, 0.95, 0.42, noise)
	add_curtain(-90, 0.6, 11.0, 0.3, 620.0, 70.0, 0.09, 0.0, 0.9, Color(0.58, 0.65, 0.82))    # 中间一层雨幕
	mid_put("mh_a1", -1950.0, ny, ns, 0.68, -89, false, Color.WHITE, ROW1_HAZE, 0.85, 0.9, 0.45, 0.7, 3, 1, mr)
	mid_put("mh_a2", -950.0, ny + 20.0, ns, 0.68, -89, false, Color.WHITE, ROW1_HAZE, 0.85, 0.9, 0.45, 0.7, 1, 0, mr)
	mid_put("mh_b3", 200.0, ny + 30.0, ns, 0.72, -89, false, Color.WHITE, ROW1_HAZE, 0.85, 0.9, 0.45, 0.7, 3, 1, mr)
	mid_put("mh_a3", 1150.0, ny + 10.0, ns, 0.72, -89, true, Color.WHITE, ROW1_HAZE, 0.85, 0.9, 0.45, 0.7, 2, 1, mr)
	for sp in smoke_src:
		smoke_node_for(sp.sp)
	for h in mid_sprites:
		var perch: Array = house_info.get(h.name, {}).get("perch", [])
		if perch.size() > 0:
			add_crows(h.sp, perch)
	# 后街的路灯：藏在中景楼脚，雾里一团暖光，从站立层的楼缝里看得到
	var lx := -2300.0
	while lx < 1900.0:
		add_glow(g, lx, 505.0, 320.0, 230.0, 0.7, -89, C_LAMP, 0.2)
		add_glow(g, lx, 455.0, 34.0, 34.0, 0.7, -89, C_LAMP, 0.75)
		lx += 760.0
	add_fog(-88, Color(0.16, 0.2, 0.3), 0.75, 0.024, 0.1, 1.0, 0.3, noise)

	# 站立层
	var st := tex("stand")
	var w := st.get_width() * PX
	add(st, x0 - anchor, top, PX, 1.0, -80)
	add(st, x0 - anchor - w, top, PX, 1.0, -80, true)    # 试验只有两屏宽的图：左右镜像接长
	add(st, x0 - anchor + w, top, PX, 1.0, -80, true)
	# 能动的柔光：盖在站立层上，火苗微闪
	var spd := [7.3, 9.1]
	for i in lamp_at.size():
		var l: Array = lamp_at[i]
		lamps.append({"node": add_glow(g, c0 + float(l[0]) - anchor, float(l[1]), float(l[3]), float(l[3]), 1.0, -78, C_LIGHT, float(l[2])), "a": float(l[2]), "sp": spd[i]})
	# 门洞的昼光泼到街面上
	add_glow(g, 0.0, 596.0, 760.0, 80.0, 1.0, -4, C_LIGHT, 0.62)
	add_glow(g, 0.0, 590.0, 280.0, 44.0, 1.0, -4, C_LIGHT, 0.55)
	# 门洞两侧的石柱被里面的光勾出来
	add_glow(g, -150.0, 360.0, 150.0, 480.0, 1.0, -78, C_LIGHT, 0.14)
	add_glow(g, 150.0, 360.0, 150.0, 480.0, 1.0, -78, C_LIGHT, 0.14)
	# 雨进了昼光就停：看不见的光罩，外面的雨到这里消失
	var dome := OccluderPolygon2D.new()
	dome.polygon = PackedVector2Array([Vector2(-190, 580), Vector2(-190, 300), Vector2(-120, 190), Vector2(0, 130), Vector2(120, 190), Vector2(190, 300), Vector2(190, 580)])
	var occ := LightOccluder2D.new()
	occ.occluder = dome
	occ.sdf_collision = true
	occ.occluder_light_mask = 0
	occ.position = Vector2(anchor, 0.0)
	bgw.add_child(occ)
	bd._rain_through.process_material.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	bd._rain_through.collision_base_size = 2.0

	# 昼光里停住的雨：每一滴是一小截斜着的雨线，下端一个亮点；被昼光照到才看得见，越靠光心越亮越暖
	var bi := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for yy in 32:
		for xx in 32:
			var d := Vector2(xx - 15.5, yy - 15.5).length() / 15.5
			bi.set_pixel(xx, yy, Color(1, 1, 1, clampf((1.0 - d) * 2.4, 0.0, 1.0)))
	bead_tex = ImageTexture.create_from_image(bi)
	var rng := RandomNumberGenerator.new()
	rng.seed = 511
	var cx := -182.0
	while cx < 182.0:
		var yy := dome_top(cx) + rng.randf_range(10.0, 60.0)
		while yy < 572.0:
			if rng.randf() < 0.35 + 0.65 * light_at(cx, yy):
				beads.append(new_bead(rng, cx - (yy - 370.0) * RAIN_TILT, yy, false, rng.randf_range(0.8, 1.5) if rng.randf() < 0.85 else rng.randf_range(1.8, 2.4)))
			yy += rng.randf_range(22.0, 58.0)
		cx += rng.randf_range(8.0, 18.0)
	# 门洞口往外：挂在主角前进的路上，碰到就重新落下
	var fx := -232.0
	while fx < 232.0:
		var fy := maxf(dome_top(fx), 150.0) + rng.randf_range(0.0, 50.0)
		while fy < 566.0:
			var e := 1.0 - clampf(Vector2(fx / 245.0, (fy - 470.0) / 300.0).length(), 0.0, 1.0)
			if rng.randf() < e * 1.3:
				beads.append(new_bead(rng, fx - (fy - 370.0) * RAIN_TILT, fy, true, rng.randf_range(1.1, 1.9) if rng.randf() < 0.8 else rng.randf_range(2.2, 3.0)))
			fy += rng.randf_range(30.0, 72.0)
		fx += rng.randf_range(13.0, 26.0)
	# 刚进光里的雨：从光罩上沿落进来，越落越慢，停住；停一会儿淡掉，再来一滴
	for i in 22:
		var nb := new_bead(rng, 0.0, 0.0, i % 3 == 0, rng.randf_range(1.0, 1.8))
		nb.mode = 1
		respawn_arrival(nb, rng.randf_range(0.0, 5.0))
		beads.append(nb)
	bead_back = Node2D.new()
	bead_back.z_as_relative = false
	bead_back.z_index = -85
	bead_back.draw.connect(draw_beads.bind(false))
	bgw.add_child(bead_back)
	bead_front = Node2D.new()
	bead_front.z_as_relative = false
	bead_front.z_index = -3
	bead_front.draw.connect(draw_beads.bind(true))
	bgw.add_child(bead_front)

	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	# 河面倒影：门洞和两盏灯在水里各一条被雨点打碎、微微晃动的光
	refl_src = [[anchor, 160.0 * bg_k, 1.0], [to_world(Vector2(c0 + float(lamp_at[0][0]), 0.0)).x, 50.0 * bg_k, 0.85], [to_world(Vector2(c0 + float(lamp_at[1][0]), 0.0)).x, 46.0 * bg_k, 0.75]]
	refl = Node2D.new()
	refl.z_as_relative = false
	refl.z_index = 7
	refl.material = add_mat
	refl.draw.connect(draw_reflections)
	stage.add_child(refl)
	# 灯下的雨：灯光范围里的雨丝被照亮；门洞外的雨落到光罩边上就没了
	lit_src = [[c0 + float(lamp_at[0][0]), float(lamp_at[0][1]), 170.0, 0.85, C_LAMP, false], [c0 + float(lamp_at[1][0]), float(lamp_at[1][1]), 150.0, 0.75, C_LAMP, false], [anchor, 330.0, 280.0, 0.8, C_LIGHT, true]]
	for si in lit_src.size():
		for i in 50:
			var q := {"s": si, "x": 0.0, "y": 0.0}
			respawn_streak(q, true)
			lit_rain.append(q)
	lit_node = Node2D.new()
	lit_node.z_as_relative = false
	lit_node.z_index = 19
	lit_node.material = add_mat
	lit_node.draw.connect(draw_lit_rain)
	bgw.add_child(lit_node)
	# 能站的台面：一道统一的冷白湿边，亮点沿边慢慢走，边上不时滴水（滴进昼光里的那几滴会停住）
	for k in [-1, 0, 1]:
		for L in LEDGES:
			var lx0: float = x0 + float(L[0]) * PX
			var lx1: float = x0 + float(L[1]) * PX
			if k != 0:
				lx0 = x0 + k * w + (1672.0 - float(L[1])) * PX
				lx1 = x0 + k * w + (1672.0 - float(L[0])) * PX
			ledges.append({"x0": lx0, "x1": lx1, "y": top + float(L[2]) * PX, "next": rng.randf_range(0.2, 1.5), "ph": rng.randf_range(0.0, 400.0)})
	ledge_node = Node2D.new()
	ledge_node.z_as_relative = false
	ledge_node.z_index = -79
	ledge_node.material = add_mat
	ledge_node.draw.connect(draw_ledges)
	bgw.add_child(ledge_node)
	drip_node = Node2D.new()
	drip_node.z_as_relative = false
	drip_node.z_index = -3
	drip_node.draw.connect(draw_drips)
	bgw.add_child(drip_node)

	# 前景：按深度拆开，虚焦，只从画面上方和河面露出来，不挡角色
	add(tex("fg_crane"), -420.0, -375.0, 1.15, 1.3, 22)
	chain = add(tex("fg_chain"), -420.0 + (1560.0 - 860.0) * 1.15, -220.0, 0.8, 1.3, 22)    # 钩子停在壁灯上方，走过去不挡灯
	chain.centered = false
	chain.offset = Vector2(-70.0, 0.0)
	# 河面上的前景栏杆虚得认不出，像一团黑渍，去掉
	# 月光光柱是旧天空的月亮带来的，这里没有月亮，留着就是右上角一道突兀的光
	stage.post.mat.set_shader_parameter("rays_amt", 0.0)
	# 角色身后一圈很淡的冷光，把人从暗背景里托出来
	halo = add_glow(g, 0.0, 0.0, 520.0, 620.0, 1.0, -2, Color(0.62, 0.72, 1.0), 0.13)
	items.pop_back()
	root.get_tree().process_frame.connect(tick)
	RenderingServer.frame_pre_draw.connect(light_override)    # 在游戏每帧设完角色光之后再改


## 昼光强度（相对 anchor 的坐标）：停住的雨靠它决定亮不亮
func light_at(x: float, y: float) -> float:
	return exp(-pow(x / 175.0, 2.0) - pow((y - 470.0) / 270.0, 2.0))


## 看不见的光罩上沿（和雨的遮挡多边形一致）
func dome_top(x: float) -> float:
	var ax := absf(x)
	if ax < 120.0:
		return 130.0 + ax / 120.0 * 60.0
	return 190.0 + (ax - 120.0) / 70.0 * 110.0


func new_bead(rng: RandomNumberGenerator, x: float, y: float, front: bool, r: float) -> Dictionary:
	return {"x": x, "y": y, "r": r, "front": front, "ph": rng.randf_range(0.0, TAU), "sp": rng.randf_range(0.35, 1.0), "state": 0, "dy": 0.0, "v": 0.0, "t": 0.0, "mode": 0}


func respawn_arrival(b: Dictionary, delay: float) -> void:
	var x := randf_range(-150.0, 150.0)
	var top := dome_top(x) + 8.0
	b.x0 = x
	b.y0 = top
	b.y1 = top + randf_range(60.0, 150.0)
	b.t = -delay
	b.hold = randf_range(3.0, 6.0)


func draw_beads(front: bool) -> void:
	var n: Node2D = bead_front if front else bead_back
	var shift := (camera_x() - anchor) * (0.0 if front else 0.1)
	for b in beads:
		if bool(b.front) != front:
			continue
		var r := float(b.r)
		var x := float(b.x)
		var y := float(b.y)
		var alpha := 1.0
		var tail := r * 5.0
		if int(b.mode) == 1:      # 正在慢下来的那几滴
			var t := float(b.t)
			if t < 0.0:
				continue
			var span := float(b.y1) - float(b.y0)
			var k := exp(-4.0 * t)
			y = float(b.y1) - span * k
			x = float(b.x0) - (y - float(b.y0)) * RAIN_TILT
			tail += span * 4.0 * k * 0.06
			alpha = clampf(t / 0.15, 0.0, 1.0) * (1.0 - clampf((t - float(b.hold)) / 0.8, 0.0, 1.0))
		else:
			var state := int(b.state)
			if state == 1:      # 被碰到，重新落下
				y += float(b.dy)
				tail = r * 12.0
			elif state == 2:    # 落地的小水圈
				var kk := float(b.t) / 0.28
				n.draw_set_transform(Vector2(anchor + x + shift, 574.0), 0.0, Vector2(1.0, 0.3))
				n.draw_arc(Vector2.ZERO, 3.0 + 13.0 * kk, 0.0, TAU, 20, Color(1.0, 0.98, 0.92, 0.6 * (1.0 - kk)), 1.5)
				continue
			elif state == 3:
				continue
			elif state == 4:    # 慢慢重新停回来
				alpha = float(b.t) / 0.7
		var lf := light_at(x, y)
		var glint := pow(maxf(0.0, sin(time * float(b.sp) + float(b.ph))), 12.0)
		var lum := (0.22 + 0.78 * lf) * (0.8 + 0.7 * glint) * alpha * (1.0 if front else 0.7)
		var col := Color(0.72, 0.82, 1.0).lerp(Color(1.0, 0.95, 0.84), lf)
		n.draw_set_transform(Vector2(anchor + x + shift, y), RAIN_TILT, Vector2.ONE)
		n.draw_texture_rect(bead_tex, Rect2(-r * 0.32, -tail, r * 0.64, tail), false, Color(col.r, col.g, col.b, lum * 0.45))
		n.draw_texture_rect(bead_tex, Rect2(-r, -r * 1.3, r * 2.0, r * 2.2), false, Color(col.r, col.g, col.b, minf(lum, 1.0)))
	n.draw_set_transform(Vector2.ZERO)


func update_beads(dt: float) -> void:
	var pl := to_local_bg(p.global_position)
	var px: float = pl.x - anchor
	var py: float = pl.y
	for b in beads:
		if int(b.mode) == 1:
			b.t = float(b.t) + dt
			if float(b.t) > float(b.hold) + 0.8:
				respawn_arrival(b, randf_range(0.2, 1.5))
			continue
		if not bool(b.front):
			continue
		match int(b.state):
			0:
				if absf(float(b.x) - px) < 46.0 and absf(float(b.y) - py) < 100.0:
					b.state = 1
					b.v = 30.0
			1:
				b.v = float(b.v) + 1900.0 * dt
				b.dy = float(b.dy) + float(b.v) * dt
				if float(b.y) + float(b.dy) >= 574.0:
					b.state = 2
					b.t = 0.0
			2, 3, 4:
				b.t = float(b.t) + dt
				if int(b.state) == 2 and float(b.t) > 0.28:
					b.state = 3
					b.t = 0.0
				elif int(b.state) == 3 and float(b.t) > 2.2:
					b.state = 4
					b.t = 0.0
					b.dy = 0.0
				elif int(b.state) == 4 and float(b.t) > 0.7:
					b.state = 0


func draw_reflections() -> void:
	for s in refl_src:
		var cxw: float = s[0]
		var w0: float = s[1]
		var a0: float = s[2]
		var y := 668.0
		while y < 840.0:
			var d := y - 668.0
			var n1 := 0.5 + 0.5 * sin(y * 0.21 + time * 3.1) * sin(y * 0.077 - time * 1.7 + cxw * 0.01)
			var wob := sin(y * 0.09 + time * 2.3 + cxw * 0.003) * (3.0 + d * 0.05)
			var ww := w0 * (0.55 + 0.6 * n1) * maxf(1.0 - d / 420.0, 0.2)
			var a := a0 * exp(-d / 85.0) * (0.35 + 0.65 * n1)
			# 软边的长椭圆光斑，上下互相叠一点，不留硬的横缝（之前 2px 硬条像百叶窗）
			var hh := 5.0 + 4.0 * n1
			refl.draw_texture_rect(bead_tex, Rect2(cxw - ww * 0.5 + wob, y - hh * 0.5, ww, hh), false, Color(C_LIGHT.r, C_LIGHT.g, C_LIGHT.b, a * 0.42))
			refl.draw_texture_rect(bead_tex, Rect2(cxw - ww * 0.2 + wob * 1.3, y - hh * 0.35, ww * 0.4, hh * 0.7), false, Color(C_LIGHT.r, C_LIGHT.g, C_LIGHT.b, a * 0.5))
			y += 4.0 + 3.0 * (1.0 - n1)


func respawn_streak(q: Dictionary, anywhere: bool) -> void:
	var s: Array = lit_src[int(q.s)]
	var rad: float = s[2]
	q.x = float(s[0]) + randf_range(-rad, rad)
	if anywhere:
		q.y = float(s[1]) + randf_range(-rad, rad * 0.4)
	else:
		q.y = float(s[1]) - rad * randf_range(0.9, 1.3)


func in_dome(x: float, y: float) -> bool:
	var rx := x - anchor
	return absf(rx) < 190.0 and y > dome_top(rx)


func update_lit_rain(dt: float) -> void:
	for q in lit_rain:
		q.y = float(q.y) + 1250.0 * dt
		q.x = float(q.x) - 1250.0 * dt * RAIN_TILT
		var s: Array = lit_src[int(q.s)]
		if float(q.y) > 580.0 or (bool(s[5]) and in_dome(float(q.x), float(q.y))) or float(q.y) > float(s[1]) + float(s[2]) * 1.6:
			respawn_streak(q, false)


func draw_lit_rain() -> void:
	for q in lit_rain:
		var s: Array = lit_src[int(q.s)]
		var rad: float = s[2]
		var dx := (float(q.x) - float(s[0])) / rad
		var dy := (float(q.y) - float(s[1]) - rad * 0.25) / (rad * 1.3)
		var a: float = float(s[3]) * exp(-(dx * dx + dy * dy) * 1.6)
		if a < 0.01:
			continue
		var c: Color = s[4]
		lit_node.draw_line(Vector2(float(q.x), float(q.y)), Vector2(float(q.x) + 24.0 * RAIN_TILT, float(q.y) - 24.0), Color(c.r, c.g, c.b, a), 1.6)


func draw_ledges() -> void:
	for L in ledges:
		var lx0: float = L.x0
		var lx1: float = L.x1
		var y: float = float(L.y) - 1.0
		ledge_node.draw_rect(Rect2(lx0, y, lx1 - lx0, 2.0), Color(0.62, 0.72, 0.9, 0.1))
		var span := lx1 - lx0
		var gx := lx0 + fposmod(time * 70.0 + float(L.ph), span + 300.0) - 150.0    # 一颗亮点沿着湿边慢慢走
		for i in 13:
			var o := (i - 6) * 9.0
			var xx := gx + o
			if xx < lx0 or xx > lx1:
				continue
			ledge_node.draw_rect(Rect2(xx, y, 9.0, 2.0), Color(0.75, 0.85, 1.0, 0.32 * exp(-pow(o / 30.0, 2.0))))


func update_drips(dt: float) -> void:
	for L in ledges:
		L.next = float(L.next) - dt
		if float(L.next) <= 0.0:
			L.next = randf_range(0.5, 1.8)
			drips.append({"x": randf_range(float(L.x0) + 8.0, float(L.x1) - 8.0), "y": float(L.y) + 4.0, "v": 0.0, "t": 0.0, "state": 0})
	for d in drips:
		match int(d.state):
			0:
				if in_dome(float(d.x), float(d.y)):      # 滴进昼光：慢下来停住
					d.v = float(d.v) * exp(-7.0 * dt)
					if float(d.v) < 8.0:
						d.state = 2
				else:
					d.v = float(d.v) + 1800.0 * dt
				d.y = float(d.y) + float(d.v) * dt
				if float(d.y) >= 578.0:
					d.y = 578.0
					d.state = 1
			1, 2:
				d.t = float(d.t) + dt
	drips = drips.filter(func(d): return not ((int(d.state) == 1 and float(d.t) > 0.3) or (int(d.state) == 2 and float(d.t) > 4.0)))


func draw_drips() -> void:
	for d in drips:
		var x: float = d.x
		var y: float = d.y
		if int(d.state) == 1:
			var k: float = float(d.t) / 0.3
			drip_node.draw_set_transform(Vector2(x, y), 0.0, Vector2(1.0, 0.3))
			drip_node.draw_arc(Vector2.ZERO, 2.0 + 9.0 * k, 0.0, TAU, 16, Color(0.8, 0.88, 1.0, 0.45 * (1.0 - k)), 1.2)
			drip_node.draw_set_transform(Vector2.ZERO)
			continue
		var a := 0.55 if int(d.state) == 0 else 0.55 * (1.0 - clampf((float(d.t) - 3.2) / 0.8, 0.0, 1.0))
		var ln := clampf(float(d.v) * 0.012, 3.0, 12.0)
		drip_node.draw_texture_rect(bead_tex, Rect2(x - 1.2, y - ln, 2.4, ln + 1.5), false, Color(0.82, 0.9, 1.0, a))


## 角色轮廓光：光线线的 char_light 本来就有月光边缘光，这里按明暗动态调（只在试验里，不改它的文件）
func light_override() -> void:
	if stage == null or p == null or stage.light_mat == null:
		return
	var m: ShaderMaterial = stage.light_mat
	var l: Vector3 = stage._lamp_at(p.global_position + Vector2(0.0, p.foot_offset - 60.0))
	var dx: float = anchor - to_local_bg(p.global_position).x
	var archf := clampf(1.0 - (absf(dx) - 40.0) / 260.0, 0.0, 1.0)
	var lit := clampf(l.x * 1.4 + archf, 0.0, 1.0)
	m.set_shader_parameter("moon_amt", lerpf(2.2, 0.5, lit))    # 光线线原值：暗处 0.85
	m.set_shader_parameter("exposure", lerpf(0.92, 1.04, lit))    # 光线线原值：暗处 0.8
	if archf > l.x:
		m.set_shader_parameter("warm", archf * 0.75)
		m.set_shader_parameter("warm_dir", Vector2(signf(dx), -0.25).normalized())
		m.set_shader_parameter("warm_col", Vector3(1.0, 0.93, 0.8))
	else:
		m.set_shader_parameter("warm_col", Vector3(1.0, 0.64, 0.32))


## 容器坐标 ↔ 世界坐标
func to_world(v: Vector2) -> Vector2:
	return Vector2(anchor, FLOOR) + (v - Vector2(anchor, FLOOR)) * bg_k


func to_local_bg(v: Vector2) -> Vector2:
	return Vector2(anchor, FLOOR) + (v - Vector2(anchor, FLOOR)) / bg_k


## 给一层背景套上远近处理（明暗阶梯、楼脚雾、月光边）
func depth(sp: Sprite2D, tint: Color, haze: float, contrast: float, blur: float, fog_amt: float, rim: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = DEPTH_SHADER
	m.shader = sh
	m.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	m.set_shader_parameter("haze", haze)
	m.set_shader_parameter("contrast", contrast)
	m.set_shader_parameter("blur_px", blur)
	m.set_shader_parameter("fog_amt", fog_amt)
	m.set_shader_parameter("rim_amt", rim)
	m.set_shader_parameter("rim_dir", Vector2(-0.35 if sp.flip_h else 0.35, -0.94))
	m.set_shader_parameter("win", [Vector4.ZERO, Vector4.ZERO, Vector4.ZERO, Vector4.ZERO, Vector4.ZERO, Vector4.ZERO, Vector4.ZERO, Vector4.ZERO])
	m.set_shader_parameter("win_on", PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0]))
	sp.material = m
	sp.modulate = Color.WHITE
	depth_mats.append(m)
	return m


## 中景的一栋楼：远近处理 + 几扇亮着的窗 + 烟囱冒烟
func mid_house(t: Texture2D, nm: String, x: float, y: float, s: float, f: float, z: int, flip: bool, tint: Color, haze: float, contrast: float, blur: float, fog_amt: float, rim: float, nwin: int, nsmoke: int, rng: RandomNumberGenerator) -> Sprite2D:
	var sp := add(t, x, y, s, f, z, flip)
	var m := depth(sp, tint, haze, contrast, blur, fog_amt, rim)
	var hi: Dictionary = house_info.get(nm, {})
	var pool: Array = (hi.wins if hi.has("wins") else WINS[nm]).duplicate()
	if hi.has("wins"):
		pool = pool.filter(func(r): return float(r[3]) - float(r[1]) < 300.0)
		m.set_shader_parameter("glass_lo", 0.035)
		m.set_shader_parameter("glass_hi", 0.07)
	var wins: Array = []
	var ons := PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0])
	for i in mini(nwin, 8):
		var r: Array = pool.pop_at(rng.randi_range(0, pool.size() - 1))
		wins.append(Vector4(r[0], r[1], r[2], r[3]))
		ons[i] = rng.randf_range(0.55, 1.0)
	while wins.size() < 8:
		wins.append(Vector4.ZERO)
	m.set_shader_parameter("win", wins)
	m.set_shader_parameter("win_on", ons)
	m.set_shader_parameter("win_gain", 0.55 + 0.45 * f)
	if nwin > 0:      # 每栋楼有一扇窗过一阵会慢慢亮起或熄灭
		win_anim.append({"mat": m, "ons": ons, "i": rng.randi_range(0, mini(nwin, 8) - 1), "base": 0.9, "on": true, "k": 1.0, "next": rng.randf_range(0.8, 3.0)})
	var chims: Array = (hi.chims if hi.has("chims") else CHIMNEYS[nm]).duplicate()
	for i in mini(nsmoke, chims.size()):
		var c: Array = chims.pop_at(rng.randi_range(0, chims.size() - 1))
		var cx: float = float(c[0])
		if flip:
			cx = t.get_width() - cx
		smoke_src.append({"sp": sp, "x": cx, "y": float(c[1]) - 6.0, "next": rng.randf_range(0.0, 0.5), "haze": haze})
	return sp


func update_mid(dt: float) -> void:
	for w in win_anim:
		w.next = float(w.next) - dt
		if float(w.next) <= 0.0:
			w.on = not bool(w.on)
			w.next = randf_range(5.0, 12.0)
		w.k = move_toward(float(w.k), 1.0 if bool(w.on) else 0.0, dt / 1.4)
		var ons: PackedFloat32Array = w.ons
		ons[int(w.i)] = float(w.base) * smoothstep(0.0, 1.0, float(w.k))
		w.mat.set_shader_parameter("win_on", ons)
	# 烟：一团团从烟囱口冒出来，往上、顺着风往左飘，越飘越大越淡
	for s in smoke_src:
		s.next = float(s.next) - dt
		if float(s.next) <= 0.0:
			s.next = randf_range(0.35, 0.6)
			puffs.append({"sp": s.sp, "x": float(s.x) + randf_range(-2.0, 2.0), "y": float(s.y), "age": 0.0, "life": randf_range(4.0, 5.5), "vx": randf_range(-20.0, -12.0), "vy": randf_range(-26.0, -18.0), "haze": s.haze})
	for q in puffs:
		q.age = float(q.age) + dt
		q.x = float(q.x) + float(q.vx) * dt
		q.y = float(q.y) + float(q.vy) * dt
		q.vx = float(q.vx) - 4.0 * dt
	puffs = puffs.filter(func(q): return float(q.age) < float(q.life))
	for n in smoke_nodes.values():
		n.queue_redraw()
	# 乌鸦：主角走近就飞走，过一阵再落回来
	for cw in crows:
		var gp: Vector2 = (cw.sp as Sprite2D).get_global_transform() * Vector2(float(cw.x), float(cw.y))
		match int(cw.state):
			0:
				cw.peck = float(cw.peck) + dt
				if absf(gp.x - p.global_position.x) < 230.0:
					cw.state = 1
					cw.t = 0.0
					cw.vx = randf_range(50.0, 110.0) * (1.0 if randf() < 0.7 else -1.0)
					cw.vy = randf_range(-60.0, -30.0)
					cw.delay = randf_range(0.0, 0.35)
			1:
				cw.t = float(cw.t) + dt
				if float(cw.t) > float(cw.delay):
					cw.vy = float(cw.vy) - 90.0 * dt
					cw.dx = float(cw.dx) + float(cw.vx) * dt
					cw.dy = float(cw.dy) + float(cw.vy) * dt
				if float(cw.t) > 4.0:
					cw.state = 2
					cw.t = 0.0
			2:
				cw.t = float(cw.t) + dt
				if float(cw.t) > 9.0 and absf(gp.x - p.global_position.x) > 400.0:
					cw.state = 0
					cw.dx = 0.0
					cw.dy = 0.0
					cw.fade = 0.0
		cw.fade = minf(float(cw.fade) + dt / 0.8, 1.0)
	for n in crow_nodes.values():
		n.queue_redraw()
	# 闪电：隔一阵打一次，两下闪，照亮天和远处的轮廓
	bolt_t -= dt
	if bolt_t <= 0.0:
		bolt_t = randf_range(14.0, 24.0)
		bolt_age = 0.0
	bolt_age += dt
	var fl := 0.0
	if bolt_age < 0.07:
		fl = 1.0
	elif bolt_age < 0.16:
		fl = 0.12
	elif bolt_age < 0.24:
		fl = 0.8
	elif bolt_age < 1.2:
		fl = 0.8 * exp(-(bolt_age - 0.24) * 5.0)
	flash_sky.modulate = Color(0.5, 0.58, 0.85, fl * 0.55)
	flash_all.modulate = Color(0.55, 0.6, 0.78, fl * 0.07)
	for m in depth_mats:
		m.set_shader_parameter("flash", fl)
	for c in curtains:
		c.set_shader_parameter("flash", fl)


func mid_put(nm: String, x: float, y: float, s: float, f: float, z: int, flip: bool, tint: Color, haze: float, contrast: float, blur: float, fog_amt: float, rim: float, nwin: int, nsmoke: int, rng: RandomNumberGenerator) -> void:
	var sp := mid_house(tex(nm), nm, x, y, s, f, z, flip, tint, haze, contrast, blur, fog_amt, rim, nwin, nsmoke, rng)
	mid_sprites.append({"name": nm, "sp": sp})


func smoke_node_for(sp: Sprite2D) -> Node2D:
	if not smoke_nodes.has(sp):
		var n := Node2D.new()
		n.draw.connect(draw_smoke.bind(sp))
		sp.add_child(n)
		smoke_nodes[sp] = n
	return smoke_nodes[sp]


func draw_smoke(sp: Sprite2D) -> void:
	var n: Node2D = smoke_nodes[sp]
	for q in puffs:
		if q.sp != sp:
			continue
		var a := float(q.age) / float(q.life)
		var r := lerpf(7.0, 36.0, sqrt(a))
		var al := 0.42 * smoothstep(0.0, 0.12, a) * (1.0 - a) * (1.0 - 0.3 * float(q.haze))
		n.draw_texture_rect(bead_tex, Rect2(float(q.x) - r, float(q.y) - r * 0.8, r * 2.0, r * 1.6), false, Color(0.42, 0.47, 0.58, al))


## 一群乌鸦站在某栋中景楼的屋脊 / 烟囱上（成图像素）
func add_crows(sp: Sprite2D, pts: Array) -> void:
	if not crow_nodes.has(sp):
		var n := Node2D.new()
		n.draw.connect(draw_crows.bind(sp))
		sp.add_child(n)
		crow_nodes[sp] = n
	for pt in pts:
		var cx: float = float(pt[0])
		if sp.flip_h:
			cx = sp.texture.get_width() - cx
		crows.append({"sp": sp, "x": cx, "y": float(pt[1]), "face": -1.0 if randf() < 0.5 else 1.0, "state": 0, "t": 0.0, "dx": 0.0, "dy": 0.0, "vx": 0.0, "vy": 0.0, "delay": 0.0, "peck": randf_range(0.0, 6.0), "fade": 1.0})


func draw_crows(sp: Sprite2D) -> void:
	var n: Node2D = crow_nodes[sp]
	var col := Color(0.05, 0.055, 0.075)
	for cw in crows:
		if cw.sp != sp or int(cw.state) == 2:
			continue
		var al := float(cw.fade)
		var c := Color(col.r, col.g, col.b, al)
		n.draw_set_transform(Vector2(float(cw.x) + float(cw.dx), float(cw.y) + float(cw.dy)), 0.0, Vector2(1.9, 1.9))    # 中景太远，按真实比例只有几像素，放大到认得出
		var o := Vector2.ZERO
		if int(cw.state) == 1 and float(cw.t) > float(cw.delay):
			var fx := signf(float(cw.vx))
			var flap := sin(float(cw.t) * 22.0)
			n.draw_colored_polygon(PackedVector2Array([o + Vector2(-7 * fx, 0), o + Vector2(0, -2), o + Vector2(8 * fx, -1), o + Vector2(0, 2)]), c)
			n.draw_colored_polygon(PackedVector2Array([o + Vector2(-2 * fx, -1), o + Vector2(3 * fx, -1), o + Vector2(-1 * fx, -1 - 11 * flap)]), c)
			n.draw_colored_polygon(PackedVector2Array([o + Vector2(-1 * fx, 0), o + Vector2(4 * fx, 0), o + Vector2(1 * fx, 7 * flap)]), Color(c.r, c.g, c.b, al * 0.8))
		else:
			var fc := float(cw.face)
			var bob := 1.5 if fmod(float(cw.peck), 5.0) < 0.35 else 0.0     # 偶尔低头啄一下
			n.draw_colored_polygon(PackedVector2Array([o + Vector2(-6 * fc, -1), o + Vector2(-2 * fc, -7), o + Vector2(4 * fc, -7), o + Vector2(5 * fc, -2), o + Vector2(0, 0)]), c)
			n.draw_circle(o + Vector2(5 * fc, -9 + bob), 2.6, c)
			n.draw_colored_polygon(PackedVector2Array([o + Vector2(7 * fc, -10 + bob), o + Vector2(11 * fc, -8.5 + bob), o + Vector2(7 * fc, -8 + bob)]), c)
			n.draw_colored_polygon(PackedVector2Array([o + Vector2(-5 * fc, -2), o + Vector2(-11 * fc, 1), o + Vector2(-9 * fc, 2), o + Vector2(-3 * fc, -1)]), c)
	n.draw_set_transform(Vector2.ZERO)


func add_curtain(z: int, k: float, cell: float, density: float, speed: float, seg: float, alpha: float, y0: float, y1: float, c: Color) -> void:
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = CURTAIN_SHADER
	m.shader = sh
	m.set_shader_parameter("k", k)
	m.set_shader_parameter("cell", cell)
	m.set_shader_parameter("density", density)
	m.set_shader_parameter("speed", speed)
	m.set_shader_parameter("seg", seg)
	m.set_shader_parameter("period", seg * 6.0)
	m.set_shader_parameter("alpha", alpha)
	m.set_shader_parameter("y0", y0)
	m.set_shader_parameter("y1", y1)
	m.set_shader_parameter("col", c)
	m.set_shader_parameter("tilt", RAIN_TILT)
	var sp := Sprite2D.new()
	var w := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	w.fill(Color.WHITE)
	sp.texture = ImageTexture.create_from_image(w)
	sp.scale = Vector2(600, 360)
	sp.material = m
	sp.z_as_relative = false
	sp.z_index = z
	stage.add_child(sp)
	fogs.append({"node": sp, "mat": m})
	curtains.append(m)


func screen_quad(z: int, add_blend: bool) -> Sprite2D:
	var sp := Sprite2D.new()
	var w := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	w.fill(Color.WHITE)
	sp.texture = ImageTexture.create_from_image(w)
	sp.scale = Vector2(600, 360)
	sp.z_as_relative = false
	sp.z_index = z
	if add_blend:
		var am := CanvasItemMaterial.new()
		am.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		sp.material = am
	sp.modulate = Color(1, 1, 1, 0)
	stage.add_child(sp)
	fogs.append({"node": sp, "mat": null})
	return sp


func camera_x() -> float:
	return to_local_bg(stage.camera.get_screen_center_position()).x


func tick() -> void:
	time += 1.0 / 60.0
	var cam: Vector2 = stage.camera.get_screen_center_position()
	var cl := to_local_bg(cam)
	var cy0 := FLOOR + (CAM_Y - FLOOR) / bg_k
	for it in items:
		it.node.position = Vector2(float(it.x) + (cl.x - anchor) * (1.0 - float(it.f)), float(it.y) + (cl.y - cy0) * (1.0 - float(it.f)))
	for f in fogs:
		f.node.global_position = cam
		if f.mat != null:
			f.mat.set_shader_parameter("cam_x", cam.x)
			f.mat.set_shader_parameter("t", time)
	for l in lamps:
		var fl := 1.0 + 0.1 * sin(time * float(l.sp)) + 0.06 * sin(time * float(l.sp) * 2.7 + 1.0)
		l.node.material.set_shader_parameter("gain", float(l.a) * fl)
	halo.global_position = p.global_position + Vector2(0.0, -10.0)
	halo.material.set_shader_parameter("gain", lerpf(0.13, 0.04, 1.0 - clampf((absf(p.global_position.x - anchor) - 180.0) / 200.0, 0.0, 1.0)))
	update_beads(1.0 / 60.0)
	update_lit_rain(1.0 / 60.0)
	update_drips(1.0 / 60.0)
	update_mid(1.0 / 60.0)
	refl.queue_redraw()
	lit_node.queue_redraw()
	ledge_node.queue_redraw()
	drip_node.queue_redraw()
	chain.rotation = sin(time * 0.9) * 0.03 + sin(time * 2.3) * 0.006
	bead_back.queue_redraw()
	bead_front.queue_redraw()
	stage.camera.arena_max = Vector2(c0 + 6000.0, stage.camera.arena_max.y)
	stage.encounter.running = false
	# 游戏 11-11 起自带门洞昼光、悬停雨、近雾、台面湿光和暗处冷雾（按游戏布局的坐标画）：试验场景用自己的，这里关掉，免得叠两份
	var bd = stage.backdrop
	bd.daylight_enabled = false
	for nm in ["_arch_pool", "_bead_back", "_bead_front", "_fog_near", "_ledge_wet", "_soft_glow"]:
		var nd = bd.get(nm)
		if nd != null:
			nd.visible = false
	stage.encounter.clear_shades()


func run() -> void:
	stage = load("res://scenes/rain_street.tscn").instantiate()
	root.add_child(stage)
	var panku = root.get_node_or_null("Panku")    # 调试控制台会把日志印在画面上，录像时藏起来
	if panku != null:
		panku.visible = false
	await process_frame
	p = stage.player
	stage.trigger_before = -1.0e9    # 不触发封印
	await frames(5)
	await build()
	stage.camera.arena_max = Vector2(c0 + 6000.0, stage.camera.arena_max.y)
	var still := OS.get_environment("STILL_DIR")
	if still != "":
		DirAccess.make_dir_recursive_absolute(still)
		for spot in [1700.0, 2300.0, anchor - c0, 3300.0]:
			p.reset_state(Vector2(c0 + spot, stage.floor_y - p.foot_offset))
			stage.camera.global_position.x = c0 + spot
			stage.camera.reset_smoothing()
			await frames(45)
			await process_frame
			root.get_viewport().get_texture().get_image().save_png(still + "/x%d.png" % int(spot))
			print("SHOT %d player=(%.0f,%.0f) c0=%.0f cam=%s zoom=%s" % [spot, p.global_position.x - c0, p.global_position.y, c0, stage.camera.get_screen_center_position(), stage.camera.zoom])
		quit()
		return
	p.reset_state(Vector2(c0 + WALK_FROM, stage.floor_y - p.foot_offset))
	stage.camera.global_position.x = c0 + WALK_FROM
	stage.camera.reset_smoothing()
	await frames(50)
	var go := fr([&"move_right"], Vector2(1, 0))
	var n := 0
	while p.global_position.x < c0 + WALK_TO and n < 900:
		await frames(1, go)
		n += 1
	await frames(60)
	print("WALK frames=%d end_x=%.0f beads_front=%d released=%d" % [n, p.global_position.x - c0, beads.filter(func(b): return bool(b.front)).size(), beads.filter(func(b): return bool(b.front) and int(b.state) != 0).size()])
	quit()
