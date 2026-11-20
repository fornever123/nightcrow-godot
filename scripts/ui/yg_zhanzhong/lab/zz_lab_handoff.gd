extends Node
## 《光粒子重构》实验：换成真关卡的那几帧。
## 先用一张和最后一帧一模一样的图盖住关卡加载与开局核心面板，确认核心后撤掉；界面层先藏起来再淡入。

const HUD_IN := 24
const HUD_FADE := 30

var f := 0
var done := false
var cover: CanvasLayer
var hud: Array = []
var was_visible := {}


func _ready() -> void:
	cover = CanvasLayer.new()
	cover.layer = 250
	cover.name = "LabCover"
	var r := TextureRect.new()
	r.texture = load(String(get_meta("cover")))
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	cover.add_child(r)
	add_child(cover)


func _process(_dt: float) -> void:
	f += 1
	var cs := get_tree().current_scene
	if not done and cs != null and cs.name != "LabFlow":
		var fo: Node = cs.get_node_or_null("ForkChoiceOverlay")
		if fo != null and fo.has_method("_confirm_opening"):
			fo.call("_confirm_opening")
			done = true
			f = 0
	if not done:
		return
	if hud.is_empty():
		_collect(get_tree().root)
	if f == 3 and cover != null:
		cover.queue_free()
		cover = null
	var k := clampf(float(f - HUD_IN) / HUD_FADE, 0.0, 1.0)
	for l: CanvasLayer in hud:
		if not is_instance_valid(l):
			continue
		l.visible = f >= HUD_IN and bool(was_visible.get(l.get_instance_id(), true))
		for c in l.get_children():
			if c is CanvasItem:
				(c as CanvasItem).modulate.a = k
	if f > HUD_IN + HUD_FADE + 2:
		queue_free()


func _collect(n: Node) -> void:
	for c in n.get_children():
		if c is CanvasLayer and c != cover and (c as CanvasLayer).layer > 0:
			hud.append(c)
			was_visible[c.get_instance_id()] = (c as CanvasLayer).visible
			(c as CanvasLayer).visible = false
		_collect(c)
