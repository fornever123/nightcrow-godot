shader_type canvas_item;
// 分层背景（street_layered.gd）的远近处理：明暗阶梯（往后更接近雾色）、对比、虚化、楼脚雾、月光勾边、暖窗、闪电。
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
