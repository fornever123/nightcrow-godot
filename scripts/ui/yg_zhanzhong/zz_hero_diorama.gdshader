shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

// 《司辰四象 · 三维裂时殿堂》真三维女主前景立体片着色器：
// - 实时呼吸起伏 + 发丝/衣摆微风波动顶点动画（活的角色，绝非死静图！）
// - 底部羽化融入三维殿堂深渊（零生硬水平截断边）
// - 动态边缘逆光（主角色轮廓高光）+ 进场/切换/确认瞬间冷钢剑锋扫光
// - 轨道远景自动冷暗降饱和，转到 C 位焦点瞬间全彩绽放！

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform vec4 accent_col : source_color = vec4(0.616, 0.451, 1.0, 1.0);
uniform vec4 active_theme_col : source_color = vec4(0.616, 0.451, 1.0, 1.0);
uniform float focus_k : hint_range(0.0, 1.0) = 1.0;     // 1.0 = C位主角，0.0 = 轨道侧翼
uniform float locked_k : hint_range(0.0, 1.0) = 0.0;    // 1.0 = 尚在光中（侧翼带极细定格光丝）
uniform float opacity : hint_range(0.0, 1.0) = 1.0;
uniform float flash_k : hint_range(0.0, 1.0) = 0.0;     // 切换/确认瞬间的刃光爆闪
uniform float glint_u = -1.5;                            // 斜向金属扫光进度
uniform float time_sec = 0.0;
uniform float sway_amp = 1.0;

void vertex() {
	// 呼吸微动 + 上半身发丝与披风随风柔摆（底部锚定稳固）
	float h_factor = clamp(1.0 - UV.y, 0.0, 1.0);
	float breath = sin(time_sec * 1.9) * 5.5 * h_factor;
	float wind_x = sin(time_sec * 2.3 + UV.y * 5.2 + UV.x * 3.1) * 7.5 * h_factor * h_factor * sway_amp;
	float wind_z = cos(time_sec * 1.7 + UV.x * 4.5) * 9.0 * h_factor * sway_amp;
	VERTEX.x += wind_x;
	VERTEX.y += breath;
	VERTEX.z += wind_z;
}

void fragment() {
	vec4 tex = texture(albedo_tex, UV);
	// 底部平滑羽化融入 3D 雾海，彻底消除半身立绘底缘齐切线
	float bot_fade = 1.0 - smoothstep(0.84, 0.995, UV.y);
	float a = tex.a * bot_fade * opacity;
	if (a < 0.02) {
		discard;
	}

	vec3 col = tex.rgb;
	// 轨道侧翼自动沉入 95% 冷钢单色暗影并统一吃当前主角主色逆光（彻底根除非朔画面里背景朔的紫色串色！）
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	float desat = (1.0 - focus_k) * 0.95;
	col = mix(col, vec3(luma * 0.92, luma * 0.95, luma), desat);
	col *= mix(0.28, 1.02, focus_k);

	// 利用邻域 alpha 梯度实时提取人物真实剪影轮廓，打上冷冽主角色三维逆光边！
	vec2 eps = vec2(0.0045, 0.0035);
	float a_l = texture(albedo_tex, UV + vec2(-eps.x, 0.0)).a;
	float a_r = texture(albedo_tex, UV + vec2(eps.x, 0.0)).a;
	float a_u = texture(albedo_tex, UV + vec2(0.0, -eps.y)).a;
	float rim = clamp(1.0 - min(min(a_l, a_r), a_u), 0.0, 1.0);
	float rim_power = mix(0.42, 1.15, focus_k) + flash_k * 1.4;
	vec3 rim_rgb = mix(active_theme_col.rgb, accent_col.rgb, focus_k);
	col += mix(rim_rgb, vec3(1.0), 0.35) * rim * rim_power * (1.0 - smoothstep(0.75, 0.98, UV.y));

	// 斜向冷钢高光扫掠（切人/确认出战瞬间从人物与兵器上掠过一道耀眼寒芒）
	float diag = UV.x * 0.72 + UV.y * 0.68;
	float sheen = exp(-pow((diag - glint_u) * 9.0, 2.0));
	col += mix(accent_col.rgb, vec3(1.0), 0.65) * sheen * (0.65 + 0.85 * flash_k) * focus_k;

	// 「尚在光中」未解锁角色在远景带有微弱垂直悬停圣光细丝（不白瓷化，保留鲜活人设）
	if (locked_k > 0.5 && focus_k < 0.85) {
		float veil = smoothstep(0.5, 0.95, sin(UV.x * 58.0 + time_sec * 0.6) * 0.5 + 0.5);
		col += vec3(0.95, 0.96, 1.0) * veil * 0.10 * (1.0 - focus_k);
	}

	col += mix(accent_col.rgb, vec3(1.0), 0.55) * flash_k * 0.32 * focus_k;

	ALBEDO = col;
	ALPHA = a;
}
