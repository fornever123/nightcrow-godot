// [YG-MARK] 由 YG 新增（首页「断晓 · 断光」WebGL 版移植到 Godot）。
// 影层：沉下去的时间在这里流动，倒悬遗迹的水墨倒影与深渊微光。
// 来源：E:\.0download\code_artifact (1).html 的 FS_SHADOW，逐行翻译。
// 与网页版的差异：uTitle（矢量字形）在 GPT 字标模式下恒为 0，相关项（墨里字影、字影边缘）已去掉。
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
uniform float uSunR = 194.0;
uniform float uFlowK = 1.0;
uniform vec4 uBox = vec4(0.0);
uniform vec4 uLogoRect = vec4(0.0, 0.0, 1.0, 1.0);
uniform sampler2D uLogo : filter_linear, repeat_disable;
uniform sampler2D uLogoW : filter_linear, repeat_disable;

vec2 P(vec2 uv) { return uv * uRes; }

// 字标图只在 uLogoRect 这块里，方框外必须是黑的（网页版是画在黑色画布上的）
vec3 logo_sample(sampler2D t, vec2 p) {
	vec2 uv = (p - uLogoRect.xy) / uLogoRect.zw;
	float m = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
	return texture(t, clamp(uv, vec2(0.0), vec2(1.0))).rgb * m;
}

vec2 mono_one(float u, float h, float Cc, float Ww, float Hh, float Tt) {
	float dx = u - Cc + h * Tt;
	float w = Ww * (1.0 - h * 1.15);
	float cut_top = Hh + dx * .55;
	float in_x = smoothstep(w + .004, w - .002, abs(dx));
	float in_y = smoothstep(cut_top + .004, cut_top - .003, h);
	float rim = exp(-abs(abs(dx) - w) * 340.0) * in_y + exp(-abs(h - cut_top) * 300.0) * in_x;
	return vec2(in_x * in_y, rim);
}

vec2 mono_rock(float u, float h, float Cc, float Ww, float Hh, float Tt, float fOff) {
	float dx = u - Cc + h * Tt;
	float w = Ww * (1.0 - h * 1.15);
	float cut_top = Hh + dx * .55;
	float fdx = dx - fOff;
	float fw = w * .78;
	float f_bot = cut_top + .022;
	float f_top = cut_top + .056 + fdx * .4;
	float f_in_x = smoothstep(fw + .004, fw - .002, abs(fdx));
	float f_in_y = smoothstep(f_bot - .003, f_bot + .003, h) * smoothstep(f_top + .003, f_top - .003, h);
	float rim = (exp(-abs(abs(fdx) - fw) * 360.0) * f_in_y + exp(-abs(h - f_top) * 320.0) * f_in_x) * 1.15;
	return vec2(f_in_x * f_in_y, rim);
}

vec2 shadow_monoliths(float u, float h) {
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
	// [YG-MARK] 11-05 改好看：和昼光层一样去掉悬空碎石的倒影
	return vec2(m, rim);
}


void fragment() {
	vec2 p = P(UV);
	vec2 pp = p - uPar * .35;
	vec2 q = pp - uC;
	float s = dot(q, uN);
	float u = dot(q, uD);
	float d = max(s, 0.0) / uRes.y;
	float t = uTime * uFlowK;
	vec3 col = vec3(.0035, .0048, .0095);
	float n1 = fbm(vec2(u / uRes.y * 1.1 - t * .08, s / uRes.y * 6.0));
	float n2 = fbm(vec2(u / uRes.y * 3.2 - t * .22, s / uRes.y * 18.0) + vec2(5.0));
	col += vec3(.042, .054, .088) * smoothstep(.46, .84, n1 * .65 + n2 * .35) * exp(-d * 2.0);
	float fl = fbm3(vec2(u / uRes.y * 2.4 - t * (.45 + 1.3 * exp(-d * 5.0)), s / uRes.y * 58.0));
	col += vec3(.13, .17, .26) * smoothstep(.72, .92, fl) * exp(-d * 3.2) * .55;

	// 倒悬远山与断碑的水波扭曲倒影
	float ripple = sin(d * 46.0 - t * 2.8) * .006 * (.25 + d * 1.8) + (fbm3(vec2(u / uRes.y * 5.5, d * 16.0 - t * 1.1)) - .5) * .014;
	vec2 q_ref_mtn = (p - uPar * .38) - uC;
	float u_mtn = dot(q_ref_mtn, uD) / uRes.y + ripple * .6;
	float d_mtn = max(dot(q_ref_mtn, uN), 0.0) / uRes.y;
	if (d_mtn > 0.0 && d_mtn < .28) {
		float valley = smoothstep(.14, .58, abs(u_mtn));
		float mtn = .032 + .095 * valley + .052 * fbm3(vec2(u_mtn * 3.4 + 2.1, 1.3));
		float in_mtn = smoothstep(mtn + .008, mtn - .005, d_mtn);
		float mtn_rim = exp(-abs(d_mtn - mtn) * 180.0);
		col = mix(col, vec3(.005, .007, .015), in_mtn * .65 * exp(-d_mtn * 3.5));
		col += vec3(.32, .42, .72) * mtn_rim * .04 * exp(-d_mtn * 3.0);   // [YG-MARK] 11-05：.09 → .04
	}
	vec2 q_ref_mono = (p - uPar * .88) - uC;
	float u_mono = dot(q_ref_mono, uD) / uRes.y + ripple;
	float d_mono = max(dot(q_ref_mono, uN), 0.0) / uRes.y;
	vec2 s_mono = shadow_monoliths(u_mono, d_mono);
	if (s_mono.x + s_mono.y > .001) {
		col = mix(col, vec3(.004, .0055, .012), s_mono.x * .82 * exp(-d_mono * 2.5));
		// [YG-MARK] 11-05 改好看：倒影的霓虹描边 .22 → .04，只剩模糊的暗影
		col += mix(vec3(.38, .52, .88), vec3(.58, .42, .98), .45) * s_mono.y * .04 * exp(-d_mono * 2.8);
	}

	// 深渊逆流光丝（沉入影中的时间微粒向上逸散）
	float u_norm = u / uRes.y;
	float thread_x = fract(u_norm * 11.0 + sin(d * 5.0 + t * .25) * .18);
	float thread = exp(-abs(thread_x - .5) * 55.0) * smoothstep(.35, .01, d) * smoothstep(0.0, .03, d)
			* pow(fract(d * 2.5 + t * .32 + h12(vec2(floor(u_norm * 11.0), 1.0))), 2.0);
	col += vec3(.45, .52, .92) * thread * .14;

	// 暗影水面落雨涟漪（透视椭圆水环）
	if (d > .06) {
		float wd = pow(max(d - .05, .001), .68);
		vec2 wp = vec2(u_norm * 8.5 - t * .04, wd * 16.0);
		vec2 wc = floor(wp);
		vec2 wf = fract(wp) - .5;
		vec2 wr = h22(wc);
		float wph = fract(t * (.52 + wr.x * .35) + wr.y * 13.7);
		float wdist = length((wf - (wr - .5) * .42) * vec2(1.0, 2.1));
		float wring = (exp(-abs(wdist - wph * .46) * 48.0) + exp(-abs(wdist - wph * .28) * 55.0) * .45)
				* (1.0 - wph) * (1.0 - wph) * step(.42, h12(wc + 7.3));
		col += mix(vec3(.46, .58, .90), vec3(.62, .48, .96), .35) * wring * .24 * smoothstep(.06, .16, d) * exp(-d * 2.4);
	}

	// 刀缝下方的幽蓝紫微光折射与水波纹脉络
	float caust = smoothstep(.62, .88, fbm3(vec2(u / uRes.y * 5.5 + t * .35, s / uRes.y * 24.0 - t * .6)));
	col += vec3(.35, .30, .72) * caust * exp(-d * 5.2) * .10;
	col += vec3(.65, .72, .94) * exp(-d * uRes.y / 14.0) * .065 + vec3(.42, .50, .72) * exp(-d * 8.0) * .042;

	// [YG-MARK] 11-05 改好看：离刀口越远越暗，下半不再是一整片平的藏青
	col *= mix(1.0, .6, smoothstep(.12, .55, d));

	vec2 tp = p - uPar * .6;
	vec2 bc = vec2((uBox.x + uBox.y) * .5, (uBox.z + uBox.w) * .5);
	float bh = max(uBox.w - uBox.z, 1.0);
	float sr = tp.y - (uBox.w - bh * .04);
	// [YG-MARK] 11-05 更高级：字标倒影关掉——正好叠在「开始游戏」后面像个鬼影
	if (false && sr > 0.0) {
		float k = sr / bh;
		float w1 = fbm(vec2(tp.x * .003, sr * .02 - t * .35));
		float w2 = fbm3(vec2(tp.x * .012 - t * .2, sr * .07 - t * 1.1));
		vec2 rp = vec2(tp.x + ((w1 - .5) * 30.0 + (w2 - .5) * 14.0) * (.3 + k * 2.0), tp.y - 2.0 * sr);
		vec3 rf = vec3(0.0);
		for (int i = 0; i < 3; i++) {
			rf += logo_sample(uLogoW, rp + vec2(0.0, (float(i) - 1.0) * (2.0 + k * 22.0)));
		}
		float brk = smoothstep(.28, .7, fbm(vec2(tp.x * .006 + t * .05, sr * .09 - t * 1.8)));
		float gl = smoothstep(.55, .8, fbm3(vec2(tp.x * .02, sr * .35 - t * 3.0)));
		// [YG-MARK] 11-05 改好看：字的倒影收短、减弱，不压在菜单后面
		col += vec3(.62, .72, .95) * rf / 3.0 * exp(-k * 4.2) * smoothstep(0.0, bh * .04, sr) * (.05 + .07 * brk + .1 * gl) * .55;
	}

	float sx = mod(uTime * 230.0, uRes.x * 1.7) - uRes.x * .35;
	float sheen = exp(-pow((tp.x - sx + (tp.y - uC.y) * .6) / 90.0, 2.0));

	vec3 lg = logo_sample(uLogo, tp);
	vec3 lgw = logo_sample(uLogoW, tp);
	float w_lum = dot(lgw, vec3(.333));
	vec2 ex2 = vec2(2.2, 0.0);
	float wx = dot(logo_sample(uLogoW, tp + ex2) - logo_sample(uLogoW, tp - ex2), vec3(.333));
	float wy = dot(logo_sample(uLogoW, tp + ex2.yx) - logo_sample(uLogoW, tp - ex2.yx), vec3(.333));
	float w_rim = clamp(length(vec2(wx, wy)) * 1.8, 0.0, 1.0) * smoothstep(.05, .35, w_lum);
	vec3 obs = vec3(.018, .022, .034) * smoothstep(.05, .3, w_lum) + vec3(.58, .68, .90) * w_rim * (.65 + .7 * sheen);
	float ts = dot(tp - uC, uN);
	float purp = max(lg.b - lg.g, 0.0);
	lg = mix(lg, obs, clamp(smoothstep(14.0, -2.0, ts) + smoothstep(.06, .22, purp), 0.0, 1.0));
	float lmask = smoothstep(.03, .22, max(w_lum, max(lg.r, max(lg.g, lg.b))));
	col = mix(col, lg * vec3(1.0, 1.06, 1.22) + vec3(.45, .56, .82) * w_rim * sheen * .55, lmask);

	// [YG-MARK] 11-05 更高级：刀口漏下来的光照亮正下方一带水面，水里倒映上面的几道光柱（被水波扭、断续），
	// 上下两半才是同一个世界；离刀口越远越沉到墨黑
	float wob = (fbm(vec2(p.x / uRes.y * 3.0, s / uRes.y * 9.0 - t * .5)) - .5) * uRes.y * .05 * (.3 + d * 3.0);
	float px2 = p.x + wob + s * .18 - uC.x;
	float leak = exp(-pow(px2 / (uRes.x * .16), 2.0));
	float shafts = exp(-pow((px2 + uRes.y * .10) / (uRes.y * .035), 2.0)) * .8
			+ exp(-pow((px2 - uRes.y * .16) / (uRes.y * .05), 2.0))
			+ exp(-pow((px2 - uRes.y * .36) / (uRes.y * .03), 2.0)) * .6;
	float sbrk = smoothstep(.35, .75, fbm3(vec2(p.x / uRes.y * 1.5, s / uRes.y * 22.0 - t * 1.4)));
	col += vec3(.30, .34, .46) * leak * exp(-d * 5.0) * .5;
	col += vec3(.42, .46, .58) * shafts * sbrk * exp(-d * 2.6) * smoothstep(0.0, .03, d) * .16;
	col *= mix(1.0, .55, smoothstep(.15, .6, d));
	COLOR = vec4(col, 1.0);
}