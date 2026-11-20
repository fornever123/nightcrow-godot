extends RefCounted
## 断晓肉鸽 · 万象牌库目录读取器（Pandora 唯一数据源）。
## 读取五大类共 23 张卡牌：
##   - 4 张【本命核心牌】（core_rift / core_crow / core_chrono / core_bell）
##   - 4 张【基础属性牌】（stat_atk / stat_spd / stat_crit / stat_def）
##   - 3 张【商店效果牌】（effect_quench / effect_all_stats / effect_surge）
##   - 6 张【升级天赋】（talent_free_roll / talent_buy_rebate / talent_synth_boost / talent_study / talent_tier_gift / talent_pocket_watch）
##   - 6 张【合成锦囊】（tactic_summon_core / tactic_gild_shop / tactic_free_page / tactic_duplicator / tactic_break_limit / tactic_enlighten）

const PandoraApi := preload("res://addons/pandora/api.gd")

const CORE_ORDER: Array[String] = [
	"core_rift",
	"core_crow",
	"core_chrono",
	"core_bell",
]

const STAT_ORDER: Array[String] = [
	"stat_atk",
	"stat_spd",
	"stat_crit",
	"stat_def",
]

const EFFECT_ORDER: Array[String] = [
	"effect_quench",
	"effect_all_stats",
	"effect_surge",
]

const TALENT_ORDER: Array[String] = [
	"talent_free_roll",
	"talent_buy_rebate",
	"talent_synth_boost",
	"talent_study",
	"talent_tier_gift",
	"talent_pocket_watch",
]

const TACTIC_ORDER: Array[String] = [
	"tactic_summon_core",
	"tactic_gild_shop",
	"tactic_free_page",
	"tactic_duplicator",
	"tactic_break_limit",
	"tactic_enlighten",
]

var _all_cards: Array[Dictionary] = []
var _cores: Array[Dictionary] = []
var _stats: Array[Dictionary] = []
var _effects: Array[Dictionary] = []
var _talents: Array[Dictionary] = []
var _tactics: Array[Dictionary] = []
var _by_id: Dictionary = {}


func _init(tree: SceneTree = null) -> void:
	reload(tree)


func reload(tree: SceneTree = null) -> void:
	_all_cards.clear()
	_cores.clear()
	_stats.clear()
	_effects.clear()
	_talents.clear()
	_tactics.clear()
	_by_id.clear()

	var loop: SceneTree = tree if tree != null else (Engine.get_main_loop() as SceneTree)
	var existing_api: Node = null
	if loop != null and loop.root != null:
		existing_api = loop.root.get_node_or_null("Pandora")

	var temp_api: Node = null
	var api: Node = existing_api
	if api == null:
		temp_api = PandoraApi.new()
		temp_api._enter_tree()
		api = temp_api
	elif api.has_method("is_loaded") and not bool(api.call("is_loaded")):
		api.call("load_data")

	var entities: Array = api.call("get_all_entities")
	for raw in entities:
		var ent := raw as PandoraEntity
		if ent == null:
			continue
		var cid := ent.get_string("card_id")
		if cid == "":
			continue
		var hex := ent.get_string("accent_hex")
		if hex == "":
			hex = "b678ff"
		var kind := ent.get_string("card_kind")
		var item := {
			"entity_id": ent.get_entity_id(),
			"entity_name": ent.get_entity_name(),
			"card_id": cid,
			"perk_id": cid,
			"card_kind": kind,
			"title": ent.get_string("title"),
			"subtitle": ent.get_string("subtitle"),
			"summary": ent.get_string("summary"),
			"tier_10": ent.get_string("tier_10"),
			"tier_40": ent.get_string("tier_40"),
			"tier_100": ent.get_string("tier_100"),
			"accent_hex": hex,
			"accent_color": Color(hex),
			"base_gain": maxi(0, roundi(ent.get_float("base_gain"))),
			"cost": maxi(0, roundi(ent.get_float("cost"))),
		}
		_all_cards.append(item)
		_by_id[cid] = item

	if temp_api != null:
		temp_api._exit_tree()
		temp_api.free()

	for cid in CORE_ORDER:
		if _by_id.has(cid):
			_cores.append((_by_id[cid] as Dictionary).duplicate(true))
	for cid in STAT_ORDER:
		if _by_id.has(cid):
			_stats.append((_by_id[cid] as Dictionary).duplicate(true))
	for cid in EFFECT_ORDER:
		if _by_id.has(cid):
			_effects.append((_by_id[cid] as Dictionary).duplicate(true))
	for cid in TALENT_ORDER:
		if _by_id.has(cid):
			_talents.append((_by_id[cid] as Dictionary).duplicate(true))
	for cid in TACTIC_ORDER:
		if _by_id.has(cid):
			_tactics.append((_by_id[cid] as Dictionary).duplicate(true))


func get_all_cards() -> Array[Dictionary]:
	return _all_cards.duplicate(true)


func get_core_cards() -> Array[Dictionary]:
	return _cores.duplicate(true)


func get_stat_cards() -> Array[Dictionary]:
	return _stats.duplicate(true)


func get_effect_cards() -> Array[Dictionary]:
	return _effects.duplicate(true)


func get_talent_cards() -> Array[Dictionary]:
	return _talents.duplicate(true)


func get_tactic_cards() -> Array[Dictionary]:
	return _tactics.duplicate(true)


func has_card(card_id: String) -> bool:
	return _by_id.has(card_id)


func get_card(card_id: String) -> Dictionary:
	if not _by_id.has(card_id):
		return {}
	return (_by_id[card_id] as Dictionary).duplicate(true)


func has_perk(card_id: String) -> bool:
	return has_card(card_id)


func get_perk(card_id: String) -> Dictionary:
	return get_card(card_id)


func roll_talent_choices(count: int = 3, rng: RandomNumberGenerator = null, exclude_ids: Array[String] = []) -> Array[Dictionary]:
	return _roll_from_pool(_talents, count, rng, exclude_ids, false)


func roll_tactic_choices(count: int = 3, rng: RandomNumberGenerator = null, exclude_ids: Array[String] = []) -> Array[Dictionary]:
	return _roll_from_pool(_tactics, count, rng, exclude_ids, true)


func _roll_from_pool(source: Array[Dictionary], count: int, rng: RandomNumberGenerator, exclude_ids: Array[String], fallback_all: bool) -> Array[Dictionary]:
	var gen := rng
	if gen == null:
		gen = RandomNumberGenerator.new()
		gen.randomize()
	var pool: Array[Dictionary] = []
	for item in source:
		if not exclude_ids.has(String(item["card_id"])):
			pool.append(item.duplicate(true))
	if fallback_all and pool.size() < count:
		pool = source.duplicate(true)
	_shuffle_with_rng(pool, gen)
	var out: Array[Dictionary] = []
	for i in mini(count, pool.size()):
		out.append(pool[i])
	return out


func _shuffle_with_rng(arr: Array[Dictionary], rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
