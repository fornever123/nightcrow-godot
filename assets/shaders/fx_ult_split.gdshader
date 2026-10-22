shader_type canvas_item;
render_mode unshaded, blend_disabled;
// 大招「月下斩」：画面沿斩线错开（第四轮 §16.11）。
// 斩线是一段大圆弧（圆心 center、半径 radius，世界坐标）：圆外的一半顺着弧往前滑 amount 个屏幕像素，
// 圆内的一半往后滑，过一会儿 amount 回到 0 就合上了。斩线本身留一道细亮缝。
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform vec2 center = vec2(0.0);
uniform float radius = 1000.0;
uniform float amount = 0.0;          // 屏幕像素
uniform float dir = 1.0;             // 往哪边滑（跟着斩的方向）
uniform float seam = 0.0;            // 亮缝宽（世界单位）
uniform vec4 seam_col : source_color = vec4(0.87, 0.82, 1.0, 1.0);
varying vec2 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec2 d = world - center;
	float r = length(d);
	vec2 n = d / max(r, 0.001);
	vec2 tg = vec2(-n.y, n.x) * dir;
	float side = r > radius ? 1.0 : -1.0;
	vec3 c = texture(screen_tex, SCREEN_UV + tg * side * amount * 0.5 * SCREEN_PIXEL_SIZE).rgb;
	float s = seam > 0.0 ? 1.0 - smoothstep(seam * 0.5, seam, abs(r - radius)) : 0.0;
	COLOR = vec4(mix(c, seam_col.rgb, s * seam_col.a), 1.0);
}
