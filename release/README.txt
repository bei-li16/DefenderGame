AEGIS OF EMBER / 余烬守望
Version 1.8.1-windows - Windows x86_64

An offline, single-player castle defense game. No account, server, payment,
telemetry, or mandatory network connection is used.

INSTALL / 安装与升级
Extract the ZIP into a user-writable folder and run DefenderGame.exe.
All runtime assets are embedded in the EXE; no separate PCK, editor,
source code, or network download is required. The package contains only
DefenderGame.exe, this README, GAME_LICENSE.txt and GODOT_COPYRIGHT.txt.
The executable is unsigned. Only use downloads from the project release page.
To upgrade, close the game, back up savedata/, and extract the new release
into a NEW folder. Copy savedata/ into that folder before launching.
Do not place an older DefenderGame.pck beside the new executable.
解压到可写目录，运行 DefenderGame.exe。资源已内嵌，无需另装编辑器。
升级前关闭游戏并备份 savedata，再将存档复制到新版本的解压目录。
请勿将旧 DefenderGame.pck 放入新目录。此版本未进行数字签名。

VERSION 1.8.1 / 本版更新（config13 / schema6）
Each bow now fires its own fixed bolt design: gold, red, green or cyan.
Critical hits and poison no longer recolor bolts in flight.
四弓分别使用金、红、绿、青制式箭矢；暴击和毒伤不再改变飞行箭颜色。
Maximum firing rates are 15 volleys/s for Guardian and Phantom bows,
and 10 volleys/s for Power and Hurricane bows. Flight speed is unchanged.
守望/幻影满级每秒15轮，震击/飓风每秒10轮；箭速不变。
Agility research shows volleys/s and milliseconds; lower nodes fit fully.
敏捷详情显示每秒轮数和毫秒间隔；修正攻击研究底部节点裁切。
Legacy owned bows now satisfy their unlock research, fixing the misleading
save-error message when forging the Power Bow without charging another unlock.
兼容旧档已拥有的长弓，修复震击长弓锻造误报保存失败，不重复扣解锁费。
Real save failures still roll back the upgrade and currency deduction.
真正保存失败仍回滚等级和扣款，前置条件不足等错误分别提示。
Includes the creature and boss animation improvements from version 1.8.0.
保留1.8.0的小怪与Boss动作强化。现有schema6存档兼容，无需重开档。

MINIMUM TARGET
Windows 10 x64; dual-core CPU; 4 GB RAM; Intel UHD 630 or equivalent
Direct3D 11 / OpenGL 3.3-capable GPU; 1 GB free storage.

RECOMMENDED
Windows 10/11 x64; quad-core CPU; 8 GB RAM; GTX 750 / GT 1030 or better.

CONTROLS
Mouse move: aim
Hold left mouse button: continuous fire
1 / 2 / 3: select Fire / Ice / Lightning
Left mouse button: cast selected spell
Right mouse button: cancel spell
Esc: cancel spell or pause
Loss of window focus pauses combat; resume explicitly when ready.

PLAYER DATA
Three save slots and settings are stored in savedata/ beside the game EXE.
Keep the game in a user-writable folder; copy savedata/ to transfer progress.
Limited local logs and user-requested diagnostic ZIP files use the current
Windows user's Godot application-data directory. No automatic upload occurs.
The game does not require administrator rights and does not write the registry.

LICENSES
See GAME_LICENSE.txt for the game's code, original content license and
third-party audio credits. Audio credits are also embedded in the executable.
See GODOT_COPYRIGHT.txt for Godot Engine and bundled third-party notices.
