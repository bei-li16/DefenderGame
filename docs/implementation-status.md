# Windows / Godot 实施状态

版本：1.0.2-windows

文档日期：2026-09-04

分支：`windows-godot`

2026-09-04 参照 `参考/` 目录 Defender II 官方与实机截图完成一轮界面迭代：战斗 HUD 顶部新增关卡进度条(⚔→💀,按出怪进度填充),城墙(红)与魔力(蓝)双条移至左下角并带图标,技能按钮改为右下角圆形金环按钮(冷却弧形扫面 + 魔力不足红色提示);研究页从列表卡片改为经典树形布局(前置连线箭头 + 节点等级 + 底部详情面板:名称/描述/当前→下级效果/升级按钮)。

2026-09-04 第二轮 `参考/` 界面迭代(Status / Stage Complete / Honor 弹窗)：新增玩家等级系统(第 N 级需 100×N 经验,由 XP 实时推导,存档免迁移)；主菜单顶栏显示 `Lv.N` 与经验进度条；荣誉页新增生涯战绩行(胜/负/胜率,`battles_won`/`battles_lost` 自结算起计)与每项成就的进度条 + 奖励预览；结算面板新增 Stage Complete 式等级进度条,升级时显示 `Lv.A → B`。回归 90/90 通过,实机验证败局正确计入 `battles_lost` 且 `Lv.20 → 21` 升级提示与进度数值与存档一致。

## 0. Windows 1.0 内容(2026-09-03 落地)

需求文档 §4 的 Windows 1.0 内容已全部落地(Battle 联机按需求明确另立项目阶段,不在本次范围):

| 内容 | 落地 |
|---|---|
| Stage | 10 → **30** 个线性 Stage,含 3 个 Boss 关(10/20/30) |
| 敌人 | 3 → **6 类普通敌人**(新增重甲 armored_guard、飞行 sky_harrier、萨满 ember_shaman)+ **3 个 Boss**(余烬督军 war_cry、霜痕巨人 frost_nova、风暴女王 storm_surge) |
| 武器 | 基础弓 → **4 把**(震击长弓高击退、飓风长弓三连射、幻影长弓穿透+高致命),按关卡进度解锁,武器库界面切换 |
| 防御 | 城墙 → +**熔岩护城河**(近城范围灼烧+点燃)与**魔法塔**(自动狙击最近敌);等级来自防御页研究 |
| 成长 | 5 项升级 → **四页研究树 18 项**(攻击/魔法/防御/效用),含 Mana 上限、回复、技能半径、冷却、城墙护甲/加固、金币/经验加成 |
| Honors | 新增 **8 项成就**,结算时按生涯统计解锁并一次性发奖,主菜单荣誉页展示 |
| 难度 | HP/伤害双上限 → **HP/伤害/速度/数量四维**缩放与上限;高 Stage 实际触发上限 |
| 存档 | schema v3 → **v4**(武器/统计/荣誉字段,逐级迁移) |
| 容错 | 发布包内置**回退内容包**(`game_rules_fallback.json` + `localization_fallback.json`),主配置损坏时回退有效配置(FR-081);开发构建坏配置直接阻断启动 |

关键设计决定:

- **奖励账本改为永久全量**:移除 MVP 审计引入的 512 窗口上限(`audit-report.md` C-2 的正式接受项允许在 1.0 引入全量结构)。1.0 的生涯统计使长期重玩成为常态,永久账本以 ~100B/局的增长换取任意历史 run 幂等,测试断言最旧键永久有效。
- **霜痕巨人 frost_nova 冻结防御设施**(熔岩河/魔法塔进入 `special_freeze_ticks` 冷却)而非攻击城墙:对高防御构筑形成真实威胁,且不绕过城墙护甲语义。
- **敌方攻击仍为“驻停后周期伤害”抽象**(审计 C-9):1.0 防御设施设计不含拦截敌方投射物玩法,无需实体化;若后续加入拦截玩法再按 C-9 决议实体化。
- **headless/脚本运行与真实存档隔离**:`GameApp` 检测到 `--script` 启动时把默认存档目录重定向到 `user://automated-app-data/` 并清空,杜绝测试套件触碰玩家真实存档(本次排查发现的真问题:此前套件会在迁移时改写真实 profile)。

1.0 验证证据(2026-09-03,i5-8400 / GTX 1060 / Godot 4.7.2):

| 验证 | 结果 |
|---|---|
| `tools/validate_content.gd` | config v3 / ruleset aegis-windows-v1 通过;回退内容包同样通过完整校验 |
| `tests/run_all.gd` | **70 passed, 0 failed**(新增武器齐射/穿透/锁定回退、防御设施开火/冷却/未研究不生效、冰霜新星冻结、Mana 上限/城墙护甲/金币加成/冷却缩减/技能半径等 14 项断言) |
| `tests/stage_autoplay.gd` | **30/30 victory**,0 failures;3 个 Boss 各恰好 `boss_deaths=1`;满配档全程 100% 城墙 |
| 其余套件 | tutorial 8/8、settings 8/8、transaction 4/4、inputmap 6/6、diagnostic 10/10、resolution_layout 双语×3 分辨率 0 失败、window_mode 7/7 |
| `tests/performance_stress.gd` | p95 1.56 ms(预算 <10 ms) |
| `tests/long_soak.gd` | 60 逻辑分钟内存平稳(29.95 MiB),节点无增长 |
| 真实玩家游玩 | 同日玩家会话连续通关 Stage 001→021(含两个 Boss 关),生涯统计/荣誉解锁/武器解锁/存档迁移在生产路径全部生效(诊断日志 `run_settled` 序列佐证) |

## 0.1 交互模型更新(2026-09-04,FR-022/FR-023 v3.1)

- **悬停自动射击**:光标悬停战场即自动连续开火(`Viewport.gui_get_hovered_control()` 为 null 时),移入 HUD/覆盖层、选中法术、拖拽施法或暂停即停;边沿驱动,不逐帧重复发命令。设置 `auto_fire` 可关闭并回退按住左键射击。
- **拖拽施法**:选中技能后按住左键拖拽,光标处实时绘制范围指示圈(合法性按目标边界/Mana/冷却红绿着色),松开在释放点施放;在 UI 上松开或右键/Esc 取消。释放检测轮询物理按键状态,覆盖释放事件被 UI 消耗的路径。
- 验证:`inputmap_acceptance` 9/9(经典按住射击 + 悬停开火 + 拖拽施法/取消全路径);真实 Viewport 输入管线探测确认按键选择与拖拽施法入队正确;生产路径实证——连续 4 局无人值守对局(无按键按下,仅悬停)击杀数持续增长(425→431→436→442),回放日志每局恰好 1 次 `fire_started` + 连续 aim,符合边沿驱动设计。

## 1. 当前结论(MVP 基线)

需求文档定义的 Windows 单机 MVP 已形成可运行源码闭环：

```text
主菜单 -> Stage -> 射击/施法/城墙 -> 胜负 -> 奖励 -> 升级 -> 下一关
```

产品名为《余烬守望 / Aegis of Ember》。实现受参考资料的信息层级启发，但没有复制或打包 `参考/` 下的图片；战场、敌人、城堡、技能效果和短音效均由项目代码原创生成，保持轻量且无需额外制作软件。

MVP 门禁 AT-001～AT-020 已在当前 Windows 开发机通过。Godot 4.7.2 官方 Windows x86_64 模板已安装，项目采用 `Copyright (c) 2026 bei-li16` 的 MIT 许可；正式 Release 已生成独立 EXE/PCK 和便携 ZIP，并从全新解压目录以非管理员进程完成包内容、清单、图形启动及 `user://` 写入验收。

Windows 1.0 的 Power/Hurricane/Phantom 武器、Lava Moat、Magic Tower、完整四页研究树和 Honors 已于 2026-09-03 全部落地(见 §0),Release 包 `Aegis-of-Ember-1.0.0-Windows-x64.zip` 已通过全部门禁重建。

## 2. 已落地模块

| 层 | 实现 |
|---|---|
| Core | 固定 30 tick RunModel、注入式确定性 RNG、连续坐标、生成、扫掠碰撞、空间 band、技能、状态、击退/抗性、Boss 特殊行为、确定性同 tick 裁决、奖励来源/版本/幂等键和事件 hash |
| Application | GameSession、RunOrchestrator、ContentService、SaveService、UpgradeService、ReplayService；结算、购买、教学和设置采用“先持久化、后提交内存”的事务边界 |
| Presentation | 启动恢复、主菜单、关卡选择、升级及前置条件、设置、教学、战场、HUD、暂停、快捷设置、结算、保存失败重试和原创 Canvas 视觉 |
| Infrastructure | JSON、临时写入/校验/原子替换、备份/迁移、InputMap、程序合成音效、本地轮转日志和手动诊断 ZIP |
| Content | 10 Stage、3 普通敌人、1 Boss、1 武器、3 技能、5 升级、中英文文本、难度倍率/上限和配置化生成规则 |
| Tooling | 内容校验、Godot 声明及项目许可生成、构建清单、headless 回归、自动通关、事务/输入/诊断/教学/设置/布局验收、崩溃恢复、压力/浸泡、真实窗口运行、PCK 预检和导出 EXE 普通用户验收脚本 |

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
| `tools/run_pack_preflight.ps1` | 生成约 143 KiB PCK；7 个必需资源存在、8 个测试/工具/文档/许可模板/参考路径排除，manifest Git SHA/config hash 一致；从源码目录外及隔离 `%APPDATA%` 启动成功 |
| `tools/set_game_license.ps1` | MIT/Proprietary 模板、占位符替换及防覆盖门禁通过；最终采用 `Copyright (c) 2026 bei-li16` 的 MIT 许可 |
| `tools/check_release_readiness.ps1` | 分支、提交、工作树、Godot、导出预设、声明、项目许可、Debug/Release 模板、非管理员状态和 PCK 预检共 12/12 就绪，blockers=0 |
| `tools/build_windows.ps1 -Configuration Release` | 内容、44 项核心回归、10 Stage、许可、PCK 和模板门禁通过；生成独立 EXE/PCK 及仅含 5 个预期文件的便携 ZIP |
| ZIP 独立解压验收 | 实际 EXE/PCK 从全新目录以非管理员进程启动，退出码 0；Compatibility/OpenGL 3.3 识别 GTX 1060，隔离用户目录生成 `profile.json`、`settings.json` |
| 静态边界检查 | 生产源码无 HTTP/WebSocket 客户端；表现层无硬编码 `KEY_`/`button_index`，无直接修改 Profile；Core 不依赖 SceneTree/Input/FileAccess/表现节点 |

真实运行使用非管理员进程和 ZIP 内的实际发布 EXE 完成，游戏的所有持久写入均位于 `user://`；启动过程不调用已安装的 Godot 编辑器或控制台。面向外部公开分发前，仍建议在另一台未安装 Godot 的最低目标配置电脑上补做兼容性抽检，但它不再是当前本机 Release 构建的阻塞项。

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
| NFR-010 构建 | 通过 | Release EXE/PCK 和 ZIP 已生成；包内 manifest 的 Godot 版本、Git SHA、配置版本和配置 hash 通过一致性检查 |
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
| AT-019 | 通过 | 正式 Windows x86_64 EXE/PCK 和 ZIP 已生成；实际 PCK 的资源边界、manifest Git SHA/config hash、全新解压目录启动及图形 Compatibility 渲染均通过 |
| AT-020 | 通过 | ZIP 内实际 EXE 由非管理员进程直接启动，不调用编辑器；`profile.json`、`settings.json` 仅写入隔离的 `%APPDATA%\Godot\app_userdata\Aegis of Ember` |

## 6. 发布结果与后续兼容性抽检

当前本机没有发布阻塞项。正式构建产物位于被 Git 忽略的 `Builds/`：

1. `Builds/Windows/DefenderGame.exe` 与 `DefenderGame.pck`。
2. `Builds/Aegis-of-Ember-0.1.0-Windows-x64.zip`。
3. ZIP 只包含 EXE、PCK、`README.txt`、`GAME_LICENSE.txt` 和 `GODOT_COPYRIGHT.txt`。

为减小本机负担，仅从官方 4.7.2 模板包安装了 `windows_debug_x86_64.exe` 和 `windows_release_x86_64.exe`（合计约 203 MiB）；约 1.19 GiB 的完整下载包在 SHA-512 校验和提取成功后已删除。Android、iOS、Web、Linux 和 macOS 模板均未安装。

下一步不是继续安装开发软件，而是进行外部兼容性抽检：在另一台未安装 Godot、接近最低目标配置的 Windows 10/11 x64 电脑上直接解压 ZIP，复核冷启动、输入、Compatibility 渲染、存档权限和 60 分钟稳定性。若准备公开发布，还应补充图标、签名与发行渠道元数据；这些不影响当前 MVP 功能闭环。
