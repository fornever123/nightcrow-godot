extends Node2D
## 第一章【司辰母钟楼 · 5:59 暗朱红磨砂母钟】7 层高精度拆件 + 5 重 Forward+ 光学动效总成
##
## 严格遵循《剧情与主题规划.md》与《第一章_影街_定稿方案》世界观与色彩铁律：
## - 全城被白光驱逐出的十倍流动时间灌入百米机械总枢【司辰母钟楼】，超载发条崩死在 5:59；
## - 唯独母钟亮起全章专属的【暗朱红磨砂透光大表盘】（环境 0% 紫，纯紫仅归主角刀光）；
## - 7 层真材质贴图 + 法线受光 + Voronoi 真晶体碎裂光学着色器：
##   1. 常态【5:59 炉心心跳与擒纵死卡回弹】（1.68s 周期蓄压前顶 -> 42Hz 金属震颤 -> 崩弹回 5:59 + XII 针尖铁花飞溅 + 全屏暗红折射波）
##   2. 光影【60° 暗朱红×冷银琴弦体积光栅】（随内部齿轮与分针实时切割明暗流动的体积斜光柱）
##   3. 高潮 A【时间倒流 · 炽红狂转与水痕/铁花逆流】（表盘炽红过载 + 分针宽幅扇形残影逆旋 + 玻璃水痕与火花倒吸）
##   4. 高潮 B【钟窗真多边形晶体崩裂悬停 & 倒流螺旋重拼】（Voronoi 多边形晶格裂纹 -> 洞开幽暗齿轮钟腔 + 24 块厚红玻璃残片悬停 -> 倒流瞬间重拼）
##   5. 终局【一剑贯通 6:00】（冲破 5:59 死线叩响 XII，裂口弥合、暗朱红超载散作冷银微尘）

signal jam_shockwave_fired(world_origin: Vector2, strength: float, crimson_boost: float)

enum ClockState {
	JAMMED_559 = 0,
	REWIND_OVERDRIVE = 1,
	SHATTERED_ORBIT = 2,
	CLEAVED_600 = 3,
}

const ASSET_DIR := "res://assets/image/boss_duanchao/crimson_clock/"
const META_PATH := ASSET_DIR + "clock_rig_meta.json"

const ANGLE_12_OCLOCK := -PI * 0.5
const HOUR_ANGLE_559 := ANGLE_12_OCLOCK + TAU * (359.0 / 720.0)
const MINUTE_ANGLE_559 := ANGLE_12_OCLOCK + TAU * (59.0 / 60.0)
const HOUR_ANGLE_600 := ANGLE_12_OCLOCK + TAU * (360.0 / 720.0)
const MINUTE_ANGLE_600 := ANGLE_12_OCLOCK + TAU

## 精心校准直径 1320u (R=660u)：顶部 XII 刻度与 5:59 针尖铁花 100% 落入镜头上三分之一黄金焦点，中心轴座悬于主角头顶正上方互不遮挡！
const DIAL_WORLD_DIAMETER := 1320.0
const HEARTBEAT_PERIOD := 1.68

## 深邃幽暗钟腔 + 局部赤红超载炉火背光（让崩裂洞口露出深邃机械腔体与青铜齿轮剪影，绝不糊成一片平涂亮橙！）
const FURNACE_CORE_SHADER := """
shader_type canvas_item;
render_mode blend_mix;

uniform float pulse : hint_range(0.0, 2.0) = 0.0;
uniform float rewind_amt : hint_range(0.0, 1.0) = 0.0;
uniform float shatter_amt : hint_range(0.0, 1.0) = 0.0;
uniform float dawn_calm : hint_range(0.0, 1.0) = 0.0;
uniform float flow_time = 0.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x),
		f.y
	);
}

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		v += amp * vnoise(p);
		p = p * 2.04 + vec2(1.7, -1.3);
		amp *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = (UV - vec2(0.5)) * 2.0;
	float r = length(uv);
	if (r > 0.94) {
		COLOR = vec4(0.0);
	} else {
		float ang = atan(uv.y, uv.x);
		float swirl = ang + flow_time * (0.28 - 2.4 * rewind_amt) + r * 2.1;
		vec2 np = vec2(cos(swirl), sin(swirl)) * (r * 3.0) + vec2(0.0, -flow_time * 0.55);
		float turb = fbm(np * 2.1) * 0.65 + fbm(np * 4.2 - flow_time * 0.35) * 0.35;

		// 钟腔深底为极暗煤黑青铁色，唯有外环刻度背光槽与炉心裂隙涌动浓郁暗朱红火焰
		vec3 cavity_dark = vec3(0.032, 0.022, 0.028);
		vec3 crimson_glow = vec3(0.76, 0.095, 0.068);
		vec3 hot_vein = vec3(1.0, 0.34, 0.16);

		float outer_furnace = smoothstep(0.50, 0.66, r) * (1.0 - smoothstep(0.84, 0.93, r));
		float core_ember = exp(-r * 3.1) * (0.55 + 0.55 * pulse + 0.65 * rewind_amt + 0.45 * shatter_amt);
		float vein_mask = pow(clamp(turb * 1.25, 0.0, 1.0), 2.2) * (0.45 + 0.55 * outer_furnace + core_ember);

		vec3 col = mix(cavity_dark, crimson_glow, clamp(vein_mask * (0.85 + 0.45 * pulse + 0.55 * rewind_amt), 0.0, 1.0));
		col += hot_vein * pow(clamp(turb, 0.0, 1.0), 3.4) * (0.22 * pulse + 0.45 * rewind_amt + 0.28 * shatter_amt);

		if (dawn_calm > 0.001) {
			col = mix(col, vec3(0.08, 0.11, 0.16), dawn_calm * 0.90);
		}
		float edge_fade = 1.0 - smoothstep(0.88, 0.94, r);
		COLOR = vec4(col, 0.96 * edge_fade);
	}
}
"""

## 磨砂暗朱红+冷银背光厚玻璃着色器（采用真 Voronoi 多边形玻璃晶格破裂算法，彻底根除方格伪影！）
const FROSTED_GLASS_SHADER := """
shader_type canvas_item;
render_mode blend_mix;

uniform float pulse : hint_range(0.0, 2.0) = 0.0;
uniform float rewind_amt : hint_range(0.0, 1.0) = 0.0;
uniform float crack_amt : hint_range(0.0, 1.0) = 0.0;
uniform float shatter_hole : hint_range(0.0, 1.0) = 0.0;
uniform float dawn_calm : hint_range(0.0, 1.0) = 0.0;
uniform float rain_phase = 0.0;

float h1(float n) { return fract(sin(n * 91.3458) * 47453.5453); }
vec2 hash22(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

// 返回 vec3(最近晶胞随机ID, 到多边形晶界裂纹的精确欧氏距离, 次近距离)
vec3 voronoi_shards(vec2 x) {
	vec2 n = floor(x);
	vec2 f = fract(x);
	vec2 mg, mr;
	float md = 8.0;
	float cell_id = 0.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 o = hash22(n + g);
			vec2 r = g + o - f;
			float d = dot(r, r);
			if (d < md) {
				md = d;
				mr = r;
				mg = g;
				cell_id = fract((o.x * 13.7 + o.y * 29.3));
			}
		}
	}
	md = 8.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = mg + vec2(float(i), float(j));
			vec2 o = hash22(n + g);
			vec2 r = g + o - f;
			if (dot(mr - r, mr - r) > 0.00001) {
				md = min(md, dot(0.5 * (mr + r), normalize(r - mr)));
			}
		}
	}
	return vec3(cell_id, md, 0.0);
}

void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	float r = length(p);
	vec4 base = texture(TEXTURE, UV);
	if (base.a <= 0.005 || r > 0.96) {
		COLOR = vec4(0.0);
	} else {
		// 1. 钟盘表面真实流淌雨痕与凝结水珠折射（时间倒流时 rain_phase 反向递增，水珠倒流向上爬！）
		float col_idx = floor(UV.x * 62.0);
		float col_rnd = h1(col_idx);
		float streak_x = abs(fract(UV.x * 62.0) - 0.5);
		float y_scroll = UV.y * 5.2 - rain_phase * (0.65 + 0.55 * col_rnd) + col_rnd * 6.0;
		float drop_cell = fract(y_scroll);
		float drop_head = smoothstep(0.76, 0.96, drop_cell) * (1.0 - smoothstep(0.96, 1.0, drop_cell));
		float drop_tail = smoothstep(0.18, 0.92, drop_cell) * 0.42;
		float rivulet = (drop_head * 1.35 + drop_tail) * (1.0 - smoothstep(0.06, 0.32, streak_x)) * step(0.34, col_rnd);

		vec2 refract_uv = UV + vec2((streak_x - 0.25) * 0.007, -rivulet * 0.011);
		vec4 refr = texture(TEXTURE, clamp(refract_uv, vec2(0.002), vec2(0.998)));
		vec3 col = mix(base.rgb, refr.rgb * 1.22 + vec3(0.12, 0.03, 0.03) * rivulet, clamp(rivulet, 0.0, 0.82));

		// 2. 外圈暗血珀朱红磨砂背光心跳增亮（平时深邃凝重，顶死心跳与倒流时撕开冷雾爆出炉火；0% 紫色）
		float is_crimson_ring = smoothstep(0.53, 0.62, r) * (1.0 - smoothstep(0.85, 0.92, r));
		float boost = pulse * 0.28 + rewind_amt * 0.50;
		col += vec3(0.38, 0.048, 0.032) * is_crimson_ring * boost;
		col += vec3(0.11, 0.026, 0.020) * (1.0 - is_crimson_ring) * (pulse * 0.12 + rewind_amt * 0.25);

		float alpha = base.a;

		// 3. 真 Voronoi 多边形锋利玻璃晶格裂纹与破洞（100% 直线折角玻璃切面，零方块！）
		if (crack_amt > 0.001 || shatter_hole > 0.001) {
			vec3 vor = voronoi_shards(p * 3.85 + vec2(0.35, -0.22));
			float shard_id = vor.x;
			float edge_d = vor.y;

			// 锋利发光玻璃裂纹网
			float crack_line = (1.0 - smoothstep(0.004, 0.028, edge_d)) * smoothstep(0.13, 0.22, r) * (1.0 - smoothstep(0.80, 0.86, r));
			col += vec3(1.15, 0.22, 0.11) * crack_line * crack_amt * (0.85 + 0.35 * pulse);

			if (shatter_hole > 0.001) {
				float valid_ring = step(0.16, r) * step(r, 0.81);
				// 约 42% 的多边形玻璃晶格整块震飞脱落，露出后方旋转的暗青铜巨轮与擒纵机构！
				float threshold = shatter_hole * 0.48;
				if (valid_ring > 0.5 && shard_id < threshold) {
					alpha = 0.0;
				} else if (valid_ring > 0.5 && edge_d < 0.042 && shard_id < threshold + 0.18) {
					// 残留玻璃断口边缘折射炽热暗红厚玻璃切面高光
					float bevel = 1.0 - smoothstep(0.0, 0.042, edge_d);
					col = mix(col, vec3(1.18, 0.25, 0.14), bevel * 0.82);
					alpha = max(alpha, bevel * 0.95);
				}
			}
		}

		if (dawn_calm > 0.001) {
			float lum = dot(col, vec3(0.299, 0.587, 0.114));
			col = mix(col, vec3(lum) * vec3(0.76, 0.84, 0.96), dawn_calm * 0.82);
		}

		COLOR = vec4(col, alpha);
	}
}
"""

const REWIND_FAN_SHADER := """
shader_type canvas_item;
render_mode blend_add;

uniform float head_angle = -1.5708;
uniform float sweep_span : hint_range(0.0, 3.14159) = 0.0;
uniform float intensity : hint_range(0.0, 2.5) = 0.0;
uniform float inner_r : hint_range(0.0, 0.5) = 0.10;
uniform float outer_r : hint_range(0.2, 1.0) = 0.82;

void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	float r = length(p);
	if (intensity <= 0.001 || sweep_span <= 0.005 || r < inner_r || r > outer_r) {
		COLOR = vec4(0.0);
	} else {
		float a = atan(p.y, p.x);
		float diff = mod(a - head_angle + TAU * 2.0, TAU);
		if (diff > sweep_span) {
			COLOR = vec4(0.0);
		} else {
			float trail = 1.0 - (diff / max(sweep_span, 0.001));
			trail = pow(clamp(trail, 0.0, 1.0), 1.45);
			float radial = smoothstep(inner_r, inner_r + 0.08, r) * (1.0 - smoothstep(outer_r - 0.10, outer_r, r));
			// 残影弧内部带细密刻度流光丝，视觉速度感拉满
			float arc_stripes = 0.72 + 0.28 * sin(r * 68.0 - diff * 12.0);
			float tip_hot = smoothstep(outer_r * 0.48, outer_r * 0.92, r);
			vec3 col = mix(vec3(0.88, 0.13, 0.09), vec3(1.0, 0.56, 0.28), tip_hot * trail);
			COLOR = vec4(col * trail * radial * arc_stripes * intensity, 1.0);
		}
	}
}
"""

var state: int = ClockState.JAMMED_559
var time_sec: float = 0.0
var rain_phase: float = 0.0

var hour_angle: float = HOUR_ANGLE_559
var minute_angle: float = MINUTE_ANGLE_559
var pulse_val: float = 0.0
var rewind_amt: float = 0.0
var crack_amt: float = 0.0
var shatter_amt: float = 0.0
var dawn_calm: float = 0.0
var gear_phase: float = 0.0

var _heartbeat_clock: float = 0.0
var _last_snap_cycle: int = -1
var _jam_strain: float = 0.0
var _jam_tremor: float = 0.0
var _fan_span: float = 0.0
var _fan_intensity: float = 0.0

var _meta: Dictionary = {}
var _furnace_quad: ColorRect
var _furnace_mat: ShaderMaterial
var _gear_back_layer: Node2D
var _gear_sprites: Array[Sprite2D] = []
var _gear_base_speeds: Array[float] = [0.18, -0.32, 0.56]
var _pallet_fork_spr: Sprite2D = null

var _glass_sprite: Sprite2D
var _glass_mat: ShaderMaterial
var _frame_sprite: Sprite2D
var _fan_quad: ColorRect
var _fan_mat: ShaderMaterial

var _hour_pivot: Node2D
var _hour_sprite: Sprite2D
var _minute_pivot: Node2D
var _minute_sprite: Sprite2D
var _hub_cap: Sprite2D

var _shards_layer: Node2D
var _shards: Array[Dictionary] = []
var _sparks_layer: Node2D
var _sparks: Array[Dictionary] = []
var _spark_tex: Texture2D
var _furnace_light: PointLight2D
var _cue_pulse: float = 0.0
var _cue_twitch: float = 0.0
var _using_v4_dial: bool = false
var overlay_only_mode: bool = false


func set_overlay_only_mode(on: bool) -> void:
	overlay_only_mode = on
	if _furnace_quad != null:
		_furnace_quad.visible = not on
	if _gear_back_layer != null:
		_gear_back_layer.visible = not on
	if _glass_sprite != null:
		_glass_sprite.visible = not on
	if _frame_sprite != null:
		_frame_sprite.visible = not on
	if _shards_layer != null:
		_shards_layer.modulate.a = 0.0 if on else 1.0
	if _furnace_light != null:
		_furnace_light.energy = 0.22 if on else 0.52


func _load_tex(path: String) -> Texture2D:
	var gpath := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(gpath):
		var img := Image.load_from_file(gpath)
		if img != null and not img.is_empty():
			return ImageTexture.create_from_image(img)
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


func _make_canvas_tex(diff_path: String, norm_path: String, spec_shine: float = 0.48) -> Texture2D:
	var d := _load_tex(diff_path)
	if d == null:
		return null
	var n := _load_tex(norm_path)
	if n == null:
		return d
	var ct := CanvasTexture.new()
	ct.diffuse_texture = d
	ct.normal_texture = n
	ct.specular_color = Color(0.92, 0.46, 0.38)
	ct.specular_shininess = spec_shine
	return ct


func _make_radial_tex(sz: int = 128, power: float = 2.2) -> ImageTexture:
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var c := float(sz - 1) * 0.5
	for y in sz:
		for x in sz:
			var r := Vector2(float(x) - c, float(y) - c).length() / c
			var v := pow(clampf(1.0 - r, 0.0, 1.0), power)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, v))
	return ImageTexture.create_from_image(img)


func _ready() -> void:
	if FileAccess.file_exists(META_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(META_PATH))
		if parsed is Dictionary:
			_meta = parsed

	_spark_tex = _make_radial_tex(48, 2.4)
	var R := DIAL_WORLD_DIAMETER * 0.5

	# 1. 最底层：深邃暗铁钟腔与超载暗朱红炉火纹理
	_furnace_quad = ColorRect.new()
	_furnace_quad.name = "CrimsonFurnaceCore"
	_furnace_quad.position = Vector2(-R, -R)
	_furnace_quad.size = Vector2(DIAL_WORLD_DIAMETER, DIAL_WORLD_DIAMETER)
	_furnace_quad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var f_sh := Shader.new()
	f_sh.code = FURNACE_CORE_SHADER
	_furnace_mat = ShaderMaterial.new()
	_furnace_mat.shader = f_sh
	_furnace_quad.material = _furnace_mat
	add_child(_furnace_quad)

	# 2. 第二层：磨砂玻璃后方三组万吨暗青铜发条巨轮、擒纵轮与咬合摆动的擒纵叉！
	_gear_back_layer = Node2D.new()
	_gear_back_layer.name = "SubGlassBronzeGears"
	add_child(_gear_back_layer)
	var gear_cfgs := [
		{"tex": "gear_main.png", "norm": "gear_main_n.png", "pos": Vector2(-R * 0.18, R * 0.08), "diam": R * 1.16, "mod": Color(0.56, 0.34, 0.28, 0.92)},
		{"tex": "gear_escape.png", "norm": "gear_escape_n.png", "pos": Vector2(R * 0.22, -R * 0.26), "diam": R * 0.80, "mod": Color(0.52, 0.32, 0.30, 0.94)},
		{"tex": "gear_main.png", "norm": "gear_main_n.png", "pos": Vector2(-R * 0.32, -R * 0.28), "diam": R * 0.66, "mod": Color(0.42, 0.25, 0.22, 0.86)},
	]
	for cfg in gear_cfgs:
		var gt := _make_canvas_tex(ASSET_DIR + String(cfg.tex), ASSET_DIR + String(cfg.norm), 0.42)
		if gt != null:
			var gs := Sprite2D.new()
			gs.texture = gt
			gs.position = cfg.pos
			var gw := maxf(float(gt.get_width()), 1.0)
			gs.scale = Vector2.ONE * (float(cfg.diam) / gw)
			gs.modulate = cfg.mod
			_gear_back_layer.add_child(gs)
			_gear_sprites.append(gs)

	var pf_tex := _make_canvas_tex(ASSET_DIR + "pallet_fork.png", ASSET_DIR + "pallet_fork_n.png", 0.48)
	if pf_tex != null:
		_pallet_fork_spr = Sprite2D.new()
		_pallet_fork_spr.texture = pf_tex
		_pallet_fork_spr.position = Vector2(R * 0.04, -R * 0.44)
		_pallet_fork_spr.scale = Vector2.ONE * ((R * 0.42) / maxf(float(pf_tex.get_height()), 1.0))
		_pallet_fork_spr.modulate = Color(0.62, 0.38, 0.30, 0.94)
		_gear_back_layer.add_child(_pallet_fork_spr)

	# 3. 第三层：优先加载 v4 高精血红哥特玫瑰彩窗钟面（带实时流淌雨痕与 Voronoi 多边形晶体崩裂 Shader）
	var glass_tex := _load_tex(ASSET_DIR + "v4_rose_glass_559.png")
	_using_v4_dial = glass_tex != null
	if glass_tex == null:
		glass_tex = _load_tex(ASSET_DIR + "dial_glass_translucent.png")
	if glass_tex != null:
		_glass_sprite = Sprite2D.new()
		_glass_sprite.name = "CrimsonFrostedGlass"
		_glass_sprite.texture = glass_tex
		_glass_sprite.scale = Vector2.ONE * (DIAL_WORLD_DIAMETER / maxf(float(glass_tex.get_width()), 1.0))
		var g_sh := Shader.new()
		g_sh.code = FROSTED_GLASS_SHADER
		_glass_mat = ShaderMaterial.new()
		_glass_mat.shader = g_sh
		_glass_sprite.material = _glass_mat
		add_child(_glass_sprite)

	# 4. 第四层：厚重哥特铸铁玫瑰窗花外框、罗马数字 I~XII 与法线受光层（v4 原生已自带精雕外框与罗马数字，避免重影）
	var frame_ct := _make_canvas_tex(ASSET_DIR + "dial_iron_frame.png", ASSET_DIR + "dial_iron_frame_n.png", 0.45)
	if frame_ct != null:
		_frame_sprite = Sprite2D.new()
		_frame_sprite.name = "GothicIronFrameAndNumerals"
		_frame_sprite.texture = frame_ct
		_frame_sprite.scale = Vector2.ONE * (DIAL_WORLD_DIAMETER / maxf(float(frame_ct.get_width()), 1.0))
		_frame_sprite.visible = not _using_v4_dial
		add_child(_frame_sprite)

	# 5. 第五层：时间倒流扇形流光残影弧
	_fan_quad = ColorRect.new()
	_fan_quad.name = "RewindSweepFan"
	_fan_quad.position = Vector2(-R, -R)
	_fan_quad.size = Vector2(DIAL_WORLD_DIAMETER, DIAL_WORLD_DIAMETER)
	_fan_quad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fan_sh := Shader.new()
	fan_sh.code = REWIND_FAN_SHADER
	_fan_mat = ShaderMaterial.new()
	_fan_mat.shader = fan_sh
	_fan_quad.material = _fan_mat
	add_child(_fan_quad)

	# 6. 第六层：十米哥特铸铁时针 + 分针（精确锚定青铜轴孔旋转）
	_hour_pivot = Node2D.new()
	_hour_pivot.name = "HourHandPivot"
	add_child(_hour_pivot)
	var hour_ct := _make_canvas_tex(ASSET_DIR + "hand_hour.png", ASSET_DIR + "hand_hour_n.png", 0.52)
	if hour_ct != null:
		_hour_sprite = Sprite2D.new()
		_hour_sprite.texture = hour_ct
		_hour_sprite.centered = false
		var hpiv: Array = _meta.get("hour_pivot_px", [47.6, float(hour_ct.get_height()) * 0.5])
		var hs := (R * 0.54) / maxf(float(hour_ct.get_width()) - float(hpiv[0]), 1.0)
		_hour_sprite.scale = Vector2.ONE * hs
		_hour_sprite.position = -Vector2(float(hpiv[0]), float(hpiv[1])) * hs
		_hour_pivot.add_child(_hour_sprite)

	_minute_pivot = Node2D.new()
	_minute_pivot.name = "MinuteHandPivot"
	add_child(_minute_pivot)
	var min_ct := _make_canvas_tex(ASSET_DIR + "hand_minute.png", ASSET_DIR + "hand_minute_n.png", 0.56)
	if min_ct != null:
		_minute_sprite = Sprite2D.new()
		_minute_sprite.texture = min_ct
		_minute_sprite.centered = false
		var mpiv: Array = _meta.get("minute_pivot_px", [45.55, float(min_ct.get_height()) * 0.5])
		var ms := (R * 0.81) / maxf(float(min_ct.get_width()) - float(mpiv[0]), 1.0)
		_minute_sprite.scale = Vector2.ONE * ms
		_minute_sprite.position = -Vector2(float(mpiv[0]), float(mpiv[1])) * ms
		_minute_pivot.add_child(_minute_sprite)

	# 中心青铜铆钉玫瑰压盖（使用漫反射贴图并关闭中心强点光高光，保留厚重青铜浮雕细节不曝白！）
	var hub_diff := _load_tex(ASSET_DIR + "hub_cap.png")
	if hub_diff != null:
		_hub_cap = Sprite2D.new()
		_hub_cap.texture = hub_diff
		_hub_cap.light_mask = 0
		_hub_cap.modulate = Color(0.88, 0.78, 0.74, 1.0)
		_hub_cap.scale = Vector2.ONE * ((R * 0.17) / maxf(float(hub_diff.get_width()), 1.0))
		add_child(_hub_cap)

	# 7. 第七层：二阶段崩裂悬停的 24 块厚暗朱红磨砂玻璃残片（跃出 M1 石拱腔体至 z=-18，支持时间倒流螺旋重拼！）
	_shards_layer = Node2D.new()
	_shards_layer.name = "SuspendedCrimsonShards"
	_shards_layer.z_as_relative = false
	_shards_layer.z_index = -18
	add_child(_shards_layer)
	_build_shatter_shards(R)

	# 8. 第八层：5:59 卡死啮合点真实金属飞溅火花粒子层（跃出石拱腔体至 z=-17）
	_sparks_layer = Node2D.new()
	_sparks_layer.name = "JamSparksLayer"
	_sparks_layer.z_as_relative = false
	_sparks_layer.z_index = -17
	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_sparks_layer.material = add_mat
	add_child(_sparks_layer)
	_sparks_layer.draw.connect(_draw_sparks)

	# 9. 动态暗朱红法线点光源（适中高度 height=380 使光照均匀掠过整面铁窗花，中心绝不刺眼过曝）
	_furnace_light = PointLight2D.new()
	_furnace_light.name = "CrimsonClockNormalLight"
	_furnace_light.texture = _make_radial_tex(256, 1.65)
	_furnace_light.texture_scale = 9.5
	_furnace_light.color = Color(0.96, 0.22, 0.16)
	_furnace_light.energy = 0.52
	_furnace_light.height = 380.0
	add_child(_furnace_light)

	_apply_transforms()


func _build_shatter_shards(R: float) -> void:
	var shard_texs: Array[Texture2D] = []
	for i in 6:
		var st := _make_canvas_tex(
			ASSET_DIR + "shard_%d.png" % i,
			ASSET_DIR + "shard_%d_n.png" % i,
			0.55
		)
		if st != null:
			shard_texs.append(st)
	if shard_texs.is_empty():
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = 20260559
	for i in 24:
		var tex := shard_texs[i % shard_texs.size()]
		var sp := Sprite2D.new()
		sp.texture = tex
		sp.visible = false
		var target_sz := rng.randf_range(95.0, 180.0)
		var base_s := target_sz / maxf(float(tex.get_width()), 1.0)
		sp.scale = Vector2.ONE * base_s
		_shards_layer.add_child(sp)

		var ang := (TAU * float(i) / 24.0) + rng.randf_range(-0.08, 0.08)
		var home_r := R * rng.randf_range(0.52, 0.78)
		var orbit_r := home_r + R * rng.randf_range(0.14, 0.38)
		_shards.append({
			"node": sp,
			"base_s": base_s,
			"home_pos": Vector2(cos(ang), sin(ang)) * home_r,
			"orbit_pos": Vector2(cos(ang + rng.randf_range(-0.18, 0.18)), sin(ang + rng.randf_range(-0.18, 0.18))) * orbit_r,
			"home_rot": ang + PI * 0.5,
			"spin_spd": rng.randf_range(-0.65, 0.65),
			"bob_phase": rng.randf_range(0.0, TAU),
			"spiral_dir": 1.0 if (i % 2 == 0) else -1.0,
		})


func set_clock_state(new_state: int, immediate: bool = false) -> void:
	var prev := state
	state = new_state
	if new_state == ClockState.SHATTERED_ORBIT and prev != ClockState.SHATTERED_ORBIT:
		crack_amt = 1.0
		_emit_jam_sparks(Vector2(0.0, -DIAL_WORLD_DIAMETER * 0.25), 48, 560.0)
		jam_shockwave_fired.emit(global_position, 1.05, 1.0)
	elif new_state == ClockState.REWIND_OVERDRIVE and prev != ClockState.REWIND_OVERDRIVE:
		jam_shockwave_fired.emit(global_position, 0.90, 0.95)
	elif new_state == ClockState.CLEAVED_600 and prev != ClockState.CLEAVED_600:
		_emit_jam_sparks(Vector2(0.0, -DIAL_WORLD_DIAMETER * 0.34), 60, 650.0)
		jam_shockwave_fired.emit(global_position, 1.18, 0.15)
	elif new_state == ClockState.JAMMED_559 and immediate:
		rewind_amt = 0.0
		crack_amt = 0.0
		shatter_amt = 0.0
		dawn_calm = 0.0
		hour_angle = HOUR_ANGLE_559
		minute_angle = MINUTE_ANGLE_559


func trigger_manual_heartbeat_burst() -> void:
	_heartbeat_clock = HEARTBEAT_PERIOD * 0.70
	_last_snap_cycle = -99


func trigger_boss_cue(cue: String, intensity: float = 1.0) -> void:
	var k := clampf(intensity, 0.35, 1.8)
	var tip_pos := Vector2(cos(minute_angle), sin(minute_angle)) * (DIAL_WORLD_DIAMETER * 0.34)
	match cue:
		"windup":
			_cue_pulse = maxf(_cue_pulse, 1.15 * k)
			_cue_twitch = maxf(_cue_twitch, 1.0 * k)
			_emit_jam_sparks(tip_pos, int(round(14.0 * k)), 360.0)
		"impact", "clash":
			_cue_pulse = maxf(_cue_pulse, 1.45 * k)
			_cue_twitch = maxf(_cue_twitch, 1.25 * k)
			_emit_jam_sparks(tip_pos, int(round(28.0 * k)), 520.0)
			jam_shockwave_fired.emit(global_position, 0.72 * k, 0.92)
		"burst":
			_cue_pulse = maxf(_cue_pulse, 1.80 * k)
			_cue_twitch = maxf(_cue_twitch, 1.50 * k)
			_emit_jam_sparks(Vector2(0.0, -DIAL_WORLD_DIAMETER * 0.24), int(round(46.0 * k)), 620.0)
			jam_shockwave_fired.emit(global_position, 1.12 * k, 1.0)
		_:
			_cue_pulse = maxf(_cue_pulse, 0.85 * k)


func _emit_jam_sparks(local_origin: Vector2, count: int, max_spd: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(time_sec * 1000.0) + _sparks.size() * 17 + 559
	for _i in count:
		var a := rng.randf_range(-PI * 0.85, PI * 0.85)
		var spd := rng.randf_range(max_spd * 0.30, max_spd)
		var is_crimson := rng.randf() < 0.55
		_sparks.append({
			"origin": local_origin,
			"pos": local_origin + Vector2(rng.randf_range(-16.0, 16.0), rng.randf_range(-16.0, 16.0)),
			"vel": Vector2(cos(a), sin(a)) * spd,
			"age": 0.0,
			"life": rng.randf_range(0.52, 1.18),
			"size": rng.randf_range(3.8, 9.6),
			"crimson": is_crimson,
		})


func step_clock(dt: float) -> void:
	time_sec += dt
	var target_rewind := 1.0 if state == ClockState.REWIND_OVERDRIVE else 0.0
	var target_shatter := 1.0 if (state == ClockState.SHATTERED_ORBIT or (state == ClockState.REWIND_OVERDRIVE and crack_amt > 0.5)) else 0.0
	var target_crack := 1.0 if (target_shatter > 0.5) else 0.0
	var target_dawn := 1.0 if state == ClockState.CLEAVED_600 else 0.0

	rewind_amt = move_toward(rewind_amt, target_rewind, dt * 3.2)
	crack_amt = move_toward(crack_amt, target_crack, dt * 2.8)
	var effective_shatter_target := target_shatter * (1.0 - smoothstep(0.25, 0.92, rewind_amt))
	if state == ClockState.CLEAVED_600:
		effective_shatter_target = 0.0
		crack_amt = move_toward(crack_amt, 0.0, dt * 3.2)
	shatter_amt = move_toward(shatter_amt, effective_shatter_target, dt * 2.6)
	dawn_calm = move_toward(dawn_calm, target_dawn, dt * 1.6)

	var rain_dir := lerpf(1.0, -3.6, rewind_amt)
	rain_phase += dt * rain_dir

	if state == ClockState.REWIND_OVERDRIVE:
		var rev_spd := TAU * (1.42 + 0.88 * rewind_amt)
		minute_angle -= rev_spd * dt
		hour_angle -= rev_spd * 0.14 * dt
		gear_phase -= dt * 6.2
		pulse_val = 0.95 + 0.35 * sin(time_sec * 19.0)
		_fan_span = lerpf(_fan_span, 1.65, clampf(dt * 7.5, 0.0, 1.0))
		_fan_intensity = lerpf(_fan_intensity, 1.48, clampf(dt * 7.5, 0.0, 1.0))
	elif state == ClockState.CLEAVED_600:
		minute_angle = lerpf(minute_angle, MINUTE_ANGLE_600, clampf(dt * 8.5, 0.0, 1.0))
		hour_angle = lerpf(hour_angle, HOUR_ANGLE_600, clampf(dt * 6.0, 0.0, 1.0))
		pulse_val = move_toward(pulse_val, 0.08, dt * 1.8)
		_fan_span = move_toward(_fan_span, 0.0, dt * 5.0)
		_fan_intensity = move_toward(_fan_intensity, 0.0, dt * 5.0)
	else:
		_heartbeat_clock += dt * (1.28 if state == ClockState.SHATTERED_ORBIT else 1.0)
		var cyc := int(floor(_heartbeat_clock / HEARTBEAT_PERIOD))
		var u := fmod(_heartbeat_clock, HEARTBEAT_PERIOD) / HEARTBEAT_PERIOD

		if u < 0.62:
			var k := smoothstep(0.12, 0.62, u)
			_jam_strain = pow(k, 1.7)
			_jam_tremor = sin(time_sec * 260.0) * 0.0048 * k
			pulse_val = 0.22 + 0.80 * k
		elif u < 0.72:
			_jam_strain = 1.0
			_jam_tremor = sin(time_sec * 330.0) * 0.009
			pulse_val = 1.18
		else:
			if cyc != _last_snap_cycle:
				_last_snap_cycle = cyc
				var tip_pos := Vector2(cos(MINUTE_ANGLE_559), sin(MINUTE_ANGLE_559)) * (DIAL_WORLD_DIAMETER * 0.34)
				_emit_jam_sparks(tip_pos, 32 if state == ClockState.SHATTERED_ORBIT else 24, 430.0)
				jam_shockwave_fired.emit(global_position + tip_pos * 0.35, 0.58 if state == ClockState.SHATTERED_ORBIT else 0.44, 0.68)
			var rk := (u - 0.72) / 0.28
			var bounce := exp(-rk * 7.5) * cos(rk * 26.0)
			_jam_strain = maxf(0.0, bounce * 0.24)
			_jam_tremor = bounce * 0.012
			pulse_val = 0.22 + 0.88 * exp(-rk * 5.2)

		var strain_rad := deg_to_rad(4.5 if state == ClockState.SHATTERED_ORBIT else 3.6) * _jam_strain
		var boss_twitch_rad := sin(time_sec * 190.0) * deg_to_rad(2.8) * _cue_twitch + deg_to_rad(5.2) * _cue_twitch
		minute_angle = MINUTE_ANGLE_559 + strain_rad + _jam_tremor + boss_twitch_rad
		hour_angle = HOUR_ANGLE_559 + strain_rad * 0.08 + _jam_tremor * 0.25 + boss_twitch_rad * 0.12
		pulse_val = clampf(pulse_val + _cue_pulse * 0.92, 0.0, 2.0)
		gear_phase += dt * (0.28 + 0.88 * _jam_strain + 2.4 * _cue_twitch)
		_fan_span = move_toward(_fan_span, 0.16 * pulse_val + 0.45 * _cue_twitch, dt * 6.0)
		_fan_intensity = move_toward(_fan_intensity, 0.28 * pulse_val + 0.65 * _cue_pulse, dt * 6.0)

	_cue_pulse = move_toward(_cue_pulse, 0.0, dt * 2.2)
	_cue_twitch = move_toward(_cue_twitch, 0.0, dt * 3.1)
	_step_sparks(dt)
	_apply_transforms()


func _step_sparks(dt: float) -> void:
	var rev := rewind_amt
	for s in _sparks:
		if rev > 0.35:
			var to_orig: Vector2 = Vector2(s.origin) - Vector2(s.pos)
			s.pos = Vector2(s.pos) + to_orig * clampf(dt * 6.5 * rev, 0.0, 1.0)
			s.age = maxf(0.05, float(s.age) - dt * 0.85)
		else:
			var v: Vector2 = s.vel
			v.y += 640.0 * dt
			v *= exp(-1.5 * dt)
			s.vel = v
			s.pos = Vector2(s.pos) + v * dt
			s.age = float(s.age) + dt
	_sparks = _sparks.filter(func(s): return float(s.age) < float(s.life))
	if _sparks_layer != null:
		_sparks_layer.queue_redraw()


func _apply_transforms() -> void:
	if _hour_pivot != null:
		_hour_pivot.rotation = hour_angle
	if _minute_pivot != null:
		_minute_pivot.rotation = minute_angle

	for i in _gear_sprites.size():
		var gs := _gear_sprites[i]
		var spd := _gear_base_speeds[i % _gear_base_speeds.size()]
		gs.rotation = gear_phase * spd + (_jam_tremor * 1.8 if i == 1 else 0.0)

	if _pallet_fork_spr != null:
		_pallet_fork_spr.rotation = -0.35 + sin(gear_phase * 4.0) * 0.16 * (1.0 if rewind_amt > 0.2 else _jam_strain) + _jam_tremor * 2.5

	if _furnace_mat != null:
		_furnace_mat.set_shader_parameter("pulse", pulse_val)
		_furnace_mat.set_shader_parameter("rewind_amt", rewind_amt)
		_furnace_mat.set_shader_parameter("shatter_amt", shatter_amt)
		_furnace_mat.set_shader_parameter("dawn_calm", dawn_calm)
		_furnace_mat.set_shader_parameter("flow_time", time_sec)

	if _glass_mat != null:
		_glass_mat.set_shader_parameter("pulse", pulse_val)
		_glass_mat.set_shader_parameter("rewind_amt", rewind_amt)
		_glass_mat.set_shader_parameter("crack_amt", crack_amt)
		_glass_mat.set_shader_parameter("shatter_hole", shatter_amt)
		_glass_mat.set_shader_parameter("dawn_calm", dawn_calm)
		_glass_mat.set_shader_parameter("rain_phase", rain_phase)

	if _fan_mat != null:
		_fan_mat.set_shader_parameter("head_angle", minute_angle)
		_fan_mat.set_shader_parameter("sweep_span", _fan_span)
		_fan_mat.set_shader_parameter("intensity", _fan_intensity * (0.42 if overlay_only_mode else 1.0))

	if _furnace_light != null:
		var dawn_col := Color(0.72, 0.82, 0.96)
		var crim_col := Color(0.92, 0.16, 0.12).lerp(Color(1.0, 0.34, 0.20), rewind_amt * 0.45)
		_furnace_light.color = crim_col.lerp(dawn_col, dawn_calm)
		var base_e := (0.16 + 0.16 * pulse_val + 0.22 * rewind_amt + 0.14 * shatter_amt) if overlay_only_mode else (0.46 + 0.42 * pulse_val + 0.36 * rewind_amt + 0.22 * shatter_amt)
		_furnace_light.energy = base_e * (1.0 - 0.45 * dawn_calm)

	for sh in _shards:
		var sp: Sprite2D = sh.node
		if shatter_amt <= 0.015:
			sp.visible = false
			continue
		sp.visible = true
		var k := smoothstep(0.0, 1.0, shatter_amt)
		var home_p: Vector2 = sh.home_pos
		var orb_p: Vector2 = sh.orbit_pos
		var mid_ctrl := (home_p + orb_p) * 0.5 + Vector2(-orb_p.y, orb_p.x) * 0.22 * float(sh.spiral_dir) * sin(k * PI)
		var cur_p := home_p.lerp(orb_p, k) + (mid_ctrl - (home_p + orb_p) * 0.5) * 0.85
		var bob := Vector2(cos(time_sec * 1.4 + float(sh.bob_phase)), sin(time_sec * 1.8 + float(sh.bob_phase))) * (12.0 * k)
		sp.position = cur_p + bob
		sp.rotation = lerpf(float(sh.home_rot), float(sh.home_rot) + time_sec * float(sh.spin_spd), k)
		var breathe := 0.85 + 0.25 * pulse_val + 0.35 * rewind_amt
		sp.modulate = Color(breathe, breathe * 0.92, breathe * 0.92, clampf(k * 1.25, 0.0, 1.0))


func _draw_sparks() -> void:
	if _spark_tex == null:
		return
	for s in _sparks:
		var k := clampf(1.0 - float(s.age) / maxf(float(s.life), 0.01), 0.0, 1.0)
		var sz := float(s.size) * (0.55 + 0.65 * k)
		var p: Vector2 = s.pos
		var v: Vector2 = s.vel
		var col := Color(1.0, 0.28, 0.14, k * 0.95) if bool(s.crimson) else Color(1.0, 0.78, 0.40, k * 0.98)
		if v.length() > 20.0:
			var dir := v.normalized()
			var tail_len := clampf(v.length() * 0.075, 8.0, 44.0)
			_sparks_layer.draw_line(p - dir * tail_len, p, col, maxf(1.8, sz * 0.42), true)
		_sparks_layer.draw_texture_rect(_spark_tex, Rect2(p - Vector2(sz, sz), Vector2(sz, sz) * 2.0), false, col)
