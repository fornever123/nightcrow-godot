extends Node
## 一段遭遇战 = 一个封印竞技场里依次刷出的若干波影子（试玩版 §7）。
##
## 只管"什么时候刷谁、刷在哪、这一波打完没有"。封印墙、镜头锁定、结算由 night_trial.gd 处理。
## 每一波的数据：
##   {"label": "影卒来袭", "spawns": [Kind…], "reinforce": [Kind…], "reinforce_at": 剩几只时增援,
##    "max_attackers": 同时最多几只出刀}

const Shade := preload("res://scripts/night/shade.gd")

signal wave_started(wave_index: int, wave_count: int, label: String)
signal wave_cleared(wave_index: int, wave_count: int)
signal cleared()
signal shade_spawned(shade: Node2D)

var waves: Array = []
var arena_left: float = 0.0
var arena_right: float = 1280.0
var floor_y: float = 580.0
var hp_mul: float = 1.0
var target: Node2D
var host: Node
## 多层地形（第三轮节点 17）：有的话影子会从 spawn_points 里挑出生点（可能站在平台上）
var terrain = null
var spawn_points: Array = []        ## [Vector2(x, 脚底 y)]，按“右、左、右、左…”交替排
var _spawn_i: int = 0

var wave_index: int = -1
var alive: Array = []
var running: bool = false
var finished: bool = false
var _queue: Array = []          ## 待刷出：[{kind, delay}]
var _reinforce: Array = []
var _reinforce_at: int = 0
var _max_attackers: int = 1
var _gap_frames: int = 0
var _spawn_side: int = 1


func setup(p_waves: Array, left: float, right: float, p_floor_y: float, p_target: Node2D,
		p_host: Node, p_hp_mul: float) -> void:
	waves = p_waves
	arena_left = left
	arena_right = right
	floor_y = p_floor_y
	target = p_target
	host = p_host
	hp_mul = p_hp_mul
	_spawn_i = 0


func start(from_wave: int = 0) -> void:
	running = true
	finished = false
	wave_index = from_wave - 1
	_wave_reported = true
	_gap_frames = 30
	_queue.clear()
	_reinforce.clear()


## 玩家倒下后：清场，从当前波重新开始
func restart_wave() -> void:
	clear_shades()
	var w := maxi(wave_index, 0)
	start(w)


func clear_shades() -> void:
	for s in alive:
		if is_instance_valid(s):
			s.queue_free()
	alive.clear()
	_queue.clear()
	_reinforce.clear()


func alive_count() -> int:
	var n := 0
	for s in alive:
		if is_instance_valid(s) and s.state != Shade.State.DEAD:
			n += 1
	return n


func _physics_process(_delta: float) -> void:
	if not running:
		return
	alive = alive.filter(func(s): return is_instance_valid(s))
	# 刷怪队列（一只一只错开出来，读得清）
	if not _queue.is_empty():
		_queue[0].delay -= 1
		if _queue[0].delay <= 0:
			_spawn(int(_queue.pop_front().kind))
		return
	var n := alive_count()
	if not _reinforce.is_empty() and n <= _reinforce_at:
		for i in _reinforce.size():
			_queue.append({"kind": _reinforce[i], "delay": 20 if i == 0 else 16})
		_reinforce.clear()
		return
	if n > 0:
		return
	if _gap_frames > 0:
		_gap_frames -= 1
		return
	if wave_index >= 0 and wave_index < waves.size() and not _wave_reported:
		_wave_reported = true
		wave_cleared.emit(wave_index, waves.size())
		_gap_frames = 70
		return
	if wave_index + 1 >= waves.size():
		running = false
		finished = true
		cleared.emit()
		return
	_begin_wave(wave_index + 1)


var _wave_reported: bool = true


func _begin_wave(idx: int) -> void:
	wave_index = idx
	_wave_reported = false
	var w: Dictionary = waves[idx]
	_max_attackers = int(w.get("max_attackers", 1))
	_reinforce = (w.get("reinforce", []) as Array).duplicate()
	_reinforce_at = int(w.get("reinforce_at", 0))
	var spawns: Array = w.get("spawns", [])
	for i in spawns.size():
		_queue.append({"kind": spawns[i], "delay": 24 if i == 0 else 18})
	_gap_frames = 40
	wave_started.emit(idx, waves.size(), String(w.get("label", "")))


func _spawn(kind: int) -> void:
	var s: Node2D = Node2D.new()
	s.set_script(Shade)
	s.setup(kind, target, floor_y, hp_mul)
	s.arena_left = arena_left
	s.arena_right = arena_right
	s.max_attackers = _max_attackers
	s.terrain = terrain
	if not spawn_points.is_empty():
		var p := _pick_spawn_point()
		s.position = Vector2(p.x, p.y - float(Shade.KINDS[kind].half_h))
		s.facing = -1 if p.x > (arena_left + arena_right) * 0.5 else 1
		_add(s)
		return
	# 交替从两侧出来；离玩家太近就换另一侧
	var margin := 110.0 + float(_rng_offset())
	var x := arena_right - margin if _spawn_side > 0 else arena_left + margin
	if target != null and is_instance_valid(target) and absf(x - target.global_position.x) < 260.0:
		_spawn_side = -_spawn_side
		x = arena_right - margin if _spawn_side > 0 else arena_left + margin
	_spawn_side = -_spawn_side
	s.position = Vector2(x, floor_y - 60.0)
	s.facing = -1 if x > (arena_left + arena_right) * 0.5 else 1
	_add(s)


func _add(s: Node2D) -> void:
	host.add_child(s)
	alive.append(s)
	s.died.connect(_on_died.bind(s))
	shade_spawned.emit(s)


## 依次取出生点，跳过离玩家太近（< 300）的
func _pick_spawn_point() -> Vector2:
	var n := spawn_points.size()
	for k in n:
		var p: Vector2 = spawn_points[(_spawn_i + k) % n]
		if target == null or not is_instance_valid(target) or absf(p.x - target.global_position.x) >= 300.0:
			_spawn_i = (_spawn_i + k + 1) % n
			return p
	var q: Vector2 = spawn_points[_spawn_i % n]
	_spawn_i = (_spawn_i + 1) % n
	return q


var _offset_i: int = 0
func _rng_offset() -> int:
	_offset_i = (_offset_i + 1) % 3
	return _offset_i * 70


func _on_died(_s: Node2D) -> void:
	pass
