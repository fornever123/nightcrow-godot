shader_type spatial;
// 《拨钟选章》立体画片：深度视差（2.5D）+ 远卡 LOD 虚化 + 轻运动模糊 + 凝光膜 + 每章常驻小动态（不画任何扫光/刀光）
render_mode unshaded, cull_back, depth_draw_always;

uniform sampler2D art : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D depth : filter_linear, repeat_disable;
uniform float depth_k = 0.03;
uniform float dim = 0.0;
uniform float blur = 0.0;
uniform vec2 mblur = vec2(0.0);
uniform float frost = 0.0;
uniform float flash = 0.0;
uniform float opacity = 1.0;
uniform float time_sec = 0.0;
uniform int fxmode = 0;
uniform float zoom = 1.0;
uniform float text_shade = 1.0;

varying vec3 wpos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 cam = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 v = normalize(cam - wpos);
	vec2 vv = vec2(v.x, -v.y) / max(v.z, 0.3);
	vec2 base_uv = (UV - 0.5) / zoom + 0.5;
	if (fxmode == 3) {
		// 浮空白城：远处云海轻轻流动
		float far = 1.0 - texture(depth, base_uv).r;
		base_uv.x += sin(time_sec * 0.21 + base_uv.y * 3.0) * 0.004 * far * far;
	}
	float d = texture(depth, base_uv).r;
	vec2 uv = base_uv;
	for (int i = 0; i < 3; i++) {
		uv = base_uv + vv * depth_k * (d - 0.45);
		d = texture(depth, uv).r;
	}
	uv = clamp(uv, vec2(0.002), vec2(0.998));

	vec3 col = vec3(0.0);
	float lod = blur;
	for (int i = 0; i < 7; i++) {
		float f = float(i) / 6.0 - 0.5;
		col += textureLod(art, clamp(uv + mblur * f, vec2(0.002), vec2(0.998)), lod).rgb;
	}
	col /= 7.0;

	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	if (fxmode == 1) {
		// 影街：暖灯呼吸
		float warm = smoothstep(0.12, 0.35, col.r - col.b) * smoothstep(0.35, 0.7, luma);
		col *= 1.0 + warm * (0.12 * sin(time_sec * 2.3 + uv.x * 9.0) + 0.06 * sin(time_sec * 7.1));
	} else if (fxmode == 2) {
		// 归晓大教堂：光柱缓缓扫过
		float hi = smoothstep(0.55, 0.85, luma);
		float band = 0.5 + 0.5 * sin((uv.x * 1.4 + uv.y * 0.9) * 9.0 - time_sec * 0.7);
		col += hi * band * vec3(1.0, 0.92, 0.72) * 0.16;
	} else if (fxmode == 4) {
		// 天顶裂口：裂口脉动
		float rift = smoothstep(0.1, 0.35, col.b - col.g) * smoothstep(0.3, 0.8, luma) + smoothstep(0.85, 0.97, luma);
		col *= 1.0 + clamp(rift, 0.0, 1.0) * (0.35 + 0.3 * sin(time_sec * 3.6));
	} else if (fxmode == 5) {
		// 试剑回廊：月光里尘埃飘落
		vec2 g = uv * vec2(70.0, 40.0) + vec2(0.0, time_sec * 1.6);
		vec2 cell = floor(g);
		vec2 fr = fract(g) - 0.5;
		float h = hash(cell);
		float mote = step(0.93, h) * smoothstep(0.12, 0.0, length(fr + vec2(sin(time_sec + h * 6.28) * 0.2, 0.0)));
		col += mote * vec3(0.8, 0.88, 1.0) * smoothstep(0.35, 0.8, luma) * 0.9;
	}

	// 凝光膜（未开放）：原画颜色和细节保留，只是被白光定住——偏冷、略去色、微微提亮；
	// 四边一圈白金细光膜，膜里悬停着缓慢浮动的白金凝光屑（世界观：鲜活原貌定格，不是灰掉）
	if (frost > 0.0) {
		float fk = clamp(frost, 0.0, 1.0);
		vec3 cool = mix(vec3(luma), col, 0.86) * vec3(0.95, 0.98, 1.03);
		col = mix(col, cool, fk);
		vec2 asp = vec2(1.7778, 1.0);
		float edge = min(min(UV.x, 1.0 - UV.x) * asp.x, min(UV.y, 1.0 - UV.y));
		float film = smoothstep(0.035, 0.0, edge) * 0.1 + smoothstep(0.005, 0.0, abs(edge - 0.02)) * 0.35;
		vec3 gold = vec3(1.0, 0.93, 0.76);
		col += gold * film * fk;
		vec2 g = UV * vec2(48.0, 27.0) + vec2(0.0, -time_sec * 0.12);
		vec2 cell = floor(g);
		float h = hash(cell);
		vec2 fr = fract(g) - 0.5 - vec2(sin(time_sec * 0.5 + h * 6.28) * 0.18, cos(time_sec * 0.4 + h * 4.0) * 0.18);
		float mote = step(0.9, h) * smoothstep(0.09, 0.0, length(fr)) * (0.6 + 0.4 * sin(time_sec * 1.3 + h * 20.0));
		col += gold * mote * 0.7 * fk;
		// 拨到锁住的章再按确认时（frost > 1）膜一下亮起，提示“被定住了”
		col += gold * max(frost - 1.0, 0.0) * 0.25;
	}

	// 左下压暗托字
	float shade = smoothstep(0.42, 1.0, uv.y) * smoothstep(0.82, 0.05, uv.x);
	col *= mix(1.0, 0.36, shade * text_shade);

	col += vec3(flash);

	col *= 1.0 - dim * 0.82;
	ALBEDO = col;
	ALPHA = opacity;
}
