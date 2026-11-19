shader_type canvas_item;
// 分层背景（street_layered.gd）的远处雨幕：屏幕上一列列细雨线，比近处的雨慢、淡，随镜头按视差平移。
uniform float cam_x = 0.0;
uniform float t = 0.0;
uniform float k = 0.3;
uniform float cell = 9.0;
uniform float density = 0.35;
uniform float speed = 500.0;
uniform float seg = 60.0;
uniform float period = 420.0;
uniform float alpha = 0.12;
uniform float y0 = 0.0;
uniform float y1 = 1.0;
uniform vec4 col : source_color = vec4(0.6, 0.68, 0.85, 1.0);
uniform float tilt = 0.1;
uniform float flash = 0.0;
float h(float n) { return fract(sin(n * 127.1) * 43758.5453); }
void fragment() {
	vec2 p = SCREEN_UV * vec2(1280.0, 720.0);
	p.x += cam_x * k * 0.65 + p.y * tilt;
	float ci = floor(p.x / cell);
	float hh = h(ci);
	float on = step(1.0 - density, hh);
	float fx = abs(fract(p.x / cell) - 0.5) * cell;
	float line = 1.0 - smoothstep(0.25, 0.85, fx);
	float y = p.y - t * speed * (0.75 + 0.5 * h(ci + 7.0)) + hh * period;
	float s = fract(y / period) * period;
	float st = smoothstep(0.0, seg * 0.25, s) * (1.0 - smoothstep(seg * 0.25, seg, s));
	float m = smoothstep(y0, y0 + 0.1, SCREEN_UV.y) * (1.0 - smoothstep(y1 - 0.1, y1, SCREEN_UV.y));
	COLOR = vec4(col.rgb + vec3(0.4) * flash, (alpha + flash * 0.25) * on * line * st * m);
}
