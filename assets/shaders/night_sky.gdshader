shader_type canvas_item;
// 星空层：只认“比周围亮很多的小点”当星星，让它们各自闪烁（银河的大片亮面不闪）。
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float luma(vec3 c) { return dot(c, vec3(0.3, 0.45, 0.25)); }

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float lum = luma(c.rgb);
	vec2 px = TEXTURE_PIXEL_SIZE * 2.5;
	float around = (luma(texture(TEXTURE, UV + vec2(px.x, 0.0)).rgb) + luma(texture(TEXTURE, UV - vec2(px.x, 0.0)).rgb)
		+ luma(texture(TEXTURE, UV + vec2(0.0, px.y)).rgb) + luma(texture(TEXTURE, UV - vec2(0.0, px.y)).rgb)) * 0.25;
	float point = smoothstep(0.08, 0.22, lum - around) * smoothstep(0.4, 0.65, lum);
	float h = hash(floor(UV / TEXTURE_PIXEL_SIZE / 4.0));
	c.rgb *= 1.0 + point * 0.7 * sin(TIME * (1.2 + h * 2.5) + h * 40.0);
	COLOR = c;
}
