extends Node
## 修改器点“应用”后，游戏自动重载当前场景。只在调试版里存在（见 tuning.gd 的 attach_watch）。
const POLL_SECONDS := 0.5

var path := ""
var _stamp := 0
var _clock := 0.0
var _reloading := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_stamp = _modified_time()


func _process(delta: float) -> void:
	_clock += delta
	if _clock < POLL_SECONDS or _reloading:
		return
	_clock = 0.0
	if _modified_time() == _stamp:
		return
	_reloading = true
	Engine.time_scale = 1.0
	get_tree().paused = false
	get_tree().reload_current_scene.call_deferred()


func _modified_time() -> int:
	return FileAccess.get_modified_time(path) if FileAccess.file_exists(path) else 0
