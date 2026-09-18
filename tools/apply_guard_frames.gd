extends SceneTree
## 把四向格挡接进玩家精灵：左右沿用现有侧面格挡图，上下换成各自方向的格挡图。
## 重新生成 guard_down.png / guard_up.png（768×320，4×2 帧）后重跑本脚本即可。
const FRAMES_PATH := "res://assets/characters/black_swordsman/player_frames.tres"
const SHEETS := {
	"guard_down": "res://assets/characters/black_swordsman/guard_down.png",
	"guard_up": "res://assets/characters/black_swordsman/guard_up.png",
}
const CELL := Vector2i(192, 160)
const COLUMNS := 4
const FRAME_COUNT := 8

func _initialize() -> void:
	var frames := load(FRAMES_PATH) as SpriteFrames
	if frames == null:
		push_error("Missing SpriteFrames: " + FRAMES_PATH)
		quit(1)
		return
	for animation in SHEETS:
		var sheet := load(SHEETS[animation]) as Texture2D
		if sheet == null:
			push_error("Missing guard sheet: " + SHEETS[animation])
			quit(1)
			return
		frames.clear(animation)
		for index in FRAME_COUNT:
			var atlas := AtlasTexture.new()
			atlas.atlas = sheet
			atlas.region = Rect2(Vector2(index % COLUMNS * CELL.x, index / COLUMNS * CELL.y), Vector2(CELL))
			frames.add_frame(animation, atlas, 1.0)
		print("guard frames: %s <- %s (%d frames)" % [animation, SHEETS[animation], frames.get_frame_count(animation)])
	var error := ResourceSaver.save(frames, FRAMES_PATH)
	if error != OK:
		push_error("Save failed: " + FRAMES_PATH)
		quit(1)
		return
	print("GUARD_FRAMES_APPLY: PASS")
	quit()
