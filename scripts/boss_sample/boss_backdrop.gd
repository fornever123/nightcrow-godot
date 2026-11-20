extends Node2D
## 第一章关底舞台：【司辰母钟楼 · 钟前校时天廊】
## （2D 手绘哥特嵌钟石拱巨塔 × 5:59 暗血珀母钟 7 层光学总成 × SubViewport 真透视 3D 实体石桥 × F1 浅景深前景巨链）
##
## 严格对齐《剧情与主题规划.md》与用户 11-17 指示（「钟不用 3d，地面 3d 试试，钟和背景看看美术能不能更好看」）：
##   1. 远中后景纯正厚涂手绘多级视差：
##      - 0.10x S4 无月暗云与百米影街深渊底图
##      - 0.16x M2 母钟楼两翼维多利亚-哥特远塔群、长飞扶壁与高架桥雾海剪影
##      - 0.26x M1 司辰母钟楼嵌钟石拱巨框与双侧青铜擒纵天轴（像素级包嵌 1320u 暗血珀母钟，彻底根除孤立圆盘贴纸感）
##   2. 地面 1.0x SubViewport 真透视 3D 实体桥面（Deck3D）：
##      - z=0 与 2D floor_y=580 像素级 1:1 重合，镜头横移时湿青石板向深处收拢、双层尖拱桥洞与栏杆立柱真实错位；
##      - 湿石板实时接收母钟暗红心跳、哥特六棱煤气路灯暖光与主角独享纯紫刀光高光；两翼无缝衔接 S1/S3 手绘真石阶翼楼；
##   3. 最前景 1.28x F1 电影级大光圈虚焦重型铸铁钟链与尖拱残角，配合 5 重母钟光学动效。

const CrimsonClockRig := preload("res://scripts/boss_sample/crimson_clock_rig.gd")
const Deck3D := preload("res://scripts/boss_sample/deck_3d.gd")
const LayerFogShader := preload("res://scripts/night/rain_layer_fog.gdshader")

const STAGE_DIR := "res://assets/image/boss_duanchao/crimson_stage/"
const STAGE_META_PATH := STAGE_DIR + "stage_meta.json"

const CLOCK_RADIUS := 660.0
const BELFRY_HOLE_WORLD_R := 618.0   ## M1 石拱内圈严丝合缝包住母钟外沿（618..651u），完整露出罗马刻度环与铁窗花
const CLOCK_PARALLAX_X := 0.44
const CLOCK_PARALLAX_Y := 0.44
const CLOCK_BASE_OFFSET_Y := -230.0
const MID_TOWER_PARALLAX_X := 0.18
const MID_TOWER_PARALLAX_Y := 0.24

const ARENA_TILE_SPAN := 4920.0      ## 左/中/右三段共覆盖 4920u，完整包裹 4800u 战场
const SINGLE_TILE_W := 1640.0

## 动效二：60° 暗血珀朱红×冷银琴弦体积斜光栅（受母钟内部齿轮相位与十米分针角度实时遮挡切割）
const VOLUMETRIC_GODRAYS_SHADER := """
shader_type canvas_item;
render_mode blend_add;

uniform vec2 clock_uv = vec2(0.5, 0.34);
uniform float pulse : hint_range(0.0, 2.0) = 0.35;
uniform float rewind_amt : hint_range(0.0, 1.0) = 0.0;
uniform float shatter_amt : hint_range(0.0, 1.0) = 0.0;
uniform float dawn_calm : hint_range(0.0, 1.0) = 0.0;
uniform float gear_phase = 0.0;
uniform float minute_angle = -1.68;
uniform float time_sec = 0.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 d = uv - clock_uv;
	vec2 ray_dir = normalize(vec2(-0.46, 0.888));
	vec2 perp_dir = vec2(ray_dir.y, -ray_dir.x);
	float along = dot(d, ray_dir);
	float across = dot(d, perp_dir);

	if (along < -0.28) {
		COLOR = vec4(0.0);
	} else {
		float str1 = sin(across * 46.0 + gear_phase * 2.4) * 0.5 + 0.5;
		float str2 = sin(across * 82.0 - gear_phase * 4.1 + sin(time_sec * 0.8)) * 0.5 + 0.5;
		float hand_cut = 1.0 - 0.38 * exp(-pow((across - sin(minute_angle) * 0.16) * 24.0, 2.0));
		float chords = pow(str1 * 0.62 + str2 * 0.38, 1.85) * hand_cut;

		float abs_c = abs(across);
		float crimson_band = smoothstep(0.08, 0.18, abs_c) * (1.0 - smoothstep(0.30, 0.46, abs_c));
		float silver_core = 1.0 - smoothstep(0.0, 0.20, abs_c);
		float dist_fade = smoothstep(-0.26, 0.08, along) * (1.0 - smoothstep(0.32, 0.96, along));

		vec3 crim_col = vec3(0.76, 0.125, 0.095) * (0.92 + 0.48 * pulse + 0.58 * rewind_amt + 0.26 * shatter_amt);
		vec3 silv_col = vec3(0.44, 0.54, 0.70) * (0.50 + 0.25 * shatter_amt);
		if (dawn_calm > 0.001) {
			crim_col = mix(crim_col, vec3(0.62, 0.74, 0.90), dawn_calm * 0.85);
		}

		vec3 col = (crim_col * crimson_band * 0.135 + silv_col * silver_core * 0.062) * (0.42 + 0.85 * chords) * dist_fade;
		COLOR = vec4(col, 1.0);
	}
}
"""

## 空气透视景深柔化与冷雾压暗层（严格位于 M1 石拱巨塔/母钟之上、3D 实体桥面与人物之下：常态让红钟退后二十米突出前景人物，爆发瞬间撕开雾气炸亮！）
const BACKDROP_DEPTH_FOG_SHADER := """
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float blur_lod : hint_range(0.0, 2.5) = 1.05;
uniform float dim_gain : hint_range(0.35, 1.1) = 0.72;
uniform float fog_mix : hint_range(0.0, 0.55) = 0.24;
uniform vec3 fog_col = vec3(0.045, 0.062, 0.095);
uniform float time_sec = 0.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = SCREEN_PIXEL_SIZE * (1.2 + blur_lod * 1.45);
	// 5-tap 轻量光学散焦，软化背景红钟与石拱的尖锐细节，让前景冷银首领与主角紫刀光一秒跳出
	vec3 c = textureLod(screen_tex, uv, blur_lod * 0.65).rgb * 0.44;
	c += textureLod(screen_tex, clamp(uv + vec2(px.x, px.y), vec2(0.001), vec2(0.999)), blur_lod * 0.65).rgb * 0.14;
	c += textureLod(screen_tex, clamp(uv + vec2(-px.x, px.y), vec2(0.001), vec2(0.999)), blur_lod * 0.65).rgb * 0.14;
	c += textureLod(screen_tex, clamp(uv + vec2(px.x, -px.y), vec2(0.001), vec2(0.999)), blur_lod * 0.65).rgb * 0.14;
	c += textureLod(screen_tex, clamp(uv + vec2(-px.x, -px.y), vec2(0.001), vec2(0.999)), blur_lod * 0.65).rgb * 0.14;

	// 轻微降饱和 + 压稳亮度，避免背后红钟饱和度盖过前景角色
	float lum = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(lum), c, 0.86) * dim_gain;

	// 底部靠近桥面处空气雾更浓，营造百米高空雨雾纵深
	float mist_wave = 0.85 + 0.15 * sin(uv.x * 9.0 + time_sec * 0.55) * cos(uv.y * 5.0 - time_sec * 0.35);
	float v_fog = fog_mix * (0.65 + 0.75 * smoothstep(0.25, 0.92, uv.y)) * mist_wave;
	c = mix(c, fog_col, clamp(v_fog, 0.0, 0.52));
	COLOR = vec4(c, 1.0);
}
"""

## 湿青石板积水薄镜实时倒影（叠在 3D 桥面石板表层，将上方 2D 母钟红光与主角紫刀光真实映入湿石缝；0% 海浪积水）
const WET_SLATE_MIRROR_SHADER := """
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D noise_tex : repeat_enable, filter_linear;
uniform float floor_line_y = 580.0;
uniform float slab_depth = 34.0;
uniform float crimson_boost : hint_range(0.0, 2.0) = 0.5;

varying vec2 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	float depth = max(world.y - floor_line_y, 0.0);
	float fade = (1.0 - smoothstep(3.0, slab_depth, depth)) * step(0.0, world.y - floor_line_y + 1.0);
	if (fade <= 0.002) {
		COLOR = vec4(0.0);
	} else {
		float n = texture(noise_tex, (world + vec2(TIME * 3.5, 0.0)) * vec2(1.0 / 180.0, 1.0 / 28.0)).r - 0.5;
		float joint_mask = 0.55 + 0.45 * smoothstep(-0.15, 0.25, sin(world.x * 0.085) * cos(world.y * 0.30 + n * 2.0));
		float wpx_y = max(abs(dFdy(world.y)), 0.0001);
		vec2 uv = SCREEN_UV;
		uv.y -= (depth * 2.15 + n * 2.2) * SCREEN_PIXEL_SIZE.y / wpx_y;
		uv.x += n * 0.0020;

		vec3 refl = vec3(0.0);
		if (uv.y >= 0.002 && uv.y <= 0.998) {
			refl = textureLod(screen_tex, clamp(uv, vec2(0.002), vec2(0.998)), 0.65).rgb;
		}
		// 仅提取高光（红钟罗马环、暖灯、主角紫刀光）叠映在 3D 石板湿膜上，不遮盖 3D 石砖立体凹凸纹理
		float hi = smoothstep(0.11, 0.54, max(refl.r, max(refl.g, refl.b)));
		vec3 wet_col = refl * (0.55 + 0.55 * hi) + vec3(0.07, 0.011, 0.009) * crimson_boost * hi;
		COLOR = vec4(wet_col, fade * joint_mask * (0.14 + 0.26 * hi));
	}
}
"""

## 可双向变速/倒流的三层斜雨幕着色器（常态斜落；触发【时间倒流】时整场百雨悬停倒吸升向夜空）
const REVERSIBLE_RAIN_SHADER := """
shader_type canvas_item;

uniform float cam_x = 0.0;
uniform float rain_scroll = 0.0;
uniform float k = 0.45;
uniform float cell = 9.0;
uniform float density = 0.34;
uniform float seg = 58.0;
uniform float period = 410.0;
uniform float alpha = 0.13;
uniform float tilt = 0.11;
uniform vec2 clock_uv = vec2(0.5, 0.34);
uniform float crimson_lit : hint_range(0.0, 2.0) = 0.65;
uniform float rewind_amt : hint_range(0.0, 1.0) = 0.0;

float h(float n) { return fract(sin(n * 127.1) * 43758.5453); }

void fragment() {
	vec2 p = SCREEN_UV * vec2(1280.0, 720.0);
	p.x += cam_x * k * 0.65 + p.y * tilt;
	float ci = floor(p.x / cell);
	float hh = h(ci);
	float on = step(1.0 - density, hh);
	float fx = abs(fract(p.x / cell) - 0.5) * cell;
	float line = 1.0 - smoothstep(0.22, 0.88, fx);

	float spd_mul = 0.76 + 0.48 * h(ci + 7.3);
	float cur_seg = seg * mix(1.0, 1.38, rewind_amt);
	float y = p.y - rain_scroll * spd_mul + hh * period;
	float s = fract(y / period) * period;
	float st = smoothstep(0.0, cur_seg * 0.25, s) * (1.0 - smoothstep(cur_seg * 0.25, cur_seg, s));

	float d_clock = length((SCREEN_UV - clock_uv) * vec2(1.45, 1.0));
	float red_zone = (1.0 - smoothstep(0.12, 0.62, d_clock)) * crimson_lit;
	vec3 base_col = vec3(0.54, 0.63, 0.78);
	vec3 red_col = vec3(0.90, 0.22, 0.16);
	vec3 col = mix(base_col, red_col, clamp(red_zone * 0.68 + rewind_amt * 0.35, 0.0, 0.86));

	COLOR = vec4(col, alpha * on * line * st);
}
"""

## 屏幕空间时间冲击波与倒流红玻璃暗角着色器
const TEMPORAL_SHOCKWAVE_SHADER := """
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec2 wave_center_uv = vec2(0.5, 0.35);
uniform float wave_radius : hint_range(0.0, 2.2) = 0.0;
uniform float wave_strength : hint_range(0.0, 1.5) = 0.0;
uniform float crimson_tint : hint_range(0.0, 1.5) = 0.6;
uniform float rewind_vignette : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 aspect_d = (uv - wave_center_uv) * vec2(1.7778, 1.0);
	float dist = length(aspect_d);
	float ring = exp(-pow((dist - wave_radius) * 15.5, 2.0)) * wave_strength;

	vec2 dir = dist > 0.0001 ? normalize(uv - wave_center_uv) : vec2(0.0, 1.0);
	vec2 disp = dir * ring * 0.016;

	float r_ch = texture(screen_tex, clamp(uv + disp * 1.35, vec2(0.001), vec2(0.999))).r;
	vec2 gb_ch = texture(screen_tex, clamp(uv + disp * 0.82, vec2(0.001), vec2(0.999))).gb;
	vec3 col = vec3(r_ch, gb_ch.x, gb_ch.y);

	col += vec3(0.68, 0.10, 0.075) * ring * crimson_tint * 0.40;

	if (rewind_vignette > 0.001) {
		float edge = smoothstep(0.42, 0.98, length((uv - vec2(0.5)) * vec2(1.35, 1.15)));
		col = mix(col, col * vec3(1.16, 0.78, 0.76) + vec3(0.22, 0.028, 0.020), edge * rewind_vignette * 0.60);
	}

	float active_alpha = clamp(ring * 2.5 + rewind_vignette * 0.98, 0.0, 1.0);
	COLOR = vec4(col, active_alpha > 0.002 ? 1.0 : 0.0);
}
"""

enum DropState { SUSPENDED, FALLING, RESPAWNING }

var camera: Camera2D = null
var floor_y: float = 580.0
var ok: bool = true
var layout: Dictionary = {}
var first_x: float = 2400.0
var spacing: float = 6400.0
var actors: Callable

var section: int = 0
var section_center: float = 2400.0
var fight_half: float = 2400.0
var cam_ref: float = 272.3

## 与旧测试及 HUD 100% 兼容的状态字段
var phase2_cracked: bool = false
var crack_amount: float = 0.0
var eclipse_dim: float = 0.0
var rewind_visual_amt: float = 0.0
var slashed_rain_total: int = 0
var victory_dawn: bool = false
var boss_hp_ratio: float = 1.0

## 暴露给 rain_street.gd 与 rain_lights.gd 的两翼主风灯（保持 size == 2 兼容回归断言）
var _lamps: Array = []

var clock_rig: Node2D = null
var deck_3d: Node2D = null
var _clock_mat: ShaderMaterial = null
var _mirror_mat: ShaderMaterial = null
var _ctex_p1: CanvasTexture = null
var _ctex_s1: CanvasTexture = null
var _ctex_s2: CanvasTexture = null
var _ctex_s3: CanvasTexture = null
var _ctex_belfry_m1: CanvasTexture = null

var _player_light: PointLight2D = null
var _clash_light: PointLight2D = null
var _wing_lamp_lights: Array[PointLight2D] = []
var _clash_light_energy: float = 0.0

var _pillar_shake_l: float = 0.0
var _pillar_shake_r: float = 0.0
var _pillar_glow_l: float = 0.0
var _pillar_glow_r: float = 0.0

var _time: float = 0.0
var _rain_scroll_far: float = 0.0
var _rain_scroll_near: float = 0.0
var _rewind_target: float = 0.0
var _eclipse_target: float = 0.0
var _boss_red_dim: float = 0.0
var _ult_mode: bool = false

var _wave_origin_world: Vector2 = Vector2.ZERO
var _wave_radius: float = 2.5
var _wave_strength: float = 0.0
var _wave_crimson: float = 0.65
var _fg_jolt: float = 0.0

var _stage_meta: Dictionary = {}
var _m1_hole_center_px := Vector2(765.0, 503.0)
var _m1_hole_radius_px: float = 272.5
var _using_v4_stage: bool = false
var _using_v5_stage: bool = false
var _v4_scale: float = 1.05
var _v4_bridge_y_px: float = 768.0
var _v5_tower_scale: float = 0.84
var _clock_cue_boost: float = 0.0
var _v5_gear_tex: Texture2D
var _v5_gear_sprites: Array[Sprite2D] = []
var _v5_gear_cfgs: Array[Dictionary] = []
var _v5_gear_phase: float = 0.0
var _canyon_mist_node: Node2D

var _sky_layer: CanvasLayer
var _far_sky_sprites: Array[Sprite2D] = []
var _far_sky_tex: Texture2D
var _mid_tower_sprites: Array[Sprite2D] = []
var _mid_tower_tex: Texture2D
var _belfry_m1_spr: Sprite2D

var _rays_back_rect: ColorRect
var _rays_back_mat: ShaderMaterial
var _fog_mid_rect: ColorRect
var _fog_mid_mat: ShaderMaterial
var _rain_far_rect: ColorRect
var _rain_far_mat: ShaderMaterial
var _rain_near_rect: ColorRect
var _rain_near_mat: ShaderMaterial
var _shockwave_layer: CanvasLayer
var _shockwave_rect: ColorRect
var _shockwave_mat: ShaderMaterial

var _tile_s1_spr: Sprite2D
var _tile_s2_spr: Sprite2D
var _tile_s3_spr: Sprite2D
var _backdrop_dof_node: Node2D
var _backdrop_dof_mat: ShaderMaterial
var _mirror_quad: Node2D
var _ground_mist_embers: Node2D
var _interactive_rain_node: Node2D
var _fg_layer: CanvasLayer
var _fg_left_spr: Sprite2D
var _fg_right_spr: Sprite2D
var _fg_chain_left_tex: Texture2D
var _fg_chain_right_tex: Texture2D

var _suspended_drops: Array[Dictionary] = []
var _rain_ripples: Array[Dictionary] = []
var _debris: Array[Dictionary] = []
var _embers: Array[Dictionary] = []
var _fg_chains: Array[Dictionary] = []


func _load_tex(path: String) -> Texture2D:
	var gpath := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(gpath):
		var img := Image.load_from_file(gpath)
		if img != null and not img.is_empty():
			return ImageTexture.create_from_image(img)
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


func _make_ctex(diff_path: String, norm_path: String, spec_col: Color, shine: float) -> CanvasTexture:
	var d := _load_tex(diff_path)
	if d == null:
		return null
	var n := _load_tex(norm_path)
	var ct := CanvasTexture.new()
	ct.diffuse_texture = d
	ct.normal_texture = n
	ct.specular_color = spec_col
	ct.specular_shininess = shine
	return ct


func _make_radial_light_tex(sz: int = 256) -> ImageTexture:
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var c := float(sz - 1) * 0.5
	for y in sz:
		for x in sz:
			var r := Vector2(float(x) - c, float(y) - c).length() / c
			var v := pow(clampf(1.0 - r, 0.0, 1.0), 2.1)
			img.set_pixel(x, y, Color(v, v, v, v))
	return ImageTexture.create_from_image(img)


func has_hd_arena_art() -> bool:
	return _ctex_s1 != null and _ctex_s2 != null and _ctex_s3 != null and _ctex_belfry_m1 != null and clock_rig != null


func _flicker(x: float) -> float:
	return 0.92 + 0.08 * sin(_time * 8.1 + x * 0.017) * cos(_time * 13.3 + x * 0.009)


func moon_screen() -> Vector2:
	return Vector2(640.0, -40000.0)


func lantern_light(p: Vector2) -> Vector3:
	var best := Vector3.ZERO
	var all_lights: Array = []
	for l in _lamps:
		all_lights.append(l.p)
	if deck_3d != null:
		for lp in deck_3d.lamp_world:
			all_lights.append(lp)
	for lp: Vector2 in all_lights:
		var d: Vector2 = lp - p
		var dist := d.length()
		var w := clampf(1.0 - dist / 390.0, 0.0, 1.0)
		w = w * w * (3.0 - 2.0 * w) * _flicker(lp.x)
		if w > best.x:
			var dir := d / maxf(dist, 0.001)
			best = Vector3(w, dir.x, dir.y)
	return best


func _ready() -> void:
	z_index = -80
	var gmeta := ProjectSettings.globalize_path(STAGE_META_PATH)
	if FileAccess.file_exists(gmeta):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(gmeta))
		if parsed is Dictionary:
			_stage_meta = parsed
			var m1m: Dictionary = _stage_meta.get("belfry_m1", {})
			var hc: Array = m1m.get("hole_center_px", [765.0, 503.0])
			if hc.size() >= 2:
				_m1_hole_center_px = Vector2(float(hc[0]), float(hc[1]))
			_m1_hole_radius_px = float(m1m.get("hole_radius_px", 272.5))

	# Z0: 最底层夜空暗底兜底
	_sky_layer = CanvasLayer.new()
	_sky_layer.layer = -25
	var bg_rect := ColorRect.new()
	bg_rect.color = Color(0.022, 0.028, 0.044, 1.0)
	bg_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sky_layer.add_child(bg_rect)
	add_child(_sky_layer)

	# Z1 (-32): 优先加载 v5 独立远景暴雨夜空+哥特城郭层（0.06x 视差三联无缝平铺）；否则退回旧 S4
	var v5_dir := STAGE_DIR + "v5_layers/"
	_far_sky_tex = _load_tex(v5_dir + "L0_storm_sky_spires.png")
	if _far_sky_tex == null:
		_far_sky_tex = _load_tex(STAGE_DIR + "sky_abyss_far.png")
	if _far_sky_tex != null:
		for i in 3:
			var fs := Sprite2D.new()
			fs.name = "FarAbyssSky_%d" % i
			fs.centered = false
			fs.z_as_relative = false
			fs.z_index = -32
			fs.light_mask = 0
			fs.texture = _far_sky_tex
			add_child(fs)
			_far_sky_sprites.append(fs)

	# Z1.5 (-28): M2 母钟楼两翼维多利亚-哥特远塔群与长飞扶壁剪影（0.16x 视差四联无缝平铺）
	_mid_tower_tex = _load_tex(STAGE_DIR + "mid_distant_towers.png")
	if _mid_tower_tex != null:
		for i in 4:
			var ms := Sprite2D.new()
			ms.name = "MidDistantTowers_%d" % i
			ms.centered = false
			ms.z_as_relative = false
			ms.z_index = -28
			ms.light_mask = 0
			ms.texture = _mid_tower_tex
			add_child(ms)
			_mid_tower_sprites.append(ms)

	# 屏幕空间远景光学大气层（远雨幕 + 冷灰蓝空气透视流雾）
	var back_fx_layer := CanvasLayer.new()
	back_fx_layer.name = "BackOpticalAtmosphere"
	back_fx_layer.layer = -15
	add_child(back_fx_layer)

	_rain_far_rect = ColorRect.new()
	_rain_far_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rain_far_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rf_sh := Shader.new()
	rf_sh.code = REVERSIBLE_RAIN_SHADER
	_rain_far_mat = ShaderMaterial.new()
	_rain_far_mat.shader = rf_sh
	_rain_far_mat.set_shader_parameter("k", 0.25)
	_rain_far_mat.set_shader_parameter("cell", 8.0)
	_rain_far_mat.set_shader_parameter("density", 0.28)
	_rain_far_mat.set_shader_parameter("seg", 44.0)
	_rain_far_mat.set_shader_parameter("alpha", 0.09)
	_rain_far_rect.material = _rain_far_mat
	back_fx_layer.add_child(_rain_far_rect)

	var noise := NoiseTexture2D.new()
	noise.seamless = true
	noise.width = 256
	noise.height = 256
	var fn := FastNoiseLite.new()
	fn.frequency = 0.011
	fn.fractal_octaves = 4
	noise.noise = fn

	_fog_mid_rect = ColorRect.new()
	_fog_mid_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fog_mid_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fog_mid_mat = ShaderMaterial.new()
	_fog_mid_mat.shader = LayerFogShader
	_fog_mid_mat.set_shader_parameter("n", noise)
	_fog_mid_mat.set_shader_parameter("col", Color(0.09, 0.12, 0.19, 1.0))
	_fog_mid_mat.set_shader_parameter("k", 0.36)
	_fog_mid_mat.set_shader_parameter("spd", 0.014)
	_fog_mid_mat.set_shader_parameter("y0", 0.36)
	_fog_mid_mat.set_shader_parameter("y1", 0.96)
	_fog_mid_mat.set_shader_parameter("strength", 0.22)
	back_fx_layer.add_child(_fog_mid_rect)

	# Z2 (-21): 核心【5:59 暗血珀磨砂母钟 7 层动态总成】（其二阶段碎红玻璃 z=-18、火花 z=-17 自动跃出石拱腔体前方）
	clock_rig = CrimsonClockRig.new()
	clock_rig.name = "CrimsonMotherClockRig"
	clock_rig.z_as_relative = false
	clock_rig.z_index = -21
	add_child(clock_rig)
	clock_rig.jam_shockwave_fired.connect(_on_clock_shockwave)
	_clock_mat = clock_rig._glass_mat

	# Z2.2 (-20): 优先加载 v5 真多层独立视差【暗黑哥特巨型母钟塔 + 3 组真实对转黑铁巨齿轮 + 纯净彩窗零过曝模式】
	var v5_meta_path := v5_dir + "v5_meta.json"
	if FileAccess.file_exists(v5_meta_path):
		var v5_parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(v5_meta_path))
		if v5_parsed is Dictionary:
			var v5_ct := _make_ctex(
				v5_dir + "L2_mother_tower.png",
				v5_dir + "L2_mother_tower_n.png",
				Color(0.72, 0.78, 0.88),
				0.34
			)
			if v5_ct != null:
				_ctex_belfry_m1 = v5_ct
				_using_v5_stage = true
				_using_v4_stage = true
				var dc: Array = v5_parsed.get("dial_center_px", [840.0, 403.0])
				if dc.size() >= 2:
					_m1_hole_center_px = Vector2(float(dc[0]), float(dc[1]))
				_m1_hole_radius_px = float(v5_parsed.get("dial_radius_px", 292.5))

	if _ctex_belfry_m1 == null:
		var v4_meta_path := STAGE_DIR + "v4_stage_meta.json"
		if FileAccess.file_exists(v4_meta_path):
			var v4_parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(v4_meta_path))
			if v4_parsed is Dictionary:
				var v4_ct := _make_ctex(
					STAGE_DIR + "v4_belfry_tower.png",
					STAGE_DIR + "v4_belfry_tower_n.png",
					Color(0.84, 0.34, 0.30),
					0.38
				)
				if v4_ct != null:
					_ctex_belfry_m1 = v4_ct
					_using_v4_stage = true
					var hc: Array = v4_parsed.get("hole_center_px", [1168.0, 284.5])
					if hc.size() >= 2:
						_m1_hole_center_px = Vector2(float(hc[0]), float(hc[1]))
					_m1_hole_radius_px = float(v4_parsed.get("hole_radius_px", 204.0))
					_v4_bridge_y_px = float(v4_parsed.get("bridge_y_px", 768.0))
	if _ctex_belfry_m1 == null:
		_ctex_belfry_m1 = _make_ctex(
			STAGE_DIR + "belfry_arch_frame.png",
			STAGE_DIR + "belfry_arch_frame_n.png",
			Color(0.76, 0.36, 0.32),
			0.42
		)

	if _using_v5_stage:
		for ms in _mid_tower_sprites:
			ms.visible = false
		# L1 (-22): 3 组独立真实咬合对转的哥特黑铁巨型齿轮（藏于母钟塔两翼背后，常态慢转、蓄力/倒流加速逆旋）
		_v5_gear_tex = _load_tex(v5_dir + "L2_gothic_gear.png")
		if _v5_gear_tex != null:
			_v5_gear_cfgs = [
				{"off": Vector2(-335.0, -45.0), "diam": 440.0, "spd": 0.085, "mod": Color(0.56, 0.62, 0.72, 0.94)},
				{"off": Vector2(345.0, 55.0), "diam": 490.0, "spd": -0.072, "mod": Color(0.52, 0.58, 0.68, 0.92)},
				{"off": Vector2(-215.0, 175.0), "diam": 320.0, "spd": -0.115, "mod": Color(0.46, 0.52, 0.62, 0.88)},
			]
			for gi in _v5_gear_cfgs.size():
				var gcfg: Dictionary = _v5_gear_cfgs[gi]
				var gsp := Sprite2D.new()
				gsp.name = "V5GothicGear_%d" % gi
				gsp.texture = _v5_gear_tex
				gsp.centered = true
				gsp.z_as_relative = false
				gsp.z_index = -22
				gsp.light_mask = 0
				gsp.modulate = gcfg.mod
				gsp.scale = Vector2.ONE * (float(gcfg.diam) / maxf(float(_v5_gear_tex.get_width()), 1.0))
				add_child(gsp)
				_v5_gear_sprites.append(gsp)
		if clock_rig != null:
			clock_rig.z_index = -18
			clock_rig.set_overlay_only_mode(true)
			var dial_scale := (_m1_hole_radius_px * _v5_tower_scale) / CLOCK_RADIUS
			clock_rig.scale = Vector2(dial_scale, dial_scale)
	elif _using_v4_stage:
		for ms in _mid_tower_sprites:
			ms.visible = false
		if clock_rig != null:
			var dial_scale := (_m1_hole_radius_px * _v4_scale + 4.5) / CLOCK_RADIUS
			clock_rig.scale = Vector2(dial_scale, dial_scale)

	if _ctex_belfry_m1 != null:
		_belfry_m1_spr = Sprite2D.new()
		_belfry_m1_spr.name = "MotherBelfryArchFrame_M1"
		_belfry_m1_spr.centered = false
		_belfry_m1_spr.z_as_relative = false
		_belfry_m1_spr.z_index = -20 if _using_v5_stage else -19
		_belfry_m1_spr.light_mask = 0 if _using_v5_stage else 1
		_belfry_m1_spr.texture = _ctex_belfry_m1
		add_child(_belfry_m1_spr)

	# L3 (-15): 桥后峡谷冷雾隔离带（专门拉开桥面与母钟塔百米纵深，同时为角色提供低对比度舞台剪影幕布）
	if _using_v5_stage:
		_canyon_mist_node = Node2D.new()
		_canyon_mist_node.name = "V5CanyonMistVeil"
		_canyon_mist_node.z_as_relative = false
		_canyon_mist_node.z_index = -15
		_canyon_mist_node.draw.connect(_draw_v5_canyon_mist)
		add_child(_canyon_mist_node)

	# Z3 (CanvasLayer 2): 60° 暗朱红×冷银琴弦体积斜光栅层 + 近景雨幕
	var rays_layer := CanvasLayer.new()
	rays_layer.name = "CrimsonVolumetricRaysLayer"
	rays_layer.layer = 2
	add_child(rays_layer)
	_rays_back_rect = ColorRect.new()
	_rays_back_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rays_back_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gr_sh := Shader.new()
	gr_sh.code = VOLUMETRIC_GODRAYS_SHADER
	_rays_back_mat = ShaderMaterial.new()
	_rays_back_mat.shader = gr_sh
	_rays_back_rect.material = _rays_back_mat
	rays_layer.add_child(_rays_back_rect)

	_rain_near_rect = ColorRect.new()
	_rain_near_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rain_near_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rn_sh := Shader.new()
	rn_sh.code = REVERSIBLE_RAIN_SHADER
	_rain_near_mat = ShaderMaterial.new()
	_rain_near_mat.shader = rn_sh
	_rain_near_mat.set_shader_parameter("k", 0.85)
	_rain_near_mat.set_shader_parameter("cell", 13.0)
	_rain_near_mat.set_shader_parameter("density", 0.25)
	_rain_near_mat.set_shader_parameter("seg", 78.0)
	_rain_near_mat.set_shader_parameter("alpha", 0.13)
	_rain_near_rect.material = _rain_near_mat
	rays_layer.add_child(_rain_near_rect)

	# Z3.5 (-14): 动态空气透视景深柔化与冷雾压暗层（位于母钟与 M1 巨塔之上、3D 实体桥面与人物之下！）
	_backdrop_dof_node = Node2D.new()
	_backdrop_dof_node.name = "BackdropDepthFogSeparation"
	_backdrop_dof_node.z_as_relative = false
	_backdrop_dof_node.z_index = -14
	var dof_sh := Shader.new()
	dof_sh.code = BACKDROP_DEPTH_FOG_SHADER
	_backdrop_dof_mat = ShaderMaterial.new()
	_backdrop_dof_mat.shader = dof_sh
	_backdrop_dof_node.material = _backdrop_dof_mat
	_backdrop_dof_node.draw.connect(_draw_backdrop_dof)
	_backdrop_dof_node.visible = not _using_v4_stage
	add_child(_backdrop_dof_node)

	# Z4 (-12): SubViewport 真透视 3D 实体湿石板决斗桥（桥面石板、双层错位尖拱洞、石座铁栏、哥特六棱煤气灯）
	deck_3d = Deck3D.new()
	deck_3d.name = "SkybridgeDeck3D"
	add_child(deck_3d)

	# Z5 (-11): 两翼手绘上层哥特塔楼与真石阶（底部柔和融入 3D 石板顶面；保留 _ctex_s2/_ctex_p1 兼容测试）
	var spec_col := Color(0.86, 0.56, 0.54)
	_ctex_s1 = _make_ctex(STAGE_DIR + "wing_s1_left_3d.png", STAGE_DIR + "wing_s1_left_3d_n.png", spec_col, 0.50)
	_ctex_s2 = _make_ctex(STAGE_DIR + "tile_s2_center.png", STAGE_DIR + "tile_s2_center_n.png", spec_col, 0.56)
	_ctex_s3 = _make_ctex(STAGE_DIR + "wing_s3_right_3d.png", STAGE_DIR + "wing_s3_right_3d_n.png", spec_col, 0.50)
	_ctex_p1 = _ctex_s2

	if _ctex_s1 != null:
		_tile_s1_spr = Sprite2D.new()
		_tile_s1_spr.name = "SkybridgeLeftWing_S1"
		_tile_s1_spr.centered = false
		_tile_s1_spr.z_as_relative = false
		_tile_s1_spr.z_index = -11
		_tile_s1_spr.texture = _ctex_s1
		_tile_s1_spr.visible = not _using_v5_stage
		add_child(_tile_s1_spr)

	if _ctex_s3 != null:
		_tile_s3_spr = Sprite2D.new()
		_tile_s3_spr.name = "SkybridgeRightWing_S3"
		_tile_s3_spr.centered = false
		_tile_s3_spr.z_as_relative = false
		_tile_s3_spr.z_index = -11
		_tile_s3_spr.texture = _ctex_s3
		_tile_s3_spr.visible = not _using_v5_stage
		add_child(_tile_s3_spr)

	# 无头模式下若 Deck3D 静默跳过，则保留 _tile_s2_spr 兜底；原生渲染下隐藏 2D 中桥，100% 交给真 3D 实体桥面呈现！
	if _ctex_s2 != null:
		_tile_s2_spr = Sprite2D.new()
		_tile_s2_spr.name = "SkybridgeCenterDuel_S2_Fallback"
		_tile_s2_spr.centered = false
		_tile_s2_spr.z_as_relative = false
		_tile_s2_spr.z_index = -11
		_tile_s2_spr.texture = _ctex_s2
		_tile_s2_spr.visible = DisplayServer.get_name() == "headless"
		add_child(_tile_s2_spr)

	# 实时 2D 法线战斗光源组（照亮两翼手绘石阶、M1 石拱巨框与母钟铁窗花）
	var light_tex := _make_radial_light_tex(256)
	for i in 2:
		var wl := PointLight2D.new()
		wl.name = "WingGasLampLight_%d" % i
		wl.texture = light_tex
		wl.texture_scale = 3.2
		wl.color = Color(1.0, 0.88, 0.66)
		wl.energy = 0.65
		wl.height = 95.0
		add_child(wl)
		_wing_lamp_lights.append(wl)

	_player_light = PointLight2D.new()
	_player_light.name = "PlayerBladePurpleNormalLight"
	_player_light.texture = light_tex
	_player_light.texture_scale = 3.8
	_player_light.color = Color(0.76, 0.30, 1.0)
	_player_light.energy = 0.25
	_player_light.height = 85.0
	add_child(_player_light)

	_clash_light = PointLight2D.new()
	_clash_light.name = "ClashBurstNormalLight"
	_clash_light.texture = light_tex
	_clash_light.texture_scale = 5.4
	_clash_light.color = Color(0.98, 0.32, 0.26)
	_clash_light.energy = 0.0
	_clash_light.height = 115.0
	add_child(_clash_light)

	# Z5.5 (-5): 3D 湿石板表层薄水膜实时倒影（把上方 2D 母钟红光与主角刀光叠映入中央桥面石缝）
	_mirror_quad = Node2D.new()
	_mirror_quad.name = "WetSlateThinMirror"
	_mirror_quad.z_as_relative = false
	_mirror_quad.z_index = -5
	var m_sh := Shader.new()
	m_sh.code = WET_SLATE_MIRROR_SHADER
	_mirror_mat = ShaderMaterial.new()
	_mirror_mat.shader = m_sh
	_mirror_mat.set_shader_parameter("noise_tex", noise)
	_mirror_mat.set_shader_parameter("floor_line_y", floor_y)
	_mirror_quad.material = _mirror_mat
	_mirror_quad.draw.connect(_draw_wet_slate_mirror)
	add_child(_mirror_quad)

	# Z5.8 (-4): 贴地流动湿冷雨雾 + 85 颗中景斜飘余烬火星（补齐商业级前中后景大气粒子层次！）
	_ground_mist_embers = Node2D.new()
	_ground_mist_embers.name = "GroundMistAndEmbers"
	_ground_mist_embers.z_as_relative = false
	_ground_mist_embers.z_index = -4
	_ground_mist_embers.draw.connect(_draw_ground_mist_and_embers)
	add_child(_ground_mist_embers)

	# Z6 (+15): 刀锋可斩落的交互悬雨凝珠、落地涟漪与击柱碎石
	_interactive_rain_node = Node2D.new()
	_interactive_rain_node.name = "InteractiveRainAndDebris"
	_interactive_rain_node.z_as_relative = false
	_interactive_rain_node.z_index = 15
	_interactive_rain_node.draw.connect(_draw_interactive_rain)
	add_child(_interactive_rain_node)

	# Z7 (CanvasLayer 4): F1 电影级浅景深光学虚焦重型铸铁钟链与哥特尖拱残角（贴左右画框外缘 + 镜头视差阻尼摆动，0% 垂直切边！）
	_fg_chain_left_tex = _load_tex(STAGE_DIR + "fg_chain_left.png")
	_fg_chain_right_tex = _load_tex(STAGE_DIR + "fg_chain_right.png")
	_fg_layer = CanvasLayer.new()
	_fg_layer.name = "ForegroundBokehChainsLayer_F1"
	_fg_layer.layer = 4
	add_child(_fg_layer)
	if _fg_chain_left_tex != null:
		_fg_left_spr = Sprite2D.new()
		_fg_left_spr.name = "FgBokehLeft"
		_fg_left_spr.texture = _fg_chain_left_tex
		_fg_left_spr.centered = false
		_fg_left_spr.light_mask = 0
		_fg_left_spr.visible = not _using_v4_stage
		_fg_layer.add_child(_fg_left_spr)
	if _fg_chain_right_tex != null:
		_fg_right_spr = Sprite2D.new()
		_fg_right_spr.name = "FgBokehRight"
		_fg_right_spr.texture = _fg_chain_right_tex
		_fg_right_spr.centered = false
		_fg_right_spr.light_mask = 0
		_fg_right_spr.visible = not _using_v4_stage
		_fg_layer.add_child(_fg_right_spr)

	# Z8 (CanvasLayer 6): 全屏光学折射时间冲击波与倒流红玻璃暗角
	_shockwave_layer = CanvasLayer.new()
	_shockwave_layer.name = "TemporalShockwaveLayer"
	_shockwave_layer.layer = 6
	add_child(_shockwave_layer)
	_shockwave_rect = ColorRect.new()
	_shockwave_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shockwave_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sw_sh := Shader.new()
	sw_sh.code = TEMPORAL_SHOCKWAVE_SHADER
	_shockwave_mat = ShaderMaterial.new()
	_shockwave_mat.shader = sw_sh
	_shockwave_rect.material = _shockwave_mat
	_shockwave_layer.visible = not _using_v5_stage
	_shockwave_layer.add_child(_shockwave_rect)

	configure_duel_arena(first_x, fight_half)


func configure_duel_arena(center_x: float, half_w: float) -> void:
	section_center = center_x
	fight_half = half_w

	var x_left := center_x - ARENA_TILE_SPAN * 0.5
	var k := SINGLE_TILE_W / 1536.0

	if deck_3d != null:
		deck_3d.configure(center_x, floor_y, half_w + 350.0)

	if _tile_s1_spr != null:
		var g1 := float(_stage_meta.get("tiles", {}).get("s1_left", {}).get("ground_px", 884.0))
		_tile_s1_spr.scale = Vector2(k, k)
		_tile_s1_spr.position = Vector2(x_left, floor_y - g1 * k)

	if _tile_s2_spr != null:
		var g2 := float(_stage_meta.get("tiles", {}).get("s2_center", {}).get("ground_px", 742.0))
		_tile_s2_spr.scale = Vector2((SINGLE_TILE_W + 4.0) / 1536.0, k)
		_tile_s2_spr.position = Vector2(x_left + SINGLE_TILE_W - 2.0, floor_y - g2 * k)

	if _tile_s3_spr != null:
		var g3 := float(_stage_meta.get("tiles", {}).get("s3_right", {}).get("ground_px", 824.0))
		_tile_s3_spr.scale = Vector2(k, k)
		_tile_s3_spr.position = Vector2(x_left + SINGLE_TILE_W * 2.0, floor_y - g3 * k)

	var lamp_l_pos := Vector2(x_left + 416.0 * k, (floor_y - 884.0 * k) + 684.0 * k)
	var lamp_r_pos := Vector2(x_left + SINGLE_TILE_W * 2.0 + 909.0 * k, (floor_y - 824.0 * k) + 652.5 * k)
	_lamps = [
		{"p": lamp_l_pos, "base": Vector2(lamp_l_pos.x, floor_y), "street": false, "art": true},
		{"p": lamp_r_pos, "base": Vector2(lamp_r_pos.x, floor_y), "street": false, "art": true},
	]
	if _wing_lamp_lights.size() >= 2:
		_wing_lamp_lights[0].position = lamp_l_pos
		_wing_lamp_lights[1].position = lamp_r_pos

	var clock_base_y := floor_y - 438.0 if _using_v5_stage else (floor_y - (_v4_bridge_y_px - _m1_hole_center_px.y) * _v4_scale if _using_v4_stage else (floor_y + CLOCK_BASE_OFFSET_Y))
	var clock_pos := Vector2(center_x, clock_base_y)
	if clock_rig != null:
		clock_rig.position = clock_pos
	_sync_belfry_m1(clock_pos)

	_init_interactive_rain()
	_init_embers()
	_init_fg_chains()


func _init_embers() -> void:
	_embers.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261118
	for _i in 85:
		_embers.append({
			"pos": Vector2(
				section_center + rng.randf_range(-fight_half, fight_half),
				floor_y - rng.randf_range(12.0, 620.0)
			),
			"vx": rng.randf_range(-42.0, -14.0),
			"vy": rng.randf_range(-34.0, -10.0),
			"r": rng.randf_range(1.4, 3.2),
			"phase": rng.randf_range(0.0, TAU),
			"warm": rng.randf() < 0.48,
		})


func _sync_belfry_m1(clock_world_pos: Vector2) -> void:
	if _belfry_m1_spr == null:
		return
	var s_m1 := _v5_tower_scale if _using_v5_stage else (_v4_scale if _using_v4_stage else (BELFRY_HOLE_WORLD_R / maxf(_m1_hole_radius_px, 1.0)))
	_belfry_m1_spr.scale = Vector2(s_m1, s_m1)
	_belfry_m1_spr.position = clock_world_pos - _m1_hole_center_px * s_m1
	if _using_v5_stage:
		for gi in _v5_gear_sprites.size():
			var gsp := _v5_gear_sprites[gi]
			var gcfg: Dictionary = _v5_gear_cfgs[gi]
			gsp.position = clock_world_pos + Vector2(gcfg.off) * s_m1
			gsp.rotation = _v5_gear_phase * float(gcfg.spd)


func _init_interactive_rain() -> void:
	_suspended_drops.clear()
	_rain_ripples.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261117
	for _i in 190:
		_suspended_drops.append({
			"pos": Vector2(
				section_center + rng.randf_range(-fight_half - 140.0, fight_half + 140.0),
				floor_y - rng.randf_range(35.0, 680.0)
			),
			"r": rng.randf_range(1.6, 3.4),
			"vel": Vector2.ZERO,
			"state": DropState.SUSPENDED,
			"alpha": rng.randf_range(0.45, 0.85),
			"phase": rng.randf_range(0.0, TAU),
			"respawn": 0.0,
		})


func _init_fg_chains() -> void:
	_fg_chains.clear()
	var sc := 0.78
	if _fg_left_spr != null:
		_fg_left_spr.scale = Vector2(sc, sc)
		_fg_left_spr.position = Vector2(-58.0, -14.0)
	if _fg_right_spr != null and _fg_chain_right_tex != null:
		_fg_right_spr.scale = Vector2(sc, sc)
		var w := float(_fg_chain_right_tex.get_width()) * sc
		_fg_right_spr.position = Vector2(1280.0 - w + 58.0, -14.0)


func _on_clock_shockwave(world_origin: Vector2, strength: float, crimson_boost: float) -> void:
	_wave_origin_world = world_origin
	_wave_radius = 0.04
	_wave_strength = maxf(_wave_strength, strength)
	_wave_crimson = crimson_boost
	_fg_jolt = maxf(_fg_jolt, strength * 0.85)


func reset_phase() -> void:
	phase2_cracked = false
	crack_amount = 0.0
	eclipse_dim = 0.0
	_eclipse_target = 0.0
	rewind_visual_amt = 0.0
	_rewind_target = 0.0
	victory_dawn = false
	_pillar_glow_l = 0.0
	_pillar_glow_r = 0.0
	_pillar_shake_l = 0.0
	_pillar_shake_r = 0.0
	_wave_strength = 0.0
	_fg_jolt = 0.0
	if clock_rig != null:
		clock_rig.set_clock_state(CrimsonClockRig.ClockState.JAMMED_559, true)
	_init_interactive_rain()


func get_clock_angles() -> Vector2:
	if clock_rig != null:
		return Vector2(clock_rig.hour_angle, clock_rig.minute_angle)
	return Vector2(CrimsonClockRig.HOUR_ANGLE_559, CrimsonClockRig.MINUTE_ANGLE_559)


func trigger_phase2_shatter() -> void:
	phase2_cracked = true
	crack_amount = 1.0
	if clock_rig != null:
		clock_rig.set_clock_state(CrimsonClockRig.ClockState.SHATTERED_ORBIT)
	pulse_normal_light(Vector2(section_center, floor_y - 260.0), Color(1.0, 0.24, 0.16), 3.2, 8.5)


func trigger_victory_dawn() -> void:
	victory_dawn = true
	_rewind_target = 0.0
	if clock_rig != null:
		clock_rig.set_clock_state(CrimsonClockRig.ClockState.CLEAVED_600)
	pulse_normal_light(Vector2(section_center, floor_y - 280.0), Color(0.86, 0.92, 1.0), 2.8, 7.5)


func set_rewind_visual(amt: float) -> void:
	_rewind_target = clampf(amt, 0.0, 1.0)
	if clock_rig != null:
		if _rewind_target > 0.25 and clock_rig.state != CrimsonClockRig.ClockState.REWIND_OVERDRIVE:
			clock_rig.set_clock_state(CrimsonClockRig.ClockState.REWIND_OVERDRIVE)
		elif _rewind_target <= 0.08 and clock_rig.state == CrimsonClockRig.ClockState.REWIND_OVERDRIVE:
			clock_rig.set_clock_state(
				CrimsonClockRig.ClockState.SHATTERED_ORBIT if phase2_cracked else CrimsonClockRig.ClockState.JAMMED_559
			)


func set_eclipse_dim(want: float) -> void:
	_eclipse_target = clampf(want, 0.0, 1.0)


func set_boss_red_telegraph(amt: float) -> void:
	_boss_red_dim = clampf(amt, 0.0, 1.0)
	if amt > 0.35 and clock_rig != null:
		clock_rig.trigger_boss_cue("windup", amt)
		_clock_cue_boost = maxf(_clock_cue_boost, amt * 0.85)


func notify_boss_clock_cue(cue: String, world_pos: Vector2, intensity: float = 1.0) -> void:
	var k := clampf(intensity, 0.35, 1.8)
	_clock_cue_boost = maxf(_clock_cue_boost, k)
	if clock_rig != null:
		clock_rig.trigger_boss_cue(cue, k)
	match cue:
		"windup":
			pulse_normal_light(world_pos + Vector2(0.0, -90.0), Color(0.95, 0.22, 0.16), 1.65 * k, 5.2)
		"impact", "clash":
			pulse_normal_light(world_pos + Vector2(0.0, -70.0), Color(1.0, 0.30, 0.22), 2.55 * k, 6.4)
		"burst":
			pulse_normal_light(world_pos + Vector2(0.0, -140.0), Color(1.0, 0.24, 0.16), 3.35 * k, 8.6)


func set_ult_silhouette_mode(on: bool) -> void:
	_ult_mode = on
	if _shockwave_layer != null:
		_shockwave_layer.visible = not on
	if _fg_layer != null:
		_fg_layer.visible = not on


func pulse_normal_light(world_pos: Vector2, col: Color, energy: float = 2.0, scale_mul: float = 5.2) -> void:
	if _clash_light == null:
		return
	_clash_light.position = world_pos
	_clash_light.color = col
	_clash_light.texture_scale = scale_mul
	_clash_light_energy = maxf(_clash_light_energy, energy)
	_clash_light.energy = _clash_light_energy
	if deck_3d != null:
		deck_3d.set_clash(world_pos, col, energy * 1.15)


func update_combat_lights(player_pos: Vector2, player_slashing: bool, _boss_pos: Vector2, _boss_active: bool) -> void:
	var light_pt := player_pos + Vector2(0.0, -56.0)
	if _player_light != null:
		_player_light.position = light_pt
		var target_e := 1.55 if player_slashing else 0.24
		_player_light.energy = lerpf(_player_light.energy, target_e, 0.35)
		if deck_3d != null:
			deck_3d.set_blade(light_pt, _player_light.energy * 1.45 if player_slashing else 0.28)


func notify_pillar_impact(side: int, strength: float = 1.0) -> void:
	var s := clampf(strength, 0.4, 1.8)
	var hit_x := (section_center - fight_half + 40.0) if side < 0 else (section_center + fight_half - 40.0)
	if side < 0:
		_pillar_shake_l = maxf(_pillar_shake_l, 12.0 * s)
		_pillar_glow_l = maxf(_pillar_glow_l, 1.0)
	else:
		_pillar_shake_r = maxf(_pillar_shake_r, 12.0 * s)
		_pillar_glow_r = maxf(_pillar_glow_r, 1.0)
	pulse_normal_light(Vector2(hit_x, floor_y - 180.0), Color(0.96, 0.28, 0.20), 2.4 * s, 6.2)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(_time * 1000.0) + (17 if side < 0 else 53)
	var dir_x := 1.0 if side < 0 else -1.0
	for _i in 12:
		_debris.append({
			"pos": Vector2(hit_x, floor_y - rng.randf_range(70.0, 280.0)),
			"vel": Vector2(dir_x * rng.randf_range(120.0, 380.0), rng.randf_range(-320.0, -60.0)),
			"sz": rng.randf_range(4.0, 9.5),
			"life": rng.randf_range(0.45, 0.90),
			"max_life": 0.90,
		})


func slash_rain_at(world_center: Vector2, radius: float, slash_dir: Vector2 = Vector2.DOWN) -> int:
	var cut := 0
	var r2 := radius * radius
	var push := slash_dir.normalized() if slash_dir.length_squared() > 0.001 else Vector2.DOWN
	for d in _suspended_drops:
		if int(d.state) != DropState.SUSPENDED:
			continue
		var dp: Vector2 = d.pos - world_center
		if dp.length_squared() <= r2:
			d.state = DropState.FALLING
			d.vel = Vector2(push.x * 95.0 + dp.x * 0.22, maxf(180.0, push.y * 230.0 + 190.0))
			cut += 1
	slashed_rain_total += cut
	return cut


func count_falling_rain() -> int:
	var n := 0
	for d in _suspended_drops:
		if int(d.state) == DropState.FALLING:
			n += 1
	return n


func _world_to_screen_uv(world_pt: Vector2) -> Vector2:
	if camera == null:
		return Vector2(0.5, 0.35)
	var cam_c := camera.get_screen_center_position()
	var z := camera.zoom.x if camera.zoom.x > 0.001 else 0.65
	var scr := (world_pt - cam_c) * z + Vector2(640.0, 360.0)
	return Vector2(scr.x / 1280.0, scr.y / 720.0)


func _process(delta: float) -> void:
	var dt := clampf(delta, 0.0, 0.05)
	_time += dt
	eclipse_dim = move_toward(eclipse_dim, _eclipse_target, dt * 2.2)
	rewind_visual_amt = move_toward(rewind_visual_amt, _rewind_target, dt * 3.2)
	_pillar_shake_l = move_toward(_pillar_shake_l, 0.0, dt * 34.0)
	_pillar_shake_r = move_toward(_pillar_shake_r, 0.0, dt * 34.0)
	_pillar_glow_l = move_toward(_pillar_glow_l, 0.0, dt * 1.4)
	_pillar_glow_r = move_toward(_pillar_glow_r, 0.0, dt * 1.4)
	_fg_jolt = move_toward(_fg_jolt, 0.0, dt * 3.4)

	if _clash_light_energy > 0.0:
		_clash_light_energy = move_toward(_clash_light_energy, 0.0, dt * 7.2)
		if _clash_light != null:
			_clash_light.energy = _clash_light_energy
		if deck_3d != null and deck_3d.clash_light != null:
			deck_3d.clash_light.light_energy = _clash_light_energy * 1.15

	var cam_pos := Vector2(section_center, cam_ref)
	var z := 0.65
	if camera != null:
		cam_pos = camera.get_screen_center_position()
		if camera.zoom.x > 0.001:
			z = camera.zoom.x

	# 1. 更新 S4 远景云层与百米影街深渊视差平铺（0.10x）
	if _far_sky_tex != null and not _far_sky_sprites.is_empty():
		var view_h := 720.0 / z + 260.0
		var sk := view_h / maxf(float(_far_sky_tex.get_height()), 1.0)
		var sw := float(_far_sky_tex.get_width()) * sk
		var base_x := cam_pos.x - fposmod((cam_pos.x - section_center) * 0.10, sw) - sw * 1.5
		var top_y := cam_pos.y - view_h * 0.52
		for i in _far_sky_sprites.size():
			var fs := _far_sky_sprites[i]
			fs.scale = Vector2(sk, sk)
			fs.position = Vector2(base_x + float(i) * sw, top_y)

	# 1.5 更新 M2 母钟楼两翼远塔群与飞扶壁剪影（0.18x 视差四联无缝平铺）
	if _mid_tower_tex != null and not _mid_tower_sprites.is_empty():
		var mk := 1.12
		var mw := float(_mid_tower_tex.get_width()) * mk
		var m_base_x := cam_pos.x - fposmod((cam_pos.x - section_center) * MID_TOWER_PARALLAX_X, mw) - mw * 2.0
		var m_dy := (cam_pos.y - cam_ref) * (1.0 - MID_TOWER_PARALLAX_Y)
		var m_top_y := floor_y - 1085.0 * mk + m_dy
		for i in _mid_tower_sprites.size():
			var ms := _mid_tower_sprites[i]
			ms.scale = Vector2(mk, mk)
			ms.position = Vector2(m_base_x + float(i) * mw, m_top_y)

	# 2. 更新 5:59 暗血珀母钟与 v5/v4/M1 巨塔及独立黑铁巨齿轮同步视差
	_clock_cue_boost = move_toward(_clock_cue_boost, 0.0, dt * 2.1)
	var c_pulse: float = 0.35
	var c_rev: float = rewind_visual_amt
	var c_shat: float = crack_amount
	var c_dawn: float = 1.0 if victory_dawn else 0.0
	var gear_dir := lerpf(1.0 + _clock_cue_boost * 2.6, -4.2, c_rev)
	_v5_gear_phase += dt * gear_dir
	var clock_base_y := floor_y - 438.0 if _using_v5_stage else (floor_y - (_v4_bridge_y_px - _m1_hole_center_px.y) * _v4_scale if _using_v4_stage else (floor_y + CLOCK_BASE_OFFSET_Y))
	var clock_pos := Vector2(section_center, clock_base_y)
	if clock_rig != null:
		var px_k := 0.26 if _using_v5_stage else (0.24 if _using_v4_stage else CLOCK_PARALLAX_X)
		var py_k := 0.18 if _using_v5_stage else (0.14 if _using_v4_stage else CLOCK_PARALLAX_Y)
		var dx := (cam_pos.x - section_center) * (1.0 - px_k)
		var dy := (cam_pos.y - cam_ref) * (1.0 - py_k)
		clock_pos = Vector2(section_center + dx, clock_base_y + dy)
		clock_rig.position = clock_pos
		clock_rig.step_clock(dt)
		crack_amount = maxf(crack_amount if phase2_cracked else 0.0, clock_rig.crack_amt)
		c_pulse = clampf(clock_rig.pulse_val + _clock_cue_boost * 0.55, 0.0, 2.0)
		c_rev = clock_rig.rewind_amt
		c_shat = clock_rig.shatter_amt
		c_dawn = clock_rig.dawn_calm
	_sync_belfry_m1(clock_pos)
	if _canyon_mist_node != null:
		_canyon_mist_node.queue_redraw()

	# 3. 同步左右翼灯与 3D 实体桥面的实时母钟红光 / 哥特煤气路灯闪烁
	var f0 := _flicker(float(_lamps[0].p.x)) if _lamps.size() > 0 else 1.0
	var f1 := _flicker(float(_lamps[1].p.x)) if _lamps.size() > 1 else 1.0
	for i in _wing_lamp_lights.size():
		if i < _lamps.size():
			_wing_lamp_lights[i].energy = (0.35 if _using_v5_stage else 0.62) * _flicker(float(_lamps[i].p.x))
	if deck_3d != null:
		deck_3d.set_lamp_flicker([f0, f1])
		var crim_col := Color(0.88, 0.13, 0.10).lerp(Color(0.98, 0.26, 0.18), c_rev * 0.45).lerp(Color(0.72, 0.84, 0.98), c_dawn)
		var crim_e := (1.45 + 0.65 * c_pulse + 0.90 * c_rev + 0.40 * c_shat + 0.55 * _clock_cue_boost) if _using_v5_stage else (2.25 + 1.85 * c_pulse + 1.55 * c_rev + 0.75 * c_shat + 1.20 * _clock_cue_boost)
		crim_e *= (1.0 - 0.52 * c_dawn)
		deck_3d.set_crimson(clock_pos, crim_e, crim_col)

	# 4. 更新可逆雨幕与光学着色器参数
	var rain_dir := lerpf(1.0, -2.85, c_rev)
	_rain_scroll_far += dt * 420.0 * rain_dir
	_rain_scroll_near += dt * 860.0 * rain_dir

	var clock_uv := _world_to_screen_uv(clock_pos)
	if _rain_far_mat != null:
		_rain_far_mat.set_shader_parameter("cam_x", cam_pos.x)
		_rain_far_mat.set_shader_parameter("rain_scroll", _rain_scroll_far)
		_rain_far_mat.set_shader_parameter("clock_uv", clock_uv)
		_rain_far_mat.set_shader_parameter("crimson_lit", (0.50 + 0.42 * c_pulse) * (1.0 - c_dawn * 0.8))
		_rain_far_mat.set_shader_parameter("rewind_amt", c_rev)

	if _rain_near_mat != null:
		_rain_near_mat.set_shader_parameter("cam_x", cam_pos.x)
		_rain_near_mat.set_shader_parameter("rain_scroll", _rain_scroll_near)
		_rain_near_mat.set_shader_parameter("clock_uv", clock_uv)
		_rain_near_mat.set_shader_parameter("crimson_lit", (0.60 + 0.52 * c_pulse) * (1.0 - c_dawn * 0.8))
		_rain_near_mat.set_shader_parameter("rewind_amt", c_rev)

	if _fog_mid_mat != null:
		_fog_mid_mat.set_shader_parameter("cam_x", cam_pos.x)
		_fog_mid_mat.set_shader_parameter("t", _time)

	if _rays_back_mat != null and clock_rig != null:
		_rays_back_mat.set_shader_parameter("clock_uv", clock_uv)
		_rays_back_mat.set_shader_parameter("pulse", c_pulse)
		_rays_back_mat.set_shader_parameter("rewind_amt", c_rev)
		_rays_back_mat.set_shader_parameter("shatter_amt", c_shat)
		_rays_back_mat.set_shader_parameter("dawn_calm", c_dawn)
		_rays_back_mat.set_shader_parameter("gear_phase", clock_rig.gear_phase)
		_rays_back_mat.set_shader_parameter("minute_angle", clock_rig.minute_angle)
		_rays_back_mat.set_shader_parameter("time_sec", _time)

	if _mirror_mat != null:
		_mirror_mat.set_shader_parameter("crimson_boost", (0.42 + 0.52 * c_pulse + 0.45 * c_rev) * (1.0 - c_dawn * 0.8))

	# 4.5 更新背景景深柔化与冷雾压暗幕（常态让红钟退后二十米突出冷银首领与紫刀光，爆发高潮自动减雾爆亮！）
	if _backdrop_dof_mat != null:
		var drama := clampf(c_rev * 0.85 + c_shat * 0.72 + c_dawn * 0.78 + maxf(c_pulse - 0.82, 0.0) * 0.65, 0.0, 1.0)
		_backdrop_dof_mat.set_shader_parameter("blur_lod", lerpf(1.15, 0.22, drama))
		_backdrop_dof_mat.set_shader_parameter("dim_gain", lerpf(0.72, 0.98, drama))
		_backdrop_dof_mat.set_shader_parameter("fog_mix", lerpf(0.24, 0.08, drama))
		_backdrop_dof_mat.set_shader_parameter("time_sec", _time)

	# 5. 更新 F1 浅景深前景重型铸铁钟链（1.28x 前景视差 + 微风与 5:59 崩弹微震）
	_update_fg_chains(cam_pos, z)

	# 6. 更新全屏时间折射冲击波环
	if _wave_strength > 0.001:
		_wave_radius += dt * 1.65
		_wave_strength = move_toward(_wave_strength, 0.0, dt * 1.15)
	if _shockwave_mat != null:
		_shockwave_mat.set_shader_parameter("wave_center_uv", _world_to_screen_uv(_wave_origin_world))
		_shockwave_mat.set_shader_parameter("wave_radius", _wave_radius)
		_shockwave_mat.set_shader_parameter("wave_strength", _wave_strength)
		_shockwave_mat.set_shader_parameter("crimson_tint", _wave_crimson)
		_shockwave_mat.set_shader_parameter("rewind_vignette", c_rev)

	_step_interactive_rain_and_debris(dt, c_rev)
	_step_embers(dt, c_rev)
	if _backdrop_dof_node != null:
		_backdrop_dof_node.queue_redraw()
	_mirror_quad.queue_redraw()
	if _ground_mist_embers != null:
		_ground_mist_embers.queue_redraw()
	_interactive_rain_node.queue_redraw()


func _step_embers(dt: float, rev: float) -> void:
	var dir_mul := lerpf(1.0, -2.6, rev)
	var x_min := section_center - fight_half - 160.0
	var x_max := section_center + fight_half + 160.0
	for e in _embers:
		var p: Vector2 = e.pos
		var ph := float(e.phase)
		p.x += (float(e.vx) + sin(_time * 1.6 + ph) * 14.0) * dt * dir_mul
		p.y += float(e.vy) * dt * dir_mul
		if p.y < floor_y - 660.0:
			p.y = floor_y - 8.0
		elif p.y > floor_y - 4.0:
			p.y = floor_y - 640.0
		if p.x < x_min:
			p.x = x_max
		elif p.x > x_max:
			p.x = x_min
		e.pos = p


func _update_fg_chains(cam_c: Vector2, _z: float) -> void:
	if _ult_mode:
		return
	# 始终保证左束 x <= -12、右束右缘 >= 1292（100% 贴死画框外缘零切边），随镜头横移产生柔顺 1.28x 前景视差呼吸与 5:59 崩弹微震！
	var sc := 0.78
	var pan_t := clampf((cam_c.x - section_center) / maxf(fight_half, 1.0), -1.0, 1.0)
	var sway_l := sin(_time * 1.15) * 4.5 + sin(_time * 22.0) * 4.0 * _fg_jolt
	var sway_r := sin(_time * 1.15 + 1.7) * 4.5 - cos(_time * 21.0) * 4.0 * _fg_jolt
	var shift := -pan_t * 36.0
	if _fg_left_spr != null:
		var lx := clampf(-56.0 + shift + sway_l, -108.0, -10.0)
		_fg_left_spr.position = Vector2(lx, -16.0 - absf(pan_t) * 8.0)
	if _fg_right_spr != null and _fg_chain_right_tex != null:
		var rw := float(_fg_chain_right_tex.get_width()) * sc
		var rx := clampf(1280.0 - rw + 56.0 + shift + sway_r, 1280.0 - rw + 10.0, 1280.0 - rw + 108.0)
		_fg_right_spr.position = Vector2(rx, -16.0 - absf(pan_t) * 8.0)


func _step_interactive_rain_and_debris(dt: float, rev: float) -> void:
	for d in _suspended_drops:
		var st := int(d.state)
		if rev > 0.28:
			d.pos.y -= (240.0 + 360.0 * rev) * dt
			d.pos.x += 26.0 * rev * dt
			if float(d.pos.y) < floor_y - 720.0:
				d.pos.y = floor_y - 24.0
			continue
		if st == DropState.SUSPENDED:
			d.pos.y += sin(_time * 2.2 + float(d.phase)) * 5.0 * dt
		elif st == DropState.FALLING:
			d.vel.y += 1480.0 * dt
			d.pos += d.vel * dt
			if float(d.pos.y) >= floor_y:
				_rain_ripples.append({"x": float(d.pos.x), "age": 0.0, "max_age": 0.38})
				d.state = DropState.RESPAWNING
				d.respawn = 1.0
		elif st == DropState.RESPAWNING:
			d.respawn = float(d.respawn) - dt
			if float(d.respawn) <= 0.0:
				d.state = DropState.SUSPENDED
				d.pos.y = floor_y - 90.0 - fmod(absf(float(d.pos.x) * 1.37), 540.0)
				d.vel = Vector2.ZERO

	var nr: Array[Dictionary] = []
	for rp in _rain_ripples:
		rp.age = float(rp.age) + dt
		if float(rp.age) < float(rp.max_age):
			nr.append(rp)
	_rain_ripples = nr

	var nd: Array[Dictionary] = []
	for db in _debris:
		db.life = float(db.life) - dt
		if float(db.life) > 0.0:
			db.vel.y += 1260.0 * dt
			db.pos += db.vel * dt
			if float(db.pos.y) > floor_y:
				db.pos.y = floor_y
				db.vel.y *= -0.28
				db.vel.x *= 0.62
			nd.append(db)
	_debris = nd


func _draw_backdrop_dof() -> void:
	if _ult_mode:
		return
	var cam_c := camera.get_screen_center_position() if camera != null else Vector2(section_center, cam_ref)
	var z := camera.zoom.x if (camera != null and camera.zoom.x > 0.001) else 0.65
	var hw := 680.0 / z
	var hh := 400.0 / z
	_backdrop_dof_node.draw_rect(Rect2(cam_c.x - hw, cam_c.y - hh, hw * 2.0, hh * 2.0), Color.WHITE)


func _draw_wet_slate_mirror() -> void:
	# 仅在中央开阔 3D 石板桥段铺设薄积水反射层，不盖住两翼上坡石阶
	var x0 := section_center - 1680.0
	var x1 := section_center + 1390.0
	_mirror_quad.draw_rect(Rect2(x0, floor_y, x1 - x0, 36.0), Color.WHITE)


func _draw_ground_mist_and_embers() -> void:
	if _ult_mode:
		return
	var cam_c := camera.get_screen_center_position() if camera != null else Vector2(section_center, cam_ref)
	# 1. 贴地流动冷白湿冷雨雾带（软化 3D 桥面与背景过渡，增强夜雨湿润水汽感）
	var mist_x0 := maxf(section_center - fight_half, cam_c.x - 1100.0)
	var mist_x1 := minf(section_center + fight_half, cam_c.x + 1100.0)
	var step_w := 260.0
	var mx: float = floorf(mist_x0 / step_w) * step_w
	while mx < mist_x1 + step_w:
		var drift := fposmod(_time * 24.0, step_w)
		var px: float = mx - drift
		var pulse_a := 0.055 + 0.025 * sin(_time * 0.9 + mx * 0.01)
		_ground_mist_embers.draw_rect(
			Rect2(px, floor_y - 36.0, step_w * 1.35, 38.0),
			Color(0.56, 0.68, 0.86, pulse_a)
		)
		mx += step_w

	# 2. 中景 85 颗斜飘暗红/暖金微火星（时间倒流时同步拉出倒流拖尾！）
	var rev: float = clock_rig.rewind_amt if clock_rig != null else rewind_visual_amt
	var dawn: float = clock_rig.dawn_calm if clock_rig != null else (1.0 if victory_dawn else 0.0)
	for e in _embers:
		var p: Vector2 = e.pos
		if absf(p.x - cam_c.x) > 1050.0:
			continue
		var r := float(e.r)
		var tw := 0.55 + 0.45 * sin(_time * 4.8 + float(e.phase))
		var base_c := Color(1.0, 0.78, 0.46) if bool(e.warm) else Color(0.96, 0.28, 0.18)
		if dawn > 0.05:
			base_c = base_c.lerp(Color(0.84, 0.92, 1.0), dawn)
		var col := Color(base_c.r, base_c.g, base_c.b, 0.78 * tw)
		var tail := Vector2(float(e.vx), float(e.vy)) * (0.28 if rev > 0.25 else 0.14) * (-1.0 if rev > 0.25 else 1.0)
		_ground_mist_embers.draw_line(p - tail, p, Color(col.r, col.g, col.b, col.a * 0.55), maxf(1.2, r * 0.65), true)
		_ground_mist_embers.draw_circle(p, r, col)


func _draw_interactive_rain() -> void:
	if _ult_mode:
		return
	var rev: float = clock_rig.rewind_amt if clock_rig != null else rewind_visual_amt
	for d in _suspended_drops:
		var st := int(d.state)
		if st == DropState.RESPAWNING and rev <= 0.28:
			continue
		var p: Vector2 = d.pos
		var r := float(d.r)
		var a := float(d.alpha) * 0.65
		var col := Color(0.95, 0.34, 0.26, a) if rev > 0.28 else Color(0.76, 0.84, 0.96, a)
		if rev > 0.28:
			_interactive_rain_node.draw_line(p + Vector2(-2.2, r * 7.5), p - Vector2(-1.0, r * 2.0), col, maxf(1.2, r * 0.55), true)
		elif st == DropState.FALLING:
			var streak := clampf(float(d.vel.y) * 0.032, 6.0, 26.0)
			_interactive_rain_node.draw_line(p - Vector2(d.vel.x * 0.015, streak), p, Color(0.86, 0.92, 1.0, a * 1.15), maxf(1.3, r * 0.6), true)
		else:
			_interactive_rain_node.draw_circle(p, r * 0.82, col)

	for rp in _rain_ripples:
		var k := float(rp.age) / float(rp.max_age)
		var rx := lerpf(4.0, 28.0, k)
		_interactive_rain_node.draw_arc(Vector2(float(rp.x), floor_y + 2.0), rx, 0.0, TAU, 18, Color(0.86, 0.42, 0.38, (1.0 - k) * 0.45), 1.3)

	for db in _debris:
		var k := clampf(float(db.life) / float(db.max_life), 0.0, 1.0)
		var sz := float(db.sz)
		_interactive_rain_node.draw_rect(Rect2(Vector2(db.pos) - Vector2(sz * 0.5, sz * 0.5), Vector2(sz, sz)), Color(0.14, 0.16, 0.22, k))


func _draw_v5_canyon_mist() -> void:
	if _canyon_mist_node == null or not _using_v5_stage:
		return
	var x0 := section_center - fight_half - 600.0
	var w := (fight_half + 600.0) * 2.0
	# 低对比冷灰蓝峡谷雾带（floor_y - 230 .. floor_y + 20）：拉开桥面与母钟塔纵深，同时给前景角色提供干净剪影幕布
	for i in 12:
		var t := float(i) / 11.0
		var y_top := floor_y - 240.0 + t * 220.0
		var band_h := 28.0
		var alpha := sin(t * PI) * (0.24 + 0.04 * sin(_time * 0.65 + t * 3.1))
		_canyon_mist_node.draw_rect(Rect2(x0, y_top, w, band_h), Color(0.068, 0.092, 0.132, alpha))
	# 桥后紧贴石栏底部一层深邃冷暗影托底，防止塔基细节穿透铁栏干扰角色脚步
	_canyon_mist_node.draw_rect(Rect2(x0, floor_y - 42.0, w, 65.0), Color(0.032, 0.044, 0.068, 0.42))
