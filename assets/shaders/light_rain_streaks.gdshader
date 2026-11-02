shader_type canvas_item;
render_mode blend_add;
// 灯下被照亮的雨丝（光线线 2026-10-30，rain_lights.gd）：每盏灯一块矩形，里面按世界坐标算一条条往下落的雨丝，
// 只在灯光照得到的范围里亮（路灯：灯罩往下的光锥；壁灯：灯头周围一团）。角度和速度跟背景的雨粒子一致。
// 顶点色：r = 1 路灯 / 0 壁灯，g = 路灯灯头在矩形里的高度（0 = 顶），a = 强度（含火苗跳动）。UV：矩形内 0..1。

uniform vec3 col : source_color = vec3(1.0, 0.74, 0.46);
uniform float speed = 1350.0;     // 世界单位/秒（street_backdrop.RAIN_SPEED）
uniform float wind = -0.2;        // 每往下落 1，往左飘多少（RAIN_WIND）
uniform float cell = 9.0;         // 雨丝的横向间距（世界单位）
uniform float seg = 170.0;        // 同一列前后两根雨丝的平均间距
uniform float len = 38.0;         // 一根雨丝多长
uniform float width = 1.4;        // 多粗（世界单位）
uniform float density = 0.35;     // 多少列有雨（11-01 背景线随雨量调小：0.7 → 0.35）
uniform float gain = 1.1;

varying vec2 world;
varying vec4 vcol;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	vcol = COLOR;
}

float h1(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

void fragment() {
	vec2 d = normalize(vec2(wind, 1.0));
	vec2 nrm = vec2(d.y, -d.x);
	float u = dot(world, nrm);
	float v = dot(world, d);
	float id = floor(u / cell);
	float r1 = h1(id);
	float r2 = h1(id + 31.7);
	float r3 = h1(id + 77.3);
	float on = step(1.0 - density, r2);
	float cx = (id + 0.2 + 0.6 * r1) * cell;
	float across = smoothstep(width, 0.0, abs(u - cx));
	float period = seg * (0.7 + 0.6 * r3);
	float ph = fract((v - TIME * speed * (0.85 + 0.25 * r2)) / period + r1 * 7.0);
	float lf = len * (0.7 + 0.6 * r1) / period;
	float streak = step(ph, lf) * (ph / lf);   // 下端（往前落的那头）最亮
	float mask;
	if (vcol.r > 0.5) {
		float head_v = vcol.g;
		float dv = max(UV.y - head_v, 0.0) / (1.0 - head_v);
		float cone = mix(0.18, 1.0, sqrt(dv));
		mask = smoothstep(cone, cone * 0.25, abs(UV.x - 0.5) * 2.0) * smoothstep(-0.02, 0.04, UV.y - head_v);
		mask *= mix(1.0, 0.3, dv);                 // 离灯越远越暗
	} else {
		float r = length(UV - 0.5) * 2.0;
		mask = smoothstep(1.0, 0.15, r);
	}
	COLOR = vec4(col * (streak * across * on * mask * gain * vcol.a), 1.0);
}
