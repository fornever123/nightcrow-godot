extends Camera2D
## 跟随 + 震屏（设计文档 §2.3 第 2 条）。
##
## 跟随是【自己算】的，不依赖 Camera2D 的自动跟随：
## 自动跟随在这个项目里实测不生效（相机停在初始位置不动），
## 与其猜是 anchor_mode / limit / drag 哪个组合的问题，不如显式钳制，
## 顺便把"镜头永远不越出竞技场"这件事变成一行看得见的代码。
##
## 震屏幅度随攻击力度，方向与击退方向一致；指数衰减回中。
## 用 FastNoiseLite 采样代替纯 randf，避免高频抖动看起来像"闪"而不是"震"。

@export var shake_decay: float = 7.0
@export var max_shake: float = 42.0
@export var frequency: float = 0.85
@export var follow_smoothing: float = 0.0
## 震屏偏移对齐的步长（屏幕像素；镜头缩放后自动换算成世界单位）
@export var pixel_snap: float = 1.0
## 震屏幅度（add_shake 的数值按屏幕像素算）换成世界单位时再乘的系数：
## 镜头缩小（zoom < 1）时世界 1 单位在屏幕上不到 1 像素，乘 1/zoom 才能保持屏幕上的幅度
@export var shake_world_scale: float = 1.0
## 竖直方向固定在这个世界 y（NAN = 按 arena_min/max 钳制）。试玩关卡里镜头只横向跟随。
@export var lock_y: float = NAN
## 跟随位置对齐的步长（屏幕像素，0 = 不对齐）。像素风地形一格 = 2 屏幕像素，
## 镜头停在半像素上时格子边缘会忽宽忽窄；对齐 1 屏幕像素就稳了。内部仍然用没对齐的位置平滑。
@export var position_snap: float = 0.0
var _follow_pos: Vector2 = Vector2(NAN, NAN)

## 跟随目标（由 main.gd 注入）
@export var follow_target: Node2D
## 跑动时镜头往前多看一点（像素）。只在真的跑起来时才转向，顿帧/停下不回弹，避免镜头来回晃。
@export var look_ahead: float = 0.0
var _look: float = 0.0
## 镜头中心被钳制的世界矩形。
##
## 注意它【不等于】竞技场范围：竞技场 1920 宽、视口也是 1920 宽的话，
## 钳制结果永远只有一个点，镜头就等于钉死不动。
## 要留出"能摇"的余量，所以这里用一个更窄的聚焦区，镜头在聚焦区内跟随，
## 超出聚焦区才停住，这样既能跟人、又不会把场地边缘推出画面。
@export var arena_min: Vector2 = Vector2(0, 0)
@export var arena_max: Vector2 = Vector2(1920, 1080)

var _trauma: float = 0.0
var _shake_dir: Vector2 = Vector2.ZERO
var _noise: FastNoiseLite
var _t: float = 0.0


func _ready() -> void:
	_noise = FastNoiseLite.new()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = frequency
	_noise.seed = 20240501
	position_smoothing_enabled = false
	# 注意：这里不能把 enabled 设成 false —— 被禁用的 Camera2D 无法 make_current()，
	# 整个视口就没人渲染了。我们只在 _process 里覆盖 global_position，
	# 引擎自己的跟随逻辑即使跑了也会被下一帧覆盖掉。
	enabled = true
	# 关掉拖动边距，避免引擎的跟随逻辑和我们自己算的位置打架
	drag_horizontal_enabled = false
	drag_vertical_enabled = false
	anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER


func _process(delta: float) -> void:
	_t += delta
	_update_follow(delta)
	_update_shake(delta)


func _update_follow(delta: float) -> void:
	if follow_target == null or not is_instance_valid(follow_target):
		return
	# 视口在【世界坐标】下的半宽高：zoom 是放大倍数，所以要把视口尺寸除以 zoom
	var view := get_viewport_rect().size
	var z := zoom
	if z.x <= 0.0:
		z.x = 1.0
	if z.y <= 0.0:
		z.y = 1.0
	var half := Vector2(view.x * 0.5 / z.x, view.y * 0.5 / z.y)
	var target := follow_target.global_position
	if look_ahead > 0.0 and follow_target is CharacterBody2D:
		var run_speed: Variant = follow_target.get("speed")
		var sp := maxf(float(run_speed) if run_speed != null else 300.0, 1.0)
		var vx := (follow_target as CharacterBody2D).velocity.x
		if absf(vx) > sp * 0.5:
			_look = move_toward(_look, signf(vx) * look_ahead, look_ahead * 1.5 * delta)
		target.x += _look
	# 先钳制目标，保证镜头任何情况下都不会露出竞技场外面
	var lo := arena_min + half
	var hi := arena_max - half
	# 竞技场比视口还小时（理论上不会），退化成取中点
	if lo.x > hi.x:
		target.x = (arena_min.x + arena_max.x) * 0.5
	else:
		target.x = clampf(target.x, lo.x, hi.x)
	if is_finite(lock_y):
		target.y = lock_y
	elif lo.y > hi.y:
		target.y = (arena_min.y + arena_max.y) * 0.5
	else:
		target.y = clampf(target.y, lo.y, hi.y)

	var cur := global_position
	if position_snap > 0.0 and is_finite(_follow_pos.x):
		# 外面直接设过 global_position（开场 / 复活）→ 以外面设的为准
		var step := position_snap / maxf(z.x, 0.01)
		if _follow_pos.snapped(Vector2.ONE * step).distance_to(cur) <= step * 0.75:
			cur = _follow_pos
	var next := target
	if follow_smoothing > 0.0:
		next = cur.lerp(target, clampf(follow_smoothing * delta, 0.0, 1.0))
	if position_snap > 0.0:
		_follow_pos = next
		global_position = next.snapped(Vector2.ONE * position_snap / maxf(z.x, 0.01))
	else:
		global_position = next


func _update_shake(delta: float) -> void:
	if _trauma <= 0.01:
		if offset != Vector2.ZERO:
			offset = Vector2.ZERO
		rotation = 0.0
		return

	_trauma = lerpf(_trauma, 0.0, clampf(shake_decay * delta, 0.0, 1.0))
	var amp := minf(_trauma, max_shake)
	# 采样噪声：两个不同偏移，得到 X/Y 不相关的抖动
	var nx := _noise.get_noise_2d(_t * 60.0, 0.0)
	var ny := _noise.get_noise_2d(0.0, _t * 60.0)
	var result := Vector2(nx, ny) * amp
	# 方向性：沿击退方向再多推一点
	if _shake_dir != Vector2.ZERO:
		result += _shake_dir * amp * 0.8
	offset = result * shake_world_scale
	if pixel_snap > 0.0:
		offset = offset.snapped(Vector2.ONE * pixel_snap / maxf(zoom.x, 0.01))
	# 极轻的滚转让重击更像镜头被撞了一下，不会影响可读性。
	rotation = result.x * 0.00075


## 触发震屏。amount 单位是像素，dir 是击退方向（可为零向量）。
func add_shake(amount: float, dir: Vector2 = Vector2.ZERO) -> void:
	# 冲击叠加：连续命中 / 撞墙不再被一次最大值吞掉。
	_trauma = minf(_trauma + maxf(amount, 0.0) * 1.15, max_shake)
	if dir.length_squared() > 0.01:
		_shake_dir = dir.normalized()

func reset_shake() -> void:
	_trauma = 0.0
	_shake_dir = Vector2.ZERO
	offset = Vector2.ZERO
	rotation = 0.0
