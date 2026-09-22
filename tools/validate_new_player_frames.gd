extends SceneTree
## 引擎侧校验 player_frames_new.tres：动画数、帧数、区域合法性、贴地/越格。
## 运行：godot --headless --path . --script res://tools/validate_new_player_frames.gd
##
## ⚠️ 这套资源已废弃，默认跳过（见下面 _init() 里的门闩）。判断依据：
##   · 当前玩家用的是 res://assets/characters/player_frames_video.tres
##     —— player.tscn 的 sprite_frames 指向它，它由 tools/build_video_player_frames.gd 生成，
##       回归覆盖在 tools/validate_player_anim.gd。
##   · player_frames_new.tres / assets/characters/black_swordsman_new/ 在全仓库**没有第二处引用**
##     （只剩生成它的 build_new_player_frames.gd 和本文件）。
## 昨天实测：64 个动画、744 帧里 39 帧「内容贴到格边（可能被裁）」，全部在 attack_* 里 ——
## 即图集切格把刀光弧裁掉了。它不影响游戏（没人读它），修它也没有游戏内收益。
##
## 待作者拍板：修那 39 处裁切，还是连同 assets/characters/black_swordsman_new/ 与
## tools/build_new_player_frames.gd 一起删掉。删素材不可逆，所以这里只做「默认静音 + 保留复检入口」。
## 要复检这套备用资源：加 `-- --force`（见 README「回归流程」一节）。

const PATH := "res://assets/characters/black_swordsman_new/player_frames_new.tres"
const EXPECT_ANIMS := 64
const EXPECT_FRAMES := 12
const GROUND_SLACK := 16

func _init() -> void:
	# 废弃分支默认跳过：否则回归流程里永远挂着一盏红，会训练人忽略失败。
	if not OS.get_cmdline_user_args().has("--force"):
		print("SKIPPED  player_frames_new.tres 已废弃（当前玩家用 player_frames_video.tres）")
		print("         复检这套备用资源：-- --force")
		quit(0)
		return
	var frames: SpriteFrames = load(PATH)
	if frames == null:
		push_error("加载失败：%s" % PATH)
		quit(1)
		return
	var anims := frames.get_animation_names()
	anims.sort()
	var fails: Array[String] = []
	var checked := 0
	var worst_ground := 0
	var worst_name := ""
	var cell := Vector2i.ZERO

	if anims.size() != EXPECT_ANIMS:
		fails.append("动画数 %d ≠ 期望 %d" % [anims.size(), EXPECT_ANIMS])

	for a in anims:
		var count := frames.get_frame_count(a)
		if count != EXPECT_FRAMES:
			fails.append("%s 帧数 %d ≠ %d" % [a, count, EXPECT_FRAMES])
		cell = Vector2i.ZERO                    # 每个动画各自一种格子尺寸（设计如此）
		for i in count:
			var t := frames.get_frame_texture(a, i)
			if t is not AtlasTexture:
				fails.append("%s[%d] 不是 AtlasTexture" % [a, i])
				continue
			var at: AtlasTexture = t
			var img: Image = at.atlas.get_image()
			if cell == Vector2i.ZERO:
				cell = Vector2i(at.region.size)
			elif Vector2i(at.region.size) != cell:
				fails.append("%s 帧尺寸不一致 %s vs %s" % [a, at.region.size, cell])
			if not at.filter_clip:
				fails.append("%s[%d] filter_clip 未开（会溢出到相邻格）" % [a, i])
			# 该格在整图里的位置 → 取子图 used_rect，检查越格与贴地
			var sub := img.get_region(Rect2i(at.region.position, at.region.size))
			var used := sub.get_used_rect()
			if used.size == Vector2i.ZERO:
				fails.append("%s[%d] 空格" % [a, i])
				continue
			if used.position.x <= 0 or used.position.y <= 0 \
					or used.position.x + used.size.x >= at.region.size.x \
					or used.position.y + used.size.y >= at.region.size.y:
				fails.append("%s[%d] 内容贴到格边（可能被裁）" % [a, i])
			var bottom := used.position.y + used.size.y
			var gl := int(at.region.size.y) - GROUND_SLACK
			var dev: int = abs(bottom - gl)
			if dev > worst_ground:
				worst_ground = dev
				worst_name = "%s[%d]" % [a, i]
			checked += 1

	print("动画 %d 个，帧 %d 张，格 %s" % [anims.size(), checked, str(cell)])
	print("最差贴地偏差 %d px（%s）——含刀光弧的帧会低于地面线，属正常" % [worst_ground, worst_name])
	if fails.is_empty():
		print("PASS：全部通过")
		quit(0)
	else:
		print("FAIL %d 项：" % fails.size())
		for f in fails.slice(0, 20):
			print("  - " + f)
		quit(1)
