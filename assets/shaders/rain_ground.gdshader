shader_type canvas_item;
render_mode blend_add;
// 雨夜河岸街湿街面上的雨点涟漪（street_backdrop.gd 的 _ground，画在背景之后、角色之前，加色混合）：
// 世界坐标里铺一张错位的格子，每格一个随机时刻落下的雨点，冒出一圈压扁的椭圆涟漪往外扩、变淡。两层格子错开，看不出规律。

uniform float street_y = 580.0;     // 街面（世界 y）
uniform float band = 26.0;          // 湿街面那一条的厚度（世界单位）
uniform vec4 tint : source_color = vec4(0.62, 0.72, 0.88, 1.0);
uniform float strength = 1.1;

varying vec2 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// cell：格子大小（世界单位）；squash：椭圆竖向压扁；rate：每秒落几次；r_max：涟漪最大半径
float ripples(vec2 p, vec2 cell, float squash, float rate, float r_max, float seed) {
	vec2 id = floor(p / cell);
	vec2 f = fract(p / cell) - 0.5;
	float h = hash(id + seed);
	float h2 = hash(id + seed + 17.3);
	vec2 off = (vec2(h, h2) - 0.5) * 0.7;
	float ph = fract(TIME * rate * (0.7 + 0.6 * h2) + h * 11.0);
	vec2 d = (f - off) * cell;
	d.y /= squash;
	float r = ph * r_max;
	float ring = smoothstep(2.6, 0.0, abs(length(d) - r)) * (1.0 - ph) * (1.0 - ph);
	float dot_ = smoothstep(2.5, 0.0, length(d)) * smoothstep(0.12, 0.0, ph);   // 落点那一下的亮点
	return ring + dot_ * 1.5;
}

void fragment() {
	float depth = world.y - street_y;
	float in_band = smoothstep(0.0, 3.0, depth) * smoothstep(band, band - 6.0, depth);
	float a = ripples(world, vec2(70.0, 14.0), 0.25, 0.6, 30.0, 0.0)          // 落点频率 11-01 随雨量调小（1.1 / 0.8 → 0.6 / 0.45）
		+ ripples(world + vec2(35.0, 7.0), vec2(90.0, 18.0), 0.25, 0.45, 38.0, 5.1) * 0.8;
	COLOR = vec4(tint.rgb * a * strength * in_band, 1.0);
}
