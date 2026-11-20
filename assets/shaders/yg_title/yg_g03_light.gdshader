// [YG-MARK] 11-08 首页换 G03：光层。Codex 画的白大理石底图 + 黑字标，取代原来程序画的灰雾（yg_light）。
// 删除方法：见 docs/YG-首页断光-删除清单.md。

shader_type canvas_item;
render_mode blend_mix, unshaded;

#include "res://assets/shaders/yg_title/yg_noise.gdshaderinc"

uniform vec2 uRes = vec2(1280.0, 720.0);
uniform float uTime = 0.0;
uniform vec2 uC = vec2(640.0, 317.0);
uniform vec2 uPar = vec2(0.0);
uniform float uDawn = 0.0;
uniform float uReveal = 0.0;
uniform vec4 uBox = vec4(0.0);
uniform vec2 uPlateC = vec2(960.0, 475.0);   // 底图上（1920×1080）断口过屏幕中线的那一点
uniform sampler2D uPlate : filter_linear, repeat_disable;
uniform sampler2D uLogo : filter_linear, repeat_disable;

vec2 plate_uv(vec2 p) {
	float s = max(uRes.x / 1920.0, uRes.y / 1080.0);
	return ((p - uC) / s + uPlateC) / vec2(1920.0, 1080.0);
}

void fragment() {
	vec2 p = UV * uRes;
	vec3 col = pow(texture(uPlate, plate_uv(p + uPar * .5)).rgb, vec3(2.2));
	// 一道很慢的光从大理石上扫过，让底图活一点
	float along = dot(p, normalize(vec2(1.0, .42)));
	float sweep = mod(uTime * uRes.x * .035, uRes.x * 2.4) - uRes.x * .5;
	col *= 1.0 + .13 * exp(-pow((along - sweep) / (uRes.y * .42), 2.0));
	// 开场：光从左上画外压下来
	float r = length(p / uRes.y - vec2(-.2, -.3)) / 2.6;
	col *= smoothstep(uDawn * 1.35, uDawn * 1.35 - .35, r);
	// 字标：黑字，像墨一样从左往右渗出来
	vec2 luv = (p - uBox.xz) / (uBox.yw - uBox.xz);
	if (luv.x > 0.0 && luv.x < 1.0 && luv.y > 0.0 && luv.y < 1.0) {
		float a = texture(uLogo, luv).a;
		float th = uReveal * 1.35 - .18 + (fbm(p * .025) - .5) * .42;
		a *= smoothstep(0.0, .07, th - luv.x);
		col = mix(col, vec3(.0035, .0035, .005), a);
	}
	COLOR = vec4(col, 1.0);
}
