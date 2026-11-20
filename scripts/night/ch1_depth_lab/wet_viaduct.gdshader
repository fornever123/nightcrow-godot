shader_type canvas_item;
// 路线 1：透视湿石板街面微反光 + 暖灯拉伸倒影 + 细雨涟漪（绝非河水，只做湿青石薄反光）
render_mode blend_add, unshaded;

uniform float time_sec = 0.0;
uniform float cam_x = 0.0;
uniform vec4 lamp_x = vec4(2480.0, 3260.0, 4120.0, 5040.0);
uniform float hero_x = 3200.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	// UV.x 映射到世界 X（矩形覆盖 3600 世界宽），UV.y 0=街面后缘 1=街面前缘
	float wx = cam_x + (UV.x - 0.5) * 3200.0;
	float y_fade = smoothstep(0.0, 0.22, UV.y) * (1.0 - smoothstep(0.75, 1.0, UV.y));

	// 四盏暖白街灯在湿石板上拉出柔和纵向反光
	float warm = 0.0;
	for (int i = 0; i < 4; i++) {
		float lx = lamp_x[i];
		float d = abs(wx - lx);
		float spread = mix(110.0, 210.0, UV.y);
		float streak = exp(-pow(d / spread, 2.0));
		float ripple = 0.82 + 0.18 * sin(UV.y * 46.0 - time_sec * 3.8 + d * 0.06);
		warm += streak * ripple;
	}
	warm = min(warm, 1.35);

	// 细微石板高光纹理与雨滴小涟漪
	vec2 cell = floor(vec2(wx * 0.055, UV.y * 14.0));
	float h = hash21(cell);
	float pulse = fract(time_sec * (0.7 + h * 0.8) + h * 17.0);
	float ring = smoothstep(0.06, 0.0, abs(length(fract(vec2(wx * 0.055, UV.y * 14.0)) - 0.5) - pulse * 0.42)) * (1.0 - pulse);
	float wet_spec = ring * (0.14 + 0.32 * warm);

	// 主角脚下轻微紫白反光（让角色真正落进湿街光影里）
	float hd = abs(wx - hero_x);
	float hero_ref = exp(-pow(hd / 95.0, 2.0)) * smoothstep(0.15, 0.85, UV.y) * 0.16;

	vec3 col = vec3(1.0, 0.86, 0.62) * (warm * 0.16 + wet_spec * 0.65)
		+ vec3(0.68, 0.58, 0.92) * hero_ref;
	COLOR = vec4(col * y_fade, y_fade * clamp(warm * 0.35 + wet_spec + hero_ref, 0.0, 0.55));
}
