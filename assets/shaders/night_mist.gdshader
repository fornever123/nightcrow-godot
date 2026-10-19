shader_type canvas_item;
// 水面薄雾（光影第一版）：贴着步道后面的水面飘的一条雾带，下浓上淡，两层噪声往相反方向慢慢流。
// 画在背景像素化那层之后（z −74），雾是平滑的，不被量化成色块。
uniform vec4 tint : source_color = vec4(0.60, 0.70, 0.90, 1.0);
uniform float strength = 0.5;
uniform float h = 120.0;          // 雾带高度（容器像素）
uniform float t = 0.0;
varying float ly;

void vertex() {
	ly = VERTEX.y;
}

void fragment() {
	float n1 = texture(TEXTURE, UV + vec2(t * 0.004, 0.0)).r;
	float n2 = texture(TEXTURE, UV * vec2(1.6, 1.25) + vec2(-t * 0.003, 0.37)).r;
	float n = n1 * 0.6 + n2 * 0.4;
	float y = clamp(ly / h, 0.0, 1.0);          // 0 = 雾带顶，1 = 水面
	float band = smoothstep(0.0, 0.9, y) * (1.0 - smoothstep(0.94, 1.0, y));
	COLOR = vec4(tint.rgb, strength * band * (0.25 + 0.75 * smoothstep(0.3, 0.8, n)));
}
