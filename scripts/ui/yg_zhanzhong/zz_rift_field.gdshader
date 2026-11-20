// [YG-MARK] 首页《斩钟》：赛璐璐干笔刀光裂口场（替代旧版 3x3 模糊拼缝 violet_field 与漫画网点）
// 世界空间沿 28° 斩缝实时计算像素级有向距离：
// - 斩缝近侧迸出硬边动画刀光色带与斜向干笔飞白尖刺（参考《C_墨与光》）；
// - 右下菜单区域沉入纯净高对比深色负空间，绝不糊字；
// - 原生接收四位女主主色（朔紫 / 萤青 / 薇红 / 曜金），切角色时零紫色残留。
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

uniform vec4 clip_plane = vec4(0.0);
uniform vec3 cut_origin = vec3(0.0);
uniform float plane_k = 1.4267;
uniform vec2 across_dir = vec2(0.8829476, -0.4694716);
uniform vec2 along_dir = vec2(0.4694716, 0.8829476);

uniform vec4 col_core : source_color = vec4(0.98, 0.96, 1.0, 1.0);
uniform vec4 col_bright : source_color = vec4(0.56, 0.36, 1.0, 1.0);
uniform vec4 col_mid : source_color = vec4(0.32, 0.14, 0.84, 1.0);
uniform vec4 col_deep : source_color = vec4(0.12, 0.05, 0.36, 1.0);
uniform vec4 col_abyss : source_color = vec4(0.042, 0.02, 0.12, 1.0);

uniform float opacity = 1.0;
uniform float pulse = 0.0;
uniform float time_sec = 0.0;

varying vec3 wpos;

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

float dry_brush_spikes(float u, float d, float scale, float reach_max, float seed) {
	float skewed = (u - d * 1.55) * scale + seed;
	float cell = floor(skewed);
	float f = fract(skewed);
	float h = hash11(cell * 17.3 + seed);
	float reach = (22.0 + pow(h, 2.2) * reach_max) * (1.0 + pulse * 0.45);
	float t = clamp(d / max(reach, 1.0), 0.0, 1.0);
	float half_w = mix(0.42, 0.02, pow(t, 0.75));
	float fw = max(fwidth(f), 0.015);
	float edge_w = 1.0 - smoothstep(half_w - fw, half_w + fw, abs(f - 0.5));
	float edge_d = 1.0 - smoothstep(reach - 8.0, reach + 4.0, d);
	return edge_w * edge_d * step(0.40, h);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (dot(clip_plane.xyz, clip_plane.xyz) > 0.0 && dot(clip_plane.xyz, wpos) + clip_plane.w < 0.0) {
		discard;
	}
	vec2 rel = (wpos.xy - cut_origin.xy) / max(plane_k, 0.001);
	float d = max(0.0, dot(rel, across_dir));
	float u = dot(rel, along_dir);

	// 基础深邃暗底（右下菜单区保持天鹅绒级纯净深底，确保白字与暗刻字 100% 锐利可读）
	vec3 col = mix(col_mid.rgb, col_deep.rgb, smoothstep(26.0, 340.0, d));
	col = mix(col, col_abyss.rgb, smoothstep(260.0, 860.0, d));

	// 斩缝近侧：三阶赛璐璐动画刀光能量带 + 斜向干笔飞白尖刺（收束在纵端与斩缝近侧，绝不冒出屏幕顶边锯齿）
	float menu_guard = (1.0 - smoothstep(140.0, 260.0, d)) * (1.0 - smoothstep(380.0, 520.0, abs(u)));
	float drift = time_sec * 9.0;
	float sp_mid = dry_brush_spikes(u + drift * 0.35, d, 0.015, 110.0, 4.1) * menu_guard;
	float sp_hot = dry_brush_spikes(u - drift * 0.22, d, 0.029, 64.0, 13.7) * menu_guard;
	float sp_core = dry_brush_spikes(u + 60.0, d, 0.045, 38.0, 27.9) * menu_guard;

	float b_mid = clamp(step(d, 72.0 + pulse * 30.0) * 0.65 + sp_mid, 0.0, 1.0);
	float b_hot = clamp(step(d, 26.0 + pulse * 18.0) + sp_hot, 0.0, 1.0);
	float b_core = clamp(step(d, 7.0 + pulse * 9.0) + sp_core * 0.85, 0.0, 1.0);

	// 边缘暗墨反切破片（增加日式动作游戏笔触张力，仅在上下两端非菜单带出现）
	float end_zone = smoothstep(180.0, 460.0, abs(u));
	float ink_cut = dry_brush_spikes(-u * 0.9, max(0.0, d - 36.0), 0.012, 260.0, 51.3) * end_zone;

	col = mix(col, col_mid.rgb * 1.18, b_mid * 0.78);
	col = mix(col, col_bright.rgb, b_hot * 0.92);
	col = mix(col, col_abyss.rgb * 0.55, ink_cut * 0.72);
	col = mix(col, col_core.rgb, b_core * 0.95);

	ALBEDO = col;
	ALPHA = opacity;
}
