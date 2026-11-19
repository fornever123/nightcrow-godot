shader_type canvas_item;
// 影街 · 天上的狂影流：几条墨黑的烟河从左下往右上的母钟楼汇过去，近的粗、远的细，越靠近钟楼越细越淡。
render_mode unshaded;
#include "res://scripts/night/redesign/ying_noise.gdshaderinc"

uniform float t = 0.0;
uniform float scroll = 0.0;          // 镜头横移 × 视差（让烟河有一点纵深错动）
uniform vec2 target = vec2(0.69, 0.3);   // 母钟楼脚（本矩形 UV）
uniform vec3 ink : source_color = vec3(0.02, 0.021, 0.026);
uniform float amount = 0.85;

float ribbon(vec2 uv, float y0, float amp, float ph, float wid) {
	float k = clamp((uv.x - 0.05) / max(target.x - 0.05, 0.01), 0.0, 1.0);   // 0 远端 → 1 钟楼
	float yc = mix(y0, target.y, k * k * (3.0 - 2.0 * k)) + amp * (1.0 - k) * sin(uv.x * 9.0 + ph + t * 0.15);
	float w = wid * mix(1.0, 0.18, k);
	float g = exp(-pow((uv.y - yc) / w, 2.0));
	return g * (1.0 - smoothstep(0.92, 1.0, k)) * step(uv.x, target.x + 0.01);
}

void fragment() {
	vec2 uv = UV;
	float r = ribbon(uv, 0.22, 0.04, 0.0, 0.04) + ribbon(uv, 0.15, 0.05, 2.1, 0.03) + 0.8 * ribbon(uv, 0.29, 0.03, 4.0, 0.045);
	vec2 p = vec2(uv.x * 6.0 + scroll - t * 0.12, uv.y * 14.0);
	float n = yn_fbm(p + yn_fbm(p * 0.5 + t * 0.05) * 1.5);
	float a = smoothstep(0.3, 0.7, r * (0.45 + n));
	COLOR = vec4(ink, a * amount);
}
