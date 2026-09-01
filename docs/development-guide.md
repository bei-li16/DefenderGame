# Windows / Godot 开发指南

文档日期：2026-09-02

分支：`windows-godot`

## 1. 本机依赖

当前开发阶段只依赖：

- Godot 4.7.2 stable 标准版（本机位于 `D:\Software\Godot-4.7.2`）。
- Git。
- 可选文本编辑器。

不需要 Unity、Visual Studio、.NET SDK、Android Studio、Xcode、数据库、Docker、第三方 Godot addon 或外部音视频编辑器。Windows export templates 仅在生成 EXE/PCK 时需要，当前按用户要求未安装。

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
& $GodotConsole --headless --path . --script res://tests/tutorial_acceptance.gd
& $GodotConsole --headless --path . --script res://tests/settings_acceptance.gd
& $GodotConsole --headless --path . --script res://tests/application_transaction_acceptance.gd
& $GodotConsole --headless --path . --script res://tests/inputmap_acceptance.gd
& $GodotConsole --headless --path . --script res://tests/diagnostic_acceptance.gd
```

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

规则真源是 `content/config/game_rules.json`，当前为 config version 2 / ruleset `aegis-mvp-v2`，包括：

- 世界、城墙、Mana 和基础弓参数。
- 火、冰、雷技能。
- 3 类普通敌人和 Boss，包括击退抗性与 Boss 特殊行为。
- Strength、Agility 与 3 项元素精通，包括价格、效果、前置和上限。
- 10 个 Stage 的生成组、奖励和有上限的难度倍率。

可见文本位于 `content/catalogs/localization.json`。修改后先运行内容校验和 `run_all.gd`，再运行 Stage 自动通关，避免引入无解关卡、坏引用、缺失翻译或越界数值。

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

正式构建统一使用门禁脚本：

```powershell
& .\tools\build_windows.ps1 -Configuration Debug
& .\tools\build_windows.ps1 -Configuration Release
```

脚本要求 Git 工作树干净，并依次执行内容校验、核心测试、10 Stage 自动通关、Godot 声明一致性、项目许可、清单和匹配模板检查。Release 成功后会生成 EXE/PCK 和包含 `README.txt`、`GAME_LICENSE.txt`、`GODOT_COPYRIGHT.txt` 的便携 ZIP。

当前导出预设已就绪，但仍有两个发布门禁：

- 按用户要求未安装 Godot 4.7.2 export templates；不要用其他 Godot 版本的模板替代。
- 项目所有者尚未选择代码/原创资产许可，因此 `release/GAME_LICENSE.txt` 尚未创建。

这两个条件不影响编辑器内开发和全部源码验收，但在解除前不能生成合规发布包。
