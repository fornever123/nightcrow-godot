shader_type canvas_item;
render_mode unshaded;
// 大招开场「领域展开」（10-31，照 Remotion UltOpeningDomainV12 / 整段预览 13 做进游戏；任何地图都能用）。
// 读当前屏幕（她和 HUD 已经藏起来），把画面拆成三块，再按升起的镜头做透视：
//   墙 = 地面线 base 以上的画面；地面 = base 往下 BAND 行竖着拉成 STREET 深、往镜头躺平；立面 = 再往下到画面底，在地面边沿往下折。
// 影子是从她脚下 (hx, HER_Z) 出发的圆，按“摊开距离”走：地面上是透视压扁的圆，到墙根往上爬（快 WALL_K 倍），到地面边沿往下折。
// 画法照赛璐璐：墨是纯黑，只用硬边白高光、白描边；墨里留着原画面的轮廓痕迹（Sobel 现算）；地上的墨是镜面，有竖向反光条。
// 帧号：real 逐帧（镜头、褪色），f 一拍二（墨）。坐标都是 1280×720 的屏幕像素。

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float base = 572.0;
uniform float hx = 500.0;
uniform float f = 0.0;
uniform float real = 0.0;

const float W = 1280.0;
const float H = 720.0;
const float STREET = 170.0;
const float BAND = 16.0;
const float HER_Z = 85.0;
const float WALL_K = 1.4;
const float P = 1000.0;
const vec3 RIM = vec3(0.933, 0.941, 1.0);

float clamp01(float v) { return clamp(v, 0.0, 1.0); }
float ramp(float t, float a, float b) { return clamp01((t - a) / (b - a)); }
float ease_out(float k) { return 1.0 - pow(1.0 - k, 3.0); }
float ease_in_out(float k) { return k < 0.5 ? 4.0 * k * k * k : 1.0 - pow(-2.0 * k + 2.0, 3.0) / 2.0; }
float hash(float n) { return fract(sin(n * 127.1 + 311.7) * 43758.5453); }

// 影子前沿的“摊开距离”（和 v10 的 reach 一样的关键帧）
float reach(float t) {
	if (t <= 4.0) return mix(0.0, 10.0, ramp(t, 0.0, 4.0));
	if (t <= 12.0) return mix(10.0, 46.0, ramp(t, 4.0, 12.0));
	if (t <= 16.0) return mix(46.0, HER_Z + 4.0, ramp(t, 12.0, 16.0));
	if (t <= 24.0) return mix(HER_Z + 4.0, 420.0, ramp(t, 16.0, 24.0));
	if (t <= 32.0) return mix(420.0, 800.0, ramp(t, 24.0, 32.0));
	return mix(800.0, 1100.0, ramp(t, 32.0, 40.0));
}

float wall_h(float R, float x) {
	float d2 = R * R - (x - hx) * (x - hx);
	if (d2 <= HER_Z * HER_Z) return 0.0;
	return (sqrt(d2) - HER_Z) * WALL_K;
}

// 墙上墨的上沿：一个个圆鼓鼓的墨团 + 五条竖向影舌（爬的时候领头，爬到顶并进黑幕）
float wall_top(float x) {
	float h = wall_h(reach(f), x);
	if (h <= 0.0) return base;
	float k = clamp01(h / 480.0);
	float lobe = 16.0 * sqrt(max(0.0, sin(x * 0.045 + f * 0.06))) + 8.0 * sqrt(max(0.0, sin(x * 0.11 - f * 0.09 + 1.3)));
	float y = base - h - (1.0 - k) * lobe;
	vec3 tg[5] = vec3[5](vec3(150.0, 26.0, 150.0), vec3(330.0, 20.0, 110.0), vec3(640.0, 18.0, 90.0), vec3(900.0, 26.0, 170.0), vec3(1150.0, 30.0, 130.0));
	for (int i = 0; i < 5; i++) {
		float dx = abs(x - (tg[i].x + 5.0 * sin(f * 0.25 + float(i) * 1.7))) / tg[i].y;
		if (dx < 1.0) y -= tg[i].z * sin(PI * k) * pow(1.0 - dx, 1.7);
	}
	return y;
}

// 原画面上的冷白轮廓（Sobel）
float edge_at(vec2 uv) {
	vec2 px = 1.0 / vec2(W, H);
	float l = dot(texture(screen_tex, uv - vec2(px.x, 0.0)).rgb, vec3(0.299, 0.587, 0.114));
	float r = dot(texture(screen_tex, uv + vec2(px.x, 0.0)).rgb, vec3(0.299, 0.587, 0.114));
	float u = dot(texture(screen_tex, uv - vec2(0.0, px.y)).rgb, vec3(0.299, 0.587, 0.114));
	float d = dot(texture(screen_tex, uv + vec2(0.0, px.y)).rgb, vec3(0.299, 0.587, 0.114));
	float m = length(vec2(r - l, d - u)) * 255.0;
	return pow(clamp01((m - 10.0) / 40.0), 0.8);
}

vec3 tone(vec3 c) {
	float desat = 1.0 - 0.75 * ramp(real, 1.0, 12.0);
	float dim = 1.0 - 0.25 * ramp(real, 4.0, 16.0);
	float g = dot(c, vec3(0.2126, 0.7152, 0.0722));
	return mix(vec3(g), c, desat) * dim;
}

// 两档硬白高光：法线朝光（左上）的那一圈边，k 是离边的远近（0 在边上）
float cel(vec2 n, float k) {
	float h = dot(normalize(n), normalize(vec2(-0.34, -0.94))) * (1.0 - k);
	return h > 0.72 ? 1.0 : (h > 0.5 ? 0.6 : 0.0);
}

// 地面 / 立面上的墨。(x, v) 是这块面上的坐标，u0 是这块面在“摊开”坐标里离墙根多远
vec4 floor_ink(float x, float v, float u0, vec2 uv_edges) {
	float R = reach(f);
	if (R <= 0.0) return vec4(0.0);
	float cy = HER_Z - u0;
	vec2 d = vec2(x - hx, v - cy);
	float a = atan(d.y, d.x);
	float j = 1.0 + 0.05 * sqrt(max(0.0, sin(a * 9.0 + f * 0.08))) + 0.03 * sin(a * 23.0 - f * 0.1);
	float r = R * j;
	float dist = length(d);
	if (dist > r) return vec4(0.0);
	vec3 col = vec3(0.016, 0.012, 0.035);
	// 墨里留着原地面的轮廓痕迹，轻轻起伏
	vec2 wob = vec2(sin(v * 0.05 + f * 0.3 + x * 0.006), cos(x * 0.02 - f * 0.2)) * 3.0 / vec2(W, H);
	col += vec3(0.8) * 0.2 * edge_at(uv_edges + wob);
	// 镜面反光条：按“摊开”坐标排，跨过地面边沿时跟着折下去，慢慢往镜头流
	float shine = ramp(f, 14.0, 24.0);
	float u = v + u0;
	float lamps[5] = float[5](180.0, 430.0, 720.0, 980.0, 1180.0);
	for (int i = 0; i < 5; i++) {
		float w = u - f * 1.4 + 200.0;
		float cell = floor(w / 72.0);
		float s = hash(cell + float(i) * 17.0);
		float a0 = cell * 72.0 + 8.0 * s;
		float len = 10.0 + 50.0 * hash(cell * 1.7 + float(i) * 5.0);
		float t = (w - a0) / len;
		if (t > 0.0 && t < 1.0) {
			float cx = lamps[i] + 4.0 * sin(u * 0.04 + f * 0.25 + float(i));
			float hw = (1.5 + 3.0 * hash(cell * 2.3 + float(i))) * sin(PI * t);
			if (abs(x - cx) < hw) col = mix(col, RIM, 0.75 * shine);
		}
	}
	// 前沿一圈赛璐璐高光
	float g = cel(d / max(dist, 0.001), clamp01((r - dist) / 5.0)) * (1.0 - 0.5 * ramp(f, 36.0, 48.0));
	col = mix(col, RIM, g * step(r - dist, 5.0));
	return vec4(col, 1.0);
}

void fragment() {
	vec2 p = SCREEN_UV * vec2(W, H);
	// 镜头：游戏视角（眼睛在墙根高度、地面看不见）→ 升起往下看，墙往上让出地面
	float ck = ease_in_out(ramp(real, 0.0, 16.0));
	float drift = ramp(real, 16.0, 66.0);
	float oy = base + (150.0 - base) * ck - 30.0 * drift;
	float ty = -150.0 * ck - 10.0 * drift;
	float tz = 70.0 * ease_out(drift);
	vec3 col = vec3(0.0);
	float best = 1e9;
	float face_h = H - base - BAND;
	// 立面：z = STREET 的竖面（最靠近镜头）
	float tc = 1.0 - (tz + STREET) / P;
	float yc = oy + tc * (p.y - oy) - ty;
	float xc = 640.0 + tc * (p.x - 640.0);
	if (tc > 0.0 && yc >= base && yc <= base + face_h && xc >= 0.0 && xc <= W) {
		best = tc;
		vec2 uv = vec2(xc, base + BAND + (yc - base)) / vec2(W, H);
		col = tone(texture(screen_tex, uv).rgb);
		vec4 ink = floor_ink(xc, yc - base, STREET, uv);
		col = mix(col, ink.rgb, ink.a);
	}
	// 地面：y = base 的平面，z 从墙根 0 到 STREET
	float tf = abs(p.y - oy) > 0.001 ? (base + ty - oy) / (p.y - oy) : -1.0;
	float zf = P * (1.0 - tf) - tz;
	float xf = 640.0 + tf * (p.x - 640.0);
	if (tf > 0.0 && tf < best && zf >= 0.0 && zf <= STREET && xf >= 0.0 && xf <= W) {
		best = tf;
		vec2 uv = vec2(xf, base + zf / STREET * BAND) / vec2(W, H);
		col = tone(texture(screen_tex, uv).rgb);
		vec4 ink = floor_ink(xf, zf, 0.0, uv);
		col = mix(col, ink.rgb, ink.a);
		// 地面边沿那条折线一闪
		float R = reach(f);
		float dz = STREET - HER_Z;
		float half_e = R > dz ? sqrt(R * R - dz * dz) : 0.0;
		float ek = ramp(f, 15.0, 17.0) * (1.0 - 0.75 * ramp(f, 22.0, 32.0)) * (1.0 - ramp(f, 50.0, 58.0));
		if (half_e > 0.0 && abs(zf - (STREET - 1.5)) < 1.25 && abs(xf - hx) < half_e) col = mix(col, RIM, ek);
	}
	// 墙：z = 0 的竖面，base 以上
	float tw = 1.0 - tz / P;
	float yw = oy + tw * (p.y - oy) - ty;
	float xw = 640.0 + tw * (p.x - 640.0);
	if (tw < best && yw >= 0.0 && yw <= base && xw >= 0.0 && xw <= W) {
		vec2 uv = vec2(xw, yw) / vec2(W, H);
		col = tone(texture(screen_tex, uv).rgb);
		float top = wall_top(xw);
		if (yw > top) {
			col = vec3(0.02, 0.016, 0.031) + RIM * 0.3 * edge_at(uv);
			// 往上爬的那层厚墨：前沿一个个墨团上的硬高光
			float tl = wall_top(xw - 3.0);
			float tr = wall_top(xw + 3.0);
			vec2 n = vec2(-(tl - tr), -6.0);
			float g = cel(n, clamp01((yw - top) / 12.0)) * (1.0 - 0.5 * ramp(f, 36.0, 48.0));
			col = mix(col, RIM, g * step(yw - top, 12.0) * step(top, base - 0.5));
		}
		// 墙根折线：90 度的那条线一闪，白的
		float R = reach(f);
		float half_w = R > HER_Z ? sqrt(R * R - HER_Z * HER_Z) : 0.0;
		float crease = ramp(f, 15.0, 17.0) * (1.0 - 0.75 * ramp(f, 22.0, 32.0)) * (1.0 - ramp(f, 50.0, 58.0));
		if (half_w > 0.0) {
			if (yw > base - 1.5 && abs(xw - hx) < half_w) col = mix(col, RIM, crease);
			float dr = 5.0 * (1.0 - ramp(f, 22.0, 30.0));
			float dd = min(length(vec2(xw - (hx - half_w), yw - base)), length(vec2(xw - (hx + half_w), yw - base)));
			if (dd < dr) col = mix(col, vec3(1.0), crease);
		}
	}
	COLOR = vec4(col, 1.0);
}
