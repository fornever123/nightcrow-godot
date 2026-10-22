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
## 落地动画的播放倍率：普通落地快放（很快就能跑），高处落下 / 下砸按原速播完整落地。
var landing_speed: float = 1.0
var landing_heavy: bool = false
var trail: Node2D
var overlay: Sprite2D
var overlay_frame_index: int = -1
var stance_clip: String = ""
var stance_clock: float = 0.0
var idle_clock: float = 0.0
var stance_drawn: bool = true
var airborne_seen: bool = false
var stance_initialized: bool = false
var _ult_tail: int = -1   ## 大招最后停在收刀动画第几帧（大招结束后从这里接着收刀）

func _ready() -> void:
	actor = get_parent().get_parent()
	setup = actor.get_meta("character", {}).get("sprite", {})
	texture_filter = TEXTURE_FILTER_NEAREST if setup.get("filter", "linear") == "nearest" else TEXTURE_FILTER_LINEAR
	actor.move_started.connect(_start)
	actor.jumped.connect(_on_jumped)
	actor.landed.connect(_on_landed)
	actor.tree_exiting.connect(_clear_trail)
	if bool(setup.get("drawSheathe", {}).get("enabled", false)):
		stance_clip = String(setup.drawSheathe.get("drawAnimation", "draw"))
	_draw_frame.call_deferred()

func _process(_delta: float) -> void:
	Art.warm()

func _physics_process(delta: float) -> void:
	if not actor.is_on_floor() and int(actor.air_frames) > int(actor.coyote_frames):
		airborne_seen = true
	if actor.is_on_floor() and not stance_initialized:
		stance_initialized = true
		if bool(setup.get("drawSheathe", {}).get("enabled", false)):
			stance_clip = String(setup.drawSheathe.get("drawAnimation", "draw"))
			stance_clock = 0.0
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
	elif actor.has_method("is_guarding") and actor.is_guarding():
		wanted = actor.guard_animation
	elif not actor.is_on_floor():
		# Legacy clips contain a full jump. Split clips follow actual velocity.
		if clip_name == "jump" and _full_jump_sequence():
			wanted = "jump"
		else:
			wanted = "fall" if actor.velocity.y > 0.0 else "jump"
	elif not String(actor.get("locomotion_animation")).is_empty() and actor.get("locomotion_animation") != null:
		wanted = actor.locomotion_animation
	elif landing > 0.0 and not _full_jump_sequence():
		wanted = "land"
	elif absf(actor.velocity.x) > 12.0:
		wanted = "run"
	elif landing > 0.0 and clip_name == "jump":
		wanted = "jump"
	elif landing > 0.0:
		wanted = "land"
	if wanted == "land" and bool(setup.get("locomotion", {}).get("enabled", false)):
		var land_clip: Dictionary = setup.get("animations", {}).get("land", {})
		var elapsed := _clip_duration(land_clip) / landing_speed - landing
		var cancel_key := "heavyLandingCancelFrame" if landing_heavy else "landingCancelFrame"
		var cancel_index := int(setup.locomotion.get(cancel_key, setup.locomotion.get("landingCancelFrame", land_clip.get("frames", []).size())))
		var cancel_time := Timeline.ticks_before(land_clip.get("frames", []), cancel_index) / maxf(float(land_clip.get("fps", 24)) * landing_speed, 0.001)
		if absf(actor.velocity.x) > 12.0 and elapsed >= cancel_time:
			landing = 0.0
			wanted = "run"
	# 大招：分镜自己定姿势（player.ult_clip / ult_pose）；结束后从收刀那一帧接着播完收刀
	var ult_clip := _ult_clip()
	if not ult_clip.is_empty():
		wanted = ult_clip
		_ult_tail = int(actor.ult_pose) if ult_clip == String(setup.get("drawSheathe", {}).get("sheatheAnimation", "sheathe")) else -1
	else:
		if _ult_tail >= 0 and wanted == "idle" and bool(setup.get("drawSheathe", {}).get("enabled", false)):
			var sk := String(setup.drawSheathe.get("sheatheAnimation", "sheathe"))
			var sc: Dictionary = setup.get("animations", {}).get(sk, {})
			stance_clip = sk
			stance_clock = Timeline.ticks_before(sc.get("frames", []), clampi(_ult_tail, 0, sc.get("frames", []).size())) / maxf(float(sc.get("fps", 24)), 0.001)
			stance_drawn = false
			idle_clock = 0.0
		_ult_tail = -1
		wanted = _stance_animation(wanted, delta)
	if wanted != clip_name:
		clip_name = wanted
		clock = 0.0
	_draw_frame()
	if is_instance_valid(trail):
		if actor.state == 1 and actor.current_move != null and actor.current_move.effect != "" and ult_clip.is_empty():
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
		# 分段变速：前摇/后摇各自的播放速度由招式时间轴换算（没配就是 move_frame/60）
		time = actor.current_move.anim_seconds(float(actor.move_frame))
	elif clip_name == "land":
		fps *= landing_speed
	elif actor.has_method("is_guarding") and actor.is_guarding() and clip_name == actor.guard_animation:
		time = actor.guard_clock
	elif actor.get("locomotion_animation") == clip_name and not clip_name.is_empty():
		time = actor.locomotion_clock
	elif not stance_clip.is_empty() and clip_name == stance_clip:
		time = stance_clock
	frame_index = Timeline.frame_at(clip, time, fps, true, actor.state != actor.State.DEAD)
	if actor.is_charging():
		frame_index = int(setup.get("chargeFrame", 2))
	elif actor.is_in_parry() and not bool(clip.get("playDuringParry", false)):
		frame_index = 0
	var ult_pose := int(actor.get("ult_pose")) if actor.get("ult_pose") != null else -1
	if ult_pose >= 0 and clip_name == _ult_clip():
		frame_index = ult_pose
		time = Timeline.ticks_before(frames, clampi(ult_pose, 0, frames.size())) / maxf(fps, 0.001)
	frame_index = clampi(frame_index, 0, frames.size() - 1)
	Art.apply(self, frames[frame_index], float(setup.get("displayScale", 1.0)))
	# Turn clips already turn the body in their pixels. Cancel the parent flip.
	if bool(clip.get("authoredTurn", false)):
		scale.x *= float(actor.facing)
	else:
		scale.x *= float(clip.get("sourceFacing", 1))
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
	airborne_seen = true
	clock = 0.0
	landing = 0.0
	if not _full_jump_sequence():
		clip_name = "jump"

func _full_jump_sequence() -> bool:
	return bool(setup.get("animations", {}).get("jump", {}).get("fullSequence", true))

func _on_landed() -> void:
	if bool(setup.get("locomotion", {}).get("enabled", false)) and not airborne_seen:
		return
	airborne_seen = false
	landing_heavy = bool(actor.get("last_landing_heavy"))
	landing_speed = 1.0 if landing_heavy else maxf(float(setup.get("locomotion", {}).get("lightLandingSpeed", 1.0)), 0.05)
	landing = _clip_duration(setup.get("animations", {}).get("land", {})) / landing_speed if bool(setup.get("locomotion", {}).get("enabled", false)) else 0.15
	# Keep the jump clock so the landing frames at the end of that clip still play.
	if clip_name != "jump" or not _full_jump_sequence():
		clock = 0.0

func _start(move: Resource, _index: int) -> void:
	clock = 0.0
	landing = 0.0
	stance_clip = ""
	idle_clock = 0.0
	stance_drawn = true
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

func _ult_clip() -> String:
	var c: Variant = actor.get("ult_clip")
	return String(c) if c != null else ""

func reset_presentation() -> void:
	_clear_trail()
	clock = 0.0
	landing = 0.0
	stance_clip = ""
	stance_clock = 0.0
	idle_clock = 0.0
	stance_drawn = true
	stance_initialized = false
	airborne_seen = false
	_ult_tail = -1

func _clip_duration(clip: Dictionary) -> float:
	return Timeline.ticks_before(clip.get("frames", []), clip.get("frames", []).size()) / maxf(float(clip.get("fps", 24)), 0.001)

func _stance_animation(wanted: String, delta: float) -> String:
	var options: Dictionary = setup.get("drawSheathe", {})
	if not bool(options.get("enabled", false)):
		return wanted
	if wanted != "idle":
		stance_clip = ""
		stance_clock = 0.0
		idle_clock = 0.0
		stance_drawn = true
		return wanted
	if not actor.is_in_hitstop():
		idle_clock += delta
		stance_clock += delta
	var draw_key := String(options.get("drawAnimation", "draw"))
	var sheathe_key := String(options.get("sheatheAnimation", "sheathe"))
	if stance_clip == draw_key:
		if stance_clock < _clip_duration(setup.get("animations", {}).get(draw_key, {})):
			return draw_key
		stance_clip = ""
		stance_drawn = true
		idle_clock = 0.0
	if stance_clip == sheathe_key:
		stance_drawn = false
		return sheathe_key
	if stance_drawn and idle_clock >= float(options.get("idleDelay", 4.0)):
		stance_clip = sheathe_key
		stance_clock = 0.0
		return sheathe_key
	return wanted
