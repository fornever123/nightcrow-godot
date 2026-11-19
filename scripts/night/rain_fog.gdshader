shader_type canvas_item;
// 雨夜河岸街分层流动雾（D1）：双八度无缝噪声漂移 + 竖向渐变遮罩 + 交错梯度噪声（IGN）抖动消除暗部 8-bit 色带。

uniform sampler2D n : repeat_enable, filter_linear;
uniform vec4 col : source_color = vec4(0.18, 0.23, 0.34, 1.0);
uniform float k = 0.55;
uniform float spd = 0.018;
uniform float y0 = 0.08;
uniform float y1 = 0.88;
uniform float y_end = 1.05;
uniform float strength = 0.38;
uniform float base_lift = 0.16;
uniform float cam_x = 0.0;
uniform float t = 0.0;

void fragment() {
	vec2 p = SCREEN_UV * vec2(1.78, 1.0) * 1.1 + vec2(cam_x * k / 1280.0, 0.0);
	float n1 = texture(n, p + vec2(t * spd, t * spd * 0.2)).r;
	float n2 = texture(n, p * 1.9 - vec2(t * spd * 1.4, -t * spd * 0.12)).r;
	float cloud = mix(base_lift, 1.0, clamp(n1 * n2 * 2.2, 0.0, 1.0));
	float mask = smoothstep(y0, y1, SCREEN_UV.y) * (1.0 - smoothstep(y_end - 0.14, y_end, SCREEN_UV.y));
	float ign = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
	float gate = smoothstep(0.0, 0.015, mask * strength);
	float alpha = clamp(cloud * mask * strength + (ign - 0.5) / 64.0 * gate, 0.0, 1.0);
	COLOR = vec4(clamp(col.rgb + (ign - 0.5) / 96.0, vec3(0.0), vec3(1.0)), alpha);
}
