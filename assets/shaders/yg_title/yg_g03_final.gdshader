// [YG-MARK] 11-08 首页换 G03：输出层，由 yg_final 改来：色散 / 冲击帧 / 闪白 / 暗角 / 颗粒，去掉 ACES 和调色。
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

void fragment() {
	vec2 uv = UV;
	vec2 p = P(UV);
	float s = dot(p - uC, uN);
	vec2 dc = uv - .5;
	float k = .0008 * dot(dc, dc) + uCA * exp(-abs(s) / 90.0) * .004;
	vec2 dir = normalize(dc + vec2(1e-5));
	vec3 c = vec3(texture(uComp, uv + dir * k).r, texture(uComp, uv).g, texture(uComp, uv - dir * k).b);
	c += texture(uBloom, uv).rgb * uBloomK;
	c *= uExpo;
	// 底图已经是定稿的颜色，不再过 ACES 和调色（原 yg_final 会把白大理石压灰）；只给高光留一段软肩
	vec3 over = max(c - vec3(.82), vec3(0.0));
	c = min(c, vec3(.82)) + (vec3(1.0) - exp(-over / .18)) * .18;
	c = pow(clamp(c, 0.0, 1.0), vec3(1.0 / 2.2));
	if (uImpact > 0.0) {
		float l2 = dot(c, vec3(.2126, .7152, .0722));
		float inv = 1.0 - smoothstep(.22, .42, l2);
		vec3 ic = mix(vec3(0.0), vec3(.96), inv);
		ic = mix(ic, vec3(1.0), exp(-abs(s) / 2.5));
		c = mix(c, ic, uImpact);
	}
	c = mix(c, vec3(1.0, .985, 1.03), uFlash);
	float v = 1.0 - smoothstep(.62, 1.15, length(dc * vec2(1.45, 1.1))) * .14;   // 暗角只压最角上：大理石要白
	c *= v;
	c += (h12(p + fract(uTime * 7.31) * vec2(311.7, 173.3)) - .5) * .022;
	c *= 1.0 - uFade;
	COLOR = vec4(max(c, vec3(0.0)), 1.0);
}
