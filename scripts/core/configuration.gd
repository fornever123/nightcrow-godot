extends RefCounted
const Move := preload("res://scripts/core/move_definition.gd")
const Timeline := preload("res://scripts/core/animation_timeline.gd")
const PATH := "res://assets/data/battle.json"
const Tuning := preload("res://scripts/core/tuning.gd")

static func read() -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return Tuning.apply("battle", value) if value is Dictionary else {}

static func character(config: Dictionary, id: String) -> Dictionary:
	for c in config.get("characters", []):
		if c.get("id", "") == id:
			return c
	return {}

## 分段变速再叠一段局部加速：断点 = 前摇 / 判定 / 接招点 / 结束（动画秒）+ 加速段起止，
## 每小段的物理帧数 = 动画时长 ÷（所在阶段速度 × 是否在加速段里）。
static func _apply_burst(m: Move, base_t: Array, speeds: Array, b0: float, b1: float, k: float) -> void:
	var ts: Array = [0.0]
	for t in base_t + [b0, b1]:
		var tc := clampf(float(t), 0.0, float(base_t[-1]))
		if not ts.has(tc):
			ts.append(tc)
	ts.sort()
	var frame_ends := PackedInt32Array()
	var anim_ends := PackedFloat64Array()
	var at_base := {}
	var acc := 0.0
	var last := 0
	for i in range(1, ts.size()):
		var t0: float = ts[i - 1]
		var t1: float = ts[i]
		var mid := (t0 + t1) * 0.5
		var seg := base_t.size() - 1
		for j in base_t.size():
			if mid < float(base_t[j]):
				seg = j
				break
		acc += (t1 - t0) / (float(speeds[seg]) * (k if mid > b0 and mid < b1 else 1.0)) * 60.0
		last = maxi(last, ceili(acc - 0.0001))
		frame_ends.append(last)
		anim_ends.append(t1)
		at_base[t1] = last
	var s_f: int = at_base.get(float(base_t[0]), 0)
	var e_f: int = maxi(s_f + 1, int(at_base.get(float(base_t[1]), s_f + 1)))
	var c_f: int = maxi(e_f, int(at_base.get(float(base_t[2]), e_f)))
	var t_f: int = maxi(e_f + 1, int(at_base.get(float(base_t[3]), c_f)))
	m.phase_timed = true
	m.startup_frames = s_f
	m.active_frames = e_f - s_f
	m.recovery_frames = t_f - e_f
	m.cancel_frame = c_f - e_f
	m.phase_frame_ends = frame_ends
	m.phase_anim_ends = anim_ends


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
		# 局部加速（11-01 冲刺斩）：只把动画第 burstFrameStart～burstFrameEnd 帧这一段放快 burstSpeed 倍，
		# 其余照常。按动画时间变速，根位移跟着动画走，总距离不变。
		var burst_speed := maxf(float(source.get("burstSpeed", 1.0)), 0.05)
		if absf(burst_speed - 1.0) > 0.0001 and source.has("burstFrameStart") and animations.has(m.animation):
			var bframes: Array = animations[m.animation].get("frames", [])
			var b0 := Timeline.ticks_before(bframes, int(source.get("burstFrameStart", 0))) / m.animation_fps
			var b1 := Timeline.ticks_before(bframes, int(source.get("burstFrameEnd", bframes.size()))) / m.animation_fps
			var speeds: Array = [startup_speed, active_speed, recovery_speed, tail_speed] if m.phase_timed else [1.0, 1.0, 1.0, 1.0]
			end = maxf(end, start)
			chain = clampf(chain, end, maxf(duration, end))
			duration = maxf(duration, chain)
			_apply_burst(m, [start, end, chain, duration], speeds, b0, b1, burst_speed)
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
		m.hitstop_first_only = bool(source.get("hitstopFirstOnly", false))
		m.air_gravity_scale = float(source.get("airGravityScale", 1.0))
		m.air_suspend_frames = maxi(0, int(source.get("airSuspendFrames", 0)))
		m.root_motion_x = animations.get(m.animation, {}).get("rootMotionX", [])
		m.root_motion_y = animations.get(m.animation, {}).get("rootMotionY", [])
		m.root_motion_scale = float(source.get("rootMotionScale", 1.0))
		var box: Dictionary = source.get("hitbox", {})
		m.hitbox = Rect2(Vector2(box.get("x", 100), box.get("y", -90)), Vector2(box.get("width", 200), box.get("height", 136)))
		# 伤害窗口 / 闪白 / 后摇移动取消（11-03 重击）：不写就是默认（整段都算伤害、不闪、走接招点规则）
		m.damage_from_frac = clampf(float(source.get("damageFromFrac", 0.0)), 0.0, 1.0)
		m.damage_to_frac = clampf(float(source.get("damageToFrac", 1.0)), 0.0, 1.0)
		m.screen_flash = clampf(float(source.get("screenFlash", 0.0)), 0.0, 1.0)
		m.move_cancel_after_active = int(source.get("moveCancelAfterActive", -1))
		# 空中版本（11-03）：空中冲刺斩上下判定 ×2、起手快、后摇短
		m.air_hitbox_height_scale = maxf(float(source.get("airHitboxHeightScale", 1.0)), 0.1)
		m.air_startup_frames = int(source.get("airStartupFrames", -1))
		m.air_recovery_frames = int(source.get("airRecoveryFrames", -1))
		m.command = &"light"
		m.is_charge = String(source.get("input", "")) == "J_HOLD"
		m.is_parry = String(source.get("input", "")) == "L"
		m.is_air = String(source.get("input", "")).begins_with("AIR_J")
		m.direction = 1 if String(source.get("input", "")) == "W+J" or String(m.id) == "air_up" or bool(source.get("upward", false)) else 0
		if m.is_charge:
			m.command = &"charge"
			m.movement_scale = clampf(float(actor.get("chargeMovementScale", m.movement_scale)), 0.0, 1.0)
			m.startup_movement_scale = m.movement_scale
			m.recovery_movement_scale = m.movement_scale
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
