extends Node
## 实验：进入影街关卡并自动确认开局核心，供 --write-movie 录出干净的游戏开局画面（只在实验里用）
## ZZ_LAB_NOHUD=1 时隐藏 layer>0 的界面层，只留游戏世界

var f := 0
var done := false


func _ready() -> void:
	if has_meta("watch"):
		set_process(true)
		return
	var keep := Node.new()
	keep.set_script(get_script())
	keep.set_meta("watch", true)
	keep.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child.call_deferred(keep)
	get_tree().change_scene_to_file.call_deferred("res://scenes/rain_trial.tscn")
	set_process(false)


func _process(_dt: float) -> void:
	if not has_meta("watch"):
		return
	f += 1
	if not done and f >= 3:
		var cs := get_tree().current_scene
		var fo: Node = cs.get_node_or_null("ForkChoiceOverlay") if cs != null else null
		if fo != null and fo.has_method("_confirm_opening"):
			fo.call("_confirm_opening")
			done = true
			print("[lab_grab] confirmed at frame ", f)
	if done and OS.get_environment("ZZ_LAB_NOHUD") == "1":
		_hide_hud(get_tree().root)


func _hide_hud(n: Node) -> void:
	for c in n.get_children():
		if c is CanvasLayer and (c as CanvasLayer).layer > 0:
			(c as CanvasLayer).visible = false
		_hide_hud(c)
