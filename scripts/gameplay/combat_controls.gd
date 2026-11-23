extends RefCounted
## 「瞬步穿锋 · 追影重斩」(1A) 实战键位映射表。
##
## 在不改动 player_factory.gd 的前提下，由 night_trial.gd 在初始化与切换键位方案时调用：
##   · 纯键盘（keyboard）：J 轻击 · K 重击/蓄力 · Shift（及双击 A/D）瞬步冲刺 · L 弹刀 · U/I 飞镖 · R 大招
##   · 键鼠（mouse）     ：左键 轻击 · 右键 重击/蓄力 · Shift（及侧键/双击 A/D）瞬步冲刺 · E 弹刀 · Q 飞镖 · R 大招
##   · 手柄（Xbox 布局） ：X 轻击 · Y 重击/蓄力 · RB 瞬步冲刺 · LB 弹刀 · B 按住时缓搓招 · LT 飞镖 · RT 大招

const GamepadManager := preload("res://scripts/core/gamepad_manager.gd")

const SCHEME_KEYBOARD := "keyboard"
const SCHEME_MOUSE := "mouse"

const LABELS := {
	"keyboard": {
		"attack": "J",
		"heavy": "K",
		"dash": "Shift / 双击A·D",
		"parry": "L",
		"ranged": "U",
	},
	"mouse": {
		"attack": "左键",
		"heavy": "右键",
		"dash": "Shift / 双击A·D",
		"parry": "E",
		"ranged": "Q",
	},
}


static func labels(scheme: String) -> Dictionary:
	var key := SCHEME_MOUSE if scheme == SCHEME_MOUSE else SCHEME_KEYBOARD
	return LABELS[key]


static func key_label(scheme: String, what: String) -> String:
	var d := labels(scheme)
	return String(d.get(what, what))


static func apply_scheme(scheme: String) -> void:
	var use_mouse := (scheme == SCHEME_MOUSE)
	if use_mouse:
		_bind_action(&"attack_light", [], [MOUSE_BUTTON_LEFT], [JOY_BUTTON_X], [])
		_bind_action(&"attack_heavy", [], [MOUSE_BUTTON_RIGHT], [JOY_BUTTON_Y], [])
		_bind_action(&"dash_modifier", [KEY_SHIFT], [MOUSE_BUTTON_XBUTTON1], [JOY_BUTTON_RIGHT_SHOULDER], [])
		_bind_action(&"short_dash", [KEY_SHIFT], [MOUSE_BUTTON_XBUTTON1], [JOY_BUTTON_RIGHT_SHOULDER], [])
		_bind_action(&"parry", [KEY_E], [], [JOY_BUTTON_LEFT_SHOULDER], [])
		_bind_action(&"attack_ranged", [KEY_Q], [], [], [[JOY_AXIS_TRIGGER_LEFT, 1.0]], 0.35)
	else:
		_bind_action(&"attack_light", [KEY_J], [], [JOY_BUTTON_X], [])
		_bind_action(&"attack_heavy", [KEY_K], [], [JOY_BUTTON_Y], [])
		_bind_action(&"dash_modifier", [KEY_SHIFT], [], [JOY_BUTTON_RIGHT_SHOULDER], [])
		_bind_action(&"short_dash", [KEY_SHIFT, KEY_C], [], [JOY_BUTTON_RIGHT_SHOULDER], [])
		_bind_action(&"parry", [KEY_L], [], [JOY_BUTTON_LEFT_SHOULDER], [])
		_bind_action(&"attack_ranged", [KEY_U, KEY_I], [], [], [[JOY_AXIS_TRIGGER_LEFT, 1.0]], 0.35)
	_bind_action(&"ult", [KEY_R], [], [], [[JOY_AXIS_TRIGGER_RIGHT, 1.0]], 0.35)
	GamepadManager.ensure_ui_actions()
	GamepadManager.ensure_skill_actions()


static func _bind_action(action: StringName, keys: Array, mouse_buttons: Array,
		pad_buttons: Array, pad_axes: Array, deadzone: float = 0.5) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	InputMap.action_erase_events(action)
	InputMap.action_set_deadzone(action, deadzone)
	for key in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		InputMap.action_add_event(action, ev)
	for mb in mouse_buttons:
		var ev := InputEventMouseButton.new()
		ev.device = -1
		ev.button_index = mb
		InputMap.action_add_event(action, ev)
	for jb in pad_buttons:
		var ev := InputEventJoypadButton.new()
		ev.device = -1
		ev.button_index = jb
		InputMap.action_add_event(action, ev)
	for ax in pad_axes:
		var ev := InputEventJoypadMotion.new()
		ev.device = -1
		ev.axis = ax[0]
		ev.axis_value = float(ax[1])
		InputMap.action_add_event(action, ev)
