extends SceneTree
## 第一批 P0 插件集成冒烟回归：PhantomCamera2D、WigglyAppendage2D、ControllerIcons、GodotStateCharts、Pandora、PankuConsole。
## 运行：godot --headless --fixed-fps 60 --path . --script res://tests/test_p0_addons.gd

var checks := 0
var failures: Array[String] = []


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		print("FAIL: ", label)


func _initialize() -> void:
	call_deferred("_run")


func _wait_frames(n: int) -> void:
	for _i in n:
		await physics_frame


func _run() -> void:
	await _test_wiggly_appendage()
	await _test_state_charts()
	await _test_phantom_camera()
	await _test_controller_icons()
	await _test_pandora()
	await _test_panku_config()

	print("%d checks, %d failures" % [checks, failures.size()])
	quit(1 if failures.size() > 0 else 0)


func _test_wiggly_appendage() -> void:
	var host := Node2D.new()
	root.add_child(host)
	var tail := WigglyAppendage2D.new()
	tail.only_process_when_visible = false
	tail.segment_count = 6
	tail.segment_length = 45.0
	tail.curvature = 0.15
	host.add_child(tail)
	await _wait_frames(3)
	check(tail.points.size() > 6, "WigglyAppendage2D generates subdivided tail points")
	host.position = Vector2(180.0, -40.0)
	host.scale.x = -1.0
	await _wait_frames(4)
	var all_finite := true
	for pt in tail.points:
		if is_nan(pt.x) or is_nan(pt.y) or is_inf(pt.x) or is_inf(pt.y):
			all_finite = false
	check(all_finite, "WigglyAppendage2D remains finite after horizontal flip and motion")
	host.queue_free()
	await _wait_frames(2)


func _test_state_charts() -> void:
	var actor := Node.new()
	root.add_child(actor)

	var chart := StateChart.new()
	var parallel := ParallelState.new()
	parallel.name = "BossBrain"
	chart.add_child(parallel)

	# 轨道 1：Boss 阶段
	var phase_track := CompoundState.new()
	phase_track.name = "PhaseTrack"
	parallel.add_child(phase_track)
	var p1 := AtomicState.new()
	p1.name = "DockPhase"
	phase_track.add_child(p1)
	var p2 := AtomicState.new()
	p2.name = "BoathousePhase"
	phase_track.add_child(p2)
	phase_track.initial_state = NodePath("DockPhase")

	var tr_phase := Transition.new()
	tr_phase.name = "ToPhase2"
	tr_phase.event = &"wall_broken"
	tr_phase.to = NodePath("../../BoathousePhase")
	p1.add_child(tr_phase)

	# 轨道 2：受击 / 霸体状态
	var armor_track := CompoundState.new()
	armor_track.name = "ArmorTrack"
	parallel.add_child(armor_track)
	var normal := AtomicState.new()
	normal.name = "Launchable"
	armor_track.add_child(normal)
	var hyper := AtomicState.new()
	hyper.name = "SuperArmor"
	armor_track.add_child(hyper)
	armor_track.initial_state = NodePath("Launchable")

	var tr_armor := Transition.new()
	tr_armor.name = "ToArmor"
	tr_armor.event = &"attack_windup"
	tr_armor.to = NodePath("../../SuperArmor")
	normal.add_child(tr_armor)

	var entered_p2 := [false]
	var entered_armor := [false]
	p2.state_entered.connect(func(): entered_p2[0] = true)
	hyper.state_entered.connect(func(): entered_armor[0] = true)

	actor.add_child(chart)
	await _wait_frames(2)
	check(p1.active and normal.active, "StateChart activates initial parallel states")

	chart.send_event(&"attack_windup")
	chart.send_event(&"wall_broken")
	await _wait_frames(2)
	check(entered_p2[0] and p2.active, "StateChart transitions Boss phase track")
	check(entered_armor[0] and hyper.active, "StateChart transitions parallel armor track independently")

	actor.queue_free()
	await _wait_frames(2)


func _test_phantom_camera() -> void:
	var mgr_script: GDScript = load("res://addons/phantom_camera/scripts/managers/phantom_camera_manager.gd")
	check(mgr_script != null, "PhantomCameraManager script loads cleanly")
	var pcam_script: GDScript = load("res://addons/phantom_camera/scripts/phantom_camera/phantom_camera_2d.gd")
	var host_script: GDScript = load("res://addons/phantom_camera/scripts/phantom_camera_host/phantom_camera_host.gd")
	check(pcam_script != null and host_script != null, "PhantomCamera2D & PhantomCameraHost scripts load cleanly")

	# 若自定义 SceneTree 未自动挂载 PhantomCameraManager，按需临时挂一个验证完整链路
	var temp_mgr: Node = null
	if root.get_node_or_null("PhantomCameraManager") == null:
		temp_mgr = mgr_script.new()
		temp_mgr.name = "PhantomCameraManager"
		root.add_child(temp_mgr)

	var stage := Node2D.new()
	root.add_child(stage)
	var player_target := Node2D.new()
	player_target.position = Vector2(100, 500)
	var boss_target := Node2D.new()
	boss_target.position = Vector2(700, 500)
	stage.add_child(player_target)
	stage.add_child(boss_target)

	var cam := Camera2D.new()
	stage.add_child(cam)
	var pcam_host: Node = host_script.new()
	cam.add_child(pcam_host)

	var pcam_group: Node2D = pcam_script.new()
	pcam_group.priority = 10
	pcam_group.follow_mode = pcam_group.FollowMode.GROUP
	stage.add_child(pcam_group)
	pcam_group.append_follow_targets(player_target)
	pcam_group.append_follow_targets(boss_target)

	var pcam_cutscene: Node2D = pcam_script.new()
	pcam_cutscene.position = Vector2(1200, 320)
	pcam_cutscene.priority = 5
	stage.add_child(pcam_cutscene)

	await _wait_frames(3)
	check(pcam_group.is_active(), "PhantomCamera2D activates higher-priority Group camera")
	pcam_cutscene.priority = 20
	await _wait_frames(2)
	check(pcam_cutscene.is_active(), "PhantomCamera2D switches to cutscene camera when priority raised")

	stage.queue_free()
	if temp_mgr != null:
		temp_mgr.queue_free()
	await _wait_frames(2)


func _test_controller_icons() -> void:
	var ci_script: GDScript = load("res://addons/controller_icons/ControllerIcons.gd")
	check(ci_script != null, "ControllerIcons singleton script loads")
	var ci_node: Node = ci_script.new()
	ci_node.name = "ControllerIcons"
	root.add_child(ci_node)
	await _wait_frames(2)
	var key_tex: Texture2D = ci_node.parse_path("key/space")
	check(key_tex != null, "ControllerIcons resolves keyboard prompt icon texture")
	ci_node.queue_free()
	await _wait_frames(2)


func _test_pandora() -> void:
	var pandora_api_script: GDScript = load("res://addons/pandora/api.gd")
	check(pandora_api_script != null, "Pandora API script loads")
	var api: Node = pandora_api_script.new()
	api.name = "Pandora"
	root.add_child(api)
	await _wait_frames(1)
	var cat: PandoraCategory = api.create_category("RoguelikeStructures")
	var perk: PandoraEntity = api.create_entity("SheatheSettlement", cat)
	check(cat != null and perk != null and api.get_entity(perk.get_entity_id()) != null, "Pandora creates and queries roguelike category & entity in memory")
	api.queue_free()
	await _wait_frames(2)


func _test_panku_config() -> void:
	check(PankuConfig.is_custom_default_config_exists(), "PankuConsole custom default config file exists")
	check(bool(ProjectSettings.get_setting("panku/disable_on_release", false)) == true, "PankuConsole is configured to auto-disable on release exports")
	var env := PankuGDExprEnv.new()
	var res: Dictionary = env.execute("2 + 3 * 4")
	check(not res.failed and int(res.result) == 14, "PankuConsole expression evaluator executes cleanly")
	var panku_scene: PackedScene = load("res://addons/panku_console/console.tscn")
	check(panku_scene != null, "PankuConsole scene loads cleanly")
	var panku_inst: Node = panku_scene.instantiate()
	panku_inst.name = "Panku"
	root.add_child(panku_inst)
	await _wait_frames(2)
	check(panku_inst.is_inside_tree(), "PankuConsole mounts in SceneTree without errors")
	panku_inst.queue_free()
	await _wait_frames(2)
