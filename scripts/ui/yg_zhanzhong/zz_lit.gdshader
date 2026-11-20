// [YG-MARK] 首页《斩钟》：受光的刻版层（钟面、齿轮、指针、碎片、字标、章节铜版）
// 贴图给形状，法线图给刻线起伏，自发光保住底色，灯只负责「扫过去那一下」的亮。
// clip_plane：世界空间裁切面（xyz 法线，w 常数），保留 dot(n,p)+w >= 0 的一侧；法线为 0 不裁。
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, specular_schlick_ggx;

uniform sampler2D tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform bool use_nrm = true;
uniform vec4 tint : source_color = vec4(1.0);
uniform vec4 glow_col : source_color = vec4(1.0);
uniform float glow = 0.8;
uniform float metal = 0.85;
uniform float rough = 0.3;
uniform float opacity = 1.0;
uniform vec4 clip_plane = vec4(0.0);
// 钟窗（11-15）：表盘中心开圆孔（贴图像素半径，<0 不开），孔沿一圈亮银细边；
// 光圈花瓣：只留一个扇形（贴图空间角度中心 / 半宽，半径上限），其余丢弃
uniform vec2 tex_px = vec2(1243.0, 1232.0);
uniform vec2 pivot_px = vec2(621.0, 615.5);
uniform float hole_px = -1.0;
uniform float hole_rim = 0.0;
uniform vec3 wedge = vec3(0.0, -1.0, 0.0);
// 机关舞台（11-15）：钟体分解件——只留贴图像素半径在 [ring.x, ring.y) 的一圈（ring.y <= 0 不用）
uniform vec2 ring = vec2(-1.0, -1.0);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (dot(clip_plane.xyz, clip_plane.xyz) > 0.0 && dot(clip_plane.xyz, wpos) + clip_plane.w < 0.0) {
		discard;
	}
	vec2 pp = UV * tex_px - pivot_px;
	float pr = length(pp);
	if (ring.y > 0.0 && (pr < ring.x || pr >= ring.y)) {
		discard;
	}
	if (hole_px > 0.0 && pr < hole_px) {
		discard;
	}
	if (wedge.y > 0.0) {
		float da = abs(mod(atan(pp.y, pp.x) - wedge.x + 3.14159265, 6.2831853) - 3.14159265);
		if (da > wedge.y || pr > wedge.z) {
			discard;
		}
	}
	vec4 c = texture(tex, UV);
	float band = (hole_px > 0.0 && hole_rim > 0.0) ? smoothstep(10.0, 3.0, pr - hole_px) : 0.0;
	c.a = max(c.a, band);
	if (c.a * opacity < 0.01) {
		discard;
	}
	ALBEDO = c.rgb * tint.rgb;
	if (use_nrm) {
		NORMAL_MAP = texture(nrm, UV).rgb;
	}
	METALLIC = metal;
	ROUGHNESS = rough;
	EMISSION = c.rgb * glow_col.rgb * glow;
	if (hole_px > 0.0 && hole_rim > 0.0) {
		ALBEDO = mix(ALBEDO, vec3(0.92, 0.92, 0.95), band);
		EMISSION += vec3(0.9, 0.9, 0.95) * band * hole_rim;
	}
	ALPHA = c.a * opacity;
}
