shader_type canvas_item;
render_mode blend_premul_alpha;
#include "res://assets/shaders/char_hq.gdshaderinc"
// 角色融入夜景（节点 5，见 docs/HANDOFF-试玩版.md §12）：
//   1) 冷色环境：略去饱和 + 乘月夜蓝 + 暗部抬一点蓝；
//   2) 月光边缘光：月亮在屏幕右上方，朝那个方向的轮廓边亮起一条冷白光；
//   3) 灯笼暖光：离灯笼越近，朝灯笼那一侧越暖（宽的漫反射 + 窄的暖边）。
//   取色走高清采样（节点 10，char_hq.gdshaderinc）：贴图是预乘透明度的，先还原成普通颜色再打光。
//   4) 第三轮（节点 16，见 §14）：角色缩小后从背景里“跳出来”——
//      外圈 ol_width 屏幕像素的深色描边（刀光不描：亮、偏蓝白或亮紫的像素不算轮廓），再略提对比和饱和。
// 方向都是“屏幕方向”，脚本按精灵是否镜像（flip）换算到贴图方向。
uniform vec3 ambient = vec3(0.85, 0.9, 1.0);
uniform float desat = 0.08;
uniform vec3 shadow_lift = vec3(0.0, 0.012, 0.04);
uniform vec3 moon_col = vec3(0.74, 0.86, 1.0);
uniform float moon_amt = 0.85;
uniform vec2 moon_dir = vec2(0.86, -0.5);
uniform vec3 warm_col = vec3(1.0, 0.64, 0.32);
uniform float warm = 0.0;
uniform vec2 warm_dir = vec2(1.0, 0.0);
uniform float flip = 1.0;
uniform vec2 px = vec2(2.0, 2.0);   // 1 个“边缘光宽度”对应多少贴图像素（x/y）
uniform vec2 spx = vec2(1.0, 1.0);  // 1 个屏幕像素对应多少贴图像素（x/y）
uniform float ol_width = 0.0;       // 描边宽度（屏幕像素），0 = 不描边
uniform vec3 ol_col = vec3(0.04, 0.047, 0.094);
uniform float punch_con = 1.0;      // 对比
uniform float punch_sat = 1.0;      // 饱和

// 轮廓取样：某点“算不算身体”（刀光：亮且偏蓝白、或亮紫（紫刀光/紫晕，见 tools/art/recolor_slash.py）→ 不算，所以刀光外面不描边）
#define OL_TAP(ACC, UVV) { \
	vec2 ol_u = (UVV); \
	vec4 ol_t = texture(TEXTURE, ol_u) * inside(ol_u); \
	if (ol_t.a > 0.02) { \
		vec3 ol_s = ol_t.rgb / ol_t.a; \
		float ol_fx = max(step(0.55, min(ol_s.r, min(ol_s.g, ol_s.b))) * step(ol_s.r + 0.04, ol_s.b), \
			step(0.68, ol_s.b) * step(ol_s.g + 0.2, ol_s.b) * step(ol_s.r + 0.08, ol_s.b)); \
		ACC = max(ACC, ol_t.a * (1.0 - ol_fx)); \
	} \
}

// 贴图外面算透明（序列帧每帧一张整图，没有图集）
float inside(vec2 uv) {
	return step(0.0, uv.x) * step(0.0, uv.y) * step(uv.x, 1.0) * step(uv.y, 1.0);
}

vec3 screen(vec3 a, vec3 b) {
	return vec3(1.0) - (vec3(1.0) - a) * (vec3(1.0) - b);
}

void vertex() {
	hq_mod = COLOR;
}

void fragment() {
	vec4 p;
	HQ_SAMPLE(p, UV)
	vec4 c = vec4(p.a > 0.0 ? p.rgb / p.a : vec3(0.0), p.a);
	if (c.a > 0.003) {
		vec2 tp = TEXTURE_PIXEL_SIZE * px;
		vec2 md = normalize(vec2(moon_dir.x * flip, moon_dir.y));
		vec2 u1 = UV + md * tp;
		vec2 u2 = UV + md * tp * 2.2;
		float rim = (1.0 - texture(TEXTURE, u1).a * inside(u1)) * 0.65 + (1.0 - texture(TEXTURE, u2).a * inside(u2)) * 0.35;
		vec2 wd = normalize(vec2(warm_dir.x * flip, warm_dir.y));
		vec2 u3 = UV + wd * tp;
		vec2 u4 = UV + wd * tp * 7.0;
		float wrim = 1.0 - texture(TEXTURE, u3).a * inside(u3);
		float wide = 1.0 - texture(TEXTURE, u4).a * inside(u4);
		float lum = dot(c.rgb, vec3(0.299, 0.587, 0.114));
		vec3 amb = mix(ambient, vec3(1.0), warm * 0.45);
		vec3 col = mix(c.rgb, vec3(lum), desat * (1.0 - warm * 0.5)) * amb + shadow_lift * (1.0 - lum) * (1.0 - lum);
		col += c.rgb * warm_col * warm * (0.22 + 0.6 * wide);
		col = screen(col, moon_col * clamp(rim, 0.0, 1.0) * moon_amt * (1.0 - warm * 0.4));
		col = screen(col, warm_col * clamp(wrim, 0.0, 1.0) * warm * 0.9);
		float l2 = dot(col, vec3(0.299, 0.587, 0.114));
		col = mix(vec3(l2), col, punch_sat);
		col = clamp(0.5 + (col - 0.5) * punch_con, 0.0, 1.0);
		c.rgb = col;
	}
	vec4 o = vec4(c.rgb * c.a, c.a);
	if (ol_width > 0.0 && c.a < 0.98) {
		vec2 r = TEXTURE_PIXEL_SIZE * spx * ol_width;
		float ol = 0.0;
		OL_TAP(ol, UV + vec2(r.x, 0.0))
		OL_TAP(ol, UV - vec2(r.x, 0.0))
		OL_TAP(ol, UV + vec2(0.0, r.y))
		OL_TAP(ol, UV - vec2(0.0, r.y))
		OL_TAP(ol, UV + r * 0.7071)
		OL_TAP(ol, UV - r * 0.7071)
		OL_TAP(ol, UV + vec2(r.x, -r.y) * 0.7071)
		OL_TAP(ol, UV + vec2(-r.x, r.y) * 0.7071)
		OL_TAP(ol, UV + vec2(r.x * 0.5, 0.0))
		OL_TAP(ol, UV - vec2(r.x * 0.5, 0.0))
		OL_TAP(ol, UV + vec2(0.0, r.y * 0.5))
		OL_TAP(ol, UV - vec2(0.0, r.y * 0.5))
		ol = smoothstep(0.15, 0.6, ol) * (1.0 - c.a);
		o += vec4(ol_col * ol, ol);
	}
	COLOR = hq_out(o);
}
