shader_type canvas_item;
// 雨夜河岸街河面（street_backdrop.gd 的 _water，画在角色和刀光之后）：
//   实时倒影：把水线以上已经画好的画面（楼、灯、角色、刀光）沿水线翻进水里，越深越糊、越暗
//   流动：两层横向拉长的噪声往左流，扭曲倒影；第三层噪声把亮的倒影（灯、窗、钟楼红窗）切成断续的横向波光
//   水面本身：深青蓝底 + 几条顺流漂走的细亮纹 + 水线处一道暗边
// 换算全用屏幕导数（dFdx/dFdy 世界坐标），不依赖窗口尺寸和镜头缩放。

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D noise_tex : repeat_enable, filter_linear;
uniform float water_y = 665.0;                                    // 水线（世界 y）
uniform float mirror_skip = 85.0;   // 倒影从水线往上跳过多少再开始映：跳过河岸护墙，直接映街面（灯、橱窗、角色）
uniform float squash = 1.0;         // 倒影竖向比例（1 = 和真镜面一样；站在街上的角色整个映进露出的那条水里）
uniform vec4 deep : source_color = vec4(0.035, 0.05, 0.08, 1.0);  // 没有倒影处的水色
uniform vec4 tint : source_color = vec4(0.78, 0.85, 0.98, 1.0);   // 倒影偏冷（不要压太暗，深色角色的倒影靠它和湿街面倒影的对比读出来）
uniform float flow = 34.0;          // 往左流的速度（世界单位 / 秒）
uniform float wobble = 9.0;         // 倒影横向扭曲幅度（世界单位）
uniform float shimmer = 0.55;       // 灯光倒影被切碎的程度 0..1

varying vec2 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

float n(vec2 p) {
	return texture(noise_tex, p).r;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// 雨点打在河面上：错位格子里随机时刻冒出的压扁椭圆涟漪（和街面 rain_ground.gdshader 同一套）
float ripples(vec2 p, vec2 cell, float flat_y, float rate, float r_max, float seed) {
	vec2 id = floor(p / cell);
	vec2 f = fract(p / cell) - 0.5;
	float h = hash(id + seed);
	float h2 = hash(id + seed + 17.3);
	vec2 off = (vec2(h, h2) - 0.5) * 0.7;
	float ph = fract(TIME * rate * (0.7 + 0.6 * h2) + h * 11.0);
	vec2 d = (f - off) * cell;
	d.y /= flat_y;
	float ring = smoothstep(3.0, 0.0, abs(length(d) - ph * r_max)) * (1.0 - ph) * (1.0 - ph);
	return ring;
}

void fragment() {
	float depth = max(world.y - water_y, 0.0);
	float fade = clamp(depth / 260.0, 0.0, 1.0);          // 0 = 贴着水线，1 = 远处的水（街面取景时只露出 0~0.6 这一段）
	vec2 drift = vec2(TIME * flow, 0.0);
	// 扭曲：大波慢、小波快，都往左流（世界坐标采样，镜头动时波纹跟着世界走）
	float w1 = n((world + drift) * vec2(1.0 / 520.0, 1.0 / 46.0)) - 0.5;
	float w2 = n((world + drift * 1.7) * vec2(1.0 / 210.0, 1.0 / 19.0) + vec2(0.37, 0.11)) - 0.5;
	float dx_world = (w1 * 1.6 + w2) * wobble * (0.3 + fade * 1.0);
	float dy_world = (w2 * 0.6) * wobble * 0.35 * fade;
	// 世界距离 → 屏幕 UV：dFdx/dFdy 给出 1 个屏幕像素是多少世界单位
	float wpx_x = dFdx(world.x);
	float wpx_y = dFdy(world.y);
	vec2 uv = SCREEN_UV;
	// 水下 depth 处映的是 街面（水线 − mirror_skip）往上 depth × squash 处的画面
	float up = depth * (1.0 + squash) + mirror_skip + dy_world;
	uv.y -= up * SCREEN_PIXEL_SIZE.y / wpx_y;
	uv.x += dx_world * SCREEN_PIXEL_SIZE.x / wpx_x;
	vec3 refl;
	if (uv.y < 0.0 || uv.y > 1.0) {
		refl = deep.rgb * 1.6;                                // 翻出屏幕上沿：用水色代替
	} else {
		refl = textureLod(screen_tex, clamp(uv, vec2(0.001), vec2(0.999)), fade * 1.0).rgb;   // 越深越糊，但角色的倒影要保持能认出来
	}
	// 亮的倒影切成断续横向波光（灯、亮窗、钟楼红窗）
	float lum = dot(refl, vec3(0.3, 0.5, 0.2));
	float s = n((world + drift * 1.25) * vec2(1.0 / 70.0, 1.0 / 5.5) + vec2(0.71, 0.29));
	float streak = smoothstep(0.38, 0.62, s);
	float bright = smoothstep(0.22, 0.55, lum);
	refl *= mix(1.0, mix(0.25, 1.55, streak), bright * shimmer);
	// 水色：贴近水线倒影最清楚，越远越暗越糊
	float reflectivity = mix(0.92, 0.6, fade);
	vec3 col = mix(deep.rgb, refl * tint.rgb, reflectivity);
	// 顺流漂走的细亮纹
	float r = n((world + drift * 0.8) * vec2(1.0 / 160.0, 1.0 / 9.0) + vec2(0.13, 0.58));
	float line = smoothstep(0.70, 0.74, r) * (1.0 - smoothstep(0.74, 0.79, r));
	col += vec3(0.30, 0.36, 0.46) * line * (0.16 + 0.12 * fade);
	// 雨点涟漪：越远越小越淡（透视）
	float rp = ripples(world, vec2(70.0, 22.0), 0.3, 0.45, 30.0, 0.0) + ripples(world + vec2(35.0, 11.0), vec2(90.0, 28.0), 0.3, 0.35, 38.0, 3.7) * 0.7;   // 11-01 随雨量调小（0.8 / 0.6 → 0.45 / 0.35）
	col += vec3(0.46, 0.54, 0.68) * rp * 0.55 * (1.0 - 0.4 * fade);
	// 水线：护墙脚下一道暗边
	col *= mix(0.7, 1.0, smoothstep(0.0, 6.0, depth));
	COLOR = vec4(col, 1.0);
}
