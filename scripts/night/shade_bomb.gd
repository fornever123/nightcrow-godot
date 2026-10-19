extends Node2D
## 影爆扔的炸弹（第四轮）：抛物线飞向玩家脚下，落地后引信很短，炸开一圈——
## 玩家和【同伴】都会被炸到、掀飞。玩家用刀砍到它 → 打回去，变成玩家的炸弹（只炸影子，炸得更狠）。
## 程序绘制，不需要新美术。

const MoveDefinition := preload("res://scripts/core/move_definition.gd")
const GRAVITY := 1500.0
const RADIUS := 150.0
const FUSE_AFTER_LAND := 16          ## 落地后多少帧炸
const MAX_LIFE := 150

signal exploded(point: Vector2, friendly: bool)
signal deflected(point: Vector2)

var shooter: Node2D = null
var victim: Node2D = null
var move: MoveDefinition             ## 炸到玩家用的（影爆的 strike_move）
var blast_move: MoveDefinition       ## 炸到影子用的（掀飞）
var velocity := Vector2.ZERO
var terrain = null
var floor_y := 580.0
var arena := Vector2(-INF, INF)
var friendly := false
var fuse := -1
var life := 0
var spin := 0.0
var _spent := false
var _hurtbox: Area2D


func setup(p_shooter: Node2D, from: Vector2, land: Vector2, mv: MoveDefinition, p_terrain, p_floor_y: float,
		left: float, right: float, hitstop_multiplier: float = 1.0) -> void:
	shooter = p_shooter
	if p_shooter != null:
		victim = p_shooter.get(&"target")
	terrain = p_terrain
	floor_y = p_floor_y
	arena = Vector2(left, right)
	position = from
	move = mv
	var t := clampf(absf(land.x - from.x) / 650.0, 0.6, 1.05)
	velocity = Vector2((land.x - from.x) / t, (land.y - from.y - 0.5 * GRAVITY * t * t) / t)
	blast_move = MoveDefinition.new()
	blast_move.id = &"bomb_blast"
	blast_move.damage = 18.0
	blast_move.knockback = 520.0
	blast_move.knockback_angle = 60.0
	blast_move.forces_launch = true
	blast_move.launch_speed = 620.0
	blast_move.victim_hitstop_frames = roundi(12 * hitstop_multiplier)
	blast_move.hitstop_frames = 0
	blast_move.shake_amount = 0.0
	blast_move.wall_damage_factor = 0.8


func _ready() -> void:
	add_to_group(&"shade_projectile")
	z_index = 4
	_hurtbox = Area2D.new()
	_hurtbox.collision_layer = 4      # 玩家的刀能砍到它
	_hurtbox.collision_mask = 0
	_hurtbox.monitoring = false
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 22.0
	shape.shape = circle
	_hurtbox.add_child(shape)
	add_child(_hurtbox)


func _ground_at(x: float, y: float) -> float:
	if terrain == null:
		return floor_y
	return terrain.support_y(x, y, 6.0, NAN)


func _physics_process(delta: float) -> void:
	if _spent:
		return
	life += 1
	spin += delta * (14.0 if fuse < 0 else 4.0)
	var prev_y := position.y
	velocity.y += GRAVITY * delta
	position += velocity * delta
	if position.x < arena.x + 12.0 or position.x > arena.y - 12.0:
		position.x = clampf(position.x, arena.x + 12.0, arena.y - 12.0)
		velocity.x = -velocity.x * 0.5
	var gy := _ground_at(position.x, prev_y + 12.0) - 12.0
	if velocity.y > 0.0 and position.y >= gy:
		position.y = gy
		if friendly:
			_explode()
			return
		if fuse < 0:
			fuse = FUSE_AFTER_LAND
		velocity.y = -absf(velocity.y) * 0.3 if absf(velocity.y) > 200.0 else 0.0
		velocity.x *= 0.45
	if fuse > 0:
		fuse -= 1
		if fuse == 0:
			_explode()
			return
	if life > MAX_LIFE:
		_explode()
		return
	# 碰到人就炸：敌人的炸弹碰玩家，打回去的炸弹碰影子
	if not friendly and victim != null and is_instance_valid(victim):
		var d: Vector2 = victim.global_position - global_position
		if absf(d.x) < 40.0 and absf(d.y) < 80.0 and life > 6:
			_explode()
			return
	if friendly:
		for o in get_tree().get_nodes_in_group(&"shade"):
			if not o.is_alive():
				continue
			var d: Vector2 = o.global_position - global_position
			if absf(d.x) < float(o.half_w) + 18.0 and absf(d.y) < float(o.half_h) + 10.0:
				_explode()
				return
	queue_redraw()


## 玩家的刀砍到它：打回去
func take_hit(_mv: Resource, from_facing: int, _point: Vector2, _charge: float = 0.0,
		_from_up: bool = false, _damage_mul: float = 1.0, _attacker: Node = null) -> bool:
	if friendly or _spent:
		return true
	friendly = true
	fuse = -1
	life = 0
	velocity = Vector2(float(from_facing) * 820.0, -480.0)
	deflected.emit(global_position)
	return false


func _explode() -> void:
	if _spent:
		return
	_spent = true
	var point := global_position
	if not friendly and victim != null and is_instance_valid(victim) and victim.has_method(&"take_hit"):
		var d: Vector2 = victim.global_position - point
		if absf(d.x) < RADIUS and absf(d.y) < RADIUS * 0.9:
			var dir := 1 if d.x >= 0.0 else -1
			victim.call(&"take_hit", move, dir, point, 0.0, false, 1.0, null)
	for o in get_tree().get_nodes_in_group(&"shade"):
		if not o.is_alive() or o.spawn_frames > 0:
			continue
		var d: Vector2 = o.global_position - point
		if absf(d.x) < RADIUS + float(o.half_w) * 0.5 and absf(d.y) < RADIUS * 0.9:
			var dir := 1 if d.x >= 0.0 else -1
			o.take_hit(blast_move, dir, o.global_position, 0.0, false, 1.3 if friendly else 1.0, self)
	exploded.emit(point, friendly)
	queue_free()


func _draw() -> void:
	var ink := Color(0.035, 0.043, 0.082)
	var hot := Color(1.0, 0.54, 0.24) if not friendly else Color(1.0, 0.88, 0.5)
	var blink := 0.0
	if fuse > 0:
		blink = 0.5 + 0.5 * sin(float(fuse) * 1.6)
	var glow := hot
	glow.a = 0.18 + 0.35 * blink
	draw_circle(Vector2.ZERO, 22.0 + 6.0 * blink, glow)
	draw_circle(Vector2.ZERO, 14.0, ink.lerp(hot, 0.25 * blink))
	draw_arc(Vector2.ZERO, 14.0, -2.4, -0.9, 8, Color(0.48, 0.6, 0.9, 0.7), 2.0)
	# 引信 + 火星
	var f := Vector2(cos(spin), sin(spin)) * 0.0 + Vector2(6.0, -14.0).rotated(spin * 0.15)
	draw_line(Vector2(4.0, -11.0), f, ink, 3.0)
	draw_circle(f, 3.5 + 2.0 * blink, Color(1.0, 0.95, 0.75))
	if fuse >= 0:
		# 落地后脚下画出爆炸范围（橙色虚圈）：看到就跑
		var ring := hot
		ring.a = 0.25 + 0.3 * blink
		draw_arc(Vector2(0, 10), RADIUS, PI + 0.15, TAU - 0.15, 28, ring, 2.0)
