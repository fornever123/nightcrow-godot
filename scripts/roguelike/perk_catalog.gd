extends RefCounted
## 断晓肉鸽 · 万象牌库目录读取器（Pandora 唯一数据源 + 强度分级权重池）。
## 读取五大类共 39 张卡牌：
##   - 4 张【本命核心牌】（core_rift / core_crow / core_chrono / core_bell）
##   - 4 张【基础属性牌】（stat_atk / stat_spd / stat_crit / stat_def）
##   - 8 张【商店效果牌】（含嗜血残酒、磐石韧膏、踏夜凌空、定心墨露、禁招残页等）
##   - 14 张【升级天赋】（含血月汲魂、铁骨凝躯、碎壳蚀锋、鸦影回流、评分与搓招天赋等）
##   - 9 张【合成锦囊】（含永恒华章、残夜血誓、司辰全书等；司辰全书需先获得永恒华章后解锁）

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
	"effect_style_tonic",
	"effect_skill_scroll",
	"effect_blood_vial",
	"effect_poise_salve",
	"effect_air_step",
	"effect_thorn_coat",
	"effect_focus_lens",
	"effect_ult_elixir",
	"effect_execute_edge",
]

const TALENT_ORDER: Array[String] = [
	"talent_free_roll",
	"talent_buy_rebate",
	"talent_synth_boost",
	"talent_study",
	"talent_tier_gift",
	"talent_pocket_watch",
	"talent_style_anchor",
	"talent_hit_shield",
	"talent_skill_unlock_1",
	"talent_skill_mastery",
	"talent_lifesteal",
	"talent_poise",
	"talent_shell_shred",
	"talent_shadow_flow",
	"talent_perfect_parry_heal",
	"talent_dash_nova",
	"talent_combo_surge",
	"talent_immortal_clock",
]

const TACTIC_ORDER: Array[String] = [
	"tactic_summon_core",
	"tactic_gild_shop",
	"tactic_free_page",
	"tactic_duplicator",
	"tactic_break_limit",
	"tactic_enlighten",
	"tactic_unlock_all_skills",
	"tactic_style_floor",
	"tactic_blood_oath",
	"tactic_shadow_overdrive",
	"tactic_chrono_overclock",
	"tactic_eclipse_crown",
]

## 按各牌对人物实际强度影响分为四阶（common / uncommon / rare / mythic），数值越大越容易刷出
const RARITY_LABELS := {
	"common": "普通",
	"uncommon": "精良",
	"rare": "稀有",
	"mythic": "传说",
}

const RARITY_COLORS := {
	"common": Color("9aa4b8"),
	"uncommon": Color("9ad0ff"),
	"rare": Color("c89eff"),
	"mythic": Color("f5dfa3"),
}

const CARD_TIERS := {
	# 商店效果牌（12 张，按对战斗强度影响分为普通 / 精良 / 稀有）
	"effect_surge": {"rarity": "common", "weight": 50.0},
	"effect_all_stats": {"rarity": "common", "weight": 48.0},
	"effect_ult_elixir": {"rarity": "common", "weight": 46.0},
	"effect_style_tonic": {"rarity": "common", "weight": 44.0},
	"effect_thorn_coat": {"rarity": "common", "weight": 44.0},
	"effect_quench": {"rarity": "uncommon", "weight": 34.0},
	"effect_focus_lens": {"rarity": "uncommon", "weight": 32.0},
	"effect_blood_vial": {"rarity": "uncommon", "weight": 30.0},
	"effect_poise_salve": {"rarity": "uncommon", "weight": 30.0},
	"effect_air_step": {"rarity": "uncommon", "weight": 28.0},
	"effect_execute_edge": {"rarity": "rare", "weight": 16.0},
	"effect_skill_scroll": {"rarity": "rare", "weight": 15.0},

	# 升级天赋（18 张：普通经济 -> 精良战斗联动 -> 稀有吸血/霸体/保连/连击增伤 -> 传说终局质变）
	"talent_free_roll": {"rarity": "common", "weight": 48.0},
	"talent_buy_rebate": {"rarity": "common", "weight": 46.0},
	"talent_study": {"rarity": "common", "weight": 44.0},
	"talent_pocket_watch": {"rarity": "common", "weight": 42.0},
	"talent_style_anchor": {"rarity": "uncommon", "weight": 32.0},
	"talent_synth_boost": {"rarity": "uncommon", "weight": 30.0},
	"talent_perfect_parry_heal": {"rarity": "uncommon", "weight": 30.0},
	"talent_dash_nova": {"rarity": "uncommon", "weight": 30.0},
	"talent_shell_shred": {"rarity": "uncommon", "weight": 28.0},
	"talent_shadow_flow": {"rarity": "uncommon", "weight": 28.0},
	"talent_hit_shield": {"rarity": "rare", "weight": 17.0},
	"talent_skill_unlock_1": {"rarity": "rare", "weight": 16.0},
	"talent_lifesteal": {"rarity": "rare", "weight": 16.0},
	"talent_poise": {"rarity": "rare", "weight": 16.0},
	"talent_combo_surge": {"rarity": "rare", "weight": 16.0},
	"talent_tier_gift": {"rarity": "mythic", "weight": 9.0},
	"talent_skill_mastery": {"rarity": "mythic", "weight": 9.0},
	"talent_immortal_clock": {"rarity": "mythic", "weight": 8.0},

	# 万象锦囊（12 张：普通经济 -> 精良提速/残影 -> 稀有质变/永恒华章/超频/血誓 -> 传说司辰全书/蚀月王冠）
	"tactic_summon_core": {"rarity": "common", "weight": 46.0},
	"tactic_duplicator": {"rarity": "common", "weight": 44.0},
	"tactic_enlighten": {"rarity": "common", "weight": 42.0},
	"tactic_gild_shop": {"rarity": "uncommon", "weight": 30.0},
	"tactic_free_page": {"rarity": "uncommon", "weight": 28.0},
	"tactic_shadow_overdrive": {"rarity": "uncommon", "weight": 28.0},
	"tactic_break_limit": {"rarity": "rare", "weight": 18.0},
	"tactic_style_floor": {"rarity": "rare", "weight": 18.0},
	"tactic_blood_oath": {"rarity": "rare", "weight": 15.0},
	"tactic_chrono_overclock": {"rarity": "rare", "weight": 15.0},
	"tactic_unlock_all_skills": {"rarity": "mythic", "weight": 10.0},
	"tactic_eclipse_crown": {"rarity": "mythic", "weight": 8.0},
}

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
		var tier_meta: Dictionary = CARD_TIERS.get(cid, {"rarity": "common", "weight": 40.0})
		var rarity := String(tier_meta.get("rarity", "common"))
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
			"rarity": rarity,
			"rarity_label": String(RARITY_LABELS.get(rarity, "普通")),
			"rarity_color": RARITY_COLORS.get(rarity, Color("9aa4b8")),
			"drop_weight": float(tier_meta.get("weight", 40.0)),
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


func get_card_weight(card_id: String, player_tier: int = 1) -> float:
	var meta: Dictionary = CARD_TIERS.get(card_id, {"rarity": "common", "weight": 40.0})
	var base_w := float(meta.get("weight", 40.0))
	var rarity := String(meta.get("rarity", "common"))
	return _scale_weight_by_tier(base_w, rarity, player_tier)


func _scale_weight_by_tier(base_w: float, rarity: String, player_tier: int) -> float:
	var t := clampi(player_tier, 1, 5)
	match rarity:
		"common":
			return base_w * (1.0 - 0.08 * float(t - 1))
		"uncommon":
			return base_w * (1.0 + 0.04 * float(t - 1))
		"rare":
			return base_w * (1.0 + 0.16 * float(t - 1))
		"mythic":
			return base_w * (1.0 + 0.25 * float(t - 1))
	return base_w


func pick_weighted_card_id(candidates: Array[String], rng: RandomNumberGenerator = null, player_tier: int = 1) -> String:
	if candidates.is_empty():
		return ""
	var gen := rng
	if gen == null:
		gen = RandomNumberGenerator.new()
		gen.randomize()
	var total := 0.0
	var weights: Array[float] = []
	for cid in candidates:
		var w := maxf(0.1, get_card_weight(cid, player_tier))
		weights.append(w)
		total += w
	var roll := gen.randf() * total
	var acc := 0.0
	for i in candidates.size():
		acc += weights[i]
		if roll <= acc:
			return candidates[i]
	return candidates[candidates.size() - 1]


func roll_talent_choices(count: int = 3, rng: RandomNumberGenerator = null, exclude_ids: Array = [], player_tier: int = 2) -> Array[Dictionary]:
	return _roll_weighted_pool(_talents, count, rng, exclude_ids, false, player_tier)


func roll_tactic_choices(count: int = 3, rng: RandomNumberGenerator = null, exclude_ids: Array = [], player_tier: int = 2, allow_unlock_all: bool = false) -> Array[Dictionary]:
	var eff_exclude: Array = exclude_ids.duplicate()
	# 前置门禁：司辰全书（tactic_unlock_all_skills）必须在获得永恒华章（tactic_style_floor）之后才能刷出
	if not allow_unlock_all and not eff_exclude.has("tactic_unlock_all_skills"):
		eff_exclude.append("tactic_unlock_all_skills")
	return _roll_weighted_pool(_tactics, count, rng, eff_exclude, true, player_tier, not allow_unlock_all)


func _roll_weighted_pool(source: Array[Dictionary], count: int, rng: RandomNumberGenerator, exclude_ids: Array, fallback_all: bool, player_tier: int, forbid_unlock_all: bool = false) -> Array[Dictionary]:
	var gen := rng
	if gen == null:
		gen = RandomNumberGenerator.new()
		gen.randomize()
	var pool: Array[Dictionary] = []
	for item in source:
		var cid := String(item["card_id"])
		if not exclude_ids.has(cid):
			pool.append(item.duplicate(true))
	if fallback_all and pool.size() < count:
		pool.clear()
		for item in source:
			var cid := String(item["card_id"])
			if forbid_unlock_all and cid == "tactic_unlock_all_skills":
				continue
			pool.append(item.duplicate(true))

	var out: Array[Dictionary] = []
	var want := mini(count, pool.size())
	for _k in want:
		var total := 0.0
		for item in pool:
			var cid := String(item["card_id"])
			total += maxf(0.1, get_card_weight(cid, player_tier))
		var roll := gen.randf() * total
		var acc := 0.0
		var pick_i := pool.size() - 1
		for i in pool.size():
			var cid := String(pool[i]["card_id"])
			acc += maxf(0.1, get_card_weight(cid, player_tier))
			if roll <= acc:
				pick_i = i
				break
		out.append(pool[pick_i])
		pool.remove_at(pick_i)
	return out
