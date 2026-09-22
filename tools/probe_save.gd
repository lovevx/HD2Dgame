extends SceneTree
## 临时探针：在真实目标 harbor.tscn 上验证「改完 → pack → 落盘」是否带上新增节点。
const TMP := "res://tools/backups/_probe_harbor.tscn"

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var packed: PackedScene = load("res://scenes/world/harbor.tscn")
	var root: Node = packed.instantiate()
	print("PROBE root children=", root.get_child_count())
	var marker := Node3D.new()
	marker.name = "ProbeMarker"
	root.add_child(marker)
	marker.owner = root
	var pack_result := PackedScene.new().pack(root)
	var save_result := ResourceSaver.save(packed, TMP)
	var text := FileAccess.get_file_as_string(TMP)
	var out := FileAccess.open("user://probe_sizes.txt", FileAccess.WRITE)
	out.store_string("pack=%s save=%s tmp_len=%d has_marker=%s\n" % [error_string(pack_result), error_string(save_result), text.length(), text.contains("ProbeMarker")])
	out.close()
	quit(0)
