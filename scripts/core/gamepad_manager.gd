extends Node
## 全局手柄输入与交互管理器（Xbox / 通用手柄全链路适配）：
## 1. 修补 Godot 4 导出默认 InputMap 缺失：为 ui_accept 注入 JOY_BUTTON_A（任意端口 device=-1），
##    移除 ui_select 默认误绑的 JOY_BUTTON_Y（防止按 Y 升级/功能键误触焦点按钮），
##    确保 ui_cancel 绑定 JOY_BUTTON_START（不绑 B，避免战斗冲刺误弹暂停）；
## 2. 维护带死区防抖的键鼠 / 手柄实时输入态（device_changed 信号），杜绝摇杆微漂移抢占提示；
## 3. 提供双轴独立滞回 + 按住连发的 StickRepeater，解决菜单摇杆串轴乱跳与单拨多跳；
## 4. 提供安全受控的手柄震动反馈（暂停/切场景自动停震，永不卡震）。

signal device_changed(using_pad: bool)

const MOTION_DETECT_DEADZONE := 0.28
const MOUSE_MOVE_MIN_SQ := 36.0
const SETTINGS_CFG := "user://settings.cfg"

static var instance: Node = null
static var _using_gamepad: bool = false
static var _active_joy_device: int = 0
static var _was_paused: bool = false
static var _skill_hints_loaded: bool = false
static var _skill_hints_enabled: bool = true


class StickRepeater extends RefCounted:
	const ACTIVATE := 0.58
	const RELEASE := 0.30
	const INITIAL_DELAY_US := 320000
	const REPEAT_INTERVAL_US := 125000

	var dir_x: int = 0
	var dir_y: int = 0
	var _next_x_us: int = 0
	var _next_y_us: int = 0

	func reset() -> void:
		dir_x = 0
		dir_y = 0
		_next_x_us = 0
		_next_y_us = 0

	func feed_motion(ev: InputEventJoypadMotion) -> Vector2i:
		var now := Time.get_ticks_usec()
		var out := Vector2i.ZERO
		if ev.axis == JOY_AXIS_LEFT_X:
			var vx := ev.axis_value
			if absf(vx) >= ACTIVATE:
				var nx := 1 if vx > 0.0 else -1
				if nx != dir_x:
					dir_x = nx
					_next_x_us = now + INITIAL_DELAY_US
					out.x = nx
			elif absf(vx) <= RELEASE:
				dir_x = 0
				_next_x_us = 0
		elif ev.axis == JOY_AXIS_LEFT_Y:
			var vy := ev.axis_value
			if absf(vy) >= ACTIVATE:
				var ny := 1 if vy > 0.0 else -1
				if ny != dir_y:
					dir_y = ny
					_next_y_us = now + INITIAL_DELAY_US
					out.y = ny
			elif absf(vy) <= RELEASE:
				dir_y = 0
				_next_y_us = 0
		return out

	func poll_repeat() -> Vector2i:
		var now := Time.get_ticks_usec()
		var out := Vector2i.ZERO
		if dir_x != 0 and _next_x_us > 0 and now >= _next_x_us:
			_next_x_us = now + REPEAT_INTERVAL_US
			out.x = dir_x
		if dir_y != 0 and _next_y_us > 0 and now >= _next_y_us:
			_next_y_us = now + REPEAT_INTERVAL_US
			out.y = dir_y
		return out


func _enter_tree() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	instance = self
	ensure_ui_actions()


func _ready() -> void:
	ensure_ui_actions()
	var pads := Input.get_connected_joypads()
	if not pads.is_empty():
		_active_joy_device = int(pads[0])
		_set_using_gamepad(true)
	if not Input.joy_connection_changed.is_connected(_on_joy_connection_changed):
		Input.joy_connection_changed.connect(_on_joy_connection_changed)


func _exit_tree() -> void:
	stop_all_rumble()
	if instance == self:
		instance = null


func _process(_delta: float) -> void:
	var paused_now := get_tree() != null and get_tree().paused
	if paused_now and not _was_paused:
		stop_all_rumble()
	_was_paused = paused_now


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton:
		var jb := event as InputEventJoypadButton
		if jb.pressed:
			if jb.device >= 0:
				_active_joy_device = jb.device
			_set_using_gamepad(true)
	elif event is InputEventJoypadMotion:
		var jm := event as InputEventJoypadMotion
		if absf(jm.axis_value) >= MOTION_DETECT_DEADZONE:
			if jm.device >= 0:
				_active_joy_device = jm.device
			_set_using_gamepad(true)
	elif event is InputEventKey:
		if (event as InputEventKey).pressed:
			_set_using_gamepad(false)
	elif event is InputEventMouseButton:
		if (event as InputEventMouseButton).pressed:
			_set_using_gamepad(false)
	elif event is InputEventMouseMotion:
		if (event as InputEventMouseMotion).relative.length_squared() >= MOUSE_MOVE_MIN_SQ:
			_set_using_gamepad(false)


func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if connected:
		_active_joy_device = device
		_set_using_gamepad(true)
	else:
		Input.stop_joy_vibration(device)
		var pads := Input.get_connected_joypads()
		if pads.is_empty():
			_set_using_gamepad(false)
		else:
			_active_joy_device = int(pads[0])


static func is_using_gamepad() -> bool:
	return _using_gamepad


static func set_using_gamepad(on: bool) -> void:
	if instance != null and is_instance_valid(instance):
		instance._set_using_gamepad(on)
	else:
		_using_gamepad = on


func _set_using_gamepad(on: bool) -> void:
	if _using_gamepad == on:
		return
	_using_gamepad = on
	if not on:
		stop_all_rumble()
	device_changed.emit(_using_gamepad)


static func ensure_ui_actions() -> void:
	# 1. ui_accept：补齐 Xbox A（JOY_BUTTON_A, device=-1），解决全游戏确认键失灵根因
	_ensure_joy_button(&"ui_accept", JOY_BUTTON_A)

	# 2. ui_select：移除内置默认绑定的 JOY_BUTTON_Y，防止手柄按 Y 误触当前焦点 Button
	if InputMap.has_action(&"ui_select"):
		var to_erase: Array[InputEvent] = []
		for ev in InputMap.action_get_events(&"ui_select"):
			if ev is InputEventJoypadButton:
				to_erase.append(ev)
		for ev in to_erase:
			InputMap.action_erase_event(&"ui_select", ev)

	# 3. ui_cancel：仅保留手柄 Start（移除 B，战斗中 B 为瞬步冲刺，菜单内单独认 B 返回）
	if not InputMap.has_action(&"ui_cancel"):
		InputMap.add_action(&"ui_cancel")
	var cancel_erase: Array[InputEvent] = []
	for ev in InputMap.action_get_events(&"ui_cancel"):
		if ev is InputEventJoypadButton and (ev as InputEventJoypadButton).button_index != JOY_BUTTON_START:
			cancel_erase.append(ev)
	for ev in cancel_erase:
		InputMap.action_erase_event(&"ui_cancel", ev)
	_ensure_joy_button(&"ui_cancel", JOY_BUTTON_START)

	# 4. 四向 UI 导航（十字键 + 左摇杆全端口覆盖）
	_ensure_joy_button(&"ui_up", JOY_BUTTON_DPAD_UP)
	_ensure_joy_button(&"ui_down", JOY_BUTTON_DPAD_DOWN)
	_ensure_joy_button(&"ui_left", JOY_BUTTON_DPAD_LEFT)
	_ensure_joy_button(&"ui_right", JOY_BUTTON_DPAD_RIGHT)
	_ensure_joy_axis(&"ui_up", JOY_AXIS_LEFT_Y, -1.0, 0.5)
	_ensure_joy_axis(&"ui_down", JOY_AXIS_LEFT_Y, 1.0, 0.5)
	_ensure_joy_axis(&"ui_left", JOY_AXIS_LEFT_X, -1.0, 0.5)
	_ensure_joy_axis(&"ui_right", JOY_AXIS_LEFT_X, 1.0, 0.5)


static func _ensure_joy_button(action: StringName, btn: JoyButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadButton:
			var jb := ev as InputEventJoypadButton
			if jb.button_index == btn and jb.device == -1:
				return
	# 移除同键但锁了单端口的旧事件，统一成全端口 device = -1
	var stale: Array[InputEvent] = []
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadButton and (ev as InputEventJoypadButton).button_index == btn:
			stale.append(ev)
	for ev in stale:
		InputMap.action_erase_event(action, ev)
	var add_ev := InputEventJoypadButton.new()
	add_ev.device = -1
	add_ev.button_index = btn
	InputMap.action_add_event(action, add_ev)


static func _ensure_joy_axis(action: StringName, axis: JoyAxis, axis_val: float, deadzone: float = 0.5) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
		InputMap.action_set_deadzone(action, deadzone)
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadMotion:
			var jm := ev as InputEventJoypadMotion
			if jm.axis == axis and signf(jm.axis_value) == signf(axis_val) and jm.device == -1:
				return
	var add_ev := InputEventJoypadMotion.new()
	add_ev.device = -1
	add_ev.axis = axis
	add_ev.axis_value = axis_val
	InputMap.action_add_event(action, add_ev)


static func rumble(weak: float, strong: float, duration: float) -> void:
	if not _using_gamepad or DisplayServer.get_name() == "headless":
		return
	if instance != null and instance.get_tree() != null and instance.get_tree().paused:
		return
	var pads := Input.get_connected_joypads()
	if pads.is_empty():
		return
	var dev := _active_joy_device if pads.has(_active_joy_device) else int(pads[0])
	Input.start_joy_vibration(dev, clampf(weak, 0.0, 1.0), clampf(strong, 0.0, 1.0), clampf(duration, 0.02, 0.6))


static func stop_all_rumble() -> void:
	if DisplayServer.get_name() == "headless":
		return
	for dev in Input.get_connected_joypads():
		Input.stop_joy_vibration(int(dev))


static func is_skill_hints_enabled() -> bool:
	if not _skill_hints_loaded:
		_skill_hints_loaded = true
		_skill_hints_enabled = true
		if DisplayServer.get_name() != "headless":
			var cfg := ConfigFile.new()
			if cfg.load(SETTINGS_CFG) == OK and cfg.has_section_key("combat", "skill_hints"):
				_skill_hints_enabled = bool(cfg.get_value("combat", "skill_hints", true))
	return _skill_hints_enabled


static func set_skill_hints_enabled(enabled: bool, save: bool = true) -> void:
	_skill_hints_loaded = true
	_skill_hints_enabled = enabled
	if save and DisplayServer.get_name() != "headless":
		var cfg := ConfigFile.new()
		cfg.load(SETTINGS_CFG)
		cfg.set_value("combat", "skill_hints", enabled)
		cfg.save(SETTINGS_CFG)


static func ensure_skill_actions() -> void:
	var key_map := {
		&"skill_stance": [KEY_TAB, KEY_CTRL],
		&"skill_up": [KEY_UP],
		&"skill_down": [KEY_DOWN],
		&"skill_left": [KEY_LEFT],
		&"skill_right": [KEY_RIGHT],
	}
	var pad_map := {
		&"skill_stance": JOY_BUTTON_B,
		&"skill_up": JOY_BUTTON_DPAD_UP,
		&"skill_down": JOY_BUTTON_DPAD_DOWN,
		&"skill_left": JOY_BUTTON_DPAD_LEFT,
		&"skill_right": JOY_BUTTON_DPAD_RIGHT,
	}
	for act in key_map.keys():
		if not InputMap.has_action(act):
			InputMap.add_action(act)
		for kc in key_map[act]:
			var found := false
			for ev in InputMap.action_get_events(act):
				if ev is InputEventKey and (ev as InputEventKey).physical_keycode == kc:
					found = true
					break
			if not found:
				var kev := InputEventKey.new()
				kev.physical_keycode = kc
				InputMap.action_add_event(act, kev)
		_ensure_joy_button(act, pad_map[act])
