class_name SpatialRift
extends Node2D
## 重刀留下的「紫色空间裂口」（A3）：
## 白芯、墨边、冷紫辉光的空间斩裂线，存活 3.0 秒后渐隐消散。
## 处于浮空 / 击飞（State.LAUNCHED，含过杀躯体）的敌人一旦穿过裂口线段，
## 裂口当场“咔”地崩裂消失，追加一记真实斩击伤害并将其朝玩家 / 反向高弹力折弹回来。

signal rift_triggered(rift: Node2D, target: Node2D, point: Vector2, rebound_velocity: Vector2)

const DEFAULT_LIFE := 3.0
const SHATTER_LIFE := 0.22
const INK := Color(0.02, 0.024, 0.048)
const VIOLET_DEEP := Color(0.46, 0.24, 0.96)
const VIOLET := Color(0.60, 0.40, 1.0)
const VIOLET_LIGHT := Color(0.84, 0.74, 1.0)

var seg_a: Vector2 = Vector2(-90.0, 60.0)
var seg_b: Vector2 = Vector2(90.0, -60.0)
var life_seconds: float = DEFAULT_LIFE
var slash_damage: float = 18.0
var hit_thickness: float = 22.0
var arm_frames: int = 4
var origin_serial: int = -1
var owner_player: Node2D = null
var move_tag: StringName = &""

var age: float = 0.0
var triggered: bool = false
var dismissed: bool = false
var _shatter_t: float = 0.0
var _prev_pos: Dictionary = {}
var _ignored_ids: Dictionary = {}
var _spurs: Array = []
var _shards: Array = []
var _rng := RandomNumberGenerator.new()


func setup(p_center: Vector2, p_dir: Vector2, p_half_len: float = 115.0,
		p_player: Node2D = null, p_damage: float = 18.0, p_tag: StringName = &"") -> void:
	global_position = p_center
	var d := p_dir.normalized() if p_dir.length_squared() > 0.0001 else Vector2(0.7, -0.7).normalized()
	seg_a = -d * p_half_len
	seg_b = d * p_half_len
	owner_player = p_player
	slash_damage = p_damage
	move_tag = p_tag


func _ready() -> void:
	add_to_group(&"spatial_rift")
	_rng.randomize()
	_build_spurs()
	queue_redraw()


func is_active() -> bool:
	return not triggered and not dismissed and age < life_seconds


## 超出同屏 3 条上限或关卡清理时立即顶掉
## 同一刀挥砍刚打飞的受击者在起飞初段不误触本刀自己留下的裂口
func ignore_target(target: Node, frames: int = 24) -> void:
	if target != null and is_instance_valid(target):
		_ignored_ids[target.get_instance_id()] = maxi(int(_ignored_ids.get(target.get_instance_id(), 0)), frames)


func dismiss() -> void:
	if dismissed:
		return
	dismissed = true
	queue_free()


func world_a() -> Vector2:
	return global_position + seg_a


func world_b() -> Vector2:
	return global_position + seg_b


func _build_spurs() -> void:
	_spurs.clear()
	var axis := seg_b - seg_a
	var length := axis.length()
	if length < 1.0:
		return
	var dir := axis / length
	var nrm := Vector2(-dir.y, dir.x)
	for i in 5:
		var u := lerpf(0.18, 0.82, float(i) / 4.0) + _rng.randf_range(-0.05, 0.05)
		var side := 1.0 if i % 2 == 0 else -1.0
		var base := seg_a.lerp(seg_b, clampf(u, 0.1, 0.9))
		var tip := base + (dir * _rng.randf_range(-18.0, 18.0) + nrm * side * _rng.randf_range(12.0, 26.0))
		_spurs.append([base, tip])


func _physics_process(delta: float) -> void:
	if dismissed:
		return
	if triggered:
		_shatter_t += delta
		for s in _shards:
			s.p += s.v * delta
			s.v *= maxf(0.0, 1.0 - 5.5 * delta)
		queue_redraw()
		if _shatter_t >= SHATTER_LIFE:
			queue_free()
		return

	age += delta
	if age >= life_seconds:
		dismiss()
		return

	var armed := arm_frames <= 0
	if arm_frames > 0:
		arm_frames -= 1
	for k in _ignored_ids.keys():
		var rem := int(_ignored_ids[k]) - 1
		if rem <= 0:
			_ignored_ids.erase(k)
		else:
			_ignored_ids[k] = rem

	var a := world_a()
	var b := world_b()
	for node in get_tree().get_nodes_in_group(&"shade"):
		if not (node is Node2D) or not is_instance_valid(node):
			continue
		var shade := node as Node2D
		var id := shade.get_instance_id()
		if not shade.has_method(&"can_trigger_rift") or not bool(shade.call(&"can_trigger_rift")):
			_prev_pos.erase(id)
			continue
		var cur := shade.global_position
		if not armed or _ignored_ids.has(id):
			_prev_pos[id] = cur
			continue
		var vel_Variant: Variant = shade.get(&"velocity")
		var vel: Vector2 = vel_Variant if vel_Variant is Vector2 else Vector2.ZERO
		var prev: Vector2 = _prev_pos.get(id, cur - vel * delta)
		_prev_pos[id] = cur
		var hit_pt := _check_crossing(prev, cur, a, b, hit_thickness + _shade_pad(shade))
		if is_finite(hit_pt.x):
			_trigger_on_shade(shade, hit_pt, vel)
			break
	queue_redraw()


## 供 Shade._process_launched 在位移步进后、落地判定前主动调用，
## 消除场景树同帧物理顺序（裂口先于敌人更新）导致落地前最后一步穿过裂口漏检的问题。
func try_trigger_on_shade(shade: Node2D, prev: Vector2, cur: Vector2) -> bool:
	if not is_active() or arm_frames > 0:
		return false
	if shade == null or not is_instance_valid(shade):
		return false
	var id := shade.get_instance_id()
	if not shade.has_method(&"can_trigger_rift") or not bool(shade.call(&"can_trigger_rift")):
		_prev_pos.erase(id)
		return false
	if _ignored_ids.has(id):
		_prev_pos[id] = cur
		return false
	_prev_pos[id] = cur
	var hit_pt := _check_crossing(prev, cur, world_a(), world_b(), hit_thickness + _shade_pad(shade))
	if not is_finite(hit_pt.x):
		return false
	var vel_variant: Variant = shade.get(&"velocity")
	var vel: Vector2 = vel_variant if vel_variant is Vector2 else Vector2.ZERO
	_trigger_on_shade(shade, hit_pt, vel)
	return true


func _shade_pad(shade: Node2D) -> float:
	var hw: Variant = shade.get(&"half_w")
	if hw is float or hw is int:
		return clampf(float(hw) * 0.5, 0.0, 28.0)
	return 0.0


func _check_crossing(prev: Vector2, cur: Vector2, a: Vector2, b: Vector2, thickness: float = -1.0) -> Vector2:
	var eff_thickness := hit_thickness if thickness < 0.0 else thickness
	var hit: Variant = Geometry2D.segment_intersects_segment(prev, cur, a, b)
	if hit is Vector2:
		return hit as Vector2
	if (cur - prev).length_squared() <= 0.25:
		return Vector2(INF, INF)
	var pair: PackedVector2Array = Geometry2D.get_closest_points_between_segments(prev, cur, a, b)
	if pair.size() == 2 and pair[0].distance_to(pair[1]) <= eff_thickness:
		return pair[1]
	return Vector2(INF, INF)


func _trigger_on_shade(shade: Node2D, hit_point: Vector2, in_vel: Vector2) -> void:
	triggered = true
	_shatter_t = 0.0
	var dir_x := 0.0
	if owner_player != null and is_instance_valid(owner_player):
		var to_player := owner_player.global_position.x - shade.global_position.x
		if absf(to_player) > 24.0:
			dir_x = signf(to_player)
	if dir_x == 0.0:
		if absf(in_vel.x) > 10.0:
			dir_x = -signf(in_vel.x)
		elif owner_player != null and is_instance_valid(owner_player) and owner_player.get(&"facing") != null:
			dir_x = -float(int(owner_player.get(&"facing")))
		else:
			dir_x = -1.0

	var rebound_x := clampf(maxf(absf(in_vel.x) * 1.18, 860.0), 860.0, 1320.0)
	var rebound_y := -clampf(maxf(absf(in_vel.y) * 0.45, 300.0), 300.0, 480.0)
	var rebound_vel := Vector2(dir_x * rebound_x, rebound_y)

	var dmg := slash_damage
	if owner_player != null and is_instance_valid(owner_player) and owner_player.get(&"attack_damage_mul") != null:
		dmg *= float(owner_player.get(&"attack_damage_mul"))

	if shade.has_method(&"take_rift_slash"):
		shade.call(&"take_rift_slash", dmg, rebound_vel, hit_point)

	_spawn_shatter_shards()
	rift_triggered.emit(self, shade, hit_point, rebound_vel)
	queue_redraw()


func _spawn_shatter_shards() -> void:
	_shards.clear()
	var axis := seg_b - seg_a
	var nrm := Vector2(-axis.y, axis.x).normalized() if axis.length_squared() > 0.01 else Vector2.UP
	for i in 14:
		var u := float(i) / 13.0
		var p := seg_a.lerp(seg_b, u) + nrm * _rng.randf_range(-5.0, 5.0)
		var side := 1.0 if i % 2 == 0 else -1.0
		var v := nrm * side * _rng.randf_range(90.0, 260.0) + axis.normalized() * _rng.randf_range(-110.0, 110.0)
		_shards.append({
			"p": p,
			"v": v,
			"len": _rng.randf_range(12.0, 28.0),
			"ang": _rng.randf_range(0.0, TAU),
			"w": _rng.randf_range(2.2, 4.6),
			"white": i % 3 == 0,
		})


## 两头尖、中间宽的刀口多边形（与 ult_map_slash._blade 同构）
static func _blade(a: Vector2, b: Vector2, mid_w: float, tip_w: float = 0.0, peak: float = 0.5) -> PackedVector2Array:
	var d := b - a
	var length := d.length()
	if length < 0.5:
		return PackedVector2Array()
	var n := Vector2(-d.y, d.x) / length
	var N := 14
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for i in N + 1:
		var t := float(i) / float(N)
		var u := t / peak if t < peak else (1.0 - t) / maxf(1.0 - peak, 0.001)
		var w := lerpf(tip_w, mid_w, sin(clampf(u, 0.0, 1.0) * PI * 0.5)) * 0.5
		var p := a.lerp(b, t)
		left.append(p + n * w)
		right.append(p - n * w)
	right.reverse()
	left.append_array(right)
	return left


func _poly(pts: PackedVector2Array, col: Color) -> void:
	if pts.size() >= 3 and col.a > 0.003:
		draw_colored_polygon(pts, col)


func _draw() -> void:
	if dismissed:
		return
	if triggered:
		var k := 1.0 - clampf(_shatter_t / SHATTER_LIFE, 0.0, 1.0)
		var flash_blade := _blade(seg_a, seg_b, 26.0 * k * k)
		_poly(flash_blade, Color(VIOLET, 0.42 * k))
		for s in _shards:
			var dir := Vector2(cos(float(s.ang)), sin(float(s.ang)))
			var p0: Vector2 = s.p - dir * float(s.len) * 0.5
			var p1: Vector2 = s.p + dir * float(s.len) * 0.5
			_poly(_blade(p0, p1, float(s.w) + 2.4), Color(INK, 0.85 * k))
			var c := Color.WHITE if bool(s.white) else VIOLET_LIGHT
			_poly(_blade(p0, p1, float(s.w) * k), Color(c, 0.95 * k))
		return

	var open_k := clampf(age / 0.09, 0.0, 1.0)
	var fade := clampf((life_seconds - age) / 0.75, 0.0, 1.0)
	var pulse := 0.9 + 0.1 * sin(age * 11.0)
	var a := open_k * fade
	if a <= 0.004:
		return

	var p0 := seg_a * (0.55 + 0.45 * open_k)
	var p1 := seg_b * (0.55 + 0.45 * open_k)

	# 1. 多层冷紫辉光外晕
	for g in [[34.0, 0.10], [20.0, 0.22], [12.0, 0.42]]:
		_poly(_blade(p0, p1, float(g[0]) * pulse), Color(VIOLET_DEEP, float(g[1]) * a))

	# 2. 墨色裂口外框（压住高光，和绝影地图斩同语言）
	_poly(_blade(p0, p1, 8.6 * pulse, 0.8), Color(INK, 0.92 * a))

	# 3. 冷紫内刃 + 锐利白芯
	_poly(_blade(p0, p1, 5.2 * pulse, 0.4), Color(VIOLET_LIGHT, 0.90 * a))
	_poly(_blade(p0, p1, 2.4 * pulse, 0.0), Color(1.0, 1.0, 1.0, 0.98 * a))

	# 4. 侧生细碎裂纹毛刺
	for sp in _spurs:
		var sa: Vector2 = sp[0] * open_k
		var sb: Vector2 = sp[1] * open_k
		draw_line(sa, sb, Color(INK, 0.75 * a), 2.6, true)
		draw_line(sa, sb, Color(VIOLET_LIGHT, 0.78 * a), 1.1, true)
