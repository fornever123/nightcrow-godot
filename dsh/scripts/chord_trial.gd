extends Node2D
## 截弦 · DSH 版试炼场。
## 规则见 dsh/docs/玩法-截弦.md：敌人出手先甩一根弦，绷紧后截断，夺招入鞘；
## 拆空所有提线 = 空弦；朱弦截不断，只能用夺来的招打碎；弦力满开断幕。

const P := preload("res://dsh/scripts/chord_palette.gd")
const CONFIG_PATH := "res://dsh/data/chord.json"

const PlayerScript := preload("res://dsh/scripts/chord_player.gd")
const EnemyScript := preload("res://dsh/scripts/chord_enemy.gd")
const ThreadScript := preload("res://dsh/scripts/chord_thread.gd")
const StageScript := preload("res://dsh/scripts/chord_stage.gd")
const BackdropScript := preload("res://dsh/scripts/chord_backdrop.gd")
const HudScript := preload("res://dsh/scripts/chord_hud.gd")
const FxScript := preload("res://dsh/scripts/chord_fx.gd")
const AudioScript := preload("res://dsh/scripts/chord_audio.gd")

var cfg: Dictionary = {}
var cut_cfg: Dictionary = {}
var acts: Array = []

var act_index: int = -1
var act: Dictionary = {}
var act_label: String = ""
var act_subtitle: String = ""
var act_t: float = 0.0
var ground_y: float = 580.0
var bounds_left: float = -600.0
var bounds_right: float = 800.0
var platforms: Array = []

var phase: String = "title"
var hint: String = ""
var hint_t: float = 0.0
var hints_seen: Dictionary = {}

var player: Node2D = null
var enemies: Array = []
var threads: Array = []
var fx: Node2D = null
var hud: Control = null
var audio: Node = null
var camera: Camera2D = null
var backdrop: Control = null
var stage: Node2D = null
var boss: Node2D = null
var boss_active: bool = false

var hearts: int = 5
var max_hearts: int = 5
var meter: float = 0.0
var arts: Array = []
var arts_info: Dictionary = {}
var sheath_slots: int = 3

var stat_duan: int = 0
var stat_jie: int = 0
var stat_jue: int = 0
var stat_arts: int = 0
var stat_broke: int = 0
var rank: String = ""
var result_t: float = 0.0
var death_t: float = 0.0
var title_fade: float = 1.0
var wipe: float = 0.0

var flash_amount: float = 0.0
var flash_color: Color = Color(1, 1, 1)
var slow_t: float = 0.0
var _ult_until_ms: int = 0
var _hitstop_until_ms: int = 0
var _shake: float = 0.0
var _clear_t: float = 0.0
var _wipe_state: String = "none"
var _wipe_t: float = 0.0
var _pending_act: int = -1
var _boss_dead_t: float = 0.0
var _last_thread_at: float = -9.0
var _cut_swing_id: int = -1
var _hit_pairs: Dictionary = {}
var _bounce_swing: int = -1
var _time: float = 0.0
var _prev_key: Dictionary = {}
var _started: bool = false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 771
	cfg = _read_json(CONFIG_PATH)
	cut_cfg = cfg.get("cut", {})
	arts_info = cfg.get("arts", {})
	acts = cfg.get("acts", [])
	hearts = int(cfg.get("player", {}).get("hearts", 5))
	max_hearts = hearts
	sheath_slots = int(cfg.get("sheath", {}).get("slots", 3))

	_make_backdrop()
	_make_stage()
	_make_camera()
	_make_player()
	_make_fx()
	_make_hud()
	_make_audio()
	_enter_act_silent(0)


func _read_json(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("截弦：缺少 " + path)
		return {}
	var v: Variant = JSON.parse_string(text)
	return v if v is Dictionary else {}


func _exit_tree() -> void:
	Engine.time_scale = 1.0


# ------------------------------------------------------------------ 搭台

func _make_backdrop() -> void:
	var layer := CanvasLayer.new()
	layer.layer = -10
	add_child(layer)
	backdrop = BackdropScript.new()
	backdrop.name = "Backdrop"
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(backdrop)


func _make_stage() -> void:
	stage = StageScript.new()
	stage.name = "Stage"
	stage.z_index = -4
	add_child(stage)


func _make_camera() -> void:
	camera = Camera2D.new()
	camera.zoom = Vector2(1.0, 1.0)
	camera.position = Vector2(0, 300)
	add_child(camera)
	camera.make_current()


func _make_player() -> void:
	player = PlayerScript.new()
	player.name = "Player"
	player.trial = self
	add_child(player)
	player.setup(cfg, Vector2(0, ground_y))
	player.swung.connect(_on_player_swung)
	player.dashed.connect(_on_player_dashed)
	player.jumped.connect(_on_player_jumped)
	player.landed.connect(_on_player_landed)
	player.hurt.connect(_on_player_hurt)
	player.died.connect(_on_player_died)


func _make_fx() -> void:
	fx = FxScript.new()
	fx.name = "Fx"
	add_child(fx)


func _make_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	hud = HudScript.new()
	hud.name = "Hud"
	hud.trial = self
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(hud)


func _make_audio() -> void:
	audio = AudioScript.new()
	audio.name = "Audio"
	add_child(audio)


func sfx(key: String, db: float = -7.0, pitch: float = 1.0) -> void:
	if audio != null:
		audio.play(key, db, pitch)


# ------------------------------------------------------------------ 折

func _enter_act_silent(index: int) -> void:
	act_index = clampi(index, 0, maxi(0, acts.size() - 1))
	act = acts[act_index] if act_index < acts.size() else {}
	act_label = String(act.get("label", ""))
	act_subtitle = String(act.get("subtitle", ""))
	ground_y = float(act.get("ground", 580.0))
	bounds_left = float(act.get("left", -600.0))
	bounds_right = float(act.get("right", 800.0))
	platforms = []
	for p in act.get("platforms", []):
		platforms.append(p)
	stage.setup(act, act_index)
	backdrop.act_index = act_index
	backdrop.act_center = (bounds_left + bounds_right) * 0.5
	player.pos = Vector2(float(act.get("spawnX", bounds_left + 240.0)), ground_y)
	player.vel = Vector2.ZERO
	player.facing = 1
	camera.position = _camera_target(true)


func _start_act(index: int) -> void:
	_clear_world()
	_enter_act_silent(index)
	if index > 0:
		player.heal(1)
		toast("拾纸补心 · 心 +1", 1.8)
	act_t = 0.0
	act_label = String(act.get("label", ""))
	act_subtitle = String(act.get("subtitle", ""))
	toast(String(act.get("hint", "")), 4.0 if index < 2 else 3.4)
	phase = "fight"
	_clear_t = 0.0
	wipe = 0.0
	_wipe_state = "none"
	_spawn_act(index)
	sfx("bell", -9.0)
	if index == acts.size() - 1:
		sfx("gong", -8.0)
		toast("无常判官", 2.4)


func _spawn_act(index: int) -> void:
	var spawns: Array = act.get("spawns", [])
	for s in spawns:
		_spawn_enemy(s)


func _spawn_enemy(spawn: Dictionary) -> void:
	var e = EnemyScript.new()
	e.name = "Puppet_%s_%d" % [String(spawn.get("type", "boy")), enemies.size()]
	add_child(e)
	e.setup(self, spawn)
	enemies.append(e)
	if e.is_boss:
		boss = e
		boss_active = true


func _clear_world() -> void:
	for e in enemies:
		if is_instance_valid(e):
			e.queue_free()
	enemies.clear()
	for th in threads:
		if is_instance_valid(th):
			th.queue_free()
	threads.clear()
	if fx != null:
		fx.clear_all()
	boss = null
	boss_active = false
	_hit_pairs.clear()
	_cut_swing_id = -1


func enemies_alive() -> Array:
	var out: Array = []
	for e in enemies:
		if is_instance_valid(e) and not e.dead:
			out.append(e)
	return out


func notify_gone(e: Node) -> void:
	enemies.erase(e)


# ------------------------------------------------------------------ 弦

func spawn_thread(source: Node2D, move_key: String, th_cfg: Dictionary) -> Node2D:
	var th = ThreadScript.new()
	th.name = "Thread"
	add_child(th)
	th.setup(self, source, move_key, th_cfg)
	threads.append(th)
	_last_thread_at = _time
	return th


func can_attack(who: Node) -> bool:
	if phase != "fight":
		return false
	if _time - _last_thread_at < 0.30:
		return false
	var wind := 0
	for e in enemies_alive():
		if e != who and String(e.state) == "windup":
			wind += 1
	var cap := 1 if act_index <= 0 else 2
	return wind < cap


func _tick_threads(delta: float) -> void:
	var keep: Array = []
	for th in threads:
		if not is_instance_valid(th):
			continue
		if th.dead:
			continue
		th.tick(delta)
		if not th.dead and is_instance_valid(th):
			keep.append(th)
	threads = keep


func resolve_thread(th) -> void:
	if th == null or not is_instance_valid(th) or th.dead:
		return
	th.dead = true
	var end: Vector2 = th.end
	var col: Color = P.RED if th.red else P.INK
	var power := 1.4 if th.red else 1.0
	if fx != null:
		if th.kind == "ground":
			fx.wave(Vector2(end.x, ground_y), 1, 70.0, col)
			fx.spike(Vector2(end.x, ground_y), 54.0 * power, col)
			fx.ink(Vector2(end.x, ground_y - 10.0), col, 0.8, 6, 0.45)
		else:
			fx.spike(Vector2(end.x, ground_y), 96.0 * power, col)
			fx.ink(Vector2(end.x, ground_y - 46.0), col, 1.0, 8, 0.5)
		fx.ring(Vector2(end.x, ground_y - 30.0), 54.0 * power, col, 0.3)
	# 伤害
	if th.strike.size.x > 0.0 and th.strike.intersects(player.hurtbox()):
		if player.shield_t > 0.0:
			_block_with_shield(th)
		else:
			_damage_player(1, th.source)
	shake(6.0 if th.red else 4.0)
	sfx("stamp" if th.red else "land", -10.0 if not th.red else -7.0)
	if th.source != null and is_instance_valid(th.source):
		th.source.on_thread_resolved(th)
	th.queue_free()


func _block_with_shield(th) -> void:
	player.shield_t = 0.0
	player.invuln = maxf(player.invuln, 0.35)
	flash(Color(0.95, 0.93, 0.99), 0.30)
	if fx != null:
		fx.ring(player.center(), 80.0, P.PURPLE, 0.5, 3.0)
		fx.scraps(player.center(), 8, 0.9)
	sfx("bounce", -4.0)
	toast("障 · 挡下并弹回", 1.4)
	if th.source != null and is_instance_valid(th.source) and not th.source.dead:
		th.source.take_hit(float(arts_info.get("zhang", {}).get("damage", 26.0)), player.pos.x)
		_increment_broke_if_red(th, th.source.center())
	stat_broke += 0
	shake(8.0)


func try_cut(box: Rect2, swing_id: int) -> void:
	if _cut_swing_id == swing_id:
		return
	var best = null
	var best_t := -1.0
	for th in threads:
		if not is_instance_valid(th) or th.dead:
			continue
		if not th.cuttable():
			continue
		var pts: PackedVector2Array = th.polyline(12)
		var hit := false
		for i in pts.size() - 1:
			if _seg_rect(pts[i], pts[i + 1], box):
				hit = true
				break
		if hit and th.t > best_t:
			best_t = th.t
			best = th
	if best != null:
		_cut_swing_id = swing_id
		cut_thread(best, best.quality(), swing_id)
		return
	# 朱弦：截不断，弹刀
	if _bounce_swing == swing_id:
		return
	for th in threads:
		if not is_instance_valid(th) or th.dead or not th.red:
			continue
		var pts2: PackedVector2Array = th.polyline(10)
		for i in pts2.size() - 1:
			if _seg_rect(pts2[i], pts2[i + 1], box):
				_bounce_swing = swing_id
				sfx("bounce", -8.0)
				if fx != null:
					fx.ink(th.point_at(th.t), P.RED, 0.6, 4, 0.3)
					fx.stamp(th.point_at(th.t) + Vector2(0, -20), "截不断", P.RED, 18, 0.5)
				if hint_t <= 0.0:
					toast("朱弦截不断 · 躲开，或者用鞘里的招打碎", 2.2)
				return


func _cut_swing_ok() -> bool:
	return true


func cut_thread(th, quality: float, swing_id: int) -> void:
	if th == null or not is_instance_valid(th) or th.dead:
		return
	if slow_t > 0.0:
		quality = 1.0
	var cut_point: Vector2 = th.point_at(th.t)
	th.dead = true
	var src = th.source
	var label := "断"
	var dmg := float(cut_cfg.get("dmgDuan", 26.0))
	var add_meter := float(cut_cfg.get("meterDuan", 12.0))
	var stagger := float(cut_cfg.get("staggerDuan", 0.65))
	if quality >= float(cut_cfg.get("jueAt", 0.93)):
		label = "绝"
		dmg = float(cut_cfg.get("dmgJue", 44.0))
		add_meter = float(cut_cfg.get("meterJue", 30.0))
		stagger = float(cut_cfg.get("staggerJue", 1.35))
		stat_jue += 1
	elif quality >= float(cut_cfg.get("duanAt", 0.78)):
		label = "截"
		dmg = float(cut_cfg.get("dmgJie", 34.0))
		add_meter = float(cut_cfg.get("meterJie", 20.0))
		stagger = float(cut_cfg.get("staggerJie", 0.95))
		stat_jie += 1
	else:
		stat_duan += 1
	if th.decoy:
		# 幌子：只断一根，不夺招、不拆招
		if fx != null:
			fx.cut_burst(cut_point, th.start, th.end, quality * 0.6, th.red, "空")
		sfx("whiff", -7.0)
		th.queue_free()
		return
	# 真弦：夺招 / 拆招 / 伤害
	meter = minf(100.0, meter + add_meter) if slow_t <= 0.0 else meter
	if src != null and is_instance_valid(src) and not src.dead:
		src.take_hit(dmg, player.pos.x)
		src.sever(th.move_key, quality)
	# 同组幌子散掉
	for other in threads:
		if other == th or not is_instance_valid(other) or other.dead:
			continue
		if other.group == th.group and other.decoy:
			other.dead = true
			if fx != null:
				fx.scraps(other.point_at(other.t), 4, 0.5)
			other.queue_free()
	if fx != null:
		fx.cut_burst(cut_point, th.start, th.end, quality, false, label)
	shake(5.0 + quality * 5.0)
	sfx("cut", -5.0, 0.95 + quality * 0.2)
	_hitstop_until_ms = Time.get_ticks_msec() + 46 + int(quality * 34.0)
	flash(Color(1, 0.99, 0.95), 0.10 + quality * 0.12)
	# 入鞘
	var art := String(th.art)
	if art != "" and arts_info.has(art):
		_gain_art(art)
		stat_arts += 1
	if not hints_seen.has("first_cut"):
		hints_seen["first_cut"] = true
		toast("截断了 · 这一招归你了（K 放）", 3.2)
	th.queue_free()


func _gain_art(art: String) -> void:
	arts.append(art)
	if arts.size() > sheath_slots:
		# 满鞘自鸣：最旧的一张当场放出去
		var oldest := String(arts[0])
		arts.remove_at(0)
		toast("满鞘自鸣 · " + String(arts_info.get(oldest, {}).get("name", "")), 1.6)
		_release(arts, oldest, true)
	sfx("take", -6.0)


# ------------------------------------------------------------------ 玩家

func player_strike(box: Rect2, dmg: float, swing_id: int, _src) -> void:
	# 打身体（每刀对每只只算一次）
	for e in enemies_alive():
		var key := "%d:%d" % [swing_id, int(e.get_instance_id())]
		if _hit_pairs.has(key):
			continue
		if box.intersects(e.hurtbox()):
			_hit_pairs[key] = true
			e.take_hit(dmg, player.pos.x)
			if fx != null:
				fx.ink(box.get_center(), P.INK, 0.55, 4, 0.32)
				fx.slash(e.center(), player.facing, 90.0, P.PURPLE_LIGHT)
			sfx("paper", -12.0)
	# 截弦
	try_cut(box, swing_id)


func _damage_player(amount: int, from: Node) -> void:
	if player.take_hit(from.position.x if from != null and is_instance_valid(from) else player.pos.x + 40.0):
		hearts = player.hearts
		flash(Color(0.35, 0.06, 0.06), 0.32)
		shake(12.0)
		sfx("hurt", -4.0)
		if fx != null:
			fx.ink(player.center(), P.RED_DEEP, 1.2, 12, 0.6)
		_hitstop_until_ms = Time.get_ticks_msec() + 70


func _on_player_swung(index: int) -> void:
	sfx("swing", -9.0 - float(index) * 0.6, 0.94 + 0.05 * float(index))


func _on_player_dashed() -> void:
	sfx("dash", -10.0)


func _on_player_jumped(air: bool) -> void:
	sfx("jump", -13.0 if not air else -11.0, 1.05 if air else 1.0)


func _on_player_landed() -> void:
	sfx("land", -16.0)


func _on_player_hurt(_left: int) -> void:
	hearts = player.hearts
	meter = maxf(0.0, meter - 10.0)


func _on_player_died() -> void:
	phase = "dead"
	death_t = 0.0
	Engine.time_scale = 1.0
	sfx("collapse", -3.0)
	flash(Color(0.12, 0.04, 0.04), 0.7)
	if fx != null:
		fx.scraps(player.center(), 26, 1.4)


# ------------------------------------------------------------------ 招（刀鞘）

func release_art(index: int) -> void:
	if index < 0 or index >= arts.size():
		return
	if phase != "fight":
		return
	var art := String(arts[index])
	arts.remove_at(index)
	_release(arts, art, false)


func _release(_list: Array, art: String, auto: bool) -> void:
	var info: Dictionary = arts_info.get(art, {})
	var dmg := float(info.get("damage", 20.0))
	match art:
		"jian":
			_art_jian(dmg)
		"zhang":
			_art_zhang(info)
		"gu":
			_art_gu(info)
		"shuang":
			_art_shuang(info)
		"pan":
			_art_pan(info)
	sfx("art", -5.0 if not auto else -7.0)
	flash(Color(0.98, 0.96, 0.90), 0.10)
	shake(6.0)


func _art_jian(dmg: float) -> void:
	var reach := float(arts_info.get("jian", {}).get("reach", 300.0))
	var c: Vector2 = player.center()
	var box := Rect2(c + Vector2(0.0 if player.facing > 0 else -reach, -80.0), Vector2(reach, 160.0))
	for i in 3:
		if fx != null:
			fx.slash(c + Vector2(player.facing * 40.0, -20.0 + float(i) * 24.0), player.facing, 150.0 + float(i) * 14.0, P.PURPLE_LIGHT)
	for e in enemies_alive():
		if box.intersects(e.hurtbox()):
			e.take_hit(dmg, player.pos.x)
			if fx != null:
				fx.ink(e.center(), P.INK, 1.0, 10, 0.5)
	_shatter_reds(box, dmg * 0.4)
	toast("剪 · 三声裂纸", 1.2)


func _art_zhang(info: Dictionary) -> void:
	player.shield_t = float(info.get("duration", 2.5))
	if fx != null:
		fx.ring(player.center(), 90.0, P.PURPLE, 0.5, 3.0)
	toast("障 · 纸伞护身 2.5 秒", 1.4)


func _art_gu(info: Dictionary) -> void:
	var reach := float(info.get("reach", 700.0))
	var stun := float(info.get("stun", 0.9))
	var dmg := float(info.get("damage", 20.0))
	for e in enemies_alive():
		if absf(e.pos.x - player.pos.x) <= reach:
			e.take_hit(dmg, player.pos.x)
			e.stun(stun)
	if fx != null:
		fx.wave(Vector2(player.pos.x, ground_y), 1, reach * 0.55, P.INK)
		fx.wave(Vector2(player.pos.x, ground_y), -1, reach * 0.55, P.INK)
		fx.ring(Vector2(player.pos.x, ground_y), reach * 0.35, P.RED_DEEP, 0.55, 3.0)
		fx.scraps(Vector2(player.pos.x, ground_y - 20.0), 10, 1.0)
	var box := Rect2(player.pos.x - reach, ground_y - 120.0, reach * 2.0, 140.0)
	_shatter_reds(box, dmg * 0.5)
	shake(10.0)
	toast("鼓 · 地面荡开", 1.2)


func _art_shuang(info: Dictionary) -> void:
	var reach := float(info.get("reach", 520.0))
	var dmg := float(info.get("damage", 22.0))
	var c: Vector2 = player.center()
	for e in enemies_alive():
		if absf(e.pos.x - player.pos.x) <= reach:
			e.take_hit(dmg, player.pos.x)
	if fx != null:
		fx.slash(c, 1, reach * 0.55, P.PURPLE_LIGHT)
		fx.slash(c, -1, reach * 0.55, P.PURPLE_LIGHT)
		fx.ring(c, reach * 0.4, P.INK, 0.4, 2.0)
	var box := Rect2(player.pos.x - reach, ground_y - 260.0, reach * 2.0, 300.0)
	_shatter_reds(box, dmg * 0.5)
	toast("双 · 前后交叉", 1.2)


func _art_pan(info: Dictionary) -> void:
	var dmg := float(info.get("damage", 55.0))
	var stun := float(info.get("stun", 2.0))
	for e in enemies_alive():
		e.take_hit(dmg, player.pos.x)
		e.stun(stun)
	if fx != null:
		fx.seal(Vector2(player.pos.x + float(player.facing) * 120.0, ground_y - 120.0), "判", 190, 1.2)
		fx.ring(player.center(), 260.0, P.RED, 0.6, 5.0)
		fx.ink(Vector2(player.pos.x, ground_y - 40.0), P.RED_DEEP, 1.6, 16, 0.8)
	_shatter_reds(Rect2(-100000, -100000, 200000, 200000), dmg)
	flash(Color(0.85, 0.30, 0.24), 0.30)
	shake(16.0)
	sfx("stamp", -2.0)
	toast("判 · 朱印落章", 1.6)


func _shatter_reds(area: Rect2, dmg: float) -> void:
	var broken := 0
	for th in threads:
		if not is_instance_valid(th) or th.dead or not th.red:
			continue
		var p: Vector2 = th.point_at(th.t)
		if not area.has_point(p):
			continue
		th.dead = true
		broken += 1
		stat_broke += 1
		if fx != null:
			fx.cut_burst(p, th.start, th.end, 1.0, true, "破朱")
			fx.scraps(p, 10, 1.1)
		if th.source != null and is_instance_valid(th.source) and not th.source.dead:
			th.source.take_hit(dmg, player.pos.x)
		th.queue_free()
	if broken > 0:
		sfx("bounce", -4.0, 0.8)
		meter = minf(100.0, meter + 8.0 * float(broken))
		if not hints_seen.has("broke_red"):
			hints_seen["broke_red"] = true
			toast("朱弦碎了 · 只有夺来的招打得碎它", 2.6)


func _increment_broke_if_red(_th, _pos: Vector2) -> void:
	pass


# ------------------------------------------------------------------ 断幕

func try_ult() -> void:
	if phase != "fight" or meter < 100.0 or slow_t > 0.0:
		return
	meter = 0.0
	slow_t = float(cfg.get("ult", {}).get("duration", 2.4))
	_ult_until_ms = Time.get_ticks_msec() + int(slow_t * 1000.0)
	flash(Color(1.0, 0.99, 0.95), 0.85)
	sfx("break", -2.0)
	shake(14.0)
	toast("断幕 · 全场弦一齐断", 2.0)
	if fx != null:
		fx.seal(player.center() + Vector2(0, -40), "断", 260, 1.6)
		fx.ring(player.center(), 300.0, P.INK, 0.7, 5.0)
	var snapshot: Array = threads.duplicate()
	for th in snapshot:
		if not is_instance_valid(th) or th.dead:
			continue
		if th.red:
			th.dead = true
			stat_broke += 1
			if fx != null:
				fx.cut_burst(th.point_at(th.t), th.start, th.end, 1.0, true, "破朱")
			if th.source != null and is_instance_valid(th.source) and not th.source.dead:
				th.source.take_hit(12.0, player.pos.x)
			th.queue_free()
		else:
			cut_thread(th, 1.0, -1)
	for e in enemies_alive():
		e.stun(0.6)


# ------------------------------------------------------------------ 回调

func on_enemy_down(e: Node) -> void:
	sfx("collapse", -6.0)
	if fx != null:
		fx.scraps(e.center(), 18, 1.2)
		fx.ink(e.center(), P.INK, 1.2, 12, 0.7)
	shake(8.0)
	if e.is_boss:
		boss_active = false
		_boss_dead_t = 0.0
		slow_t = 2.6
		_ult_until_ms = Time.get_ticks_msec() + 2600
		flash(Color(1, 0.99, 0.95), 0.7)
		sfx("gong", -4.0)
		if fx != null:
			fx.seal(Vector2(e.pos.x, ground_y - 220.0), "弦尽", 300, 2.4)
		toast("弦尽", 2.4)


# ------------------------------------------------------------------ 主循环

func _physics_process(delta: float) -> void:
	_tick_time_scale()
	_time += delta
	_tick_input()
	_tick_hint(delta)
	_tick_flash(delta)
	_tick_phase(delta)
	_tick_threads(delta)
	_tick_camera(delta)
	if backdrop != null:
		backdrop.camera_x = camera.position.x
		backdrop.camera_y = camera.position.y
		backdrop.focus = 1.0 if (phase == "fight" and enemies_alive().size() > 0) else 0.0
	if slow_t > 0.0:
		slow_t = maxf(0.0, float(_ult_until_ms - Time.get_ticks_msec()) / 1000.0)
	flash_amount = maxf(0.0, flash_amount - delta * 2.6)


func _tick_time_scale() -> void:
	var scale := 1.0
	if Time.get_ticks_msec() < _hitstop_until_ms:
		scale = 0.05
	elif slow_t > 0.0:
		scale = float(cfg.get("ult", {}).get("timeScale", 0.34))
	Engine.time_scale = scale


func _tick_phase(delta: float) -> void:
	match phase:
		"title":
			title_fade = 1.0
			if _started:
				title_fade = 0.0
		"fight":
			var alive := enemies_alive()
			if alive.is_empty():
				phase = "clear"
				_clear_t = 0.0
				if act_index < acts.size() - 1:
					toast("这一折走完 · 纸门开了", 2.0)
		"clear":
			_clear_t += delta
			if act_index >= acts.size() - 1:
				if _clear_t > 1.4:
					_begin_result()
			else:
				if _clear_t > 1.1 and _wipe_state == "none":
					_wipe_state = "in"
					_wipe_t = 0.0
					_pending_act = act_index + 1
		"result":
			result_t += delta
		"dead":
			death_t += delta
			if death_t > 2.6:
				get_tree().reload_current_scene()
	# 换折的纸幕
	if _wipe_state == "in":
		_wipe_t = minf(1.0, _wipe_t + delta * 2.6)
		wipe = _wipe_t
		if _wipe_t >= 1.0:
			_start_act(_pending_act)
			_wipe_state = "out"
			_wipe_t = 1.0
	elif _wipe_state == "out":
		_wipe_t = maxf(0.0, _wipe_t - delta * 3.2)
		wipe = _wipe_t
		if _wipe_t <= 0.0:
			_wipe_state = "none"


func _begin_result() -> void:
	phase = "result"
	result_t = 0.0
	rank = _rank()
	if backdrop != null:
		backdrop.focus = 0.0
	sfx("bell", -6.0)


func _rank() -> String:
	var cuts := stat_duan + stat_jie + stat_jue
	if cuts <= 0:
		return "下下 · 一根都没截到"
	var perfect := float(stat_jue) / float(cuts)
	var lost := max_hearts - hearts
	if lost == 0 and perfect >= 0.45:
		return "上上 · 弦尽"
	if perfect >= 0.30 and lost <= 2:
		return "上 · 断弦"
	if lost <= 3:
		return "中 · 会截"
	return "下 · 还在躲"


func _tick_hint(delta: float) -> void:
	hint_t = maxf(0.0, hint_t - delta)
	act_t += delta


func _tick_flash(delta: float) -> void:
	flash_amount = maxf(0.0, flash_amount - delta * 2.6)


func flash(color: Color, amount: float) -> void:
	flash_color = color
	flash_amount = maxf(flash_amount, amount)


func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func _camera_target(snap: bool = false) -> Vector2:
	var half := 640.0
	var lo := bounds_left + half
	var hi := bounds_right - half
	var x: float = player.pos.x if player != null else 0.0
	if hi < lo:
		x = (bounds_left + bounds_right) * 0.5
	else:
		x = clampf(x, lo, hi)
	var y := 300.0
	if player != null:
		y = lerpf(300.0, clampf(player.pos.y - 300.0, 120.0, 380.0), 0.25)
	if snap:
		return Vector2(x, y)
	return Vector2(x, y)


func _tick_camera(delta: float) -> void:
	if camera == null or player == null:
		return
	var target := _camera_target()
	var k := clampf(delta * 5.2, 0.0, 1.0)
	camera.position = camera.position.lerp(target, k)
	_shake = maxf(0.0, _shake - delta * 46.0)
	if _shake > 0.1:
		var off := Vector2(_rng.randf_range(-_shake, _shake), _rng.randf_range(-_shake, _shake) * 0.7)
		camera.position += off


# ------------------------------------------------------------------ 输入

func _just(key: int) -> bool:
	var now := Input.is_physical_key_pressed(key)
	var was := bool(_prev_key.get(key, false))
	_prev_key[key] = now
	return now and not was


func _just_mouse(button: int) -> bool:
	var now := Input.is_mouse_button_pressed(button)
	var key := -button - 60
	var was := bool(_prev_key.get(key, false))
	_prev_key[key] = now
	return now and not was


func _just_pad(btn: int) -> bool:
	var now := Input.is_joy_button_pressed(0, btn)
	var key := -btn - 900
	var was := bool(_prev_key.get(key, false))
	_prev_key[key] = now
	return now and not was


func _tick_input() -> void:
	if phase == "title":
		if _just(KEY_J) or _just_mouse(MOUSE_BUTTON_LEFT) or _just_pad(JOY_BUTTON_X):
			_started = true
			_start_act(0)
			sfx("cut", -8.0)
		return
	if phase == "result":
		return
	if _just(KEY_K) or _just_pad(JOY_BUTTON_Y):
		release_art(arts.size() - 1)
	if _just(KEY_1):
		release_art(0)
	if _just(KEY_2):
		release_art(1)
	if _just(KEY_3):
		release_art(2)
	if _just(KEY_R) or _just_pad(JOY_BUTTON_RIGHT_SHOULDER):
		try_ult()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				get_tree().quit()
			KEY_F5:
				get_tree().reload_current_scene()


# ------------------------------------------------------------------ 工具

func _seg_rect(a: Vector2, b: Vector2, r: Rect2) -> bool:
	if r.has_point(a) or r.has_point(b):
		return true
	var p := [
		r.position,
		Vector2(r.end.x, r.position.y),
		r.end,
		Vector2(r.position.x, r.end.y),
	]
	for i in 4:
		var hit = Geometry2D.segment_intersects_segment(a, b, p[i], p[(i + 1) % 4])
		if hit != null:
			return true
	return false


func toast(text: String, seconds: float = 2.0) -> void:
	if text == hint and hint_t > 0.4:
		return
	hint = text
	hint_t = seconds
	sfx("hint", -18.0)

# ------------------------------------------------------------------ 查询（HUD）

func act_progress() -> String:
	return "%d / %d" % [act_index + 1, acts.size()]
