// [YG-MARK] 由 YG 新增（首页「断晓 · 断光」WebGL 版移植到 Godot）。
// 泛光升采样：网页版 FS_UP。渲染时用叠加混合（render_mode blend_add 由代码里的
// CanvasItemMaterial / 材质 blend 设置控制，这里保持 blend_add 以还原 gl.ONE,ONE）。
// 删除方法：见 docs/YG-首页断光-删除清单.md。

shader_type canvas_item;
render_mode blend_add, unshaded;

uniform vec2 uTexel = vec2(0.0015625, 0.00277778);
uniform float uK = 1.0;
uniform sampler2D uSrc : filter_linear, repeat_disable;

void fragment() {
	vec2 uv = UV;
	vec2 t = uTexel;
	vec3 c = texture(uSrc, uv).rgb * 4.0;
	c += (texture(uSrc, uv + vec2(t.x, 0.0)).rgb + texture(uSrc, uv - vec2(t.x, 0.0)).rgb
			+ texture(uSrc, uv + vec2(0.0, t.y)).rgb + texture(uSrc, uv - vec2(0.0, t.y)).rgb) * 2.0;
	c += texture(uSrc, uv + t).rgb + texture(uSrc, uv - t).rgb
			+ texture(uSrc, uv + vec2(t.x, -t.y)).rgb + texture(uSrc, uv + vec2(-t.x, t.y)).rgb;
	COLOR = vec4(c / 16.0 * uK, 1.0);
}
