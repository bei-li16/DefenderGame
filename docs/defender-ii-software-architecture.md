# Defender II Windows / Unity 软件架构

版本：3.0-unity-windows

文档日期：2026-09-01

对应分支：`windows-unity`

目标：使用 Unity 6.3 LTS 在一台 Windows 电脑上完成可离线发布的 2D 单机 MVP

## 1. 架构目标

本方案保留原始设计中最有长期价值的部分：数据驱动、固定步长、可重放规则、原子存档和表现/规则隔离；删除首版不需要的移动平台、云服务、支付、联机和专用服务器。

架构优先级如下：

1. 一名开发者可以在现有 Windows 电脑上安装、运行、测试和发布。
2. Local 核心循环不依赖网络、账号或外部服务。
3. 核心规则容易单测，不被 Unity 场景生命周期绑死。
4. 内容通过配置扩充，不为尚未确定的平台提前建设基础设施。
5. 保留未来迁移的接口边界，但不为接口编写空实现和远程服务。

## 2. 技术栈决策

| 能力 | 首版决策 | 约束 |
|---|---|---|
| 引擎 | Unity 6.3 LTS | 锁定编辑器补丁版本并提交 `ProjectVersion.txt` |
| 语言 | C# | Domain 仅使用 Unity 支持的 .NET API，不引用 `UnityEngine` |
| 渲染 | Built-in 2D / SpriteRenderer | 不启用实时阴影和重型后处理；若需要 2D Lights 再评审 URP |
| UI | uGUI + TextMeshPro | 菜单和战斗 HUD 使用独立 Canvas |
| 输入 | Unity Input System | `UI`、`Combat` 两个 Action Map；鼠标/键盘首发 |
| 配置 | JSON + ScriptableObject 资源目录 | JSON 存规则，ScriptableObject 只关联 Sprite/Audio/Prefab |
| 存档 | 锁定版本的 Newtonsoft JSON + 校验备份 | 不引入 SQLite |
| 测试 | Unity Test Framework + NUnit | EditMode 测 Domain，PlayMode 测场景接线 |
| 构建 | Unity Build Profile / 命令行 | Windows x64；Development 用 Mono，Release 可选 IL2CPP |
| 版本管理 | Git | 小型二进制资源直接 Git；达到阈值后再引入 Git LFS |

不安装或不引用 Addressables、UGS、Netcode、Transport、IAP、Analytics、Remote Config、Android/iOS 模块和 Dedicated Server 模块。首版本地化表可以使用简单 JSON/CSV；只有内容量证明必要时才引入 Localization Package。

## 3. 平台、工具和资源预算

### 3.1 开发机

当前设备 Windows 11、i5-8400、16GB、GTX 1060 足以完成本项目。建议给 Unity 编辑器、项目 `Library`、构建和缓存预留 30～50GB SSD 空间。

最小安装：

- Git。
- Unity Hub。
- Unity 6.3 LTS Windows Editor。
- VS Code + C# 扩展，或 Visual Studio Community 的 Unity 工作负载。
- 仅在 Release 使用 IL2CPP 时安装 Windows Build Support、MSVC C++ 工具和 Windows SDK。

### 3.2 运行目标

- Windows 10 21H1+ / Windows 11 x64。
- 默认 DirectX 11。
- 窗口、无边框窗口和全屏。
- 1920×1080 为设计分辨率，验证 1366×768 和 2560×1440。
- 游戏文件和存档不要求管理员权限。

## 4. 工程结构

```text
Assets/
  Game/
    Domain/                    # Defender.Game.Domain.asmdef，纯 C#
      Combat/
      Entities/
      Progression/
      Rules/
      Replay/
    Application/               # Defender.Game.Application.asmdef
      Session/
      Economy/
      Save/
      Content/
    Presentation/              # Defender.Game.Presentation.asmdef
      Gameplay/
      HUD/
      Menus/
      Tutorial/
    Infrastructure/            # Defender.Game.Infrastructure.asmdef
      Config/
      Persistence/
      Input/
      Audio/
      Build/
    Content/
      Art/
      Audio/
      Prefabs/
      Scenes/
      Config/
      Localization/
  Tests/
    EditMode/
    PlayMode/
    Performance/
    ReplayFixtures/
Packages/
ProjectSettings/
UserSettings/                  # 忽略，不提交
Builds/                        # 忽略，不提交
```

程序集依赖：

```text
Presentation ──> Application ──> Domain
Infrastructure ────────────────> Application / Domain
Tests ─────────────────────────> 被测试程序集
```

禁止 `Domain -> UnityEngine`、`Domain -> Application`、`Application -> Presentation`。测试程序集是唯一允许通过测试可见性访问内部类型的程序集。

## 5. 运行时架构

```text
┌──────────────────────────────────────────────┐
│ Presentation                                │
│ Scene / Sprite / HUD / Menu / Tutorial      │
└──────────────────┬───────────────────────────┘
                   │ commands / view models
┌──────────────────▼───────────────────────────┐
│ Application                                 │
│ GameSession / RunOrchestrator / SaveService │
│ UpgradeService / ContentService             │
└──────────────────┬───────────────────────────┘
                   │ domain commands / events
┌──────────────────▼───────────────────────────┐
│ Domain                                      │
│ Stage / Spawn / Combat / Projectile / Skill │
│ Defense / Progression / RNG / Replay        │
└──────────────────┬───────────────────────────┘
                   │ local ports
┌──────────────────▼───────────────────────────┐
│ Infrastructure                              │
│ JSON Config / File Save / Input / Audio     │
└──────────────────────────────────────────────┘
```

不存在远程后端。所有端口均由同一进程中的本地适配器实现。

## 6. 模块职责

### 6.1 Presentation

- `GameplayView`：根据只读快照同步 Sprite、动画、粒子和音效。
- `HudPresenter`：显示城墙、Mana、Stage、波次、技能和暂停状态。
- `MenuPresenter`：主菜单、Stage 选择、升级、设置和结算。
- `InputPresenter`：把 Input System 回调转换成应用命令，不直接生成箭矢或扣 Mana。
- `TutorialPresenter`：监听领域事件推进教学，不复制战斗判定。

### 6.2 Application

- `GameSession`：创建、暂停、恢复和结束 Run；驱动固定 tick。
- `RunOrchestrator`：加载 Stage、Profile 快照和配置，协调结算。
- `UpgradeService`：验证余额、前置和上限，生成新 Profile。
- `SaveService`：统一存档事务、备份、迁移和恢复。
- `ContentService`：把 JSON 规则和 Unity 资源目录组合成不可变运行配置。
- `ReplayService`：开发构建记录 seed、命令和事件哈希。

### 6.3 Domain

- `StageDirector`：目标、进度、Boss 周期和胜负候选。
- `SpawnDirector`：模板、seed、生成顺序、位置和间隔。
- `EntityStore`：敌人、投射物、状态效果和防御设施的生命周期。
- `CombatSystem`：命中、护甲、伤害、Fatal Blow、击退和死亡。
- `ProjectileSystem`：弹道、连续碰撞和生命周期。
- `SkillSystem`：Mana、冷却、范围伤害和控制效果。
- `DefenseSystem`：城墙，以及后续 Lava Moat/Magic Tower。
- `ProgressionSystem`：XP、金币、升级、武器和技能等级。
- `DeterministicRng`：按 stream 隔离生成、暴击和掉落随机序列。

### 6.4 Infrastructure

首版只保留以下端口：

```text
IProfileRepository.Load() / Save(ProfileEnvelope)
IConfigRepository.LoadBuiltIn() -> GameConfig
IInputSource.Read() -> InputCommand[]
IAudioOutput.Play(SoundId)
IFileSystem.Read / Write / Replace
IClock.MonotonicTicks()
```

接口用于测试替身和平台隔离，不允许创建尚无调用者的 `ICloudSave`、`IStore`、`ITransport` 等空抽象。

## 7. 核心领域模型

```text
PlayerProfile 1──1 Settings
PlayerProfile 1──* UpgradeState
PlayerProfile 1──* WeaponState
PlayerProfile 1──* RewardLedgerEntry
Run 1──1 CombatLoadoutSnapshot
Run 1──1 StageState
Run 1──1 WallState
Run 1──* EnemyState
Run 1──* ProjectileState
Run 1──* StatusEffectState
```

关键字段：

- `PlayerProfile`：`schemaVersion`、`rulesetVersion`、`currentStage`、`coins`、`xp`、升级、武器、技能和设置。
- `Run`：`runId`、`stageId`、`seed`、`tick`、`state`、`kills`、`earnedCoins`、`wall`、`mana` 和实体集合。
- `CombatLoadoutSnapshot`：进入战斗时冻结的武器、升级、技能和防御属性。
- `EnemyState`：连续坐标、HP、速度、攻击参数、护甲、标签、抗性和状态效果。
- `RewardLedgerEntry`：幂等键、来源、数值、状态和配置版本。

实体使用数值 ID 或稳定字符串 ID。Unity `GameObject` 不是领域实体，不进入存档或回放。

## 8. 固定步长与事件顺序

模拟使用 `dt = 1/30s`。渲染可在 60 FPS 插值，但不得用 `Time.deltaTime` 直接改变领域结果。

每个 tick 的固定顺序：

1. 按 `tick, sequence` 消费输入命令。
2. Stage/Spawn 更新并生成敌人。
3. 更新敌人移动、攻击计时和状态效果。
4. 更新防御设施。
5. 更新箭矢、技能投射物和碰撞。
6. 结算命中、伤害、控制、死亡、金币和 Mana。
7. 结算城墙伤害和胜负。
8. 发布有序事件并生成只读快照。

事件顺序固定为：

```text
Spawn -> Command -> Hit -> Damage -> Status -> Death -> Reward -> RunEnd
```

建议公式仅作为初始配置：

```text
arrowDamage = weaponDamageTable[strengthLevel]
fireIntervalMs = max(minIntervalMs, agilityIntervalTable[agilityLevel])
effectiveDamage = max(1, rawDamage * (1 - armor / (armor + armorK)))
fatalDamage = fatalTriggered ? effectiveDamage * 2 : effectiveDamage
mana = clamp(mana + regen - spellCost, 0, maxMana)
```

## 9. 输入、场景和表现

Input System 定义：

```text
UI:       Navigate, Submit, Cancel, Point, Click
Combat:   Aim, Fire, SelectFire, SelectIce, SelectLightning,
          Cast, CancelCast, Pause
```

鼠标像素坐标先由 Camera 转换为世界坐标，再映射到领域逻辑坐标。领域层只接收 `AimChanged(x, y)`、`FireStarted`、`FireStopped`、`SkillSelected`、`CastSkill(x, y)` 和 `PauseRequested`。

场景最小集合：

- `Bootstrap`：依赖组合、配置和存档加载。
- `MainMenu`：主菜单、Stage、升级、设置。
- `Gameplay`：所有 Local Stage 共用，通过配置切换内容。

不得为每个 Stage 复制 Gameplay 场景。

表现对象通过对象池维护；领域创建/销毁事件驱动视图租借和归还。粒子、屏幕震动和飘字可以在低画质关闭，不影响命中和伤害。

## 10. 配置与内容

规则 JSON 示例：

```json
{
  "configVersion": 1,
  "rulesetVersion": "classic-inspired-v1",
  "simulationTickRate": 30,
  "stage": {
    "id": "stage_001",
    "seedPolicy": "per_run",
    "spawnOrder": "seeded_shuffle",
    "enemyGroups": ["melee_basic"],
    "clearReward": {"coins": 100, "xp": 20}
  }
}
```

构建前验证：

- ID 唯一且引用存在。
- 数值非负，概率在 `[0,1]`。
- 冷却和攻击间隔不小于一个 tick。
- Stage 至少有一个可完成的结束条件。
- 升级前置图无环。
- Sprite、Audio、Prefab 资源目录包含所有表现 ID。

ScriptableObject 不保存玩家进度，也不承担规则真源；它只把稳定内容 ID 映射到 Unity 资源。

## 11. 持久化与恢复

存档位置使用 `Application.persistentDataPath`，文件结构：

```text
profile.json
profile.json.bak
settings.json
replays/              # 仅开发构建或用户主动导出
logs/                 # 限量轮转
```

`ProfileEnvelope` 包含：

```text
schemaVersion
appVersion
configVersion
payload
payloadHash
savedAtUtc
```

写入流程：

1. 序列化到同目录临时文件。
2. 重新读取并验证 schema/hash。
3. 将现有主档替换为 `.bak`。
4. 原子移动临时文件为主档。
5. 重新读取主档确认成功。

结算先生成带幂等键的 `RewardLedgerEntry`，然后与 Profile 在一次 SaveService 事务中写入。加载时重复的 ledger 键只能返回已有结果。

## 12. 错误处理与日志

- 预期错误使用结果类型，不依赖异常控制正常流程。
- 配置、存档和资源错误必须包含稳定错误码和字段路径。
- 发布日志记录应用版本、配置版本、场景、错误码和堆栈；不记录用户目录全路径和完整存档内容。
- 日志按文件大小轮转，默认最多保留 5 份。
- 发布构建不发送遥测；用户可以手动打包诊断文件。

## 13. 性能策略

- 敌人、箭矢、飘字和常用特效使用预热对象池。
- 空间查询使用网格或纵向 band，但 band 只优化查询，不限制位置。
- 高速箭使用 swept collision；领域逻辑不依赖 Unity 物理回调顺序。
- Sprite Atlas、音频压缩和批次在内容增长后按 Profiler 证据优化。
- 先以 100 敌人/200 投射物为门禁，不为未经验证的 5000 实体场景引入 ECS。
- 每次性能优化必须保留固定 seed 的结果一致性。

## 14. 测试策略

### 14.1 EditMode

- 伤害、护甲、Fatal Blow、击退。
- Mana、冷却、状态叠加和 Boss 抗性。
- Stage 目标、同 tick 胜负和奖励幂等。
- 固定 seed 的生成与事件 hash。
- Profile 迁移、损坏检测和备份恢复。
- 配置 schema、引用和范围校验。

### 14.2 PlayMode

- Bootstrap、菜单、Gameplay 场景接线。
- 鼠标持续射击和技能目标坐标。
- 暂停、重开、返回菜单和结算。
- 分辨率、窗口模式、UI 缩放和中英文。

### 14.3 性能与构建

- 100 敌人/200 投射物 5 分钟压力场景。
- 60 分钟长局内存趋势。
- 干净 Windows x64 构建并在无 Unity 环境启动。
- Development 和 Release 均运行一组回放金样。

## 15. 构建与发布

| 配置 | 后端 | 用途 | 输出 |
|---|---|---|---|
| Windows Development | Mono | 日常调试、Profiler、回放导出 | `Builds/Windows-Dev/` |
| Windows Release | Mono 或 IL2CPP | 外部测试和正式 ZIP | `Builds/Windows/` |
| EditMode Tests | Unity Test Runner | 领域和配置门禁 | NUnit XML + 覆盖率 |

MVP 默认先用 Mono Release，减少 MSVC/IL2CPP 安装负担。只有发布策略、逆向风险或性能数据证明必要时才切 IL2CPP。

构建脚本必须写入：

```text
appVersion
unityVersion
gitCommit
configVersion
configHash
buildUtc
```

发布包为 ZIP，不写注册表，不要求管理员权限。代码签名、安装器和 Steam 接入是独立发布任务。

## 16. 交付分期

1. **骨架**：Unity 工程、asmdef、Bootstrap、测试和命令行构建。
2. **垂直切片**：基础弓、一个敌人、城墙、固定 tick、胜负。
3. **MVP 内容**：三种敌人、三技能、10 Stage、Boss、结算。
4. **可靠性**：存档、迁移、升级、配置校验、回放金样。
5. **发布**：性能、低配测试、Windows ZIP 和版本清单。
6. **评审后扩展**：完整研究树、武器、设施和 Honors。

## 17. 架构风险与控制

| 风险 | 控制 |
|---|---|
| 为未来平台过度设计 | 范围门禁；没有首版调用者就不创建端口或服务 |
| Unity 场景承载玩法规则 | Domain asmdef 禁止 UnityEngine；规则测试必须可在 EditMode 运行 |
| 存档损坏或重复发奖 | 备份、hash、迁移、ledger 幂等键和故障注入测试 |
| 大量 GameObject 卡顿 | 对象池、快照驱动视图、空间查询和性能基准 |
| 原作数值不完整 | 配置版本、来源字段、回放金样，不把推测写死 |
| 未来加入联机破坏单机 | Battle 必须作为独立 ADR/里程碑，不改写 Local Domain 契约 |

## 18. 参考资料

- [Unity 6 releases](https://unity.com/releases/unity-6)
- [Unity 6.3 system requirements](https://docs.unity3d.com/6000.3/Documentation/Manual/system-requirements.html)
- 完整产品研究和原移动跨平台架构见 `main` 分支与 `archive/mobile-cross-platform-v2.0` 标签。
