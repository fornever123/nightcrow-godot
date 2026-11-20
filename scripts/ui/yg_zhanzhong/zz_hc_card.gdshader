// [YG-MARK] 角色选择「钟铸铁卡」：把画好的整张卡（SubViewport）绕竖轴转成带透视的立体卡，带铸铁厚度。
// 确认出战时 split > 0：一道紫刀光从右上斩到左下，卡沿刀口裂成两半错开。
shader_type canvas_item;

uniform sampler2D face : filter_linear;
uniform vec2 vp_size = vec2(900.0, 1100.0);
uniform float scale = 1.0;       // 屏幕像素 / 卡面像素
uniform float yaw = 0.0;         // 弧度，正 = 右边往里转
uniform float focal = 1500.0;
uniform float dim = 0.0;
uniform float flash = 0.0;
uniform float opacity = 1.0;
uniform float split = 0.0;       // 0..1 斩开程度
uniform float slash_line = 0.0;  // 刀口那条光的亮度
uniform vec4 accent : source_color = vec4(0.62, 0.45, 1.0, 1.0);
uniform float thick = 14.0;      // 铸铁厚度（卡面像素）
uniform vec2 rect_size = vec2(1200.0, 1400.0);

const vec2 CUT_DIR = vec2(-0.6, 0.8);   // 右上 → 左下

vec2 unproject(vec2 d, float depth, out bool ok) {
	// 卡面平面绕竖轴转 yaw，并沿法线往后推 depth；求屏幕偏移 d 对应的卡面坐标
	float s = sin(yaw);
	float c = cos(yaw);
	float zf = focal + depth * c;
	float xo = -depth * s;
	float den = focal * c - d.x * s;
	ok = den > 1.0;
	float u = (d.x * zf - focal * xo) / max(den, 1.0);
	float z = zf + u * s;
	float v = d.y * z / focal;
	return vec2(u, v);
}

vec4 face_at(vec2 local) {
	vec2 uv = local / vp_size + 0.5;
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) return vec4(0.0);
	return texture(face, uv);
}

vec4 cut_face(vec2 local) {
	if (split <= 0.0) return face_at(local);
	vec2 n = vec2(CUT_DIR.y, -CUT_DIR.x);
	float side = sign(dot(local, n));
	float gap = split * 120.0;
	if (abs(dot(local, n)) < gap * 0.5) return vec4(0.0);
	vec2 src = local - side * n * gap * 0.5 - side * CUT_DIR * split * 90.0;
	return face_at(src);
}

void fragment() {
	vec2 d = (UV - 0.5) * rect_size / scale;
	bool ok;
	vec2 local = unproject(d, 0.0, ok);
	vec4 col = ok ? cut_face(local) : vec4(0.0);

	// 铸铁厚度：往后推几层，露出的侧面是暗钢
	if (col.a < 0.99 && thick > 0.0) {
		float edge = 0.0;
		for (int i = 1; i <= 4; i++) {
			bool ok2;
			vec2 l2 = unproject(d, thick * float(i) / 4.0, ok2);
			if (ok2) edge = max(edge, cut_face(l2).a);
		}
		vec3 steel = vec3(0.16, 0.16, 0.19);
		col.rgb = mix(steel * edge, col.rgb, col.a);
		col.a = max(col.a, edge);
	}

	col.rgb *= 1.0 - dim;
	col.rgb += vec3(flash) * col.a;

	// 刀口的光
	if (slash_line > 0.0 && ok) {
		vec2 n = vec2(CUT_DIR.y, -CUT_DIR.x);
		float dl = abs(dot(local, n));
		float along = dot(local, CUT_DIR);
		// 刀光两头尖：中段最粗，往两端收成针
		float len = 1.0 - smoothstep(0.0, vp_size.y * 0.62, abs(along));
		float wd = mix(0.5, 2.6, len);
		// 斩下那一瞬是一根白芯刀光；裂开后刀光散掉，只剩两道切口边缘发主色光
		float core = exp(-dl / wd) * step(0.001, len) * (1.0 - smoothstep(0.0, 0.35, split));
		float halo = exp(-dl / (6.0 + 18.0 * len)) * len * (1.0 - smoothstep(0.0, 0.5, split));
		float g = split * 60.0;
		float edge = exp(-abs(dl - g) / (2.0 + 5.0 * len)) * len * smoothstep(0.0, 0.2, split);
		vec3 lc = mix(accent.rgb, vec3(1.0), clamp(core, 0.0, 1.0) * 0.85);
		float k = (core * 1.6 + halo * 0.5) * slash_line;
		col.rgb += lc * k + accent.rgb * edge * 1.3 * slash_line;
		col.a = max(col.a, clamp(k + edge * slash_line, 0.0, 1.0));
	}
	COLOR = vec4(col.rgb, col.a * opacity);
}
