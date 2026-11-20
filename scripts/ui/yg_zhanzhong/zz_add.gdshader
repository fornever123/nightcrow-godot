// [YG-MARK] 首页《斩钟》：叠加发光层（斩缝漏进来的天光、光尘）
shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
uniform bool use_tex = true;
uniform vec4 tint : source_color = vec4(1.0);
uniform float opacity = 1.0;
uniform vec4 clip_plane = vec4(0.0);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (dot(clip_plane.xyz, clip_plane.xyz) > 0.0 && dot(clip_plane.xyz, wpos) + clip_plane.w < 0.0) {
		discard;
	}
	vec4 c;
	if (use_tex) {
		c = texture(tex, UV);
	} else {
		// 软圆点
		float r = length(UV - 0.5) * 2.0;
		float k = max(0.0, 1.0 - r);
		c = vec4(mix(vec3(0.62, 0.52, 1.0), vec3(1.0, 0.99, 1.0), k * k), k * k * k);
	}
	ALBEDO = c.rgb * tint.rgb * c.a * tint.a * opacity;
	ALPHA = 1.0;
}
