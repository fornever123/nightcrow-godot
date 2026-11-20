// [YG-MARK] 首页《斩钟》：按出战角色换主色（三维钟这一层之上、界面之下）
// 原画面是「黑灰 + 朔的紫」；这里只转色相，灰黑没有色相不受影响，所以画法、网点、速度线全保留。
// sat / val 只作用在有颜色的像素上（按饱和度渐入），用来把每位女主的颜色调到合适的深浅。
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform float hue = 0.0;     // 转多少（0～1 圈）
uniform float sat = 1.0;
uniform float val = 1.0;
uniform float lift = 0.0;

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

void fragment() {
	vec3 src = texture(screen_tex, SCREEN_UV).rgb;
	vec3 h = rgb2hsv(src);
	float col = clamp((h.y - 0.12) / 0.2, 0.0, 1.0);
	h.x = fract(h.x + hue);
	h.y = clamp(h.y * (1.0 + (sat - 1.0) * col), 0.0, 1.0);
	h.z = clamp(h.z * (1.0 + (val - 1.0) * col) + lift * col, 0.0, 1.0);
	COLOR = vec4(hsv2rgb(h), 1.0);
}
