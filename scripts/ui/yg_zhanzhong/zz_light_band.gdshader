// [YG-MARK] 设置页「白光定格」：横贯全屏的一道冷白光（门缝里漏出的白光）。
// 光线贴在 line_v 那条水平线上：线上方是向上散开的光晕，线下方很快收住；左右两端渐隐。
// open = 0 时只是一条线，1 时完全张开；fill 之后的部分压暗（总音量用它表示音量到哪）；flash = 定格那一下的过曝。
shader_type canvas_item;
render_mode blend_add;

uniform vec2 rect_size = vec2(1920.0, 470.0);
uniform float line_v = 0.6;
uniform float open = 1.0;
uniform float intensity = 1.0;
uniform float fill = 1.0;
uniform float flash = 0.0;
uniform float t = 0.0;
uniform vec3 tint = vec3(0.86, 0.9, 1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	vec2 px = UV * rect_size;
	float line_px = line_v * rect_size.y;
	float op = max(open, 0.0001);
	float dy = (px.y - line_px) / op;        // 张开前，光晕被压扁在线上
	float up = max(-dy, 0.0);
	float dn = max(dy, 0.0);

	// 光晕：线上方两层（宽、窄），线下方收得快
	float halo = (dy < 0.0)
		? exp(-up / 170.0) * 0.32 + exp(-up / 62.0) * 0.62 + exp(-up / 18.0) * 0.55
			+ (1.0 - smoothstep(110.0, 190.0, up)) * 0.16
		: exp(-dn / 12.0) * 0.9 + exp(-dn / 60.0) * 0.12;
	float core = exp(-abs(px.y - line_px) / 1.8) * 1.4 + exp(-abs(px.y - line_px) / 6.0) * 0.5;

	// 光里的尘和横向光纹：随时间缓慢漂移（光里时间是停的，所以漂得很慢）
	float streak = vnoise(vec2(px.x / 140.0 + t * 0.05, px.y / 9.0));
	float grain = vnoise(px / 3.0 + vec2(t * 0.3, 0.0));
	float mote = step(0.9975, hash(floor(px / 3.0) + floor(t * 0.5))) * exp(-up / 160.0) * (dy < 0.0 ? 1.0 : 0.0);
	halo *= 0.78 + 0.34 * streak + 0.08 * (grain - 0.5);

	// 左右渐隐：左侧从选中字后面亮起，右端保留充足亮度让刻度 10 与 100 清晰锐利
	float u = UV.x;
	float env = smoothstep(0.0, 0.18, u) * (1.0 - 0.52 * smoothstep(0.95, 1.0, u));
	env *= smoothstep(0.0, 90.0, px.y) * (1.0 - smoothstep(rect_size.y - 60.0, rect_size.y, px.y));   // 上下边缘收干净
	// 音量：fill 之后压暗
	float lit = mix(0.14, 1.0, 1.0 - smoothstep(fill - 0.004, fill + 0.004, u));

	float flick = 1.0 + 0.025 * sin(t * 7.3) * sin(t * 2.9);
	float k = (halo + core) * env * lit * intensity * flick * (1.0 + flash * 1.4);
	k *= smoothstep(0.0, 0.06, open);
	vec3 col = mix(tint, vec3(1.0), clamp(core * 0.6 + flash * 0.5, 0.0, 1.0));
	COLOR = vec4(col * k + vec3(mote * 0.7 * env), 1.0);
}
