AEGIS OF EMBER / 余烬守望
Version 1.7.1-windows - Windows x86_64

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

VERSION 1.7.1 / 本版更新
Straight, continuous castle walls align above and below the ballista and
extend past both towers to the screen edges, with muted stone and ground colors.
城墙竖直贯通、上下共线并延伸出屏幕，统一石材、地面与原弩机风格。
Recorded crossbow, fire, ice and thunder sounds replace synthetic combat tones.
Separate launch/impact voices and a limiter keep overlapping attacks clear.
三系技能与弩箭改为实录分层音效，区分发动和命中，改善连射与叠加混音。
Existing v6 save slots remain compatible; back up before upgrading.

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
