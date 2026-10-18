shader_type canvas_item;
render_mode blend_premul_alpha;
// 角色/特效序列帧默认材质：只做高清采样（训练场、特效、拖尾都用它）。夜景里玩家换成 char_light（同样包含高清采样）。
#include "res://assets/shaders/char_hq.gdshaderinc"

void vertex() {
	hq_mod = COLOR;
}

void fragment() {
	vec4 c;
	HQ_SAMPLE(c, UV)
	COLOR = hq_out(c);
}
