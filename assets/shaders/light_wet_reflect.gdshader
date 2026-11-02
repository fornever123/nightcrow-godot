shader_type canvas_item;
render_mode blend_premul_alpha;
// 湿街面上的角色倒影（光线线 2026-10-30，rain_lights.gd）：角色精灵沿街面上下翻转，
// 只在街面那一条湿带里显示（越往下越淡），压暗偏冷，横向随雨点轻轻抖。贴图是预乘透明度的（ArtCache）。

uniform float street_y = 580.0;   // 街面（世界 y）= 镜面
uniform float band = 24.0;        // 湿带厚度（世界单位）
uniform float strength = 0.35;
uniform vec3 tint : source_color = vec3(0.62, 0.68, 0.82);
uniform float wobble = 0.004;     // 横向抖动（UV）

varying vec2 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	float depth = world.y - street_y;
	float f = clamp(1.0 - depth / band, 0.0, 1.0);
	float k = f * f * step(0.0, depth) * strength;
	vec2 uv = UV + vec2(sin(world.y * 0.9 + TIME * 7.0) * wobble, 0.0);
	vec4 t = texture(TEXTURE, uv);
	COLOR = vec4(t.rgb * tint, t.a) * k;
}
