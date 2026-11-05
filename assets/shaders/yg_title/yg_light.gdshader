// [YG-MARK] 由 YG 新增（首页「断晓 · 断光」WebGL 版移植到 Godot）。
// 昼光层：太阳初升、时间停住、远山与断碑残垣多层视差剪影。
// 来源：E:\.0download\code_artifact (1).html 的 FS_LIGHT，逐行翻译。
// 与网页版的差异：网页版 uTitle（矢量字形高度图）在 GPT 字标模式下是全黑、所有相关项恒为 0，
// 这里直接去掉，画面与网页版 GPT 模式一致。
// 删除方法：见 docs/YG-首页断光-删除清单.md。

shader_type canvas_item;
render_mode blend_mix, unshaded;

#include "res://assets/shaders/yg_title/yg_noise.gdshaderinc"

uniform vec2 uRes = vec2(1280.0, 720.0);
uniform float uTime = 0.0;
uniform vec2 uC = vec2(640.0, 302.0);
uniform vec2 uD = vec2(0.984, 0.179);
uniform vec2 uN = vec2(-0.179, 0.984);
uniform vec2 uPar = vec2(0.0);
uniform vec2 uSun = vec2(435.0, -302.0);
uniform float uSunR = 540.0;
uniform float uDawn = 0.0;
uniform float uSunK = 0.0;
uniform float uReveal = 0.0;
uniform vec4 uBox = vec4(0.0);
uniform vec4 uLogoRect = vec4(0.0, 0.0, 1.0, 1.0);
uniform sampler2D uLogoW : filter_linear, repeat_disable;

const vec3 BONE = vec3(1.0, .965, .905);
const vec3 WARM = vec3(1.0, .9, .76);

vec2 P(vec2 uv) { return uv * uRes; }

// 字标图只在 uLogoRect 这块里，方框外必须是黑的（网页版是画在黑色画布上的）
vec3 logo_sample(sampler2D t, vec2 p) {
	vec2 uv = (p - uLogoRect.xy) / uLogoRect.zw;
	float m = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
	return texture(t, clamp(uv, vec2(0.0), vec2(1.0))).rgb * m;
}

// 远古断碑与悬空残石：返回 vec2(碑体遮罩, 逆光金边)
vec2 mono_one(float u, float h, float Cc, float Ww, float Hh, float Tt) {
	float dx = u - Cc + h * Tt;
	float w = Ww * (1.0 - h * 1.15);
	float cut_top = Hh + dx * .55 + (vn(vec2(u * 65.0, Cc * 100.0)) - 0.5) * .008;
	float in_x = smoothstep(w + .002, w - .0015, abs(dx));
	float in_y = smoothstep(cut_top + .002, cut_top - .002, h);
	float edge_x = exp(-abs(abs(dx) - w) * 450.0) * in_y * step(dx * sign(Cc), 0.0);
	float edge_top = exp(-abs(h - cut_top) * 380.0) * in_x;
	return vec2(in_x * in_y, edge_x * .85 + edge_top * 1.15);
}

// 被斩断后悬停在半空的碑顶残石
vec2 mono_rock(float u, float h, float Cc, float Ww, float Hh, float Tt, float fOff) {
	float dx = u - Cc + h * Tt;
	float w = Ww * (1.0 - h * 1.15);
	float cut_top = Hh + dx * .55 + (vn(vec2(u * 65.0, Cc * 100.0)) - 0.5) * .008;
	float fdx = dx - fOff;
	float fw = w * .78;
	float f_bot = cut_top + .022;
	float f_top = cut_top + .056 + fdx * .4;
	float f_in_x = smoothstep(fw + .002, fw - .0015, abs(fdx));
	float f_in_y = smoothstep(f_bot - .002, f_bot + .002, h) * smoothstep(f_top + .002, f_top - .002, h);
	float f_rim = (exp(-abs(abs(fdx) - fw) * 480.0) * f_in_y + exp(-abs(h - f_bot) * 420.0) * f_in_x) * 1.25;
	return vec2(f_in_x * f_in_y, f_rim);
}

vec2 monoliths(float u, float h) {
	if (h < 0.0 || h > 0.38) {
		return vec2(0.0);
	}
	float m = 0.0, rim = 0.0;
	vec2 a;
	a = mono_one(u, h, -0.76, 0.026, 0.24, 0.14);
	m = max(m, a.x); rim = max(rim, a.y);
	a = mono_one(u, h, -0.58, 0.021, 0.185, -0.11);
	m = max(m, a.x); rim = max(rim, a.y);
	a = mono_one(u, h, -0.43, 0.014, 0.115, 0.08);
	m = max(m, a.x); rim = max(rim, a.y);
	a = mono_one(u, h, 0.44, 0.015, 0.125, -0.09);
	m = max(m, a.x); rim = max(rim, a.y);
	a = mono_one(u, h, 0.60, 0.023, 0.20, 0.12);
	m = max(m, a.x); rim = max(rim, a.y);
	a = mono_one(u, h, 0.77, 0.028, 0.255, -0.15);
	m = max(m, a.x); rim = max(rim, a.y);
	// [YG-MARK] 11-05 改好看：悬空碎石去掉——和下面的碑一起读起来像字母“i”
	return vec2(m, rim);
}

vec3 sky(vec2 p) {
	vec2 q = p - uC;
	float s = dot(q, uN);
	float u = dot(q, uD);
	vec2 dl = p - uSun;
	float r = length(dl) / uRes.y;
	float a = atan(dl.x, dl.y);
	vec3 g = vec3(.008, .007, .009);
	g += WARM * (exp(-r * 1.65) * .56 + exp(-r * 3.8) * .52 * uSunK);
	// 破晓晨光：主光柱笼罩字标，辅以柔化丁达尔体积光与晨雾金边
	float bm = exp(-pow((a + .16) / .052, 2.0)) * .65
			+ exp(-pow((a - .21) / .085, 2.0)) * 1.15
			+ exp(-pow((a - .54) / .038, 2.0)) * .78
			+ exp(-pow((a - .02) / .14, 2.0)) * .35;
	bm *= .72 + .28 * fbm3(vec2(a * 36.0, r * 2.2));
	g += mix(WARM, BONE, .4) * bm * exp(-r * .95) * .54 * smoothstep(.08, .42, r);
	float dst = step(.9958, h12(floor(p / 6.5))) * bm;
	g += BONE * dst * smoothstep(.48, 0.0, length(fract(p / 6.5) - .5)) * 2.1;
	float fg = fbm(vec2(p.x / uRes.y * 1.3, p.y / uRes.y * 4.0) + vec2(3.0, 7.0));
	float fg2 = fbm(vec2(p.x / uRes.y * 4.0, p.y / uRes.y * 14.0) + vec2(9.0, 1.0));
	g *= .64 + .68 * fg + .25 * (fg2 - .5);

	// 第0层（极远景）：天穹残缺日晷法阵光环
	vec2 sun_c = vec2(uC.x, uC.y - uRes.y * .06) - uPar * .12;
	vec2 d_ring = (p - sun_c) / uRes.y;
	float r_ring = length(d_ring);
	float a_ring = atan(d_ring.y, d_ring.x);
	float ring_gap = smoothstep(.15, .45, vn(vec2(a_ring * 3.5, 1.7)));
	float halo_ring = (exp(-abs(r_ring - .29) * 320.0) * .65 + exp(-abs(r_ring - .355) * 420.0) * .35) * ring_gap * smoothstep(.05, -.02, s / uRes.y);
	float ticks = exp(-abs(r_ring - .322) * 240.0) * step(.92, cos(a_ring * 36.0)) * ring_gap * smoothstep(.02, -.04, s / uRes.y);
	// [YG-MARK] 11-05 改好看：同心圆光环像准星，去掉（halo_ring / ticks 不再叠加）

	// 第1层（远景视差）：连绵远山剪影与山脊晨雾
	vec2 q_far = (p - uPar * .38) - uC;
	float u_far = dot(q_far, uD) / uRes.y;
	float h_far = -dot(q_far, uN) / uRes.y;
	if (h_far > -.01 && h_far < .28) {
		float valley = smoothstep(.14, .58, abs(u_far));
		float mtn = .032 + .095 * valley + .052 * fbm3(vec2(u_far * 3.4 + 2.1, 1.3)) + .018 * vn(vec2(u_far * 13.0, 4.2));
		float in_mtn = smoothstep(mtn + .004, mtn - .003, h_far) * smoothstep(-.005, .003, h_far);
		float mtn_rim = exp(-abs(h_far - mtn) * 240.0) * smoothstep(-.002, .01, h_far);
		vec3 mtn_col = vec3(.026, .022, .024) + WARM * exp(-r * 1.7) * .095 + BONE * exp(-h_far * 18.0) * .05;
		g = mix(g, mtn_col, in_mtn * .88);
		g += mix(WARM, BONE, .5) * mtn_rim * (.18 + .22 * bm) * uSunK;
	}

	// 第2层（中景视差）：断碑残垣与悬空残石
	vec2 q_mid = (p - uPar * .88) - uC;
	float u_mid = dot(q_mid, uD) / uRes.y;
	float h_mid = -dot(q_mid, uN) / uRes.y;
	vec2 mono = monoliths(u_mid, h_mid);
	if (mono.x + mono.y > .001) {
		vec3 stone_col = vec3(.014, .012, .015) + WARM * exp(-h_mid * 12.0) * .04;
		g = mix(g, stone_col, mono.x * .94);
		// [YG-MARK] 11-05 改好看：白描边压到四分之一，碑是实心剪影，只留一线逆光
		g += mix(WARM, BONE, .55) * mono.y * (.32 + .35 * uSunK) * .24;
	}

	// 第3层（近景视差）：左右两侧险峻断崖暗角剪影
	vec2 q_near = (p - uPar * 1.45) - uC;
	float u_near = dot(q_near, uD) / uRes.y;
	float h_near = -dot(q_near, uN) / uRes.y;
	float w_half = uRes.x * .5 / uRes.y;
	float cliff_edge = w_half * .63;
	if (h_near > -.01 && abs(u_near) > cliff_edge) {
		float cliff = (abs(u_near) - cliff_edge) * .65 + .04 * fbm3(vec2(h_near * 9.0, u_near * 4.0));
		float in_cliff = smoothstep(cliff + .004, cliff - .003, h_near * .42) * smoothstep(-.005, .003, h_near);
		float cliff_rim = exp(-abs(h_near * .42 - cliff) * 280.0) * step(0.0, h_near);
		g = mix(g, vec3(.007, .006, .008), in_cliff * .95);
		g += WARM * cliff_rim * .16 * uSunK;
	}

	// 靠近刀口分界处的晨曦暖雾辉光
	float hz = exp(-abs(s) / (uRes.y * .16)) * (.4 + .6 * fg);
	g += mix(WARM, vec3(1.0, .85, .68), .5) * hz * .12;
	// [YG-MARK] 11-05 改好看：铺满全屏的灰雾减半；光只聚在中间光柱一带，两侧压暗 → 有明暗层次、不再一片平灰
	g += BONE * (.018 + .03 * fg) * mix(1.05, .55, smoothstep(.18, 1.0, p.y / uRes.y));
	float pool = exp(-pow((p.x - uC.x + uRes.y * .06) / (uRes.x * .36), 2.0));
	g *= mix(.36, 1.0, pool) * mix(.8, 1.0, smoothstep(0.0, .3, p.y / uRes.y));
	// 刀口以下是“地面”，越往下越暗（开场还没斩时不再是一整片灰雾）。
	// 不整体调暖：11-02 雾调暖发灰褐发土被撤过，暖色只留在开场光刚亮起那一下（见 fragment 的 early）
	g *= mix(1.0, .42, smoothstep(0.0, uRes.y * .5, s));
	return g * .82;
}

void fragment() {
	vec2 p = P(UV);
	vec2 pp = p - uPar * .35;
	// [YG-MARK] 11-05 改好看：光不再整屏一起变亮，而是从画面上方的光源处一圈圈铺开，先暖金、铺满后转暖白
	float r_sun = length(pp - uSun) / uRes.y;
	float spread = smoothstep(uDawn * 2.7 + .05, uDawn * 2.7 - .55, r_sun) * smoothstep(0.0, .25, uDawn);
	vec3 early = mix(vec3(1.18, .93, .66), vec3(1.0), smoothstep(.45, 1.0, uDawn));
	vec3 col = vec3(.005, .0045, .0035) + sky(pp) * spread * early;

	vec2 tp = p - uPar * .6;
	float xn = (tp.x - uBox.x) / (uBox.y - uBox.x);
	float th = uReveal * 1.35 - .18 + (fbm(tp * .025) - .5) * .42;
	float rv = smoothstep(xn - .07, xn + .07, th);
	vec2 bc = vec2((uBox.x + uBox.y) * .5, (uBox.z + uBox.w) * .5);
	vec2 br = vec2((uBox.y - uBox.x) * .62, (uBox.w - uBox.z) * .75);
	float stage = exp(-dot((tp - bc) / br, (tp - bc) / br) * 1.1);
	col *= 1.0 - .9 * stage * smoothstep(0.0, .4, uReveal);

	vec3 lg = logo_sample(uLogoW, tp);
	float lum = max(lg.r, max(lg.g, lg.b));
	float lm = smoothstep(.03, .22, lum) * rv;
	col = mix(col, lg * vec3(1.14, 1.1, 1.02), lm);

	// 待机时每 6.5 秒一道慢光扫过白瓷字
	float sxp = mix(uBox.x - uRes.y * .25, uBox.y + uRes.y * .25, clamp(mod(uTime, 6.5) / 1.5, 0.0, 1.0));
	float shn = exp(-pow((tp.x - sxp + (tp.y - bc.y) * .5) / (uRes.y * .038), 2.0)) * step(mod(uTime, 6.5), 1.5);
	col += vec3(1.0, .97, .9) * shn * lm * smoothstep(.35, .9, lum) * .62;

	COLOR = vec4(col, 1.0);
}
