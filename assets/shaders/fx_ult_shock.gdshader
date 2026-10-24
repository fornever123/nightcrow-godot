shader_type canvas_item;
render_mode unshaded, blend_disabled;
// 大招「千刃」：冲击后期（全屏）。读屏幕，以 center（屏幕 UV）为圆心：
//   径向模糊（往圆心方向采样几次）+ 红蓝色差（沿径向错开）+ 一圈往外扩的折射冲击波。
// strength = 0 时等于原画面（ult_fx 平时把这个节点藏起来）。
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform vec2 center = vec2(0.5);
uniform float strength = 0.0;      // 0～1：径向模糊 + 色差
uniform float wave_r = -1.0;       // 冲击波半径（屏幕高度为 1；<0 = 没有）
uniform float wave_w = 0.06;
uniform float wave_amp = 0.0;      // 冲击波折射强度（屏幕 UV）
uniform float aspect = 1.7778;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 d = uv - center;
	vec2 da = vec2(d.x * aspect, d.y);
	float r = length(da);
	vec2 n = r > 0.0001 ? d / r : vec2(0.0);
	if (wave_r > 0.0) {
		float k = 1.0 - smoothstep(0.0, wave_w, abs(r - wave_r));
		uv -= n * k * wave_amp;
	}
	float blur = 0.045 * strength * clamp(r * 1.4, 0.0, 1.0);
	float ca = 0.006 * strength * clamp(r * 2.0, 0.0, 1.0);
	vec3 acc = vec3(0.0);
	for (int i = 0; i < 6; i++) {
		float t = float(i) / 5.0;
		vec2 o = uv - d * blur * t;
		acc.r += texture(screen_tex, o + n * ca).r;
		acc.g += texture(screen_tex, o).g;
		acc.b += texture(screen_tex, o - n * ca).b;
	}
	COLOR = vec4(acc / 6.0, 1.0);
}
