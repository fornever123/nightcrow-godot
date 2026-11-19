shader_type canvas_item;
// 画面重构样板：整帧调色——暗部偏冷、轻 S 曲线、暗角（在 sRGB 空间里调，HDR 2D 下屏幕纹理是线性的）
uniform sampler2D screen : hint_screen_texture, filter_linear;
uniform float vignette = 0.38;
uniform float curve = 0.22;

void fragment() {
	vec3 lin = texture(screen, SCREEN_UV).rgb;
	vec3 over = max(lin - vec3(1.0), vec3(0.0));
	vec3 c = pow(clamp(lin, 0.0, 1.0), vec3(1.0 / 2.2));
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, c * vec3(0.9, 0.98, 1.1), 1.0 - smoothstep(0.0, 0.45, l));
	c += (c * c * (3.0 - 2.0 * c) - c) * curve;
	vec2 d = SCREEN_UV - 0.5;
	d.x *= 1.5;
	c *= 1.0 - vignette * smoothstep(0.3, 0.9, length(d));
	COLOR = vec4(pow(max(c, vec3(0.0)), vec3(2.2)) + over, 1.0);
}
