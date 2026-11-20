extends SceneTree
## 断晓界面专项回归（F1 + F2 + F3）：
## 1) 4 款 SIL OFL 1.1 开源商用哥特/石刻/狂草/重宋字体加载非空、混排字形有效、UI 脚本零 SystemFont 残留；
## 2) 战斗 HUD 大招提示接入 ControllerIcons 动态图标（键鼠 R <-> 手柄 RT），移除硬编码 label_keys.png；
## 3) 雨街播放多路动态音效与绝影音轨后，经暂停菜单回到标题并退出时 0 报错、0 音频/资源泄漏。

const GothicFonts := preload("res://scripts/ui/gothic_fonts.gd")
const ResultPanel := preload("res://scripts/ui/rain_trial_result.gd")
const TRIAL_SCENE := "res://scenes/rain_trial.tscn"
const TITLE_SCENE := "res://scenes/yg_title_zhanzhong.tscn"   # 11-17 暂停菜单“回到标题”改指斩钟首页

const UI_SCRIPTS: Array[String] = [
	"res://scripts/ui/gothic_fonts.gd",
	"res://scripts/night/combat_hud.gd",
	"res://scripts/ui/pause_menu.gd",
	"res://scripts/ui/rain_trial_result.gd",
	"res://scripts/ui/yg_title/yg_title_ui.gd",
]

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		print("FAIL: ", label)


func _is_clean_font(f: Font) -> bool:
	return f != null and f.get_class() != ("System" + "Font")


func _send_key(code: int) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await process_frame


func _send_pad_button(btn: JoyButton) -> void:
	for pressed in [true, false]:
		var ev := InputEventJoypadButton.new()
		ev.button_index = btn
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await process_frame


func _count_active_media(node: Node) -> Vector2i:
	## 返回 Vector2i(正在播放数, 仍持有非空 stream 的播放器数)
	var playing_cnt := 0
	var stream_cnt := 0
	if node is AudioStreamPlayer:
		var ap := node as AudioStreamPlayer
		if ap.playing:
			playing_cnt += 1
		if ap.stream != null:
			stream_cnt += 1
	elif node is AudioStreamPlayer2D:
		var ap2 := node as AudioStreamPlayer2D
		if ap2.playing:
			playing_cnt += 1
		if ap2.stream != null:
			stream_cnt += 1
	elif node is VideoStreamPlayer:
		var vp := node as VideoStreamPlayer
		if vp.is_playing():
			playing_cnt += 1
		if vp.stream != null:
			stream_cnt += 1
	for child in node.get_children():
		var sub := _count_active_media(child)
		playing_cnt += sub.x
		stream_cnt += sub.y
	return Vector2i(playing_cnt, stream_cnt)


func _silence_tree_media(node: Node) -> void:
	if node is AudioStreamPlayer:
		var ap := node as AudioStreamPlayer
		ap.stop()
		ap.stream = null
	elif node is AudioStreamPlayer2D:
		var ap2 := node as AudioStreamPlayer2D
		ap2.stop()
		ap2.stream = null
	elif node is VideoStreamPlayer:
		var vp := node as VideoStreamPlayer
		vp.stop()
		vp.stream = null
	for child in node.get_children():
		_silence_tree_media(child)


func _run() -> void:
	_test_gothic_fonts()
	await _test_static_and_result_panel()
	await _test_hud_icons_and_return_to_title_clean()
	await _teardown_cleanly()

	if failures.is_empty():
		print("UI_CLEAN_TESTS: %d checks / 0 failures" % checks)
		quit(0)
	else:
		print("UI_CLEAN_TESTS: %d checks / %d failures" % [checks, failures.size()])
		quit(1)


func _test_gothic_fonts() -> void:
	check(FileAccess.file_exists("res://assets/fonts/gothic/OFL.txt"), "开源哥特字体目录含 SIL OFL 1.1 授权文件")
	for p in GothicFonts.all_font_paths():
		var res := load(p)
		check(res is FontFile, "开源字体资源成功加载为 FontFile：%s" % p)

	var bl := GothicFonts.blackletter()
	var cz := GothicFonts.cinzel(700)
	var dg := GothicFonts.digits(700, true)
	var br := GothicFonts.brush()
	var sf := GothicFonts.serif(450)
	var hv := GothicFonts.serif(900)

	check(_is_clean_font(bl) and bl.fallbacks.size() >= 1, "PirataOne 哥特黑体非空且配置中文回退")
	check(_is_clean_font(cz) and cz.fallbacks.size() >= 1, "Cinzel 石刻衬线非空且配置中文回退")
	check(_is_clean_font(dg) and _is_clean_font(br) and _is_clean_font(sf) and _is_clean_font(hv),
			"石刻斜体数字、马善政狂草与思源重宋全部非空且非系统字体")

	check(bl.get_string_size("Intermissio Lux Scissa S", HORIZONTAL_ALIGNMENT_LEFT, -1, 48).x > 80.0,
			"PirataOne 哥特铭文与评级字母字形尺寸正常")
	check(cz.get_string_size("CONTROLS 128 用时 0:42", HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x > 80.0,
			"Cinzel 石刻与重宋混排尺寸正常")
	check(br.get_string_size("弹刀！破晓！连击", HORIZONTAL_ALIGNMENT_LEFT, -1, 32).x > 60.0,
			"马善政毛笔狂草弹出字形尺寸正常")


func _test_static_and_result_panel() -> void:
	var banned_token := "System" + "Font"
	for path in UI_SCRIPTS:
		var src := FileAccess.get_file_as_string(path)
		check(src != "" and not src.contains(banned_token), "脚本源码零系统字体残留：%s" % path)

	var hud_src := FileAccess.get_file_as_string("res://scripts/night/combat_hud.gd")
	check(not hud_src.contains("label_keys.png"), "combat_hud.gd 已移除写死的 label_keys.png")
	check(hud_src.contains("ControllerIconTexture.gd") and hud_src.contains("\"ult\""),
			"combat_hud.gd 已接入 ControllerIconTexture(path=\"ult\")")

	var panel := ResultPanel.new()
	panel.summary = {"grade": "S", "seconds": 75.0, "max_combo": 36}
	root.add_child(panel)
	await process_frame
	await process_frame
	check(_is_clean_font(panel._body_font) and _is_clean_font(panel._title_font) and _is_clean_font(panel._grade_font),
			"试玩结算面板三套哥特/石刻/重宋字体均非系统字体")
	panel.free()
	await process_frame


func _test_hud_icons_and_return_to_title_clean() -> void:
	var packed: PackedScene = load(TRIAL_SCENE)
	var stage: Node = packed.instantiate()
	root.add_child(stage)
	current_scene = stage
	for _i in 8:
		await process_frame

	var hud: Control = stage.get("hud")
	var menu: CanvasLayer = stage.get_node_or_null("PauseMenu")
	check(hud != null and menu != null, "雨街试玩 HUD 与暂停菜单挂载正常")
	if hud == null or menu == null:
		return

	check(_is_clean_font(hud._font) and _is_clean_font(hud._serif) and _is_clean_font(hud._heavy)
			and _is_clean_font(hud._digits) and _is_clean_font(hud._black) and _is_clean_font(hud._brush),
			"CombatHud 运行时全部字体字段均为打包开源字体")
	check(_is_clean_font(menu._title_font) and _is_clean_font(menu._serif)
			and _is_clean_font(menu._serif_bold) and _is_clean_font(menu._digits),
			"PauseMenu 运行时全部字体字段均为打包开源字体")

	# F2：键鼠 R <-> 手柄 RT 动态切换
	await _send_key(KEY_J)
	check(not hud.is_using_pad_prompt() and hud.get_ult_resolved_icon_path().ends_with("/key/r.png"),
			"键鼠输入下 HUD 大招提示自动解析为 R 图标")
	await _send_pad_button(JOY_BUTTON_X)
	check(hud.is_using_pad_prompt() and hud.get_ult_resolved_icon_path().ends_with("/rt.png"),
			"手柄输入下 HUD 大招提示自动切换为 RT 图标")
	await _send_key(KEY_K)
	check(not hud.is_using_pad_prompt() and hud.get_ult_resolved_icon_path().ends_with("/key/r.png"),
			"切回键鼠输入后 HUD 大招提示恢复为 R 图标")

	# 触发满能量扫光与弹出字绘制，覆盖全套新字体渲染路径
	hud.ult_frac = 1.0
	if stage.get("style") != null:
		stage.style.combo = 12
	hud.callout("弹刀！")
	hud.queue_redraw()
	await process_frame
	await process_frame

	# F1：播放多路场内音效与绝影音轨，随后打开暂停菜单退回标题
	var audio: Node = stage.get("audio")
	var ult_fx: Node = stage.get("ult_fx")
	if audio != null:
		audio.play_swing(0.8)
		audio.play_hit(0.9, true)
		audio.play_parry()
		audio.play_clear()
	if ult_fx != null and ult_fx.get("_voice") is AudioStreamPlayer:
		var uv := ult_fx.get("_voice") as AudioStreamPlayer
		if uv.stream != null:
			uv.play()
	await process_frame
	await process_frame
	var before_counts := _count_active_media(stage)
	check(before_counts.y > 0, "退回标题前场内存在挂载音频/视频流的播放器（实测 %d 个）" % before_counts.y)

	await _send_key(KEY_ESCAPE)
	check(menu.opened and paused, "Esc 打开暂停菜单")
	menu._to_title()
	var after_silence := _count_active_media(stage)
	check(after_silence.x == 0 and after_silence.y == 0,
			"_to_title() 立即停播并清空场内全部音频与视频流（残留播放=%d, 残留流=%d）" % [after_silence.x, after_silence.y])

	for _i in 12:
		await process_frame
	check(not paused and current_scene != null and current_scene.scene_file_path == TITLE_SCENE,
			"从暂停菜单无报错切回标题场景 yg_title_zhanzhong.tscn")

	if current_scene != null:
		var title_ui: Control = current_scene.get("ui")
		check(title_ui != null and _is_clean_font(title_ui._serif) and _is_clean_font(title_ui._serif_light)
				and _is_clean_font(title_ui._gothic) and _is_clean_font(title_ui._menu_font)
				and _is_clean_font(title_ui._blackletter),
				"标题页 YgTitleUi 全部字体（含 Lux Scissa 哥特副标与 Cinzel 徽章）均为打包开源字体")


func _teardown_cleanly() -> void:
	# 实机非无头下若标题页发起了后台线程预载 rain_trial.tscn，等待并回收
	if DisplayServer.get_name() != "headless":
		var deadline := Time.get_ticks_msec() + 5000
		while ResourceLoader.load_threaded_get_status(TRIAL_SCENE) == ResourceLoader.THREAD_LOAD_IN_PROGRESS and Time.get_ticks_msec() < deadline:
			OS.delay_msec(10)
		if ResourceLoader.load_threaded_get_status(TRIAL_SCENE) == ResourceLoader.THREAD_LOAD_LOADED:
			var _preloaded = ResourceLoader.load_threaded_get(TRIAL_SCENE)

	if current_scene != null:
		_silence_tree_media(current_scene)
		var sc := current_scene
		current_scene = null
		sc.free()
	await process_frame
	OS.delay_msec(80)
	await process_frame
