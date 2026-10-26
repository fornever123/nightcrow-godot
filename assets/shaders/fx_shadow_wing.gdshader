shader_type canvas_item;
// 大招「绝影」的影翼 / 影子剪影：同一张翼贴图压成纯黑，外面描一圈紫色发光轮廓。
// rim_px 是贴图像素（脚本按屏幕上约 3 像素换算）；fade 控制整体淡出（消散时用）。
uniform vec4 core : source_color = vec4(0.03, 0.015, 0.06, 1.0);
uniform vec4 rim : source_color = vec4(0.67, 0.36, 1.0, 1.0);
uniform float rim_px = 18.0;
uniform float fade = 1.0;
varying vec4 vcol;    // 顶点色（modulate）：fragment 里的 COLOR 一开始就乘了贴图透明度，描边在贴图透明处会被乘没

void vertex() {
	vcol = COLOR;
}

void fragment() {
	vec4 tx = texture(TEXTURE, UV);
	float a = tx.a;
	float m = a;
	for (int i = 0; i < 12; i++) {
		float ang = float(i) * 0.5235988;
		vec2 o = vec2(cos(ang), sin(ang)) * rim_px * TEXTURE_PIXEL_SIZE;
		m = max(m, texture(TEXTURE, UV + o).a);
	}
	float edge = clamp(m - a, 0.0, 1.0);
	// 羽毛结构：贴图亮度的 18% 留在黑色里（不再是纯黑剪纸），再往紫偏一点
	float l = dot(tx.rgb, vec3(0.3, 0.5, 0.2));
	vec3 body = core.rgb + vec3(0.32, 0.18, 0.6) * l * 0.35;
	vec3 c = mix(rim.rgb, body, smoothstep(0.35, 0.9, a));
	COLOR = vec4(c, max(a, edge) * fade * vcol.a);
}
