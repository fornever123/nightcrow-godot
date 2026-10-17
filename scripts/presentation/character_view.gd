extends Sprite2D
const Art := preload("res://scripts/presentation/art_cache.gd")
const Trail := preload("res://scripts/presentation/trail_view.gd")
var actor: CharacterBody2D
var setup: Dictionary = {}
var clip_name: String = "idle"
var frame_index: int = 0
var clock: float = 0.0
var landing: float = 0.0
var trail: Node2D

func _ready() -> void:
	actor = get_parent().get_parent()
	setup = actor.get_meta("character", {}).get("sprite", {})
	texture_filter = TEXTURE_FILTER_NEAREST if setup.get("filter", "linear") == "nearest" else TEXTURE_FILTER_LINEAR
	actor.move_started.connect(_start)
	actor.jumped.connect(_on_jumped)
	actor.landed.connect(_on_landed)
	actor.tree_exiting.connect(_clear_trail)
	_draw_frame()

func _process(_delta: float) -> void:
	Art.warm()

func _physics_process(delta: float) -> void:
	if not actor.is_in_hitstop():
		clock += delta
		landing = maxf(0.0, landing - delta)
	var wanted := "idle"
	if actor.state == 1 and actor.current_move != null:
		wanted = actor.current_move.animation
	elif actor.is_charging():
		wanted = "attack_3"
	elif not actor.is_on_floor():
		# The jump clip already contains the rise, the air transitions, and the landing.
		# Switching to fall here would restart the clock and skip the rest of them.
		if clip_name == "jump":
			wanted = "jump"
		else:
			wanted = "fall" if actor.velocity.y > 0.0 else "jump"
	elif absf(actor.velocity.x) > 12.0:
		wanted = "run"
	elif landing > 0.0 and clip_name == "jump":
		wanted = "jump"
	elif landing > 0.0:
		wanted = "land"
	if wanted != clip_name:
		clip_name = wanted
		clock = 0.0
	_draw_frame()
	if is_instance_valid(trail):
		if actor.state == 1 and actor.current_move != null and actor.current_move.effect != "":
			trail.sync_pose(frame_index, actor.global_position + Vector2(0, actor.foot_offset), actor.facing, float(setup.animations[clip_name].get("fps",36)))
		trail.tick(delta, actor.is_in_hitstop())

func _draw_frame() -> void:
	var clip: Dictionary = setup.get("animations", {}).get(clip_name, setup.get("animations", {}).get("idle", {}))
	var frames: Array = clip.get("frames", [])
	if frames.is_empty():
		visible = false
		return
	var fps := float(clip.get("fps", 24.0))
	var time := clock
	if actor.state == 1 and actor.current_move != null:
		fps = actor.current_move.animation_fps
		time = float(actor.move_frame) / 60.0
	frame_index = int(time * fps)
	if actor.is_charging():
		frame_index = 2
	elif actor.is_in_parry():
		frame_index = 0
	elif bool(clip.get("loop", false)):
		var loop_from := int(clip.get("loopFrame", 0))
		if frame_index >= loop_from:
			var cycle := frames.size() - loop_from
			if cycle > 0:
				frame_index = loop_from + (frame_index - loop_from) % cycle
		frame_index = mini(frame_index, frames.size() - 1)
	else:
		frame_index = mini(frame_index, frames.size() - 1)
	Art.apply(self, frames[frame_index], float(setup.get("displayScale", 1.0)))
	if actor.is_in_parry():
		var pose := Vector2(1.08,0.93) if actor.is_parrying() else Vector2(0.93,1.07)
		scale *= Vector2.ONE + (pose - Vector2.ONE) * actor.squash_strength
		self_modulate = Color(0.9,0.92,1.0) if actor.is_parrying() else Color.WHITE
	elif actor.is_charging():
		self_modulate = Color(1.0,0.9,1.0)
	else:
		self_modulate = Color.WHITE

func _on_jumped(_double: bool) -> void:
	clock = 0.0
	landing = 0.0

func _on_landed() -> void:
	landing = 0.15
	# Keep the jump clock so the landing frames at the end of that clip still play.
	if clip_name != "jump":
		clock = 0.0

func _start(move: Resource, _index: int) -> void:
	clock = 0.0
	landing = 0.0
	if move.effect != "" and setup.get("effects", {}).has(move.effect):
		_clear_trail()
		trail = Node2D.new()
		trail.set_script(Trail)
		trail.setup = setup["effects"][move.effect]
		trail.display_scale = float(setup.get("displayScale", 1.0))
		actor.get_parent().add_child(trail)
		trail.global_position = actor.global_position + Vector2(0, actor.foot_offset)
		trail.scale.x = actor.facing

func _clear_trail() -> void:
	if is_instance_valid(trail):
		trail.queue_free()
	trail = null

func set_identity_color(_c: Color) -> void:
	pass
