shader_type spatial;
// 《钟窗选章》全屏章节世界：钟后面一整面 2.5D 深度视差世界，透过钟窗看是饱和原色，窗外压暗去色。
// 换章 = 两个世界按深度分层推移（近景走得多、远景走得少），由剑针拨动驱动；不画任何刀光。
render_mode unshaded, cull_disabled, depth_draw_always;

uniform sampler2D art_a : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D dep_a : filter_linear, repeat_disable;
uniform sampler2D art_b : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D dep_b : filter_linear, repeat_disable;
uniform int fx_a = 0;
uniform int fx_b = 0;
uniform float frost_a = 0.0;
uniform float frost_b = 0.0;
uniform float swap = 0.0;          // 0 = 只看 a；1 = 只看 b
uniform float swap_dir = 1.0;      // +1 新世界从右进；-1 从左进
uniform float depth_k = 0.06;
uniform float time_sec = 0.0;
uniform float zoom = 1.0;
uniform vec2 par = vec2(0.0);       // 镜头漂移带出的额外视差
// 钟窗（屏幕空间，单位：视口高度）
uniform vec2 win_c = vec2(0.67, 0.5);
uniform float win_r = 0.4;
uniform float out_dim = 0.62;      // 窗外压暗
uniform float out_a = 1.0;         // 窗外世界的不透明度（进场时从 0 起）
uniform float flash = 0.0;
uniform float opacity = 1.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

vec3 fx(vec3 col, vec2 uv, int mode, float t) {
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	if (mode == 1) {
		float warm = smoothstep(0.12, 0.35, col.r - col.b) * smoothstep(0.35, 0.7, luma);
		col *= 1.0 + warm * (0.14 * sin(t * 2.3 + uv.x * 9.0) + 0.06 * sin(t * 7.1));
	} else if (mode == 2) {
		float hi = smoothstep(0.55, 0.85, luma);
		float band = 0.5 + 0.5 * sin((uv.x * 1.4 + uv.y * 0.9) * 9.0 - t * 0.7);
		col += hi * band * vec3(1.0, 0.92, 0.72) * 0.14;
	} else if (mode == 4) {
		float rift = smoothstep(0.1, 0.35, col.b - col.g) * smoothstep(0.3, 0.8, luma) + smoothstep(0.85, 0.97, luma);
		col *= 1.0 + clamp(rift, 0.0, 1.0) * (0.3 + 0.25 * sin(t * 3.6));
	} else if (mode == 5) {
		vec2 g = uv * vec2(70.0, 40.0) + vec2(0.0, t * 1.6);
		vec2 cell = floor(g);
		vec2 fr = fract(g) - 0.5;
		float h = hash(cell);
		float mote = step(0.93, h) * smoothstep(0.12, 0.0, length(fr + vec2(sin(t + h * 6.28) * 0.2, 0.0)));
		col += mote * vec3(0.8, 0.88, 1.0) * smoothstep(0.35, 0.8, luma) * 0.9;
	}
	return col;
}

vec3 frost_fx(vec3 col, float k, vec2 uv, float t) {
	if (k <= 0.0) return col;
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	vec3 cool = mix(vec3(luma), col, 0.86) * vec3(0.95, 0.98, 1.03);
	col = mix(col, cool, clamp(k, 0.0, 1.0));
	vec2 g = uv * vec2(48.0, 27.0) + vec2(0.0, -t * 0.12);
	vec2 cell = floor(g);
	float h = hash(cell);
	vec2 fr = fract(g) - 0.5 - vec2(sin(t * 0.5 + h * 6.28) * 0.18, cos(t * 0.4 + h * 4.0) * 0.18);
	float mote = step(0.9, h) * smoothstep(0.09, 0.0, length(fr)) * (0.6 + 0.4 * sin(t * 1.3 + h * 20.0));
	col += vec3(1.0, 0.93, 0.76) * mote * 0.7 * clamp(k, 0.0, 1.0);
	col += vec3(1.0, 0.93, 0.76) * max(k - 1.0, 0.0) * 0.22;
	return col;
}

// 取一个世界在 uv 处的颜色；shift = 这个世界整体被推开的量（近景乘得更多）；valid = 是否落在画内
vec3 sample_world(sampler2D art, sampler2D dep, vec2 uv0, vec2 vv, float shift, int mode, float frost, float t, out float valid) {
	float d = texture(dep, uv0).r;
	vec2 uv = uv0;
	for (int i = 0; i < 3; i++) {
		uv = uv0 + vv * depth_k * (d - 0.45) - vec2(shift * (1.0 + 0.7 * d), 0.0);
		d = texture(dep, clamp(uv, 0.0, 1.0)).r;
	}
	valid = step(0.0, uv.x) * step(uv.x, 1.0);
	vec3 col = texture(art, clamp(uv, vec2(0.001), vec2(0.999))).rgb;
	col = fx(col, uv, mode, t);
	col = frost_fx(col, frost, uv, t);
	return col;
}

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 cam = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 v = normalize(cam - wpos);
	vec2 vv = vec2(v.x, -v.y) / max(v.z, 0.3) + par;
	vec2 uv0 = (UV - 0.5) / zoom + 0.5;
	float e = swap;
	float va;
	float vb;
	vec3 ca = sample_world(art_a, dep_a, uv0, vv, e * swap_dir, fx_a, frost_a, time_sec, va);
	vec3 cb = sample_world(art_b, dep_b, uv0, vv, (e - 1.0) * swap_dir, fx_b, frost_b, time_sec, vb);
	vec3 col = ca * va;
	if (e > 0.0001) {
		col = mix(col, cb, vb);
		// 两个世界之间露出的缝是纯墨黑
		col *= max(va, vb);
	}
	// 钟窗
	vec2 sp = vec2(SCREEN_UV.x * VIEWPORT_SIZE.x / VIEWPORT_SIZE.y, SCREEN_UV.y);
	vec2 wc = vec2(win_c.x * VIEWPORT_SIZE.x / VIEWPORT_SIZE.y, win_c.y);
	float inside = smoothstep(win_r + 0.004, win_r - 0.004, length(sp - wc));
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	vec3 outside = mix(vec3(luma) * vec3(0.86, 0.9, 1.0), col, 0.35) * (1.0 - out_dim);
	col = mix(outside, col, inside);
	col += vec3(flash) * inside;
	ALBEDO = col;
	ALPHA = opacity * mix(out_a, 1.0, inside);
}
