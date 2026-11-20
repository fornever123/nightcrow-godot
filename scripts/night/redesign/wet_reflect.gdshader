shader_type canvas_item;
// 影街 · 灯在湿石板上拉出的竖向暖光（11-19 到 8 分）：参照游戏雨夜街面“灯下一道碎光”。
// 红线：只做薄湿反光，不做镜面水洼——光被石缝横向打碎、上实下虚、随雨轻轻颤，不映出灯形。
render_mode blend_add, unshaded;

uniform float strength = 0.5;
uniform vec4 col : source_color = vec4(1.0, 0.82, 0.55, 1.0);

varying vec2 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

float hash(float n) { return fract(sin(n) * 43758.5453); }

void fragment() {
	// UV.x 0..1 横跨光带，UV.y 0 = 街沿（灯脚下），1 = 往近处拉到最远
	float cx = abs(UV.x - 0.5) * 2.0;
	float core = exp(-cx * cx * 6.0);                              // 横向：中间实、两边虚
	float fall = pow(1.0 - UV.y, 1.6) * smoothstep(0.0, 0.1, UV.y);
	// 石缝把光横向打碎：一条条不等宽的亮段，随时间缓慢颤动
	float row = floor(world.y / 5.0);
	float jit = hash(row * 1.7 + floor(TIME * 6.0 + hash(row) * 3.0));
	float wob = sin(world.y * 0.55 + TIME * 3.0 + hash(row) * 6.28) * 0.5 + 0.5;
	float seg = smoothstep(0.25, 0.7, 0.55 * jit + 0.45 * wob);
	float shift = (hash(row + 13.0) - 0.5) * 0.25 * UV.y;          // 越远越散
	float core2 = exp(-pow(abs(UV.x - 0.5 - shift) * 2.0, 2.0) * 6.0);
	float a = mix(core, core2, 0.6) * fall * mix(0.35, 1.0, seg) * strength;
	COLOR = vec4(col.rgb * a, a);
}
