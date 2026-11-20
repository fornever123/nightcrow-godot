shader_type canvas_item;
render_mode blend_add;
// 灯旁被照亮的雨丝（d2_ambient_fx.gd 每盏灯画一块方片）：按世界坐标画往左斜落的细雨丝（和全场雨同斜度：每往下 1 往左 0.1），
// 只在方片中心（灯）周围一圈可见，越靠灯越亮。颜色和闪烁由绘制颜色给。不是光柱，也不是定格的雨。
uniform float tilt = 0.1;
uniform float spacing = 7.0;      // 雨丝横向间距（世界单位）
uniform float seg = 120.0;        // 一段雨丝的循环长度
uniform float strength = 0.85;

varying vec2 world;
varying vec4 vc;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	vc = COLOR;
}

float hash(float n) { return fract(sin(n * 91.3458) * 47453.5453); }

void fragment() {
	vec2 c = (UV - vec2(0.5, 0.42)) * vec2(1.0, 0.95);
	float fall = clamp(1.0 - length(c) * 2.0, 0.0, 1.0);
	fall *= fall;
	float px = world.x + world.y * tilt;
	float col = floor(px / spacing);
	float h = hash(col);
	float on = step(0.45, h);
	float fx = fract(px / spacing);
	float line = 1.0 - smoothstep(0.06, 0.16, abs(fx - 0.5));
	float ph = fract(world.y / seg - TIME * (5.5 + 3.0 * hash(col + 7.1)) + h * 13.0);
	float drop = smoothstep(0.0, 0.08, ph) * (1.0 - smoothstep(0.18, 0.34, ph));
	float a = line * drop * on * fall * strength * vc.a;
	COLOR = vec4(vc.rgb * a, a);
}
