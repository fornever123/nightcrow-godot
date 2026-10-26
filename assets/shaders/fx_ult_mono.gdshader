shader_type canvas_item;
render_mode unshaded;
// 大招「绝影」：整屏褪成黑白、压暗、提一点对比（读屏幕纹理，放在世界和光影后期之上、大招 UI 之下）。
// 收尾时颜色从刀线往上下恢复：离 reveal_y 这条水平线 reveal_r 以内的地方先回到彩色。
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float amount : hint_range(0.0, 1.0) = 0.0;   // 去饱和程度
uniform float dim : hint_range(0.0, 1.0) = 0.0;      // 压暗
uniform float contrast = 1.15;
uniform float reveal_y = 0.5;                        // 刀线在屏幕上的高度（SCREEN_UV 的 y）
uniform float reveal_r = 0.0;                        // 颜色恢复到离刀线多远（SCREEN_UV 单位，0 = 不恢复）

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float colored = reveal_r > 0.0 ? 1.0 - smoothstep(reveal_r - 0.1, reveal_r, abs(SCREEN_UV.y - reveal_y)) : 0.0;
	float a = amount * (1.0 - colored);
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	vec3 g = mix(c, vec3(l), a);
	g = (g - 0.5) * mix(1.0, contrast, a) + 0.5;
	g *= 1.0 - dim * (1.0 - colored);
	COLOR = vec4(clamp(g, 0.0, 1.0), 1.0);
}
