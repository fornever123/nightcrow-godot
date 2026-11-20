extends SceneTree
## 开发探针：真实读 assets/data/tuning.json 后游戏看到的值。修改器验收用。
## NIGHTCROW_TUNING=1 时看叠加后的值；不设时 --script 启动应该看默认值。
const Tuning := preload("res://scripts/core/tuning.gd")
const Config := preload("res://scripts/core/configuration.gd")
const Encounters := preload("res://scripts/core/encounters.gd")
const Shade := preload("res://scripts/night/shade.gd")


func _initialize() -> void:
	print("PROBE enabled=", Tuning.enabled(), " has_script_arg=", OS.get_cmdline_args().has("--script"), " display=", DisplayServer.get_name())
	var battle: Dictionary = Config.read()
	for m in battle.moves:
		if m.id in ["light_1", "dash_slash"]:
			print("PROBE ", m.id, " damage=", m.damage, " hitbox_w=", m.hitbox.width, " startupSpeed=", m.get("startupSpeed"))
	var moves: Dictionary = Config.moves(battle)
	var light: Object = moves["light_1"]
	print("PROBE light_1 def startup=", light.get("startup_frames"), " active=", light.get("active_frames"))
	print("PROBE grunt_hp=", Encounters.kinds(Shade.KIND_IDS)[Shade.Kind.GRUNT].hp)
	print("PROBE wave0=", Encounters.waves(Shade.KIND_IDS)[0][0].spawns)
	quit(0)
