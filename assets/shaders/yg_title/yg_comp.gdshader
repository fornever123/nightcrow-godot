// [YG-MARK] 由 YG 新增（首页「断晓 · 断光」WebGL 版移植到 Godot）。
// 合成：一刀两断 + 时空撕裂带 + 斩裂昼夜互换。
// 来源：E:\.0download\code_artifact (1).html 的 FS_COMP，逐行翻译；
// 网页版把玩家刀口存在 uniform 数组里，这里拆成 uTC0..2 / uTA0..2 三个槽。
// 删除方法：见 docs/YG-首页断光-删除清单.md。

shader_type canvas_item;
render_mode blend_mix, unshaded;

#include "res://assets/shaders/yg_title/yg_noise.gdshaderinc"

uniform vec2 uRes = vec2(1280.0, 720.0);
uniform float uTime = 0.0;
uniform vec2 uC = vec2(640.0, 302.0);
uniform vec2 uD = vec2(0.984, 0.179);
uniform vec2 uN = vec2(-0.179, 0.984);
uniform vec2 uShake = vec2(0.0);
uniform vec2 uTipPos = vec2(0.0);
uniform vec2 uGlintPos = vec2(0.0);
uniform float uSw = -100000.0;
uniform float uTip = -100000.0;
uniform float uSlide = 0.0;
uniform float uGap = 0.0;
uniform float uFront = 0.0;
uniform float uSeam = 0.0;
uniform float uShock = 0.0;
uniform float uOpen = 0.0;
uniform float uVoid = 0.0;
uniform float uCollapse = 0.0;
uniform float uSeamLen = 1.0;
uniform float uGlint = 0.0;
uniform float uCutOn = 0.0;
uniform float uSlashing = 0.0;
uniform float uDragOn = 0.0;
uniform vec4 uDrag = vec4(0.0);
uniform vec4 uMouse = vec4(0.0);
uniform vec4 uTC0 = vec4(0.0);
uniform vec4 uTC1 = vec4(0.0);
uniform vec4 uTC2 = vec4(0.0);
uniform vec4 uTA0 = vec4(0.0);
uniform vec4 uTA1 = vec4(0.0);
uniform vec4 uTA2 = vec4(0.0);
uniform sampler2D uL : filter_linear, repeat_disable;
uniform sampler2D uS : filter_linear, repeat_disable;
uniform sampler2D uFx : filter_linear, repeat_disable;

const vec3 VIO = vec3(.54, .40, 1.0);
const vec3 GRY = vec3(.82, .82, .86);
const vec3 WHT = vec3(1.0, .96, 1.08);
const vec3 GLD = vec3(1.0, .88, .68);

vec2 P(vec2 uv) { return uv * uRes; }
vec2 toUv(vec2 p) { return p / uRes; }

float inb(vec2 p) {
	vec2 a = smoothstep(vec2(-2.0), vec2(1.0), p) * smoothstep(uRes + vec2(2.0), uRes - vec2(1.0), p);
	return a.x * a.y;
}

void cut_slice(vec4 tc, vec4 ta, float idx, inout vec2 p, inout vec3 add, inout float swap_mask) {
	if (ta.x + ta.y < .002) {
		return;
	}
	vec2 d = vec2(cos(tc.z), sin(tc.z));
	vec2 n = vec2(-d.y, d.x);
	float si = dot(p - tc.xy, n);
	float ui = dot(p - tc.xy, d);
	float sd = si < 0.0 ? -1.0 : 1.0;
	float a = abs(si);
	float half_l = max(tc.w, 40.0);
	float u_norm = abs(ui) / half_l;
	float blade_env = clamp(1.0 - u_norm * u_norm, 0.0, 1.0);
	float tear_w = ta.x * 1.55 * blade_env;
	float in_tear = smoothstep(tear_w + .8, max(tear_w - .8, 0.0), a) * step(u_norm, 1.02);
	swap_mask = max(swap_mask, in_tear * clamp(ta.y * 1.2, 0.0, 1.0));
	float tear_edge = exp(-abs(a - tear_w) / 1.25) * blade_env;
	float sw = exp(-pow((a - ta.z * 2400.0) / 50.0, 2.0)) * exp(-ta.z * 3.5) * 15.0;
	float fk = .7 + .3 * vn(vec2(ui * .02 - uTime * 6.0, idx * 7.0));
	add += (WHT * exp(-a / 1.2) * 2.1 * step(tear_w, .5) + (WHT * 1.8 + VIO * 1.4) * tear_edge
			+ VIO * exp(-max(a - tear_w, 0.0) / 8.0) * .55 + GRY * exp(-a / 60.0) * .05)
			* ta.y * fk * smoothstep(1.18, .88, u_norm);
	p -= sd * (ta.x * d * blade_env + n * (min(ta.x * .12, 1.8) * blade_env + sw));
}

void fragment() {
	vec2 p0 = P(UV);
	vec2 p = p0 + uShake;
	vec3 add = vec3(0.0);
	float swap_mask = 0.0;
	cut_slice(uTC0, uTA0, 0.0, p, add, swap_mask);
	cut_slice(uTC1, uTA1, 1.0, p, add, swap_mask);
	cut_slice(uTC2, uTA2, 2.0, p, add, swap_mask);

	vec2 q = p - uC;
	float s = dot(q, uN);
	float u = dot(q, uD);
	float on = uCutOn * step(u, uTip);
	float sw = 0.0;
	if (uShock > 0.0) {
		sw = exp(-pow((abs(s) - uShock * 2800.0) / 80.0, 2.0)) * exp(-uShock * 2.4) * 28.0;
	}
	float sd = s < 0.0 ? -1.0 : 1.0;
	float a = abs(s);
	float gap = uGap + uOpen * uRes.y * .78;
	float slide = uSlide + uOpen * uRes.x * .05;
	// 刀口边缘的黑曜石折射扭曲
	float refract_w = (vn(vec2(u * .065 - uTime * 2.5, s * .12)) - .5) * exp(-max(a - gap, 0.0) / 14.0) * 5.5 * on * (1.0 - uOpen);
	vec3 col;
	float s1 = s;
	if (on > .5) {
		if (a < gap) {
			col = WHT * uVoid * exp(-a / (1.6 + uOpen * 7.0)) * 2.4 + GRY * uVoid * exp(-a / (20.0 + uOpen * uRes.y * .12)) * .04;
		} else {
			vec2 src = p - sd * (gap * uN + (slide + refract_w) * uD) - uN * sd * sw;
			vec2 qq = src - uC;
			s1 = dot(qq, uN);
			float u1 = dot(qq, uD);
			s1 /= max(1.0 - uCollapse, 1e-3);
			src = uC + u1 * uD + s1 * uN;
			vec3 L = texture(uL, toUv(src)).rgb;
			vec3 S = texture(uS, toUv(src)).rgb;
			if (sd < 0.0) {
				col = L;
			} else {
				col = mix(L, S, smoothstep(0.0, 80.0, uFront - s1));
				float fe = step(1.0, uFront) * (1.0 - smoothstep(.5 * uRes.y, 1.2 * uRes.y, uFront));
				col += GRY * (exp(-abs(s1 - uFront) / 3.5) * 1.2 + exp(-abs(s1 - uFront) / 30.0) * .12) * fe;
			}
			// 玩家斩击裂隙内：局部昼夜世界互换
			if (swap_mask > .005) {
				vec3 other = sd < 0.0 ? (S * vec3(1.15, 1.2, 1.4) + vec3(.02, .015, .045))
						: (L * vec3(1.12, 1.06, .96) + vec3(.035, .025, .01));
				col = mix(col, other, swap_mask * .92);
			}
			if (uOpen + uCollapse > .0005) {
				col *= inb(src) * mix(1.0, .25, uCollapse);
			}
		}
	} else {
		col = texture(uL, toUv(p)).rgb + texture(uS, toUv(p)).rgb;
	}

	float len_m = smoothstep(uSeamLen * uRes.x * .62 + 2.0, uSeamLen * uRes.x * .62 - 40.0, abs(u));
	float fl = .7 + .3 * vn(vec2(u * .012 - uTime * 4.0, 3.0)) + .18 * vn(vec2(u * .05 + uTime * 9.0, 1.0));
	float ae = uOpen > .0005 ? a * (1.0 + uOpen * 3.0) : max(a - gap, 0.0);
	if (uOpen > .0005) {
		add += (WHT * exp(-abs(a - gap) / 1.4) * 1.8 + VIO * exp(-abs(a - gap) / 9.0) * .3) * on * (1.0 - uOpen * .6);
	}
	// [YG-MARK] 11-05 更高级：刀口中间最亮、两头收细（原来 .29 宽、两头还留 12% 亮度，读起来是一根匀的亮线）
	float al = exp(-pow(u / (uRes.x * .24), 2.0));
	float ef = smoothstep(uRes.x * .56, uRes.x * .2, abs(u));
	float cw = mix(.32, 1.0, al);
	float vb = .78 + .22 * sin(uTime * .8);
	// 鼠标靠近刀口时的能量共鸣
	float m_dist_seam = length(p0 - uMouse.xy);
	float m_res = exp(-m_dist_seam / (uRes.y * .11)) * exp(-ae / 18.0) * uMouse.w * (.45 + uMouse.z * .85);
	// 刀缝边缘细碎黑曜石裂纹与游走电弧
	float jag = pow(vn(vec2(u * .11 - s * .08, uTime * .6)), 3.0) * exp(-ae / 9.0) * al;
	float arc_disp = (vn(vec2(u * .032 - uTime * 6.5, floor(uTime * 14.0) * .7)) - .5) * 8.5 * (al + m_res * .8)
			+ (vn(vec2(u * .11 + uTime * 13.0, 3.7)) - .5) * 3.5;
	float arc = exp(-abs(s - gap * sd - arc_disp) / 1.1) * step(.42, vn(vec2(u * .02 + uTime * 3.5, 8.0))) * (al * .85 + m_res) * on * (1.0 - uOpen);
	vec3 seam = WHT * exp(-ae / (.82 * cw)) * 2.1 * mix(.05, 1.15, al)
			+ VIO * exp(-ae / (3.6 * cw)) * .62 * (al * vb + m_res)
			+ VIO * exp(-ae / 24.0) * .042 * al * vb
			+ (WHT * 1.2 + VIO * 1.5) * arc + GLD * jag * .28;
	add += seam * uSeam * fl * on * len_m * ef * (1.0 - uOpen * .85);
	// 鼠标划过昼光悬珠层时的微弱时空涟漪
	if (uMouse.w > .5 && uMouse.z > .02) {
		float mr = length(p0 - uMouse.xy);
		float m_ring = exp(-abs(mr - uRes.y * .028) / 1.8) * uMouse.z * .22;
		add += mix(GLD, VIO, smoothstep(-20.0, 20.0, s)) * m_ring;
	}
	if (uSlashing > 0.0) {
		float beh = max(uSw - u, 0.0);
		float tr = step(u, uSw) * exp(-beh / 650.0);
		add += (WHT * exp(-a / (1.0 + beh * .012)) * 4.5 + VIO * exp(-a / (8.0 + beh * .03)) * .6
				+ GRY * exp(-a / (40.0 + beh * .08)) * .25) * tr * uSlashing;
		vec2 dt = p0 - uTipPos;
		float du = dot(dt, uD);
		float dn = dot(dt, uN);
		add += (vec3(1.0) * exp(-length(dt) / 9.0) * 16.0 + WHT * exp(-abs(dn) / 1.4) * exp(-abs(du) / 280.0) * 5.0
				+ GRY * exp(-length(dt) / 60.0) * 1.2 + WHT * exp(-abs(du) / 1.4) * exp(-abs(dn) / 26.0) * 1.4) * uSlashing;
	}
	if (uGlint > 0.0) {
		vec2 dt = p0 - uGlintPos;
		float du = dot(dt, uD);
		float dn = dot(dt, uN);
		add += (exp(-length(dt) / 4.0) * 12.0 + exp(-abs(dn) / .9) * exp(-abs(du) / 150.0) * 3.0
				+ exp(-abs(du) / .9) * exp(-abs(dn) / 45.0) * 1.6) * uGlint * WHT
				+ GRY * exp(-length(dt) / 40.0) * uGlint * .6;
	}
	if (uDragOn > 0.0) {
		vec2 A = uDrag.xy;
		vec2 B = uDrag.zw;
		vec2 ab = B - A;
		float hh = clamp(dot(p0 - A, ab) / max(dot(ab, ab), 1.0), 0.0, 1.0);
		float dd = length(p0 - A - ab * hh);
		add += (WHT * exp(-dd / 1.1) * 1.35 + VIO * exp(-dd / 7.5) * .38) * hh * hh * uDragOn
				+ (WHT * 1.4 + VIO * .6) * exp(-length(p0 - B) / 6.5) * 3.4 * uDragOn;
	}
	col += add;
	col += texture(uFx, toUv(p0 + uShake)).rgb;
	if (isnan(col.x) || isnan(col.y) || isnan(col.z) || isinf(col.x) || isinf(col.y) || isinf(col.z)) {
		col = vec3(0.0);
	}
	COLOR = vec4(min(col, vec3(200.0)), 1.0);
}
