extends SceneTree
## 雨街试玩暂停菜单（scripts/ui/pause_menu.gd）：Esc 开关、方向键选择、子页返回、设置生效、重新开始、结算时不能打开。
const TRIAL := "res://scenes/rain_trial.tscn"
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		print("FAIL: ", label)


func key(code: int) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = pressed
		Input.parse_input_event(e)
		await process_frame
	await process_frame


func run() -> void:
	var stage = load(TRIAL).instantiate()
	root.add_child(stage)
	current_scene = stage
	for i in 10:
		await process_frame
	var menu = stage.get_node_or_null("PauseMenu")
	check(menu != null, "雨街试玩挂了暂停菜单")
	if menu == null:
		_finish()
		return
	check(not menu.opened and not paused, "开场不暂停")
	await key(KEY_ESCAPE)
	check(menu.opened and paused and menu.visible, "Esc 打开暂停并冻结世界")
	check(menu.index == 0, "默认选中“继续”")
	await key(KEY_DOWN)
	await key(KEY_DOWN)
	check(menu.index == 2, "方向键下移两项到“操作说明”")
	await key(KEY_ENTER)
	check(menu.page == menu.Page.HELP, "回车进入操作说明")
	await key(KEY_ESCAPE)
	check(menu.page == menu.Page.MAIN and menu.opened and menu.index == 2, "Esc 从操作说明回到主菜单并停在原项")
	await key(KEY_DOWN)
	await key(KEY_ENTER)
	check(menu.page == menu.Page.SETTINGS, "进入设置")
	await key(KEY_DOWN)
	await key(KEY_DOWN)
	var help_before: bool = stage.hud.help_visible
	await key(KEY_RIGHT)
	check(stage.hud.help_visible != help_before, "设置里切换底部操作提示")
	await key(KEY_DOWN)
	var dmg_before: bool = stage.fx.damage_numbers_enabled
	await key(KEY_ENTER)
	check(stage.fx.damage_numbers_enabled != dmg_before, "设置里切换伤害数字")
	var factory = menu.Factory
	await key(KEY_DOWN)
	await key(KEY_RIGHT)
	check(factory.scheme() == factory.SCHEME_MOUSE and menu._help_rows()[3][0] == "左键", "设置里切到键鼠，操作说明跟着换")
	await key(KEY_RIGHT)
	check(factory.scheme() == factory.SCHEME_KEYBOARD and menu._help_rows()[3][0] == "J", "再按一次切回键盘")
	await key(KEY_ESCAPE)
	await key(KEY_ESCAPE)
	check(not menu.opened and not paused and stage.hud.visible, "再按 Esc 关闭，世界和 HUD 马上恢复")
	var t0 := Time.get_ticks_msec()
	while menu.visible and Time.get_ticks_msec() - t0 < 1000:
		await process_frame
	check(not menu.visible, "关闭淡出后菜单隐藏")
	check(menu._drops.size() == menu.RAIN_DROPS, "暂停时菜单自己的雨层已生成")
	# 重新开始
	await key(KEY_ESCAPE)
	await key(KEY_DOWN)
	await key(KEY_ENTER)
	for i in 8:
		await process_frame
	check(not paused and current_scene != stage, "“重新开始”解除暂停并重新进入试玩")
	stage = current_scene
	for i in 6:
		await process_frame
	# 结算时 Esc 不打开
	if stage != null and stage.get("pause_menu") != null:
		stage.trial_completed = true
		paused = true
		await key(KEY_ESCAPE)
		check(not stage.pause_menu.opened, "结算 / 已暂停时 Esc 不会再开暂停菜单")
		paused = false
		# 回到标题（首页线 11-05）
		stage.trial_completed = false
		await key(KEY_ESCAPE)
		for i in 4:
			await key(KEY_DOWN)
		check(stage.pause_menu.index == 4 and stage.pause_menu.MAIN_ITEMS[4] == "回到标题", "主菜单第 5 项是“回到标题”")
		await key(KEY_ENTER)
		for i in 10:
			await process_frame
		check(not paused and Engine.time_scale == 1.0 and current_scene != null
				and current_scene.scene_file_path == "res://scenes/yg_title_zhanzhong.tscn", "“回到标题”解除暂停并进入首页")
	_finish()


func _finish() -> void:
	if failures.is_empty():
		print("PAUSE_MENU_TESTS: %d checks / 0 failures" % checks)
		quit(0)
	else:
		print("PAUSE_MENU_TESTS: %d checks / %d failures" % [checks, failures.size()])
		quit(1)
