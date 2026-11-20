shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

// 《司辰四象 · 三维裂时殿堂》立体背光星盘与体积圣光着色器：
// 置于每位女主 3D 背后 z = -420 处，随女主主色实时呼吸流转（非朔角色严格 0% 紫！）

uniform vec4 accent_col : source_color = vec4(0.616, 0.451, 1.0, 1.0);
uniform float opacity : hint_range(0.0, 1.0) = 1.0;
uniform float time_sec = 0.0;
uniform float burst_k = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0 || opacity <= 0.004) {
		discard;
	}
	float ang = atan(p.y, p.x);

	// 柔和大背光核 + 旋转哥特辐射光束
	float core = exp(-r * r * 4.2) * (0.62 + 0.45 * burst_k);
	float rays = pow(0.5 + 0.5 * sin(ang * 12.0 - time_sec * 0.45), 4.0) * exp(-r * 2.4) * 0.42;
	float fine_rays = pow(0.5 + 0.5 * sin(ang * 24.0 + time_sec * 0.25), 6.0) * exp(-r * 3.0) * 0.24;

	// 精密司辰星盘双同心刻度细环
	float ring1 = smoothstep(0.012, 0.002, abs(r - 0.62));
	float ring2 = smoothstep(0.008, 0.001, abs(r - 0.78));
	float ticks = step(0.86, sin(ang * 36.0 + time_sec * 0.18)) * smoothstep(0.032, 0.006, abs(r - 0.70));

	float energy = (core + rays + fine_rays) + (ring1 * 0.55 + ring2 * 0.35 + ticks * 0.45) * (1.0 - smoothstep(0.82, 1.0, r));
	float edge_fade = 1.0 - smoothstep(0.75, 1.0, r);
	vec3 col = mix(accent_col.rgb, vec3(0.98, 0.98, 1.0), clamp(core * 0.55 + ring1 * 0.6 + burst_k * 0.35, 0.0, 1.0));

	ALBEDO = col * energy * opacity * edge_fade;
	ALPHA = clamp(energy * opacity * edge_fade, 0.0, 1.0);
}
