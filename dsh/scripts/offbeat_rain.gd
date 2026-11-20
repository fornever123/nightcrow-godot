extends Control
## 屏幕空间雨：错拍试炼场的雨层（纯画，不参与玩法）。

var drops: Array = []
var wind: float = -0.34
var _time: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	randomize()
	for i in 120:
		drops.append({
			"x": randf() * 1400.0,
			"y": randf() * 760.0,
			"len": randf_range(18.0, 46.0),
			"speed": randf_range(820.0, 1500.0),
			"alpha": randf_range(0.05, 0.20),
			"w": randf_range(0.6, 1.5),
		})


func _process(delta: float) -> void:
	_time += delta
	var h := size.y
	for d in drops:
		d["y"] = float(d["y"]) + float(d["speed"]) * delta
		d["x"] = float(d["x"]) + float(d["speed"]) * wind * delta
		if float(d["y"]) > h + 40.0:
			d["y"] = -60.0
			d["x"] = randf() * (size.x + 300.0) - 150.0
		if float(d["x"]) < -200.0:
			d["x"] = size.x + 120.0
	queue_redraw()


func _draw() -> void:
	for d in drops:
		var p := Vector2(float(d["x"]), float(d["y"]))
		var q := p + Vector2(wind * float(d["len"]), float(d["len"]))
		draw_line(p, q, Color(0.72, 0.79, 0.92, float(d["alpha"])), float(d["w"]), true)
