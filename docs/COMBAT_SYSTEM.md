# 即时战斗实现现状

战斗运行于探索场景，不切换控制模式。玩家、普通敌人与 Boss 持续实时更新；眩晕用于小怪处决和 Boss 短暂硬直。

完整实现索引与数值表见 [REALTIME_COMBAT_EXTRACTION.md](REALTIME_COMBAT_EXTRACTION.md)。实际运行以 `player.gd`、`scripts/combat/`、`scripts/main/campaign.gd` 和 `scripts/world/` 为准。