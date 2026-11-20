shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

// 三维空间高能真剑气弧光带（用于首页穿钟劈裂 & 确认出战破界冲刺，绝非粗糙条纹遮罩！）

uniform vec4 accent_col : source_color = vec4(0.616, 0.451, 1.0, 1.0);
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float opacity : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	if (opacity <= 0.005 || progress <= 0.001 || progress >= 0.999) {
		discard;
	}
	// UV.x 沿剑锋前进方向 0..1，UV.y 沿剑弧宽度 0..1
	float head = progress * 1.45;
	float tail = max(0.0, head - 0.72);
	float along = smoothstep(tail, tail + 0.18, UV.x) * (1.0 - smoothstep(head - 0.08, head, UV.x));

	// 锐利剑刃厚度（前尖后宽，极锐核心 + 柔和主色光羽）
	float dist_edge = abs(UV.y - 0.5) * 2.0;
	float taper = mix(0.25, 1.0, clamp((UV.x - tail) / max(0.01, head - tail), 0.0, 1.0));
	float core = exp(-pow(dist_edge / (0.14 * taper), 2.0));
	float halo = exp(-pow(dist_edge / (0.55 * taper), 2.0)) * 0.65;

	float fade = sin(clamp(progress, 0.0, 1.0) * 3.14159);
	float intensity = (core * 1.5 + halo) * along * fade * opacity;
	vec3 col = mix(accent_col.rgb, vec3(1.0, 0.99, 1.0), clamp(core * 0.85, 0.0, 1.0));

	ALBEDO = col * intensity;
	ALPHA = clamp(intensity, 0.0, 1.0);
}
