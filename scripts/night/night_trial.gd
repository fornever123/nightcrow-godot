extends Node2D
## 试玩版主场景：夜晚堤岸一路往右走，遇到封印竞技场就开打，三处封印为一轮，无限循环。
## 设计说明见 docs/HANDOFF-试玩版.md §7（战斗）/ §6（场景）。
##
## 结构：
##   night_trial.gd（本文件）  世界、封印墙、镜头、玩家死亡重开、把战斗事件接到特效/音效/评价
##   encounter.gd              一处封印里的波次与刷怪
##   terrain.gd                多层地形（单向平台 + 实心石台），每处封印一段布局
##   shade.gd                  敌人（影卒 / 甲影 / 影弓 / 影爆），连续击退→挑飞→浮空→方向终结→撞墙/连锁（2026-10-21 起无失衡/眩晕）
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
const Terrain := preload("res://scripts/night/terrain.gd")
const NightLight := preload("res://scripts/night/night_light.gd")
const CharLight := preload("res://assets/shaders/char_light.gdshader")
const RIM_PX := 2.5                 ## 角色月光边缘光宽度（屏幕像素）
const OUTLINE_PX := 2.0             ## 角色深色描边宽度（屏幕像素，第三轮方案1）
## 镜头缩放（第三轮节点 15）：0.5 = 世界 2 单位 = 屏幕 1 像素，角色在屏幕上约 85px 高。
## 只缩镜头、不缩世界：判定、速度、跳高、击退和身高的比例全都不变。
const ZOOM := 0.5
## 镜头中心固定的世界 y：地面 floor_y=580 在屏幕上还是第 580 行（(580−140)×0.5+360）
const CAM_Y := 140.0
const SHADOW_COL := Color(0.01, 0.015, 0.045)
const CameraScript := preload("res://scripts/presentation/camera_shake.gd")
const AudioFeedback := preload("res://scripts/presentation/audio_feedback.gd")
const ImpactFX := preload("res://scripts/presentation/impact_fx.gd")
const Feel := preload("res://scripts/core/feel_scale.gd")
const UltFx := preload("res://scripts/night/ult_fx.gd")
## 大招能量：打中敌人按伤害 ×ULT_GAIN_HIT，自己挨打按掉血 ×ULT_GAIN_HURT（满 100）
const ULT_GAIN_HIT := 0.8
const ULT_GAIN_HURT := 1.2

const G := Shade.Kind.GRUNT
const B := Shade.Kind.BRUTE
const A := Shade.Kind.ARCHER        ## 影弓（第四轮）
const X := Shade.Kind.BOMBER        ## 影爆（第四轮）
## 第三轮：镜头缩到 0.5 后画面宽 2560 世界单位，竞技场跟着变宽（全宽 2400，墙贴着画面边），
## 里面摆多层地形（terrain.gd 的 SECTIONS，坐标相对封印中心）
const ARENA_HALF := 1200.0
const FIRST_ARENA_X := 2500.0
const ARENA_SPACING := 3600.0       ## 相邻两处封印中心的距离（中间约 3.5 秒的路，路上也有能跳的台子）
const TRIGGER_BEFORE := 1000.0      ## 走到封印中心左边这么远就合上封印（= 进了竞技场 200）
const START_X := 300.0
const WAVE_HEAL := 25.0
const ROUND_HP_MUL := 1.2
const PARRY_WINDOW := 12

## 一轮 = 三处封印。每处封印 = 若干波。数据格式见 encounter.gd 顶部注释。
## 第四轮：加入影弓（A）和影爆（X）。远程影和近战影各算各的出手名额。
const ROUND: Array = [
	[
		{"label": "影卒来袭", "spawns": [G, G], "max_attackers": 1},
		{"label": "冷箭", "spawns": [G, A, G], "reinforce": [G], "reinforce_at": 1, "max_attackers": 2},
	],
	[
		{"label": "甲影与影爆", "spawns": [B, G, X], "max_attackers": 2},
	],
	[
		{"label": "影潮", "spawns": [G, B, A], "reinforce": [X, G], "reinforce_at": 2, "max_attackers": 2},
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
var terrain: Node2D                 ## 多层地形（第三轮节点 17）
var post: CanvasLayer               ## 光影后期（辉光、月光光柱、调色、暗角；night_light.gd）
var light_mat: ShaderMaterial       ## 角色环境光（节点 5；夜景缺失时为空）
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
var _plunge_frame: int = -100
var _hints_done: Dictionary = {}
var _hint_queue: Array = []
var _round_time: float = 0.0
var _round_rank: int = 0
var _round_max_combo: int = 0
var _time: float = 0.0
var ult_fx: Node2D
var _ult_hint_shown := false
var _ult_collect := false         ## 旧分镜大招用；千刃直接冒伤害数字，恒为 false（大招砍死的影照常放击杀特效）
var _ult_targets: Array = []      ## 千刃：起手时屏幕里的影 {node, cuts}
var _ult_dir: int = 1             ## 千刃：当前往哪边斩
var _ult_left: float = 0.0
var _ult_right: float = 0.0
var _ult_anchor: Node2D           ## 千刃期间镜头钉在这里
const ULT_PASS_OVERSHOOT := 130.0 ## 千刃：瞬移到目标另一侧多远


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
	# 多层地形：玩家也撞单向平台那一层；站在上面按住 S 再按跳 = 往下穿
	player.collision_mask = 1 | Terrain.ONE_WAY_LAYER
	player.one_way_mask = Terrain.ONE_WAY_LAYER
	player.can_die = true
	player.getup_invuln_frames = 40
	# 第四轮：小兵的轻击（击退 < 350）落地就站稳，只有重击/炸弹才会被打倒
	player.soft_knock_threshold = 350.0
	player.hard_down_frames = 20
	player.root_motion_block_group = &"shade"
	player.ult_enabled = true
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
	_build_lighting()
	audio = AudioFeedback.new()
	audio.configure(config.get("audio", {}))
	add_child(audio)
	fx = ImpactFX.new()
	fx.enabled = bool(config.feedback.get("effectsEnabled", true))
	fx.damage_numbers_enabled = bool(config.ui.get("showDamageNumbers", true))
	fx.z_index = 5
	fx.text_scale = 1.0 / ZOOM
	fx.fx_scale = 1.0
	fx.floor_at = func(x: float, y: float) -> float: return terrain.support_y(x, y)
	add_child(fx)
	fx.track_player(player)
	fx.track_glow(player.get_node("Visual/ActorSprite"))
	ult_fx = UltFx.new()
	ult_fx.fx = fx
	ult_fx.player = player
	add_child(ult_fx)
	style = Style.new()
	_build_hud()
	ult_fx.hud = hud
	ult_fx.sheathed.connect(func(_p: Vector2): audio.play_block())
	_ult_anchor = Node2D.new()
	_ult_anchor.name = "UltCameraAnchor"
	add_child(_ult_anchor)
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
	terrain = Terrain.new()
	terrain.name = "Terrain"
	terrain.floor_y = floor_y
	terrain.z_index = -70           # 背景像素化那层（−75）之后：地形和角色一样清楚
	add_child(terrain)
	_ensure_terrain(0)


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


## 角色环境光（节点 5，见 HANDOFF §12）：只给试玩关卡的角色挂材质，训练场不受影响
func _build_lighting() -> void:
	if backdrop == null:
		return
	post = NightLight.new()
	post.name = "PostLight"
	post.stage = self
	add_child(post)
	light_mat = ShaderMaterial.new()
	light_mat.shader = CharLight
	light_mat.set_shader_parameter("ol_width", OUTLINE_PX)
	light_mat.set_shader_parameter("punch_con", 1.08)
	light_mat.set_shader_parameter("punch_sat", 1.12)
	light_mat.set_shader_parameter("hq_max_taps", 8)
	(player.get_node("Visual/ActorSprite") as Sprite2D).material = light_mat


func _update_lighting() -> void:
	if light_mat == null:
		return
	var spr: Sprite2D = player.get_node("Visual/ActorSprite")
	var gt := spr.get_global_transform()
	light_mat.set_shader_parameter("flip", -1.0 if gt.x.x < 0.0 else 1.0)
	# 贴图像素 ↔ 屏幕像素：精灵全局缩放 × 镜头缩放
	var sx := maxf(gt.x.length() * camera.zoom.x, 0.0001)
	var sy := maxf(gt.y.length() * camera.zoom.y, 0.0001)
	light_mat.set_shader_parameter("px", Vector2(RIM_PX / sx, RIM_PX / sy))
	light_mat.set_shader_parameter("spx", Vector2(1.0 / sx, 1.0 / sy))
	var l: Vector3 = _lamp_at(player.global_position + Vector2(0, player.foot_offset - 60.0))
	light_mat.set_shader_parameter("warm", l.x * 0.85)
	light_mat.set_shader_parameter("warm_dir", Vector2(l.y, l.z))
	for s in get_tree().get_nodes_in_group(&"shade"):
		s.lamp = _lamp_at(s.global_position)


## 堤岸石灯笼 + 亭子檐下灯笼，取更亮的那一盏
func _lamp_at(p: Vector2) -> Vector3:
	var l: Vector3 = backdrop.lantern_light(p)
	if terrain != null:
		var l2: Vector3 = terrain.lantern_light(p)
		if l2.x > l.x:
			l = l2
	return l


func _build_camera() -> void:
	camera = Camera2D.new()
	camera.set_script(CameraScript)
	camera.position = Vector2(640, CAM_Y)
	camera.zoom = Vector2(ZOOM, ZOOM)
	camera.lock_y = CAM_Y
	camera.position_snap = 1.0       # 镜头停在整屏幕像素上：像素风地形的格子不会忽宽忽窄
	camera.shake_decay = float(config.camera.get("shakeDecay", 7))
	# 噪声与方向偏置沿用 C 盘参考；缩放补偿后保持完整屏幕震幅。
	camera.pixel_snap = 2.0 * float(config.camera.get("shakePixelSnap", 1))
	camera.shake_world_scale = 1.0 / ZOOM
	camera.max_shake = float(config.camera.get("maxShake", 42))
	add_child(camera)
	camera.make_current()
	camera.follow_target = player
	camera.follow_smoothing = float(config.camera.get("followLerp", 0.12)) * 60.0
	camera.look_ahead = float(config.camera.get("lookAhead", 0.0)) / ZOOM
	camera.arena_min = Vector2(back_limit - 30.0, 0)
	camera.arena_max = Vector2(1.0e9, 720)
	camera.global_position = Vector2(maxf(START_X, back_limit - 30.0 + 640.0 / ZOOM), CAM_Y)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	hud = Hud.new()
	hud.style = style
	hud.help_visible = bool(config.ui.get("showMoveHints", true))
	hud.help_text = "A/D 移动   W/空格 跳   S+空格 跳下木台   J 攻击·按住蓄力   W+J/J+W 跳起上挑   K 远射   L 格挡/弹刀   Shift+J 冲刺斩   J+K 大招\n空格取消出招（受击/倒地/大招除外）·空中命中慢坠   S+J 下砸·前+J 横扫   H 隐藏   F3 木桩   R 重开"
	layer.add_child(hud)


func _connect_player() -> void:
	player.hit_confirmed.connect(_on_player_hit)
	player.parry_success.connect(_on_parry)
	player.block_success.connect(_on_block)
	# 冲刺斩起步“呼”一声；刀风统一走 swing_cue（判定帧前 3 帧，音画对齐）
	player.move_started.connect(func(move: Resource, _index: int):
		if move == player.dash_move or move == player.dash_left_move:
			audio.play_dash()
			fx.spawn_dash(player.global_position + Vector2(0, player.foot_offset), player.facing)
			fx.mark_dash_start(player.global_position)
			fx.start_ghosts(player.get_node("Visual/ActorSprite"), 0.45))
	player.swing_cue.connect(func(move: Resource, index: int): audio.play_swing_of(move, index))
	player.jumped.connect(func(is_double: bool):
		audio.play_jump(is_double)
		fx.spawn_jump(player.global_position + Vector2(0, player.foot_offset), is_double))
	player.landed.connect(func():
		audio.play_land(player.last_landing_heavy)
		if Engine.get_physics_frames() - _plunge_frame > 2:
			fx.spawn_land(player.global_position + Vector2(0, player.foot_offset), player.last_landing_heavy))
	player.charge_started.connect(audio.play_charge_start)
	player.charge_released.connect(func(_f: int, charged: bool): audio.play_charge_release(charged))
	player.ranged_fired.connect(func(p: Node):
		audio.play_ranged()
		if p is Node2D:
			fx.spawn_muzzle((p as Node2D).global_position, Vector2(player.facing, 0)))
	player.plunge_landed.connect(_on_plunge_landed)
	player.wall_slam.connect(_on_player_wall)
	player.died.connect(_on_player_died)
	player.ult_started.connect(_on_ult_started)
	player.ult_hit.connect(_on_ult_hit)
	player.ult_pass.connect(_on_ult_pass)
	player.ult_finished.connect(_ult_release_camera)
	audio.attach_player(player)


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
	if not _hints_done.has(&"drop") and player.is_on_floor() and player.standing_on_one_way():
		_queue_hint(&"drop", "站在木台 / 屋檐上：按住 S 再按空格 = 跳下去", 5.0)
	var juggling := false
	for s in get_tree().get_nodes_in_group(&"shade"):
		if s.state == Shade.State.LAUNCHED or s.state == Shade.State.STUNNED:
			juggling = true
		if s.state == Shade.State.WINDUP and not _hints_done.has(&"parry"):
			_queue_hint(&"parry", "敌人亮橙光 = 马上出刀 → 看准按 L 弹刀（命中后会停住）", 5.0)
	style.tick(delta, juggling)
	_round_max_combo = maxi(_round_max_combo, style.combo)
	_round_rank = maxi(_round_rank, style.rank_index())
	if player.hp > _hp_seen:
		_hp_seen = player.hp
	elif player.hp < _hp_seen - 0.01 and phase == Phase.FIGHT:
		_on_player_hurt(_hp_seen - player.hp, player.global_position + Vector2(0, -20))
	var target_alpha := 1.0 if phase != Phase.EXPLORE else 0.0
	seal_alpha = move_toward(seal_alpha, target_alpha, delta * 2.5)
	_pump_hints()


func _next_center() -> float:
	return _center_of(encounter_index)


func _center_of(i: int) -> float:
	return FIRST_ARENA_X + float(i) * ARENA_SPACING


## 第 i 处和下一处的地形都生成好；走远了的拆掉
func _ensure_terrain(i: int) -> void:
	terrain.ensure_section(i, _center_of(i))
	terrain.ensure_section(i + 1, _center_of(i + 1))
	terrain.free_sections_before(i - 1)


func _lock_arena() -> void:
	arena_center = _next_center()
	var left := arena_center - ARENA_HALF
	var right := arena_center + ARENA_HALF
	seal_x = Vector2(left, right)
	seal_walls = [_make_wall(left - 20.0), _make_wall(right + 20.0)]
	camera.arena_min = Vector2(arena_center - ARENA_HALF - 40.0, 0)
	camera.arena_max = Vector2(arena_center + ARENA_HALF + 40.0, 720)
	var waves: Array = ROUND[encounter_index % ROUND.size()]
	encounter.setup(waves, left, right, floor_y, player, self, pow(ROUND_HP_MUL, float(round_index)))
	_ensure_terrain(encounter_index)
	encounter.terrain = terrain
	encounter.spawn_points = terrain.spawn_points(encounter_index, arena_center)
	encounter.start()
	phase = Phase.FIGHT
	camera.add_shake(4.0 * shake_mul)
	audio.play_seal()


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
	if not _hints_done.has(&"knockback"):
		_queue_hint(&"knockback", "连续命中会逐步增强击退；落地后重新计算", 5.5)


func _on_wave_cleared(idx: int, count: int) -> void:
	player.hp = minf(player.max_hp, player.hp + WAVE_HEAL)
	if idx < count - 1:
		audio.play_clear()
		hud.banner("清场", "生命 +%d · 下一波马上来" % int(WAVE_HEAL), 1.6)


func _on_encounter_cleared() -> void:
	audio.play_clear()
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
			["挑飞", "%d" % st.launch],
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
	audio.play_die()
	camera.add_shake(12.0 * shake_mul)


func _revive() -> void:
	encounter.restart_wave()
	var rx := arena_center - 320.0
	player.reset_state(Vector2(rx, terrain.solid_top(rx, 30.0) - player.foot_offset))
	player.get_node("Visual/ActorSprite").reset_presentation()
	player.invuln_frames = 60
	_hp_seen = player.hp
	fx.clear()
	ult_fx.clear()
	_ult_release_camera()
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
	s.windup_started.connect(audio.play_shade_windup)
	s.ui_scale = 1.0 / ZOOM
	if s.kind == A:
		s.strike_started.connect(func(_h: bool): audio.play_shade_shot())
	else:
		s.strike_started.connect(audio.play_shade_swing)
	s.guarded.connect(_on_shade_guarded.bind(s))
	s.guard_broken.connect(_on_shade_guard_broken)
	s.dodged.connect(func(_p: Vector2): fx.spawn_dust(Vector2(s.global_position.x, s.feet_y()), 0.5))
	s.friendly_hit.connect(_on_friendly_hit)
	s.projectile_spawned.connect(_on_projectile)
	fx.spawn_dust(Vector2(s.global_position.x, s.feet_y()), 0.6)
	if s.kind == B and not _hints_done.has(&"brute"):
		_queue_hint(&"brute", "甲影出刀时有霸体（白光打不断）→ 弹刀 / 按住 J 蓄力斩 来破防", 6.0)
	elif s.kind == A and not _hints_done.has(&"archer"):
		_queue_hint(&"archer", "影弓：橙色瞄准线变粗 = 要放箭 → 按 L 弹回去，或者一刀把箭砍回去", 6.0)
	elif s.kind == X and not _hints_done.has(&"bomber"):
		_queue_hint(&"bomber", "影爆扔炸弹：落地马上炸（同伴也炸）→ 砍它一刀把炸弹打回去", 6.0)


func _on_player_hit(target: Node2D, mv: Resource, point: Vector2) -> void:
	if target != player and target.is_in_group(&"shade_projectile"):
		# 一刀把影矢 / 炸弹砍回去
		camera.add_shake(6.0 * shake_mul, Vector2(player.facing, 0))
		audio.play_deflect()
		fx.spawn_deflect(point, Vector2(player.facing, 0))
		hud.callout("打回去！", Color("ffe08a"), 34)
		return
	if target == player or not target.is_in_group(&"shade"):
		return
	style.add_hit(mv.id)
	player.add_ult_energy(clampf(mv.damage, 3.0, 30.0) * ULT_GAIN_HIT)
	if target.state == Shade.State.LAUNCHED:
		style.add_event(&"juggle")
	var dir := target.global_position - player.global_position
	if mv.direction > 0:
		dir = Vector2.UP
	# 招式分档震幅已在 Config.moves 中乘过全局倍率，这里不重复相乘。
	if mv.shake_amount > 0.0:
		camera.add_shake(mv.shake_amount * (0.2 if mv.is_ranged() else 1.0), dir)
	audio.play_impact(mv)
	var is_dash: bool = mv == player.dash_move or mv == player.dash_left_move
	fx.spawn_hit(point.lerp(target.global_position, 0.5), ImpactFX.power_of(mv), mv.direction > 0, dir, is_dash, mv.id)
	if is_dash:
		fx.spawn_dash_hit(point.lerp(target.global_position, 0.5), player.facing)


func _on_shade_damaged(amount: float, _hp: float, point: Vector2, s: Node2D) -> void:
	fx.spawn_text(point.lerp(s.global_position + Vector2(0, -s.half_h), 0.5), "%.0f" % amount, amount)


func _on_shade_broken(point: Vector2, s: Node2D) -> void:
	style.add_event(&"stun")
	if s.kind == B:
		style.add_event(&"armor_break")
		hud.callout("破防·眩晕！", Color("ffe066"), 40)
	else:
		hud.callout("眩晕！", Color("ffe066"), 38)
	camera.add_shake(12.0 * shake_mul, Vector2.UP)
	audio.play_stun()
	fx.spawn_break(point)
	_queue_hint(&"stun", "眩晕中！W + J 把它挑飞（眩晕中挑得更高）", 5.0, true)


func _on_shade_launched(point: Vector2) -> void:
	style.add_event(&"launch")
	hud.callout("挑飞！", Color("9fd8ff"), 36)
	audio.play_launch()
	fx.spawn_launch(point)
	fx.spawn_dust(Vector2(point.x, terrain.support_y(point.x, point.y)), 0.7)
	_queue_hint(&"air", "W后按J或J后按W：跳起上挑！空中 J 连斩，命中短暂慢坠 · S+J 下砸 · 前+J 横扫撞墙", 6.0, true)


func _on_slam_impact(point: Vector2, strength: float) -> void:
	style.add_event(&"slam", clampf(strength, 0.5, 1.5))
	hud.callout("下砸！", Color("ffb054"), 40)
	camera.add_shake(22.0 * strength * shake_mul, Vector2.DOWN)
	audio.play_slam(strength)
	fx.spawn_ground_slam(point, clampf(strength, 0.6, 1.4))


func _on_shade_wall(speed: float, damage: float, point: Vector2, s: Node2D) -> void:
	var dir := point - s.global_position
	var strength := Feel.from_wall_speed(speed)
	fx.spawn_wall_slam(point, dir, strength)
	audio.play_wall(strength)
	camera.add_shake(16.0 * shake_mul * clampf(strength, 0.4, 1.2), dir)
	if damage > 0.0 or s.state == Shade.State.DEAD:
		style.add_event(&"wall")
		hud.callout("撞墙！", Color("ff8a5c"), 38)
		if damage > 0.0:
			fx.spawn_text(point, "撞墙 %.0f" % damage, damage, true)
		_queue_hint(&"chain", "把敌人打向墙 / 别的影子：撞墙、连锁都会再吃一次伤害", 5.0, true)


func _on_chain_hit(level: int, point: Vector2) -> void:
	style.add_event(&"chain", 1.0 + 0.25 * float(level - 1))
	hud.callout("连锁 ×%d！" % level, Color("7fe3c8"), 36)
	fx.spawn_hit(point, 0.8, false)
	audio.play_chain(level)
	camera.add_shake(10.0 * shake_mul)


func _on_shade_guarded(point: Vector2, s: Node2D) -> void:
	camera.add_shake(5.0 * shake_mul, s.global_position - player.global_position)
	audio.play_block()
	fx.spawn_block(point, s.global_position - player.global_position)
	fx.spawn_text(point + Vector2(0, -20), "挡")
	_queue_hint(&"guard", "敌人举刀格挡（身前蓝弧）→ 第三刀 / 按住 J 蓄力 / W+J / Shift+J 能砸开，或者绕到背后", 6.0, true)


func _on_shade_guard_broken(point: Vector2) -> void:
	camera.add_shake(10.0 * shake_mul, Vector2.UP)
	style.add_event(&"guard_break")
	hud.callout("破招！", Color("ffe066"), 34)
	audio.play_guard_break()
	fx.spawn_break(point)


func _on_friendly_hit(point: Vector2) -> void:
	camera.add_shake(5.0 * shake_mul, point - player.global_position)
	style.add_event(&"friendly")
	hud.callout("误伤！", Color("9fe0b0"), 32)


## 影弓的箭 / 影爆的炸弹出手：接上它们的事件
func _on_projectile(node: Node2D) -> void:
	if node.has_signal(&"exploded"):
		node.exploded.connect(_on_bomb_exploded)
	if node.has_signal(&"struck"):
		node.struck.connect(func(t: Node, point: Vector2, friendly: bool):
			if friendly and t.is_in_group(&"shade"):
				style.add_event(&"reflect")
			if t.is_in_group(&"shade"):
				camera.add_shake((8.0 if friendly else 4.0) * shake_mul, t.global_position - point))


func _on_bomb_exploded(point: Vector2, friendly: bool) -> void:
	camera.add_shake(18.0 * shake_mul, Vector2.UP)
	audio.play_bomb(1.0)
	fx.spawn_explosion(point, 1.0)
	if friendly:
		style.add_event(&"reflect")
		hud.callout("炸回去！", Color("ffb054"), 36)


func _on_shade_parried(_by: Node, _point: Vector2) -> void:
	style.add_event(&"parry")
	hud.callout("弹刀！", Color("dfe8ff"), 38)


func _on_shade_died(s: Node2D) -> void:
	camera.add_shake(6.0 * shake_mul, s.global_position - player.global_position)
	audio.play_shade_die()
	if not _ult_collect:          # 大招砍死的：等它爆开（ult_fx 的余波）再炸，不在这里炸
		fx.spawn_kill(s.global_position)
	fx.track_dissolve(s)
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
	if dmg <= 0.01:
		_hp_seen = player.hp
		return
	_on_player_hurt(dmg, point, s.strike_move.shake_amount, player.global_position - s.global_position, s.kind == B)


## 玩家掉血（近战刀 / 影矢 / 炸弹都走这里）
func _on_player_hurt(dmg: float, point: Vector2, shake: float = 3.0, dir: Vector2 = Vector2.ZERO, heavy: bool = false) -> void:
	_hp_seen = player.hp
	player.add_ult_energy(dmg * ULT_GAIN_HURT)
	var combo_before := style.combo
	style.take_damage(dmg)
	if combo_before >= 5:
		hud.callout("连击中断", Color("8d96ab"), 26)
	hud.hurt()
	if shake > 0.0:
		camera.add_shake(shake * shake_mul, dir)
	audio.play_hurt(0.8 if heavy or dmg >= 12.0 else 0.4)
	fx.spawn_hurt(point, dir, heavy or dmg >= 12.0)
	fx.spawn_text(point + Vector2(0, -30), "-%.0f" % dmg, dmg)


func _on_parry(attacker: Node, point: Vector2) -> void:
	var dir := Vector2(player.facing, 0)
	if attacker is Node2D:
		dir = (attacker as Node2D).global_position - player.global_position
	camera.add_shake(10.0 * shake_mul, dir)
	audio.play_parry()
	fx.spawn_parry(point, dir)


func _on_block(attacker: Node, point: Vector2) -> void:
	camera.add_shake(4.0 * shake_mul, Vector2(player.facing, 0))
	audio.play_block()
	fx.spawn_block(point, (attacker as Node2D).global_position - player.global_position if attacker is Node2D else Vector2(player.facing, 0))
	fx.spawn_text(point, "格挡")


func _on_plunge_landed(point: Vector2) -> void:
	_plunge_frame = Engine.get_physics_frames()
	fx.spawn_ground_slam(point, 0.8)
	camera.add_shake(14.0 * shake_mul, Vector2.DOWN)
	# 声音交给紧接着的 landed（重落地）


func _on_player_wall(speed: float, damage: float, point: Vector2) -> void:
	var dir := point - player.global_position
	camera.add_shake(16.0 * shake_mul, dir)
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
	hud.ult_frac = player.ult_energy / maxf(player.ult_max, 1.0)
	if player.ult_ready() and not _ult_hint_shown:
		_ult_hint_shown = true
		_queue_hint(&"ult", "能量满了！J + K 一起按：大招（全屏斩）", 6.0, true)
	var enc_no := encounter_index % ROUND.size() + 1
	if phase == Phase.EXPLORE:
		var left := ROUND.size() - encounter_index % ROUND.size()
		hud.wave_text = "第 %d 轮 · 前方还有 %d 处封印" % [round_index + 1, left]
	else:
		hud.wave_text = "第 %d 轮 · 封印 %d/%d · 第 %d/%d 波" % [round_index + 1, enc_no, ROUND.size(),
				maxi(encounter.wave_index, 0) + 1, encounter.waves.size()]
	_update_lighting()
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
	_draw_player_shadow()
	_draw_seals()
	if debug_boxes:
		var shape: CollisionShape2D = player.get_node("MeleeHitbox/CollisionShape2D")
		var p: Vector2 = shape.global_position
		draw_rect(Rect2(p - shape.shape.size / 2, shape.shape.size), Color(1, 0.4, 0.4, 0.7), false, 2)
		for s in get_tree().get_nodes_in_group(&"shade"):
			draw_rect(Rect2(s.global_position - Vector2(s.half_w, s.half_h), Vector2(s.half_w, s.half_h) * 2), Color(0.4, 0.9, 0.8, 0.7), false, 2)


## 玩家脚下的影子：月亮在右上方 → 影子略偏左；离地越高越小越淡；
## 靠近灯笼时再加一道背向灯笼拉长的淡影。（影卒的影子在 shade.gd 里自己画）
func _draw_player_shadow() -> void:
	if player == null or player.state == player.State.DEAD:
		return
	var x: float = player.global_position.x
	var foot: float = player.global_position.y + player.foot_offset
	# 影子落在脚下最高的那个面上（平台 / 石台 / 地面）
	var gy := floor_y if terrain == null else float(terrain.support_y(x, foot, 20.0))
	var air := clampf((gy - foot) / 300.0, 0.0, 1.0)
	var k := 1.0 - air * 0.5
	_soft_ellipse(Vector2(x - 5.0, gy + 3.0), Vector2(60.0 * k, 6.5 * k), 0.45 * (1.0 - air * 0.8))   # 外圈淡影
	_soft_ellipse(Vector2(x - 3.0, gy + 2.0), Vector2(40.0 * k, 3.5 * k), 0.8 * (1.0 - air))          # 贴地接触影
	if backdrop != null and gy >= floor_y - 1.0:
		var l: Vector3 = backdrop.lantern_light(Vector2(x, floor_y - 60.0))
		if l.x > 0.03:
			var away := -1.0 if l.y > 0.0 else 1.0
			_soft_ellipse(Vector2(x + away * (40.0 + 40.0 * l.x), gy + 3.0), Vector2(56.0 + 50.0 * l.x, 5.0), 0.35 * l.x * (1.0 - air))


func _soft_ellipse(c: Vector2, r: Vector2, alpha: float) -> void:
	if alpha <= 0.005:
		return
	for i in 3:
		var k := 1.0 - float(i) * 0.25
		var pts := PackedVector2Array()
		for j in 28:
			var a := TAU * float(j) / 28.0
			pts.append(c + Vector2(cos(a) * r.x * k, sin(a) * r.y * k))
		draw_colored_polygon(pts, Color(SHADOW_COL, alpha * 0.4))


## 封印墙：两道月光竖幕 + 往上飘的符纹
func _draw_seals() -> void:
	if seal_alpha <= 0.01:
		return
	for i in 2:
		var x: float = seal_x.x if i == 0 else seal_x.y
		var inward := 1.0 if i == 0 else -1.0
		var top := floor_y - 1400.0
		for k in 10:
			var w := 8.0 + float(k) * 12.0
			var a := seal_alpha * 0.07 * (1.0 - float(k) / 10.0)
			var rx := x if inward > 0.0 else x - w
			draw_rect(Rect2(rx, top, w, floor_y - top), Color(0.75, 0.85, 1.0, a))
		draw_line(Vector2(x, top), Vector2(x, floor_y), Color(0.85, 0.92, 1.0, 0.55 * seal_alpha), 4.0)
		for r in 9:
			var phase_y := fposmod(_time * 120.0 + float(r) * 148.0, 1040.0)
			var y := floor_y - phase_y
			var s := 10.0 + 4.0 * sin(_time * 3.0 + float(r))
			var p := Vector2(x + inward * 20.0, y)
			var col := Color(1.0, 0.86, 0.55, seal_alpha * 0.7 * sin(PI * phase_y / 1040.0))
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, -s), p + Vector2(s * 0.6, 0), p + Vector2(0, s), p + Vector2(-s * 0.6, 0)]), col)


# ---------------------------------------------------------------- 大招「千刃」（2026-10-23 重做）

## 起手：时间停住——屏幕里活着的影和飞行物全部定住；镜头钉在当前位置（连斩瞬移时画面不乱晃）
func _on_ult_started() -> void:
	audio.play_ult_start()
	ult_fx.begin()
	camera.add_shake(3.0 * shake_mul, Vector2.UP)
	var cx: float = camera.get_screen_center_position().x
	var half := 640.0 / ZOOM - 40.0
	_ult_targets.clear()
	var freeze: int = player.ult_total_frames + 2
	for s in get_tree().get_nodes_in_group(&"shade"):
		if not s.is_alive():
			continue
		s.hitstop_frames = maxi(s.hitstop_frames, freeze)
		if s.spawn_frames <= 0 and absf(s.global_position.x - cx) <= half + 100.0:
			_ult_targets.append({"node": s, "cuts": 0})
	_ult_targets.sort_custom(func(a, b): return a.node.global_position.x < b.node.global_position.x)
	for b in get_tree().get_nodes_in_group(&"shade_projectile"):
		b.set_physics_process(false)
	_ult_dir = player.facing
	_ult_left = cx - half
	_ult_right = cx + half
	_ult_anchor.global_position = camera.get_screen_center_position()
	camera.follow_target = _ult_anchor


## 第 k 斩：瞬移穿过下一个目标（来回折返），沿路留残影和一道斩线，目标身上多一道刀痕
func _on_ult_pass(k: int, count: int) -> void:
	if k == 0:
		# 第一刀先把飞在半空的影矢 / 炸弹全部斩碎
		for b in get_tree().get_nodes_in_group(&"shade_projectile"):
			if is_instance_valid(b):
				fx.spawn_deflect(b.global_position, Vector2(player.facing, 0))
				b.queue_free()
	var from: Vector2 = player.global_position
	var tg: Dictionary = _ult_pick_target(from.x)
	var dest_x: float
	if tg.is_empty():
		# 屏幕里没有影：对着空气来回斩（照样好看）
		dest_x = from.x + float(_ult_dir) * 300.0
		if dest_x < _ult_left or dest_x > _ult_right:
			_ult_dir = -_ult_dir
			dest_x = from.x + float(_ult_dir) * 300.0
	else:
		dest_x = tg.node.global_position.x + float(_ult_dir) * ULT_PASS_OVERSHOOT
	dest_x = clampf(dest_x, _ult_left, _ult_right)
	player._set_facing(_ult_dir)
	player.ult_dash_by(dest_x - from.x)
	var to: Vector2 = player.global_position
	var cut_pt := Vector2.INF
	var node: Node2D = null
	if not tg.is_empty():
		node = tg.node
		tg.cuts += 1
		cut_pt = node.global_position + Vector2(0.0, -node.half_h * 0.35)
		node.flash = 4
		node.flash_color = Color.WHITE
	ult_fx.cut(from, to, cut_pt, node, k, count)
	audio.play_swing(0.45 + 0.4 * float(k) / float(maxi(count - 1, 1)))
	if node != null:
		audio.play_blade_hit(0.35)
	camera.add_shake((2.0 + 2.5 * float(k) / float(maxi(count - 1, 1))) * shake_mul, Vector2(_ult_dir, 0))


## 下一个目标：沿当前方向、主角前面最近的那只；前面没有了就掉头。只有一只的话来回穿它。
func _ult_pick_target(x: float) -> Dictionary:
	var alive := _ult_targets.filter(func(t): return is_instance_valid(t.node) and t.node.is_alive())
	if alive.is_empty():
		return {}
	for attempt in 2:
		var best: Dictionary = {}
		var best_d := INF
		for t in alive:
			var d: float = (t.node.global_position.x - x) * float(_ult_dir)
			if d > 20.0 and d < best_d:
				best_d = d
				best = t
		if not best.is_empty():
			return best
		_ult_dir = -_ult_dir
	return alive[0]


## 收刀之后一齐爆开：每只挨过刀的影吃满伤害并被打飞（躲不开、挡不住、霸体也扛不住），伤害数字这时才冒
func _on_ult_hit() -> void:
	audio.play_ult_slash()
	var mv: Resource = player.ult_move()
	var px: float = player.global_position.x
	var hit: Array = []
	for t in _ult_targets:
		var s: Node2D = t.node
		if not is_instance_valid(s) or not s.is_alive():
			continue          # 屏幕里的影全都吃这一下（刀数不够没轮到的也算一刀）
		var dir := 1 if s.global_position.x >= px else -1
		var pt: Vector2 = s.global_position + Vector2(0.0, -s.half_h * 0.3)
		s.hitstop_frames = 0
		s.take_hit(mv, dir, pt, 0.0, false, 1.0, player)
		s.hitstop_frames = maxi(s.hitstop_frames, 4)
		hit.append({"node": s, "pt": pt, "cuts": maxi(int(t.cuts), 1)})
	ult_fx.burst(hit)
	camera.add_shake((14.0 if hit.size() > 0 else 6.0) * shake_mul, Vector2(player.facing, 0))
	if hit.size() > 0:
		audio.play_blade_hit(1.0)
	style.add_event(&"ult")
	_ult_release_camera()


func _ult_release_camera() -> void:
	if camera.follow_target == _ult_anchor:
		camera.follow_target = player
	_ult_targets.clear()
