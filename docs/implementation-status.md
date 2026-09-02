# Windows / Godot MVP 实施状态

版本：0.1.0-mvp

文档日期：2026-09-02

分支：`windows-godot`

## 1. 当前结论

需求文档定义的 Windows 单机 MVP 已形成可运行源码闭环：

```text
主菜单 -> Stage -> 射击/施法/城墙 -> 胜负 -> 奖励 -> 升级 -> 下一关
```

产品名为《余烬守望 / Aegis of Ember》。实现受参考资料的信息层级启发，但没有复制或打包 `参考/` 下的图片；战场、敌人、城堡、技能效果和短音效均由项目代码原创生成，保持轻量且无需额外制作软件。

MVP 源码门禁 AT-001～AT-018 已通过。无需模板的 PCK 资源收集、内容排除、清单一致性和隔离启动预检也已通过。AT-019、AT-020 仍需要实际 Windows EXE/PCK 对和便携 ZIP，当前受“不要安装 export templates”的明确约束以及项目许可尚未选定而保持待办，不能用编辑器或 PCK 预检代替最终发布包结论。

Windows 1.0 的 Power/Hurricane/Phantom 武器、Lava Moat、Magic Tower、完整四页研究树和 Honors 仍按需求文档保留为后续范围，不属于本次 MVP 发布门禁。

## 2. 已落地模块

| 层 | 实现 |
|---|---|
| Core | 固定 30 tick RunModel、注入式确定性 RNG、连续坐标、生成、扫掠碰撞、空间 band、技能、状态、击退/抗性、Boss 特殊行为、确定性同 tick 裁决、奖励来源/版本/幂等键和事件 hash |
| Application | GameSession、RunOrchestrator、ContentService、SaveService、UpgradeService、ReplayService；结算、购买、教学和设置采用“先持久化、后提交内存”的事务边界 |
| Presentation | 启动恢复、主菜单、关卡选择、升级及前置条件、设置、教学、战场、HUD、暂停、快捷设置、结算、保存失败重试和原创 Canvas 视觉 |
| Infrastructure | JSON、临时写入/校验/原子替换、备份/迁移、InputMap、程序合成音效、本地轮转日志和手动诊断 ZIP |
| Content | 10 Stage、3 普通敌人、1 Boss、1 武器、3 技能、5 升级、中英文文本、难度倍率/上限和配置化生成规则 |
| Tooling | 内容校验、Godot 许可声明生成、构建清单、headless 回归、自动通关、事务/输入/诊断/教学/设置/布局验收、崩溃恢复、压力/浸泡和真实窗口运行检查 |

## 3. 最终自动验证结果

2026-09-02 在 i5-8400、16GB、GTX 1060、Windows 11、Godot 4.7.2 上执行：

| 验证 | 结果 |
|---|---|
| 编辑器载入与 PowerShell 解析 | Godot headless editor 完整扫描项目并正常退出；全部 `.ps1` 语法解析通过 |
| `tools/validate_content.gd` | config version 2、ruleset `aegis-mvp-v2` 校验通过 |
| `tests/run_all.gd` | 44 passed，0 failed；覆盖确定性、同 tick 败局裁决、存档/迁移/恢复修复、奖励永久幂等、升级前置、配置化数值和本地化完整性 |
| `tests/stage_autoplay.gd` | Stage 001～010 全部 victory；新档 0 级升级完成 Stage 001 时城墙为 100%；Stage 010 Boss death 恰好 1 次 |
| `tests/tutorial_acceptance.gd` | 首次教学暂停模拟、瞄准、按住连续射击、松开停止和施法；8/8 通过，最终回归耗时 849 ms |
| `tests/settings_acceptance.gd` | 设置即时保存；低/中/高质量采用不同背景、特效和飘字预算；震动开关与 UI 缩放即时生效，8/8 通过 |
| `tests/application_transaction_acceptance.gd` | 结算、升级、教学和设置保存失败时不提交不一致内存状态，4/4 通过 |
| `tests/inputmap_acceptance.gd` | 射击、施法和暂停均经 InputMap；暂停会释放持续射击，6/6 通过 |
| `tests/diagnostic_acceptance.gd` | 本地日志字段白名单、大小/数量轮转、无路径/Profile 数据和手动 ZIP，10/10 通过 |
| `tools/run_save_crash_acceptance.ps1` | `profile.json.tmp` 已写入 100,663,600 bytes 时强杀确切 PID；重启读取 generation 1 有效主档，不形成损坏恢复循环 |
| `tests/performance_stress.gd` | 100 敌人 + 200 投射物 + 9,000 tick（逻辑 5 分钟）；平均 1.017 ms，p95 1.224 ms，总耗时 9.16 s |
| `tests/long_soak.gd` | 108,000 tick（逻辑 60 分钟）；p95 1.219 ms；内存 25.74→28.91 MiB、增长 3.17 MiB、峰值 29.45 MiB；节点 3→3 |
| `tests/resolution_layout.gd` | zh_CN/en_US × 1366×768/1920×1080/2560×1440 × 菜单/战斗 9 种状态，共 54 组全部通过 |
| `tests/window_mode_acceptance.gd` | 真实窗口下窗口、无边框、全屏、准星映射和 1920×1080 逻辑画布 7/7 通过 |
| `tools/run_windows_runtime_acceptance.ps1` | Compatibility/GTX 1060：平均 408.25 FPS、帧时 p95 3.05 ms、进程峰值工作集 194.75 MiB；5 次启动平均 1.510 s、最慢 1.728 s |
| `tools/run_pack_preflight.ps1` | 不安装模板生成约 143 KiB PCK；7 个必需资源存在、7 个测试/工具/文档/参考路径排除，manifest Git SHA/config hash 一致；从源码目录外及隔离 `%APPDATA%` 启动成功 |
| 静态边界检查 | 生产源码无 HTTP/WebSocket 客户端；表现层无硬编码 `KEY_`/`button_index`，无直接修改 Profile；Core 不依赖 SceneTree/Input/FileAccess/表现节点 |

真实运行使用非管理员进程完成，游戏的所有持久写入均位于 `user://`。这证明源码路径不要求提权，但 AT-020 仍需在未安装 Godot 的普通用户环境用发布 EXE 复核。

## 4. 需求追踪

| 需求 | 状态 | 实现与证据 |
|---|---|---|
| FR-001～FR-005 启动/存档/设置 | MVP 源码通过 | 默认档和唯一安装 ID、事务保存、主档/备份/损坏副本、v1→v3 迁移、即时设置与失败回滚 |
| FR-010～FR-014 菜单/Stage/结算 | MVP 源码通过 | 无占位入口、已解锁/重玩/奖励预览、确定性胜负、完整结算字段、暂停/确认退出 |
| FR-020～FR-024 战场/输入/反馈 | MVP 源码通过 | 连续 2D 坐标、InputMap、缩放准星、持续射击、三法术目标校验、文字/形状/音频复合反馈 |
| FR-030～FR-050 武器/技能/城墙 | MVP 源码通过 | 配置化 Strength/Agility、基础弓快照、Power Shot 击退、2× Fatal、火冰雷、Mana 和城墙 |
| FR-051 后续防御设施 | 按范围后置 | Lava Moat、Magic Tower 属于 Windows 1.0，不阻塞 MVP |
| FR-060～FR-064 敌人/生成/Boss | MVP 源码通过 | 3 种普通敌人、1 Boss、固定 seed 生成、难度维度及上限、Boss 预警/特殊行为/唯一死亡事件 |
| FR-070～FR-073 经济/升级 | MVP 源码通过 | coins/xp、来源/规则版本/幂等键、5 项升级的效果/价格/前置/上限、永久奖励账本 |
| FR-080～FR-083 配置/随机/回放 | MVP 源码通过 | v2 JSON 规则真源、启动/构建校验、注入 seed/run ID、命令日志和事件 SHA-256 |
| NFR-001～NFR-009 | 本机源码通过 | 性能、启动、60 分钟稳定性、离线、可靠性、分层、可复现、可访问性和双语均有自动证据 |
| NFR-010 构建 | 部分通过 | 构建脚本及 manifest 字段已实现，manifest 已进入并通过 PCK 一致性检查；发布 EXE/PCK 对未生成 |
| NFR-011～NFR-012 | 源码通过 | 不采集/上传数据；无 Asset Library addon 或生产第三方插件 |

## 5. AT-001～AT-020 状态

| ID | 状态 | 证据或剩余工作 |
|---|---|---|
| AT-001 | 通过 | 首玩脚本覆盖暂停说明、瞄准、连续射击、松开和施法，最终回归 849 ms 内完成 |
| AT-002 | 通过 | InputMap 按住/移动/松开命令和箭矢属性测试通过；真实窗口准星映射通过 |
| AT-003 | 通过 | Mana 不足、冷却中和非法目标均不生成效果且不错误扣费 |
| AT-004 | 通过 | 城墙归零只发出一次 defeat，结束后 step 不再结算；同 tick 最后一杀与城墙归零固定裁决为失败 |
| AT-005 | 通过 | 自动通关 10 Stage；结算、奖励和下一关解锁接入 Profile 事务 |
| AT-006 | 通过 | 失败局保留击杀金币且不发通关奖励 |
| AT-007 | 通过 | `run_id + reward_version` 永久账本阻止重复奖励，超过 200 条后旧键仍有效 |
| AT-008 | 通过 | 临时档写入期间强杀确切 Godot PID，重启由主档或备份恢复有效 generation |
| AT-009 | 通过 | v1→v3 逐级迁移；不支持 schema 回退备份；损坏主档修复后不形成恢复循环 |
| AT-010 | 通过 | 固定 seed/命令产生一致事件 SHA-256；独立真实局使用唯一 run ID |
| AT-011 | 通过 | 逻辑 5 分钟压力 p95 1.224 ms；60 分钟等价 soak 无节点增长，内存最终约 29 MiB |
| AT-012 | 通过 | 真实 Windows 窗口的窗口、无边框、全屏和准星逻辑坐标映射 7/7 通过 |
| AT-013 | 通过 | 中英文、三目标分辨率、菜单/战斗 9 种状态共 54 组布局无越界 |
| AT-014 | 通过 | 强制 Fatal Blow 为基础箭伤的精确 2 倍并保留文字/声音反馈 |
| AT-015 | 通过 | Stage 010 自动通关只产生 1 次 Boss death 和 1 次结算 |
| AT-016 | 通过 | 重复敌人 ID 返回字段路径 `enemies[1].id` 和错误码 `duplicate_id` |
| AT-017 | 通过 | 完整单机流程无网络依赖；生产脚本静态检查无 HTTP/WebSocket 客户端 |
| AT-018 | 通过 | Core 静态检查无 Node、SceneTree、Input、FileAccess、AudioServer 或 Time 依赖 |
| AT-019 | PCK 预检通过，待 EXE | 无模板 PCK 已生成、检查并隔离启动；按用户要求未安装 export templates，项目许可文件尚未确定，正式 EXE/PCK 对尚未生成 |
| AT-020 | 源码路径通过，待发布包 | 当前非管理员进程和 `user://` 写入路径通过；仍需发布 EXE 在未安装 Godot 的普通用户环境复核 |

## 6. 当前发布阻塞项与下一步

PCK 预检脚本已经证明资源过滤、manifest 和包内启动路径有效。正式构建脚本会先检查干净 Git、内容、核心测试、10 Stage、Godot/第三方许可声明和项目许可，再生成带 Godot 版本、Git SHA、配置版本/hash、UTC 时间的清单并导出。当前仍有两个主动门禁：

1. 本机没有 Godot 4.7.2 的 `windows_debug_x86_64.exe` / `windows_release_x86_64.exe` export templates；这是遵循用户“不安装模板”的预期状态。
2. `release/GAME_LICENSE.txt` 尚不存在；项目发布许可必须由项目所有者选择，不能由实现者代替授权。

解除后依次执行：

1. 安装与 Godot 4.7.2 完全匹配的官方 export templates。
2. 确定项目代码/原创资产许可并创建 `release/GAME_LICENSE.txt`。
3. 运行 `tools/build_windows.ps1 -Configuration Release`，生成 EXE/PCK 和带许可声明的便携 ZIP。
4. 在未安装 Godot 的普通 Windows 用户环境执行 AT-019、AT-020。
5. 用独立最低目标配置复核冷启动、Compatibility 渲染和 60 分钟稳定性。

在这两个门禁解除前，项目可以继续通过 Godot 标准版直接开发、运行和测试，但不能宣称 Windows 发布包已经验收。
