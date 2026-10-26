shader_type canvas_item;
// 绝影冷峻版：被斩开的影的半身——只画刃口一侧（刃口用屏幕像素给：p0 点、dir 方向；side = 1 留刃口上面，-1 留下面）。
uniform vec2 screen_size = vec2(1280.0, 720.0);
uniform vec2 p0 = vec2(0.0);
uniform vec2 dir = vec2(1.0, 0.0);
uniform float side = 1.0;

void fragment() {
	vec2 px = SCREEN_UV * screen_size;
	vec2 n = vec2(-dir.y, dir.x);
	float d = dot(px - p0, n);   // 屏幕 y 向下：刃口上面 d < 0
	if (-d * side < 0.0) {
		discard;
	}
}
