shader_type canvas_item;
render_mode unshaded;

// 《断晓》商业级电影后处理层（仅在斩切 / 切人 / 切章 / 破界瞬间激活，常驻零脏感）：
// - 径向高速推镜动态模糊 (radial_blur)
// - 镜头边缘 RGB 色散冲击 (chroma_amp)
// - 1~2 帧日漫动作大片高反差瞬杀冲击帧 (impact_k)
// - 电影宽银幕黑边呼吸 (letterbox_ratio) + 极柔镜头暗角 (vignette_k)

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec4 accent_col : source_color = vec4(0.616, 0.451, 1.0, 1.0);
uniform float chroma_amp : hint_range(0.0, 0.035) = 0.0;
uniform float radial_blur : hint_range(0.0, 0.05) = 0.0;
uniform float impact_k : hint_range(0.0, 1.0) = 0.0;
uniform float letterbox_ratio : hint_range(0.0, 0.16) = 0.0;
uniform float vignette_k : hint_range(0.0, 1.0) = 0.0;
uniform vec2 focus_uv = vec2(0.56, 0.48);

void fragment() {
	vec2 uv = SCREEN_UV;
	float edge_d = min(uv.y, 1.0 - uv.y);
	if (letterbox_ratio > 0.001 && edge_d < letterbox_ratio) {
		COLOR = vec4(0.02, 0.02, 0.032, 1.0);
	} else {
		vec2 dir = uv - focus_uv;
		float dist = length(dir);
		vec2 ndir = dist > 0.0001 ? dir / dist : vec2(0.0);

		vec3 col = texture(screen_tex, uv).rgb;

		// 1. 径向高速推镜动态模糊（6 采样轻量高速）
		if (radial_blur > 0.0004) {
			vec3 acc = vec3(0.0);
			float step_len = radial_blur * dist;
			for (int i = 0; i < 6; i++) {
				float fi = (float(i) / 5.0 - 0.5) * 1.6;
				acc += texture(screen_tex, clamp(uv - ndir * step_len * fi, vec2(0.001), vec2(0.999))).rgb;
			}
			col = mix(col, acc / 6.0, clamp(radial_blur * 28.0, 0.0, 0.85));
		}

		// 2. 镜头 RGB 色散冲击（高能斩裂/切人/切章瞬间的光学张力）
		if (chroma_amp > 0.0003) {
			vec2 shift = ndir * chroma_amp * (0.35 + dist * 1.25);
			float r = texture(screen_tex, clamp(uv + shift, vec2(0.001), vec2(0.999))).r;
			float b = texture(screen_tex, clamp(uv - shift, vec2(0.001), vec2(0.999))).b;
			col.r = mix(col.r, r, 0.85);
			col.b = mix(col.b, b, 0.85);
		}

		// 3. 高反差日漫瞬杀冲击帧（黑白极锐对比 + 角色主色辉刃，持续 1~2 帧极具炸裂感）
		if (impact_k > 0.005) {
			float luma = dot(col, vec3(0.299, 0.587, 0.114));
			float bw = smoothstep(0.22, 0.58, luma);
			vec3 manga = mix(vec3(0.03, 0.028, 0.05), mix(vec3(1.0), accent_col.rgb, 0.36), bw);
			col = mix(col, manga, clamp(impact_k * 0.82, 0.0, 0.82));
		}

		// 4. 电影感极柔暗角
		if (vignette_k > 0.001) {
			float vig = smoothstep(0.48, 1.12, dist);
			col *= 1.0 - vig * 0.42 * vignette_k;
		}

		COLOR = vec4(col, 1.0);
	}
}
