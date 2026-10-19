extends Node2D
## 影弓射出的影矢（第四轮）：直线飞，打中路上的【第一个人】——玩家或者挡在中间的同伴都算。
## 玩家按 L 弹刀，或者用刀砍到它 → 反弹回去变成玩家的箭，专打影子。
## 程序绘制，不需要新美术。

const MoveDefinition := preload("res://scripts/core/move_definition.gd")
const SPEED := 1050.0
const LIFE := 96                     ## 帧
const IGNORE_SHOOTER := 8            ## 刚射出的几帧不打射手自己

signal deflected(point: Vector2)
signal struck(target: Node, point: Vector2, friendly: bool)

var shooter: Node2D = null
var victim: Node2D = null            ## 射手当时瞄的玩家
var move: MoveDefinition
var reflect_move: MoveDefinition
var velocity := Vector2.ZERO
var friendly := false                ## true = 被玩家打回去了，现在只打影子
var frames := 0
var arena := Vector2(-INF, INF)
var _spent := false
var _hurtbox: Area2D
var _trail: Array[Vector2] = []


func setup(p_shooter: Node2D, from: Vector2, dir: Vector2, mv: MoveDefinition, hitstop_multiplier: float = 1.0) -> void:
	shooter = p_shooter
	if p_shooter != null:
		victim = p_shooter.get(&"target")
		arena = Vector2(float(p_shooter.get(&"arena_left")), float(p_shooter.get(&"arena_right")))
	position = from
	velocity = (dir if dir.length() > 0.01 else Vector2.RIGHT).normalized() * SPEED
	move = mv
	reflect_move = MoveDefinition.new()
	reflect_move.id = &"bolt_reflect"
	reflect_move.damage = 16.0
	reflect_move.knockback = 380.0
	reflect_move.knockback_angle = 22.0
	reflect_move.victim_hitstop_frames = roundi(10 * hitstop_multiplier)
	reflect_move.hitstop_frames = 0
	reflect_move.shake_amount = 0.0


func _ready() -> void:
	add_to_group(&"shade_projectile")
	z_index = 4
	_hurtbox = Area2D.new()
	_hurtbox.collision_layer = 4      # 和影的受击盒同一层：玩家的刀能砍到它
	_hurtbox.collision_mask = 0
	_hurtbox.monitoring = false
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(56.0, 28.0)
	shape.shape = rect
	_hurtbox.add_child(shape)
	add_child(_hurtbox)


func _physics_process(delta: float) -> void:
	if _spent:
		return
	frames += 1
	_trail.push_front(global_position)
	if _trail.size() > 6:
		_trail.pop_back()
	position += velocity * delta
	if frames > LIFE or position.x < arena.x - 40.0 or position.x > arena.y + 40.0:
		_finish()
		return
	_check_hits()
	queue_redraw()


func _check_hits() -> void:
	var dir := 1 if velocity.x >= 0.0 else -1
	if not friendly and victim != null and is_instance_valid(victim) and victim.has_method(&"take_hit"):
		var d: Vector2 = victim.global_position - global_position
		if absf(d.x) < 34.0 and absf(d.y) < 82.0:
			var res = victim.call(&"take_hit", move, dir, global_position, 0.0, false, 1.0, self)
			if friendly:
				return        # 被弹刀弹回去了（on_parried 已经掉头），继续飞
			if res != true:
				struck.emit(victim, global_position, false)
			_finish()
			return
	for o in get_tree().get_nodes_in_group(&"shade"):
		if not o.is_alive() or o.spawn_frames > 0:
			continue
		if o == shooter and not friendly and frames < IGNORE_SHOOTER:
			continue
		var d: Vector2 = o.global_position - global_position
		if absf(d.x) < float(o.half_w) + 14.0 and absf(d.y) < float(o.half_h):
			var res = o.take_hit(reflect_move if friendly else move, dir, global_position, 0.0, false,
					1.0 if friendly else 0.5, self)
			if res == true and o.is_dodging():
				continue      # 翻滚躲开了，箭接着飞
			if res != true:
				struck.emit(o, global_position, friendly)
			_finish()
			return


## 玩家的刀砍到它：打回去（返回 false → 玩家这一刀算“砍中了东西”，有顿帧）
func take_hit(_mv: Resource, from_facing: int, _point: Vector2, _charge: float = 0.0,
		_from_up: bool = false, _damage_mul: float = 1.0, _attacker: Node = null) -> bool:
	if friendly or _spent:
		return true
	_reflect(from_facing)
	return false


## 玩家弹刀弹到它
func on_parried(cause: Node = null) -> void:
	var dir := -1 if velocity.x > 0.0 else 1
	if cause is Node2D:
		dir = 1 if global_position.x >= (cause as Node2D).global_position.x else -1
	_reflect(dir)


func _reflect(dir: int) -> void:
	friendly = true
	frames = 0
	velocity = Vector2(float(dir) * SPEED * 1.25, 0.0)
	_trail.clear()
	deflected.emit(global_position)


func _finish() -> void:
	_spent = true
	queue_free()


func _draw() -> void:
	var col := Color(1.0, 0.54, 0.24) if not friendly else Color(1.0, 0.88, 0.5)
	var ink := Color(0.035, 0.043, 0.082)
	# 拖尾
	for i in _trail.size():
		var p := to_local(_trail[i])
		var c := col
		c.a = 0.35 * (1.0 - float(i) / float(_trail.size()))
		draw_line(p, p - velocity.normalized() * 18.0, c, 4.0 - float(i) * 0.5)
	var d := velocity.normalized()
	var n := Vector2(-d.y, d.x)
	var tail := -d * 40.0
	draw_line(tail, Vector2.ZERO, ink, 5.0)
	draw_line(tail * 0.9, Vector2.ZERO, col.lerp(ink, 0.5), 2.0)
	# 箭头：发光的三角
	var glow := col
	glow.a = 0.35
	draw_circle(Vector2.ZERO, 12.0, glow)
	draw_colored_polygon(PackedVector2Array([d * 14.0, -d * 4.0 + n * 7.0, -d * 4.0 - n * 7.0]), col)
	# 尾羽
	draw_line(tail, tail - d * 8.0 + n * 8.0, ink, 3.0)
	draw_line(tail, tail - d * 8.0 - n * 8.0, ink, 3.0)
