shader_type canvas_item;
// 水里的倒影：贴图已 flip_v，越往下越淡、越碎、越偏海水色。
uniform float strength = 0.4;
uniform float ripple = 3.0;
uniform vec4 tint : source_color = vec4(0.14, 0.22, 0.45, 1.0);
uniform float tint_amt = 0.55;
varying float depth;

void vertex() {
	depth = VERTEX.y;
}

void fragment() {
	float k = clamp(depth / 90.0, 0.0, 1.0);
	vec2 px = TEXTURE_PIXEL_SIZE;
	vec2 uv = UV;
	uv.x += sin(depth * 0.55 - TIME * 2.4) * px.x * ripple * (0.4 + k * 1.6);
	vec4 c = texture(TEXTURE, uv);
	float bands = 0.75 + 0.25 * sin(depth * 1.3 + TIME * 3.0);
	c.rgb = mix(c.rgb, tint.rgb, tint_amt + 0.25 * k);
	c.a *= strength * (1.0 - k) * bands;
	COLOR = c;
}
