shader_type canvas_item;
// 分层背景（street_layered.gd）的流动雾：贴屏幕的一块，按镜头 x 视差平移，IGN 抖动无色带。
uniform sampler2D n : repeat_enable, filter_linear;
uniform vec4 col : source_color;
uniform float k = 1.0;
uniform float spd = 0.01;
uniform float y0 = 0.3;
uniform float y1 = 0.9;
uniform float strength = 0.5;
uniform float cam_x = 0.0;
uniform float t = 0.0;
uniform sampler2D screen : hint_screen_texture;
void fragment() {
	vec2 p = SCREEN_UV * vec2(1.78, 1.0) * 1.1 + vec2(cam_x * k / 1280.0, 0.0);
	float a = texture(n, p + vec2(t * spd, t * spd * 0.2)).r * texture(n, p * 1.9 - vec2(t * spd * 1.4, 0.0)).r * 2.2;
	float mask = smoothstep(y0, y1, SCREEN_UV.y);
	float ign = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
	COLOR = vec4(col.rgb + (ign - 0.5) / 96.0, clamp(a * mask * strength + (ign - 0.5) / 64.0, 0.0, 1.0));
}
