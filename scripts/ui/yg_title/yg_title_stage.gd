extends Control
## [YG-MARK] 由 YG 新增（首页「断晓 · 断光」WebGL 版移植到 Godot）。
##
## 渲染骨架：把网页版的 7 个着色器 pass 搭成 Godot 的 SubViewport 链。
##   VP_LIGHT  昼光层（yg_light）+ 光层雨滴粒子
##   VP_SHADOW 影层（yg_shadow）+ 影层雨滴粒子
##   VP_FX     火星 / 光片粒子（只有粒子，黑底）
##   VP_COMP   合成（yg_comp）：一刀两断、撕裂带、昼夜互换
##   DOWN[0..n] 泛光降采样链（yg_bloom_down）
##   VP_ACC    泛光叠加（yg_bloom_up，叠加混合）
##   VP_FINAL  输出（yg_final）：色散 / ACES / 冲击帧 / 闪白 / 暗角 / 颗粒
## 与网页版的差异：泛光改成「每级各自升采样后叠加」，不做逐级回注（省 5 个 backbuffer，
## 观感差别只在糊的层次上，几乎看不出来）。
## [YG-MARK] 11-05 适配：画面按窗口真实像素渲染（相当于网页版的 dpr）。所有着色器和粒子坐标仍是
## 1280×720 设计单位，SubViewport 用 size_2d_override 把设计尺寸拉满真实像素；开了 F7 超采样再乘 2，
## 上限 3 倍（4K）。泛光链和泛光叠加仍按设计尺寸算，所以光晕大小和以前一样。窗口大小变了由 app 调 rebuild。
##
## 删除方法：见 docs/YG-首页断光-删除清单.md。

const SimScript := preload("res://scripts/ui/yg_title/yg_title_sim.gd")
const SH_LIGHT := preload("res://assets/shaders/yg_title/yg_light.gdshader")
const SH_SHADOW := preload("res://assets/shaders/yg_title/yg_shadow.gdshader")
const SH_COMP := preload("res://assets/shaders/yg_title/yg_comp.gdshader")
const SH_DOWN := preload("res://assets/shaders/yg_title/yg_bloom_down.gdshader")
const SH_UP := preload("res://assets/shaders/yg_title/yg_bloom_up.gdshader")
const SH_FINAL := preload("res://assets/shaders/yg_title/yg_final.gdshader")
const SH_PART := preload("res://assets/shaders/yg_title/yg_part.gdshader")

const MARK_CUT := "res://assets/image/yg_title/mark_cut.webp"
const MARK_WHOLE := "res://assets/image/yg_title/mark_whole.webp"

const MAXP := 6000
const MAX_SCALE := 3.0      ## [YG-MARK] 设计尺寸的最多 3 倍（3840×2160）

var sim: RefCounted

var _cw := 1280             ## 设计尺寸
var _ch := 720
var _sw := 1280             ## 昼光 / 影 / 火星层的像素尺寸
var _sh := 720
var _pw := 1280             ## [YG-MARK] 合成 / 输出层的像素尺寸
var _ph := 720
var px_scale := 1.0         ## [YG-MARK] 1 个设计单位 = 多少渲染像素

var _vp_light: SubViewport
var _vp_shadow: SubViewport
var _vp_fx: SubViewport
var _vp_comp: SubViewport
var _vp_acc: SubViewport
var _vp_final: SubViewport

var _rect_light: ColorRect
var _rect_shadow: ColorRect
var _rect_comp: ColorRect
var _rect_final: ColorRect

var _mm_light: MultiMeshInstance2D
var _mm_shadow: MultiMeshInstance2D
var _mm_fx: MultiMeshInstance2D

var _down_vps: Array = []
var _down_rects: Array = []
var _acc_rects: Array = []

var _tex_cut: Texture2D
var _tex_whole: Texture2D
var _display: TextureRect

var _bloom_levels := 6


func build(s: RefCounted, view_size: Vector2i) -> void:
	sim = s
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_cw = max(2, view_size.x)
	_ch = max(2, view_size.y)
	_tex_cut = load(MARK_CUT)
	_tex_whole = load(MARK_WHOLE)
	px_scale = target_scale()
	_build_chain()


## [YG-MARK] 现在该用的渲染倍率：窗口把设计尺寸放大了多少 ×（超采样开着再 ×2），取 0.05 的整数倍
func target_scale() -> float:
	if not is_inside_tree():
		return 1.0
	var root := get_tree().root
	var s := root.get_final_transform().x.length()
	var ss := root.get_node_or_null("Supersample")
	if ss != null and bool(ss.get("enabled")):
		s *= 2.0
	return clampf(snappedf(s, 0.05), 0.5, MAX_SCALE)


## [YG-MARK] content = 画在里面的 2D 内容按多大的设计尺寸摆（零 = 和像素尺寸一样，不拉伸）
func _mk_vp(w: int, h: int, content := Vector2i.ZERO) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = Vector2i(max(2, w), max(2, h))
	if content != Vector2i.ZERO:
		vp.size_2d_override = content
		vp.size_2d_override_stretch = true
	vp.disable_3d = true
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	vp.handle_input_locally = false
	vp.gui_disable_input = true
	vp.use_hdr_2d = true
	add_child(vp)
	return vp


func _mk_rect(vp: SubViewport, shader: Shader, w: int, h: int) -> ColorRect:
	var r := ColorRect.new()
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.color = Color(1, 1, 1, 1)
	r.position = Vector2.ZERO
	r.size = Vector2(w, h)
	var m := ShaderMaterial.new()
	m.shader = shader
	r.material = m
	vp.add_child(r)
	return r


func _mk_parts(vp: SubViewport, shader: Shader) -> MultiMeshInstance2D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	mm.mesh = quad
	mm.instance_count = MAXP
	mm.visible_instance_count = 0
	var inst := MultiMeshInstance2D.new()
	inst.multimesh = mm
	inst.position = Vector2.ZERO
	var m := ShaderMaterial.new()
	m.shader = shader
	inst.material = m
	vp.add_child(inst)
	return inst


func _build_chain() -> void:
	_refresh_quality()
	var design := Vector2i(_cw, _ch)

	_vp_light = _mk_vp(_sw, _sh, design)
	_rect_light = _mk_rect(_vp_light, SH_LIGHT, _cw, _ch)
	_mm_light = _mk_parts(_vp_light, SH_PART)

	_vp_shadow = _mk_vp(_sw, _sh, design)
	_rect_shadow = _mk_rect(_vp_shadow, SH_SHADOW, _cw, _ch)
	_mm_shadow = _mk_parts(_vp_shadow, SH_PART)

	_vp_fx = _mk_vp(_sw, _sh, design)
	_mm_fx = _mk_parts(_vp_fx, SH_PART)

	_vp_comp = _mk_vp(_pw, _ph, design)
	_rect_comp = _mk_rect(_vp_comp, SH_COMP, _cw, _ch)

	_bloom_levels = int(sim.ql()["bloom"])
	var bw := _cw
	var bh := _ch
	for i in _bloom_levels:
		bw = max(1, bw >> 1)
		bh = max(1, bh >> 1)
		var vp := _mk_vp(bw, bh)
		var rect := _mk_rect(vp, SH_DOWN, bw, bh)
		_down_vps.append(vp)
		_down_rects.append(rect)

	_vp_acc = _mk_vp(_cw, _ch)
	for i in _bloom_levels:
		var r := ColorRect.new()
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.color = Color(1, 1, 1, 1)
		r.position = Vector2.ZERO
		r.size = Vector2(_cw, _ch)
		var m := ShaderMaterial.new()
		m.shader = SH_UP
		r.material = m
		_vp_acc.add_child(r)
		_acc_rects.append(r)

	_vp_final = _mk_vp(_pw, _ph, design)
	_rect_final = _mk_rect(_vp_final, SH_FINAL, _cw, _ch)

	_display = TextureRect.new()
	_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_display.position = Vector2.ZERO
	_display.size = Vector2(_cw, _ch)
	_display.texture = _vp_final.get_texture()
	_display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_display.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(_display)


func _refresh_quality() -> void:
	_pw = max(2, int(round(_cw * px_scale)))
	_ph = max(2, int(round(_ch * px_scale)))
	_sw = max(2, int(round(_pw * float(sim.ql()["scene"]))))
	_sh = max(2, int(round(_ph * float(sim.ql()["scene"]))))


## [YG-MARK] 渲染倍率变了（窗口缩放 / 全屏 / F7）就重建
func set_px_scale(s: float) -> void:
	if absf(s - px_scale) < 0.01:
		return
	px_scale = s
	rebuild()


## 画质切换后重建整条 SubViewport 链
func rebuild() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_down_vps.clear()
	_down_rects.clear()
	_acc_rects.clear()
	_build_chain()


func _mat(c: ColorRect) -> ShaderMaterial:
	return c.material as ShaderMaterial


func _pmat(inst: MultiMeshInstance2D) -> ShaderMaterial:
	return inst.material as ShaderMaterial


## 每帧：打包粒子 + 推所有 uniform
func step() -> void:
	var par := Vector2(float(sim.mouse["sx"]) * 12.0 * sim.k, float(sim.mouse["sy"]) * 8.0 * sim.k)
	var dawn := 1.0
	var sun_off := 0.0
	var sun_k := 1.0
	var reveal := 1.0
	if sim.state == "intro":
		dawn = sim.sstep(float(sim.TL["rise_a"]), float(sim.TL["rise_b"]), sim.it)
		sun_off = (1.0 - sim.e_out(clampf((sim.it - float(sim.TL["rise_a"])) / (float(sim.TL["rise_b"]) - float(sim.TL["rise_a"]) + 0.4), 0.0, 1.0))) * sim.R * 1.3
		sun_k = sim.sstep(float(sim.TL["rise_a"]) + 0.3, float(sim.TL["rise_b"]), sim.it)
		reveal = clampf((sim.it - float(sim.TL["title_a"])) / (float(sim.TL["title_b"]) - float(sim.TL["title_a"])), 0.0, 1.0)
	var sun := Vector2(sim.W * 0.34, -sim.H * 0.42 + sun_off * 0.65)

	sim.intro_rain = (sim.state == "intro" and not sim.cut_done)
	_pack()

	# 昼光层
	var ml := _mat(_rect_light)
	ml.set_shader_parameter("uRes", Vector2(sim.W, sim.H))
	ml.set_shader_parameter("uTime", sim.sim_t)
	ml.set_shader_parameter("uC", sim.C)
	ml.set_shader_parameter("uD", sim.D)
	ml.set_shader_parameter("uN", sim.N)
	ml.set_shader_parameter("uPar", par)
	ml.set_shader_parameter("uSun", sun)
	ml.set_shader_parameter("uSunR", sim.H * 0.75)
	ml.set_shader_parameter("uDawn", dawn)
	ml.set_shader_parameter("uSunK", sun_k)
	ml.set_shader_parameter("uReveal", reveal)
	ml.set_shader_parameter("uBox", sim.box)
	ml.set_shader_parameter("uLogoRect", Vector4(sim.logo_origin.x, sim.logo_origin.y, sim.logo_size.x, sim.logo_size.y))
	ml.set_shader_parameter("uLogoW", _tex_whole)

	var pl := _pmat(_mm_light)
	pl.set_shader_parameter("uRes", Vector2(sim.W, sim.H))
	pl.set_shader_parameter("uTime", sim.sim_t)
	pl.set_shader_parameter("uC", sim.C)
	pl.set_shader_parameter("uN", sim.N)
	pl.set_shader_parameter("uPar", par)
	pl.set_shader_parameter("uSun", sun)
	pl.set_shader_parameter("uSunR", sim.H * 0.75)
	pl.set_shader_parameter("uDawn", maxf(dawn, 0.0))
	pl.set_shader_parameter("uBox", sim.box)
	pl.set_shader_parameter("uMode", 0.0)
	pl.set_shader_parameter("uStreak", 0.022)

	# 影层
	_rect_shadow.visible = not sim.intro_rain
	var ms := _mat(_rect_shadow)
	ms.set_shader_parameter("uRes", Vector2(sim.W, sim.H))
	ms.set_shader_parameter("uTime", sim.sim_t)
	ms.set_shader_parameter("uC", sim.C)
	ms.set_shader_parameter("uD", sim.D)
	ms.set_shader_parameter("uN", sim.N)
	ms.set_shader_parameter("uPar", par)
	ms.set_shader_parameter("uSunR", sim.R)
	ms.set_shader_parameter("uFlowK", 1.0)
	ms.set_shader_parameter("uBox", sim.box)
	ms.set_shader_parameter("uLogoRect", Vector4(sim.logo_origin.x, sim.logo_origin.y, sim.logo_size.x, sim.logo_size.y))
	ms.set_shader_parameter("uLogo", _tex_cut)
	ms.set_shader_parameter("uLogoW", _tex_whole)

	var ps := _pmat(_mm_shadow)
	ps.set_shader_parameter("uRes", Vector2(sim.W, sim.H))
	ps.set_shader_parameter("uTime", sim.sim_t)
	ps.set_shader_parameter("uC", sim.C)
	ps.set_shader_parameter("uN", sim.N)
	ps.set_shader_parameter("uPar", par)
	ps.set_shader_parameter("uSun", sun)
	ps.set_shader_parameter("uSunR", sim.R)
	ps.set_shader_parameter("uDawn", 1.0)
	ps.set_shader_parameter("uBox", sim.box)
	ps.set_shader_parameter("uMode", 1.0)
	ps.set_shader_parameter("uStreak", 0.022)

	var pf := _pmat(_mm_fx)
	pf.set_shader_parameter("uRes", Vector2(sim.W, sim.H))
	pf.set_shader_parameter("uTime", sim.sim_t)
	pf.set_shader_parameter("uC", sim.C)
	pf.set_shader_parameter("uN", sim.N)
	pf.set_shader_parameter("uPar", Vector2.ZERO)
	pf.set_shader_parameter("uSun", sun)
	pf.set_shader_parameter("uSunR", sim.R)
	pf.set_shader_parameter("uDawn", 1.0)
	pf.set_shader_parameter("uMode", 2.0)

	# 合成
	var sk := 0.0
	if sim.shake:
		sk = sim.trauma * sim.trauma * 22.0 * sim.k
	var shake := Vector2(
			sk * (sin(sim.now * 71.3) + sin(sim.now * 43.1 + 1.3)) * 0.5,
			sk * (sin(sim.now * 63.7 + 2.1) + sin(sim.now * 37.9)) * 0.5)
	var mouse_state := Vector4(float(sim.mouse["x"]), float(sim.mouse["y"]),
			clampf(float(sim.mouse["sp"]) / (900.0 * sim.k), 0.0, 1.0),
			1.0 if (sim.cut_done and (sim.state == "menu" or sim.state == "settings" or sim.state == "confirm")) else 0.0)
	var mc := _mat(_rect_comp)
	mc.set_shader_parameter("uRes", Vector2(sim.W, sim.H))
	mc.set_shader_parameter("uTime", sim.sim_t)
	mc.set_shader_parameter("uC", sim.C)
	mc.set_shader_parameter("uD", sim.D)
	mc.set_shader_parameter("uN", sim.N)
	mc.set_shader_parameter("uShake", shake)
	mc.set_shader_parameter("uTipPos", sim.cut_tip_pos)
	mc.set_shader_parameter("uGlintPos", sim.cut_glint_pos)
	mc.set_shader_parameter("uSw", sim.cut_sw)
	mc.set_shader_parameter("uTip", sim.cut_tip)
	mc.set_shader_parameter("uSlide", sim.cut_slide)
	mc.set_shader_parameter("uGap", sim.cut_gap)
	mc.set_shader_parameter("uFront", sim.cut_front)
	mc.set_shader_parameter("uSeam", sim.cut_seam)
	mc.set_shader_parameter("uShock", sim.cut_shock_t if sim.cut_shock_t >= 0.0 else 0.0)
	mc.set_shader_parameter("uOpen", sim.fin_open)
	mc.set_shader_parameter("uVoid", sim.fin_void)
	mc.set_shader_parameter("uCollapse", sim.fin_collapse)
	mc.set_shader_parameter("uSeamLen", sim.fin_seam_len)
	mc.set_shader_parameter("uGlint", sim.cut_glint)
	mc.set_shader_parameter("uCutOn", sim.cut_on)
	mc.set_shader_parameter("uSlashing", sim.cut_slashing)
	mc.set_shader_parameter("uDragOn", sim.drag_on)
	if not sim.drag.is_empty() and bool(sim.drag.get("slash", false)):
		mc.set_shader_parameter("uDrag", Vector4(sim.drag["x0"], sim.drag["y0"], sim.drag["x"], sim.drag["y"]))
	else:
		mc.set_shader_parameter("uDrag", Vector4.ZERO)
	mc.set_shader_parameter("uMouse", mouse_state)
	mc.set_shader_parameter("uL", _vp_light.get_texture())
	mc.set_shader_parameter("uS", _vp_shadow.get_texture())
	mc.set_shader_parameter("uFx", _vp_fx.get_texture())
	var tc := [Vector4.ZERO, Vector4.ZERO, Vector4.ZERO]
	var ta := [Vector4.ZERO, Vector4.ZERO, Vector4.ZERO]
	var n := mini(3, sim.slots.size())
	for i in n:
		var s: Dictionary = sim.slots[i]
		var age: float = sim.sim_t - float(s["born"])
		tc[i] = Vector4(s["x"], s["y"], s["ang"], float(s["len"]) * 0.5)
		ta[i] = Vector4(
				float(s["A"]) * (1.0 - exp(-age * 45.0)) * exp(-age * 1.25),
				(2.4 * exp(-age * 1.6) + 0.6 * exp(-age * 0.6)) * clampf((3.6 - age) / 0.8, 0.0, 1.0),
				age, 0.0)
	mc.set_shader_parameter("uTC0", tc[0])
	mc.set_shader_parameter("uTC1", tc[1])
	mc.set_shader_parameter("uTC2", tc[2])
	mc.set_shader_parameter("uTA0", ta[0])
	mc.set_shader_parameter("uTA1", ta[1])
	mc.set_shader_parameter("uTA2", ta[2])

	# 泛光降采样
	for i in _bloom_levels:
		var vp: SubViewport = _down_vps[i]
		var src: Texture2D = _vp_comp.get_texture() if i == 0 else _down_vps[i - 1].get_texture()
		var src_size := Vector2(_cw, _ch) if i == 0 else Vector2(_down_vps[i - 1].size)
		var m := _mat(_down_rects[i])
		m.set_shader_parameter("uSrc", src)
		m.set_shader_parameter("uTexel", Vector2(1.0 / src_size.x, 1.0 / src_size.y))
		m.set_shader_parameter("uPre", 1.0 if i == 0 else 0.0)
		m.set_shader_parameter("uThr", 1.1)
	# 泛光叠加
	for i in _bloom_levels:
		var r: ColorRect = _acc_rects[i]
		var m := r.material as ShaderMaterial
		var vp: SubViewport = _down_vps[i]
		m.set_shader_parameter("uSrc", vp.get_texture())
		m.set_shader_parameter("uTexel", Vector2(1.0 / vp.size.x, 1.0 / vp.size.y))
		m.set_shader_parameter("uK", 1.0)

	# 输出
	var ie: float = sim.now - sim.impact_rt
	var impact := 1.0 if (sim.impact_rt >= 0.0 and ie < 0.065) else 0.0
	var mf := _mat(_rect_final)
	mf.set_shader_parameter("uRes", Vector2(sim.W, sim.H))
	mf.set_shader_parameter("uTime", sim.now)
	mf.set_shader_parameter("uC", sim.C)
	mf.set_shader_parameter("uN", sim.N)
	mf.set_shader_parameter("uBloomK", 0.15)
	mf.set_shader_parameter("uExpo", 1.0)
	mf.set_shader_parameter("uImpact", impact)
	mf.set_shader_parameter("uFlash", sim.flash)
	mf.set_shader_parameter("uFade", sim.fin_fade)
	mf.set_shader_parameter("uCA", (0.15 + sim.trauma * 1.2) if sim.cut_done else 0.0)
	mf.set_shader_parameter("uComp", _vp_comp.get_texture())
	mf.set_shader_parameter("uBloom", _vp_acc.get_texture())


func _put(mm: MultiMeshInstance2D, idx: int, d: RefCounted, alpha: float) -> void:
	mm.multimesh.set_instance_custom_data(idx, Color(d.x, d.y, d.size, alpha))
	mm.multimesh.set_instance_transform_2d(idx, Transform2D(0.0, Vector2(d.vx, d.vy)))
	mm.multimesh.set_instance_color(idx, Color(d.seed, 0.0, 0.0, 1.0))


func _pack() -> void:
	var rain_keep := maxf(0.35, float(sim.rain_percent) / 100.0)
	var nl := 0
	var ns := 0
	var intro_rain: bool = sim.intro_rain
	for d in sim.drops:
		var a: float = d.a
		if d.layer == 0:
			if d.born > -90.0:
				a *= clampf((sim.sim_t - d.born) / 1.6, 0.0, 1.0)
			# [YG-MARK] 11-05 改好看：冻住后淡出的比例 42% → 60%，光里的悬珠少一些、不像满屏雪花
			if d.st == 1 and d.size <= 6.0 and d.keep > 0.40:
				var f := 1.0 - clampf((sim.sim_t - d.fz) / 0.9, 0.0, 1.0)
				if f <= 0.0:
					continue
				a *= f
			var still: bool = (d.st == 1 or d.st == 4)
			if intro_rain and not still:
				if d.keep > rain_keep:
					continue
				if ns >= MAXP:
					continue
				_put(_mm_shadow, ns, d, minf(1.0, a * 1.05))
				ns += 1
				continue
			if nl >= MAXP:
				continue
			_put(_mm_light, nl, d, minf(1.0, a * 1.05))
			nl += 1
		else:
			if d.keep > rain_keep:
				continue
			if ns >= MAXP:
				continue
			_put(_mm_shadow, ns, d, minf(1.0, a * 1.05))
			ns += 1
	_mm_light.multimesh.visible_instance_count = nl
	_mm_shadow.multimesh.visible_instance_count = ns

	var nf := 0
	for p in sim.fx:
		if nf >= MAXP:
			break
		var al := clampf(p.life / maxf(p.max_life, 1e-4), 0.0, 1.0)
		_mm_fx.multimesh.set_instance_custom_data(nf, Color(p.x, p.y, p.size, al))
		_mm_fx.multimesh.set_instance_transform_2d(nf, Transform2D(0.0, Vector2(p.vx, p.vy)))
		var sd: float = p.seed if p.kind == 0 else p.rot
		_mm_fx.multimesh.set_instance_color(nf, Color(sd, float(p.kind), 0.0, 1.0))
		nf += 1
	_mm_fx.multimesh.visible_instance_count = nf
