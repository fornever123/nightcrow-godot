shader_type canvas_item;
render_mode unshaded;
// 大招地图斩的整屏后期（10-31，照 Remotion UltMapSlashV4 的 filter）：盖在世界、她和斩线上面。
//   mode 1 冲击帧白底黑剪影：grayscale(1) brightness(2.6) contrast(6)；mode 2 同上再反相；
//   mode 3 时停：grayscale(0.85) contrast(1.25)；blur > 0 甩镜头那几帧的模糊（像素）
//   hblur > 0 挥刀甩进地图斩的横向模糊（预览 17 的 SVG feGaussianBlur stdDeviation="hblur 0"）；
//   gain / con 爆发帧的 brightness / contrast（按 CSS 的顺序：先乘亮度，再绕 0.5 拉反差）
//   white 刀光白屏（26×2b：地图斩第一帧整屏 white_color）

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform int mode = 0;
uniform float blur = 0.0;
uniform float hblur = 0.0;
uniform float gain = 1.0;
uniform float con = 1.0;
uniform float white = 0.0;
uniform vec4 white_color : source_color = vec4(0.984, 0.976, 1.0, 1.0);

void fragment() {
	vec2 px = 1.0 / vec2(1280.0, 720.0);
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	if (blur > 0.3) {
		vec3 acc = c;
		float wsum = 1.0;
		for (int i = 0; i < 12; i++) {
			float a = float(i) * 2.399963;
			float r = blur * sqrt((float(i) + 0.5) / 12.0) * 1.6;
			float w = exp(-r * r / max(2.0 * blur * blur, 0.01));
			acc += texture(screen_tex, SCREEN_UV + vec2(cos(a), sin(a)) * r * px).rgb * w;
			wsum += w;
		}
		c = acc / wsum;
	}
	if (hblur > 0.3) {
		vec3 acc = vec3(0.0);
		float wsum = 0.0;
		for (int i = -12; i <= 12; i++) {
			float x = float(i) / 12.0 * 2.5 * hblur;
			float w = exp(-x * x / (2.0 * hblur * hblur));
			acc += texture(screen_tex, SCREEN_UV + vec2(x * px.x, 0.0)).rgb * w;
			wsum += w;
		}
		c = acc / wsum;
	}
	c = clamp((c * gain - 0.5) * con + 0.5, 0.0, 1.0);
	float g = dot(c, vec3(0.2126, 0.7152, 0.0722));
	if (mode == 1 || mode == 2) {
		float v = clamp((g * 2.6 - 0.5) * 6.0 + 0.5, 0.0, 1.0);
		c = vec3(mode == 2 ? 1.0 - v : v);
	} else if (mode == 3) {
		c = mix(c, vec3(g), 0.85);
		c = clamp((c - 0.5) * 1.25 + 0.5, 0.0, 1.0);
	}
	c = mix(c, white_color.rgb, white);
	COLOR = vec4(c, 1.0);
}
