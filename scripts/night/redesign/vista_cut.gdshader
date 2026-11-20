shader_type canvas_item;
// 影街 · 远景开口（11-19 到 8 分，玩法线确认方案 A）：1-1A 世界 x 3432～4347 三层以上没有平台，
// 楼只画到二层栏杆，上面挖掉，露出后面的夜空、远城和母钟楼（far.png 里那座 + 塔后天光）。
// 两端三层平台的画面不能抹（世界 2467～3431 y106.7、4347～4640 y88），所以 x 边界只往里羽化。

uniform float cut_x0 = 3432.0;
uniform float cut_x1 = 4347.0;
uniform float cut_y = 222.0;       // 世界 y：这条线以上挖掉
uniform float feather_x = 10.0;
uniform float feather_y = 6.0;
uniform float on = 1.0;
uniform float keep_inside = 0.0;   // 1 = 反过来：只留开口里的（给开口后面的母钟楼用，免得从别处楼缝漏出来）

varying vec2 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec4 c = COLOR;    // Godot 4：片元里 COLOR 进来已是 贴图 × modulate，别再乘一次贴图
	float in_x = smoothstep(cut_x0, cut_x0 + feather_x, world.x) * (1.0 - smoothstep(cut_x1 - feather_x, cut_x1, world.x));
	float in_y = 1.0 - smoothstep(cut_y - feather_y, cut_y, world.y);
	c.a *= mix(1.0 - on * in_x * in_y, in_x, keep_inside);
	COLOR = c;
}
