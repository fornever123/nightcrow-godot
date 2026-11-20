extends Control
## [YG-MARK] 角色选择「扇刃」（用户 11-19：先选“B 加 C 的刀”，看完说“没有张力”，再选“做 B 扇刃”）
## 四张刀刃形角色卡像一手牌，从屏幕右下角外的钟轴扇开：选中的那张转到最左、最大，几乎和屏幕一样高；
## 另外三张依次往右转开、变小、变暗，被屏幕边裁掉一截。换人 = 整把扇绕钟轴转一格，背后的钟面跟着转。
## 卡窗里的内容永远正立（按屏幕坐标取样），不跟刀刃一起斜：
##   朔：常规比例立绘（roster_shuo.jpg）；萤 / 薇 / 曜：还没设计外观，只有过曝白光里的逆光黑剪影（尚在光中）。
## 进场：扇子从右边一甩打开，最前那张最后到、过冲一下落定，刀身上扫过一道亮光。
## 确认朔（shatter_out）：一刀把她那张卡拦腰斩断，剑尖那半截飞出去，另外三张沿各自刀身方向射出画面。
## 接口与 zz_roster.gd 相同（setup / enter / leave / shatter_out / select_index / idx / is_playable / bump_locked / update / hit_* / set_hover）。

const W := 1920.0
const H := 1080.0
const INK := Color("#08070c")
const WHITE := Color("#f5f2eb")
const STEEL := Color(0.70, 0.72, 0.78)
const DEG := PI / 180.0
const CARD_SHADER := preload("res://scripts/ui/yg_zhanzhong/zz_fan_card.gdshader")

const HUB := Vector2(1600.0, 1140.0)      # 钟轴（扇心），在屏幕右下角外
const FRAME_WL := 0.2893                  # 卡框素材的宽 / 长
const WIDE_Y := 0.27                      # 卡最宽处（从剑尖量）
const CUT := Vector2(-0.6, 0.8)           # 确认时那一刀：右上 → 左下

# 扇上的槽位：p = -1（刚离开最前、往左倒下）、0（最前）、1～3（往右转开）、4（最右、藏起）
const SLOT_TH := [84.0, 47.0, 19.0, 3.0, -12.0, -27.0]       # 刀身相对竖直往左倒的角度
const SLOT_LEN := [1480.0, 1600.0, 1170.0, 1090.0, 1010.0, 930.0]
const SLOT_WF := [0.40, 0.42, 0.30, 0.292, 0.285, 0.28]      # 宽 / 长
const SLOT_DIM := [0.6, 0.0, 0.22, 0.36, 0.48, 0.62]

const ROSTER := [
	{"key": "shuo", "word": "rs_shuo", "epithet": "夜鸦", "playable": true, "art": "roster_shuo",
		"face": Vector2(1180.0, 330.0),
		"quote": ["挡路的影，斩了；", "卡死的光，劈开。"], "traits": ["快剑连斩", "冲刺挥斩", "精准弹刀"]},
	{"key": "ying", "word": "rs_ying", "epithet": "惊风", "playable": false, "sil": "hc_sil_ying"},
	{"key": "wei", "word": "rs_wei", "epithet": "残火", "playable": false, "sil": "hc_sil_wei"},
	{"key": "yao", "word": "rs_yao", "epithet": "破晓", "playable": false, "sil": "hc_sil_yao"},
]

var T: Node = null
var font_cn: Font
var font_cn_med: Font
var font_lat: Font

var backdrop: ColorRect
var back: Control
var cards: Array = []      # [{node, mat, art_tex, fl, p, th, len, w, hub, poly}]
var front: Control
var fx: Control
var idx := 0
var reel := 0.0
var reel_v := 0.0
var shown := false
var now := 0.0
var t_enter := -10.0
var t_leave := -10.0
var t_sel := -10.0
var leave_mode := ""       # "slash"（确认进选章）/ "fade"（返回首页）
var lock_bump := 0.0
var hover_i := -1
var pointer := Vector2.ZERO
var glow_tex: GradientTexture2D


func setup(title: Node) -> void:
	T = title
	font_cn = T.font_cn
	font_cn_med = T.font_cn_med
	font_lat = T.font_lat
	size = Vector2(W, H)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

	backdrop = ColorRect.new()
	backdrop.color = Color(INK, 0.0)
	backdrop.size = Vector2(W * 1.4, H * 1.4)
	backdrop.position = Vector2(-W * 0.2, -H * 0.2)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	glow_tex = GradientTexture2D.new()
	glow_tex.gradient = g
	glow_tex.fill = GradientTexture2D.FILL_RADIAL
	glow_tex.fill_from = Vector2(0.5, 0.5)
	glow_tex.fill_to = Vector2(1.0, 0.5)
	glow_tex.width = 256
	glow_tex.height = 256

	back = _layer(_draw_back)
	for i in ROSTER.size():
		cards.append(_build_card(i))
	front = _layer(_draw_front)
	fx = _layer(_draw_fx)
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	fx.material = add


func _layer(fn: Callable) -> Control:
	var c := Control.new()
	c.size = Vector2(W, H)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(fn)
	add_child(c)
	return c


func _build_card(i: int) -> Dictionary:
	var item: Dictionary = ROSTER[i]
	var hp: Dictionary = T.HEROES[String(item["key"])]
	var node := Control.new()
	node.size = Vector2(W, H)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = CARD_SHADER
	m.set_shader_parameter("frame", T._tex("fan_frame"))
	m.set_shader_parameter("mask", T._tex("fan_mask"))
	m.set_shader_parameter("accent", hp["ui"])
	var tex: Texture2D
	if bool(item["playable"]):
		m.set_shader_parameter("mode", 0)
		tex = _load(String(item["art"]))
	else:
		m.set_shader_parameter("mode", 1)
		tex = T._tex(String(item["sil"]))
	m.set_shader_parameter("art", tex)
	node.material = m
	add_child(node)
	var c := {"node": node, "mat": m, "art_tex": tex, "fl": 0.0, "p": float(i),
		"th": 0.0, "len": 1000.0, "w": 300.0, "hub": HUB, "poly": PackedVector2Array(), "op": 0.0,
		"split": 0.0, "fly": 0.0}
	node.draw.connect(_draw_card.bind(c))
	return c


func _load(stem: String) -> Texture2D:
	for ext: String in [".jpg", ".png", ".webp"]:
		var p: String = "res://assets/image/yg_zhanzhong/" + stem + ext
		if ResourceLoader.exists(p):
			return load(p) as Texture2D
	return null


# ================================================================ 进出与选择
func enter(hero_key: String) -> void:
	shown = true
	visible = true
	leave_mode = ""
	t_enter = now
	idx = 0
	for i in ROSTER.size():
		if String(ROSTER[i]["key"]) == hero_key:
			idx = i
			break
	reel = float(idx)
	reel_v = 0.0
	t_sel = now
	for c in cards:
		c["fl"] = 0.0
		c["split"] = 0.0
		c["fly"] = 0.0


func leave() -> void:
	shown = false
	t_leave = now
	leave_mode = ""   # 下一帧看首页切到了哪：切进选章 = 斩开，回首页 = 收起（首页两种写法都兼容）


## 确认出战：拦腰斩断最前那张，另外三张沿刀身方向射出去，露出背后已经在推镜的选章舞台
func shatter_out() -> void:
	shown = false
	t_leave = now
	leave_mode = "slash"


func select_index(new_i: int) -> void:
	new_i = wrapi(new_i, 0, ROSTER.size())
	if new_i == idx or not shown:
		return
	idx = new_i
	t_sel = now
	(cards[idx] as Dictionary)["fl"] = 1.0
	if T != null:
		T._apply_hero(String(ROSTER[idx]["key"]), true)
		T._play("h3_slash_fast" if T.sfx.has("h3_slash_fast") else "ui_move", -4.5, 1.06)
		T.hitstop = 0.020
		T._hit(12.0, 0.010, 0.16)


func current_key() -> String:
	return String(ROSTER[idx]["key"])


func is_playable() -> bool:
	return bool(ROSTER[idx]["playable"])


func bump_locked() -> void:
	lock_bump = 1.0
	(cards[idx] as Dictionary)["fl"] = 0.9


func _open() -> float:
	if shown:
		return clampf((now - t_enter) / 0.18, 0.0, 1.0)
	var dur := 0.42 if leave_mode == "slash" else 0.16
	var q := clampf((now - t_leave) / dur, 0.0, 1.0)
	return 1.0 - q * q


func _back_out(x: float) -> float:
	# 一次过冲的缓出：扇子甩开时最前那张冲过头一点再落定
	var s := 1.9
	var u := x - 1.0
	return 1.0 + u * u * ((s + 1.0) * u + s)


# ================================================================ 每帧
func update(dt: float, ptr: Vector2) -> void:
	now += dt
	pointer = ptr
	if not shown and leave_mode == "":
		leave_mode = "slash" if T.screen == "select" else "fade"
	var op := _open()
	if not shown and op <= 0.005:
		visible = false
		return
	visible = true
	backdrop.color = Color(INK, 0.80 * op)
	lock_bump = maxf(0.0, lock_bump - dt * 3.2)

	var h := minf(dt, 1.0 / 30.0)
	var goal := reel + wrapf(float(idx) - reel, -2.0, 2.0)
	reel_v += ((goal - reel) * 230.0 - reel_v * 23.0) * h
	reel += reel_v * h

	var et := now - t_enter
	var lt := now - t_leave
	var par := (pointer.x / W - 0.5) * -16.0
	for i in cards.size():
		var c: Dictionary = cards[i]
		c["fl"] = maxf(0.0, float(c["fl"]) - dt * 2.6)
		var p := wrapf(float(i) - reel, -0.6, 3.4)
		# 进场：整把扇从右边藏起的位置一甩打开；越靠前的走得越远、到得越晚
		var stag := clampf((et - 0.04 * (3.0 - p)) / 0.42, 0.0, 1.0)
		var e := _back_out(stag) if stag < 1.0 else 1.0
		var pp := lerpf(4.0, p, e)
		c["p"] = pp
		var th := _slot(SLOT_TH, pp)
		var ln := _slot(SLOT_LEN, pp)
		var wf := _slot(SLOT_WF, pp)
		var dim := _slot(SLOT_DIM, pp)
		if not bool(ROSTER[i]["playable"]):
			dim *= 0.6
		var a := smoothstep(-0.3, -0.05, p) * (1.0 - smoothstep(3.0, 3.4, p)) * clampf(stag * 3.0, 0.0, 1.0)
		var front_k := 1.0 - clampf(absf(pp), 0.0, 1.0)
		var fl := float(c["fl"])
		ln *= 1.0 + 0.025 * fl * front_k
		var hub := HUB + Vector2(par * (0.5 + 0.3 * pp), 0.0)
		# 鼠标在卡上：顺着刀身探出来一截
		if hover_i == i and i != idx:
			dim *= 0.55
			ln += 26.0
		# 未开放被按：最前那张横着一抖、往回缩
		if i == idx and lock_bump > 0.0:
			th += sin(now * 62.0) * 1.6 * lock_bump
			ln *= 1.0 - 0.03 * lock_bump
		var opa := a * op
		var split := 0.0
		var fly := 0.0
		if not shown and leave_mode == "slash":
			if i == idx:
				split = pow(clampf((lt - 0.03) / 0.28, 0.0, 1.0), 0.5)
				opa = a * (1.0 - clampf((lt - 0.16) / 0.26, 0.0, 1.0))
			else:
				fly = pow(clampf(lt / 0.3, 0.0, 1.0), 1.6)
				opa = a * (1.0 - clampf(lt / 0.22, 0.0, 1.0))
		elif not shown:
			opa = a * op
		c["th"] = th
		c["len"] = ln
		c["w"] = ln * wf
		c["hub"] = hub
		c["op"] = opa
		c["split"] = split
		c["fly"] = fly
		var node: Control = c["node"]
		node.visible = opa > 0.005
		var m: ShaderMaterial = c["mat"]
		m.set_shader_parameter("dim", dim)
		m.set_shader_parameter("flash", 0.45 * fl * fl)
		m.set_shader_parameter("glow", lerpf(0.25, 1.0, front_k) * (1.0 + 0.6 * fl))
		m.set_shader_parameter("opacity", opa)
		m.set_shader_parameter("t", now)
		m.set_shader_parameter("card_len", ln)
		# 刀身扫光：进场到位那一下 + 每次转到最前
		var gs := clampf((et - 0.45 - 0.05 * (3.0 - p)) / 0.35, 0.0, 1.0)
		var gsel := clampf((now - t_sel - 0.08) / 0.35, 0.0, 1.0) if i == idx else 1.0
		var gk := minf(gs, gsel)
		m.set_shader_parameter("glint_y", lerpf(-0.1, 1.1, gk))
		m.set_shader_parameter("glint", 0.9 * sin(gk * PI) * (1.0 if gk < 1.0 else 0.0))
		_place_art(c, i)
		c["poly"] = _kite(c)
		node.queue_redraw()
	# 前后：离最前越近越靠上（只调子节点顺序，不用 z_index，免得盖住首页底边的键位提示）
	var order := range(cards.size())
	order.sort_custom(func(a: int, b: int) -> bool: return absf(float(cards[a]["p"])) > absf(float(cards[b]["p"])))
	var base := back.get_index() + 1
	for k in order.size():
		var nd: Control = cards[order[k]]["node"]
		if nd.get_index() != base + k:
			move_child(nd, base + k)
	back.queue_redraw()
	front.queue_redraw()
	fx.queue_redraw()


func _slot(tbl: Array, p: float) -> float:
	var q := clampf(p + 1.0, 0.0, float(tbl.size() - 1))
	var i0 := int(floor(q))
	var i1 := mini(i0 + 1, tbl.size() - 1)
	var f := q - float(i0)
	f = f * f * (3.0 - 2.0 * f)
	return lerpf(float(tbl[i0]), float(tbl[i1]), f)


func _dir(th_deg: float) -> Vector2:
	var a := th_deg * DEG
	return Vector2(-sin(a), -cos(a))


func _xf(c: Dictionary) -> Transform2D:
	return Transform2D(-float(c["th"]) * DEG, Vector2(c["hub"]) + _dir(float(c["th"])) * 2400.0 * float(c["fly"]))


## 卡窗内容（正立）摆在哪：朔的脸 / 剪影的身体，钉在刀身上某一点，跟着卡缩放
func _place_art(c: Dictionary, i: int) -> void:
	var item: Dictionary = ROSTER[i]
	var tex: Texture2D = c["art_tex"]
	var ln := float(c["len"])
	var hub: Vector2 = _xf(c).origin
	var d := _dir(float(c["th"]))
	var r: Rect2
	if bool(item["playable"]):
		var s := ln / 1600.0
		var anchor := hub + d * ln * 0.74
		var face: Vector2 = item["face"]
		r = Rect2(anchor - face * s, Vector2(tex.get_width(), tex.get_height()) * s)
	else:
		var sh := ln * 0.46
		var sw := sh * float(tex.get_width()) / float(tex.get_height())
		var anchor := hub + d * ln * 0.70
		r = Rect2(anchor - Vector2(sw, sh) * 0.5, Vector2(sw, sh))
	(c["mat"] as ShaderMaterial).set_shader_parameter("art_rect", Vector4(r.position.x, r.position.y, r.size.x, r.size.y))


## 刀刃轮廓（命中测试用）：剑尖、最宽两点、钟轴
func _kite(c: Dictionary) -> PackedVector2Array:
	var xf := _xf(c)
	var ln := float(c["len"])
	var w := float(c["w"])
	var yw := -ln * (1.0 - WIDE_Y)
	return PackedVector2Array([xf * Vector2(0, -ln), xf * Vector2(w * 0.5, yw), xf * Vector2(0, 0), xf * Vector2(-w * 0.5, yw)])


# ================================================================ 一张卡（四边形；斩开时是两片）
func _draw_card(c: Dictionary) -> void:
	var node: Control = c["node"]
	if float(c["op"]) <= 0.005:
		return
	var xf := _xf(c)
	var ln := float(c["len"])
	var w := float(c["w"])
	var quad := PackedVector2Array([xf * Vector2(-w * 0.5, -ln), xf * Vector2(w * 0.5, -ln), xf * Vector2(w * 0.5, 0), xf * Vector2(-w * 0.5, 0)])
	var split := float(c["split"])
	if split <= 0.0:
		_poly(node, quad, xf, Vector2.ZERO, w, ln)
		return
	# 拦腰一刀：过刀身 62% 处，方向固定（右上 → 左下）
	var cd := CUT.normalized()
	var n := Vector2(cd.y, -cd.x)
	var pc := xf * Vector2(0, -ln * 0.62)
	var big := 4000.0
	var half_a := PackedVector2Array([pc - cd * big, pc + cd * big, pc + cd * big + n * big, pc - cd * big + n * big])
	var half_b := PackedVector2Array([pc - cd * big, pc + cd * big, pc + cd * big - n * big, pc - cd * big - n * big])
	var axis := _dir(float(c["th"]))
	var gap := split * 70.0
	for k in 2:
		var side := 1.0 if k == 0 else -1.0
		var parts := Geometry2D.intersect_polygons(quad, half_a if k == 0 else half_b)
		# 剑尖那半截（在刀身方向更远的一侧）顺着刀身飞出去，钟轴那半截往回沉
		var tip_side := signf(n.dot(axis))
		var is_tip := side == tip_side
		var off := n * side * gap * 0.5 + (axis * split * 260.0 + cd * split * 60.0 if is_tip else -axis * split * 50.0 - cd * split * 30.0)
		for part: PackedVector2Array in parts:
			_poly(node, part, xf, off, w, ln)


func _poly(node: Control, pts: PackedVector2Array, xf: Transform2D, off: Vector2, w: float, ln: float) -> void:
	var inv := xf.affine_inverse()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var out := PackedVector2Array()
	var oc := Color(off.x / 1000.0 + 0.5, off.y / 1000.0 + 0.5, 0.0, 1.0)
	for q in pts:
		var l := inv * q
		uvs.append(Vector2(l.x / w + 0.5, 1.0 + l.y / ln))
		cols.append(oc)
		out.append(q + off)
	node.draw_polygon(out, cols, uvs)


# ================================================================ 背景层：钟面（跟着扇子转）、钟针、最前那张背后的光
func _draw_back() -> void:
	var op := _open()
	if op <= 0.01:
		return
	var c0: Dictionary = cards[idx]
	var col: Color = T.accent
	var hub := HUB
	# 大钟面：冷铁色，扇子转一格它转一格
	var dial: Texture2D = T._tex("dial")
	if dial != null:
		back.draw_set_transform(hub, -reel * 0.26 + 0.1, Vector2.ONE)
		back.draw_texture_rect(dial, Rect2(Vector2(-1150, -1150), Vector2(2300, 2300)), false, Color(0.56, 0.58, 0.64, 0.20 * op))
		back.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 刻度圈
	for j in 120:
		var a := -PI * 0.5 + (float(j) / 120.0) * TAU - reel * 0.26
		var d := Vector2(cos(a), sin(a))
		var big := j % 10 == 0
		var p0 := hub + d * 1290.0
		back.draw_line(p0, p0 + d * (26.0 if big else 10.0), Color(STEEL, (0.30 if big else 0.12) * op), 2.0 if big else 1.0, true)
	back.draw_arc(hub, 1290.0, 0.0, TAU, 180, Color(STEEL, 0.16 * op), 1.5, true)
	# 最前那张背后：她自己颜色的光
	var k := op * (0.75 + 0.25 * float(c0["fl"]))
	var cp := Vector2(c0["hub"]) + _dir(float(c0["th"])) * float(c0["len"]) * 0.68
	back.draw_texture_rect(glow_tex, Rect2(cp - Vector2(760, 760), Vector2(1520, 1520)), false, Color(col, 0.20 * k))
	# 每张刀卡压在钟面上的投影：往右下错开一截的黑影，让卡从背景里立起来
	for cc: Dictionary in cards:
		if float(cc["op"]) < 0.02 or float(cc["split"]) > 0.0:
			continue
		var kp: PackedVector2Array = cc["poly"]
		if kp.size() < 4:
			continue
		var sh := PackedVector2Array()
		var ctr := (kp[0] + kp[2]) * 0.5
		for q in kp:
			sh.append(ctr + (q - ctr) * 1.04 + Vector2(18, 22))
		back.draw_colored_polygon(sh, Color(0, 0, 0, 0.55 * float(cc["op"])))
	# 钟的分针：从钟轴往右上伸出去的一根长钢针，扇子就挂在它上面
	var ha := -32.0 - reel * 4.0
	var hd := _dir(ha)
	var hn := Vector2(hd.y, -hd.x)
	var tip := hub + hd * 1180.0
	back.draw_colored_polygon(PackedVector2Array([hub + hn * 12.0, tip, hub - hn * 12.0]), Color(STEEL * 0.8, 0.9 * op))
	back.draw_line(hub, tip, Color(WHITE, 0.55 * op), 1.5, true)
	var dm := hub + hd * 900.0
	back.draw_colored_polygon(PackedVector2Array([dm + hd * 46.0, dm + hn * 16.0, dm - hd * 30.0, dm - hn * 16.0]), Color(STEEL, 0.9 * op))


# ================================================================ 前景层：左侧信息、页眉、后排卡的名牌、钟轴
func _draw_front() -> void:
	var op := _open()
	if op <= 0.01:
		return
	var item: Dictionary = ROSTER[idx]
	var hp: Dictionary = T.HEROES[String(item["key"])]
	var col: Color = hp["ui"]
	var c := front
	var si := clampf((now - t_sel) / 0.32, 0.0, 1.0)
	var se := 1.0 - pow(1.0 - si, 3.0)
	var ia := op * se
	var dx := -50.0 * (1.0 - se)

	# 后排卡的名牌：正立，钉在刀身下段
	for i in cards.size():
		var cc: Dictionary = cards[i]
		if i == idx or float(cc["op"]) < 0.05 or float(cc["split"]) > 0.0:
			continue
		var it: Dictionary = ROSTER[i]
		var ic: Color = T.HEROES[String(it["key"])]["ui"]
		var ca := float(cc["op"]) * (1.0 - 0.5 * float(cc["fly"]))
		var pos := _xf(cc) * Vector2(0, -float(cc["len"]) * 0.47)
		var word: Texture2D = T._tex(String(it["word"]))
		var wh := 66.0
		var ww := wh * float(word.get_width()) / float(word.get_height())
		c.draw_texture_rect(word, Rect2(pos + Vector2(-ww * 0.5 + 3, -wh + 4), Vector2(ww, wh)), false, Color(0, 0, 0, 0.8 * ca))
		c.draw_texture_rect(word, Rect2(pos + Vector2(-ww * 0.5, -wh), Vector2(ww, wh)), false, Color(WHITE, ca))
		c.draw_line(pos + Vector2(-58, 10), pos + Vector2(58, 10), Color(ic, 0.95 * ca), 3.0)
		if not bool(it["playable"]):
			var tx := "尚在光中"
			var ts := font_cn_med.get_string_size(tx, HORIZONTAL_ALIGNMENT_LEFT, -1, 24)
			c.draw_string(font_cn_med, pos + Vector2(-ts.x * 0.5 + 2, 46), tx, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(0, 0, 0, 0.7 * ca))
			c.draw_string(font_cn_med, pos + Vector2(-ts.x * 0.5, 44), tx, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(0.92, 0.92, 0.95, ca))

	# 钟轴：几圈铁环压住所有刀刃的根
	var hub := HUB
	c.draw_circle(hub, 92.0, Color(0.05, 0.05, 0.07, 0.95 * op))
	c.draw_arc(hub, 92.0, 0.0, TAU, 64, Color(STEEL, 0.9 * op), 3.0, true)
	c.draw_arc(hub, 70.0, 0.0, TAU, 64, Color(STEEL, 0.5 * op), 1.5, true)
	c.draw_circle(hub, 22.0, Color(col, 0.9 * op))

	# 页眉：左上斜切白牌「选择主角」
	var tt: Texture2D = T._tex("rs_title")
	var th := 58.0
	var tw := th * float(tt.get_width()) / float(tt.get_height())
	var pr := Rect2(Vector2(40, 40), Vector2(tw + 96, 92))
	c.draw_colored_polygon(_slant(pr.position + Vector2(6, 7), pr.size, 30.0), Color(0, 0, 0, 0.7 * op))
	c.draw_colored_polygon(_slant(pr.position, pr.size, 30.0), Color(WHITE, 0.96 * op))
	c.draw_colored_polygon(_slant(pr.position + Vector2(18, 0), Vector2(16, pr.size.y), 30.0), Color(col, op))
	c.draw_texture_rect(tt, Rect2(pr.position + Vector2(58, (pr.size.y - th) * 0.5), Vector2(tw, th)), false, Color(INK, op))

	# 名字大字：斜着压，身后一道她颜色的错位影
	var word: Texture2D = T._tex(String(item["word"]))
	var wh := 270.0
	var ww := wh * float(word.get_width()) / float(word.get_height())
	var wp := Vector2(70 + dx * 1.4, 170)
	c.draw_set_transform_matrix(Transform2D(0.0, Vector2.ONE, -0.16, wp))
	c.draw_texture_rect(word, Rect2(Vector2(14, 12), Vector2(ww, wh)), false, Color(col, 0.85 * ia))
	c.draw_texture_rect(word, Rect2(Vector2(5, 7), Vector2(ww, wh)), false, Color(0, 0, 0, 0.9 * ia))
	c.draw_texture_rect(word, Rect2(Vector2.ZERO, Vector2(ww, wh)), false, Color(WHITE, ia))
	c.draw_set_transform_matrix(Transform2D.IDENTITY)
	# 称号 + 一道斜线
	var ep := String(item["epithet"])
	var ey := 500.0
	c.draw_string(font_cn, Vector2(84 + dx, ey + 4), ep, HORIZONTAL_ALIGNMENT_LEFT, -1, 58, Color(0, 0, 0, 0.8 * ia))
	c.draw_string(font_cn, Vector2(80 + dx, ey), ep, HORIZONTAL_ALIGNMENT_LEFT, -1, 58, Color(WHITE, ia))
	c.draw_colored_polygon(PackedVector2Array([Vector2(60 + dx, ey + 24), Vector2(400 + dx, ey + 12), Vector2(400 + dx, ey + 16), Vector2(60 + dx, ey + 30)]), Color(col, ia))

	if bool(item["playable"]):
		var qy := 586.0
		for li in (item["quote"] as Array).size():
			var q := String(item["quote"][li])
			c.draw_string(font_cn_med, Vector2(74 + dx * 0.8, qy + li * 48 + 3), q, HORIZONTAL_ALIGNMENT_LEFT, -1, 36, Color(0, 0, 0, 0.8 * ia))
			c.draw_string(font_cn_med, Vector2(72 + dx * 0.8, qy + li * 48), q, HORIZONTAL_ALIGNMENT_LEFT, -1, 36, Color(WHITE, 0.95 * ia))
		var ty := 712.0
		for k in (item["traits"] as Array).size():
			var dly := clampf((now - t_sel - 0.06 * k) / 0.25, 0.0, 1.0)
			var ka := op * (1.0 - pow(1.0 - dly, 3.0))
			var pos := Vector2(56 + (1.0 - ka) * -40.0 - k * 6.0, ty + k * 76)
			c.draw_colored_polygon(_slant(pos + Vector2(6, 7), Vector2(330, 62), 20.0), Color(0, 0, 0, 0.7 * ka))
			c.draw_colored_polygon(_slant(pos, Vector2(330, 62), 20.0), Color(WHITE, 0.95 * ka))
			c.draw_colored_polygon(_slant(pos, Vector2(70, 62), 20.0), Color(INK, 0.92 * ka))
			_diamond(c, pos + Vector2(38, 31), 11.0, Color(col, ka))
			c.draw_string(font_cn, pos + Vector2(92, 45), String(item["traits"][k]), HORIZONTAL_ALIGNMENT_LEFT, -1, 36, Color(INK, ka))
	else:
		var ty := 620.0
		var tx := "尚在光中"
		c.draw_string(font_cn, Vector2(74 + dx * 0.8, ty + 4), tx, HORIZONTAL_ALIGNMENT_LEFT, -1, 54, Color(0, 0, 0, 0.8 * ia))
		c.draw_string(font_cn, Vector2(72 + dx * 0.8, ty), tx, HORIZONTAL_ALIGNMENT_LEFT, -1, 54, Color(WHITE, 0.96 * ia * (1.0 - 0.5 * lock_bump)))
		c.draw_rect(Rect2(56 + dx * 0.8, ty - 48, 5, 58), Color(col, ia))
		c.draw_string(font_cn_med, Vector2(74 + dx * 0.6, ty + 60), "她还停在光里，尚未出场", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(0.74, 0.74, 0.8, ia))
		if lock_bump > 0.0:
			c.draw_rect(Rect2(0, 0, W, H), Color(1, 1, 1, 0.16 * lock_bump * lock_bump))


# ================================================================ 光效层（叠加）：确认那一刀
func _draw_fx() -> void:
	if shown or leave_mode != "slash":
		return
	var lt := now - t_leave
	var line := clampf(lt / 0.04, 0.0, 1.0) * (1.0 - clampf((lt - 0.1) / 0.24, 0.0, 1.0))
	if line <= 0.0:
		return
	var c0: Dictionary = cards[idx]
	var col: Color = T.accent
	var cd := CUT.normalized()
	var n := Vector2(cd.y, -cd.x)
	var pc := _xf(c0) * Vector2(0, -float(c0["len"]) * 0.62)
	var reach := 1500.0 * clampf(lt / 0.06, 0.0, 1.0)
	# 刀光：两头尖、中段最粗；外面一层她的颜色
	var widths: Array[float] = [30.0, 12.0, 4.0]
	var colors: Array[Color] = [Color(col, 0.35), Color(col.lerp(WHITE, 0.4), 0.7), Color(1, 1, 1, 1.0)]
	for layer in 3:
		var wdt: float = widths[layer] * (1.0 - 0.6 * clampf(lt / 0.3, 0.0, 1.0))
		var lc: Color = colors[layer]
		lc.a *= line
		fx.draw_colored_polygon(PackedVector2Array([pc - cd * reach, pc + n * wdt, pc + cd * reach, pc - n * wdt]), lc)


func _slant(p: Vector2, s: Vector2, sl: float) -> PackedVector2Array:
	return PackedVector2Array([p + Vector2(sl, 0), p + Vector2(s.x, 0), p + Vector2(s.x - sl, s.y), p + Vector2(0, s.y)])


func _diamond(c: CanvasItem, p: Vector2, r: float, col: Color) -> void:
	c.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0)]), col)


# ================================================================ 鼠标命中
func hit_slice(p: Vector2) -> int:
	if not shown:
		return -1
	var order := range(cards.size())
	order.sort_custom(func(a: int, b: int) -> bool: return absf(float(cards[a]["p"])) < absf(float(cards[b]["p"])))
	for i: int in order:
		var c: Dictionary = cards[i]
		if float(c["op"]) > 0.3 and Geometry2D.is_point_in_polygon(p, c["poly"]):
			return i
	return -1


func hit_cta(p: Vector2) -> bool:
	return shown and hit_slice(p) == idx


func set_hover(p: Vector2) -> bool:
	hover_i = hit_slice(p)
	return hover_i >= 0
