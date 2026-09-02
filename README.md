# DefenderGame 方案仓库

本仓库使用分支保存互斥的技术方案，避免在同一实现中同时维护两套引擎。

| 分支 | 用途 |
|---|---|
| `main` | 归档 2026-09-01 的移动跨平台需求与架构基线，不在此分支开发 |
| `windows-unity` | Unity 6.3 LTS、C#、Windows x64、本地单机优先 |
| `windows-godot` | Godot 4.7.2、GDScript、Windows x64 的实际 MVP 实现分支 |

查看方案：

```powershell
git switch windows-unity
git switch windows-godot
```

详细产品研究保存在 `main`；方案分支的文档只保留实现所需结论，并通过范围门禁阻止首版重新引入移动端、服务器、账号和支付系统。

## Windows / Godot 实现

`windows-godot` 当前包含可直接运行的原创单机游戏《余烬守望 / Aegis of Ember》：

- 10 个线性 Stage、3 类普通敌人和 1 个 Boss。
- 基础弓、连续射击、Fatal Blow、Power Shot。
- 火球、冰刺和雷击，以及 Mana、冷却、状态和抗性。
- 城墙、胜负、金币、XP、5 项升级和奖励幂等。
- 主菜单、关卡选择、升级、设置、教学、暂停和结算。
- 简体中文/英文、窗口/无边框/全屏、分辨率和 UI 缩放。
- JSON 配置、固定 30 tick、确定性随机、回放事件 hash。
- `user://` JSON 存档、临时写入、hash 校验、备份与 v1→v3 迁移。
- 本地轮转日志和玩家主动导出的隐私安全诊断 ZIP，不进行网络上传。
- 原创程序绘制视觉和程序合成音频；`参考/` 图片不会进入导出包。

运行游戏：

```powershell
& 'D:\Software\Godot-4.7.2\Godot_v4.7.2-stable_win64.exe' --path .
```

执行主要验证：

```powershell
& 'D:\Software\Godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://tests/run_all.gd
& 'D:\Software\Godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://tests/stage_autoplay.gd
& 'D:\Software\Godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://tests/performance_stress.gd
& 'D:\Software\Godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://tests/resolution_layout.gd
& 'D:\Software\Godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://tests/settings_acceptance.gd
& 'D:\Software\Godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://tests/application_transaction_acceptance.gd
& 'D:\Software\Godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://tests/inputmap_acceptance.gd
& 'D:\Software\Godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://tests/diagnostic_acceptance.gd
& .\tools\run_save_crash_acceptance.ps1
& .\tools\run_windows_runtime_acceptance.ps1
& .\tools\run_pack_preflight.ps1
```

当前源码验收 AT-001～AT-018 已通过，无模板 PCK 预检也已通过；可分发 EXE/PCK 仍等待 export templates 和项目许可决定。完整证据与门禁见 [`docs/implementation-status.md`](docs/implementation-status.md)，开发与构建命令见 [`docs/development-guide.md`](docs/development-guide.md)。
