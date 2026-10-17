extends Node2D
func _draw() -> void:
	draw_rect(Rect2(-31,-65,62,131),Color("795a44"))
	draw_rect(Rect2(-27,-61,54,124),Color("ab8054"))
	draw_line(Vector2(-12,-60),Vector2(-15,62),Color("705237"),3)
	draw_line(Vector2(13,-60),Vector2(10,62),Color("ca9d6c"),3)
	for y in [-38,38]:
		draw_rect(Rect2(-33,y,66,10),Color("48444d"))
	draw_circle(Vector2(0,-3),18,Color("d1b285"))
	draw_arc(Vector2(0,-3),13,0,TAU,24,Color("93674a"),3)
	draw_circle(Vector2(0,-3),5,Color("744936"))
