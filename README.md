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

`windows-godot` 当前包含可直接运行的原创单机游戏《余烬守望 / Aegis of Ember》(Windows 1.0)：

- 无尽关卡：前 30 关保留既有编排，第 31 关起按曲线生成数量、波次、出怪时长和六类普通怪组合；每 10 关恰好一位 Boss，余烬督军→霜痕巨人→风暴女王循环，普通关无 Boss。详见 [无尽关卡规则](docs/endless-stages.md)。
- 4 把武器:守望长弓、震击长弓(强化击退)、飓风长弓(三连射)、幻影长弓(穿透)。守望长弓初始可用,其余在武器研究中花费金币解锁;顶部弓箭图标展开下拉框切换已解锁弓箭,研究详情也可点击“装备”。两处选择同步保存,并用于随后进入的关卡战斗。
- 火、冰、雷各三级共九个技能，支持主页下拉装备、独立研究和递增 Mana 消耗；选中后显示元素魔法光标。三阶在 3 秒内独立随机倾泻 56/52/60 发，不预留空区、不限制覆盖率；单发直击/溅射半径及范围成长已收小。五页研究树（攻击/魔法/防御/武器/后勤）。技能数值、来源与兼容规则见 [三级技能链说明](docs/skill-chains-reimplementation.md)。
- 攻击研究恢复力量、敏捷、击退、毒箭、暴击、多重箭、高级猎人七节点；共享真实属性预览、依赖等级、独立箭矢与百分比经验加成，旧精通一次性退款。原版证据与项目平衡值见 [攻击研究说明](docs/attack-research-reimplementation.md)。
- 无尽科技：力量、九技能伤害、魔力上限、城墙生命、设施伤害和三弓锻造共 17 项持续升级；其余科技保留等级上限，技能范围/状态时长在研究 20 级封顶。旧价格区间保留，后续费用改用多项式增长，见 [无尽研究说明](docs/endless-research.md)。
- 防御设施:熔岩护城河(范围灼烧)与魔法塔(自动狙击),由防御页研究解锁;霜痕巨人的冰霜新星会暂时冻结玩家防御。
- Honors 成就系统(8 项)、无尽关卡的强度曲线与性能预算、金币/XP 加成研究和奖励永久幂等账本。
- 主菜单(弓箭下拉选择)、分页选关(每页 20 关、可定位已解锁关卡)、研究分页(含武器解锁与装备)、荣誉、设置、教学、暂停和结算(胜利保存后直达下一关，通关 30 关的旧档自动衔接第 31 关)。
- 简体中文/英文、窗口/无边框/全屏、分辨率和 UI 缩放。
- JSON 配置 + 发布包内置回退配置、固定 30 tick、确定性随机、回放事件 hash。
- `user://` JSON 存档、临时写入、hash 校验、备份与 v1→v4 迁移。
- 本地轮转日志和玩家主动导出的隐私安全诊断 ZIP,不进行网络上传。
- 原创程序绘制视觉和程序合成音频;`参考/` 图片不会进入导出包。

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
& .\tools\check_release_readiness.ps1
& .\tools\build_windows.ps1 -Configuration Release
```

当前源码版本以 `project.godot` 为准；规则为 config v11（独立随机倾泻与小范围成长，保留无尽关卡与研究）。无尽研究专项 286 项通过，原 30 关及 9 个生成关卡自动通关全胜，额外覆盖高研究等级下的第 1000/10000 关；本次改动尚未重新导出发行包。正式构建会在被 Git 忽略的 `Builds/` 下生成 Windows x86_64 EXE/PCK 和便携 ZIP；项目采用 `Copyright (c) 2026 bei-li16` 的 MIT 许可。完整证据见 [`docs/implementation-status.md`](docs/implementation-status.md)，开发与构建命令见 [`docs/development-guide.md`](docs/development-guide.md)。
