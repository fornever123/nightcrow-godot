extends RefCounted
## [YG-MARK] 由 YG 新增（首页「断晓 · 断光」WebGL 版移植到 Godot）。
##
## 首页的模拟部分：雨滴 / 悬珠 / 火星 / 刀口 / 收尾演出 / 鼠标交互，
## 从 E:\.0download\code_artifact (1).html 的 drop、fx、cut、fin 与 update() 逐行翻译。
## 只管数据，不碰任何节点；渲染在 yg_title_stage.gd，界面在 yg_title_app.gd。
##
## 删除方法：见 docs/YG-首页断光-删除清单.md（整个 scripts/ui/yg_title/ 一起删）。

# ---------------------------------------------------------------- 环境几何
var W := 1280.0
var H := 720.0
var k := 1.0
var C := Vector2(640.0, 302.0)
var D := Vector2(1.0, 0.0)
var N := Vector2(0.0, 1.0)
var R := 194.0
var F := 147.0
var box := Vector4()            ## 字标方框：x0, x1, y0, y1

const ANG_DEG := 10.32

# ---------------------------------------------------------------- 质量控制
const QUAL := {
	"low": {"scene": 0.5, "bloom": 4, "drops": 1200, "fx": 0.5},
	"mid": {"scene": 1.0, "bloom": 5, "drops": 2000, "fx": 0.8},
	"high": {"scene": 1.0, "bloom": 6, "drops": 2300, "fx": 1.0},
}

# ---------------------------------------------------------------- 设置
var quality := "high"
var rain_percent := 70
var shake := true
var volume := 70

# ---------------------------------------------------------------- 时钟
var now := 0.0
var sim_t := 0.0
var it := 0.0
var hitstop := 0.0
var trauma := 0.0
var impact_rt := -1.0
var flash := 0.0
var state := "intro"

# ---------------------------------------------------------------- 刀口
var cut_sw := -1e5
var cut_on := 0.0
var cut_tip := -1e5
var cut_slashing := 0.0
var cut_slide := 0.0
var cut_slide_v := 0.0
var cut_gap := 0.0
var cut_front := 0.0
var cut_seam := 0.0
var cut_seam_boost := 0.0
var cut_shock_t := -1.0
var cut_done := false
var cut_glint := 0.0
var cut_tip_pos := Vector2.ZERO
var cut_glint_pos := Vector2.ZERO

# ---------------------------------------------------------------- 收尾
var fin_open := 0.0
var fin_void := 0.0
var fin_collapse := 0.0
var fin_seam_len := 1.0
var fin_fade := 0.0
var fin_t := 0.0
var fin_kind := ""
var fin_card := false
var fin_hit := false

# ---------------------------------------------------------------- 玩家刀口
var slots: Array = []

# ---------------------------------------------------------------- 鼠标
var drag: Dictionary = {}
var drag_on := 0.0
var mouse := {"x": -999.0, "y": -999.0, "px": -999.0, "py": -999.0,
		"vx": 0.0, "vy": 0.0, "sp": 0.0, "cd": 0.0, "sx": 0.0, "sy": 0.0,
		"tx": 0.0, "ty": 0.0}

# ---------------------------------------------------------------- 粒子
class Drop:
	var x := 0.0
	var y := 0.0
	var vx := 0.0
	var vy := 0.0
	var size := 1.0
	var a := 1.0
	var seed := 0.0
	var layer := 0
	var st := 0
	var born := -99.0
	var vtk := 1200.0
	var vt := 1200.0
	var keep := 0.0
	var fz := -99.0

class Fx:
	var x := 0.0
	var y := 0.0
	var vx := 0.0
	var vy := 0.0
	var life := 0.0
	var max_life := 1.0
	var size := 1.0
	var rot := 0.0
	var spin := 0.0
	var kind := 0
	var seed := 0.0

var drops: Array = []
var fx: Array = []
var next_drip := 6.0
var last_slash_t := -9.0
var intro_rain := false
var recycle_frozen := 0
var recycle_cache_t := -1.0
var recycle_target := 0

# ---------------------------------------------------------------- 时间轴
const TL := {"rise_a": 0.7, "rise_b": 3.0, "freeze_a": 1.25, "freeze_b": 2.95,
		"title_a": 2.55, "title_b": 3.45, "glint_a": 3.35,
		"slash_a": 3.72, "slash_dur": 0.15, "ui_a": 4.75}
const IMPACT_T := 3.87


func _init(w: float, h: float) -> void:
	set_size(w, h)


func set_size(w: float, h: float) -> void:
	var old_w := W
	var old_h := H
	W = max(1.0, w)
	H = max(1.0, h)
	k = max(0.25, min(H, W * 0.5625) / 1080.0)
	var ang := deg_to_rad(ANG_DEG)
	D = Vector2(cos(ang), sin(ang))
	N = Vector2(-sin(ang), cos(ang))
	# [YG-MARK] 11-05 改好看：刀口 / 字标中心 0.42H → 0.385H、字标 0.205H → 0.195H，给下面的菜单留出呼吸
	C = Vector2(W * 0.5, H * 0.385)
	R = min(H * 0.27, W * 0.21)
	F = min(H * 0.195, W * 0.148)
	# 字标图（GPT 版）在画布上的位置：和网页版 makeTitle() 里 GPT 分支一致
	var sc := F * 2.35 / 1264.0
	var ix := C.x - 880.0 * sc
	var iy := C.y - 447.9 * sc
	box = Vector4(ix + 248.0 * sc, ix + 1512.0 * sc, iy + 73.0 * sc, iy + 889.0 * sc)
	logo_origin = Vector2(ix, iy)
	logo_size = Vector2(1672.0 * sc, 941.0 * sc)
	if not drops.is_empty() and old_w >= 100.0 and old_h >= 100.0 and (old_w != W or old_h != H):
		for d in drops:
			d.x *= W / old_w
			d.y *= H / old_h
			d.vt = d.vtk * k
			if d.layer == 1 or (d.layer == 0 and d.st == 0):
				d.vx = 230.0 * k


var logo_origin := Vector2.ZERO
var logo_size := Vector2(100.0, 100.0)


func ql() -> Dictionary:
	return QUAL.get(quality, QUAL["high"])


func seam_y(x: float) -> float:
	return C.y + tan(deg_to_rad(ANG_DEG)) * (x - C.x)


func s_of(x: float, y: float) -> float:
	return (x - C.x) * N.x + (y - C.y) * N.y


func off_u() -> Vector2:
	return Vector2(-cut_slide * D.x - cut_gap * N.x, -cut_slide * D.y - cut_gap * N.y)


func off_l() -> Vector2:
	return Vector2(cut_slide * D.x + cut_gap * N.x, cut_slide * D.y + cut_gap * N.y)


func _hyp(a: float, b: float) -> float:
	return sqrt(a * a + b * b)


func rnd(a: float, b: float) -> float:
	return a + randf() * (b - a)


# ---------------------------------------------------------------- 雨滴
func new_drop() -> Drop:
	var d := Drop.new()
	var r := randf()
	if r < 0.007:
		d.size = rnd(7.0, 14.0)
		d.a = rnd(0.08, 0.14)
	elif r < 0.22:
		d.size = rnd(2.15, 3.7)
		d.a = rnd(0.68, 0.95)
	else:
		d.size = rnd(0.85, 2.1)
		d.a = rnd(0.55, 1.0)
	var depth := clampf((d.size - 0.8) / 12.0, 0.0, 1.0)
	d.vtk = 950.0 + depth * 1100.0 + randf() * 250.0
	d.vt = d.vtk * k
	d.seed = randf() * 100.0
	d.keep = randf()
	return d


func init_drops() -> void:
	drops.clear()
	var n: int = ql()["drops"]
	for i in n:
		var d := new_drop()
		d.x = randf() * W
		d.y = randf() * H
		d.vx = 230.0 * k
		d.vy = d.vt
		drops.append(d)


func freeze_all() -> void:
	for d in drops:
		if d.layer == 0:
			d.vx = 0.0
			d.vy = 0.0
			d.st = 1
			d.fz = sim_t


func rebalance_drops() -> void:
	var n: int = ql()["drops"]
	while drops.size() > n:
		drops.pop_back()
	while drops.size() < n:
		var d := new_drop()
		recycle(d)
		d.y = randf() * H
		drops.append(d)
	recycle_target = int(round(n * 0.36))


# ---------------------------------------------------------------- 火星
func spawn_spark(x: float, y: float, vx: float, vy: float, life: float, size: float,
		kind: int = 0, spin: float = 0.0) -> void:
	if fx.size() > 4000:
		return
	var p := Fx.new()
	p.x = x
	p.y = y
	p.vx = vx
	p.vy = vy
	p.life = life
	p.max_life = life
	p.size = size
	p.kind = kind
	p.rot = randf() * 6.28
	p.spin = spin
	p.seed = randf() * 6.28
	fx.append(p)


func burst_line(x0: float, y0: float, dx: float, dy: float, length: float, n: float, dir: float = 1.0) -> void:
	var nx := -dy
	var ny := dx
	var count := int(round(n * float(ql()["fx"])))
	for i in count:
		var t := randf() * length - length * 0.5
		var x := x0 + dx * t
		var y := y0 + dy * t
		var side := -1.0 if randf() < 0.5 else 1.0
		var sp := rnd(150.0, 1500.0) * k
		var along := rnd(-0.2, 1.0) * dir
		spawn_spark(x, y,
				(dx * along * 1.3 + nx * side * rnd(0.1, 0.6)) * sp,
				(dy * along * 1.3 + ny * side * rnd(0.1, 0.6)) * sp - 80.0 * k,
				rnd(0.25, 0.9), rnd(0.8, 2.2), 0)


func shards_line(x0: float, y0: float, dx: float, dy: float, length: float, n: float) -> void:
	var nx := -dy
	var ny := dx
	var count := int(round(n * float(ql()["fx"])))
	for i in count:
		var t := randf() * length - length * 0.5
		var x := x0 + dx * t
		var y := y0 + dy * t
		var side := -1.0 if randf() < 0.5 else 1.0
		var sp := rnd(120.0, 620.0) * k
		spawn_spark(x + nx * side * 3.0, y + ny * side * 3.0,
				(dx * rnd(-0.5, 0.5) + nx * side) * sp,
				(dy * rnd(-0.5, 0.5) + ny * side) * sp - (120.0 if side < 0.0 else 0.0) * k,
				rnd(0.8, 1.8), rnd(3.0, 10.0) * k,
				1 if side < 0.0 else 2, rnd(-9.0, 9.0))


# ---------------------------------------------------------------- 刀
func do_impact() -> void:
	cut_slashing = 0.0
	cut_done = true
	cut_tip = 1e5
	hitstop = 0.1
	impact_rt = now
	trauma = 1.0
	cut_slide_v = 1900.0 * k
	cut_gap = 1.6 * k
	cut_seam_boost = 3.5
	cut_shock_t = 0.0
	var L := _hyp(W, H)
	burst_line(C.x, C.y, D.x, D.y, L, 700.0)
	shards_line(C.x, C.y, D.x, D.y, L * 0.9, 60.0)


func sweep_sparks(a: float, b: float) -> void:
	var steps := 6
	for i in steps:
		var uu := a + (b - a) * (float(i) / steps)
		var x := C.x + D.x * uu
		var y := C.y + D.y * uu
		if x < -20.0 or x > W + 20.0:
			continue
		var n := int(round(9.0 * float(ql()["fx"])))
		for j in n:
			var side := -1.0 if randf() < 0.5 else 1.0
			var sp := rnd(300.0, 1800.0) * k
			spawn_spark(x, y,
					(D.x * rnd(0.3, 1.1) + N.x * side * rnd(0.05, 0.45)) * sp,
					(D.y * rnd(0.3, 1.1) + N.y * side * rnd(0.05, 0.45)) * sp,
					rnd(0.2, 0.7), rnd(0.8, 2.0), 0)


func start_slash() -> void:
	cut_on = 1.0
	cut_slashing = 1.0
	cut_tip = -(W * 0.56 + 80.0)


func player_slash(ax: float, ay: float, bx: float, by: float) -> void:
	var dx := bx - ax
	var dy := by - ay
	var length := _hyp(dx, dy)
	if length < 40.0:
		return
	var ang := atan2(dy, dx)
	var ux := dx / length
	var uy := dy / length
	var mx := (ax + bx) * 0.5
	var my := (ay + by) * 0.5
	if slots.size() >= 3:
		slots.pop_front()
	slots.append({"x": mx, "y": my, "ang": ang, "len": length, "born": sim_t,
			"A": (11.0 + min(length / 52.0, 10.0)) * k})
	hitstop = 0.045
	trauma = max(trauma, 0.5)
	last_slash_t = sim_t
	burst_line(mx, my, ux, uy, length, 260.0, 1.0)
	shards_line(mx, my, ux, uy, length, 26.0)
	var nx := -uy
	var ny := ux
	var rd := 90.0 * k
	var o_u := off_u()
	var o_l := off_l()
	for d in drops:
		var o := o_l if d.layer != 0 else o_u
		var x: float = d.x + o.x
		var y: float = d.y + o.y
		var t := clampf(((x - ax) * ux + (y - ay) * uy) / length, 0.0, 1.0)
		var px := ax + ux * length * t
		var py := ay + uy * length * t
		var dd := _hyp(x - px, y - py)
		if dd > rd:
			continue
		var side := -1.0 if ((x - ax) * nx + (y - ay) * ny) < 0.0 else 1.0
		if d.layer == 0 and (d.st == 1 or d.st == 2):
			d.st = 3
			d.vx = nx * side * rnd(30.0, 160.0) * k + ux * rnd(-40.0, 40.0)
			d.vy = ny * side * rnd(30.0, 160.0) * k - rnd(0.0, 60.0) * k
		elif d.layer == 1:
			d.vx += nx * side * rnd(200.0, 500.0) * k * (1.0 - dd / rd)
			d.vy += ny * side * rnd(100.0, 300.0) * k


func to_shadow(d: Drop, vy_override: float = -1e9) -> void:
	var o_u := off_u()
	var o_l := off_l()
	d.x += o_u.x - o_l.x
	d.y += o_u.y - o_l.y
	d.layer = 1
	d.st = 0
	if vy_override > -1e8:
		d.vy = maxf(vy_override, d.vt * 0.85)
	else:
		d.vy = d.vt * 1.12
	d.vx = d.vy * 0.135


func recycle(d: Drop) -> void:
	if recycle_cache_t != sim_t:
		var n := 0
		for e in drops:
			if e.layer == 0 and e.st == 1:
				n += 1
		recycle_frozen = n
		recycle_cache_t = sim_t
	if cut_done and recycle_frozen < recycle_target and randf() < 0.6:
		var x := randf() * W
		var top := seam_y(x) - 10.0 * k
		var y := randf() * top
		var o := off_u()
		d.x = x - o.x
		d.y = y - o.y
		d.vx = 0.0
		d.vy = 0.0
		d.layer = 0
		d.st = 1
		d.born = sim_t
		recycle_frozen += 1
		return
	d.layer = 1
	d.st = 0
	d.x = randf() * W * 1.24 - W * 0.18
	d.y = seam_y(d.x) + rnd(-12.0, 28.0) * k
	d.vy = d.vt * 1.12
	d.vx = d.vy * 0.135


# ---------------------------------------------------------------- 更新
func update_drops(dt: float) -> void:
	if dt <= 0.0:
		return
	var g := 2400.0 * k
	var o_u := off_u()
	var freeze_r := 1e9
	if state == "intro":
		if it < float(TL["freeze_a"]):
			freeze_r = -1.0
		else:
			var t := clampf((it - float(TL["freeze_a"])) / (float(TL["freeze_b"]) - float(TL["freeze_a"])), 0.0, 1.0)
			freeze_r = (4.0 * t * t * t if t < 0.5 else 1.0 - pow(-2.0 * t + 2.0, 3.0) / 2.0) * _hyp(W, H) * 1.02
	var front := cut_front
	for d in drops:
		if d.layer == 0:
			if d.st == 0:
				d.vy += (d.vt - d.vy) * minf(1.0, dt * 3.0)
				d.vx = d.vy * 0.135
				d.x += d.vx * dt
				d.y += d.vy * dt
				if d.y > H + 40.0:
					d.y = -40.0 - randf() * 60.0
					d.x = randf() * W
				if freeze_r > 0.0 and _hyp(d.x - C.x, d.y - C.y) < freeze_r:
					d.st = 4
			elif d.st == 4:
				var kk := exp(-dt * 11.0)
				d.vx *= kk
				d.vy *= kk
				d.x += d.vx * dt
				d.y += d.vy * dt
				if _hyp(d.vx, d.vy) < 6.0:
					d.vx = 0.0
					d.vy = 0.0
					d.st = 1
					d.fz = sim_t
			elif d.st == 1:
				if cut_done and state != "leave":
					var wx: float = d.x + o_u.x
					var wy: float = d.y + o_u.y
					var s := s_of(wx, wy)
					if s > 0.0 and s < front:
						to_shadow(d, rnd(0.0, 60.0) * k)
					elif float(mouse["sp"]) > 18.0 and d.size < 5.5:
						var mdx := wx - float(mouse["x"])
						var mdy := wy - float(mouse["y"])
						var md := _hyp(mdx, mdy)
						var mr := 68.0 * k
						if md < mr and md > 0.1:
							var push: float = (1.0 - md / mr) * minf(float(mouse["sp"]) * 0.18, 85.0 * k) * dt
							d.x += (mdx / md) * push
							d.y += (mdy / md) * push
							if md < 26.0 * k and float(mouse["sp"]) > 75.0 and float(mouse["cd"]) <= 0.0 and d.size < 3.8 and randf() < 0.35:
								d.st = 2
								mouse["cd"] = 0.07
								for i in 4:
									spawn_spark(wx, wy, rnd(-120.0, 120.0) * k, rnd(-140.0, 40.0) * k,
											rnd(0.22, 0.48), rnd(0.7, 1.5), 0)
			elif d.st == 2:
				d.y += 24.0 * k * dt
				d.x += 3.0 * k * dt
				var s2 := s_of(d.x + o_u.x, d.y + o_u.y)
				if s2 > 0.0:
					var x2: float = d.x + o_u.x
					var y2: float = d.y + o_u.y
					for i in 10:
						spawn_spark(x2, y2, rnd(-260.0, 260.0) * k, rnd(-260.0, 60.0) * k,
								rnd(0.2, 0.5), rnd(0.6, 1.4), 0)
					spawn_spark(x2, y2, 0.0, -10.0, 0.9, 2.5 * k, 3)
					to_shadow(d, 260.0 * k)
			elif d.st == 3:
				d.vy += g * 0.6 * dt
				d.x += d.vx * dt
				d.y += d.vy * dt
				if cut_done:
					var s3 := s_of(d.x + o_u.x, d.y + o_u.y)
					if s3 > 0.0:
						to_shadow(d)
				if d.y > H + 40.0:
					recycle(d)
		else:
			var tv: float = d.vt * 1.12
			d.vy += (tv - d.vy) * minf(1.0, dt * 5.0)
			d.vx += (d.vy * 0.135 - d.vx) * minf(1.0, dt * 6.0)
			d.x += d.vx * dt
			d.y += d.vy * dt
			if d.y > H + 60.0 or d.x < -100.0 or d.x > W + 100.0:
				recycle(d)


func seam_splash(dt: float) -> void:
	if not cut_done or state == "leave" or dt <= 0.0:
		return
	var n := dt * 55.0 * float(ql()["fx"])
	var o_l := off_l()
	while n > 0.0:
		n -= 1.0
		if randf() >= n:
			continue
		# [YG-MARK] 11-05 更高级：火星跟着刀口的亮度走，聚在中间（原来整条均匀撒）
		var x := clampf(C.x + (randf() + randf() + randf() - 1.5) * W * 0.36, 0.0, W)
		var y := seam_y(x)
		spawn_spark(x + o_l.x + N.x * 2.0 * k, y + o_l.y + N.y * 2.0 * k,
				rnd(-50.0, 50.0) * k, -rnd(30.0, 140.0) * k, rnd(0.18, 0.4), rnd(0.5, 0.9), 0)
	# [YG-MARK] 11-05 更高级：偶尔有一粒光屑从断口滴下去，落进影里
	if randf() < dt * 1.6:
		var x2 := clampf(C.x + (randf() + randf() - 1.0) * W * 0.3, 0.0, W)
		var y2 := seam_y(x2)
		spawn_spark(x2 + o_l.x + N.x * 4.0 * k, y2 + o_l.y + N.y * 4.0 * k,
				rnd(-6.0, 6.0) * k, rnd(10.0, 40.0) * k, rnd(0.9, 1.3), rnd(0.7, 1.0), 0)


func update_fx(dt: float) -> void:
	if dt <= 0.0:
		return
	for i in range(fx.size() - 1, -1, -1):
		var p: Fx = fx[i]
		p.life -= dt
		if p.life <= 0.0:
			fx.remove_at(i)
			continue
		var dr := 3.2 if p.kind == 0 else (1.2 if p.kind == 3 else 1.6)
		var gg := 700.0 if p.kind == 0 else (-30.0 if p.kind == 3 else 380.0)
		var kk := exp(-dt * dr)
		p.vx *= kk
		p.vy = p.vy * kk + gg * k * dt
		p.x += p.vx * dt
		p.y += p.vy * dt
		p.rot += p.spin * dt


func update(dt: float, rdt: float) -> void:
	# 视差与鼠标速度追踪
	mouse["sx"] = float(mouse["sx"]) + (float(mouse["tx"]) - float(mouse["sx"])) * minf(1.0, rdt * 3.0)
	mouse["sy"] = float(mouse["sy"]) + (float(mouse["ty"]) - float(mouse["sy"])) * minf(1.0, rdt * 3.0)
	if rdt > 0.0:
		var ivx := 0.0
		var ivy := 0.0
		if float(mouse["px"]) > -900.0:
			ivx = (float(mouse["x"]) - float(mouse["px"])) / rdt
			ivy = (float(mouse["y"]) - float(mouse["py"])) / rdt
		mouse["vx"] = float(mouse["vx"]) + (ivx - float(mouse["vx"])) * minf(1.0, rdt * 14.0)
		mouse["vy"] = float(mouse["vy"]) + (ivy - float(mouse["vy"])) * minf(1.0, rdt * 14.0)
		mouse["sp"] = _hyp(float(mouse["vx"]), float(mouse["vy"]))
		mouse["px"] = mouse["x"]
		mouse["py"] = mouse["y"]
		if float(mouse["cd"]) > 0.0:
			mouse["cd"] = float(mouse["cd"]) - rdt

	if state == "intro":
		var prev := it
		it += dt
		if prev < float(TL["slash_a"]) and it >= float(TL["slash_a"]):
			start_slash()
		if cut_slashing != 0.0:
			var t := clampf((it - float(TL["slash_a"])) / float(TL["slash_dur"]), 0.0, 1.0)
			var u0 := -(W * 0.56 + 80.0)
			var u1 := W * 0.56 + 80.0
			var prev_tip := cut_tip
			cut_tip = u0 + (u1 - u0) * (t * t * 0.35 + t * 0.65)
			cut_sw = cut_tip
			sweep_sparks(prev_tip, cut_tip)
			if t >= 1.0:
				do_impact()
		if prev < float(TL["ui_a"]) and it >= float(TL["ui_a"]):
			show_ui_requested = true

	# 刀口的弹簧
	if cut_done:
		var target := (0.0 if state == "leave" else 15.0) * k
		var a := (target - cut_slide) * 120.0 - cut_slide_v * 12.0
		cut_slide_v += a * dt
		cut_slide += cut_slide_v * dt
		var since := (it - IMPACT_T) if state == "intro" else 9.0
		cut_front = e_out(clampf(since / 0.85, 0.0, 1.0)) * H * 1.3 if state == "intro" else H * 1.3
		if cut_shock_t >= 0.0:
			cut_shock_t += dt
			if cut_shock_t > 2.5:
				cut_shock_t = -1.0
	cut_seam_boost *= exp(-dt * 2.2)
	if cut_done:
		cut_seam = 0.75 + 0.12 * sin(sim_t * 1.7) + 0.05 * sin(sim_t * 5.3) + cut_seam_boost
	elif cut_slashing != 0.0:
		cut_seam = 1.2
	else:
		cut_seam = 0.0

	# 开场前的寒光
	if state == "intro":
		cut_glint = sstep(float(TL["glint_a"]), float(TL["glint_a"]) + 0.25, it) * (1.0 - sstep(float(TL["slash_a"]) - 0.04, float(TL["slash_a"]) + 0.02, it))
	else:
		cut_glint = 0.0
	cut_tip_pos = Vector2(C.x + D.x * cut_sw, C.y + D.y * cut_sw)
	var u0g := _u_of(W * 0.035, seam_y(W * 0.035))
	cut_glint_pos = Vector2(C.x + D.x * u0g, C.y + D.y * u0g)

	# 待机：上面悬着的雨珠偶尔沉到刀口、断开、落进影子里
	if cut_done and (state == "menu" or state == "settings" or state == "confirm" or state == "intro"):
		next_drip -= dt
		if next_drip <= 0.0:
			next_drip = rnd(1.6, 3.8)
			var o_u := off_u()
			var cands: Array = []
			for d in drops:
				if d.layer == 0 and d.st == 1 and d.size < 4.0:
					var s := s_of(d.x + o_u.x, d.y + o_u.y)
					if s > -110.0 * k and s < -6.0 * k:
						cands.append(d)
				if cands.size() > 40:
					break
			if not cands.is_empty():
				cands[randi() % cands.size()].st = 2
		if randf() < dt * 7.0:
			var uu := rnd(-W * 0.55, W * 0.55)
			spawn_spark(C.x + D.x * uu, C.y + D.y * uu, rnd(-20.0, 20.0) * k, rnd(-50.0, -10.0) * k,
					rnd(1.2, 2.6), rnd(1.0, 2.2) * k, 3)

	# 收尾演出
	if state == "leave" or state == "exit":
		fin_t += dt
		var t := fin_t
		if state == "leave":
			var sw_dur := 0.17
			var u0 := -(W * 0.56 + 80.0)
			var u1 := W * 0.56 + 80.0
			if t < sw_dur:
				var kk := t / sw_dur
				var prev := cut_sw
				cut_slashing = 1.0
				cut_sw = u0 + (u1 - u0) * (kk * kk * 0.35 + kk * 0.65)
				sweep_sparks(prev, cut_sw)
			elif not fin_hit:
				fin_hit = true
				cut_slashing = 0.0
				cut_sw = -1e5
				hitstop = 0.09
				impact_rt = now
				trauma = 1.0
				cut_seam_boost = 5.0
				cut_shock_t = 0.0
				burst_line(C.x, C.y, D.x, D.y, _hyp(W, H), 600.0)
				shards_line(C.x, C.y, D.x, D.y, W, 70.0)
			fin_open = e_io(clampf((t - sw_dur - 0.04) / 1.6, 0.0, 1.0))
			fin_void = 0.0 if t < sw_dur else 1.0
			fin_fade = sstep(1.35, 2.15, t)
			if t > 2.25 and not fin_card:
				fin_card = true
				card_requested = true
		else:
			fin_collapse = e_in(clampf(t / 0.85, 0.0, 1.0)) * 0.997
			fin_seam_len = 1.0 - e_io(clampf((t - 0.85) / 0.5, 0.0, 1.0))
			cut_seam_boost = maxf(cut_seam_boost, 1.2 if t < 1.35 else 0.0)
			fin_fade = sstep(1.3, 1.7, t) * 0.4 + sstep(1.6, 1.9, t) * 0.6
			if t > 1.95 and not fin_card:
				fin_card = true
				card_requested = true
	if state == "return":
		fin_t += rdt
		fin_fade = 1.0 - sstep(0.0, 0.9, fin_t)
		fin_open = 0.0
		fin_collapse = 0.0
		fin_seam_len = 1.0
		fin_void = 0.0
		if fin_t > 0.9:
			state = "menu"
			fin_fade = 0.0

	# 玩家刀口愈合
	for i in range(slots.size() - 1, -1, -1):
		if sim_t - float(slots[i]["born"]) > 3.6:
			slots.remove_at(i)

	update_drops(dt)
	seam_splash(dt)
	update_fx(dt)

	# 镜头震动
	trauma = maxf(0.0, trauma - rdt * 1.5)
	if impact_rt >= 0.0:
		var e := now - impact_rt
		flash = 0.0 if e < 0.065 else maxf(0.0, 0.45 * exp(-(e - 0.065) * 11.0))
	else:
		flash = 0.0


var show_ui_requested := false
var card_requested := false


func _u_of(x: float, y: float) -> float:
	return (x - C.x) * D.x + (y - C.y) * D.y


func clamp01(v: float) -> float:
	return clampf(v, 0.0, 1.0)


func sstep(a: float, b: float, v: float) -> float:
	var t := clampf((v - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func e_out(t: float) -> float:
	return 1.0 - pow(1.0 - t, 3.0)


func e_in(t: float) -> float:
	return t * t * t


func e_io(t: float) -> float:
	if t < 0.5:
		return 4.0 * t * t * t
	return 1.0 - pow(-2.0 * t + 2.0, 3.0) / 2.0


# ---------------------------------------------------------------- 状态切换
func restart_intro() -> void:
	state = "intro"
	it = 0.0
	cut_sw = -1e5
	cut_on = 0.0
	cut_tip = -1e5
	cut_slashing = 0.0
	cut_slide = 0.0
	cut_slide_v = 0.0
	cut_gap = 0.0
	cut_front = 0.0
	cut_seam = 0.0
	cut_seam_boost = 0.0
	cut_shock_t = -1.0
	cut_done = false
	cut_glint = 0.0
	fin_open = 0.0
	fin_void = 0.0
	fin_collapse = 0.0
	fin_seam_len = 1.0
	fin_fade = 0.0
	fin_t = 0.0
	fin_kind = ""
	fin_card = false
	fin_hit = false
	slots.clear()
	fx.clear()
	impact_rt = -1.0
	card_requested = false
	show_ui_requested = false
	init_drops()
	next_drip = 6.0


func skip_intro() -> void:
	if state != "intro":
		return
	if it < float(TL["slash_a"]) - 0.25:
		it = float(TL["slash_a"]) - 0.25
		freeze_all()
	elif cut_done and it < float(TL["ui_a"]):
		it = float(TL["ui_a"]) - 0.01


func jump_to_menu() -> void:
	init_drops()
	freeze_all()
	cut_on = 1.0
	cut_done = true
	cut_tip = 1e5
	cut_slide = 15.0 * k
	cut_gap = 1.6 * k
	cut_front = H * 1.3
	it = float(TL["ui_a"]) + 1.0
	var o_u := off_u()
	for d in drops:
		if s_of(d.x + o_u.x, d.y + o_u.y) > 0.0:
			to_shadow(d)
			d.vy = d.vt


func begin_leave(kind: String) -> void:
	state = "leave"
	fin_t = 0.0
	fin_kind = kind
	fin_card = false
	fin_hit = false
	card_requested = false
	cut_sw = -(W * 0.56 + 80.0)
	trauma = 0.25


func begin_exit() -> void:
	state = "exit"
	fin_t = 0.0
	fin_card = false
	fin_kind = "exit"
	card_requested = false
	trauma = 0.35


func back_from_card() -> void:
	state = "return"
	fin_t = 0.0
	cut_slide = 15.0 * k
	cut_slide_v = 0.0
	fin_open = 0.0
	fin_collapse = 0.0
	fin_seam_len = 1.0
	fin_void = 0.0
	cut_seam_boost = 2.5
