extends Node2D
## 截弦 · 傀儡敌人（五种，全部代码绘制）。
## 设计核心：它身上挂着几根提线 = 它还会几招。截断一招，那根线就断、那招永久消失。
## 拆空 = 空弦，当场散成纸。

const P := preload("res://dsh/scripts/chord_palette.gd")

const MOVES := {
	"qiao": {"name": "敲", "windup": 1.05, "kind": "spike", "art": "jian"},
	"sao": {"name": "扫", "windup": 1.28, "kind": "ground", "art": "jian"},
	"zhang": {"name": "伞张", "windup": 1.30, "kind": "fan", "art": "zhang"},
	"xuan": {"name": "伞旋", "windup": 1.36, "kind": "arc", "art": "zhang", "bend": 150.0},
	"lei": {"name": "擂", "windup": 1.24, "kind": "ground", "art": "gu"},
	"leizhu": {"name": "擂朱", "windup": 1.36, "kind": "ground", "art": "gu", "red": true},
	"jiao": {"name": "交", "windup": 1.18, "kind": "cross", "art": "shuang"},
	"fu": {"name": "缚", "windup": 1.30, "kind": "arc", "art": "shuang", "bend": -110.0},
	"panbi": {"name": "判笔", "windup": 1.42, "kind": "spike", "art": "pan"},
	"juanzong": {"name": "卷宗", "windup": 1.30, "kind": "seq3", "art": "pan"},
	"moya": {"name": "墨押", "windup": 1.40, "kind": "ground", "art": "pan"},
	"fan": {"name": "幡", "windup": 1.46, "kind": "arc", "art": "pan", "bend": 180.0},
	"zhupi": {"name": "朱批", "windup": 1.32, "kind": "ground", "art": "pan", "red": true},
}

const DEFAULTS := {
	"boy": ["qiao", "sao"],
	"san": ["zhang", "xuan"],
	"gu": ["lei", "leizhu"],
	"shuang": ["jiao", "fu"],
	"judge": ["panbi", "juanzong", "moya", "fan", "zhupi"],
}

const BODY := {
	"boy": {"hw": 20.0, "h": 132.0, "hp": 70.0, "range": 460.0, "speed": 92.0},
	"san": {"hw": 24.0, "h": 168.0, "hp": 90.0, "range": 540.0, "speed": 70.0},
	"gu": {"hw": 34.0, "h": 126.0, "hp": 120.0, "range": 400.0, "speed": 54.0},
	"shuang": {"hw": 20.0, "h": 164.0, "hp": 80.0, "range": 500.0, "speed": 104.0},
	"judge": {"hw": 40.0, "h": 214.0, "hp": 260.0, "range": 720.0, "speed": 44.0},
}

var trial: Node = null
var type_id: String = "boy"
var is_boss: bool = false

var pos: Vector2 = Vector2.ZERO
var facing: int = -1
var moves: Array = []
var max_moves: int = 1
var severed: int = 0
var hp: float = 100.0
var max_hp: float = 100.0
var body: Dictionary = {}

var state: String = "idle"
var state_t: float = 0.0
var cooldown: float = 0.6
var stun_t: float = 0.0
var death_t: float = 0.0
var dead: bool = false
var gone: bool = false

var t: float = 0.0
var sway: float = 0.0
var tilt: float = 0.0
var flash: float = 0.0
var wind_amt: float = 0.0
var strike_amt: float = 0.0
var phase: int = 1
var hinted: Dictionary = {}

var active_threads: Array = []
var current_move: String = ""
var _pending: Array = []
var _anim_seed: float = 0.0


func setup(p_trial: Node, spawn: Dictionary) -> void:
	trial = p_trial
	type_id = String(spawn.get("type", "boy"))
	body = BODY.get(type_id, BODY["boy"])
	is_boss = type_id == "judge"
	pos = Vector2(float(spawn.get("x", 0.0)), float(p_trial.ground_y))
	position = pos
	hp = float(body.get("hp", 80.0))
	max_hp = hp
	var list: Array = spawn.get("moves", [])
	if list.is_empty():
		list = DEFAULTS.get(type_id, ["qiao"])
	moves = []
	for m in list:
		moves.append(String(m))
	max_moves = moves.size()
	_anim_seed = randf() * TAU
	z_index = 2
	facing = -1


func alive() -> bool:
	return not dead


func hurtbox() -> Rect2:
	var hw := float(body.get("hw", 20.0))
	var h := float(body.get("h", 130.0))
	return Rect2(pos + Vector2(-hw, -h), Vector2(hw * 2.0, h))


func center() -> Vector2:
	return pos + Vector2(0, -float(body.get("h", 130.0)) * 0.55)


func chord_origin(kind: String) -> Vector2:
	var f := float(facing)
	if kind == "ground":
		return pos + Vector2(f * 22.0, -8.0)
	match type_id:
		"boy":
			return pos + Vector2(f * 26.0, -96.0)
		"san":
			return pos + Vector2(0.0, -186.0)
		"gu":
			return pos + Vector2(0.0, -74.0)
		"shuang":
			return pos + Vector2(f * 30.0, -112.0)
		"judge":
			return pos + Vector2(f * 34.0, -152.0)
	return pos + Vector2(0, -100)


# ------------------------------------------------------------------ 主循环

func _physics_process(delta: float) -> void:
	if trial == null:
		return
	t += delta
	sway = sin(t * 2.1 + _anim_seed) * 2.0
	flash = maxf(0.0, flash - delta * 6.0)
	strike_amt = maxf(0.0, strike_amt - delta * 3.4)
	state_t += delta
	position = pos
	if dead:
		death_t += delta
		if death_t > 1.15 and not gone:
			gone = true
			trial.notify_gone(self)
			queue_free()
		queue_redraw()
		return

	if stun_t > 0.0:
		stun_t = maxf(0.0, stun_t - delta)
		queue_redraw()
		return

	match state:
		"idle":
			_walk(delta)
			cooldown = maxf(0.0, cooldown - delta)
			if cooldown <= 0.0 and trial != null and trial.can_attack(self):
				_pick_move()
		"walk":
			_walk(delta)
			cooldown = maxf(0.0, cooldown - delta)
			if cooldown <= 0.0 and trial != null and trial.can_attack(self):
				_pick_move()
		"windup":
			wind_amt = minf(1.0, wind_amt + delta * 3.4)
			if _threads_done():
				_finish_move()
		"recover":
			wind_amt = maxf(0.0, wind_amt - delta * 4.0)
			if state_t >= 0.42:
				state = "idle"
				state_t = 0.0
		"stagger":
			wind_amt = 0.0
			tilt = lerpf(tilt, 0.22, 0.1)
			if state_t >= 0.01:
				pass
			if state_t >= _stagger_len:
				state = "idle"
				state_t = 0.0
				tilt = 0.0
				cooldown = 0.35
		"storm":
			wind_amt = minf(1.0, wind_amt + delta * 2.0)
			if state_t >= 0.6:
				state = "idle"
				state_t = 0.0
	queue_redraw()


var _stagger_len: float = 0.8


func _walk(delta: float) -> void:
	if trial == null:
		return
	var target_x: float = float(trial.player.pos.x)
	var dx := target_x - pos.x
	var want := 0.0
	var rng := float(body.get("range", 460.0))
	if absf(dx) > rng:
		want = signf(dx)
	elif absf(dx) < rng * 0.45:
		want = -signf(dx) * 0.5
	if want != 0.0:
		var sp := float(body.get("speed", 80.0))
		pos.x += want * sp * delta
	facing = 1 if dx > 0.0 else -1
	pos.x = clampf(pos.x, float(trial.bounds_left) + 40.0, float(trial.bounds_right) - 40.0)
	if state == "idle":
		state = "walk"


func _threads_done() -> bool:
	for th in active_threads:
		if is_instance_valid(th) and not th.dead:
			return false
	active_threads.clear()
	return true


func _pick_move() -> void:
	if moves.is_empty():
		return
	if phase == 3 and is_boss and not hinted.has("juebi"):
		hinted["juebi"] = true
		_begin_juebi()
		return
	var key := ""
	var roll := randf()
	var total := moves.size()
	var idx := int(floor(roll * float(total))) % total
	key = String(moves[idx])
	_begin_move(key)


func _begin_move(key: String) -> void:
	var def: Dictionary = MOVES.get(key, {})
	if def.is_empty():
		return
	current_move = key
	state = "windup"
	state_t = 0.0
	wind_amt = 0.0
	active_threads.clear()
	var aim: Vector2 = trial.player.center()
	var points := _aim_points(String(def.get("kind", "spike")), aim)
	var group := int(randi() % 100000) + 1
	for p in points:
		var cfg := {
			"windup": float(def.get("windup", 1.1)) + float(p.get("delay", 0.0)),
			"kind": String(p.get("kind", def.get("kind", "spike"))),
			"art": String(def.get("art", "")),
			"red": bool(def.get("red", false)) or bool(p.get("red", false)),
			"main": bool(p.get("main", true)),
			"decoy": bool(p.get("decoy", false)),
			"group": group,
			"start": chord_origin(String(p.get("kind", def.get("kind", "spike")))),
			"end": p.get("end", aim),
			"strike": p.get("strike", Rect2(aim - Vector2(50, 60), Vector2(100, 120))),
			"bend": float(def.get("bend", 0.0)) if not p.has("bend") else float(p.get("bend", 0.0)),
		}
		var th = trial.spawn_thread(self, key, cfg)
		active_threads.append(th)
	if is_boss:
		trial.toast("判官 · " + String(def.get("name", "")), 1.2)


func _aim_points(kind: String, aim: Vector2) -> Array:
	var out: Array = []
	var gy: float = float(trial.ground_y)
	match kind:
		"spike":
			out.append(_point(aim, Rect2(aim.x - 54.0, aim.y - 60.0, 108.0, 84.0)))
		"ground":
			out.append(_point(Vector2(aim.x, gy - 10.0), Rect2(aim.x - 74.0, gy - 86.0, 148.0, 90.0)))
		"fan":
			var mid := aim
			out.append(_point(mid, Rect2(mid.x - 52.0, mid.y - 54.0, 104.0, 76.0)))
			out.append(_point(Vector2(mid.x - 190.0, mid.y - 6.0), Rect2(mid.x - 242.0, mid.y - 60.0, 104.0, 76.0), false, true, 0.04))
			out.append(_point(Vector2(mid.x + 190.0, mid.y - 6.0), Rect2(mid.x + 138.0, mid.y - 60.0, 104.0, 76.0), false, true, 0.04))
		"arc":
			out.append(_point(aim, Rect2(aim.x - 58.0, aim.y - 62.0, 116.0, 90.0)))
		"cross":
			out.append(_point(Vector2(aim.x, aim.y - 62.0), Rect2(aim.x - 54.0, aim.y - 122.0, 108.0, 66.0)))
			out.append(_point(Vector2(aim.x, aim.y + 62.0), Rect2(aim.x - 54.0, aim.y + 30.0, 108.0, 62.0), true, false, 0.0))
		"seq3":
			out.append(_point(aim, Rect2(aim.x - 52.0, aim.y - 58.0, 104.0, 80.0), true, false, 0.0))
			out.append(_point(Vector2(aim.x + 120.0, aim.y), Rect2(aim.x + 66.0, aim.y - 58.0, 108.0, 80.0), true, false, 0.34))
			out.append(_point(Vector2(aim.x - 130.0, gy - 10.0), Rect2(aim.x - 200.0, gy - 86.0, 140.0, 90.0), true, false, 0.70))
		_:
			out.append(_point(aim, Rect2(aim.x - 52.0, aim.y - 58.0, 104.0, 80.0)))
	return out


func _point(end: Vector2, strike: Rect2, main: bool = true, decoy: bool = false, delay: float = 0.0) -> Dictionary:
	return {"end": end, "strike": strike, "main": main, "decoy": decoy, "delay": delay}


func _finish_move() -> void:
	state = "recover"
	state_t = 0.0
	strike_amt = 1.0
	cooldown = 1.0 + randf() * 0.7


func on_thread_cut(th, _quality: float) -> void:
	# 由 trial 调用：只有 main 弦被截才算拆掉一招
	if th != null and is_instance_valid(th):
		active_threads.erase(th)


func on_thread_resolved(th) -> void:
	if th != null and is_instance_valid(th):
		active_threads.erase(th)
	if active_threads.is_empty() and state == "windup":
		state = "recover"
		state_t = 0.0
		cooldown = 1.2 + randf() * 0.6


func sever(move_key: String, quality: float) -> void:
	if dead:
		return
	var idx := moves.find(move_key)
	if idx >= 0:
		moves.remove_at(idx)
	severed += 1
	_stagger_len = 0.55 + 0.55 * quality
	state = "stagger"
	state_t = 0.0
	flash = 1.0
	tilt = -0.18
	if is_boss:
		_on_boss_sever()
	if moves.is_empty():
		_collapse()


func _on_boss_sever() -> void:
	if phase == 1 and severed >= 2:
		phase = 2
		trial.toast("判官把被夺的招，用朱线缝了回来", 3.0)
		moves.append("zhupi")
		moves.append("zhupi")
		max_moves += 2
		# 满堂红：立刻甩三根朱弦
		var aim: Vector2 = trial.player.center()
		var gy: float = float(trial.ground_y)
		for i in 3:
			var cfg := {
				"windup": 1.15 + 0.18 * float(i),
				"kind": "spike" if i == 1 else "ground",
				"art": "pan",
				"red": true,
				"main": true,
				"group": 900 + i,
				"start": chord_origin("spike" if i == 1 else "ground"),
				"end": aim if i == 1 else Vector2(aim.x + float(i - 1) * 120.0, gy - 10.0),
				"strike": Rect2(aim.x - 60.0, aim.y - 60.0, 120.0, 90.0) if i == 1 else Rect2(aim.x + float(i - 1) * 120.0 - 70.0, gy - 86.0, 140.0, 90.0),
				"bend": 0.0,
			}
			var th = trial.spawn_thread(self, "zhupi", cfg)
			active_threads.append(th)
		state = "storm"
		state_t = 0.0
	elif phase == 2 and severed >= 5:
		phase = 3
		trial.toast("绝笔 · 他只剩这一整套谱", 3.0)


func _begin_juebi() -> void:
	state = "windup"
	state_t = 0.0
	wind_amt = 0.0
	active_threads.clear()
	var aim: Vector2 = trial.player.center()
	var gy: float = float(trial.ground_y)
	for i in 6:
		var side := -1.0 if i % 2 == 0 else 1.0
		var cfg := {
			"windup": 0.95 + 0.20 * float(i),
			"kind": "spike" if i % 3 != 2 else "ground",
			"art": "pan",
			"red": false,
			"main": true,
			"group": 500 + i,
			"start": chord_origin("spike"),
			"end": Vector2(aim.x + side * 40.0, aim.y - 20.0 + float(i % 3) * 34.0) if i % 3 != 2 else Vector2(aim.x + side * 100.0, gy - 10.0),
			"strike": Rect2(aim.x - 60.0, aim.y - 70.0, 120.0, 110.0) if i % 3 != 2 else Rect2(aim.x + side * 100.0 - 70.0, gy - 86.0, 140.0, 90.0),
			"bend": 0.0,
		}
		var th = trial.spawn_thread(self, "juebi", cfg)
		active_threads.append(th)


func take_hit(dmg: float, from_x: float) -> void:
	if dead:
		return
	hp -= dmg
	flash = 1.0
	var dir := signf(pos.x - from_x)
	if dir == 0.0:
		dir = 1.0
	pos.x += dir * minf(26.0, dmg * 0.7)
	if hp <= 0.0:
		_collapse()


func stun(sec: float) -> void:
	if dead:
		return
	stun_t = maxf(stun_t, sec)
	tilt = 0.16


func _collapse() -> void:
	if dead:
		return
	dead = true
	state = "dead"
	death_t = 0.0
	hp = 0.0
	for th in active_threads:
		if is_instance_valid(th):
			th.dead = true
			th.queue_free()
	active_threads.clear()
	z_index = 1
	if trial != null:
		trial.on_enemy_down(self)


func is_boss_alive() -> bool:
	return is_boss and not dead


# ------------------------------------------------------------------ 画

func _ink(alpha: float = 1.0) -> Color:
	var c := P.INK.lerp(P.WHITE, flash * 0.7)
	c.a = alpha
	return c


func _draw() -> void:
	var alpha := 1.0
	if dead:
		alpha = clampf(1.0 - death_t / 1.15, 0.0, 1.0)
	var gy: float = float(trial.ground_y) - pos.y
	# 落影
	draw_colored_polygon(_ellipse(Vector2(0, gy), 34.0, 6.0), Color(0.09, 0.08, 0.09, 0.16 * alpha))
	# 提线（还会几招就几根绷着；拆掉的是断线）
	_draw_strings(alpha)
	if dead:
		_draw_death(alpha)
		return
	match type_id:
		"boy":
			_draw_boy(alpha)
		"san":
			_draw_san(alpha)
		"gu":
			_draw_gu(alpha)
		"shuang":
			_draw_shuang(alpha)
		"judge":
			_draw_judge(alpha)
	if flash > 0.05:
		draw_circle(Vector2(0, -float(body.get("h", 130.0)) * 0.55), float(body.get("h", 130.0)) * 0.42, Color(1, 1, 1, flash * 0.16))


func _ellipse(c: Vector2, rx: float, ry: float, steps: int = 20) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in steps:
		var a := TAU * float(i) / float(steps)
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


func _draw_strings(alpha: float) -> void:
	var n := maxi(max_moves, 1)
	var top := -float(body.get("h", 130.0)) - 34.0
	for i in n:
		var ox := (float(i) - float(n - 1) * 0.5) * 26.0
		var alive_string := i < moves.size()
		if alive_string:
			var wig := sin(t * 1.6 + float(i)) * 2.0
			var c := Color(P.INK.r, P.INK.g, P.INK.b, 0.34 * alpha)
			draw_line(Vector2(ox, -320.0), Vector2(ox + wig, top), c, 1.0)
			draw_circle(Vector2(ox + wig, top), 1.8, c)
		else:
			# 断线：垂下来的一小截卷
			var c2 := Color(P.INK.r, P.INK.g, P.INK.b, 0.22 * alpha)
			draw_line(Vector2(ox, -320.0), Vector2(ox + 8.0, -286.0), c2, 1.0)
			draw_line(Vector2(ox + 8.0, -286.0), Vector2(ox + 4.0, -268.0), c2, 1.0)


func _draw_death(alpha: float) -> void:
	# 散成一地纸片
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242 + int(_anim_seed * 10.0)
	var h := float(body.get("h", 130.0))
	for i in 14:
		var k := clampf(death_t * 2.2 - float(i) * 0.04, 0.0, 1.0)
		var px := rng.randf_range(-40.0, 40.0) * k
		var py := -h * (0.2 + 0.8 * rng.randf()) + float(i) * 3.0 + death_t * 46.0
		var s := rng.randf_range(3.0, 8.0) * (1.0 - k * 0.4)
		var c := P.INK
		c.a = alpha * 0.8
		draw_colored_polygon(PackedVector2Array([
			Vector2(px - s, py), Vector2(px + s * 0.6, py - s * 0.5),
			Vector2(px + s, py + s * 0.4), Vector2(px - s * 0.4, py + s * 0.6)]), c)


func _draw_boy(alpha: float) -> void:
	var f := float(facing)
	var ink := _ink(alpha)
	var body_c := Vector2(0, -62 + sway)
	# 身体
	draw_colored_polygon(PackedVector2Array([
		body_c + Vector2(-15, -36), body_c + Vector2(15, -36),
		body_c + Vector2(19, 30), body_c + Vector2(-19, 30)]), ink)
	# 腿
	draw_line(body_c + Vector2(-9, 28), Vector2(-12, 0), ink, 8.0, true)
	draw_line(body_c + Vector2(9, 28), Vector2(12, 0), ink, 8.0, true)
	# 头
	var head := body_c + Vector2(0, -52)
	draw_circle(head, 14.0, ink)
	draw_line(head + Vector2(f * 3.0, -5.0), head + Vector2(f * 11.0, -3.0), Color(0.96, 0.94, 0.88, 0.8 * alpha), 1.8, true)
	# 竹板
	var arm := body_c + Vector2(f * 14.0, -26.0)
	var ang := -0.5 - wind_amt * 1.5 + strike_amt * 2.6
	var tip := arm + Vector2(cos(ang) * f, sin(ang)) * 62.0
	draw_line(arm, tip, ink, 6.0, true)
	draw_circle(tip, 4.0, ink)
	# 袖
	draw_line(body_c + Vector2(f * 10.0, -30.0), arm, ink, 9.0, true)


func _draw_san(alpha: float) -> void:
	var f := float(facing)
	var ink := _ink(alpha)
	var body_c := Vector2(0, -86 + sway)
	# 长衣
	draw_colored_polygon(PackedVector2Array([
		body_c + Vector2(-14, -46), body_c + Vector2(14, -46),
		body_c + Vector2(22, 56), body_c + Vector2(4, 62),
		body_c + Vector2(-18, 58)]), ink)
	draw_line(body_c + Vector2(-10, 40), body_c + Vector2(-24 + sway, 62), ink, 5.0, true)
	# 头 + 发髻
	var head := body_c + Vector2(0, -66)
	draw_circle(head, 13.0, ink)
	draw_circle(head + Vector2(-6, -12), 7.0, ink)
	draw_line(head + Vector2(f * 4.0, -3.0), head + Vector2(f * 10.0, 1.0), Color(0.96, 0.94, 0.88, 0.8 * alpha), 1.6, true)
	# 纸伞
	var umb := body_c + Vector2(0, -96 - wind_amt * 16.0)
	var r := 48.0
	draw_line(body_c + Vector2(f * 12.0, -26.0), umb, ink, 3.0)
	draw_arc(umb, r, PI, TAU, 26, ink, 3.0, true)
	draw_line(umb + Vector2(-r, 0), umb + Vector2(r, 0), ink, 2.0)
	for i in 5:
		var ang := PI + PI * float(i + 1) / 6.0
		draw_line(umb, umb + Vector2(cos(ang), sin(ang)) * r, Color(P.INK.r, P.INK.g, P.INK.b, 0.55 * alpha), 1.2, true)
	draw_circle(umb + Vector2(0, 2), 3.0, P.RED if alpha > 0.5 else ink)
	# 袖
	draw_line(body_c + Vector2(-14, -40), body_c + Vector2(-30, -6), ink, 7.0, true)
	draw_line(body_c + Vector2(14, -40), umb + Vector2(f * 10, 4), ink, 6.0, true)


func _draw_gu(alpha: float) -> void:
	var f := float(facing)
	var ink := _ink(alpha)
	var belly := Vector2(0, -70 + sway * 0.6)
	# 肚子
	draw_circle(belly, 42.0, ink)
	for i in 3:
		draw_arc(belly, 34.0 - float(i) * 10.0, 0.0, TAU, 28, Color(0.96, 0.94, 0.88, 0.16 * alpha), 1.4, true)
	# 头
	var head := Vector2(0, -128 + sway * 0.4)
	draw_circle(head, 15.0, ink)
	draw_line(head + Vector2(f * 4.0, -4.0), head + Vector2(f * 11.0, -1.0), Color(0.96, 0.94, 0.88, 0.8 * alpha), 1.8, true)
	# 帽
	draw_colored_polygon(PackedVector2Array([
		head + Vector2(-18, -10), head + Vector2(18, -10), head + Vector2(12, -26), head + Vector2(-12, -26)]), ink)
	# 短臂：起手抬、落手砸
	var lift := -wind_amt * 34.0 + strike_amt * 40.0
	draw_line(belly + Vector2(-28, -20), belly + Vector2(-48, -4 + lift), ink, 8.0, true)
	draw_line(belly + Vector2(28, -20), belly + Vector2(48, -4 + lift), ink, 8.0, true)
	# 腿
	draw_line(belly + Vector2(-18, 34), Vector2(-24, 0), ink, 10.0, true)
	draw_line(belly + Vector2(18, 34), Vector2(24, 0), ink, 10.0, true)
	# 朱线：只有它会甩朱弦
	if moves.has("leizhu"):
		var c := Color(P.RED.r, P.RED.g, P.RED.b, 0.5 * alpha)
		draw_line(belly + Vector2(-30, 6), belly + Vector2(30, 6), c, 1.6)


func _draw_shuang(alpha: float) -> void:
	var f := float(facing)
	var ink := _ink(alpha)
	var body_c := Vector2(0, -84 + sway)
	# 极瘦的身体
	draw_colored_polygon(PackedVector2Array([
		body_c + Vector2(-9, -54), body_c + Vector2(9, -54),
		body_c + Vector2(13, 52), body_c + Vector2(-13, 52)]), ink)
	draw_line(body_c + Vector2(-7, 46), Vector2(-16, 0), ink, 5.0, true)
	draw_line(body_c + Vector2(7, 46), Vector2(16, 0), ink, 5.0, true)
	# 两张脸：一白一黑
	var head := body_c + Vector2(0, -76)
	draw_circle(head, 12.0, ink)
	var mask := head + Vector2(f * 6.0, 0)
	draw_circle(mask, 8.0, Color(0.96, 0.94, 0.88, 0.85 * alpha))
	draw_circle(mask + Vector2(f * 2.0, -2.0), 1.6, ink)
	draw_circle(mask + Vector2(f * 2.0, 3.0), 1.6, ink)
	# 两条长绸：起手时拉直
	var ext := 46.0 + wind_amt * 40.0
	var rib_a := PackedVector2Array([
		body_c + Vector2(-10, -40),
		body_c + Vector2(-30, -10) + Vector2(0, sin(t * 2.4) * 8.0),
		body_c + Vector2(-ext - 30.0, 20) + Vector2(0, sin(t * 2.0 + 1.0) * 12.0)])
	var rib_b := PackedVector2Array([
		body_c + Vector2(10, -40),
		body_c + Vector2(30, -4) + Vector2(0, sin(t * 2.2 + 2.0) * 8.0),
		body_c + Vector2(ext + 24.0, 26) + Vector2(0, sin(t * 1.8 + 3.0) * 12.0)])
	draw_polyline(rib_a, Color(P.INK.r, P.INK.g, P.INK.b, 0.85 * alpha), 2.4, true)
	draw_polyline(rib_b, Color(P.RED.r, P.RED.g, P.RED.b, 0.55 * alpha), 2.0, true)
	# 袖
	draw_line(body_c + Vector2(-9, -44), body_c + Vector2(-26, -16), ink, 5.0, true)
	draw_line(body_c + Vector2(9, -44), body_c + Vector2(26, -14), ink, 5.0, true)


func _draw_judge(alpha: float) -> void:
	var f := float(facing)
	var ink := _ink(alpha)
	var body_c := Vector2(0, -104 + sway * 0.5)
	# 袍
	draw_colored_polygon(PackedVector2Array([
		body_c + Vector2(-30, -74), body_c + Vector2(30, -74),
		body_c + Vector2(46, 96), body_c + Vector2(10, 104),
		body_c + Vector2(-30, 100)]), ink)
	draw_line(body_c + Vector2(-18, 84), body_c + Vector2(-40, 102), ink, 8.0, true)
	draw_line(body_c + Vector2(18, 84), body_c + Vector2(44, 102), ink, 8.0, true)
	# 高帽
	var hat_base := body_c + Vector2(0, -96)
	draw_colored_polygon(PackedVector2Array([
		hat_base + Vector2(-30, 0), hat_base + Vector2(30, 0),
		hat_base + Vector2(22, -74), hat_base + Vector2(-22, -74)]), ink)
	draw_line(hat_base + Vector2(-44, 2), hat_base + Vector2(44, 2), ink, 5.0, true)
	# 白面具
	var face := body_c + Vector2(f * 4.0, -70)
	draw_circle(face, 16.0, Color(0.97, 0.95, 0.89, 0.92 * alpha))
	draw_circle(face + Vector2(-5, -2), 2.4, ink)
	draw_circle(face + Vector2(5, -2), 2.4, ink)
	draw_line(face + Vector2(-6, 7), face + Vector2(6, 7), ink, 1.6)
	# 判笔（右手）
	var arm := body_c + Vector2(f * 34.0, -40.0)
	draw_line(body_c + Vector2(f * 22.0, -52.0), arm, ink, 9.0, true)
	var pang := -0.4 - wind_amt * 1.2 + strike_amt * 2.0
	var pen_tip := arm + Vector2(cos(pang) * f, sin(pang)) * 96.0
	draw_line(arm, pen_tip, ink, 5.0, true)
	draw_colored_polygon(PackedVector2Array([
		pen_tip + Vector2(0, -7), pen_tip + Vector2(f * 14.0, 0), pen_tip + Vector2(0, 7)]), Color(P.RED.r, P.RED.g, P.RED.b, 0.9 * alpha))
	# 卷宗（左手）
	draw_rect(Rect2(body_c + Vector2(-64, -34), Vector2(34, 46)), Color(0.97, 0.95, 0.89, 0.75 * alpha))
	draw_rect(Rect2(body_c + Vector2(-64, -34), Vector2(34, 46)), Color(P.INK.r, P.INK.g, P.INK.b, 0.5 * alpha), false, 1.6)
	# 肩上的朱线（二阶段）
	if phase >= 2:
		var c := Color(P.RED.r, P.RED.g, P.RED.b, 0.55 * alpha + 0.15 * sin(t * 4.0))
		draw_line(body_c + Vector2(-30, -70), body_c + Vector2(30, -70), c, 2.4)
		draw_line(body_c + Vector2(-30, 20), body_c + Vector2(30, 20), c, 1.4)
	# 身后的悬卷
	for i in 3:
		var sx := -70.0 + float(i) * 70.0
		var sy := -230.0 + sin(t * 0.8 + float(i)) * 4.0
		draw_rect(Rect2(Vector2(sx - 12, sy), Vector2(24, 60)), Color(0.97, 0.95, 0.89, 0.20 * alpha))
		draw_rect(Rect2(Vector2(sx - 12, sy), Vector2(24, 60)), Color(P.INK.r, P.INK.g, P.INK.b, 0.18 * alpha), false, 1.0)
