shader_type canvas_item;
// 画面重构样板：码头墙下的河面倒影（站立层倒过来，水波晃、越往下越淡）
uniform float edge = 0.85;        // 街面那一行在整张图里的 UV.y（倒影从这里开始）
uniform float reach = 0.42;       // 倒影往下能看到多深（UV 单位）
uniform float strength = 0.75;
uniform vec3 tint : source_color = vec3(0.7, 0.76, 0.9);

void fragment() {
	float dist = edge - UV.y;                       // 0 = 水线
	vec2 uv = UV;
	uv.x += sin(UV.y * 260.0 + TIME * 2.2) * 0.0016 + sin(UV.y * 71.0 - TIME * 1.4) * 0.0022;
	vec4 c = texture(TEXTURE, uv);
	float band = 0.82 + 0.18 * sin(UV.y * 900.0 + TIME * 3.0);   // 细碎的水纹明暗
	float a = strength * (1.0 - smoothstep(0.0, reach, dist)) * band;
	COLOR = vec4(c.rgb * tint, c.a * a);
}
