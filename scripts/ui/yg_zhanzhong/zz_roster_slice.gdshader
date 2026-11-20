shader_type canvas_item;
// 《刀裂四分》28° 斜切角色分格着色器：解析级抗锯齿斜刃裁切 + 折叠态自动锁眼特写 + 展开态可见格锁脸 + 刀光边界辉光

uniform sampler2D portrait_tex : source_color, filter_linear_mipmap;
uniform vec2 screen_size = vec2(1920.0, 1080.0);
uniform float x_left_top = 0.0;       // 本格左边界在屏幕顶部的 x（像素）
uniform float x_right_top = 1200.0;   // 本格右边界在屏幕顶部的 x（像素）
uniform float slant_dx = 440.0;       // 底部相对顶部向左倾斜像素量（约 22°~24° 匹配主视觉刀锋角）
uniform float active_k = 1.0;         // 1 = 展开主英雄，0 = 折叠斜条特写
uniform float hover_k = 0.0;          // 鼠标悬停微亮
uniform float locked_k = 0.0;         // 1 = 尚在光中（未解锁角色折叠态略冷压暗）
uniform float open_k = 1.0;           // 页面进出总进度 0..1
uniform float flash_k = 0.0;          // 切换/斩开瞬间刃光脉冲
uniform vec2 parallax = vec2(0.0);    // 鼠标微视差
uniform vec2 eye_uv = vec2(0.64, 0.35); // 折叠态锁焦眼睛中心 UV
uniform vec4 accent_col : source_color = vec4(0.616, 0.451, 1.0, 1.0);

void fragment() {
	vec2 px = UV * screen_size;
	float t_y = UV.y;
	float xl = x_left_top - slant_dx * t_y;
	float xr = x_right_top - slant_dx * t_y;

	float inv_len = inversesqrt(1.0 + (slant_dx / screen_size.y) * (slant_dx / screen_size.y));
	float dl = (px.x - xl) * inv_len;
	float dr = (xr - px.x) * inv_len;

	float mask_l = (x_left_top < -100.0) ? 1.0 : smoothstep(-1.0, 1.2, dl);
	float mask_r = (x_right_top > screen_size.x + slant_dx + 100.0) ? 1.0 : smoothstep(-1.0, 1.2, dr);
	float inside = mask_l * mask_r;
	if (inside < 0.005 || open_k < 0.005) {
		discard;
	}

	// 计算本格在眼部高度的可见区间，使展开态 4 女主全脸精准锚定在本格中偏右（0 裁脸、0 挡脸）
	float xl_face = max(0.0, x_left_top - slant_dx * 0.35);
	float xr_face = min(screen_size.x, x_right_top - slant_dx * 0.35);
	float target_face_x = mix(xl_face, xr_face, 0.67) / screen_size.x;
	vec2 uv_open = (UV - vec2(target_face_x, eye_uv.y)) * 0.92 + eye_uv + parallax * vec2(-0.014, -0.008);

	// 折叠眼部特写 UV：取可见斜条区间中点，连最左「朔」与最右「曜」也能把凌厉眼神锁在正中！
	float x_mid = 0.5 * (xl_face + xr_face);
	vec2 d_from_mid = (px - vec2(x_mid, screen_size.y * 0.38)) / screen_size;
	vec2 uv_strip = eye_uv + d_from_mid * vec2(0.74, 0.74) + parallax * vec2(-0.006, -0.004);

	vec2 suv = mix(uv_strip, uv_open, active_k);
	suv = clamp(suv, vec2(0.002), vec2(0.998));

	vec3 col = texture(portrait_tex, suv).rgb;

	// 折叠态强去饱和压暗：尤其切到萤/薇/曜时，左侧折叠态「朔」0% 亮紫泄露！
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	float desat = (1.0 - active_k) * mix(0.88, 0.62, locked_k) * (1.0 - hover_k * 0.35);
	col = mix(col, vec3(luma), desat);
	float dim = mix(mix(0.56, 0.48, locked_k) + hover_k * 0.16, 1.0, active_k);
	col *= dim;

	// 展开态格内局部左暗幕托底（对朔/萤/薇/曜全员稳定提供 >15:1 文字安全区，纯中性黑墨零紫偏）
	float slice_l = max(0.0, xl);
	float slice_r = min(screen_size.x, xr);
	float local_x = (px.x - slice_l) / max(1.0, slice_r - slice_l);
	float left_scrim = (1.0 - smoothstep(0.0, 0.56, local_x)) * active_k;
	col = mix(col, vec3(0.024, 0.025, 0.028), left_scrim * 0.82);
	float bot_scrim = smoothstep(0.68, 1.0, UV.y);
	col = mix(col, vec3(0.022, 0.023, 0.026), bot_scrim * mix(0.78, 0.50, active_k));

	// 28° 斜刃分界高光边（折叠条用中性冷钢，仅当前展开主格绽放其专属主角色，杜绝邻格串色）
	float edge_l = (x_left_top < -100.0) ? 0.0 : exp(-abs(dl) * 0.38);
	float edge_r = (x_right_top > screen_size.x + slant_dx + 100.0) ? 0.0 : exp(-abs(dr) * 0.38);
	float edge_sharp = max(
		(x_left_top < -100.0) ? 0.0 : smoothstep(3.0, 0.0, abs(dl)),
		(x_right_top > screen_size.x + slant_dx + 100.0) ? 0.0 : smoothstep(3.0, 0.0, abs(dr))
	);
	float glow_band = max(edge_l, edge_r) * (0.24 + 0.52 * active_k + 0.45 * flash_k + 0.22 * hover_k);
	vec3 edge_col = mix(vec3(0.76, 0.78, 0.82), accent_col.rgb, active_k);
	col += edge_col * glow_band * 0.74;
	col += vec3(0.96, 0.96, 0.98) * edge_sharp * (0.62 + 0.36 * active_k + 0.5 * flash_k);

	// 切换瞬间的白炽斩击高光衰减
	col += mix(accent_col.rgb, vec3(1.0), 0.55) * flash_k * 0.26 * active_k;

	COLOR = vec4(col, inside * open_k);
}
