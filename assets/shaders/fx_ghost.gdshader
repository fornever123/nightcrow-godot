shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;
// 冲刺残影（第四轮 · 冲刺斩特效 v2，见 docs/HANDOFF-试玩版.md §16.9）：
//   只取“身体”的轮廓 —— 帧里烘焙的刀光 / 速度条 / 尘土（很亮、亮紫、浅灰蓝的像素）不算，
//   否则残影会变成一大团；平滑半透明（不再用抖动点，抖动在动的时候像噪点）；
//   里面淡、外圈亮一道，像一层紫色的影子。
// 颜色 / 透明度走 modulate（脚本按残影年龄从浅紫渐变到深紫并淡出）。
// rim = 亮边宽度（贴图像素，脚本按屏幕大小换算成约 1.5 个屏幕像素）。
uniform float rim = 4.0;
uniform float inner_alpha = 0.62;                  // 里面相对亮边的不透明度
uniform vec3 inner_tint = vec3(0.6, 0.5, 0.98);    // 里面的颜色 = modulate × 这个（更深更饱和的紫）
varying vec4 v_mod;

void vertex() {
	v_mod = COLOR;
}

// 这个像素是不是帧里烘焙的特效（刀光白芯 / 亮紫刀身 / 浅灰蓝尘土）：是 → 残影里不画
float is_fx(vec4 t) {
	if (t.a < 0.03) {
		return 0.0;
	}
	vec3 c = t.rgb / t.a;           // 贴图是预乘透明度的，先还原
	float mx = max(c.r, max(c.g, c.b));
	float mn = min(c.r, min(c.g, c.b));
	float lum = dot(c, vec3(0.3, 0.59, 0.11));
	float pale = step(0.55, lum) * step(mx - mn, 0.24);
	// 亮紫：蓝最高、绿也不低（头发的紫蓝绿很低，不会被算进去）
	float vio = step(0.6, c.b) * step(0.27, c.g) * step(c.g + 0.15, c.b) * step(c.r + 0.05, c.b);
	return max(pale, vio);
}

void fragment() {
	vec4 t = texture(TEXTURE, UV);
	float b0 = t.a * (1.0 - is_fx(t));
	if (b0 <= 0.0) {
		discard;
	}
	// 亮边只看外轮廓（透明度），不看颜色 —— 否则衣服上的白高光也会描出一圈，像线稿
	vec2 px = TEXTURE_PIXEL_SIZE * rim;
	float nmin = 1.0;
	nmin = min(nmin, texture(TEXTURE, UV + vec2(px.x, 0.0)).a);
	nmin = min(nmin, texture(TEXTURE, UV - vec2(px.x, 0.0)).a);
	nmin = min(nmin, texture(TEXTURE, UV + vec2(0.0, px.y)).a);
	nmin = min(nmin, texture(TEXTURE, UV - vec2(0.0, px.y)).a);
	nmin = min(nmin, texture(TEXTURE, UV + px * 0.7071).a);
	nmin = min(nmin, texture(TEXTURE, UV - px * 0.7071).a);
	nmin = min(nmin, texture(TEXTURE, UV + vec2(px.x, -px.y) * 0.7071).a);
	nmin = min(nmin, texture(TEXTURE, UV + vec2(-px.x, px.y) * 0.7071).a);
	float edge = clamp(1.0 - nmin, 0.0, 1.0);
	float a = b0 * v_mod.a * mix(inner_alpha, 1.0, edge);
	vec3 col = mix(v_mod.rgb * inner_tint, v_mod.rgb, edge);
	COLOR = vec4(col * a, a);
}
