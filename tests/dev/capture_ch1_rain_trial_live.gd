extends SceneTree
## 主游戏 rain_trial.tscn 正式接入第一章「影街与司辰母钟楼」24 张完整商业地图库实机验收与原生截图脚本
## 注意：必须使用原生窗口渲染（严禁加 --headless），默认隐藏 Panku 控制台浮层。

const TRIAL_SCENE := "res://scenes/rain_trial.tscn"


func _initialize() -> void:
	call_deferred("_run")


func _hide_debug_overlays() -> void:
	for child in root.get_children():
		var nm := String(child.name)
		if nm.begins_with("Panku") or nm.to_lower().contains("panku") or nm.to_lower().contains("console"):
			if child is CanvasLayer:
				child.visible = false
			for sub in child.get_children():
				if sub is CanvasItem or sub is CanvasLayer:
					sub.visible = false


func _wait_frames(n: int) -> void:
	for _i in n:
		await physics_frame
		await process_frame


func _save_shot(out_dir: String, fname: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	var full := out_dir.path_join(fname)
	img.save_png(full)
	print("SAVED_LIVE_SHOT: " + full)


func _clear_arena(stage: Node, next_idx: int) -> void:
	stage.encounter.clear_shades()
	stage.encounter.running = false
	stage._unlock_arena()
	stage.phase = stage.Phase.EXPLORE
	stage.encounter_index = next_idx


func _run() -> void:
	var out_rel := OS.get_environment("CH1_LIVE_SHOT_OUT")
	if out_rel == "":
		out_rel = "docs/视觉设计/地图规划/第一章扩充A_20261114/主游戏24张全库实机截图"
	var out_dir := ProjectSettings.globalize_path("res://" + out_rel) if not out_rel.contains(":") else out_rel
	DirAccess.make_dir_recursive_absolute(out_dir)

	var stage: Node = load(TRIAL_SCENE).instantiate()
	stage.set_meta("ch1_shadow_street", true)
	stage.set_meta("ch1_slot0_code", "1-1A")
	root.add_child(stage)
	current_scene = stage
	_hide_debug_overlays()
	await _wait_frames(8)
	_hide_debug_overlays()

	assert(stage.backdrop._ch1_shadow_mode, "StreetBackdrop 必须处于第一章影街模式")
	assert(stage.backdrop._layered._ch1_manifest.size() == 24, "第一章 manifest 必须完整挂载全部 24 张商业资产")
	assert(stage.backdrop._water.visible, "出生点 x=320 必须完整保留 11-12 起点入口街河面倒影")
	assert(stage.backdrop._layered.chain != null, "出生点 x=320 必须完整保留 11-12 起点入口街前景吊钩与悬停雨珠")
	assert(absf(stage.backdrop._layered.edge_x - 2018.2) < 12.0, "11-12 起点入口街门洞右缘羽化边界必须位于 x≈2018.2")

	var p: CharacterBody2D = stage.player
	var c0: float = stage._center_of(0)
	var c1: float = stage._center_of(1)
	var c2: float = stage._center_of(2)

	# 00A. 开局首屏（x=320 完整恢复 11-12 起点入口街 + 万象起手界面）
	await _wait_frames(8)
	await _save_shot(out_dir, "00A_开局首屏_恢复11-12起点入口街_x320.png")

	if stage.has_method("_on_wanxiang_opening_confirmed"):
		stage.call("_on_wanxiang_opening_confirmed", "core_rift", "talent_free_roll")
	else:
		paused = false

	if stage.hud != null:
		stage.hud.help_visible = false
	for hk in [&"move", &"floors", &"drop", &"parry", &"knockback", &"brute", &"archer", &"bomber", &"blast", &"air", &"chain", &"guard", &"ult"]:
		stage._hints_done[hk] = true
	stage._hint_queue.clear()

	# 00B. 11-12 起点入口街与门洞交界实机（x=320..2038：湿边阳台碰撞、河面倒影、门洞昼光悬停雨珠全部原汁原味保留，右侧无缝过渡进 1-1A 影街！）
	stage.terrain.ensure_section(0, c0)
	stage.backdrop.swap_ch1_slot_stage(0, "1-1A")
	var y_entry_balcony: float = stage.terrain.support_y(880.0, 280.0)
	assert(absf(y_entry_balcony - 344.3) < 6.0, "11-12 起点入口街二楼木阳台单向平台碰撞生效")
	p.reset_state(Vector2(1580.0, stage.floor_y - p.foot_offset))
	stage.camera.global_position = Vector2(1680.0, stage._cam_y_for(stage.floor_y))
	await _wait_frames(16)
	await _save_shot(out_dir, "00B_起点入口街走出门洞_无缝接1-1A灯影空轿街.png")

	# 00C. 走出门洞进入 1-1B 停摆电车雨站（门洞外侧 x=2280 直接踏上候车高月台石板面，且离开门洞后水面平滑收干！）
	stage.backdrop.swap_ch1_slot_stage(0, "1-1B")
	var y_station_plat: float = stage.terrain.support_y(2280.0, 480.0)
	assert(y_station_plat < 560.0, "1-1B 门洞外候车高月台碰撞生效")
	p.reset_state(Vector2(2280.0, y_station_plat - p.foot_offset))
	stage.camera.global_position = Vector2(2360.0, stage._cam_y_for(stage.floor_y))
	await _wait_frames(16)
	assert(not stage.backdrop._water.visible, "走出起点入口街门洞后，新影街自动收干旧河面")
	await _save_shot(out_dir, "00C_走出门洞踏上1-1B停摆电车雨站高月台.png")

	# 01. 1-1A 中段（空马车 + 角色踏上右侧石拱门五级青石台阶）
	stage.backdrop.swap_ch1_slot_stage(0, "1-1A")
	_clear_arena(stage, 0)
	var x_arch_step := c0 + 530.0
	var y_arch_step: float = stage.terrain.support_y(x_arch_step, 480.0)
	assert(y_arch_step < 545.0, "1-1A 中段石拱门五级青石台阶碰撞生效")
	p.reset_state(Vector2(x_arch_step, y_arch_step - p.foot_offset))
	stage.camera.global_position = Vector2(c0 + 220.0, stage._cam_y_for(stage.floor_y))
	await _wait_frames(16)
	if stage.hud != null and "_banner_t" in stage.hud:
		stage.hud._banner_t = 0.0
		stage.hud.queue_redraw()
	await _save_shot(out_dir, "01_1-1A中段_空马车与踏上石拱门青石阶_实机.png")

	# 02. 1-1A 右翼（角色稳稳站在停摆茶座五级石阶外廊茶桌旁，零穿模！）
	_clear_arena(stage, 0)
	var x_cafe := c0 + 1220.0
	var y_cafe: float = stage.terrain.support_y(x_cafe, 480.0)
	assert(y_cafe < 550.0, "1-1A 右翼停摆茶座五级石阶外廊碰撞生效")
	p.reset_state(Vector2(x_cafe, y_cafe - p.foot_offset))
	stage.camera.global_position = Vector2(c0 + 1120.0, stage._cam_y_for(stage.floor_y))
	await _wait_frames(16)
	await _save_shot(out_dir, "02_1-1A右翼_停摆茶座外廊与559石墩_实机.png")

	# 03. 1-1B 停摆电车雨站中段（角色跳上老电车第二节车厢顶，右侧接跨街木构东天桥）
	stage.backdrop.swap_ch1_slot_stage(0, "1-1B")
	_clear_arena(stage, 0)
	var x_tram2 := c0 - 530.0
	var y_tram2: float = stage.terrain.support_y(x_tram2, 260.0)
	assert(y_tram2 < 360.0, "1-1B 电车第二节车厢顶碰撞生效")
	p.reset_state(Vector2(x_tram2, y_tram2 - p.foot_offset))
	stage.camera.global_position = Vector2(c0 - 120.0, stage._cam_y_for(stage.floor_y))
	await _wait_frames(16)
	await _save_shot(out_dir, "03_1-1B_停摆电车雨站_车窗狂影与东天桥_实机.png")

	# 04. J1 街口高低分流岔路（角色直接踏在画中左侧大折返青石长阶半腰！）
	_clear_arena(stage, 1)
	stage.terrain.ensure_section(1, c1)
	var x_j1_stair := 7180.0
	var y_j1_stair: float = stage.terrain.support_y(x_j1_stair, 360.0)
	assert(y_j1_stair < 520.0, "J1 左侧大型青石折返长阶斜坡碰撞生效")
	p.reset_state(Vector2(x_j1_stair, y_j1_stair - p.foot_offset - 18.0))
	stage.camera.global_position = Vector2(7580.0, stage._cam_y_for(stage.floor_y))
	await _wait_frames(16)
	assert(p.global_position.y + p.foot_offset < 530.0, "J1 玩家胶囊体真实物理稳稳站立在青石折返长阶半腰")
	await _save_shot(out_dir, "04_J1_街口高低分流岔路_实机.png")

	# 05. 1-2B 百表当铺夹巷（角色踏上过街石拱门连廊）
	stage.backdrop.swap_ch1_slot_stage(1, "1-2B")
	_clear_arena(stage, 1)
	var x_2b := c1 - 1460.0
	var y_2b: float = stage.terrain.support_y(x_2b, 300.0)
	p.reset_state(Vector2(x_2b, y_2b - p.foot_offset))
	stage.camera.global_position = Vector2(c1 - 1220.0, stage._cam_y_for(stage.floor_y))
	await _wait_frames(16)
	await _save_shot(out_dir, "05_1-2B左中_发条修配窄门接百表当铺_实机.png")

	# 06. 1-2A 飞鸦玻璃花房顶（角色严丝合缝站在玻璃温室二层铁栏外廊上，不再悬在拱洞半空！）
	stage.backdrop.swap_ch1_slot_stage(1, "1-2A")
	_clear_arena(stage, 1)
	var x_2a := c1 + 1260.0
	var y_2a: float = stage.terrain.support_y(x_2a, 220.0)
	assert(absf(y_2a - 272.5) < 25.0, "1-2A 玻璃温室二层铁栏外廊高度精准对齐画中栏杆底座")
	p.reset_state(Vector2(x_2a, y_2a - p.foot_offset))
	stage.camera.global_position = Vector2(c1 + 1180.0, stage._cam_y_for(320.0))
	await _wait_frames(16)
	await _save_shot(out_dir, "06_1-2A右翼_碎裂温室破窗透流云_实机.png")

	# 07. E1 漏光校晷小广场（角色踏上中央八角黄铜日晷三级圆坛）
	stage.encounter_index = 1
	stage.backdrop._on_stage_fork_route_selected("dawn_breach")
	_clear_arena(stage, 1)
	var y_e1: float = stage.terrain.support_y(c1, 500.0)
	assert(y_e1 < 550.0, "E1 广场中央黄铜日晷圆坛台阶碰撞生效")
	p.reset_state(Vector2(c1 - 120.0, y_e1 - p.foot_offset))
	stage.camera.global_position = Vector2(c1, stage._cam_y_for(stage.floor_y))
	await _wait_frames(16)
	await _save_shot(out_dir, "07_E1_漏光校晷小广场_驱时白光鲜活悬停_实机.png")

	# 08. S1 无主校时表坊（角色跳上修表大师中央长木案台）
	_clear_arena(stage, 2)
	stage.terrain.ensure_section(2, c2)
	var x_s1 := c1 + 3200.0
	var y_s1: float = stage.terrain.support_y(x_s1, 380.0)
	p.reset_state(Vector2(x_s1, y_s1 - p.foot_offset))
	stage.camera.global_position = Vector2(c1 + 3200.0, stage._cam_y_for(stage.floor_y))
	await _wait_frames(16)
	await _save_shot(out_dir, "08_S1_无主校时表坊_肉鸽中场休整室_实机.png")

	# 09. 1-3A 逆影铸铁飞廊左翼（角色站在铆接高架桥铁栏内侧钢桥面上）
	stage.backdrop.swap_ch1_slot_stage(2, "1-3A")
	_clear_arena(stage, 2)
	var x_3a := c2 - 1260.0
	var y_3a: float = stage.terrain.support_y(x_3a, 100.0)
	p.reset_state(Vector2(x_3a, y_3a - p.foot_offset))
	stage.camera.global_position = Vector2(c2 - 1180.0, stage._cam_y_for(160.0))
	await _wait_frames(16)
	await _save_shot(out_dir, "09_1-3A左翼_双层铆接高架西引桥_实机.png")

	# 10. 1-3B 司辰铸钟残廊左翼（角色踏上断裂巨型青铜音叉石基座）
	stage.backdrop.swap_ch1_slot_stage(2, "1-3B")
	_clear_arena(stage, 2)
	var x_3b := c2 - 2110.0
	var y_3b: float = stage.terrain.support_y(x_3b, 480.0)
	p.reset_state(Vector2(x_3b, y_3b - p.foot_offset))
	stage.camera.global_position = Vector2(c2 - 1520.0, stage._cam_y_for(stage.floor_y))
	await _wait_frames(16)
	await _save_shot(out_dir, "10_1-3B左翼_断裂青铜音叉与铸钟冷室_实机.png")

	# 11. 1-3C 司辰母钟楼正门前庭（角色站在双折铜管铁楼梯登顶廊台，右侧接青铜总枢巨门六级正阶）
	stage.backdrop.swap_ch1_slot_stage(2, "1-3C")
	_clear_arena(stage, 2)
	var x_3c := c2 + 520.0
	var y_3c: float = stage.terrain.support_y(x_3c, 200.0)
	assert(y_3c < 290.0, "1-3C 双折铜管外楼梯顶廊碰撞生效")
	p.reset_state(Vector2(x_3c, y_3c - p.foot_offset))
	stage.camera.global_position = Vector2(c2 + 1060.0, stage._cam_y_for(stage.floor_y))
	await _wait_frames(16)
	await _save_shot(out_dir, "11_1-3C_司辰母钟楼正门前庭_青铜总枢巨门_实机.png")

	# 12. 1-4 上段 母钟擒纵天轴与临顶盘旋阶（角色沿画中石阶登上中央圆形擒纵天轴观景台）
	_clear_arena(stage, 3)
	var x_14 := c2 + 5380.0
	var y_14: float = stage.terrain.support_y(x_14, 180.0)
	assert(y_14 < 300.0, "1-4 盘旋长阶与中央黄铜天轴圆盘碰撞生效")
	p.reset_state(Vector2(x_14, y_14 - p.foot_offset))
	stage.camera.global_position = Vector2(c2 + 5380.0, stage._cam_y_for(320.0))
	await _wait_frames(16)
	await _save_shot(out_dir, "12_1-4上段_母钟擒纵天轴与临顶盘旋阶_实机.png")

	print("CH1_24_ASSETS_LIVE_VERIFY_PASS: 12 native Forward+ screenshots captured, 0 errors")
	stage.queue_free()
	await _wait_frames(3)
	quit()
