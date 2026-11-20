extends "res://scripts/night/rain_street.gd"
## 雨街肉鸽试玩段（万象棋双引擎版：升级送天赋 · 合成送锦囊 · 首领直通）：
## - 100% 保留既有雨街三处封印、跨层跳跃与 test_rain_trial.gd 无头回归契约；
## - 开局只选 1 张本命核心（直升 Lv.10）；
## - 破封展开「万象牌桌」：U 升级送天赋，同名三合一送 0⚡ 锦囊；
## - 第三处封印完成后点击「迎战镇守首领 · 断潮」，通过 RunBridge 将构筑带入 boss_sample.tscn。

const ResultPanel := preload("res://scripts/ui/rain_trial_result.gd")
const PauseMenu := preload("res://scripts/ui/pause_menu.gd")
const PerkRig := preload("res://scripts/roguelike/perk_rig.gd")
const RunDirector := preload("res://scripts/roguelike/run_director.gd")
const ForkChoiceOverlay := preload("res://scripts/roguelike/fork_choice_overlay.gd")
const RunBridge := preload("res://scripts/roguelike/run_bridge.gd")

const TRIAL_SCENE := "res://scenes/rain_trial.tscn"
const BOSS_SCENE := "res://scenes/boss_sample.tscn"
const CH1_LAYOUT_PATH := "res://assets/data/ch1_shadow_street_layout.json"

signal boss_fight_requested(scene_path: String)

var boss_scene_path: String = BOSS_SCENE
var trial_completed := false
var trial_summary: Dictionary = {}
var pause_menu: CanvasLayer
var perk_rig: Node2D
var run_director: Node
var fork_overlay: CanvasLayer

## 自定义 SceneTree 旧测试脚本默认静默直通，100% 保持原坐标契约
var roguelike_auto_pick := false
var _auto_pick_overridden := false
var ch1_shadow_street_enabled := false
var _ch1_overridden := false
var _ch1_route_variants: Dictionary = {}

var _trial_time := 0.0
var _restart_pending := false
var _choice_active := false
var _pending_final_seal := false
var _pending_seal_no := 1


func set_roguelike_interactive(interactive: bool) -> void:
	_auto_pick_overridden = true
	roguelike_auto_pick = not interactive


func enable_ch1_shadow_street(enabled: bool) -> void:
	_ch1_overridden = true
	ch1_shadow_street_enabled = enabled


func _enter_tree() -> void:
	var is_custom_test_tree := (get_tree() != null and get_tree().get_script() != null)
	if not _ch1_overridden:
		ch1_shadow_street_enabled = not is_custom_test_tree
	if ch1_shadow_street_enabled and FileAccess.file_exists(CH1_LAYOUT_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CH1_LAYOUT_PATH))
		if parsed is Dictionary:
			layout = (parsed as Dictionary).duplicate(true)
			_ch1_route_variants = (layout.get("routeVariants", {}) as Dictionary).duplicate(true)
			for sec_item in layout.get("sections", []):
				if sec_item is Dictionary and sec_item.has("ch1_code"):
					_ch1_route_variants[String(sec_item.get("ch1_code"))] = (sec_item as Dictionary).duplicate(true)
			arena_half = float(layout.get("arenaHalf", 2400))
			arena_spacing = float(layout.get("arenaSpacing", 6400))
			first_arena_x = START_X + 1700.0 + arena_half
			trigger_before = arena_half - 200.0


func _stage_ready() -> void:
	super()
	if not _auto_pick_overridden:
		roguelike_auto_pick = (get_tree() != null and get_tree().get_script() != null)

	perk_rig = PerkRig.new()
	perk_rig.name = "PerkRig"
	add_child(perk_rig)
	perk_rig.setup(self, player)

	run_director = RunDirector.new()
	run_director.name = "RunDirector"
	add_child(run_director)
	run_director.setup(self, perk_rig)

	fork_overlay = ForkChoiceOverlay.new()
	fork_overlay.name = "ForkChoiceOverlay"
	fork_overlay.opening_confirmed.connect(_on_opening_confirmed)
	fork_overlay.table_finished.connect(_on_wanxiang_table_finished)
	add_child(fork_overlay)

	if ch1_shadow_street_enabled:
		hud.banner("第一章 · 影街与司辰母钟楼", "钟停 5:59", 2.4)
	else:
		hud.banner("雨街 · 战斗试玩", "三处封印", 2.4)

	pause_menu = PauseMenu.new()
	pause_menu.name = "PauseMenu"
	pause_menu.stage = self
	add_child(pause_menu)
	hud.help_text += "   Esc 暂停"

	if not roguelike_auto_pick:
		_open_initial_setup.call_deferred()


func _open_initial_setup() -> void:
	if trial_completed or roguelike_auto_pick or run_director == null or fork_overlay == null:
		return
	if run_director.opening_completed:
		return
	_set_choice_pause(true)
	fork_overlay.open_opening_draft(run_director)


func _on_opening_confirmed(picked_core_id: String) -> void:
	if run_director != null:
		run_director.apply_opening_selection(picked_core_id)
	_hp_seen = player.hp
	_set_choice_pause(false)
	if run_director != null and run_director.catalog != null:
		var c_title := String(run_director.catalog.get_card(picked_core_id).get("title", picked_core_id))
		hud.banner("【%s】Lv.10" % c_title, "向右破封", 1.8)


func _physics_process(delta: float) -> void:
	if trial_completed or _choice_active:
		return
	_trial_time += delta
	if phase == Phase.FIGHT and run_director != null:
		run_director.tick_combat(delta)
	super(delta)


func _lock_arena() -> void:
	if run_director != null:
		run_director.begin_segment()
	super()


func _on_player_hurt(dmg: float, point: Vector2, shake: float = 3.0, dir: Vector2 = Vector2.ZERO, heavy: bool = false) -> void:
	var final_dmg := dmg
	if perk_rig != null:
		final_dmg = perk_rig.intercept_player_hurt(dmg, point, dir)
	if final_dmg <= 0.01:
		_hp_seen = player.hp
		if fx != null:
			fx.spawn_block(point, dir if dir.length_squared() > 0.01 else Vector2(float(player.facing), 0.0))
		return
	if phase == Phase.FIGHT and run_director != null:
		run_director.record_player_hit()
	super(final_dmg, point, shake, dir, heavy)


func _on_encounter_cleared() -> void:
	if trial_completed or _choice_active:
		return

	if roguelike_auto_pick:
		if run_director != null:
			run_director.auto_resolve_silent()
		if encounter_index + 1 < round_waves.size():
			super()
			return
		_finalize_trial_result()
		return

	if run_director != null and not run_director.opening_completed:
		run_director.apply_opening_selection("core_rift")

	encounter.running = false
	encounter.finished = true
	audio.play_clear()

	_pending_final_seal = (encounter_index + 1 >= round_waves.size())
	_pending_seal_no = encounter_index + 1
	var rank_idx := style.rank_index() if style != null else 0
	run_director.open_seal_table(_pending_seal_no, rank_idx)
	_set_choice_pause(true)
	fork_overlay.open_wanxiang_table(run_director, _pending_seal_no, _pending_final_seal)


func _on_wanxiang_table_finished() -> void:
	fork_overlay.close_overlay()
	_set_choice_pause(false)
	_hp_seen = player.hp

	if not _pending_final_seal:
		_apply_ch1_next_stage_variant()
		player.hp = minf(player.max_hp, player.hp + WAVE_HEAL)
		_hp_seen = player.hp
		_unlock_arena()
		encounter_index += 1
		var c_title := "万象核心"
		if run_director != null and run_director.catalog != null and run_director.core_id != "":
			c_title = String(run_director.catalog.get_card(run_director.core_id).get("title", run_director.core_id))
		var c_lv: int = int(perk_rig.core_level) if perk_rig != null else 10
		hud.banner("【%s】 Lv.%d" % [c_title, c_lv], "继续前行", 1.8)
		return

	_finalize_trial_result()


func _apply_ch1_next_stage_variant() -> void:
	if not ch1_shadow_street_enabled:
		return
	var next_slot := encounter_index + 1
	var prefer_high: bool = perk_rig != null and String(perk_rig.core_id) in ["core_bell", "core_chrono"]
	if next_slot == 1:
		_swap_ch1_slot_stage(1, "1-2A" if prefer_high else "1-2B")
	elif next_slot == 2:
		_swap_ch1_slot_stage(2, "1-3A" if prefer_high else "1-3B")


func _swap_ch1_slot_stage(slot_idx: int, code: String) -> void:
	var target_sec: Dictionary = {}
	if _ch1_route_variants.has(code):
		target_sec = (_ch1_route_variants[code] as Dictionary).duplicate(true)
	else:
		for s in layout.get("sections", []):
			if s is Dictionary and String(s.get("ch1_code", "")) == code:
				target_sec = (s as Dictionary).duplicate(true)
				break
	if target_sec.is_empty():
		return
	if terrain != null and terrain.has_method("replace_section"):
		terrain.call("replace_section", slot_idx, _center_of(slot_idx), target_sec)
	if backdrop != null and backdrop.has_method("set_ch1_route_code"):
		backdrop.call("set_ch1_route_code", slot_idx, code, target_sec)


func _finalize_trial_result() -> void:
	encounter.running = false
	encounter.finished = true
	audio.play_clear()
	_unlock_arena()
	encounter_index += 1
	trial_completed = true
	trial_summary = style.stats.duplicate(true)
	trial_summary["seconds"] = _trial_time
	trial_summary["combat_seconds"] = _round_time
	trial_summary["max_combo"] = maxi(_round_max_combo, style.max_combo)
	trial_summary["grade"] = Style.RANKS[clampi(_round_rank - (1 if int(style.stats.times_hit) >= 6 else 0), 0, 4)]
	if run_director != null:
		var rs: Dictionary = run_director.build_run_summary()
		trial_summary["core_id"] = rs["core_id"]
		trial_summary["core_title"] = rs["core_title"]
		trial_summary["core_level"] = rs["core_level"]
		trial_summary["player_tier"] = rs["player_tier"]
		trial_summary["stat_levels"] = rs["stat_levels"]
		trial_summary["gold_cores"] = rs["gold_cores"]
		trial_summary["synth_total"] = rs["synth_total"]
		trial_summary["shadow_cap"] = rs["shadow_cap"]
		trial_summary["chosen_perks"] = rs["chosen_perks"]
	_hint_queue.clear()
	hud.hint("", 0.0)
	hud.hide_result()
	hud.wave_text = "战斗试玩 · 三处封印已解除"
	hud.queue_redraw()
	var result := ResultPanel.new()
	result.name = "TrialResult"
	result.summary = trial_summary
	result.result_font = hud._font
	result.restart_requested.connect(_restart_trial)
	add_child(result)
	_inject_boss_button(result)
	get_tree().paused = true
	print("RAIN_TRIAL_COMPLETE ", JSON.stringify(trial_summary))


func _inject_boss_button(result: CanvasLayer) -> void:
	var rows := result.get_node_or_null("Screen/Center/Panel/Rows") as VBoxContainer
	if rows == null:
		return
	var retry := rows.get_node_or_null("Retry") as Button
	var leave := rows.get_node_or_null("Leave") as Button
	if retry == null or leave == null:
		return

	if run_director != null and perk_rig != null:
		var c_title := String(trial_summary.get("core_title", "万象构筑"))
		var rogue_lbl := Label.new()
		rogue_lbl.name = "RoguelikeSummary"
		rogue_lbl.text = "【%s】Lv.%d  ·  攻%d 速%d 暴%d 防%d" % [
			c_title,
			perk_rig.core_level,
			int(perk_rig.stat_levels.get("stat_atk", 1)),
			int(perk_rig.stat_levels.get("stat_spd", 1)),
			int(perk_rig.stat_levels.get("stat_crit", 1)),
			int(perk_rig.stat_levels.get("stat_def", 1)),
		]
		rogue_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rogue_lbl.add_theme_font_size_override("font_size", 18)
		rogue_lbl.add_theme_color_override("font_color", Color("e4ccff"))
		rows.add_child(rogue_lbl)
		rows.move_child(rogue_lbl, retry.get_index())

	var fight_boss := Button.new()
	fight_boss.name = "FightBoss"
	fight_boss.text = "迎战首领 · 断潮"
	fight_boss.custom_minimum_size.y = 50
	var boss_normal := StyleBoxFlat.new()
	boss_normal.bg_color = Color("1b142c")
	boss_normal.border_color = Color("d5a8ff")
	boss_normal.set_border_width_all(2)
	var boss_focus := StyleBoxFlat.new()
	boss_focus.bg_color = Color("281d42")
	boss_focus.border_color = Color("f5dfa3")
	boss_focus.set_border_width_all(3)
	fight_boss.add_theme_stylebox_override("normal", boss_normal)
	fight_boss.add_theme_stylebox_override("hover", boss_focus)
	fight_boss.add_theme_stylebox_override("focus", boss_focus)
	fight_boss.add_theme_stylebox_override("pressed", boss_focus)
	fight_boss.add_theme_color_override("font_color", Color("f5dfa3"))
	fight_boss.add_theme_color_override("font_focus_color", Color("fff8e6"))
	fight_boss.add_theme_color_override("font_hover_color", Color("fff8e6"))
	fight_boss.pressed.connect(_enter_boss_fight)
	rows.add_child(fight_boss)
	rows.move_child(fight_boss, leave.get_index())

	retry.focus_neighbor_top = leave.get_path()
	retry.focus_neighbor_bottom = fight_boss.get_path()
	fight_boss.focus_neighbor_top = retry.get_path()
	fight_boss.focus_neighbor_bottom = leave.get_path()
	leave.focus_neighbor_top = fight_boss.get_path()
	leave.focus_neighbor_bottom = retry.get_path()
	_safe_grab_focus.call_deferred(retry)


func _safe_grab_focus(ctrl: Control) -> void:
	if ctrl != null and is_instance_valid(ctrl) and ctrl.is_inside_tree():
		ctrl.grab_focus()


func _set_choice_pause(active: bool) -> void:
	_choice_active = active
	if pause_menu != null:
		pause_menu.process_mode = Node.PROCESS_MODE_DISABLED if active else Node.PROCESS_MODE_ALWAYS
	if get_tree() != null:
		get_tree().paused = active


func _enter_boss_fight() -> void:
	if _restart_pending:
		return
	_restart_pending = true
	if perk_rig != null and perk_rig.is_active_build():
		RunBridge.handoff_to_boss(get_tree(), perk_rig.export_snapshot())
	boss_fight_requested.emit(boss_scene_path)
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file.call_deferred(boss_scene_path)


func _restart_trial() -> void:
	if _restart_pending:
		return
	_restart_pending = true
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file.call_deferred(TRIAL_SCENE)


func _exit_tree() -> void:
	if (trial_completed or _choice_active) and get_tree() != null:
		get_tree().paused = false
