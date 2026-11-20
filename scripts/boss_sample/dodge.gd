extends Node
## 玩法线 Boss 小样：占位短闪。外挂在玩家身上，不改 player.gd。
## 约 0.2 秒，任何招式都能取消（被打飞、大招中除外）。没有专门动作帧，靠残影表示。
## 闪过敌人的招后，下一刀变重。

signal started(dir: int)
signal heavy_armed()
signal heavy_landed(target: Node2D, point: Vector2)

const ACTION := &"sample_dodge"
## 11-07 用户试玩：“这个短闪不好用，太慢了”。原来 12 帧 1500 px/秒、冷却 16 帧，闪过还慢放 0.14 秒。
## 现在 8 帧 2400 px/秒（距离差不多），冷却 4 帧，不慢放。
const FRAMES := 8                   ## 约 0.13 秒
const INVULN := 10                  ## 比位移多 2 帧，留一点余量
const SPEED := 2400.0               ## 约 280 px
const COOLDOWN := 4
const COUNTS_FOR := 14              ## 按下后这么多帧内，敌人出刀都算闪过
const HEAVY_MUL := 1.7
const HEAVY_FRAMES := 180           ## 3 秒内不出手，变重就没了

var player: CharacterBody2D
var _left: int = 0
var _dir: int = 1
var _cool: int = 0
var _since: int = 999
var _air_used: bool = false
var _heavy: int = 0
var _requested: int = 0             ## 测试用：代替按键（±1）
var refund_on_hit: bool = true      ## 打中就还空中短闪；浮空规则（air_rules.gd）改成只有空a3 还


func _ready() -> void:
	process_physics_priority = 1    # 排在玩家之后
	player.hit_confirmed.connect(_on_hit)


func request(dir: int) -> void:
	_requested = dir


func is_dodging() -> bool:
	return _left > 0


func counts_as_dodge() -> bool:
	return _since <= COUNTS_FOR and player.invuln_frames > 0


func is_heavy() -> bool:
	return _heavy > 0


func arm_heavy() -> void:
	_heavy = HEAVY_FRAMES
	player.attack_damage_mul = HEAVY_MUL
	heavy_armed.emit()


func _physics_process(_delta: float) -> void:
	_since = mini(_since + 1, 999)
	_cool = maxi(_cool - 1, 0)
	if _heavy > 0:
		_heavy -= 1
		if _heavy == 0:
			player.attack_damage_mul = 1.0
	if player.is_on_floor():
		_air_used = false
	if _left > 0:
		_tick()
	var want := _requested
	_requested = 0
	if want == 0 and Input.is_action_just_pressed(ACTION):
		want = _input_dir()
	if want != 0:
		_try_start(want)


func _input_dir() -> int:
	var axis := Input.get_axis(&"move_left", &"move_right")
	if absf(axis) > 0.25:
		return 1 if axis > 0.0 else -1
	return player.facing


func _try_start(dir: int) -> void:
	if _cool > 0 or player.ult_frame >= 0:
		return
	if player.state != player.State.NEUTRAL and player.state != player.State.ATTACK:
		return
	if not player.is_on_floor():
		if _air_used:
			return
		_air_used = true
	_cancel_player()
	_dir = dir
	_left = FRAMES
	_since = 0
	_cool = FRAMES + COOLDOWN
	player.invuln_frames = maxi(player.invuln_frames, INVULN)
	player._set_facing(dir)
	player.velocity = Vector2(float(dir) * SPEED, 0.0)
	player._set_visual_scale(Vector2(1.25, 0.82))
	player._squash_timer = FRAMES
	_ghost()
	started.emit(dir)


## 和 player.gd 的 _try_action_jump_cancel 清同一批状态
func _cancel_player() -> void:
	if player.is_guarding():
		player._stop_guard()
	player._cancel_locomotion()
	player._reset_air_combo()
	player._reaction_guard_held = false
	player.charge_frames = -1
	player._charge_accum = 0.0
	player._charge_t = 0.0
	player.current_move = null
	player.current_is_up = false
	player.finisher_intent = &""
	player._uppercut_jump_pending = false
	player.state = player.State.NEUTRAL
	player.link_open = false
	player._landing_lag = 0
	player.hitstop_frames = 0
	player.hitstop_this_tick = false
	player._attack_hold_frames = 0


func _tick() -> void:
	_left -= 1
	if player.state != player.State.NEUTRAL or player.is_on_wall():
		_left = 0     # 出招或撞墙就结束
		return
	if _left == 0:
		player.velocity.x = float(_dir) * player.speed
		return
	player.velocity = Vector2(float(_dir) * SPEED, 0.0)
	_ghost()


## 占位残影：复制当前这一帧的样子，慢慢淡掉
func _ghost() -> void:
	var src: Sprite2D = player.get_node_or_null("Visual/ActorSprite")
	if src == null or src.texture == null:
		return
	var g := Sprite2D.new()
	g.texture = src.texture
	g.centered = src.centered
	g.offset = src.offset
	g.flip_h = src.flip_h
	g.hframes = src.hframes
	g.vframes = src.vframes
	g.frame = src.frame
	g.region_enabled = src.region_enabled
	g.region_rect = src.region_rect
	g.modulate = Color(0.55, 0.85, 1.0, 0.55)
	g.z_index = src.z_index - 1
	get_parent().add_child(g)
	g.global_transform = src.global_transform
	var t := g.create_tween()
	t.tween_property(g, "modulate:a", 0.0, 0.16)
	t.tween_callback(g.queue_free)


func _on_hit(target: Node2D, _mv: Resource, point: Vector2) -> void:
	if refund_on_hit:
		_air_used = false     # 打中了能再闪一次，好接着追
	if _heavy <= 0 or not target.is_in_group(&"shade"):
		return
	_heavy = 0
	player.attack_damage_mul = 1.0
	target.set(&"hitstop_frames", int(target.get(&"hitstop_frames")) + 8)
	heavy_landed.emit(target, point)
