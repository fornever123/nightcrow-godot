extends RefCounted
## 连击数 + D/C/B/A/S 评价（试玩版，见 docs/HANDOFF-试玩版.md §7）。
##
## 纯逻辑、不画东西：night_trial.gd 把战斗事件喂进来，combat_hud.gd 只负责显示。
## 设计意图 —— 让"眩晕连段"这条主线最值钱：
##   · 普通命中只给一点分，而且同一招连续用会越来越不值钱（逼玩家换招）；
##   · 眩晕 / 挑飞 / 下砸 / 撞墙 / 连锁 / 弹刀 这些"主题事件"给大分；
##   · 有敌人还在浮空或眩晕时，连击计时走得慢（鼓励把连段续下去）；
##   · 挨打 = 连击清零 + 评价分砍半。

const RANKS: Array[String] = ["D", "C", "B", "A", "S"]
const RANK_NAMES: Array[String] = ["起手", "连贯", "凌厉", "华丽", "绝影"]
const THRESHOLDS: Array[float] = [0.0, 35.0, 80.0, 150.0, 230.0]
const MAX_POINTS := 320.0
const COMBO_WINDOW := 2.4          ## 秒：两次命中之间允许的最长间隔
const HIT_POINTS := 4.0
## 同一招在最近 RECENT 次命中里出现过几次 → 本次得分系数
const VARIETY := [1.0, 0.7, 0.45, 0.25, 0.12]
const RECENT := 5
const EVENT_POINTS := {
	&"stun": 18.0, &"armor_break": 14.0, &"launch": 10.0, &"slam": 22.0, &"wall": 16.0,
	&"chain": 12.0, &"parry": 20.0, &"kill": 6.0, &"air_kill": 14.0, &"juggle": 1.5,
	&"friendly": 12.0, &"reflect": 14.0, &"guard_break": 10.0, &"ult": 30.0,
}
## 这些事件本身也算一"击"（会让连击数 +1）
const EVENT_COUNTS_AS_HIT := [&"wall", &"chain", &"slam", &"friendly", &"reflect"]

var points: float = 0.0
var combo: int = 0
var combo_timer: float = 0.0
var max_combo: int = 0
var best_rank: int = 0
var recent: Array[StringName] = []
var stats: Dictionary = {}


func _init() -> void:
	reset_stats()


func reset_stats() -> void:
	stats = {"hits": 0, "stun": 0, "armor_break": 0, "launch": 0, "slam": 0, "wall": 0, "chain": 0,
		"parry": 0, "kill": 0, "air_kill": 0, "juggle": 0, "damage_taken": 0.0, "times_hit": 0,
		"friendly": 0, "reflect": 0, "guard_break": 0, "ult": 0}
	max_combo = 0
	best_rank = rank_index()


func reset_all() -> void:
	points = 0.0
	combo = 0
	combo_timer = 0.0
	recent.clear()
	reset_stats()


func add_hit(move_id: StringName) -> float:
	var seen := 0
	for id in recent:
		if id == move_id:
			seen += 1
	var gain: float = HIT_POINTS * float(VARIETY[mini(seen, VARIETY.size() - 1)])
	recent.append(move_id)
	while recent.size() > RECENT:
		recent.pop_front()
	stats.hits += 1
	_bump_combo()
	_gain(gain)
	return gain


func add_event(kind: StringName, amount: float = 1.0) -> float:
	var gain: float = float(EVENT_POINTS.get(kind, 0.0)) * amount
	if stats.has(String(kind)):
		stats[String(kind)] += 1
	if EVENT_COUNTS_AS_HIT.has(kind):
		_bump_combo()
	elif combo > 0:
		combo_timer = maxf(combo_timer, COMBO_WINDOW)
	_gain(gain)
	return gain


func take_damage(amount: float) -> void:
	stats.damage_taken += amount
	stats.times_hit += 1
	combo = 0
	combo_timer = 0.0
	points = maxf(0.0, points * 0.5 - 20.0)


## juggling = 场上有敌人正在浮空或眩晕
func tick(delta: float, juggling: bool) -> void:
	if combo_timer > 0.0:
		combo_timer -= delta * (0.45 if juggling else 1.0)
		if combo_timer <= 0.0:
			combo_timer = 0.0
			combo = 0
	var idx := rank_index()
	var decay := 2.0 + 3.0 * float(idx)
	if combo_timer > 0.0:
		decay *= 0.3
	points = maxf(0.0, points - decay * delta)


func rank_index() -> int:
	var idx := 0
	for i in THRESHOLDS.size():
		if points >= THRESHOLDS[i]:
			idx = i
	return idx


func rank_letter() -> String:
	return RANKS[rank_index()]


func rank_name() -> String:
	return RANK_NAMES[rank_index()]


## 0..1：离下一档还有多远（S 档时是 S 档内的进度）
func rank_progress() -> float:
	var idx := rank_index()
	var lo := THRESHOLDS[idx]
	var hi := MAX_POINTS if idx == THRESHOLDS.size() - 1 else THRESHOLDS[idx + 1]
	return clampf((points - lo) / maxf(hi - lo, 1.0), 0.0, 1.0)


func combo_fraction() -> float:
	return clampf(combo_timer / COMBO_WINDOW, 0.0, 1.0)


func _bump_combo() -> void:
	combo += 1
	combo_timer = COMBO_WINDOW
	max_combo = maxi(max_combo, combo)


func _gain(g: float) -> void:
	# 连击越长，主题事件越值钱一点点（最多 +50%）
	points = minf(MAX_POINTS, points + g * (1.0 + minf(float(combo), 25.0) * 0.02))
	best_rank = maxi(best_rank, rank_index())
