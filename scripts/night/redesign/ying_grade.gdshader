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
// 11-19 对照渎神2 / 终焉之莉莉 / 玛格诺利亚：参照几乎没有纯黑，暗部是“有颜色的暗”；远处更灰更雾（空气透视）；冷暗暖亮。
// 全部默认 0 = 不生效，D2 下由 ying_look.gd 打开。冷色只用灰蓝 / 深青，不碰紫（红线）。
uniform float shadow_lift = 0.0;                    // 暗部抬起多少（往 shadow_col 靠）
uniform vec3 shadow_col = vec3(0.07, 0.085, 0.10);  // 暗部底色（按屏幕显示值填，石板灰蓝，G≈B 不偏紫）
uniform float haze_amt = 0.0;                       // 屏幕上半截往雾色靠多少（远处变灰变雾，而不是变黑）
uniform vec3 haze_col = vec3(0.15, 0.165, 0.18);   // 雾色（按屏幕显示值填）
uniform float split_amt = 0.0;                      // 冷暗暖亮：暗部往冷、亮部往暖
uniform float sat = 1.0;                            // 饱和度
uniform float haze_drift = 0.0;                     // 雾成团、缓慢飘：0 = 均匀雾，1 = 团块明显
uniform float cam_x = 0.0;                          // 镜头世界 x（雾带一点视差）

float _h2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float _vn(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(_h2(i), _h2(i + vec2(1, 0)), f.x), mix(_h2(i + vec2(0, 1)), _h2(i + vec2(1, 1)), f.x), f.y);
}
float _fbm(vec2 p) { return 0.55 * _vn(p) + 0.3 * _vn(p * 2.03 + 7.1) + 0.15 * _vn(p * 4.1 + 3.3); }

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
	// 远处变雾：上半截（离角色远的地方）往雾色靠，暖灯少靠
	float up = 1.0 - smoothstep(0.08, 0.62, SCREEN_UV.y);
	vec2 fp = vec2(SCREEN_UV.x * aspect * 1.6 + cam_x * 0.00035 + TIME * 0.018, SCREEN_UV.y * 2.2 - TIME * 0.004);
	float clump = mix(1.0, mix(0.35, 1.55, smoothstep(0.25, 0.75, _fbm(fp))), haze_drift);
	c = mix(c, pow(haze_col, vec3(1.0 / 2.2)), clamp(haze_amt * clump, 0.0, 0.9) * up * (1.0 - warm * 0.6));
	// 有颜色的暗：越暗越往暗部底色靠（不是整体加灰，亮处不动）
	float l2 = dot(c, vec3(0.299, 0.587, 0.114));
	// 在屏幕显示值里做“托底”：0 → shadow_col，1 → 1，中间线性——暗部里的明暗层次保留，只是不再掉成纯黑
	vec3 dsp = pow(max(c, vec3(0.0)), vec3(2.2));
	dsp = mix(dsp, shadow_col + dsp * (vec3(1.0) - shadow_col), shadow_lift);
	c = pow(dsp, vec3(1.0 / 2.2));
	// 冷暗暖亮 + 饱和
	l2 = dot(c, vec3(0.299, 0.587, 0.114));
	c += split_amt * (vec3(-0.015, 0.0, 0.025) * (1.0 - smoothstep(0.3, 0.55, l2)) + vec3(0.02, 0.006, -0.02) * smoothstep(0.55, 0.8, l2));   // c 是 1/2.2 次方空间：0.3≈屏幕 0.07，0.55≈0.27
	c = mix(vec3(l2), c, sat);
	COLOR = vec4(pow(max(c, vec3(0.0)), vec3(2.2)) + over, 1.0);
}
