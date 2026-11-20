// [YG-MARK] 字成城（11-08）：泛光。uThr > 0 时只留亮部。
shader_type canvas_item;
render_mode blend_disabled, unshaded;

uniform sampler2D uSrc : filter_linear, repeat_disable;
uniform vec2 uTexel = vec2(.002, .0035);
uniform float uThr = 0.0;

void fragment() {
	vec3 c = vec3(0.0);
	float tot = 0.0;
	for (int x = -3; x <= 3; x++) {
		for (int y = -3; y <= 3; y++) {
			float w = exp(-float(x * x + y * y) / 5.0);
			c += texture(uSrc, UV + vec2(float(x), float(y)) * uTexel).rgb * w;
			tot += w;
		}
	}
	c /= tot;
	if (uThr > 0.0) {
		float l = max(max(c.r, c.g), c.b);
		c *= smoothstep(uThr, uThr + .28, l);
	}
	COLOR = vec4(c, 1.0);
}
