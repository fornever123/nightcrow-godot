extends Sprite2D
const Art := preload("res://scripts/presentation/art_cache.gd")
const Trail := preload("res://scripts/presentation/trail_view.gd")
const Timeline := preload("res://scripts/core/animation_timeline.gd")
var actor: CharacterBody2D
var setup: Dictionary = {}
var clip_name: String = "idle"
var frame_index: int = 0
var clock: float = 0.0
var landing: float = 0.0
var trail: Node2D
var overlay: Sprite2D
var overlay_frame_index: int = -1

func _ready() -> void:
	actor = get_parent().get_parent()
	setup = actor.get_meta("character", {}).get("sprite", {})
	texture_filter = TEXTURE_FILTER_NEAREST if setup.get("filter", "linear") == "nearest" else TEXTURE_FILTER_LINEAR
	actor.move_started.connect(_start)
	actor.jumped.connect(_on_jumped)
	actor.landed.connect(_on_landed)
	actor.tree_exiting.connect(_clear_trail)
	_draw_frame.call_deferred()

func _process(_delta: float) -> void:
	Art.warm()

func _physics_process(delta: float) -> void:
	if not actor.is_in_hitstop():
		clock += delta
		landing = maxf(0.0, landing - delta)
	var wanted := "idle"
	if actor.state == actor.State.DEAD and not setup.get("animations", {}).get("death", {}).get("frames", []).is_empty():
		wanted = "death"
	elif actor.state == 1 and actor.current_move != null:
		wanted = actor.current_move.animation
	elif actor.is_charging():
		wanted = String(setup.get("chargeAnimation", "attack_3"))
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
	overlay_frame_index = -1
	if is_instance_valid(overlay):
		overlay.visible = false
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
	frame_index = Timeline.frame_at(clip, time, fps, true, actor.state != actor.State.DEAD)
	if actor.is_charging():
		frame_index = int(setup.get("chargeFrame", 2))
	elif actor.is_in_parry() and not bool(clip.get("playDuringParry", false)):
		frame_index = 0
	frame_index = clampi(frame_index, 0, frames.size() - 1)
	Art.apply(self, frames[frame_index], float(setup.get("displayScale", 1.0)))
	var overlay_time := Timeline.ticks_before(frames, frame_index) / fps if actor.is_charging() else time
	if not actor.is_charging() and actor.state != actor.State.DEAD and bool(clip.get("loop", false)):
		var total := Timeline.ticks_before(frames, frames.size())
		var before := Timeline.ticks_before(frames, clampi(int(clip.get("loopFrame", 0)), 0, frames.size() - 1))
		if time * fps >= total:
			overlay_time = (before + fposmod(time * fps - before, total - before)) / fps
	_draw_overlay(clip, overlay_time, fps)
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
	var clip: Dictionary = setup.get("animations", {}).get(move.animation, {})
	if bool(clip.get("effectsBaked", false)) or not String(clip.get("overlayEffect", "")).is_empty():
		_clear_trail()
		return
	if move.effect != "" and setup.get("effects", {}).has(move.effect):
		_clear_trail()
		trail = Node2D.new()
		trail.set_script(Trail)
		trail.setup = setup["effects"][move.effect]
		trail.display_scale = float(setup.get("displayScale", 1.0))
		actor.get_parent().add_child(trail)
		trail.global_position = actor.global_position + Vector2(0, actor.foot_offset)
		trail.scale.x = actor.facing

func _draw_overlay(clip: Dictionary, time: float, fps: float) -> void:
	overlay_frame_index = -1
	if is_instance_valid(overlay):
		overlay.visible = false
	if bool(clip.get("effectsBaked", false)):
		return
	var key := String(clip.get("overlayEffect", ""))
	var effect: Dictionary = setup.get("effects", {}).get(key, {})
	if key.is_empty() or effect.is_empty():
		return
	var speed := fps / maxf(float(clip.get("fps", 24.0)), 0.000001)
	overlay_frame_index = Timeline.frame_at(effect, time * speed, -1.0, false, false)
	if overlay_frame_index < 0:
		return
	if not is_instance_valid(overlay):
		overlay = Sprite2D.new()
		overlay.name = "ActionOverlay"
		overlay.texture_filter = texture_filter
		get_parent().add_child(overlay)
	# A sibling shares Visual's facing/squash and the actor sprite's foot origin.
	overlay.position = position
	Art.apply(overlay, effect.frames[overlay_frame_index], float(setup.get("displayScale", 1.0)))

func _clear_trail() -> void:
	if is_instance_valid(trail):
		trail.queue_free()
	trail = null

func set_identity_color(_c: Color) -> void:
	pass
