extends Node2D
## 试玩版主场景：夜晚堤岸一路往右走，遇到封印竞技场就开打，三处封印为一轮，无限循环。
## 设计说明见 docs/HANDOFF-试玩版.md §7（战斗）/ §6（场景）。
##
## 结构：
##   night_trial.gd（本文件）  世界、封印墙、镜头、玩家死亡重开、把战斗事件接到特效/音效/评价
##   encounter.gd              一处封印里的波次与刷怪
##   shade.gd                  敌人（影卒 / 甲影），失衡→眩晕→挑飞→浮空→方向终结→撞墙/连锁
##   style_meter.gd            连击数 + D/C/B/A/S 评价（纯逻辑）
##   combat_hud.gd             HUD（纯显示）
##   player_factory.gd         按 battle.json 搭玩家（与训练场同一套参数）

const Config := preload("res://scripts/core/configuration.gd")
const Factory := preload("res://scripts/night/player_factory.gd")
const Shade := preload("res://scripts/night/shade.gd")
const Encounter := preload("res://scripts/night/encounter.gd")
const Style := preload("res://scripts/night/style_meter.gd")
const Hud := preload("res://scripts/night/combat_hud.gd")
const Backdrop := preload("res://scripts/night/night_backdrop.gd")
const CameraScript := preload("res://scripts/presentation/camera_shake.gd")
const AudioFeedback := preload("res://scripts/presentation/audio_feedback.gd")
const ImpactFX := preload("res://scripts/presentation/impact_fx.gd")
const Feel := preload("res://scripts/core/feel_scale.gd")

const G := Shade.Kind.GRUNT
const B := Shade.Kind.BRUTE
const ARENA_HALF := 620.0           ## 封印竞技场半宽（全宽 1240，比画面窄 40，墙贴着画面边）
const FIRST_ARENA_X := 1500.0
const ARENA_SPACING := 1750.0       ## 相邻两处封印中心的距离（中间约 6 秒的散步路）
const TRIGGER_BEFORE := 240.0       ## 走到封印中心左边这么远就合上封印
const START_X := 300.0
const WAVE_HEAL := 25.0
const ROUND_HP_MUL := 1.2
const PARRY_WINDOW := 12

## 一轮 = 三处封印。每处封印 = 若干波。数据格式见 encounter.gd 顶部注释。
const ROUND: Array = [
	[
		{"label": "影卒来袭", "spawns": [G, G], "max_attackers": 1},
		{"label": "影卒围攻", "spawns": [G, G, G], "reinforce": [G], "reinforce_at": 1, "max_attackers": 2},
	],
	[
		{"label": "甲影现身", "spawns": [B, G, G], "max_attackers": 2},
	],
	[
		{"label": "影潮", "spawns": [G, B, G], "reinforce": [B, G], "reinforce_at": 2, "max_attackers": 2},
	],
]

enum Phase { EXPLORE, FIGHT, FALLEN }

var config: Dictionary
var moves: Dictionary
var player: CharacterBody2D
var camera: Camera2D
var audio: Node
var fx: Node2D
var hud: Control
var style: Style
var encounter: Node
var backdrop: Node2D                ## 夜景（节点 4 接入；为空时画占位地面）
var floor_y: float = 580.0
var phase: Phase = Phase.EXPLORE
var round_index: int = 0
var encounter_index: int = 0
var arena_center: float = 0.0
var seal_walls: Array = []
var seal_alpha: float = 0.0
var seal_x: Vector2 = Vector2.ZERO  ## 当前（或刚解除的）封印左右墙的 x
var back_wall: StaticBody2D
var back_limit: float = 40.0
var fallen_frames: int = 0
var debug_boxes: bool = false
var shake_mul: float = 1.0
var _hp_seen: float = 100.0
var _hints_done: Dictionary = {}
var _hint_queue: Array = []
var _round_time: float = 0.0
var _round_rank: int = 0
var _round_max_combo: int = 0
var _time: float = 0.0


func _ready() -> void:
	config = Config.read()
	if config.is_empty():
		push_error("无法读取统一战斗配置")
		return
	moves = Config.moves(config)
	floor_y = float(config.stage.bounds.floorY)
	shake_mul = float(config.feedback.get("shakeMultiplier", 1))
	RenderingServer.set_default_clear_color(Color("0a0f1f"))
	Factory.register_input()
	_build_world()
	player = Factory.build(config, moves, Vector2(START_X, floor_y))
	player.can_die = true
	player.getup_invuln_frames = 40
	player.root_motion_block_group = &"shade"
	player.launcher_cancel = true
	# 玩家被打飞后落地/撞墙不再额外扣血（训练场里落地也算"撞墙"，影卒一刀 8 实际会掉 26）。
	# 试玩版里玩家掉多少血 = 敌人这一刀的伤害，读得懂。撞击特效照放。
	player.wall_damage_scale = 0.0
	# 弹刀窗口 8 → 12 帧（只改试玩场景这一份角色数据，训练场和 battle.json 不变）。
	# 敌人在前摇结束后第 2 帧判定，所以"看到刀尖白星就按 L"正好落在窗口里。
	var ch: Dictionary = (player.get_meta("character", {}) as Dictionary).duplicate(true)
	if ch.has("sprite") and ch.sprite.has("guard"):
		ch.sprite.guard.parryWindowFrames = PARRY_WINDOW
		player.set_meta("character", ch)
	add_child(player)
	_hp_seen = player.hp
	_build_camera()
	_build_backdrop()
	audio = AudioFeedback.new()
	audio.configure(config.get("audio", {}))
	add_child(audio)
	fx = ImpactFX.new()
	fx.enabled = bool(config.feedback.get("effectsEnabled", true))
	fx.damage_numbers_enabled = bool(config.ui.get("showDamageNumbers", true))
	fx.z_index = 5
	add_child(fx)
	style = Style.new()
	_build_hud()
	encounter = Encounter.new()
	encounter.name = "Encounter"
	add_child(encounter)
	encounter.wave_started.connect(_on_wave_started)
	encounter.wave_cleared.connect(_on_wave_cleared)
	encounter.cleared.connect(_on_encounter_cleared)
	encounter.shade_spawned.connect(_on_shade_spawned)
	_connect_player()
	hud.banner("月下堤岸", "往右走，影子会在前面拦路", 3.2)
	_queue_hint(&"move", "A / D 移动   W / 空格 跳   J 攻击", 6.0)
	print("NIGHT_TRIAL_READY")


# ---------------------------------------------------------------- 搭建

func _build_world() -> void:
	var ground := StaticBody2D.new()
	ground.name = "Ground"
	ground.collision_layer = 1
	ground.collision_mask = 0
	var shape := CollisionShape2D.new()
	var plane := WorldBoundaryShape2D.new()       # 无限长地面：一直往右走也不会掉下去
	plane.normal = Vector2.UP
	shape.shape = plane
	ground.position = Vector2(0, floor_y)
	ground.add_child(shape)
	add_child(ground)
	back_wall = _make_wall(back_limit - 20.0)


func _make_wall(x: float) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(40, 1400)
	shape.shape = box
	body.position = Vector2(x, floor_y - 600.0)
	body.add_child(shape)
	add_child(body)
	return body


func _build_backdrop() -> void:
	var b: Node2D = Backdrop.new()
	b.name = "Backdrop"
	b.camera = camera
	b.floor_y = floor_y
	add_child(b)
	move_child(b, 0)
	if b.ok:
		backdrop = b
	else:
		b.queue_free()   # 图层缺失时退回占位背景，游戏照样能玩


func _build_camera() -> void:
	camera = Camera2D.new()
	camera.set_script(CameraScript)
	camera.position = Vector2(640, 360)
	camera.shake_decay = float(config.camera.get("shakeDecay", 7))
	camera.pixel_snap = float(config.camera.get("shakePixelSnap", 1))
	camera.max_shake = float(config.camera.get("maxShake", 42))
	add_child(camera)
	camera.make_current()
	camera.follow_target = player
	camera.follow_smoothing = float(config.camera.get("followLerp", 0.12)) * 60.0
	camera.arena_min = Vector2(back_limit - 30.0, 0)
	camera.arena_max = Vector2(1.0e9, 720)
	camera.global_position = Vector2(maxf(START_X, back_limit + 610.0), 360)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	hud = Hud.new()
	hud.style = style
	hud.help_visible = bool(config.ui.get("showMoveHints", true))
	hud.help_text = "A/D 移动   W/空格 跳（可二段）   J 攻击·按住蓄力   W+J 挑飞   K 远射   L 弹刀·按住格挡   Shift+J 冲刺斩\n空中：J 连斩   S+J 下砸   按住前方+J 横扫        H 隐藏说明   F3 木桩训练场   R 从头开始"
	layer.add_child(hud)


func _connect_player() -> void:
	player.hit_confirmed.connect(_on_player_hit)
	player.parry_success.connect(_on_parry)
	player.block_success.connect(func(_a: Node, point: Vector2): audio.play_parry(0.4); fx.spawn_text(point, "格挡"))
	player.move_started.connect(func(move: Resource, index: int): audio.play_swing_of(move, index))
	player.jumped.connect(audio.play_jump)
	player.landed.connect(func(): audio.play_land(); fx.spawn_dust(player.global_position + Vector2(0, player.foot_offset)))
	player.charge_started.connect(audio.play_charge_start)
	player.charge_released.connect(func(_f: int, charged: bool): audio.play_charge_release(charged))
	player.ranged_fired.connect(func(_p: Node): audio.play_ranged())
	player.plunge_landed.connect(_on_plunge_landed)
	player.wall_slam.connect(_on_player_wall)
	player.died.connect(_on_player_died)


# ---------------------------------------------------------------- 流程

func _physics_process(delta: float) -> void:
	if config.is_empty():
		return
	_time += delta
	match phase:
		Phase.EXPLORE:
			if player.global_position.x >= _next_center() - TRIGGER_BEFORE:
				_lock_arena()
		Phase.FIGHT:
			_round_time += delta
		Phase.FALLEN:
			fallen_frames -= 1
			if fallen_frames <= 0:
				_revive()
	var juggling := false
	for s in get_tree().get_nodes_in_group(&"shade"):
		if s.state == Shade.State.LAUNCHED or s.state == Shade.State.STUNNED:
			juggling = true
		if s.state == Shade.State.WINDUP and not _hints_done.has(&"parry"):
			_queue_hint(&"parry", "敌人亮橙光 = 马上出刀 → 看准按 L 弹刀（大量失衡）", 5.0)
	style.tick(delta, juggling)
	_round_max_combo = maxi(_round_max_combo, style.combo)
	_round_rank = maxi(_round_rank, style.rank_index())
	if player.hp > _hp_seen:
		_hp_seen = player.hp
	var target_alpha := 1.0 if phase != Phase.EXPLORE else 0.0
	seal_alpha = move_toward(seal_alpha, target_alpha, delta * 2.5)
	_pump_hints()


func _next_center() -> float:
	return FIRST_ARENA_X + float(encounter_index) * ARENA_SPACING


func _lock_arena() -> void:
	arena_center = _next_center()
	var left := arena_center - ARENA_HALF
	var right := arena_center + ARENA_HALF
	seal_x = Vector2(left, right)
	seal_walls = [_make_wall(left - 20.0), _make_wall(right + 20.0)]
	camera.arena_min = Vector2(arena_center - 640.0, 0)
	camera.arena_max = Vector2(arena_center + 640.0, 720)
	var waves: Array = ROUND[encounter_index % ROUND.size()]
	encounter.setup(waves, left, right, floor_y, player, self, pow(ROUND_HP_MUL, float(round_index)))
	encounter.start()
	phase = Phase.FIGHT
	camera.add_shake(4.0 * shake_mul)
	audio.play_wall(0.35)


func _unlock_arena() -> void:
	for w in seal_walls:
		if is_instance_valid(w):
			w.queue_free()
	seal_walls.clear()
	back_limit = arena_center - ARENA_HALF
	back_wall.position.x = back_limit - 20.0
	camera.arena_min = Vector2(back_limit - 30.0, 0)
	camera.arena_max = Vector2(1.0e9, 720)
	phase = Phase.EXPLORE


func _on_wave_started(idx: int, count: int, label: String) -> void:
	var sub := "第 %d / %d 波" % [idx + 1, count]
	if round_index > 0:
		sub += " · 第 %d 轮" % (round_index + 1)
	hud.banner(label, sub, 2.0)
	if not _hints_done.has(&"poise"):
		_queue_hint(&"poise", "连续命中会填满敌人头顶的金色【失衡条】→ 打满就眩晕", 5.5)


func _on_wave_cleared(idx: int, count: int) -> void:
	player.hp = minf(player.max_hp, player.hp + WAVE_HEAL)
	if idx < count - 1:
		hud.banner("清场", "生命 +%d · 下一波马上来" % int(WAVE_HEAL), 1.6)


func _on_encounter_cleared() -> void:
	_unlock_arena()
	encounter_index += 1
	if encounter_index % ROUND.size() == 0:
		_show_round_result()
		round_index += 1
		style.reset_stats()
		_round_time = 0.0
		_round_rank = style.rank_index()
		_round_max_combo = 0
	else:
		hud.banner("封印解除", "生命 +%d · 继续往右走" % int(WAVE_HEAL), 2.2)


func _show_round_result() -> void:
	var st: Dictionary = style.stats
	var grade := _round_rank
	if int(st.times_hit) >= 6:
		grade -= 1
	grade = clampi(grade, 0, 4)
	var mins := int(_round_time) / 60
	var secs := int(_round_time) % 60
	hud.show_result({
		"title": "第 %d 轮 结算" % (round_index + 1),
		"grade": Style.RANKS[grade],
		"lines": [
			["用时", "%d:%02d" % [mins, secs]],
			["最高连击", str(_round_max_combo)],
			["眩晕 / 挑飞", "%d / %d" % [st.stun, st.launch]],
			["下砸 / 撞墙 / 连锁", "%d / %d / %d" % [st.slam, st.wall, st.chain]],
			["弹刀", str(st.parry)],
			["受击", "%d 次（%d 伤害）" % [st.times_hit, int(st.damage_taken)]],
		],
		"footer": "继续往右走：下一轮影子更耐打（生命 ×%.2f）" % pow(ROUND_HP_MUL, float(round_index + 1)),
	}, 6.5)


func _on_player_died() -> void:
	phase = Phase.FALLEN
	fallen_frames = 150
	encounter.running = false
	style.take_damage(0.0)
	hud.banner("倒下了", "马上从这一波重新开始", 2.4)
	camera.add_shake(12.0 * shake_mul)


func _revive() -> void:
	encounter.restart_wave()
	player.reset_state(Vector2(arena_center - 320.0, floor_y - player.foot_offset))
	player.get_node("Visual/ActorSprite").reset_presentation()
	player.invuln_frames = 60
	_hp_seen = player.hp
	fx.clear()
	phase = Phase.FIGHT


# ---------------------------------------------------------------- 战斗事件 → 特效 / 音效 / 评价

func _on_shade_spawned(s: Node2D) -> void:
	s.damaged.connect(_on_shade_damaged.bind(s))
	s.broken.connect(_on_shade_broken.bind(s))
	s.launched_high.connect(_on_shade_launched)
	s.slam_impact.connect(_on_slam_impact)
	s.wall_slam.connect(_on_shade_wall.bind(s))
	s.chain_hit.connect(_on_chain_hit)
	s.parried.connect(_on_shade_parried)
	s.died.connect(_on_shade_died.bind(s))
	s.strike_landed.connect(_on_strike_landed.bind(s))
	fx.spawn_dust(Vector2(s.global_position.x, floor_y), 0.6)
	if s.kind == B and not _hints_done.has(&"brute"):
		_queue_hint(&"brute", "甲影出刀时有霸体（白光打不断）→ 弹刀 / 按住 J 蓄力斩 来破防", 6.0)


func _on_player_hit(target: Node2D, mv: Resource, point: Vector2) -> void:
	if target == player or not target.is_in_group(&"shade"):
		return
	style.add_hit(mv.id)
	if target.state == Shade.State.LAUNCHED:
		style.add_event(&"juggle")
	var dir := target.global_position - player.global_position
	if mv.direction > 0:
		dir = Vector2.UP
	camera.add_shake(mv.shake_amount * (0.2 if mv.is_ranged() else 1.0), dir)
	audio.play_impact(mv)
	fx.spawn_hit(point.lerp(target.global_position, 0.5), Feel.from_move(mv), mv.forces_launch)


func _on_shade_damaged(amount: float, _hp: float, point: Vector2, s: Node2D) -> void:
	fx.spawn_text(point.lerp(s.global_position + Vector2(0, -s.half_h), 0.5), "%.0f" % amount, amount)


func _on_shade_broken(point: Vector2, s: Node2D) -> void:
	style.add_event(&"stun")
	if s.kind == B:
		style.add_event(&"armor_break")
		hud.callout("破防·眩晕！", Color("ffe066"), 40)
	else:
		hud.callout("眩晕！", Color("ffe066"), 38)
	camera.add_shake(7.0 * shake_mul, Vector2.UP)
	audio.play_parry(0.9)
	fx.spawn_parry(point, Vector2.UP)
	_queue_hint(&"stun", "眩晕中！W + J 把它挑飞（眩晕中挑得更高）", 5.0, true)


func _on_shade_launched(point: Vector2) -> void:
	style.add_event(&"launch")
	hud.callout("挑飞！", Color("9fd8ff"), 36)
	fx.spawn_dust(Vector2(point.x, floor_y), 0.7)
	_queue_hint(&"air", "跳起来 J 空中连斩 · S + J 下砸 · 按住前方再 J 横扫撞墙", 6.0, true)


func _on_slam_impact(point: Vector2, strength: float) -> void:
	style.add_event(&"slam", clampf(strength, 0.5, 1.5))
	hud.callout("下砸！", Color("ffb054"), 40)
	camera.add_shake(15.0 * strength * shake_mul, Vector2.DOWN)
	audio.play_wall(0.9)
	fx.spawn_wall_slam(point, Vector2.DOWN, 1.0)
	fx.spawn_dust(point, 1.0)


func _on_shade_wall(speed: float, damage: float, point: Vector2, s: Node2D) -> void:
	var dir := point - s.global_position
	var strength := Feel.from_wall_speed(speed)
	fx.spawn_wall_slam(point, dir, strength)
	audio.play_wall(strength)
	camera.add_shake(10.0 * shake_mul * clampf(strength, 0.4, 1.2), dir)
	if damage > 0.0:
		style.add_event(&"wall")
		hud.callout("撞墙！", Color("ff8a5c"), 38)
		fx.spawn_text(point, "撞墙 %.0f" % damage, damage, true)
		_queue_hint(&"chain", "把敌人打向墙 / 别的影子：撞墙、连锁都会再吃一次伤害", 5.0, true)


func _on_chain_hit(level: int, point: Vector2) -> void:
	style.add_event(&"chain", 1.0 + 0.25 * float(level - 1))
	hud.callout("连锁 ×%d！" % level, Color("7fe3c8"), 36)
	fx.spawn_hit(point, 0.8, false)
	audio.play_hit(0.75)
	camera.add_shake(6.0 * shake_mul)


func _on_shade_parried(_by: Node, _point: Vector2) -> void:
	style.add_event(&"parry")
	hud.callout("弹刀！", Color("dfe8ff"), 38)


func _on_shade_died(s: Node2D) -> void:
	var airborne: bool = s.position.y < s.ground_y() - 10.0
	if airborne:
		style.add_event(&"air_kill")
		hud.callout("空中击破！", Color("ffd27a"), 32)
	else:
		style.add_event(&"kill")
	# 一波的最后一只：短暂慢动作，让终结那一下读得出来
	if encounter.alive_count() == 0 and encounter._queue.is_empty() and encounter._reinforce.is_empty():
		_slowmo(0.3, 0.45)


func _on_strike_landed(point: Vector2, s: Node2D) -> void:
	var dmg: float = _hp_seen - float(player.hp)
	_hp_seen = player.hp
	if dmg <= 0.01:
		return
	var combo_before := style.combo
	style.take_damage(dmg)
	if combo_before >= 5:
		hud.callout("连击中断", Color("8d96ab"), 26)
	hud.hurt()
	camera.add_shake(s.strike_move.shake_amount * shake_mul, player.global_position - s.global_position)
	audio.play_impact(s.strike_move)
	fx.spawn_hit(point, 0.6, false)
	fx.spawn_text(point + Vector2(0, -30), "-%.0f" % dmg, dmg)


func _on_parry(attacker: Node, point: Vector2) -> void:
	var dir := Vector2(player.facing, 0)
	if attacker is Node2D:
		dir = (attacker as Node2D).global_position - player.global_position
	camera.add_shake(5.0 * shake_mul, dir)
	audio.play_parry()
	fx.spawn_parry(point, dir)


func _on_plunge_landed(point: Vector2) -> void:
	fx.spawn_dust(point, 1.0)
	camera.add_shake(8.0 * shake_mul, Vector2.DOWN)
	audio.play_land()


func _on_player_wall(speed: float, damage: float, point: Vector2) -> void:
	var dir := point - player.global_position
	camera.add_shake(10.0 * shake_mul, dir)
	audio.play_wall(Feel.from_wall_speed(speed))
	fx.spawn_wall_slam(point, dir, Feel.from_wall_speed(speed))
	if damage > 0.0:
		fx.spawn_text(point, "撞击 -%.0f" % damage, damage, true)


func _slowmo(scale: float, seconds: float) -> void:
	Engine.time_scale = scale
	var t := get_tree().create_timer(seconds, true, false, true)
	t.timeout.connect(func(): Engine.time_scale = 1.0)


func _exit_tree() -> void:
	Engine.time_scale = 1.0


# ---------------------------------------------------------------- 提示

func _queue_hint(id: StringName, text: String, seconds: float, urgent: bool = false) -> void:
	if _hints_done.has(id):
		return
	_hints_done[id] = true
	if urgent:
		_hint_queue.push_front([text, seconds])
	else:
		_hint_queue.append([text, seconds])


func _pump_hints() -> void:
	if _hint_queue.is_empty() or hud._hint_t > 0.6:
		return
	var h: Array = _hint_queue.pop_front()
	hud.hint(h[0], h[1])


# ---------------------------------------------------------------- 输入 / HUD

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("reset"):
		Engine.time_scale = 1.0
		get_tree().reload_current_scene.call_deferred()
	elif event.is_action_pressed("debug_toggle"):
		debug_boxes = not debug_boxes
	elif event.is_action_pressed("toggle_help"):
		hud.help_visible = not hud.help_visible
	elif event.is_action_pressed("open_training"):
		Engine.time_scale = 1.0
		get_tree().change_scene_to_file.call_deferred("res://scenes/training.tscn")


func _process(_delta: float) -> void:
	if config.is_empty():
		return
	hud.player_hp = player.hp
	hud.player_max_hp = player.max_hp
	var enc_no := encounter_index % ROUND.size() + 1
	if phase == Phase.EXPLORE:
		var left := ROUND.size() - encounter_index % ROUND.size()
		hud.wave_text = "第 %d 轮 · 前方还有 %d 处封印" % [round_index + 1, left]
	else:
		hud.wave_text = "第 %d 轮 · 封印 %d/%d · 第 %d/%d 波" % [round_index + 1, enc_no, ROUND.size(),
				maxi(encounter.wave_index, 0) + 1, encounter.waves.size()]
	queue_redraw()


func _draw() -> void:
	if config.is_empty() or camera == null:
		return
	var c := camera.get_screen_center_position()
	if backdrop == null:
		# 占位：夜景（节点 4）接入前的纯色天空和地面
		draw_rect(Rect2(c.x - 700, c.y - 420, 1400, floor_y - (c.y - 420)), Color("101830"))
		draw_rect(Rect2(c.x - 700, floor_y, 1400, 300), Color("1b2033"))
		draw_line(Vector2(c.x - 700, floor_y), Vector2(c.x + 700, floor_y), Color("56607e"), 2)
	_draw_seals()
	if debug_boxes:
		var shape: CollisionShape2D = player.get_node("MeleeHitbox/CollisionShape2D")
		var p: Vector2 = shape.global_position
		draw_rect(Rect2(p - shape.shape.size / 2, shape.shape.size), Color(1, 0.4, 0.4, 0.7), false, 2)
		for s in get_tree().get_nodes_in_group(&"shade"):
			draw_rect(Rect2(s.global_position - Vector2(s.half_w, s.half_h), Vector2(s.half_w, s.half_h) * 2), Color(0.4, 0.9, 0.8, 0.7), false, 2)


## 封印墙：两道月光竖幕 + 往上飘的符纹
func _draw_seals() -> void:
	if seal_alpha <= 0.01:
		return
	for i in 2:
		var x: float = seal_x.x if i == 0 else seal_x.y
		var inward := 1.0 if i == 0 else -1.0
		var top := floor_y - 520.0
		for k in 10:
			var w := 4.0 + float(k) * 6.0
			var a := seal_alpha * 0.07 * (1.0 - float(k) / 10.0)
			var rx := x if inward > 0.0 else x - w
			draw_rect(Rect2(rx, top, w, floor_y - top), Color(0.75, 0.85, 1.0, a))
		draw_line(Vector2(x, top), Vector2(x, floor_y), Color(0.85, 0.92, 1.0, 0.55 * seal_alpha), 2.0)
		for r in 7:
			var phase_y := fposmod(_time * 60.0 + float(r) * 74.0, 520.0)
			var y := floor_y - phase_y
			var s := 5.0 + 2.0 * sin(_time * 3.0 + float(r))
			var p := Vector2(x + inward * 10.0, y)
			var col := Color(1.0, 0.86, 0.55, seal_alpha * 0.7 * sin(PI * phase_y / 520.0))
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, -s), p + Vector2(s * 0.6, 0), p + Vector2(0, s), p + Vector2(-s * 0.6, 0)]), col)
