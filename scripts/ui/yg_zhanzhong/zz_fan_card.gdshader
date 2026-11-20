// [YG-MARK] 角色选择「扇刃」：一张刀刃形角色卡（用户 11-19 选 B 扇刃）。
// 卡是一个四边形（多边形），UV = 卡自己的坐标（x 横、y 从剑尖 0 到钟轴 1）。
// frame：银白铁框（透明处是卡窗和镂空孔）；mask：R = 卡窗，G = 镂空孔。
// 卡窗里的内容按「屏幕坐标」取样，所以人物永远正立，不跟着刀刃一起斜：
//   mode 0（可出战）：立绘；mode 1（尚在光中）：过曝冷白光里的逆光黑剪影 + 她自己颜色的描边。
// 顶点颜色的 rg 编码这一片相对卡原位的位移（斩开时两半各自错开，内容跟着那一半走）。
shader_type canvas_item;

uniform sampler2D frame : filter_linear_mipmap;
uniform sampler2D mask : filter_linear;
uniform sampler2D art : filter_linear_mipmap;
uniform vec4 art_rect = vec4(0.0, 0.0, 100.0, 100.0);   // 屏幕像素 x, y, w, h
uniform int mode = 0;
uniform vec4 accent : source_color = vec4(0.62, 0.45, 1.0, 1.0);
uniform float dim = 0.0;
uniform float flash = 0.0;
uniform float glow = 0.5;
uniform float opacity = 1.0;
uniform float t = 0.0;
uniform float card_len = 1000.0;   // 这张卡现在的长度（像素），用来算描边宽度
uniform float glint = 0.0;         // 刀身扫光强度
uniform float glint_y = 0.0;       // 扫光在刀身上的位置（0 剑尖 → 1 钟轴）

varying vec2 spos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	spos = VERTEX - (COLOR.rg - 0.5) * 1000.0;
}

vec4 art_at(vec2 sp) {
	vec2 a = (sp - art_rect.xy) / art_rect.zw;
	if (a.x < 0.0 || a.y < 0.0 || a.x > 1.0 || a.y > 1.0) return vec4(0.0);
	return texture(art, a);
}

void fragment() {
	vec4 fr = texture(frame, UV);
	vec3 m = texture(mask, UV).rgb;
	float win = m.r;
	float holes = m.g;

	vec3 col;
	if (mode == 0) {
		vec4 a = art_at(spos);
		vec3 base = vec3(0.03, 0.028, 0.04);
		col = mix(base, a.rgb, a.a);
		// 刀刃两侧往里压暗，钟轴一端沉进黑里，剑尖一端透一点她的颜色
		float side = abs(UV.x - 0.5) * 2.0;
		col *= 1.0 - 0.45 * smoothstep(0.55, 1.0, side);
		col *= 1.0 - 0.75 * smoothstep(0.72, 0.98, UV.y);
		col += accent.rgb * 0.22 * smoothstep(0.35, 0.0, UV.y) * glow;
	} else {
		// 过曝冷白光：靠剑尖最亮，竖向光纹缓缓流，悬停的尘
		float r = length(vec2((UV.x - 0.5) * 1.4, UV.y - 0.3));
		col = mix(vec3(0.58, 0.62, 0.7), vec3(1.0, 1.0, 1.02), exp(-r * 2.6));
		col *= 0.86 + 0.18 * vnoise(vec2(spos.x / 22.0, spos.y / 240.0 - t * 0.05));
		col *= 1.0 - 0.6 * smoothstep(0.7, 1.0, UV.y);
		float mote = step(0.996, hash(floor(spos / 3.0))) * (0.6 + 0.4 * sin(t * 0.7 + hash(floor(spos / 3.0)) * 6.0));
		col += vec3(mote) * 0.45;
		float s = art_at(spos).a;
		float px = clamp(card_len / 900.0, 0.4, 2.0);
		float rim = 0.0;
		float halo = 0.0;
		for (int i = 0; i < 8; i++) {
			float ang = float(i) * 0.785398;
			vec2 d = vec2(cos(ang), sin(ang));
			rim = max(rim, art_at(spos + d * 3.0 * px).a);
			halo += art_at(spos + d * 11.0 * px).a;
		}
		halo /= 8.0;
		col = mix(col, accent.rgb * 0.9 + 0.1, clamp(halo * (1.0 - s) * 0.8, 0.0, 1.0));
		col = mix(col, mix(vec3(1.0), accent.rgb, 0.55) * 1.25, clamp((rim - s) * 1.2, 0.0, 1.0));
		col = mix(col, vec3(0.012, 0.012, 0.018), s);
	}

	// 镂空孔：她的颜色往外透（主色自乘提饱和，不发粉）
	float fl = 0.75 + 0.25 * vnoise(vec2(t * 2.0, spos.y / 40.0));
	vec3 sat = accent.rgb * accent.rgb * 1.25 + accent.rgb * 0.2;
	vec3 hole_col = vec3(0.012) + sat * glow * fl * 1.1;

	float inside = clamp(win + holes, 0.0, 1.0);
	vec3 c = col * win + hole_col * holes;
	c = c / max(inside, 0.001);
	// 铁框：一道沿刀身扫过的亮光（出鞘那一下的“锃”）
	vec3 metal = fr.rgb * (1.0 - 0.35 * dim) + vec3(1.0) * glint * exp(-abs(UV.y - glint_y) * 26.0);
	c = mix(c, metal, fr.a);
	float alpha = max(fr.a, inside);

	c *= 1.0 - dim;
	c += vec3(flash) * alpha;
	COLOR = vec4(c, alpha * opacity);
}
