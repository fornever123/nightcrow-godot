shader_type canvas_item;
// 大招「绝影 · 鸦羽止」：她的定格图在黑白世界里只留紫色（发梢渐变、眼睛、宝石），其余去色。amount = 0 还原彩色。
uniform float amount : hint_range(0.0, 1.0) = 1.0;

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

void fragment() {
	vec4 c = COLOR;
	vec3 hsv = rgb2hsv(c.rgb);
	float keep = (hsv.x >= 0.68 && hsv.x <= 0.86) ? clamp((hsv.y - 0.35) / 0.3, 0.0, 1.0) : 0.0;
	float l = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	vec3 g = mix(vec3(l), c.rgb, keep);
	COLOR = vec4(mix(c.rgb, g, amount), c.a);
}
