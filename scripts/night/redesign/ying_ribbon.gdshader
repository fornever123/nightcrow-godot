shader_type canvas_item;
// 影街 · 手绘墨烟带（Codex 画的狂影素材）：形体随流动噪声扭动，边缘被往右流的噪声慢慢吃掉又长回来，
// 整条带子由 ying_look.gd 往右（母钟楼方向）漂、首尾淡入淡出。
render_mode unshaded;
#include "res://scripts/night/redesign/ying_noise.gdshaderinc"

uniform float t = 0.0;
uniform float seed = 0.0;
uniform float warp = 0.02;
uniform float erode = 0.32;

varying vec4 v_mod;

void vertex() {
	v_mod = COLOR;
}

void fragment() {
	vec2 q = UV;
	float n1 = yn_fbm(vec2(UV.x * 5.0 - t * 0.25 + seed, UV.y * 2.5 + t * 0.07));
	float n2 = yn_fbm(vec2(UV.x * 4.0 - t * 0.2 + seed * 1.7, UV.y * 2.0 - t * 0.05) + 3.1);
	q += (vec2(n2, n1) - 0.5) * vec2(warp, warp * 2.5);
	vec4 c = texture(TEXTURE, q);
	float e = yn_fbm(vec2(UV.x * 9.0 - t * 0.45 + seed * 2.3, UV.y * 4.0 + t * 0.1));
	c.a *= smoothstep(erode, erode + 0.22, e * 0.8 + c.a * 0.45);
	COLOR = c * v_mod;
}
