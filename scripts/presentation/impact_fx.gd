extends Node2D
## C-drive impact timing, drawn locally without importing its old character or scenery art.
const Feel := preload("res://scripts/core/feel_scale.gd")
const HIT_LAYERS: Array[Dictionary] = [
	{"name":"flash", "delay":0.00, "life":0.09},
	{"name":"core", "delay":0.00, "life":0.30},
	{"name":"ring", "delay":0.02, "life":0.28},
	{"name":"arc", "delay":0.03, "life":0.24},
	{"name":"spark", "delay":0.05, "life":0.22},
	{"name":"ember", "delay":0.09, "life":0.26},
]
var enabled: bool = true
var damage_numbers_enabled: bool = true
var max_effects: int = 64
var last_hit_plan: Array[Dictionary] = []
var last_kind: String = ""
var text_sequence: int = 0
var font: SystemFont

func _ready() -> void:
	z_index = 20
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC"])

func _layer(point: Vector2, kind: String, strength: float, delay: float, life: float,
		dir := Vector2.RIGHT, tint := Color("dfc9ff")) -> void:
	if not enabled or get_child_count() >= max_effects:
		return
	var effect := Burst.new()
	effect.kind = kind
	effect.strength = clampf(strength,0,1)
	effect.delay = delay
	effect.life = life
	effect.direction = dir.normalized() if dir.length_squared() > 0 else Vector2.RIGHT
	effect.tint = tint
	add_child(effect)
	effect.global_position = point

func spawn_hit(point: Vector2, strength: float, up: bool = false) -> void:
	last_kind = "hit"
	last_hit_plan.clear()
	if not enabled:
		return
	for layer in HIT_LAYERS:
		last_hit_plan.append(layer.duplicate())
		_layer(point,layer.name,strength,layer.delay,layer.life,Vector2.UP if up else Vector2.RIGHT)

func spawn_parry(point: Vector2, dir: Vector2) -> void:
	last_kind = "parry"
	_layer(point,"flash",0.35,0,0.07,dir,Color("d9ebff"))
	_layer(point,"ring",0.35,0.01,0.20,dir,Color("d9ebff"))
	_layer(point,"spark",0.4,0.03,0.20,dir,Color("d9ebff"))

func spawn_wall_slam(point: Vector2, dir: Vector2, strength: float) -> void:
	last_kind = "wall"
	_layer(point,"core",strength,0,0.20,dir,Color("ffc88f"))
	_layer(point,"ring",strength,0.01,0.25,dir,Color("ffc88f"))
	_layer(point,"spark",strength,0.02,0.28,dir,Color("ffc88f"))

func spawn_dust(point: Vector2, strength: float = 0.45) -> void:
	_layer(point,"dust",strength,0,0.22,Vector2.RIGHT,Color("b8aac9"))

func spawn_text(point: Vector2, text: String, amount: float = 0, wall: bool = false) -> void:
	if not damage_numbers_enabled or get_child_count() >= max_effects:
		return
	text_sequence += 1
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font",font)
	label.add_theme_font_size_override("font_size",int(clampf(18+amount*0.35,18,34)))
	label.add_theme_color_override("font_color",Color("ffc88f") if wall else Color("f4eaff"))
	label.add_theme_color_override("font_outline_color",Color("211b2d"))
	label.add_theme_constant_override("outline_size",3)
	label.z_index = 30
	add_child(label)
	label.global_position = point + Vector2(-10,-30-float(text_sequence%3)*15)
	var tween := label.create_tween().set_parallel(true)
	tween.tween_property(label,"position:y",label.position.y-36,0.65).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label,"modulate:a",0.0,0.42).set_delay(0.23)
	tween.chain().tween_callback(label.queue_free)

func clear() -> void:
	for node in get_children():
		remove_child(node)
		node.queue_free()
	last_hit_plan.clear()
	last_kind = ""
	text_sequence = 0

class Burst extends Node2D:
	var kind: String = ""
	var strength: float = 0.5
	var delay: float = 0
	var life: float = 0.2
	var age: float = 0
	var direction := Vector2.RIGHT
	var tint := Color("dfc9ff")

	func _process(delta: float) -> void:
		age += delta
		if age >= delay+life:
			queue_free()
		else:
			queue_redraw()

	func _draw() -> void:
		if age < delay:
			return
		var t := clampf((age-delay)/life,0,1)
		var alpha := (1.0-t)*(1.0-t)
		var color := Color(tint,alpha)
		var radius := 12.0+strength*18.0
		match kind:
			"flash":
				_star(radius*(0.7+t*0.5),Color(1,1,1,alpha),direction.angle())
			"core":
				_star(radius*(0.5+sqrt(t)*0.7),color,direction.angle()+0.2)
			"ring":
				draw_arc(Vector2.ZERO,6+(radius+8)*sqrt(t),0,TAU,40,color,1.5)
			"arc":
				draw_arc(Vector2.ZERO,radius*(0.8+sqrt(t)),direction.angle()-0.9,direction.angle()+0.8,20,color,2.0)
			"spark", "ember":
				var count := 4 if kind == "spark" else 3
				for i in count:
					var angle := direction.angle()+float(i)*TAU/float(count)+0.4
					var axis := Vector2.from_angle(angle)
					var pos := axis*(8+t*(32+strength*28))
					if kind == "ember":
						pos.y += t*t*18
					var length := (7.0 if kind == "spark" else 3.0)*(1.0-t)
					draw_line(pos-axis*length,pos+axis*length,color,1.5)
			"dust":
				draw_set_transform(Vector2.ZERO,0,Vector2(1.0,0.24))
				draw_arc(Vector2.ZERO,8+sqrt(t)*30,PI,TAU,24,Color(tint,alpha*0.45),2.0)

	func _star(radius: float, color: Color, angle: float) -> void:
		var points := PackedVector2Array()
		for i in 8:
			var r := radius if i%2 == 0 else radius*0.18
			points.append(Vector2.from_angle(angle+float(i)*TAU/8)*r)
		draw_colored_polygon(points,color)
