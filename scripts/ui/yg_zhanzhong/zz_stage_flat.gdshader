shader_type spatial;
// 《机关舞台》景片：章节插画按深度切成的剪影景片。正面是画；背面是铆钉铸铁板。
// 硬边（卡通纸景片）+ 冷色细勾边；lit = 0 是逆光黑剪影，1 是原画。
// glow_front：灯链——UV.x 小于它的暖光（窗、灯）点亮；sky_flash：闪电；wave_*：钟响冲击波推过云层。
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
uniform float lit = 1.0;
uniform float glow_on = 1.0;
uniform float glow_front = 2.0;
uniform float rim = 0.0;
uniform vec3 rim_col = vec3(0.78, 0.86, 1.0);
uniform float flash = 0.0;
uniform float outline = 0.0;
uniform float opacity = 1.0;
uniform vec2 xr = vec2(0.0, 1.0);
uniform float sky_flash = 0.0;
uniform vec2 wave_c = vec2(0.5, 0.5);
uniform float wave_r = -1.0;
uniform float wave_k = 0.0;
// reveal_r ≥ 0：只显示 wave_c 周围这个半径以内（线条预演里落针后的表盘波揭开插画）
uniform float reveal_r = -1.0;
// 天幕面片比画面大一圈（追钟机位会看到更宽），超出部分沿用边缘颜色
uniform float uv_k = 1.0;

float hard(float a) {
	return smoothstep(0.46, 0.62, a);
}

// 上沿：上方是空的那一圈（逆光只打在朝天的边上）
float top_edge(vec2 uv, float px) {
	return 1.0 - hard(texture(tex, uv - vec2(0.0, px / 1080.0)).a);
}

float edge_of(vec2 uv, float px) {
	vec2 o = vec2(px / 1920.0, px / 1080.0);
	float a = hard(texture(tex, uv + vec2(o.x, 0.0)).a);
	a = min(a, hard(texture(tex, uv - vec2(o.x, 0.0)).a));
	a = min(a, hard(texture(tex, uv + vec2(0.0, o.y)).a));
	a = min(a, hard(texture(tex, uv - vec2(0.0, o.y)).a));
	return 1.0 - a;
}

void fragment() {
	if (UV.x < xr.x || UV.x >= xr.y) {
		discard;
	}
	vec2 uv = (UV - 0.5) * uv_k + 0.5;
	// 天幕扩展区采用镜像折叠采样，彻底杜绝仰角登天运镜时 repeat_disable 顶部像素拉成“竖条码”！
	if (uv_k > 1.01) {
		vec2 m_uv = vec2(
			uv.x < 0.0 ? -uv.x : (uv.x > 1.0 ? 2.0 - uv.x : uv.x),
			uv.y < 0.0 ? -uv.y : (uv.y > 1.0 ? 2.0 - uv.y : uv.y)
		);
		uv = clamp(m_uv, vec2(0.002), vec2(0.998));
	}
	float ring = 0.0;
	if (wave_r > 0.0) {
		vec2 d = (uv - wave_c) * vec2(1.7778, 1.0);
		float r = length(d);
		ring = exp(-pow((r - wave_r) / 0.06, 2.0)) * wave_k;
		uv -= (d / max(r, 1e-4)) / vec2(1.7778, 1.0) * ring * 0.05;
	}
	vec4 c = texture(tex, uv);
	float a = hard(c.a);
	if (reveal_r >= 0.0) {
		vec2 dr = ((UV - 0.5) * uv_k + 0.5 - wave_c) * vec2(1.7778, 1.0);
		a *= 1.0 - smoothstep(reveal_r - 0.035, reveal_r, length(dr));
	}
	if (a * opacity < 0.02) {
		discard;
	}
	// 画面边框处不描边（收细轮廓宽度，彻底消除剪纸白边穿帮）
	float bm = step(0.004, UV.x) * step(UV.x, 0.996) * step(0.004, UV.y) * step(UV.y, 0.996);
	float e = edge_of(uv, 1.35) * bm;
	float et = top_edge(uv, 1.75) * bm;
	vec3 col;
	if (FRONT_FACING) {
		float luma = dot(c.rgb, vec3(0.299, 0.587, 0.114));
		float warm = smoothstep(0.06, 0.25, c.r - c.b) * smoothstep(0.3, 0.7, luma);
		float on = 1.0 - smoothstep(glow_front - 0.006, glow_front + 0.012, UV.x);
		vec3 sil = c.rgb * 0.03 + vec3(0.002, 0.0025, 0.005);
		col = mix(sil, c.rgb, lit);
		col = mix(col, c.rgb * 1.45, warm * glow_on * on * (1.0 - lit * 0.75));
		col += rim_col * (e * rim * 0.10 + et * outline * 0.16);
		col += vec3(0.72, 0.9, 1.0) * sky_flash * (0.35 + 0.65 * luma);
		col += vec3(0.7, 0.8, 1.0) * ring * 0.07;
	} else {
		// 背面：冷铸铁 + 铆钉 + 剪影边一圈细腻金属高光
		vec2 g = UV * vec2(64.0, 36.0);
		vec2 f = fract(g) - 0.5;
		float rivet = smoothstep(0.16, 0.08, length(f)) * step(0.5, fract(floor(g.x) * 0.5 + floor(g.y) * 0.5));
		float brushed = 0.5 + 0.5 * sin(UV.y * 900.0 + sin(UV.x * 40.0) * 3.0);
		col = vec3(0.07, 0.075, 0.09) * (0.85 + 0.15 * brushed) + vec3(0.32, 0.33, 0.36) * rivet * 0.5;
		col += vec3(0.5, 0.52, 0.56) * e * 0.18;
	}
	// 锁定、闪电那一下只让剪影边缘微亮一闪
	col += rim_col * flash * mix(e, et, 0.6) * 0.85;
	col = min(col, vec3(1.0 + sky_flash * 0.5));
	ALBEDO = col;
	ALPHA = a * opacity;
}
