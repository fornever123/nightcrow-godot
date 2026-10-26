shader_type canvas_item;
// 大招「绝影」冷峻版冲击帧：角色 / 影整个画成一种纯色剪影（只保留形状的 alpha）。
uniform vec4 tint : source_color = vec4(0.0, 0.0, 0.0, 1.0);

void fragment() {
	float a = step(0.35, COLOR.a);
	COLOR = vec4(tint.rgb, a * tint.a);
}
