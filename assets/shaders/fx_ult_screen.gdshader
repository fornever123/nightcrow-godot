shader_type canvas_item;
render_mode unshaded;
// 大招「绝影 · 鸦羽止」的屏幕级效果（读屏幕纹理，盖在世界和她之上、大招 UI 之下）：
//   画面沿刀线错开 / 冲击波扭曲（最多 4 个）/ 色差 / 径向速度线 / 暗角 / 颗粒。全部为 0 时原样输出。
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform vec2 screen_size = vec2(1280.0, 720.0);
uniform float split_y = 0.5;          // 刀线高度（SCREEN_UV）
uniform float split_px = 0.0;         // 上半往右错开多少像素（下半反向一半）
uniform vec4 shocks[4];               // xy = 中心（SCREEN_UV），z = 半径（屏幕高度的比例），w = 强度
uniform float aberration_px = 0.0;    // 红蓝错开多少像素
uniform float lines = 0.0;            // 径向速度线强度
uniform vec2 lines_center = vec2(0.5);
uniform float lines_seed = 0.0;       // 每帧换一次，线条跳动
uniform float vignette = 0.0;
uniform float grain = 0.0;
uniform float grain_seed = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float aspect = screen_size.x / screen_size.y;
	if (split_px != 0.0) {
		uv.x -= (uv.y < split_y ? split_px : -0.5 * split_px) / screen_size.x;
	}
	for (int i = 0; i < 4; i++) {
		vec4 sh = shocks[i];
		if (sh.w <= 0.0) {
			continue;
		}
		vec2 d = (uv - sh.xy) * vec2(aspect, 1.0);
		float r = length(d);
		float ring = 1.0 - smoothstep(0.0, 0.03, abs(r - sh.z));
		uv -= (d / max(r, 1e-4)) * ring * sh.w * 0.018 / vec2(aspect, 1.0);
	}
	vec3 col;
	if (aberration_px > 0.0) {
		vec2 o = vec2(aberration_px / screen_size.x, 0.0);
		col = vec3(texture(screen_tex, uv + o).r, texture(screen_tex, uv).g, texture(screen_tex, uv - o).b);
	} else {
		col = texture(screen_tex, uv).rgb;
	}
	if (lines > 0.0) {
		vec2 d = (SCREEN_UV - lines_center) * vec2(aspect, 1.0);
		float ang = atan(d.y, d.x);
		// 漫画集中线：角度上等宽 = 画面上是楔形（靠中心细、往外粗）；160 份里亮约三成，每根宽度和起点随机，
		// 硬边（两色，不做软渐变），只在外圈
		float u = (ang + 3.14159265) / 6.2831853 * 160.0;
		float id = floor(u);
		float h = hash(vec2(id, lines_seed));
		float h2 = hash(vec2(id * 1.7, lines_seed + 3.1));
		float half_w = 0.08 + 0.32 * h2;
		float wedge = 1.0 - smoothstep(half_w - 0.04, half_w, abs(fract(u) - 0.5));
		float start = 0.34 + 0.3 * h;
		float on = step(0.68, h) * wedge * smoothstep(start, start + 0.08, length(d));
		col = mix(col, vec3(0.95, 0.93, 1.0), on * lines);
	}
	vec2 v = (SCREEN_UV - 0.5) * vec2(1.0, 1.25);
	col *= 1.0 - vignette * smoothstep(0.32, 0.85, length(v));
	col += (hash(SCREEN_UV * screen_size + grain_seed * 17.0) - 0.5) * grain;
	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
