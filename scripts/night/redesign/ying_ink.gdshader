shader_type canvas_item;
// 影街 · 墙上的狂影（压在站立层上、同一张图同一裁切，只在有画的地方出现）。
// 被白光赶出来的流动时间积在照不到光的地方：凹进去的（深度图暗处）、靠近街面的地方最浓，灯照到的亮处没有；
// 一条条往右（母钟楼方向）流、边缘翻卷。
render_mode unshaded;
#include "res://scripts/night/redesign/ying_noise.gdshaderinc"

uniform sampler2D depth_tex : filter_linear;
uniform float t = 0.0;
uniform float aspect = 1.78;        // 贴图宽 / 高
uniform float amount = 0.55;
uniform float speed = 0.05;
uniform vec3 ink : source_color = vec3(0.015, 0.016, 0.02);

void fragment() {
	vec4 src = texture(TEXTURE, UV);
	float d = texture(depth_tex, UV).r;
	float lum = dot(src.rgb, vec3(0.299, 0.587, 0.114));
	vec2 p = vec2(UV.x * aspect, UV.y) * vec2(2.4, 9.0);       // 横向拉长：一缕缕
	vec2 w = vec2(yn_fbm(p * 0.5 + vec2(t * speed * 0.5, 0.0)), yn_fbm(p * 0.5 + vec2(5.2, t * 0.03)));
	float n = yn_fbm(p + w * 2.2 - vec2(t * speed * 3.0, 0.0));
	float ridge = 1.0 - abs(n * 2.0 - 1.0);
	float wisps = smoothstep(0.72, 0.9, ridge);                // 细烟丝
	float n2 = yn_fbm(vec2(UV.x * aspect * 1.4 - t * speed * 1.5, UV.y * 3.0) + w);
	float ground = smoothstep(0.5, 0.95, UV.y);
	float body = smoothstep(0.46, 0.62, n2 + ground * 0.35) * smoothstep(0.3, 0.9, UV.y);   // 贴街面的浓团
	float mask = mix(0.65, 1.0, 1.0 - d);                       // 凹处更浓
	mask *= 1.0 - smoothstep(0.42, 0.75, lum);                   // 灯照到的亮处没有
	float a = wisps * mix(0.35, 0.9, ground + 0.3) * (1.0 - smoothstep(0.55, 0.8, UV.y)) * mask;   // 11-18：去掉贴街面的浓团（用户：“地面那坨影子不行”）
	float edge = smoothstep(0.58, 0.72, ridge) * (1.0 - wisps);  // 烟丝外一圈很淡的灰边
	vec3 col = mix(ink, vec3(0.22, 0.22, 0.23), edge * 0.6);
	COLOR = vec4(col, max(a, edge * 0.18 * mask) * amount * src.a);
}
