# Windows / Godot 开发指南

文档日期：2026-09-01

分支：`windows-godot`

## 1. 本机依赖

当前开发阶段只依赖：

- Godot 4.7.2 stable 标准版（已解压到 `D:\Software\Godot-4.7.2`）。
- Git。
- 可选文本编辑器。

不需要 Unity、Visual Studio、.NET SDK、Android Studio、Xcode、数据库、Docker、第三方 Godot addon 或外部音视频编辑器。Windows export templates 仅在生成 EXE/PCK 时需要，当前按用户要求未安装。

## 2. 启动

从仓库根目录启动游戏：

```powershell
& 'D:\Software\Godot-4.7.2\Godot_v4.7.2-stable_win64.exe' --path .
```

打开编辑器：

```powershell
& 'D:\Software\Godot-4.7.2\Godot_v4.7.2-stable_win64.exe' --editor --path .
```

Godot 项目使用 1920×1080 逻辑画布、Compatibility Renderer 和 30 physics tick/s。默认窗口会按显示器尺寸缩放。

## 3. 验证命令

内容校验：

```powershell
& 'D:\Software\Godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://tools/validate_content.gd
```

核心、存档、升级、回放和场景测试：

```powershell
& 'D:\Software\Godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://tests/run_all.gd
```

10 Stage 自动通关：

```powershell
& 'D:\Software\Godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://tests/stage_autoplay.gd
```

100 敌人、200 投射物、9000 tick 压力测试：

```powershell
& 'D:\Software\Godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://tests/performance_stress.gd
```

三种目标分辨率布局检查：

```powershell
& 'D:\Software\Godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://tests/resolution_layout.gd
```

## 4. 内容编辑

规则真源是 `content/config/game_rules.json`，包括：

- 世界、城墙、Mana 和基础弓参数。
- 火、冰、雷技能。
- 3 类普通敌人和 Boss。
- Strength、Agility 与 3 项元素精通。
- 10 个 Stage 的生成组和奖励。

可见文本位于 `content/catalogs/localization.json`。修改后先运行内容校验和 `run_all.gd`，再运行 Stage 自动通关，避免引入无解关卡或坏引用。

## 5. 存档与诊断

Godot 将玩家数据写入 `user://`，Windows 默认对应 `%APPDATA%\Godot\app_userdata\Aegis of Ember`。主要文件：

```text
profile.json
profile.json.bak
settings.json
settings.json.bak
replays/
```

主档损坏时会保留 `.corrupt-<timestamp>` 诊断副本并尝试备份。若主档和备份都无效，启动恢复页提供重试、开始新档和退出，不会静默覆盖原文件。

## 6. 构建清单与 Windows 导出

生成清单：

```powershell
& 'D:\Software\Godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://tools/write_build_manifest.gd
```

它会生成 `content/build/build-manifest.json`，包含应用版本、Godot 版本、Git SHA、配置版本、配置 hash 和 UTC 时间；文件不提交 Git，但会被资源导出收集。

安装完全匹配的 4.7.2 export templates 后才可执行：

```powershell
& 'D:\Software\Godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --export-debug 'Windows Desktop' 'Builds\Windows-Dev\DefenderGame.exe'
& 'D:\Software\Godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --export-release 'Windows Desktop' 'Builds\Windows\DefenderGame.exe'
```

当前导出预设已就绪，但模板目录为空。不要用其他 Godot 版本的模板替代。
