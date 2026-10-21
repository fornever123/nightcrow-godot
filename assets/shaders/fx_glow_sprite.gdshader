shader_type canvas_item;
render_mode unshaded, blend_add;
// 角色帧里刀光的辉光（第四轮 · 顶级特效，见 docs/HANDOFF-试玩版.md §16.10）：
// 一张跟着主角精灵走的“影子精灵”（贴图、帧、翻转都同步，四周多留 pad 给光晕），
// 只取亮紫的刀光像素（头发的紫蓝偏暗、绿很低，不算；白衣服不算），模糊一圈后相加混合叠上去。
// 剑身的紫色高光也会微微发光。strength 由脚本控制：平时淡淡一层，打中时亮一下再退。
uniform float radius = 28.0;                     // 模糊半径（贴图像素，脚本按约 7 个屏幕像素换算）
uniform float strength = 0.6;
uniform vec3 tint = vec3(0.78, 0.64, 1.0);       // 光晕偏紫
uniform vec4 bounds = vec4(0.0, 0.0, 1.0, 1.0);  // 这一帧在贴图里的 UV 范围（外面当透明）

vec3 fx(sampler2D tex, vec2 uv) {
	if (uv.x < bounds.x || uv.y < bounds.y || uv.x > bounds.z || uv.y > bounds.w) {
		return vec3(0.0);
	}
	vec4 t = texture(tex, uv);
	if (t.a < 0.03) {
		return vec3(0.0);
	}
	vec3 c = t.rgb / t.a;            // 贴图是预乘透明度的，先还原
	float lum = dot(c, vec3(0.3, 0.59, 0.11));
	float vio = step(0.6, c.b) * step(0.27, c.g) * step(c.g + 0.15, c.b) * step(c.r + 0.05, c.b);
	return c * (vio * smoothstep(0.3, 0.6, lum) * t.a);
}

void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE * radius;
	vec3 acc = fx(TEXTURE, UV) * 0.2;
	float wsum = 0.2;
	for (int i = 0; i < 8; i++) {
		float a = float(i) * 0.7854 + 0.2;
		acc += fx(TEXTURE, UV + vec2(cos(a), sin(a)) * px * 0.3) * 0.12;
		wsum += 0.12;
	}
	for (int i = 0; i < 12; i++) {
		float a = float(i) * 0.5236;
		acc += fx(TEXTURE, UV + vec2(cos(a), sin(a)) * px * 0.64) * 0.07;
		wsum += 0.07;
	}
	for (int i = 0; i < 16; i++) {
		float a = float(i) * 0.3927 + 0.1;
		acc += fx(TEXTURE, UV + vec2(cos(a), sin(a)) * px) * 0.035;
		wsum += 0.035;
	}
	vec3 g = acc / wsum * tint * strength * 2.0;
	COLOR = vec4(g, 1.0);
}
