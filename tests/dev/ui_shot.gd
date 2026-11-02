extends SceneTree
## 开发工具（UI 会话 10-31）：现有 UI 盘点截图。雨街试玩的开场横幅 / HUD / 连击评价 / 伤害数字 / 弹出字 / 提示 / 封印横幅 / 大招满 / 受伤 / 结算页，再截训练场。
## 需要真实渲染（不加 --headless）：engine/Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/dev/ui_shot.gd --resolution 1280x720 --fixed-fps 60
## 截图目录：环境变量 SHOT_DIR。
const Buffer := preload("res://scripts/core/input_buffer.gd")
const Shade := preload("res://scripts/night/shade.gd")
var stage
var p
var c0 := 0.0
var dir := ""


func _initialize() -> void:
	call_deferred("run")


func fr(actions: Array[StringName] = [], edges: Array[StringName] = [], axis := Vector2.ZERO) -> Buffer.Frame:
	var f := Buffer.Frame.new()
	f.actions = actions
	f.pressed_this_frame = edges
	f.axis = axis
	return f


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, name])
	print("SHOT ", name)


func frames(n: int, f: Buffer.Frame = null) -> void:
	for i in n:
		p.set_injected_frame(f if f != null else fr())
		await physics_frame


func shade(kind: int, x: float, feet: float, facing: int) -> Node2D:
	var sh: Node2D = Node2D.new()
	sh.set_script(Shade)
	sh.setup(kind, p, stage.floor_y, 1.0)
	sh.position = Vector2(c0 + x, feet - 60.0)
	sh.terrain = stage.terrain
	stage.add_child(sh)
	sh.spawn_frames = 0
	sh.active = false
	sh.facing = facing
	stage._on_shade_spawned(sh)
	return sh


func run() -> void:
	dir = OS.get_environment("SHOT_DIR")
	DirAccess.make_dir_recursive_absolute(dir)
	stage = load("res://scenes/rain_trial.tscn").instantiate()
	root.add_child(stage)
	current_scene = stage
	await process_frame
	p = stage.player
	c0 = stage._center_of(0)
	# 和 PLAY_RAIN_RIGHT 一样出生在钟楼右侧
	p.reset_state(Vector2(c0 + 450.0, stage.floor_y - p.foot_offset))
	await frames(40)
	await shot("01_开场横幅_HUD_操作说明")
	await frames(150)
	await shot("02_开场提示条")

	# 战斗：三只影卒挤在一起，普通三连打出连击 / 评价 / 伤害数字
	stage.hud._banner_life = 0.0
	stage.encounter.clear_shades()
	stage.encounter.running = false
	p.reset_state(Vector2(c0 - 1180.0, 580.0 - p.foot_offset))
	p._set_facing(1)
	await frames(30)
	shade(Shade.Kind.GRUNT, -1100, 580, -1)
	shade(Shade.Kind.GRUNT, -1085, 580, -1)
	shade(Shade.Kind.BRUTE, -1060, 580, -1)
	await frames(20)
	var J: StringName = &"attack_light"
	for round in 2:
		for hit in 3:
			await frames(1, fr([J], [J]))
			await frames(5)
			if round == 1 and hit == 1:
				await shot("03_多目标伤害数字_连击评价")
			await frames(12)
	await shot("04_连击评价_敌人血条")
	stage.hud.visible = false
	for n in stage.get_children():
		if n.get_script() == Shade:
			n.bars_hidden = true
	await frames(45)
	await shot("00_无UI底图")
	stage.hud.visible = true
	stage.hud.callout("挑飞！", Color("9fd8ff"), 36)
	await frames(3)
	stage.hud.callout("弹刀！", Color("dfe8ff"), 38)
	await frames(4)
	await shot("05_弹出字")

	# 大招满 + 低血 + 受伤红边
	p.ult_energy = p.ult_max
	p.hp = p.max_hp * 0.22
	stage.hud.hurt()
	await frames(4)
	await shot("06_大招满_低血_受伤红边")

	# 封印解除横幅
	stage.encounter.clear_shades()
	await frames(40)
	stage.hud.banner("封印解除", "生命 +30 · 继续往右走", 2.2)
	await frames(14)
	await shot("07_封印解除横幅")
	stage.hud.help_visible = false
	await frames(150)
	await shot("08_H隐藏说明后的常态HUD")

	# 旧的 HUD 内结算（无限循环那套，雨街试玩不用）
	stage.hud.show_result({
		"title": "第 1 轮 结算", "grade": "A",
		"lines": [["用时", "4:12"], ["最高连击", "37"], ["挑飞", "12"], ["下砸 / 撞墙 / 连锁", "5 / 3 / 2"], ["弹刀", "4"], ["受击", "3 次（42 伤害）"]],
		"footer": "继续往右走：下一轮影子更耐打（生命 ×1.25）"}, 6.5)
	await frames(30)
	await shot("09_旧HUD结算面板")
	stage.hud.hide_result()

	# 试玩结算页（rain_trial_result.gd）
	stage.encounter_index = stage.round_waves.size() - 1
	stage.style.max_combo = 37
	stage._trial_time = 287.0
	stage._on_encounter_cleared()
	await process_frame
	await process_frame
	await shot("10_试玩结算页")
	paused = false
	stage.queue_free()
	await process_frame

	# 训练场
	var tr = load("res://scenes/training.tscn").instantiate()
	root.add_child(tr)
	current_scene = tr
	for i in 90:
		await physics_frame
	await shot("11_训练场")
	print("CAP_DONE")
	quit()
