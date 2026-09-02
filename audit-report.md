# 《Aegis of Ember / 余烬守望》实现内容审计报告

| 项 | 值 |
|---|---|
| 审计分支 | `audit/windows-godot`（自 `windows-godot` @ `a818816` 拉出） |
| 审计日期 | 2026-09-03 |
| 审计依据 | `docs/defender-ii-requirements.md`（v3.0）、`docs/defender-ii-software-architecture.md`（v3.0）、`docs/implementation-status.md`、`参考/`（Defender II 图片参考库与来源清单） |
| 验证环境 | Windows 11、Godot 4.7.2 stable（本机 `D:\Software\Godot-4.7.2\`），headless 模式 |
| 审计方式 | 全量通读 `src/`（约 5,807 行 GDScript）与 `content/` 配置；逐条对照 FR/NFR/AT；实机复跑关键验证脚本 |

---

## 1. 结论摘要

**总体判定：MVP 实现与需求文档、架构文档高度一致，文档声明的验证结果全部可复现，无发布阻塞项。** 需求追踪矩阵中 FR-001～FR-083 的 MVP 条目全部有实现与测试证据，FR-051/FR-032 部分内容按范围门禁正确后置。发现的问题集中在三个层面：**架构文档与实现的两处表述性偏差**（均为合理简化但文档未更新）、**若干可延后清理的代码卫生项**（死代码、无界账本、回放日志噪声），以及**面向 Windows 1.0 的结构性准备**（大文件拆分、快照成本、难度曲线偏保守）。

本次审计实际复跑的验证：

| 验证 | 结果 |
|---|---|
| `tests/run_all.gd` | **44 passed, 0 failed**（含确定性、同 tick 败局裁决、存档迁移/恢复、幂等、升级原子性、Core 依赖静态检查、无网络依赖检查） |
| `tools/validate_content.gd` | 通过，`config_version=2`、`ruleset=aegis-mvp-v2` |
| `tests/stage_autoplay.gd` | Stage 001～010 **全部 victory**，0 failures；Stage 010 Boss `boss_deaths=1`；新档 Stage 001 城墙 100% |
| 本地化完整性（审计脚本） | zh_CN / en_US 各 104 个 key，**双向无缺失** |
| 发布产物 | `Builds/Windows/DefenderGame.exe` + `.pck` 与便携 ZIP 在本地存在（Git 忽略，不入库） |

---

## 2. 需求追踪审计（FR-001 ～ FR-083）

状态口径：**通过** = 有实现代码且有对应测试证据；**后置** = 按需求 §1.4/§4 范围门禁排除在 MVP 外，且 UI 未暴露占位入口。

### 2.1 启动、档案与设置

| 需求 | 状态 | 审计证据与备注 |
|---|---|---|
| FR-001 首次启动 | 通过 | `game_app.gd:235` 生成含唯一 `install_id`（Crypto 随机 16 字节）的默认档；初始化失败走 `bootstrap.gd` 恢复界面，提供重试/新档/退出三选项，坏内容时禁用"新档"按钮（`bootstrap.gd:63`） |
| FR-002 本地存档 | 通过 | `save_service.gd:32` 实现临时文件 → 回读校验 → 旧主档转 `.bak` → 原子改名 → 最终复验，任一步失败回滚并保留备份 |
| FR-003 存档恢复 | 通过 | `save_service.gd:82` 主档缺失/解析失败/hash 不符时尝试 `.bak`；损坏文件保留为 `.corrupt-<时间戳>` 诊断副本（`_preserve_corrupt`），不形成覆盖循环（有专项测试 PASS） |
| FR-004 版本迁移 | 通过 | `save_service.gd:142` v1→v2→v3 逐级迁移，内存副本上完成，失败不覆盖旧档；不支持的 schema 回退备份 |
| FR-005 设置 | 通过 | 主音量/音乐/音效/语言/全屏/无边框/分辨率/画质/瞄准辅助/震动/UI 缩放全部存在（`game_app.gd:250`、`main_menu.gd:250`）；`update_setting` 先生效后保存、失败回滚（`game_app.gd:195`） |

### 2.2 菜单与 Stage

| 需求 | 状态 | 审计证据与备注 |
|---|---|---|
| FR-010 主菜单 | 通过 | `main_menu.gd:117` 仅有继续/选关/升级/设置/教学/退出，无灰色占位按钮；锁定关与满级升级的禁用属于状态语义而非未实现占位 |
| FR-011 Stage 选择 | 通过 | `main_menu.gd:140` 显示编号、Boss ⚠ 标记、最佳结果（城墙%/击杀）、锁定态或奖励预览；解锁门控来自 `highest_unlocked_stage`（`run_orchestrator.gd:9` 服务层双重校验） |
| FR-012 Stage 胜负 | 通过 | `run_model.gd:527` 同 tick 先判败后判胜（固定裁决为失败，专项测试 PASS）；胜利条件 = 生成队列耗尽且敌人清空 |
| FR-013 结算 | 通过 | `gameplay.gd:426` 显示胜负/Stage/波次/击杀/城墙%/金币/XP/新解锁；失败局击杀金币保留（`run_model.gd:149` result 不含 clear_reward 当失败时） |
| FR-014 暂停与退出 | 通过 | Esc 暂停 → 继续/重开/快捷设置/返回菜单（`gameplay.gd:324`）；返回菜单有确认对话框；暂停即发 `fire_stopped`，退出不触发奖励（结算仅由 `run_finished` 事件驱动） |

### 2.3 战斗场景与输入

| 需求 | 状态 | 审计证据与备注 |
|---|---|---|
| FR-020 战场 | 通过 | 城堡在左（`world.castle_x_milli=210000`），敌人从右侧连续 y ∈ [250000, 920000] 进入（seeded 随机，无 lane）；远程敌人在 `attack_x=720000` 处驻停 |
| FR-021 瞄准 | 通过 | `gameplay.gd:62` 鼠标 → 每物理 tick `aim` 命令（ milli 坐标）；真实窗口准星映射有 7/7 验收 PASS。注：实现直接用 viewport 坐标，未走架构文档所述 Camera2D（见 §4 偏差 A-1） |
| FR-022 连续射击 | 通过 | `run_model.gd:255` 按住持续产箭、每箭取当前瞄准方向；松开/暂停/死亡/离开场景均停止（暂停发 `fire_stopped`，结算后 `step` 不再执行） |
| FR-023 法术输入 | 通过 | 1/2/3 选火/冰/雷、左键施放、右键取消（Esc 在选技能时优先取消、否则暂停，`gameplay.gd:94`）；Mana 不足/冷却/越界目标均 `skill_rejected` 且不扣费（专项测试 PASS） |
| FR-024 反馈 | 通过 | 文字飘字 + 形状特效 + 屏幕震动 + 程序合成音效复合反馈；`skill_rejected`/`wall_damage`/`boss_warning` 均有文字提示，不只依赖颜色 |

### 2.4 武器、技能与防御

| 需求 | 状态 | 审计证据与备注 |
|---|---|---|
| FR-030 Strength | 通过 | `run_model.gd:296` 箭矢伤害在生成时按当时 Strength 等级快照，飞行中不变 |
| FR-031 Agility | 通过 | `run_model.gd:319` 射击间隔 = `max(min_interval_ticks, base - Agility×effect)`，下限来自配置 |
| FR-032 武器 | 通过（MVP 部分） | 仅 `basic_bow`，数据结构已含 `pierce`/`knockback` 字段为 1.0 扩展留位；Power/Hurricane/Phantom 按需求明确属于 1.0 |
| FR-033 Power Shot | 通过 | 12% 概率击退，受 `knockback_resistance_permille` 抵抗（Boss 1000% 完全免疫），并 clamp 在 `[attack_x, spawn_x]` 边界内（`run_model.gd:455`） |
| FR-034 Fatal Blow | 通过 | 8% 概率最终伤害精确 ×2（`fatal_multiplier=2`），显示"致命一击！/Fatal Blow!"，无一击必杀默认行为 |
| FR-040 元素技能 | 通过 | 火球=范围伤害+燃烧 DoT；冰刺=范围伤害+减速 45%+冻结；雷击=范围内最近 4 目标+眩晕；全部数值配置驱动 |
| FR-041 Mana | 通过 | `clampi(mana, 0, max_mana)`（`run_model.gd:341`）；自然恢复 1/15 tick，施法扣费、冷却独立 |
| FR-050 城墙 | 通过 | HP 显示于 HUD 与结算；敌人到达攻击点按各自间隔造成伤害；归零后 `_resolve_run_end` 置 DEFEAT，`step` 后续返回空（只结算一次） |
| FR-051 后续防御设施 | 后置 | Lava Moat / Magic Tower 属于 Windows 1.0，代码无残留占位 |

### 2.5 敌人、波次与 Boss

| 需求 | 状态 | 审计证据与备注 |
|---|---|---|
| FR-060 敌人模型 | 通过 | 模板含 HP/速度/伤害/攻击间隔/护甲/攻击点/标签/状态抗性/击退抗性/碰撞半径，全部配置化 |
| FR-061 敌人模板 | 通过 | `melee_basic`/`fast_raider`/`ranged_hexer` + Boss `ember_warlord`，共 4 模板 |
| FR-062 生成 | 通过 | `_build_spawn_queue`（`run_model.gd:174`）按 Stage 配置 + 独立 `_spawn_rng` 预生成队列，同 seed 顺序一致 |
| FR-063 难度曲线 | 通过 | HP +75%/关、伤害 +45%/关，分别有上限 1750‰/1450‰（`run_model.gd:206`）。注：MVP 10 关内尚未触及上限（第 10 关为 1675‰/1405‰），上限在 1.0 的 30+ 关才会生效 |
| FR-064 Boss | 通过 | 独立血条（`gameplay.gd:569`）、出生即 `boss_warning` 预警、特殊行为 `war_cry`（周期性对墙 20 伤害）、死亡因实体移除 + 实体级幂等键只处理一次（autoplay `boss_deaths=1` 复核） |

### 2.6 成长与经济

| 需求 | 状态 | 审计证据与备注 |
|---|---|---|
| FR-070 资源 | 通过 | `coins`/`xp` 为主，`crystals` 保留为 0 值字段；击杀与通关奖励均带 `source`/`reward_version`/`idempotency_key`（`run_model.gd:512`） |
| FR-071 升级 | 通过 | 等级/下一级效果/价格/前置/上限齐全；`upgrade_service.gd:5` 校验顺序 = 上限→前置→余额，失败返回原 profile（不部分修改），成功在副本上扣费 |
| FR-072 MVP 研究 | 通过 | Strength(12 级)/Agility(6 级)/火冰雷专精(各 8 级) 共 5 项 |
| FR-073 奖励幂等 | 通过 | `run_id + reward_version` 永久 ledger（`upgrade_service.gd:27`），重复 key 返回 `duplicate:true` 不加资源 |

### 2.7 配置、随机与诊断

| 需求 | 状态 | 审计证据与备注 |
|---|---|---|
| FR-080 数据驱动 | 通过 | 敌人/Stage/武器/技能/升级全部在 `game_rules.json`；声明 `config_version`/`ruleset_version`/`source` |
| FR-081 配置校验 | 通过 | `content_validator.gd` 启动时校验（ID 唯一、引用存在、数值范围、Boss 标记一致性、升级依赖无环、本地化 key 完整），`tools/validate_content.gd` 供构建前使用 |
| FR-082 确定性随机 | 通过 | 自实现 LCG（`deterministic_rng.gd`），spawn 与 combat 分 stream（不同异或种子）；Core 无 `randf/rand RandomNumberGenerator` 依赖 |
| FR-083 调试回放 | 通过 | `game_session.replay_record()` 记录 seed/命令/事件 SHA-256，`replay_service` 可导出/回读；无玩家 UI（符合"MVP 不提供回放 UI"）。注：生产构建也常驻记录命令/事件日志，见 §5 问题 C-4 |

## 3. 非功能需求审计（NFR-001 ～ NFR-012）

| 需求 | 状态 | 审计证据 |
|---|---|---|
| NFR-001 性能 | 通过 | 压力测试（文档记录 p95 1.224 ms ≪ 10 ms 预算）；空间 band 加速（`run_model.gd:468`）与扫掠碰撞实现与架构一致 |
| NFR-002 启动 | 通过 | 文档记录 5 次启动平均 1.510 s（目标 <4 s） |
| NFR-003 内存 | 通过 | 60 分钟 soak：内存增长 3.17 MiB、节点数不变 |
| NFR-004 离线 | 通过 | run_all 内含"生产脚本无网络客户端"静态检查 PASS；全代码无 HTTP/WebSocket |
| NFR-005 可靠性 | 通过 | 存档三件套（临时/备份/损坏副本）+ 强杀进程验收 + 迁移回退均有自动测试 |
| NFR-006 可维护性 | 通过 | Core 全部 `RefCounted`/纯静态；run_all 含 Core 依赖静态检查 PASS（无 SceneTree/Input/FileAccess/Audio/Time） |
| NFR-007 可复现 | 通过 | 事件经 `_emit` 打 tick+sequence 并按 `EVENT_ORDER` 排序（`run_model.gd:596`），hash 一致性测试 PASS |
| NFR-008 可访问性 | 通过 | 反馈多通道非仅颜色；UI 缩放 0.85–1.25；音量/震动可关；瞄准辅助可开关 |
| NFR-009 本地化 | 通过 | zh/en 各 104 key 全量对齐（本次审计复核）；验证器强制缺失即报错 |
| NFR-010 构建 | 通过 | export preset `Windows Desktop` 固定；manifest 含 godot 版本/Git SHA/config hash（`tools/write_build_manifest.gd`） |
| NFR-011 隐私 | 通过 | 日志 details 走白名单四字段（`diagnostic_service.gd:85`），含路径符号的 token 直接改写为 `redacted_path`；诊断 ZIP 仅玩家手动触发 |
| NFR-012 依赖 | 通过 | 无 Asset Library addon、无第三方插件 |

## 4. 架构符合性审计

### 4.1 符合项

- 四层依赖方向正确：Core（RefCounted）← Application ← Presentation；唯一 Autoload 组合根 `GameApp`；Infrastructure 不含规则逻辑。
- 固定 30 tick、整数 milli 坐标、注入式 RNG、有序事件数组、`step(commands)` 契约——与架构文档 §6/§8 一致。
- 表现层不直改 Profile/HP/Mana：全部经 `GameApp` 服务方法，事务边界（先持久化后提交内存）在结算/购买/教学/设置四处一致落实。
- 场景复用：`gameplay.tscn` 单场景 + 配置差异，无 `stage_00X.tscn` 复制（架构 §7.3 红线）。
- 结算由 core 事件 `run_end` 驱动一次，`_settled` 防重入（`gameplay.gd:165`），与 AT-015 对应。

### 4.2 偏差项（均不阻塞，建议更新文档或补记录）

| 编号 | 偏差 | 影响与建议 |
|---|---|---|
| A-1 | 架构 §9 写"鼠标坐标通过 Camera2D 转成逻辑坐标"；实现无 Camera2D，`gameplay.gd:63` 直接取 viewport 全局坐标 ×1000 | 因 stretch=canvas_items+expand，逻辑画布恒为 1920×1080 扩展域，功能正确且有窗口验收覆盖。建议改文档表述，或在引入战场 Camera2D（若 1.0 需要镜头效果）时统一 |
| A-2 | 架构 §6.3 写 GameplayView 维护 Sprite2D/AnimationPlayer/GPUParticles2D 与节点池；实现为 immediate-mode `CanvasItem._draw()` 程序绘制，无实体节点、无需池化 | 这是"原创程序绘制视觉"路线的合理落地，实测性能余量大（408 FPS）。建议在架构文档补一段"当前实现采用过程式绘制，节点池策略仅在切换到 Sprite 实体时生效"，避免后续开发者按旧文档找池化代码 |
| A-3 | 架构 §4 计划的 `src/core/entities|progression`、`presentation/hud|tutorial`、`infrastructure/config|persistence|input`、`content/art|audio|fonts|themes` 目录未创建 | 实际布局是收敛后的扁平版（combat/rules/replay + application + presentation + infrastructure），功能等价。建议文档同步最终目录树 |
| A-4 | 架构 §10 的 `.tres` 表现资源目录方案未采用 | 全程序绘制下无表现资源可映射，规则-表现分离改由 `name_key` + 绘制 match 实现。1.0 若引入真实美术资产，再按原文档建 `.tres` 目录即可 |

## 5. 代码质量与工程卫生发现

分级：**P1** 建议进入 1.0 开发前处理；**P2** 1.0 过程中处理；**P3** 机会性清理。

| 编号 | 级别 | 发现 | 位置 | 说明与建议 |
|---|---|---|---|---|
| C-1 | P2 | `_boss_rewarded` 为死代码：赋值后从未读取 | `run_model.gd:58,523` | Boss 奖励唯一性实际由"死亡即移除实体 + 实体级幂等键"保证。建议删除该变量，或改为在 `_resolve_run_end` 里对 Boss 关做断言（Boss 关胜利必须 `_boss_rewarded`），把隐患变检查 |
| C-2 | P2 | `reward_ledger` 无界增长 | `upgrade_service.gd:40` | 幂等键只 append 永不清理，长期游玩存档线性膨胀。建议引入分段账本（如保留最近 N=512 条 + 把更早的 key 折叠进一个"历史水位"摘要），或按 `run_id` 时间窗裁剪——注意 AT-007 要求旧键永久有效，裁剪方案需同时保存"已结算 run_id 前缀区间" |
| C-3 | P2 | 每 tick 深拷贝快照 | `run_model.gd:118`（30 次/秒 `duplicate(true)` 全量敌人+投射物） | MVP 规模实测无压力（p95 1.2ms），但 1.0 的 6+ 敌人、防御设施、更多投射物下会放大。建议 1.0 引入代际脏标记：tick 内无变化时复用上一快照，或 presentation 直接持有只读数组引用 + tick 结束后统一换引用 |
| C-4 | P2 | 命令/事件日志全量常驻且含瞄准噪声 | `game_session.gd:13-14,38` | `_command_log` 记录所有 `aim` 命令（生产每物理 tick 1 条，5 分钟局约 9,000 条 dict）+ `_event_log` 全量事件在局内持续增长。当前规模内存可控（数十 MiB 级内），但属隐性成本。建议：① debug 标志控制日志记录（`OS.is_debug_build()`）；② aim 命令按 tick 合并（同 tick 最后一条即全量语义）；③ 回放记录导出前对连续 aim 做差分压缩 |
| C-5 | P3 | `combat_aim` InputMap action 空定义且无查询者 | `project.godot:39` | 瞄准走 `get_global_mouse_position()` 轮询，该 action 无事件也无消费者。删除或保留作占位皆可，建议删除以保持 InputMap 真实 |
| C-6 | P3 | 结算"继续"按钮（`result.next`）行为是返回主菜单，非直接进入下一关 | `gameplay.gd:467` | 玩家胜利后需经菜单二跳进下一关，轻微 UX 摩擦。建议该按钮在胜利时直接 `GameApp.start_stage("stage_%03d" % (number+1))`（同时可保留菜单入口） |
| C-7 | P3 | 波次语义双轨：HUD"敌军 x/y"实为击杀/总生成数，结算 `wave` 字段实为已到达组号 | `gameplay.gd:125`、`run_model.gd:40` | 功能正确但术语混用，1.0 引入真波次机制前建议统一命名（`kills_total` vs `wave_reached`） |
| C-8 | P3 | 状态抗性减免下限 950‰ 是代码常量而非配置 | `run_model.gd:583` | FR-080 要求数值配置化；此为规则性常量，可接受，但 1.0 扩展敌人模板时若需调整会触碰代码，建议挪入 `game_rules.json` 的规则常量区 |
| C-9 | P3 | 远程敌人攻击抽象为"驻停后周期性直接对墙伤害"，无敌方投射物实体 | `run_model.gd:413` | MVP 合理简化。注意 1.0 的 Lava Moat/Magic Tower 若要"拦截敌方投射物"这类玩法，需先把敌方攻击实体化；此决策应与防御设施设计一并做 |
| C-10 | P3 | 大文件：`gameplay.gd` 833 行、`run_model.gd` 634 行 | — | 见 §7 结构性建议，1.0 开工前拆分 |
| C-11 | P3 | `Builds/` 本地残留探针产物（多份 `WindowsPackageProbe` 日志、`PackPreflight/*.tmp`） | `Builds/` | 已被 Git 忽略，不影响仓库；建议提供 `tools/clean_builds.ps1` 或定期手动清理 |

## 6. 与参考游戏（Defender II）的信息对照

`参考/` 目录提供了 Defender II 的官方商店图、社区帖与 2012 年同期评测截图，并附来源清单 CSV（文件/来源类别/页面来源/直链/采集日期/内容标签/版本说明，共 7 字段，采集于 2026-09-01）。对照结论：

**已落地的信息层级**（MVP 范围内与参考一致）：主菜单模式入口、横屏战场（左城堡右敌群）、火/冰/雷三技能、Boss 预警与血条、Stage 选择与结算、升级页、设置、教学。

**参考中存在、按范围门禁正确后置的内容**（UI 无占位暴露，符合 FR-010 红线）：

- 攻击/魔法/防御/武器四页研究树 → MVP 仅单页 5 项升级
- 金币/水晶商店 → 仅本地经济，无商店 UI
- Honors 成就弹窗 → 无成就系统
- Battle 双人模式 → 明确另立阶段
- Lava Moat、Magic Tower → 后置（FR-051）
- 多重箭/弩武器线 → 仅基础弓

**保真度注意**（来自参考图片的观察，供 1.0 设计参考）：

1. 参考图显示 Defender II 的敌群密度与同屏数量显著高于当前 MVP（如 `it-blog_05`、`unwire_02`），配合 `参考/README` 的提示"社区图片只能作 B/C/D 级辅助证据"，1.0 调参时可作为密度方向的定性依据，不可直接抄数值。
2. 参考图中的熔岩沟（战场中段的伤害地形）在需求中被列为 1.0 Lava Moat，当前战场几何（castle_x=210000, attack_x=350000, spawn_x=1880000）已预留中段空间，无需改动世界坐标即可插入。

**版权合规**：`export_presets.cfg:11` 的 `exclude_filter="参考/*,docs/*,tests/*,tools/*,..."` 确保参考图片不进包；参考 README 明确了"仅内部视觉研究、不打包不商用"的使用边界。审计确认合规。

## 7. 面向 Windows 1.0 的差距与开发指导

需求 §4 已给出 1.0 内容清单（30+ Stage、6+ 敌人、3+ Boss、Power/Hurricane/Phantom 武器、Lava Moat、Magic Tower、四页 Research、Honors）。结合本次审计，给出按优先级的实施路线：

### P0 — 1.0 开工前的结构准备（建议先做，约一周量级）

1. **拆分 `run_model.gd`**：按架构文档 §6.1 的职责边界拆出 `SpawnSystem`、`SkillSystem`、`CombatSystem`（当前全部内联）。拆分必须保持事件顺序与 hash 不变——以现有回放金样（run_all 确定性测试 + autoplay）作为重构安全网，重构后 `event_hash` 必须逐字节一致。
2. **拆分 `gameplay.gd`**：拆出 HUD 构建（`_build_hud` 系）与战场渲染（`_draw_*` 系）两个协作类，为 1.0 的防御设施渲染和新武器视觉腾位置。
3. **快照机制改造**（C-3）与**命令日志降噪**（C-4）：两者都是 30+ 敌人规模的前置条件。
4. **难度曲线调参基线**：当前 autoplay 10 关全 `wall≥97%`（仅 Boss 关 97%），曲线偏保守——熟练玩家配合升级会明显碾压。建议为 1.0 建一个"seed 扫描 + 策略梯度"的调参脚本（在 `stage_autoplay.gd` 基础上输出每关城墙余量分布），把"普通玩家通关率"变成可观测指标。

### P1 — 1.0 内容主线（按依赖顺序）

1. **新武器（Power/Hurricane/Phantom）**：数据结构已留位（`pierce` 字段、击退、特殊效果）。 hurricane 类多弹道需要投射物系统支持"一次射击多实体"，Phantom 类追踪需要弹道转向逻辑——先扩 `ProjectileSystem` 再加配置。
2. **敌方投射物实体化**（C-9 前置决策）→ **Lava Moat / Magic Tower**：防御设施接入点在架构预留的固定更新顺序第 4 步（更新防御设施）；Lava Moat 是区域伤害（可复用技能范围判定），Magic Tower 是自动攻击实体（可复用投射物系统）。两者都必须是独立可选系统（FR-051），即 Stage 配置里显式声明启用。
3. **四页研究树**：现升级模型（prerequisites/价格增长/上限）已支持树形扩展，主要工作是 UI 分页 + 内容校验器的依赖规模提升。Honors 可基于现有 `best_results` 与新增统计字段实现。
4. **内容扩充（30+ Stage / 6+ 敌人 / 3+ Boss）**：`content_validator.gd:59-66` 的 MVP 硬校验（`requires_ten_mvp_stages`、`requires_one_mvp_boss`、`requires_three_mvp_skills`）需同步改为范围感知校验（按 `ruleset_version` 或新增 `content_scope` 字段区分 MVP/1.0 门禁），否则无法扩充。
5. **难度上限生效检查**：MVP 关卡范围内 `difficulty_scaling` 上限从未触发（见 FR-063 备注），30+ 关设计时必须验证上限行为符合设计意图。

### P2 — 发布与工程化（文档已列，审计确认仍有效）

- 外部低配机兼容抽检（另一台无 Godot 的 Win10/11 最低配置）——文档明确这是当前唯一建议补做的验收。
- 图标、代码签名、发行渠道元数据（进入公开发布阶段时）。
- 本地 `Builds/` 清理脚本（C-11）。
- 更新 `defender-ii-software-architecture.md` 的 A-1～A-4 偏差表述，保持文档与实现一致。

## 8. 审计检查清单核对

| 目标要求 | 结果 |
|---|---|
| 在审计分支下开展 | ✅ 本报告撰写并提交于 `audit/windows-godot` |
| 基于 docs 下架构与需求 | ✅ 逐条对照 FR-001~083、NFR-001~012、AT-001~020 及架构 §1~§18 |
| 基于参考下的游戏信息 | ✅ §6 与 Defender II 参考库逐主题对照，含版权合规确认 |
| 对游戏实现内容完成审计 | ✅ 全量通读 src/content/scenes/project.godot/export_presets，复跑 3 组验证脚本 |
| 根目录输出审计结果文档 md | ✅ 本文件 `audit-report.md` |
| 指导后续开发 | ✅ §7 给出 P0/P1/P2 优先级路线与前置依赖 |

## 9. 修复迭代记录(2026-09-03)

依据本报告 §5/§4 的结论,在 `audit/windows-godot` 分支完成一轮代码修复,并用全量回归套件验证。

### 9.1 已修复

| 编号 | 修复内容 | 回归证据 |
|---|---|---|
| C-1 | `_boss_rewarded` 从死代码改为 `result()` 的 `boss_slain` 诊断字段(`run_model.gd`),供结算与后续 Honors 使用 | 新增 3 项断言:无 Boss 关胜利 `boss_slain=false`;Boss 被击杀后结果字段为真且只结算一次 |
| C-2 | `reward_ledger` 引入 512 条容量上限与 `reward_ledger_pruned` 剪枝计数(`upgrade_service.gd`);`game_app.gd` 默认档补齐新字段,旧档经默认字段补全机制自动迁移。**与审计原建议(前缀区间水位)的偏差为正式接受项**:run_id 为随机 32 位 hex,不存在可排序前缀,"已结算前缀区间"无法定义;且现有代码不存在跨会话重结算路径(`settle_run` 仅由 run 结束信号与同会话保存重试触发,历史结果不落盘),512 窗口在全部现有路径下语义完整。若 1.0 引入可重结算历史对局的功能(如回放结算 UI),账本必须升级为全量结构(建议:单调 run 序号 + `min_seq` 水位) | 新增 2 项断言:520 次结算后账本恒为 512 条且 pruned=8;窗口内新键保持幂等;原 205 次旧键幂等测试不变通过 |
| C-3 | `snapshot()` 改为浅拷贝并文档化只读别名契约("tags 数组生成后不再原地修改") | 压力测试 p95 1.294 ms;10 关 autoplay 每 tick 数值与基线逐字节一致 |
| C-4 | `GameSession` 日志门控(`logging_enabled = OS.is_debug_build()`,Release 构建不再累积命令/事件日志)+ 同窗口 `aim` 命令合并(只保留最新瞄准,aim 不产生事件,回放语义不变) | 新增 2 项断言:连续两个 aim 合并为 1 条且取最新;后续非 aim 命令保持顺序;soak 60 逻辑分钟内存增长 3.17 MiB 与基线一致 |
| C-5 | 删除 `project.godot` 中无事件、无消费者的 `combat_aim` 空 action | inputmap 验收 6/6 通过 |
| C-6 | 结算界面"继续"按钮在胜利时直达下一关(`stage_%03d`),失败局维持返回菜单 | resolution_layout 含 result 状态检查,0 失败 |
| C-8 | 状态抗性减免下限移入配置 `rules.status_resistance_floor_permille`(默认 950),`content_validator.gd` 增加范围校验 | 新增断言:默认下限下 999 抗性灼烧 1000 tick → 50;下限 0 → 1000(全额) |
| C-11 | 新增 `tools/clean_builds.ps1`(-All 可全清)。首次执行暴露 PowerShell 5.1 兼容缺陷:`-LiteralPath` 与 `-Include` 组合会忽略过滤条件,误删了本应保留的本地发布产物(EXE/PCK/ZIP/manifest);已改为 `Where-Object` 扩展名过滤并重跑验证。产物通过 `tools/build_windows.ps1 -Configuration Release` 全流水线重新生成并重新验收。**终态说明**:构建/预检流程本身会重新生成 `PackPreflight/`、`WindowsPackageProbe/` 等探针目录,属预期行为;发布确认后手动执行一次本脚本即恢复终态(不建议挂入构建流水线,探针产物是排障证据) | 清理脚本仅删除探针目录与 tmp/log;重建的 Release 包通过构建门禁与导出验收 |
| A-1~A-4 | 架构文档四处偏差已同步:无 Camera2D 的直接坐标映射、过程式绘制说明、实际目录树、`.tres` 方案启用条件(`docs/defender-ii-software-architecture.md`) | 文档与实现一致 |

### 9.2 有意推迟(含理由)

- **C-7(波次语义双轨)**:纯命名清晰度问题,涉及 result 字段与 HUD 文案,建议与 1.0 真波次机制一并处理,避免无谓的存档/回放字段变更。
- **C-9(敌方攻击实体化)**:1.0 防御设施(Lava Moat/Magic Tower 拦截玩法)的设计决策,不属于本轮缺陷修复。
- **C-10(拆分 run_model.gd / gameplay.gd)**:审计 P0 结构准备项,是独立的结构重构,需要以事件哈希金样为安全网单独执行;本轮先完成其依赖的行为修正(快照、日志),降低后续重构的耦合面。
- **打包级 PowerShell 验收**(save crash/runtime probe/pack preflight/release readiness):`pack_preflight` 与导出验收由 `build_windows.ps1` 内部执行,已在审计分支重建 Release 包时通过;`check_release_readiness.ps1` 硬性要求 `windows-godot` 分支,已于修复合并回实现分支后重跑(见 §9.4)。

### 9.3 本轮回归结果

| 套件 | 结果 |
|---|---|
| `tests/run_all.gd` | **53 passed, 0 failed**(原 44 + 新增 9) |
| `tools/validate_content.gd` | 通过(config v2,含新 `rules` 段校验) |
| `tests/stage_autoplay.gd` | 10/10 victory;数值与修复前基线逐字节一致(确定性保持) |
| `tests/performance_stress.gd` | p95 1.294 ms(预算 <10 ms) |
| `tests/long_soak.gd` | 60 逻辑分钟:内存增长 3.17 MiB、节点 3→3 |
| `tests/tutorial_acceptance.gd` | 8/8 |
| `tests/settings_acceptance.gd` | 8/8 |
| `tests/application_transaction_acceptance.gd` | 4/4 |
| `tests/inputmap_acceptance.gd` | 6/6 |
| `tests/diagnostic_acceptance.gd` | 10/10 |
| `tests/resolution_layout.gd` | 2 语言 × 3 分辨率 × 菜单/战斗(含 result 状态),0 失败 |
| `tests/window_mode_acceptance.gd` | 7/7(真实窗口) |

### 9.4 合并与发布门禁收尾(评审意见执行记录)

外部评审确认"修改-审计循环"主体闭环后,指出三个收尾点,处理如下:

1. **合并回实现分支并重跑发布门禁**:本报告与修复提交以快进合并落到 `windows-godot`;在实现分支上重跑 `tools/check_release_readiness.ps1`(要求 12/12、blockers=0)并执行 `tools/build_windows.ps1 -Configuration Release`,使发布清单的 Git SHA 指向合并后的代码。
2. **C-2 口径正式化**:采用评审给出的选项二——在 §9.1 明示实现与原建议的偏差及理由,作为正式接受项记录(见 C-2 行),并写明 1.0 触发升级的条件。
3. **C-11 终态清理**:Release 重建后执行一次 `tools/clean_builds.ps1`,移除构建流程重新生成的探针目录,保留 `Builds/Windows`、便携 ZIP 与构建清单作为最终产物。

---

*审计人:ZCode 自动审计(基于仓库静态审查 + headless 实机验证)。§1~§8 为审计原始结论;§9 记录基于审计结论的修复迭代与评审收尾。C-7/C-9/C-10 有意推迟,理由见 §9.2。*
