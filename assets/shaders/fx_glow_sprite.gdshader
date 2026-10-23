shader_type canvas_item;
render_mode unshaded, blend_add;
// 角色帧里刀光的辉光（第四轮 · 顶级特效，见 docs/HANDOFF-试玩版.md §16.10 / §16.11）：
// 一张跟着主角精灵走的“影子精灵”（贴图、帧、翻转都同步，四周多留 pad 给光晕），
// 只取亮紫的刀光像素（头发的紫蓝偏暗、绿很低，不算；白衣服不算），模糊一圈后相加混合叠上去。
// 剑身的紫色高光也会微微发光。strength 由脚本控制：平时淡淡一层，打中时亮一下再退。
// 大招起手：blade = 这一帧刀柄 → 刀尖（贴图像素），sweep 0→1 从刀柄往刀尖一路点亮（钢色刀尖也亮），
// 亮的前沿有一道更白的“走光”。boost = 刀身额外亮度。
uniform float radius = 28.0;                     // 模糊半径（贴图像素，脚本按约 7 个屏幕像素换算）
uniform float strength = 0.6;
uniform vec3 tint = vec3(0.78, 0.64, 1.0);       // 光晕偏紫
uniform vec4 bounds = vec4(0.0, 0.0, 1.0, 1.0);  // 这一帧在贴图里的 UV 范围（外面当透明）
uniform vec4 blade = vec4(0.0);                  // 刀柄 xy → 刀尖 zw（贴图像素）
uniform float blade_w = 9.0;                     // 刀身半宽（贴图像素）
uniform float sweep = 0.0;
uniform float boost = 0.0;

// x = 已点亮的刀身，y = 走光前沿
vec2 blade_mask(vec2 uv, vec2 tsize) {
	if (boost <= 0.0) {
		return vec2(0.0);
	}
	vec2 p = uv * tsize;
	vec2 ab = blade.zw - blade.xy;
	float len = max(length(ab), 1.0);
	vec2 u = ab / len;
	float s = dot(p - blade.xy, u);
	float d = abs(dot(p - blade.xy, vec2(-u.y, u.x)));
	float inside = (1.0 - smoothstep(blade_w * 0.6, blade_w, d)) * smoothstep(-10.0, 0.0, s) * (1.0 - smoothstep(len, len + 12.0, s));
	float front = sweep * (len + 12.0);
	float lit = 1.0 - smoothstep(front - 8.0, front + 4.0, s);
	float head = exp(-pow((s - front) / 14.0, 2.0)) * step(sweep, 0.999);
	return vec2(lit, head) * inside;
}

vec3 fx(sampler2D tex, vec2 uv, vec2 tsize) {
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
	float w = vio * smoothstep(0.3, 0.6, lum) * strength;
	vec2 bm = blade_mask(uv, tsize);
	w += (bm.x + bm.y * 1.5) * boost * smoothstep(0.2, 0.45, lum);
	return c * (w * t.a);
}

void fragment() {
	vec2 tsize = 1.0 / TEXTURE_PIXEL_SIZE;
	vec2 px = TEXTURE_PIXEL_SIZE * radius;
	vec3 acc = fx(TEXTURE, UV, tsize) * 0.2;
	float wsum = 0.2;
	for (int i = 0; i < 8; i++) {
		float a = float(i) * 0.7854 + 0.2;
		acc += fx(TEXTURE, UV + vec2(cos(a), sin(a)) * px * 0.3, tsize) * 0.12;
		wsum += 0.12;
	}
	for (int i = 0; i < 12; i++) {
		float a = float(i) * 0.5236;
		acc += fx(TEXTURE, UV + vec2(cos(a), sin(a)) * px * 0.64, tsize) * 0.07;
		wsum += 0.07;
	}
	for (int i = 0; i < 16; i++) {
		float a = float(i) * 0.3927 + 0.1;
		acc += fx(TEXTURE, UV + vec2(cos(a), sin(a)) * px, tsize) * 0.035;
		wsum += 0.035;
	}
	vec3 g = acc / wsum * tint * 2.0;
	// 刀身本身也变亮（不只是外面的光晕）：点亮的部分偏白紫，走光前沿更白
	if (boost > 0.0) {
		vec4 t = texture(TEXTURE, UV);
		vec2 bm = blade_mask(UV, tsize);
		float on = step(bounds.x, UV.x) * step(UV.x, bounds.z) * step(bounds.y, UV.y) * step(UV.y, bounds.w);
		g += vec3(0.75, 0.68, 1.0) * t.a * on * (bm.x * 0.22 + bm.y * 0.9) * boost;
	}
	COLOR = vec4(g, 1.0);
}
