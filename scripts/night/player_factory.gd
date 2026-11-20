extends RefCounted
## 按统一配置（battle.json）搭出玩家。逻辑与 training.gd 的 _ready 完全一致，
## 只是抽成一个函数，让试玩场景和训练场用同一套参数（改修改器两边同时生效）。

const Config := preload("res://scripts/core/configuration.gd")
const Art := preload("res://scripts/presentation/art_cache.gd")
const PlayerScene := preload("res://scenes/actors/player.tscn")


static func build(config: Dictionary, moves: Dictionary, spawn: Vector2) -> CharacterBody2D:
	var c := Config.character(config, "player")
	Art.reset(c.sprite)
	var player: CharacterBody2D = PlayerScene.instantiate()
	player.set_meta("character", c)
	var world_scale := float(c.sprite.get("worldScale", c.sprite.get("displayScale", 1)))
	player.foot_offset = 84.0 * world_scale
	player.position = Vector2(spawn.x, spawn.y - player.foot_offset)
	player.get_node("Visual/ActorSprite").position.y = player.foot_offset
	var capsule: CapsuleShape2D = player.get_node("CollisionShape2D").shape
	capsule.height = 168.0 * world_scale
	capsule.radius = minf(25.0 * world_scale, capsule.height / 2)
	var hurt: RectangleShape2D = player.get_node("Hurtbox/CollisionShape2D").shape
	hurt.size = Vector2(c.hurtbox.width, c.hurtbox.height) * world_scale
	var settings: Dictionary = config.settings
	player.apply_movement_config(c, settings)
	player.max_hp = c.maxHp
	player.squash_strength = float(config.feedback.get("squashStrength", 0))
	player.hitstop_multiplier = float(config.feedback.get("hitstopMultiplier", 1))
	player.parry_hitstop_frames = roundi(float(config.feedback.get("parryHitstop", 0.05)) * 60 * float(config.feedback.get("hitstopMultiplier", 1)))
	player.attack_buffer_frames = int(config.runtime.get("attackBufferFrames", 36))
	player.hold_to_charge_frames = int(config.runtime.get("holdToChargeFrames", 10))
	player.combo_keep_frames = int(config.runtime.get("comboKeepFrames", 48))
	player.light_combo = [moves.light_1, moves.light_2, moves.light_3]
	player.charge_move = moves.charge_1
	player.up_strike_move = moves.up_strike
	player.air_up_move = moves.air_up
	player.ranged_move = moves.ranged_1
	player.parry_move = moves.parry_1
	for move_id in ["air_light_1", "air_light_2", "air_light_3"]:
		if moves.has(move_id):
			player.air_combo.append(moves[move_id])
	player.dash_move = moves.get("dash_slash")
	player.dash_left_move = moves.get("dash_slash_left")
	# 11-03：空中冲刺斩、下落攻击都有各自的招式资源（"单独动作模组"）；没有就退回地面冲刺斩 / 空中第三刀
	player.air_dash_move = moves.get("air_dash_slash")
	player.air_dash_left_move = moves.get("air_dash_slash_left")
	player.air_plunge_move = moves.get("air_plunge")
	for i in 3:
		if moves.has("guard_hit_%d" % (i + 1)):
			player.guard_reactions.append(moves["guard_hit_%d" % (i + 1)])
		if moves.has("parry_react_%d" % (i + 1)):
			player.parry_reactions.append(moves["parry_react_%d" % (i + 1)])
	var runtime_ranged: Dictionary = {}
	for source in config.moves:
		if source.id == "ranged_1":
			runtime_ranged = source.get("projectile", {})
	player.ranged_speed = float(runtime_ranged.get("speed", 940))
	player.ranged_life_frames = roundi(float(runtime_ranged.get("life", 1.5)) * 60)
	player.ranged_offset = Vector2(runtime_ranged.get("spawnX", 54), player.foot_offset + float(runtime_ranged.get("spawnY", -90)))
	return player


## 键位（11-01 用户）：键盘 / 键鼠【二选一】，默认键盘；手柄两种模式下都能用。
##   两套共用：A/D 移动 · W/空格 跳 · S 下平台 · R 大招 · F5 重开 · H 提示 · F1 / F3
##   键盘（keyboard）：J 攻击 · K 远射 · L 弹刀 · **双击 A / D 冲刺斩**（Shift 是别名；J+K 也能放大招）
##   键鼠（mouse）：左键 攻击 · **双击 A / D 冲刺斩**（右键 / Shift 是别名）· E 弹刀 · Q 远射（这时 J / K / L 不起作用）
##   手柄（Xbox 布局）：左摇杆 / 十字键 · A 跳 · X 攻击 · Y 远射 · B 冲刺斩 · RB 弹刀 · RT 大招 · Start 暂停 · Back 重开
## 选哪套记在 user://controls.cfg；改用 set_scheme()，会立刻重绑并存盘。
## jump_pure 是“只是跳”的键（空格 / 手柄 A）：W 同时是跳和上方向，按住它不算上挑意图，见 player._pure_jump_down()。
const SCHEME_KEYBOARD := "keyboard"
const SCHEME_MOUSE := "mouse"
const SCHEMES := [SCHEME_KEYBOARD, SCHEME_MOUSE]
const SCHEME_NAMES := {"keyboard": "键盘", "mouse": "键鼠"}
const CONTROLS_CFG := "user://controls.cfg"
const KEYS := {"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT], "jump": [KEY_W, KEY_SPACE],
	"jump_pure": [KEY_SPACE], "aim_up": [KEY_W, KEY_UP], "move_down": [KEY_S, KEY_DOWN],
	"ult": [KEY_R], "reset": [KEY_F5], "debug_toggle": [KEY_F1],
	"toggle_help": [KEY_H], "open_training": [KEY_F3]}
const SCHEME_KEYS := {
	"keyboard": {"attack_light": [KEY_J], "attack_ranged": [KEY_K], "parry": [KEY_L], "dash_modifier": [KEY_SHIFT]},
	"mouse": {"attack_light": [], "attack_ranged": [KEY_Q], "parry": [KEY_E], "dash_modifier": [KEY_SHIFT]},
}
const SCHEME_MOUSE_BUTTONS := {
	"keyboard": {},
	"mouse": {"attack_light": [MOUSE_BUTTON_LEFT], "dash_modifier": [MOUSE_BUTTON_RIGHT]},
}
## 提示文字里每个键叫什么
const SCHEME_LABELS := {
	"keyboard": {"attack": "J", "ranged": "K", "parry": "L", "dash": "双击 A/D"},
	"mouse": {"attack": "左键", "ranged": "Q", "parry": "E", "dash": "双击 A/D"},
}
const PAD_BUTTONS := {"move_left": [JOY_BUTTON_DPAD_LEFT], "move_right": [JOY_BUTTON_DPAD_RIGHT],
	"aim_up": [JOY_BUTTON_DPAD_UP], "move_down": [JOY_BUTTON_DPAD_DOWN], "jump": [JOY_BUTTON_A],
	"jump_pure": [JOY_BUTTON_A], "attack_light": [JOY_BUTTON_X], "attack_ranged": [JOY_BUTTON_Y],
	"dash_modifier": [JOY_BUTTON_B], "parry": [JOY_BUTTON_RIGHT_SHOULDER], "reset": [JOY_BUTTON_BACK]}
## [轴, 方向]；摇杆上下的死区比左右大，免得跑步时手一偏就变成上挑 / 下平台
const PAD_AXES := {"move_left": [JOY_AXIS_LEFT_X, -1.0], "move_right": [JOY_AXIS_LEFT_X, 1.0],
	"aim_up": [JOY_AXIS_LEFT_Y, -1.0], "move_down": [JOY_AXIS_LEFT_Y, 1.0], "ult": [JOY_AXIS_TRIGGER_RIGHT, 1.0]}
const DEADZONES := {"move_left": 0.25, "move_right": 0.25, "aim_up": 0.5, "move_down": 0.5, "ult": 0.5}

static var _scheme := ""
static var _extra := {}


## 当前用哪套。第一次问时读存档；headless（自动测试）不读存档，一律键盘，
## 环境变量 NIGHTCROW_CONTROLS=keyboard / mouse 可以覆盖（测试用）。
static func scheme() -> String:
	if _scheme.is_empty():
		_scheme = SCHEME_KEYBOARD
		var env := OS.get_environment("NIGHTCROW_CONTROLS")
		if SCHEMES.has(env):
			_scheme = env
		elif DisplayServer.get_name() != "headless":
			var cfg := ConfigFile.new()
			if cfg.load(CONTROLS_CFG) == OK and SCHEMES.has(String(cfg.get_value("controls", "scheme", ""))):
				_scheme = String(cfg.get_value("controls", "scheme"))
	return _scheme


## 换一套键位：立刻重绑；save = 记进 user://controls.cfg（测试传 false）。
## 调完再调一下关卡的 apply_control_scheme()，底部提示会跟着换。
static func set_scheme(value: String, save := true) -> void:
	if not SCHEMES.has(value):
		return
	_scheme = value
	if save:
		var cfg := ConfigFile.new()
		cfg.load(CONTROLS_CFG)
		cfg.set_value("controls", "scheme", value)
		cfg.save(CONTROLS_CFG)
	register_input(_extra)


static func scheme_name() -> String:
	return SCHEME_NAMES[scheme()]


## 提示文字用：attack / ranged / parry / dash 在当前这套里叫什么
static func key_label(what: String) -> String:
	return String(SCHEME_LABELS[scheme()].get(what, what))


static func register_input(extra: Dictionary = {}) -> void:
	_extra = extra
	var current := scheme()
	var keys := KEYS.duplicate()
	keys.merge(SCHEME_KEYS[current], true)
	keys.merge(extra, true)
	for name in PAD_BUTTONS:
		if not keys.has(name):
			keys[name] = []
	for name in keys:
		if not InputMap.has_action(name):
			InputMap.add_action(name)
		InputMap.action_erase_events(name)
		InputMap.action_set_deadzone(name, float(DEADZONES.get(name, 0.5)))
		for key in keys[name]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(name, event)
	var mouse: Dictionary = SCHEME_MOUSE_BUTTONS[current]
	for name in mouse:
		for button in mouse[name]:
			var event := InputEventMouseButton.new()
			event.device = -1   # 任何设备（引擎里的 ALL_DEVICES）
			event.button_index = button
			InputMap.action_add_event(name, event)
	for name in PAD_BUTTONS:
		for button in PAD_BUTTONS[name]:
			var event := InputEventJoypadButton.new()
			event.device = -1   # 插在第几个口的手柄都认
			event.button_index = button
			InputMap.action_add_event(name, event)
	for name in PAD_AXES:
		var event := InputEventJoypadMotion.new()
		event.device = -1
		event.axis = PAD_AXES[name][0]
		event.axis_value = PAD_AXES[name][1]
		InputMap.action_add_event(name, event)
	# 手柄 B 现在是冲刺斩：从 ui_cancel 里拿掉（不然一按 B 就暂停），暂停改用 Start
	for event in InputMap.action_get_events(&"ui_cancel"):
		if event is InputEventJoypadButton:
			InputMap.action_erase_event(&"ui_cancel", event)
	var start := InputEventJoypadButton.new()
	start.device = -1
	start.button_index = JOY_BUTTON_START
	InputMap.action_add_event(&"ui_cancel", start)
