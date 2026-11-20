extends Control
## 《断晓》通用战斗底层 · 驻时白血（虚血抢回 · 零减速正激励）组件（frozen_hp_rig.gd）
##
## 严格对齐 `E:/00game/剧情与主题规划.md` §五.1：
##   1. 受击扣血量的 65% 转为冷白高亮 `frozen_hp`（驻时白血），移速与攻速 0 惩罚。
##   2. 初始停留 1.8s，每次有效命中延长 0.25s（单次受击累计停留封顶 2.8s），超时后以 50%/s 化作白光屑剥落。
##   3. 防无脑换血铁律：身上仍有未抢回的 `frozen_hp` 时若再次受击，旧白血当场碎裂清零，仅保留本次新伤的 65%。
##   4. 归一化抢回：平砍/空连抢回 `基础伤 × 0.45`；重招留痕/染紫裂口直接抢回当前白血的 `45%`；
##      精准弹刀 (`parry`) 瞬间抢回 `100%` 白血并立刻刷满短闪冷却。

signal frozen_created(amount: float, shattered_old: float)
signal frozen_rallied(amount: float, full_parry: bool)
signal frozen_shattered(lost_amount: float)

const BossFonts := preload("res://scripts/boss_sample/boss_fonts.gd")

const CONVERT_RATIO := 0.65
const HOLD_INITIAL := 1.80
const HOLD_EXTEND := 0.25
const HOLD_CAP := 2.80
const DECAY_PER_SEC := 0.50
const NORMAL_RALLY_MUL := 0.45
const HEAVY_RALLY_FRAC := 0.45

## 精确对齐 combat_hud.gd 左上 A5 血条像素槽位（HUD_S = 0.2, HUD_X = 4.0, HUD_Y = 0.0）
const BAR_X0 := 53.2
const BAR_X1 := 291.0
const BAR_TOP := 82.4
const BAR_BOT := 95.4

var stage: Node = null
var player: CharacterBody2D = null
var dodge: Node = null

var frozen_hp: float = 0.0
var pool_peak: float = 0.0
var hold_left: float = 0.0
var hold_total_given: float = 0.0
var total_rallied: float = 0.0
var shatter_count: int = 0

var _prev_hp: float = -1.0
var _rally_flash: float = 0.0
var _shatter_flash: float = 0.0
var _shards: Array = []          ## [{p, v, s, life, t, gold}]
var _font_cn: Font = null
var _rng := RandomNumberGenerator.new()


func setup(stage_ref: Node, player_ref: CharacterBody2D, dodge_ref: Node = null) -> void:
	stage = stage_ref
	player = player_ref
	dodge = dodge_ref
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font_cn = BossFonts.load_font(BossFonts.SERIF_SC)
	if player != null:
		_prev_hp = float(player.hp)
		if player.has_signal(&"hit_confirmed") and not player.hit_confirmed.is_connected(_on_player_hit_confirmed):
			player.hit_confirmed.connect(_on_player_hit_confirmed)
		if player.has_signal(&"parry_success") and not player.parry_success.is_connected(_on_player_parry_success):
			player.parry_success.connect(_on_player_parry_success)


func reset_state() -> void:
	frozen_hp = 0.0
	pool_peak = 0.0
	hold_left = 0.0
	hold_total_given = 0.0
	_rally_flash = 0.0
	_shatter_flash = 0.0
	_shards.clear()
	if player != null and is_instance_valid(player):
		_prev_hp = float(player.hp)
	queue_redraw()


## 由关卡在玩家真实扣血时调用（或由 _process 兜底检测掉血）
func notify_damage_taken(lost_hp: float) -> void:
	if player == null or not is_instance_valid(player) or lost_hp <= 0.05:
		return
	if float(player.hp) <= 0.0:
		frozen_hp = 0.0
		pool_peak = 0.0
		hold_left = 0.0
		_prev_hp = 0.0
		queue_redraw()
		return

	var old_shattered := 0.0
	if frozen_hp > 0.05:
		old_shattered = frozen_hp
		shatter_count += 1
		_spawn_bar_shards(frozen_hp, false)
		frozen_hp = 0.0
		_shatter_flash = 1.0
		frozen_shattered.emit(old_shattered)

	var max_hp := maxf(float(player.max_hp), 1.0)
	var cur_hp := float(player.hp)
	var gain := minf(lost_hp * CONVERT_RATIO, maxf(0.0, max_hp - cur_hp))
	frozen_hp = gain
	pool_peak = maxf(gain, 1.0)
	hold_left = HOLD_INITIAL
	hold_total_given = HOLD_INITIAL
	_prev_hp = cur_hp
	frozen_created.emit(gain, old_shattered)
	queue_redraw()


func rally_from_attack(base_damage: float, is_heavy_or_rift: bool = false) -> float:
	if frozen_hp <= 0.01 or player == null or not is_instance_valid(player) or float(player.hp) <= 0.0:
		return 0.0
	# 延长驻留窗口（单次受击封顶 2.8s）
	var room := maxf(0.0, HOLD_CAP - hold_total_given)
	var add_t := minf(HOLD_EXTEND, room)
	hold_left += add_t
	hold_total_given += add_t

	var want := maxf(base_damage, 12.0) * NORMAL_RALLY_MUL
	if is_heavy_or_rift:
		want = maxf(want, frozen_hp * HEAVY_RALLY_FRAC)
	return _apply_rally(want, false)


func rally_full_on_parry() -> float:
	if dodge != null and is_instance_valid(dodge):
		dodge.set(&"_cool", 0)
		dodge.set(&"_air_used", false)
	if frozen_hp <= 0.01 or player == null or not is_instance_valid(player) or float(player.hp) <= 0.0:
		return 0.0
	return _apply_rally(frozen_hp, true)


func _apply_rally(want: float, full_parry: bool) -> float:
	var take := clampf(want, 0.0, frozen_hp)
	if take <= 0.01:
		return 0.0
	var max_hp := maxf(float(player.max_hp), 1.0)
	var old_hp := float(player.hp)
	var new_hp := minf(max_hp, old_hp + take)
	var healed := maxf(0.0, new_hp - old_hp)
	player.hp = new_hp
	if stage != null and stage.get("hud") != null:
		stage.hud.player_hp = new_hp
	frozen_hp = maxf(0.0, frozen_hp - take)
	if frozen_hp <= 0.05:
		frozen_hp = 0.0
		hold_left = 0.0
	_prev_hp = new_hp
	total_rallied += healed
	_rally_flash = 1.0
	if full_parry:
		_spawn_bar_shards(healed, true)
	frozen_rallied.emit(healed, full_parry)
	queue_redraw()
	return healed


func _on_player_hit_confirmed(_target: Node2D, move: Resource, _point: Vector2) -> void:
	if frozen_hp <= 0.01:
		return
	var dmg := 18.0
	var heavy := false
	if move != null:
		if move.get("damage") != null:
			dmg = float(move.get("damage"))
		var mid := StringName(move.get("id")) if move.get("id") != null else &""
		heavy = mid in [&"dash_slash", &"dash_slash_left", &"air_dash_slash", &"air_dash_slash_left", &"charge_slash", &"plunge", &"light_3", &"air_light_3"]
	if dodge != null and dodge.has_method(&"is_heavy") and bool(dodge.call(&"is_heavy")):
		heavy = true
	rally_from_attack(dmg, heavy)


func _on_player_parry_success(_attacker: Node, _point: Vector2) -> void:
	rally_full_on_parry()


func _process(delta: float) -> void:
	if player != null and is_instance_valid(player):
		var cur_hp := float(player.hp)
		if _prev_hp < 0.0:
			_prev_hp = cur_hp
		elif cur_hp < _prev_hp - 0.1:
			# 若外部直接扣减了 player.hp（如测试直接改血或投射物命中），自动同步生成驻时白血
			var diff := _prev_hp - cur_hp
			_prev_hp = cur_hp
			notify_damage_taken(diff)
		elif cur_hp > _prev_hp + 0.05:
			_prev_hp = cur_hp
			var max_hp := maxf(float(player.max_hp), 1.0)
			frozen_hp = minf(frozen_hp, maxf(0.0, max_hp - cur_hp))

	if frozen_hp > 0.0:
		if hold_left > 0.0:
			hold_left = maxf(0.0, hold_left - delta)
		else:
			var loss := maxf(pool_peak, 10.0) * DECAY_PER_SEC * delta
			frozen_hp = maxf(0.0, frozen_hp - loss)
			if _rng.randf() < 0.45:
				_spawn_decay_mote()

	_rally_flash = maxf(0.0, _rally_flash - delta * 3.8)
	_shatter_flash = maxf(0.0, _shatter_flash - delta * 3.5)
	for s in _shards:
		s.t += delta
		s.p += s.v * delta
		s.v.y += 220.0 * delta
	_shards = _shards.filter(func(s): return s.t < s.life)

	if frozen_hp > 0.0 or _rally_flash > 0.0 or _shatter_flash > 0.0 or not _shards.is_empty():
		queue_redraw()


func _bar_x(ratio: float) -> float:
	return lerpf(BAR_X0, BAR_X1, clampf(ratio, 0.0, 1.0))


func _spawn_bar_shards(amount: float, gold_heal: bool) -> void:
	if player == null or not is_instance_valid(player):
		return
	var max_hp := maxf(float(player.max_hp), 1.0)
	var x0 := _bar_x(float(player.hp) / max_hp)
	var x1 := _bar_x((float(player.hp) + amount) / max_hp)
	var cnt := clampi(int(absf(x1 - x0) / 5.0) + 5, 6, 16)
	for _i in cnt:
		_shards.append({
			"p": Vector2(_rng.randf_range(minf(x0, x1), maxf(x0 + 4.0, x1)), _rng.randf_range(BAR_TOP, BAR_BOT)),
			"v": Vector2(_rng.randf_range(-45.0, 85.0), _rng.randf_range(-130.0, -30.0)),
			"s": _rng.randf_range(2.0, 3.8),
			"life": _rng.randf_range(0.32, 0.56),
			"t": 0.0,
			"gold": gold_heal,
		})


func _spawn_decay_mote() -> void:
	if player == null or not is_instance_valid(player):
		return
	var max_hp := maxf(float(player.max_hp), 1.0)
	var x_end := _bar_x((float(player.hp) + frozen_hp) / max_hp)
	_shards.append({
		"p": Vector2(x_end, _rng.randf_range(BAR_TOP, BAR_BOT)),
		"v": Vector2(_rng.randf_range(6.0, 28.0), _rng.randf_range(-42.0, -14.0)),
		"s": _rng.randf_range(1.6, 2.6),
		"life": 0.36,
		"t": 0.0,
		"gold": false,
	})


func _draw() -> void:
	if player == null or not is_instance_valid(player):
		return
	var max_hp := maxf(float(player.max_hp), 1.0)
	var cur_hp := clampf(float(player.hp), 0.0, max_hp)

	if frozen_hp > 0.05:
		var x0 := _bar_x(cur_hp / max_hp)
		var x1 := _bar_x(minf(max_hp, cur_hp + frozen_hp) / max_hp)
		var w := maxf(2.0, x1 - x0)
		var pulse := 0.86 + 0.14 * sin(Time.get_ticks_msec() * 0.014)
		var base_col := Color(0.86, 0.93, 1.0, 0.92 * pulse)
		var core_col := Color(1.0, 1.0, 1.0, 0.96)
		draw_rect(Rect2(x0, BAR_TOP + 0.8, w, BAR_BOT - BAR_TOP - 1.6), base_col)
		draw_rect(Rect2(x0, BAR_TOP + 0.8, w, 3.2), core_col)
		draw_line(Vector2(x1, BAR_TOP - 1.5), Vector2(x1, BAR_BOT + 1.5), Color(1.0, 0.98, 0.90, 0.95), 1.8)
		if _font_cn != null and frozen_hp >= 2.0:
			var label := "驻时白血 +%d" % int(round(frozen_hp))
			var tw := _font_cn.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			var tx := BAR_X1 - tw - 18.0
			var ty := BAR_TOP - 13.0
			draw_string_outline(_font_cn, Vector2(tx, ty), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 3, Color(0.02, 0.03, 0.06, 0.92))
			draw_string(_font_cn, Vector2(tx, ty), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.90, 0.96, 1.0, 0.96))

	if _rally_flash > 0.01:
		var rx1 := _bar_x(cur_hp / max_hp)
		draw_rect(Rect2(BAR_X0, BAR_TOP - 1.0, maxf(6.0, rx1 - BAR_X0), BAR_BOT - BAR_TOP + 2.0), Color(1.0, 0.96, 0.80, 0.48 * _rally_flash))

	for s in _shards:
		var a := clampf(1.0 - float(s.t) / maxf(float(s.life), 0.01), 0.0, 1.0)
		var c := Color(1.0, 0.92, 0.62, a) if bool(s.gold) else Color(0.90, 0.96, 1.0, a)
		var sz := float(s.s)
		draw_rect(Rect2((s.p as Vector2) - Vector2(sz * 0.5, sz * 0.5), Vector2(sz, sz)), c)
