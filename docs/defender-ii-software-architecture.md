# Defender II 软件架构文档

版本：2.0  
文档日期：2026-09-01  
适用范围：DroidHen《Defender II》移动端 2D 城堡防守游戏的兼容重制/同类实现  
目标读者：客户端、服务端、游戏玩法、UI、美术、QA、数据分析与运维工程师

## 1. 文档目标与边界

本文把公开资料中可以确认的玩法转化为可落地的软件设计，并给出可调配置、领域模型、状态机、接口和测试边界。它不是原作源码的逆向结果；原作的内部公式、关卡表、资源掉落、武器清单和网络协议未公开，文中标记为“建议实现”或“待实测”的内容不能当作原作事实。

本设计的第一交付目标是一个可离线运行、忠于原作操作和成长结构的 Local 模式，第二目标是原作式实时并行 Battle 模式。首版不包含社交、公会、抽卡、开放世界或复杂剧情系统。

## 2. 调研基线与设计决策

### 2.1 产品识别

范围指 DroidHen 的移动游戏 `Defender II`（Android 包名 `com.droidhen.defender2`），不要与 HAL Laboratory/Williams 的 NES/街机横向射击游戏 Defender II 混淆。Google Play 页面将其归类为 Strategy/Tower defense，支持单人和离线标签，开发者为 DroidHen。

截至调研日，Google Play 显示 1,000 万以上下载、4.1 分、约 29.1 万条评价，标记为离线、单人、含广告和应用内购买；App Store 显示 iPhone/iPad 版本、原作兼容 iOS/iPadOS 12+、英语和韩语、应用内购买。Android 约于 2012-03-22 发布，iOS 约于 2012-09-10 发布。原作商店元数据与本项目首发基线不同：新项目锁定 iOS/iPadOS 15+、Metal 和 A12 性能目标。版本号和商店政策会继续变化，不得作为玩法常量写入代码。

### 2.2 证据分级

| 等级 | 定义 | 使用原则 |
|---|---|---|
| A | DroidHen、Google Play、Apple App Store 等官方页面 | 可进入产品基线；仍需注明平台和版本 |
| B | 2012-2013 年同期截图、评测，多来源互相印证 | 可形成兼容需求；数值保留版本开关 |
| C | 玩家论坛、攻略、成就数据库、长期评论 | 用于补充内容表和设计风险，不单独决定公式 |
| D | 单一玩家评论或截图推断 | 只记录为待验证假设 |

任何数值配置都必须带 `sourceGrade`、`sourceVersion`、`verifiedAt`。社区资料中出现冲突时，以 A 级描述优先，未有 A 级答案则保留多个版本配置，不能选择看起来最合理的数字冒充原作事实。

### 2.3 A/B 级资料确认的机制

以下行为直接来自商店说明或多来源描述，作为产品基线：

* 敌人以持续增强的波次攻击城堡，并会出现 Boss。
* 玩家通过触控或手柄瞄准、发射箭矢；拖拽技能图标施放法术。
* 城墙可升级以增加生命值。
* Strength 增加箭矢伤害，Agility 增加射击频率。
* 武器/弓可选择和装备；Power shot 可击退敌人；Fatal Blow 有概率造成双倍伤害。
* Lava Moat 在敌人掉入时造成灼烧；Magic Tower 产出施法所需 Mana，并可进行魔法攻击。
* Local mode 目标是击败波次；Battle mode 以存活时间更长者获胜。
* 产品宣传曾明确提到新 Battle mode、Lava moat、Magic tower、Research center、crossbows。
* 横屏战斗场景为连续 2D 区域：城堡和弩在左，敌人从右侧全屏进入；没有可放置塔格或固定道路。
* 按住战场可连续射击；HUD 有城墙生命、Mana、三个元素技能、金币、水晶、Stage 和进度。
* Local 按 Stage 线性推进；Stage 结束显示 XP、击杀、剩余生命百分比、金币和水晶，约每 10 Stage 出现 Boss。
* 成长分为四页：攻击、魔法、防御和弓/弩。玩家具有 XP 与等级，历史截图显示 Battle 在等级 2 解锁。
* 击杀获得金币，过关获得金币、水晶和 XP；历史评测记录过关 2 水晶、Battle 胜者额外 1 水晶，但该数值只适用于早期版本。
* Battle 为两名玩家并行面对同步敌群的生存竞赛，界面展示对手状态、计时和双方结果；双方死亡相差一秒也可决定胜负。

### 2.4 C 级资料补充的内容

同期攻略和截图确认了较完整的研究项：

* 攻击：Strength、Agility、Power Shot、Poisoned Arrow、Fatal Blow、Multiple Arrows、Senior Hunter。
* 魔法：Mana Research；Lightning Strike -> Thunder Storm -> Ragnarok；Glacial Spike -> Frost Nova -> Ice Age；Fire Ball -> Meteor -> Armageddon。
* 防御：City Wall -> Magic Tower -> Magic Power/Splash；City Wall -> Lava Moat -> Burn/Entangling Lava。
* 武器：Power、Hurricane、Phantom 三条成长线，以及用 250 水晶购买、随玩家等级自动成长的 Final Fantasy 弓/弩。
* Honors/成就：Big Spender、Great Mage、Monster Hunter、Defender、Tactician Master、Fire/Ice/Lightning Master，各三级，共 24 项。

社区对平衡的共识是优先 Agility、Strength、Multiple Arrows、冰系和城墙；雷系适合打断，火系范围大但耗 Mana；Magic Tower、Poisoned Arrow 和早期 Lava Moat 常被评价为投入回报低。这些是平衡诊断，不是必须照抄的强弱关系。

### 2.5 资料不足与冲突

原作没有公开内部公式、完整敌人名称、技能倍率、生成算法或网络协议。社区记录还存在明显版本差异：Fatal Blow 上限有 9/15 两种记录，City Wall 上限有 21/23/30 三种记录但都出现 320 HP，早期和后期的属性上限不同。实现时必须将这些内容放入 `RulesetVersion`，不能硬编码或混成一套表。

### 2.6 第一代 Defender 与 Defender II 的演进

第一代与第二代应视为同一核心战斗循环的两个规则版本，而不是两个完全独立的产品。2011 年第一代评测描述的是固定在城堡上的单一弩炮、点击/按住射击、最多同时装备三个法术、金币/水晶购买弩炮和法术升级，以及逐级增强的单机敌群；当时只有 Local，且没有 Battle、Honors、Lava Moat、Magic Tower、XP 等第二代系统。[第一代评测](https://cglfgamerzreview.wordpress.com/2011/12/02/another-android-review-defender/)[第一代评测](https://2shotsofgeek.com/index.php/2012/03/09/a-tiny-twist-on-defense-defender-review/)

2012 年第二代评测明确称其“基本沿用第一代、重点扩充商店/成长”，并列出新增在线模式、熔岩沟、自动攻击魔法塔、更多弩、Research Center/属性节点和成就系统；第二代的敌人类型整体延续第一代，仅增加投石/弹射类等新威胁。[jeuxvideo.com 对比评测](https://www.jeuxvideo.com/articles/0001/00017345-defender-ii-test.htm)[DroidHen Google Play](https://play.google.com/store/apps/details?id=com.droidhen.defender2)

| 能力/资产 | Defender（第一代） | Defender II（第二代） | 架构决策 |
|---|---|---|---|
| 核心战斗 | 固定城堡弩炮，单机波次，按住连续射击 | 保留同一操作和波次，加入更多敌人/Boss 调整 | 复用 `CombatSystem`、`ProjectileSystem`、`StageDirector` |
| 玩法模式 | Local/单机；同期评测称无尽关卡 | Local + 在线 Battle，同一敌群并行生存 | `ModeRules` 策略注入，不复制战斗逻辑 |
| 法术 | 9 种法术池，最多 3 个 active；火球可升级为陨石 | 火/冰/雷三元素链与三个 HUD 槽，Mana/冷却继续沿用 | `SkillSystem` 数据驱动；槽位规则版本化 |
| 成长/资源 | 金币升级弩炮、生命；水晶升级法术、Mana 和局内回 Mana | 增加 XP/玩家等级、Research Center、更多弩、Final Fantasy 自动成长 | `ProgressionSystem` 扩展字段并保留迁移器 |
| 防御设施 | 主要是城墙生命和玩家手动弩炮 | 新增 Lava Moat、Magic Tower（自动攻击/提供 Mana） | `DefenseSystem` 可选实体；第一代配置不生成设施 |
| 成就/称号 | 无第二代 Honors 体系 | 24 项三级 Honors，部分提供实际战斗/经济加成 | `HonorService` 仅在 II 规则集启用 |
| 关卡奖励 | 早期评测记为胜利最多 2 水晶、Boss 4 水晶；失败可继续刷金币 | 结算字段增加 XP、击杀、生命%、金币/水晶；Battle 胜者有额外水晶 | `RewardLedger` + `rulesetVersion`，禁止跨版套用掉落 |
| 武器获取 | 多把弩/升级，但没有 II 的等级解锁体系 | 通过等级解锁更多弩；Final Fantasy 需 250 水晶并按等级成长 | `WeaponCatalog` 支持 unlock policy 和自动成长表 |
| 保存/服务 | 第一代评测提到设备本地多存档，无在线同步 | 第二代仍以本地档为主，后续商店/平台版本持续修复 | 原子存档、可选云备份、版本迁移；不假设官方云存档 |

兼容实现的最小边界：`defender-1` 只加载核心 Local、基础技能/弩和金币/水晶经济；`classic-2012` 在其上打开 XP、四页研究、设施、Honors 和 Battle。两个规则集共享实体、事件和回放 schema，但不得共享会改变掉落、上限或胜负的隐式常量。

### 2.7 第二代发布与更新证据

App Store 版本历史显示 1.0（2012-09-06）、1.1（2012-10-17）、1.1.1（2012-11-11，注明“Battle Mode is coming!”），之后 1.2 增加金币/水晶促销，1.3 增加 Gift Pack，1.4-1.9 主要是 Bug 修复、性能优化和平台适配。[App Store 版本历史](https://apps.apple.com/us/app/defender-ii/id550081851)

因此更新系统必须区分“内容规则更新”和“维护更新”：内容更新增加 `rulesetVersion`/配置迁移，维护更新保留规则和回放兼容；商店价格、礼包、广告和平台隐私字段由远程商品/平台适配层管理，不能写入领域逻辑。当前商店仍显示 1.9、iOS 12+、广告和 IAP，但这些是可变平台元数据，只用于发布配置和 QA 矩阵。

### 2.8 媒体与玩家意见对工程的约束

媒体正面评价集中在“短局、操作直接、升级组合多、敌群变大时有爽感”；负面意见集中在广告压缩战斗区域、音效质量一般、在线模式类型单一、Boss 难度跳变和高阶段重复/资源瓶颈。[Android Central 评测](https://www.androidcentral.com/defender-2-review-wave-defense-with-magic-and-big-honkin-crossbow)[jeuxvideo.com 评测](https://www.jeuxvideo.com/articles/0001/00017345-defender-ii-test.htm)

玩家评价还报告高阶段刷关次数过多、晶体不足、IAP 诱导感、购买后不到账、卸载/换设备丢进度、返回键退出和更新后卡顿。实现上必须提供失败局可积累的金币、可观测的水晶收入、商店收据重试/退款处理、原子存档/可选云备份、返回键确认、长局性能预算和可回滚配置；这些是质量需求，不代表必须复制原作的失衡。

## 3. 产品概念模型

一局游戏由“Status/研究准备 -> Stage 战斗 -> 结算”组成。玩家控制城堡左侧固定弩炮，在连续 2D 战场上向触点方向射击；敌人从屏幕右侧不同纵向位置进入，向城墙移动或在射程点停下远攻。玩家的直接火力、三个元素法术、熔岩沟和上下两座魔法塔共同处理敌人。敌人抵达攻击位置后伤害城墙，城墙生命归零即失败。

Local 模式是线性 Stage 推进：每个 Stage 有敌人组成、数量/持续时间、随机生成顺序和结束条件；每 10 Stage 的 Boss 周期有多份同期资料支持。Battle 模式是无尽强度递增的并行竞赛，两名玩家收到同一生成序列，先倒下者失败。

局外成长由金币、水晶、XP/等级和四页 Research Center 驱动。金币主要来自击杀和结算，水晶来自过关、Battle、Honors 或购买；失败仍保留击杀金币。所有成长属性由 Profile 持久化，进入战斗时生成只读 `CombatLoadoutSnapshot`，战斗中使用生成时的属性快照。

### 3.1 世界与表现设定

公开商店文案只确认“城堡受到怪物波次攻击”的高层设定，没有正式角色名或地图年表。官方/历史截图展示了哥特式城堡、发光魔法塔、熔岩沟、奇幻弩炮，以及拳套怪、尖刺球、法师、巨人、龙骑士等敌人。首版采用可替换的明亮奇幻动作塔防主题，强调剪影、箭矢命中、`Fatal!` 字样、元素爆炸和城墙受击，不依赖长剧情。

表现层必须把设定做成数据和资源标签：`faction`、`biome`、`bossTitle`、`waveBanner`、`musicSet`、`vfxTheme`。这样后续可以在不改领域逻辑的情况下替换为不同主题或地区版本。任何新剧情、角色或世界观文案均需由产品确认后再进入本地化表。

## 3.2 技术栈与平台决策

本项目采用以下唯一首发技术方案；除非架构评审批准，不在实现阶段同时维护另一套引擎或网络栈。

| 层/能力 | 决策 | 版本/约束 | 选择理由 |
|---|---|---|---|
| 游戏引擎 | Unity 6.3 LTS | 锁定 LTS 编辑器版本，提交 `ProjectSettings`、`Packages/manifest.json` 和 `packages-lock.json` | 2D 移动端、触控、商店、Profiler 和跨平台构建成熟；Unity 官方将 6.3 标为 LTS，并支持 Android/iOS 构建 |
| 语言/编译 | C#，规则程序集使用 .NET Standard 2.1 兼容 API | 禁止在 Domain 使用 `UnityEngine`；启用 nullable、显式数值转换和 analyzers | 共享客户端、服务器、回放和单元测试；减少浮点/平台差异 |
| 渲染 | URP 2D Renderer、Sprite Atlas、Shader Graph（仅表现层） | 目标 60 FPS；默认关闭后处理和实时阴影 | 适合横屏 2D、低端移动机，资源和批次可控 |
| 运行时 UI | uGUI/Canvas + TextMeshPro | HUD 使用 Screen Space；菜单与战斗分离 Canvas；所有文案本地化 key | 战斗 HUD 的尺寸、安全区和触控命中区可预测，便于复刻历史界面 |
| 输入 | Unity Input System | Action Map：`UI`、`LocalCombat`、`BattleCombat`；触控、鼠标、手柄映射同一命令 | 统一按下/移动/抬起和手柄；Domain 只接收命令 |
| 资源 | Addressables + Sprite Atlas | 远端内容必须带 catalog/hash；首发包包含 Local 前 20 Stage 资源 | 支持分包、缓存、回滚；避免一次性加载全部敌人/特效 |
| 配置 | JSON（Newtonsoft.Json）+ ScriptableObject 资源索引 | JSON 只存可审计规则；运行时转不可变 `GameConfig`；发布前 schema 校验 | 研究树、奖励和波次需要多态字段、版本和来源追踪 |
| 领域模拟 | 自研固定步长纯 C# 模拟 | 30 tick/s；关键计数使用 `int64`；随机使用可重放 PCG/XorShift 流；显示层可 60 FPS 插值 | 100 敌人/200 投射物规模不需要 ECS；优先可读性和跨端确定性 |
| 本地存档 | SQLite（SQLite-net 或同等 ADO.NET 适配）+ 加密/校验备份 | `profile.db`、`run_snapshot`、`reward_ledger`、`purchase_receipt` 分表；事务 + 原子替换 | 支持迁移、幂等奖励和崩溃恢复；不依赖网络 |
| 身份/云存档 | Unity Authentication + Cloud Save（可选登录绑定） | 首次匿名登录；用户主动绑定 Apple/Google；云存档冲突采用版本号和人工选择 | UGS 官方提供跨设备身份与 Cloud Save 集成；Local 不因登录失败阻断 |
| Battle 会话 | Unity Multiplayer Services SDK（Sessions/Matchmaker/Lobby） | 2 人房间；匹配元数据包含等级、升级评分、ruleset/config hash | 统一会话、匹配和跨平台玩家连接 |
| Battle 网络 | Netcode for GameObjects + Unity Transport；生产使用 Linux Dedicated Server，开发可用 Relay | 服务端权威；客户端只发命令；快照 10 tick；UDP/DTLS，必要时 WSS 回退 | 两人、小规模 GameObject 场景适合 NGO；与现有单机场景复用成本低。若未来扩展到大规模竞争，再评估 Netcode for Entities |
| Battle 服务端 | Unity Dedicated Server build（无渲染）+ `BattleAuthority` | 每房间独立模拟；服务端保存 seed、命令序列、快照和结果签名；主机迁移不作为生产依赖 | 避免客户端决定奖励；与 Domain 共享规则程序集 |
| 业务后端 | ASP.NET Core 8 LTS `Profile/Receipt/Support API`；PostgreSQL 16；Redis 7（限流/短期匹配状态） | REST/JSON，OpenAPI；服务到服务使用 mTLS/短期 JWT；所有写入幂等 | 收据验证、客服恢复、审计和跨平台账户不应依赖客户端；数据库适合账本和查询 |
| 支付 | Unity In-App Purchasing 适配 Google Play Billing / Apple StoreKit 2 | 商品为消耗型金币/水晶包与礼包；收据先服务端验证再授予；研究时 Google Play Billing 9.1.0 为参考版本，具体由 Unity IAP 兼容矩阵锁定 | 统一商店 API，同时保留平台收据原文摘要、退款和补发能力 |
| 广告 | MVP 不接入；运营阶段使用 `IAdsService` 适配 Unity LevelPlay 或经批准的供应商 | 广告回调不能直接改 Domain 余额；奖励广告必须服务端/本地幂等 | 媒体指出广告会压缩战斗区域，先保证核心体验；供应商可替换 |
| 遥测/配置 | UGS Analytics/Remote Config；敏感审计写入业务后端 | 事件 schema 固定，匿名 `installId`；远程配置签名、灰度、回滚 | 快速观察武器、元素、Boss 和经济平衡，同时保持规则可追溯 |
| 测试 | Unity Test Framework（EditMode/PlayMode）、NUnit、Unity Performance Testing、Multiplayer Play Mode | 每个 ruleset 有回放金样；设备验收覆盖 Android/iOS 真机 | 验证确定性、输入、断线和性能，不以手工试玩替代自动化 |
| 构建/发布 | Git + Git LFS；GitHub Actions（Windows 构建机 + macOS 构建机）；Fastlane/商店 CLI | 分支保护、代码审查、构建产物 SHA-256、符号文件和 Addressables catalog 归档 | 资源较多且需要 Android/iOS 双端签名；构建可复现、可回滚 |

### 3.3 应用平台与发布范围

* **首发平台**：Android 8.0（API 26）及以上，ARM64，横屏；Google Play App Bundle（AAB），目标 API/target SDK 按发布时 Google Play 要求，构建机使用 Unity 官方配套 Android SDK/NDK/OpenJDK。
* **首发平台**：iOS/iPadOS 15 及以上，A12 或更新 SoC 作为性能目标，Metal，横屏；通过 Xcode/Apple Developer 签名提交 App Store。历史原作支持更低系统不构成新项目的兼容承诺。
* **不纳入首发**：Windows、WebGL、macOS 原生、主机和 Android TV。所有平台相关能力必须通过 `Infrastructure` 适配器隔离；未来新增平台不得修改 Domain 或回放格式。
* **屏幕与输入**：支持 16:9、19.5:9 和 4:3 平板；以安全区内的逻辑横屏坐标模拟；触控为首要输入，鼠标/手柄作为桌面和测试输入。
* **最低性能设备**：Android 中端 ARM64、4 GB RAM；iOS A12、3 GB RAM。目标是 30 tick/s 模拟、60 FPS 渲染；低于基线只保证 Local 可运行，不保证 60 FPS。
* **网络策略**：Local 首次启动、教学、战斗、结算和存档不要求网络；Battle、云存档、排行榜、内购收据确认和遥测需要网络。网络不可用时必须显示原因和重试，不得把 Local 锁死。

### 3.4 工程目录和程序集

```text
Assets/
  Game/
    Domain/                  # Defender.Game.Domain.asmdef，纯 C#
      Combat/ Entities/ Progression/ Rules/ Replay/
    Application/             # Defender.Game.Application.asmdef
      Session/ Match/ Economy/ Save/ Content/
    Presentation/            # Defender.Game.Presentation.asmdef
      Battle/ HUD/ Menus/ Tutorial/ Localization/
    Infrastructure/          # Defender.Game.Infrastructure.asmdef
      Config/ Persistence/ Platform/ Transport/ Telemetry/
    Content/                 # Addressables groups、Sprite、Audio、VFX、Localization
  Tests/
    EditMode/ PlayMode/ Contract/ Performance/ ReplayFixtures/
Server/
  BattleAuthority/            # Unity Dedicated Server build，共享 Domain/Application
Backend/
  ProfileApi/ ReceiptApi/      # ASP.NET Core 8 LTS
  migrations/ openapi/
```

程序集依赖只能从上到下：`Presentation -> Application -> Domain`，`Infrastructure -> Application/Domain`；Domain 不反向引用任何 Unity 或平台程序集。每个程序集启用 asmdef、nullable 和分析规则，禁止通过 `InternalsVisibleTo` 绕过模块边界（测试程序集除外）。

### 3.5 关键第三方包和锁定规则

`Packages/manifest.json` 至少包含 Input System、Addressables、Localization、UGUI、TextMeshPro、Newtonsoft JSON、Test Framework、Performance Testing、Multiplayer Services、Netcode for GameObjects、Unity Transport、Multiplayer Play Mode 和 Authentication/Cloud Save/Analytics/Remote Config。具体包版本必须与 Unity 6.3 LTS 的验证矩阵一致并提交 lock 文件；升级包时先跑完整回放、Battle 断线、支付沙盒和真机性能套件。

不得直接在 Domain 调用 SDK。所有 UGS、IAP、广告、SQLite、系统返回键和生命周期回调都通过已有端口（如 `ITransport`、`IStore`、`IProfileRepository`、`IClock`）实现；若供应商更换，只允许修改 Infrastructure 和组合根。

### 3.6 构建配置矩阵

| 产物 | Unity Build Target | 编译后端/架构 | 图形与运行参数 | 签名/发布 |
|---|---|---|---|---|
| Android Development | Android | IL2CPP、ARM64；Development/Autoconnect Profiler | Vulkan 优先、OpenGL ES 3 回退；横屏；Script Debugging 仅开发包 | debug keystore；内部测试轨道 |
| Android Release | Android | IL2CPP、ARM64；Managed Stripping Level 为 Medium，禁止剥离 Domain DTO/反射类型 | Vulkan/ES3 按设备分级；纹理压缩 ETC2/ASTC 分档；AAB、Split APK by ABI 不作为商店产物 | Play App Signing；上传密钥存 CI secret；生成 mapping/symbols |
| iOS Development | iOS | IL2CPP、ARM64；符号和 Development 检查 | Metal；横屏；开启 Xcode 日志；不启用 bitcode | Apple Development provisioning；真机测试 |
| iOS Release | iOS | IL2CPP、ARM64；Strip Engine Code；Link XML 保留序列化类型 | Metal；ASTC；按设备分级 Addressables；IPA/Archive | App Store distribution；Fastlane match/签名证书由 CI 管理 |
| Battle Dedicated Server | Linux Server | IL2CPP、x86_64（容器）或 ARM64（经压测批准）；无渲染窗口 | 固定 30 tick/s；关闭音频、Addressables 视觉资源和平台 SDK；健康检查端口 | 容器镜像按 git SHA 发布；运行时仅读取签名配置 |
| EditMode/Domain Tests | Windows/macOS CI | .NET/Unity Test Framework；不需要 GPU | 固定时钟、RNG、文化区和时区；输出 NUnit XML、覆盖率和回放 hash | CI 工件保留 90 天 |

构建配置必须通过 `BuildProfile` 资产集中管理，禁止工程师直接在场景或脚本中检测平台后改玩法参数。Android/iOS/Server 的 `rulesetVersion`、`configHash` 和资源 catalog 必须在启动日志中打印；Release 包关闭调试菜单和作弊命令。

## 4. 总体架构

采用“客户端本地确定性模拟 + 生产环境权威对战服务”的分层结构。Local 不依赖后端；Battle 生产链路必须经过 Dedicated Server，Relay 只用于开发、测试和受控灰度：

```text
┌────────────────────────────────────────────────────────┐
│ Presentation                                          │
│ HUD / 触控、手柄输入 / 瞄准层 / 菜单 / 教学 / 本地化     │
└───────────────────────┬────────────────────────────────┘
                        │ Commands / ViewModels
┌───────────────────────▼────────────────────────────────┐
│ Application                                             │
│ GameSession、RunOrchestrator、UpgradeService、          │
│ EconomyService、HonorService、MatchService、SaveService  │
└───────────────────────┬────────────────────────────────┘
                        │ domain commands/events
┌───────────────────────▼────────────────────────────────┐
│ Domain (纯逻辑，可无图形运行)                            │
│ StageDirector、SpawnDirector、EntitySystem、CombatSystem、│
│ ProjectileSystem、SkillSystem、DefenseSystem、            │
│ Economy/Progression、HonorSystem、Rules/Collision、RNG    │
└───────────────────────┬────────────────────────────────┘
                        │ ports
┌───────────────────────▼────────────────────────────────┐
│ Infrastructure                                          │
│ 渲染/音频适配、输入适配、SQLite/文件存档、               │
│ 配置加载、遥测、HTTP/WebSocket、平台支付/广告            │
└────────────────────────────────────────────────────────┘

服务端组件：Auth/Profile、Matchmaking、Battle Authority、Leaderboard、Config、Receipt、Telemetry。Local 客户端在后端不可用时仍可运行；Battle 没有权威房间时不得降级为客户端互信或隐式异步模式。
```

领域层不得依赖 Unity/Unreal/Android/iOS API；这样可以用同一套规则驱动客户端、服务器、回放和自动化测试。

### 4.1 部署拓扑

```text
Android/iOS Client
  | HTTPS (Profile/Config/Receipt)       | UTP/DTLS (Battle commands/snapshots)
  v                                       v
API Gateway/WAF -------------------- Battle Matchmaker
  |                                      |
  +--> ProfileApi --> PostgreSQL         +--> Dedicated Server pool (Linux)
  +--> ReceiptApi --> platform validators       |
  +--> SupportApi --> audit/read model          +--> BattleAuthority (Domain + Application)
  +--> Config/Telemetry                         +--> Redis session/rate-limit state

UGS: Authentication / Cloud Save / Remote Config / Analytics / Multiplayer Services
Platform: Google Play Billing / StoreKit 2 / Apple Game Center (optional achievements)
```

* API Gateway 只暴露 HTTPS 443，强制 TLS 1.2+、请求 ID、JWT 校验、限流和版本路由；Dedicated Server 仅开放 UTP/DTLS 端口和健康检查，不直接暴露数据库。
* Battle 房间固定 2 个玩家、1 个服务器进程内模拟；服务器故障由 Matchmaker 标记房间失败并返回可重试状态，不进行无验证主机迁移。
* PostgreSQL 保存账户绑定、Profile 版本、奖励账本、收据和客服审计；Redis 只保存短期匹配/连接状态，丢失后可重建。
* Remote Config/Addressables 发布必须先写入 staging 环境，通过回放、签名和灰度检查后再切 production；客户端保留上一个可用 catalog/config。

## 5. 模块职责与接口

### 5.1 客户端模块

| 模块 | 职责 | 主要接口 |
|---|---|---|
| `GameView` | 绘制连续 2D 战场、城堡、弩炮、敌人、投射物和特效；只订阅只读状态 | `render(GameSnapshot)` |
| `InputAdapter` | 将按下/移动/抬起和手柄转为瞄准、持续射击、拖放施法命令 | `pointerDown/Move/Up()`, `cast()` |
| `HudPresenter` | 显示城墙 HP、Mana、Stage 进度、金币/水晶、三个元素槽与暂停 | `bind(GameViewModel)` |
| `Status/Research` | Local/Battle、XP/等级、Honors、四页研究树和装备 | `start()`, `upgrade()`, `equip()` |
| `Tutorial` | 首次进入时分步解释射击、技能、熔岩沟、魔法塔 | `advance(stepId)` |
| `Localization` | 中英文及后续语言的文本、数字、无障碍标签 | `t(key, args)` |

### 5.2 应用层模块

* `GameSession`：创建、暂停、恢复、结束一局；维护固定时间步与生命周期。
* `RunOrchestrator`：读取模式规则与 Stage 配置，协调生成、Stage 结算、失败保留金币和奖励。
* `UpgradeService`：校验货币、前置条件、等级上限，产生不可变的 Profile 新版本。
* `LoadoutService`：校验武器和火/冰/雷三个固定元素槽，生成 `CombatLoadout`。
* `EconomyService`：处理金币、水晶、Mana 战中补充、奖励幂等和应用内购买收据。
* `HonorService`：累计 24 项三级 Honors 的进度、解锁效果并同步平台成就。
* `SaveService`：保存 Profile、设置、未完成局快照；使用原子写入和版本迁移。
* `MatchService`：Battle 模式按战力匹配、同步生成流、房间生命周期、对手状态、断线重连和裁决。
* `ReplayService`：记录输入命令和随机种子，支持回放与问题复现。

### 5.3 领域层模块

* `StageDirector`：控制 Local 线性 Stage、目标、时间/进度、Boss 周期和 Stage 结束条件。
* `SpawnDirector`：按模板与种子控制敌人组成、纵向坐标、间隔、批次和随机顺序；Battle 两端共用同一流。
* `EntitySystem`：维护敌人、箭矢、法术投射物、塔、效果实例的生命周期和空间索引。
* `CombatSystem`：统一处理命中、伤害、暴击/Fatal Blow、护甲/抗性、击退和死亡。
* `SkillSystem`：处理技能资源消耗、冷却/充能、范围、持续时间和叠加规则。
* `DefenseSystem`：城墙、熔岩沟、魔法塔的触发、攻击和资源产出。
* `ProgressionSystem`：XP/等级、金币/水晶、四页研究树、武器解锁与 Final Fantasy 自动成长。
* `HonorSystem`：监听累计事件，完成 Big Spender 等 Honors 并生成永久修正。
* `Rules`：模式胜负、目标波次、时间上限、暂停政策和难度修正。
* `DeterministicRng`：以局种子和事件序号产生随机结果；禁止使用不可复现的系统随机数。

领域层建议只暴露命令和事件：

```text
Command: PointerPressed, AimChanged, PointerReleased, CastSkill, RefillMana,
         PauseRun, UpgradePurchased, WeaponEquipped
Event:   ArrowSpawned, HitResolved, EnemySpawned, EnemyDied, WallDamaged,
         CurrencyGranted, ManaChanged, StageStarted, StageCleared, BossSpawned,
         XpGranted, HonorProgressed, HonorUnlocked, MatchStarted, MatchResult,
         PurchaseGranted, RunEnded
```

### 5.4 基础设施端口

```text
IClock.nowTicks() -> int64
IRandom.next(stream, min, max) -> value
IProfileRepository.load/save(Profile)
IConfigRepository.load(version) -> GameConfig
ITransport.send/receive(Message)
IPlatformAchievements.unlock(id)
IStore.purchase(productId) -> Receipt
IReceiptVerifier.verify(receipt) -> PurchaseGrant
IAudio.play(SoundId)
IAnalytics.track(Event)
```

接口实现可替换；单元测试使用内存存储、固定时钟、固定 RNG 和空渲染器。

### 5.6 关键协议契约

#### Profile API

```http
GET  /v1/profile                 -> ProfileEnvelope
PUT  /v1/profile                 {baseVersion, operations[], clientIdempotencyKey}
POST /v1/profile/restore         {backupId, expectedVersion}
```

`ProfileEnvelope` 至少包含 `playerId`、`profileVersion`、`schemaVersion`、`rulesetVersion`、XP/等级、金币/水晶、研究等级、武器、三个元素槽、Honors、累计统计和 `updatedAt`。服务端使用乐观并发控制；版本冲突返回 409 和最新档，不静默覆盖。

#### Receipt API

```http
POST /v1/receipts/verify
     {platform, productId, purchaseTokenOrReceipt, clientIdempotencyKey}
->   {status, grantId, currencyDeltas[], receiptState, retryAfterMs}
```

收据服务校验商品 ID、签名、用户绑定、购买状态和是否已消费；成功后在 `RewardLedger` 与 `PurchaseReceipt` 同一事务中写入授予。客户端只能展示 `currencyDeltas`，不能自行计算商品数量。`pending`/网络错误返回可重试状态，退款由平台回调或定时对账触发撤销/冻结策略。

#### Battle 协议

```text
MatchReady(matchId, rulesetVersion, configHash, stageTemplateId, seed,
           normalization, serverTick, snapshot)
ClientCommand(matchId, clientTick, sequence, type, payload, inputHash)
ServerSnapshot(matchId, serverTick, ackSequenceByPlayer, entityDelta,
               opponentSummary, stateHash)
MatchResult(matchId, winnerPlayerId, reason, stats, rewardGrantId, signature)
```

命令只允许 `AimChanged`、`FireStarted`、`FireStopped`、`CastSkill` 和 `ResyncRequest`；服务端按 `serverTick -> playerId -> sequence` 排序，重复序列返回原 ACK。快照丢失超过阈值触发全量同步；`stateHash` 用于检测客户端篡改和回放偏差。

### 5.5 依赖规则与执行边界

* `Presentation` 只能调用 Application 用例和订阅 ViewModel，不能直接修改 `Run`、`Profile` 或奖励余额。
* `Application` 负责事务边界和生命周期；每次 `UpgradePurchased`、`RunEnded`、`HonorUnlocked`、`PurchaseGranted` 必须在一个可恢复的写入事务中完成。
* `Domain` 不访问网络、文件、平台支付或渲染 API；所有随机性、时间和配置通过端口注入。
* `Infrastructure` 不实现玩法规则，只负责端口适配、序列化、传输、平台回调和资源加载。
* Battle 服务端和客户端共享 Domain 的规则包与事件 schema；服务端拥有最终时钟、RNG、奖励和胜负裁决。

建议目录边界如下，便于多人并行开发和独立测试：

```text
src/
  domain/{combat,entities,progression,rules,replay}
  application/{session,match,economy,save,content}
  presentation/{battle,hud,menus,tutorial,localization}
  infrastructure/{config,persistence,platform,transport,telemetry}
tests/{domain,application,contract,performance,replay-fixtures}
```

## 6. 核心领域模型

### 6.1 实体关系

```text
PlayerProfile 1──1 Loadout
PlayerProfile 1──* UpgradeState
PlayerProfile 1──* WeaponInventory
PlayerProfile 1──* HonorProgress
Run 1──1 CombatLoadoutSnapshot
Run 1──1 StageDirector
Run 1──* Enemy
Run 1──* Projectile/Effect
Run 1──1 WallState
Run 1──1 MoatState
Run 1──1 MagicTowerState
BattleMatch 1──2 RunSnapshot
PlayerProfile 1──* RewardLedgerEntry
PlayerProfile 1──* PurchaseReceipt
```

### 6.2 关键实体字段

* `PlayerProfile`：`playerId`、`schemaVersion`、`rulesetVersion`、`level/xp`、`currentLocalStage`、`coins/crystals`、`battleWins/losses`、四页研究等级、`weapons[]`、三个元素槽、Honors 进度、累计统计和设置。
* `CombatLoadout`：武器快照、研究/荣誉修正快照、`fireSkillId/iceSkillId/lightningSkillId`、城墙/熔岩沟/魔法塔等级、模式修正。
* `Run`：`runId`、`mode`、`stageId`、`seed`、`tick`、`state`、`stageProgress`、`kills`、`elapsedMs`、本局金币、`wall`、`mana`、实体集合。
* `Enemy`：`entityId`、`archetypeId`、连续 `position(x,y)`、`hp/maxHp`、移动/攻击/风行动画状态、速度、攻击伤害/间隔、护甲、标签、抗性和状态效果。
* `Weapon`：`weaponId`、`family`（Base/Power/Hurricane/Phantom/FinalFantasy）、等级、基础伤害、射击间隔、弹速、散布、箭数、属性加成、解锁条件和自动成长表。
* `Skill`：`skillId`、`element`、`tier`、目标方式、Mana 成本、冷却、范围、持续时间、伤害脉冲、控制效果、打断等级和装备规则。
* `DefenseStructure`：`kind`、`level`、`hp`、`attackProfile`、`manaPerSec`、`range`、`enabled`。
* `HonorProgress`：`honorId`、`tier`、`counterValue`、`claimed`、`modifierIds[]`、平台成就同步状态。
* `RewardLedgerEntry`：`idempotencyKey`（`runId + rewardVersion` 或收据 ID）、来源、币种、数量、状态、创建时间和规则版本；只允许从 `pending` 到 `committed` 一次转换。
* `PurchaseReceipt`：平台、商品 ID、原始收据摘要、验证状态、退款状态、授予时间和审计字段；原始收据不写入普通分析日志。

### 6.3 历史兼容内容表

下表用于构建 `classic-2012` 规则集，精确倍率仍需目标版本实测：

| 分支 | 已确认项目 | 社区记录的上限/行为 |
|---|---|---|
| 攻击 | Strength、Agility | Agility 30；Strength 早晚版本上限不同 |
| 箭矢 | Power Shot、Poisoned Arrow、Fatal Blow | Power/Poison 常见上限 9；Fatal 记录有 9/15 冲突 |
| 多重/经验 | Multiple Arrows、Senior Hunter | Multiple 30，最终约 5 箭；Hunter 9，额外 XP |
| 魔法基础 | Lightning Strike、Glacial Spike、Fire Ball | 常见记录上限 9 |
| 魔法中阶 | Thunder Storm、Frost Nova、Meteor | 常见记录上限 9 |
| 魔法高阶 | Ragnarok、Ice Age、Armageddon | 后期记录上限 30 |
| 防御 | City Wall、Magic Tower、Lava Moat | Wall 等级记录冲突但常见 320 HP；Tower 2；Moat 3 |
| 防御强化 | Magic Power、Splash、Burn、Entangling Lava | 记录上限 99/20/99/20 |

官方明确 Fatal Blow 是概率双倍伤害；攻略中“一击必杀”的说法与官方冲突，不采用。上限仅用于兼容数据输入，不作为新规则集的平衡目标。

## 7. 战斗模拟设计

### 7.1 时间步与更新顺序

使用固定模拟步长 `dt = 1/30 s`（建议实现，目标设备可降级渲染但不得改变模拟结果）。每个 tick 严格按以下顺序执行：

1. 消费并排序输入命令（按 `clientTick`、`sequence`）。
2. 更新 Stage/Spawn Director 和生成计时器。
3. 更新敌人路径、攻击计时器与状态效果。
4. 更新熔岩沟与魔法塔。
5. 更新玩家箭矢、技能投射物和碰撞。
6. 结算命中、伤害、击退、死亡、奖励和 Mana。
7. 处理城墙伤害、胜负条件和波次清理。
8. 发布领域事件并生成只读 `GameSnapshot`。

同一 tick 的死亡应在伤害结算阶段统一处理；事件排序固定为 `Spawn -> Hit -> Damage -> Death -> Reward -> End`，防止客户端/服务端因遍历顺序不同而分歧。

### 7.2 建议实现公式

以下是可运行的初始公式，不代表原作已证实数值；所有常数放在 `GameConfig`。

```text
arrowDamage = weapon.baseDamage * (1 + strengthLevel * strengthPerLevel)
fireInterval = weapon.fireInterval / (1 + agilityLevel * agilityPerLevel)
effectiveDamage = max(1, rawDamage * (1 - armor / (armor + armorK)))
fatalProc = rng < fatalChance(fatalBlowLevel)
singleArrowDamage = arrowDamage * multiArrowDamageFactor(multipleArrowsLevel)
finalArrowDamage = fatalProc ? effectiveDamage(singleArrowDamage) * 2 : effectiveDamage(singleArrowDamage)
powerShotKnockback = weapon.knockback + powerShotLevel * knockbackPerLevel
mana = clamp(mana + manaRegenPerSec * dt - spellCost, 0, manaMax)
```

经典规则集应使用离散表而不是线性猜测：历史截图中 Strength Lv.1 为 24、下一等级 28，Agility 每级显示增加 2；这些只证明早期 UI 的离散增量，不能外推所有等级。新规则集才可采用 `strengthPerLevel` 等公式。`fatalMultiplier=2` 来自官方说明，属于确定行为。

### 7.3 碰撞与目标选择

* 战场采用连续 2D 世界坐标，不建立塔格或硬 lane；可用纵向 band 优化空间查询，但 band 不得限制敌人位置。
* 弩炮固定在左侧，朝最近触点/手柄准星方向发射；按住输入时由武器射击间隔持续产生箭矢，抬起立即停止。
* 多重箭同一次射击生成多条带角度差的轨迹；每支箭独立碰撞，是否能同时命中同一大体型敌人由规则集配置。
* 魔法塔位于城墙上方和下方，采用固定攻击间隔；社区观察的有效范围约为从城墙到屏幕 3/4，需实测后换成世界单位。
* 近战敌人推进到城墙/熔岩区域后攻击；远程敌人在 `preferredAttackX` 停下并执行蓄力攻击；巨人可受击退重走，龙骑士的喷火蓄力可被高打断等级攻击中断。
* 高速箭使用 swept collision，范围法术使用快照命中或周期查询，不能依赖渲染帧碰撞。

### 7.4 状态效果

统一使用 `StatusEffectInstance`：`effectId`、`sourceId`、`stacks`、`remainingMs`、`maxStacks`、`stackPolicy`。经典首版支持 `Poison`、`Burn`、`Freeze`、`ActionDelay`、`Stun/Interrupt`、`Knockback`、`MoatEntangle`。每个效果明确 Boss 抗性、刷新/叠加和击杀归属；冰系表现为停止/冻结，雷系偏动作延迟与打断，火系为高 Mana 的范围/连续伤害。

### 7.5 Stage、批次与难度

Local Stage 配置必须数据驱动：敌人总量/时间、批次组成、纵向生成范围、顺序随机池、生成间隔、Boss、奖励和结束条件均可配置。同期评测称同一 Stage 的总量和组成接近固定，但顺序有随机性；因此使用“模板 + seed 洗牌”，而不是固定脚本或完全随机。

```text
enemyHp = baseHp * (1 + stage * hpGrowth)
enemyDamage = baseDamage * (1 + stage * damageGrowth)
enemySpeed = baseSpeed * (1 + min(stage * speedGrowth, speedCap))
```

经典规则集默认每 10 Stage 出现 Boss；Stage 10、20 等应作为回放金样验证。Battle 使用无尽批次和强度阶梯，所有累计计数使用 `int64` 并支持大数 UI。TapTap 单一评论称 Battle 存活超过 3 分钟会提高下一局难度，该行为列为 D 级假设，不进入默认规则。

### 7.6 四页研究树

研究系统不是通用自由节点图，而是四个固定领域的有向无环图：

```text
Attack:  Strength ─┬─ Power Shot ───────┐
                   └─ Poisoned Arrow ───┼─ Multiple Arrows ─ Senior Hunter
         Agility ──┬─ Poisoned Arrow ───┤
                   └─ Fatal Blow ───────┘

Magic:   Mana Research ─┬─ Lightning Strike ─ Thunder Storm ─ Ragnarok
                        ├─ Glacial Spike ───── Frost Nova ──── Ice Age
                        └─ Fire Ball ───────── Meteor ───────── Armageddon

Defense: City Wall ─┬─ Magic Tower ─ Magic Power / Splash
                    └─ Lava Moat ─── Burn / Entangling Lava

Weapon:  Base ─┬─ Power Lv.1 ...
               ├─ Hurricane Lv.1 ...
               ├─ Phantom Lv.1 ...
               └─ Final Fantasy (按玩家等级自动成长)
```

节点必须支持 `currencyType`、价格、前置等级、版本上限和效果表。经典 UI 每种元素装备一个法术，HUD 固定三个按钮；不实现任意三个同元素技能的通用槽位。

### 7.7 Honors

Honors 由累计统计事件驱动，三级阈值为：

| Honor | Lv.1 / Lv.2 / Lv.3 |
|---|---|
| Big Spender | 花费金币 50,000 / 250,000 / 1,000,000 |
| Great Mage | 用水晶恢复 Mana 60 / 300 / 1,000 |
| Monster Hunter | 击杀 5,000 / 30,000 / 200,000 |
| Defender | 完成 Stage 50 / 150 / 350 |
| Tactician Master | Battle 获胜 30 / 100 / 300 |
| Fire/Ice/Lightning Master | 对应元素施法 200 / 1,000 / 3,000 次 |

历史截图确认 Big Spender 提供每击杀额外金币，其他 Honor 的具体永久加成只在低可信攻略中出现，必须配置化并等待实测。平台成就解锁失败不得回滚游戏内 Honor。

## 8. 数据驱动配置

推荐使用 JSON/二进制表，发布包带 `configVersion` 和校验哈希；服务器可下发经过签名的平衡配置。

```json
{
  "configVersion": 1,
  "rulesetVersion": "classic-2012",
  "sourceGrade": "B",
  "sourceVersion": "2012-screenshot-review",
  "verifiedAt": "2026-09-01",
  "economy": {
    "killReward": {"currency": "coins", "amountTable": "classic.killCoins"},
    "localClearReward": {"currencies": ["coins", "crystals", "xp"]},
    "failedRunKeepsKillCoins": true,
    "battleWinnerBonus": {"currency": "crystals", "amountTable": "classic.battleWinner"}
  },
  "battle": {
    "mode": "realtime_parallel",
    "sameSpawnStream": true,
    "battleNormalization": "classic_equal_loadout",
    "unlockLevel": 2,
    "disconnectGraceMs": 10000
  },
  "stage": {
    "progression": "linear",
    "bossEveryStages": 10,
    "spawnOrder": "seeded_shuffle"
  },
  "weapons": [
    {
      "id": "crossbow_basic",
      "kind": "crossbow",
      "baseDamage": 18,
      "fireIntervalMs": 700,
      "projectileSpeed": 26,
      "knockback": 0.4,
      "pierce": 0
    }
  ],
  "skills": [
    {
      "id": "glacial_spike",
      "element": "ice",
      "tier": 1,
      "slot": "ice",
      "targeting": "point",
      "manaCost": 25,
      "cooldownMs": 6000,
      "radius": 2.5,
      "effects": [{"type": "slow", "value": 0.65, "durationMs": 3000}]
    }
  ],
  "honors": {
    "tiers": 3,
    "count": 24,
    "thresholdSource": "exophase-gamefaqs"
  }
}
```

配置校验规则：ID 唯一、引用存在、数值非负、百分比在 `[0,1]`、冷却不小于模拟步长、Boss 不得引用不存在的技能。客户端启动时校验失败应回退到上一个已知良好版本并记录错误。

## 9. 模式与网络

### 9.1 Local 模式

完全本地确定性运行；允许暂停，后台恢复时根据平台策略冻结或结束局。结算先写入本地待提交队列，再异步上报分析事件。离线可玩是公开产品标签，因此核心玩法不应强制网络。

### 9.2 Battle 模式

原作式 Battle 应按“实时并行、同一敌群”设计：两名玩家同时面对相同的生成序列，分别保护自己的城墙，先倒下者失败；界面显示对手存活状态、计时和结果。同期资料还称双方装备相同，因此经典兼容规则集默认启用 `battleNormalization`，避免局外投入直接决定胜负。异步镜像可作为低成本排行榜/重赛功能，但不能作为 Battle 主流程的产品文案。

推荐使用权威服务器或可验证的确定性会话：

* 服务端持有 RNG、波次、伤害和胜负；客户端仅发送瞄准、开火、施法命令。
* 房间创建时下发 `matchId`、`rulesetVersion`、`stageTemplateId`、`seed`、`battleNormalization` 和初始快照；两端消费相同的 `SpawnEvent(tick, sequence, archetypeId, position)`。
* 消息包含 `matchId`、`tick`、`sequence`、`command`、`payload`、`clientHash`；服务端拒绝过期、重复或超速命令。
* 服务端每 10 tick 广播压缩快照；客户端预测本地输入并在快照到达时回滚重放。
* 断线宽限 10 秒（建议值），超时按投降/失败处理；重连需要最近快照和未确认命令。
* 结果由服务端签名，客户端不得直接修改奖励或排名。

匹配优先按玩家等级和升级评分配对，逐步放宽范围并记录等待时间；若不启用归一化，必须在匹配和结果页展示装备差异。对手状态只同步必要摘要（存活、城墙百分比、当前 Stage/波次、击杀、计时），不发送对手输入坐标。

## 10. 持久化、迁移与恢复

使用 SQLite 或带校验的单文件存档。Profile、装备、升级和设置独立表；未完成 Run 存储 `schemaVersion`、`configVersion`、`seed`、tick 和必要实体状态。写入采用临时文件/事务 -> fsync -> 原子替换；保存损坏时回滚到最近备份。

迁移器按版本递增执行，例如 `v1 -> v2` 增加技能槽，`v2 -> v3` 拆分武器字段。迁移失败不得覆盖原档，应显示恢复选项并上报匿名错误码。

## 11. 性能、稳定性与安全指标

* 目标设备：Android 8+/iOS 15+ 的中端设备；具体最低机型在性能测试后锁定。
* 模拟 30 tick/s；战场同时 100 个敌人、200 个投射物时逻辑帧耗时 p95 < 10 ms，渲染 60 FPS 设备 p95 < 16.7 ms。
* 首屏冷启动 < 3 s（不含首次资源解压），局内内存增量 < 150 MB，连续 30 分钟无增长趋势。
* 所有存档输入、远程配置、奖励请求做 schema 校验；Battle 结算必须服务端校验，防止改速、改伤害、重复领奖。
* 不记录原始触控坐标等不必要个人数据；分析事件使用随机 `installId`，提供隐私同意和删除入口。

## 12. 可观测性

事件最少包括：`run_started`、`wave_started`、`enemy_spawned`、`skill_cast`、`wall_damaged`、`boss_spawned`、`run_ended`、`upgrade_purchased`、`match_result`。字段包含 `appVersion`、`configVersion`、`mode`、`stage`、`seedHash`、`durationMs`、`wave`、`reason`，不包含账号明文。

关键仪表板：崩溃率、ANR、首屏耗时、局完成率、各波失败率、技能使用率、Battle 断线率、配置回滚次数。日志分为 debug/info/warn/error，生产环境默认关闭逐箭矢 debug 日志。

## 13. 测试策略

* 领域单测：伤害、护甲、暴击、击退、状态叠加、Mana、城墙、Boss、波次条件、RNG 重放。
* 属性测试：固定 seed 时重复运行得到相同事件序列；实体数量上限内不泄漏；任何伤害不会把 HP 变为 NaN/负无穷。
* 集成测试：Profile 保存迁移、配置校验、局暂停恢复、断线重连、结算幂等。
* 客户端测试：不同宽高比、刘海/安全区、触控拖拽、手柄、低帧率、横竖屏策略、中文/英文和无障碍。
* 性能测试：100/200/500 敌人压力、长局 60 分钟、低端机热降频、后台切换。
* 回放金样：每个版本保存若干 `seed + command log`；领域逻辑变更必须明确回放兼容策略。

## 14. 交付分期

1. **MVP**：单场景、Local 线性 Stage、基础弓、三种敌人、城墙、波次、暂停/结算、存档。
2. **战斗完整**：Strength/Agility、Power/Hurricane/Phantom 武器、Power Shot、Fatal Blow、火/冰/雷三槽技能、Mana、熔岩沟、魔法塔、Boss。
3. **成长与运营**：四页 Research Center、24 项三级 Honors、更多关卡/敌人、配置热更新、遥测、广告/内购适配。
4. **Battle**：同一敌群的实时并行权威对战、归一化装备、断线重连、签名结算；异步回放/排行榜作为补充。

## 15. 主要风险与缓解

| 风险 | 影响 | 缓解 |
|---|---|---|
| 原作数值不可得 | 手感和难度偏差 | 全量数据表、录屏对比、A/B 平衡、配置版本化 |
| 移动端输入精度不足 | 瞄准挫败 | 触控坐标映射、目标吸附可配置、手柄支持、输入延迟测试 |
| 长局实体过多 | 卡顿/耗电 | 对象池、空间索引、实体上限、逻辑与渲染解耦 |
| Battle 被作弊 | 排名和经济受损 | 服务端权威结算、命令校验、速率限制、异常回放审计 |
| 断线/存档损坏 | 进度丢失 | 原子写入、备份、迁移器、重连快照、幂等结算 |

## 16. 参考资料

* [Google Play：Defender II（DroidHen）](https://play.google.com/store/apps/details?id=com.droidhen.defender2) —— 官方商店说明、核心机制、模式、平台标签。
* [Neoseeker：Defender II](https://www.neoseeker.com/defender-ii/) —— 复述官方玩法说明与模式。
* [AppBrain：Defender II](https://www.appbrain.com/app/defender-ii/com.droidhen.defender2) —— 包名、版本/平台要求等第三方元数据。
* [Skich：Defender II](https://skich.app/games/defender-ii) —— 发布日期、类型与玩家内容入口。
* [Gamermenu：Defender 2](https://gamermenu.blogspot.com/p/blog-page.html) —— 玩家攻略对技能树、冰/火/雷法术、Power/Hurricane/Phantom 弩和升级方向的补充观察，仅作线索，不作为精确数值来源。
* [Galaxy of Geek：Defender II review](https://galaxyofgeek.com/2012/04/15/review-defender-ii-android-monsters-crossbows-and-fireballs-oh-my/) —— 同期评测对按住连续射击、击杀金币、过关水晶、失败保留金币、随机顺序和十关 Boss 的观察。
* [Gamebase Taiwan 攻略](https://news.gamebase.com.tw/news/detail/96090041) —— 研究节点、元素效果、Boss 打断和装备建议；数值与强弱判断需版本化。
* [Unwire 截图与介绍](https://unwire.hk/2012/03/27/great-tower-defence-game-defender-ii/news/) —— 2012 年界面截图：四页成长、Stage 结算、Battle 在等级 2 解锁、Honors 和商店类别。
* [App Store：Defender II](https://apps.apple.com/us/app/defender-ii/id550081851?platform=watch) —— iOS 平台、广告/IAP、更新历史和兼容性元数据。
* [Exophase 成就表](https://www.exophase.com/game/defender-2-android/achievements/) / [GameFAQs 成就表](https://gamefaqs.gamespot.com/android/839892-defender-ii/cheats) —— 24 项、三级 Honors 阈值。
* [Arqade：Final Fantasy bow](https://gaming.stackexchange.com/questions/82246/when-does-the-final-fantasy-bows-stats-surpass-those-of-phantom-lv-9) / [Magic Tower range](https://gaming.stackexchange.com/questions/64506/what-is-the-range-for-magic-tower) —— 社区对武器成长和魔法塔射程的观察。
* [Italian Defender II review](https://www.it-blog.ro/review-defender-ii) / [MobileWorld24 review](https://mobileworld24.pl/2012/03/30/bron-swego-zamku-defender-ii-juz-w-google-play/) —— Battle 同敌群、装备公平性、匹配风险和单机流程的同期描述。
* [TapTap Defender II 讨论](https://www.taptap.cn/app/1591/topic) —— 无尽波数等玩家观察；单一评论不作为默认规则。
* [CGLF 第一代 Defender 评测与更新笔记](https://cglfgamerzreview.wordpress.com/2011/12/02/another-android-review-defender/) —— 第一代的九法术/三槽、单机、资源和 Final Fantasy 弓演进记录。
* [2 Shots Of Geek 第一代评测](https://2shotsofgeek.com/index.php/2012/03/09/a-tiny-twist-on-defense-defender-review/) —— 第一代固定弩炮、短局、法术和每十关 Boss 的同期体验。
* [Android Central Defender 2 评测](https://www.androidcentral.com/defender-2-review-wave-defense-with-magic-and-big-honkin-crossbow) —— 第二代控制、升级、Battle、广告/音效和体验评价。
* [Unity 6 releases](https://unity.com/releases/unity-6) / [Unity 6.3 system requirements](https://docs.unity3d.com/6000.3/Documentation/Manual/system-requirements.html) —— Unity LTS、Android/iOS 构建和编辑器工具链基线。
* [Unity Multiplayer netcode](https://docs.unity.com/multiplayer/netcode/netcode) / [Multiplayer Services sessions](https://docs.unity.com/en-us/mps-sdk/sessions) —— NGO/Entities 选择、Sessions 和实时网络边界。
* [Unity Cloud Save](https://docs.unity.com/en-us/cloud-save/get-started) / [Unity Authentication](https://docs.unity.com/en-us/authentication/use-cases) —— 匿名身份、跨设备绑定和云存档接入。
* [Google Play Billing integration](https://developer.android.com/google/play/billing/integrate.html) —— 商品查询、服务端验签、发放和消耗/确认生命周期。
