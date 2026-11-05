extends Control
## [YG-MARK] 由 YG 新增（首页「断晓 · 断光」WebGL 版移植到 Godot）。
##
## 首页总控：时间轴 / 状态机 / 键鼠输入 / 菜单和设置 / 转场进游戏。
## 对应 E:\.0download\code_artifact (1).html 里的 update()、输入段和菜单逻辑。
##
## 三个伙伴文件：
##   scripts/ui/yg_title/yg_title_sim.gd   模拟（雨滴、刀口、收尾）
##   scripts/ui/yg_title/yg_title_stage.gd 渲染（SubViewport 链 + 着色器）
##   scripts/ui/yg_title/yg_title_ui.gd    界面（铭文、菜单、设置、卡）
##   scripts/ui/yg_title/yg_title_audio.gd 声音
##
## 删除方法：见 docs/YG-首页断光-删除清单.md。

const SimScript := preload("res://scripts/ui/yg_title/yg_title_sim.gd")
const StageScript := preload("res://scripts/ui/yg_title/yg_title_stage.gd")
const UiScript := preload("res://scripts/ui/yg_title/yg_title_ui.gd")
const AudioScript := preload("res://scripts/ui/yg_title/yg_title_audio.gd")

const GAME_SCENE := "res://scenes/rain_trial.tscn"
const Factory := preload("res://scripts/night/player_factory.gd")

## [YG-MARK] 11-05 适配：设置存盘。
##   user://yg_title.cfg   首页自己的：画质 / 雨量 / 镜头震动
##   user://settings.cfg   和暂停菜单共用（已请 UI 线照同样键名读写）：[audio] master 0~1（总线 0）、[display] fullscreen
##   user://graphics.cfg   超采样，沿用 Supersample 自己的存法；操作方式沿用 Factory 的 user://controls.cfg
const TITLE_CFG := "user://yg_title.cfg"
const SHARED_CFG := "user://settings.cfg"
const GRAPHICS_CFG := "user://graphics.cfg"

## [YG-MARK] 同一次运行里第二次进首页（暂停菜单「回到标题」）就跳过开场，直接到菜单
static var _seen := false

var sim: RefCounted
var stage: Control
var ui: Control
var audio: Node

var _view := Vector2(1280.0, 720.0)
var _card_fired := false
var _prev_slashing := 0.0
var _prev_done := false

## [YG-MARK] 11-05 适配：窗口缩放后过 0.25 秒、两次读到同一个倍率才重建画面链（拖窗口时不狂重建）
var _scale_check := 0.25
var _scale_pending := -1.0
## [YG-MARK] 11-05 适配：手柄 / 摇杆按住方向时的连发
const PAD_DEAD := 0.5
const REPEAT_FIRST := 0.38
const REPEAT_NEXT := 0.11
var _held := ""
var _repeat_t := 0.0
var _stick := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_view = get_viewport_rect().size
	if _view.x < 2.0 or _view.y < 2.0:
		_view = Vector2(1280.0, 720.0)

	sim = SimScript.new(_view.x, _view.y)
	_load_settings()
	sim.init_drops()
	sim.recycle_target = int(round(float(sim.ql()["drops"]) * 0.36))

	stage = StageScript.new()
	add_child(stage)
	stage.build(sim, Vector2i(int(_view.x), int(_view.y)))

	ui = UiScript.new()
	add_child(ui)
	ui.setup(sim, _view)

	audio = AudioScript.new()
	add_child(audio)
	audio.setup(sim)

	sim.restart_intro()
	ui.set_mode("menu")
	ui.hide_ui()
	# 不是开机第一屏（从试玩「回到标题」进来，包括 OPEN_RAIN_TRIAL 直接进试玩的情况）也跳过开场
	if _seen or Engine.get_process_frames() > 10:
		sim.jump_to_menu()
		sim.it = float(sim.TL["ui_a"]) - 0.01   # 下一帧跨过 ui_a，菜单照常浮出
	_seen = true


func _process(delta: float) -> void:
	if sim == null:
		return
	var rdt := minf(0.05, maxf(0.0, delta))
	sim.now += rdt
	var dt := rdt
	if sim.hitstop > 0.0:
		sim.hitstop -= rdt
		dt = 0.0
	sim.sim_t += dt
	sim.update(dt, rdt)
	_watch_scale(rdt)
	_pad_repeat(rdt)
	stage.step()
	ui.tick(rdt)
	_audio_hooks()
	_post()


## [YG-MARK] 窗口 / 全屏 / F7 超采样变了 → 画面链按新的像素倍率重建
func _watch_scale(rdt: float) -> void:
	_scale_check -= rdt
	if _scale_check > 0.0:
		return
	_scale_check = 0.25
	var want: float = stage.target_scale()
	if absf(want - stage.px_scale) < 0.01:
		_scale_pending = -1.0
		return
	if absf(want - _scale_pending) < 0.01:
		stage.set_px_scale(want)
		_scale_pending = -1.0
	else:
		_scale_pending = want


func _pad_repeat(rdt: float) -> void:
	if _held == "":
		return
	# 左右连发只给滑条（全屏 / 开关类按住不放会来回闪）
	if (_held == "left" or _held == "right") and not (ui.mode == "settings" and str(ui.ROWS[ui.rsel]["type"]) == "slider"):
		return
	_repeat_t -= rdt
	if _repeat_t <= 0.0:
		_repeat_t = REPEAT_NEXT
		_nav(_held)


func _audio_hooks() -> void:
	if sim.cut_slashing > 0.5 and _prev_slashing <= 0.5:
		audio.play("slash")
	if sim.cut_done and not _prev_done:
		audio.play("slash_big")
	_prev_slashing = sim.cut_slashing
	_prev_done = sim.cut_done


func _post() -> void:
	if sim.show_ui_requested:
		sim.show_ui_requested = false
		sim.state = "menu"
		ui.refresh_continue()
		ui.show_ui()
		_preload_game()
	if sim.card_requested and not _card_fired:
		_card_fired = true
		if sim.fin_kind == "exit":
			get_tree().quit()
		else:
			_enter_game()


## [YG-MARK] 11-05：菜单出来就在后台加载试玩，按开始时不再顿一下
func _preload_game() -> void:
	if ResourceLoader.load_threaded_get_status(GAME_SCENE) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		ResourceLoader.load_threaded_request(GAME_SCENE)


## [YG-MARK] 11-05：收黑之后换到试玩，root 下挂一层黑幕，进去后 0.6 秒淡出再自删（不拦输入、不暂停）
func _enter_game() -> void:
	var packed: PackedScene = null
	var st := ResourceLoader.load_threaded_get_status(GAME_SCENE)
	if st == ResourceLoader.THREAD_LOAD_LOADED or st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		packed = ResourceLoader.load_threaded_get(GAME_SCENE) as PackedScene
	if packed == null:
		packed = load(GAME_SCENE) as PackedScene
	var veil := CanvasLayer.new()
	veil.name = "YgTitleFadeIn"
	veil.layer = 120
	var rect := ColorRect.new()
	rect.color = Color(0, 0, 0, 1)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.add_child(rect)
	get_tree().root.add_child(veil)
	var tw := veil.create_tween()
	tw.tween_interval(0.12)
	tw.tween_property(rect, "color:a", 0.0, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_callback(veil.queue_free)
	get_tree().change_scene_to_packed(packed)


## [YG-MARK] 调试用：把首页按 1/60 秒定步快进到第 seconds 秒（截图自查，和网页版的 ?at= 一个意思）
func fast_forward(seconds: float) -> void:
	var step := 1.0 / 60.0
	var guard := 0
	while sim.now < seconds and guard < 60000:
		guard += 1
		sim.now += step
		var dt := step
		if sim.hitstop > 0.0:
			sim.hitstop -= step
			dt = 0.0
		sim.sim_t += dt
		sim.update(dt, step)
		ui.tick(step)
		if sim.show_ui_requested:
			sim.show_ui_requested = false
			sim.state = "menu"
			ui.refresh_continue()
			ui.show_ui()
	stage.step()

# ---------------------------------------------------------------- [YG-MARK] 11-05 设置读写
func _load_settings() -> void:
	var c := ConfigFile.new()
	if c.load(TITLE_CFG) == OK:
		var q := str(c.get_value("title", "quality", sim.quality))
		if q in ["low", "mid", "high"]:
			sim.quality = q
		sim.rain_percent = clampi(int(c.get_value("title", "rain", sim.rain_percent)), 0, 100)
		sim.shake = bool(c.get_value("title", "shake", sim.shake))
	var s := ConfigFile.new()
	if s.load(SHARED_CFG) == OK:
		if s.has_section_key("audio", "master"):
			_set_master(float(s.get_value("audio", "master", 1.0)))
		if s.has_section_key("display", "fullscreen") and DisplayServer.get_name() != "headless":
			_set_fullscreen(bool(s.get_value("display", "fullscreen", false)))


func _save_settings() -> void:
	var c := ConfigFile.new()
	c.load(TITLE_CFG)
	c.set_value("title", "quality", sim.quality)
	c.set_value("title", "rain", sim.rain_percent)
	c.set_value("title", "shake", sim.shake)
	c.save(TITLE_CFG)
	var s := ConfigFile.new()
	s.load(SHARED_CFG)
	s.set_value("audio", "master", master_volume())
	s.set_value("display", "fullscreen", is_fullscreen())
	s.save(SHARED_CFG)


func master_volume() -> float:
	if AudioServer.is_bus_mute(0):
		return 0.0
	return clampf(db_to_linear(AudioServer.get_bus_volume_db(0)), 0.0, 1.0)


func _set_master(v: float) -> void:
	v = clampf(snappedf(v, 0.1), 0.0, 1.0)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(v, 0.0001)))
	AudioServer.set_bus_mute(0, v <= 0.0)


func is_fullscreen() -> bool:
	var m := DisplayServer.window_get_mode()
	return m == DisplayServer.WINDOW_MODE_FULLSCREEN or m == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN


func _set_fullscreen(on: bool) -> void:
	if on == is_fullscreen():
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)


func _supersample() -> Node:
	return get_tree().root.get_node_or_null("Supersample")


func supersample_on() -> bool:
	var ss := _supersample()
	return ss != null and bool(ss.get("enabled"))


func _set_supersample(on: bool) -> void:
	var ss := _supersample()
	if ss == null:
		return
	ss.call("set_enabled", on)
	var cfg := ConfigFile.new()
	cfg.load(GRAPHICS_CFG)
	cfg.set_value("graphics", "supersample", on)
	cfg.save(GRAPHICS_CFG)
	_scale_check = 0.0     # 马上按新倍率重建
	_scale_pending = stage.target_scale()


## 设置页每一行现在的值（界面画的时候问这里）
func row_value(key: String) -> Variant:
	match key:
		"quality": return ["low", "mid", "high"].find(str(sim.quality))
		"rain": return int(sim.rain_percent)
		"shake": return bool(sim.shake)
		"master": return roundi(master_volume() * 100.0)
		"fullscreen": return is_fullscreen()
		"ssaa": return supersample_on()
		"scheme": return Factory.SCHEMES.find(Factory.scheme())
	return null


# ---------------------------------------------------------------- 菜单
func _menu_items() -> Array:
	return ui.MENU


func _item_rect(i: int) -> Rect2:
	var h: float = ui._item_h()
	var y: float = ui._menu_top() + i * h
	return Rect2(Vector2(_view.x * 0.5 - 20.0 * ui.u, y), Vector2(40.0 * ui.u, h))


func _hover(p: Vector2) -> void:
	if ui.mode != "menu" or sim.state != "menu":
		return
	for i in ui.MENU.size():
		if _item_rect(i).has_point(p):
			if ui.sel != i:
				ui.sel = i
				audio.play("tick")
			return


func _menu_confirm() -> void:
	var item: Dictionary = ui.MENU[ui.sel]
	var act := str(item["act"])
	if act == "start":
		sim.begin_leave(act)
		ui.hide_ui()
		ui.set_mode("menu")
		return
	if act == "help":     # [YG-MARK] 11-05：「继续」是假的（没有存档系统），换成「操作说明」
		audio.play("confirm")
		sim.state = "settings"    # 模拟层只分“菜单类 / 开场 / 离开”，说明页和设置页同一类
		ui.set_mode("help")
		return
	if act == "settings":
		audio.play("confirm")
		sim.state = "settings"
		ui.rsel = 0
		ui.set_mode("settings")
		return
	if act == "quit":
		audio.play("confirm")
		sim.state = "confirm"
		ui.csel = 1
		ui.set_mode("confirm")


func _close_settings() -> void:
	audio.play("tick")
	sim.state = "menu"
	ui.set_mode("menu")


func _close_confirm() -> void:
	audio.play("tick")
	sim.state = "menu"
	ui.set_mode("menu")


func _close_help() -> void:
	audio.play("tick")
	sim.state = "menu"
	ui.set_mode("menu")


func _change_row(i: int, d: int) -> void:
	var row: Dictionary = ui.ROWS[i]
	var key := str(row["k"])
	match key:
		"quality":
			var order := ["low", "mid", "high"]
			var idx := clampi(order.find(str(sim.quality)) + d, 0, 2)
			if order[idx] == str(sim.quality):
				return
			sim.quality = order[idx]
			stage.rebuild()
			sim.init_drops()
			sim.freeze_all()
			sim.recycle_target = int(round(float(sim.ql()["drops"]) * 0.36))
		"rain":
			sim.rain_percent = clampi(int(sim.rain_percent) + d * 10, 0, 100)
		"master":
			_set_master(master_volume() + d * 0.1)
		"shake":
			sim.shake = not sim.shake
			if sim.shake:
				sim.trauma = 0.5
		"fullscreen":
			_set_fullscreen(not is_fullscreen())
		"ssaa":
			_set_supersample(not supersample_on())
		"scheme":
			var n: int = Factory.SCHEMES.size()
			var idx := (Factory.SCHEMES.find(Factory.scheme()) + d + n) % n
			Factory.set_scheme(Factory.SCHEMES[idx])
	_save_settings()
	audio.play("tick")


func _restart_intro() -> void:
	if sim.state == "leave" or sim.state == "exit":
		return
	sim.restart_intro()
	ui.hide_ui()
	ui.set_mode("menu")
	_card_fired = false
	_prev_done = false
	_prev_slashing = 0.0
	ui.toast("重 播 开 场 演 出")


# ---------------------------------------------------------------- 输入
func _input(event: InputEvent) -> void:
	if sim == null:
		return
	if event is InputEventMouseMotion:
		var p := get_local_mouse_position()
		sim.mouse["x"] = p.x
		sim.mouse["y"] = p.y
		sim.mouse["tx"] = (p.x / sim.W - 0.5) * 2.0
		sim.mouse["ty"] = (p.y / sim.H - 0.5) * 2.0
		if not sim.drag.is_empty():
			sim.drag["x"] = p.x
			sim.drag["y"] = p.y
			if not bool(sim.drag.get("slash", false)):
				var d0 := Vector2(float(sim.drag["x0"]), float(sim.drag["y0"]))
				if p.distance_to(d0) > 18.0:
					sim.drag["slash"] = true
			sim.drag_on = 1.0 if bool(sim.drag.get("slash", false)) else 0.0
		_hover(p)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		ui.pad_mode = false
		if event.pressed:
			_on_press(get_local_mouse_position())
		else:
			_on_release(get_local_mouse_position())
	elif event is InputEventKey and event.pressed and not event.echo:
		ui.pad_mode = false
		_on_key(event.keycode)
	elif event is InputEventJoypadButton:
		_on_pad_button(event)
	elif event is InputEventJoypadMotion:
		_on_pad_axis(event)


# ---------------------------------------------------------------- [YG-MARK] 11-05 手柄（Xbox 布局：十字键 / 左摇杆 选，A / Start 确认，B 返回）
const PAD_MAP := {
	JOY_BUTTON_DPAD_UP: "up", JOY_BUTTON_DPAD_DOWN: "down",
	JOY_BUTTON_DPAD_LEFT: "left", JOY_BUTTON_DPAD_RIGHT: "right",
	JOY_BUTTON_A: "ok", JOY_BUTTON_START: "ok", JOY_BUTTON_B: "back",
}


func _on_pad_button(ev: InputEventJoypadButton) -> void:
	var cmd: String = PAD_MAP.get(ev.button_index, "")
	if not ev.pressed:
		if cmd != "" and cmd == _held:
			_held = ""
		return
	ui.pad_mode = true
	_pad_press(cmd)


func _on_pad_axis(ev: InputEventJoypadMotion) -> void:
	if ev.axis == JOY_AXIS_LEFT_X:
		_stick.x = ev.axis_value
	elif ev.axis == JOY_AXIS_LEFT_Y:
		_stick.y = ev.axis_value
	else:
		return
	var cmd := ""
	if _stick.length() >= PAD_DEAD:
		if absf(_stick.y) >= absf(_stick.x):
			cmd = "down" if _stick.y > 0.0 else "up"
		else:
			cmd = "right" if _stick.x > 0.0 else "left"
	elif _stick.length() > 0.3:
		return     # 死区之间不变，免得在门槛上来回跳
	if cmd == _held:
		return
	_held = ""
	if cmd != "":
		ui.pad_mode = true
		_pad_press(cmd)


func _pad_press(cmd: String) -> void:
	if sim.state == "card":
		sim.back_from_card()
		ui.set_mode("menu")
		return
	if sim.state == "intro":
		sim.skip_intro()
		return
	if cmd == "":
		return
	if cmd in ["up", "down", "left", "right"]:
		_held = cmd
		_repeat_t = REPEAT_FIRST
	_nav(cmd)


func _on_press(p: Vector2) -> void:
	if sim.state == "card":
		sim.back_from_card()
		ui.set_mode("menu")
		return
	if sim.state == "intro":
		sim.skip_intro()
		return
	sim.drag = {"x0": p.x, "y0": p.y, "x": p.x, "y": p.y, "slash": false}
	sim.drag_on = 0.0


func _on_release(p: Vector2) -> void:
	var was_slash := bool(sim.drag.get("slash", false)) if not sim.drag.is_empty() else false
	if was_slash:
		var a := Vector2(float(sim.drag["x0"]), float(sim.drag["y0"]))
		if sim.state == "menu" or sim.state == "settings" or sim.state == "confirm":
			sim.player_slash(a.x, a.y, p.x, p.y)
			audio.play("slash")
	sim.drag = {}
	sim.drag_on = 0.0
	if was_slash:
		return
	# 点选
	if ui.mode == "menu" and sim.state == "menu":
		for i in ui.MENU.size():
			if _item_rect(i).has_point(p):
				ui.sel = i
				_menu_confirm()
				return
	elif ui.mode == "settings":
		# [YG-MARK] 11-05：按点到哪一行来（原来 ROWS.has(rsel) 恒为假，点了没反应）
		var i: int = ui.row_at(p)
		if i < 0:
			return
		ui.rsel = i
		if str(ui.ROWS[i]["type"]) == "back":
			_close_settings()
		else:
			_change_row(i, 1)
	elif ui.mode == "help":
		_close_help()
	elif ui.mode == "confirm":
		if ui.csel == 0:
			sim.begin_exit()
			ui.hide_ui()
		else:
			_close_confirm()


func _on_key(k: int) -> void:
	if k == KEY_M:
		audio.toggle_mute()
		return
	if sim.state == "card":
		sim.back_from_card()
		ui.set_mode("menu")
		return
	if k == KEY_R:
		_restart_intro()
		return
	if sim.state == "intro":
		sim.skip_intro()
		return
	if k == KEY_X:
		if sim.state == "menu" or sim.state == "settings" or sim.state == "confirm":
			var a := randf_range(-0.5, 0.5)
			var cx: float = sim.W * randf_range(0.3, 0.7)
			var cy: float = sim.H * randf_range(0.15, 0.85)
			var L: float = sim.W * 0.5
			sim.player_slash(cx - cos(a) * L, cy - sin(a) * L, cx + cos(a) * L, cy + sin(a) * L)
			audio.play("slash")
		return
	var cmd := ""
	if k == KEY_UP or k == KEY_W:
		cmd = "up"
	elif k == KEY_DOWN or k == KEY_S:
		cmd = "down"
	elif k == KEY_LEFT or k == KEY_A:
		cmd = "left"
	elif k == KEY_RIGHT or k == KEY_D:
		cmd = "right"
	elif k == KEY_ENTER or k == KEY_SPACE or k == KEY_J or k == KEY_KP_ENTER:
		cmd = "ok"
	elif k == KEY_ESCAPE or k == KEY_BACKSPACE or k == KEY_K:
		cmd = "back"
	if cmd != "":
		_nav(cmd)


## [YG-MARK] 11-05：键盘和手柄共用的菜单导航（cmd = up / down / left / right / ok / back）
func _nav(cmd: String) -> void:
	var up := cmd == "up"
	var dn := cmd == "down"
	var lf := cmd == "left"
	var rt := cmd == "right"
	var ok := cmd == "ok"
	var back := cmd == "back"

	if ui.mode == "menu" and sim.state == "menu":
		if up or dn:
			ui.sel = (ui.sel + (1 if dn else -1) + ui.MENU.size()) % ui.MENU.size()
			audio.play("tick")
		elif ok:
			_menu_confirm()
		elif back:
			ui.sel = ui.MENU.size() - 1
			audio.play("tick")
	elif ui.mode == "help":
		if ok or back:
			_close_help()
	elif ui.mode == "settings":
		if up or dn:
			ui.rsel = (ui.rsel + (1 if dn else -1) + ui.ROWS.size()) % ui.ROWS.size()
			audio.play("tick")
		elif lf or rt:
			if str(ui.ROWS[ui.rsel]["type"]) != "back":
				_change_row(ui.rsel, 1 if rt else -1)
		elif ok:
			if str(ui.ROWS[ui.rsel]["type"]) == "back":
				_close_settings()
			else:
				_change_row(ui.rsel, 1)
		elif back:
			_close_settings()
	elif ui.mode == "confirm":
		if lf or rt or up or dn:
			ui.csel = 1 - ui.csel
			audio.play("tick")
		elif ok:
			if ui.csel == 0:
				sim.begin_exit()
				ui.hide_ui()
			else:
				_close_confirm()
		elif back:
			_close_confirm()
