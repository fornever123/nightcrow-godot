extends CanvasLayer
## 《断晓》玩家战死 `5:59` 触底回溯实机演出（death_rewind_fx.gd）
##
## 严格对齐 `E:/00game/剧情与主题规划.md` §五.3：
##   - 严禁修改 `Engine.time_scale`！
##   - `hp <= 0` 瞬间将战斗世界设为 `PROCESS_MODE_DISABLED` 原帧锁死全场；
##   - 顶层独立 `CanvasLayer`（`PROCESS_MODE_ALWAYS`）：
##       1) `0.00s..0.12s`：刺眼冷白遮罩自上而下淹没全屏并浮现 `5 : 59` 刻痕；
##       2) `0.12s..0.62s`（`0.50s`）：同步静音音频总线，保持视觉与听觉绝对静止死寂；
##       3) `0.62s..0.87s`（`0.25s`）：解除静音响起单声倒抽钟鸣，白幕向上逆向坍缩回入夜锚点。

signal rewind_completed()

const BossFonts := preload("res://scripts/boss_sample/boss_fonts.gd")

const SWEEP_DOWN_SEC := 0.12
const DEAD_SILENCE_SEC := 0.50
const COLLAPSE_UP_SEC := 0.25
const TOTAL_SEC := SWEEP_DOWN_SEC + DEAD_SILENCE_SEC + COLLAPSE_UP_SEC

var active: bool = false
var elapsed: float = 0.0
var boss_hp_left_pct: int = 0

var _canvas: Control = null
var _roman_font: Font = null
var _cn_font: Font = null
var _muted_buses: Array[int] = []
var _chime_played: bool = false
var _audio_ref: Node = null
var _frozen_targets: Array[Node] = []
var _prev_modes: Array[int] = []


func _ready() -> void:
	layer = 42
	process_mode = Node.PROCESS_MODE_ALWAYS
	_roman_font = BossFonts.load_font(BossFonts.GOTHIC_CINZEL)
	_cn_font = BossFonts.load_font(BossFonts.SERIF_SC)
	_canvas = Control.new()
	_canvas.name = "WhiteoutCanvas"
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_whiteout)
	add_child(_canvas)


func _exit_tree() -> void:
	_restore_audio_and_nodes()


func trigger_rewind(freeze_nodes: Array, boss_pct: int = 0, audio_node: Node = null) -> void:
	if active:
		return
	active = true
	elapsed = 0.0
	boss_hp_left_pct = boss_pct
	_chime_played = false
	_frozen_targets.clear()
	_prev_modes.clear()
	for n in freeze_nodes:
		if n != null and is_instance_valid(n) and n != self:
			_frozen_targets.append(n)
			_prev_modes.append(int(n.process_mode))
			n.process_mode = Node.PROCESS_MODE_DISABLED
	_audio_ref = audio_node
	_canvas.queue_redraw()


func _mute_master_for_silence() -> void:
	if not _muted_buses.is_empty():
		return
	for idx in AudioServer.bus_count:
		if not AudioServer.is_bus_mute(idx):
			AudioServer.set_bus_mute(idx, true)
			_muted_buses.append(idx)


func _unmute_master() -> void:
	for idx in _muted_buses:
		if idx >= 0 and idx < AudioServer.bus_count:
			AudioServer.set_bus_mute(idx, false)
	_muted_buses.clear()


func _restore_audio_and_nodes() -> void:
	_unmute_master()
	for i in _frozen_targets.size():
		var n := _frozen_targets[i]
		if n != null and is_instance_valid(n):
			n.process_mode = _prev_modes[i] as Node.ProcessMode
	_frozen_targets.clear()
	_prev_modes.clear()


func _process(delta: float) -> void:
	if not active:
		return
	elapsed += delta
	if elapsed >= SWEEP_DOWN_SEC and elapsed < SWEEP_DOWN_SEC + DEAD_SILENCE_SEC:
		_mute_master_for_silence()
	elif elapsed >= SWEEP_DOWN_SEC + DEAD_SILENCE_SEC and not _chime_played:
		_chime_played = true
		_unmute_master()
		if _audio_ref != null and is_instance_valid(_audio_ref) and _audio_ref.has_method(&"_play_clip"):
			_audio_ref.call(&"_play_clip", "parry", -0.35, -7.0)
	_canvas.queue_redraw()
	if elapsed >= TOTAL_SEC:
		active = false
		_restore_audio_and_nodes()
		_canvas.queue_redraw()
		rewind_completed.emit()


func _draw_whiteout() -> void:
	if not active or _canvas == null:
		return
	var sz := _canvas.size
	if sz.x <= 1.0 or sz.y <= 1.0:
		sz = Vector2(1280.0, 720.0)

	var top_y := 0.0
	var bot_y := sz.y
	var text_alpha := 0.0

	if elapsed < SWEEP_DOWN_SEC:
		var k := clampf(elapsed / SWEEP_DOWN_SEC, 0.0, 1.0)
		var ease_k := 1.0 - pow(1.0 - k, 3.0)
		bot_y = sz.y * ease_k
		text_alpha = clampf((k - 0.45) / 0.55, 0.0, 1.0)
	elif elapsed < SWEEP_DOWN_SEC + DEAD_SILENCE_SEC:
		bot_y = sz.y
		text_alpha = 1.0
	else:
		var k2 := clampf((elapsed - SWEEP_DOWN_SEC - DEAD_SILENCE_SEC) / COLLAPSE_UP_SEC, 0.0, 1.0)
		var ease_up := pow(k2, 2.2)
		bot_y = sz.y * (1.0 - ease_up)
		text_alpha = 1.0 - k2

	if bot_y > top_y + 0.5:
		_canvas.draw_rect(Rect2(0.0, top_y, sz.x, bot_y - top_y), Color(0.965, 0.98, 1.0, 0.985))
		if bot_y < sz.y - 2.0:
			_canvas.draw_line(Vector2(0.0, bot_y), Vector2(sz.x, bot_y), Color(0.72, 0.84, 0.98, 0.95), 4.0)

	if text_alpha > 0.02:
		var cy := sz.y * 0.48
		var ink := Color(0.035, 0.048, 0.075, text_alpha)
		var sub_ink := Color(0.16, 0.20, 0.28, text_alpha * 0.78)
		_canvas.draw_line(Vector2(sz.x * 0.18, cy + 18.0), Vector2(sz.x * 0.82, cy + 18.0), Color(0.05, 0.07, 0.11, text_alpha * 0.55), 1.6)
		if _roman_font != null:
			_canvas.draw_string(_roman_font, Vector2(0.0, cy), "5 : 59", HORIZONTAL_ALIGNMENT_CENTER, sz.x, 76, ink)
		if _cn_font != null:
			var note := "白光吞没全境  ·  时间触底回溯"
			if boss_hp_left_pct > 0:
				note += "  （残影余量 %d%%）" % boss_hp_left_pct
			_canvas.draw_string(_cn_font, Vector2(0.0, cy + 52.0), note, HORIZONTAL_ALIGNMENT_CENTER, sz.x, 17, sub_ink)
