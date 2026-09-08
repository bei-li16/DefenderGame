# Windows / Godot 开发指南

文档日期：2026-09-02

分支：`windows-godot`

## 1. 本机依赖

当前开发阶段只依赖：

- Godot 4.7.2 stable 标准版（本机位于 `D:\Software\Godot-4.7.2`）。
- 与 Godot 4.7.2 完全匹配的 Windows x86_64 Debug/Release export templates（位于 `%APPDATA%\Godot\export_templates\4.7.2.stable`，合计约 203 MiB）。
- Git。
- 可选文本编辑器。

不需要 Unity、Visual Studio、.NET SDK、Android Studio、Xcode、数据库、Docker、第三方 Godot addon 或外部音视频编辑器。为保持轻量，只安装了两个 Windows x86_64 模板；Android、iOS、Web、Linux 和 macOS 模板均未安装，完整模板下载包在校验和提取后已删除。

下面用 `$Godot` 和 `$GodotConsole` 简化命令；如换电脑，只需修改这两个值：

```powershell
$Godot = 'D:\Software\Godot-4.7.2\Godot_v4.7.2-stable_win64.exe'
$GodotConsole = 'D:\Software\Godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe'
```

## 2. 启动

从仓库根目录启动游戏：

```powershell
& $Godot --path .
```

打开编辑器：

```powershell
& $Godot --editor --path .
```

Godot 项目使用 1920×1080 逻辑画布、Compatibility Renderer 和 30 physics tick/s。默认窗口会按显示器尺寸缩放。

## 3. 验证命令

内容校验和核心回归：

```powershell
& $GodotConsole --headless --path . --script res://tools/validate_content.gd
& $GodotConsole --headless --path . --script res://tests/run_all.gd
```

Stage、教学、设置、应用事务、InputMap 和诊断验收：

```powershell
& $GodotConsole --headless --path . --script res://tests/stage_autoplay.gd
& $GodotConsole --headless --path . --script res://tests/endless_stages_acceptance.gd
& $GodotConsole --headless --path . --script res://tests/endless_research_acceptance.gd
& $GodotConsole --headless --path . --script res://tests/tutorial_acceptance.gd
& $GodotConsole --headless --path . --script res://tests/settings_acceptance.gd
& $GodotConsole --headless --path . --script res://tests/application_transaction_acceptance.gd
& $GodotConsole --headless --path . --script res://tests/inputmap_acceptance.gd
& $GodotConsole --headless --path . --script res://tests/diagnostic_acceptance.gd
& $GodotConsole --headless --path . --script res://tests/weapon_selection_acceptance.gd
& $GodotConsole --headless --path . --script res://tests/skill_chains_acceptance.gd
& $GodotConsole --headless --path . --script res://tests/skill_interaction_acceptance.gd
& $GodotConsole --headless --path . --script res://tests/attack_research_acceptance.gd
& $GodotConsole --headless --path . --script res://tests/materials_acceptance.gd
& $GodotConsole --headless --path . --script res://tests/castle_layout_acceptance.gd
```

弓箭选择验收覆盖顶部单一入口、四把弓的切换、锁定弓跳转研究、解锁后装备、研究页同步、存档失败与重试，以及实际战斗使用所选弓箭。测试使用隔离存档，不修改玩家存档。移除 `--headless` 还会验证原生/嵌入式下拉框在三档 UI 缩放下的位置；追加 `-- --capture` 可将界面截图保存到被 Git 忽略的 `Builds/weapon-selection-review/`。

技能交互专项覆盖主页三系九技能下拉装备/研究同步/失败回滚、1/2/3 热键的各阶魔法光标、成功/失败/取消/暂停/UI/窗口退出的指针状态；三阶 108 个种子与研究组合抽样累计伤害覆盖率（保留空隙），并验证 100 敌人下三系同放的全部 168 发和逻辑性能。移除 `--headless` 并追加 `-- --capture` 可额外检查真实系统指针与双语三档缩放下拉位置，保存到 `Builds/skill-interaction-review/`。此专项已纳入正式导出门禁，测试应串行运行。

无尽关卡验收覆盖前 600 关的 Boss/普通关隔离、曲线、百万关有限生成、存活上限延后出怪、确定性、旧 30 关存档衔接、首通和保存失败、分页与定位。移除 `--headless` 并追加 `-- --capture` 可将中英文选关和下一关界面保存到 `Builds/endless-stages-review/`。`stage_autoplay.gd` 自动通关原 30 关与 9 个无尽段样例；高关卡生成测试不等同于证明满级角色可通关所有关卡。详见 [无尽关卡规则](endless-stages.md)。脚本共享隔离测试档，应串行运行，不操作真实玩家存档。

素材动画验收覆盖 19 张纹理导入、弓箭映射、弩塔 UV 裁切、快照隔离、冻结/眩晕/减速/暂停、真实事件触发动作、死亡回收和共享网格。移除 `--headless` 并追加 `-- --capture` 可进行 100 动画怪物＋200 箭的真实渲染检查，并保存菜单/研究/战场截图到 `Builds/materials-review/`。接入规则与现有立绘动画的限制见 [素材接入说明](materials-integration.md)。

攻击研究验收覆盖七节点前置、四弓全部齐射档位、毒伤/击退/暴击快照、经验结算、一次性退款及中英文购买/装备同步。移除 `--headless` 并追加 `-- --capture` 可截图到 `Builds/attack-research-review/`；测试仅使用隔离存档。完整规则见 [攻击研究说明](attack-research-reimplementation.md)。

压力、布局和逻辑 60 分钟稳定性：

```powershell
& $GodotConsole --headless --path . --script res://tests/performance_stress.gd
& $GodotConsole --headless --path . --script res://tests/resolution_layout.gd
& $GodotConsole --headless --path . --script res://tests/long_soak.gd
```

保存中终止进程并重启恢复：

```powershell
& .\tools\run_save_crash_acceptance.ps1
```

窗口、无边框、全屏和准星坐标检查需要真实显示服务，不能增加 `--headless`：

```powershell
& $GodotConsole --path . --script res://tests/window_mode_acceptance.gd
```

真实 Compatibility 渲染、Windows 进程峰值工作集和 5 次启动耗时：

```powershell
& .\tools\run_windows_runtime_acceptance.ps1
```

两个 PowerShell 验收脚本只终止自己刚创建并取得 PID 的测试进程。输出写入被 Git 忽略的 `Builds/`；测试档位于隔离的 `user://` 子目录并在验证后清理。

## 4. 内容编辑

规则真源是 `content/config/game_rules.json`，当前为 config version 9 / ruleset `aegis-windows-endless-research-v1`，回退包同步使用 `aegis-windows-fallback-endless-research-v1`，包括：

- 世界、城墙、Mana 和基础弓参数。
- 火、冰、雷三系九技能及装备、升级链。
- 6 类普通敌人和 3 个 Boss，包括状态/元素/击退抗性与 Boss 特殊行为。
- 七项攻击科技、多重箭逐级属性、研究价格/门槛/上限；防御、武器与后勤研究。
- 17 项无尽研究的 `endless`、`endless_cost` 与技能 `secondary_max_level`；原 `max_level` 对无尽节点表示原价格区间边界。不能用旧等级上限直接截断存档或判定满级。
- 前 30 关的既有生成组与倍率，以及 `endless_stages` 中的无限后续关卡曲线、普通怪权重、三 Boss 轮换、波间喘息和存活数量预算。

可见文本位于 `content/catalogs/localization.json`。修改后先运行内容校验和 `run_all.gd`，再运行 Stage 自动通关，避免引入无解关卡、坏引用、缺失翻译或越界数值。

`endless_research_acceptance.gd` 检查高等级购买、费用、实际效果、存档和中英文研究页，以及第 1000/10000 关的正常自动战斗。移除 `--headless` 并追加 `-- --capture` 可在 `Builds/endless-research-review/` 生成截图。`resolution_layout.gd` 另检查双语 × 三分辨率的百万级研究详情。规则与参数见 [无尽研究说明](endless-research.md)，该专项也已加入 Windows 导出门禁。

## 5. 存档与诊断

Godot 将玩家数据写入 `user://`，Windows 默认对应 `%APPDATA%\Godot\app_userdata\Aegis of Ember`。主要内容：

```text
profile.json
profile.json.bak
settings.json
settings.json.bak
replays/
logs/
diagnostics/
```

主档损坏时会保留 `.corrupt-<timestamp>` 诊断副本并尝试备份。若主档和备份都无效，启动恢复页提供重试、开始新档和退出，不会静默覆盖原文件。购买、结算、教学和设置均在持久化成功后才提交内存状态；保存失败会显示重试入口。

日志最多保留 5 个文件，每个最大 256 KiB，只记录白名单事件和错误码，不写完整 Profile、存档内容或本机绝对路径。设置页的“导出诊断日志”仅在玩家主动点击时生成本地 ZIP；程序不会上传或发送该文件。

## 6. 构建清单、许可与 Windows 导出

生成 Godot 引擎及第三方组件声明：

```powershell
& $GodotConsole --headless --path . --script res://tools/write_godot_copyright.gd
```

生成构建清单（命令会先执行完整内容校验）：

```powershell
& $GodotConsole --headless --path . --script res://tools/write_build_manifest.gd
```

清单位于 `content/build/build-manifest.json`，包含应用版本、Godot 版本、Git SHA、配置版本、配置 hash 和 UTC 时间。该文件不提交 Git，但会被资源导出收集。

换机后即使暂未安装 export templates，仍可执行本地 PCK 发布预检：

```powershell
& .\tools\run_pack_preflight.ps1
```

该脚本要求工作树干净，重新生成清单并用 `--export-pack` 创建被 Git 忽略的本地 PCK。随后从隔离目录检查必需资源、Git SHA 和配置 hash，确认测试、工具、文档及 `参考/` 未进入包，并在隔离的 `%APPDATA%` 下启动 60 帧。它不生成 Windows EXE，也不能替代 AT-019/AT-020 的发布包验收。

正式构建统一使用门禁脚本：

```powershell
& .\tools\build_windows.ps1 -Configuration Debug
& .\tools\build_windows.ps1 -Configuration Release
```

脚本要求 Git 工作树干净，并依次执行内容校验、核心测试、无尽关卡专项、30 编排关 + 9 生成关自动通关、存档槽位、Godot 声明一致性、PCK 预检、项目许可、清单和匹配模板检查。导出后还会检查实际 PCK，使用非管理员进程和隔离 `%APPDATA%` 启动实际 EXE，并确认 `profile.json`、`settings.json` 写入用户数据目录。Release 成功后才会生成包含 EXE/PCK、`README.txt`、`GAME_LICENSE.txt`、`GODOT_COPYRIGHT.txt` 的便携 ZIP。

项目当前采用 `Copyright (c) 2026 bei-li16` 的 MIT 许可。需要为后续项目有意更换许可时，可任选一条命令生成待审阅文件：

```powershell
& .\tools\set_game_license.ps1 -License MIT -CopyrightHolder '版权主体名称' -Year 2026
& .\tools\set_game_license.ps1 -License Proprietary -CopyrightHolder '版权主体名称' -Year 2026
```

生成器默认拒绝覆盖已有 `release/GAME_LICENSE.txt`，需要有意替换时才使用 `-Force`。MIT 模板采用 [OSI 公布文本](https://opensource.org/license/mit)；Proprietary 是便于审阅的项目模板，不替代适用司法辖区的专业法律意见。两个源模板都被导出预设和 PCK 探针明确排除，发布 ZIP 只收集最终确认的 `GAME_LICENSE.txt`。

当前导出预设、MIT 项目许可和 Godot 4.7.2 Windows x86_64 模板均已就绪。不要用其他 Godot 版本的模板替代；正式构建必须从干净 Git 工作树执行。

需要一次查看全部发布条件时运行：

```powershell
& .\tools\check_release_readiness.ps1
```

它会执行 PCK 预检，并把分支、Git、Godot、导出预设、许可、两个模板、非管理员状态和 PCK 结果汇总到 `Builds/ReleaseReadiness/release-readiness.json`。当前本机结果为 12/12、blockers=0。未满足条件或跳过动态预检时返回退出码 2；只想快速查看静态材料时可增加 `-SkipPackPreflight`，但该模式不会产生“发布就绪”结论。
