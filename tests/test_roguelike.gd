extends SceneTree
## 断晓肉鸽（极简《万象棋》双引擎：升级给天赋 · 合成给锦囊 · 首领直通）完整无头验收套件：
## 1. Pandora 唯一数据源 23 张卡牌加载、极简少字上限（summary <= 14 字）与零「白瓷/石化」校验；
## 2. 四大本命核心（万仞裂空 / 千羽绝影 / 刹那断晷 / 司辰金钟）Lv.10/40/100 真实判定与零改 Engine.time_scale 校验；
## 3. 四维纯净属性（攻 / 速 / 暴 / 防）安全帧缩放、驻时凝光盾吸收与逆时锁血校验；
## 4. 万象牌桌双引擎（开局单选核心、升级给天赋、同名三合一给锦囊、商店效果牌）与跨场景直切断潮（BossSample）继承校验。

const PerkCatalog := preload("res://scripts/roguelike/perk_catalog.gd")
const Shade := preload("res://scripts/night/shade.gd")
const Bolt := preload("res://scripts/night/shade_bolt.gd")

const TRIAL_SCENE := "res://scenes/rain_trial.tscn"
const BOSS_SCENE := "res://scenes/boss_sample.tscn"

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		print("FAIL: ", label)


func _wait_physics(n: int = 1) -> void:
	for _i in n:
		await physics_frame


func _wait_process(n: int = 1) -> void:
	for _i in n:
		await process_frame


func _spawn_shade(stage: Node, kind: int, pos_x: float, hp_val: float = 300.0, surface_y: float = NAN) -> Node2D:
	var s := Node2D.new()
	s.set_script(Shade)
	s.setup(kind, stage.player, stage.floor_y, 1.0)
	var fy: float = stage.floor_y if is_nan(surface_y) else surface_y
	s.position = Vector2(pos_x, fy - float(Shade.KINDS[kind].half_h))
	s.terrain = stage.terrain
	s.arena_left = stage.arena_center - stage.arena_half
	s.arena_right = stage.arena_center + stage.arena_half
	s.spawn_frames = 0
	s.active = false
	s.hp = hp_val
	s.max_hp = hp_val
	stage.add_child(s)
	stage._on_shade_spawned(s)
	if stage.get("perk_rig") != null:
		stage.perk_rig._on_shade_spawned(s)
	return s


func _clear_test_shades(stage: Node) -> void:
	for n in get_nodes_in_group(&"shade"):
		if is_instance_valid(n):
			n.queue_free()
	for b in get_nodes_in_group(&"shade_projectile"):
		if is_instance_valid(b):
			b.queue_free()
	for r in get_nodes_in_group(&"spatial_rift"):
		if is_instance_valid(r):
			r.queue_free()
	if stage != null and stage.get("fx") != null:
		stage.fx.clear()
	Engine.time_scale = 1.0
	await _wait_process(2)


func _run() -> void:
	_test_pandora_catalog()
	await _test_four_cores_and_four_stats()
	await _test_wanxiang_table_and_boss_handoff()

	if failures.is_empty():
		print("ROGUELIKE_OK: %d checks, 0 failures" % checks)
		quit(0)
	else:
		print("ROGUELIKE_FAIL: %d checks, %d failures" % [checks, failures.size()])
		quit(1)


# ---------------------------------------------------------------- 1. Pandora 目录、极简字数与世界观红线验收

func _test_pandora_catalog() -> void:
	var cat := PerkCatalog.new(self)
	var all_cards := cat.get_all_cards()
	var cores := cat.get_core_cards()
	var stats := cat.get_stat_cards()
	var effects := cat.get_effect_cards()
	var talents := cat.get_talent_cards()
	var tactics := cat.get_tactic_cards()

	check(all_cards.size() == 23, "Pandora 加载全部 23 张万象卡牌（实际 %d）" % all_cards.size())
	check(cores.size() == 4 and stats.size() == 4 and effects.size() == 3 and talents.size() == 6 and tactics.size() == 6,
		"4 张本命核心 + 4 张基础属性 + 3 张商店效果牌 + 6 张升级天赋 + 6 张合成锦囊分类齐全")

	var forbidden_found := false
	var max_summary_len := 0
	for item in all_cards:
		var sum_txt := String(item.get("summary", ""))
		max_summary_len = maxi(max_summary_len, sum_txt.length())
		var blob := "%s|%s|%s|%s|%s|%s" % [
			String(item.get("title", "")),
			String(item.get("subtitle", "")),
			sum_txt,
			String(item.get("tier_10", "")),
			String(item.get("tier_40", "")),
			String(item.get("tier_100", "")),
		]
		if blob.contains("白瓷") or blob.contains("石化"):
			forbidden_found = true
	check(max_summary_len <= 14, "全牌库严格执行极简少字铁律（最长词条仅 %d 字 <= 14）" % max_summary_len)
	check(not forbidden_found, "全牌库严守《剧情与主题规划》红线，零「白瓷/石化」废止词条")


# ---------------------------------------------------------------- 2. 四大本命核心牌 + 四维基础属性验收

func _test_four_cores_and_four_stats() -> void:
	var stage: Node = load(TRIAL_SCENE).instantiate()
	root.add_child(stage)
	current_scene = stage
	await _wait_process(2)

	var rig: Node2D = stage.perk_rig
	var p: CharacterBody2D = stage.player
	check(rig != null and stage.run_director != null and stage.fork_overlay != null,
		"RainTrial 成功外挂 PerkRig / RunDirector / ForkChoiceOverlay")

	var cx: float = stage._center_of(0)
	stage.arena_center = cx
	p.reset_state(Vector2(cx - 120.0, stage.floor_y - p.foot_offset))
	p._set_facing(1)
	await _wait_physics(2)

	# ---- A. 四维基础属性安全缩放验证 ----
	var base_spd := float(p.speed)
	var base_hp := float(p.max_hp)
	var orig_actives: Array[int] = []
	for mv in p.light_combo:
		if mv is MoveDefinition:
			orig_actives.append(int((mv as MoveDefinition).active_frames))
	rig.add_stat_levels("stat_atk", 10)
	rig.add_stat_levels("stat_spd", 36)
	rig.add_stat_levels("stat_crit", 55)
	rig.add_stat_levels("stat_def", 20)
	var all_active_safe := true
	var a_idx := 0
	for mv in p.light_combo:
		if mv is MoveDefinition:
			if int((mv as MoveDefinition).active_frames) < orig_actives[a_idx]:
				all_active_safe = false
			a_idx += 1
	check(float(p.attack_damage_mul) >= 1.35
		and float(p.speed) > base_spd
		and float(p.max_hp) > base_hp + 60.0
		and rig.shadow_cap >= 4
		and all_active_safe,
		"四维属性提升攻击倍率(>=1.35)、移速、残影格(%d)、生命上限(%.0f)且判定帧绝不缩水吞帧" % [rig.shadow_cap, p.max_hp])

	# ---- B. 核心牌①《万仞裂空》 ----
	rig.set_core_hero("core_rift", 10)
	var s_rift := _spawn_shade(stage, Shade.Kind.BRUTE, cx + 180.0, 500.0)
	p.keen_edge_timer = 1.0
	p._keen_swing_active = true
	p.move_started.emit(p.charge_move, 0)
	p._keen_swing_active = false
	await _wait_physics(12)
	var rifts_spawned := get_nodes_in_group(&"spatial_rift").size()
	check(rig.rift_arc_count >= 1 and rifts_spawned >= 1 and float(s_rift.hp) < 500.0,
		"【万仞裂空 Lv.10】重斩挥出穿透冷紫弧光并撕开真实 SpatialRift")

	rig.set_core_hero("core_rift", 40)
	p.plunge_landed.emit(Vector2(cx + 150.0, stage.floor_y))
	await _wait_physics(2)
	check(rig.rift_detonation_count >= 1, "【万仞裂空 Lv.40】下砸引爆全场空间裂口炸出十字斩")

	rig.set_core_hero("core_rift", 100)
	rig._sky_storm_cd = 0.0
	var hp_before_storm := float(s_rift.hp)
	p.plunge_landed.emit(Vector2(cx + 120.0, stage.floor_y))
	await _wait_physics(24)
	check(rig.sky_storm_count >= 1 and float(s_rift.hp) < hp_before_storm,
		"【万仞裂空 Lv.100】万仞裁夜降下天幕巨刃风暴洗屏重创敌影")
	await _clear_test_shades(stage)

	# ---- C. 核心牌②《千羽绝影》 ----
	rig.set_core_hero("core_crow", 40)
	var s_crow := _spawn_shade(stage, Shade.Kind.GRUNT, cx + 110.0, 2500.0)
	p.keen_edge_timer = 0.0
	p.short_dash_started.emit(1, p.global_position)
	check(p.keen_edge_timer > 0.5, "【千羽绝影 Lv.10】瞬步自动点亮紫电锋芒")
	p.move_started.emit(p.light_combo[0], 0)
	await _wait_physics(18)
	check(rig.clone_slash_count >= 2 and rig.feather_shot_count >= 1 and float(s_crow.hp) < 2500.0,
		"【千羽绝影 Lv.40】拉出双重残影替身合击并射出追踪幻影飞刃")

	rig.set_core_hero("core_crow", 100)
	var bolt_mv := MoveDefinition.new()
	bolt_mv.damage = 10.0
	var enemy_bolt_crow := Node2D.new()
	enemy_bolt_crow.set_script(Bolt)
	enemy_bolt_crow.setup(null, Vector2(cx + 180.0, stage.floor_y - 60.0), Vector2.LEFT, bolt_mv, 1.0)
	stage.add_child(enemy_bolt_crow)
	await _wait_process(1)
	p.short_dash_started.emit(1, p.global_position)
	await _wait_process(2)
	check(bool(p.unlimited_dash) and rig.slash_web_count >= 1 and get_nodes_in_group(&"shade_projectile").is_empty(),
		"【千羽绝影 Lv.100】开启无间鸦闪无限冲刺，并张开全屏斩网抹除敌方投射物")
	await _clear_test_shades(stage)

	# ---- D. 核心牌③《刹那断晷》 ----
	rig.set_core_hero("core_chrono", 40)
	var s_ch1 := _spawn_shade(stage, Shade.Kind.BRUTE, cx + 90.0, 500.0)
	var s_ch2 := _spawn_shade(stage, Shade.Kind.GRUNT, cx + 240.0, 500.0)
	p.hit_confirmed.emit(s_ch1, p.light_combo[3], s_ch1.global_position)
	await _wait_physics(2)
	check(rig.thunder_strike_count >= 1 and rig.crit_trigger_count >= 1 and float(s_ch2.hp) < 500.0,
		"【刹那断晷 Lv.10/40】锋芒与暴击劈落紫白惊雷并连锁弹射周围敌影")

	rig.apply_luminous_shell(s_ch1, 60.0)
	p.keen_edge_timer = 0.0
	s_ch1.call("_break_shell")
	check(p.keen_edge_timer > 0.5, "【刹那断晷 Lv.40】击碎敌方凝光壳瞬间自动刷新紫电锋芒")

	rig.set_core_hero("core_chrono", 100)
	rig._time_stop_cd = 0.0
	var s_ts := _spawn_shade(stage, Shade.Kind.GRUNT, cx + 160.0, 900.0)
	var bolt_ts := Node2D.new()
	bolt_ts.set_script(Bolt)
	bolt_ts.setup(null, Vector2(cx + 300.0, stage.floor_y - 60.0), Vector2.LEFT, bolt_mv, 1.0)
	stage.add_child(bolt_ts)
	await _wait_process(1)
	var ts_before := Engine.time_scale
	p.perfect_dodge_triggered.emit(s_ts, p.global_position)
	await _wait_physics(2)
	check(rig.time_stop_count >= 1
		and rig.time_stop_timer > 1.5
		and is_equal_approx(Engine.time_scale, ts_before)
		and int(s_ts.hitstop_frames) > 0
		and not bolt_ts.is_physics_processing(),
		"【刹那断晷 Lv.100】极限看破瞬发刹那 5:59 冻结敌影与箭弹，且零触碰 Engine.time_scale")
	rig.time_stop_timer = 0.02
	var hp_before_ts_burst := float(s_ts.hp)
	for _w in 24:
		if rig.time_stop_timer == 0.0:
			break
		await _wait_physics(1)
	check(rig.time_stop_timer == 0.0 and float(s_ts.hp) < hp_before_ts_burst,
		"【刹那断晷 Lv.100】2秒时停结束自动降下紫电审判引爆全场")
	await _clear_test_shades(stage)

	# ---- E. 核心牌④《司辰金钟》 ----
	rig.set_core_hero("core_bell", 100)
	var _s_bell := _spawn_shade(stage, Shade.Kind.BRUTE, cx + 110.0, 600.0)
	var hp_full := float(p.hp)
	p.hp = hp_full - 18.0
	var rem_dmg: float = rig.intercept_player_hurt(18.0, p.global_position)
	check(rem_dmg <= 0.01 and is_equal_approx(float(p.hp), hp_full) and rig.bell_wave_count >= 1,
		"【司辰金钟 Lv.10】驻时凝光盾全额吸收伤害保住连击，并反震银白冲击波")

	var waves_before: int = int(rig.bell_wave_count)
	for _sw in 4:
		p.move_started.emit(p.light_combo[0], 0)
	check(rig.bell_wave_count > waves_before, "【司辰金钟 Lv.40】无需挨打，每挥 4 刀自动扩开司辰钟鸣波")

	rig.aegis_hp = 0.0
	p.hp = 1.0
	rig.intercept_player_hurt(80.0, p.global_position)
	check(rig.cheat_death_triggered_count == 1 and float(p.hp) >= float(p.max_hp) * 0.35 and rig.grand_bell_count >= 1,
		"【司辰金钟 Lv.100】致命伤害触发【逆时金身】锁血回盾并横扫全屏母钟巨浪")

	await _clear_test_shades(stage)
	stage.queue_free()
	current_scene = null
	await _wait_process(3)


# ---------------------------------------------------------------- 3. 万象牌桌（升级给天赋 · 合成给锦囊 · 效果牌）+ 直切断潮验收

func _test_wanxiang_table_and_boss_handoff() -> void:
	var stage: Node = load(TRIAL_SCENE).instantiate()
	stage.set_roguelike_interactive(true)
	root.add_child(stage)
	current_scene = stage
	await _wait_process(3)

	var overlay: CanvasLayer = stage.fork_overlay
	var director: Node = stage.run_director
	var rig: Node2D = stage.perk_rig
	var p: CharacterBody2D = stage.player

	check(paused and overlay.is_open and overlay.uses_only_open_source_fonts(),
		"交互模式入场自动展开极简「选择本命核心」面板，且严格仅用内置开源字体 NotoSerifSC")

	# 开局只选 1 张本命核心《万仞裂空》（Lv.10，自带 ●○○ 1 格合成进度，无初始天赋）
	overlay.confirm_opening_with("core_rift")
	check(not paused
		and rig.core_id == "core_rift"
		and rig.core_level == 10
		and int(director.synth_pips.get("core", 0)) == 1
		and director.active_talents.is_empty(),
		"开局仅选 1 张核心牌（Lv.10，●○○ 1/3 合成格，开局不塞天赋）")

	# ==== 第 1 处封印破封：进入 4 槽万象牌桌 ====
	p.reset_state(Vector2(stage._center_of(0) - stage.trigger_before + 20.0, stage.floor_y - p.foot_offset))
	await _wait_physics(3)
	stage.encounter.clear_shades()
	stage.encounter.running = false
	director.segment_time = 12.0
	director.segment_hits = 0
	stage._on_encounter_cleared()

	check(paused and overlay.is_open and director.shop_slots.size() == 4 and director.energy >= 12,
		"第 1 处封印破封展开 4 槽万象牌桌（能量 %d⚡）" % int(director.energy))

	# ---- 引擎 1：点击【升级】-> 牌手升至 Lv.2，立刻弹出 3 选 1【天赋】！ ----
	var up_ok: bool = director.upgrade_tier()
	check(up_ok
		and int(director.player_tier) == 2
		and director.tier_base_gain() == 9
		and String(director.pending_draft_kind) == "talent"
		and director.pending_draft_choices.size() == 3,
		"【升级给天赋】点击升级升至 Lv.2（单卡基础升幅涨至 +9），立即触发 3 选 1 天赋")

	# 强制指定首项为《免单刷新》以精确验证天赋被动
	var free_roll_card: Dictionary = director.catalog.get_card("talent_free_roll")
	director.pending_draft_choices[0] = free_roll_card
	director.pick_draft_choice(0)
	director.energy = 20
	director.refresh_shop()
	check(director.has_talent("talent_free_roll") and int(director.shop_slots[0].get("cost", 99)) == 0,
		"拣选天赋《免单刷新》后每次刷新首槽自动 0⚡ 免单")

	# ---- 引擎 2：买同名核心牌凑满 ●●● 三合一 -> 触发合成暴涨并立刻弹出 3 选 1【锦囊】！ ----
	var core_card: Dictionary = director.catalog.get_card("core_rift")
	director.shop_slots[0] = director._make_shop_slot(core_card, 2, false, false)
	director.shop_slots[1] = director._make_shop_slot(core_card, 2, false, false)
	var lv_before_synth: int = int(rig.core_level)
	director.buy_slot(0) # core pips: 1 -> 2 (●●○)，此时槽位 1 应预测买即合成
	var predicts_synth: bool = director.will_slot_synthesize(director.shop_slots[1])
	var buy_res: Dictionary = director.buy_slot(1) # core pips: 2 -> 3 -> 0 (●●● 合成！)
	check(predicts_synth
		and bool(buy_res.get("synthesized", false))
		and int(director.synth_total) == 1
		and int(director.synth_pips.get("core", -1)) == 0
		and int(rig.core_level) >= lv_before_synth + 26
		and String(director.pending_draft_kind) == "tactic"
		and director.pending_draft_choices.size() == 3,
		"【合成给锦囊】买同名牌凑齐 ●●● 触发三合一暴涨（Lv.%d -> Lv.%d），立即弹出 3 选 1 锦囊" % [lv_before_synth, int(rig.core_level)])

	# 拣选锦囊《万象征召》-> 0⚡ 当场瞬发把整页 4 张全变核心牌且减 1⚡！
	director.pending_draft_choices[0] = director.catalog.get_card("tactic_summon_core")
	director.pick_draft_choice(0)
	var all_core_1cost := true
	for sl in director.shop_slots:
		if String(sl.get("card_id", "")) != "core_rift" or int(sl.get("cost", 9)) != 1:
			all_core_1cost = false
	check(not director.is_draft_active() and all_core_1cost,
		"拣选锦囊《万象征召》0⚡ 当场瞬发：整页 4 张全化为 1⚡ 本命核心牌")

	# 连续连击：双倍镜 + 点石成金 + 破界符 -> 直冲百级神技！
	director._execute_tactic_by_id("tactic_gild_shop")
	director._execute_tactic_by_id("tactic_duplicator")
	director.energy = 30
	director.buy_slot(0) # 双倍金卡 × 双倍镜 = +4 格合成 + 巨幅等级
	while director.is_draft_active():
		director.pending_draft_choices[0] = director.catalog.get_card("tactic_break_limit")
		director.pick_draft_choice(0)
	check(rig.tier_req(100) <= 75 and rig.has_core_tier(100),
		"点石成金+双倍镜+破界符丝滑连转，提前突破百级神技（当前核心 Lv.%d，百级门槛 Lv.%d）" % [int(rig.core_level), rig.tier_req(100)])

	# ---- 商店效果牌验证（淬锋露 / 四象散 / 回能饮） ----
	var atk_before := int(rig.stat_levels.get("stat_atk", 1))
	var eff_all: Dictionary = director.catalog.get_card("effect_all_stats")
	director.shop_slots[2] = director._make_shop_slot(eff_all, 2, false, false)
	director.buy_slot(2)
	check(int(rig.stat_levels.get("stat_atk", 1)) >= atk_before + 6,
		"商店直接刷出并购买效果牌《四象散》，四维属性全线提升")

	overlay.finish_table_now()
	check(not paused and stage.encounter_index == 1, "点击出战解锁第 1 处封印并推进至第 2 处")

	# ==== 第 2、3 处封印：验证每波自动减免 2⚡ 升级费，并打通至结算页 ====
	var cost_before_seal2: int = int(director.TIER_UPGRADE_COSTS[director.player_tier])
	for s_idx in [1, 2]:
		p.reset_state(Vector2(stage._center_of(s_idx) - stage.trigger_before + 20.0, stage.floor_y - p.foot_offset))
		await _wait_physics(3)
		stage.encounter.clear_shades()
		stage.encounter.running = false
		director.segment_time = 28.0
		director.segment_hits = 1
		stage._on_encounter_cleared()
		if s_idx == 1:
			check(director.upgrade_cost() == cost_before_seal2 - 2,
				"破封过波自动使当前升级费减免 2⚡（%d⚡ -> %d⚡）" % [cost_before_seal2, director.upgrade_cost()])
		while director.is_draft_active():
			director.pick_draft_choice(0)
		overlay.finish_table_now()

	check(stage.trial_completed and paused and stage.encounter_index == 3,
		"第 3 处封印万象牌桌收桌后进入结算页")

	await _wait_process(3)
	var fight_boss := stage.get_node_or_null("TrialResult/Screen/Center/Panel/Rows/FightBoss") as Button
	var retry_btn := stage.get_node_or_null("TrialResult/Screen/Center/Panel/Rows/Retry") as Button
	var expected_core_lv: int = int(rig.core_level)
	check(fight_boss != null and retry_btn != null and retry_btn.has_focus(),
		"结算页包含「迎战首领 · 断潮」按钮且保留 Retry 默认焦点契约")

	# ==== 真实跨场景直切 boss_sample.tscn 并验证构筑 100% 继承 ====
	fight_boss.pressed.emit()
	for _f in 12:
		await _wait_process(1)

	var boss_stage := current_scene
	check(not paused and boss_stage != null and boss_stage.scene_file_path == BOSS_SCENE,
		"点击「迎战首领 · 断潮」成功直切 boss_sample.tscn")

	var boss_rig := boss_stage.get_node_or_null("PerkRig") as Node2D if boss_stage != null else null
	check(boss_rig != null
		and String(boss_rig.get("core_id")) == "core_rift"
		and int(boss_rig.get("core_level")) == expected_core_lv
		and float(boss_stage.player.attack_damage_mul) >= 1.20,
		"RunBridge 成功将本命核心(Lv.%d)与四维属性完整注入首领战「断潮」" % (int(boss_rig.get("core_level")) if boss_rig != null else -1))

	var bridge := root.get_node_or_null("RoguelikeRunBridge")
	if bridge != null:
		bridge.queue_free()
	if current_scene != null:
		current_scene.queue_free()
		current_scene = null
	await _wait_process(4)
