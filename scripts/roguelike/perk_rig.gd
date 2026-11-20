extends Node2D
## 断晓肉鸽 · 万象核心与四维属性战斗驱动器（PerkRig）
## 不修改 player.gd / shade.gd / boss_shade.gd 源码，纯外挂信号与克隆招式资源驱动：
## 1. 1 张【本命核心流派牌】（Lv.1 -> 10 -> 40 -> 100 -> 999 三阶技能与墨紫银白几何特效）
## 2. 4 项【纯净基础属性】（攻击 / 速度 / 暴击 / 防御 + 驻时凝光盾）
## 3. 100% 兼容 RainTrial 与首领战 BossSample（断潮），严禁触碰 Engine.time_scale，严禁橙红预警色。

const PerkCatalog := preload("res://scripts/roguelike/perk_catalog.gd")
const Shade := preload("res://scripts/night/shade.gd")
const SpatialRiftScript := preload("res://scripts/gameplay/spatial_rift.gd")

const FONT_SERIF_PATH := "res://assets/fonts/yg_title/NotoSerifSC-VF.ttf"
const FONT_GOTHIC_PATH := "res://assets/fonts/gothic/Cinzel-VF.ttf"

const COL_INK := Color("120d1d")
const COL_VIOLET := Color("b678ff")
const COL_VIOLET_LIGHT := Color("dfc2ff")
const COL_SILVER := Color("eef6ff")
const COL_GOLD := Color("f5dfa3")

## 波次后所有属性/伤害类 Buff 数值效果统一乘以 0.1（仅缩放数值，保留全部核心/边界机制）
const BUFF_VALUE_SCALE := 0.1

signal core_changed(core_id: String, level: int)
signal stat_changed(stat_id: String, level: int)
signal milestone_unlocked(core_id: String, milestone: int)
signal perk_triggered(effect_id: String, world_pos: Vector2)

var stage: Node = null
var player: CharacterBody2D = null
var boss_ref: Node2D = null
var catalog: RefCounted = null
var rng := RandomNumberGenerator.new()

## 核心流派与四维等级状态（唯一战斗养成事实源）
var core_id: String = ""
var core_level: int = 0
var threshold_scale: float = 1.0
var stat_levels: Dictionary = {
	"stat_atk": 1,
	"stat_spd": 1,
	"stat_crit": 1,
	"stat_def": 1,
}

## 评分稳定与搓招技能组专属 Buff 修饰符（支持跨场景同步至首领战）
var style_decay_mul: float = 1.0
var style_combo_bonus: float = 0.0
var style_gain_mul: float = 1.0
var style_hit_protect: bool = false
var style_rank_floor: int = 0
var skill_rank_discount: int = 0
var skill_early_unlocks: int = 0
var skill_unlock_all: bool = false
var skill_slowmo_bonus: float = 0.0
var skill_cd_mul: float = 1.0
var skill_dmg_mul: float = 1.0
var skill_cast_style_bonus: float = 0.0
var skill_cast_ult_bonus: float = 0.0

## 非基础数值/核心的战斗机制 Buff（吸血、抗打断霸体、韧性层数、碎壳、回流、空中跳、低血狂澜）
var lifesteal_ratio: float = 0.0
var attack_poise: bool = false
var poise_max_charges: int = 0
var _poise_regen_timer: float = 0.0
var shell_shred_bonus: float = 0.0
var shadow_flow_enabled: bool = false
var _flow_haste_timer: float = 0.0
var extra_air_jumps_bonus: int = 0
var aerial_dmg_bonus: float = 0.0
var low_hp_dmg_bonus: float = 0.0
var total_lifesteal_healed: float = 0.0
var thorn_ratio: float = 0.0
var ult_gain_mul: float = 1.0
var execute_bonus: float = 0.0
var parry_heal_enabled: bool = false
var dash_nova_enabled: bool = false
var combo_surge_per_10: float = 0.0
var immortal_clock_enabled: bool = false
var shadow_cap_bonus: int = 0
var shadow_regen_mul: float = 1.0
var thorn_reflect_count: int = 0
var dash_nova_count: int = 0

## 兼容旧查询字段
var active_perks: Dictionary = {}
var shadow_cap: int = 2

## 驻时凝光盾与逆时锁血状态
var aegis_hp: float = 0.0
var aegis_max: float = 0.0
var _aegis_regen_delay: float = 0.0
var cheat_death_charges: int = 0
var cheat_death_triggered_count: int = 0

## 统计计数（供 HUD 与无头测试断言）
var swing_count: int = 0
var crit_trigger_count: int = 0
var over_crit_count: int = 0
var rift_arc_count: int = 0
var rift_detonation_count: int = 0
var sky_storm_count: int = 0
var clone_slash_count: int = 0
var feather_shot_count: int = 0
var slash_web_count: int = 0
var thunder_strike_count: int = 0
var time_stop_count: int = 0
var bell_wave_count: int = 0
var grand_bell_count: int = 0

## 刹那 5:59 局部时停态（绝不修改 Engine.time_scale）
var time_stop_timer: float = 0.0
var _chrono_charge: float = 0.0
var _time_stop_cd: float = 0.0
var _time_stop_marks: Dictionary = {}
var _frozen_projectiles: Array[Node] = []

## 百级大招节流计时
var _sky_storm_cd: float = 0.0
var _grand_bell_cd: float = 0.0
var _applying_perk_hit: bool = false
var _hurt_intercepted_frame: int = -1
var _tracked_hp: float = -1.0
var _time: float = 0.0

## 角色原始基线快照（克隆 MoveDefinition 防止跨局污染共享资源）
var _baseline_captured: bool = false
var _base_max_hp: float = 100.0
var _base_speed: float = 450.0
var _base_wall_scale: float = 0.15
var _base_charge_scale: float = 1.0
var _base_heavy_charge_frames: int = 25
var _base_shadow_max: int = 2
var _base_shadow_regen: float = 3.0
var _base_unlimited_dash: bool = false
var _base_extra_air_jumps: int = 1
var _base_soft_knock: float = 350.0
var _computed_base_atk_mul: float = 1.0
var _computed_base_speed: float = 450.0
var _move_baselines: Array[Dictionary] = []

## 合成判定招式（严格使用 MoveDefinition 匹配 take_hit 签名）
var _mv_arc: MoveDefinition
var _mv_storm: MoveDefinition
var _mv_clone: MoveDefinition
var _mv_feather: MoveDefinition
var _mv_thunder: MoveDefinition
var _mv_bell: MoveDefinition
var _mv_crit: MoveDefinition

## 活跃几何特效队列
var arc_slashes: Array[Dictionary] = []
var sky_blades: Array[Dictionary] = []
var decoys: Array[Dictionary] = []
var feather_bolts: Array[Dictionary] = []
var bell_rings: Array[Dictionary] = []
var vfx_lines: Array[Dictionary] = []
var vfx_flashes: Array[Dictionary] = []

## 右上角极简万象徽章 HUD
var _hud_layer: CanvasLayer = null
var _hud_canvas: Control = null
var _font_serif: Font = null
var _font_gothic: Font = null
var _banner_text: String = ""
var _banner_timer: float = 0.0


func _ready() -> void:
	z_index = 5
	process_physics_priority = -10
	rng.randomize()
	if ResourceLoader.exists(FONT_SERIF_PATH):
		_font_serif = load(FONT_SERIF_PATH) as Font
	if ResourceLoader.exists(FONT_GOTHIC_PATH):
		_font_gothic = load(FONT_GOTHIC_PATH) as Font
	if catalog == null:
		catalog = PerkCatalog.new(get_tree())
	if _mv_arc == null:
		_build_synthetic_moves()
	_ensure_hud()
	if stage != null and player == null:
		player = stage.get("player")
	if player != null:
		bind_player(player)


func _exit_tree() -> void:
	_release_time_stop(false)


func setup(p_stage: Node, p_player: CharacterBody2D) -> void:
	stage = p_stage
	if catalog == null:
		catalog = PerkCatalog.new(p_stage.get_tree() if p_stage != null else null)
	if _mv_arc == null:
		_build_synthetic_moves()
	bind_player(p_player)
	if stage != null:
		var enc: Node = stage.get("encounter")
		if enc != null and enc.has_signal("shade_spawned"):
			_connect_once(enc, &"shade_spawned", _on_shade_spawned)
		var maybe_boss: Variant = stage.get("boss")
		if maybe_boss is Node2D and is_instance_valid(maybe_boss):
			bind_boss(maybe_boss as Node2D)
	sync_style_modifiers()


func bind_boss(p_boss: Node2D) -> void:
	if p_boss == null or not is_instance_valid(p_boss):
		return
	boss_ref = p_boss
	_on_shade_spawned(p_boss)
	_connect_once(p_boss, &"shell_damaged", _on_boss_shell_damaged)
	_connect_once(p_boss, &"shell_shattered", _on_boss_shell_shattered)


func bind_player(p_player: CharacterBody2D) -> void:
	if p_player == null or not is_instance_valid(p_player):
		return
	player = p_player
	_capture_player_baseline()
	_connect_once(player, &"move_started", _on_player_move_started)
	_connect_once(player, &"hit_confirmed", _on_player_hit_confirmed)
	_connect_once(player, &"parry_success", _on_player_parry_success)
	_connect_once(player, &"plunge_landed", _on_player_plunge_landed)
	_connect_once(player, &"short_dash_started", _on_player_short_dash)
	_connect_once(player, &"shadow_pursuit_started", _on_player_shadow_pursuit)
	_connect_once(player, &"perfect_dodge_triggered", _on_player_perfect_dodge)
	_connect_once(player, &"combo_finisher_triggered", _on_player_combo_finisher)
	_sync_player_stats()


func _connect_once(obj: Object, sig: StringName, cb: Callable) -> void:
	if obj != null and obj.has_signal(sig) and not obj.is_connected(sig, cb):
		obj.connect(sig, cb)


func _capture_player_baseline() -> void:
	if _baseline_captured or player == null:
		return
	_baseline_captured = true
	_base_max_hp = float(player.max_hp)
	_base_speed = float(player.speed)
	_base_wall_scale = float(player.wall_damage_scale)
	_base_charge_scale = float(player.charge_rate_scale)
	_base_heavy_charge_frames = int(player.heavy_full_charge_frames)
	_base_shadow_max = int(player.max_shadow_charges)
	_base_shadow_regen = float(player.shadow_regen_seconds)
	_base_unlimited_dash = bool(player.unlimited_dash)
	_base_extra_air_jumps = int(player.extra_air_jumps)
	_base_soft_knock = float(player.soft_knock_threshold)
	_computed_base_atk_mul = float(player.attack_damage_mul)
	_computed_base_speed = float(player.speed)
	_move_baselines.clear()

	# 克隆角色持有的 MoveDefinition，避免跨局污染全局 .tres 资源
	for arr_prop in [&"light_combo", &"air_combo"]:
		var orig_arr: Array = player.get(arr_prop)
		var cloned_arr: Array = []
		for item in orig_arr:
			if item is MoveDefinition:
				var dup: MoveDefinition = (item as MoveDefinition).duplicate()
				cloned_arr.append(dup)
				_record_move_baseline(dup)
			else:
				cloned_arr.append(item)
		player.set(arr_prop, cloned_arr)

	var single_props: Array[StringName] = [
		&"charge_move",
		&"up_strike_move",
		&"air_up_move",
		&"parry_move",
		&"dash_move",
		&"dash_left_move",
		&"air_dash_move",
		&"air_dash_left_move",
		&"air_plunge_move",
		&"combo_k_launch_move",
		&"combo_k_pierce_move",
		&"combo_k_pierce_left_move",
		&"combo_k_cleave_move",
	]
	for prop in single_props:
		var res: Variant = player.get(prop)
		if res is MoveDefinition:
			var dup_single: MoveDefinition = (res as MoveDefinition).duplicate()
			player.set(prop, dup_single)
			_record_move_baseline(dup_single)


func _record_move_baseline(mv: MoveDefinition) -> void:
	_move_baselines.append({
		"move": mv,
		"startup": mv.startup_frames,
		"active": mv.active_frames,
		"recovery": mv.recovery_frames,
		"fps": mv.animation_fps,
		"hitbox": mv.hitbox,
	})


func _build_synthetic_moves() -> void:
	_mv_arc = _make_move(&"wanxiang_arc", 16.0 * BUFF_VALUE_SCALE, 320.0, false, 1)
	_mv_storm = _make_move(&"wanxiang_storm", 24.0 * BUFF_VALUE_SCALE, 440.0, true, 2)
	_mv_storm.launch_speed = 540.0
	_mv_clone = _make_move(&"wanxiang_clone", 14.0 * BUFF_VALUE_SCALE, 260.0, false, 1)
	_mv_feather = _make_move(&"wanxiang_feather", 9.0 * BUFF_VALUE_SCALE, 140.0, false, 0)
	_mv_thunder = _make_move(&"wanxiang_thunder", 15.0 * BUFF_VALUE_SCALE, 220.0, false, 1)
	_mv_bell = _make_move(&"wanxiang_bell", 16.0 * BUFF_VALUE_SCALE, 520.0, false, 2)
	_mv_crit = _make_move(&"wanxiang_crit", 10.0 * BUFF_VALUE_SCALE, 80.0, false, 0)


func _make_move(id_name: StringName, dmg: float, kb: float, launch: bool, hitstop: int) -> MoveDefinition:
	var mv := MoveDefinition.new()
	mv.id = id_name
	mv.damage = dmg
	mv.knockback = kb
	mv.forces_launch = launch
	mv.hitstop_frames = hitstop
	mv.victim_hitstop_frames = hitstop
	mv.startup_frames = 0
	mv.active_frames = 3
	mv.recovery_frames = 0
	return mv


# ---------------------------------------------------------------- 核心牌与四维等级养成 API

func is_active_build() -> bool:
	if core_id != "" and core_level > 0:
		return true
	for k in stat_levels.keys():
		if int(stat_levels[k]) > 1:
			return true
	return (
		lifesteal_ratio > 0.0
		or attack_poise
		or poise_max_charges > 0
		or shell_shred_bonus > 0.0
		or shadow_flow_enabled
		or extra_air_jumps_bonus > 0
		or low_hp_dmg_bonus > 0.0
		or thorn_ratio > 0.0
		or execute_bonus > 0.0
		or parry_heal_enabled
		or dash_nova_enabled
		or combo_surge_per_10 > 0.0
		or immortal_clock_enabled
		or shadow_cap_bonus > 0
	)


func tier_req(base_req: int) -> int:
	return maxi(1, ceili(float(base_req) * threshold_scale))


func has_core_tier(base_req: int) -> bool:
	return core_id != "" and core_level >= tier_req(base_req)


func set_core_hero(new_core_id: String, initial_level: int = 10) -> void:
	var prev_lv := core_level if core_id == new_core_id else 0
	core_id = new_core_id
	core_level = clampi(initial_level, 1, 999)
	active_perks[core_id] = core_level
	if core_id == "core_bell" and has_core_tier(100):
		cheat_death_charges = 1
	_sync_player_stats()
	if aegis_max > 0.0:
		aegis_hp = aegis_max
	_check_milestone_crossings(prev_lv, core_level)
	core_changed.emit(core_id, core_level)
	_refresh_hud()


func add_core_levels(amount: int) -> int:
	if core_id == "" or amount == 0:
		return core_level
	var prev := core_level
	core_level = clampi(core_level + amount, 1, 999)
	active_perks[core_id] = core_level
	_sync_player_stats()
	_check_milestone_crossings(prev, core_level)
	core_changed.emit(core_id, core_level)
	_refresh_hud()
	return core_level


func add_stat_levels(stat_id: String, amount: int) -> int:
	if not stat_levels.has(stat_id) or amount == 0:
		return int(stat_levels.get(stat_id, 1))
	var next_lv := clampi(int(stat_levels[stat_id]) + amount, 1, 999)
	stat_levels[stat_id] = next_lv
	active_perks[stat_id] = next_lv
	_sync_player_stats()
	stat_changed.emit(stat_id, next_lv)
	_refresh_hud()
	return next_lv


func set_stat_level(stat_id: String, new_level: int) -> void:
	if not stat_levels.has(stat_id):
		return
	stat_levels[stat_id] = clampi(new_level, 1, 999)
	active_perks[stat_id] = int(stat_levels[stat_id])
	_sync_player_stats()
	stat_changed.emit(stat_id, int(stat_levels[stat_id]))
	_refresh_hud()


func apply_threshold_discount(mult: float = 0.75) -> void:
	var prev_t10 := has_core_tier(10)
	var prev_t40 := has_core_tier(40)
	var prev_t100 := has_core_tier(100)
	threshold_scale = clampf(threshold_scale * mult, 0.45, 1.0)
	_sync_player_stats()
	if not prev_t10 and has_core_tier(10):
		_on_milestone_reached(10)
	if not prev_t40 and has_core_tier(40):
		_on_milestone_reached(40)
	if not prev_t100 and has_core_tier(100):
		_on_milestone_reached(100)
	_refresh_hud()


## 兼容旧调用：支持直接授予核心牌或基础属性
func grant_perk(card_id: String, gain_override: int = -1) -> int:
	if card_id.begins_with("core_"):
		if core_id == "":
			set_core_hero(card_id, gain_override if gain_override > 0 else 10)
		else:
			add_core_levels(gain_override if gain_override > 0 else 8)
		return core_level
	if stat_levels.has(card_id):
		var def_gain := 12 if card_id == "stat_def" else 8
		return add_stat_levels(card_id, gain_override if gain_override > 0 else def_gain)
	return 0


func export_snapshot() -> Dictionary:
	return {
		"core_id": core_id,
		"core_level": core_level,
		"threshold_scale": threshold_scale,
		"stat_levels": stat_levels.duplicate(true),
		"style_decay_mul": style_decay_mul,
		"style_combo_bonus": style_combo_bonus,
		"style_gain_mul": style_gain_mul,
		"style_hit_protect": style_hit_protect,
		"style_rank_floor": style_rank_floor,
		"skill_rank_discount": skill_rank_discount,
		"skill_early_unlocks": skill_early_unlocks,
		"skill_unlock_all": skill_unlock_all,
		"skill_slowmo_bonus": skill_slowmo_bonus,
		"skill_cd_mul": skill_cd_mul,
		"skill_dmg_mul": skill_dmg_mul,
		"skill_cast_style_bonus": skill_cast_style_bonus,
		"skill_cast_ult_bonus": skill_cast_ult_bonus,
		"lifesteal_ratio": lifesteal_ratio,
		"attack_poise": attack_poise,
		"poise_max_charges": poise_max_charges,
		"shell_shred_bonus": shell_shred_bonus,
		"shadow_flow_enabled": shadow_flow_enabled,
		"extra_air_jumps_bonus": extra_air_jumps_bonus,
		"aerial_dmg_bonus": aerial_dmg_bonus,
		"low_hp_dmg_bonus": low_hp_dmg_bonus,
		"thorn_ratio": thorn_ratio,
		"ult_gain_mul": ult_gain_mul,
		"execute_bonus": execute_bonus,
		"parry_heal_enabled": parry_heal_enabled,
		"dash_nova_enabled": dash_nova_enabled,
		"combo_surge_per_10": combo_surge_per_10,
		"immortal_clock_enabled": immortal_clock_enabled,
		"shadow_cap_bonus": shadow_cap_bonus,
		"shadow_regen_mul": shadow_regen_mul,
	}


func import_snapshot(snap: Dictionary) -> void:
	if snap.is_empty():
		return
	threshold_scale = float(snap.get("threshold_scale", 1.0))
	style_decay_mul = float(snap.get("style_decay_mul", 1.0))
	style_combo_bonus = float(snap.get("style_combo_bonus", 0.0))
	style_gain_mul = float(snap.get("style_gain_mul", 1.0))
	style_hit_protect = bool(snap.get("style_hit_protect", false))
	style_rank_floor = int(snap.get("style_rank_floor", 0))
	skill_rank_discount = int(snap.get("skill_rank_discount", 0))
	skill_early_unlocks = int(snap.get("skill_early_unlocks", 0))
	skill_unlock_all = bool(snap.get("skill_unlock_all", false))
	skill_slowmo_bonus = float(snap.get("skill_slowmo_bonus", 0.0))
	skill_cd_mul = float(snap.get("skill_cd_mul", 1.0))
	skill_dmg_mul = float(snap.get("skill_dmg_mul", 1.0))
	skill_cast_style_bonus = float(snap.get("skill_cast_style_bonus", 0.0))
	skill_cast_ult_bonus = float(snap.get("skill_cast_ult_bonus", 0.0))
	lifesteal_ratio = float(snap.get("lifesteal_ratio", 0.0))
	attack_poise = bool(snap.get("attack_poise", false))
	poise_max_charges = int(snap.get("poise_max_charges", 0))
	shell_shred_bonus = float(snap.get("shell_shred_bonus", 0.0))
	shadow_flow_enabled = bool(snap.get("shadow_flow_enabled", false))
	extra_air_jumps_bonus = int(snap.get("extra_air_jumps_bonus", 0))
	aerial_dmg_bonus = float(snap.get("aerial_dmg_bonus", 0.0))
	low_hp_dmg_bonus = float(snap.get("low_hp_dmg_bonus", 0.0))
	thorn_ratio = float(snap.get("thorn_ratio", 0.0))
	ult_gain_mul = float(snap.get("ult_gain_mul", 1.0))
	execute_bonus = float(snap.get("execute_bonus", 0.0))
	parry_heal_enabled = bool(snap.get("parry_heal_enabled", false))
	dash_nova_enabled = bool(snap.get("dash_nova_enabled", false))
	combo_surge_per_10 = float(snap.get("combo_surge_per_10", 0.0))
	immortal_clock_enabled = bool(snap.get("immortal_clock_enabled", false))
	shadow_cap_bonus = int(snap.get("shadow_cap_bonus", 0))
	shadow_regen_mul = float(snap.get("shadow_regen_mul", 1.0))
	var saved_stats: Variant = snap.get("stat_levels", {})
	if saved_stats is Dictionary:
		for k in stat_levels.keys():
			if (saved_stats as Dictionary).has(k):
				stat_levels[k] = clampi(int((saved_stats as Dictionary)[k]), 1, 999)
				active_perks[k] = int(stat_levels[k])
	var cid := String(snap.get("core_id", ""))
	var clv := int(snap.get("core_level", 0))
	if cid != "" and clv > 0:
		core_id = cid
		core_level = clampi(clv, 1, 999)
		active_perks[core_id] = core_level
	_sync_player_stats()
	sync_style_modifiers()
	if aegis_max > 0.0:
		aegis_hp = aegis_max
	if (core_id == "core_bell" and has_core_tier(100)) or immortal_clock_enabled:
		cheat_death_charges = maxi(cheat_death_charges, 1)
	_refresh_hud()


func sync_style_modifiers() -> void:
	if stage == null:
		return
	var st: Variant = stage.get("style")
	if st == null:
		return
	st.set("decay_mul", style_decay_mul)
	st.set("combo_window_bonus", style_combo_bonus)
	st.set("gain_mul", style_gain_mul)
	st.set("hit_protect", style_hit_protect)
	st.set("rank_floor", style_rank_floor)
	if st.has_method(&"enforce_floor"):
		st.call(&"enforce_floor")


func apply_style_talent(tid: String) -> void:
	match tid:
		"talent_style_anchor":
			style_decay_mul = clampf(style_decay_mul * 0.55, 0.15, 1.0)
			style_combo_bonus += 1.2
		"talent_hit_shield":
			style_hit_protect = true
		"talent_skill_unlock_1":
			skill_rank_discount = mini(skill_rank_discount + 1, 4)
			skill_slowmo_bonus += 0.8
		"talent_skill_mastery":
			skill_cd_mul = clampf(skill_cd_mul * 0.65, 0.25, 1.0)
			skill_cast_style_bonus += 15.0
			skill_cast_ult_bonus += 8.0
		"talent_lifesteal":
			lifesteal_ratio = minf(lifesteal_ratio + 0.08, 0.45)
		"talent_poise":
			attack_poise = true
		"talent_shell_shred":
			shell_shred_bonus += 0.50
		"talent_shadow_flow":
			shadow_flow_enabled = true
		"talent_perfect_parry_heal":
			parry_heal_enabled = true
		"talent_dash_nova":
			dash_nova_enabled = true
		"talent_combo_surge":
			combo_surge_per_10 += 0.06
		"talent_immortal_clock":
			immortal_clock_enabled = true
			cheat_death_charges = maxi(cheat_death_charges, 1)
	_sync_player_stats()
	sync_style_modifiers()
	_refresh_hud()


func apply_skill_effect(cid: String) -> void:
	match cid:
		"effect_style_tonic":
			style_gain_mul = minf(style_gain_mul + 0.20, 3.0)
		"effect_skill_scroll":
			skill_early_unlocks = mini(skill_early_unlocks + 1, 4)
		"effect_blood_vial":
			lifesteal_ratio = minf(lifesteal_ratio + 0.03, 0.45)
			if player != null and is_instance_valid(player):
				heal_player(float(player.max_hp) * 0.20)
		"effect_poise_salve":
			poise_max_charges = mini(poise_max_charges + 1, 5)
			if player != null and is_instance_valid(player) and player.get("buff_poise_charges") != null:
				player.set("buff_poise_charges", mini(poise_max_charges, int(player.get("buff_poise_charges")) + 1))
		"effect_air_step":
			extra_air_jumps_bonus = mini(extra_air_jumps_bonus + 1, 3)
			aerial_dmg_bonus += 0.15
		"effect_thorn_coat":
			thorn_ratio = minf(thorn_ratio + 0.40, 2.40)
		"effect_focus_lens":
			skill_slowmo_bonus += 0.5
			skill_dmg_mul += 0.12
		"effect_ult_elixir":
			ult_gain_mul = minf(ult_gain_mul + 0.25, 3.0)
		"effect_execute_edge":
			execute_bonus = minf(execute_bonus + 0.35, 1.40)
	_sync_player_stats()
	sync_style_modifiers()
	_refresh_hud()


func apply_skill_tactic(tid: String) -> void:
	match tid:
		"tactic_unlock_all_skills":
			skill_unlock_all = true
			skill_dmg_mul += 0.25
		"tactic_style_floor":
			style_rank_floor = maxi(style_rank_floor, 2)
		"tactic_blood_oath":
			lifesteal_ratio = minf(lifesteal_ratio + 0.12, 0.45)
			attack_poise = true
			low_hp_dmg_bonus += 0.30
		"tactic_shadow_overdrive":
			shadow_cap_bonus = mini(shadow_cap_bonus + 2, 6)
			shadow_regen_mul = clampf(shadow_regen_mul * 0.60, 0.30, 1.0)
		"tactic_chrono_overclock":
			skill_cd_mul = clampf(skill_cd_mul * 0.50, 0.20, 1.0)
			skill_slowmo_bonus += 1.0
		"tactic_eclipse_crown":
			skill_dmg_mul += 0.40
			ult_gain_mul = minf(ult_gain_mul + 0.30, 3.0)
			if player != null and is_instance_valid(player) and player.has_method(&"add_ult_energy"):
				player.call(&"add_ult_energy", 100.0)
	_sync_player_stats()
	sync_style_modifiers()
	_refresh_hud()


func heal_player(amount: float) -> void:
	if player == null or not is_instance_valid(player) or amount <= 0.0:
		return
	var before := float(player.hp)
	if before <= 0.0:
		return
	var after := minf(float(player.max_hp), before + amount)
	var actual := after - before
	if actual > 0.01:
		player.hp = after
		_tracked_hp = after
		total_lifesteal_healed += actual
		if stage != null and stage.get("_hp_seen") != null:
			stage.set("_hp_seen", after)
		if actual >= 0.8:
			_spawn_flash(player.global_position + Vector2(0.0, -34.0), 42.0, Color("8ff2c8"), 0.18)


func on_combo_skill_hit(damage_dealt: float, _point: Vector2) -> void:
	if lifesteal_ratio > 0.0 and damage_dealt > 0.0:
		heal_player(damage_dealt * lifesteal_ratio)


func _grant_shadow_and_ult(shadows: int, ult_amt: float, haste_sec: float = 0.0) -> void:
	if player == null or not is_instance_valid(player):
		return
	if shadows > 0 and player.get("shadow_charges") != null and player.get("max_shadow_charges") != null:
		player.shadow_charges = mini(int(player.max_shadow_charges), int(player.shadow_charges) + shadows)
	if ult_amt > 0.0 and player.has_method(&"add_ult_energy"):
		player.call(&"add_ult_energy", ult_amt * ult_gain_mul)
	if haste_sec > 0.0:
		_flow_haste_timer = maxf(_flow_haste_timer, haste_sec)


func _check_milestone_crossings(prev_lv: int, next_lv: int) -> void:
	if core_id == "" or next_lv <= prev_lv:
		return
	for m in [10, 40, 100]:
		var req := tier_req(m)
		if prev_lv < req and next_lv >= req:
			_on_milestone_reached(m)


func _on_milestone_reached(milestone: int) -> void:
	if milestone == 100 and core_id == "core_bell":
		cheat_death_charges = maxi(cheat_death_charges, 1)
	if milestone == 10 and aegis_max > 0.0 and aegis_hp <= 0.0:
		aegis_hp = aegis_max
	var card_info: Dictionary = catalog.get_card(core_id) if catalog != null else {}
	var title := String(card_info.get("title", core_id))
	_banner_text = "%s Lv.%d" % [title, milestone]
	_banner_timer = 1.8
	if player != null and is_instance_valid(player):
		_spawn_flash(player.global_position + Vector2(0.0, -48.0), 145.0, COL_VIOLET_LIGHT, 0.36)
	milestone_unlocked.emit(core_id, milestone)


# ---------------------------------------------------------------- 角色面板同步（非侵入式安全缩放）

func get_damage_reduction() -> float:
	var d_def := maxi(0, int(stat_levels.get("stat_def", 1)) - 1)
	var bell_bonus := 0.12 if (core_id == "core_bell" and has_core_tier(10)) else 0.0
	return clampf((float(d_def) * 0.012 + bell_bonus) * BUFF_VALUE_SCALE, 0.0, 0.70)


func get_crit_chance() -> float:
	var d_crit := maxi(0, int(stat_levels.get("stat_crit", 1)) - 1)
	var chrono_bonus := 0.15 if (core_id == "core_chrono" and has_core_tier(10)) else 0.0
	return (float(d_crit) * 0.022 + chrono_bonus) * BUFF_VALUE_SCALE


func get_crit_bonus_mul() -> float:
	var d_crit := maxi(0, int(stat_levels.get("stat_crit", 1)) - 1)
	return (0.55 + float(d_crit) * 0.016) * BUFF_VALUE_SCALE


func get_core_power_mul() -> float:
	var lv_bonus := 1.0 + float(maxi(core_level - 10, 0)) * 0.020 * BUFF_VALUE_SCALE
	var atk_mul := float(player.attack_damage_mul) if player != null and is_instance_valid(player) else 1.0
	return lv_bonus * atk_mul


func _sync_player_stats() -> void:
	if player == null or not is_instance_valid(player) or not _baseline_captured:
		return
	# 未激活构筑（例如 test_rain_trial.gd 无头默认模式）：严格保持角色全套原始物理手感不变
	if not is_active_build():
		shadow_cap = _base_shadow_max
		return

	var d_atk := maxi(0, int(stat_levels.get("stat_atk", 1)) - 1)
	var d_spd := maxi(0, int(stat_levels.get("stat_spd", 1)) - 1)
	var d_def := maxi(0, int(stat_levels.get("stat_def", 1)) - 1)

	# 1. 攻击：伤害倍率 + 安全判定框拓宽 + 撞墙倍率（数值增益 ×0.1）
	_computed_base_atk_mul = 1.0 + float(d_atk) * 0.042 * BUFF_VALUE_SCALE
	player.attack_damage_mul = _computed_base_atk_mul
	player.wall_damage_scale = _base_wall_scale * (1.0 + float(d_atk) * 0.020 * BUFF_VALUE_SCALE)
	var hb_scale_x := minf(1.45, 1.0 + (float(d_atk) * 0.012 + (0.14 if core_id == "core_rift" and has_core_tier(10) else 0.0)) * BUFF_VALUE_SCALE)
	var hb_scale_y := minf(1.24, 1.0 + float(d_atk) * 0.005 * BUFF_VALUE_SCALE)

	# 2. 速度：移速 + 招式前后摇安全加速 + 蓄力加速（数值 ×0.1），残影上限与百级无限闪机制保留
	_computed_base_speed = _base_speed * (1.0 + minf(0.45, float(d_spd) * 0.011) * BUFF_VALUE_SCALE)
	player.speed = _computed_base_speed * (1.20 if _flow_haste_timer > 0.0 else 1.0)
	player.charge_rate_scale = _base_charge_scale * (1.0 + float(d_spd) * 0.025 * BUFF_VALUE_SCALE)
	player.heavy_full_charge_frames = maxi(10, roundi(float(_base_heavy_charge_frames) / (1.0 + float(d_spd) * 0.025 * BUFF_VALUE_SCALE)))

	# 2.5 非基础数值机制同步：霸体抗打断 / 韧性层数 / 额外空中跳
	if player.get("buff_attack_poise") != null:
		player.set("buff_attack_poise", attack_poise)
	if player.get("buff_poise_charges") != null:
		if poise_max_charges > 0 and int(player.get("buff_poise_charges")) == 0 and _poise_regen_timer <= 0.0:
			player.set("buff_poise_charges", poise_max_charges)
		else:
			player.set("buff_poise_charges", mini(poise_max_charges, int(player.get("buff_poise_charges"))))
	player.extra_air_jumps = _base_extra_air_jumps + extra_air_jumps_bonus
	if attack_poise:
		player.soft_knock_threshold = maxf(_base_soft_knock, 620.0)
	else:
		player.soft_knock_threshold = maxf(_base_soft_knock, 480.0 if (aegis_hp > 1.0 and core_id == "core_bell" and has_core_tier(10)) else _base_soft_knock)

	var bonus_shadows := 0
	var spd_lv := int(stat_levels.get("stat_spd", 1))
	if spd_lv >= 15:
		bonus_shadows += 1
	if spd_lv >= 35:
		bonus_shadows += 1
	if spd_lv >= 75:
		bonus_shadows += 1
	if core_id == "core_crow" and has_core_tier(10):
		bonus_shadows += 1
	bonus_shadows += shadow_cap_bonus
	var prev_cap := int(player.max_shadow_charges)
	shadow_cap = _base_shadow_max + bonus_shadows
	player.max_shadow_charges = shadow_cap
	if shadow_cap > prev_cap:
		player.shadow_charges = mini(shadow_cap, int(player.shadow_charges) + (shadow_cap - prev_cap))
	player.shadow_regen_seconds = maxf(0.55, (_base_shadow_regen / (1.0 + float(d_spd) * 0.024 * BUFF_VALUE_SCALE)) * shadow_regen_mul)
	player.unlimited_dash = _base_unlimited_dash or (core_id == "core_crow" and has_core_tier(100))

	# 3. 防御：最大生命（等额抬升当前血量）+ 弹刀判定拓宽 + 驻时凝光盾上限（数值 ×0.1）
	var old_max_hp := float(player.max_hp)
	var target_max_hp := _base_max_hp + float(d_def) * 4.5 * BUFF_VALUE_SCALE
	player.max_hp = target_max_hp
	if target_max_hp > old_max_hp + 0.01:
		player.hp = minf(target_max_hp, float(player.hp) + (target_max_hp - old_max_hp))
		if stage != null and stage.get("_hp_seen") != null:
			stage.set("_hp_seen", player.hp)

	var prev_aegis_max := aegis_max
	var base_shield := float(d_def) * 2.2 * BUFF_VALUE_SCALE
	if core_id == "core_bell" and has_core_tier(10):
		base_shield += (42.0 + float(core_level) * 1.45) * BUFF_VALUE_SCALE
	aegis_max = base_shield
	if aegis_max > prev_aegis_max:
		aegis_hp = minf(aegis_max, aegis_hp + (aegis_max - prev_aegis_max))
	else:
		aegis_hp = minf(aegis_hp, aegis_max)

	# 4. 写回克隆招式帧数与判定框（攻速/弹刀加成数值 ×0.1）
	var atk_haste := minf(0.42, float(d_spd) * 0.010) * BUFF_VALUE_SCALE
	var parry_bonus := roundi((float(clampi(d_def / 8, 0, 6)) + (2.0 if core_id == "core_bell" and has_core_tier(10) else 0.0)) * BUFF_VALUE_SCALE)
	for entry in _move_baselines:
		var mv: MoveDefinition = entry["move"]
		if mv == null:
			continue
		if mv.is_parry_move():
			mv.active_frames = int(entry["active"]) + parry_bonus
			continue
		var su := int(entry["startup"])
		var ac := int(entry["active"])
		var rc := int(entry["recovery"])
		mv.startup_frames = maxi(3, roundi(float(su) * (1.0 - atk_haste * 0.55))) if su >= 3 else su
		mv.active_frames = maxi(3, ac) if ac >= 3 else ac
		mv.recovery_frames = maxi(3, roundi(float(rc) * (1.0 - atk_haste))) if rc >= 3 else rc
		mv.animation_fps = float(entry["fps"]) * (1.0 + atk_haste * 0.75)
		var base_hb: Rect2 = entry["hitbox"]
		mv.hitbox = Rect2(
			Vector2(base_hb.position.x * hb_scale_x, base_hb.position.y),
			Vector2(base_hb.size.x * hb_scale_x, base_hb.size.y * hb_scale_y)
		)


# ---------------------------------------------------------------- 受击护盾与减伤拦截

## 由 rain_trial._on_player_hurt 或伤害监听调用；返回最终实际扣血量（0.0 表示全额被驻时凝光盾吸收）
func intercept_player_hurt(raw_dmg: float, point: Vector2, _dir: Vector2 = Vector2.ZERO) -> float:
	if player == null or not is_instance_valid(player) or raw_dmg <= 0.0 or not is_active_build():
		if player != null and is_instance_valid(player):
			_tracked_hp = float(player.hp)
		return raw_dmg
	_hurt_intercepted_frame = Engine.get_physics_frames()

	# 1. 计算受击前真实血量与防御减伤（防止致死伤害被底层 clamp 后多退血）
	var post_raw_hp := float(player.hp)
	var pre_hit_hp := minf(float(player.max_hp), post_raw_hp + raw_dmg)
	if _tracked_hp > post_raw_hp + 0.01 and absf((_tracked_hp - raw_dmg) - post_raw_hp) <= 2.0:
		pre_hit_hp = _tracked_hp
	var dr := get_damage_reduction()
	var mitigated_dmg := raw_dmg * (1.0 - dr)
	var remaining_dmg := mitigated_dmg
	_aegis_regen_delay = 3.2

	# 2. 驻时凝光盾吸收与反震
	if aegis_hp > 0.01:
		var absorbed := minf(aegis_hp, remaining_dmg)
		aegis_hp = maxf(0.0, aegis_hp - absorbed)
		remaining_dmg = maxf(0.0, remaining_dmg - absorbed)
		player.invuln_frames = maxi(int(player.invuln_frames), 18)
		if core_id == "core_bell" and has_core_tier(10):
			_trigger_bell_shockwave(player.global_position + Vector2(0.0, -32.0), 280.0, 1.0)
		else:
			_spawn_flash(point, 68.0, COL_GOLD, 0.20)

	# 2.5 荆棘夜袍：受击触发近身银紫荆棘反伤
	if thorn_ratio > 0.0 and raw_dmg > 0.0:
		var thorn_dmg := maxf(4.0, raw_dmg * thorn_ratio)
		_mv_crit.damage = thorn_dmg
		var center := player.global_position + Vector2(0.0, -34.0)
		var hit_any := false
		for s in _alive_shades():
			if s.global_position.distance_to(center) <= 340.0:
				hit_any = true
				var fdir := 1 if s.global_position.x >= center.x else -1
				_deal_perk_hit(s, _mv_crit, fdir, s.global_position + Vector2(0.0, -30.0), 1.0)
				_spawn_line(center, s.global_position + Vector2(0.0, -30.0), COL_SILVER, 0.18, 3.0)
		if hit_any:
			thorn_reflect_count += 1
			_spawn_flash(center, 96.0, Color("9ad0ff"), 0.20)

	var target_hp := clampf(pre_hit_hp - remaining_dmg, 0.0, float(player.max_hp))
	if post_raw_hp <= 1.5 and remaining_dmg > 1.5:
		target_hp = minf(target_hp, post_raw_hp)
	player.hp = target_hp

	# 3. 司辰金钟 Lv.100【逆时金身】或【倒拨五分】濒死驻时锁血（每幕 1 次）
	var can_cheat := (core_id == "core_bell" and has_core_tier(100)) or immortal_clock_enabled
	if float(player.hp) <= 1.5 and cheat_death_charges > 0 and can_cheat:
		cheat_death_charges -= 1
		cheat_death_triggered_count += 1
		var heal_pct := 0.55 if immortal_clock_enabled else 0.38
		player.hp = maxf(float(player.hp), float(player.max_hp) * heal_pct)
		aegis_hp = aegis_max
		player.invuln_frames = maxi(int(player.invuln_frames), 75)
		_banner_text = "【倒拨五分】时间回溯 · 死境逢生！" if immortal_clock_enabled else "【逆时金身】驻时锁血 · 母钟护体！"
		_banner_timer = 2.2
		_trigger_grand_bell_wave(player.global_position)
		remaining_dmg = 0.0

	if stage != null and stage.get("_hp_seen") != null:
		stage.set("_hp_seen", player.hp)
	_tracked_hp = float(player.hp)
	_refresh_hud()
	return remaining_dmg


# ---------------------------------------------------------------- 信号联动：核心牌三阶技能与暴击

func arm_keen_edge() -> void:
	if player == null or not is_instance_valid(player):
		return
	player.keen_edge_timer = float(player.keen_edge_duration)
	if player.has_signal(&"keen_edge_ready_changed"):
		player.keen_edge_ready_changed.emit(true)


func _is_heavy_or_keen_move(mv: MoveDefinition) -> bool:
	if mv == null:
		return false
	if player != null and bool(player.get("_keen_swing_active")):
		return true
	var mid := mv.id
	if mid in [
		&"light_4", &"charge_1", &"up_strike", &"air_up", &"air_plunge",
		&"dash_slash", &"dash_slash_left", &"air_dash_slash", &"air_dash_slash_left",
		&"combo_k_launch", &"combo_k_pierce", &"combo_k_pierce_left", &"combo_k_cleave"
	]:
		return true
	return mv.is_charge or mv.damage >= 18.0


func _on_player_move_started(mv: Resource, _index: int = 0) -> void:
	if not is_active_build() or player == null or not (mv is MoveDefinition):
		return
	var move := mv as MoveDefinition
	if move.is_parry_move() or move.is_ranged():
		return

	swing_count += 1
	var ppos := player.global_position + Vector2(0.0, -38.0)
	var fdir := int(player.facing) if int(player.facing) != 0 else 1
	var is_heavy := _is_heavy_or_keen_move(move)

	match core_id:
		"core_rift":
			if has_core_tier(10) and is_heavy:
				_spawn_rift_arc(ppos, fdir, 1.15)
				spawn_real_rift(ppos + Vector2(float(fdir) * 140.0, -8.0), Vector2(float(fdir) * 0.68, -0.73))
			elif has_core_tier(40):
				_spawn_rift_arc(ppos, fdir, 0.72)
			if has_core_tier(40) and is_heavy:
				detonate_all_rifts()
			if has_core_tier(100) and (is_heavy or swing_count % 6 == 0) and _sky_storm_cd <= 0.0:
				_trigger_sky_blade_storm()
		"core_crow":
			if move.id in [&"dash_slash", &"dash_slash_left", &"air_dash_slash", &"air_dash_slash_left"]:
				if has_core_tier(10):
					_spawn_decoy(player.global_position, fdir, has_core_tier(40))
					arm_keen_edge()
				if has_core_tier(100):
					_trigger_slash_web(player.global_position)
			if has_core_tier(40):
				_spawn_feather_bolts(ppos, fdir, 2 if is_heavy else 1)
		"core_bell":
			if has_core_tier(40) and swing_count % 4 == 0:
				_trigger_bell_shockwave(ppos, 320.0, 1.15)
			if has_core_tier(100) and (is_heavy or swing_count % 8 == 0) and _grand_bell_cd <= 0.0:
				_trigger_grand_bell_wave(ppos)


func _on_player_combo_finisher(_mv: Resource, _stage_idx: int) -> void:
	if not is_active_build() or player == null:
		return
	if core_id == "core_rift" and has_core_tier(40):
		detonate_all_rifts()
	if core_id == "core_rift" and has_core_tier(100) and _sky_storm_cd <= 0.0:
		_trigger_sky_blade_storm()


func _on_player_short_dash(direction: int, origin: Vector2) -> void:
	if not is_active_build() or player == null:
		return
	var dir_sign := direction if direction != 0 else (int(player.facing) if int(player.facing) != 0 else 1)
	if dash_nova_enabled:
		_trigger_dash_nova(origin)
	if core_id == "core_crow" and has_core_tier(10):
		_spawn_decoy(origin, dir_sign, false)
		if has_core_tier(40):
			_spawn_decoy(origin + Vector2(float(dir_sign) * 150.0, 0.0), -dir_sign, true)
		arm_keen_edge()
	if core_id == "core_crow" and has_core_tier(100):
		_trigger_slash_web(origin)


func _on_player_shadow_pursuit(_target: Node2D, destination: Vector2) -> void:
	if not is_active_build() or player == null:
		return
	var fdir := int(player.facing) if int(player.facing) != 0 else 1
	if dash_nova_enabled:
		_trigger_dash_nova(player.global_position)
	if core_id == "core_crow" and has_core_tier(10):
		_spawn_decoy(player.global_position, fdir, false)
		if has_core_tier(40):
			_spawn_decoy(destination, -fdir, true)
		arm_keen_edge()
	if core_id == "core_crow" and has_core_tier(100):
		_trigger_slash_web(destination)


func _trigger_dash_nova(origin: Vector2) -> void:
	dash_nova_count += 1
	var center := origin + Vector2(0.0, -34.0)
	bell_rings.append({"pos": center, "max_r": 240.0, "ttl": 0.24, "max_ttl": 0.24, "grand": false})
	_clear_enemy_projectiles_near(center, 250.0)
	_mv_clone.damage = 14.0
	for s in _alive_shades():
		if s.global_position.distance_to(center) <= 240.0:
			var fdir := 1 if s.global_position.x >= center.x else -1
			_deal_perk_hit(s, _mv_clone, fdir, center, 1.0)
			_damage_any_shell(s, 14.0, center)


func _on_player_perfect_dodge(_enemy: Node2D, point: Vector2) -> void:
	if not is_active_build():
		return
	if core_id == "core_chrono" and has_core_tier(100) and _time_stop_cd <= 0.0:
		trigger_time_stop_domain(point)


func _on_player_parry_success(attacker: Node, point: Vector2) -> void:
	if not is_active_build() or player == null:
		return
	if shadow_flow_enabled:
		_grant_shadow_and_ult(1, 12.0, 2.5)
	if parry_heal_enabled:
		heal_player(float(player.max_hp) * 0.10)
		if stage != null and stage.get("style") != null and stage.style.has_method(&"add_raw_points"):
			stage.style.call(&"add_raw_points", 25.0)
	if core_id == "core_bell":
		if has_core_tier(10):
			aegis_hp = minf(aegis_max, aegis_hp + aegis_max * 0.35)
			_trigger_bell_shockwave(point, 340.0, 1.35)
		if has_core_tier(100) and _grand_bell_cd <= 0.0:
			_trigger_grand_bell_wave(point)
	elif core_id == "core_chrono":
		if has_core_tier(10) and attacker is Node2D and is_instance_valid(attacker):
			_strike_thunder(attacker as Node2D, has_core_tier(40))
		if has_core_tier(100) and _time_stop_cd <= 0.0:
			trigger_time_stop_domain(point)
	elif core_id == "core_rift" and has_core_tier(100) and _sky_storm_cd <= 0.0:
		_trigger_sky_blade_storm()


func _on_player_plunge_landed(point: Vector2) -> void:
	if not is_active_build() or player == null:
		return
	if core_id == "core_rift":
		if has_core_tier(10):
			spawn_real_rift(point + Vector2(0.0, -45.0), Vector2(0.85, -0.52))
		if has_core_tier(40):
			detonate_all_rifts(point)
		if has_core_tier(100) and _sky_storm_cd <= 0.0:
			_trigger_sky_blade_storm()
	elif core_id == "core_bell" and has_core_tier(40):
		_trigger_bell_shockwave(point, 360.0, 1.35)


func _on_player_hit_confirmed(target: Node2D, mv: Resource, point: Vector2) -> void:
	if _applying_perk_hit or not is_active_build() or player == null:
		return
	if target == null or not is_instance_valid(target):
		return
	var victim := target
	var move := mv as MoveDefinition
	_process_hit_effects(victim, move, point)


## 首领断潮有凝光壳时 take_hit 返回 false 不发 hit_confirmed，通过 shell_damaged 补齐暴击与核心联动
func _on_boss_shell_damaged(_amount: float, _remain: float, _is_backstab: bool, point: Vector2) -> void:
	if _applying_perk_hit or not is_active_build() or boss_ref == null or not is_instance_valid(boss_ref):
		return
	var cur_mv: MoveDefinition = player.get("current_move") as MoveDefinition if player != null else null
	_process_hit_effects(boss_ref, cur_mv, point)


func _on_boss_shell_shattered(_point: Vector2) -> void:
	if core_id == "core_chrono" and has_core_tier(40):
		arm_keen_edge()
	if shell_shred_bonus > 0.0:
		_grant_shadow_and_ult(1, 12.0)


func _process_hit_effects(victim: Node2D, move: MoveDefinition, point: Vector2) -> void:
	var d_crit := maxi(0, int(stat_levels.get("stat_crit", 1)) - 1)
	if d_crit > 0 and player.has_method(&"add_ult_energy"):
		player.add_ult_energy(float(d_crit) * 0.35 * BUFF_VALUE_SCALE * ult_gain_mul)
	elif ult_gain_mul > 1.001 and player.has_method(&"add_ult_energy"):
		player.add_ult_energy(1.8 * (ult_gain_mul - 1.0))

	# 吸血（血月汲魂 / 嗜血残酒 / 残夜血誓）
	var base_dmg := float(move.damage) if move != null else 12.0
	if lifesteal_ratio > 0.0:
		var est_dmg := base_dmg * float(player.attack_damage_mul)
		heal_player(est_dmg * lifesteal_ratio)

	# 断命残锋：对 30% 血以下敌人追加斩杀伤害
	if execute_bonus > 0.0 and victim != null and is_instance_valid(victim):
		var vhp: Variant = victim.get("hp")
		var vmax: Variant = victim.get("max_hp")
		if vhp != null and vmax != null and float(vmax) > 0.0 and (float(vhp) / float(vmax)) <= 0.30:
			_mv_crit.damage = maxf(3.0, base_dmg * execute_bonus)
			_deal_perk_hit(victim, _mv_crit, int(player.facing), point, 1.0)
			_spawn_flash(point, 52.0, COL_GOLD, 0.16)

	# 碎壳蚀锋：普通命中对凝光壳追加 +50% 额外碎壳伤害
	if shell_shred_bonus > 0.0 and victim != null and is_instance_valid(victim):
		_damage_any_shell(victim, base_dmg * shell_shred_bonus, point)

	# 司辰金钟 Lv.100 挥刀回盾（aegis_max 已按 ×0.1 缩放）
	if core_id == "core_bell" and has_core_tier(100) and aegis_max > 0.0:
		aegis_hp = minf(aegis_max, aegis_hp + aegis_max * 0.06)

	# 暴击与超暴击结算
	var crit_rate := get_crit_chance()
	var is_crit := false
	var is_over_crit := false
	if crit_rate >= 1.0:
		is_crit = true
		is_over_crit = rng.randf() < (crit_rate - 1.0)
	elif crit_rate > 0.0 and rng.randf() < crit_rate:
		is_crit = true

	if is_crit:
		crit_trigger_count += 1
		var bonus_mul := get_crit_bonus_mul() * (1.65 if is_over_crit else 1.0)
		var bonus_dmg := maxf(0.5, base_dmg * bonus_mul)
		_mv_crit.damage = bonus_dmg
		_deal_perk_hit(victim, _mv_crit, int(player.facing), point, 1.0)
		if is_over_crit:
			over_crit_count += 1
			_damage_any_shell(victim, 22.0 * BUFF_VALUE_SCALE, point)
		_spawn_flash(point, 58.0 if is_over_crit else 40.0, COL_SILVER if is_over_crit else COL_VIOLET_LIGHT, 0.16)
		if stage != null and stage.get("fx") != null:
			var fx_node: Node = stage.get("fx")
			if fx_node.has_method(&"spawn_text"):
				fx_node.call(&"spawn_text", point + Vector2(0.0, -36.0), "超暴!" if is_over_crit else "暴击!", bonus_dmg, true)

	# 刹那断晷：落雷与时停蓄能
	if core_id == "core_chrono" and has_core_tier(10):
		var is_keen := bool(player.get("_keen_swing_active")) or (move != null and move.id == &"light_4")
		var airborne := false
		if victim.has_method(&"ground_y"):
			airborne = victim.global_position.y < float(victim.call(&"ground_y")) - 12.0
		if is_keen or airborne or is_crit:
			_strike_thunder(victim, has_core_tier(40))
		if has_core_tier(100):
			if time_stop_timer > 0.0:
				var vid := victim.get_instance_id()
				_time_stop_marks[vid] = {
					"node": victim,
					"stacks": int(_time_stop_marks.get(vid, {}).get("stacks", 0)) + 1,
				}
			elif _time_stop_cd <= 0.0:
				_chrono_charge += 28.0 if is_crit else 18.0
				if _chrono_charge >= 100.0:
					_chrono_charge = 0.0
					trigger_time_stop_domain(point)


func _on_shade_spawned(s: Node2D) -> void:
	if s == null or not is_instance_valid(s):
		return
	if s.has_signal(&"shell_broken"):
		_connect_once(s, &"shell_broken", _on_enemy_shell_broken)
	if s.has_signal(&"lethal_blow"):
		_connect_once(s, &"lethal_blow", _on_enemy_lethal_blow)


func _on_enemy_shell_broken(_s: Node2D) -> void:
	if core_id == "core_chrono" and has_core_tier(40):
		arm_keen_edge()
	if shell_shred_bonus > 0.0:
		_grant_shadow_and_ult(1, 12.0)


func _on_enemy_lethal_blow(_point: Vector2, _dir: Vector2, overkill_launch: bool) -> void:
	if overkill_launch and core_id == "core_chrono" and has_core_tier(40):
		arm_keen_edge()
	if shadow_flow_enabled:
		_grant_shadow_and_ult(1, 12.0, 2.5)


# ---------------------------------------------------------------- 四大本命核心牌具体招式实现

## 1.《万仞裂空》：半屏穿透冷紫斩弧 + 真实 SpatialRift + 裂口十字引爆 + 万仞裁夜巨刃洗屏
func _spawn_rift_arc(origin: Vector2, dir_sign: int, scale_k: float = 1.0) -> void:
	rift_arc_count += 1
	arc_slashes.append({
		"pos": origin + Vector2(float(dir_sign) * 44.0, 0.0),
		"dir": dir_sign,
		"speed": 1320.0,
		"scale": scale_k,
		"ttl": 0.34 * scale_k,
		"max_ttl": 0.34 * scale_k,
		"hit_ids": {},
	})
	perk_triggered.emit("core_rift_arc", origin)


func spawn_real_rift(world_pos: Vector2, axis_dir: Vector2 = Vector2(0.7, -0.7)) -> Node2D:
	if stage == null or not is_inside_tree():
		return null
	var existing := get_tree().get_nodes_in_group(&"spatial_rift")
	while existing.size() >= 4:
		var oldest := existing.pop_front() as Node2D
		if oldest != null and is_instance_valid(oldest) and oldest.has_method(&"dismiss"):
			oldest.call(&"dismiss")
	var rift: Node2D = SpatialRiftScript.new()
	stage.add_child(rift)
	var dmg := 20.0 * BUFF_VALUE_SCALE * get_core_power_mul()
	rift.call(&"setup", world_pos, axis_dir, 125.0, player, dmg, &"core_rift")
	return rift


func detonate_all_rifts(pull_center: Vector2 = Vector2.INF) -> int:
	if not is_inside_tree():
		return 0
	var rifts_now := get_tree().get_nodes_in_group(&"spatial_rift")
	if rifts_now.is_empty():
		return 0
	var count := 0
	var p_mul := get_core_power_mul()
	for node in rifts_now:
		var r := node as Node2D
		if r == null or not is_instance_valid(r):
			continue
		if r.has_method(&"is_active") and not bool(r.call(&"is_active")):
			continue
		var rpos := r.global_position
		count += 1
		rift_detonation_count += 1
		_spawn_flash(rpos, 140.0, COL_VIOLET, 0.26)
		_spawn_line(rpos + Vector2(-135.0, -35.0), rpos + Vector2(135.0, 35.0), COL_SILVER, 0.24, 5.0)
		_spawn_line(rpos + Vector2(-35.0, 135.0), rpos + Vector2(35.0, -135.0), COL_VIOLET_LIGHT, 0.24, 5.0)
		for s in _alive_shades():
			if s.global_position.distance_to(rpos) <= 230.0:
				var fdir := 1 if s.global_position.x >= rpos.x else -1
				if is_finite(pull_center.x):
					s.global_position = s.global_position.lerp(pull_center, 0.35)
				_deal_perk_hit(s, _mv_storm, fdir, rpos, 0.85 * p_mul)
				_damage_any_shell(s, 28.0 * BUFF_VALUE_SCALE, rpos)
		if r.has_method(&"dismiss"):
			r.call(&"dismiss")
	return count


func _trigger_sky_blade_storm() -> void:
	_sky_storm_cd = 2.2
	sky_storm_count += 1
	var bounds := _arena_bounds()
	var span := maxf(480.0, bounds.y - bounds.x - 160.0)
	var blade_n := 6
	for i in blade_n:
		var ratio := float(i) / float(blade_n - 1)
		var bx := bounds.x + 80.0 + span * ratio
		var gy := float(stage.get("floor_y")) if stage != null and stage.get("floor_y") != null else (player.global_position.y + 44.0)
		sky_blades.append({
			"x": bx,
			"ground_y": gy,
			"delay": float(i) * 0.045,
			"ttl": 0.36,
			"max_ttl": 0.36,
			"struck": false,
		})
	perk_triggered.emit("core_rift_storm", player.global_position if player != null else Vector2.ZERO)


## 2.《千羽绝影》：冷紫像素替身 + 追踪幻影飞刃 + 无间鸦闪全屏斩网
func _spawn_decoy(pos: Vector2, facing_dir: int, delayed_second: bool = false) -> void:
	decoys.append({
		"pos": pos,
		"facing": facing_dir if facing_dir != 0 else 1,
		"timer": 0.22 if delayed_second else 0.12,
		"slashed": false,
		"fade": 0.26,
	})


func _spawn_feather_bolts(origin: Vector2, facing_dir: int, count: int) -> void:
	for i in count:
		feather_shot_count += 1
		var spread_y := -18.0 + float(i) * 24.0
		feather_bolts.append({
			"pos": origin + Vector2(float(facing_dir) * 28.0, spread_y),
			"vel": Vector2(float(facing_dir) * 1080.0, spread_y * 2.5),
			"ttl": 0.75,
		})


func _trigger_slash_web(center: Vector2) -> void:
	slash_web_count += 1
	var p_mul := get_core_power_mul()
	_clear_enemy_projectiles_near(center, 720.0)
	var hit_any := false
	for s in _alive_shades():
		if absf(s.global_position.x - center.x) <= 680.0 and absf(s.global_position.y - center.y) <= 340.0:
			hit_any = true
			var sp := s.global_position + Vector2(0.0, -32.0)
			_spawn_line(sp + Vector2(-120.0, -58.0), sp + Vector2(120.0, 58.0), COL_SILVER, 0.22, 4.0)
			_spawn_line(sp + Vector2(-120.0, 58.0), sp + Vector2(120.0, -58.0), COL_VIOLET, 0.22, 4.0)
			_deal_perk_hit(s, _mv_clone, int(player.facing) if player != null else 1, sp, 0.95 * p_mul)
			_damage_any_shell(s, 18.0 * BUFF_VALUE_SCALE, sp)
	if not hit_any:
		_spawn_line(center + Vector2(-220.0, -64.0), center + Vector2(220.0, 64.0), COL_VIOLET_LIGHT, 0.20, 3.5)
		_spawn_line(center + Vector2(-220.0, 64.0), center + Vector2(220.0, -64.0), COL_SILVER, 0.20, 3.5)
	perk_triggered.emit("core_crow_web", center)


## 3.《刹那断晷》：紫白惊雷碎壳 + 连环弹射 + 刹那 5:59 局部时停（严禁改 Engine.time_scale）
func _strike_thunder(primary: Node2D, chain_enabled: bool) -> void:
	if primary == null or not is_instance_valid(primary):
		return
	thunder_strike_count += 1
	var p_mul := get_core_power_mul()
	var pt := primary.global_position + Vector2(0.0, -36.0)
	_spawn_lightning_bolt(pt + Vector2(0.0, -280.0), pt)
	_deal_perk_hit(primary, _mv_thunder, int(player.facing) if player != null else 1, pt, p_mul)
	_damage_any_shell(primary, 26.0 * BUFF_VALUE_SCALE, pt)

	if chain_enabled:
		var jumps := 0
		for s in _alive_shades():
			if s == primary or jumps >= 2:
				continue
			if s.global_position.distance_to(primary.global_position) <= 380.0:
				jumps += 1
				var spt := s.global_position + Vector2(0.0, -36.0)
				_spawn_lightning_bolt(pt, spt)
				_deal_perk_hit(s, _mv_thunder, int(player.facing) if player != null else 1, spt, 0.72 * p_mul)
				_damage_any_shell(s, 18.0 * BUFF_VALUE_SCALE, spt)


func trigger_time_stop_domain(center: Vector2) -> void:
	time_stop_count += 1
	time_stop_timer = 2.0
	_time_stop_cd = 5.5
	_time_stop_marks.clear()
	_freeze_active_enemy_entities()
	_spawn_flash(center, 220.0, COL_SILVER, 0.35)
	perk_triggered.emit("core_chrono_timestop", center)


func _freeze_active_enemy_entities() -> void:
	if not is_inside_tree():
		return
	for s in _alive_shades():
		if s.get("hitstop_frames") != null:
			s.set("hitstop_frames", maxi(int(s.get("hitstop_frames")), 8))
	for b in get_tree().get_nodes_in_group(&"shade_projectile"):
		if b != null and is_instance_valid(b):
			b.set_physics_process(false)
			if not _frozen_projectiles.has(b):
				_frozen_projectiles.append(b)


func _release_time_stop(detonate: bool) -> void:
	time_stop_timer = 0.0
	for b in _frozen_projectiles:
		if b != null and is_instance_valid(b):
			b.set_physics_process(true)
	_frozen_projectiles.clear()

	if detonate and is_inside_tree():
		var p_mul := get_core_power_mul()
		# 保底对场上全部存活敌影落雷，叠印记的敌影引爆最高三倍紫电
		for s in _alive_shades():
			var vid := s.get_instance_id()
			var stacks := maxi(1, mini(3, int(_time_stop_marks.get(vid, {}).get("stacks", 1))))
			var pt := s.global_position + Vector2(0.0, -36.0)
			_spawn_lightning_bolt(pt + Vector2(0.0, -320.0), pt)
			_deal_perk_hit(s, _mv_thunder, int(player.facing) if player != null else 1, pt, float(stacks) * 1.15 * p_mul)
			_damage_any_shell(s, 24.0 * BUFF_VALUE_SCALE * float(stacks), pt)
	_time_stop_marks.clear()


## 4.《司辰金钟》：驻时凝光盾反震 + 4刀自动钟鸣波 + 母钟全屏横扫巨浪
func _trigger_bell_shockwave(center: Vector2, radius: float, scale_k: float) -> void:
	bell_wave_count += 1
	var shield_bonus := aegis_max * 0.18
	var p_mul := get_core_power_mul() * scale_k
	bell_rings.append({
		"pos": center,
		"max_r": radius,
		"ttl": 0.28,
		"max_ttl": 0.28,
		"grand": false,
	})
	_clear_enemy_projectiles_near(center, radius + 40.0)
	_mv_bell.damage = 15.0 * BUFF_VALUE_SCALE + shield_bonus
	for s in _alive_shades():
		if s.global_position.distance_to(center) <= radius:
			var fdir := 1 if s.global_position.x >= center.x else -1
			_deal_perk_hit(s, _mv_bell, fdir, center, p_mul)
			_damage_any_shell(s, 26.0 * BUFF_VALUE_SCALE + shield_bonus * 0.5, center)
	perk_triggered.emit("core_bell_wave", center)


func _trigger_grand_bell_wave(center: Vector2) -> void:
	_grand_bell_cd = 3.2
	grand_bell_count += 1
	var bounds := _arena_bounds()
	var span_r := maxf(680.0, (bounds.y - bounds.x) * 0.75)
	var shield_bonus := aegis_max * 0.25
	var p_mul := get_core_power_mul() * 1.45
	bell_rings.append({
		"pos": center,
		"max_r": span_r,
		"ttl": 0.42,
		"max_ttl": 0.42,
		"grand": true,
	})
	_clear_enemy_projectiles_near(center, span_r)
	_mv_bell.damage = 22.0 * BUFF_VALUE_SCALE + shield_bonus
	for s in _alive_shades():
		var fdir := 1 if s.global_position.x >= center.x else -1
		_deal_perk_hit(s, _mv_bell, fdir, s.global_position, p_mul)
		_damage_any_shell(s, 40.0 * BUFF_VALUE_SCALE + shield_bonus * 0.5, s.global_position)
	perk_triggered.emit("core_bell_grand", center)


# ---------------------------------------------------------------- 物理帧推进（投射物、替身、护盾再生、局部时停）

func _physics_process(delta: float) -> void:
	_time += delta
	if _sky_storm_cd > 0.0:
		_sky_storm_cd = maxf(0.0, _sky_storm_cd - delta)
	if _grand_bell_cd > 0.0:
		_grand_bell_cd = maxf(0.0, _grand_bell_cd - delta)
	if _time_stop_cd > 0.0:
		_time_stop_cd = maxf(0.0, _time_stop_cd - delta)
	if _banner_timer > 0.0:
		_banner_timer = maxf(0.0, _banner_timer - delta)

	# 首领战等未覆写 _on_player_hurt 的场景：自动追踪血量差触发凝光盾与逆时锁血
	if is_active_build() and player != null and is_instance_valid(player):
		var cur_hp := float(player.hp)
		if _tracked_hp < 0.0 or cur_hp > _tracked_hp:
			_tracked_hp = cur_hp
		elif cur_hp < _tracked_hp - 0.05:
			if _hurt_intercepted_frame != Engine.get_physics_frames():
				intercept_player_hurt(_tracked_hp - cur_hp, player.global_position)
			_tracked_hp = float(player.hp)

	# 驻时凝光盾自动再生与护盾在身免小硬直
	if aegis_max > 0.0 and player != null and is_instance_valid(player):
		if _aegis_regen_delay > 0.0:
			_aegis_regen_delay = maxf(0.0, _aegis_regen_delay - delta)
		elif aegis_hp < aegis_max:
			aegis_hp = minf(aegis_max, aegis_hp + aegis_max * 0.22 * delta)
		if aegis_hp > 1.0 and core_id == "core_bell" and has_core_tier(10):
			player.soft_knock_threshold = maxf(float(player.soft_knock_threshold), 480.0)

	# 护体韧性自动回复（每 6 秒恢复 1 层）、疾行回流移速、低血狂澜与空伤实时同步
	if is_active_build() and player != null and is_instance_valid(player):
		if poise_max_charges > 0 and player.get("buff_poise_charges") != null:
			var cur_p := int(player.get("buff_poise_charges"))
			if cur_p < poise_max_charges:
				_poise_regen_timer += delta
				if _poise_regen_timer >= 6.0:
					_poise_regen_timer = 0.0
					player.set("buff_poise_charges", mini(poise_max_charges, cur_p + 1))
			else:
				_poise_regen_timer = 0.0
		if _flow_haste_timer > 0.0:
			_flow_haste_timer = maxf(0.0, _flow_haste_timer - delta)
			player.speed = _computed_base_speed * (1.20 if _flow_haste_timer > 0.0 else 1.0)
		var dyn_mul := _computed_base_atk_mul
		if low_hp_dmg_bonus > 0.0 and float(player.hp) <= float(player.max_hp) * 0.5:
			dyn_mul *= (1.0 + low_hp_dmg_bonus)
		if aerial_dmg_bonus > 0.0 and not player.is_on_floor():
			dyn_mul *= (1.0 + aerial_dmg_bonus)
		if combo_surge_per_10 > 0.0 and stage != null and stage.get("style") != null:
			var stacks := mini(6, int(stage.style.combo) / 10)
			if stacks > 0:
				dyn_mul *= (1.0 + float(stacks) * combo_surge_per_10)
		player.attack_damage_mul = dyn_mul

	# 刹那 5:59 局部时停维持与结算
	if time_stop_timer > 0.0:
		_freeze_active_enemy_entities()
		time_stop_timer -= delta
		if time_stop_timer <= 0.0:
			_release_time_stop(true)

	_tick_arc_slashes(delta)
	_tick_sky_blades(delta)
	_tick_decoys(delta)
	_tick_feather_bolts(delta)
	_tick_vfx(delta)
	queue_redraw()
	if _hud_canvas != null:
		_hud_canvas.queue_redraw()


func _tick_arc_slashes(delta: float) -> void:
	var p_mul := get_core_power_mul()
	var i := arc_slashes.size() - 1
	while i >= 0:
		var item: Dictionary = arc_slashes[i]
		var pos: Vector2 = item["pos"] + Vector2(float(item["dir"]) * float(item["speed"]) * delta, 0.0)
		item["pos"] = pos
		item["ttl"] = float(item["ttl"]) - delta
		var sk := float(item["scale"])
		var hits: Dictionary = item["hit_ids"]
		_clear_enemy_projectiles_near(pos, 96.0 * sk)
		for s in _alive_shades():
			var sid := s.get_instance_id()
			if hits.has(sid):
				continue
			if absf(s.global_position.x - pos.x) <= 95.0 * sk and absf(s.global_position.y - pos.y) <= 125.0 * sk:
				hits[sid] = true
				_deal_perk_hit(s, _mv_arc, int(item["dir"]), pos, p_mul * sk)
				_damage_any_shell(s, 18.0 * BUFF_VALUE_SCALE * sk, pos)
		if float(item["ttl"]) <= 0.0:
			arc_slashes.remove_at(i)
		i -= 1


func _tick_sky_blades(delta: float) -> void:
	var p_mul := get_core_power_mul()
	var i := sky_blades.size() - 1
	while i >= 0:
		var b: Dictionary = sky_blades[i]
		if float(b["delay"]) > 0.0:
			b["delay"] = float(b["delay"]) - delta
			i -= 1
			continue
		if not bool(b["struck"]):
			b["struck"] = true
			var bx := float(b["x"])
			var gy := float(b["ground_y"])
			var impact := Vector2(bx, gy - 36.0)
			_clear_enemy_projectiles_near(impact, 160.0)
			for s in _alive_shades():
				if absf(s.global_position.x - bx) <= 145.0:
					var fdir := 1 if (player == null or s.global_position.x >= player.global_position.x) else -1
					_deal_perk_hit(s, _mv_storm, fdir, impact, p_mul)
					_damage_any_shell(s, 32.0 * BUFF_VALUE_SCALE, impact)
		b["ttl"] = float(b["ttl"]) - delta
		if float(b["ttl"]) <= 0.0:
			sky_blades.remove_at(i)
		i -= 1


func _tick_decoys(delta: float) -> void:
	var p_mul := get_core_power_mul()
	var i := decoys.size() - 1
	while i >= 0:
		var d: Dictionary = decoys[i]
		if not bool(d["slashed"]):
			d["timer"] = float(d["timer"]) - delta
			if float(d["timer"]) <= 0.0:
				d["slashed"] = true
				clone_slash_count += 1
				var dpos: Vector2 = d["pos"]
				var fdir := int(d["facing"])
				_clear_enemy_projectiles_near(dpos, 180.0)
				for s in _alive_shades():
					if s.global_position.distance_to(dpos) <= 210.0:
						_deal_perk_hit(s, _mv_clone, fdir, dpos, p_mul)
						_damage_any_shell(s, 18.0 * BUFF_VALUE_SCALE, dpos)
		else:
			d["fade"] = float(d["fade"]) - delta
			if float(d["fade"]) <= 0.0:
				decoys.remove_at(i)
		i -= 1


func _tick_feather_bolts(delta: float) -> void:
	var p_mul := get_core_power_mul()
	var i := feather_bolts.size() - 1
	while i >= 0:
		var fb: Dictionary = feather_bolts[i]
		var pos: Vector2 = fb["pos"]
		var vel: Vector2 = fb["vel"]
		var target := _nearest_shade(pos)
		if target != null:
			var want := (target.global_position + Vector2(0.0, -36.0) - pos).normalized() * 1160.0
			vel = vel.lerp(want, minf(1.0, delta * 14.0))
		pos += vel * delta
		fb["pos"] = pos
		fb["vel"] = vel
		fb["ttl"] = float(fb["ttl"]) - delta
		var hit := false
		for s in _alive_shades():
			if s.global_position.distance_to(pos) <= 74.0:
				var fdir := 1 if vel.x >= 0.0 else -1
				_deal_perk_hit(s, _mv_feather, fdir, pos, 0.72 * p_mul)
				_damage_any_shell(s, 8.0 * BUFF_VALUE_SCALE, pos)
				_spawn_flash(pos, 32.0, COL_VIOLET_LIGHT, 0.12)
				hit = true
				break
		if hit or float(fb["ttl"]) <= 0.0:
			feather_bolts.remove_at(i)
		i -= 1


func _tick_vfx(delta: float) -> void:
	var i := bell_rings.size() - 1
	while i >= 0:
		bell_rings[i]["ttl"] = float(bell_rings[i]["ttl"]) - delta
		if float(bell_rings[i]["ttl"]) <= 0.0:
			bell_rings.remove_at(i)
		i -= 1
	var j := vfx_lines.size() - 1
	while j >= 0:
		vfx_lines[j]["ttl"] = float(vfx_lines[j]["ttl"]) - delta
		if float(vfx_lines[j]["ttl"]) <= 0.0:
			vfx_lines.remove_at(j)
		j -= 1
	var k := vfx_flashes.size() - 1
	while k >= 0:
		vfx_flashes[k]["ttl"] = float(vfx_flashes[k]["ttl"]) - delta
		if float(vfx_flashes[k]["ttl"]) <= 0.0:
			vfx_flashes.remove_at(k)
		k -= 1


# ---------------------------------------------------------------- 伤害、碎壳与清弹辅助

func _deal_perk_hit(shade: Node2D, mv: MoveDefinition, from_facing: int, point: Vector2, mul: float = 1.0) -> void:
	if shade == null or not is_instance_valid(shade) or not shade.has_method(&"take_hit"):
		return
	if shade.get("state") != null and int(shade.get("state")) == Shade.State.DEAD:
		return
	_applying_perk_hit = true
	shade.call(&"take_hit", mv, from_facing if from_facing != 0 else 1, point, 0.0, false, mul, player)
	_applying_perk_hit = false


## 统一削减普通甲影（shell_hp）与首领断潮（damage_shell）的凝光壳
func _damage_any_shell(shade: Node2D, amount: float, point: Vector2) -> void:
	if shade == null or not is_instance_valid(shade) or amount <= 0.0:
		return
	var fdir := int(player.facing) if player != null and int(player.facing) != 0 else 1
	if shade.has_method(&"damage_shell"):
		_applying_perk_hit = true
		shade.call(&"damage_shell", amount, point, fdir, false)
		_applying_perk_hit = false
		return
	if shade.get("shell_hp") != null and float(shade.get("shell_hp")) > 0.0:
		var next_sh := maxf(0.0, float(shade.get("shell_hp")) - amount)
		shade.set("shell_hp", next_sh)
		if next_sh <= 0.0 and shade.has_method(&"_break_shell"):
			shade.call(&"_break_shell")


## 给加赛精锐敌影披覆原生凝光壳（严禁使用旧“白瓷”词条）
func apply_luminous_shell(shade: Node2D, shell_amount: float = 60.0) -> void:
	if shade == null or not is_instance_valid(shade):
		return
	if shade.get("max_shell") != null and shade.get("shell_hp") != null:
		shade.set("max_shell", maxf(float(shade.get("max_shell")), shell_amount))
		shade.set("shell_hp", float(shade.get("max_shell")))
		shade.set("_shell_broken_emitted", false)


func _clear_enemy_projectiles_near(center: Vector2, radius: float) -> void:
	if not is_inside_tree():
		return
	var r2 := radius * radius
	for b in get_tree().get_nodes_in_group(&"shade_projectile"):
		if b is Node2D and is_instance_valid(b):
			if (b as Node2D).global_position.distance_squared_to(center) <= r2:
				b.queue_free()
	# 首领断潮的裂水波与悬雨针（若有）一并可在巨钟波内净化
	if boss_ref != null and is_instance_valid(boss_ref):
		var needles: Variant = boss_ref.get("_rain_needles")
		if needles is Array:
			for item in needles:
				if item is Dictionary and (item as Dictionary).has("pos"):
					if ((item as Dictionary)["pos"] as Vector2).distance_squared_to(center) <= r2:
						(item as Dictionary)["done"] = true


func _alive_shades() -> Array[Node2D]:
	var out: Array[Node2D] = []
	if not is_inside_tree():
		return out
	for n in get_tree().get_nodes_in_group(&"shade"):
		var s := n as Node2D
		if s != null and is_instance_valid(s) and int(s.get("state")) != Shade.State.DEAD:
			out.append(s)
	return out


func _nearest_shade(origin: Vector2) -> Node2D:
	var best: Node2D = null
	var best_d := INF
	for s in _alive_shades():
		var d := s.global_position.distance_squared_to(origin)
		if d < best_d:
			best_d = d
			best = s
	return best


func _arena_bounds() -> Vector2:
	if stage != null:
		var seal: Variant = stage.get("seal_x")
		if seal is Vector2 and (seal as Vector2).y > (seal as Vector2).x + 50.0:
			return seal as Vector2
		if stage.get("arena_center") != null and stage.get("arena_half") != null:
			var c := float(stage.get("arena_center"))
			var h := float(stage.get("arena_half"))
			if h > 50.0:
				return Vector2(c - h, c + h)
	var px := player.global_position.x if player != null and is_instance_valid(player) else 640.0
	return Vector2(px - 880.0, px + 880.0)


func _spawn_lightning_bolt(from_pt: Vector2, to_pt: Vector2) -> void:
	var segs := 6
	var prev := from_pt
	var ortho := (to_pt - from_pt).orthogonal().normalized()
	for i in range(1, segs + 1):
		var u := float(i) / float(segs)
		var nxt := from_pt.lerp(to_pt, u)
		if i < segs:
			nxt += ortho * rng.randf_range(-24.0, 24.0)
		_spawn_line(prev, nxt, COL_VIOLET, 0.22, 6.0)
		_spawn_line(prev, nxt, COL_SILVER, 0.22, 2.4)
		prev = nxt
	_spawn_flash(to_pt, 56.0, COL_SILVER, 0.18)


func _spawn_line(a: Vector2, b: Vector2, col: Color, ttl: float, width: float = 3.5) -> void:
	vfx_lines.append({"a": a, "b": b, "col": col, "ttl": ttl, "max_ttl": ttl, "w": width})


func _spawn_flash(pos: Vector2, radius: float, col: Color, ttl: float) -> void:
	vfx_flashes.append({"pos": pos, "r": radius, "col": col, "ttl": ttl, "max_ttl": ttl})


# ---------------------------------------------------------------- 纯几何程序化渲染（严守墨黑+冷紫+银白+微金，零橙红）

func _draw() -> void:
	if not is_active_build():
		return

	# 1. 角色周身驻时凝光盾环与 5:59 时停结界钟盘
	if player != null and is_instance_valid(player):
		var pp := to_local(player.global_position + Vector2(0.0, -34.0))
		if aegis_hp > 0.5 and aegis_max > 0.0:
			var ratio := clampf(aegis_hp / aegis_max, 0.12, 1.0)
			draw_arc(pp, 48.0, -PI * 0.5, -PI * 0.5 + TAU * ratio, 28, Color(COL_GOLD, 0.72), 3.2)
			draw_arc(pp, 43.0, 0.0, TAU, 24, Color(COL_SILVER, 0.22), 1.4)
		if time_stop_timer > 0.0:
			var tr := clampf(time_stop_timer / 2.0, 0.0, 1.0)
			draw_arc(pp, 260.0, 0.0, TAU, 48, Color(COL_VIOLET, 0.42 * tr + 0.15), 4.0)
			draw_arc(pp, 252.0, 0.0, TAU, 36, Color(COL_SILVER, 0.65 * tr), 1.8)
			var hand_ang := -PI * 0.5 - (1.0 - tr) * TAU
			draw_line(pp, pp + Vector2(cos(hand_ang), sin(hand_ang)) * 180.0, Color(COL_SILVER, 0.78), 2.6)
			draw_line(pp, pp + Vector2(0.0, -125.0), Color(COL_VIOLET_LIGHT, 0.70), 3.2)

	# 2.《万仞裂空》半屏穿透冷紫弧光
	for item in arc_slashes:
		var ap := to_local(item["pos"])
		var gf := float(item["dir"])
		var sk := float(item["scale"])
		var u := clampf(float(item["ttl"]) / maxf(0.05, float(item["max_ttl"])), 0.0, 1.0)
		var a0 := -1.12 if gf > 0.0 else PI - 1.12
		var a1 := 1.12 if gf > 0.0 else PI + 1.12
		var center := ap - Vector2(gf * 48.0 * sk, 0.0)
		draw_arc(center, 118.0 * sk, a0, a1, 24, Color(COL_INK, 0.85 * u), 20.0 * sk)
		draw_arc(center, 118.0 * sk, a0, a1, 24, Color(COL_VIOLET, 0.92 * u), 13.0 * sk)
		draw_arc(center, 118.0 * sk, a0 * 0.88, a1 * 0.88, 20, Color(COL_SILVER, 0.98 * u), 4.5 * sk)

	# 3.《万仞裁夜》天幕降落巨刃风暴
	for b in sky_blades:
		if float(b["delay"]) > 0.0:
			continue
		var u := clampf(float(b["ttl"]) / maxf(0.05, float(b["max_ttl"])), 0.0, 1.0)
		var gp := to_local(Vector2(float(b["x"]), float(b["ground_y"])))
		var top := gp + Vector2(0.0, -560.0)
		var hw := 26.0 * u
		var poly := PackedVector2Array([
			top,
			gp + Vector2(hw, -42.0),
			gp,
			gp + Vector2(-hw, -42.0),
		])
		draw_colored_polygon(poly, Color(COL_VIOLET, 0.76 * u))
		draw_line(top, gp, Color(COL_SILVER, 0.96 * u), 5.5 * u)

	# 4.《千羽绝影》冷紫像素残影替身与飞刃
	for d in decoys:
		var dp := to_local(d["pos"])
		var f := float(d["facing"])
		if not bool(d["slashed"]):
			var body := PackedVector2Array([
				dp + Vector2(-15.0 * f, 44.0),
				dp + Vector2(-22.0 * f, -12.0),
				dp + Vector2(8.0 * f, -54.0),
				dp + Vector2(26.0 * f, -36.0),
				dp + Vector2(14.0 * f, 44.0),
			])
			draw_colored_polygon(body, Color(COL_INK, 0.88))
			draw_polyline(body, Color(COL_VIOLET, 0.92), 2.4)
		else:
			var a := clampf(float(d["fade"]) / 0.26, 0.0, 1.0)
			draw_arc(dp + Vector2(22.0 * f, -12.0), 148.0, -1.05, 1.05, 22, Color(COL_VIOLET, 0.88 * a), 8.5)
			draw_arc(dp + Vector2(22.0 * f, -12.0), 148.0, -0.92, 0.92, 18, Color(COL_SILVER, 0.96 * a), 3.0)

	for fb in feather_bolts:
		var fp := to_local(fb["pos"])
		var fv := (fb["vel"] as Vector2).normalized()
		draw_line(fp - fv * 22.0, fp + fv * 16.0, Color(COL_VIOLET, 0.92), 5.0)
		draw_line(fp - fv * 12.0, fp + fv * 16.0, Color(COL_SILVER, 0.98), 2.0)

	# 5.《司辰金钟》银白微金钟鸣扩散波
	for ring in bell_rings:
		var u := 1.0 - clampf(float(ring["ttl"]) / maxf(0.05, float(ring["max_ttl"])), 0.0, 1.0)
		var alpha := 1.0 - u
		var rp := to_local(ring["pos"])
		var cur_r := lerpf(28.0, float(ring["max_r"]), 1.0 - pow(1.0 - u, 3.0))
		var is_grand := bool(ring["grand"])
		draw_arc(rp, cur_r, 0.0, TAU, 40, Color(COL_GOLD if is_grand else COL_SILVER, 0.86 * alpha), (10.0 if is_grand else 6.0) * alpha + 1.5)
		draw_arc(rp, cur_r * 0.84, 0.0, TAU, 32, Color(COL_VIOLET_LIGHT, 0.52 * alpha), 2.2)

	# 6. 惊雷折线与闪光
	for ln in vfx_lines:
		var u := clampf(float(ln["ttl"]) / maxf(0.04, float(ln["max_ttl"])), 0.0, 1.0)
		var col: Color = ln["col"]
		draw_line(to_local(ln["a"]), to_local(ln["b"]), Color(col.r, col.g, col.b, u * 0.95), float(ln["w"]) * u + 0.8)

	for fl in vfx_flashes:
		var u := clampf(float(fl["ttl"]) / maxf(0.04, float(fl["max_ttl"])), 0.0, 1.0)
		var col2: Color = fl["col"]
		var r_cur := float(fl["r"]) * (1.0 - 0.55 * u)
		draw_arc(to_local(fl["pos"]), r_cur, 0.0, TAU, 26, Color(col2.r, col2.g, col2.b, u * 0.85), 4.5 * u + 1.2)


# ---------------------------------------------------------------- 右上角极简万象徽章 HUD（零 SystemFont）

func _ensure_hud() -> void:
	if _hud_layer != null or _font_serif == null:
		return
	_hud_layer = CanvasLayer.new()
	_hud_layer.name = "WanxiangHudLayer"
	_hud_layer.layer = 9
	add_child(_hud_layer)
	_hud_canvas = Control.new()
	_hud_canvas.name = "WanxiangHudCanvas"
	_hud_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_canvas.draw.connect(_draw_hud_badge)
	_hud_layer.add_child(_hud_canvas)


func _refresh_hud() -> void:
	if _hud_canvas != null:
		_hud_canvas.queue_redraw()


func _draw_hud_badge() -> void:
	if _hud_canvas == null or _font_serif == null or not is_active_build():
		return
	var vp := _hud_canvas.get_viewport_rect().size
	var box_w := 288.0
	var box_h := 68.0 if aegis_max <= 0.0 else 78.0
	var rect := Rect2(vp.x - box_w - 20.0, 16.0, box_w, box_h)
	_hud_canvas.draw_rect(rect, Color(0.06, 0.05, 0.10, 0.82))
	_hud_canvas.draw_rect(rect, Color(COL_VIOLET, 0.55), false, 1.5)

	var core_title := "万象构筑"
	var accent := COL_VIOLET_LIGHT
	if core_id != "" and catalog != null:
		var info: Dictionary = catalog.get_card(core_id)
		core_title = String(info.get("title", core_id))
		accent = info.get("accent_color", COL_VIOLET_LIGHT)

	var head := "【%s】 Lv.%d" % [core_title, core_level]
	_hud_canvas.draw_string(_font_serif, rect.position + Vector2(12.0, 25.0), head, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, accent)

	# 右侧 10/40/100 境界灯
	var tiers := [10, 40, 100]
	for idx in tiers.size():
		var m: int = tiers[idx]
		var lit := has_core_tier(m)
		var mx := rect.end.x - 98.0 + float(idx) * 32.0
		var mcol := COL_GOLD if lit else Color(0.45, 0.44, 0.54, 0.65)
		_hud_canvas.draw_string(_font_serif, Vector2(mx, rect.position.y + 24.0), str(m), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, mcol)

	var stats_line := "攻 %d   速 %d   暴 %d   防 %d" % [
		int(stat_levels.get("stat_atk", 1)),
		int(stat_levels.get("stat_spd", 1)),
		int(stat_levels.get("stat_crit", 1)),
		int(stat_levels.get("stat_def", 1)),
	]
	_hud_canvas.draw_string(_font_serif, rect.position + Vector2(12.0, 50.0), stats_line, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COL_SILVER)

	if aegis_max > 0.0:
		var bar_bg := Rect2(rect.position.x + 12.0, rect.position.y + 60.0, box_w - 24.0, 6.0)
		_hud_canvas.draw_rect(bar_bg, Color(0.18, 0.16, 0.24, 0.9))
		var fill_w := bar_bg.size.x * clampf(aegis_hp / maxf(aegis_max, 1.0), 0.0, 1.0)
		_hud_canvas.draw_rect(Rect2(bar_bg.position, Vector2(fill_w, bar_bg.size.y)), COL_GOLD)

	if _banner_timer > 0.0 and _banner_text != "":
		var a := clampf(_banner_timer, 0.0, 1.0)
		var cx := vp.x * 0.5
		_hud_canvas.draw_string(_font_serif, Vector2(cx - 160.0, 96.0), _banner_text, HORIZONTAL_ALIGNMENT_CENTER, 320.0, 22, Color(COL_GOLD, a))
