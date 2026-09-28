# 即时战斗设计

本项目只采用即时战斗。玩家移动、读招、闪避、攻击、技能、眩晕、处决、敌人 AI 和 Boss 阶段均在当前场景实时运行。

当前规则、数值、文件入口和素材清单见 [REALTIME_COMBAT_EXTRACTION.md](REALTIME_COMBAT_EXTRACTION.md)。数值真值源为 `player.gd`、`data/combat_skills.gd`、`data/attributes.gd` 与 `scripts/combat/`。