extends SceneTree
## 2 倍超采样开关（scripts/presentation/supersample.gd）。
## headless：只查“什么都不做”。要测真实画面不能加 --headless：
##   engine/Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/test_supersample.gd --resolution 1280x720
## 查：F7 切换并存盘、层和子视口路由、描边补偿、重开 / 换场景后继续生效、子视口同帧不延迟、暂停菜单鼠标选中、窗口缩放和黑边、关掉后还原。
## 用户的 user://graphics.cfg 测前备份、测后还原。
const TRIAL := "res://scenes/rain_trial.tscn"
const TITLE := "res://scenes/yg_title_duanguang.tscn"
const CFG := "user://graphics.cfg"
const DESIGN := Vector2i(1280, 720)
var checks := 0
var failures: Array[String] = []
var ss: Node
var cfg_backup := PackedByteArray()
var had_cfg := false


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		print("FAIL: ", label)


func wait(n: int) -> void:
	for i in n:
		await process_frame


func key(code: int) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = pressed
		Input.parse_input_event(e)
		await process_frame
	await process_frame


func screen() -> Image:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	return img


func mean_luma(img: Image) -> float:
	var small := img.duplicate() as Image
	small.resize(32, 18, Image.INTERPOLATE_BILINEAR)
	var s := 0.0
	for y in small.get_height():
		for x in small.get_width():
			s += small.get_pixel(x, y).get_luminance()
	return s / float(small.get_width() * small.get_height())


## 缩成小图后逐格比：画面错位 / 缩放不对会差很多，雨丝和灯闪这种小东西不算
func coarse_diff(a: Image, b: Image) -> float:
	var sa := a.duplicate() as Image
	var sb := b.duplicate() as Image
	sa.resize(64, 36, Image.INTERPOLATE_BILINEAR)
	sb.resize(64, 36, Image.INTERPOLATE_BILINEAR)
	var s := 0.0
	for y in 36:
		for x in 64:
			s += absf(sa.get_pixel(x, y).get_luminance() - sb.get_pixel(x, y).get_luminance())
	return s / (64.0 * 36.0)


func layers_of(from: Node) -> Array:
	var out := []
	for c in from.get_children():
		if c is SubViewport:
			continue
		if c is CanvasLayer:
			out.append(c)
		out.append_array(layers_of(c))
	return out


## 主窗口里除显示层以外的 CanvasLayer 是否都画到 want 上
func all_routed(want: Viewport) -> bool:
	var n := 0
	for l in layers_of(root):
		if l.name == &"SupersampleDisplay":
			continue
		n += 1
		var cv: Viewport = l.custom_viewport
		if want == root:
			if cv != null and cv != root:
				return false
		elif cv != want:
			return false
	return n > 0


func stage_mat(stage: Node) -> ShaderMaterial:
	return stage.get("light_mat") as ShaderMaterial


func run() -> void:
	ss = root.get_node_or_null("Supersample")
	check(ss != null, "自动加载 Supersample 存在")
	if ss == null:
		_finish()
		return
	if DisplayServer.get_name() == "headless":
		check(not ss.enabled, "headless 不开超采样")
		ss.set_enabled(true)
		check(not ss.enabled and ss.view() == null, "headless 下 set_enabled 无效")
		check(root.canvas_cull_mask == 0xFFFFFFFF, "headless 不改主窗口剔除层")
		_finish()
		return
	had_cfg = FileAccess.file_exists(CFG)
	if had_cfg:
		cfg_backup = FileAccess.get_file_as_bytes(CFG)
	ss.set_enabled(false)
	await _run_rendered()
	ss.set_enabled(false)
	if had_cfg:
		var f := FileAccess.open(CFG, FileAccess.WRITE)
		f.store_buffer(cfg_backup)
		f.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG))
	_finish()


func _run_rendered() -> void:
	var stage: Node = load(TRIAL).instantiate()
	root.add_child(stage)
	current_scene = stage
	await wait(40)
	# ---- 关着：和没有这个脚本一样
	check(ss.view() == null, "关着没有 2 倍画布可用")
	check(root.canvas_cull_mask == 0xFFFFFFFF, "关着主窗口什么都画")
	check(is_equal_approx(float(stage_mat(stage).get_shader_parameter("ol_width")), 1.1), "关着描边 1.1")
	var off_img: Image = await screen()
	check(mean_luma(off_img) > 0.02, "关着画面不是黑的")

	# ---- 打开
	ss.set_enabled(true)
	await wait(5)
	var sub: SubViewport = ss.view()
	check(sub != null, "打开后有 2 倍画布")
	check(sub != null and sub.size == DESIGN * 2, "2 倍画布尺寸 = 窗口 × 2")
	check(sub != null and sub.size_2d_override == DESIGN, "2D 坐标仍是设计尺寸")
	check(root.canvas_cull_mask == ss.DISPLAY_BIT, "主窗口只画缩小显示那一层")
	check(all_routed(sub), "所有 CanvasLayer 都改画到 2 倍画布")
	check(root.get_visible_rect().size == Vector2(DESIGN), "游戏看到的屏幕尺寸不变")
	check(is_equal_approx(float(stage_mat(stage).get_shader_parameter("ol_width")), 2.2), "打开后描边 ×2")
	check(sub != null and sub.canvas_transform.is_equal_approx(root.canvas_transform), "镜头变换同步")
	var on_img: Image = await screen()
	check(on_img.get_size() == DESIGN, "输出仍是窗口大小")
	check(mean_luma(on_img) > 0.02, "打开后画面不是黑的")
	var d: float = coarse_diff(off_img, on_img)
	print("off/on coarse diff = %.4f" % d)
	check(d < 0.03, "开关前后画面位置和亮度一致（%.4f）" % d)

	# ---- 子视口同帧：场景里新建的小画布这一帧改色，这一帧的成品就要看到
	await _probe_same_frame(stage, "打开时")

	# ---- F7：切换 + 存盘
	await key(KEY_F7)
	check(not ss.enabled, "F7 关闭")
	var c := ConfigFile.new()
	check(c.load(CFG) == OK and c.get_value("graphics", "supersample", true) == false, "F7 关闭写进存档")
	check(is_equal_approx(float(stage_mat(stage).get_shader_parameter("ol_width")), 1.1), "关闭后描边还原")
	check(root.canvas_cull_mask == 0xFFFFFFFF, "关闭后主窗口剔除层还原")
	check(all_routed(root), "关闭后层都回主窗口")
	var back_img: Image = await screen()
	var d2: float = coarse_diff(off_img, back_img)
	check(d2 < 0.03, "关闭后画面和最初一致（%.4f）" % d2)
	await key(KEY_F7)
	check(ss.enabled, "F7 再打开")
	c = ConfigFile.new()
	check(c.load(CFG) == OK and c.get_value("graphics", "supersample", false) == true, "F7 打开写进存档")

	# ---- 暂停菜单：鼠标选中（层画到 2 倍画布后，GUI 坐标不能错）
	await wait(5)
	await _menu_mouse(stage)

	# ---- 窗口缩放、非 16:9 黑边
	await _resize_check()

	# ---- 重开关卡：新场景的层、子视口、描边都要重新接上
	reload_current_scene()
	await wait(40)
	stage = current_scene
	check(stage != null and stage_mat(stage) != null, "重开后关卡在")
	if stage != null:
		sub = ss.view()
		check(all_routed(sub), "重开后层继续画到 2 倍画布")
		check(is_equal_approx(float(stage_mat(stage).get_shader_parameter("ol_width")), 2.2), "重开后新材质描边 ×2")
		await _probe_same_frame(stage, "重开后")
		await _probe_same_frame(stage, "关着建小画布再打开", true)
		check(mean_luma(await screen()) > 0.02, "重开后画面不是黑的")

	# ---- 换场景：首页 → 关卡
	change_scene_to_file(TITLE)
	await wait(60)
	# 首页根节点是 Control，平时没有 CanvasLayer，走共用的世界层
	check(root.canvas_cull_mask == ss.DISPLAY_BIT, "首页时主窗口仍只画缩小显示那一层")
	var title_img: Image = await screen()
	check(mean_luma(title_img) > 0.005, "首页画面不是黑的")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.runtime/fx_aa"))
	title_img.save_png(ProjectSettings.globalize_path("res://.runtime/fx_aa/title_ssaa_on.png"))
	change_scene_to_file(TRIAL)
	await wait(40)
	stage = current_scene
	check(stage != null and all_routed(ss.view()), "从首页进关卡后继续生效")
	if stage != null and stage_mat(stage) != null:
		check(is_equal_approx(float(stage_mat(stage).get_shader_parameter("ol_width")), 2.2), "从首页进关卡后描边 ×2")


## toggle = 先关掉超采样建小画布，再打开（小画布比 2 倍画布晚激活，又没有新视口来触发引擎重排，最容易晚一帧）
func _probe_same_frame(stage: Node, label: String, toggle := false) -> void:
	if toggle:
		ss.set_enabled(false)
		await wait(3)
	var vp := SubViewport.new()
	vp.size = Vector2i(16, 16)
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var fill := ColorRect.new()
	fill.size = Vector2(16, 16)
	fill.color = Color.BLACK
	vp.add_child(fill)
	stage.add_child(vp)
	var layer := CanvasLayer.new()
	layer.layer = 100
	var show := TextureRect.new()
	show.texture = vp.get_texture()
	show.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	show.position = Vector2(600, 300)
	show.size = Vector2(80, 80)
	layer.add_child(show)
	stage.add_child(layer)
	await wait(5)
	if toggle:
		ss.set_enabled(true)
		await wait(5)
	var same := true
	for col in [Color(1, 0, 0), Color(0, 1, 0), Color(0, 0, 1), Color(1, 0, 0)]:
		fill.color = col
		var img: Image = await screen()
		var got: Color = img.get_pixel(640, 340)
		if absf(got.r - col.r) > 0.1 or absf(got.g - col.g) > 0.1 or absf(got.b - col.b) > 0.1:
			same = false
	check(same, "%s小画布改色当帧就显示（不晚一帧）" % label)
	layer.queue_free()
	vp.queue_free()
	await wait(2)


func _menu_mouse(stage: Node) -> void:
	var menu = stage.get_node_or_null("PauseMenu")
	check(menu != null, "有暂停菜单")
	if menu == null:
		return
	await key(KEY_ESCAPE)
	check(menu.opened, "超采样开着 Esc 能开菜单")
	await wait(40)
	var hits: Array = menu.get("_hits")
	check(hits.size() >= 2, "菜单项都登记了点击区")
	if hits.size() >= 2:
		var target: Array = hits[1]
		var pos: Vector2 = (target[0] as Rect2).get_center()
		var m := InputEventMouseMotion.new()
		m.position = pos
		m.global_position = pos
		Input.parse_input_event(m)
		await wait(3)
		check(menu.index == int(target[1]), "鼠标移到第 2 项能选中（index=%d）" % menu.index)
	await key(KEY_ESCAPE)
	await wait(3)
	check(not menu.opened, "菜单能关")
	paused = false


func _resize_check() -> void:
	var was := root.size
	root.size = Vector2i(1600, 900)
	await wait(6)
	var sub: SubViewport = ss.view()
	check(sub.size == Vector2i(3200, 1800), "窗口 1600×900 时 2 倍画布 3200×1800（实际 %s）" % sub.size)
	check(root.get_visible_rect().size == Vector2(DESIGN), "窗口缩放后设计尺寸不变")
	root.size = Vector2i(1000, 800)      # 比 16:9 高：上下黑边
	await wait(6)
	check(sub.size == Vector2i(2000, 1125), "窗口 1000×800 时按 16:9 内容算（实际 %s）" % sub.size)
	# 黑边是引擎显示到窗口时加的，不在主窗口纹理里：纹理只有内容区，大小正好是 2 倍画布的一半
	var img: Image = await screen()
	check(img.get_size().x == 1000 and absi(img.get_size().y - 563) <= 1, "主窗口纹理是 16:9 内容区（实际 %s）" % img.get_size())
	check(mean_luma(img) > 0.01, "内容区有画面")
	var left := 0.0
	var right := 0.0
	for y in range(50, img.get_size().y - 50, 25):
		left += img.get_pixel(3, y).get_luminance()
		right += img.get_pixel(img.get_size().x - 4, y).get_luminance()
	check(left > 0.05 and right > 0.05, "画面铺满内容区左右两边（没有缩小或错位）")
	root.size = was
	await wait(6)
	check(sub.size == DESIGN * 2, "窗口还原后 2 倍画布还原")


func _finish() -> void:
	print("SUPERSAMPLE_TESTS: %d checks / %d failures" % [checks, failures.size()])
	for f in failures:
		print("  ", f)
	quit(1 if failures.size() > 0 else 0)
