// [YG-MARK] 由 YG 新增（首页「断晓 · 断光」WebGL 版移植到 Godot）。
// 粒子：悬珠 / 雨 / 火星 / 光片。来源：网页版 VS_PART + FS_PART。
// 数据通道（Godot 用 MultiMesh 实例数据代替网页版的顶点属性）：
//   INSTANCE_CUSTOM = (x, y, size, alpha)
//   COLOR           = (seed, kind, 0, 0)
//   实例变换原点     = (vx, vy)   —— 只用来把速度传进着色器，位置写在 INSTANCE_CUSTOM 里
// 删除方法：见 docs/YG-首页断光-删除清单.md。

shader_type canvas_item;
render_mode blend_add, unshaded;

uniform vec2 uRes = vec2(1280.0, 720.0);
uniform vec2 uPar = vec2(0.0);
uniform vec2 uSun = vec2(435.0, -302.0);
uniform vec2 uC = vec2(640.0, 302.0);
uniform vec2 uN = vec2(-0.179, 0.984);
uniform float uSunR = 194.0;
uniform float uTime = 0.0;
uniform float uMode = 0.0;
uniform float uDawn = 0.0;
uniform float uStreak = .022;
uniform vec4 uBox = vec4(0.0);

varying vec2 vQ;
varying vec3 vCol;
varying float vA;
varying float vType;

void vertex() {
	vec2 c = VERTEX * 2.0;
	vec4 cs = INSTANCE_CUSTOM;
	vec4 ic = COLOR;
	vec2 pos = cs.xy;
	float size = cs.z;
	float alpha = cs.w;
	float seed = ic.r;
	float kind = ic.g;
	vec2 avel = MODEL_MATRIX[3].xy;

	float sp = length(avel);
	vec2 dir = sp > .001 ? avel / sp : vec2(0.0, 1.0);
	vec2 perp = vec2(-dir.y, dir.x);
	vec2 hl = vec2(1.0);
	float type = 0.0;
	vec3 col = vec3(1.0);
	float rot = 0.0;

	if (uMode < .5) {
		float depth = clamp((size - .8) / 12.0, 0.0, 1.0);
		pos += uPar * (.3 + depth * 1.6);
		float sb = max(dot(pos - uC, uN), 0.0);
		// [YG-MARK] 11-05 更高级：冻住的悬珠只留一部分，集中在中间光柱里、往两边变稀，分三层远近
		float shaft = mix(.2, 1.0, exp(-pow((pos.x - uC.x) / (uRes.x * .28), 2.0)));
		if (size > 6.0 && sp < 30.0) {
			// 前景：少量大的虚焦光斑
			type = 3.0;
			hl = vec2(size * 1.9);
			col = vec3(1.0, .97, .92) * .085 * shaft * max(uDawn, .18);
		} else if (size > 6.0) {
			type = 3.0;
			hl = vec2(size * .95);
			col *= vec3(.52, .64, .92) * .16;
		} else if (sp < 30.0) {
			// 冻在光里的水珠
			float bs = size * .62;
			float ds = length(pos - uSun);
			float lit = .24 + 2.8 * exp(-ds / (uSunR * 1.25)) + 1.45 * exp(-abs(dot(pos - uC, uN)) / (uRes.y * .08));
			col = vec3(1.0, .92, .79) * lit * max(uDawn, .18) * 1.38 + vec3(.08, .075, .07);
			float tq = step(fract(seed * 3.17), .15) * pow(max(0.0, sin(uTime * (.35 + fract(seed * 5.3) * .3) + seed * 9.0)), 45.0);
			pos.y += tq * bs * 1.8;
			if (bs > 2.05) {
				// 中景：清楚的折射水珠，靠近刀口的映一点紫
				type = 5.0;
				hl = vec2(bs * 1.18, bs * 1.58) * step(fract(seed * 7.31), .62);
				vec2 bc = vec2((uBox.x + uBox.y) * .5, (uBox.z + uBox.w) * .5);
				col *= (1.45 + 1.35 * exp(-length(pos - bc) / (uRes.y * .24))) * shaft;
				col = mix(col, col.g * vec3(.78, .66, 1.12), .4 * exp(-abs(dot(pos - uC, uN)) / (uRes.y * .1)));
			} else {
				// 远景：微尘，只留四成多
				type = 0.0;
				hl = vec2(bs * 1.75 + .95) * step(fract(seed * 7.31), .42);
				// [YG-MARK] 11-05 改好看：小的是远处的，更暗，拉出远近
				col *= .72 * mix(.42, 1.0, smoothstep(.85, 2.1, size)) * shaft;
			}
		} else {
			// 落下来的雨（开场也走这段，和斩完之后一样）
			float sbv = max(-sb, 0.0);
			float suv = dot(pos - uC, vec2(uN.y, -uN.x));
			float deep_fade = mix(.28, 1.0, exp(-sbv / (uRes.y * .46)));
			float menu_calm = 1.0 - .58 * exp(-pow(suv / (uRes.y * .22), 2.0)) * smoothstep(uRes.y * .08, uRes.y * .22, sbv);   // 开场雨（§5 不动）
			float lit = (.42 + 2.1 * exp(-sbv / (uRes.y * .11)) + .55 * exp(-length(pos - uC) / (uSunR * 1.5))) * deep_fade * menu_calm;
			vec3 tint = mix(vec3(.52, .64, .92), vec3(.68, .58, .98), exp(-sbv / (uRes.y * .12)) * clamp(fract(seed * 3.7), 0.0, 1.0));
			col = tint * lit * .78;
			type = 6.0;
			float nd = clamp((size - .85) / 2.7, 0.0, 1.0);
			float len = max(size * 8.5 + 16.0, sp * uStreak * 1.65) * mix(.68, 1.48, nd * nd);
			float w = mix(.58, 1.18, nd * nd);
			hl = vec2(w, len * .5);
			pos -= dir * len * .5;
			col *= mix(.32, 1.45, pow(nd, 1.3)) * (1.0 + 1.1 * step(fract(seed * 13.7), .035));
		}
	} else if (uMode < 1.5) {
		float depth = clamp((size - .8) / 12.0, 0.0, 1.0);
		pos += uPar * (.25 + depth * 1.4);
		float sb = abs(dot(pos - uC, uN));
		float su = dot(pos - uC, vec2(uN.y, -uN.x));
		float seam_fade = smoothstep(0.0, uRes.y * .042, sb);
		float deep_fade = mix(.28, 1.0, exp(-sb / (uRes.y * .46)));
		float menu_calm = 1.0 - .86 * exp(-pow(su / (uRes.y * .27), 2.0)) * smoothstep(uRes.y * .06, uRes.y * .2, sb);   // [YG-MARK] 11-05 更高级：菜单后面留安静区
		float lit = (.42 + 2.1 * exp(-sb / (uRes.y * .11)) + .55 * exp(-length(pos - uC) / (uSunR * 1.5))) * seam_fade * deep_fade * menu_calm;
		vec3 tint = mix(vec3(.52, .64, .92), vec3(.68, .58, .98), exp(-sb / (uRes.y * .12)) * clamp(fract(seed * 3.7), 0.0, 1.0));
		col = tint * lit * .78;
		if (size > 6.0) {
			type = 3.0;
			hl = vec2(size * .95);
			col *= .16;
		} else if (sp > 30.0) {
			type = 6.0;
			float nd = clamp((size - .85) / 2.7, 0.0, 1.0);
			float len = max(size * 8.5 + 16.0, sp * uStreak * 1.65) * mix(.68, 1.48, nd * nd);
			float w = mix(.58, 1.18, nd * nd);
			hl = vec2(w, len * .5);
			pos -= dir * len * .5;
			col *= mix(.32, 1.45, pow(nd, 1.3)) * (1.0 + 1.1 * step(fract(seed * 13.7), .035));
		} else {
			type = 0.0;
			hl = vec2(size * 1.8 + 1.0);
			col *= .45;
		}
	} else {
		if (kind < .5) {
			type = 1.0;
			float len = max(4.0, sp * .03);
			hl = vec2(size * .5 + .6, len * .5);
			pos -= dir * len * .5;
			col = mix(vec3(.85, .84, .9), vec3(3.6, 3.55, 3.6), alpha * alpha) * 2.0 * alpha;
		} else if (kind < 2.5) {
			type = 2.0;
			hl = vec2(size);
			rot = seed;
			col = (kind < 1.5 ? vec3(1.7, 1.66, 1.6) : vec3(.8, .8, .84)) * alpha * 1.3;
		} else {
			type = 0.0;
			hl = vec2(size * 2.4 + 1.0);
			col = vec3(.95, .93, .98) * alpha * 1.3;
		}
	}

	vec2 off;
	if (type > 1.5 && type < 2.5) {
		mat2 R = mat2(vec2(cos(rot), sin(rot)), vec2(-sin(rot), cos(rot)));
		off = R * (c * hl * vec2(.32, 1.0));
	} else if ((type > .5 && type < 1.5) || type > 5.5) {
		off = perp * c.x * hl.x + dir * c.y * hl.y;
	} else {
		off = c * hl;
	}
	vec2 w = pos + off;
	VERTEX = w - avel;
	vQ = c;
	vCol = col;
	vA = uMode < 1.5 ? alpha : 1.0;
	vType = type;
}

void fragment() {
	float a;
	float r = length(vQ);
	if (vType < 0.5) {
		a = exp(-r * r * 16.0) + exp(-r * r * 3.6) * .16;
		a *= smoothstep(1.0, .8, r);
	} else if (vType < 1.5) {
		float t = (vQ.y + 1.0) * .5;
		a = exp(-vQ.x * vQ.x * 8.5) * mix(.04, 1.0, t * t) * smoothstep(1.0, .84, vQ.y);
	} else if (vType > 5.5) {
		float t = (vQ.y + 1.0) * .5;
		float core = exp(-vQ.x * vQ.x * 26.0);
		float halo = exp(-vQ.x * vQ.x * 4.2) * .16;
		float trail = pow(t, 2.1) * smoothstep(1.0, .88, t);
		float head = exp(-vQ.x * vQ.x * 18.0 - (t - .88) * (t - .88) * 220.0) * 1.25;
		a = (core * .85 + halo) * trail + head;
	} else if (vType > 1.5 && vType < 2.5) {
		float e = (1.0 - vQ.y) * .5 - abs(vQ.x);
		a = smoothstep(0.0, .1, e) * (.5 + .5 * (1.0 - vQ.y) * .5) + exp(-r * r * 2.0) * .15;
	} else if (vType > 2.5 && vType < 3.5) {
		a = smoothstep(1.0, .72, r) * (.42 + .4 * smoothstep(.45, .92, r));
	} else if (vType > 4.5 && vType < 5.5) {
		float body = smoothstep(1.0, .82, r);
		a = body * .08 + smoothstep(.62, .93, r) * body * .3
				+ exp(-(vQ.x * vQ.x * 5.0 + (vQ.y - .55) * (vQ.y - .55) * 28.0)) * .9
				+ exp(-dot(vQ - vec2(-.34, -0.42), vQ - vec2(-.34, -0.42)) * 70.0) * 1.5;
	} else {
		a = exp(-vQ.x * vQ.x * 3.4) * exp(-vQ.y * vQ.y * 2.6)
				+ exp(-dot(vQ - vec2(0.0, .45), vQ - vec2(0.0, .45)) * 14.0) * .6;
	}
	COLOR = vec4(vCol * a * vA, 1.0);
}
