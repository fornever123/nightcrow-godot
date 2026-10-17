extends Area2D
## 远程弹丸（K 键）。
##
## 设计要点：
##  · **命中走和近战完全相同的 take_hit 链路** —— 所以击退、浮空倍率、
##    僵直、以及最重要的【撞墙二次伤害】全都免费继承，不需要另写一套。
##  · 传递打击感：命中时给玩家一小段顿帧（比近战短），
##    这样"远程也能打出确认感"，又不会打断走位节奏。
##  · 撞到地形就消失，不穿透。
##
## 碰撞层：layer 16（弹丸），mask 5 = 1(地形) | 4(受击盒)。

signal hit_target(target: Node, point: Vector2)

## 由 player.gd 在发射时注入。
var move: Resource = null
## 飞行方向：+1 朝右 / -1 朝左
var facing: int = 1
## 飞行速度 px/s
var speed: float = 940.0
## 存活帧数上限（防止没撞到东西时永远飞下去）
var life_frames: int = 90
## 命中时给【射手】的顿帧帧数
var shooter_hitstop: int = 3
## 射出者，用来排除自伤
var shooter: Node = null
## 命中判定 mask。默认 5 = 1(地形) | 4(敌人受击盒)。
## PVP 里射手会注入更大的值（13 = 地形 + 敌人 + 对手受击盒），
## 于是同一发弹丸既能打怪也能打对手 —— 不需要为 PVP 另写一种弹丸。
@export var hit_mask: int = 5
## 弹丸染色（跟随射手身份色）。alpha == 0 表示"不染色，用场景里的原色"。
var tint: Color = Color(0.0, 0.0, 0.0, 0.0)

var _frames: int = 0
var _spent: bool = false


func _ready() -> void:
	# 弹丸之间互不干扰，只关心地形和受击盒
	monitoring = true
	monitorable = false
	collision_mask = hit_mask
	if tint.a > 0.0:
		var v := get_node_or_null(^"Visual")
		if v != null:
			var glow := v.get_node_or_null(^"Glow") as ColorRect
			if glow != null:
				glow.color = Color(tint.r, tint.g, tint.b, 0.28)
			var core := v.get_node_or_null(^"Core") as ColorRect
			if core != null:
				core.color = Color(tint.r * 0.35 + 0.65, tint.g * 0.35 + 0.65,
						tint.b * 0.35 + 0.65, 1.0)


func _physics_process(delta: float) -> void:
	if _spent:
		return
	_frames += 1
	global_position.x += speed * float(facing) * delta

	# 1) 先看有没有打到人（受击盒在 layer 4）
	for area in get_overlapping_areas():
		var target := _find_hittable(area)
		if target != null:
			_resolve_hit(target, area.global_position)
			return

	# 2) 再看有没有撞到地形（layer 1，排除射手自己）
	for body in get_overlapping_bodies():
		if body == shooter:
			continue
		_despawn()
		return

	if _frames >= life_frames:
		_despawn()


## 从受击盒往上找到真正能挨打的那个节点（约定：带 take_hit 的祖先）。
## 用 has_method 而不是硬编码节点名，这样换敌人/换受击盒都还能用。
func _find_hittable(from: Node) -> Node:
	var n := from
	while n != null:
		if n.has_method(&"take_hit"):
			return n
		n = n.get_parent()
	return null


func _resolve_hit(target: Node, point: Vector2) -> void:
	_spent = true
	# 击退方向就是弹丸飞行方向：把飞行方向当成"攻击者的朝向"传进去，
	# take_hit 里的 knockback_velocity(facing) 就能直接算出正确的击退向量。
	var px := point.x if point != Vector2.ZERO else global_position.x
	# 第 7 个参数是 attacker（= 射手）。弹丸也能被弹刀弹开 ——
	# 不带过去的话，玩家在招架判定帧里被弹丸打到只会照常掉血（静默失效）。
	var res: Variant = target.take_hit(move, facing, Vector2(px, global_position.y),
			0.0, false, 1.0, shooter)
	if res != true:
		if shooter != null and is_instance_valid(shooter) \
				and shooter.get(&"hitstop_frames") != null:
			shooter.hitstop_frames = maxi(int(shooter.hitstop_frames), shooter_hitstop)
		hit_target.emit(target, global_position)
	_despawn()


func _despawn() -> void:
	_spent = true
	queue_free()
