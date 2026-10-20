# PixelCat 毛线物理与收紧流程实现报告

日期：2026-10-20
工作分支：`feature/yarn-physics-v3.1`
基线：`c0b0598c2e44de2419d3de6e65e80ba5e36706ea`

## 本轮实现

- 保留现有 InputMap：`ranged_attack` 仍为 K，`yarn_cut` 仍为 Q。
- 毛线连接期间，玩家移动造成的实际路由长度正增量才会增加有效绳长；锚定目标或支点移动、路由拓扑变化不提供放线长度。
- K 在连接存在时不发射新弹丸，而是停止所有仍在放线的连接，并锁定当时绳长；停止放线不会清零松弛量，也不会直接触发束缚。
- 只有放线停止、有效缠绕成立、松弛耗尽且玩家本帧主动向外拉时才结算。猫已到硬性绳长边界时，如果仍有有效向外输入且没有传送/复活位移，可立即完成结算，不需要再移动额外距离。
- 逐目标应用免疫和束缚；成功后猫端连接结束。实际存在的闭环会复制到独立 `BoundYarnLoop`，由 Line2D 与 StaticBody2D 胶囊边构成，持续时间取本次 `bind_duration`。晚进入绳圈的敌人只受物理阻挡，不会补绑。
- 史莱姆碰撞层加入活动绷紧绳线及保留绳圈；扑击撞到绳障碍时停止并进入 RECOVER，不施加额外眩晕。猫的碰撞掩码不包含持久绳圈层，因此束缚后可以离开。

## 修改文件

- `project.godot`
- `scenes/enemies/slime.tscn`
- `scripts/bound_yarn_loop.gd`、`scripts/bound_yarn_loop.gd.uid`
- `scripts/enemies/slime.gd`
- `scripts/player_combat.gd`
- `scripts/yarn_connection.gd`
- `tests/yarn_feed_retained_loop.gd`、`tests/yarn_feed_retained_loop.gd.uid`
- `tests/v3_1_1_yarn_slime_fixes.gd`
- `tests/yarn_wrap_group_physics.gd`
- 本报告

UID 文件由 Godot 为新增脚本生成，用于稳定资源标识，按项目既有脚本 UID 规范保留。

## 验证

引擎：Godot 4.7.2 stable（`ed1daf0bf`）。所有测试通过隔离的 `APPDATA` 运行，并设置 `PIXELCAT_TEST_MODE=1`；存档启动/恢复测试另用隔离目录进行新档、写入、重启读取三阶段验证。

无头项目导入命令：

```powershell
Godot_v4.7.2-stable_win64_console.exe --headless --path . --editor --quit --log-file <隔离目录>/feed-final-import.log
```

结果：退出码 0，项目扫描完成。导入日志同时出现 Godot 的 `Safe save failed` 警告；日志没有给出失败目标路径，因此不能确定失败的是项目元数据还是编辑器配置，亦不能据此声称相关文件保存正常。

测试命令模板：

```powershell
$env:APPDATA = '<隔离目录>'
$env:PIXELCAT_TEST_MODE = '1'
Godot_v4.7.2-stable_win64_console.exe --headless --path . --log-file <隔离目录>/<测试名>.log --script res://tests/<测试名>.gd
```

13 个现有及新增测试脚本均退出码 0，并出现各自的 `*_PASSED` 标记：

- `combat_v3_1_phase_02.gd`
- `combat_v3_phase_a.gd` 至 `combat_v3_phase_f.gd`
- `review_v3_1_2_regressions.gd`
- `v3_1_1_yarn_slime_fixes.gd`
- `v3_1_phases_04_to_06.gd`
- `yarn_feed_retained_loop.gd`（新增）
- `yarn_review_v3_4_regressions.gd`
- `yarn_wrap_group_physics.gd`

存档启动验证（隔离目录）也通过：`PROFILE_BOOTSTRAP_NEW_PASSED`、`PROFILE_BOOTSTRAP_WRITE_PASSED`、`PROFILE_BOOTSTRAP_VERIFY_PASSED`。其中 verify 阶段取消 `PIXELCAT_TEST_MODE`，以实际覆盖重启读档路径。

`git diff --check`：退出码 0。

## 尚未覆盖 / 风险

- 物理回归覆盖了真实 CharacterBody2D 绕行、停止放线后向外拉、猫端脱离、独立绳圈碰撞/到期及史莱姆扑击收招。闭环节点以固定的独立闭合多边形测试了保留和物理边界；尚未在实战场景中跑通一条会由真实动态路由自行形成闭环、随后成功结算并保留该闭环的完整端到端用例。
- 没有进行图形界面的手动游玩验收；输入映射通过项目设置读取，K 的停止行为通过战斗控制器处理函数及物理集成测试验证。
- Safe save 警告未能关联到具体目标文件，建议后续在可观察文件写入目标的环境中复查。

## 提交范围

只应提交上述源码、场景、测试、UID 与本报告。工作树中的 `Godot/` 是本机数据，不属于提交范围。目标仅为 `feature/yarn-physics-v3.1`；不得合并或推送到 `main`。
