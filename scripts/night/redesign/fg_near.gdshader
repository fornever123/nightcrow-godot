shader_type canvas_item;
// 背景线 11-18 立体感试验 · 路线 A：镜头最前面的遮挡件。离焦（预乘高斯糊）、不吃 2D 灯，颜色只看 modulate。
render_mode unshaded;

uniform float blur = 1.6;   // 糊的半径（贴图像素）

varying vec4 v_mod;

void vertex() {
	v_mod = COLOR;
}

void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE * blur;
	vec3 rgb = vec3(0.0);
	float a = 0.0;
	float ws = 0.0;
	for (int i = -2; i <= 2; i++) {
		for (int j = -2; j <= 2; j++) {
			float w = exp(-float(i * i + j * j) / 4.0);
			vec4 t = texture(TEXTURE, UV + vec2(float(i), float(j)) * px);
			rgb += t.rgb * t.a * w;    // 预乘：透明处的底色不渗进来
			a += t.a * w;
			ws += w;
		}
	}
	COLOR = vec4(rgb / max(a, 1e-4), a / ws) * v_mod;
}
