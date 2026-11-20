// [YG-MARK] 字成城（11-08）：水线以上的整个场景。夜空 → 三层字城 → 体积光 → 主字标 → 斩线 → 岸和灯。
// 坐标都按 1920×1080 设计单位。颜色直接在显示空间里算（和样张一致）。
shader_type canvas_item;
render_mode blend_disabled, unshaded;

const float WL = 770.0;
const vec2 DESIGN = vec2(1920.0, 1080.0);
const vec3 FOG = vec3(30.0, 43.0, 82.0) / 255.0;

uniform float uT = 0.0;
uniform vec2 uCam = vec2(0.0);
uniform float uZoom = 1.0;
uniform vec2 uCut0 = vec2(1000.0, 372.0);
uniform vec2 uD = vec2(.9703, -.2419);
uniform vec2 uN = vec2(.2419, .9703);
uniform float uTip = -5000.0;      // 刀尖走到的位置（沿刀方向）
uniform float uTail = -5000.0;     // 刀尾：过了这里刀身的强光退掉
uniform float uBlade = 0.0;        // 出刀时刀身的亮度
uniform float uLight = 0.0;        // 斩线的光，0～1
uniform float uFront = 0.0;        // 光从斩线往外推到多远（像素）
uniform float uOver = 0.0;         // 落点的过曝
uniform float uSlide = 0.0;        // 字上下两半沿刀错开
uniform float uOpen = 0.0;         // 确认时斩线张开
uniform float uFlood = 0.0;        // 确认时白光吞画面
uniform float uCrack = 0.0;        // 釉裂蔓延到多远
uniform float uSweepU = -5000.0;   // 扫过字面的光，沿刀的位置
uniform float uSweepA = 0.0;
uniform float uPrePoint = 0.0;     // 出刀前刀口那一点
uniform vec4 uLampX = vec4(380.0, 720.0, 1060.0, 1400.0);
uniform vec4 uLamp = vec4(0.0);
uniform sampler2D uCity : filter_linear, repeat_disable;
uniform sampler2D uWin : filter_linear, repeat_disable;
uniform sampler2D uLogo : filter_linear_mipmap, repeat_disable;
uniform sampler2D uLogoN : filter_linear_mipmap, repeat_disable;
uniform sampler2D uNoise : filter_linear, repeat_enable;

const vec4 LOGO_RECT = vec4(480.0, 136.0, 1000.0, 640.5);

float sstep(float a, float b, float x) {
	float t = clamp((x - a) / (b - a), 0.0, 1.0);
	return t * t * (3.0 - 2.0 * t);
}

vec2 layer(vec2 p, float par) {
	vec2 c = vec2(960.0, WL);
	return (p - c) / mix(1.0, uZoom, par) + c + uCam * par;
}

vec4 logo_at(vec2 q) {
	vec2 uv = (q - LOGO_RECT.xy) / LOGO_RECT.zw;
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
		return vec4(0.0);
	}
	return texture(uLogo, uv);
}

float fogk(float y) {
	return sstep(WL - 340.0, WL, y);
}

vec3 over_city(vec3 col, float a, vec3 tone, float k, float y, float sd, float lit) {
	float f = fogk(y) * k;
	vec3 c = mix(tone, FOG, f) + exp(-abs(sd) / 190.0) * vec3(.15, .155, .19) * lit * (1.0 - k * .5);
	return mix(col, c, a);
}

void fragment() {
	vec2 p = UV * DESIGN;
	vec2 ph = layer(p, 1.0);
	vec2 rel = ph - uCut0;
	float sd = dot(rel, uN);
	float ud = dot(rel, uD);
	float ad = abs(sd);
	float t = clamp(p.y / WL, 0.0, 1.0);

	// 夜空
	vec2 qs = layer(p, .12);
	float cloud = texture(uNoise, qs * vec2(.00042, .00105) + vec2(uT * .0035, .13)).r;
	float cloud2 = texture(uNoise, qs * vec2(.0007, .0017) + vec2(uT * .0065, .41)).g;
	vec3 col = mix(vec3(5.0, 6.0, 14.0) / 255.0, vec3(24.0, 34.0, 68.0) / 255.0, t) * (.42 + 1.15 * mix(cloud, cloud2, .35));
	col += sstep(.5, .78, cloud) * exp(-ad / 300.0) * vec3(.10, .115, .17) * uLight;

	// 字城
	vec2 qf = layer(p, .22);
	float far = texture(uCity, (qf + vec2(240.0, 0.0)) / vec2(2400.0, 1080.0)).r;
	col = over_city(col, far, vec3(15.0, 19.0, 34.0) / 255.0, .62, qf.y, sd, uLight);
	float mist = texture(uNoise, qf * vec2(.0005, .0016) + vec2(uT * .012, .7)).r;
	col += pow(fogk(p.y), 2.0) * FOG * (.07 + .50 * mist * mist);
	vec2 qm = layer(p, .42);
	vec2 muv = (qm + vec2(240.0, 0.0)) / vec2(2400.0, 1080.0);
	float mid = texture(uCity, muv).g;
	col = over_city(col, mid, vec3(8.0, 10.0, 20.0) / 255.0, .42, qm.y, sd, uLight);
	float win = texture(uWin, muv).r;
	float wf = .72 + .28 * sin(uT * .9 + floor(qm.x * .021) * 3.7);
	col += win * wf * vec3(1.0, .66, .33) * .78 * (1.0 - fogk(qm.y) * .5);
	float mist2 = texture(uNoise, qm * vec2(.0007, .002) + vec2(-uT * .018, .2)).r;
	col += pow(fogk(p.y), 3.0) * FOG * (.04 + .40 * mist2);
	vec2 qn = layer(p, .68);
	float near = texture(uCity, (qn + vec2(240.0, 0.0)) / vec2(2400.0, 1080.0)).b;
	col = over_city(col, near, vec3(5.0, 6.0, 13.0) / 255.0, .28, qn.y, sd, uLight);

	// 主字标的两半
	vec2 slide = uD * uSlide;
	vec2 shift = uN * uOpen;
	vec2 hq = sd < 0.0 ? ph - slide + shift : ph + slide - shift;
	vec4 hero = logo_at(hq);
	float ha = hero.a * sstep(1.6, 3.4, ad) ;
	if (uOpen > .01) {
		ha *= sstep(uOpen - 1.0, uOpen + 1.0, ad);
	}

	// 体积光：从每个像素朝斩线走，被字挡住的方向就暗。光束从字缝里穿出来
	if (uLight > .002) {
		float open_rays = 0.0;
		for (int i = 1; i <= 12; i++) {
			float k = float(i) / 13.0;
			open_rays += 1.0 - logo_at(ph - uN * sd * k).a;
		}
		open_rays /= 12.0;
		vec2 rn = vec2(ud * .0018, ad * .00012);
		float streak = texture(uNoise, rn + vec2(uT * .004, .6)).g;
		float beam = exp(-ad / 210.0) * pow(open_rays, 2.4) * (.12 + 1.1 * pow(streak, 2.0));
		col += beam * vec3(1.0, .93, .82) * .20 * uLight;
		// 字背后压一点暗，字和城才分得开
	}
	float halo = textureLod(uLogo, clamp((hq - LOGO_RECT.xy) / LOGO_RECT.zw, vec2(0.0), vec2(1.0)), 4.0).a;
	col *= 1.0 - halo * .42 * uLight;

	if (ha > .002) {
		vec2 luv = clamp((hq - LOGO_RECT.xy) / LOGO_RECT.zw, vec2(0.0), vec2(1.0));
		vec4 nt = texture(uLogoN, luv);
		vec3 n = normalize(vec3((nt.rg - .5) * 2.0, .62));
		float relief = pow(dot(hero.rgb, vec3(.333)), 2.0);
		float front = sstep(uFront, uFront - 150.0, ad);
		// 光源是最近的那段斩线
		vec3 L = normalize(vec3(-uN * sd, 150.0));
		vec3 V = vec3(0.0, 0.0, 1.0);
		vec3 Hv = normalize(L + V);
		float atten = exp(-ad / 170.0) * uLight * front;
		float diff = max(dot(n, L), 0.0);
		float spec = pow(max(dot(n, Hv), 0.0), 46.0);
		// 未受光时：和城一样黑，只有一点点夜空的冷色，看起来就是塔
		vec3 unlit = vec3(5.0, 6.0, 13.0) / 255.0 + relief * vec3(.022, .028, .05) * (.5 + .5 * n.y * -1.0);
		// 受光后的底色
		float lift = front * uLight;
		vec3 amb = relief * mix(vec3(.31, .34, .43), vec3(.54, .53, .54), exp(-ad / 340.0));
		float sky_n = clamp(-n.y * .5 + .5, 0.0, 1.0);
		amb *= .62 + .70 * sky_n;
		vec3 hc = mix(unlit, amb + vec3(.03, .035, .06), lift);
		hc += relief * diff * atten * vec3(1.10, 1.02, .90) * .70;
		hc += spec * atten * vec3(1.0, .96, .9) * .55;
		// 雨水沿字面往下淌：一道道亮和暗
		vec2 dq = vec2(hq.x * .021, hq.y * .0024 - uT * .10);
		float run = texture(uNoise, dq).r;
		float run2 = texture(uNoise, dq * vec2(2.3, 1.4) + .37).g;
		float wet = sstep(.56, .72, run) * (.4 + .6 * run2);
		hc += wet * pow(max(dot(n, normalize(vec3(.12, -.5, .86))), 0.0), 14.0) * vec3(.42, .47, .60) * lift;
		hc *= 1.0 - wet * .10 * lift;
		// 釉裂：光顺着裂缝透出来
		float cr = nt.b * sstep(uCrack, uCrack - 60.0, ad);
		hc = mix(hc, hc * .55, cr * .42);
		hc += cr * exp(-ad / 70.0) * vec3(1.0, .90, .72) * .62 * uLight;
		// 扫过字面的一道光
		float sw = exp(-pow((ud - uSweepU + hq.y * .28) / 76.0, 2.0)) * uSweepA;
		hc += (pow(max(dot(n, normalize(vec3(.42, -.34, .84))), 0.0), 20.0) * 1.0 + relief * .10) * sw * vec3(.95, .96, 1.0);
		// 字脚没进雾和水
		float hf = sstep(WL - 150.0, WL + 10.0, ph.y) * .5;
		hc = mix(hc, FOG * .55, hf * lift);
		// 肩部压缩：瓷再亮也留层次，不糊成一片白
		vec3 over_c = max(hc - vec3(.72), vec3(0.0));
		hc = min(hc, vec3(.72)) + (vec3(1.0) - exp(-over_c * 2.0)) * .26;
		col = mix(col, hc, ha);
	}

	// 岸：一条不规则的暗边
	float bank_n = texture(uNoise, vec2(ph.x * .0016, .13)).r;
	float bank = sstep(WL - 6.0 - 7.0 * bank_n, WL - 3.0 - 7.0 * bank_n, ph.y);
	col *= 1.0 - bank * .80;

	// 灯柱和灯：灯柱是暗线，灯在柱顶
	for (int i = 0; i < 4; i++) {
		float x = uLampX[i];
		vec2 lq = ph - vec2(x, WL - 70.0);
		if (abs(ph.x - x) < 1.7 && ph.y > WL - 64.0 && ph.y < WL) {
			col *= .1;
		}
		float k = uLamp[i];
		float r = length(lq);
		col += (exp(-r / 4.5) * 2.2 + exp(-r / 24.0) * .50 + exp(-r / mix(44.0, 130.0, clamp(k, 0.0, 1.0))) * .17) * vec3(1.0, .69, .36) * k;
		// 没亮也有一点火种
		col += exp(-r / 3.0) * vec3(1.0, .6, .3) * .10;
	}

	// 斩线
	float in_tip = step(ud, uTip);
	float env = exp(-pow(ud / 900.0, 2.0));
	float glow = exp(-ad / 7.0) * .30 + exp(-ad / 44.0) * .07 + exp(-ad / 190.0) * .02;
	col += glow * env * vec3(1.0, .933, .831) * uLight * in_tip;
	float core = exp(-ad / 1.0) * sstep(1250.0, 300.0, abs(ud));
	col += core * vec3(1.0, .988, .957) * 2.4 * in_tip * max(uLight, uBlade);
	float vio = step(0.0, sd) * exp(-sd / 5.0) * sstep(1250.0, 300.0, abs(ud));
	col += vio * vec3(110.0, 70.0, 224.0) / 255.0 * .62 * in_tip * max(uLight, uBlade);
	// 刀身：出刀那 0.14 秒，刀尖处最亮，后面拖一段
	if (uBlade > .001) {
		float beh = max(uTip - ud, 0.0);
		float tr = in_tip * exp(-beh / 520.0);
		col += exp(-ad / (1.4 + beh * .006)) * tr * 3.0 * uBlade * vec3(1.0, .98, .95);
		col += exp(-ad / 26.0) * tr * .38 * uBlade * vec3(.86, .84, 1.0);
		col += exp(-length(vec2(ud - uTip, sd)) / 7.0) * 1.2 * uBlade;
	}
	// 出刀前左端那一点
	if (uPrePoint > .001) {
		vec2 pp = ph - (uCut0 - uD * 1040.0);
		col += exp(-length(pp) / 7.0) * uPrePoint * vec3(1.0, .97, .92) * 1.5;
		col += exp(-abs(dot(pp, uN)) / 1.3) * exp(-abs(dot(pp, uD)) / 150.0) * uPrePoint * .75;
	}
	// 落点的过曝：只有雾和光亮一下，不是全屏白闪
	col += uOver * (exp(-ad / 280.0) * vec3(.62, .60, .58) + vec3(.035, .04, .06));
	// 确认：白光从缝里吞画面
	if (uOpen > .01) {
		col += exp(-max(ad - uOpen, 0.0) / (10.0 + uOpen * .35)) * vec3(1.0, .97, .91) * 1.6;
	}
	col = mix(col, vec3(1.0, .975, .93), uFlood);
	COLOR = vec4(col, 1.0);
}
