extends Node2D
## 街灯光池与光柱。玩法上这些位置就是「光区」（延迟 −0.12、移速 ×0.78）。

var lamps: Array = []
var ground_y: float = 580.0
var _t: float = 0.0


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	for item in lamps:
		var x := float(item)
		var head_y := ground_y - 326.0
		var breath := 0.82 + 0.18 * sin(_t * 1.7 + x * 0.01)
		# 灯头光晕
		for i in 4:
			var r := 10.0 + 9.0 * float(i)
			draw_circle(Vector2(x, head_y), r, Color(1.0, 0.86, 0.58, 0.035 * breath))
		draw_circle(Vector2(x, head_y), 4.5, Color(1.0, 0.93, 0.76, 0.9))
		# 光柱（上窄下宽）
		var cone := PackedVector2Array([
			Vector2(x - 16.0, head_y + 6.0),
			Vector2(x + 16.0, head_y + 6.0),
			Vector2(x + 285.0, ground_y),
			Vector2(x - 285.0, ground_y),
		])
		draw_colored_polygon(cone, Color(1.0, 0.84, 0.55, 0.03 * breath))
		# 地面光池
		_pool(Vector2(x, ground_y), Vector2(315.0, 52.0), Color(1.0, 0.82, 0.52, 0.055 * breath))
		_pool(Vector2(x, ground_y), Vector2(190.0, 30.0), Color(1.0, 0.86, 0.60, 0.07 * breath))
		_pool(Vector2(x, ground_y), Vector2(90.0, 14.0), Color(1.0, 0.92, 0.72, 0.08 * breath))
		# 灯下的湿反光
		draw_line(Vector2(x - 120.0, ground_y + 4.0), Vector2(x + 120.0, ground_y + 4.0), Color(1.0, 0.85, 0.6, 0.10 * breath), 2.0, true)


func _pool(c: Vector2, r: Vector2, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 28:
		var a := TAU * float(i) / 28.0
		pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	draw_colored_polygon(pts, col)
