shader_type canvas_item;
render_mode blend_add;
// 雨夜河岸街加色柔光（D1：门洞/桥洞昼光、路灯柔光微闪、暗处冷雾衬底）：IGN 抖动消除暗墙光晕色阶断层。

uniform float gain = 1.0;

void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	float w = c.a * gain;
	float ign = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
	float dither = (ign - 0.5) / 96.0 * step(0.004, w);
	COLOR = vec4(max(c.rgb * w + vec3(dither), vec3(0.0)), 1.0);
}
