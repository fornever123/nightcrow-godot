shader_type canvas_item;
// 大招「绝影」冷峻版切入：立绘只在“刀缝”里显示（缝 = 一条斜带，屏幕像素），压暗、提对比、略去饱和；
// 立绘图片自身的硬边（左边刀尖、下边、右边）径向淡出。必须放在没有变换的 CanvasLayer 里（画布坐标 = 屏幕像素）。
uniform vec2 slit_c = vec2(640.0, 330.0);   // 缝中线上一点
uniform vec2 slit_n = vec2(0.0, 1.0);       // 缝的法线（单位）
uniform float slit_hh = 0.0;                // 缝张开的半高
uniform float bright = 1.0;
uniform float sat = 0.7;
uniform float contrast = 1.18;
uniform vec2 fade_c = vec2(0.62, 0.38);
uniform float fade_r = 0.78;

varying vec2 spos;

void vertex() {
	spos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec4 c = COLOR;
	float d = abs(dot(spos - slit_c, slit_n));
	float inside = 1.0 - smoothstep(slit_hh - 1.0, slit_hh + 1.0, d);
	float e = 1.0 - smoothstep(fade_r * 0.92, fade_r * 1.28, length(UV - fade_c));
	float l = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	vec3 g = mix(vec3(l), c.rgb, sat);
	g = (g - 0.5) * contrast + 0.5;
	g *= bright;
	COLOR = vec4(clamp(g, 0.0, 1.0), c.a * inside * e);
}
