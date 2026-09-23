# 战斗音效录音替换

2026-09-24：原有三系技能和弩箭的正弦波/噪声合成音，改为录音剪辑和分层处理。原声与许可、下载地址和 SHA-256 见 `tools/audio_sources/sources.json`；发行包的 `GAME_LICENSE.txt` 和内嵌 `Gamematerials/Audio/credits.json` 保留署名。此次没有使用原商业游戏的音轨。

| 事件 | 声音结构 |
| --- | --- |
| 弩箭发射 | 实录弩弦释放、弩身短促震动；裁去靶上命中，禁止提前播放击靶声 |
| 弩箭命中 | 从独立击靶时点提取箭矢接触与短余响，避免旧有低频鼓点 |
| 火系发动 / 命中 | 火把挥动与喷燃 / 火焰扩张、燃烧、少量噼啪余焰 |
| 冰系发动 / 命中 | 碎冰摩擦渐起 / 不规则冰裂和落下的细碎冰块，无纯音铃声 |
| 雷系发动 / 命中 | 短促宽频先导声 / 雷击的爆裂、较低频率的滚雷衰减，无振荡器啁啾 |

八类声音各三段变体，共 24 段、约 1.25 MB 的 44.1 kHz 单声道 PCM16。WAV 导入保持 `compress/mode=0`，保留弩弦与碎冰的瞬态。变体在通过限流后循环选择，轻微音高变化仅依赖事件字段，不使用战斗随机数。暴击保持机械音色，齐射仅播放一次弩弦释放。

发动仍绑定 `skill_launch`，命中仍绑定 `skill_pulse` / `hit`，`skill_cast` / `damage` 不重复发声。16 个受限声道分配为：6 个技能命中、3 个技能发动、2 个弩弦、2 个击靶、1 个界面/墙体、2 个告警/结果。优先使用空闲声道，池满时仅替换同池最旧尾声。主总线加入 -1 dB 的前瞻限幅，防止全屏技能和连续射击叠加削顶。

重新生成资源（运行游戏及正式打包不依赖 Python）：

```powershell
python -m venv Builds/audio-tools
& .\Builds\audio-tools\Scripts\python.exe -m pip install numpy scipy soundfile
& .\Builds\audio-tools\Scripts\python.exe tools/build_combat_audio.py
& 'D:\Software\Godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe' --headless --editor --import --path .
```

验证必须串行执行：

```powershell
& 'D:\Software\Godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe' --path . --script res://tests/combat_audio_acceptance.gd -- --capture
```

专项检查 PCM 格式、静音端点、直流分量、变体独立性、峰值余量、暴击/齐射路由、静音及声道隔离，并通过真实战斗事件录制主总线。首轮图形验收 129 项通过：10 秒场景包含 75 次齐射、108 次命中及火/冰/雷 56/52/60 次落击，录音峰值 -1.00 dB、无丢帧。此为工程验证，不等同于主观听感评分。

`Builds/audio-review/new-combat-foley.wav` 按弩箭、火、冰、雷排列，供对照试听；`battle-mix.wav` 是实际游戏混音输出。素材测量在 `asset-analysis.json`，图形验收日志为 `combat-audio.log`。

正式 Windows Release 已重建并更新 EXE/ZIP，构建快照为 `7f264f8ab71c639ffaa88744aab6f6a1e1d29d21`，完整门禁与非管理员启动通过。对新 EXE 内嵌资源再次运行图形音频验收，129 项通过；24 段录音及署名均在包内，制作工具和原始录音不在包内。包内混音录音为 `Builds/audio-review/pack/battle-mix.wav`，日志为 `pack-audio.log`；构建日志在 `Builds/RebuildLogs/audio-20260924-011629/`。导出仅保留既有的图标缺少 128 像素尺寸警告。
