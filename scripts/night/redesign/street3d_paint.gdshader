shader_type spatial;
// 背景线 11-19 手绘构件卡片（RAIN_3D=U2）：画里自带的光影当底（自发光），真实灯光再加一层。
// 用 discard 抠形状、不写 ALPHA —— 透明背景的 SubViewport 里，透明度裁切 + 自发光会把整张卡冲成半透明白块。
render_mode cull_disabled, depth_draw_opaque;

uniform sampler2D tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tint = vec3(1.0);
uniform float lit = 0.55;
uniform float bake = 0.75;
uniform float rep = 1.0;
uniform bool flip = false;
uniform vec2 vrange = vec2(0.0, 1.0);    // 只取贴图的一段竖向范围（比如柱拱长条最上面那道台口梁）

void fragment() {
	vec2 uv = UV;
	if (flip) { uv.x = 1.0 - uv.x; }
	uv.x *= rep;
	uv.y = mix(vrange.x, vrange.y, uv.y);
	vec4 c = texture(tex, uv);
	if (c.a < 0.5) { discard; }
	ALBEDO = c.rgb * tint * lit;
	EMISSION = c.rgb * tint * bake;
	ROUGHNESS = 0.85;
	SPECULAR = 0.2;
}
