shader_type canvas_item;
// 画面重构样板：按景深把一层往雾色里推，底部再额外融进雾
uniform vec3 fog_color : source_color = vec3(0.36, 0.43, 0.52);
uniform float haze : hint_range(0.0, 1.0) = 0.0;
uniform float darken = 1.0;
uniform float base_fade_start : hint_range(0.0, 1.0) = 0.85;
uniform float base_fade : hint_range(0.0, 1.0) = 0.0;
uniform vec3 base_color : source_color = vec3(0.05, 0.07, 0.10);

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	c.rgb = mix(c.rgb * darken, fog_color, haze);
	float b = base_fade * smoothstep(base_fade_start, 1.0, UV.y);
	c.rgb = mix(c.rgb, base_color, b);
	COLOR = c * COLOR;
}
