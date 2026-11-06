extends SceneTree
## [YG-MARK] 11-06 首页「断晓 · 断光」手柄测试（headless）。删除方法见 docs/YG-首页断光-删除清单.md。
## 只用手柄事件（Input.parse_input_event 发 InputEventJoypadButton / InputEventJoypadMotion）走一遍：
## 跳过开场 → 菜单上下 → 按住连发（十字键 / 摇杆）→ 进设置 → 滑条连发、开关不连发 → 左右改操作方式 → B 返回
## → Y 静音 / X 随手一刀 / Back 重播 → 键鼠和手柄混用时提示来回切 → 退出确认不连发 → 选“开始”进 rain_trial。
## 跑之前备份首页会写的 user:// 设置文件，跑完原样放回，不改玩家自己的设置。
## 用法：engine/Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/test_title_pad.gd

const TITLE := "res://scenes/yg_title_duanguang.tscn"
const GAME := "res://scenes/rain_trial.tscn"
const CFGS := ["user://yg_title.cfg", "user://settings.cfg", "user://graphics.cfg", "user://controls.cfg"]

var checks := 0
var failures: Array[String] = []
var backups := {}
var app: Control


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		print("FAIL: ", label)


# ---------------------------------------------------------------- 输入
func btn(index: int, pressed: bool) -> void:
	var e := InputEventJoypadButton.new()
	e.device = 0
	e.button_index = index
	e.pressed = pressed
	e.pressure = 1.0 if pressed else 0.0
	Input.parse_input_event(e)
	await process_frame


func tap(index: int) -> void:
	await btn(index, true)
	await btn(index, false)
	await process_frame


func axis(a: int, v: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.device = 0
	e.axis = a
	e.axis_value = v
	Input.parse_input_event(e)
	await process_frame


func key(code: int) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = pressed
		Input.parse_input_event(e)
		await process_frame


func wait_sec(s: float) -> void:
	var end := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < end:
		await process_frame


## 等到条件成立，最多 s 秒
func wait_until(cond: Callable, s: float) -> bool:
	var end := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await process_frame
	return cond.call()


## 按住期间每帧数 getter 的值变了几次
func count_changes(getter: Callable, s: float) -> int:
	var n := 0
	var last = getter.call()
	var end := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < end:
		await process_frame
		var v = getter.call()
		if v != last:
			n += 1
			last = v
	return n


func sel() -> int:
	return int(app.ui.sel)


func rsel() -> int:
	return int(app.ui.rsel)


func goto_menu_item(act: String) -> void:
	for i in 5:
		if str(app.ui.MENU[sel()]["act"]) == act:
			return
		await tap(JOY_BUTTON_DPAD_DOWN)


func goto_row(k: String) -> void:
	for i in 9:
		if str(app.ui.ROWS[rsel()]["k"]) == k:
			return
		await tap(JOY_BUTTON_DPAD_DOWN)


# ---------------------------------------------------------------- 设置文件备份
func backup() -> void:
	for p in CFGS:
		backups[p] = FileAccess.get_file_as_bytes(p) if FileAccess.file_exists(p) else null


func restore() -> void:
	for p in CFGS:
		var b = backups.get(p)
		if b == null:
			if FileAccess.file_exists(p):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
		else:
			var f := FileAccess.open(p, FileAccess.WRITE)
			if f:
				f.store_buffer(b)
				f.close()


# ---------------------------------------------------------------- 流程
func run() -> void:
	backup()
	app = load(TITLE).instantiate()
	root.add_child(app)
	current_scene = app
	for i in 3:
		await process_frame
	check(str(app.sim.state) == "intro", "开机先放开场")

	# 1. 跳过开场
	var it0: float = app.sim.it
	await tap(JOY_BUTTON_A)
	# skip_intro 按设计先快进到刀落前 0.25 秒（保留斩那一下），所以看时间轴有没有跳，而不是看 state
	check(float(app.sim.it) >= float(app.sim.TL["slash_a"]) - 0.3 and float(app.sim.it) > it0 + 0.5, "A 跳过开场（快进到刀落前）")
	check(await wait_until(func(): return str(app.sim.state) == "menu", 10.0), "跳过后进菜单")
	check(app.ui.pad_mode, "用了手柄 → 提示切成手柄键名")
	await wait_sec(0.3)

	# 2. 上下选择
	app.ui.sel = 0
	await tap(JOY_BUTTON_DPAD_DOWN)
	check(sel() == 1, "十字键下：第二项")
	await tap(JOY_BUTTON_DPAD_UP)
	check(sel() == 0, "十字键上：回第一项")
	await axis(JOY_AXIS_LEFT_Y, 1.0)
	check(sel() == 1, "左摇杆下推：下一项")
	await axis(JOY_AXIS_LEFT_Y, 0.97)
	await axis(JOY_AXIS_LEFT_Y, 1.0)
	await axis(JOY_AXIS_LEFT_X, 0.08)
	check(sel() == 1, "摇杆推满时手抖不算多按")
	await axis(JOY_AXIS_LEFT_Y, 0.0)
	await axis(JOY_AXIS_LEFT_X, 0.0)
	check(app._held == "", "摇杆回中：停止连发")

	# 3. 连发
	await btn(JOY_BUTTON_DPAD_DOWN, true)
	var n_dpad := await count_changes(sel, 0.9)
	await btn(JOY_BUTTON_DPAD_DOWN, false)
	check(n_dpad >= 3, "按住十字键下 0.9 秒会连发（变了 %d 次）" % n_dpad)
	check(await count_changes(sel, 0.4) == 0, "松开十字键停止连发")

	await axis(JOY_AXIS_LEFT_Y, 1.0)
	var n_stick := await count_changes(sel, 0.9)
	await axis(JOY_AXIS_LEFT_Y, 0.0)
	check(n_stick >= 3, "摇杆一直推着会连发（变了 %d 次）" % n_stick)
	check(await count_changes(sel, 0.4) == 0, "摇杆回中停止连发")

	await btn(JOY_BUTTON_DPAD_DOWN, true)
	await axis(JOY_AXIS_LEFT_Y, 0.05)
	await axis(JOY_AXIS_LEFT_X, -0.04)
	var n_mix := await count_changes(sel, 0.9)
	await btn(JOY_BUTTON_DPAD_DOWN, false)
	check(n_mix >= 3, "按着十字键时摇杆微抖不打断连发（变了 %d 次）" % n_mix)

	# 4. 设置：滑条连发、开关不连发、左右改操作方式、B 返回
	await goto_menu_item("settings")
	await tap(JOY_BUTTON_A)
	check(str(app.ui.mode) == "settings", "A 进设置")
	await goto_row("rain")
	app.sim.rain_percent = 0
	await btn(JOY_BUTTON_DPAD_RIGHT, true)
	await wait_sec(0.9)
	await btn(JOY_BUTTON_DPAD_RIGHT, false)
	check(int(app.sim.rain_percent) >= 30, "滑条按住右会连发（雨量到 %d）" % int(app.sim.rain_percent))
	await goto_row("shake")
	var shake0: bool = app.sim.shake
	await btn(JOY_BUTTON_DPAD_RIGHT, true)
	await wait_sec(0.9)
	await btn(JOY_BUTTON_DPAD_RIGHT, false)
	check(bool(app.sim.shake) != shake0, "开关按住只切一次")
	await tap(JOY_BUTTON_DPAD_LEFT)
	check(bool(app.sim.shake) == shake0, "开关再按一次切回")
	await goto_row("scheme")
	var F = load("res://scripts/night/player_factory.gd")
	var scheme0: String = F.scheme()
	await tap(JOY_BUTTON_DPAD_LEFT)
	check(F.scheme() != scheme0, "十字键左改操作方式")
	await tap(JOY_BUTTON_DPAD_RIGHT)
	check(F.scheme() == scheme0, "十字键右改回操作方式")
	await tap(JOY_BUTTON_B)
	check(str(app.ui.mode) == "menu" and str(app.sim.state) == "menu", "B 从设置返回菜单")

	# 5. 操作说明：A 进、B 出
	await goto_menu_item("help")
	await tap(JOY_BUTTON_A)
	check(str(app.ui.mode) == "help", "A 进操作说明")
	await tap(JOY_BUTTON_B)
	check(str(app.ui.mode) == "menu", "B 从操作说明返回")

	# 6. Y 静音 / X 随手一刀
	var m0: bool = app.audio.muted
	await tap(JOY_BUTTON_Y)
	check(bool(app.audio.muted) != m0, "Y 开关声音")
	await tap(JOY_BUTTON_Y)
	check(bool(app.audio.muted) == m0, "Y 再按一次恢复")
	var s0: float = app.sim.last_slash_t
	await wait_sec(0.1)
	await tap(JOY_BUTTON_X)
	check(float(app.sim.last_slash_t) != s0, "X 随手一刀")

	# 7. 键鼠 / 手柄混用
	await key(KEY_SHIFT)
	check(not app.ui.pad_mode, "按键盘 → 提示换回键盘")
	await tap(JOY_BUTTON_DPAD_UP)
	check(app.ui.pad_mode, "再按手柄 → 换成手柄")
	var mm := InputEventMouseMotion.new()
	mm.position = Vector2(10, 10)
	mm.relative = Vector2(1, 0)
	mm.screen_relative = Vector2(1, 0)
	Input.parse_input_event(mm)
	await process_frame
	check(app.ui.pad_mode, "鼠标微抖不算换回")
	mm = InputEventMouseMotion.new()
	mm.position = Vector2(60, 40)
	mm.relative = Vector2(50, 30)
	mm.screen_relative = Vector2(50, 30)
	Input.parse_input_event(mm)
	await process_frame
	check(not app.ui.pad_mode, "动鼠标 → 提示换回键鼠")

	# 8. 退出确认：按住左右不来回翻；B 取消
	await goto_menu_item("quit")
	await tap(JOY_BUTTON_A)
	check(str(app.ui.mode) == "confirm", "A 打开退出确认")
	var c0: int = app.ui.csel
	await btn(JOY_BUTTON_DPAD_RIGHT, true)
	check(int(app.ui.csel) != c0, "退出确认按右翻到另一个按钮")
	var n_conf := await count_changes(func(): return int(app.ui.csel), 0.9)
	await btn(JOY_BUTTON_DPAD_RIGHT, false)
	check(n_conf == 0, "退出确认按住不连发（又翻了 %d 次）" % n_conf)
	await tap(JOY_BUTTON_B)
	check(str(app.ui.mode) == "menu" and str(app.sim.state) == "menu", "B 取消退出")

	# 9. Back 重播开场，A 再跳过
	await tap(JOY_BUTTON_BACK)
	check(str(app.sim.state) == "intro", "Back 重播开场")
	await wait_sec(0.2)
	await tap(JOY_BUTTON_A)
	check(await wait_until(func(): return str(app.sim.state) == "menu", 10.0), "重播后 A 跳过回菜单")
	await wait_sec(0.3)

	# 10. 开始 → 进 rain_trial
	await goto_menu_item("start")
	await tap(JOY_BUTTON_A)
	check(str(app.sim.state) == "leave", "A 按“开始游戏”开始离场")
	var entered := await wait_until(func(): return current_scene != null and current_scene.scene_file_path == GAME, 20.0)
	check(entered, "离场后进入 rain_trial")
	_finish()


func _finish() -> void:
	restore()
	if failures.is_empty():
		print("PASS test_title_pad (%d checks)" % checks)
		quit(0)
	else:
		print("FAILED test_title_pad: %d / %d" % [failures.size(), checks])
		quit(1)
