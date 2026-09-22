extends RefCounted
## 校验脚本共用的隔离环境。两件事缺一不可，只做第一件会留下「本机才通过」的假绿：
##
##   1. **隔离存档** —— 把 GameState.save_path 指到本测试专属的 user:// 文件，跑完删干净。
##      不隔离的校验会直接写玩家真实存档（跑一次验证就改掉乐园币/背包/宝箱记录）。
##
##   2. **固定初始状态** —— GameState 在 _ready() 里已经读过真实存档，所以 *只* 换
##      save_path 并不够：attributes / coins / campaign 仍是本机存档里的值，派生上限
##      （max_hp = 50+体力×10、max_mp = 智力×10、max_stamina = 60+体力×12）跟着本机
##      进度漂移，断言就成了「装了这台的存档才过」。这里统一走 reset_progress()，
##      把六维钉回 Campaign.BASE_STATS（str6/agi7/con5/int6/cha3/luk1），
##      于是 max_hp=100、max_mp=60、max_stamina=120 —— 校验脚本可以放心断言具体数值，
##      但仍然推荐写派生公式而不是字面量（见 validate_battle 的体力上限断言）。
##
## 用法（必须在 call_deferred 的 run() 里、且 GameState 已就绪之后调用）：
##   const TestEnv := preload("res://tools/test_env.gd")
##   var gs: Node = root.get_node("GameState")
##   var save_path := TestEnv.isolate(gs, "battle")
##   ...
##   TestEnv.cleanup(gs)        # 退出前删掉隔离档（含 .bak / .tmp）
##
## keep_persistence=true 留给要真写盘的校验（validate_save_transaction 要验原子替换与
## .bak 回退，必须让 save_game() 真的落盘）。其余校验一律默认断写盘，跑完磁盘无痕。

## 隔离档路径：按 tag 区分，避免同一台机器上并行跑两个校验时互相踩。
static func path_for(tag: String) -> String:
	return "user://%s_validation.cfg" % tag

## 删掉一份存档的全部世代（正式档 / 备份 / 写一半的临时档）。
static func purge(path: String) -> void:
	for suffix in ["", ".bak", ".tmp"]:
		var abs_path := ProjectSettings.globalize_path(path + suffix)
		if FileAccess.file_exists(abs_path):
			DirAccess.remove_absolute(abs_path)

## 隔离 + 归零。返回实际使用的存档路径，退出前把它交给 cleanup()。
## 注意顺序：先换路径、再 purge、最后 reset_progress —— 否则 reset 会把档写回真实存档。
static func isolate(gs: Node, tag: String, keep_persistence := false) -> String:
	var path := path_for(tag)
	gs.set("save_path", path)
	gs.set("persistence_enabled", keep_persistence)
	purge(path)
	gs.call("reset_progress")
	return path

## 收尾：断写盘 + 清掉隔离档。
static func cleanup(gs: Node) -> void:
	gs.set("persistence_enabled", false)
	purge(str(gs.get("save_path")))
