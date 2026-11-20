shader_type spatial;
// 《光粒子重构》实验：几十万颗带色带深度的光粒子。A 画面逐格化成光 → 绕钟轴卷成旋涡 → 落成 B 画面的立体点云
// → 沿轮廓亮成线稿 → 由近到远灌色 → 逐格交给实体浮雕面。全程三维，镜头可以从粒子中间穿过去。
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

#include "res://scripts/ui/yg_zhanzhong/lab/zz_lab_common.gdshaderinc"

uniform sampler2D tex_a : source_color, filter_linear;
uniform sampler2D dep_a : filter_linear;
uniform sampler2D edge_a : filter_linear;
uniform sampler2D tex_b : source_color, filter_linear;
uniform sampler2D dep_b : filter_linear;
uniform sampler2D edge_b : filter_linear;
uniform mat4 cam_a;
uniform mat4 cam_b;
uniform vec3 ax_a = vec3(0.0, 0.0, -2000.0);   // 旋涡轴经过的点（出发时）
uniform vec3 ax_b = vec3(0.0, 0.0, -3000.0);   // （到达时）
uniform vec3 ax_dir = vec3(0.0, 0.0, -1.0);
uniform float turns = 1.0;          // 整圈数（整数，保证落点严丝合缝）
uniform float pinch = 0.22;         // 飞行中向轴心收拢
uniform float stream = 900.0;       // 沿轴向前后拉开
uniform float noise_amp = 240.0;
uniform vec3 silver = vec3(0.78, 0.86, 1.0);
uniform float light_gain = 1.0;

varying vec3 v_col;
varying float v_a;
varying float v_soft;

void vertex() {
	vec2 cell = floor(VERTEX.xy * grid);
	vec2 uv = (cell + 0.5) / grid;
	float rnd = lab_hash(cell);
	float rnd2 = lab_hash(cell + 17.31);
	float da = textureLod(dep_a, uv, 0.0).r;
	float db = textureLod(dep_b, uv, 0.0).r;
	vec3 pa = lab_map(cam_a, uv, da);
	vec3 pb = lab_map(cam_b, uv, db);
	vec3 ca = textureLod(tex_a, uv, 0.0).rgb;
	vec3 cb = textureLod(tex_b, uv, 0.0).rgb;
	float eb = textureLod(edge_b, uv, 0.0).r;

	float t0 = dep_t0 + lab_depart(uv, da, rnd);
	float started = step(t0, T);
	float t = clamp((T - t0) / (fly_dur * (0.94 + 0.12 * rnd2)), 0.0, 1.0);
	float s = t * t * t * (t * (t * 6.0 - 15.0) + 10.0);
	float bell = sin(3.14159265 * t);

	// 旋涡：绕钟轴整圈转，半径先收后放，同时沿轴向前后拉开
	vec3 ax = normalize(ax_dir);
	vec3 o = mix(ax_a, ax_b, s);
	vec3 p = mix(pa, pb, s);
	vec3 v = p - o;
	vec3 vpar = dot(v, ax) * ax;
	vec3 vperp = (v - vpar) * (1.0 - pinch * bell * (0.55 + 0.45 * rnd));
	float ang = turns * 6.2831853 * s;
	vec3 vrot = vperp * cos(ang) + cross(ax, vperp) * sin(ang);
	p = o + vpar + vrot;
	// 整体连贯：拉开和扰动都按原画位置/深度算，看得到画面本身被拧成旋涡
	p += ax * (da - 0.45 + (rnd - 0.5) * 0.25) * stream * bell;
	p += vec3(sin(uv.y * 7.0 + T * 2.1), cos(uv.x * 9.0 + T * 1.7), sin((uv.x + uv.y) * 6.0 + T * 1.3)) * noise_amp * bell;

	// 颜色：起飞闪白 → 银白光流（带一点两边画面的颜色）→ 落成线稿 → 灌色
	float flash = 1.6 * exp(-t * 22.0) * started;
	vec3 c_dep = ca + silver * flash;
	float glint = step(0.992, rnd2) * 5.0;
	vec3 c_mid = mix(ca, cb, s) * (0.8 + 0.3 * bell) + silver * (0.12 * bell + glint) * light_gain;
	vec3 c_arr = silver * 1.5 * eb * eb * light_gain;
	vec3 c = mix(c_dep, c_mid, smoothstep(0.0, 0.3, t));
	c = mix(c, c_arr, smoothstep(0.62, 1.0, t));
	float pd = lab_paint(uv, db, rnd);
	float pq = clamp((T - pd) / 0.3, 0.0, 1.0);
	c += silver * 0.8 * sin(3.14159265 * pq) * eb;

	vec3 cam_pos = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float dist = max(length(p - cam_pos), 1.0);
	float grow = 1.0 + 0.5 * bell;
	POINT_SIZE = clamp(scr.x / grid.x * 1.12 * z0 / dist * grow, 1.0, 30.0);
	v_col = c;
	v_a = started * (1.0 - pq) * smoothstep(250.0, 900.0, dist);
	v_soft = smoothstep(0.02, 0.18, t) * (1.0 - smoothstep(0.82, 0.99, t));
	VERTEX = p;
}

void fragment() {
	float r = length(POINT_COORD - 0.5) * 2.0;
	float shape = mix(1.0, 1.0 - smoothstep(0.25, 1.0, r), v_soft);
	if (v_a * shape < 0.003) discard;
	ALBEDO = v_col;
	ALPHA = v_a * shape;
}
