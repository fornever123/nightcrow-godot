extends Node2D
## One configuration file for game and modifier; C-drive combat remains the gameplay core.
const Config := preload("res://scripts/core/configuration.gd")
const Art := preload("res://scripts/presentation/art_cache.gd")
const PlayerScene := preload("res://scenes/actors/player.tscn")
const DummyScene := preload("res://scenes/actors/dummy.tscn")
const CameraScript := preload("res://scripts/presentation/camera_shake.gd")
const AudioFeedback := preload("res://scripts/presentation/audio_feedback.gd")
const ImpactFX := preload("res://scripts/presentation/impact_fx.gd")
const Feel := preload("res://scripts/core/feel_scale.gd")
const Timeline := preload("res://scripts/core/animation_timeline.gd")
var config: Dictionary
var moves: Dictionary
var player: CharacterBody2D
var dummy: CharacterBody2D
var camera: Camera2D
var hud: Label
var help_label: Label
var poll: float = 0.0
var disk_hash: int = 0
var debug_boxes: bool = false
var last_damage: float = 0.0
var total_hits: int = 0
var audio: Node
var fx: Node2D
var combo_hits: int = 0
var combo_time: float = 0.0
var last_feedback: String = ""
var reloading: bool = false
var training_attacks: bool = false
var training_attack_clock: float = 0.0
var training_telegraph: float = 0.0

func _ready() -> void:
	config = Config.read()
	if config.is_empty():
		push_error("无法读取统一战斗配置")
		return
	disk_hash = FileAccess.get_file_as_string(Config.PATH).hash()
	moves = Config.moves(config)
	RenderingServer.set_default_clear_color(Color(config.art.get("background","#20212c")))
	_register_input()
	var bounds: Dictionary = config.stage.bounds
	_floor(Rect2(bounds.left, bounds.floorY, bounds.right - bounds.left, 100))
	_floor(Rect2(bounds.left - 40, -500, 40, bounds.floorY + 600))
	_floor(Rect2(bounds.right, -500, 40, bounds.floorY + 600))
	var c := Config.character(config, "player")
	Art.reset(c.sprite)
	player = PlayerScene.instantiate()
	player.set_meta("character", c)
	# Source PNG pixel scale is independent of the physical character's size.
	var world_scale := float(c.sprite.get("worldScale", c.sprite.get("displayScale",1)))
	player.foot_offset = 84.0 * world_scale
	player.position = Vector2(config.stage.spawn.player.x, config.stage.spawn.player.y - player.foot_offset)
	player.get_node("Visual/ActorSprite").position.y = player.foot_offset
	var capsule: CapsuleShape2D = player.get_node("CollisionShape2D").shape
	capsule.height = 168.0 * world_scale
	capsule.radius = minf(25.0 * world_scale, capsule.height/2)
	var hurt: RectangleShape2D = player.get_node("Hurtbox/CollisionShape2D").shape
	hurt.size = Vector2(c.hurtbox.width,c.hurtbox.height) * world_scale
	player.apply_movement_config(c, config.settings)
	player.max_hp = c.maxHp
	player.squash_strength = float(config.feedback.get("squashStrength",0))
	player.parry_hitstop_frames = roundi(float(config.feedback.get("parryHitstop",0.05))*60*float(config.feedback.get("hitstopMultiplier",1)))
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
		if moves.has("guard_hit_%d" % (i+1)):
			player.guard_reactions.append(moves["guard_hit_%d" % (i+1)])
		if moves.has("parry_react_%d" % (i+1)):
			player.parry_reactions.append(moves["parry_react_%d" % (i+1)])
	var runtime_ranged: Dictionary = {}
	for source in config.moves:
		if source.id == "ranged_1":
			runtime_ranged = source.get("projectile", {})
	player.ranged_speed = float(runtime_ranged.get("speed", 940))
	player.ranged_life_frames = roundi(float(runtime_ranged.get("life", 1.5)) * 60)
	player.ranged_offset = Vector2(runtime_ranged.get("spawnX", 54), player.foot_offset + float(runtime_ranged.get("spawnY", -90)))
	add_child(player)
	var d := Config.character(config, "dummy")
	dummy = DummyScene.instantiate()
	dummy.position = Vector2(config.stage.spawn.enemies[0].x, config.stage.spawn.enemies[0].y - 68)
	dummy.max_hp = d.get("maxHp", 320)
	dummy.respawn_delay_frames = 60
	dummy.flash_enabled = bool(config.feedback.get("effectsEnabled",true))
	add_child(dummy)
	camera = Camera2D.new()
	camera.set_script(CameraScript)
	camera.position = Vector2(640,360)
	camera.shake_decay = float(config.camera.get("shakeDecay",7))
	camera.pixel_snap = float(config.camera.get("shakePixelSnap",1))
	camera.max_shake = float(config.camera.get("maxShake",42))
	add_child(camera)
	camera.make_current()
	if bool(config.camera.get("followPlayer",false)):
		camera.follow_target = player
		camera.arena_min = Vector2(bounds.left,0)
		camera.arena_max = Vector2(bounds.right,720)
		camera.follow_smoothing = float(config.camera.get("followLerp",0.12))*60
	audio = AudioFeedback.new()
	audio.configure(config.get("audio",{}))
	add_child(audio)
	fx = ImpactFX.new()
	fx.enabled = bool(config.feedback.get("effectsEnabled",true))
	fx.damage_numbers_enabled = bool(config.ui.get("showDamageNumbers",true))
	add_child(fx)
	player.hit_confirmed.connect(_hit)
	player.parry_success.connect(_parry)
	player.block_success.connect(_block)
	player.move_started.connect(func(move: Resource, _index: int):
		if move == player.dash_move or move == player.dash_left_move:
			audio.play_dash())
	player.swing_cue.connect(func(move: Resource, index: int): audio.play_swing_of(move,index))
	audio.attach_player(player)
	player.jumped.connect(audio.play_jump)
	player.landed.connect(_landed)
	player.charge_started.connect(audio.play_charge_start)
	player.charge_released.connect(func(_frames: int, charged: bool): audio.play_charge_release(charged))
	player.ranged_fired.connect(func(_projectile: Node): audio.play_ranged())
	dummy.damaged.connect(_damage)
	dummy.wall_slam.connect(_wall_hit.bind(dummy))
	player.wall_slam.connect(_wall_hit.bind(player))
	dummy.died.connect(_knockdown)
	_build_hud()
	queue_redraw()
	print("NIGHTCROW_READY: E角色168px / C战斗 / 木桩场景 / 统一JSON")

func _floor(rect: Rect2) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = rect.size
	shape.shape = box
	body.position = rect.get_center()
	body.add_child(shape)
	add_child(body)

func _register_input() -> void:
	var bindings := {"move_left":[KEY_A,KEY_LEFT],"move_right":[KEY_D,KEY_RIGHT],"jump":[KEY_W,KEY_SPACE],
		"aim_up":[KEY_W,KEY_UP],"move_down":[KEY_S,KEY_DOWN],"attack_light":[KEY_J],"attack_ranged":[KEY_K],
		"parry":[KEY_L],"dash_modifier":[KEY_SHIFT],"reset":[KEY_R],"debug_toggle":[KEY_F1],"training_attack_toggle":[KEY_F2]}
	for name in bindings:
		if not InputMap.has_action(name):
			InputMap.add_action(name)
		InputMap.action_erase_events(name)
		for key in bindings[name]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(name,event)

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := Control.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(panel)
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC"])
	panel.add_theme_font_override("font",font)
	var title := Label.new()
	title.text = "夜鸦  /  木桩训练场"
	title.position = Vector2(28,24)
	title.add_theme_font_size_override("font_size",24)
	panel.add_child(title)
	hud = Label.new()
	hud.position = Vector2(28,68)
	hud.add_theme_font_size_override("font_size",16)
	panel.add_child(hud)
	help_label = Label.new()
	help_label.position = Vector2(28,622)
	help_label.text = "A / D 跑动与转身   空格 / W 二段跳   J 地面 / 空中三连   按住 J 蓄力\nShift + J 冲刺斩   K 远射   W + J 挑飞   L 弹刀 / 按住格挡   F2 测试来袭开关   R 重置   F1 判定框   F3 返回试玩"
	help_label.add_theme_font_size_override("font_size",16)
	help_label.visible = bool(config.ui.get("showMoveHints",true))
	panel.add_child(help_label)
	var reset := Button.new()
	reset.text = "重置训练  R"
	reset.position = Vector2(990,26)
	reset.size = Vector2(122,38)
	reset.pressed.connect(_reset)
	panel.add_child(reset)
	var edit := Button.new()
	edit.text = "打开修改器"
	edit.position = Vector2(1130,26)
	edit.size = Vector2(122,38)
	edit.pressed.connect(_editor)
	panel.add_child(edit)

func _editor() -> void:
	var script := ProjectSettings.globalize_path("res://tools/battle-editor/start-editor.ps1")
	OS.create_process("powershell.exe",PackedStringArray(["-NoProfile","-ExecutionPolicy","Bypass","-WindowStyle","Hidden","-File",script]),false)

func _hit(target: Node2D, move: Resource, point: Vector2) -> void:
	if target == player:
		return
	total_hits += 1
	combo_hits = combo_hits+1 if combo_time>0 else 1
	combo_time = maxf(1.8,float(move.total_frames())/60+0.6)
	var dir := target.global_position-player.global_position
	if move.direction>0:
		dir = Vector2.UP
	camera.add_shake(move.shake_amount*(0.2 if move.is_ranged() else 1.0),dir)
	audio.play_impact(move)
	fx.spawn_hit(point.lerp(target.global_position,0.5),Feel.from_move(move),move.forces_launch)
	last_feedback = "命中 · 角色停顿 %d 帧 / 木桩 %d 帧" % [player.hitstop_frames,dummy.hitstop_frames]

func _damage(amount: float, _hp: float, point: Vector2) -> void:
	last_damage = amount
	fx.spawn_text(point.lerp(dummy.global_position,0.5),"-%.0f" % amount,amount)

func _wall_hit(speed: float, damage: float, point: Vector2, target: Node2D) -> void:
	last_damage = damage
	var dir := point-target.global_position
	camera.add_shake(10.0*float(config.feedback.get("shakeMultiplier",1)),dir)
	audio.play_wall(Feel.from_wall_speed(speed))
	fx.spawn_wall_slam(point,dir,Feel.from_wall_speed(speed))
	fx.spawn_text(point,"撞击 -%.0f" % damage,damage,true)
	last_feedback = "撞击 · 二次伤害 %.0f" % damage

func _parry(attacker: Node, point: Vector2) -> void:
	var dir := Vector2(player.facing,0)
	if attacker == self:
		dir = dummy.global_position - player.global_position
	elif attacker is Node2D:
		dir = (attacker as Node2D).global_position-player.global_position
	camera.add_shake(5.0*float(config.feedback.get("shakeMultiplier",1)),dir)
	audio.play_parry()
	fx.spawn_parry(point,dir)
	fx.spawn_text(point,"弹刀")
	last_feedback = "弹刀成功 · 零伤害"

func _block(_attacker: Node, point: Vector2) -> void:
	audio.play_block()
	fx.spawn_text(point, "格挡")
	last_feedback = "格挡成功"

func on_parried(_cause: Node = null) -> void:
	training_telegraph = 0.0
	training_attack_clock = 0.0

func _physics_process(delta: float) -> void:
	if not training_attacks or not is_instance_valid(player) or not is_instance_valid(dummy):
		return
	training_attack_clock += delta
	training_telegraph = maxf(0.0, 0.6 - fposmod(training_attack_clock, 2.2)) if training_attack_clock >= 2.2 else 0.0
	if training_attack_clock >= 2.8:
		training_attack_clock = 0.0
		training_telegraph = 0.0
		# Only the existing wooden dummy sends this optional, telegraphed test strike.
		if absf(player.global_position.x - dummy.global_position.x) <= 240.0 and absf(player.global_position.y - dummy.global_position.y) < 100.0:
			var strike: Resource = moves.light_1.duplicate()
			strike.damage = 6.0
			strike.knockback = 120.0
			strike.victim_hitstop_frames = 4
			var from_facing := 1 if player.global_position.x > dummy.global_position.x else -1
			var point := player.global_position + Vector2(0, -20)
			var blocked: bool = player.take_hit(strike, from_facing, point, 0.0, false, 1.0, self)
			if not blocked:
				fx.spawn_text(point, "测试命中 -6")
				last_feedback = "木桩测试命中 · 按 L 防守"

func _landed() -> void:
	audio.play_land(player.last_landing_heavy)
	fx.spawn_dust(player.global_position+Vector2(0,player.foot_offset))

func _knockdown() -> void:
	camera.add_shake(10.0*float(config.feedback.get("shakeMultiplier",1)))
	last_feedback = "木桩击倒"

func _reset() -> void:
	player.reset_state(Vector2(config.stage.spawn.player.x,config.stage.spawn.player.y - player.foot_offset))
	dummy.reset_state()
	player.get_node("Visual/ActorSprite").reset_presentation()
	for node in get_children():
		if node is Area2D:
			node.queue_free()
	last_damage = 0
	total_hits = 0
	combo_hits = 0
	combo_time = 0
	last_feedback = ""
	training_attack_clock = 0.0
	training_telegraph = 0.0
	fx.clear()
	audio.stop_all()
	camera.reset_shake()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("reset"):
		_reset()
	if event.is_action_pressed("debug_toggle"):
		debug_boxes = not debug_boxes
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		# 试玩版：F3 回到月下堤岸试玩关卡
		get_tree().change_scene_to_file.call_deferred("res://scenes/night_trial.tscn")
	if event.is_action_pressed("training_attack_toggle"):
		training_attacks = not training_attacks
		training_attack_clock = 0.0
		training_telegraph = 0.0
		last_feedback = "测试来袭已开启：靠近木桩，观察提示后按 L" if training_attacks else "测试来袭已关闭"

func _process(delta: float) -> void:
	if config.is_empty():
		return
	combo_time = maxf(0,combo_time-delta)
	if combo_time == 0:
		combo_hits = 0
	poll += delta
	if poll >= 0.5 and not reloading:
		poll = 0.0
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.runtime"))
		var marker := FileAccess.open("res://.runtime/game.json",FileAccess.WRITE)
		if marker != null:
			marker.store_string(JSON.stringify({"pid":OS.get_process_id(),"heartbeat":Time.get_unix_time_from_system()*1000,"projectRoot":ProjectSettings.globalize_path("res://"),"configHash":disk_hash,"playerScale":float(config.characters[0].sprite.get("displayScale",1)),"moveFrames":{"light_1":moves.light_1.total_frames(),"light_2":moves.light_2.total_frames(),"light_3":moves.light_3.total_frames()}}))
		var stop_path := "res://.runtime/stop-%d.request" % OS.get_process_id()
		if FileAccess.file_exists(stop_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(stop_path))
			DirAccess.remove_absolute(ProjectSettings.globalize_path("res://.runtime/game.json"))
			get_tree().quit()
			return
		var contents := FileAccess.get_file_as_string(Config.PATH)
		if bool(config.runtime.get("autoReload",true)) and contents.hash() != disk_hash and JSON.parse_string(contents) is Dictionary:
			reloading = true
			get_tree().reload_current_scene.call_deferred()
	var view: Sprite2D = player.get_node("Visual/ActorSprite")
	hud.text = "木桩 HP %.0f / %.0f    本次伤害 %.1f    命中 %d 次    累计伤害 %.1f" % [dummy.hp,dummy.max_hp,last_damage,total_hits,dummy.total_damage_taken]
	if bool(config.ui.get("showComboCounter",true)):
		hud.text += "\n连击 %d    浮空追击 %d    撞击 %d" % [combo_hits,dummy.juggle_count,dummy.wall_slam_count]
	if bool(config.ui.get("showDebugText",true)):
		var clip: Dictionary = view.setup.get("animations", {}).get(view.clip_name, {})
		hud.text += "\n动作 %s · 第 %d 帧    %s" % [clip.get("name", view.clip_name),view.frame_index+1,last_feedback]
	queue_redraw()

func _draw() -> void:
	if config.is_empty():
		return
	var ground := float(config.stage.bounds.floorY)
	draw_rect(Rect2(0,ground,1280,140),Color(config.art.get("ground","#292b38")))
	draw_line(Vector2(config.stage.bounds.left,ground),Vector2(config.stage.bounds.right,ground),Color("665776"),2)
	if debug_boxes and is_instance_valid(player):
		var shape: CollisionShape2D = player.get_node("MeleeHitbox/CollisionShape2D")
		var p: Vector2 = shape.global_position
		draw_rect(Rect2(p-shape.shape.size/2,shape.shape.size),Color(1,0.4,0.4,0.7),false,2)
		draw_rect(Rect2(dummy.global_position-Vector2(37,68),Vector2(74,136)),Color(0.4,0.9,0.8,0.7),false,2)
	if training_telegraph > 0.0 and is_instance_valid(dummy):
		draw_arc(dummy.global_position + Vector2(0, -85), 25.0, 0.0, TAU, 24, Color(1.0, 0.65, 0.2), 3.0)
