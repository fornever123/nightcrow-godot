shader_type canvas_item;
render_mode unshaded, blend_disabled;
// 大招「月下斩」（第四轮 §16.12）：时间停住时背景褪色压暗。
// ult_fx 在地形 / 夜景之后（z −3）读屏幕：去饱和、压暗、微微偏冷；角色、刀光、残影都画在它后面，不受影响。
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float amount = 0.0;

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	vec3 g = vec3(l) * vec3(0.93, 0.92, 1.0);
	c = mix(c, g, 0.85 * amount);
	c *= 1.0 - 0.52 * amount;
	COLOR = vec4(c, 1.0);
}
