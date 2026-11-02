shader_type canvas_item;
// 大招眼睛分格（2026-10-29 原型）：全屏 ColorRect，画一个斜着的平行四边形分格，里面是整张眼睛特写，
// 用深度图做几像素视差、遮罩做发丝摆动、虹膜内径向重映射做瞳孔收缩、紫色加亮做眼光；
// 前景几片虚焦鸦羽；一道刀线沿左下银边的延长线斩开分格，两半沿刀线错开滑出。分格外透明（露出冻结的游戏画面）。
// 参数全部由 scripts/night/ult_eye_panel.gd 按帧设置。坐标：p 屏幕像素，img 眼睛图像素。

uniform sampler2D eye_tex : source_color, filter_linear_mipmap;
uniform sampler2D mask_tex : filter_linear;            // R 深度 / G 摆动
uniform sampler2D feather_tex : source_color, filter_linear_mipmap;
uniform vec2 screen = vec2(1280.0, 720.0);
uniform vec2 img_size = vec2(1672.0, 941.0);

uniform vec2 center = vec2(640.0, 360.0);             // 分格中心
uniform vec2 half_size = vec2(590.0, 324.0);          // 完全张开时的半宽 / 半高
uniform float open = 1.0;                             // 0 = 一条缝，1 = 张开
uniform float slit = 0.0;                             // 刀缝那道光的长度（0～1，从中间往两边长）
uniform float skew = 0.14;                            // 左右边的斜度（tan）
uniform float tilt = -0.026;                          // 整格转角（弧度）
uniform float frame_px = 5.0;                         // 墨线框
uniform float img_scale = 0.7045;                     // 眼睛图 1 像素 = 屏幕多少像素（zoom=1 时）
uniform float zoom = 1.0;
uniform float turn = 0.0;                             // 图在格子里额外的转角
uniform vec2 pan = vec2(0.0);                         // 图中心偏移（图像素）
uniform vec2 parallax = vec2(0.0);                    // 视差：按 (深度 - 0.5) 乘这个（图像素）
uniform float sway_t = 0.0;                           // 摆动的时间（秒，按帧算，截图可复现）
uniform float sway_px = 3.0;
uniform vec4 eye_l = vec4(730.0, 408.0, 66.0, 58.0);  // 虹膜中心、半径（图像素）
uniform vec4 eye_r = vec4(1104.0, 488.0, 54.0, 44.0);
uniform float pupil = 0.0;                            // 瞳孔收缩强度（0～0.35）
uniform float glow = 0.0;                             // 紫色加亮
uniform float iris = 0.0;                             // 虹膜额外亮起
uniform float streak = 0.0;                           // 左眼横向眼光
uniform vec4 violet : source_color = vec4(0.62, 0.38, 1.0, 1.0);
uniform vec2 glint_a = vec2(480.0, 672.0);            // 左下银边（图像素）
uniform vec2 glint_b = vec2(1100.0, 941.0);
uniform float glint_pos = -1.0;                       // 寒光走到银边的哪儿（0～1，<0 不画）
uniform vec4 feathers[4];                             // 前景鸦羽：屏幕 x, y, 角度, 长度（像素；0 = 不画）
uniform float feather_lod = 2.5;
uniform vec2 cut_p = vec2(0.0);                       // 刀线经过的点（屏幕像素）
uniform vec2 cut_d = vec2(1.0, 0.0);                  // 刀线方向（单位向量）
uniform float cut_line = 0.0;                         // 刀线亮度
uniform float split = 0.0;                            // 两半错开多少（像素）
uniform float alpha = 1.0;

vec2 rot(vec2 v, float a) {
	float c = cos(a), s = sin(a);
	return vec2(c * v.x - s * v.y, s * v.x + c * v.y);
}

// 屏幕点 → 格子坐标（转正，没有斜切）
vec2 to_cell(vec2 p) {
	return rot(p - center, -tilt);
}

// 在格子里？返回到边的距离（像素，>0 在里面）
float inside(vec2 q) {
	float hh = half_size.y * open;
	float x = q.x - q.y * skew;
	return min(half_size.x - abs(x), hh - abs(q.y));
}

vec2 pupil_warp(vec2 img, vec4 e) {
	vec2 d = (img - e.xy) / e.zw;
	float r = length(d);
	if (r < 1.0) {
		float s = 1.0 + pupil * (1.0 - r) * (1.0 - r);
		img = e.xy + (img - e.xy) * s;
	}
	return img;
}

float purple(vec3 c) {
	return smoothstep(0.12, 0.32, c.b - c.g) * smoothstep(0.25, 0.55, c.b);
}

// 格子坐标 → 眼睛图颜色（含视差、摆动、瞳孔、眼光、寒光、前景羽毛之前）
vec3 eye_color(vec2 q) {
	vec2 img = rot(q, -turn) / (img_scale * zoom) + img_size * 0.5 + pan;
	vec4 m = texture(mask_tex, img / img_size);
	img += parallax * (m.r - 0.5) * 2.0;
	float w = m.g;
	img += w * sway_px * vec2(sin(sway_t * 1.9 + img.y * 0.011), 0.5 * sin(sway_t * 1.4 + img.x * 0.009));
	img = pupil_warp(img, eye_l);
	img = pupil_warp(img, eye_r);
	vec2 uv = clamp(img / img_size, vec2(0.001), vec2(0.999));
	vec3 c = texture(eye_tex, uv).rgb;
	float pm = purple(c);
	c += violet.rgb * pm * glow;
	vec3 blur = textureLod(eye_tex, uv, 4.5).rgb;            // 粗糙的假辉光：低一级贴图里的紫色往外溢
	c += violet.rgb * purple(blur) * glow * 0.35;
	float ir = 0.0;
	ir = max(ir, 1.0 - smoothstep(0.55, 1.05, length((img - eye_l.xy) / eye_l.zw)));
	ir = max(ir, 1.0 - smoothstep(0.55, 1.05, length((img - eye_r.xy) / eye_r.zw)));
	c += c * ir * iris * (0.3 + pm) * 1.3;                   // 提亮但不改色相（直接加紫会偏粉）
	// 左眼横向眼光
	vec2 sd = img - eye_l.xy;
	c += mix(violet.rgb, vec3(1.0), 0.5) * streak * exp(-abs(sd.y) / 4.0) * exp(-abs(sd.x) / 260.0);
	// 银边上走过的寒光
	if (glint_pos >= 0.0) {
		vec2 ab = glint_b - glint_a;
		float s = dot(img - glint_a, ab) / dot(ab, ab);
		float dist = length(img - (glint_a + ab * clamp(s, 0.0, 1.0)));
		float band = exp(-dist / 5.0) * exp(-pow((s - glint_pos) * 7.0, 2.0));
		c += vec3(0.95, 0.92, 1.0) * band * 1.4;
	}
	return c;
}

vec4 feather_over(vec2 p, vec4 col) {
	for (int i = 0; i < 4; i++) {
		vec4 f = feathers[i];
		if (f.w <= 0.0) {
			continue;
		}
		vec2 l = rot(p - f.xy, -f.z) / f.w;           // 羽毛贴图 200×80：长度 f.w 像素
		vec2 fuv = l * vec2(1.0, 2.5) + 0.5;
		if (fuv.x < 0.0 || fuv.x > 1.0 || fuv.y < 0.0 || fuv.y > 1.0) {
			continue;
		}
		vec4 t = textureLod(feather_tex, fuv, feather_lod);
		vec3 ink = mix(vec3(0.02, 0.015, 0.035), t.rgb, 0.35);
		col.rgb = mix(col.rgb, ink, t.a * 0.85);
	}
	return col;
}

// 一半格子：off 是这一半挪了多少，keep 是保留刀线哪一侧（+1 / -1）
vec4 half_cell(vec2 p, vec2 off, float keep) {
	vec2 sp = p - off;
	vec2 n = vec2(-cut_d.y, cut_d.x);
	float side = dot(sp - cut_p, n);
	if (split > 0.0 && side * keep < 0.0) {
		return vec4(0.0);
	}
	vec2 q = to_cell(sp);
	float d = inside(q);
	if (d <= 0.0) {
		return vec4(0.0);
	}
	vec4 col = vec4(eye_color(q), 1.0);
	col = feather_over(sp, col);
	float ink = 1.0 - smoothstep(frame_px - 1.0, frame_px, d);
	col.rgb = mix(col.rgb, vec3(0.015, 0.012, 0.025), ink);
	// 张开时上下刀口发白
	float edge = exp(-abs(abs(q.y) - half_size.y * open) / 2.0) * (1.0 - open);
	col.rgb += vec3(1.0) * edge * 2.0;
	col.a = smoothstep(0.0, 1.5, d);
	return col;
}

void fragment() {
	vec2 p = UV * screen;
	vec2 n = vec2(-cut_d.y, cut_d.x);
	vec4 col = vec4(0.0);
	if (open > 0.002) {
		vec4 a = half_cell(p, -cut_d * split - n * split * 0.35, -1.0);
		vec4 b = half_cell(p, cut_d * split + n * split * 0.35, 1.0);
		col = a.a > 0.0 ? a : b;
	}
	// 刀缝那道光：格子张开前从中间往两边长出来
	vec2 q0 = to_cell(p);
	float sl = exp(-abs(q0.y) / 1.6) * step(abs(q0.x), screen.x * 0.6 * slit) * (1.0 - open);
	col = mix(col, vec4(1.0), clamp(sl * 1.5, 0.0, 1.0) * step(0.001, slit));
	// 斩开的刀线：横贯全屏
	float cd = abs(dot(p - cut_p, n));
	float core = exp(-cd / 1.8);
	float halo = exp(-cd / 14.0);
	float la = clamp(core + halo * 0.6, 0.0, 1.0) * cut_line;
	col.rgb = mix(col.rgb, mix(violet.rgb, vec3(1.0), core), la);
	col.a = max(col.a, la);
	COLOR = vec4(col.rgb, col.a * alpha);
}
