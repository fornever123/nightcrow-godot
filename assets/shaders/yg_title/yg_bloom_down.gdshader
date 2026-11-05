// [YG-MARK] 由 YG 新增（首页「断晓 · 断光」WebGL 版移植到 Godot）。
// 泛光降采样：网页版 FS_DOWN。
// 删除方法：见 docs/YG-首页断光-删除清单.md。

shader_type canvas_item;
render_mode blend_mix, unshaded;

uniform vec2 uTexel = vec2(0.00078125, 0.00138889);
uniform float uPre = 0.0;
uniform float uThr = 1.1;
uniform sampler2D uSrc : filter_linear, repeat_disable;

void fragment() {
	vec2 uv = UV;
	vec3 c = texture(uSrc, uv).rgb * .5
			+ .125 * (texture(uSrc, uv + uTexel * vec2(-1.0, -1.0)).rgb + texture(uSrc, uv + uTexel * vec2(1.0, -1.0)).rgb
			+ texture(uSrc, uv + uTexel * vec2(-1.0, 1.0)).rgb + texture(uSrc, uv + uTexel * vec2(1.0, 1.0)).rgb);
	if (uPre > .5) {
		c = min(c, vec3(80.0));
		float br = max(c.r, max(c.g, c.b));
		float k = max(br - uThr, 0.0);
		k = k * k / (k + .6);
		c *= k / max(br, 1e-4);
	}
	COLOR = vec4(c, 1.0);
}
