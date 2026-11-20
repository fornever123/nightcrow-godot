shader_type spatial;
// 《光粒子重构》实验：画面的实体浮雕面（按深度图顶起的网格）。
// mode 1 = 出发画面：粒子飞走的那一格同时挖掉；mode 2 = 到达画面：粒子灌完色的那一格同时凝实；mode 0 = 常驻全显
render_mode unshaded, cull_disabled, blend_mix;

#include "res://scripts/ui/yg_zhanzhong/lab/zz_lab_common.gdshaderinc"

uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform sampler2D dep : filter_linear;
uniform mat4 cam;
uniform int mode = 0;

void vertex() {
	vec2 uv = VERTEX.xy;
	VERTEX = lab_map(cam, uv, textureLod(dep, uv, 0.0).r);
}

void fragment() {
	vec2 cell = floor(UV * grid);
	vec2 cuv = (cell + 0.5) / grid;
	float rnd = lab_hash(cell);
	float d = texture(dep, cuv).r;
	if (mode == 1 && T >= dep_t0 + lab_depart(cuv, d, rnd)) discard;
	float a = 1.0;
	if (mode == 2) {
		a = clamp((T - lab_paint(cuv, d, rnd)) / 0.3, 0.0, 1.0);
		if (a <= 0.0) discard;
	}
	ALBEDO = texture(tex, UV).rgb;
	ALPHA = a;
}
