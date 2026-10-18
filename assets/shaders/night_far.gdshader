shader_type canvas_item;
// 远景：海面波光（地平线以下横向轻微扭动，越近越大）+ 星星闪烁 + 月光路闪点。
// 星星只认“比周围亮很多的小点”（局部对比度），月亮和云这种大块亮面不会被闪。
uniform float horizon = 0.58;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float luma(vec3 c) { return dot(c, vec3(0.3, 0.45, 0.25)); }

void fragment() {
	vec2 uv = UV;
	float d = uv.y - horizon;
	if (d > 0.0) {
		float k = smoothstep(0.0, 0.42, d);
		uv.x += sin(uv.y * 420.0 / (0.25 + k) - TIME * 1.6) * 0.0016 * k;
		uv.y += sin(uv.x * 90.0 + TIME * 1.1) * 0.0007 * k;
	}
	vec4 c = texture(TEXTURE, uv);
	float lum = luma(c.rgb);
	vec2 px = TEXTURE_PIXEL_SIZE * 2.5;
	float around = (luma(texture(TEXTURE, uv + vec2(px.x, 0.0)).rgb) + luma(texture(TEXTURE, uv - vec2(px.x, 0.0)).rgb)
		+ luma(texture(TEXTURE, uv + vec2(0.0, px.y)).rgb) + luma(texture(TEXTURE, uv - vec2(0.0, px.y)).rgb)) * 0.25;
	float point = smoothstep(0.08, 0.22, lum - around) * smoothstep(0.4, 0.65, lum);
	vec2 cell = floor(UV * vec2(320.0, 180.0));
	float h = hash(cell);
	if (d < -0.01) {
		c.rgb *= 1.0 + point * 0.7 * sin(TIME * (1.2 + h * 2.5) + h * 40.0);
	} else if (d > 0.0) {
		// 月光路上的亮点偶尔闪一下
		float glint = point * step(0.9, hash(cell + floor(TIME * 4.0 + h)));
		c.rgb += vec3(0.4, 0.45, 0.55) * glint;
	}
	COLOR = c;
}
