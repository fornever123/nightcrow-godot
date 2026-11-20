// [YG-MARK] 11-08 首页换 G03：影层。Codex 画的黑水底图 + 白字标，水面用程序波动，雨点落处起涟漪。取代 yg_shadow。
// 删除方法：见 docs/YG-首页断光-删除清单.md。

shader_type canvas_item;
render_mode blend_mix, unshaded;

#include "res://assets/shaders/yg_title/yg_noise.gdshaderinc"

uniform vec2 uRes = vec2(1280.0, 720.0);
uniform float uTime = 0.0;
uniform vec2 uC = vec2(640.0, 317.0);
uniform vec2 uPar = vec2(0.0);
uniform vec4 uBox = vec4(0.0);
uniform vec2 uPlateC = vec2(960.0, 475.0);
uniform sampler2D uPlate : filter_linear, repeat_disable;
uniform sampler2D uLogo : filter_linear, repeat_disable;

vec2 plate_uv(vec2 p) {
	float s = max(uRes.x / 1920.0, uRes.y / 1080.0);
	vec2 uv = ((p - uC) / s + uPlateC) / vec2(1920.0, 1080.0);
	return 1.0 - abs(1.0 - abs(uv));   // 水面晃出图外时折回来，不然贴边拉出横条
}

void fragment() {
	vec2 p = UV * uRes;
	float water = smoothstep(uRes.y * .70, uRes.y * .84, p.y);
	// 水面：越近晃得越多，横向拉长的波纹
	float near = (p.y / uRes.y - .7) / .3;
	vec2 wob = vec2(vn(vec2(p.x * .006, p.y * .05) + vec2(uTime * .22, uTime * .5)),
			vn(vec2(p.x * .009, p.y * .07) - vec2(uTime * .18, uTime * .42))) - .5;
	vec2 q = p + uPar * .5 + wob * vec2(26.0, 9.0) * water * (.4 + near) * (uRes.y / 720.0);
	vec3 col = pow(texture(uPlate, plate_uv(q)).rgb, vec3(2.2));
	// 反光时明时暗，不是一张死图
	col *= mix(1.0, mix(.62, 1.7, vn(vec2(p.x * .009, p.y * .03) + vec2(uTime * .3, -uTime * .16))), water);
	// 雨点落处的涟漪（透视压扁的圆环）
	float rip = 0.0;
	for (int i = 0; i < 14; i++) {
		float fi = float(i);
		float period = 1.7 + h12(vec2(fi, 3.1)) * 1.6;
		float tt = uTime / period + h12(vec2(fi, 7.7));
		float cell = floor(tt);
		float age = fract(tt);
		vec2 h = h22(vec2(fi * 1.7 + 3.0, cell));
		vec2 c = vec2(h.x * uRes.x, mix(uRes.y * .78, uRes.y * .985, h.y * h.y));
		float depth = mix(.45, 1.2, (c.y / uRes.y - .78) / .205) * (uRes.y / 720.0);
		vec2 dd = (p - c) * vec2(1.0, 3.6);
		float rad = age * 34.0 * depth;
		rip += exp(-abs(length(dd) - rad) / (1.0 * depth)) * (1.0 - age) * (1.0 - age);
	}
	col += vec3(.60, .63, .72) * rip * .34 * water;
	// 贴屏幕底压暗一点，按键提示才读得清
	col *= mix(1.0, .62, smoothstep(uRes.y * .93, uRes.y * .99, p.y));
	// 字标过了断口的部分：白瓷字
	vec2 luv = (p - uBox.xz) / (uBox.yw - uBox.xz);
	if (luv.x > 0.0 && luv.x < 1.0 && luv.y > 0.0 && luv.y < 1.0) {
		vec4 lg = texture(uLogo, luv);
		col = mix(col, pow(lg.rgb, vec3(2.2)), lg.a);
	}
	COLOR = vec4(col, 1.0);
}
