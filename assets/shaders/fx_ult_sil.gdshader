shader_type canvas_item;
render_mode unshaded;
// 大招切入带里的主角特写（第四轮 §16.12）：硬边（不要半透明毛边）。
// paint = 0 → 纯剪影（填 ink）；paint = 1 → 原画颜色压成几档（赛璐璐感），暗部压向 ink。
uniform vec4 ink : source_color = vec4(0.05, 0.035, 0.09, 1.0);
uniform float fade = 1.0;
uniform float paint = 1.0;
uniform float levels = 4.0;

void fragment() {
	vec4 t = texture(TEXTURE, UV);
	float a = step(0.62, t.a) * fade;
	vec3 c = t.rgb;
	// 对比拉大一点，再分档
	c = clamp((c - 0.5) * 1.25 + 0.52, 0.0, 1.0);
	c = floor(c * levels + 0.5) / levels;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(ink.rgb, c, smoothstep(0.08, 0.3, l));
	COLOR = vec4(mix(ink.rgb, c, paint), a);
}
