extends SceneTree
## 《断晓》第一章 · 影街 — 6 节点商业特征升级版可玩实机灰盒原型（2026-11-14）
## 零触碰其他工作线文件；继承 rain_street.gd 全部真实主角手感、敌人 AI、分层远景与后期光影。
##
## 人类直接试玩（按数字键 1~6 秒切 6 个关卡节点，F2 重刷本关波次，F1 看碰撞框）：
##   engine\Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/dev/play_ch1_shadow_street.gd --resolution 1280x720
##
## 原生窗口自动化验收 + 实机截图（严禁加 --headless）：
##   $env:SHOT_OUT="docs/视觉设计/雨夜河岸街/影街灰盒实机_20261114"; engine\Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/dev/play_ch1_shadow_street.gd --resolution 1280x720 --fixed-fps 60

const Buffer := preload("res://scripts/core/input_buffer.gd")
const Shade := preload("res://scripts/night/shade.gd")

var stage: Ch1ShadowStreetStage


func _initialize() -> void:
	call_deferred("_boot")


func _hide_debug_overlays() -> void:
	for child in root.get_children():
		var nm := String(child.name)
		if nm.begins_with("Panku") or nm.to_lower().contains("panku") or nm.to_lower().contains("console"):
			if child is CanvasLayer:
				child.visible = false
			for sub in child.get_children():
				if sub is CanvasItem or sub is CanvasLayer:
					sub.visible = false


func _boot() -> void:
	stage = Ch1ShadowStreetStage.new()
	root.add_child(stage)
	current_scene = stage
	_hide_debug_overlays()
	await process_frame
	_hide_debug_overlays()
	for i in 4:
		await physics_frame
	var shot_out := OS.get_environment("SHOT_OUT")
	if shot_out != "":
		await _run_verification_and_shots(shot_out)
		quit()
		return
	DisplayServer.window_set_title("《断晓》第一章·影街 实机试玩 — 按 1~6 切关 / F3 切换成图与灰盒 / F2 重刷敌波 / F1 碰撞框")
	stage.warp_to_stage(0, true)
	print("CH1_SHADOW_STREET_PLAYABLE_READY (按 1-6 切换关卡, F3 切换厚涂成图/灰盒, F2 重刷敌波, F1 碰撞框)")


func _frames(n: int, f: Buffer.Frame = null) -> void:
	for i in n:
		if f != null:
			stage.player.set_injected_frame(f)
		await physics_frame


func _fr(actions: Array[StringName] = [], axis := Vector2.ZERO, pressed: Array[StringName] = []) -> Buffer.Frame:
	var f := Buffer.Frame.new()
	f.actions = actions
	f.pressed_this_frame = pressed
	f.axis = axis
	return f


func _run_verification_and_shots(out_rel: String) -> void:
	var abs_dir := ProjectSettings.globalize_path("res://" + out_rel) if not out_rel.contains(":") else out_rel
	DirAccess.make_dir_recursive_absolute(abs_dir)
	if stage.hud != null:
		stage.hud.help_visible = false
	for hk in [&"move", &"floors", &"drop", &"parry", &"knockback", &"brute", &"archer", &"bomber", &"blast", &"air", &"chain", &"guard", &"ult"]:
		stage._hints_done[hk] = true
	stage._hint_queue.clear()

	# 1) 验证主角一段跳高度 >= 280px（确保 580 -> 300 -> 20 全章平台 100% 可达）
	stage.warp_to_stage(0, false)
	var c0 := stage._center_of(0)
	stage.player.reset_state(Vector2(c0 - 1300.0, 580.0 - stage.player.foot_offset))
	await _frames(15, _fr())
	var highest_feet := 580.0
	await _frames(1, _fr([&"jump"], Vector2.ZERO, [&"jump"]))
	for i in 42:
		await _frames(1, _fr([&"jump"]))
		highest_feet = minf(highest_feet, stage.player.global_position.y + stage.player.foot_offset)
	var jump_gain := 580.0 - highest_feet
	assert(jump_gain >= 320.0, "一段跳高度不足: %.1f" % jump_gain)
	print("VERIFY_SINGLE_JUMP_OK gain=%.1fpx (>280px step)" % jump_gain)
	stage.player.clear_input_queue()

	# 2) 验证 1-3B 两撞碎裂黄铜立钟柜：第 1 撞裂玻璃爆齿轮仍挡路，第 2 撞彻底崩碎移除实心墙
	stage.warp_to_stage(4, false)
	var c4: float = stage._center_of(4)
	var cab_blocks_before: int = int(stage.terrain.blocks.size())
	var cab_wx: float = c4 - 680.0
	stage.damage_cabinet_near(Vector2(cab_wx - 55.0, 500.0), 520.0)
	assert(stage.get_cabinet_hp(4, 0) == 1, "第 1 撞后立钟柜应剩 1 点耐久")
	assert(int(stage.terrain.blocks.size()) == cab_blocks_before, "第 1 撞后立钟柜仍保留反弹墙体")
	stage.damage_cabinet_near(Vector2(cab_wx - 55.0, 500.0), 610.0)
	assert(stage.get_cabinet_hp(4, 0) == 0, "第 2 撞后立钟柜应彻底碎裂")
	assert(int(stage.terrain.blocks.size()) == cab_blocks_before - 1, "第 2 撞后实心阻挡块应已从 terrain.blocks 移除")
	print("VERIFY_BREAKABLE_CABINET_2HIT_OK blocks %d -> %d" % [cab_blocks_before, int(stage.terrain.blocks.size())])

	# 3) 逐关截取真实 1280x720 原生画面（含建筑光影特征与刷怪长影/战斗态势）
	var shots := [
		{"idx": 0, "file": "01_1-1_无人夜宴街_空轿与暖窗皮影.png", "px": -1480.0, "py": 580.0, "fight": true, "wait": 54},
		{"idx": 1, "file": "02_1-2A_飞鸦玻璃花房顶_发光穹脊与雾海.png", "px": -520.0, "py": 20.0, "fight": true, "wait": 56},
		{"idx": 2, "file": "03_1-2B_百表当铺夹巷_飞扶壁与千表窗.png", "px": -620.0, "py": 580.0, "fight": true, "wait": 56},
		{"idx": 3, "file": "04_1-3A_逆影铸铁飞廊_朱红琴弦光栅.png", "px": -360.0, "py": 20.0, "fight": true, "wait": 56},
		{"idx": 4, "file": "05_1-3B_司辰铸钟残廊_擒纵轮与碎裂钟柜.png", "px": -940.0, "py": 580.0, "fight": true, "cracked_demo": true, "wait": 52},
		{"idx": 5, "file": "06_1-4_巨钟背影盘旋阶_反投巨影.png", "px": -120.0, "py": 215.0, "fight": false, "wait": 30},
	]
	for s in shots:
		var idx: int = int(s.idx)
		stage.warp_to_stage(idx, bool(s.fight))
		var cx: float = stage._center_of(idx)
		var target_x: float = cx + float(s.px)
		var sup_y: float = float(stage.terrain.support_y(target_x, float(s.py) - 12.0, 14.0))
		stage.player.reset_state(Vector2(target_x, sup_y - stage.player.foot_offset))
		stage.player.facing = 1
		stage._cam_feet = sup_y
		stage.camera.lock_y = stage._cam_y_for(sup_y)
		stage.camera.global_position = Vector2(target_x + 220.0, stage.camera.lock_y)
		stage.camera.reset_smoothing()
		if s.get("cracked_demo", false):
			stage.damage_cabinet_near(Vector2(cx - 680.0 - 50.0, 500.0), 560.0)
		_hide_debug_overlays()
		for k in int(s.wait):
			await physics_frame
		if stage.hud != null:
			stage.hud.banner("", "", 0.0)
		await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_viewport().get_texture().get_image()
		var out_path := abs_dir.path_join(String(s.file))
		img.save_png(out_path)
		print("SHOT_SAVED ", s.file, " size=", img.get_size())


# =============================================================================
# 第一章 · 影街 专属舞台类（继承 RainStreet，零改外部脚本）
# =============================================================================
class Ch1ShadowStreetStage extends "res://scripts/night/rain_street.gd":
	var current_stage_idx: int = 0
	var use_painted_bg: bool = true
	var _painted_tex: Array[Texture2D] = []
	var _art_back: Node2D
	var _art_front: Node2D
	var _nav_label: Label
	var _cabinets: Dictionary = {}       ## sec_idx -> Array[{x0, x1, y, hp, block_dict, piece}]
	var _debris: Array = []              ## [{p, v, rot, vr, r, kind, life}]
	var _telegraphs: Array = []          ## [{shade, total, left, origin}]

	const PAINTED_BG_FILES := [
		"docs/视觉设计/地图规划/第一章成图_20261114/成图16x9_01_1-1_无人夜宴街.png",
		"docs/视觉设计/地图规划/第一章成图_20261114/成图16x9_02_1-2A_飞鸦玻璃花房顶.png",
		"docs/视觉设计/地图规划/第一章成图_20261114/成图16x9_03_1-2B_百表当铺夹巷.png",
		"docs/视觉设计/地图规划/第一章成图_20261114/成图16x9_04_1-3A_逆影铸铁飞廊.png",
		"docs/视觉设计/地图规划/第一章成图_20261114/成图16x9_05_1-3B_司辰铸钟残廊.png",
		"docs/视觉设计/地图规划/第一章成图_20261114/成图16x9_06_1-4_巨钟背影盘旋阶.png",
	]
	const PAINTED_GROUND_FRAC := [0.870, 0.778, 0.866, 0.892, 0.868, 0.865]

	const STAGE_SPECS := [
		{
			"code": "1-1",
			"name": "无人夜宴街 · 空轿与暖窗皮影",
			"sub": "1300px 追斩撞墙大道 · 无马空轿投四奔马长影 · 二楼琥珀磨砂窗无主华尔兹",
			"blocks": [
				[-1860, -1680, 436, "stone"],
				[-680, -520, 300, "stone"],
				[560, 760, 404, "stone"],
				[1860, 2000, 436, "stone"],
			],
			"platforms": [
				[-1660, -940, 300, "slab"],
				[-360, 300, 300, "slab"],
				[820, 1580, 300, "slab"],
				[-1220, -760, 20, "slab"],
				[980, 1440, 20, "slab"],
			],
			"slopes": [
				[260, 580, 480, 532, "steps", {"solid": true}],
				[480, 532, 1240, 532, "steps", {"solid": true}],
				[1240, 532, 1460, 580, "steps", {"solid": true}],
			],
			"lamps": [
				[-1760, 396, "wall"], [-1160, 330, "street"], [-595, 290, "street"],
				[120, 330, "street"], [920, 360, "wall"], [1680, 330, "street"],
			],
			"spawns": [[-1160, 580], [-880, 580], [220, 580], [1040, 532], [-1320, 300], [1180, 300]],
			"waves": [
				{"label": "1-1 夜宴狂影 · 追斩撞墙", "spawns": [G, G, B], "reinforce": [G, A], "reinforce_at": 1, "max_attackers": 2},
			],
		},
		{
			"code": "1-2A",
			"name": "飞鸦玻璃花房顶 · 发光穹脊与雾海",
			"sub": "真高空铅皮天沟（下为万家雾海无马路） · 560px 极限下砸爆 1.4x 满冲击",
			"blocks": [
				[-1960, -1820, 420, "stone"],
				[-70, 70, 440, "stone"],
				[1820, 1960, 420, "stone"],
			],
			"platforms": [
				[-1860, -1400, 300, "plank"],
				[-240, 240, 300, "plank"],
				[1400, 1860, 300, "plank"],
				[-1320, -300, 20, "slab"],
				[300, 1320, 20, "slab"],
			],
			"slopes": [],
			"lamps": [
				[-810, 240, "wall"], [810, 240, "wall"], [0, 280, "street"],
			],
			"spawns": [[-620, 580], [-360, 580], [380, 580], [-820, 20], [780, 20], [640, 580]],
			"waves": [
				{"label": "1-2A 温室高脊 · 天降下砸", "spawns": [G, G, B, A], "reinforce": [G, X], "reinforce_at": 2, "max_attackers": 2},
			],
		},
		{
			"code": "1-2B",
			"name": "百表当铺夹巷 · 飞扶壁拱洞与千表窗",
			"sub": "五层黑石一线天 · 3 道可穿行飞扶壁拱洞 · 窄巷聚怪一刀贯串破白壳",
			"blocks": [
				[-1275, -1125, -240, "stone", {"bottom": 165}],
				[-75, 75, -240, "stone", {"bottom": 165}],
				[1125, 1275, -240, "stone", {"bottom": 165}],
				[-1265, -1135, 452, "stone"],
				[-65, 65, 452, "stone"],
				[1135, 1265, 452, "stone"],
			],
			"platforms": [
				[-1960, -1340, 300, "plank"],
				[-1060, -160, 300, "plank"],
				[160, 1060, 300, "plank"],
				[1340, 1960, 300, "plank"],
				[-960, -240, 20, "plank"],
				[240, 960, 20, "plank"],
			],
			"slopes": [],
			"lamps": [
				[-420, 430, "street"], [-580, 440, "wall"], [620, 360, "wall"], [-1560, 360, "wall"],
			],
			"spawns": [[-340, 580], [-210, 580], [-90, 580], [320, 580], [-560, 300], [560, 300]],
			"waves": [
				{"label": "1-2B 千表夹巷 · 一刀贯串", "spawns": [B, G, G, B], "reinforce": [G, A], "reinforce_at": 2, "max_attackers": 2},
			],
		},
		{
			"code": "1-3A",
			"name": "逆影铸铁飞廊 · 朱红琴弦光栅",
			"sub": "y=20 全场贯通双层铁廊桥 · 60° 朱红×冷银琴弦光栅 · 桥墩黑影逆流上爬",
			"blocks": [
				[-1480, -1320, 430, "stone"],
				[-80, 80, 430, "stone"],
				[1320, 1480, 430, "stone"],
			],
			"platforms": [
				[-1660, -1140, 300, "slab"],
				[-260, 260, 300, "slab"],
				[1140, 1660, 300, "slab"],
				[-2150, -700, 20, "slab"],
				[-500, 500, 20, "slab"],
				[700, 2150, 20, "slab"],
			],
			"slopes": [],
			"lamps": [
				[-1400, 280, "wall"], [0, 280, "wall"], [1400, 280, "wall"],
			],
			"spawns": [[80, 20], [280, 20], [-880, 20], [-240, 580], [260, 580], [920, 20]],
			"waves": [
				{"label": "1-3A 琴弦飞廊 · 高桥空战", "spawns": [G, A, B, G], "reinforce": [A, X], "reinforce_at": 2, "max_attackers": 2},
			],
		},
		{
			"code": "1-3B",
			"name": "司辰铸钟残廊 · 擒纵巨轮与碎裂立钟柜",
			"sub": "玻璃穹顶室内遮雨 · 3 座永久青铜重墙(1300px) + 3 座两撞炸齿轮立钟柜(600px)",
			"blocks": [
				[-1000, 2360, -220, "slab", {"solid": true, "bottom": -184}],
				[-1350, -1190, 410, "stone"],
				[-70, 90, 390, "stone"],
				[1210, 1390, 400, "stone"],
			],
			"platforms": [
				[-1880, -1400, 300, "plank"],
				[-1120, -200, 300, "plank"],
				[200, 1120, 300, "plank"],
				[1440, 2060, 300, "plank"],
			],
			"slopes": [],
			"lamps": [
				[-1560, 340, "street"], [-680, 430, "wall"], [640, 430, "wall"], [1680, 380, "wall"],
			],
			"cabinets": [-680.0, 640.0, 1880.0],
			"spawns": [[-820, 580], [-460, 580], [340, 580], [-520, 300], [540, 300]],
			"waves": [
				{"label": "1-3B 铸钟残廊 · 弹珠碎柜", "spawns": [B, G, G], "reinforce": [B, X], "reinforce_at": 1, "max_attackers": 2},
			],
		},
		{
			"code": "1-4",
			"name": "巨钟背影盘旋阶 · 塔内反投巨影",
			"sub": "20s 无战斗垂直蓄力 · 直径超屏幕的磨砂红表盘背面反投 IIX 与 5:59 抽动分针黑影",
			"blocks": [],
			"platforms": [
				[-2200, -1820, 580, "slab"],
				[-960, -680, 370, "slab"],
				[180, 460, 160, "slab"],
				[1320, 2080, -60, "slab"],
			],
			"slopes": [
				[-1860, 580, -920, 370, "steps"],
				[-720, 370, 220, 160, "steps"],
				[420, 160, 1360, -60, "steps"],
			],
			"lamps": [
				[120, 120, "street"], [980, -20, "wall"],
			],
			"spawns": [[0, 580]],
			"waves": [],
		},
	]

	func _init() -> void:
		super()
		var secs: Array = []
		var wlist: Array = []
		for sp in STAGE_SPECS:
			secs.append({
				"name": String(sp.code) + " " + String(sp.name),
				"blocks": (sp.blocks as Array).duplicate(true),
				"platforms": (sp.platforms as Array).duplicate(true),
				"slopes": (sp.slopes as Array).duplicate(true),
				"lamps": (sp.lamps as Array).duplicate(true),
				"foreground": [],
				"buildings": [],
				"spawns": (sp.spawns as Array).duplicate(true),
			})
			wlist.append((sp.waves as Array).duplicate(true))
		layout["sections"] = secs
		round_waves = wlist
		stage_title = PackedStringArray(["第一章 · 影街", "空城无一人，满墙皆狂影 · 按 1~6 秒切全章六个节点"])

	func _stage_ready() -> void:
		super()
		# 严守最新世界观铁律：第一章严禁河水/海浪，严禁第二章专属的“门洞白昼光+悬停雨珠”
		if backdrop != null:
			backdrop.daylight_enabled = false
			backdrop.beads_enabled = false
			if backdrop.get("_water") != null:
				backdrop._water.visible = false
			if backdrop.get("_arch_pool") != null:
				backdrop._arch_pool.visible = false
			if backdrop.get("_bead_back") != null:
				backdrop._bead_back.visible = false
			if backdrop.get("_bead_front") != null:
				backdrop._bead_front.visible = false

		_load_painted_textures()

		_art_back = Node2D.new()
		_art_back.name = "Ch1StageArtBack"
		_art_back.z_as_relative = false
		_art_back.z_index = -14
		_art_back.draw.connect(_draw_stage_back)
		add_child(_art_back)

		_art_front = Node2D.new()
		_art_front.name = "Ch1StageArtFront"
		_art_front.z_as_relative = false
		_art_front.z_index = -3
		_art_front.draw.connect(_draw_stage_front)
		add_child(_art_front)

		encounter.shade_spawned.connect(_on_ch1_shade_spawned)

		var ui_layer := CanvasLayer.new()
		ui_layer.layer = 11
		add_child(ui_layer)
		_nav_label = Label.new()
		_nav_label.position = Vector2(24, 684)
		_nav_label.add_theme_font_size_override("font_size", 15)
		_nav_label.add_theme_color_override("font_color", Color(0.84, 0.88, 0.96, 0.92))
		_nav_label.add_theme_color_override("font_outline_color", Color(0.03, 0.04, 0.08, 0.95))
		_nav_label.add_theme_constant_override("outline_size", 4)
		ui_layer.add_child(_nav_label)
		_refresh_nav_text()

	func _load_painted_textures() -> void:
		_painted_tex.clear()
		var loaded_any := false
		for rel in PAINTED_BG_FILES:
			var abs_p := ProjectSettings.globalize_path("res://" + String(rel))
			var tex: Texture2D = null
			if FileAccess.file_exists(abs_p):
				var im := Image.load_from_file(abs_p)
				if im != null and not im.is_empty():
					tex = ImageTexture.create_from_image(im)
					loaded_any = true
			_painted_tex.append(tex)
		if not loaded_any:
			use_painted_bg = false

	func _apply_terrain_visibility() -> void:
		var has_paint := use_painted_bg and current_stage_idx < _painted_tex.size() and _painted_tex[current_stage_idx] != null
		if terrain != null:
			terrain.modulate.a = 0.0 if has_paint else 1.0

	func _refresh_nav_text() -> void:
		if _nav_label == null:
			return
		var sp: Dictionary = STAGE_SPECS[current_stage_idx]
		var mode_str := "厚涂成图" if use_painted_bg else "结构灰盒"
		_nav_label.text = "[1~6]切关  [F3]背景:%s  [F2]重刷敌波  [F1]碰撞框  |  当前：%s %s" % [mode_str, sp.code, sp.name]

	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and not event.echo:
			match event.keycode:
				KEY_1, KEY_KP_1:
					warp_to_stage(0, true)
					return
				KEY_2, KEY_KP_2:
					warp_to_stage(1, true)
					return
				KEY_3, KEY_KP_3:
					warp_to_stage(2, true)
					return
				KEY_4, KEY_KP_4:
					warp_to_stage(3, true)
					return
				KEY_5, KEY_KP_5:
					warp_to_stage(4, true)
					return
				KEY_6, KEY_KP_6:
					warp_to_stage(5, false)
					return
				KEY_F3:
					use_painted_bg = not use_painted_bg
					_apply_terrain_visibility()
					_refresh_nav_text()
					return
				KEY_F2:
					warp_to_stage(current_stage_idx, current_stage_idx < 5)
					return
		if event.is_action_pressed("reset"):
			Engine.time_scale = 1.0
			warp_to_stage(current_stage_idx, current_stage_idx < 5)
		elif event.is_action_pressed("debug_toggle"):
			debug_boxes = not debug_boxes
		elif event.is_action_pressed("toggle_help") and hud != null:
			hud.help_visible = not hud.help_visible

	func warp_to_stage(idx: int, start_combat: bool = true) -> void:
		idx = clampi(idx, 0, STAGE_SPECS.size() - 1)
		current_stage_idx = idx
		encounter.clear_shades()
		_telegraphs.clear()
		_unlock_arena()
		encounter_index = idx
		_ensure_terrain(idx)
		_rebuild_cabinets_for(idx)
		var cx: float = _center_of(idx)
		var spawn_x: float = cx - 1350.0 if idx != 5 else cx - 1920.0
		var sup: float = float(terrain.support_y(spawn_x, -900.0, 16.0))
		player.hp = player.max_hp
		_hp_seen = player.hp
		player.reset_state(Vector2(spawn_x, sup - player.foot_offset))
		_cam_feet = sup
		camera.lock_y = _cam_y_for(sup)
		camera.arena_min = Vector2(cx - arena_half - 40.0, -520.0)
		camera.arena_max = Vector2(cx + arena_half + 40.0, 720.0)
		camera.global_position = Vector2(spawn_x + 180.0, camera.lock_y)
		camera.reset_smoothing()

		# 室内/半室内雨雾适配（1-2A 高空去地涟漪、1-3B 室内穹顶减穿透雨、1-4 塔内全遮雨）
		if backdrop != null:
			if backdrop.get("_ground") != null:
				backdrop._ground.visible = (idx != 1 and idx != 5)
			if backdrop.get("_rain") != null:
				backdrop._rain.visible = (idx != 5)
			if backdrop.get("_rain_through") != null:
				backdrop._rain_through.visible = (idx != 5)
				backdrop._rain_through.modulate.a = 0.22 if idx == 4 else 1.0

		_apply_terrain_visibility()
		var sp: Dictionary = STAGE_SPECS[idx]
		if start_combat and not (sp.waves as Array).is_empty():
			_lock_arena()
		else:
			hud.banner(String(sp.code) + " · " + String(sp.name), String(sp.sub), 2.8)
		_refresh_nav_text()

	func _rebuild_cabinets_for(idx: int) -> void:
		if _cabinets.has(idx):
			for cab in _cabinets[idx]:
				if cab.block_dict != null:
					terrain.blocks.erase(cab.block_dict)
				if is_instance_valid(cab.piece):
					cab.piece.queue_free()
		_cabinets[idx] = []
		_apply_terrain_visibility()
		var sp: Dictionary = STAGE_SPECS[idx]
		if not sp.has("cabinets"):
			return
		var cx := _center_of(idx)
		for rel_x in sp.cabinets:
			var wx := cx + float(rel_x)
			var piece: Node2D = terrain.add_block(wx - 54.0, wx + 54.0, 432.0, "wood", idx)
			piece.visible = false  # 由我们的 2.5D 立钟柜美术节点绘制完整/半碎外观
			var bd: Dictionary = piece.data
			_cabinets[idx].append({
				"wx": wx, "x0": wx - 54.0, "x1": wx + 54.0, "y": 432.0,
				"hp": 2, "block_dict": bd, "piece": piece,
			})

	func get_cabinet_hp(sec_idx: int, cab_i: int) -> int:
		if not _cabinets.has(sec_idx) or cab_i >= _cabinets[sec_idx].size():
			return -1
		return int(_cabinets[sec_idx][cab_i].hp)

	func _on_ch1_shade_spawned(s: Node2D) -> void:
		# 1.0 秒（60 帧）「无主长影从墙面/地面抽搐剥落立起」预警
		s.spawn_frames = 60
		_telegraphs.append({
			"shade": s,
			"total": 60.0,
			"left": 60.0,
			"feet": Vector2(s.global_position.x, s.feet_y()),
		})
		s.wall_slam.connect(func(impact_speed: float, _dmg: float, pt: Vector2):
			damage_cabinet_near(pt, impact_speed)
		)

	func damage_cabinet_near(pt: Vector2, impact_speed: float) -> void:
		if not _cabinets.has(current_stage_idx):
			return
		for cab in _cabinets[current_stage_idx]:
			if int(cab.hp) <= 0:
				continue
			if absf(pt.x - float(cab.wx)) <= 105.0 and pt.y >= float(cab.y) - 40.0:
				cab.hp = int(cab.hp) - 1
				var burst_n := 10 if int(cab.hp) == 1 else 22
				var dir_x := -1.0 if pt.x > float(cab.wx) else 1.0
				for i in burst_n:
					var ang := randf_range(-2.5, -0.5)
					var spd := randf_range(220.0, 620.0)
					_debris.append({
						"p": Vector2(float(cab.wx), randf_range(445.0, 555.0)),
						"v": Vector2(cos(ang) * spd + dir_x * 160.0, sin(ang) * spd - 120.0),
						"rot": randf() * TAU,
						"vr": randf_range(-12.0, 12.0),
						"r": randf_range(6.0, 14.0),
						"gear": (i % 2 == 0),
						"life": randf_range(0.55, 1.05),
					})
				camera.add_shake((5.5 if int(cab.hp) == 1 else 9.5) * shake_mul)
				if fx != null:
					fx.spawn_text(Vector2(float(cab.wx), 395.0), "钟柜裂！" if int(cab.hp) == 1 else "立钟粉碎！通道贯通")
				if int(cab.hp) <= 0:
					if cab.block_dict != null:
						terrain.blocks.erase(cab.block_dict)
						cab.block_dict = null
					if is_instance_valid(cab.piece):
						cab.piece.queue_free()
				break

	func _process(delta: float) -> void:
		super(delta)
		for i in range(_debris.size() - 1, -1, -1):
			var d: Dictionary = _debris[i]
			d.life = float(d.life) - delta
			if float(d.life) <= 0.0:
				_debris.remove_at(i)
				continue
			d.v = (d.v as Vector2) + Vector2(0.0, 1450.0 * delta)
			d.p = (d.p as Vector2) + (d.v as Vector2) * delta
			if (d.p as Vector2).y > floor_y - 4.0:
				d.p = Vector2((d.p as Vector2).x, floor_y - 4.0)
				d.v = Vector2((d.v as Vector2).x * 0.55, -absf((d.v as Vector2).y) * 0.42)
			d.rot = float(d.rot) + float(d.vr) * delta

		for i in range(_telegraphs.size() - 1, -1, -1):
			var tg: Dictionary = _telegraphs[i]
			tg.left = float(tg.left) - delta * 60.0
			if float(tg.left) <= 0.0 or not is_instance_valid(tg.shade):
				_telegraphs.remove_at(i)

		if _art_back != null:
			_art_back.queue_redraw()
		if _art_front != null:
			_art_front.queue_redraw()

	# -----------------------------------------------------------------
	# 2.5D 建筑体块、暖窗无主狂影、60° 朱红光栅、两撞立钟柜与墙影剥落绘制
	# -----------------------------------------------------------------
	func _bevel_rect(canvas: Node2D, x0: float, y0: float, x1: float, y1: float, bev: float,
			face: Color, side: Color, cap: Color) -> void:
		canvas.draw_rect(Rect2(x0, y0, x1 - x0, y1 - y0), face)
		if bev > 0.0:
			var dy := bev * 0.22
			canvas.draw_colored_polygon(PackedVector2Array([
				Vector2(x1, y0), Vector2(x1 + bev, y0 - dy),
				Vector2(x1 + bev, y1 - dy * 0.4), Vector2(x1, y1),
			]), side)
			canvas.draw_colored_polygon(PackedVector2Array([
				Vector2(x0, y0), Vector2(x1, y0),
				Vector2(x1 + bev, y0 - dy), Vector2(x0 + bev, y0 - dy),
			]), cap)
		canvas.draw_line(Vector2(x0, y0), Vector2(x1, y0), cap.lightened(0.22), 3.0)

	func _draw_banquet_window(c: Node2D, wx: float, wy: float, w: float, h: float, pose: int) -> void:
		var hw := w * 0.5
		c.draw_circle(Vector2(wx, wy - h * 0.5), w * 0.95, Color(1.0, 0.68, 0.28, 0.14))
		c.draw_rect(Rect2(wx - hw, wy - h + hw, w, h - hw), Color(0.86, 0.56, 0.22, 0.90))
		c.draw_circle(Vector2(wx, wy - h + hw), hw, Color(0.92, 0.64, 0.28, 0.92))
		# 窗内定格 5:59 无主狂影（微颤）
		var sway := sin(_time * 2.1 + float(pose) * 1.7) * 3.5
		var sc := Color(0.06, 0.05, 0.08, 0.92)
		if pose % 2 == 0:
			for dx in [-w * 0.18, w * 0.16]:
				var px: float = wx + float(dx) + sway * 0.4
				c.draw_colored_polygon(PackedVector2Array([
					Vector2(px - 14, wy), Vector2(px - 6, wy - h * 0.50),
					Vector2(px + 8, wy - h * 0.50), Vector2(px + 16, wy),
				]), sc)
				c.draw_circle(Vector2(px + 1, wy - h * 0.58), 9.0, sc)
			c.draw_line(Vector2(wx - w * 0.14, wy - h * 0.42), Vector2(wx + w * 0.14, wy - h * 0.44), sc, 4.0)
		else:
			var px := wx + sway * 0.5
			c.draw_colored_polygon(PackedVector2Array([
				Vector2(px - 15, wy), Vector2(px - 7, wy - h * 0.54),
				Vector2(px + 9, wy - h * 0.54), Vector2(px + 15, wy),
			]), sc)
			c.draw_circle(Vector2(px + 1, wy - h * 0.62), 9.5, sc)
			c.draw_line(Vector2(px + 6, wy - h * 0.46), Vector2(px + 26, wy - h * 0.66), sc, 4.0)
		# 铁窗棂
		var fc := Color(0.09, 0.11, 0.16, 0.98)
		c.draw_rect(Rect2(wx - hw, wy - h + hw, w, h - hw), fc, false, 4.0)
		c.draw_line(Vector2(wx, wy - h), Vector2(wx, wy), fc, 3.0)
		c.draw_line(Vector2(wx - hw, wy - h * 0.36), Vector2(wx + hw, wy - h * 0.36), fc, 3.0)

	func _draw_looming_clocktower(c: Node2D, wx: float, base_y: float, sc: float, red_a: float) -> void:
		var tw := 220.0 * sc
		var th := 760.0 * sc
		var top_y := base_y - th
		_bevel_rect(c, wx - tw * 0.5, top_y, wx + tw * 0.5, base_y, 38.0 * sc,
				Color(0.06, 0.075, 0.12, 0.96), Color(0.20, 0.13, 0.18, 0.96), Color(0.32, 0.36, 0.48, 0.95))
		c.draw_colored_polygon(PackedVector2Array([
			Vector2(wx - tw * 0.54, top_y), Vector2(wx, top_y - 280.0 * sc), Vector2(wx + tw * 0.58, top_y),
		]), Color(0.05, 0.06, 0.10, 0.98))
		var dy := top_y + 155.0 * sc
		var dr := 76.0 * sc
		c.draw_circle(Vector2(wx, dy), dr * 2.1, Color(0.78, 0.16, 0.16, red_a * 0.28))
		c.draw_circle(Vector2(wx, dy), dr, Color(0.58, 0.12, 0.14, red_a))
		c.draw_arc(Vector2(wx, dy), dr, 0.0, TAU, 36, Color(0.90, 0.32, 0.28, red_a), 4.0 * sc)
		# 5:59 卡死抽动指针
		var twitch := 0.018 if fmod(_time, 2.4) < 0.12 else 0.0
		var min_ang := -PI * 0.5 - 0.105 + twitch
		c.draw_line(Vector2(wx, dy), Vector2(wx, dy) + Vector2(cos(min_ang), sin(min_ang)) * dr * 0.86, Color(0.08, 0.04, 0.06), 4.5 * sc)
		c.draw_line(Vector2(wx, dy), Vector2(wx + 3.0 * sc, dy + dr * 0.62), Color(0.08, 0.04, 0.06), 5.5 * sc)

	func _draw_stage_back() -> void:
		var c := _art_back
		var idx := current_stage_idx
		var cx := _center_of(idx)
		if use_painted_bg and idx < _painted_tex.size() and _painted_tex[idx] != null:
			var tex: Texture2D = _painted_tex[idx]
			var tile_w := 1600.0
			var tile_h := tile_w * 9.0 / 16.0
			var g_frac: float = float(PAINTED_GROUND_FRAC[idx])
			var y_top := floor_y - tile_h * g_frac
			c.draw_rect(Rect2(cx - 3600.0, y_top - 640.0, 7200.0, 660.0), Color(0.045, 0.06, 0.095, 1.0))
			c.draw_rect(Rect2(cx - 3600.0, y_top + tile_h - 4.0, 7200.0, 560.0), Color(0.04, 0.05, 0.075, 1.0))
			for ti in range(-3, 4):
				var tx := cx - tile_w * 0.5 + float(ti) * tile_w
				var flip_w := -tile_w if (absi(ti) % 2 == 1) else tile_w
				c.draw_texture_rect(tex, Rect2(tx, y_top, flip_w, tile_h), false)
			return
		# 干涸深石底板（遮掉原河道位置，严守禁海铁律）
		if idx != 1:
			c.draw_rect(Rect2(cx - 3200.0, floor_y, 6400.0, 560.0), Color(0.055, 0.065, 0.095, 1.0))
			c.draw_line(Vector2(cx - 3200.0, floor_y), Vector2(cx + 3200.0, floor_y), Color(0.46, 0.54, 0.68, 0.75), 3.0)
		else:
			# 1-2A 真高空屋顶：天沟边缘以下全是翻涌万家深雾海 + 针尖远灯！
			c.draw_rect(Rect2(cx - 3200.0, floor_y, 6400.0, 620.0), Color(0.07, 0.095, 0.15, 1.0))
			c.draw_rect(Rect2(cx - 2100.0, floor_y, 4200.0, 54.0), Color(0.11, 0.13, 0.19, 1.0))
			for i in 18:
				var lx := cx - 2200.0 + float(i) * 260.0 + sin(_time * 0.5 + float(i)) * 12.0
				var ly := floor_y + 135.0 + float((i * 47) % 160)
				c.draw_circle(Vector2(lx, ly), 22.0, Color(1.0, 0.74, 0.40, 0.10))
				c.draw_circle(Vector2(lx, ly), 4.0, Color(1.0, 0.82, 0.52, 0.55))

		match idx:
			0: # 1-1 无人夜宴街
				_draw_looming_clocktower(c, cx + 1650.0, floor_y, 0.55, 0.58)
				_bevel_rect(c, cx - 2150.0, -40.0, cx - 820.0, floor_y, 44.0,
						Color(0.09, 0.105, 0.155), Color(0.16, 0.19, 0.27), Color(0.36, 0.42, 0.54))
				_bevel_rect(c, cx + 380.0, -90.0, cx + 1780.0, floor_y, 48.0,
						Color(0.095, 0.11, 0.165), Color(0.17, 0.20, 0.29), Color(0.38, 0.44, 0.56))
				var wxs := [-1820.0, -1480.0, -1140.0, 660.0, 1060.0, 1460.0]
				for i in wxs.size():
					_draw_banquet_window(c, cx + float(wxs[i]), 265.0, 128.0, 210.0, i)
				# 无马黑漆空轿（x=-1860..-1680）+ 地面四匹无主奔马长影！
				_bevel_rect(c, cx - 1860.0, 436.0, cx - 1680.0, floor_y, 26.0,
						Color(0.05, 0.06, 0.09), Color(0.15, 0.18, 0.25), Color(0.50, 0.58, 0.72))
				c.draw_arc(Vector2(cx - 1825.0, 552.0), 26.0, 0.0, TAU, 20, Color(0.34, 0.40, 0.52), 4.0)
				c.draw_arc(Vector2(cx - 1720.0, 548.0), 30.0, 0.0, TAU, 20, Color(0.34, 0.40, 0.52), 4.0)
				for hi in 4:
					var hx := cx - 1630.0 + float(hi) * 108.0 + sin(_time * 3.0 + float(hi)) * 4.0
					c.draw_colored_polygon(PackedVector2Array([
						Vector2(hx, floor_y + 16), Vector2(hx + 76, floor_y + 6),
						Vector2(hx + 104, floor_y + 24), Vector2(hx + 82, floor_y + 44), Vector2(hx + 16, floor_y + 40),
					]), Color(0.015, 0.02, 0.035, 0.88))
				# 八角 5:59 煤气钟亭（x=-680..-520）
				_bevel_rect(c, cx - 680.0, 300.0, cx - 520.0, floor_y, 28.0,
						Color(0.08, 0.095, 0.14), Color(0.19, 0.22, 0.31), Color(0.56, 0.64, 0.78))
				c.draw_circle(Vector2(cx - 600.0, 365.0), 32.0, Color(0.92, 0.72, 0.40, 0.92))
				c.draw_line(Vector2(cx - 600.0, 365.0), Vector2(cx - 603.0, 340.0), Color(0.08, 0.06, 0.08), 3.0)
				c.draw_line(Vector2(cx - 600.0, 365.0), Vector2(cx - 598.0, 384.0), Color(0.08, 0.06, 0.08), 3.5)

			1: # 1-2A 飞鸦玻璃花房顶
				_draw_looming_clocktower(c, cx + 1620.0, floor_y + 120.0, 0.92, 0.76)
				for span in [Vector2(-1320.0, -300.0), Vector2(300.0, 1320.0)]:
					var gx0: float = cx + span.x
					var gx1: float = cx + span.y
					var gcx := (gx0 + gx1) * 0.5
					c.draw_circle(Vector2(gcx, 320.0), 380.0, Color(0.95, 0.64, 0.28, 0.16))
					c.draw_rect(Rect2(gx0 + 20.0, 20.0, gx1 - gx0 - 40.0, 560.0), Color(0.36, 0.28, 0.20, 0.58))
					# 内部枯蕨剪影 + 铸铁竖肋
					c.draw_colored_polygon(PackedVector2Array([
						Vector2(gcx - 140.0, 580.0), Vector2(gcx - 65.0, 270.0), Vector2(gcx - 10.0, 580.0),
					]), Color(0.06, 0.07, 0.10, 0.78))
					c.draw_colored_polygon(PackedVector2Array([
						Vector2(gcx + 20.0, 580.0), Vector2(gcx + 95.0, 220.0), Vector2(gcx + 165.0, 580.0),
					]), Color(0.06, 0.07, 0.10, 0.78))
					var rx := gx0 + 30.0
					while rx < gx1 - 20.0:
						c.draw_line(Vector2(rx, 20.0), Vector2(rx, 580.0), Color(0.08, 0.10, 0.15, 0.95), 5.0)
						rx += 96.0

			2: # 1-2B 百表当铺夹巷
				c.draw_rect(Rect2(cx - 2450.0, -480.0, 2950.0, 1060.0), Color(0.055, 0.068, 0.105, 0.96))
				c.draw_rect(Rect2(cx + 760.0, -480.0, 1750.0, 1060.0), Color(0.06, 0.072, 0.11, 0.96))
				# 一线天窄缝（x=+500..+760）露出 5:59 钟楼暗朱红表盘边角
				_draw_looming_clocktower(c, cx + 635.0, floor_y, 0.90, 0.82)
				# 地标：百表当铺暖金剖面八角凸窗（挂满 5:59 怀表）
				var px0 := cx - 880.0
				var px1 := cx - 420.0
				c.draw_circle(Vector2((px0 + px1) * 0.5, 430.0), 260.0, Color(1.0, 0.72, 0.28, 0.18))
				_bevel_rect(c, px0, 325.0, px1, 566.0, 28.0,
						Color(0.76, 0.50, 0.20, 0.90), Color(0.36, 0.25, 0.14, 0.95), Color(0.52, 0.58, 0.72))
				for ry in [372.0, 434.0, 496.0]:
					var wx := px0 + 36.0
					while wx < px1 - 28.0:
						c.draw_line(Vector2(wx, 330.0), Vector2(wx, float(ry) - 12.0), Color(0.18, 0.12, 0.08), 1.5)
						c.draw_circle(Vector2(wx, float(ry)), 12.0, Color(0.96, 0.78, 0.42))
						c.draw_arc(Vector2(wx, float(ry)), 12.0, 0.0, TAU, 16, Color(0.22, 0.14, 0.08), 2.0)
						c.draw_line(Vector2(wx, float(ry)), Vector2(wx, float(ry) - 9.0), Color(0.12, 0.08, 0.05), 1.8)
						wx += 46.0
				# 3 道带 15° 厚度的飞扶壁过街石拱梁与地面护角石墩
				for ax in [-1200.0, 0.0, 1200.0]:
					_bevel_rect(c, cx + float(ax) - 75.0, -240.0, cx + float(ax) + 75.0, 165.0, 42.0,
							Color(0.09, 0.11, 0.165), Color(0.20, 0.24, 0.33), Color(0.48, 0.55, 0.68))

			3: # 1-3A 逆影铸铁飞廊
				_draw_looming_clocktower(c, cx + 1720.0, floor_y + 80.0, 1.38, 0.90)
				# 60° 斜向暗朱红 × 冷银「琴弦光栅」斜切桥下 560px 空战雾区！
				var bx := cx - 2100.0
				while bx < cx + 2100.0:
					if absf(bx - (cx - 600.0)) > 95.0 and absf(bx - (cx + 600.0)) > 95.0:
						var col := Color(0.78, 0.18, 0.18, 0.15) if bx > cx - 100.0 else Color(0.58, 0.68, 0.88, 0.11)
						c.draw_colored_polygon(PackedVector2Array([
							Vector2(bx, 28.0), Vector2(bx + 54.0, 28.0),
							Vector2(bx - 270.0, floor_y), Vector2(bx - 324.0, floor_y),
						]), col)
					bx += 126.0
				# 三根巨型石桥墩 + 逆重力向上爬升的漆黑影带！
				for px_off in [-1400.0, 0.0, 1400.0]:
					var px := cx + float(px_off)
					_bevel_rect(c, px - 72.0, 26.0, px + 72.0, floor_y, 34.0,
							Color(0.08, 0.095, 0.145), Color(0.24, 0.14, 0.18), Color(0.46, 0.52, 0.66))
					for si in [-36.0, 0.0, 36.0]:
						var sx := px + float(si)
						var climb := fmod(_time * 120.0 + absf(float(si)) * 3.0, 540.0)
						c.draw_rect(Rect2(sx - 6.0, 34.0, 12.0, floor_y - 34.0), Color(0.02, 0.02, 0.04, 0.88))
						c.draw_circle(Vector2(sx, floor_y - climb), 9.0, Color(0.01, 0.01, 0.02, 0.96))

			4: # 1-3B 司辰铸钟残廊
				_draw_looming_clocktower(c, cx - 1820.0, floor_y + 40.0, 1.15, 0.82)
				# 右侧 3/4 室内碎玻璃铁肋铸钟工坊背景墙与停摆大齿轮剪影
				c.draw_rect(Rect2(cx - 1000.0, -210.0, 3360.0, 790.0), Color(0.06, 0.07, 0.105, 0.97))
				for g in [Vector3(-420.0, 190.0, 210.0), Vector3(380.0, 140.0, 240.0), Vector3(1180.0, 210.0, 195.0)]:
					var gp := Vector2(cx + g.x, g.y)
					c.draw_arc(gp, g.z, 0.0, TAU, 40, Color(0.11, 0.13, 0.19), 18.0)
					c.draw_arc(gp, g.z * 0.48, 0.0, TAU, 28, Color(0.10, 0.12, 0.17), 10.0)
				# 永久重墙 1：半陷石地的直径 4 米青铜擒纵巨轮（x=-1270）
				c.draw_arc(Vector2(cx - 1270.0, floor_y + 10.0), 170.0, PI, TAU, 28, Color(0.58, 0.48, 0.30), 22.0)
				c.draw_circle(Vector2(cx - 1270.0, floor_y + 10.0), 152.0, Color(0.22, 0.18, 0.13))
				# 永久重墙 3：斜砸进地面的两吨裂口试音青铜巨钟（x=+1300）
				c.draw_colored_polygon(PackedVector2Array([
					Vector2(cx + 1205.0, floor_y), Vector2(cx + 1245.0, 400.0),
					Vector2(cx + 1355.0, 412.0), Vector2(cx + 1395.0, floor_y),
				]), Color(0.20, 0.19, 0.18))
				c.draw_line(Vector2(cx + 1302.0, 408.0), Vector2(cx + 1285.0, 500.0), Color(0.04, 0.04, 0.06), 6.0)

			5: # 1-4 巨钟背影盘旋阶
				c.draw_rect(Rect2(cx - 2500.0, -680.0, 5000.0, 1400.0), Color(0.05, 0.035, 0.06, 0.98))
				var dial_c := Vector2(cx + 120.0, 140.0)
				var dr := 680.0
				c.draw_circle(dial_c, dr * 1.12, Color(0.80, 0.18, 0.18, 0.24))
				c.draw_circle(dial_c, dr, Color(0.48, 0.11, 0.14, 0.88))
				c.draw_circle(dial_c, dr * 0.72, Color(0.60, 0.16, 0.18, 0.86))
				c.draw_arc(dial_c, dr, 0.0, TAU, 64, Color(0.12, 0.06, 0.09), 18.0)
				for i in 12:
					var a := float(i) * TAU / 12.0
					c.draw_line(dial_c, dial_c + Vector2(cos(a), sin(a)) * dr, Color(0.10, 0.05, 0.08), 8.0)
				var twitch := 0.015 if fmod(_time, 2.5) < 0.14 else 0.0
				var mang := -PI * 0.5 + 0.105 - twitch  # 从表盘背面看：5:59 分针偏右 6°！
				c.draw_line(dial_c, dial_c + Vector2(cos(mang), sin(mang)) * (dr - 28.0), Color(0.04, 0.03, 0.05), 22.0)
				c.draw_line(dial_c, dial_c + Vector2(-6.0, dr * 0.62), Color(0.04, 0.03, 0.05), 26.0)

	func _draw_stage_front() -> void:
		var c := _art_front
		# 1-3B 可撞碎 2 次的黄铜玻璃天文立钟柜 + 飞散齿轮/玻璃碴
		if _cabinets.has(current_stage_idx):
			for cab in _cabinets[current_stage_idx]:
				var hp := int(cab.hp)
				var wx := float(cab.wx)
				if hp <= 0:
					# 碎裂底座残骸（不挡路）
					c.draw_rect(Rect2(wx - 48.0, floor_y - 16.0, 96.0, 16.0), Color(0.22, 0.15, 0.10))
					continue
				var tilt := 0.0 if hp == 2 else 9.0
				_bevel_rect(c, wx - 50.0 + tilt, 432.0, wx + 50.0 + tilt, floor_y, 20.0,
						Color(0.22, 0.15, 0.11), Color(0.40, 0.29, 0.19), Color(0.78, 0.66, 0.44))
				var dial_col := Color(0.94, 0.76, 0.42) if hp == 2 else Color(0.55, 0.42, 0.24)
				c.draw_circle(Vector2(wx + tilt, 472.0), 24.0, dial_col)
				c.draw_line(Vector2(wx + tilt, 472.0), Vector2(wx + tilt, 452.0), Color(0.10, 0.07, 0.05), 2.5)
				if hp == 1:
					# 半碎裂纹与外露铜摆
					c.draw_line(Vector2(wx - 32.0 + tilt, 444.0), Vector2(wx + 28.0 + tilt, 540.0), Color(0.95, 0.92, 0.80), 2.5)
					c.draw_arc(Vector2(wx + 12.0 + tilt, 524.0), 14.0, 0.0, TAU, 14, Color(0.92, 0.74, 0.36), 3.0)

		for d in _debris:
			var p: Vector2 = d.p
			var r: float = d.r
			if bool(d.gear):
				c.draw_arc(p, r, 0.0, TAU, 12, Color(0.95, 0.78, 0.40, clampf(float(d.life) * 1.5, 0.0, 1.0)), 3.0)
			else:
				c.draw_circle(p, r * 0.45, Color(0.84, 0.90, 0.98, clampf(float(d.life) * 1.4, 0.0, 1.0)))

		# 1.0s 刷怪前「无主墙影剧烈拉长剥落 + 双白眼芒」预警演出
		for tg in _telegraphs:
			var k := 1.0 - clampf(float(tg.left) / float(tg.total), 0.0, 1.0)
			var ft: Vector2 = tg.feet
			var h := lerpf(24.0, 152.0, ease(k, 0.45))
			var wob := sin(_time * 26.0 + ft.x) * (1.0 - k) * 10.0
			c.draw_colored_polygon(PackedVector2Array([
				Vector2(ft.x - 38.0, ft.y),
				Vector2(ft.x - 14.0 + wob, ft.y - h),
				Vector2(ft.x + 14.0 + wob, ft.y - h * 0.94),
				Vector2(ft.x + 38.0, ft.y),
			]), Color(0.02, 0.02, 0.04, 0.92))
			if k > 0.25:
				var ey := ft.y - h * 0.82
				c.draw_circle(Vector2(ft.x - 5.0 + wob, ey), 3.2, Color(0.92, 0.96, 1.0, k))
				c.draw_circle(Vector2(ft.x + 6.0 + wob, ey), 3.2, Color(0.92, 0.96, 1.0, k))
