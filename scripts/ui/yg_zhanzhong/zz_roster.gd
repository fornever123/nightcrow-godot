extends Control
## [YG-MARK] 角色选择页「刀裂四分」（C 方案 · 四姝平权 28° 斜刃斩裂展开）
## 1. 与首页三维钟 28° 斩缝一脉相承：4 名平权女主（朔 / 萤 / 薇 / 曜）化作 4 道 28° 斜切刀格；
## 2. 选中角色弹簧展开至 64% 主视野，其余 3 位收束为锐利眼部特写斜条；
## 3. 切换角色实时驱动整座 3D 钟与全站主色切换（朔紫 / 萤青 / 薇红 / 曜金，非朔角色 0% 紫残留）；
## 4. 确认「夜鸦」朔 → 无缝转入机关舞台选章；未开放三姝显示「尚在光中」且可完整鉴赏人设与配色。

const W := 1920.0
const H := 1080.0
const SLANT := 440.0
const INK := Color("#08070c")
const WHITE := Color("#f5f2eb")
const IMG := "res://assets/image/yg_zhanzhong/"
const SLICE_SHADER := preload("res://scripts/ui/yg_zhanzhong/zz_roster_slice.gdshader")

const ROSTER := [
	{
		"key": "shuo", "surname": "朔", "epithet": "夜鸦", "playable": true,
		"weapon": "黑银直剑",
		"quote": "“影街的夜太长了，先把挡路的黑影斩干净。”",
		"traits": ["快剑连斩", "冲刺挥斩", "精准弹刀"],
		"tex": "roster_shuo", "word": "rs_shuo", "eye": Vector2(0.64, 0.35),
	},
	{
		"key": "ying", "surname": "萤", "epithet": "惊风", "playable": false,
		"weapon": "青银断环双刃 · 飞爪锁链",
		"quote": "“停在一秒钟里，算什么活着？”",
		"traits": ["高机游走", "飞爪牵引", "断环连斩"],
		"tex": "roster_ying", "word": "rs_ying", "eye": Vector2(0.74, 0.36),
	},
	{
		"key": "wei", "surname": "薇", "epithet": "残火", "playable": false,
		"weapon": "单手宽刃巨剑 · 黑铁撞甲",
		"quote": "“借五点五十九分磨剑，只求正面劈开天缝。”",
		"traits": ["重剑蓄斩", "铁甲格挡", "裂地轰飞"],
		"tex": "roster_wei", "word": "rs_wei", "eye": Vector2(0.64, 0.32),
	},
	{
		"key": "yao", "surname": "曜", "epithet": "破晓", "playable": false,
		"weapon": "圣堂十字光剑",
		"quote": "“留在光里，就永远不会再痛了。”",
		"traits": ["圣芒斩击", "中距居合", "驻光结界"],
		"tex": "roster_yao", "word": "rs_yao", "eye": Vector2(0.65, 0.34),
	},
]

var T: Node = null
var font_cn: Font
var font_cn_med: Font
var font_lat: Font

var backdrop: ColorRect
var slices: Array = []
var overlay: Control
var idx := 0
var hover_i := -1
var hover_cta := false
var shown := false
var now := 0.0
var t_enter := -10.0
var t_leave := -10.0
var t_sel := -10.0
var lock_bump := 0.0
var pointer := Vector2.ZERO
var cta_rect := Rect2()


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

	for i in ROSTER.size():
		var item: Dictionary = ROSTER[i]
		var r := ColorRect.new()
		r.size = Vector2(W, H)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var m := ShaderMaterial.new()
		m.shader = SLICE_SHADER
		var tex := _load_portrait(String(item["tex"]))
		if tex != null:
			m.set_shader_parameter("portrait_tex", tex)
		m.set_shader_parameter("screen_size", Vector2(W, H))
		m.set_shader_parameter("slant_dx", SLANT)
		m.set_shader_parameter("eye_uv", item["eye"])
		var hp: Dictionary = T.HEROES[String(item["key"])]
		m.set_shader_parameter("accent_col", hp["ui"])
		m.set_shader_parameter("locked_k", 0.0 if bool(item["playable"]) else 1.0)
		r.material = m
		add_child(r)
		slices.append({
			"rect": r, "mat": m, "w": 480.0, "v": 0.0,
			"act": 1.0 if i == 0 else 0.0, "fl": 0.0, "xl": 0.0, "xr": 480.0,
		})

	overlay = Control.new()
	overlay.size = Vector2(W, H)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.draw.connect(_draw_overlay)
	add_child(overlay)


func _load_portrait(stem: String) -> Texture2D:
	for ext: String in [".jpg", ".png", ".webp"]:
		var p: String = IMG + stem + ext
		if ResourceLoader.exists(p):
			return load(p) as Texture2D
	return null


func enter(hero_key: String) -> void:
	shown = true
	visible = true
	t_enter = now
	t_sel = now
	idx = 0
	for i in ROSTER.size():
		if String(ROSTER[i]["key"]) == hero_key:
			idx = i
			break
	var total := W + SLANT
	var wide := 1256.0
	var narrow := (total - wide) / 3.0
	for i in slices.size():
		var s: Dictionary = slices[i]
		s["w"] = wide if i == idx else narrow
		s["v"] = 0.0
		s["act"] = 1.0 if i == idx else 0.0
		s["fl"] = 1.0 if i == idx else 0.35
	overlay.queue_redraw()


func leave() -> void:
	shown = false
	t_leave = now


func select(new_idx: int) -> String:
	var n := ROSTER.size()
	var ni := posmod(new_idx, n)
	if ni == idx:
		return String(ROSTER[idx]["key"])
	idx = ni
	t_sel = now
	for i in slices.size():
		var s: Dictionary = slices[i]
		s["fl"] = 1.0 if i == idx else 0.35
	return String(ROSTER[idx]["key"])


func select_index(new_idx: int) -> void:
	var prev_i := idx
	var k := select(new_idx)
	if idx != prev_i and T != null:
		T._apply_hero(k, true)
		T._play("h3_slash_fast" if T.sfx.has("h3_slash_fast") else "ui_move", -5.0, 1.05)


func current_key() -> String:
	return String(ROSTER[idx]["key"])


func is_playable() -> bool:
	return bool(ROSTER[idx]["playable"])


func bump_locked() -> void:
	lock_bump = 1.0


func _open() -> float:
	if shown:
		var p := clampf((now - t_enter) / 0.32, 0.0, 1.0)
		return 1.0 - pow(1.0 - p, 3.0)
	var q := clampf((now - t_leave) / 0.22, 0.0, 1.0)
	return 1.0 - q * q


func update(dt: float, ptr: Vector2) -> void:
	now += dt
	pointer = ptr
	var op := _open()
	if not shown and op <= 0.005:
		visible = false
		return
	visible = true
	backdrop.color = Color(INK, 0.88 * op)
	lock_bump = maxf(0.0, lock_bump - dt * 4.5)

	var total := W + SLANT
	var wide := 1256.0
	var narrow := (total - wide) / 3.0
	var h := minf(dt, 1.0 / 30.0)
	var sum_w := 0.0
	for i in slices.size():
		var s: Dictionary = slices[i]
		var goal := wide if i == idx else narrow
		s["v"] = float(s["v"]) + ((goal - float(s["w"])) * 360.0 - float(s["v"]) * 28.0) * h
		s["w"] = maxf(110.0, float(s["w"]) + float(s["v"]) * h)
		sum_w += float(s["w"])

	var cur_x := 0.0
	var scale_w := total / maxf(sum_w, 1.0)
	for i in slices.size():
		var s: Dictionary = slices[i]
		var wi := float(s["w"]) * scale_w
		var xl := -180.0 if i == 0 else cur_x
		var xr := total + 180.0 if i == slices.size() - 1 else (cur_x + wi)
		s["xl"] = cur_x
		s["xr"] = cur_x + wi
		cur_x += wi

		s["act"] = lerpf(float(s["act"]), 1.0 if i == idx else 0.0, 1.0 - exp(-dt * 16.0))
		s["fl"] = maxf(0.0, float(s["fl"]) - dt * 3.8)
		var m: ShaderMaterial = s["mat"]
		m.set_shader_parameter("x_left_top", xl)
		m.set_shader_parameter("x_right_top", xr)
		m.set_shader_parameter("active_k", float(s["act"]))
		m.set_shader_parameter("hover_k", 1.0 if hover_i == i else 0.0)
		m.set_shader_parameter("open_k", op)
		m.set_shader_parameter("flash_k", float(s["fl"]))
		m.set_shader_parameter("parallax", pointer)

	overlay.queue_redraw()


func _draw_overlay() -> void:
	var c := overlay
	var op := _open()
	if op <= 0.02:
		return

	# 1. 左上角「选择主角」斜切刀锋页眉
	var hd_y := 46.0 - 44.0 * (1.0 - op)
	var hd_pts := PackedVector2Array([
		Vector2(68, hd_y), Vector2(396, hd_y),
		Vector2(368, hd_y + 72), Vector2(40, hd_y + 72),
	])
	var hd_sh := PackedVector2Array()
	for p in hd_pts:
		hd_sh.append(p + Vector2(8, 8))
	c.draw_colored_polygon(hd_sh, Color(INK, 0.88 * op))
	c.draw_colored_polygon(hd_pts, Color(WHITE, 0.96 * op))
	c.draw_colored_polygon(PackedVector2Array([
		Vector2(66, hd_y), Vector2(82, hd_y), Vector2(54, hd_y + 72), Vector2(38, hd_y + 72),
	]), Color(T.accent, op))
	var rs_title: Texture2D = T._tex("rs_title")
	if rs_title != null:
		var th := 52.0
		var tw := th * float(rs_title.get_width()) / maxf(1.0, float(rs_title.get_height()))
		c.draw_texture_rect(rs_title, Rect2(104.0, hd_y + 10.0, minf(tw, 256.0), th), false, Color(INK, op))
	else:
		c.draw_string(font_cn, Vector2(108, hd_y + 52), "选择主角", HORIZONTAL_ALIGNMENT_LEFT, -1, 44, Color(INK, op))

	# 2. 折叠斜条的姓名与「尚在光中 / 可出战」竖排铭牌
	for i in ROSTER.size():
		var s: Dictionary = slices[i]
		var act := float(s["act"])
		if act > 0.65:
			continue
		var strip_a := clampf((0.65 - act) / 0.45, 0.0, 1.0) * op
		var item: Dictionary = ROSTER[i]
		var hp: Dictionary = T.HEROES[String(item["key"])]
		var col_acc: Color = Color("#bfc4d4") if (i == 0 and idx != 0) else (hp["ui"] as Color)
		var by := 460.0 if (i == 0 and float(s["xr"]) - SLANT * 0.64 < 120.0) else 676.0
		var ty_b := by / H
		var xl_vis := maxf(0.0, float(s["xl"]) - SLANT * ty_b)
		var xr_vis := minf(W, float(s["xr"]) - SLANT * ty_b)
		var xm_bot := clampf(0.5 * (xl_vis + xr_vis), 58.0, W - 58.0)
		c.draw_colored_polygon(_slant_rect(Rect2(xm_bot - 26.0, by - 64.0, 52.0, 260.0), 10.0), Color(INK, 0.66 * strip_a))
		var sur := String(item["surname"])
		var sw := font_cn.get_string_size(sur, HORIZONTAL_ALIGNMENT_LEFT, -1, 62).x
		c.draw_string(font_cn, Vector2(xm_bot - sw * 0.5 + 3, by + 3), sur, HORIZONTAL_ALIGNMENT_LEFT, -1, 62, Color(INK, 0.92 * strip_a))
		c.draw_string(font_cn, Vector2(xm_bot - sw * 0.5, by), sur, HORIZONTAL_ALIGNMENT_LEFT, -1, 62, Color(WHITE, 0.96 * strip_a))
		_diamond(c, Vector2(xm_bot, by + 24.0), 6.0, Color(col_acc, strip_a))
		c.draw_line(Vector2(xm_bot, by + 34.0), Vector2(xm_bot, by + 182.0), Color(WHITE, 0.24 * strip_a), 1.4, true)
		var status := "可出战" if bool(item["playable"]) else "尚在光中"
		for ci in status.length():
			var ch := status.substr(ci, 1)
			var cw := font_cn_med.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
			c.draw_string(font_cn_med, Vector2(xm_bot - cw * 0.5 + 1.5, by + 64.0 + ci * 28.0 + 1.5), ch,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(INK, 0.92 * strip_a))
			c.draw_string(font_cn_med, Vector2(xm_bot - cw * 0.5, by + 64.0 + ci * 28.0), ch,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(col_acc if bool(item["playable"]) else WHITE, (0.96 if bool(item["playable"]) else 0.80) * strip_a))

	# 3. 展开主角色左侧精排信息区
	var active_item: Dictionary = ROSTER[idx]
	var active_s: Dictionary = slices[idx]
	var act_x0 := float(active_s["xl"])
	var sel_p := clampf((now - t_sel) / 0.22, 0.0, 1.0)
	var se := 1.0 - pow(1.0 - sel_p, 3.0)
	var a_info := se * op
	var ox := -34.0 * (1.0 - se) + sin(now * 58.0) * 10.0 * lock_bump
	var acc: Color = T.accent
	var playable: bool = active_item["playable"]
	var row_x := func(ry: float) -> float:
		return 68.0 if idx == 0 else maxf(68.0, act_x0 - SLANT * (ry / H) + 52.0)

	var ny := 214.0
	var nx0: float = float(row_x.call(ny)) + ox
	var sur_tex: Texture2D = T._tex(String(active_item["word"]))
	if sur_tex != null:
		var sh := 162.0
		var sw := sh * float(sur_tex.get_width()) / maxf(1.0, float(sur_tex.get_height()))
		c.draw_texture_rect(sur_tex, Rect2(nx0 + 9, ny + 9, sw, sh), false, Color(acc, 0.68 * a_info))
		for d in [Vector2(-2, -2), Vector2(2, -2), Vector2(-2, 2), Vector2(4, 5)]:
			c.draw_texture_rect(sur_tex, Rect2(nx0 + d.x, ny + d.y, sw, sh), false, Color(INK, 0.92 * a_info))
		c.draw_texture_rect(sur_tex, Rect2(nx0, ny, sw, sh), false, Color(WHITE, a_info))
		var ep_x := nx0 + sw + 20.0
		var ep_txt := String(active_item["epithet"])
		var ep_w := font_cn.get_string_size(ep_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x
		c.draw_colored_polygon(_slant_rect(Rect2(ep_x - 14.0, ny + 76.0, ep_w + 32.0, 56.0), 8.0), Color(INK, 0.72 * a_info))
		c.draw_string(font_cn, Vector2(ep_x + 2, ny + 120), ep_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 40, Color(INK, 0.92 * a_info))
		c.draw_string(font_cn, Vector2(ep_x, ny + 118), ep_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 40, Color(WHITE, 0.96 * a_info))
		c.draw_line(Vector2(ep_x - 14.0, ny + 132.0), Vector2(ep_x + ep_w + 18.0, ny + 132.0), Color(acc, 0.95 * a_info), 2.8, true)

	var wy := 418.0
	var wx0: float = float(row_x.call(wy)) + ox
	var weap_txt := "武器 · " + String(active_item["weapon"])
	var ww := font_cn_med.get_string_size(weap_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 25).x + 56.0
	var wpts := _slant_rect(Rect2(wx0, wy, ww, 46.0), 10.0)
	c.draw_colored_polygon(wpts, Color(INK, 0.92 * a_info))
	c.draw_colored_polygon(PackedVector2Array([wpts[0], wpts[0] + Vector2(8, 0), wpts[3] + Vector2(8, 0), wpts[3]]), Color(acc, a_info))
	c.draw_string(font_cn_med, Vector2(wx0 + 26, wy + 32), weap_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 25, Color(WHITE, 0.96 * a_info))

	var qy := 482.0
	var qx0: float = float(row_x.call(qy)) + ox
	var q_txt := String(active_item["quote"])
	var qw := maxf(410.0, font_cn_med.get_string_size(q_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x + 68.0)
	c.draw_colored_polygon(_slant_rect(Rect2(qx0, qy, qw, 52.0), 10.0), Color(INK, 0.68 * a_info))
	c.draw_line(Vector2(qx0 + 8.0, qy + 6.0), Vector2(qx0, qy + 46.0), Color(WHITE, 0.55 * a_info), 2.4, true)
	c.draw_string(font_cn_med, Vector2(qx0 + 24, qy + 35), q_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(WHITE, 0.88 * a_info))

	var ty := 562.0
	var traits: Array = active_item["traits"]
	for ti in traits.size():
		var tr_y := ty + float(ti) * 50.0
		var tx0: float = float(row_x.call(tr_y)) + ox
		var tr_txt := String(traits[ti])
		var tr_r := Rect2(tx0, tr_y, 248.0, 42.0)
		var tpts := _slant_rect(tr_r, 9.0)
		c.draw_colored_polygon(tpts, Color(INK, 0.88 * a_info))
		c.draw_colored_polygon(PackedVector2Array([tpts[0], tpts[0] + Vector2(6, 0), tpts[3] + Vector2(6, 0), tpts[3]]), Color(acc, 0.94 * a_info))
		for pi in 4:
			c.draw_line(tpts[pi], tpts[(pi + 1) % 4], Color(WHITE, 0.20 * a_info), 1.0, true)
		_diamond(c, Vector2(tr_r.position.x + 28, tr_r.position.y + 21), 5.0, Color(acc, a_info))
		c.draw_string(font_cn, Vector2(tr_r.position.x + 48, tr_r.position.y + 30), tr_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(WHITE, 0.96 * a_info))

	var cy := 756.0
	var cx0: float = float(row_x.call(cy)) + ox
	cta_rect = Rect2(cx0, cy, 420.0, 94.0)
	var cpts := _slant_rect(cta_rect, 18.0)
	var csh := PackedVector2Array()
	for p in cpts:
		csh.append(p + Vector2(10, 10))
	c.draw_colored_polygon(csh, Color(INK, 0.92 * a_info))
	if playable:
		var fill := WHITE.lerp(Color(1.15, 1.15, 1.15), 1.0 if hover_cta else 0.0)
		c.draw_colored_polygon(cpts, Color(fill, a_info))
		c.draw_colored_polygon(PackedVector2Array([cpts[0], cpts[0] + Vector2(14, 0), cpts[3] + Vector2(14, 0), cpts[3]]), Color(acc, a_info))
		c.draw_string_outline(font_cn, Vector2(cta_rect.position.x + 48, cta_rect.position.y + 63), "确认出战", HORIZONTAL_ALIGNMENT_LEFT, -1, 46, 2, Color(INK, a_info))
		c.draw_string(font_cn, Vector2(cta_rect.position.x + 48, cta_rect.position.y + 63), "确认出战", HORIZONTAL_ALIGNMENT_LEFT, -1, 46, Color(INK, a_info))
		var key_txt := "A" if T.last_pad else "ENTER"
		var kw := font_lat.get_string_size(key_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x + 28.0
		var kr := Rect2(cta_rect.position.x + 264, cta_rect.position.y + 29, kw, 36.0)
		c.draw_colored_polygon(_slant_rect(kr, 7.0), Color(INK, a_info))
		c.draw_string(font_lat, Vector2(kr.position.x + 17, kr.position.y + 26), key_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(acc.lightened(0.25), a_info))
	else:
		c.draw_colored_polygon(cpts, Color(0.045, 0.047, 0.064, 0.94 * a_info))
		c.draw_colored_polygon(PackedVector2Array([cpts[0], cpts[0] + Vector2(10, 0), cpts[3] + Vector2(10, 0), cpts[3]]), Color(acc, 0.85 * a_info))
		for pi in 4:
			c.draw_line(cpts[pi], cpts[(pi + 1) % 4], Color(WHITE, 0.30 * a_info), 1.4, true)
		c.draw_string(font_cn, Vector2(cta_rect.position.x + 46, cta_rect.position.y + 52), "尚 在 光 中 · 暂 未 解 锁", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(WHITE, 0.90 * a_info))
		c.draw_string(font_cn_med, Vector2(cta_rect.position.x + 46, cta_rect.position.y + 80), "后续章节登场 · 当前可预览专属配色", HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color(acc.lightened(0.22), 0.88 * a_info))


func _slant_rect(r: Rect2, sl: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(r.position.x + sl, r.position.y),
		Vector2(r.end.x + sl, r.position.y),
		Vector2(r.end.x, r.end.y),
		Vector2(r.position.x, r.end.y),
	])


func _diamond(c: CanvasItem, p: Vector2, r: float, col: Color) -> void:
	c.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0)]), col)


func hit_slice(p: Vector2) -> int:
	if not shown:
		return -1
	var ty := clampf(p.y / H, 0.0, 1.0)
	for i in slices.size():
		var s: Dictionary = slices[i]
		var xl := float(s["xl"]) - SLANT * ty
		var xr := float(s["xr"]) - SLANT * ty
		if p.x >= xl and p.x <= xr:
			return i
	return -1


func hit_cta(p: Vector2) -> bool:
	return shown and cta_rect.has_point(p)


func set_hover(p: Vector2) -> bool:
	hover_cta = hit_cta(p)
	hover_i = hit_slice(p)
	return hover_cta or hover_i >= 0
