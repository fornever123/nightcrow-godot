shader_type canvas_item;
render_mode unshaded, blend_disabled;
// 大招「绝影」冲击帧：读屏幕，按亮度二值化后反色（亮的变黑剪影、暗的变白底），整体略带一点紫白。
// 只在砸中那一下显示 2～3 帧（动画里的“冲击帧”）。
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float threshold = 0.22;
uniform vec3 paper = vec3(0.93, 0.9, 1.0);
uniform vec3 ink = vec3(0.04, 0.02, 0.08);
uniform float flip = 0.0;   // 1 = 黑底白剪影

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	bool lit = l > threshold;
	if (flip > 0.5) {
		lit = !lit;
	}
	COLOR = vec4(lit ? ink : paper, 1.0);
}
