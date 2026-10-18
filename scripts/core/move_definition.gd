class_name MoveDefinition
extends Resource
## 招式数据定义（对应设计文档 §3.3）。
##
## 这是"加卡牌/加技能 = 加一个 .tres，不改代码"的那张表。
## 帧数据全部以 60 fps 为基准（Godot 物理帧默认也是 60 Hz）。

@export_group("标识")
@export var id: StringName = &""
@export var display_name: String = ""

@export_group("输入条件")
## -1 = 需要按 ↓，0 = 无方向要求，1 = 需要按 ↑
@export_range(-1, 1, 1) var direction: int = 0
@export var is_air: bool = false
@export var command: StringName = &""          ## 例如 &"light" / &"heavy"

@export_group("帧数据 (60fps)")
@export var startup_frames: int = 4
@export var active_frames: int = 3
@export var recovery_frames: int = 10

@export_group("效果")
@export var damage: float = 10.0
## 击退初速，单位 px/s
@export var knockback: float = 300.0
## 击退角度（度）。0 = 水平，负数 = 向上挑
@export var knockback_angle: float = 0.0
## 撞墙二次伤害系数（设计文档 §2.1：轻击 ×0.5，重击 ×0.8）
@export var wall_damage_factor: float = 0.5
## 强制把目标抛向空中（上挑、连续浮空追击用）。
## 为真时击退向量会被"至少这么多向上速度"兜底，保证真的打飞而不是蹭一下。
@export var forces_launch: bool = false
@export var launch_speed: float = 480.0
## 控制（设计文档 §4）：命中后目标硬直多少帧。0 = 无控制。
@export var stun_frames: int = 0
## 命中时的前冲位移（px）。这是"冲上去打"的顿挫感来源，0 = 原地出招。
@export var lunge: float = 0.0

@export_group("打击感")
## 命中顿帧帧数（设计文档 §2.3：轻击 4–6，重击 8–10）
@export var hitstop_frames: int = 5
## 对方顿帧帧数（一般和 hitstop_frames 相同；第三段/蓄力会故意拉长）
@export var victim_hitstop_frames: int = 5
@export var shake_amount: float = 4.0
## 命中时的挤压拉伸强度：(1.35, 0.72) 之类
@export var squash: Vector2 = Vector2(1.35, 0.72)

@export_group("蓄力")
## 长按蓄力的招式：按住攻击键蓄力，松开才出手。
@export var is_charge: bool = false
@export var min_charge_frames: int = 22
@export var max_charge_frames: int = 48
## 满蓄力时伤害/击退的额外倍率
@export var charge_damage_bonus: float = 1.9
@export var charge_knockback_bonus: float = 1.7
@export var charge_hitstop_bonus: int = 6

@export_group("连段")
@export var next_move: MoveDefinition = null
## 后摇第几帧起允许取消/接下一段（设计文档 §2.2：后摇开始后第 2 帧）
@export var cancel_frame: int = 1
@export var cancel_into: Array[StringName] = []

@export_group("弹刀")
## 这是一个"招架"招式：**判定帧内**被攻击打到，就把来招弹开 ——
## 自己不受伤、攻击者后仰硬直。
##
## 【为什么是一个 bool 标志，而不是靠 id 判】和 `is_ranged()` 同一条规矩：
## "哪种招式算招架"只能有一个来源。将来加"上段弹刀 / 空中弹刀"，
## 只要把这一项打开，player.gd 的判定逻辑一行都不用改。
##
## 判定窗口的长度 = 本招式的 active_frames（帧数据那一栏），
## 所以"弹刀松不松"是在工坊里调 active_frames，不是改代码。
@export var is_parry: bool = false


## 是不是远程招式（扔东西，没有挥砍动作）。
##
## 【判这个问题的地方只该有这一处】以前 `String(mv.id) == "ranged_1"` 在
## main.gd 和 level_director.gd 各写了一遍，两处都得记得改。用 `command`
## 而不是 `id`：加第二个远程招式时只要把 command 填成 &"ranged"，
## "不挥空 / 走投掷音 / 轻震屏"三条规则会一起跟上。
func is_ranged() -> bool:
	return command == &"ranged"


## 是不是招架招式。同 `is_ranged()`：判这个问题的地方只该有这一处。
##
## 【为什么要包一层方法而不是直接读字段】跨脚本拿到的招式是 `Resource`，
## 直接读 `.is_parry` 会在"这是个别的 Resource 类型"时抛解析错误；
## 走方法就能用 has_method 先问一句。见 player.is_parrying();
func is_parry_move() -> bool:
	return is_parry


## 整个招式的总帧数
func total_frames() -> int:
	return startup_frames + active_frames + recovery_frames


## 第 f 帧属于哪个阶段。f 从 0 开始。
func phase_at(f: int) -> StringName:
	if f < startup_frames:
		return &"startup"
	if f < startup_frames + active_frames:
		return &"active"
	if f < total_frames():
		return &"recovery"
	return &"done"


## 击退速度向量。facing = 1 朝右 / -1 朝左。
## forces_launch 为真时，向上那一份会被 launch_speed 兜底，保证真的打飞起来。
func knockback_velocity(facing: int) -> Vector2:
	var rad := deg_to_rad(knockback_angle)
	# Godot 的 Y 轴向下为正，所以"向上挑"的负角度要再取反一次
	var v := Vector2(cos(rad) * facing, -sin(rad)) * knockback
	if forces_launch:
		v.y = minf(v.y, -absf(launch_speed))
	return v

# Unified modifier data, foot-relative hitbox centre + dimensions.
@export var animation: String = "attack_1"
@export var animation_fps: float = 36.0
@export var hitbox: Rect2 = Rect2(Vector2(100,-90),Vector2(200,136))
@export var movement_scale: float = 0.62
@export var startup_movement_scale: float = 0.372
@export var recovery_movement_scale: float = 0.465
@export var effect: String = ""

## Optional desktop action mechanics. Times are normalized animation progress,
## distances are cumulative pixels; physics applies each delta through collision.
@export var dash_distance: float = 0.0
@export var movement_timeline: Array = []
@export var air_gravity_scale: float = 1.0
@export var air_suspend_frames: int = 0

func distance_at(progress: float) -> float:
	var t := clampf(progress, 0.0, 1.0)
	var previous_time := 0.0
	var previous_distance := 0.0
	for point in movement_timeline:
		var end_time := clampf(float(point.get("time", 1.0)), previous_time, 1.0)
		var end_distance := float(point.get("distance", dash_distance))
		if t <= end_time:
			var weight := clampf((t - previous_time) / maxf(end_time - previous_time, 0.00001), 0.0, 1.0)
			return lerpf(previous_distance, end_distance, weight)
		previous_time = end_time
		previous_distance = end_distance
	return previous_distance if not movement_timeline.is_empty() else dash_distance * t
