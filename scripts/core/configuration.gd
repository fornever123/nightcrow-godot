extends RefCounted
const Move := preload("res://scripts/core/move_definition.gd")
const Timeline := preload("res://scripts/core/animation_timeline.gd")
const PATH := "res://assets/data/battle.json"

static func read() -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return value if value is Dictionary else {}

static func character(config: Dictionary, id: String) -> Dictionary:
	for c in config.get("characters", []):
		if c.get("id", "") == id:
			return c
	return {}

static func moves(config: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var actor := character(config, "player")
	var animations: Dictionary = actor.get("sprite", {}).get("animations", {})
	for source in config.get("moves", []):
		var m := Move.new()
		m.id = StringName(source["id"])
		m.display_name = String(source.get("name", m.id))
		m.animation = String(source.get("animation", "idle"))
		m.animation_fps = float(animations.get(m.animation, {}).get("fps", 36)) * float(source.get("animationSpeed", 1.0))
		var duration := float(source.get("duration", 0.5))
		var start := float(source.get("activeStart", 0.08))
		var end := float(source.get("activeEnd", 0.16))
		var chain := float(source.get("chainOpen", end))
		if bool(source.get("syncAnimation", false)) and animations.has(m.animation):
			var clip: Dictionary = animations[m.animation]
			var frames: Array = clip.get("frames", [])
			duration = Timeline.ticks_before(frames, frames.size()) / m.animation_fps
			start = Timeline.ticks_before(frames, int(source.get("activeFrameStart", 2))) / m.animation_fps
			end = Timeline.ticks_before(frames, int(source.get("activeFrameEnd", 12)) + 1) / m.animation_fps
			chain = Timeline.ticks_before(frames, int(source.get("chainFrame", frames.size()))) / m.animation_fps
		# 分段变速（第二轮手感）：前摇 / 判定 / 后摇到接招点 / 收招尾巴 各自一个播放速度。
		# 全局倍率在 settings 里，方便整体再调快或调慢。
		var settings: Dictionary = config.get("settings", {})
		var startup_speed := maxf(float(source.get("startupSpeed", 1.0)) * float(settings.get("startupSpeedMultiplier", 1.0)), 0.05)
		var active_speed := maxf(float(source.get("activeSpeed", 1.0)), 0.05)
		var recovery_speed := maxf(float(source.get("recoverySpeed", 1.0)) * float(settings.get("recoverySpeedMultiplier", 1.0)), 0.05)
		var tail_speed := maxf(float(source.get("tailSpeed", source.get("recoverySpeed", 1.0))) * float(settings.get("recoverySpeedMultiplier", 1.0)), 0.05)
		m.phase_timed = absf(startup_speed - 1.0) > 0.0001 or absf(active_speed - 1.0) > 0.0001 \
				or absf(recovery_speed - 1.0) > 0.0001 or absf(tail_speed - 1.0) > 0.0001
		if m.phase_timed:
			end = maxf(end, start)
			chain = clampf(chain, end, maxf(duration, end))
			duration = maxf(duration, chain)
			var s_f := maxi(0, ceili(start / startup_speed * 60.0 - 0.0001))
			var e_f := maxi(s_f + 1, s_f + ceili((end - start) / active_speed * 60.0 - 0.0001))
			var c_f := e_f + maxi(0, ceili((chain - end) / recovery_speed * 60.0 - 0.0001))
			var t_f := maxi(e_f + 1, c_f + ceili((duration - chain) / tail_speed * 60.0 - 0.0001))
			m.startup_frames = s_f
			m.active_frames = e_f - s_f
			m.recovery_frames = t_f - e_f
			m.cancel_frame = c_f - e_f
			m.phase_frame_ends = PackedInt32Array([s_f, e_f, c_f, t_f])
			m.phase_anim_ends = PackedFloat64Array([start, end, chain, duration])
		else:
			m.startup_frames = maxi(0, ceili(start * 60.0 - 0.0001))
			var end_tick := maxi(m.startup_frames + 1, ceili(end * 60.0 - 0.0001))
			m.active_frames = end_tick - m.startup_frames
			m.recovery_frames = maxi(1, ceili(duration * 60.0 - 0.0001) - end_tick)
			m.cancel_frame = maxi(0, ceili(chain * 60.0 - 0.0001) - end_tick)
		m.move_cancel_delay = int(source.get("moveCancelDelay", -1))
		m.damage = float(source.get("damage", 10))
		var x := float(source.get("knockbackX", 200))
		var y := float(source.get("launchY", 0))
		m.knockback = Vector2(x, y).length()
		m.knockback_angle = rad_to_deg(atan2(y, x))
		m.forces_launch = bool(source.get("forcesLaunch", false))
		m.launch_speed = y
		m.stun_frames = roundi(float(source.get("hitstun", 0)) * 60.0)
		m.hitstop_frames = roundi(float(source.get("hitstop", 0.05)) * 60.0 * float(config.feedback.get("hitstopMultiplier",1)))
		m.victim_hitstop_frames = roundi(float(source.get("victimHitstop", source.get("hitstop", 0.05))) * 60.0 * float(config.feedback.get("hitstopMultiplier",1)))
		m.shake_amount = float(source.get("shakeAmount", 5)) * float(config.feedback.get("shakeMultiplier",1))
		m.squash = Vector2(float(source.get("squashX",1.35)),float(source.get("squashY",0.72)))
		m.wall_damage_factor = float(source.get("wallDamageFactor", 0.5))
		m.lunge = float(source.get("lunge", 0))
		m.movement_scale = float(source.get("movementSpeedMultiplier", 0.62))
		var light := String(source.get("input", "")) == "J"
		m.startup_movement_scale = m.movement_scale * (1.0 if light else 0.6)
		m.recovery_movement_scale = m.movement_scale * (1.0 if light else 0.75)
		m.effect = String(source.get("effect", ""))
		m.dash_distance = float(source.get("dashDistance", 0.0))
		m.movement_timeline = source.get("movementTimeline", [])
		m.air_gravity_scale = float(source.get("airGravityScale", 1.0))
		m.air_suspend_frames = maxi(0, int(source.get("airSuspendFrames", 0)))
		m.root_motion_x = animations.get(m.animation, {}).get("rootMotionX", [])
		m.root_motion_scale = float(source.get("rootMotionScale", 1.0))
		var box: Dictionary = source.get("hitbox", {})
		m.hitbox = Rect2(Vector2(box.get("x", 100), box.get("y", -90)), Vector2(box.get("width", 200), box.get("height", 136)))
		m.command = &"light"
		m.is_charge = String(source.get("input", "")) == "J_HOLD"
		m.is_parry = String(source.get("input", "")) == "L"
		m.is_air = String(source.get("input", "")).begins_with("AIR_J")
		m.direction = 1 if String(source.get("input", "")) == "W+J" or String(m.id) == "air_up" or bool(source.get("upward", false)) else 0
		if m.is_charge:
			m.command = &"charge"
		elif m.is_parry:
			m.command = &"parry"
		if String(source.get("input", "")) == "K":
			m.command = &"ranged"
		elif String(source.get("input", "")) == "SHIFT+J":
			m.command = &"dash"
		elif m.is_air:
			m.command = &"air_light"
		elif String(m.id).begins_with("guard_hit_") or String(m.id).begins_with("parry_react_"):
			m.command = &"guard_reaction"
			m.is_parry = true
		m.min_charge_frames = roundi(float(source.get("minHold", 0.36)) * 60.0)
		m.max_charge_frames = roundi(float(source.get("maxHold", 0.8)) * 60.0)
		m.charge_damage_bonus = float(source.get("chargeDamageBonus", 1.9))
		m.charge_knockback_bonus = float(source.get("chargeKnockbackBonus", 1.7))
		m.charge_hitstop_bonus = roundi(float(source.get("chargeHitstopBonus",0.1)) * 60.0 * float(config.feedback.get("hitstopMultiplier",1)))
		result[String(m.id)] = m
	return result
