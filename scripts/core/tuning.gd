extends RefCounted
## 修改器的改动层：assets/data/tuning.json 里的“路径 → 值”叠加到默认数据上。
## 路径第一段是文档（battle / encounters / layout），之后按键走；遇到数组按元素的 id 或 name 匹配。
## 字典里还没有的中间键会新建（layout/backdrop/... 默认文档里没有，默认值在 street_backdrop.gd）。
## 默认数据（battle.json、encounters.json）不被修改，恢复默认就是删掉一条。
const PATH := "res://assets/data/tuning.json"
const Watch := preload("res://scripts/core/tuning_watch.gd")

## 只给测试用：非空时无条件代替 tuning.json。
static var test_values: Dictionary = {}


## 无头测试、--script 启动的机器人和录像工具都看默认值。环境变量 NIGHTCROW_TUNING 可强制开（1）或关（0）。
static func enabled() -> bool:
	var forced := OS.get_environment("NIGHTCROW_TUNING")
	if forced == "0":
		return false
	if forced == "1":
		return true
	if DisplayServer.get_name() == "headless":
		return false
	var args := OS.get_cmdline_args()
	return not (args.has("--script") or args.has("-s"))


static func read_values() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not (parsed is Dictionary) or not (parsed.get("values") is Dictionary):
		push_warning("tuning.json 格式不对，已忽略")
		return {}
	return parsed.values


static func apply(doc: String, data: Dictionary) -> Dictionary:
	if not test_values.is_empty():
		return apply_values(doc, data, test_values)
	return apply_values(doc, data, read_values()) if enabled() else data


static func apply_values(doc: String, data: Dictionary, values: Dictionary) -> Dictionary:
	for path in values:
		var parts := String(path).split("/")
		if parts.size() >= 2 and parts[0] == doc:
			_write(data, parts, values[path], String(path))
	return data


static func _write(data: Dictionary, parts: PackedStringArray, value: Variant, path: String) -> void:
	var at: Variant = data
	for i in range(1, parts.size() - 1):
		at = _step(at, parts[i])
		if at == null:
			push_warning("tuning：路径走不通，已跳过 %s" % path)
			return
	if not (at is Dictionary):
		push_warning("tuning：路径走不通，已跳过 %s" % path)
		return
	at[parts[parts.size() - 1]] = value.duplicate(true) if (value is Array or value is Dictionary) else value


static func _step(at: Variant, key: String) -> Variant:
	if at is Dictionary:
		if not at.has(key):
			at[key] = {}
		var next: Variant = at[key]
		return next if (next is Dictionary or next is Array) else null
	if at is Array:
		for element in at:
			if element is Dictionary and (String(element.get("id", "")) == key or String(element.get("name", "")) == key):
				return element
	return null


## 调试版里监视 tuning.json：一保存就重载当前场景。发布版不加。
static func attach_watch(host: Node) -> void:
	if OS.is_debug_build() and enabled():
		var watch: Node = Watch.new()
		watch.name = "TuningWatch"
		watch.path = PATH
		host.add_child(watch)
