extends Node
## 断晓肉鸽 · 跨场景首领战构筑桥接器（RainTrial -> BossSample）
## 仅在点击「迎战镇守首领 · 断潮」时挂载于 root：
##   - 切入 BossSample 后等待 2 帧（确保 BossSample._ready 初始化完玩家 200 血与断潮实例），
##     自动挂载 PerkRig 并完整还原核心牌等级、四维属性、破界倍率与首领碎壳联动；
##   - 若切入非首领场景（如测试探针 boss_handoff_probe.tscn 或返回标题），记录快照后自动销毁，零节点泄漏。

const PerkRig := preload("res://scripts/roguelike/perk_rig.gd")

var snapshot: Dictionary = {}
var _injected_scene: Node = null
var _frames_waited: int = 0
var _pending_inject: bool = false


static func handoff_to_boss(tree: SceneTree, run_snapshot: Dictionary) -> Node:
	if tree == null or tree.root == null:
		return null
	var existing := tree.root.get_node_or_null("RoguelikeRunBridge")
	if existing != null:
		existing.free()
	var bridge := new()
	bridge.name = "RoguelikeRunBridge"
	bridge.snapshot = run_snapshot.duplicate(true)
	bridge._pending_inject = true
	tree.root.add_child(bridge)
	return bridge


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var cur := tree.current_scene
	if cur == null:
		return

	if _pending_inject:
		# 仍在旧 RainTrial 尚未切完场景：继续等
		if cur.get("boss_scene_path") != null:
			return
		_frames_waited += 1
		if _frames_waited < 2:
			return
		_pending_inject = false
		_frames_waited = 0
		if cur.get("player") != null and cur.get("boss") != null:
			_inject_into_boss_stage(cur)
		else:
			# 非 BossSample 场景（如探针场景或标题页）：保留 2 帧供测试读取后自清理
			_injected_scene = cur
			_cleanup_later()
		return

	if _injected_scene != null and cur != _injected_scene:
		queue_free()


func _inject_into_boss_stage(boss_stage: Node) -> void:
	_injected_scene = boss_stage
	var rig := boss_stage.get_node_or_null("PerkRig") as Node2D
	if rig == null:
		rig = PerkRig.new()
		rig.name = "PerkRig"
		boss_stage.add_child(rig)
	var p := boss_stage.get("player") as CharacterBody2D
	rig.call("setup", boss_stage, p)
	rig.call("import_snapshot", snapshot)
	var b := boss_stage.get("boss") as Node2D
	if b != null:
		rig.call("bind_boss", b)


func _cleanup_later() -> void:
	var tree := get_tree()
	if tree == null:
		queue_free()
		return
	await tree.process_frame
	await tree.process_frame
	if is_inside_tree():
		queue_free()
