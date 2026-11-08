# PixelCat Day 15 — 史莱姆果冻跳（程序动画 V1）

**基础分支**：`feature/day14-crafting`，沿用 Day 14 的合成、菜单和夜晚掉落，不改变 gameplay 规则。

## 演出设计

史莱姆仍然只有四方向 64×64 单帧贴图，动画通过 Sprite2D 的局部位置、缩放，以及位于角色后面的独立地面阴影表现：

- **待机**：1.2 秒微弱呼吸，身体尺寸变化不超过约 2.5%。
- **巡逻**：0.43 秒一个小跳，幅度为标准跳跃的 80%。
- **追击**：0.32 秒一个较快的果冻跳，幅度为 112%。
- **标准跳跃曲线**：0% 正常 → 14% 压扁蓄力 → 30% 伸长离地 → 53% 腾空顶点 → 72% 下落 → 83% 啪叽落地 → 93% 微弱反弹 → 100% 回到正常。
- **攻击前摇**：变宽压扁，沿用原有橙红色提示。
- **冲刺**：拉长、微微腾空，沿用冲刺颜色。
- **受击**：根据受击剩余时间快速压扁。
- **眩晕、毛线束缚**：变扁、不再正常跳动；束缚还会轻微扭动。
- **死亡**：先扁成一滩，之后用原有 0.28 秒缩小消失动画。
- **影子**：纯色、清晰像素边缘的扁椭圆，腾空时缩小并变浅，不用模糊或柔光。

参数都可以在 Slime Inspector 的 Jelly Animation 分类中调整：巡逻周期、追击周期、追击幅度、平滑强度。

## 技术原则

- `scripts/enemies/slime_jelly_motion.gd` 保存可单独测试的分段动画曲线。
- `scripts/enemies/slime_shadow.gd` 绘制并控制地面阴影。
- `scripts/enemies/slime.gd` 根据原有状态机决定动画目标值，再平滑驱动视觉节点。
- 仅改变 `Sprite2D.position/scale` 和 `JellyShadow.scale/modulate`；**不得改变 CharacterBody2D 位置、速度定义、碰撞体、攻击范围和判定**。
- 保留受击闪白、原有方向贴图和死亡缩小逻辑。
- 顺手修复 `_die()` 中原有的材料掉落空数组类型转换错误：在非探索状态死亡时，不再尝试把普通 Array 强转为 Array[Dictionary]。

## 已跑的 Godot 4.5.1 Headless 检查

- `tests/slime_jelly_animation.gd`：26 项通过（分段关键帧、方向、阴影、碰撞不变、不同状态视觉）。
- `tests/sticky_yarn_v4.gd`：通过；且不再出现 _die 的 Array[Dictionary] 脚本错误。
- `tests/v3_1_phases_04_to_06.gd`：通过。
- `tests/material_loot_integration.gd`：通过。
- `tests/crafting_manager.gd`：26 项通过。
- `tests/menu_flow.gd`：通过。

注意：Headless 的通过不等于 Windows 下的审美验收。请实际在夜晚看到史莱姆后观察：巡逻是否轻柔、追击是否有更明显弹跳、地面阴影是否贴合场景。也检查闪白、死亡以及和小猫碰撞时的姿态。

### 实机调整建议

初版分别设置巡逻 `0.43s`、追击 `0.32s`、最大腾空约 `7px × 1.12`；如觉得太快，请调整 Inspector 的周期，而不是修改攻击冷却时间。出现运动病/过度晃动时优先调低 `chase_hop_amplitude`。
