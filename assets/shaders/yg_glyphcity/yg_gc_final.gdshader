// [YG-MARK] 字成城（11-08）：把场景贴上去，算水面（真倒影、波、涟漪、灯影），加泛光、前景和收尾。
shader_type canvas_item;
render_mode blend_disabled, unshaded;

const float WL = 770.0;
const vec2 DESIGN = vec2(1920.0, 1080.0);

uniform float uT = 0.0;
uniform vec2 uCam = vec2(0.0);
uniform float uShock = -1.0;       // 落点后的秒数：水面冲击波
uniform vec2 uShockC = vec2(1000.0, 790.0);
uniform float uBoost = 0.0;        // 落点后水面短暂提亮
uniform vec4 uLampX = vec4(380.0, 720.0, 1060.0, 1400.0);
uniform vec4 uLamp = vec4(0.0);
uniform vec4 uLampLen = vec4(0.0); // 灯影落到哪（距水线）
uniform vec4 uRingX = vec4(0.0);   // 选中时落点的涟漪：x, 寿命 0～1
uniform float uRingT = -1.0;
uniform float uRingCx = 0.0;
uniform float uBand = 0.0;         // 压低菜单一带，字才读得清
uniform float uFade = 0.0;
uniform sampler2D uScene : filter_linear, repeat_disable;
uniform sampler2D uBloomA : filter_linear, repeat_disable;
uniform sampler2D uBloomB : filter_linear, repeat_disable;
uniform sampler2D uNoise : filter_linear, repeat_enable;
uniform sampler2D uFore : filter_linear, repeat_disable;

float sstep(float a, float b, float x) {
	float t = clamp((x - a) / (b - a), 0.0, 1.0);
	return t * t * (3.0 - 2.0 * t);
}

float h11(float x) {
	return fract(sin(x * 91.3458) * 47453.5453);
}

void fragment() {
	vec2 p = UV * DESIGN;
	vec3 col;
	if (p.y < WL) {
		col = texture(uScene, UV).rgb;
	} else {
		float d = clamp((p.y - WL) / (1080.0 - WL), 0.0, 1.0);
		float z = 1.0 / (d + .2);
		// 横向按透视压缩，纵向用对数，波纹在每个深度都是横向拉长的，不会变成放射线
		vec2 wuv = vec2((p.x - 960.0) * z * .00036, log(d + .2) * .45);
		vec2 n = texture(uNoise, wuv + vec2(uT * .006, uT * .019)).rg - .5;
		n += (texture(uNoise, wuv * 2.7 + vec2(-uT * .011, uT * .037)).gb - .5) * .62;
		n *= 1.7;
		float rings = 0.0;
		vec2 ring_n = vec2(0.0);
		for (int i = 0; i < 22; i++) {
			float fi = float(i);
			float per = 1.3 + h11(fi + 3.1) * 1.9;
			float tt = uT / per + h11(fi * 1.7);
			float cell = floor(tt);
			float age = fract(tt);
			float rx = h11(fi * 3.3 + cell * 1.31) * 1920.0;
			float ry_k = h11(fi * 5.1 + cell * 2.17);
			float ry = mix(WL + 12.0, 1072.0, ry_k * ry_k);
			float dep = (ry - WL) / (1080.0 - WL);
			vec2 v = (p - vec2(rx, ry)) * vec2(1.0, 4.1);
			float rad = age * (20.0 + dep * 96.0);
			float r = length(v);
			float wave = exp(-abs(r - rad) / (.9 + dep * 2.2)) * (1.0 - age) * (1.0 - age);
			rings += wave * (.3 + dep);
			ring_n += normalize(v + vec2(.001)) * wave;
		}
		// 选中项落点的涟漪
		if (uRingT >= 0.0 && uRingT < 1.0) {
			vec2 v = (p - vec2(uRingCx, 984.0)) * vec2(1.0, 3.6);
			float r = length(v);
			float rad = 12.0 + uRingT * 220.0;
			float wave = exp(-abs(r - rad) / 3.2) * pow(1.0 - uRingT, 1.6);
			rings += wave * 1.1;
			ring_n += normalize(v + vec2(.001)) * wave * 1.3;
		}
		// 落点的冲击波：由远及近
		float shock = 0.0;
		if (uShock >= 0.0 && uShock < 1.6) {
			vec2 v = (p - uShockC) * vec2(1.0, 3.3);
			float rad = uShock * 1180.0;
			float r = length(v);
			shock = exp(-abs(r - rad) / (10.0 + uShock * 34.0)) * pow(1.0 - uShock / 1.6, 1.4);
			ring_n += normalize(v + vec2(.001)) * shock * 1.4;
		}
		float ax = 7.0 + d * 62.0;
		float ay = 5.0 + d * 44.0;
		vec2 off = n * vec2(ax, ay) + ring_n * vec2(9.0, 16.0);
		vec3 refl = vec3(0.0);
		for (int k = 0; k < 5; k++) {
			float jy = (float(k) - 2.0) * (1.0 + d * 8.0);
			vec2 s = vec2(p.x + off.x, 2.0 * WL - p.y + off.y + jy);
			s.y = min(s.y, WL - 14.0);
			refl += texture(uScene, s / DESIGN).rgb;
		}
		refl /= 5.0;
		float fres = .92 - .50 * pow(d, .7);
		col = refl * fres * vec3(.84, .90, 1.02) + vec3(3.0, 4.0, 9.0) / 255.0;
		// 碎波的高光：只有上面有亮东西才亮
		float sp = sstep(.62, .78, .5 + n.y * .9) * (.2 + d);
		vec3 mir = texture(uScene, vec2(p.x, min(2.0 * WL - p.y, WL - 1.0)) / DESIGN, 3.0).rgb;
		col += sp * (.12 + 1.2 * dot(mir, vec3(.33))) * vec3(.26, .30, .40) * .7;
		col += rings * vec3(.24, .28, .38) * (.5 + 1.3 * dot(mir, vec3(.33)));
		col += shock * vec3(.62, .62, .68) * .20;
		col *= 1.0 + uBoost * .5;
		// 灯影
		for (int i = 0; i < 4; i++) {
			float k = uLamp[i];
			if (k < .005) {
				continue;
			}
			float cx = uLampX[i];
			float wob = (texture(uNoise, vec2(p.x * .0004 + float(i) * .31, p.y * .009 - uT * .05)).r - .5) * (14.0 + d * 90.0);
			float s = 4.0 + d * mix(5.0, 17.0, clamp(k, 0.0, 1.0));
			float streak = exp(-pow((p.x - cx - wob) / s, 2.0));
			float slit = .24 + 1.65 * sstep(.47, .66, texture(uNoise, vec2(p.x * .0024, p.y * .023 - uT * .13)).g);
			float reach = sstep(0.0, -46.0, (p.y - WL) - uLampLen[i]);
			col += streak * slit * reach * vec3(1.0, .643, .306) * .95 * k;
		}
		col *= 1.0 - exp(-pow((p.y - 992.0) / 56.0, 2.0)) * .5 * uBand;
	}
	// 泛光
	col += texture(uBloomA, UV).rgb * .22 + texture(uBloomB, UV).rgb * .24;
	// 前景：贴镜头的虚焦字形，比主体动得多
	float fg = texture(uFore, UV + uCam * 1.7 / DESIGN).r;
	col *= 1.0 - fg * .94;
	// 暗角
	float vig = length((p - vec2(960.0, 497.0)) / vec2(1190.0, 800.0));
	col *= 1.0 - sstep(.55, 1.12, vig) * .70;
	float grain = fract(sin(dot(p + fract(uT * 7.13) * vec2(311.7, 173.3), vec2(12.9898, 78.233))) * 43758.5453) - .5;
	col += grain * .012;
	col *= 1.0 - uFade;
	COLOR = vec4(col, 1.0);
}
