extends Node
## 玩法线 Boss 小样：浮空连的规则。外挂在玩家身上，不改 player.gd（战斗线的文件）。
##
## 11-08 用户：“浮空难我更希望是连招麻烦一点，比如现在连招里面的技能给奖励，打出奖励才能成功浮空连招。
## 比如我之前的设想，闪a给跳挑飞a给跳空a3给跳”“这段话是给思路，不是给结果啊”
## “我的想法是难在怎么排列，而不是要求按的时机”“我希望还是简单一些，然后某些招式是高奖励招式”。
##
## 简单版，三档：
##   · 普通：空a1、空a2 —— 只有伤害，打中也不放慢下落
##   · 小奖励：挑飞（地面 W+J）、空a3 —— 给跳；空a3 还把空中短闪还给你
##   · 高奖励：闪a（短闪后马上那一刀）、空中上挑（空中 W+J）—— 给跳、它多飘 1 秒、打得更重
## 代价：闪a 要用空中短闪，而空中短闪只有空a3 还。空中上挑现在按不出来（技能键位方案已搁置）；
## 它后摇只有 8 帧、第 4 帧能接招，几乎没代价，以后要做得和闪a 共用次数。
## 所以自然会排成 空a1a2a3 → 闪a → 空a1a2a3 → 闪a ……，不用记额外规则。
## 它基础浮空 3 秒，最多 6 秒。
##
## 之前试过的“到顶才托准”（节拍）、空中三刀加长后摇、同一种连着两次不给，默认都关掉，代码留着当肉鸽奖励素材。
## 肉鸽：rules 每一项都是一局里奖励能改的旋钮，比如把下砸、碰刀也变成高奖励招。

signal judged(on_beat: bool, point: Vector2)
signal whiffed(point: Vector2)
signal jump_given(source: StringName, point: Vector2, high: bool)
signal jump_denied(source: StringName, point: Vector2)   ## 打中了给跳的招，但和上一种一样

const FLASH_A_WINDOW := 20          ## 短闪开始后这么多帧内出的刀算闪a（短闪本身 8 帧，收完还有 12 帧）
const SOURCE_NAME := {&"launch": "挑飞", &"air3": "空a3", &"flash": "闪a", &"air_up": "空中上挑"}

const BASE := {
	# —— 给跳 ——
	"jump_sources": [&"launch", &"air3", &"flash", &"air_up"],  ## 哪些招打中给跳
	"high_sources": [&"flash", &"air_up"],   ## 高奖励招：另外让它多飘 high_extend 帧、打得更重；奖励可以加（下砸、碰刀……）
	"high_extend": 60,          ## 高奖励招让它多飘 1 秒
	"high_hitstop": 6,          ## 高奖励招多停几帧，打起来更重
	"dodge_from_air3": true,    ## 空中短闪只有空a3 打中才还（原来打中什么都还）
	"no_repeat": false,         ## 同一种连着两次不给（试过，简单版关掉）
	"jump_max": 3,              ## 最多同时存几次（和原来一样）
	"hit_hang": "reward",       ## 空中打中放慢下落：all = 原来每下都放慢；reward = 只有给跳的招放慢；none
	                            ## 原来每下都放慢，主角自己就挂在天上，跳根本用不上，给跳的规则卡不住人
	# —— 节拍（默认关）——
	"beat_check": false,
	"beat_vy": -150.0,          ## 它的上升速度慢过这个才算打准
	"early_keep": 0.45,
	"early_slide": 340.0,
	# —— 空中三刀帧数（默认不改：null）——
	"air_frames": null,         ## 例 [[5,4,12,7],[5,4,12,7],[4,6,16,10]] = 前摇/判定/后摇/接招点
	"whiff_extra": 0,
	"early_no_hang": true,
	"air_dash_per_jump": -1,    ## 空中冲刺斩每次腾空几次，-1 = 不限（原来）
}

var player: CharacterBody2D
var dodge: Node = null
var rules: Dictionary = {}
var last_source: StringName = &""   ## 上一次给跳的是哪一种（落地清空）
var given: Array = []               ## 这次腾空里按顺序给过的跳（测试、提示用）
var _moves: Array = []
var _base_frames: Dictionary = {}
var _snap: Dictionary = {}
var _pending_early := false
var _watch: Resource = null
var _whiff_done := false
var _swing_is_flash := false
var _target: Node = null
var force_new_swing := false        ## 测试用：下一次打中当成新的一刀
var _hit_mv: Resource = null        ## 正在打中的这一刀
var _hit_mf: int = 0
var _prev_hit_mv: Resource = null   ## 上一刀（打中过的）
var _swing_rewarded := false        ## 这一刀已经给过奖励（一刀可能打中好几下）
var _vy_before := 0.0               ## 上一帧主角的竖直速度（放慢下落会把它乘 0.45，不放慢时还原）


func _ready() -> void:
	process_physics_priority = 1    # 排在玩家之后
	if rules.is_empty():
		rules = BASE.duplicate(true)
	# 主角自己的“打中就还跳”关掉，改由这里按招给
	player.air_hit_refund_hits = 9999
	player.launcher_refund_hits = 9999
	player.air_jump_refund_hits = 0
	apply()
	player.hit_confirmed.connect(_on_hit_confirmed)
	if dodge != null:
		dodge.refund_on_hit = not bool(rules.dodge_from_air3)


## 把 rules 写到主角身上。肉鸽奖励改了 rules 以后再调一次。
func apply() -> void:
	player.air_jump_refund_max = int(rules.jump_max)
	var per: int = int(rules.air_dash_per_jump)
	player.air_dash_unlimited = per < 0
	if per >= 0:
		player.air_dash_uses = per
	if rules.air_frames == null:
		return
	if _moves.is_empty():
		for m in player.air_combo:
			_moves.append(m.duplicate())
		for i in _moves.size():
			if i + 1 < _moves.size() and _moves[i].next_move == player.air_combo[i + 1]:
				_moves[i].next_move = _moves[i + 1]
		player.air_combo = _moves
	var fr: Array = rules.air_frames
	for i in mini(_moves.size(), fr.size()):
		var m: MoveDefinition = _moves[i]
		m.startup_frames = int(fr[i][0])
		m.active_frames = int(fr[i][1])
		m.recovery_frames = int(fr[i][2])
		m.cancel_frame = int(fr[i][3])
		_base_frames[m] = [m.recovery_frames, m.cancel_frame]


## 这一刀是哪一种给跳的招（不是就返回空）
func source_of(mv: Resource) -> StringName:
	if mv == null:
		return &""
	if mv == player.air_up_move:
		return &"air_up"
	if mv == player.up_strike_move:
		return &"launch"
	if _swing_is_flash or (player.is_dash_move(mv) and player._dash_in_air):
		return &"flash"
	if mv.id == &"air_light_3" and player.air_combo.size() >= 2 and _prev_hit_mv == player.air_combo[1]:
		# 只算空a2 接上来的空a3。三连打完再按 J 会一直出第三刀，不能每刀都给
		return &"air3"
	return &""


## Boss 判完节奏调这个（只在 beat_check 打开时）
func on_judged(on_beat: bool, point: Vector2) -> void:
	_pending_early = not on_beat and bool(rules.early_no_hang)
	if _pending_early:
		_snap = {"vy": player.velocity.y}
	judged.emit(on_beat, point)


func _on_hit_confirmed(target: Node, mv: Resource, point: Vector2) -> void:
	_target = target
	# 在这里认“是不是新的一刀”：空a3 前摇是 0，第一帧就会打中，等不到下面 _physics_process 去认
	var mf: int = player.move_frame
	if mv != _hit_mv or mf < _hit_mf or force_new_swing:
		_prev_hit_mv = _hit_mv
		_hit_mv = mv
		_swing_rewarded = false
		force_new_swing = false
	_hit_mf = mf
	var src := source_of(mv)
	var hang := str(rules.hit_hang)
	if hang == "none" or (hang == "reward" and src == &"") or _pending_early:
		player._air_hit_slow_frames = 0
		var vy: float = float(_snap.vy) if _pending_early else _vy_before
		player.velocity.y = maxf(player.velocity.y, vy)
	_pending_early = false
	if src == &"" or not (rules.jump_sources as Array).has(src):
		return
	if _swing_rewarded:
		return
	if bool(rules.no_repeat) and src == last_source:
		jump_denied.emit(src, point)
		return
	last_source = src
	_swing_rewarded = true
	if src == &"air3" and bool(rules.dodge_from_air3) and dodge != null:
		dodge._air_used = false
	var high := (rules.high_sources as Array).has(src)
	if high:
		var extra: int = int(rules.high_hitstop)
		player.hitstop_frames += extra
		if _target != null and is_instance_valid(_target):
			_target.hitstop_frames += extra
	given.append(src)
	if player.bonus_air_jumps < player.air_jump_refund_max:
		player.bonus_air_jumps += 1
		player.air_jump_refunded.emit(player.bonus_air_jumps)
	jump_given.emit(src, point, high)


func _physics_process(_delta: float) -> void:
	_vy_before = player.velocity.y
	if player.is_on_floor() and player.state != player.State.ATTACK:
		last_source = &""
		given.clear()
	var mv: Resource = player.current_move if player.state == player.State.ATTACK else null
	if mv != _watch or (mv != null and player.move_frame < 2):
		if _watch != null and _base_frames.has(_watch):
			_watch.recovery_frames = _base_frames[_watch][0]
			_watch.cancel_frame = _base_frames[_watch][1]
		if mv != _watch:
			# 新出的一刀：短闪刚结束就算闪a
			_swing_is_flash = mv != null and dodge != null and int(dodge._since) <= FLASH_A_WINDOW
		_watch = mv
		_whiff_done = false
	if mv == null or not _base_frames.has(mv) or _whiff_done:
		return
	if player.move_frame >= mv.startup_frames + mv.active_frames and not player.last_swing_hit:
		_whiff_done = true
		var extra: int = int(rules.whiff_extra)
		if extra > 0:
			mv.recovery_frames = _base_frames[mv][0] + extra
			mv.cancel_frame = _base_frames[mv][1] + extra
			player._air_hit_slow_frames = 0
			whiffed.emit(player.global_position)
