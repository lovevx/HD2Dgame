extends SceneTree
## Decode imported CompressedTexture2D resources through Godot's Image API.
## Usage: godot --headless --path . --script res://tools/dump_compressed_textures.gd -- res://out res://asset.png ...

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("Expected output directory followed by one or more Texture2D resource paths")
		quit(2)
		return

	var output_dir := String(args[0])
	var absolute_dir := ProjectSettings.globalize_path(output_dir)
	var dir_error := DirAccess.make_dir_recursive_absolute(absolute_dir)
	if dir_error != OK and dir_error != ERR_ALREADY_EXISTS:
		push_error("Cannot create output directory: %s (err=%d)" % [absolute_dir, dir_error])
		quit(2)
		return

	var failures := 0
	for index in range(1, args.size()):
		var resource_path := String(args[index])
		var texture := ResourceLoader.load(resource_path) as Texture2D
		if texture == null:
			push_error("Not a readable Texture2D: %s" % resource_path)
			failures += 1
			continue
		var image := texture.get_image()
		if image == null or image.is_empty():
			push_error("Texture2D.get_image() returned empty: %s" % resource_path)
			failures += 1
			continue
		var output_path := absolute_dir.path_join("%03d.png" % (index - 1))
		var save_error := image.save_png(output_path)
		if save_error != OK:
			push_error("Image.save_png() failed: %s (err=%d)" % [output_path, save_error])
			failures += 1
		else:
			print("Decoded %s -> %s (%dx%d)" % [resource_path, output_path, image.get_width(), image.get_height()])
	quit(1 if failures > 0 else 0)
