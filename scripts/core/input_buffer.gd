class_name InputBuffer
extends RefCounted
## 输入环形队列（设计文档 §2.4 / §3.2）。
##
## Godot 的 InputMap 只能定义单键动作，不支持"↑ + 攻击"这种组合键，
## 也不能回溯"玩家在攻击前 12 帧内是否按过 ↑"。
## 所以这里维护最近 N 帧的输入历史，招式匹配时回溯查询。
##
## 关键设计：**压入发生在顿帧之前**。
## 角色自己数帧的 hitstop 会让 _physics_process 提前 return，
## 如果输入采样写在那个 return 后面，顿帧期间按的键就丢了。见 player.gd 的顺序。

const DEFAULT_SIZE: int = 24
## 单帧快照
class Frame:
	var actions: Array[StringName] = []
	var axis: Vector2 = Vector2.ZERO
	var pressed_this_frame: Array[StringName] = []
	## 单调递增的全局帧序号（由 InputBuffer.push 盖上）。
	## 用来唯一标识"哪一次按下" —— 不能用"距今多少帧"来标识，
	## 因为不同时刻的两次按下可能落在同一个帧龄上，导致新按键被误判成已消费。
	##
	## 注意：这个值【必须由 push 来盖】。手工构造 Frame 的地方（测试的
	## _make_frame）不会也不能自己分配 seq，否则会出现"帧龄不同但 seq 相同"
	## 或者"seq 恒为 -1"的假边沿。消费者只应该比较 push 之后的 seq。
	var seq: int = -1

var _size: int
var _frames: Array[Frame] = []
var _head: int = 0
var _count: int = 0
var _seq: int = 0
## Actor-active time: hitstop still records fresh input, without aging it out.
var _logic_clock: int = 0
var _logic_stamps: PackedInt64Array = []
## 上一帧压进来的是哪个对象。同一个对象被连续压入时，它代表的是
## "同一条按下边沿在多帧里被重放"（测试的粘住帧就是这样），
## 这时必须复用 seq，否则一次真实的按下会被数成很多次按下。
var _last_frame: Frame = null


func _init(size: int = DEFAULT_SIZE) -> void:
	_size = maxi(size, 4)
	_frames.resize(_size)
	_logic_stamps.resize(_size)
	for i in _size:
		_frames[i] = Frame.new()


## 每物理帧调用一次，必须在角色自己的 hitstop 判定之前。
##
## seq 在这里统一盖章：只要压入的是【新的 Frame 对象】，就得到一个新的 seq，
## 边沿因此天然不会被重复消费。测试注入的粘住帧是同一个对象，会复用 seq，
## 于是"按住"= 一条边沿，和真人按住键的行为完全一致。
func push(frame: Frame, advance_clock: bool = true) -> void:
	if advance_clock:
		_logic_clock += 1
	if frame == _last_frame:
		frame.seq = _seq
	else:
		_seq += 1
		frame.seq = _seq
		_last_frame = frame
	_head = (_head + 1) % _size
	_frames[_head] = frame
	_logic_stamps[_head] = _logic_clock
	_count = mini(_count + 1, _size)


## Age measured in actionable ticks; raw frame_at remains real-time history
## for tightly timed simultaneous commands such as J+K.
func logic_age_at(ago: int) -> int:
	if ago < 0 or ago >= _count:
		return _size
	return _logic_clock - _logic_stamps[_index(-ago)]


## 采样当前 Input 状态，组装成一个 Frame。
static func sample(tracked: Array[StringName], axis_actions: Array[StringName] = []) -> Frame:
	var f := Frame.new()
	for a in tracked:
		if Input.is_action_pressed(a):
			f.actions.append(a)
		if Input.is_action_just_pressed(a):
			f.pressed_this_frame.append(a)
	if axis_actions.size() == 4:
		f.axis = Input.get_vector(axis_actions[0], axis_actions[1], axis_actions[2], axis_actions[3])
	return f


## 最近 n 帧内是否【按下过】某个动作（边沿，不是按住）。
func pressed_within(action: StringName, n: int) -> bool:
	for i in mini(n, _count):
		if _frames[_index(-i)].pressed_this_frame.has(action):
			return true
	return false


## 最近 n 帧内是否【按住过】某个动作。
func held_within(action: StringName, n: int) -> bool:
	for i in mini(n, _count):
		if _frames[_index(-i)].actions.has(action):
			return true
	return false


## 取最近 n 帧内按住过动作的那一帧（离现在最近的一帧）。
func last_held_frame(action: StringName, n: int) -> Frame:
	for i in mini(n, _count):
		var f := _frames[_index(-i)]
		if f.actions.has(action):
			return f
	return null


## 最近一帧的输入轴
func current_axis() -> Vector2:
	if _count == 0:
		return Vector2.ZERO
	return _frames[_head].axis


## 已记录的帧数（上限为构造时给的 size）
func frame_count() -> int:
	return _count


## 取"距今 ago 帧"的那一帧；ago=0 是最近一帧。越界返回 null。
func frame_at(ago: int) -> Frame:
	if ago < 0 or ago >= _count:
		return null
	return _frames[_index(-ago)]


## 调试/UI 用：把最近 n 帧的按键压成一行短字符串，旧的在前。
func debug_string(n: int = 12) -> String:
	var out: Array[String] = []
	var total := mini(n, _count)
	for i in range(total - 1, -1, -1):
		var f := _frames[_index(-i)]
		if f.pressed_this_frame.is_empty():
			out.append("·")
		else:
			var tags: Array[String] = []
			for a in f.pressed_this_frame:
				tags.append(String(a).substr(0, 3).to_upper())
			out.append("[%s]" % "+".join(tags))
	return " ".join(out)


## 清空历史帧。
##
## 故意【不】重置 _seq 和 _last_frame：
##   - _seq 保持单调递增，清零后新边沿不会撞上旧的 seq 值（撞上就会被误判成"已消费"）。
##   - _last_frame 保留，避免"清空后又压入同一个粘住帧对象"被当成新边沿。
func clear() -> void:
	_count = 0
	_head = 0


func _index(offset: int) -> int:
	return ((_head + offset) % _size + _size) % _size
