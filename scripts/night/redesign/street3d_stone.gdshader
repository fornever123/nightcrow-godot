shader_type spatial;
// 背景线 11-19「3D 街体」的石头材质：按面朝向分三张可平铺贴图（世界坐标贴，块多长都不拉伸）。
//   朝上 → top_tex（街面石子 / 步廊台面石板），朝镜头 → face_tex（石墙），侧面 → side_tex（石墙）。
// 法线由贴图明度现算（够用，省一套法线图）；湿石面低粗糙度，灯下有一层很薄的反光（红线：不做水洼镜面）。
// fade_z0 / fade_z1：往后（−z）到这段距离里压暗成夜色。
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform sampler2D top_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D face_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D side_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec2 top_scale = vec2(260.0, 260.0);   // 一张贴图铺多少世界单位
uniform vec2 face_scale = vec2(220.0, 220.0);
uniform float bump = 1.4;
uniform float rough_top = 0.42;
uniform float rough_wall = 0.8;
uniform vec3 tint : source_color = vec3(1.0);
uniform float macro = 0.0;     // 大尺度明暗斑：同一张贴图按 1/7 尺寸再采一次当明暗，压掉一眼可见的重复
uniform float fade_z0 = 99999.0;
uniform float fade_z1 = 100000.0;
uniform vec3 fade_col : source_color = vec3(0.05, 0.055, 0.06);

uniform sampler2D refl_tex : hint_default_black, filter_linear;    // 镜像相机拍的倒影（只街面用）
uniform float refl = 0.0;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float lum(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

void fragment() {
	vec2 uv;
	vec3 col;
	float rough;
	vec2 du;
	vec2 dv;
	vec3 rcol = vec3(0.0);
	if (wnrm.y > 0.5) {
		uv = wpos.xz / top_scale;
		col = texture(top_tex, uv).rgb;
		float mv = lum(texture(top_tex, uv * 0.137 + vec2(0.31, 0.17)).rgb) + lum(texture(top_tex, uv * 0.061 + vec2(0.7, 0.4)).rgb);
		col *= mix(1.0, 0.45 + mv * 1.1, macro);
		float e = 1.0 / 1024.0;
		du = vec2(e, 0.0); dv = vec2(0.0, e);
		float h0 = lum(col);
		float hx = lum(texture(top_tex, uv + du).rgb);
		float hz = lum(texture(top_tex, uv + dv).rgb);
		vec3 n = normalize(vec3(-(hx - h0) * bump * 60.0, 1.0, -(hz - h0) * bump * 60.0));
		NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
		rough = rough_top + (1.0 - h0) * 0.25;    // 石缝（暗）更糙，石面更润
		if (refl > 0.0) {
			// 倒影：主镜头看到的 v 行 ↔ 镜像相机的 1 − v 行；石面起伏把倒影打碎一点（湿石板的薄反光，不是水洼镜面）
			vec2 ruv = vec2(SCREEN_UV.x, 1.0 - SCREEN_UV.y) + n.xz * vec2(0.012, 0.03);
			vec3 r = texture(refl_tex, ruv).rgb;
			float wet = smoothstep(0.12, 0.4, h0);
			float fres = 0.35 + 0.65 * pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
			rcol = r * refl * wet * fres;
		}
	} else if (abs(wnrm.z) > 0.5) {
		uv = vec2(wpos.x, -wpos.y) / face_scale;
		col = texture(face_tex, uv).rgb;
		rough = rough_wall;
	} else {
		uv = vec2(wpos.z, -wpos.y) / face_scale;
		col = texture(side_tex, uv).rgb;
		rough = rough_wall;
	}
	ALBEDO = col * tint;
	ROUGHNESS = rough;
	SPECULAR = 0.45;
	// 往后（−z）这段距离里压暗进夜色：街面尽头不留硬边
	float k = smoothstep(fade_z0, fade_z1, -wpos.z);
	ALBEDO = mix(ALBEDO, fade_col, k);
	EMISSION = rcol * (1.0 - k);
}
