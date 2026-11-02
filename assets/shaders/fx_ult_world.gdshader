shader_type canvas_item;
render_mode unshaded;
// 大招 ④ 地图斩 + ⑤ 收刀的世界（10-31，照 Remotion UltMapSlashV4 / 整段预览 13 做进游戏）。读当前屏幕（她藏起来了，另画在上面）：
//   影子里的世界：去色、压暗、提对比，留冷白轮廓痕迹（Sobel）；
//   断开后整条街沿斩线错开：线上面那半和下面那半各自挪开（沿线滑 + 沿法线张开一点），线缝里透出白芯紫辉的线；
//   “咔”之后合回去；影子退潮：只有她脚下越缩越小的圆里还是影子世界，圆外恢复原本的颜色。
//   推近看收刀时（soft > 0）世界轻轻糊开，免得放大后的背景全是噪点（11-01，照 UltMapSlashV5 的 bgBlur）。
// 坐标都是 1280×720 的屏幕像素。

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float dark = 1.0;            // 影子世界的亮度系数
uniform vec2 pivot = vec2(640.0, 400.0); // 斩线上一点
uniform vec2 dir = vec2(1.0, 0.0);   // 斩线方向（单位向量）
uniform vec2 off_above = vec2(0.0);  // 上半边的位移
uniform vec2 off_below = vec2(0.0);  // 下半边的位移
uniform float split = 0.0;           // 1 = 已经断开（分两半画）
uniform float seam_w = 0.0;          // 线缝白芯宽
uniform float seam_glow = 0.0;       // 线缝紫辉宽
uniform float seam_a = 1.0;
uniform vec2 tide_c = vec2(640.0, 400.0);
uniform float tide_r = 1e5;          // 影子世界只留在这个圆里（羽化 60 像素）
uniform float lit = 0.0;             // 1 = 圆外恢复原色
uniform float soft = 0.0;            // 世界糊开的程度（屏幕像素，高斯 sigma）
uniform float tide_fade = 0.0;       // 退潮时圆里的影子世界也跟着淡回原色（0～1），不然最后缩成脚下一块黑

const float W = 1280.0;
const float H = 720.0;

float edge_at(vec2 uv) {
	vec2 px = 1.0 / vec2(W, H);
	float l = dot(texture(screen_tex, uv - vec2(px.x, 0.0)).rgb, vec3(0.299, 0.587, 0.114));
	float r = dot(texture(screen_tex, uv + vec2(px.x, 0.0)).rgb, vec3(0.299, 0.587, 0.114));
	float u = dot(texture(screen_tex, uv - vec2(0.0, px.y)).rgb, vec3(0.299, 0.587, 0.114));
	float d = dot(texture(screen_tex, uv + vec2(0.0, px.y)).rgb, vec3(0.299, 0.587, 0.114));
	float m = length(vec2(r - l, d - u)) * 255.0;
	return pow(clamp((m - 10.0) / 40.0, 0.0, 1.0), 0.8);
}

// 读屏幕颜色；soft > 0.3 时取一圈 12 个点做近似高斯模糊
vec3 tap(vec2 uv) {
	vec3 c = texture(screen_tex, uv).rgb;
	if (soft <= 0.3) return c;
	vec2 px = 1.0 / vec2(W, H);
	float wsum = 1.0;
	for (int i = 0; i < 12; i++) {
		float a = float(i) * 2.399963;
		float r = soft * sqrt((float(i) + 0.5) / 12.0) * 1.6;
		float w = exp(-r * r / max(2.0 * soft * soft, 0.01));
		c += texture(screen_tex, uv + vec2(cos(a), sin(a)) * r * px).rgb * w;
		wsum += w;
	}
	return c / wsum;
}

// 影子里的世界：grayscale(0.8) brightness(0.55 dark) contrast(1.35) + 冷白轮廓 0.6 dark
vec3 shadow_world(vec2 q) {
	vec2 uv = q / vec2(W, H);
	vec3 c = tap(uv);
	float g = dot(c, vec3(0.2126, 0.7152, 0.0722));
	c = mix(c, vec3(g), 0.8) * 0.55 * dark;
	c = (c - 0.5) * 1.35 + 0.5;
	c = max(c, vec3(0.0));
	c += vec3(0.933, 0.941, 1.0) * 0.6 * dark * edge_at(uv);
	return c;
}

void fragment() {
	vec2 p = SCREEN_UV * vec2(W, H);
	vec2 n = vec2(-dir.y, dir.x);       // 指向线的下方
	vec3 col;
	if (split < 0.5) {
		col = shadow_world(p);
	} else {
		// 线缝：先画在底下，两半世界盖上去，张开的地方露出来
		float dl = abs(dot(p - pivot, n));
		col = vec3(0.0);
		col = mix(col, vec3(0.604, 0.42, 1.0), 0.5 * seam_a * exp(-pow(dl / max(seam_glow * 0.5, 0.5), 2.0)));
		col = mix(col, vec3(0.949, 0.937, 1.0), seam_a * (1.0 - smoothstep(seam_w * 0.5 - 0.5, seam_w * 0.5 + 0.5, dl)));
		vec2 qa = p - off_above;
		if (dot(qa - pivot, n) < 0.0) col = shadow_world(qa);
		vec2 qb = p - off_below;
		if (dot(qb - pivot, n) >= 0.0) col = shadow_world(qb);
	}
	if (lit > 0.5) {
		// 影子退潮：圆外是原本的颜色
		float r = length(p - tide_c);
		float k = smoothstep(max(0.0, tide_r - 60.0), tide_r, r);
		col = mix(col, tap(SCREEN_UV), max(k, tide_fade));
	}
	COLOR = vec4(col, 1.0);
}
