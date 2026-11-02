extends "res://scripts/night/rain_street.gd"
## 有限战斗样段：复用雨街全部战斗/素材，一轮三处封印后结算。
const ResultPanel := preload("res://scripts/ui/rain_trial_result.gd")
const PauseMenu := preload("res://scripts/ui/pause_menu.gd")
const TRIAL_SCENE := "res://scenes/rain_trial.tscn"

var trial_completed := false
var trial_summary: Dictionary = {}
var pause_menu: CanvasLayer
var _trial_time := 0.0
var _restart_pending := false


func _stage_ready() -> void:
	super()
	hud.banner("雨街 · 战斗试玩", "三处封印 · 挑飞、空追、方向收尾", 3.2)
	pause_menu = PauseMenu.new()
	pause_menu.name = "PauseMenu"
	pause_menu.stage = self
	add_child(pause_menu)
	hud.help_text += "   Esc 暂停"


func _physics_process(delta: float) -> void:
	if trial_completed:
		return
	_trial_time += delta
	super(delta)


func _on_encounter_cleared() -> void:
	if trial_completed:
		return
	if encounter_index + 1 < round_waves.size():
		super()
		return
	# 在父类重置本轮统计/增加下一轮难度之前，保存完整结果。
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
	get_tree().paused = true
	print("RAIN_TRIAL_COMPLETE ", JSON.stringify(trial_summary))


func _restart_trial() -> void:
	if _restart_pending:
		return
	_restart_pending = true
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file.call_deferred(TRIAL_SCENE)


func _exit_tree() -> void:
	if trial_completed and get_tree() != null:
		get_tree().paused = false
