@tool
extends EditorInspectorPlugin
var controller: EditorPlugin

func _can_handle(object: Object) -> bool:
	return object is HD2DStage or object is HD2DTerrain or object is HD2DCharacter or object is HD2DCameraRig or object is HD2DRoad or object is HD2DProp

func _parse_begin(object: Object) -> void:
	var box := VBoxContainer.new()
	var label := Label.new()
	label.text="HD-2D · 原生参数 / 中文向导"
	box.add_child(label)
	var button := Button.new()
	button.text="在场景工坊中编辑"
	button.pressed.connect(func():
		controller.select_context(object)
		if object is HD2DProp: controller.ui.tabs.current_tab=0
		controller.dock.make_visible())
	box.add_child(button)
	if object is HD2DTerrain:
		var warning := Label.new()
		warning.text="高度场：无洞穴/悬空。建议保持节点缩放为 1。"
		warning.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		box.add_child(warning)
	add_custom_control(box)
	controller.i18n.watch(box)
