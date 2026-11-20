extends RefCounted
## 敌人、波次、关卡规则：默认值在 assets/data/encounters.json，修改器的改动由 tuning.gd 叠加。
const Tuning := preload("res://scripts/core/tuning.gd")
const PATH := "res://assets/data/encounters.json"
## JSON 数字读出来都是 float；这些字段原来是 int，要转回去。
const INT_FIELDS := ["windup", "strike", "recover", "cool_min", "cool_max", "stun", "guard_frames", "down"]


static func read() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not (parsed is Dictionary):
		push_error("无法读取 %s" % PATH)
		return {}
	return Tuning.apply("encounters", parsed)


## ids：敌人名字 → 枚举值（shade.gd 的 KIND_IDS）。返回键为枚举 int 的字典。
static func kinds(ids: Dictionary) -> Dictionary:
	var source: Dictionary = read().get("kinds", {})
	var result := {}
	for id in ids:
		if not source.has(id):
			push_error("encounters.json 缺少敌人 %s" % id)
			continue
		var spec: Dictionary = source[id].duplicate(true)
		for field in INT_FIELDS:
			if spec.has(field):
				spec[field] = int(spec[field])
		result[int(ids[id])] = spec
	return result


static func waves(ids: Dictionary) -> Array:
	var result: Array = []
	for seal in read().get("waves", []):
		var seal_waves: Array = []
		for wave in seal:
			var w: Dictionary = wave.duplicate(true)
			w.spawns = _kinds_of(wave.get("spawns", []), ids)
			if wave.has("reinforce"):
				w.reinforce = _kinds_of(wave.reinforce, ids)
			if wave.has("reinforce_at"):
				w.reinforce_at = int(wave.reinforce_at)
			if wave.has("max_attackers"):
				w.max_attackers = int(wave.max_attackers)
			seal_waves.append(w)
		result.append(seal_waves)
	return result


static func _kinds_of(names: Array, ids: Dictionary) -> Array:
	var result: Array = []
	for n in names:
		if ids.has(n):
			result.append(int(ids[n]))
		else:
			push_warning("波次里有未知敌人 %s，已跳过" % n)
	return result


static func rules() -> Dictionary:
	return read().get("rules", {})
