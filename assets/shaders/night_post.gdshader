shader_type canvas_item;
render_mode unshaded;
// 光影后期（光影第一版）：画在整个夜景 + 地形 + 角色之上、界面之下（CanvasLayer 5），读屏幕纹理。
//   1) 辉光：屏幕纹理的多级缩小图（mipmap）里取亮的部分叠回来——月亮、灯笼、窗户、刀光会“发光”；
//   2) 月光光柱：从月亮往左下散开的几道淡光，慢慢摆动；
//   3) 调色：压暗、加对比，暗部偏深蓝、亮部偏暖，统一整个画面的颜色；
//   4) 角色光：主角周围微微提亮（画面焦点）；
//   5) 暗角：四角和屏幕底部的水面压暗，视线集中到中间。
// Compatibility 渲染器不支持 2D 的 WorldEnvironment 辉光，所以自己做（实测 mipmap 可用）。
uniform sampler2D scr : hint_screen_texture, filter_linear_mipmap;
uniform vec2 design = vec2(1280.0, 720.0);
uniform vec2 moon = vec2(1064.0, 160.0);      // 月亮在屏幕上的位置（设计分辨率像素）
uniform vec2 hero = vec2(640.0, 520.0);       // 主角胸口在屏幕上的位置
uniform float t = 0.0;
uniform bool enabled = true;
// 辉光
uniform float bloom_amt = 0.95;
uniform float bloom_th = 0.42;
uniform vec3 bloom_tint = vec3(1.0, 0.97, 0.92);
// 光柱
uniform float rays_amt = 0.22;
uniform vec3 rays_col = vec3(0.70, 0.82, 1.0);
// 调色
uniform float exposure = 0.90;
uniform float contrast = 1.18;
uniform float pivot = 0.30;
uniform float sat = 1.08;
uniform vec3 shadow_tint = vec3(0.88, 0.96, 1.08);
uniform vec3 high_tint = vec3(1.06, 1.0, 0.92);
// 角色光
uniform float hero_amt = 0.16;
uniform float hero_r = 230.0;
uniform vec3 hero_col = vec3(0.92, 0.9, 1.0);
// 暗角
uniform float vig_amt = 0.46;
uniform float vig_bottom = 0.34;
uniform float vig_top = 0.18;          // 天顶压暗

float luma(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

vec3 bright(vec3 c, float th) {
	float l = luma(c);
	return c * smoothstep(th, th + 0.28, l);
}

// 4 点取样的某一级缩小图（让辉光更圆，不出方块）
vec3 lod4(vec2 uv, float lod) {
	vec2 o = exp2(lod) * 0.5 / design;
	return 0.25 * (textureLod(scr, uv + vec2(o.x, o.y), lod).rgb + textureLod(scr, uv + vec2(-o.x, o.y), lod).rgb
		+ textureLod(scr, uv + vec2(o.x, -o.y), lod).rgb + textureLod(scr, uv + vec2(-o.x, -o.y), lod).rgb);
}

float rays(vec2 p) {
	vec2 d = p - moon;
	float dist = length(d) / design.y;
	float ang = atan(d.y, d.x);
	// 宽窄两层条纹叠起来，慢慢摆
	float s = 0.5 + 0.5 * sin(ang * 11.0 + 1.3 * sin(ang * 3.0 + t * 0.07) + t * 0.03);
	float s2 = 0.5 + 0.5 * sin(ang * 27.0 - t * 0.05 + 1.0);
	s = smoothstep(0.3, 1.0, s) * (0.55 + 0.45 * s2);
	float down = smoothstep(0.0, 0.55, d.y / max(length(d), 1.0));           // 只往下方散
	float fall = smoothstep(0.10, 0.20, dist) * exp(-dist * 0.9);             // 月亮本体不画，越远越淡
	return s * down * fall;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 c = textureLod(scr, uv, 0.0).rgb;
	if (!enabled) {
		COLOR = vec4(c, 1.0);
	} else {
		vec2 p = uv * design;
		// 辉光：越大越淡，阈值逐级降低（小亮点在大级别里被平均掉，所以要放低门槛）
		vec3 b = bright(lod4(uv, 1.0), bloom_th) * 0.32
			+ bright(lod4(uv, 2.0), bloom_th - 0.04) * 0.32
			+ bright(lod4(uv, 3.0), bloom_th - 0.09) * 0.27
			+ bright(lod4(uv, 4.0), bloom_th - 0.14) * 0.22
			+ bright(lod4(uv, 5.0), bloom_th - 0.18) * 0.20
			+ bright(lod4(uv, 6.0), bloom_th - 0.21) * 0.18;
		// 调色
		c *= exposure;
		float l = luma(c);
		c = mix(vec3(l), c, sat);
		c = max(vec3(0.0), (c - pivot) * contrast + pivot);
		float hl = smoothstep(0.08, 0.7, l);
		c *= mix(shadow_tint, high_tint, hl);
		// 角色光
		vec2 hd = (p - hero) / hero_r;
		c *= 1.0 + hero_amt * hero_col * exp(-dot(hd, hd) * 1.6);
		// 辉光叠加（屏幕混合，不会一下子爆白）
		vec3 g = b * bloom_amt * bloom_tint;
		c = 1.0 - (1.0 - c) * (1.0 - g);
		// 光柱
		vec3 r = rays_col * rays_amt * rays(p);
		c = 1.0 - (1.0 - c) * (1.0 - r);
		// 暗角
		vec2 q = (uv - vec2(0.5, 0.46)) * vec2(1.0, 1.15);
		float v = smoothstep(0.32, 0.86, length(q)) * vig_amt;
		v += smoothstep(0.80, 1.0, uv.y) * vig_bottom;
		v += (1.0 - smoothstep(0.0, 0.3, uv.y)) * vig_top;
		c *= 1.0 - clamp(v, 0.0, 0.8);
		COLOR = vec4(c, 1.0);
	}
}
