shader_type canvas_item;
// 背景线 11-18 立体感试验：站立层成图 + 深度图。底色先压暗（灯光再按法线把起伏照出来），越靠后越暗、越进雾；
// 法线来自 CanvasTexture 的 normal_texture，由引擎 2D 灯按 N·L 计算。
uniform sampler2D depth_tex : filter_linear;
uniform vec4 fog : source_color = vec4(0.17, 0.21, 0.29, 1.0);
uniform float base = 0.86;      // 没被动态灯照到时的亮度（后期调色会再压暗部，别压太狠）
uniform float haze = 0.3;       // 最远处混进雾色的比例
uniform float recess = 0.35;    // 凹处 / 后退的楼额外压暗

void fragment() {
	vec4 c = COLOR;                                // Godot 4：COLOR 已经乘过贴图，不要再乘一次
	float d = texture(depth_tex, UV).r;           // 1 = 近
	float far = clamp(1.0 - d, 0.0, 1.0);
	c.rgb *= base * (1.0 - recess * far * far);
	c.rgb = mix(c.rgb, fog.rgb * base, far * haze);
	COLOR = c;
}
