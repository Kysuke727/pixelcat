# 已废弃：Yarn V3 绕线玩法测试

以下测试覆盖的是 **已正式废弃** 的 YarnConnection 绕线玩法：绕支点角度、路径路由、张力、玩家剪断与冷却返还。

它们保留在仓库中仅用于历史对照，**不属于 Sticky Yarn V4 的验收套件**。V4 战斗控制器不再实例化 YarnConnection，也不再暴露 V3 的毛线技能字段，因此这些测试在 V4 分支上运行会失败，这是预期结果，不应被当作 V4 回归。

| 文件 | 覆盖内容 | 状态 |
| --- | --- | --- |
| `tests/combat_v3_phase_c.gd` | YarnConnection 创建、减速、剪断退款、绕支点、张力、过期与场景清理 | 废弃，启动时打印 `DEPRECATED_YARN_V3_SKIPPED` 并跳过 |
| `tests/v3_1_1_yarn_slime_fixes.gd` | 绕线角度阈值、支点半径、张力、旧毛线技能加成、剪断退款 | 废弃，启动时打印 `DEPRECATED_YARN_V3_SKIPPED` 并跳过 |

未标记为废弃的测试仍用于 V4 回归，例如：

- `tests/sticky_yarn_v4.gd`：V4 黏黏球验收套件。
- `tests/combat_v3_phase_a.gd`、`combat_v3_phase_b.gd`、`combat_v3_phase_d.gd`：近战、碰撞、格挡。
- `tests/combat_v3_phase_e.gd`：史莱姆减速/束缚控制接口（直接调用，不依赖 YarnConnection）。
- `tests/combat_v3_1_phase_02.gd`：闪避、束缚失败与免疫。
- `tests/combat_v3_phase_f.gd`：战斗场景与 HUD 结构。
- `tests/v3_1_phases_04_to_06.gd`、`tests/review_v3_1_2_regressions.gd`：进度、存档与既有回归。
- `tests/profile_bootstrap.gd`：存档引导与旧数据。

V4 阶段 1 不删除上述废弃文件、`scripts/yarn_connection.gd`、绕线支点场景或旧技能点字段；清理工作留给后续阶段并由 Owner 审核。
