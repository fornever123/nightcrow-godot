shader_type canvas_item;
// 影街 · 街下翻卷的墨烟（取代街面以下那条死黑带）：上沿软、往右慢慢流。
render_mode unshaded;
#include "res://scripts/night/redesign/ying_noise.gdshaderinc"

uniform float t = 0.0;
uniform float cam_x = 0.0;
uniform float wpx = 2400.0;        // 这块矩形的世界宽度（噪声按世界坐标走，跟镜头不滑）
uniform vec3 ink : source_color = vec3(0.012, 0.013, 0.016);
uniform vec3 rim : source_color = vec3(0.34, 0.34, 0.35);

void fragment() {
	vec2 wp = vec2(UV.x * wpx + cam_x, UV.y * 600.0) / 260.0;
	float n = yn_fbm(wp * vec2(0.7, 1.4) + vec2(-t * 0.08, t * 0.03) + yn_fbm(wp + t * 0.05));
	float edge = UV.y - (0.12 + 0.18 * (n - 0.5));            // 翻卷的上沿
	float a = smoothstep(0.0, 0.12, edge);
	float lit = smoothstep(0.0, 0.06, edge) * (1.0 - smoothstep(0.06, 0.2, edge));   // 上沿一道很淡的灰边
	float roll = yn_fbm(wp * 1.6 + vec2(-t * 0.1, 0.0));      // 烟团内部的翻卷明暗
	vec3 col = mix(ink, rim * 0.55, smoothstep(0.42, 0.75, roll));
	col = mix(col, rim, lit * 0.8);
	COLOR = vec4(col, a);
}
