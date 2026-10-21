shader_type canvas_item;
render_mode unshaded, blend_disabled;
// 特效辉光（第四轮 · 顶级特效，见 docs/HANDOFF-试玩版.md §16.10）：
// 渲染器是 gl_compatibility，WorldEnvironment 的 2D 辉光靠不住，所以自己做：
// 像素特效小画布（pixel_fx.gd）→ 这个着色器在 1/4 分辨率画布上取“亮的 / 亮紫的”像素做一圈模糊 →
// 再用相加混合盖回屏幕。白芯、金火花、紫斩线外面都会有一层柔光；尘土、墨点这些暗的不发光。
uniform float radius = 6.0;      // 模糊半径（特效小画布像素，1 格 = 2 屏幕像素）
uniform float gain = 2.0;        // 亮度
uniform float threshold = 0.55;  // 多亮才发光（亮度）

vec3 bright(vec4 c) {
	float lum = dot(c.rgb, vec3(0.3, 0.59, 0.11));
	float w = smoothstep(threshold, 0.95, lum);
	float vio = step(c.r + 0.06, c.b) * step(c.g + 0.12, c.b) * step(0.7, c.b);
	w = max(w, vio * 0.8);
	return c.rgb * c.a * w;
}

void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE;
	vec3 acc = bright(texture(TEXTURE, UV)) * 0.2;
	float wsum = 0.2;
	for (int i = 0; i < 8; i++) {
		float a = float(i) * 0.7854 + 0.2;
		acc += bright(texture(TEXTURE, UV + vec2(cos(a), sin(a)) * px * radius * 0.28)) * 0.12;
		wsum += 0.12;
	}
	for (int i = 0; i < 12; i++) {
		float a = float(i) * 0.5236;
		acc += bright(texture(TEXTURE, UV + vec2(cos(a), sin(a)) * px * radius * 0.62)) * 0.07;
		wsum += 0.07;
	}
	for (int i = 0; i < 16; i++) {
		float a = float(i) * 0.3927 + 0.1;
		acc += bright(texture(TEXTURE, UV + vec2(cos(a), sin(a)) * px * radius)) * 0.035;
		wsum += 0.035;
	}
	COLOR = vec4(acc / wsum * gain, 1.0);
}
