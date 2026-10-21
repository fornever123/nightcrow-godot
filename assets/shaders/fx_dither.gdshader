shader_type canvas_item;
render_mode unshaded, blend_mix;
// 像素特效：透明度不画成半透明，而是用 4×4 拜耳抖动“有/没有”（像素画的淡出方式）。
// cell = 抖动格子大小（屏幕像素）。特效小画布里 1 格就是 1 个画布像素，所以 cell = 1；
// 直接画在世界里的残影用 cell = 2（和背景像素块一样大）。
// silhouette = 只取贴图形状，颜色用 modulate（残影用）。
uniform float cell = 1.0;
uniform bool silhouette = false;
varying vec4 v_mod;

void vertex() {
	v_mod = COLOR;
}

float bayer4(vec2 p) {
	ivec2 q = ivec2(mod(floor(p), 4.0));
	int i = q.y * 4 + q.x;
	float m[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return (m[i] + 0.5) / 16.0;
}

void fragment() {
	vec4 c = COLOR;
	if (silhouette) {
		c = vec4(v_mod.rgb, texture(TEXTURE, UV).a * v_mod.a);
	}
	if (c.a < bayer4(FRAGCOORD.xy / cell)) {
		discard;
	}
	COLOR = vec4(c.rgb, 1.0);
}
