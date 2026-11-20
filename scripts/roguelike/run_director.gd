extends Node
## 断晓肉鸽 · 万象牌桌导演（RunDirector）
## 纯正《万象棋》双引擎架构：
##   1. 开局只选 1 张【本命核心牌】（出门 Lv.10，自带 1/3 合成格 ●○○）
##   2. 【升级给天赋】：消耗能量升阶（Lv.1 -> Lv.5，每破一封自动减 2⚡），立得 3 选 1 永久【天赋】，并拔高全店卡牌等级与解锁效果牌
##   3. 【合成给锦囊】：同名牌买满 3 格（●●●）触发三合一暴涨，立得 3 选 1 瞬发【0⚡ 锦囊】

const PerkCatalog := preload("res://scripts/roguelike/perk_catalog.gd")

const SHOP_SIZE := 4
const MAX_PLAYER_TIER := 5

const TIER_UPGRADE_COSTS := {
	1: 5,
	2: 7,
	3: 9,
	4: 11,
}

const TIER_BASE_GAINS := {
	1: 6,
	2: 9,
	3: 13,
	4: 18,
	5: 25,
}

signal table_updated()
signal draft_offered(kind: String, choices: Array[Dictionary])
signal synthesis_triggered(card_id: String, new_level: int)
signal tier_upgraded(new_tier: int)

var stage: Node = null
var perk_rig: Node2D = null
var catalog: RefCounted = null
var rng := RandomNumberGenerator.new()

## 本局构筑状态
var core_id: String = ""
var opening_completed: bool = false
var player_tier: int = 1
var upgrade_discount: int = 0
var active_talents: Array[String] = []

## 牌桌经济与合成进度（core + 四维，满 3 合成送锦囊）
var energy: int = 0
var synth_pips: Dictionary = {
	"core": 0,
	"stat_atk": 0,
	"stat_spd": 0,
	"stat_crit": 0,
	"stat_def": 0,
}
var synth_total: int = 0
var roll_count_total: int = 0
var cards_bought_total: int = 0
var tactics_used_total: int = 0
var duplicator_armed: bool = false
var status_toast: String = ""

## 商店 4 槽位与待选三选一队列（"talent" / "tactic"）
var shop_slots: Array[Dictionary] = []
var pending_draft_kind: String = ""
var pending_draft_choices: Array[Dictionary] = []
var _draft_queue: Array[String] = []
var _resolving_draft: bool = false

## 单段战斗表现统计
var segment_time: float = 0.0
var segment_hits: int = 0
var last_clear_time: float = 0.0
var last_clear_hits: int = 0

## 结算兼容字段
var gold_cores: int = 0
var chosen_perks: Array[String] = []


func _ready() -> void:
	rng.randomize()
	if catalog == null:
		catalog = PerkCatalog.new(get_tree())


func setup(p_stage: Node, p_perk_rig: Node2D, fixed_seed: int = 0) -> void:
	stage = p_stage
	perk_rig = p_perk_rig
	if catalog == null:
		catalog = PerkCatalog.new(p_stage.get_tree() if p_stage != null else null)
	if fixed_seed != 0:
		rng.seed = fixed_seed
	else:
		rng.randomize()


# ---------------------------------------------------------------- 1. 开局选 1 张本命核心

func apply_opening_selection(picked_core_id: String, _legacy_arg: String = "") -> void:
	if picked_core_id == "":
		picked_core_id = "core_rift"
	core_id = picked_core_id
	opening_completed = true
	player_tier = 1
	upgrade_discount = 0
	active_talents.clear()
	chosen_perks.clear()
	chosen_perks.append(core_id)
	synth_pips = {
		"core": 1,
		"stat_atk": 0,
		"stat_spd": 0,
		"stat_crit": 0,
		"stat_def": 0,
	}
	if perk_rig != null:
		perk_rig.set_core_hero(core_id, 10)
	status_toast = ""
	table_updated.emit()


func has_talent(tid: String) -> bool:
	return active_talents.has(tid)


func has_style_floor() -> bool:
	if chosen_perks.has("tactic_style_floor"):
		return true
	return perk_rig != null and int(perk_rig.get("style_rank_floor")) >= 2


func has_unlock_all_skills() -> bool:
	if chosen_perks.has("tactic_unlock_all_skills"):
		return true
	return perk_rig != null and bool(perk_rig.get("skill_unlock_all"))


# ---------------------------------------------------------------- 2. 战斗计时与破封开桌

func begin_segment() -> void:
	segment_time = 0.0
	segment_hits = 0


func tick_combat(delta: float) -> void:
	segment_time += delta


func record_player_hit() -> void:
	segment_hits += 1


func snapshot_segment_clear() -> void:
	last_clear_time = segment_time
	last_clear_hits = segment_hits


func open_seal_table(seal_no: int, style_rank_idx: int = 0) -> void:
	snapshot_segment_clear()

	var base_gain := 9
	if seal_no == 2:
		base_gain = 11
	elif seal_no >= 3:
		base_gain = 13

	var bonus_energy := 0
	if style_rank_idx >= 4 or last_clear_hits == 0:
		bonus_energy = 3
	elif style_rank_idx >= 3 or last_clear_time <= 30.0:
		bonus_energy = 2

	var watch_bonus := 5 if has_talent("talent_pocket_watch") else 0
	var added := base_gain + bonus_energy + watch_bonus
	energy += added
	gold_cores += 1

	if seal_no >= 2 and player_tier < MAX_PLAYER_TIER:
		upgrade_discount += 2

	status_toast = "+%d⚡" % added
	_roll_shop_page(false)
	table_updated.emit()


# ---------------------------------------------------------------- 3. 升级给天赋（Lv.1 -> Lv.5）

func tier_base_gain(tier_lv: int = -1) -> int:
	var t := player_tier if tier_lv < 0 else tier_lv
	return int(TIER_BASE_GAINS.get(clampi(t, 1, MAX_PLAYER_TIER), 6))


func upgrade_cost() -> int:
	if player_tier >= MAX_PLAYER_TIER:
		return 0
	var base_c := int(TIER_UPGRADE_COSTS.get(player_tier, 99))
	return maxi(0, base_c - upgrade_discount)


func is_draft_active() -> bool:
	return not pending_draft_choices.is_empty()


func can_upgrade_tier() -> bool:
	if is_draft_active():
		return false
	if player_tier >= MAX_PLAYER_TIER:
		return false
	return energy >= upgrade_cost()


func upgrade_tier() -> bool:
	if not can_upgrade_tier():
		return false
	var c := upgrade_cost()
	energy = maxi(0, energy - c)
	player_tier += 1
	upgrade_discount = 0

	_roll_shop_page(false)
	tier_upgraded.emit(player_tier)
	_enqueue_draft("talent")
	if has_talent("talent_tier_gift"):
		_enqueue_draft("tactic")

	status_toast = "升至 Lv.%d" % player_tier
	table_updated.emit()
	return true


# ---------------------------------------------------------------- 4. 商店刷牌、买牌、同名三合一送锦囊

func _roll_shop_page(from_manual_refresh: bool) -> void:
	shop_slots.clear()
	for i in SHOP_SIZE:
		var cid := _pick_random_shop_card_id()
		var base_card: Dictionary = catalog.get_card(cid) if catalog != null else {}
		var kind := String(base_card.get("card_kind", "stat"))
		var is_gold := (kind != "effect") and (player_tier >= 2) and (rng.randf() < 0.14)
		var is_free := (not is_gold) and (rng.randf() < 0.10)
		if from_manual_refresh and i == 0 and has_talent("talent_free_roll"):
			is_free = true
		var cost_val := 0 if is_free else int(base_card.get("cost", 2))
		shop_slots.append(_make_shop_slot(base_card, cost_val, is_gold, is_free))


func _pick_random_shop_card_id() -> String:
	var active_core := core_id if core_id != "" else "core_rift"
	var roll := rng.randf()
	# 按牌手等阶平滑提升效果牌出现率（Lv.1 20% -> Lv.5 32%），基础属性与核心维持主体节奏
	var core_p := 0.24 + 0.01 * float(clampi(player_tier - 1, 0, 4))
	var eff_p := 0.20 + 0.03 * float(clampi(player_tier - 1, 0, 4))
	if roll < core_p:
		return active_core
	if roll < core_p + eff_p:
		var effects: Array[String] = [
			"effect_style_tonic",
			"effect_blood_vial",
			"effect_poise_salve",
			"effect_air_step",
			"effect_thorn_coat",
			"effect_focus_lens",
			"effect_ult_elixir",
			"effect_execute_edge",
			"effect_skill_scroll",
		]
		if player_tier >= 2:
			effects.append_array(["effect_quench", "effect_all_stats", "effect_surge"])
		if catalog != null and catalog.has_method(&"pick_weighted_card_id"):
			return String(catalog.call(&"pick_weighted_card_id", effects, rng, player_tier))
		return effects[rng.randi_range(0, effects.size() - 1)]
	var stats := ["stat_atk", "stat_spd", "stat_crit", "stat_def"]
	return stats[rng.randi_range(0, stats.size() - 1)]


func _compute_slot_gain(cid: String, kind: String, is_gold: bool) -> int:
	var base_g := tier_base_gain()
	if kind == "effect":
		if cid == "effect_quench":
			return maxi(14, base_g + 5)
		if cid == "effect_all_stats":
			return maxi(6, roundi(float(base_g) * 0.65))
		if cid == "effect_style_tonic":
			return 20
		if cid == "effect_skill_scroll":
			return 1
		if cid == "effect_blood_vial":
			return 3
		if cid == "effect_poise_salve":
			return 1
		if cid == "effect_air_step":
			return 1
		if cid == "effect_thorn_coat":
			return 40
		if cid == "effect_focus_lens":
			return 12
		if cid == "effect_ult_elixir":
			return 25
		if cid == "effect_execute_edge":
			return 35
		return 3
	if cid == "stat_def":
		base_g = roundi(float(base_g) * 1.5)
	return base_g * (2 if is_gold else 1)


func _make_shop_slot(card_data: Dictionary, cost_val: int, is_gold: bool, is_free: bool) -> Dictionary:
	var cid := String(card_data.get("card_id", "stat_atk"))
	var kind := String(card_data.get("card_kind", "core" if cid.begins_with("core_") else "stat"))
	var gain_val := _compute_slot_gain(cid, kind, is_gold)
	var summary_txt := String(card_data.get("summary", ""))
	if cid == "effect_quench":
		summary_txt = "核心 +%d 级" % gain_val
	elif cid == "effect_all_stats":
		summary_txt = "四维各 +%d 级" % gain_val
	elif cid == "effect_surge":
		summary_txt = "立即 +%d⚡" % gain_val
	elif cid == "effect_style_tonic":
		summary_txt = "评分获取永久 +20%"
	elif cid == "effect_skill_scroll":
		summary_txt = "永久提前解锁下档技能"
	elif cid == "effect_blood_vial":
		summary_txt = "永久 +3% 吸血，回血 20%"
	elif cid == "effect_poise_salve":
		summary_txt = "常驻 +1 层免打断护体韧性"
	elif cid == "effect_air_step":
		summary_txt = "永久 +1 空中跳，空伤 +15%"
	elif cid == "effect_thorn_coat":
		summary_txt = "永久 +40% 受击荆棘反伤"
	elif cid == "effect_focus_lens":
		summary_txt = "时缓 +0.5秒，技伤 +12%"
	elif cid == "effect_ult_elixir":
		summary_txt = "绝影充能效率永久 +25%"
	elif cid == "effect_execute_edge":
		summary_txt = "对 30% 血以下敌人伤 +35%"
	return {
		"card_id": cid,
		"card_kind": kind,
		"title": String(card_data.get("title", cid)),
		"summary": summary_txt,
		"accent_color": card_data.get("accent_color", Color("b678ff")),
		"rarity": String(card_data.get("rarity", "common")),
		"rarity_label": String(card_data.get("rarity_label", "普通")),
		"rarity_color": card_data.get("rarity_color", Color("9aa4b8")),
		"gain": gain_val,
		"cost": maxi(0, cost_val),
		"is_gold": is_gold,
		"is_free": is_free or cost_val <= 0,
		"bought": false,
	}


func get_slot_pip_key(slot: Dictionary) -> String:
	var kind := String(slot.get("card_kind", ""))
	if kind == "core":
		return "core"
	if kind == "stat":
		return String(slot.get("card_id", ""))
	return ""


func will_slot_synthesize(slot: Dictionary) -> bool:
	if bool(slot.get("bought", false)):
		return false
	var pk := get_slot_pip_key(slot)
	if pk == "":
		return false
	var add_n := (2 if bool(slot.get("is_gold", false)) else 1) * (2 if duplicator_armed else 1)
	return int(synth_pips.get(pk, 0)) + add_n >= 3


func can_buy_slot(slot_idx: int) -> bool:
	if is_draft_active():
		return false
	if slot_idx < 0 or slot_idx >= shop_slots.size():
		return false
	var slot: Dictionary = shop_slots[slot_idx]
	if bool(slot.get("bought", false)):
		return false
	return energy >= int(slot.get("cost", 2))


func buy_slot(slot_idx: int) -> Dictionary:
	if not can_buy_slot(slot_idx):
		return {"ok": false}
	var slot: Dictionary = shop_slots[slot_idx]
	var cost_val := int(slot.get("cost", 2))
	energy = maxi(0, energy - cost_val)
	slot["bought"] = true
	cards_bought_total += 1

	var rebate := false
	if has_talent("talent_buy_rebate") and (cards_bought_total % 3 == 0):
		energy += 2
		rebate = true

	var times := 2 if duplicator_armed else 1
	duplicator_armed = false
	var total_gain := 0
	var did_synth := false
	for _t in times:
		var res := _apply_slot_effect(slot)
		total_gain += int(res.get("gained", 0))
		did_synth = did_synth or bool(res.get("synthesized", false))

	var title := String(slot.get("title", ""))
	if did_synth:
		status_toast = "【%s】合成！+%d 级" % [title, total_gain]
	elif rebate:
		status_toast = "【%s】+%d · 返 +2⚡" % [title, total_gain]
	else:
		status_toast = "【%s】+%d" % [title, total_gain]

	_check_page_cleared_refresh()
	table_updated.emit()
	return {"ok": true, "gained": total_gain, "synthesized": did_synth}


func _apply_slot_effect(slot: Dictionary) -> Dictionary:
	var cid := String(slot.get("card_id", ""))
	var kind := String(slot.get("card_kind", "stat"))
	var study_bonus := 4 if has_talent("talent_study") else 0
	var gain_val := int(slot.get("gain", 6))

	if kind == "effect":
		chosen_perks.append(cid)
		if cid == "effect_quench":
			var g_core := gain_val + study_bonus
			if perk_rig != null:
				perk_rig.add_core_levels(g_core)
			return {"gained": g_core, "synthesized": false}
		if cid == "effect_all_stats":
			var g_all := gain_val + (2 if study_bonus > 0 else 0)
			if perk_rig != null:
				for st_id in ["stat_atk", "stat_spd", "stat_crit", "stat_def"]:
					perk_rig.add_stat_levels(st_id, g_all)
			return {"gained": g_all * 4, "synthesized": false}
		if cid == "effect_surge":
			energy += gain_val
			return {"gained": gain_val, "synthesized": false}
		if cid in [
			"effect_style_tonic", "effect_skill_scroll", "effect_blood_vial",
			"effect_poise_salve", "effect_air_step", "effect_thorn_coat",
			"effect_focus_lens", "effect_ult_elixir", "effect_execute_edge",
		]:
			if perk_rig != null and perk_rig.has_method(&"apply_skill_effect"):
				perk_rig.call(&"apply_skill_effect", cid)
			return {"gained": gain_val, "synthesized": false}
		return {"gained": 0, "synthesized": false}

	var before_lv := _get_level_of(cid)
	_add_level_to(cid, gain_val + study_bonus)

	# 同名三合一判定（●●● -> 等级暴涨 + 送 3 选 1 锦囊）
	var pip_key := "core" if kind == "core" else cid
	var pips_add := 2 if bool(slot.get("is_gold", false)) else 1
	var cur_pips := int(synth_pips.get(pip_key, 0)) + pips_add
	var did_synth := false
	while cur_pips >= 3:
		cur_pips -= 3
		did_synth = true
		synth_total += 1
		var synth_bonus := maxi(8, roundi(float(tier_base_gain()) * 0.8))
		var now_lv := _add_level_to(cid, synth_bonus)
		if has_talent("talent_synth_boost") and perk_rig != null:
			perk_rig.add_core_levels(12)
			if kind == "core":
				now_lv = int(perk_rig.core_level)
		synthesis_triggered.emit(cid, now_lv)
		_enqueue_draft("tactic")
	synth_pips[pip_key] = cur_pips

	var after_lv := _get_level_of(cid)
	return {"gained": after_lv - before_lv, "synthesized": did_synth}


func _check_page_cleared_refresh() -> void:
	if shop_slots.is_empty():
		return
	for slot in shop_slots:
		if not bool(slot.get("bought", false)):
			return
	_roll_shop_page(false)


func can_refresh_shop() -> bool:
	return (not is_draft_active()) and energy >= 1


func refresh_shop() -> bool:
	if not can_refresh_shop():
		return false
	energy -= 1
	roll_count_total += 1
	_roll_shop_page(true)
	status_toast = "首张免单 0⚡" if has_talent("talent_free_roll") else ""
	table_updated.emit()
	return true


# ---------------------------------------------------------------- 5. 三选一抽卡队列（天赋 / 锦囊瞬发）

func _enqueue_draft(kind: String) -> void:
	_draft_queue.append(kind)
	if not _resolving_draft and pending_draft_choices.is_empty():
		_pop_next_draft()


func _pop_next_draft() -> void:
	while not _draft_queue.is_empty():
		var next_kind := String(_draft_queue.pop_front())
		var rolled: Array[Dictionary] = _roll_draft_pool(next_kind)
		if not rolled.is_empty():
			pending_draft_kind = next_kind
			pending_draft_choices = rolled
			draft_offered.emit(pending_draft_kind, pending_draft_choices)
			return
	pending_draft_kind = ""
	pending_draft_choices.clear()


func _roll_draft_pool(kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if catalog == null:
		return out
	var raw: Variant = null
	if kind == "talent":
		raw = catalog.roll_talent_choices(3, rng, active_talents, player_tier)
	else:
		var tactic_exclude: Array[String] = []
		if has_style_floor():
			tactic_exclude.append("tactic_style_floor")
		if has_unlock_all_skills():
			tactic_exclude.append("tactic_unlock_all_skills")
		if chosen_perks.has("tactic_blood_oath"):
			tactic_exclude.append("tactic_blood_oath")
		# 司辰全书（tactic_unlock_all_skills）必须在获得永恒华章（tactic_style_floor）之后才能刷出
		raw = catalog.roll_tactic_choices(3, rng, tactic_exclude, player_tier, has_style_floor())
	if raw is Array:
		for item in raw:
			if item is Dictionary:
				out.append(item as Dictionary)
	return out


func pick_draft_choice(choice_idx: int) -> bool:
	if pending_draft_choices.is_empty():
		return false
	var idx := clampi(choice_idx, 0, pending_draft_choices.size() - 1)
	var chosen: Dictionary = pending_draft_choices[idx]
	var cid := String(chosen.get("card_id", ""))
	var title := String(chosen.get("title", cid))
	var kind := pending_draft_kind

	_resolving_draft = true
	pending_draft_kind = ""
	pending_draft_choices.clear()

	if kind == "talent":
		if cid != "" and not active_talents.has(cid):
			active_talents.append(cid)
			chosen_perks.append(cid)
			if perk_rig != null and perk_rig.has_method(&"apply_style_talent"):
				perk_rig.call(&"apply_style_talent", cid)
		if cid == "talent_free_roll" and not shop_slots.is_empty():
			# 若首槽未买则立享免单反馈
			if not bool(shop_slots[0].get("bought", false)):
				shop_slots[0]["cost"] = 0
				shop_slots[0]["is_free"] = true
		status_toast = "天赋【%s】生效" % title
	elif kind == "tactic":
		_execute_tactic_by_id(cid)

	_resolving_draft = false
	if pending_draft_choices.is_empty():
		_pop_next_draft()
	table_updated.emit()
	return true


func pick_tactic_choice(choice_idx: int) -> bool:
	return pick_draft_choice(choice_idx)


func _execute_tactic_by_id(tid: String) -> void:
	if tid == "":
		return
	tactics_used_total += 1
	chosen_perks.append(tid)
	var active_core := core_id if core_id != "" else "core_rift"

	match tid:
		"tactic_summon_core":
			var core_data: Dictionary = catalog.get_card(active_core) if catalog != null else {}
			shop_slots.clear()
			for i in SHOP_SIZE:
				shop_slots.append(_make_shop_slot(core_data, 1, false, false))
			status_toast = "万象征召：整页变核心牌 (1⚡)"

		"tactic_gild_shop":
			for i in SHOP_SIZE:
				if i >= shop_slots.size() or bool(shop_slots[i].get("bought", false)) or String(shop_slots[i].get("card_kind", "")) == "effect":
					var fill_id := active_core if i == 0 else _pick_stat_only_id()
					var fill_data: Dictionary = catalog.get_card(fill_id) if catalog != null else {}
					var new_slot := _make_shop_slot(fill_data, int(fill_data.get("cost", 2)), true, false)
					if i < shop_slots.size():
						shop_slots[i] = new_slot
					else:
						shop_slots.append(new_slot)
				else:
					var s: Dictionary = shop_slots[i]
					if not bool(s.get("is_gold", false)):
						s["is_gold"] = true
						s["gain"] = int(s.get("gain", 6)) * 2
			status_toast = "点石成金：整页翻倍金卡"

		"tactic_free_page":
			for i in shop_slots.size():
				var s2: Dictionary = shop_slots[i]
				if not bool(s2.get("bought", false)):
					s2["bought"] = true
					_apply_slot_effect(s2)
			_roll_shop_page(false)
			status_toast = "免单横扫：整页全收"

		"tactic_duplicator":
			duplicator_armed = true
			status_toast = "双倍镜：下张牌触发 2 次"

		"tactic_break_limit":
			if perk_rig != null:
				perk_rig.add_core_levels(15)
				perk_rig.apply_threshold_discount(0.75)
			status_toast = "破界符：核心+15 · 门槛-25%"

		"tactic_enlighten":
			if perk_rig != null:
				perk_rig.add_core_levels(25)
			energy += 2
			status_toast = "灌顶丹：核心+25 · +2⚡"

		"tactic_unlock_all_skills":
			if perk_rig != null and perk_rig.has_method(&"apply_skill_tactic"):
				perk_rig.call(&"apply_skill_tactic", tid)
			status_toast = "司辰全书：全 D~S 技能已解锁 · 技伤 +25%"

		"tactic_style_floor":
			if perk_rig != null and perk_rig.has_method(&"apply_skill_tactic"):
				perk_rig.call(&"apply_skill_tactic", tid)
			status_toast = "永恒华章：战斗评分保底 B 档（已解锁司辰全书）"

		"tactic_blood_oath":
			if perk_rig != null and perk_rig.has_method(&"apply_skill_tactic"):
				perk_rig.call(&"apply_skill_tactic", tid)
			status_toast = "残夜血誓：+12% 吸血 · 出招霸体 · 半血增伤 +30%"

		"tactic_shadow_overdrive":
			if perk_rig != null and perk_rig.has_method(&"apply_skill_tactic"):
				perk_rig.call(&"apply_skill_tactic", tid)
			status_toast = "千影奔流：残影上限 +2 · 回复加快 40%"

		"tactic_chrono_overclock":
			if perk_rig != null and perk_rig.has_method(&"apply_skill_tactic"):
				perk_rig.call(&"apply_skill_tactic", tid)
			status_toast = "凝晷超频：时缓与技能冷却减半 · 时缓 +1.0秒"

		"tactic_eclipse_crown":
			if perk_rig != null and perk_rig.has_method(&"apply_skill_tactic"):
				perk_rig.call(&"apply_skill_tactic", tid)
			status_toast = "蚀月王冠：绝影回满 · 技能伤害 +40%"


func _pick_stat_only_id() -> String:
	var stats := ["stat_atk", "stat_spd", "stat_crit", "stat_def"]
	return stats[rng.randi_range(0, stats.size() - 1)]


# ---------------------------------------------------------------- 6. 无头旧回归静默直通与结算摘要

func auto_resolve_silent() -> Dictionary:
	snapshot_segment_clear()
	gold_cores += 1
	if not opening_completed:
		apply_opening_selection("core_rift")
	else:
		if perk_rig != null:
			perk_rig.add_core_levels(12)
	return {
		"core_id": core_id,
		"core_level": perk_rig.core_level if perk_rig != null else 10,
	}


func _get_level_of(cid: String) -> int:
	if perk_rig == null:
		return 1
	if cid.begins_with("core_"):
		return int(perk_rig.core_level)
	return int(perk_rig.stat_levels.get(cid, 1))


func _add_level_to(cid: String, amount: int) -> int:
	if perk_rig == null:
		return 1
	if cid.begins_with("core_"):
		return int(perk_rig.add_core_levels(amount))
	return int(perk_rig.add_stat_levels(cid, amount))


func build_run_summary() -> Dictionary:
	var core_title := core_id
	if catalog != null and core_id != "":
		core_title = String(catalog.get_card(core_id).get("title", core_id))
	return {
		"core_id": core_id,
		"core_title": core_title,
		"core_level": perk_rig.core_level if perk_rig != null else 0,
		"player_tier": player_tier,
		"active_talents": active_talents.duplicate(),
		"stat_levels": perk_rig.stat_levels.duplicate(true) if perk_rig != null else {},
		"gold_cores": gold_cores,
		"synth_total": synth_total,
		"cards_bought_total": cards_bought_total,
		"shadow_cap": perk_rig.shadow_cap if perk_rig != null else 2,
		"chosen_perks": chosen_perks.duplicate(),
	}
