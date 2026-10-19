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


static func register_input() -> void:
	var bindings := {"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT], "jump": [KEY_W, KEY_SPACE],
		"aim_up": [KEY_W, KEY_UP], "move_down": [KEY_S, KEY_DOWN], "attack_light": [KEY_J], "attack_ranged": [KEY_K],
		"parry": [KEY_L], "dash_modifier": [KEY_SHIFT], "reset": [KEY_R], "debug_toggle": [KEY_F1],
		"toggle_help": [KEY_H], "open_training": [KEY_F3]}
	for name in bindings:
		if not InputMap.has_action(name):
			InputMap.add_action(name)
		InputMap.action_erase_events(name)
		for key in bindings[name]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(name, event)
