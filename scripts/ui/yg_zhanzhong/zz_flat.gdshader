// [YG-MARK] 首页《斩钟》：不受光的平涂层（底色、墨影、雨、斩缝、径向压暗）
// tex_rgb = 1 用贴图颜色 × tint；= 0 只用贴图的不透明度、颜色全取 tint（墨影）。
// radial = 1 时不用贴图，按 UV 到中心的距离画径向渐变（中心 alpha = tint.a，边缘 0）。
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
uniform bool use_tex = true;
uniform float tex_rgb = 1.0;
uniform vec4 tint : source_color = vec4(1.0);
uniform float opacity = 1.0;
uniform float radial = 0.0;
uniform vec4 clip_plane = vec4(0.0);
// 沿 UV.x 的亮带（斩缝那道走过去的光）：center、half width；<0 不用
uniform vec2 band = vec2(-1.0, 0.0);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (dot(clip_plane.xyz, clip_plane.xyz) > 0.0 && dot(clip_plane.xyz, wpos) + clip_plane.w < 0.0) {
		discard;
	}
	vec4 c = use_tex ? texture(tex, UV) : vec4(1.0);
	vec3 col = mix(vec3(1.0), c.rgb, tex_rgb) * tint.rgb;
	float a = c.a * tint.a * opacity;
	if (radial > 0.5) {
		float r = length(UV - 0.5) * 2.0;
		a = tint.a * opacity * (1.0 - smoothstep(0.15, 1.0, r)) * mix(1.0, 0.75, smoothstep(0.15, 0.6, r));
	}
	if (band.x >= 0.0) {
		float d = abs(UV.x - band.x) / max(band.y, 1e-4);
		a *= max(0.0, 1.0 - d * d);
	}
	if (a < 0.003) {
		discard;
	}
	ALBEDO = col;
	ALPHA = a;
}
