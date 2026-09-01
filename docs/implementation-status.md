# Windows / Godot MVP 实施状态

版本：0.1.0-mvp

文档日期：2026-09-01

分支：`windows-godot`

## 1. 当前结论

需求文档定义的 Windows 单机 MVP 已形成可运行闭环：

```text
主菜单 -> Stage -> 射击/施法/城墙 -> 胜负 -> 奖励 -> 升级 -> 下一关
```

产品名为《余烬守望 / Aegis of Ember》。实现受参考资料的信息层级启发，但没有复制或打包 `参考/` 下的图片；战场、敌人、城堡、技能效果和短音效均由项目代码原创生成，保持轻量且无需额外制作软件。

Windows 1.0 的 Power/Hurricane/Phantom 武器、Lava Moat、Magic Tower、完整四页研究树和 Honors 仍按需求文档保留为 MVP 验收后的扩展，不属于本次首版门禁。

## 2. 已落地模块

| 层 | 实现 |
|---|---|
| Core | 固定 tick RunModel、确定性 RNG、生成、连续坐标、箭矢扫掠碰撞、空间 band、技能、状态、Boss、胜负、奖励和事件 hash |
| Application | GameSession、RunOrchestrator、ContentService、SaveService、UpgradeService、ReplayService |
| Presentation | 启动恢复、主菜单、关卡选择、升级、设置、教学、战场、HUD、暂停、结算和原创 Canvas 视觉 |
| Infrastructure | JSON、原子文件替换、备份/迁移、InputMap、程序合成音效和音乐 |
| Content | 10 Stage、3 普通敌人、1 Boss、1 武器、3 技能、5 升级、中英文文本 |
| Tooling | 内容校验、构建清单、headless 测试、自动通关、性能和分辨率布局检查 |

## 3. 自动验证结果

2026-09-01 在 i5-8400、16GB、GTX 1060、Windows 11、Godot 4.7.2 上执行：

| 验证 | 结果 |
|---|---|
| `tests/run_all.gd` | 27 passed，0 failed |
| `tests/stage_autoplay.gd` | Stage 001～010 全部 victory；Stage 010 Boss death 恰好 1 次 |
| 新档首关基线 | 0 级升级自动玩家以 100% 城墙完成 Stage 001 |
| `tests/performance_stress.gd` | 100 敌人 + 200 投射物 + 9000 tick；最终独立回归平均 1.445 ms，p95 2.424 ms，总耗时 13.00 s |
| `tests/resolution_layout.gd` | MainMenu 与 Gameplay 在 1366×768、1920×1080、2560×1440 全部通过 |
| `tools/validate_content.gd` | config version 1、ruleset `aegis-mvp-v1` 校验通过 |

Windows 实际窗口还验证了 1280×720 下菜单/HUD 无裁切、鼠标拖动瞄准命中、火球扣除 Mana，以及暂停 2.2 秒期间敌人位置和城墙 HP 不变。

## 4. AT-001～AT-020 状态

| ID | 状态 | 证据或剩余工作 |
|---|---|---|
| AT-001 | 已实现，需最终玩家计时 | 首次教学覆盖瞄准、按住射击、1/2/3 施法；教学打开时模拟暂停 |
| AT-002 | 通过 | 实际鼠标瞄准命中；按住/松开命令和箭矢属性测试通过 |
| AT-003 | 通过 | `run_all.gd` 验证 Mana 不足不生成效果且不扣费 |
| AT-004 | 通过 | 城墙归零只发出一次 defeat，结束后 step 不再结算 |
| AT-005 | 通过 | 自动通关 10 Stage；结算和下一关解锁接入 Profile |
| AT-006 | 通过 | 自动测试验证失败局保留 7 击杀金币且没有通关奖励 |
| AT-007 | 通过 | 重复 `run_id + reward_version` 不重复发奖 |
| AT-008 | 基础机制通过 | 临时文件、flush、重新读取、主备替换和坏主档恢复均有磁盘测试；最终发布前再做进程强杀人工测试 |
| AT-009 | 通过 | v1→v3 迁移；不支持 schema 会回退有效备份 |
| AT-010 | 通过 | 固定 seed/命令生成相同事件 SHA-256 |
| AT-011 | 通过当前门禁 | 5 分钟等价 9000 tick 压力场景 p95 2.424 ms；60 分钟内存 soak 留在发布候选阶段 |
| AT-012 | 已实现，需发布包复核 | 窗口、无边框、全屏和分辨率设置即时生效；逻辑坐标不随物理窗口改变 |
| AT-013 | 通过 | 三目标分辨率、两场景布局自动检查无越界 |
| AT-014 | 通过 | 强制 Fatal Blow 为基础箭伤的精确 2 倍并保留文字/声音反馈 |
| AT-015 | 通过 | Stage 010 自动通关只产生 1 次 Boss death 和 1 次结算 |
| AT-016 | 通过 | 重复敌人 ID 返回 `enemies[1].id / duplicate_id` |
| AT-017 | 通过 | 生产脚本静态检查无 HTTP/WebSocket/TCP/ENet 客户端依赖 |
| AT-018 | 通过 | Core 静态检查无 Node、SceneTree、Input、FileAccess、AudioServer 或 Time 依赖 |
| AT-019 | 待模板 | 导出预设和清单已就绪；因用户要求不安装 export templates，EXE/PCK 尚未生成 |
| AT-020 | 代码路径通过，需发布包复核 | 所有写入使用 `user://`，不要求管理员权限；待 EXE 在普通用户账户复核 |

## 5. 当前发布阻塞项

本机 `%APPDATA%\Godot\export_templates` 目录为空。Godot 导出诊断准确报告缺少：

```text
4.7.2.stable/windows_debug_x86_64.exe
4.7.2.stable/windows_release_x86_64.exe
```

这是遵循用户“先装软件、不装模板”要求的预期状态，不是代码错误。获得安装模板授权后，最后步骤是：

1. 安装官方 Godot 4.7.2 export templates。
2. 重新运行所有自动测试和构建清单。
3. 导出 Debug/Release EXE/PCK。
4. 在未安装 Godot的普通 Windows 用户环境运行并执行 AT-019、AT-020。
5. 完成 60 分钟 soak 和发布 ZIP/许可审阅。
