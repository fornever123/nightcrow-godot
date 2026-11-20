extends Control
## [YG-MARK] 角色选择「钟铸铁卡」（用户 11-19 选 B + C 的刀）
## 四张哥特铸铁表盘卡（卡顶 I～IV），沿一段钟面弧线排开：选中的卡在最前最大、正对镜头，铁艺镂空孔里透出她的颜色；
## 其余三张依次退后、侧转。换人 = 整条弧像钟面一样转一格，新到最前的那张一闪。
## 朔是唯一能玩的：卡里是现成立绘，剑冲出卡框。萤 / 薇 / 曜 还没设计外观，卡里是一片过曝白光里的逆光黑剪影（尚在光中）。
## 确认朔：一道紫刀光把她的卡斩成两半，直接切进「拨钟选章」。按在未开放的人身上：卡被白光弹回来。
## 接口与 zz_roster.gd 相同（setup / enter / leave / select_index / idx / is_playable / bump_locked / update / hit_* / set_hover），
## zz_title 只换了 preload。

const W := 1920.0
const H := 1080.0
const INK := Color("#08070c")
const WHITE := Color("#f5f2eb")
const DEG := PI / 180.0
const FACE_SHADER := preload("res://scripts/ui/yg_zhanzhong/zz_hc_face.gdshader")
const CARD_SHADER := preload("res://scripts/ui/yg_zhanzhong/zz_hc_card.gdshader")

const VP := Vector2(900.0, 1100.0)        # 每张卡的画布（比卡大，留给冲出卡框的剑）
const CARD := Vector2(640.0, 960.0)       # 卡本身
const CARD_O := Vector2(130.0, 70.0)      # 卡在画布里的左上角
const WIN := Rect2(0.188, 0.275, 0.622, 0.549)   # 卡窗（卡 UV）
const MEDAL := Vector2(0.5, 0.195)        # 卡顶圆徽章中心
const PLATE := Rect2(0.234, 0.833, 0.537, 0.085) # 卡底铭牌
const NUMS := ["I", "II", "III", "IV"]

# 弧线上的槽位：p = -1（刚离开最前、往左下沉）、0（最前）、1～3（往右后退）、4（最远）
const SLOT_X := [-260.0, 690.0, 1150.0, 1440.0, 1690.0, 1900.0]
const SLOT_Y := [640.0, 572.0, 600.0, 612.0, 622.0, 628.0]
const SLOT_H := [700.0, 880.0, 590.0, 510.0, 440.0, 380.0]
const SLOT_YAW := [38.0, 9.0, -26.0, -32.0, -37.0, -42.0]
const SLOT_DIM := [0.6, 0.0, 0.38, 0.52, 0.62, 0.72]

const ROSTER := [
	{"key": "shuo", "word": "rs_shuo", "epithet": "夜鸦", "playable": true,
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
var cards: Array = []      # [{vp, face, inner, mat_face, disp, mat, fl, bump}]
var front: Control
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

	back = Control.new()
	back.size = Vector2(W, H)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.draw.connect(_draw_back)
	add_child(back)

	for i in ROSTER.size():
		cards.append(_build_card(i))

	front = Control.new()
	front.size = Vector2(W, H)
	front.mouse_filter = Control.MOUSE_FILTER_IGNORE
	front.draw.connect(_draw_front)
	add_child(front)


func _build_card(i: int) -> Dictionary:
	var item: Dictionary = ROSTER[i]
	var hp: Dictionary = T.HEROES[String(item["key"])]
	var vp := SubViewport.new()
	vp.size = Vector2i(VP)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(vp)

	var inner := ColorRect.new()
	inner.position = CARD_O
	inner.size = CARD
	var mf := ShaderMaterial.new()
	mf.shader = FACE_SHADER
	mf.set_shader_parameter("mask", T._tex("hc_mask"))
	mf.set_shader_parameter("dial", T._tex("dial"))
	mf.set_shader_parameter("accent", hp["ui"])
	mf.set_shader_parameter("card_px", CARD)
	mf.set_shader_parameter("mode", 0 if bool(item["playable"]) else 1)
	if item.has("sil"):
		var st: Texture2D = T._tex(String(item["sil"]))
		mf.set_shader_parameter("art", st)
		# 剪影：高占窗口 88%，脚踩在窗口底边上方一点
		var wh := WIN.size.y * CARD.y
		var sh := wh * 0.88
		var sw := sh * float(st.get_width()) / float(st.get_height())
		var by := (WIN.position.y + WIN.size.y) * CARD.y - wh * 0.03
		var cx := (WIN.position.x + WIN.size.x * 0.5) * CARD.x
		var r := Rect2(cx - sw * 0.5, by - sh, sw, sh)
		mf.set_shader_parameter("art_rect", Vector4(r.position.x / CARD.x, r.position.y / CARD.y, r.end.x / CARD.x, r.end.y / CARD.y))
	inner.material = mf
	vp.add_child(inner)

	var face := Control.new()
	face.size = VP
	face.draw.connect(_draw_face.bind(i))
	vp.add_child(face)

	var disp := ColorRect.new()
	disp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = CARD_SHADER
	m.set_shader_parameter("face", vp.get_texture())
	m.set_shader_parameter("vp_size", VP)
	m.set_shader_parameter("accent", hp["ui"])
	disp.material = m
	add_child(disp)
	return {"vp": vp, "face": face, "inner": inner, "mat_face": mf, "disp": disp, "mat": m,
		"fl": 0.0, "p": float(i), "rect": Rect2()}


# ================================================================ 进出与选择
func enter(hero_key: String) -> void:
	shown = true
	visible = true
	leave_mode = ""
	t_enter = now
	for c in cards:
		(c["vp"] as SubViewport).render_target_update_mode = SubViewport.UPDATE_ALWAYS
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
	(cards[idx] as Dictionary)["fl"] = 1.0


func leave() -> void:
	shown = false
	t_leave = now
	leave_mode = ""


func select_index(new_i: int) -> void:
	new_i = wrapi(new_i, 0, ROSTER.size())
	if new_i == idx or not shown:
		return
	idx = new_i
	t_sel = now
	(cards[idx] as Dictionary)["fl"] = 1.0
	T._apply_hero(String(ROSTER[idx]["key"]), true)


func is_playable() -> bool:
	return bool(ROSTER[idx]["playable"])


func bump_locked() -> void:
	lock_bump = 1.0
	(cards[idx] as Dictionary)["fl"] = 0.9


func _enter_k() -> float:
	return clampf((now - t_enter) / 0.5, 0.0, 1.0)


func _open() -> float:
	if shown:
		var p := clampf((now - t_enter) / 0.3, 0.0, 1.0)
		return 1.0 - pow(1.0 - p, 3.0)
	var dur := 0.5 if leave_mode == "slash" else 0.22
	var q := clampf((now - t_leave) / dur, 0.0, 1.0)
	return 1.0 - q * q


# ================================================================ 每帧
func update(dt: float, ptr: Vector2) -> void:
	now += dt
	pointer = ptr
	if not shown and leave_mode == "":
		leave_mode = "slash" if T.screen == "select" else "fade"
	var op := _open()
	if not shown and op <= 0.005:
		visible = false
		for c in cards:
			(c["vp"] as SubViewport).render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	visible = true
	backdrop.color = Color(INK, 0.84 * op)
	lock_bump = maxf(0.0, lock_bump - dt * 3.2)

	# 弧线转动：弹簧追到选中那一格（走最短的方向）
	var h := minf(dt, 1.0 / 30.0)
	var goal := reel + wrapf(float(idx) - reel, -2.0, 2.0)
	reel_v += ((goal - reel) * 230.0 - reel_v * 23.0) * h
	reel += reel_v * h

	var ek := _enter_k()
	var lt := now - t_leave
	for i in cards.size():
		var c: Dictionary = cards[i]
		c["fl"] = maxf(0.0, float(c["fl"]) - dt * 3.0)
		var p := wrapf(float(i) - reel, -0.6, 3.4)
		# 进场：从右后方沿弧线滑进来，一张接一张
		var stag := clampf((ek - 0.08 * float(i)) / 0.75, 0.0, 1.0)
		var e := 1.0 - pow(1.0 - stag, 3.0)
		var pp := p + (1.0 - e) * 3.0
		c["p"] = pp
		var x := _slot(SLOT_X, pp)
		var y := _slot(SLOT_Y, pp)
		var hh := _slot(SLOT_H, pp)
		var yaw := _slot(SLOT_YAW, pp) * DEG
		var dim := _slot(SLOT_DIM, pp)
		if not bool(ROSTER[i]["playable"]):
			dim *= 0.55   # 白光卡退到后面也还是亮的
		var a := smoothstep(-0.3, -0.05, pp) * (1.0 - smoothstep(3.0, 3.4, pp)) * e
		var front_k := 1.0 - clampf(absf(pp), 0.0, 1.0)
		# 新到最前那张：一闪 + 往前顶一下
		var fl := float(c["fl"])
		hh *= 1.0 + 0.03 * fl * front_k
		# 未开放被按：最前那张被白光弹回（左右抖 + 往后缩）
		if i == idx and lock_bump > 0.0:
			x += sin(now * 70.0) * 16.0 * lock_bump
			hh *= 1.0 - 0.04 * lock_bump
		# 鼠标在卡上：轻轻探出
		if hover_i == i and i != idx:
			dim *= 0.6
			y -= 10.0
		# 视差：鼠标把整条弧轻轻带动
		x += (pointer.x / W - 0.5) * -14.0 * (1.0 + pp * 0.3)
		var sc := hh / CARD.y
		var rs := VP * sc * Vector2(1.5, 1.08)
		var disp: ColorRect = c["disp"]
		disp.size = rs
		disp.position = Vector2(x, y) - rs * 0.5
		var m: ShaderMaterial = c["mat"]
		m.set_shader_parameter("rect_size", rs)
		m.set_shader_parameter("scale", sc)
		m.set_shader_parameter("yaw", yaw)
		m.set_shader_parameter("focal", 1700.0)
		m.set_shader_parameter("dim", dim)
		m.set_shader_parameter("flash", 0.5 * fl * fl)
		m.set_shader_parameter("thick", 16.0)
		var split := 0.0
		var line := 0.0
		var opa := a * op
		if not shown and leave_mode == "slash":
			if i == idx:
				line = clampf(lt / 0.05, 0.0, 1.0) * (1.0 - clampf((lt - 0.18) / 0.3, 0.0, 1.0))
				split = pow(clampf((lt - 0.04) / 0.3, 0.0, 1.0), 0.5)
				opa = a * (1.0 - clampf((lt - 0.2) / 0.3, 0.0, 1.0))
			else:
				opa = a * (1.0 - clampf(lt / 0.12, 0.0, 1.0))
		m.set_shader_parameter("split", split)
		m.set_shader_parameter("slash_line", line)
		m.set_shader_parameter("opacity", opa)
		disp.visible = opa > 0.005
		# 前后：离最前越近越靠上
		disp.z_index = 10 - int(round(absf(pp) * 2.0))
		c["rect"] = Rect2(x - CARD.x * sc * 0.5 * absf(cos(yaw)), y - CARD.y * sc * 0.5, CARD.x * sc * absf(cos(yaw)), CARD.y * sc)
		var mf: ShaderMaterial = c["mat_face"]
		mf.set_shader_parameter("t", now)
		mf.set_shader_parameter("glow", lerpf(0.12, 1.0, front_k) * (1.0 + 0.6 * fl))
		mf.set_shader_parameter("flash", 0.0)
		(c["face"] as Control).queue_redraw()
	back.queue_redraw()
	front.queue_redraw()


func _slot(tbl: Array, p: float) -> float:
	var q := clampf(p + 1.0, 0.0, float(tbl.size() - 1))
	var i0 := int(floor(q))
	var i1 := mini(i0 + 1, tbl.size() - 1)
	var f := q - float(i0)
	f = f * f * (3.0 - 2.0 * f)
	return lerpf(float(tbl[i0]), float(tbl[i1]), f)


# ================================================================ 卡面（画在每张卡自己的画布里）
func _draw_face(i: int) -> void:
	var c: Control = (cards[i] as Dictionary)["face"]
	var item: Dictionary = ROSTER[i]
	var hp: Dictionary = T.HEROES[String(item["key"])]
	var col: Color = hp["ui"]
	var on := i == idx
	var frame: Texture2D = T._tex("hc_frame")
	c.draw_texture_rect(frame, Rect2(CARD_O, CARD), false)
	# 卡顶罗马数字
	var mc := CARD_O + MEDAL * CARD
	var num: String = NUMS[i]
	var fs := 58
	var ns := font_lat.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var np := mc + Vector2(-ns.x * 0.5, ns.y * 0.3)
	c.draw_string(font_lat, np + Vector2(3, 4), num, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.8))
	c.draw_string(font_lat, np, num, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.86, 0.86, 0.9) if not on else col.lerp(WHITE, 0.55))
	# 铭牌：名字（刀锋宋）+ 未开放的「尚在光中」
	var pr := Rect2(CARD_O + PLATE.position * CARD, PLATE.size * CARD)
	var word: Texture2D = T._tex(String(item["word"]))
	var locked := not bool(item["playable"])
	var wh := 50.0 if locked else 62.0
	var ww := wh * float(word.get_width()) / float(word.get_height())
	var wy := pr.position.y + (6.0 if locked else (pr.size.y - wh) * 0.5)
	c.draw_texture_rect(word, Rect2(pr.get_center().x - ww * 0.5 + 3, wy + 4, ww, wh), false, Color(0, 0, 0, 0.85))
	c.draw_texture_rect(word, Rect2(pr.get_center().x - ww * 0.5, wy, ww, wh), false, Color(0.95, 0.94, 0.92))
	if locked:
		var tx := "尚在光中"
		var ts := font_cn_med.get_string_size(tx, HORIZONTAL_ALIGNMENT_LEFT, -1, 22)
		c.draw_string(font_cn_med, Vector2(pr.get_center().x - ts.x * 0.5, pr.end.y - 6), tx, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.8, 0.8, 0.84))
		# 铭牌两端一线她自己的颜色
		c.draw_line(Vector2(pr.position.x + 30, pr.end.y - 13), Vector2(pr.get_center().x - ts.x * 0.5 - 12, pr.end.y - 13), Color(col, 0.9), 2.0)
		c.draw_line(Vector2(pr.get_center().x + ts.x * 0.5 + 12, pr.end.y - 13), Vector2(pr.end.x - 30, pr.end.y - 13), Color(col, 0.9), 2.0)
	else:
		# 朔：立绘画在铁框上面，剑冲出卡框
		var art: Texture2D = T._tex("hc_shuo")
		var win_r := Rect2(CARD_O + WIN.position * CARD, WIN.size * CARD)
		var ah := win_r.size.y * 1.16
		var aw := ah * float(art.get_width()) / float(art.get_height())
		var ax := win_r.get_center().x - aw * 0.5 - 30.0
		var ay := win_r.end.y - ah + 4.0
		# 脚下一圈主角色的光，立绘落在光上
		c.draw_texture_rect(glow_tex, Rect2(win_r.get_center().x - 200, win_r.end.y - 70, 400, 120), false, Color(col, 0.55))
		c.draw_texture_rect(art, Rect2(ax, ay, aw, ah), false)


# ================================================================ 背景层：最前那张卡后面的光
func _draw_back() -> void:
	var op := _open()
	if op <= 0.01:
		return
	var col: Color = T.accent
	var c0: Dictionary = cards[idx]
	var r: Rect2 = c0["rect"]
	var k := op * (0.75 + 0.25 * float(c0["fl"]))
	back.draw_texture_rect(glow_tex, Rect2(r.get_center() - Vector2(620, 620), Vector2(1240, 1240)), false, Color(col, 0.22 * k))
	back.draw_texture_rect(glow_tex, Rect2(r.get_center() + Vector2(-420, 300), Vector2(840, 260)), false, Color(col, 0.35 * k))
	# 底边：一段钟面弧刻度，卡都站在这条弧上
	var cc := Vector2(1150, 2600)
	var rr := 1790.0
	for j in 61:
		var a := lerpf(-PI * 0.5 - 0.42, -PI * 0.5 + 0.42, float(j) / 60.0)
		var d := Vector2(cos(a), sin(a))
		var big := j % 5 == 0
		var p0 := cc + d * rr
		back.draw_line(p0, p0 + d * (18.0 if big else 8.0), Color(WHITE, (0.32 if big else 0.14) * op), 2.0 if big else 1.0, true)
	back.draw_arc(cc, rr, -PI * 0.5 - 0.42, -PI * 0.5 + 0.42, 96, Color(WHITE, 0.22 * op), 1.5, true)


# ================================================================ 前景层：左侧信息、页眉、确认刀光
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
	var dx := -40.0 * (1.0 - se)

	# 页眉：右上「选择主角」+ 一道刀形线
	var tt: Texture2D = T._tex("rs_title")
	var th := 62.0
	var tw := th * float(tt.get_width()) / float(tt.get_height())
	var tp := Vector2(W - 96 - tw, 58)
	c.draw_texture_rect(tt, Rect2(tp + Vector2(4, 5), Vector2(tw, th)), false, Color(0, 0, 0, 0.8 * op))
	c.draw_texture_rect(tt, Rect2(tp, Vector2(tw, th)), false, Color(WHITE, op))
	var ly := tp.y + th + 18
	c.draw_colored_polygon(PackedVector2Array([Vector2(tp.x - 260, ly), Vector2(W - 70, ly - 2), Vector2(W - 70, ly + 2), Vector2(tp.x - 260, ly + 1)]), Color(WHITE, 0.5 * op))
	_diamond(c, Vector2(tp.x - 268, ly), 6.0, Color(col, op))

	# 名字大字
	var word: Texture2D = T._tex(String(item["word"]))
	var wh := 230.0
	var ww := wh * float(word.get_width()) / float(word.get_height())
	var wp := Vector2(64 + dx * 1.4, 150)
	c.draw_texture_rect(word, Rect2(wp + Vector2(7, 9), Vector2(ww, wh)), false, Color(0, 0, 0, 0.85 * ia))
	c.draw_texture_rect(word, Rect2(wp, Vector2(ww, wh)), false, Color(WHITE, ia))
	# 称号铭牌（斜切白牌）
	var ep := String(item["epithet"])
	var er := Rect2(Vector2(70 + dx, 398), Vector2(196, 58))
	c.draw_colored_polygon(_slant(er.grow(0).position + Vector2(5, 6), er.size, 16.0), Color(0, 0, 0, 0.7 * ia))
	c.draw_colored_polygon(_slant(er.position, er.size, 16.0), Color(WHITE, 0.95 * ia))
	c.draw_colored_polygon(_slant(er.position, Vector2(14, er.size.y), 16.0), Color(col, ia))
	c.draw_string(font_cn, er.position + Vector2(44, 44), ep, HORIZONTAL_ALIGNMENT_LEFT, -1, 40, Color(INK, ia))

	if bool(item["playable"]):
		var qy := 520.0
		for li in (item["quote"] as Array).size():
			c.draw_string(font_cn_med, Vector2(72 + dx * 0.8, qy + li * 46), String(item["quote"][li]), HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color(WHITE, 0.92 * ia))
		c.draw_rect(Rect2(56 + dx * 0.8, qy - 30, 4, 84), Color(col, ia))
		var ty := 650.0
		for k in (item["traits"] as Array).size():
			var dly := clampf((now - t_sel - 0.06 * k) / 0.25, 0.0, 1.0)
			var ka := op * (1.0 - pow(1.0 - dly, 3.0))
			var pos := Vector2(66 + (1.0 - ka) * -30.0, ty + k * 72)
			c.draw_colored_polygon(_slant(pos + Vector2(5, 6), Vector2(228, 56), 14.0), Color(0, 0, 0, 0.7 * ka))
			c.draw_colored_polygon(_slant(pos, Vector2(228, 56), 14.0), Color(WHITE, 0.94 * ka))
			c.draw_colored_polygon(_slant(pos + Vector2(14, 0), Vector2(10, 56), 14.0), Color(col, ka))
			c.draw_string(font_cn, pos + Vector2(46, 41), String(item["traits"][k]), HORIZONTAL_ALIGNMENT_LEFT, -1, 32, Color(INK, ka))
	else:
		var ty := 540.0
		var tx := "尚在光中"
		c.draw_string(font_cn, Vector2(72 + dx * 0.8, ty), tx, HORIZONTAL_ALIGNMENT_LEFT, -1, 46, Color(WHITE, 0.95 * ia * (1.0 - 0.5 * lock_bump)))
		c.draw_rect(Rect2(56 + dx * 0.8, ty - 42, 4, 52), Color(col, ia))
		c.draw_string(font_cn_med, Vector2(74 + dx * 0.6, ty + 56), "她还停在光里，尚未出场", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(0.72, 0.72, 0.78, ia))
		if lock_bump > 0.0:
			c.draw_rect(Rect2(0, 0, W, H), Color(1, 1, 1, 0.16 * lock_bump * lock_bump))

	# 确认出战：斩开那一下的全屏闪
	if not shown and leave_mode == "slash":
		var lt := now - t_leave
		var f := clampf(1.0 - (lt - 0.04) / 0.16, 0.0, 1.0) * clampf(lt / 0.04, 0.0, 1.0)
		if f > 0.0:
			c.draw_rect(Rect2(0, 0, W, H), Color(col.lerp(WHITE, 0.6), 0.28 * f))


func _slant(p: Vector2, s: Vector2, sl: float) -> PackedVector2Array:
	return PackedVector2Array([p + Vector2(sl, 0), p + Vector2(s.x, 0), p + Vector2(s.x - sl, s.y), p + Vector2(0, s.y)])


func _diamond(c: CanvasItem, p: Vector2, r: float, col: Color) -> void:
	c.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0)]), col)


# ================================================================ 鼠标命中
func hit_slice(p: Vector2) -> int:
	if not shown:
		return -1
	# 先测最前面的卡
	var order := range(cards.size())
	order.sort_custom(func(a: int, b: int) -> bool: return absf(float(cards[a]["p"])) < absf(float(cards[b]["p"])))
	for i: int in order:
		if (cards[i]["rect"] as Rect2).has_point(p) and (cards[i]["disp"] as ColorRect).visible:
			return i
	return -1


func hit_cta(p: Vector2) -> bool:
	return shown and hit_slice(p) == idx


func set_hover(p: Vector2) -> bool:
	hover_i = hit_slice(p)
	return hover_i >= 0
