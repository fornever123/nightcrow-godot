// [YG-MARK] 角色选择「钟铸铁卡」卡面内层：窗口里的内容 + 铁艺镂空孔里透出的主角色光。
// mask：R = 卡窗，G = 镂空孔，B = 整张卡的外形。铁框贴图画在它上面，孔是透明的，所以孔里看到的就是这里的颜色。
// mode 0（可出战）：窗口里是压暗的表盘机芯，底部透出主角色光；朔的立绘另外画在铁框上面（会冲出卡框）。
// mode 1（尚在光中）：窗口里是一片过曝的冷白光，剪影被逆光照成纯黑，只留一圈她自己颜色的描边。
shader_type canvas_item;

uniform sampler2D mask : filter_linear;
uniform sampler2D dial : filter_linear_mipmap;
uniform sampler2D art : filter_linear;
uniform vec4 art_rect = vec4(0.25, 0.3, 0.75, 0.8);   // 剪影在卡上的位置（卡 UV：x0, y0, x1, y1）
uniform int mode = 0;
uniform vec4 accent : source_color = vec4(0.62, 0.45, 1.0, 1.0);
uniform float glow = 0.3;      // 镂空孔里的光（选中时亮）
uniform float flash = 0.0;
uniform float t = 0.0;
uniform vec2 card_px = vec2(640.0, 960.0);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

float sil(vec2 uv) {
	vec2 a = (uv - art_rect.xy) / (art_rect.zw - art_rect.xy);
	if (a.x < 0.0 || a.y < 0.0 || a.x > 1.0 || a.y > 1.0) return 0.0;
	return texture(art, a).a;
}

vec3 dial_at(vec2 uv, float spin) {
	// 表盘贴在窗口中心，慢慢转
	vec2 c = vec2(0.5, 0.52);
	vec2 d = (uv - c) * vec2(card_px.x / card_px.y, 1.0) * 1.05;
	float s = sin(spin), co = cos(spin);
	d = vec2(co * d.x - s * d.y, s * d.x + co * d.y);
	vec2 duv = d + 0.5;
	if (duv.x < 0.0 || duv.y < 0.0 || duv.x > 1.0 || duv.y > 1.0) return vec3(0.0);
	vec4 k = texture(dial, duv);
	return k.rgb * k.a;
}

void fragment() {
	vec2 uv = UV;
	vec3 m = texture(mask, uv).rgb;
	float win = m.r;
	float holes = m.g;
	vec2 px = uv * card_px;

	vec3 col;
	if (mode == 0) {
		vec3 base = vec3(0.028, 0.026, 0.04);
		float lum = dot(dial_at(uv, t * 0.03), vec3(0.333));
		col = base + vec3(0.22, 0.22, 0.25) * lum;
		// 底部透上来的主角色光 + 中心一点冷光
		float low = smoothstep(0.45, 0.85, uv.y);
		col += accent.rgb * low * 0.32 * (0.85 + 0.15 * sin(t * 1.7));
		col += vec3(0.6, 0.62, 0.7) * exp(-length((uv - vec2(0.5, 0.45)) * vec2(2.2, 1.6)) * 3.0) * 0.12;
		float vig = smoothstep(0.75, 0.25, length((uv - vec2(0.5, 0.55)) * vec2(1.6, 1.1)));
		col *= 0.55 + 0.45 * vig;
	} else {
		// 过曝的冷白光：上方最亮，竖向光纹缓缓流，暗处隐约是表盘刻度
		float r = length((uv - vec2(0.5, 0.42)) * vec2(1.4, 1.0));
		col = mix(vec3(0.62, 0.66, 0.74), vec3(1.0, 1.0, 1.02), exp(-r * 2.4));
		float streak = vnoise(vec2(px.x / 26.0, px.y / 260.0 - t * 0.04));
		col *= 0.88 + 0.16 * streak;
		col -= dial_at(uv, -t * 0.015) * 0.18;
		// 光里悬停的尘：时间停了，几乎不动
		float mote = step(0.996, hash(floor(px / 3.0))) * (0.6 + 0.4 * sin(t * 0.7 + hash(floor(px / 3.0)) * 6.0));
		col += vec3(mote) * 0.5;
		// 剪影 + 逆光描边
		float a = sil(uv);
		float rim = 0.0;
		vec2 e = vec2(3.0) / card_px;
		for (int i = 0; i < 8; i++) {
			float ang = float(i) * 0.785398;
			rim = max(rim, sil(uv + vec2(cos(ang), sin(ang)) * e));
		}
		float halo = 0.0;
		vec2 e2 = vec2(11.0) / card_px;
		for (int i = 0; i < 8; i++) {
			float ang = float(i) * 0.785398 + 0.39;
			halo += sil(uv + vec2(cos(ang), sin(ang)) * e2);
		}
		halo /= 8.0;
		col = mix(col, accent.rgb * 0.9 + 0.1, clamp(halo * (1.0 - a) * 0.85, 0.0, 1.0));
		col = mix(col, mix(vec3(1.0), accent.rgb, 0.55) * 1.25, clamp((rim - a) * 1.2, 0.0, 1.0));
		col = mix(col, vec3(0.012, 0.012, 0.018), a);
	}
	col += vec3(flash) * win;

	// 镂空孔：主角色光（随时间轻轻呼吸）
	float fl = 0.75 + 0.25 * vnoise(vec2(t * 2.0, px.y / 40.0));
	// 孔里的光要"深"不要"粉"：主色自乘提饱和，越往孔中心越亮
	vec3 sat = accent.rgb * accent.rgb * 1.25 + accent.rgb * 0.2;
	vec3 hole_col = vec3(0.012) + sat * glow * fl * (0.7 + 0.5 * holes) + vec3(flash * 0.5);
	col = mix(col, hole_col, holes * (1.0 - win));

	COLOR = vec4(col, clamp(win + holes, 0.0, 1.0));
}
