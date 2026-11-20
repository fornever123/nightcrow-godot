extends Control
## 屏幕暗角。

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var w := size.x
	var h := size.y
	var layers := 9
	for i in layers:
		var k := float(i) / float(layers)
		var band := 26.0 + k * 56.0
		var a := 0.030 * (1.0 - k * 0.55)
		var col := Color(0.0, 0.005, 0.02, a)
		draw_rect(Rect2(0, 0, w, band), col)
		draw_rect(Rect2(0, h - band, w, band), col)
		draw_rect(Rect2(0, 0, band, h), col)
		draw_rect(Rect2(w - band, 0, band, h), col)
	draw_rect(Rect2(0, h - 120.0, w, 120.0), Color(0.04, 0.06, 0.10, 0.10))
	draw_rect(Rect2(0, h - 46.0, w, 46.0), Color(0.03, 0.04, 0.08, 0.16))
	# 全局压一层冷暗调，贴近雨夜的影调
	draw_rect(Rect2(0, 0, w, h), Color(0.02, 0.03, 0.07, 0.10))
