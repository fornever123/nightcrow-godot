shader_type canvas_item;
// 画面重构样板：横向雾带（噪声慢移，上下边柔和）
uniform sampler2D noise : repeat_enable, filter_linear;
uniform vec4 tint : source_color = vec4(0.55, 0.63, 0.72, 1.0);
uniform float density = 0.5;
uniform float scroll = 0.0;
uniform float speed = 0.01;
uniform vec2 nscale = vec2(2.0, 1.0);
uniform float top_soft = 0.4;
uniform float bottom_soft = 0.4;
uniform float hdr = 1.0;

void fragment() {
	vec2 uv = UV * nscale + vec2(scroll + TIME * speed, 0.0);
	float n = texture(noise, uv).r;
	float n2 = texture(noise, uv * 2.3 + vec2(TIME * speed * 1.7, 0.31)).r;
	float f = smoothstep(0.2, 0.8, n * 0.65 + n2 * 0.35);
	float v = smoothstep(0.0, top_soft, UV.y) * (1.0 - smoothstep(1.0 - bottom_soft, 1.0, UV.y));
	COLOR = vec4(tint.rgb * hdr, tint.a * density * f * v);
}
