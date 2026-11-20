shader_type spatial;
// 《拨钟选章》哥特铸铁画框：保留 AI 画框贴图的手绘明暗（卡通平涂，不走 PBR 发灰），
// 压成冷铁色；法线图只用来做一道掠光——换章落定时光从左扫到右，朝光的花格棱面依次亮起
render_mode unshaded, cull_back, depth_draw_always;

uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform sampler2D ntex : filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(1.0);
uniform float dim = 0.0;
uniform float glow = 0.0;      // 选中 / 悬停时的底光
uniform float sweep = -1.0;    // 掠光进度 0→1；<0 关闭
uniform float frost = 0.0;     // 未开放：偏冷

void fragment() {
	vec4 c = texture(tex, UV);
	if (c.a < 0.02) discard;
	// 暗部压深、亮部保留 → 铸铁的分量
	vec3 col = pow(c.rgb, vec3(1.35)) * 1.02;
	col *= tint.rgb;
	col = mix(col, vec3(dot(col, vec3(0.3, 0.59, 0.11))) * vec3(0.9, 0.96, 1.06), frost * 0.5);
	vec3 n = texture(ntex, UV).rgb * 2.0 - 1.0;
	float luma = dot(c.rgb, vec3(0.3, 0.59, 0.11));
	// 底光：朝左上的棱面微亮
	float key = max(dot(n, normalize(vec3(-0.5, 0.6, 0.65))), 0.0);
	col += vec3(0.9, 0.93, 1.0) * pow(key, 6.0) * 0.12 * smoothstep(0.35, 0.8, luma) * (0.5 + glow);
	if (sweep >= 0.0) {
		// 一团光沿画框从左扫到右，只点亮朝光源（右上前方）的花格棱面
		float x = (UV.x - mix(-0.15, 1.15, sweep)) * 5.0;
		float band = exp(-x * x);
		float sp = pow(max(dot(n, normalize(vec3(0.45, 0.35, 0.82))), 0.0), 8.0);
		col += vec3(1.0, 0.97, 0.9) * sp * band * 0.8 * sin(3.14159 * sweep) * smoothstep(0.3, 0.75, luma);
	}
	col *= 1.0 - dim * 0.82;
	ALBEDO = col;
	ALPHA = c.a;
}
