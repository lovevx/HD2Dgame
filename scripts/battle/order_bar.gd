class_name OrderBar
extends HBoxContainer
## AT 顺序条（P1 v1）：屏顶一条水平序列，按敏捷降序排；当前行动单位高亮青色。
## 由 battle 循环在每轮 rebuild 一次；意图图标槽 P2 加。

const SystemUI := preload("res://scripts/ui/system_ui.gd")

var _labels: Array[Label] = []

## labels: PackedStringArray（如 ["玩家 Lv.5", "敌 Lv.4"]）；current_index 高亮当前行动位。
func build(labels: PackedStringArray, current_index: int) -> void:
	for child in get_children():
		child.queue_free()
	_labels.clear()
	for i in labels.size():
		var chip := Label.new()
		chip.text = labels[i]
		chip.add_theme_font_size_override("font_size", 20)
		chip.add_theme_color_override("font_color", Color("5fd0ff"))
		chip.add_theme_color_override("font_outline_color", Color(0.05, 0.08, 0.15, 0.9))
		chip.add_theme_constant_override("outline_size", 6)
		chip.modulate.a = 1.0 if i == current_index else 0.55
		chip.add_theme_color_override("font_color", Color.WHITE if i == current_index else Color("5fd0ff"))
		add_child(chip)
		if i < labels.size() - 1:
			var sep := Label.new()
			sep.text = "  ›  "
			sep.add_theme_font_size_override("font_size", 20)
			sep.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0, 0.5))
			add_child(sep)
		_labels.append(chip)