// 角色高清采样（节点 10，见 docs/HANDOFF-试玩版.md §13）。
// 问题：序列帧原图 340–1200px，屏幕上只显示 0.17–0.49 倍。普通双线性只取 4 个像素，
//       缩小两倍以上就会漏像素 → 锯齿、闪烁；原图透明处是黑色 → 边上一圈发黑/发糊。
// 做法：
//   1) ArtCache 加载时把贴图预乘透明度（rgb×a），这里用预乘混合，透明边不再混进黑色；
//   2) 按“一个屏幕像素盖住多少贴图像素”在这个范围里均匀取 n×n 个点平均（n 自动 1–6），
//      相当于把原图高质量缩小到屏幕大小；
//   3) 轻微锐化：减去一个 2 倍范围的模糊（反锐化掩模），找回缩小时损失的线条；
//   4) 边缘收紧：把很淡的半透明边（抠图残留的毛边）压掉一点。
// 用法：主着色器里 `render_mode blend_premul_alpha;` + `#include` 本文件，
//       vertex() 里写 `hq_mod = COLOR;`，fragment() 里 `vec4 c; HQ_SAMPLE(c, UV)` 取色，最后 hq_out() 输出。
uniform float hq_sharp : hint_range(0.0, 1.5) = 0.8;
uniform float hq_edge : hint_range(1.0, 2.0) = 1.12;
uniform int hq_max_taps : hint_range(1, 8) = 6;
varying vec4 hq_mod;   // 顶点色（已经乘好 modulate / self_modulate）

// 注意：不能把 TEXTURE 当参数传进自定义函数（兼容渲染器会报 custom_samplers 错），
//       所以取样部分写成宏，在 fragment() 里原地展开。

// n×n 网格均匀取样（越界的点按透明算），结果是预乘颜色
#define HQ_BOX(ACC, UVV, DX, DY, N) { \
	ACC = vec4(0.0); \
	float hq_inv_ = 1.0 / float(N); \
	for (int hq_j = 0; hq_j < 8; hq_j++) { \
		if (hq_j >= (N)) break; \
		for (int hq_i = 0; hq_i < 8; hq_i++) { \
			if (hq_i >= (N)) break; \
			vec2 hq_o = (vec2(float(hq_i), float(hq_j)) + 0.5) * hq_inv_ - 0.5; \
			vec2 hq_u = (UVV) + (DX) * hq_o.x + (DY) * hq_o.y; \
			vec2 hq_b = step(vec2(0.0), hq_u) * step(hq_u, vec2(1.0)); \
			ACC += texture(TEXTURE, hq_u) * (hq_b.x * hq_b.y); \
		} \
	} \
	ACC *= hq_inv_ * hq_inv_; \
}

// 锐化 + 边缘收紧（c = 正常范围平均，wide = 2 倍范围平均）
vec4 hq_finish(vec4 c, vec4 wide) {
	if (hq_sharp > 0.0) {
		c += (c - wide) * hq_sharp;
		c.a = clamp(c.a, 0.0, 1.0);
		c.rgb = clamp(c.rgb, vec3(0.0), vec3(c.a));
	}
	if (hq_edge > 1.0 && c.a > 0.0) {
		float a2 = clamp((c.a - 0.5) * hq_edge + 0.5, 0.0, 1.0);
		c = vec4(c.rgb * (a2 / c.a), a2);
	}
	return c;
}

// OUT = 预乘颜色（rgb 已乘 a）
#define HQ_SAMPLE(OUT, UVV) { \
	vec2 hq_dx = dFdx(UVV); \
	vec2 hq_dy = dFdy(UVV); \
	float hq_fp = max(length(hq_dx / TEXTURE_PIXEL_SIZE), length(hq_dy / TEXTURE_PIXEL_SIZE)); \
	int hq_n = clamp(int(ceil(hq_fp - 0.05)), 1, hq_max_taps); \
	vec4 hq_c; \
	HQ_BOX(hq_c, UVV, hq_dx, hq_dy, hq_n) \
	vec4 hq_w = hq_c; \
	if (hq_sharp > 0.0) { \
		int hq_n2 = clamp(max(hq_n, 2), 2, hq_max_taps); \
		HQ_BOX(hq_w, UVV, hq_dx * 2.0, hq_dy * 2.0, hq_n2) \
	} \
	OUT = hq_finish(hq_c, hq_w); \
}

// 预乘颜色 × 顶点色 → 输出（预乘混合要求 rgb 也乘上顶点色的 a）
vec4 hq_out(vec4 c) {
	return vec4(c.rgb * hq_mod.rgb * hq_mod.a, c.a * hq_mod.a);
}
