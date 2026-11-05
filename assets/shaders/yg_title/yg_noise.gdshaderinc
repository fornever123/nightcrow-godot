// [YG-MARK] 由 YG 新增（首页「断晓 · 断光」WebGL 版移植到 Godot）。
// 用途：噪声函数，从 E:\.0download\code_artifact (1).html 的 HDR 头原样翻译。
// 删除方法：见 docs/YG-首页断光-删除清单.md —— 整个 assets/shaders/yg_title/ 目录一起删即可。

float h12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * .1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 h22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(.1031, .1030, .0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

float vn(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h12(i), h12(i + vec2(1.0, 0.0)), f.x),
			mix(h12(i + vec2(0.0, 1.0)), h12(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float a = .5, s = 0.;
	mat2 m = mat2(vec2(1.6, 1.2), vec2(-1.2, 1.6));
	for (int i = 0; i < 5; i++) {
		s += a * vn(p);
		p = m * p + vec2(3.1, 1.7);
		a *= .5;
	}
	return s;
}

float fbm3(vec2 p) {
	float a = .5, s = 0.;
	mat2 m = mat2(vec2(1.6, 1.2), vec2(-1.2, 1.6));
	for (int i = 0; i < 3; i++) {
		s += a * vn(p);
		p = m * p + vec2(3.1, 1.7);
		a *= .5;
	}
	return s / .875;
}
