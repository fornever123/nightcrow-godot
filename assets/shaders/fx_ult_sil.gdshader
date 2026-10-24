shader_type canvas_item;
render_mode unshaded;
// 大招切入带里的主角特写（第四轮 §16.12）：硬边（不要半透明毛边）。
// paint = 0 → 纯剪影（填 ink）；paint = 1 → 原画颜色压成几档（赛璐璐感），暗部压向 ink。
uniform vec4 ink : source_color = vec4(0.05, 0.035, 0.09, 1.0);
uniform float fade = 1.0;
uniform float paint = 1.0;
uniform float levels = 4.0;
// 千刃切入带的遮罩（屏幕像素）：带的上边是 band_a → band_b 这条线，往下 band_h 高；带外不画。band_h = 0 = 不遮
uniform vec2 band_a = vec2(0.0);
uniform vec2 band_b = vec2(1.0, 0.0);
uniform float band_h = 0.0;
uniform vec2 screen_size = vec2(1280.0, 720.0);

void fragment() {
	vec4 t = texture(TEXTURE, UV);
	float a = step(0.62, t.a) * fade;
	if (band_h > 0.0) {
		vec2 sp = SCREEN_UV * screen_size;
		float k = (sp.x - band_a.x) / max(band_b.x - band_a.x, 1.0);
		float top = mix(band_a.y, band_b.y, k);
		a *= step(top + 3.0, sp.y) * step(sp.y, top + band_h - 3.0);
	}
	vec3 c = t.rgb;
	// 对比拉大一点，再分档
	c = clamp((c - 0.5) * 1.25 + 0.52, 0.0, 1.0);
	c = floor(c * levels + 0.5) / levels;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(ink.rgb, c, smoothstep(0.08, 0.3, l));
	COLOR = vec4(mix(ink.rgb, c, paint), a);
}
