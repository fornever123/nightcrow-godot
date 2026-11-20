shader_type canvas_item;
// 影街 · 背景调色（只压在角色后面：z −76，站立层之后、角色之前）。
// 用户 11-18：“还有这个蓝色滤镜估计也是问题”——把蓝色滤镜退掉：偏蓝的地方推回中性炭灰，暖灯不动；
// 轻提亮 + S 曲线，最深的暗部才留一点冷。
render_mode unshaded;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float neutral = 0.12;     // 偏蓝像素往中性灰推多少（11-18 用户选“色调 3”：只退蓝滤镜，保留原画颜色）
uniform float exposure = 1.0;
uniform float contrast = 1.08;
uniform float pivot = 0.18;
uniform vec3 grey_tint = vec3(1.02, 1.0, 0.97);   // 石头微暖
// 11-19 主次：以角色为中心，越往屏幕边、越往上越暗一点（只压背景，暖灯少压一半）——满屏一样亮 → 视线落在人走的那一层
uniform vec2 focus = vec2(0.5, 0.72);   // 角色在屏幕上的位置（SCREEN_UV）
uniform float focus_amt = 0.0;          // 离角色最远处压暗多少
uniform float top_amt = 0.0;            // 屏幕最上沿压暗多少
uniform float aspect = 1.7778;

void fragment() {
	vec3 lin = texture(screen_tex, SCREEN_UV).rgb;
	vec3 over = max(lin - vec3(1.0), vec3(0.0));
	vec3 c = pow(clamp(lin, 0.0, 1.0), vec3(1.0 / 2.2));
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	float warm = clamp((c.r - c.b) * 4.0, 0.0, 1.0);          // 灯光、窗灯：保护
	c = mix(c, vec3(l) * grey_tint, neutral * (1.0 - warm));
	c = (c - pivot) * contrast + pivot;
	c *= exposure;
	c = mix(c, c * vec3(0.95, 0.98, 1.03), 1.0 - smoothstep(0.0, 0.12, l));   // 最深的暗部一点冷
	float d = length((SCREEN_UV - focus) * vec2(aspect, 1.0));
	float far_k = focus_amt * smoothstep(0.3, 1.3, d);
	float top_k = top_amt * (1.0 - smoothstep(0.05, 0.6, SCREEN_UV.y));
	c *= 1.0 - (far_k + top_k) * (1.0 - warm * 0.5);
	COLOR = vec4(pow(max(c, vec3(0.0)), vec3(2.2)) + over, 1.0);
}
