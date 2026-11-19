shader_type canvas_item;
// 画面重构样板：街下深处——被白光赶出来的时间在暗处翻涌（狂影的温床）
uniform sampler2D noise : repeat_enable, filter_linear;
uniform float scroll = 0.0;
uniform vec3 dark : source_color = vec3(0.008, 0.012, 0.024);
uniform vec3 lift : source_color = vec3(0.11, 0.14, 0.2);
uniform float strength = 1.0;

void fragment() {
	vec2 uv = UV * vec2(3.0, 1.1) + vec2(scroll, 0.0);
	vec2 w = vec2(texture(noise, uv * 0.6 + vec2(TIME * 0.015, -TIME * 0.05)).r,
			texture(noise, uv * 0.6 + vec2(0.37, TIME * 0.035)).r);
	float n = texture(noise, uv + (w - 0.5) * 0.8 + vec2(0.0, -TIME * 0.06)).r;
	float mass = smoothstep(0.42, 0.72, n);          // 翻涌的暗团
	float grad = smoothstep(0.0, 0.6, UV.y);
	float a = clamp(grad * 0.9 + mass * 0.55 * smoothstep(0.05, 0.45, UV.y), 0.0, 0.985);
	vec3 col = mix(dark, lift, (1.0 - mass) * 0.35 * (1.0 - UV.y));
	COLOR = vec4(col, a * strength);
}
