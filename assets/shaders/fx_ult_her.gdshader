shader_type canvas_item;
// 大招里单独画的她（10-31）：照 Remotion 的 filter——saturate / brightness，再加 1.5 像素冷白描边和一圈紫辉
//   saturate(sat) brightness(bright) drop-shadow(0 0 rim_px 冷白 rim_a) drop-shadow(0 0 glow_px 紫 glow_a)
// rim_px / glow_px 是屏幕像素；px_scale = 一个贴图像素在屏幕上多大

uniform float sat = 1.0;
uniform float bright = 1.0;
uniform float rim_a = 0.0;
uniform float glow_a = 0.0;
uniform float rim_px = 1.5;
uniform float glow_px = 6.0;
uniform float px_scale = 1.0;
uniform vec4 flat_col = vec4(0.0);   // a > 0：整个剪影涂成这个颜色（冲击帧）

float alpha_ring(sampler2D tex, vec2 uv, vec2 step_uv, float r) {
	float m = 0.0;
	for (int i = 0; i < 12; i++) {
		float a = float(i) * TAU / 12.0;
		m = max(m, texture(tex, uv + vec2(cos(a), sin(a)) * step_uv * r).a);
	}
	return m;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float g = dot(c.rgb, vec3(0.2126, 0.7152, 0.0722));
	c.rgb = mix(vec3(g), c.rgb, sat) * bright;
	if (flat_col.a > 0.0) c.rgb = flat_col.rgb;
	vec2 s = TEXTURE_PIXEL_SIZE / max(px_scale, 0.01);
	if (flat_col.a <= 0.0 && (rim_a > 0.0 || glow_a > 0.0)) {
		float rim = alpha_ring(TEXTURE, UV, s, rim_px) * rim_a;
		float glow = max(alpha_ring(TEXTURE, UV, s, glow_px * 0.5), alpha_ring(TEXTURE, UV, s, glow_px)) * glow_a * 0.6;
		vec4 under = vec4(0.59, 0.43, 1.0, glow);
		under = mix(under, vec4(0.92, 0.94, 1.0, 1.0), rim);
		under.a = max(under.a, rim);
		c = vec4(mix(under.rgb, c.rgb, c.a), c.a + under.a * (1.0 - c.a));
	}
	COLOR = c * COLOR;
}
