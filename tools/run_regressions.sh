#!/usr/bin/env bash
## 回归流程：把 tools/ 下的校验脚本成批跑一遍，逐条报 PASS / FAIL / 耗时。
##
## 用法：
##   tools/run_regressions.sh                    # 跑默认套件（见下面 SUITE）
##   tools/run_regressions.sh --list             # 只列套件内容，不跑
##   tools/run_regressions.sh validate_demo       # 只跑指定几支（名字不带 .gd）
##
## Godot 可执行文件按序取：$GODOT_BIN → 本机 Steam 安装位置 → PATH 里的 godot。
## 单支超时默认 420 秒，用 RG_TIMEOUT 覆盖。
##
## 约定：套件里只放**当前全绿**的脚本。红的要么修好再进，要么留在 SIDE 列表里 ——
## 一盏常年亮着的红灯会训练人忽略失败，回归流程就白建了。
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

## 默认套件（2026-09-23 全绿；2026-09-28 在 31c6d86 上复查：colpo / level_refine / combo_skills / settings / demo 五支在未改动代码上即红，待单独处理）。
SUITE=(
  validate_demo              # 自由练习场冒烟：木桩/野狼、伤害结算、倒下重开、不动正式资源
  validate_save_transaction  # 出击结算事务 + 存档原子写/版本/坏档回退
  validate_six_attrs         # 六维派生公式 + 属性点接口 + 试炼场集成
  validate_world_drops       # 掉落池 / 场景宝箱 / 决战全回复 / 阶段结算清装备
  validate_combat_skills     # 即时战斗技能数值
  validate_combo_skills      # 连段技能
  validate_core_loop         # 核心循环
  validate_quest_panel       # J 任务面板
  validate_player_hud        # 玩家状态 HUD：快捷栏判定 / 冷却暗幕 / 受击残影 / 低血红晕
  validate_settings          # 设置页：设置档读写兜底 + 画面/声音/游玩/按键是否真生效 + 两个入口
  validate_onboarding_flow   # 开场 → 港口引导
  validate_level_refine      # 关卡细化
  validate_colpo             # 科尔波山白盒（最慢：装整场景 + 三波敌人）
  validate_new_player_frames # 废弃分支，脚本自带跳过门闩（加 --force 才真跑）
)

## 已知红、暂不进套件（不是"没问题"，是待单独处理；见 README「待决」一节）。
##   validate_player_anim   8 个 attack_* 动画帧率断言失败（期望 15，实测 12）
##   check_harbor_hub       8 项陈旧断言 + 过场后段错误（signal 11），非本次改动引入
SIDE=()

find_godot() {
  if [[ -n "${GODOT_BIN:-}" && -x "${GODOT_BIN}" ]]; then printf '%s' "$GODOT_BIN"; return; fi
  local c
  for c in \
    "E:/SteamLibrary/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe" \
    "D:/SteamLibrary/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe" \
    "D:/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe"
  do
    [[ -x "$c" ]] && { printf '%s' "$c"; return; }
  done
  command -v godot || command -v godot4 || true
}

selected=()
case "${1:-}" in
  --list) printf '%s\n' "${SUITE[@]}"; exit 0 ;;
  -h|--help) sed -n '1,20p' "${BASH_SOURCE[0]}"; exit 0 ;;
  "") selected=("${SUITE[@]}") ;;
  *) selected=("$@") ;;
esac

GODOT="$(find_godot)"
if [[ -z "$GODOT" ]]; then
  echo "找不到 Godot 可执行文件。设 GODOT_BIN 指向它，或把它放进 PATH。" >&2
  exit 2
fi

TIMEOUT="${RG_TIMEOUT:-420}"
LOGDIR="$ROOT/.tmp_preview/regressions"
rm -rf "$LOGDIR"; mkdir -p "$LOGDIR"

echo "Godot : $GODOT"
echo "项目  : $ROOT"
echo "日志  : $LOGDIR"
echo

failed=()
for t in "${selected[@]}"; do
  script="$ROOT/tools/$t.gd"
  if [[ ! -f "$script" ]]; then
    printf 'MISS  %-26s 找不到 %s\n' "$t" "tools/$t.gd"
    failed+=("$t")
    continue
  fi
  start=$(date +%s)
  timeout "$TIMEOUT" "$GODOT" --headless --path "$ROOT" --script "res://tools/$t.gd" \
    > "$LOGDIR/$t.log" 2>&1
  code=$?
  dur=$(( $(date +%s) - start ))
  if [[ $code -eq 0 ]]; then
    printf 'PASS  %-26s %3ds\n' "$t" "$dur"
  elif [[ $code -eq 124 ]]; then
    printf 'TIMEOUT %-24s %3ds  （RG_TIMEOUT=%s）\n' "$t" "$dur" "$TIMEOUT"
    failed+=("$t")
  else
    printf 'FAIL  %-26s %3ds  exit=%d\n' "$t" "$dur" "$code"
    failed+=("$t")
  fi
done

echo
if [[ ${#failed[@]} -eq 0 ]]; then
  echo "全部通过（${#selected[@]} 支）"
  exit 0
fi

echo "失败 ${#failed[@]} 支：${failed[*]}"
echo "失败日志尾部："
for t in "${failed[@]}"; do
  echo "---- $t ----"
  tail -n 15 "$LOGDIR/$t.log" 2>/dev/null | sed 's/^/    /'
done
exit 1
