// [YG-MARK] 由 YG 新增（首页「断晓 · 断光」WebGL 版移植到 Godot）。
// 菜单字的斜切：丢掉刀口线一侧的像素，让同一行字分成上下两片。
// 删除方法：见 docs/YG-首页断光-删除清单.md。

shader_type canvas_item;
render_mode blend_mix, unshaded;

uniform vec2 uRes = vec2(1280.0, 720.0);
uniform vec2 uLine = vec2(640.0, 360.0);
uniform vec2 uN = vec2(-0.179, 0.984);
uniform float uSide = 1.0;

// [YG-MARK] 11-05：改用本地坐标（= 设计坐标），不用 SCREEN_UV —— 窗口不是 16:9 有黑边、或开了超采样时，
// 屏幕 UV 和设计坐标对不上，刀口会切偏。uRes 保留但不再参与计算。
varying vec2 local_p;

void vertex() {
	local_p = VERTEX;
}

void fragment() {
	vec2 p = local_p;
	float s = dot(p - uLine, uN);
	if (uSide > 0.0) {
		if (s < 0.0) {
			discard;
		}
	} else {
		if (s > 0.0) {
			discard;
		}
	}
}
