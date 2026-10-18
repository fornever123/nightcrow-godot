shader_type canvas_item;
// 地平线薄雾：噪声图当浓度，上下两端淡出。
uniform vec4 tint : source_color = vec4(0.62, 0.72, 0.92, 1.0);
uniform float strength = 0.30;
varying float local_y;

void vertex() {
	local_y = VERTEX.y;
}

void fragment() {
	float n = texture(TEXTURE, UV).r;
	float y = local_y / 96.0;
	float band = smoothstep(0.0, 0.45, y) * (1.0 - smoothstep(0.6, 1.0, y));
	COLOR = vec4(tint.rgb, strength * band * smoothstep(0.35, 0.85, n));
}
