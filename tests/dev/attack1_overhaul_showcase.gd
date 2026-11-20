extends SceneTree
## 断晓 · 普攻1段 + 4帧旋腕收剑 + 6帧流线短闪 + 全套 AI 手绘赛璐璐作画特效 实机录制器 V7（纯AI精绘神颜统一版）
## 角色本体与世界特效 100% 纯 AI 手绘纹理驱动（零程序多边形、零数学新月 Shader）；支持河道实时倒影、预乘无白边与破壳三拍作画编排：
##   engine/Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/dev/attack1_overhaul_showcase.gd --resolution 1280x720 --fixed-fps 60

const Art := preload("res://scripts/presentation/art_cache.gd")
const Buffer := preload("res://scripts/core/input_buffer.gd")
const Shade := preload("res://scripts/night/shade.gd")

const V7_ASSETS_RES := "res://docs/视觉设计/角色动作/普攻1段与特效大改_20261113/v7_ai_assets"

const CANVAS_W := 1536.0
const CANVAS_H := 960.0
const CANVAS_PIVOT_X := 580.0
const CANVAS_PIVOT_Y := 860.0
# 原版 standing authored 高度 ≈ 409px (对应 displayScale 0.410758 -> 实机身高 168px)；V7 统一标定 TARGET_STAND_H = 428px
const SCALE_TO_AUTHORED := (168.0 / 0.410758) / 428.0

var stage: Node2D
var p: CharacterBody2D
var c0: float = 0.0
var out_dir: String = ""
var mode: String = "overhaul"
var director: AiSakugaVfxDirector


func _initialize() -> void:
	call_deferred("_run")


func _hide_debug_and_hints() -> void:
	for child in root.get_children():
		var nm := String(child.name)
		if nm.begins_with("Panku") or nm.to_lower().contains("panku") or nm.to_lower().contains("console"):
			if child is CanvasLayer:
				child.visible = false
			for sub in child.get_children():
				if sub is CanvasItem or sub is CanvasLayer:
					sub.visible = false
	if stage != null:
		for hk in [&"move", &"floors", &"drop", &"parry", &"knockback", &"brute", &"archer", &"bomber", &"blast", &"air", &"chain", &"guard", &"ult"]:
			stage._hints_done[hk] = true
		stage._hint_queue.clear()
		if stage.hud != null:
			stage.hud.help_visible = false
			stage.hud._hint = ""
			stage.hud._hint_t = 0.0
			stage.hud._banner = ""
			stage.hud._banner_life = 0.0


func fr(actions: Array[StringName] = [], edges: Array[StringName] = [], axis := Vector2.ZERO) -> Buffer.Frame:
	var f := Buffer.Frame.new()
	f.actions = actions
	f.pressed_this_frame = edges
	f.axis = axis
	return f


func step_frames(n: int, f: Buffer.Frame = null) -> void:
	for _i in n:
		_hide_debug_and_hints()
		p.set_injected_frame(f if f != null else fr())
		await physics_frame


func record_frames(act_tag: String, n: int, input_schedule: Dictionary = {}, clear_post_dash_at: int = -1) -> void:
	var act_dir := "%s/%s" % [out_dir, act_tag]
	DirAccess.make_dir_recursive_absolute(act_dir)
	for i in n:
		_hide_debug_and_hints()
		if i == clear_post_dash_at:
			p._short_dash_ticks = 0
			p._post_dash_window = 0
			p.velocity.x = 0.0
		var inj: Buffer.Frame = input_schedule.get(i, fr())
		p.set_injected_frame(inj)
		await physics_frame
		await RenderingServer.frame_post_draw
		root.get_viewport().get_texture().get_image().save_png("%s/f_%03d.png" % [act_dir, i])


func _load_tex_raw(abs_fp: String, do_premul: bool = false) -> ImageTexture:
	var img := Image.load_from_file(abs_fp)
	img.convert(Image.FORMAT_RGBA8)
	if do_premul:
		img.premultiply_alpha()
	return ImageTexture.create_from_image(img)


func _load_char_sequence(sub_dir: String, prefix: String, count: int) -> Array:
	var base_abs := ProjectSettings.globalize_path("%s/%s" % [V7_ASSETS_RES, sub_dir])
	var list: Array = []
	for i in count:
		var key := "%s/%s_%02d" % [sub_dir, prefix, i]
		var fp := "%s/%s_%02d.png" % [base_abs, prefix, i]
		var tex := _load_tex_raw(fp, Art.premultiply)
		var tex_key := "__a1_overhaul_v7/" + key
		Art.textures[tex_key] = tex
		list.append({
			"asset": tex_key,
			"width": CANVAS_W * SCALE_TO_AUTHORED,
			"height": CANVAS_H * SCALE_TO_AUTHORED,
			"pivotX": CANVAS_PIVOT_X * SCALE_TO_AUTHORED,
			"pivotY": CANVAS_PIVOT_Y * SCALE_TO_AUTHORED,
			"durationTicks": 1,
		})
	return list


func _load_vfx_bank() -> Dictionary:
	var vfx_abs := ProjectSettings.globalize_path("%s/vfx" % V7_ASSETS_RES)
	var bank := {
		"hit_slash": [],
		"water_splash": [],
		"porcelain_burst": [],
		"porcelain_shards": [],
		"feather_burst": [],
		"feathers": [],
	}
	# 全部启用预乘 Alpha (do_premul = true)，配合 BLEND_MODE_PREMULT_ALPHA 彻底根绝任何半透明白边/灰边！
	for i in 4:
		bank["hit_slash"].append(_load_tex_raw("%s/hit_slash_%02d.png" % [vfx_abs, i], true))
		bank["water_splash"].append(_load_tex_raw("%s/water_splash_%02d.png" % [vfx_abs, i], true))
		bank["porcelain_shards"].append(_load_tex_raw("%s/porcelain_shard_%02d.png" % [vfx_abs, i], true))
	for i in 3:
		bank["porcelain_burst"].append(_load_tex_raw("%s/porcelain_burst_%02d.png" % [vfx_abs, i], true))
	for i in 2:
		bank["feather_burst"].append(_load_tex_raw("%s/feather_burst_%02d.png" % [vfx_abs, i], true))
	for i in 8:
		bank["feathers"].append(_load_tex_raw("%s/feather_%02d.png" % [vfx_abs, i], true))
	return bank


func _install_overhaul_assets() -> Dictionary:
	var sprite_cfg: Dictionary = p.get_meta("character").sprite
	var disp_scale := float(sprite_cfg.get("displayScale", 0.410758))

	var idle_list := _load_char_sequence("idle", "idle", 8)
	var a1_list := _load_char_sequence("attack_1", "a1", 13)
	var settle_list := _load_char_sequence("attack_1_settle", "settle", 4)
	var dash_list := _load_char_sequence("dash_step", "dash", 6)
	var vfx_bank := _load_vfx_bank()

	# 待机使用 100% 忠于原版五官发型神韵的官方高清 8 帧呼吸序列 (69 ticks @ 24fps)，锐度较原版提升 2.5 倍且零走形！
	var idle_durs := [9, 9, 9, 9, 9, 9, 8, 7]
	for i in idle_list.size():
		idle_list[i]["durationTicks"] = int(idle_durs[i])
	sprite_cfg.animations.idle.frames = idle_list

	# 普攻1段：1536宽画布无裁边高清重画 + AI 手绘书法飞白黑紫骨白大弧刀光（effectsBaked = true）
	var clip_a1: Dictionary = sprite_cfg.animations.attack_1
	clip_a1.frames = a1_list
	clip_a1["effectsBaked"] = true
	clip_a1["overlayEffect"] = ""

	if p.get("light_combo") != null:
		for mv in p.light_combo:
			if mv != null and StringName(mv.get(&"id")) == &"light_1":
				mv.effect = ""

	# 关闭旧版代码画的粉红粗条、黄圈、半分辨率像素粒子与模糊残影，让 100% AI 手绘特效独占画面！
	stage.fx.glow_base = 0.14
	if stage.get("_hit_overlay") != null:
		stage._hit_overlay.visible = false
	if stage.fx.get("pfx") != null:
		stage.fx.pfx.visible = false
	if stage.fx.get("_flash") != null:
		stage.fx._flash.visible = false
	if stage.fx.get("_impact") != null:
		stage.fx._impact.visible = false
	if stage.fx.get("ghosts") != null:
		stage.fx.ghosts.visible = false

	return {
		"disp_scale": disp_scale,
		"settle": settle_list,
		"dash": dash_list,
		"vfx": vfx_bank,
	}


func _reset_actor(rel_x: float, settle_n: int = 24) -> void:
	Engine.time_scale = 1.0
	stage.encounter.clear_shades()
	stage.encounter.running = false
	for s in get_nodes_in_group(&"shade"):
		if is_instance_valid(s):
			s.free()
	for prj in get_nodes_in_group(&"shade_projectile"):
		if is_instance_valid(prj):
			prj.free()
	for child in stage.fx.get_children():
		if child is Label:
			child.free()

	if director != null:
		director.clear_transient()

	p.reset_state(Vector2(c0 + rel_x, stage.floor_y - p.foot_offset))
	p._set_facing(1)
	p.combo_index = 0
	p._rework_next_light = 0
	p._rework_combo_timer = 0
	p.keen_edge_timer = 0.0
	p._post_dash_window = 0
	p._short_dash_ticks = 0
	if stage.style != null:
		stage.style.reset_stats()
		stage.style.combo = 0
	if stage.hud != null:
		stage.hud._callouts.clear()
		stage.hud._last_combo = 0
		stage.hud._combo_pop = 0.0
		stage.hud.visible = true

	stage.camera.global_position = Vector2(c0 + rel_x + 125.0, stage._cam_y_for(stage.floor_y))
	await step_frames(settle_n)
	_hide_debug_and_hints()


func _spawn_shade(kind: int, rel_x: float, custom_shell_hp: float = -1.0) -> Node2D:
	var sh: Node2D = Node2D.new()
	sh.set_script(Shade)
	sh.setup(kind, p, stage.floor_y, 1.0)
	sh.position = Vector2(c0 + rel_x, stage.floor_y - 60.0)
	sh.terrain = stage.terrain
	stage.add_child(sh)
	sh.spawn_frames = 0
	sh.active = false
	sh.facing = -1
	if custom_shell_hp >= 0.0:
		sh.shell_hp = custom_shell_hp
	stage._on_shade_spawned(sh)
	if director != null:
		director.bind_shade(sh)
	return sh


func _run() -> void:
	if OS.has_environment("SHOWCASE_MODE") and not OS.get_environment("SHOWCASE_MODE").is_empty():
		mode = OS.get_environment("SHOWCASE_MODE")
	out_dir = OS.get_environment("SHOT_DIR")
	if out_dir.is_empty():
		var sub_folder := "shots_baseline" if mode == "baseline" else "shots_overhaul"
		out_dir = ProjectSettings.globalize_path("res://docs/视觉设计/角色动作/普攻1段与特效大改_20261113/" + sub_folder)
	DirAccess.make_dir_recursive_absolute(out_dir)

	stage = load("res://scenes/rain_street.tscn").instantiate()
	root.add_child(stage)
	await process_frame
	_hide_debug_and_hints()

	p = stage.player
	stage.fx.rng.seed = 20261114
	await step_frames(20)

	c0 = stage._center_of(0)
	p.reset_state(Vector2(c0 - 1650.0, stage.floor_y - p.foot_offset))
	await step_frames(40, fr([&"move_right"], [], Vector2(1, 0)))

	if mode == "overhaul":
		var extra := _install_overhaul_assets()
		director = AiSakugaVfxDirector.new()
		director.setup(stage, p, extra)
		stage.add_child(director)

	var J: StringName = &"attack_light"
	var D: StringName = &"dash_modifier"

	# Act 1: 湿街挥空重劈（1536宽画布无裁边书法满月刀光 + 贴地前推劈水卷浪&河道实时倒影 + 丝滑4帧旋腕收剑过渡）
	await _reset_actor(-1180.0, 26)
	await record_frames("act1_whiff_settle", 46, {
		2: fr([J], [J]),
	})

	# Act 2: 双影卒贯体斩（刀尖切入距离 + 顺势 ↖→↘ 俯劈斩爆 + 身后鸦墨炸羽 + 8款手绘鸦羽河道倒影 + 旋腕收剑，零旧版模糊a2混入）
	await _reset_actor(-1185.0, 24)
	_spawn_shade(Shade.Kind.GRUNT, -1048.0)
	_spawn_shade(Shade.Kind.GRUNT, -988.0)
	await step_frames(10)
	await record_frames("act2_hit_chain", 46, {
		2: fr([J], [J]),
	})

	# Act 3: 精英甲影破壳三拍交响（z=-2 仅压暗雨街背景保主角刀光纯白高亮 + 冰裂核闪 -> 金缮爆环 -> 立体碎瓷顺势崩飞湿街弹跳&河道倒影）
	await _reset_actor(-1185.0, 24)
	_spawn_shade(Shade.Kind.BRUTE, -1046.0, 10.0)
	await step_frames(10)
	await record_frames("act3_shell_break", 52, {
		2: fr([J], [J]),
	})
	Engine.time_scale = 1.0

	# Act 4: AI手绘6帧平滑掠空短闪（冷紫身形流光残影 + 刹步推水）-> 无缝取消接新版普攻1段满月重劈
	await _reset_actor(-1355.0, 24)
	_spawn_shade(Shade.Kind.GRUNT, -1042.0)
	await step_frames(10)
	await record_frames("act4_dash_cleave", 46, {
		2: fr([D, &"move_right"], [D], Vector2(1, 0)),
		9: fr([J], [J], Vector2(1, 0)),
	}, 9)

	Engine.time_scale = 1.0
	print("SHOWCASE_V5_AI_VFX_DONE mode=", mode, " dir=", out_dir)
	quit()


# ==============================================================================
# AiSakugaVfxDirector V5:
# - 全部世界特效置于 z_index = -1 .. 5 (< _water.z_index = 6)，自动获得河道实时波纹倒影并融入前景雨丝之后！
# - 预乘 Alpha (BLEND_MODE_PREMULT_ALPHA) 彻底消灭白边/灰边！
# - 破壳重击三拍错峰编排 + 俯劈顺向轴对齐，主角面庞与满月白光 100% 通透无遮挡！
# ==============================================================================
class AiSakugaVfxDirector extends Node2D:
	const DASH_TICK_MAP := [0, 1, 1, 2, 2, 3, 4, 5]

	var stage: Node2D
	var player: CharacterBody2D
	var actor_spr: Sprite2D
	var disp_scale: float = 0.410758
	var settle_frames: Array = []
	var dash_frames: Array = []
	var vfx_bank: Dictionary = {}

	var premul_unshaded_mat: CanvasItemMaterial
	var ghost_unshaded_mat: CanvasItemMaterial
	var world_dim_spr: ColorRect

	var _was_in_a1: bool = false
	var _settle_tick: int = -1
	var _active_settle_idx: int = -1
	var _dash_anim_tick: int = -1
	var _active_dash_idx: int = -1
	var _dash_dir_sign: int = 1
	var _water_sprayed_serial: int = -1
	var _cut_spawned_serial: int = -1
	var _shell_broken_frame: int = -999
	var _dim_age: float = -1.0
	var _dim_life: float = 0.18

	var anim_sprites: Array[Dictionary] = []
	var phys_shards: Array[Dictionary] = []
	var phys_feathers: Array[Dictionary] = []
	var dash_ghosts: Array[Dictionary] = []
	var nudged_labels: Dictionary = {}
	var rng := RandomNumberGenerator.new()

	func setup(p_stage: Node2D, p_player: CharacterBody2D, extra: Dictionary) -> void:
		stage = p_stage
		player = p_player
		actor_spr = player.get_node("Visual/ActorSprite") as Sprite2D
		disp_scale = float(extra.get("disp_scale", 0.410758))
		settle_frames = extra.get("settle", [])
		dash_frames = extra.get("dash", [])
		vfx_bank = extra.get("vfx", {})
		process_priority = 50
		process_physics_priority = 50
		rng.seed = 20261114

	func _ready() -> void:
		premul_unshaded_mat = CanvasItemMaterial.new()
		premul_unshaded_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
		premul_unshaded_mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED

		ghost_unshaded_mat = CanvasItemMaterial.new()
		ghost_unshaded_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA if Art.premultiply else CanvasItemMaterial.BLEND_MODE_MIX
		ghost_unshaded_mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED

		# z_index = -2：精准压暗远中近街景 (z <= -5)，同时 100% 保护主角/受击怪 (z = 0) 与全部 AI 手绘特效 (z = -1..5) 的纯白高光不被染灰！
		world_dim_spr = ColorRect.new()
		world_dim_spr.color = Color(0.03, 0.02, 0.08, 0.0)
		world_dim_spr.size = Vector2(6000, 3000)
		world_dim_spr.position = Vector2(-3000, -1500)
		world_dim_spr.z_as_relative = false
		world_dim_spr.z_index = -2
		world_dim_spr.visible = false
		add_child(world_dim_spr)

		player.hit_confirmed.connect(_on_player_hit_landed)
		player.short_dash_started.connect(_on_short_dash_started)

	func bind_shade(sh: Node2D) -> void:
		if not sh.shell_broken.is_connected(_on_shade_shell_broken):
			sh.shell_broken.connect(_on_shade_shell_broken)

	func clear_transient() -> void:
		_was_in_a1 = false
		_settle_tick = -1
		_active_settle_idx = -1
		_dash_anim_tick = -1
		_active_dash_idx = -1
		_dim_age = -1.0
		nudged_labels.clear()
		if world_dim_spr != null:
			world_dim_spr.visible = false
		for item in anim_sprites:
			if is_instance_valid(item.spr):
				item.spr.free()
		for item in phys_shards:
			if is_instance_valid(item.spr):
				item.spr.free()
		for item in phys_feathers:
			if is_instance_valid(item.spr):
				item.spr.free()
		for g in dash_ghosts:
			if is_instance_valid(g.spr):
				g.spr.free()
		anim_sprites.clear()
		phys_shards.clear()
		phys_feathers.clear()
		dash_ghosts.clear()

	func _premul_color(c: Color, alpha_k: float = 1.0) -> Color:
		var a := clampf(c.a * alpha_k, 0.0, 1.0)
		return Color(c.r * a, c.g * a, c.b * a, a)

	func _spawn_frame_sequence(
		frames: Array,
		world_pos: Vector2,
		frame_durations: Array,
		base_scale: Vector2,
		rot_rad: float = 0.0,
		z_idx: int = 4,
		centered_flag: bool = true,
		custom_offset: Vector2 = Vector2.ZERO,
		raw_col: Color = Color(1.0, 1.0, 1.0, 1.0),
		scale_end_mult: float = 1.0,
		delay_sec: float = 0.0,
		slide_vel: Vector2 = Vector2.ZERO,
		slide_drag: float = 6.0
	) -> void:
		if frames.is_empty():
			return
		var spr := Sprite2D.new()
		spr.material = premul_unshaded_mat
		spr.centered = centered_flag
		spr.offset = custom_offset
		spr.texture = frames[0]
		spr.global_position = world_pos
		spr.scale = base_scale
		spr.rotation = rot_rad
		spr.modulate = _premul_color(raw_col, 1.0)
		spr.z_as_relative = false
		spr.z_index = z_idx
		spr.visible = (delay_sec <= 0.0001)
		stage.add_child(spr)
		anim_sprites.append({
			"spr": spr,
			"frames": frames,
			"durs": frame_durations,
			"idx": 0,
			"t": 0.0,
			"total_t": 0.0,
			"total_dur": _sum_arr(frame_durations),
			"base_scale": base_scale,
			"scale_end": scale_end_mult,
			"raw_col": raw_col,
			"delay": delay_sec,
			"vel": slide_vel,
			"drag": slide_drag,
		})

	func _sum_arr(arr: Array) -> float:
		var s := 0.0
		for v in arr:
			s += float(v)
		return maxf(s, 0.001)

	func _spawn_ai_water_wave(
		ground_pos: Vector2, dir_sign: int, sx_mag: float, sy_mag: float, forward_spd: float = 175.0
	) -> void:
		var tex_list: Array = vfx_bank.get("water_splash", [])
		if tex_list.is_empty():
			return
		# z_index = 3 (< _water.z_index = 6)：劈水卷浪紧贴湿石板向前滑推，且自动实时映入下方河道水波！
		_spawn_frame_sequence(
			tex_list,
			ground_pos,
			[0.042, 0.062, 0.064, 0.074],
			Vector2(sx_mag * float(dir_sign), sy_mag),
			0.0,
			3,
			false,
			Vector2(-125.0, -376.0),
			Color(0.88, 0.94, 1.05, 0.94),
			1.08,
			0.0,
			Vector2(forward_spd * float(dir_sign), 0.0),
			6.2
		)

	func _spawn_ai_water_ripple_only(ground_pos: Vector2, scale_mag: float) -> void:
		var tex_list: Array = vfx_bank.get("water_splash", [])
		if tex_list.size() < 4:
			return
		_spawn_frame_sequence(
			[tex_list[3]],
			ground_pos,
			[0.18],
			Vector2(scale_mag, scale_mag * 0.72),
			0.0,
			1,
			false,
			Vector2(-192.0, -375.0),
			Color(0.85, 0.92, 1.04, 0.78),
			1.24
		)

	func _spawn_ai_hit_slash(hit_pos: Vector2, f_sign: float, heavy: bool, delay_sec: float = 0.0) -> void:
		var tex_list: Array = vfx_bank.get("hit_slash", [])
		if tex_list.is_empty():
			return
		var sc := 0.52 if heavy else 0.40
		# 关键动力学修正：将原左下->右上(/)斩爆垂直翻转为左上->右下(\)，100% 顺应普攻1段当头重劈轨迹，绝不逆插主角面庞！
		_spawn_frame_sequence(
			tex_list,
			hit_pos,
			[0.034, 0.052, 0.048, 0.046],
			Vector2(sc * f_sign, -sc),
			deg_to_rad(6.0 * f_sign),
			5,
			true,
			Vector2.ZERO,
			Color(1.06, 1.00, 1.12, 0.98),
			1.08,
			delay_sec,
			Vector2(f_sign * 42.0, 18.0),
			8.0
		)

	func _spawn_ai_feathers(hit_pos: Vector2, f_sign: float, count: int, heavy: bool, delay_sec: float = 0.0) -> void:
		var burst_list: Array = vfx_bank.get("feather_burst", [])
		if not burst_list.is_empty():
			var b_sc := 0.38 if heavy else 0.30
			# z_index = -1：鸦墨黑雾衬在受击怪身后，既托出前景刀光与碎瓷的锐利剪影，又绝不糊住前景受击焦点！
			_spawn_frame_sequence(
				burst_list,
				hit_pos + Vector2(f_sign * 18.0, -4.0),
				[0.048, 0.064],
				Vector2(b_sc * f_sign, b_sc),
				deg_to_rad(6.0 * f_sign),
				-1,
				true,
				Vector2.ZERO,
				Color(0.96, 0.94, 1.04, 0.92),
				1.14,
				delay_sec
			)

		var f_texs: Array = vfx_bank.get("feathers", [])
		if f_texs.is_empty():
			return
		for i in count:
			var tex: Texture2D = f_texs[i % f_texs.size()]
			var spr := Sprite2D.new()
			spr.material = premul_unshaded_mat
			spr.texture = tex
			spr.centered = true
			var sc := rng.randf_range(0.17, 0.25) * (1.12 if heavy else 1.0)
			spr.scale = Vector2(sc * (1.0 if (i % 2 == 0) else -1.0), sc)
			spr.z_as_relative = false
			spr.z_index = 5
			var raw_c := Color(0.96, 0.94, 1.05, 0.96)
			spr.modulate = _premul_color(raw_c, 1.0)
			spr.visible = (delay_sec <= 0.0001)

			# 顺着劈砍前上方扇面 (-76° .. +24°) 炸散，避免逆飞糊住主角脸部
			var deg := -76.0 + (100.0 * float(i) / maxf(1.0, float(count - 1))) + rng.randf_range(-6.0, 6.0)
			var ang := deg_to_rad(deg)
			if f_sign < 0.0:
				ang = PI - ang
			var spd := rng.randf_range(420.0, 820.0) * (1.12 if heavy else 1.0)
			var vel := Vector2(cos(ang), sin(ang)) * spd
			var ofs := Vector2(cos(ang), sin(ang)) * rng.randf_range(16.0, 36.0)
			spr.global_position = hit_pos + ofs
			spr.rotation = vel.angle() + PI * 0.25
			stage.add_child(spr)

			phys_feathers.append({
				"spr": spr,
				"vel": vel,
				"base_sc": spr.scale,
				"raw_col": raw_c,
				"delay": delay_sec,
				"age": 0.0,
				"life": rng.randf_range(0.64, 0.94),
				"phase": rng.randf_range(0.0, TAU),
				"spin_bias": rng.randf_range(-0.6, 0.6),
			})

	func _spawn_ai_porcelain_shatter(core_pos: Vector2, exit_pos: Vector2, f_sign: float, floor_y: float) -> void:
		var burst_list: Array = vfx_bank.get("porcelain_burst", [])
		if burst_list.size() >= 3:
			# 【第 1 拍 · delay = 0.00s (f_008..009)】：紧凑金缮冰裂球核锁在甲影胸甲正中，主角满月白光 100% 完整切入！
			_spawn_frame_sequence(
				[burst_list[0]],
				core_pos,
				[0.036],
				Vector2(0.34, 0.34),
				0.0,
				4,
				true,
				Vector2.ZERO,
				Color(1.05, 1.02, 0.98, 0.94),
				1.10,
				0.0
			)
			# 【第 2 拍 · delay = 0.034s (f_010..014)】：金缮白瓷爆环在受击出刀侧 (exit_pos) 炸开，尺度精控 0.48，绝不糊脸！
			_spawn_frame_sequence(
				[burst_list[1], burst_list[2]],
				exit_pos,
				[0.052, 0.062],
				Vector2(0.48 * f_sign, 0.48),
				deg_to_rad(-6.0 * f_sign),
				4,
				true,
				Vector2.ZERO,
				Color(0.96, 0.96, 1.02, 0.90),
				1.15,
				0.034,
				Vector2(f_sign * 36.0, 0.0),
				7.0
			)

		var shard_texs: Array = vfx_bank.get("porcelain_shards", [])
		if shard_texs.is_empty():
			return
		# 【第 3 拍 · delay = 0.048s (f_011+)】：10 枚立体金缮碎瓷顺着斩击前上方锥角 (-78°..+14°) 崩飞并在湿街弹跳溅起水环！
		var raw_shard_col := Color(0.90, 0.94, 1.04, 0.96)
		for i in 10:
			var tex: Texture2D = shard_texs[i % shard_texs.size()]
			var spr := Sprite2D.new()
			spr.material = premul_unshaded_mat
			spr.texture = tex
			spr.centered = true
			var sc := rng.randf_range(0.19, 0.25) if i < 5 else rng.randf_range(0.14, 0.19)
			spr.scale = Vector2(sc * (1.0 if (i % 2 == 0) else -1.0), sc)
			spr.z_as_relative = false
			spr.z_index = 5
			spr.modulate = _premul_color(raw_shard_col, 1.0)
			spr.visible = false

			var deg := -78.0 + float(i) * 9.8 + rng.randf_range(-3.5, 3.5)
			var launch_a := deg_to_rad(deg)
			if f_sign < 0.0:
				launch_a = PI - launch_a
			var dir := Vector2(cos(launch_a), sin(launch_a))
			var spd := rng.randf_range(420.0, 790.0)
			spr.global_position = exit_pos + dir * rng.randf_range(18.0, 36.0) + Vector2(0.0, -4.0)
			spr.rotation = rng.randf_range(0.0, TAU)
			stage.add_child(spr)

			phys_shards.append({
				"spr": spr,
				"vel": dir * spd,
				"vrot": rng.randf_range(-13.0, 13.0),
				"floor_y": floor_y - 3.0,
				"bounced": false,
				"raw_col": raw_shard_col,
				"delay": 0.048,
				"age": 0.0,
				"life": rng.randf_range(0.72, 0.98),
			})

	func _spawn_dash_silhouette_ghost(dash_frame_dict: Dictionary, dir_sign: int) -> void:
		var tex: Texture2D = Art.textures.get(String(dash_frame_dict.get("asset", "")))
		if tex == null:
			return
		var g := Sprite2D.new()
		g.material = ghost_unshaded_mat
		Art.apply(g, dash_frame_dict, disp_scale)
		g.scale.x = absf(g.scale.x) * float(dir_sign)
		g.global_position = actor_spr.global_position
		g.z_as_relative = false
		g.z_index = -1
		var gc := Color(0.32, 0.18, 0.74, 0.44)
		g.modulate = _premul_color(gc, 1.0) if Art.premultiply else gc
		stage.add_child(g)
		dash_ghosts.append({
			"spr": g,
			"raw_col": gc,
			"age": 0.0,
			"life": 0.11,
		})

	func _on_short_dash_started(dir_sign: int, origin: Vector2) -> void:
		_dash_anim_tick = 0
		_active_dash_idx = 0
		_dash_dir_sign = dir_sign
		_settle_tick = -1
		_active_settle_idx = -1
		var feet: Vector2 = origin + Vector2(0.0, float(player.foot_offset))
		# 起闪脚跟向后掀开一朵轻盈贴地的 AI 手绘水浪
		_spawn_ai_water_wave(feet + Vector2(-float(dir_sign) * 14.0, 2.0), -dir_sign, 0.30, 0.19, 95.0)

	func _on_player_hit_landed(target: Node2D, mv: Resource, _point: Vector2) -> void:
		if target == null or not target.is_in_group(&"shade") or mv == null:
			return
		# 若同一帧已触发精英破壳三拍演出，则由破壳演出统一接管，避免双份斩爆叠加！
		if Engine.get_physics_frames() == _shell_broken_frame:
			return
		var f_sign := float(player.facing)
		var exit_pos := target.global_position + Vector2(f_sign * 24.0, -34.0)
		if _cut_spawned_serial != player.action_serial:
			_cut_spawned_serial = player.action_serial
			_spawn_ai_hit_slash(exit_pos, f_sign, false, 0.0)
		_spawn_ai_feathers(exit_pos, f_sign, 5, false, 0.0)

	func _on_shade_shell_broken(sh: Node2D) -> void:
		if sh == null or not is_instance_valid(sh):
			return
		_shell_broken_frame = Engine.get_physics_frames()
		_cut_spawned_serial = player.action_serial
		var f_sign := float(player.facing)
		var core_pos: Vector2 = sh.global_position + Vector2(f_sign * 6.0, -34.0)
		var exit_pos: Vector2 = sh.global_position + Vector2(f_sign * 26.0, -34.0)

		# z=-2 仅压暗雨街背景 0.18s，主角、满月白光与金缮碎瓷 100% 耀眼夺目！
		_dim_age = 0.0
		world_dim_spr.global_position = stage.camera.global_position - Vector2(3000, 1500)
		world_dim_spr.color = Color(0.03, 0.02, 0.08, 0.56)
		world_dim_spr.visible = true

		_spawn_ai_porcelain_shatter(core_pos, exit_pos, f_sign, stage.floor_y)
		_spawn_ai_hit_slash(exit_pos, f_sign, true, 0.016)
		_spawn_ai_feathers(exit_pos, f_sign, 10, true, 0.034)

	func _apply_actor_override() -> void:
		if _active_dash_idx >= 0 and _active_dash_idx < dash_frames.size():
			var vis := player.get_node("Visual") as Node2D
			vis.scale = Vector2(float(player.facing), 1.0)
			Art.apply(actor_spr, dash_frames[_active_dash_idx], disp_scale)
			actor_spr.scale.x = absf(actor_spr.scale.x)
		elif _active_settle_idx >= 0 and _active_settle_idx < settle_frames.size():
			Art.apply(actor_spr, settle_frames[_active_settle_idx], disp_scale)
			actor_spr.scale.x = absf(actor_spr.scale.x)

	func _process(_delta: float) -> void:
		_apply_actor_override()

	func _physics_process(delta: float) -> void:
		if stage.get("_impact_rings") != null:
			stage._impact_rings.clear()

		# 将新增的受击伤害跳字微抬 32px，避免压在金缮爆环或斜劈火心正中央
		for child in stage.fx.get_children():
			if child is Label:
				var lbl := child as Label
				var iid: int = lbl.get_instance_id()
				if not nudged_labels.has(iid):
					nudged_labels[iid] = true
					lbl.position.y -= 32.0

		var in_a1: bool = (int(player.state) == 1 and player.current_move != null and String(player.current_move.animation) == "attack_1")
		var feet: Vector2 = player.global_position + Vector2(0.0, float(player.foot_offset))

		if in_a1:
			_settle_tick = -1
			_active_settle_idx = -1
			var anim_sec: float = player.current_move.anim_seconds(float(player.move_frame))
			var cur_idx := int(floor(anim_sec * 24.0 + 0.001))
			# cur_idx >= 5 (f_007..008 满月巨弧劈落积水路面瞬间)：在刀尖前方 166px 贴地同步推出扁平修长的劈水卷浪与河道倒影！
			if cur_idx >= 5 and _water_sprayed_serial != player.action_serial:
				_water_sprayed_serial = player.action_serial
				_spawn_ai_water_wave(
					feet + Vector2(float(player.facing) * 166.0, 2.0),
					player.facing,
					0.52,
					0.29,
					185.0
				)

		# 普攻1段自然收招结束且未接招/移动时，无缝播放 4 帧 AI 手绘旋腕收剑回身过渡（每帧 3 ticks = 12 ticks）
		if _was_in_a1 and not in_a1:
			if int(player.state) == 0 and player.is_on_floor() and int(player._short_dash_ticks) <= 0 and absf(player.velocity.x) < 30.0:
				_settle_tick = 0
		_was_in_a1 = in_a1

		if _settle_tick >= 0:
			if int(player.state) != 0 or not player.is_on_floor() or int(player._short_dash_ticks) > 0 or absf(player.velocity.x) > 35.0:
				_settle_tick = -1
				_active_settle_idx = -1
			else:
				_active_settle_idx = clampi(_settle_tick / 3, 0, settle_frames.size() - 1)
				_settle_tick += 1
				if _settle_tick >= settle_frames.size() * 3:
					_settle_tick = -1
		else:
			_active_settle_idx = -1

		# 6 帧 AI 手绘高速流线短闪（[1, 2, 2, 1, 1, 1] 节奏锁住峰值紫芒楔形流光 + 2 道冷紫身形剪影残影 + 刹步推水！）
		if int(player._short_dash_ticks) > 0 or (_dash_anim_tick >= 0 and _dash_anim_tick < DASH_TICK_MAP.size()):
			if int(player.state) != 0:
				_dash_anim_tick = -1
				_active_dash_idx = -1
			else:
				var map_i := clampi(_dash_anim_tick, 0, DASH_TICK_MAP.size() - 1)
				_active_dash_idx = clampi(int(DASH_TICK_MAP[map_i]), 0, dash_frames.size() - 1)
				_apply_actor_override()
				if _dash_anim_tick == 2 or _dash_anim_tick == 4:
					_spawn_dash_silhouette_ghost(dash_frames[_active_dash_idx], _dash_dir_sign)
				if _dash_anim_tick == 5:
					_spawn_ai_water_wave(
						feet + Vector2(float(_dash_dir_sign) * 26.0, 2.0),
						_dash_dir_sign,
						0.28,
						0.16,
						115.0
					)
				_dash_anim_tick += 1
		else:
			_dash_anim_tick = -1
			_active_dash_idx = -1

		_apply_actor_override()
		_step_ai_vfx(delta, player.is_in_hitstop())

	func _step_ai_vfx(delta: float, in_hitstop: bool) -> void:
		var dt_seq := delta * (0.48 if in_hitstop else 1.0)
		var dt_phys := delta * (0.42 if in_hitstop else 1.0)

		if _dim_age >= 0.0:
			_dim_age += delta
			if _dim_age >= _dim_life:
				_dim_age = -1.0
				world_dim_spr.visible = false
			else:
				var k := 1.0 - (_dim_age / _dim_life)
				world_dim_spr.color.a = 0.56 * k * k

		for i in range(dash_ghosts.size() - 1, -1, -1):
			var g := dash_ghosts[i]
			var spr: Sprite2D = g.spr
			if not is_instance_valid(spr):
				dash_ghosts.remove_at(i)
				continue
			g.age = float(g.age) + delta
			if float(g.age) >= float(g.life):
				spr.queue_free()
				dash_ghosts.remove_at(i)
				continue
			var gk := 1.0 - float(g.age) / float(g.life)
			var gc: Color = g.raw_col
			spr.modulate = _premul_color(gc, gk * gk) if Art.premultiply else Color(gc.r, gc.g, gc.b, gc.a * gk * gk)

		for i in range(anim_sprites.size() - 1, -1, -1):
			var it := anim_sprites[i]
			var spr: Sprite2D = it.spr
			if not is_instance_valid(spr):
				anim_sprites.remove_at(i)
				continue
			if float(it.delay) > 0.0:
				it.delay = float(it.delay) - delta
				if float(it.delay) > 0.0:
					continue
				spr.visible = true

			it.t = float(it.t) + dt_seq
			it.total_t = float(it.total_t) + dt_seq
			var vel: Vector2 = it.vel
			if vel.length_squared() > 0.1:
				spr.global_position += vel * dt_seq
				it.vel = vel.lerp(Vector2.ZERO, clampf(dt_seq * float(it.drag), 0.0, 1.0))

			var durs: Array = it.durs
			while int(it.idx) < durs.size() and float(it.t) >= float(durs[it.idx]):
				it.t = float(it.t) - float(durs[it.idx])
				it.idx = int(it.idx) + 1
			if int(it.idx) >= durs.size():
				spr.queue_free()
				anim_sprites.remove_at(i)
				continue
			spr.texture = it.frames[it.idx]
			var u := clampf(float(it.total_t) / float(it.total_dur), 0.0, 1.0)
			spr.scale = (it.base_scale as Vector2) * lerpf(1.0, float(it.scale_end), u)
			var ak := 1.0 if u <= 0.70 else (1.0 - (u - 0.70) / 0.30)
			spr.modulate = _premul_color(it.raw_col as Color, ak)

		for i in range(phys_shards.size() - 1, -1, -1):
			var s := phys_shards[i]
			var spr: Sprite2D = s.spr
			if not is_instance_valid(spr):
				phys_shards.remove_at(i)
				continue
			if float(s.delay) > 0.0:
				s.delay = float(s.delay) - delta
				if float(s.delay) > 0.0:
					continue
				spr.visible = true

			s.age = float(s.age) + delta
			if float(s.age) >= float(s.life):
				spr.queue_free()
				phys_shards.remove_at(i)
				continue
			s.vel.y += 1440.0 * delta
			spr.global_position += (s.vel as Vector2) * delta
			spr.rotation += float(s.vrot) * delta
			if spr.global_position.y >= float(s.floor_y) and float(s.vel.y) > 0.0:
				spr.global_position.y = float(s.floor_y)
				s.vel.y = -float(s.vel.y) * 0.42
				s.vel.x *= 0.68
				s.vrot = float(s.vrot) * 0.52
				if not bool(s.bounced):
					s.bounced = true
					_spawn_ai_water_ripple_only(Vector2(spr.global_position.x, float(s.floor_y) + 4.0), 0.22)
			var rem_s := clampf((float(s.life) - float(s.age)) / 0.18, 0.0, 1.0)
			spr.modulate = _premul_color(s.raw_col as Color, rem_s)

		for i in range(phys_feathers.size() - 1, -1, -1):
			var f := phys_feathers[i]
			var spr: Sprite2D = f.spr
			if not is_instance_valid(spr):
				phys_feathers.remove_at(i)
				continue
			if float(f.delay) > 0.0:
				f.delay = float(f.delay) - delta
				if float(f.delay) > 0.0:
					continue
				spr.visible = true

			f.age = float(f.age) + dt_phys
			if float(f.age) >= float(f.life):
				spr.queue_free()
				phys_feathers.remove_at(i)
				continue
			if float(f.age) < 0.13:
				f.vel *= pow(0.16, dt_phys * 5.0)
				spr.global_position += (f.vel as Vector2) * dt_phys
				spr.rotation = (f.vel as Vector2).angle() + PI * 0.25
			else:
				var fl_t: float = (float(f.age) - 0.13) * 8.5 + float(f.phase)
				var sway := sin(fl_t) * 62.0
				f.vel = (f.vel as Vector2).lerp(Vector2(sway, 54.0), clampf(dt_phys * 8.5, 0.0, 1.0))
				spr.global_position += (f.vel as Vector2) * dt_phys
				spr.rotation = lerpf(spr.rotation, float(f.spin_bias) + sin(fl_t) * 0.52, clampf(dt_phys * 6.5, 0.0, 1.0))
				var base_sc: Vector2 = f.base_sc
				spr.scale = Vector2(base_sc.x, base_sc.y * (0.72 + 0.28 * cos(fl_t * 1.3)))
			var rem_f := clampf((float(f.life) - float(f.age)) / 0.20, 0.0, 1.0)
			spr.modulate = _premul_color(f.raw_col as Color, rem_f)
