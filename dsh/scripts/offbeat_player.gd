extends Node2D
## 「错拍」主角（DSH 线自制，不依赖 scripts/gameplay/player.gd）。
##
## 设计：
##   · position = 脚底；物理手算（场地只有平地，不需要碰撞体）。
##   · 招式时间轴与判定盒直接读 battle.json（Config.moves），和原版手感同源。
##   · 序列帧用 Art.apply 播放（idle / run / jump / fall / attack_1~3 / dash_* / death）。
##   · 主角永远在「现在」，没有延迟；延迟只作用于敌人。

signal damaged(amount: float)
signal died()
signal attack_started(index: int)
signal attack_ended(index: int, hit_any: bool)

const Config := preload("res://scripts/core/configuration.gd")
const Art := preload("res://scripts/presentation/art_cache.gd")

enum Mode { MOVE, ATTACK, DASH, HURT, DEAD }

var trial: Node = null

var config: Dictionary = {}
var moves: Dictionary = {}
var sprite_setup: Dictionary = {}
var display_scale: float = 1.0
var settings: Dictionary = {}

var sprite: Sprite2D
var clips: Dictionary = {}
var clip: String = "idle"
var clip_t: float = 0.0

var facing: int = 1
var max_hp: float = 100.0
var hp: float = 100.0
var vel: Vector2 = Vector2.ZERO
var on_floor: bool = true

var mode: int = Mode.MOVE
var mode_t: float = 0.0
var attack_index: int = 0
var attack_hits: Dictionary = {}
var dash_t: float = 0.0
var dash_cd: float = 0.0
var dash_dir: int = 1

var invuln: float = 0.0
var in_light: bool = false
var in_shadow: bool = true

var _prev: Dictionary = {}
var _damages: Array = [14.0, 18.0, 34.0]


func setup(cfg: Dictionary, spawn: Vector2) -> void:
	config = cfg
	moves = Config.moves(config)
	sprite_setup = Config.character(config, "player").get("sprite", {})
	display_scale = float(sprite_setup.get("displayScale", 1.0))
	settings = config.get("_offbeat", {}).get("player", {})
	if not (settings.get("damage", null) is Array):
		_damages = [14.0, 18.0, 34.0]
	else:
		_damages = settings.get("damage")
	max_hp = float(settings.get("hp", 100.0))
	hp = max_hp
	position = spawn
	sprite = Sprite2D.new()
	sprite.name = "Sprite"
	add_child(sprite)
	Art.reset(sprite_setup)
	_collect_clips()
	_set_clip("idle", true)


func _collect_clips() -> void:
	var anims: Dictionary = sprite_setup.get("animations", {})
	for key in ["idle", "run", "jump", "fall", "attack_1", "attack_2", "attack_3",
			"dash_right", "dash_left", "death", "guard_hit_1", "parry_react_1"]:
		if anims.has(key):
			clips[key] = anims[key]


func _down(key: int) -> bool:
	return Input.is_physical_key_pressed(key)


func _just(key: int) -> bool:
	var now := Input.is_physical_key_pressed(key)
	var was := bool(_prev.get(key, false))
	_prev[key] = now
	return now and not was


func _just_mouse(button: int) -> bool:
	var now := Input.is_mouse_button_pressed(button)
	var was := bool(_prev.get(-button - 100, false))
	_prev[-button - 100] = now
	return now and not was


func _physics_process(delta: float) -> void:
	if mode == Mode.DEAD:
		_tick_anim(delta)
		return
	_tick_timers(delta)
	_tick_input(delta)
	_tick_physics(delta)
	_tick_anim(delta)


func _tick_timers(delta: float) -> void:
	dash_cd = maxf(0.0, dash_cd - delta)
	invuln = maxf(0.0, invuln - delta)
	mode_t += delta


func _tick_input(delta: float) -> void:
	var left := _down(KEY_A) or _down(KEY_LEFT)
	var right := _down(KEY_D) or _down(KEY_RIGHT)
	var jump := _just(KEY_SPACE) or _just(KEY_W) or _just(KEY_UP)
	var j_key := _just(KEY_J)
	var m_click := _just_mouse(MOUSE_BUTTON_LEFT)
	var attack := j_key or m_click
	var d_key := _just(KEY_SHIFT)
	var d_click := _just_mouse(MOUSE_BUTTON_RIGHT)
	var dash := d_key or d_click

	if mode == Mode.HURT:
		if mode_t >= float(settings.get("hurtTime", 0.32)):
			mode = Mode.MOVE
			mode_t = 0.0
		return

	if mode == Mode.DASH:
		if mode_t >= dash_t:
			mode = Mode.MOVE
			mode_t = 0.0
			vel.x = 0.0
		return

	if mode == Mode.ATTACK:
		if left and not right:
			facing = -1
		elif right and not left:
			facing = 1
		if attack and _attack_can_chain():
			_start_attack(attack_index + 1)
			return
		if _attack_finished():
			var any := not attack_hits.is_empty()
			emit_signal("attack_ended", attack_index, any)
			mode = Mode.MOVE
			mode_t = 0.0
		return

	# 自由状态
	if left and not right:
		facing = -1
	elif right and not left:
		facing = 1
	if jump and on_floor:
		vel.y = -float(settings.get("jumpSpeed", 760.0))
		on_floor = false
	if attack:
		_start_attack(1)
		return
	if dash and dash_cd <= 0.0:
		_start_dash(1 if (right and not left) else (-1 if (left and not right) else facing))


func _attack_move() -> Object:
	return moves.get("light_%d" % attack_index, null)


func _attack_frames() -> int:
	return int(mode_t * 60.0)


func _attack_can_chain() -> bool:
	var m = _attack_move()
	if m == null or attack_index >= 3:
		return false
	return _attack_frames() >= int(m.startup_frames) + int(m.cancel_frame)


func _attack_finished() -> bool:
	var m = _attack_move()
	if m == null:
		return true
	return _attack_frames() >= int(m.startup_frames) + int(m.active_frames) + int(m.recovery_frames)


func _start_attack(index: int) -> void:
	attack_index = clampi(index, 1, 3)
	mode = Mode.ATTACK
	mode_t = 0.0
	attack_hits.clear()
	_set_clip("attack_%d" % attack_index, true)
	emit_signal("attack_started", attack_index)


func _start_dash(dir: int) -> void:
	dash_dir = dir
	facing = dir
	mode = Mode.DASH
	mode_t = 0.0
	dash_t = float(settings.get("dashTime", 0.30))
	dash_cd = float(settings.get("dashCooldown", 0.45))
	attack_hits.clear()
	invuln = maxf(invuln, 0.16)
	_set_clip("dash_right" if dir > 0 else "dash_left", true)
	emit_signal("attack_started", 4)


func _tick_physics(delta: float) -> void:
	if mode == Mode.DASH:
		vel = Vector2(dash_dir * float(settings.get("dashSpeed", 1020.0)), 0.0)
		position += vel * delta
		_clamp_bounds()
		_resolve_dash()
		return

	var speed := float(settings.get("speed", 310.0))
	if in_light:
		speed *= 0.78
	elif in_shadow:
		speed *= 1.15
	var move_x := 0.0
	if mode == Mode.MOVE or mode == Mode.ATTACK:
		if _down(KEY_A) or _down(KEY_LEFT):
			move_x -= 1.0
		if _down(KEY_D) or _down(KEY_RIGHT):
			move_x += 1.0
		if mode == Mode.ATTACK:
			move_x *= float(settings.get("attackMovement", 0.32))

	if on_floor:
		vel.x = move_x * speed
	else:
		var control := float(settings.get("airControl", 0.72))
		vel.x = lerpf(vel.x, move_x * speed, clampf(control * delta * 12.0, 0.0, 1.0))
	vel.y += float(settings.get("gravity", 1900.0)) * delta
	position += vel * delta

	var ground := 580.0
	if trial != null:
		ground = float(trial.ground_y)
	if position.y >= ground:
		position.y = ground
		vel.y = 0.0
		on_floor = true
	else:
		on_floor = false
	_clamp_bounds()

	if mode == Mode.ATTACK:
		var m = _attack_move()
		if m != null:
			var frames := _attack_frames()
			var start := int(m.startup_frames)
			var end := start + int(m.active_frames)
			if frames >= start and frames < end:
				_resolve_attack(m, float(_damages[attack_index - 1]))


func _clamp_bounds() -> void:
	var left := -1860.0
	var right := 1860.0
	if trial != null:
		left = float(trial.bounds_left)
		right = float(trial.bounds_right)
	position.x = clampf(position.x, left, right)


func attack_box() -> Rect2:
	var m = _attack_move()
	if m == null:
		return Rect2(position, Vector2.ZERO)
	var r: Rect2 = m.hitbox
	var x := r.position.x
	if facing < 0:
		x = -r.position.x - r.size.x
	return Rect2(position + Vector2(x, r.position.y), r.size)


func _resolve_attack(m, damage: float) -> void:
	if trial == null:
		return
	var box: Rect2 = attack_box()
	for shade in trial.shades_alive():
		var id: int = int(shade.get_instance_id())
		if attack_hits.has(id):
			continue
		if box.intersects(shade.logic_hurt_box()):
			attack_hits[id] = true
			var mult: float = trial.beat_multiplier()
			shade.take_hit(damage * mult, facing, position)
			trial.on_shade_hit(shade, damage * mult, box)


func _resolve_dash() -> void:
	if trial == null or attack_hits.size() > 0:
		return
	var box := Rect2(position + Vector2(-70.0 if facing < 0 else 10.0, -150.0), Vector2(150.0, 150.0))
	for shade in trial.shades_alive():
		var id: int = int(shade.get_instance_id())
		if attack_hits.has(id):
			continue
		if box.intersects(shade.logic_hurt_box()):
			attack_hits[id] = true
			var mult: float = trial.beat_multiplier()
			shade.take_hit(24.0 * mult, facing, position)
			trial.on_shade_hit(shade, 24.0 * mult, box)


func hurt(amount: float, from_x: float) -> void:
	if invuln > 0.0 or mode == Mode.DEAD:
		return
	hp -= amount
	invuln = float(settings.get("invulnTime", 0.75))
	mode = Mode.HURT
	mode_t = 0.0
	vel.x = signf(position.x - from_x) * 260.0
	vel.y = -180.0
	on_floor = false
	_set_clip("guard_hit_1", true)
	emit_signal("damaged", amount)
	if hp <= 0.0:
		_die()


func _die() -> void:
	hp = 0.0
	mode = Mode.DEAD
	mode_t = 0.0
	_set_clip("death", true)
	emit_signal("died")


func is_dead() -> bool:
	return mode == Mode.DEAD


func _set_clip(name: String, restart: bool = false) -> void:
	if not clips.has(name):
		return
	if name == clip and not restart:
		return
	clip = name
	clip_t = 0.0


func _tick_anim(delta: float) -> void:
	if mode == Mode.ATTACK:
		var m = _attack_move()
		if m != null and m.has_method("anim_seconds"):
			clip_t = m.anim_seconds(float(_attack_frames()))
	elif mode == Mode.DASH:
		_set_clip("dash_right" if dash_dir > 0 else "dash_left")
		clip_t += delta
	elif mode == Mode.DEAD or mode == Mode.HURT:
		clip_t += delta
	elif not on_floor:
		_set_clip("jump" if vel.y < 0.0 else "fall")
		clip_t += delta
	elif absf(vel.x) > 20.0:
		_set_clip("run")
		clip_t += delta
	else:
		_set_clip("idle")
		clip_t += delta
	_draw_frame()


func _draw_frame() -> void:
	if sprite == null or not clips.has(clip):
		return
	var c: Dictionary = clips[clip]
	var frames: Array = c.get("frames", [])
	if frames.is_empty():
		return
	var fps := float(c.get("fps", 24.0))
	var index := int(floor(clip_t * fps))
	if bool(c.get("loop", true)):
		index = posmod(index, frames.size())
	else:
		index = clampi(index, 0, frames.size() - 1)
	Art.apply(sprite, frames[index], display_scale)
	sprite.flip_h = facing < 0
	sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)
	if in_light:
		sprite.modulate = Color(1.1, 1.05, 0.98, 1.0)
	elif in_shadow:
		sprite.modulate = Color(0.86, 0.89, 1.0, 1.0)
	if invuln > 0.0 and int(invuln * 20.0) % 2 == 0:
		sprite.modulate.a = 0.55
