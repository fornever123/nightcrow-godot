shader_type canvas_item;
// 背景线 11-18 立体感试验 · 路线 A「糊板」（空洞骑士 BlurPlane 的做法）：放在站立层正后面，
// 把它后面已经画好的远景整块糊掉、再蒙一层冷雾，近处站立层和角色就从背景里跳出来。
render_mode unshaded;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float radius = 2.0;                                  // 屏幕像素
uniform vec4 tint : source_color = vec4(0.15, 0.19, 0.27, 1.0);
uniform float haze = 0.14;

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE * radius;
	vec3 acc = vec3(0.0);
	float ws = 0.0;
	for (int i = -3; i <= 3; i++) {
		for (int j = -3; j <= 3; j++) {
			float w = exp(-float(i * i + j * j) / 8.0);
			acc += textureLod(screen_tex, SCREEN_UV + vec2(float(i), float(j)) * px, 0.0).rgb * w;
			ws += w;
		}
	}
	COLOR = vec4(mix(acc / ws, tint.rgb, haze), 1.0);
}
