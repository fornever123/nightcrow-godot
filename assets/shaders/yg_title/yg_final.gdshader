// [YG-MARK] 由 YG 新增（首页「断晓 · 断光」WebGL 版移植到 Godot）。
// 输出：色散 / ACES / 冲击帧 / 闪白 / 暗角 / 颗粒。来源：网页版 FS_FINAL。
// 删除方法：见 docs/YG-首页断光-删除清单.md。

shader_type canvas_item;
render_mode blend_mix, unshaded;

#include "res://assets/shaders/yg_title/yg_noise.gdshaderinc"

uniform vec2 uRes = vec2(1280.0, 720.0);
uniform float uTime = 0.0;
uniform vec2 uC = vec2(640.0, 302.0);
uniform vec2 uN = vec2(-0.179, 0.984);
uniform float uBloomK = .15;
uniform float uExpo = 1.0;
uniform float uImpact = 0.0;
uniform float uFlash = 0.0;
uniform float uFade = 0.0;
uniform float uCA = 0.0;
uniform sampler2D uComp : filter_linear, repeat_disable;
uniform sampler2D uBloom : filter_linear, repeat_disable;

vec2 P(vec2 uv) { return uv * uRes; }

vec3 aces(vec3 x) {
	return clamp((x * (2.51 * x + .03)) / (x * (2.43 * x + .59) + .14), 0.0, 1.0);
}

void fragment() {
	vec2 uv = UV;
	vec2 p = P(UV);
	float s = dot(p - uC, uN);
	vec2 dc = uv - .5;
	float k = .0035 * dot(dc, dc) + uCA * exp(-abs(s) / 90.0) * .004;
	vec2 dir = normalize(dc + vec2(1e-5));
	vec3 c = vec3(texture(uComp, uv + dir * k).r, texture(uComp, uv).g, texture(uComp, uv - dir * k).b);
	c += texture(uBloom, uv).rgb * uBloomK;
	c *= uExpo;
	c = aces(c);
	float l = dot(c, vec3(.2126, .7152, .0722));
	// [YG-MARK] 11-05 更高级：一套颜色——刀口以下去饱和成墨蓝黑（贴着刀口的紫光不动），上面偏冷银；加一点 S 曲线对比
	float below = smoothstep(10.0, 70.0, s);
	c = mix(c, vec3(l) * vec3(.84, .92, 1.1), .6 * below);
	c = mix(c, vec3(l) * vec3(.97, .99, 1.03), .35 * (1.0 - below));
	c = clamp(c, 0.0, 1.0);
	c = mix(c, c * c * (3.0 - 2.0 * c), .45);
	c *= mix(vec3(.93, .97, 1.08), vec3(1.03, 1.0, .97), smoothstep(.22, .8, l));
	c = pow(c, vec3(1.0 / 2.2));
	if (uImpact > 0.0) {
		float l2 = dot(c, vec3(.2126, .7152, .0722));
		float inv = 1.0 - smoothstep(.22, .42, l2);
		vec3 ic = mix(vec3(0.0), vec3(.96), inv);
		ic = mix(ic, vec3(1.0), exp(-abs(s) / 2.5));
		c = mix(c, ic, uImpact);
	}
	c = mix(c, vec3(1.0, .985, 1.03), uFlash);
	float v = 1.0 - smoothstep(.28, 1.05, length(dc * vec2(1.45, 1.1))) * .86;   // [YG-MARK] 11-05 更高级：暗角加重
	c *= v;
	c += (h12(p + fract(uTime * 7.31) * vec2(311.7, 173.3)) - .5) * .045;
	c *= 1.0 - uFade;
	COLOR = vec4(max(c, vec3(0.0)), 1.0);
}
