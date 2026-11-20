// 《光粒子重构》实验：粒子与浮雕面共用的投影和时间函数（两边逐格算得一模一样，实体面才能刚好在粒子飞走的那一格消失）

uniform vec2 scr = vec2(1920.0, 1080.0);
uniform float fpx = 2015.0;        // 竖直 FOV 30° 在 1080 高时的焦距（像素）
uniform float z0 = 2000.0;         // 画面放在镜头前多远
uniform float zr = 0.32;           // 深度起伏占 z0 的比例
uniform vec2 grid = vec2(640.0, 360.0);

uniform float T = -100.0;          // 本段转场的时间（秒），<0 表示还没开始
// 离开（A 画面化成光）
uniform int dep_mode = 0;          // 0 = 沿钟面顺时针扫；1 = 近景先走、由中心向外
uniform float dep_t0 = 0.0;
uniform float dep_span = 1.0;
uniform float fly_dur = 1.3;
uniform vec2 hub = vec2(950.0, 540.0);
uniform float twelve = -1.0838;    // 屏幕里 12 点方向（y 向下）
// 到达（B 画面由点云 → 线稿 → 上色 → 凝实）
uniform float paint_t0 = 100.0;
uniform float paint_span = 0.9;

float lab_hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

vec2 lab_cell_uv(vec2 uv) { return (floor(uv * grid) + 0.5) / grid; }

vec3 lab_map(mat4 cam, vec2 uv, float d) {
	float Z = z0 * (1.0 - zr * (d - 0.5) * 2.0);
	vec3 l = vec3((uv.x - 0.5) * scr.x / fpx * Z, (0.5 - uv.y) * scr.y / fpx * Z, -Z);
	return (cam * vec4(l, 1.0)).xyz;
}

float lab_depart(vec2 uv, float d, float rnd) {
	if (dep_mode == 0) {
		vec2 p = uv * scr - hub;
		float a = atan(p.y, p.x);
		float rel = fract((a - twelve) / 6.2831853 + 1.0);
		return rel * dep_span + length(p) / 1100.0 * 0.14 + rnd * 0.08;
	}
	vec2 c = (uv - 0.5) * vec2(1.78, 1.0);
	return (1.0 - d) * dep_span * 0.55 + length(c) * dep_span * 0.45 + rnd * 0.14;
}

float lab_paint(vec2 uv, float d, float rnd) {
	vec2 c = (uv - 0.5) * vec2(1.78, 1.0);
	return paint_t0 + (1.0 - d) * paint_span * 0.45 + length(c) * paint_span * 0.45 + rnd * 0.1;
}
