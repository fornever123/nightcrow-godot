shader_type canvas_item;
render_mode blend_mix;

// 首页舞台（《断晓》）。这里只画世界本身：墨影、凝滞的昼光、冻在光里的雨珠与光尘、
// 断口与熔线、那一刀、转场墨涌。参数全部由 scripts/ui/cut_stage.gd 每帧驱动，
// 所以可以用 seek() 定格截图。

uniform vec2 res = vec2(1280.0, 720.0);
uniform float t = 0.0;
uniform float fade = 1.0;
uniform float reveal = 1.0;
uniform float dust_amt = 0.0;
uniform float gap = 0.0;
uniform float cut_y = 300.0;
uniform float up_shift = 0.0;
uniform float down_shift = 0.0;
uniform float upper_amt = 1.0;
uniform float lower_amt = 1.0;
uniform float leak = 0.0;
uniform float slash_x = -9999.0;
uniform float slash_alpha = 0.0;
uniform float flash = 0.0;
uniform float shock = -2.0;
uniform float shock_amt = 0.0;
uniform float ink = 0.0;
uniform float cx_off = 0.0;
uniform float drift = 0.0;
uniform float breathe = 0.0;

const vec3 C_DEEP = vec3(0.0030, 0.0040, 0.0095);
const vec3 C_INK  = vec3(0.0090, 0.0100, 0.0200);
const vec3 C_WARM = vec3(1.0000, 0.9150, 0.7550);
const vec3 C_GOLD = vec3(1.0000, 0.7900, 0.4800);
const vec3 C_SILV = vec3(0.8400, 0.8850, 0.9800);
const vec3 C_VIOL = vec3(0.4400, 0.3000, 0.9600);
const vec3 C_VHOT = vec3(0.7800, 0.6800, 1.0000);

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.52;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 p = UV * res;
	p.y += drift;
	float cx = res.x * 0.5 + cx_off;
	float hw = res.x * 0.126;
	float dx = abs(p.x - cx);

	// ---------------------------------------------------------------- 影 / 墨
	float shadow = smoothstep(res.y * 0.38, res.y * 1.06, p.y);
	vec2 q = p * 0.0038 + vec2(t * 0.0095, -t * 0.0060);
	float n1 = fbm(q);
	float n2 = fbm(q * 2.30 + n1 * 1.70 + vec2(-t * 0.008, t * 0.0055));
	vec3 col = mix(C_DEEP, C_INK, n2 * 0.85 + 0.12);

	// 影子里替人流逝的时间：几乎看不见的冷紫细流
	float vein = smoothstep(0.026, 0.0, abs(n2 - 0.50));
	col += C_VIOL * vein * 0.030 * (0.35 + shadow * 0.75);
	// 影面极缓的水纹
	float ripple = 0.5 + 0.5 * sin(p.y * 0.050 + n2 * 9.0 + t * 0.50);
	col += C_VIOL * ripple * 0.0035 * shadow;
	// 黑液在影子里流动（时间的低语），只有一层极缓的明暗
	vec2 mq = vec2(p.x * 0.0016, p.y * 0.0044) + vec2(t * 0.005, -t * 0.009);
	float flow = fbm(mq);
	vec2 mq2 = vec2(p.x * 0.0030, p.y * 0.0082) + vec2(-t * 0.003, t * 0.007);
	float flow2 = fbm(mq2);
	col += vec3(0.016, 0.019, 0.040) * smoothstep(0.36, 0.88, flow) * shadow * (0.55 + 0.45 * flow2);
	col -= vec3(0.006, 0.006, 0.010) * smoothstep(0.62, 0.20, flow2) * shadow;
	// 墨的边缘：用噪声梯度当液体表面的反光边
	float rim = length(vec2(dFdx(n2), dFdy(n2)));
	col += vec3(0.065, 0.080, 0.145) * smoothstep(0.0020, 0.0300, rim) * shadow * 0.24;
	// 远处的冷雾，避免死黑
	col += C_SILV * n1 * 0.006 * (1.0 - shadow);

	// ---------------------------------------------------------------- 影子里的雨（时间的流动）：光柱外有雨，光柱里没有
	if (dust_amt > 0.01) {
		float col_id = floor(p.x / 7.0);
		float hr = hash11(col_id * 3.7);
		if (hr > 0.58) {
			float speed = 210.0 + 250.0 * hash11(col_id + 5.3);
			float len = 9.0 + 22.0 * hash11(col_id + 8.1);
			float phase = hash11(col_id + 11.9);
			float ytop = mod(p.y - t * speed - phase * 760.0, 780.0) - 30.0;
			float sx = (col_id + 0.5) * 7.0;
			float slant = -0.10;
			float dxr = abs(p.x - (sx + (p.y - ytop) * slant));
			float seg = 1.0 - smoothstep(0.0, 1.0, abs(p.y - (ytop - len * 0.5)) / (len * 0.5));
			float a = exp(-pow(dxr / 0.55, 2.0)) * seg * 0.20;
			a *= smoothstep(hw * 0.85, hw * 1.30, dx) * (0.30 + 0.70 * shadow);
			col += vec3(0.60, 0.66, 0.80) * a;
		}
	}

	// ---------------------------------------------------------------- 天上的裂缝：昼光从断环里漏下来
	float sky = exp(-pow((p.x - cx) / (hw * 3.05), 2.0)) * (1.0 - smoothstep(0.0, res.y * 0.24, p.y));
	sky *= 0.72 + 0.28 * fbm(vec2(p.x * 0.006 + t * 0.05, t * 0.03));
	col += mix(C_GOLD, C_WARM, 0.55) * sky * 0.115 * clamp(reveal, 0.0, 1.0) * fade;

	// ---------------------------------------------------------------- 昼光光柱
	float reveal_end = -90.0 + (res.y + 190.0) * clamp(reveal, 0.0, 1.0);
	float head = 1.0 - smoothstep(reveal_end - 4.0, reveal_end + 46.0, p.y);
	float bottom = 1.0 - smoothstep(res.y * 0.70, res.y * 1.06, p.y);

	float dy = p.y - cut_y;
	float gap_half = gap * 0.5;
	float w_up = 1.0 - smoothstep(gap_half, gap_half + 1.6, dy);
	float w_lo = smoothstep(gap_half, gap_half + 1.6, dy);
	float cutk = clamp(gap / 18.0, 0.0, 1.0);
	float yy = p.y - (dy < 0.0 ? up_shift : down_shift);
	float dy2 = p.y - cut_y;

	float body = exp(-pow(dx / hw, 2.0) * 2.4);
	// 下半截沉进影子，边缘被影揉碎、慢慢摆
	float wob = sin(yy * 0.055 + t * 1.15 + sin(p.x * 0.010) * 2.2) * 5.5 * w_lo;
	float body_lo = exp(-pow(abs(p.x - cx + wob) / (hw * 1.28), 2.0) * 2.2);
	float halo = exp(-pow(dx / (hw * 1.70), 2.0) * 1.45);
	float inner = exp(-pow(dx / (hw * 0.300), 2.0));
	float core = exp(-pow(dx / max(hw * 0.075, 3.0), 2.0));
	float lit_mask = head * (1.0 - smoothstep(res.y * 0.72, res.y * 1.06, yy));
	float seg = clamp(w_up * upper_amt + w_lo * lower_amt, 0.0, 1.0);
	float lit = lit_mask * seg;

	// 光柱里的雾：被光冻住的水汽
	float inside = 1.0 - smoothstep(hw * 0.74, hw * 1.16, dx);
	float fog = fbm(vec2(p.x * 0.011, yy * 0.0055) + vec2(0.0, t * 0.020));
	fog = smoothstep(0.26, 0.82, fog) * inside;

	// 凝滞的白色丝弦：一束细丝，边缘收在光柱里
	float strands = 0.0;
	for (int i = 0; i < 2; i++) {
		float k = float(i);
		float spacing = hw * (0.072 + 0.058 * k);
		float g = (p.x - cx) / spacing;
		float id = floor(g);
		float hh = hash11(id * 1.73 + k * 13.17);
		float alive_s = step(0.38, hh);
		float wob = sin(yy * 0.0105 + hh * 6.2831) * (1.1 + 1.6 * hash11(id + 5.5));
		float local = (fract(g) - 0.5) * spacing - wob;
		float w = 0.55 + 1.35 * hash11(id * 3.11 + k * 7.71);
		float flick = 0.85 + 0.15 * sin(t * 0.45 + hh * 22.0);
		strands += alive_s * exp(-pow(local / w, 2.0)) * (0.05 + 0.10 * hash11(id * 5.37 + k)) * flick;
	}
	strands *= inside;

	vec3 beam = mix(C_GOLD, C_WARM, 0.62) * (halo * 0.075 + mix(body, body_lo, w_lo) * 0.330);
	float spill = exp(-pow(dx / (hw * 4.2), 2.0) * 1.1);
	beam += C_GOLD * spill * lit * 0.020;
	beam += C_WARM * inner * 0.170;
	beam += vec3(1.0, 0.985, 0.960) * core * 0.520;
	beam += C_WARM * strands * 1.45;
	beam += C_WARM * fog * 0.100;
	col += beam * lit;

	// 被斩断的截面：断口两侧有一点点冷紫的硬边
	float edge = exp(-pow((abs(dy) - gap_half) / 1.15, 2.0)) * cutk;
	col += C_VHOT * edge * lit * 0.05;

	// 光柱落进影面：一小片倒影光
	float refl = exp(-pow((p.x - cx) / (hw * 1.35), 2.0)) * exp(-pow((p.y - res.y * 0.80) / 40.0, 2.0));
	col += C_WARM * refl * 0.060 * (1.0 - clamp(lower_amt, 0.0, 1.0) * 0.55) * head;

	// ---------------------------------------------------------------- 前景虚焦的光斑（景深）
	if (dust_amt > 0.01) {
		vec2 bg = vec2(330.0, 280.0);
		vec2 bc = floor(p / bg);
		float bh = hash21(bc + 21.7);
		if (bh > 0.52) {
			vec2 c = (bc + vec2(hash21(bc + 1.9), hash21(bc + 4.3))) * bg;
			c.x += sin(t * 0.11 + bh * 6.0) * 20.0;
			c.y += cos(t * 0.07 + bh * 3.0) * 12.0;
			float r = 24.0 + 44.0 * hash21(bc + 8.1);
			float d = length(p - c);
			float a = exp(-pow(d / r, 2.0)) * (0.018 + 0.030 * hash21(bc + 12.5));
			col += mix(C_GOLD, C_WARM, 0.45) * a * dust_amt;
		}
	}

	// ---------------------------------------------------------------- 冻在光里的雨珠
	if (dust_amt > 0.001 && inside > 0.01) {
		vec2 gs = vec2(92.0, 84.0);
		vec2 cell = floor(p / gs);
		float h = hash21(cell);
		if (h > 0.70) {
			vec2 jit = vec2(hash21(cell + 3.7), hash21(cell + 9.1)) * 0.66 + 0.17;
			vec2 c = (cell + jit) * gs;
			float falls = step(0.55, hash21(cell + 17.3));
			c.y += leak * (24.0 + 46.0 * hash21(cell + 5.5)) * falls;
			float r = 1.8 + 2.8 * hash21(cell + 11.9);
			float d = length(p - c);
			float disc = 1.0 - smoothstep(r * 0.60, r, d);
			float spec = pow(max(0.0, 1.0 - d / (r * 1.7)), 8.0);
			float glow = exp(-pow(d / (r * 2.6), 2.0)) * 0.18;
			vec3 bead = mix(C_GOLD, C_WARM, 0.5) * (disc * 0.42 + glow);
			bead += vec3(1.0, 0.99, 0.96) * spec * 0.65 * disc;
			col += bead * dust_amt * inside * (0.70 + 0.60 * clamp(upper_amt, 0.0, 1.0));
		}
		// 更细的光尘
		vec2 gs2 = vec2(27.0, 29.0);
		vec2 c2 = floor(p / gs2);
		float h2 = hash21(c2 + 51.3);
		if (h2 > 0.90) {
			vec2 c = (c2 + vec2(hash21(c2 + 1.1), hash21(c2 + 2.2))) * gs2;
			float tw = 0.5 + 0.5 * sin(t * 1.10 + h2 * 41.0);
			col += C_WARM * exp(-pow(length(p - c) / 0.85, 2.0)) * 0.45 * tw * dust_amt * inside;
		}
	}

	// ---------------------------------------------------------------- 断口之下：时间漏成细细的光丝
	if (leak > 0.02) {
		float lane2 = floor(p.x / 9.0);
		float hL = hash11(lane2 * 1.7 + 4.3);
		float keep = step(0.84, hL);
		float sx = (lane2 + 0.5) * 9.0;
		float w = 0.55 + 1.25 * hash11(lane2 + 2.2);
		float reach = min(leak, 1.35) * 250.0 * (0.30 + 0.55 * hash11(lane2 + 8.8));
		float dyl = p.y - (cut_y + gap * 0.6);
		float alive = step(0.0, dyl) * (1.0 - smoothstep(reach * 0.45, reach, dyl));
		float sway = sin(dyl * 0.05 + t * 0.9 + hL * 9.0) * 2.2;
		float la = exp(-pow((p.x - sx + sway) / w, 2.0)) * alive * 0.085;
		la *= 1.0 - smoothstep(res.y * 0.50, res.y * 0.62, p.y);
		col += C_WARM * la * (1.0 - smoothstep(hw * 0.85, hw * 1.35, abs(p.x - cx)));
	}

	// ---------------------------------------------------------------- 断口漏下的时间
	if (leak > 0.01) {
		float lane = floor(p.x / 12.0);
		float hl = hash11(lane);
		if (hl > 0.56 && dx < hw * 1.10) {
			float ph = fract(hl + leak * (0.18 + 0.10 * hash11(lane + 9.0)));
			float px = (lane + hash11(lane + 3.0)) * 12.0;
			float py = cut_y + gap * 0.8 + ph * 245.0;
			float d = length(vec2(p.x - px, p.y - py));
			float a = exp(-pow(d / 1.15, 2.0)) * (1.0 - ph) * 0.40 * min(leak, 1.0);
			col += C_WARM * a;
		}
	}

	// ---------------------------------------------------------------- 断口的黑缝与熔线
	// 先压暗：斩断之后，缝里是黑的，所以两截才分得开
	float band = exp(-pow(dy / (gap_half * 0.34 + 1.1), 2.0)) * (1.0 - smoothstep(hw * 0.9, hw * 2.1, dx));
	col *= 1.0 - 0.90 * band * cutk;

	// 熔线：极细的一条冷紫白光，只在中段
	float seam_x = 1.0 - smoothstep(res.x * 0.10, res.x * 0.27, abs(p.x - cx));
	float seam_core = exp(-pow(dy / 1.05, 2.0));
	float seam_glow = exp(-pow(dy / 4.2, 2.0));
	float grainline = mix(1.0, 0.45 + 0.55 * hash11(floor(p.x / 3.0) + 7.0), smoothstep(res.x * 0.11, res.x * 0.26, abs(p.x - cx)));
	col += mix(C_VHOT, vec3(1.0, 0.99, 0.97), 0.45 + 0.28 * sin(t * 1.9 + breathe * 3.0)) * seam_core * seam_x * cutk * 1.25 * grainline;
	col += C_VHOT * seam_glow * seam_x * cutk * 0.085;
	// 斩点：刀痕和光柱交汇的地方，一直在发一点光
	float hub = exp(-pow(length(vec2((p.x - cx) / 30.0, (p.y - cut_y) / 3.0)), 2.0));
	col += mix(C_VHOT, vec3(1.0), 0.62) * hub * cutk * (0.22 + 0.10 * sin(t * 2.3 + breathe * 2.0));
	float hub_ray = exp(-abs(p.y - cut_y) / 1.0) * exp(-abs(p.x - cx) / 210.0);
	col += C_VHOT * hub_ray * cutk * 0.085;

	// ---------------------------------------------------------------- 刀光
	if (slash_alpha > 0.001) {
		float tail = 1.0 - smoothstep(0.0, 430.0, p.x - slash_x);
		float blade = exp(-pow(abs(p.y - cut_y) / 1.55, 2.0)) * tail;
		float hot = exp(-pow(abs(p.y - cut_y) / 4.5, 2.0)) * (1.0 - smoothstep(0.0, 130.0, p.x - slash_x));
		vec2 hd = (p - vec2(slash_x, cut_y)) / vec2(34.0, 2.8);
		float head = exp(-pow(length(hd), 2.0));
		float star = exp(-abs(p.y - cut_y) / 0.8) * exp(-abs(p.x - slash_x) / 210.0);
		col += mix(C_VHOT, vec3(1.0), 0.62) * (blade * 1.55 + hot * 0.55 + head * 1.05 + star * 0.45) * slash_alpha;
	}

	// ---------------------------------------------------------------- 冲击波
	if (shock_amt > 0.001) {
		vec2 sd = (p - vec2(cx, cut_y)) / vec2(res.x * 0.60, 13.0);
		float ring = exp(-pow((length(sd) - shock) / 0.065, 2.0));
		float fade_k = 1.0 - smoothstep(0.4, 1.30, shock);
		col += C_VHOT * ring * 0.45 * shock_amt * fade_k;
		col += vec3(1.0) * ring * ring * 0.22 * shock_amt * fade_k;
	}

	// ---------------------------------------------------------------- 闪白 / 墨涌 / 颗粒
	col += vec3(1.0, 0.975, 0.940) * flash * 0.80;
	col = mix(col, vec3(0.0028, 0.0028, 0.0060), clamp(ink, 0.0, 1.0));
	float g = hash21(p * 0.85 + vec2(fract(t) * 97.0, fract(t * 0.7) * 61.0));
	col += (g - 0.5) * 0.016;
	col *= fade;
	COLOR = vec4(max(col, vec3(0.0)), 1.0);
}
