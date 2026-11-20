shader_type canvas_item;

// 首页后期：只负责“电影感”——亮部泛光、轻微色散、暗角、颗粒、极淡的横向扫描。
// 不改变构图，参数固定。

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float bloom_amt = 0.52;
uniform float threshold = 0.64;
uniform float grain = 0.042;
uniform float vignette = 0.62;
uniform float chroma = 0.0005;
uniform float scan = 0.022;

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec3 pick(vec2 uv) {
	vec3 c = textureLod(screen_tex, uv, 0.0).rgb;
	float l = max(max(c.r, c.g), c.b);
	return c * smoothstep(threshold, threshold + 0.30, l);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 c = uv - vec2(0.5);
	float k = chroma * (0.35 + dot(c, c) * 2.6);
	vec3 col;
	col.r = textureLod(screen_tex, uv + c * k, 0.0).r;
	col.g = textureLod(screen_tex, uv, 0.0).g;
	col.b = textureLod(screen_tex, uv - c * k, 0.0).b;

	// 亮部泛光：两圈半径、十二个方向，权重按距离衰减
	vec3 bl = vec3(0.0);
	float wsum = 0.0;
	for (int i = 0; i < 12; i++) {
		float a = float(i) * 0.5235988 + 0.26;
		vec2 dir = vec2(cos(a), sin(a));
		vec2 o1 = dir * SCREEN_PIXEL_SIZE * 7.0;
		vec2 o2 = dir * SCREEN_PIXEL_SIZE * 22.0;
		bl += pick(uv + o1) * 1.0;
		bl += pick(uv + o2) * 0.62;
		wsum += 1.62;
	}
	bl /= wsum;
	col += bl * bloom_amt;

	// 轻柔的胶片压缩，保留亮部层次
	col = col / (1.0 + col * 0.22);

	// 暗角
	float v = length(c * vec2(1.06, 0.98)) * 1.34;
	col *= 1.0 - vignette * pow(clamp(v, 0.0, 1.0), 2.35);

	// 极淡的横向扫描（片头质感）
	col *= 1.0 - scan * (0.5 + 0.5 * sin(uv.y * 720.0 * 0.32));

	// 颗粒
	float g = hash21(uv * vec2(1280.0, 720.0) + vec2(SCREEN_PIXEL_SIZE.x * 0.0, 0.0));
	col += (g - 0.5) * grain;

	COLOR = vec4(max(col, vec3(0.0)), 1.0);
}
