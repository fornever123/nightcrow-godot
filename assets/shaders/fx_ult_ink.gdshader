shader_type canvas_item;
render_mode unshaded, blend_disabled;
// 大招「月下斩」出刀定格（第四轮 §16.11）：两帧黑白。
// ult_fx 先在背景上铺一张“纸”（paper 色，地形和角色之下），这个全屏节点再读屏幕：
// 还是纸色的地方 → 纸；别的（地形、角色、敌人、近景、特效）→ 墨色剪影。
// §16.12：invert = 反过来（黑底白剪影），定格时两种交替着闪。
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform vec3 paper = vec3(0.95, 0.94, 0.98);
uniform vec3 ink = vec3(0.07, 0.05, 0.12);
uniform float tol = 0.05;
uniform bool invert = false;

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	bool bg = distance(c, paper) < tol;
	if (invert) {
		bg = !bg;
	}
	COLOR = vec4(bg ? paper : ink, 1.0);
}
