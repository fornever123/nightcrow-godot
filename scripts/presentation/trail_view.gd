extends Node2D
const Art := preload("res://scripts/presentation/art_cache.gd")
var setup: Dictionary = {}
var display_scale: float = 1.0
var sprite: Sprite2D
var time: float = 0.0
var last_pose: int = -1
var following: bool = true
var stale: int = 0
var hold: float = 0.06

func _ready() -> void:
	z_index = 3
	sprite = Sprite2D.new()
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	sprite.visible = false
	add_child(sprite)

func sync_pose(pose: int, feet: Vector2, facing: int, fps: float) -> void:
	if not following:
		return
	global_position = feet
	scale.x = facing
	time = float(pose) / maxf(fps, 1)
	if pose != last_pose:
		stale = 0
	last_pose = pose
	if pose >= 10:
		following = false

func tick(delta: float, frozen: bool) -> void:
	if not frozen:
		stale += 1
		if stale > 3:
			following = false
		if not following:
			if hold > 0:
				hold = maxf(0.0, hold - delta)
			else:
				time += delta * float(setup.get("erosionSpeed", 0.8))
	var frames: Array = setup.get("frames", [])
	var index := int(time * float(setup.get("fps", 90)))
	if index >= frames.size():
		queue_free()
		return
	Art.apply(sprite, frames[index], display_scale)
