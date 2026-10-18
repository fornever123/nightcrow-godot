shader_type canvas_item;
// 海面：逐行视差（越靠下越近、跟镜头走得越快）+ 波纹扭动 + 程序生成的月光带。
// 月光带固定在月亮下方（不随镜头动），带里的亮点取自海面波纹，所以会跟着水波走。
// 精灵贴着屏幕放（左边多画 margin），贴图横向重复。
uniform float cam_x = 0.0;          // 屏幕左边缘的世界 x
uniform float margin = 48.0;
uniform float top_y = 417.0;        // 精灵顶边的屏幕 y（= 地平线）
uniform float bridge_y = 425.0;     // 桥脚（0.42）
uniform float back_y = 572.0;       // 步道后沿（1.0）
uniform float front_y = 648.0;      // 步道前沿下方的水面（1.0）
uniform float bottom_f = 1.25;      // 屏幕最底下那一行的视差
uniform float far_f = 0.12;         // 地平线那一行
uniform float bridge_f = 0.42;
uniform float band_x = 1010.0;      // 月光带中心（屏幕 x）
uniform float band_gain = 1.25;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float luma(vec3 c) { return dot(c, vec3(0.3, 0.45, 0.25)); }

float factor(float sy) {
	if (sy < bridge_y) return mix(far_f, bridge_f, clamp((sy - top_y) / max(bridge_y - top_y, 1.0), 0.0, 1.0));
	if (sy < back_y) return mix(bridge_f, 1.0, (sy - bridge_y) / max(back_y - bridge_y, 1.0));
	if (sy < front_y) return 1.0;
	return mix(1.0, bottom_f, clamp((sy - front_y) / max(720.0 - front_y, 1.0), 0.0, 1.0));
}

void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE;
	float lx = UV.x / px.x;                 // 精灵内的像素列
	float ly = UV.y / px.y;                 // 精灵内的像素行
	float sx = lx - margin;                 // 屏幕 x
	float sy = top_y + ly;                  // 屏幕 y
	float k = clamp(ly / (720.0 - top_y), 0.0, 1.0);
	float tx = sx + cam_x * factor(sy);
	tx += sin(ly * 1.6 / (0.25 + k) - TIME * 1.6) * 0.9 * k;
	float ty = ly + sin(tx * 0.06 + TIME * 1.1) * 0.35 * k;
	vec2 uv = vec2(tx * px.x, clamp(ty, 0.0, 1.0 / px.y - 1.0) * px.y);
	vec4 c = texture(TEXTURE, uv);
	// 月光带：越近越宽；亮度由水波的亮纹决定
	float bw = mix(34.0, 130.0, k);
	float dx = (sx - band_x) / bw;
	float band = exp(-dx * dx * 1.7);
	float l0 = luma(c.rgb);
	float l1 = luma(texture(TEXTURE, uv + vec2(5.0 * px.x, 0.0)).rgb) + luma(texture(TEXTURE, uv - vec2(5.0 * px.x, 0.0)).rgb);
	float crest = clamp((l0 - l1 * 0.5) * 5.0 + 0.3, 0.0, 1.0);
	float shimmer = 0.8 + 0.2 * sin(TIME * 2.7 + sy * 0.9 + sx * 0.03);
	float near_hz = 1.0 - smoothstep(0.0, 0.25, k);
	vec3 moon = vec3(0.86, 0.9, 1.0);
	c.rgb += moon * band * band_gain * ((0.12 + 0.22 * near_hz) + 0.95 * crest * crest * shimmer);
	// 带里偶尔闪的亮点
	vec2 cell = floor(vec2(tx / 3.0, ly / 2.0));
	float g = step(0.985, hash(cell + floor(TIME * 5.0 + hash(cell) * 7.0))) * crest;
	c.rgb += moon * g * band * 0.8;
	COLOR = c;
}
