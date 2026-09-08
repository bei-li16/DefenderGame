# Defender II Windows / Godot 软件架构

版本：3.1-godot-windows

文档日期：2026-09-03

对应分支：`windows-godot`

目标：使用 Godot 4.7.2 和 GDScript 在一台 Windows 电脑上完成轻量、离线、可测试的 2D 单机 MVP

实施状态：本文架构已在当前分支落地。模块、测试结果和发布阻塞项见 [`implementation-status.md`](implementation-status.md)，本机命令见 [`development-guide.md`](development-guide.md)。

## 1. 架构目标

本方案以最小工具链为首要约束。Godot 编辑器、导出模板、Git 和游戏资源应构成首版全部开发依赖，不安装 .NET、Visual Studio、移动 SDK、数据库、容器或云服务。

架构优先级：

1. 下载解压后即可开发，项目可在当前 Windows 电脑本地完成全流程。
2. Local 游戏不依赖网络、账号、平台 SDK 或第三方 addon。
3. 核心规则可以在 `--headless` 模式测试，不依赖 SceneTree 和渲染。
4. 玩法内容数据驱动，表现资源与规则 ID 分离。
5. 架构为已验收需求服务，不预建联机、支付和多平台抽象。

## 2. 技术栈决策

| 能力 | 首版决策 | 约束 |
|---|---|---|
| 引擎 | Godot 4.7.2 stable 标准版 | 锁定 4.7.2，不使用 4.8 dev 构建 |
| 语言 | typed GDScript | 不使用 C#/.NET；公共 API、字段和返回值写类型 |
| 渲染 | Compatibility Renderer + CanvasItem 2D | 面向 D3D11/OpenGL 3.3 级硬件；不用 Forward+ 特效 |
| UI | Control、Container、Theme | 设计分辨率 1920×1080，使用 stretch 和锚点适配 |
| 输入 | InputMap | `ui_*` 与 `combat_*` action 分离，鼠标/键盘首发 |
| 内容 | JSON 规则 + `.tres` 资源目录 + PackedScene | JSON 是规则真源，Resource 只映射表现资产 |
| 存档 | FileAccess/DirAccess + JSON + hash/备份 | 槽位文件保存于 EXE 同级 `savedata/`（可携带），偏好与日志在 `user://`，不使用数据库 |
| 测试 | 自有轻量 headless runner | 不依赖测试 addon；失败返回非零退出码 |
| 构建 | Windows Desktop export preset | Windows x86_64，EXE/PCK 打 ZIP |
| 版本管理 | Git | 提交 `project.godot`、场景、资源、`.uid` 和 export preset |

MVP 不接入 Asset Library 插件。若以后引入 addon，必须记录仓库、提交或版本、许可证、更新策略和替代方案。

## 3. 平台、工具与资源预算

### 3.1 开发环境

当前 Windows 11、i5-8400、16GB、GTX 1060 明显高于 Godot 简单 2D 项目的推荐基线。

最小安装：

- Godot 4.7.2 标准版。
- 对应版本的 Windows export templates。
- Git。
- 可选文本编辑器；默认使用 Godot 内置脚本编辑器。

Godot 官方给出的推荐存储约为 1.5GB（编辑器、模板和缓存）。项目需另给源资源和导出预留 3～10GB；不需要为移动 SDK 或 Visual Studio 预留空间。

### 3.2 运行目标

- Windows 10/11 x86_64。
- Compatibility Renderer。
- 窗口、无边框窗口、全屏。
- 1920×1080 设计分辨率；验证 1366×768、1920×1080、2560×1440。
- 普通用户权限运行，存档写入 EXE 同级 `savedata/`；目录不可写时保存事务按失败路径处理，不静默降级。

## 4. 工程结构

```text
project.godot
export_presets.cfg
src/
  core/                         # 纯规则;不继承 Node
    combat/run_model.gd
    rules/deterministic_rng.gd, content_validator.gd
    replay/event_hasher.gd
  application/                  # GameSession、RunOrchestrator、Save/Upgrade/Content/ReplayService
  presentation/
    art/                        # GameArt 素材注册、共享 UV 网格与怪物动作
    gameplay/                   # 战场渲染与 HUD(CanvasItem 纹理/网格 + 程序特效)
    menus/                      # bootstrap、主菜单、背景
    ui_theme.gd
  infrastructure/
    audio/procedural_audio.gd
    diagnostic_service.gd
  autoload/game_app.gd          # 唯一组合根与应用生命周期
scenes/
  bootstrap.tscn
  main_menu.tscn
  gameplay.tscn
content/
  config/game_rules.json        # 规则真源
  catalogs/localization.json    # 双语文本
tests/                          # 自有 headless runner 与验收脚本
tools/                          # 内容校验、构建清单、发布脚本
docs/
参考/                           # 视觉研究资料,导出排除
```

`.godot/`、导出目录和本地日志不提交。Godot 生成的 `.uid` 文件与资源一起提交，避免引用在不同电脑上漂移。

## 5. 分层与依赖

```text
┌──────────────────────────────────────────────┐
│ Presentation                                │
│ Node2D / Sprite2D / Control / Animation     │
└──────────────────┬───────────────────────────┘
                   │ input intents / view model
┌──────────────────▼───────────────────────────┐
│ Application                                 │
│ GameSession / Orchestrator / Save / Upgrade │
└──────────────────┬───────────────────────────┘
                   │ commands / events
┌──────────────────▼───────────────────────────┐
│ Core                                         │
│ RunModel / Spawn / Combat / Skill / Progress │
└──────────────────┬───────────────────────────┘
                   │ small local adapters
┌──────────────────▼───────────────────────────┐
│ Infrastructure                              │
│ JSON / FileAccess / InputMap / AudioStream  │
└──────────────────────────────────────────────┘
```

依赖规则：

- `core` 脚本继承 `RefCounted` 或只提供静态/纯函数，不继承 `Node`。
- `core` 不调用 `get_tree()`、`Input`、`FileAccess`、`AudioServer`、`Time` 或场景路径。
- `presentation` 只能发送意图和渲染快照，不能直接修改 Profile、HP、Mana 或奖励。
- `application` 持有事务和生命周期，组合 core 与 infrastructure。
- `infrastructure` 不实现伤害、奖励、胜负或升级规则。
- `GameApp` 是唯一 Autoload 组合根；不得把所有模块注册成全局单例。

## 6. 模块职责

### 6.1 Core

> 实现现状：子系统的职责当前合并在 `src/core/combat/run_model.gd` 单文件内，生成/投射物/技能/防御的纯函数已拆至 `spawn_system.gd`、`projectile_system.gd`、`skill_system.gd`、`defense_system.gd`（RunModel 作为门面持有状态并保持 tick 顺序）。进一步按状态对象拆分属已知技术债。

- `RunModel`：本局状态和固定 tick 入口。
- `StageSystem`：Stage 目标、进度、Boss 周期和胜负候选。
- `StageCatalog`：无状态的关卡解析与无尽计划生成。`describe(number)` 为分页 UI、首通奖励返回轻量摘要，`resolve(id)` 仅为当前关卡展开有界出怪计划；规范 ID 为 `stage_%03d`，拒绝同一关卡的别名，避免重复奖励。前 30 关保留编排，后续由 `endless_stages` 统一控制曲线、混合波次、Boss 轮换与性能预算，不缓存无限列表。
- `SpawnSystem`：模板、seed、顺序、位置和间隔。
- `EntityStore`：敌人、投射物、效果和设施的纯数据生命周期。
- `CombatSystem`：命中、护甲、伤害、Fatal Blow、击退和死亡。
- `ProjectileSystem`：弹道、连续碰撞和销毁。
- `SkillSystem`：Mana、冷却、范围效果、状态和打断。
- `SkillCatalog`：三系技能可用性、装备归一化与有效属性的纯规则查询；研究预览、HUD、指示器和战斗共用，避免升级后显示与实际效果不一致。
- `AttackCatalog`：攻击研究的共享有效属性、战斗经验倍率和旧研究退款纯函数。RunModel 在关卡开始计算 `attack_stats`；菜单详情与武器摘要使用同一查询，不重复维护公式。
- `ResearchCatalog`：共享研究等级政策、常量时间深等级报价、等级读取和安全成长算术。`endless: true` 时 `max_level` 只表示原价格区间边界，购买和 UI 必须调用 `can_upgrade`，不能自行比较旧上限；`SkillCatalog` 将无限伤害点数与最多 20 级的附属属性点数分开。研究预览、购买、存档归一化与战斗快照共用规则，见 [无尽研究说明](endless-research.md)。
- `DefenseSystem`：城墙，以及版本 1 的 Lava Moat/Magic Tower。
- `ProgressionSystem`：金币、XP、升级和装备快照。
- `DeterministicRng`：自有整数 RNG，按 stream 隔离生成、暴击和掉落。

核心 API 示例：

```gdscript
class_name RunModel
extends RefCounted

func step(commands: Array[GameCommand]) -> Array[GameEvent]:
    return []

func snapshot() -> RunSnapshot:
    return RunSnapshot.new()
```

实际实现必须返回只读约定的数据，不把可写字典直接暴露给表现层。

### 6.2 Application

- `GameSession`：创建、暂停、恢复、结束 Run，按固定节拍调用 `RunModel.step()`。
- `RunOrchestrator`：加载 Stage、Profile 快照和配置，协调结算。
- `UpgradeService`：校验余额、前置和上限，生成新 Profile。
- `SaveService`：统一存档、备份、迁移和奖励幂等事务。
- `ContentService`：组合 JSON 规则与 `.tres` 资源目录，生成不可变运行配置。
- `ReplayService`：调试构建记录 seed、命令和事件 hash。

### 6.3 Presentation

- `GameplayView`：按只读快照渲染战场。背景/城墙/弩塔/箭矢使用导入纹理，怪物使用共享 ArrayMesh UV 网格动作和快照位置插值，技能/状态继续由 CanvasItem 绘制。无逐实体 Sprite/粒子节点；飘字、特效和死亡立绘队列按预算回收。暂停停止表现层时钟，伤害只来自 core 事件。详见 [素材与动画接入](materials-integration.md)。
- `HudView`：城墙、Mana、Stage、技能、暂停和结算。
- `MenuController`：主菜单、Stage 选择、升级和设置。
- `InputController`：InputMap -> 应用命令。
- `TutorialController`：根据事件推进教学。

表现层可以使用 Godot signal，但规则顺序不能由 signal 连接顺序决定。Application 每 tick 收集 core 返回的有序事件，再分发给视图。

三级技能链中，`skill_cast` 表示一次扣费/施法，`skill_launch` 表示一颗开始下落，`skill_pulse` 表示一颗实际落地。三系统一为单发定点、圆盘内随机倾泻、全战场随机倾泻；独立 `_spell_rng` 生成互不重复且不等间隔的发射 tick 和落点。`RunModel.active_spells` 保存每颗的发射/落地 tick 和有效属性，落地才按当时敌人位置独立结算直击、衰减溅射和状态。`falling_spells` 快照提供在途轨迹，表现层只能插值，爆炸/冰击/落雷与音效由落地事件驱动。Run 结束清空队列，暂停不推进。Profile 的 `equipped_skills` 经 Application 原子保存，每系固定一槽，随后进入的关卡使用不可变装备快照。配置和规则细节见 [`skill-chains-reimplementation.md`](skill-chains-reimplementation.md)。

攻击研究中，Projectile 快照包含实际箭伤、暴击、击退距离和毒伤/时长/间隔。命中系统只使用该快照；敌人保存独立毒计时，固定 tick 跳伤，刷新不重置倒计时。高级猎人的击杀、通关经验经同一纯函数写入事件与结算，沿用永久奖励幂等账本。来源、等级表与边界约定见 [`attack-research-reimplementation.md`](attack-research-reimplementation.md)。

### 6.4 Infrastructure

首版仅实现：

```text
ProfileRepository.load/save
ConfigRepository.load_builtin
InputAdapter.collect_commands
AudioAdapter.play
LocalFileStore.read/write/replace
BuildManifest.load
```

不创建 `CloudSave`、`Store`、`Transport`、`Analytics` 等尚无调用者的接口。

## 7. 场景树设计

### 7.1 Bootstrap

```text
Bootstrap (Node)
└── LoadingUi (Control)
```

`GameApp` 在 Bootstrap 阶段加载配置、验证内容、读取 Profile，然后切换到 MainMenu。初始化失败由 LoadingUi 显示可重试错误。

### 7.2 MainMenu

```text
MainMenu (Control)
├── Navigation
├── StagePanel
├── UpgradePanel
├── SettingsPanel
└── DialogLayer
```

面板通过 MenuController 调用 Application 服务。UI 不读取或写入存档文件。

### 7.3 Gameplay

```text
Gameplay (Node2D)
├── World (Node2D)
│   ├── Background
│   ├── Castle
│   ├── EnemyLayer
│   ├── ProjectileLayer
│   └── EffectLayer
├── GameplayView
├── InputController
├── Hud (CanvasLayer)
└── PauseLayer (CanvasLayer)
```

所有 Local Stage 共用同一个 `gameplay.tscn`，Stage 差异来自配置。不得复制场景形成 `stage_001.tscn`、`stage_002.tscn`。

无尽关卡不再用 `config.stages.size()` 作为解锁、存档归一化、奖励或下一关入口的上限。Application 和 Core 共用 `StageCatalog`；`SpawnSystem` 对生成关使用明确的 `at_tick`/`wave` 字段，不能再次套用旧数量倍率。满员暂停消费出怪队列，空位出现后继续，胜利仍要求队列耗尽且存活敌人清零。HUD 使用 `wave_count`，不能把每只敌人的生成条目数误当作波数。生成计划使用关卡专属 RNG，出怪坐标继续使用运行 seed，技能与战斗随机流互不干扰。公式和边界见 [无尽关卡规则](endless-stages.md)。

## 8. 固定步长、坐标与随机

Project Settings 将 physics tick 配置为 30。`GameSession._physics_process()` 每次只向 core 推进一个整数 tick；渲染可以在 60 FPS 对上一/当前快照插值。

固定更新顺序：

1. tick 增加，更新冷却，生成到期敌人。
2. 按命令顺序处理输入，包括技能校验/扣费/创建投放计划。
3. 推进到期技能发射与落地，结算独立伤害/控制；恢复 Mana。
4. 更新敌人持续状态、移动、攻击与特殊技能。
5. 更新防御设施、箭矢与碰撞伤害。
6. 结算死亡、击杀金币与经验。
7. 处理城墙、胜负和奖励。
8. 排序输出事件和只读快照。

事件顺序：

```text
Spawn -> Command -> Hit -> Damage -> Status -> Death -> Reward -> RunEnd
```

为了减少浮点和版本差异：

- 时间全部使用 tick 或整数毫秒。
- HP、Mana、货币和伤害使用整数。
- Core 位置使用缩放整数 `x_milli/y_milli`，Presentation 转成 `Vector2`。
- 随机使用项目内固定算法，不直接依赖全局 `randf()`/`randi()`。
- 每类随机行为使用独立 stream，增加表现随机不会改变掉落结果。

## 9. 输入与分辨率

InputMap：

```text
combat_aim
combat_fire
combat_select_fire
combat_select_ice
combat_select_lightning
combat_cast
combat_cancel_cast
game_pause
ui_accept
ui_cancel
```

InputController 把 viewport 鼠标坐标直接转成逻辑坐标（项目使用 `canvas_items` 拉伸 + `expand` 宽高比，逻辑画布保持 1920×1080 扩展域，无需 Camera2D；`combat_fire`/`combat_cast` 等动作经 InputMap，瞄准由每物理 tick 的 `aim` 命令轮询鼠标位置），并发出：

```text
AimChanged(x_milli, y_milli)
FireStarted
FireStopped
SkillSelected(skill_id)
CastSkill(x_milli, y_milli)
PauseRequested
```

交互模型（1.0，对应 FR-022/FR-023）：

- **悬停自动射击**：光标位于战场且未悬停任何阻断射击的 HUD 控件（`gui_get_hovered_control()` 为 null 或悬停对象为技能按钮——技能按钮是施法快捷键，不中断射击）时，表现层向 core 发出一次 `fire_started`；光标移入 UI、打开暂停/结算/设置覆盖层、选中法术或处于拖拽施法中时发出一次 `fire_stopped`。开火状态按边沿驱动（状态变化才发命令），不逐帧重复。`settings.auto_fire=false` 时回退为按住左键开火、松手停止的经典模式。
- **拖拽施法**：选中任意阶位即使用 `magic_cursor.gd` 绘制对应元素与阶位，替代十字准星和系统箭头；三阶不再跳过光标。按下左键后，`CanvasItem._draw()` 对一阶绘制直击/溅射圈，对二阶绘制随机落点圆盘，对三阶高亮全战场。光标和预览在恢复屏幕震动变换后绘制。合法性实时着色：Mana、冷却任一不满足即红色，一/二阶还检查目标边界，三阶忽略坐标。松开左键发出 `cast_skill`；释放在 UI 控件上视为取消（发出 `cancel_skill`）；右键/Esc 取消并中断拖拽。释放检测以轮询鼠标按键状态为准，覆盖释放事件被 UI 消耗的路径。进入 UI、暂停、窗口失焦/移出和退出场景时释放自定义指针所有权、恢复系统指针。
- 法术选中与拖拽期间自动射击暂停，避免瞄准冲突；施法完成或取消后悬停射击自动恢复。
- **主页技能装备**：三个 MenuButton 分别枚举同系列技能，保持原生/嵌入窗口的坐标缩放映射；调用 `GameApp.select_skill` 原子保存后重建页首、刷新现有研究详情，不重置研究树选中与滚动。锁定技能跳到对应 `upgrade_id`，不提前装备。
- **全屏倾泻规划（config v10）**：`DefenderSkillSystem.screen_landing_points` 使用独立 `_spell_rng` 从抖动候选格选取分散点，避让一个随施法随机变化的小开口（计入有效溅射半径），再打乱空间顺序。发射时间继续在 90 tick 窗口不放回抽样；落地结算、伤害衰减和状态逻辑不变。升级只改变单发参数，数量、窗口与蓝耗不随研究等级增长。详见技能链说明的覆盖率验收。

设计视口为 1920×1080，stretch 保持宽高适配。HUD 使用 Control anchors/containers，战场 Camera2D 使用可配置逻辑边界。窗口变化只改变显示映射，不改变领域单位和攻击范围。

## 10. 配置与资源目录

规则 JSON 示例：

```json
{
  "config_version": 1,
  "ruleset_version": "classic-inspired-v1",
  "simulation_tick_rate": 30,
  "stages": [
    {
      "id": "stage_001",
      "spawn_order": "seeded_shuffle",
      "enemy_groups": ["melee_basic"],
      "clear_reward": {"coins": 100, "xp": 20}
    }
  ]
}
```

当前已接入 `Gamematerials/` 的 19 张纹理，`src/presentation/art/game_art.gd` 注册稳定 ID 到导入资源的映射，`creature_visuals.gd` 管理只读动作状态。`.tres` 目录是后续更大资源库的可选演进方案，不是当前运行依赖：

```text
enemy_id -> PackedScene / Texture2D / sound_id
weapon_id -> Texture2D / projectile_scene / sound_id
skill_id -> icon / effect_scene / sound_id
```

规则脚本不得通过资源文件推导伤害或奖励。

导出前由 `tools/validate_content.gd` 验证：

- ID 唯一、引用存在。
- 数值非负、概率在 `[0,1]`。
- 冷却和攻击间隔不少于一 tick。
- Stage 有可完成结束条件。
- 升级依赖无环。
- 每个表现 ID 都能加载对应资源。

## 11. 持久化与迁移

存档为可携带的多槽位文件，存放于 EXE 同级的 `savedata/` 目录（编辑器内运行时为项目 `savedata/`），整目录拷贝即可迁移到其他电脑：

```text
<exe_dir>/savedata/slot_1.json        # 活动存档槽位（共 3 个：slot_1..slot_3）
<exe_dir>/savedata/slot_N.json.bak    # 每槽位独立备份
<exe_dir>/savedata/settings.json      # 机器级偏好（音量/语言/分辨率/active_save_slot）
<exe_dir>/savedata/profile.json       # 旧版单档文件；仅在迁移时读取，保留作备份
user://replays/                       # 调试或用户主动导出
user://logs/                          # 限量轮转
```

槽位规则：

- `SaveService.save_profile_slot/load_profile_slot` 按槽位读写；`GameApp` 将所有 Profile 事务路由到 `active_save_slot`（默认 1，保存在 settings 中）。
- 首次启动迁移：slot 1 缺失而旧 `profile.json` 存在时，旧档被槽位 1 采纳并落盘为 `slot_1.json`（旧文件保留不删）。
- 切换存档：先冲刷当前槽位的游戏时长，再加载目标槽位（空槽位立即生成新档），设置写入成功后才切换内存 Profile；任何一步失败都保持原槽位。
- 游戏时长（`stats.playtime_seconds`）由 `GameApp` 缓冲，满 30 秒、结算、返回主菜单或窗口关闭时落盘。
- 无尽段复用原 Profile schema，最高解锁与首通记录保存真实关卡编号，不再截断到 30。归一化时从已有胜利记录恢复下一关，包括旧档第 30 关已通关但最高解锁仍为 30 的情况；不会凭迁移重复发奖。结算仍先原子保存，成功后提交内存状态并启用“下一关”，失败时保持可重试且不开放未保存的解锁。首通水晶对账遍历已有胜利记录，而非有限的前 30 关配置数组。
- 存档管理页读取 `read_slot_summary`（只读摘要：通关数/杀敌数/金币/水晶/时长/最后保存时间），荣誉堂展示同一份统计。

存档信封：

```text
schema_version
app_version
config_version
payload
payload_hash
saved_at_utc
```

保存流程：

1. 写入同目录 `.tmp` 并调用 `flush()`。
2. 重新读取并验证 JSON/schema/hash。
3. 将现有主档移动为 `.bak`。
4. 将 `.tmp` 重命名为主档。
5. 重新读取主档确认；失败则恢复 `.bak`。

结算生成 `run_id + reward_version` 幂等键，与 Profile 一起保存。重复键只返回已有结果，不再次增加金币或 XP。

迁移器按 `v1 -> v2 -> v3` 顺序执行。迁移在内存副本上完成，通过校验后才写新主档；失败不能覆盖旧档。

攻击树使用附加迁移标记 `attack_research_revision`（当前 1），不改变 schema v6。历史三项精通的退款、归档等级与标记由 `AttackCatalog.normalize_profile()` 在副本上一次计算，并随 Application 存档事务一并保存。该标记不进入通用默认补齐，防止旧档提前获得标记而漏迁移；详见攻击研究专项验收。

## 12. Headless 测试

测试入口：

```powershell
godot --headless --path . --script res://tests/run_all.gd
```

`run_all.gd` 负责加载测试列表、捕获断言、打印摘要并以测试失败数作为非零退出结果。测试本身只依赖项目脚本，不依赖 addon。

Core 测试：

- 伤害、护甲、Fatal Blow 和击退。
- Mana、冷却、状态叠加和 Boss 抗性。
- Stage 目标、同 tick 胜负和奖励幂等。
- 固定 seed 的生成顺序和事件 hash。
- 配置验证、Profile 迁移和备份恢复。

场景集成测试：

- Bootstrap -> MainMenu -> Gameplay。
- 鼠标持续射击、技能选择和坐标映射。
- 暂停、重开、退出和结算。
- 三种分辨率、中英文和 UI 缩放。

性能测试：

- 100 敌人/200 投射物运行 5 分钟。
- 60 分钟长局节点数和内存趋势。
- Compatibility Renderer 在集显测试机上的帧时间。

## 13. 性能策略

- 敌人、箭矢、飘字和高频特效使用预热节点池。
- Core 使用紧凑数据数组；Presentation 使用有界动作字典和共享纹理/网格，不为每只怪创建 Node。
- 使用网格或纵向 band 加速空间查询，但不把敌人吸附到 lane。
- 高速箭使用 core 的 swept collision，不依赖 Area2D signal 的处理顺序。
- 粒子数量、屏幕震动和飘字可按画质关闭，不影响规则。
- 先以 100/200 实体门禁优化，不提前引入 ECS addon。

## 14. 错误处理与诊断

- 预期错误返回结构化结果：`ok`、`error_code`、`field_path`、`message_key`。
- 发布日志包含应用版本、Godot 版本、配置版本、场景和错误码。
- 不记录 Windows 用户目录全路径、完整 Profile 或原始输入轨迹。
- 日志最多保留 5 份并限制单文件大小。
- 发布包不发送遥测；玩家可手动导出诊断 ZIP。

## 15. 导出与发布

导出预设名称固定为 `Windows Desktop`：

```powershell
& .\tools\run_pack_preflight.ps1
godot --headless --path . --export-debug "Windows Desktop" Builds/Windows-Dev/DefenderGame.exe
godot --headless --path . --export-release "Windows Desktop" Builds/Windows/DefenderGame.exe
```

`run_pack_preflight.ps1` 不需要 export templates。它从干净提交生成 manifest 和本地 PCK，验证必需/排除资源、Git SHA、配置 hash，并从隔离目录启动该包。该检查只提前验证数据包，不代替正式 EXE 和普通用户环境验收。

导出前必须依次运行内容校验、headless 测试和版本清单生成。清单包含：

```text
app_version
godot_version
git_commit
config_version
config_hash
build_utc
```

正式构建在打 ZIP 前必须校验实际 PCK，并从非管理员进程、隔离 `%APPDATA%` 启动实际 EXE，确认默认档案与设置只写入 `user://`。项目所有者可用 `tools/set_game_license.ps1` 从 MIT 或专有模板生成待审阅许可；源模板不进入 PCK。发布 ZIP 包含 EXE、PCK、最终项目许可、Godot/第三方声明和 README，不写注册表、不要求管理员权限。安装器、代码签名和 Steam 是独立发布阶段。

## 16. 交付分期

1. **骨架**：Godot 工程、目录、GameApp、测试入口和 export preset。
2. **垂直切片**：基础弓、一个敌人、城墙、固定 tick、胜负。
3. **MVP 内容**：三种敌人、三技能、10 Stage、Boss 和结算。
4. **可靠性**：存档、迁移、升级、配置校验和回放金样。
5. **发布**：性能、低配测试、Windows ZIP 和版本清单。
6. **评审后扩展**：完整研究树、武器、防御设施和 Honors。

## 17. 风险与控制

| 风险 | 控制 |
|---|---|
| GDScript 动态类型导致运行时错误 | typed GDScript、严格 warning、headless 测试和小型公开 API |
| SceneTree 逐渐承载规则 | core 禁止 Node/Input/FileAccess，依赖检查和测试直接实例化 RunModel |
| 全局 signal 顺序不确定 | core 返回有序事件数组，signal 只通知表现 |
| 存档损坏或重复发奖 | 临时文件、备份、hash、迁移和幂等 ledger |
| 大量 Node 卡顿 | core 数据与视图节点分离、对象池、空间查询和性能门禁 |
| addon 增加维护负担 | MVP 禁止生产 addon；新增依赖必须 ADR 和版本锁定 |
| 原作数值不完整 | 配置版本、来源字段和回放金样，不将推测写死 |
| 后续要求联机 | Battle 作为独立里程碑，不污染 Local 核心契约 |

## 18. 参考资料

- [Godot release archive](https://godotengine.org/download/archive/)
- [Godot system requirements](https://docs.godotengine.org/en/stable/about/system_requirements.html)
- 完整产品研究和移动跨平台架构见 `main` 分支与 `archive/mobile-cross-platform-v2.0` 标签。
