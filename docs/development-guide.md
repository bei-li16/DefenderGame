# Windows / Godot 开发指南

文档日期：2026-09-22（源码 1.7.0）

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
& $GodotConsole --headless --path . --script res://tests/presentation_polish_acceptance.gd
```

弓箭选择验收覆盖顶部单一入口、四把弓的切换、锁定弓跳转研究、解锁后装备、研究页同步、存档失败与重试，以及实际战斗使用所选弓箭。测试使用隔离存档，不修改玩家存档。移除 `--headless` 还会验证原生/嵌入式下拉框在三档 UI 缩放下的位置；追加 `-- --capture` 可将界面截图保存到被 Git 忽略的 `Builds/weapon-selection-review/`。

技能交互专项覆盖主页三系九技能下拉装备/研究同步/失败回滚、1/2/3 热键的各阶魔法光标、成功/失败/取消/暂停/UI/窗口退出的指针状态；三阶 108 个种子与研究组合逐发比对独立均匀随机落点（含中部），验证升级不移动落点、九技能半径增幅与封顶，并验证 100 敌人下三系同放的全部 168 发和逻辑性能。不再限制或验收累计覆盖百分比。移除 `--headless` 并追加 `-- --capture` 可额外检查真实系统指针与双语三档缩放下拉位置，保存到 `Builds/skill-interaction-review/`。此专项已纳入正式导出门禁，测试应串行运行。

无尽关卡验收覆盖前 600 关的 Boss/普通关隔离、曲线、百万关有限生成、存活上限延后出怪、确定性、旧 30 关存档衔接、首通和保存失败、分页与定位。移除 `--headless` 并追加 `-- --capture` 可将中英文选关和下一关界面保存到 `Builds/endless-stages-review/`。`stage_autoplay.gd` 自动通关原 30 关与 9 个无尽段样例；高关卡生成测试不等同于证明满级角色可通关所有关卡。详见 [无尽关卡规则](endless-stages.md)。脚本共享隔离测试档，应串行运行，不操作真实玩家存档。

素材动画验收覆盖当前 20 张注册纹理、弓箭映射、弩塔 UV 裁切、快照隔离、冻结/眩晕/减速/暂停、真实事件触发动作、死亡回收和共享网格。移除 `--headless` 并追加 `-- --capture` 可进行 100 动画怪物＋200 箭的真实渲染检查，并保存菜单/研究/战场截图到 `Builds/materials-review/`。接入规则与现有立绘动画的限制见 [素材接入说明](materials-integration.md)。

`presentation_polish_acceptance.gd` 验证真实施法到荣誉保存的链路、失败回滚、败局金币、满蓝开局、音乐 PCM/限流及界面；图形模式增加混音检查。`-- --capture` 输出中英文菜单/研究、密集法术、Boss、暂停设置、结算截图及三段配乐 WAV 至 `Builds/polish-review-20260922/`。`-- --interactive` 启动可操作的隔离测试档，供鼠标键盘试玩；关闭窗口即可结束，不使用玩家进度。所有脚本必须串行运行。

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

规则真源是 `content/config/game_rules.json`，当前为 config version 12 / ruleset `aegis-windows-presentation-polish-v1`，回退包同步使用 `aegis-windows-fallback-presentation-polish-v1`。v12 不改倾泻分布、研究或关卡曲线，仅标识结算语义与体验修订。包括：

- 世界、城墙、Mana 和基础弓参数。
- 火、冰、雷三系九技能及装备、升级链。
- 6 类普通敌人和 3 个 Boss，包括状态/元素/击退抗性与 Boss 特殊行为。
- 七项攻击科技、多重箭逐级属性、研究价格/门槛/上限；防御、武器与后勤研究。
- 17 项无尽研究的 `endless`、`endless_cost` 与技能 `secondary_max_level`；原 `max_level` 对无尽节点表示原价格区间边界。不能用旧等级上限直接截断存档或判定满级。
- 前 30 关的既有生成组与倍率，以及 `endless_stages` 中的无限后续关卡曲线、普通怪权重、三 Boss 轮换、波间喘息和存活数量预算。

可见文本位于 `content/catalogs/localization.json`。修改后先运行内容校验和 `run_all.gd`，再运行 Stage 自动通关，避免引入无解关卡、坏引用、缺失翻译或越界数值。

`endless_research_acceptance.gd` 检查高等级购买、费用、实际效果、存档和中英文研究页，以及第 1000/10000 关的正常自动战斗。移除 `--headless` 并追加 `-- --capture` 可在 `Builds/endless-research-review/` 生成截图。`resolution_layout.gd` 另检查双语 × 四分辨率的百万级研究详情。规则与参数见 [无尽研究说明](endless-research.md)，该专项也已加入 Windows 导出门禁。

## 5. 存档与诊断

槽位和设置统一写入 EXE 同级 `savedata/`（编辑器运行时为项目根目录）；需要用户可写目录。日志、诊断、调试回放位于 `user://`，Windows 默认对应 `%APPDATA%\Godot\app_userdata\Aegis of Ember`。schema 为 v6。

```text
savedata/slot_1.json                  # 槽位 1..3，各有 .bak
savedata/settings.json                # 含活动槽号，亦有 .bak
savedata/profile.json                 # 旧档迁移来源，不是当前主档
user://replays/
user://logs/
user://diagnostics/
```

主档损坏时保留 `.corrupt-<timestamp>` 副本并尝试备份；主档存在但双档无效时进入恢复页。当前仍有“主档缺失且备份损坏会返回默认档”的边界风险，不能宣称所有双档无效情形均已安全恢复。购买、结算、教学保存成功才提交内存；设置先应用、保存失败则回滚。

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

脚本要求 Git 工作树干净，并执行内容校验、核心、无尽关卡/研究、技能交互、视听体验专项、30 编排关 + 9 生成关自动通关、存档槽位、Godot 声明、PCK 预检、许可、清单和模板检查。自 1.7 起，发行资源内嵌进 EXE；导出后直接验证 EXE 内的资源清单，并复制 EXE 到隔离运行目录，确认 `savedata/slot_1.json` 与设置写入 EXE 同级目录。Release ZIP 严格只含 `DefenderGame.exe`、`README.txt`、`GAME_LICENSE.txt` 和 `GODOT_COPYRIGHT.txt` 四项，不含独立 PCK、源码、编辑器、测试日志或玩家存档。独立 PCK 仅用于构建前诊断，不上传发行页。Git 忽略 EXE/DLL/PCK/ZIP，源码提交与 GitHub Release 二进制附件分离。

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

它会执行 PCK 预检，并将结果汇总到 `Builds/ReleaseReadiness/release-readiness.json`。历史的 12/12 不代表本轮工作树已发布就绪；1.7 修改仍需审阅提交后重新构建。未满足条件或跳过动态预检时返回退出码 2；`-SkipPackPreflight` 只检查静态材料，不产生发布就绪结论。

## 三系特效专项

新增 `tests/elemental_vfx_acceptance.gd`，已经加入 `build_windows.ps1` 串行门禁。使用 `--capture` 可输出九技能阶段截图、三档混合压力截图及六段 WAV 至 `Builds/elemental-vfx-review/`。测试涵盖透明图集、真实落击事件、效果过期、音频分组与 PCM 边界，命令和说明见 [三系视听重制](elemental-vfx.md)。

## 九技能图标与城防专项

2026-09-23 收尾 `tests/fortress_art_acceptance.gd`，加入正式构建串行门禁；PCK 必需路径增加九图标、城防部件、两张横屏地面及相应脚本。专项检查图标各界面映射、动画像素差、快照不变、音频路由、暂停和场景清理。命令、输出位置和试玩隔离说明见 [城防视听强化](fortress-art.md)。图形验收应与其他 `--script` 测试串行运行。

## 整机 UI 专项

`tests/production_ui_acceptance.gd` 覆盖新城墙/弩机/九宫格/图标资源、安装位置、固定 HUD 内槽、装饰区鼠标穿透、所有研究页及菜单/战斗覆盖层。图形模式追加 `-- --capture`，输出中英文两种分辨率的 64 张非空像素验证截图到 `Builds/production-ui-review/`。`resolution_layout.gd` 另覆盖中英文与 1280x720、1366x768、1920x1080、2560x1440。两者已加入正式构建串行门禁。

`tests/window_mode_acceptance.gd` 必须在图形模式运行；新增音量、画质、自动射击、语言设置不重置最大化窗口的回归。所有 `--script` 测试共享隔离自动化目录，不能并行运行。命令、素材锚点、截图范围和正式发行边界见 [整机 UI 重制](production-ui.md)。
