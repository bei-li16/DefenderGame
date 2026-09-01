# Defender II 需求文档

版本：2.0  
文档日期：2026-09-01  
需求级别：可用于 MVP 立项、拆分任务和验收  
范围：DroidHen《Defender II》风格的 2D 城堡防守游戏；默认兼容规则集为 `classic-2012`

## 1. 目标与成功标准

### 1.1 产品目标

玩家通过精准射击、技能施放和局外升级，抵御逐渐增强的敌人波次，保护城墙并挑战更高阶段；同时提供 Local 生存玩法和 Battle 竞争玩法。游戏应支持离线完成核心单机局，操作在触控设备上可单手完成，也可用手柄。

### 1.2 世界与表现设定

公开资料没有提供原作的完整故事设定。本项目采用可替换的默认设定：玩家是边境城堡瞭望塔上的守卫者，使用弓/弩和法术抵御从荒野或传送门出现的怪物，城墙、熔岩沟和魔法塔组成纵深防线；阶段 Boss 是攻城军的首领。美术和音频采用明亮奇幻、强轮廓、高对比反馈，保证敌人、箭矢、技能和城墙受击在小屏上可辨识。设定文本、敌人称谓和 Boss 名称必须全部走本地化 key，不能散落在代码或贴图中。

### 1.3 MVP 成功标准

* 新玩家在 60 秒内完成教学并成功发射箭矢、施放一次技能。
* 一局 Local 可从开始运行到胜负结算，不依赖网络，不丢失进度。
* 在目标中端设备上 100 个同时敌人时保持 30 tick/s 模拟和稳定画面。
* 规则由配置驱动；不改代码即可调整敌人、波次、武器和技能数值。
* 关键领域测试覆盖率不低于 80%，核心胜负/伤害路径达到 100% 分支覆盖。

### 1.4 技术栈与应用平台（已决策）

本项目首发技术方案固定为 Unity 6.3 LTS、C#、URP 2D Renderer、uGUI/TextMeshPro、Input System、Addressables 和 JSON + ScriptableObject 资源索引。战斗规则放在无 `UnityEngine` 依赖的纯 C# Domain 程序集中，客户端、Dedicated Server、回放和 EditMode 测试共享该程序集。

| 项目 | 首发决策 | 需求约束 |
|---|---|---|
| Android | Android 8.0/API 26+、ARM64、Google Play AAB、横屏 | 目标设备 4 GB RAM；以 Unity 配套 SDK/NDK/OpenJDK 构建；不得依赖 Google Play 才能运行 Local |
| iOS/iPadOS | iOS/iPadOS 15+、Metal、横屏、App Store | A12/3 GB RAM 为性能目标；Xcode/Apple 签名；Local 不因 Apple 登录失败阻断 |
| 后续平台 | Windows 仅作为后续端；首发不支持 WebGL/macOS/主机 | 平台 API 只能通过 Infrastructure 适配器接入 |
| Battle | Unity Multiplayer Services SDK + Netcode for GameObjects + Unity Transport；生产 Linux Dedicated Server，开发 Relay | 2 人房间、服务端权威、10 tick 快照、断线宽限配置化；NGO 与 Domain 解耦 |
| 业务后端 | ASP.NET Core 8 LTS、PostgreSQL 16、Redis 7、REST/OpenAPI | Profile、收据、审计和客服恢复接口必须幂等；服务端不得接受客户端最终奖励 |
| 云服务 | Unity Authentication、Cloud Save、Matchmaker/Lobby/Relay、Analytics/Remote Config | 匿名登录可选绑定 Apple/Google；Cloud Save 冲突按版本号解决；Remote Config 带签名和回滚 |
| 支付 | Unity IAP，适配 Google Play Billing/Apple StoreKit 2 | 金币/水晶为消耗型商品，服务端验签后发放；退款、重复收据和补发可审计 |
| 测试/构建 | Unity Test Framework、Performance Testing、Multiplayer Play Mode、Git LFS、GitHub Actions、Fastlane | 固定 seed 回放、真机性能、支付沙盒和双客户端 Battle 作为合并门禁 |

Unity 6.3 LTS 官方支持移动端构建；Unity Multiplayer 文档对小规模 GameObject 项目提供 Netcode for GameObjects，对竞争型专用服务器建议 Netcode for Entities。由于本项目 Battle 仅 2 人且需复用单机 GameObject 场景，首发选 NGO；若未来扩展到大规模竞技，再单独评审 Entities 迁移。[Unity 6 LTS](https://unity.com/releases/unity-6)[Unity Multiplayer netcode](https://docs.unity.com/multiplayer/netcode/netcode)

Google Play Billing 的购买生命周期要求“查询商品 -> 发起购买 -> 服务端验证 -> 发放 -> 消耗/确认”；因此 FR-082/FR-090 的收据幂等和补发是强制要求，不能由客户端购买回调直接加币。[Google Play Billing 集成](https://developer.android.com/google/play/billing/integrate.html)

## 2. 研究结论与可信度

### 2.1 证据分级与兼容契约

官方 Google Play 说明确认触控/手柄射箭、拖拽施法、城墙升级、Strength/Agility、武器、Power shot、Fatal Blow、Lava Moat、Magic Tower、Local/Battle 及 Boss；商店还将产品标为单人、离线、含广告和应用内购买。[Google Play](https://play.google.com/store/apps/details?id=com.droidhen.defender2)

2012 年同期截图/评测补充了连续 2D 战场、按住连续射击、四页成长、Stage 结算字段、等级 2 解锁 Battle、击杀金币/过关水晶、失败保留金币和约每十关 Boss。[Galaxy of Geek](https://galaxyofgeek.com/2012/04/15/review-defender-ii-android-monsters-crossbows-and-fireballs-oh-my/) [Unwire 截图](https://unwire.hk/2012/03/27/great-tower-defence-game-defender-ii/news/)

`classic-2012` MUST 遵守下表的行为契约；数值仍由配置表提供，不能散落在客户端代码中：

| 领域 | 兼容要求 | 证据/实现备注 |
|---|---|---|
| 战场 | 连续 2D 横屏；城堡/弩在左，敌人从右侧不同纵向位置进入 | B 级截图；不得实现固定 lane |
| 射击 | 指针按住期间按武器间隔连续发箭，移动可持续改变瞄准 | B 级同期评测 |
| Local | 线性 Stage；目标完成即胜，城墙归零即败；常见每 10 Stage Boss | A/B；Stage 组成近似固定、顺序用 seed 洗牌 |
| 结算 | 展示 XP、击杀、剩余生命%、金币、水晶；失败仍保留击杀金币 | B 级截图/评测，早期过关水晶约 2，必须版本化 |
| Battle | 两端同时面对同一敌群，比较存活时间/结果；等级 2 解锁 | B 级截图与同期评测；默认实时并行、同装备归一化 |
| 成长 | Attack、Magic、Defense、Weapon 四页；火/冰/雷三个元素槽 | B/C 级截图和攻略；节点、价格、上限配置化 |
| Honors | 8 个主题、每个 3 级，共 24 项；统计事件驱动 | C 级成就数据库；游戏内效果以配置为准 |

证据等级：A=官方页面，B=同期截图/多来源评测，C=攻略/论坛/成就库，D=单一评论或推断。每个配置值 MUST 带 `sourceGrade`、`sourceVersion`、`verifiedAt`；冲突值并存于不同 `rulesetVersion`，不得擅自取平均。

### 2.2 已知内容与冲突

攻略记录的研究链为：Strength/Agility -> Power Shot、Poisoned Arrow、Fatal Blow -> Multiple Arrows -> Senior Hunter；Mana Research -> Lightning/Glacial/Fire 三条链，各自延伸 Thunder Storm/Frost Nova/Meteor，再到 Ragnarok/Ice Age/Armageddon；City Wall -> Magic Tower 或 Lava Moat，再到各自强化；武器包括 Power、Hurricane、Phantom 和 250 水晶购买的 Final Fantasy 自动成长线。[Gamebase 攻略](https://news.gamebase.com.tw/news/detail/96090041) [Gamermenu](https://gamermenu.blogspot.com/p/blog-page.html)

官方明确 Fatal Blow 为概率双倍伤害；攻略中“一击必杀”与官方冲突，需求采用双倍伤害。Fatal Blow 上限存在 9/15 版本冲突，City Wall 上限存在 21/23/30 冲突但均出现 320 HP 记录，必须由规则版本和实测快照决定。[JVC 玩家论坛](https://www.jeuxvideo.com/forums/1-14935-3333-1-0-1-0-les-limites.htm)

### 2.3 社区反馈转化原则

玩家常建议优先 Agility、Strength、Multiple Arrows、冰系和城墙；雷系用于打断，火系范围大但耗 Mana；Magic Tower、Poisoned Arrow 和早期 Lava Moat 常被认为回报低。该反馈只用于平衡实验和遥测假设，不得替代官方行为契约。另有评论报告匹配等级差、返回键误退和卸载丢档等风险，需求因此加入装备归一化、生命周期处理和原子存档验收。

### 2.4 第一代到第二代的差异与更新

第一代 Defender 的公开评测显示：核心是城堡屋顶固定弩炮、点击/按住射击、最多三个已装备法术、金币/水晶升级和持续增强的单机波次；当时没有在线 Battle、Honors、Lava Moat、Magic Tower 或 XP 等第二代扩展。[第一代评测](https://cglfgamerzreview.wordpress.com/2011/12/02/another-android-review-defender/)[第一代评测](https://2shotsofgeek.com/index.php/2012/03/09/a-tiny-twist-on-defense-defender-review/)

第二代沿用上述循环，重点增加 Battle、更多弩、XP/等级、Research Center、毒箭/经验节点、Lava Moat、自动攻击并产 Mana 的 Magic Tower、Honors 和新敌人威胁。媒体将其评价为“第一代的扩展/更新”，而非完全不同的续作；第二代主要新意集中在商店/成长库存和在线模式。[jeuxvideo.com 对比评测](https://www.jeuxvideo.com/articles/0001/00017345-defender-ii-test.htm)[DroidHen Google Play](https://play.google.com/store/apps/details?id=com.droidhen.defender2)

| 维度 | Defender（第一代） | Defender II（第二代） | 需求影响 |
|---|---|---|---|
| 模式 | 单机 Local | Local + Battle；同一敌群并行生存 | Battle 等级 2 解锁、同敌群、服务端裁决 |
| 战斗输入 | 固定弩炮、点按/按住射击 | 相同输入，更多武器和技能组合 | 复用连续 2D 输入/ProjectileSystem |
| 技能 | 9 种法术池，最多 3 个 active | 火/冰/雷链、三槽 HUD、Mana/冷却 | 三槽兼容契约；节点和倍率配置化 |
| 成长 | 弩炮、生命、法术和 Mana 升级 | 增加 XP/等级、四页 Research、Honors、更多弩 | Profile 增加 XP、Honor、Weapon unlock 字段 |
| 防御 | 城墙 + 手动弩炮 | 新增 Lava Moat、Magic Tower | 设施为可选实体；第一代规则不生成 |
| 敌人与关卡 | 逐级增强，约每十关 Boss | 延续敌群/Boss，加入新投石类威胁和更密集后期 | `StageDirector` 模板 + seed；Boss 周期可版本化 |
| 经济 | 金币/水晶；早期胜利水晶有限，失败仍可刷金币 | 增加 XP、Battle/成就奖励、IAP 礼包 | `RewardLedger`、内购收据和规则版本隔离 |
| 版本更新 | 早期本地多存档、内容变化少 | 1.1.1 规划 Battle，1.2 促销，1.3 Gift Pack，后续主要修复/性能 | 维护更新不改变规则；内容更新必须迁移/回放声明 |

### 2.5 媒体评价和产品取舍

媒体认为第二代优点是短局、直接操作、升级组合丰富、敌群变大时反馈爽快；缺点是广告可能压缩战斗视野、音效一般、Battle 玩法单一、Boss 难度有跳变。[Android Central](https://www.androidcentral.com/defender-2-review-wave-defense-with-magic-and-big-honkin-crossbow)[jeuxvideo.com](https://www.jeuxvideo.com/articles/0001/00017345-defender-ii-test.htm)

玩家长期评价补充了高阶段资源/水晶瓶颈、重复刷关、IAP 诱导感、内购不到账、卸载/换设备丢档、返回键误退和更新后卡顿等问题。[App Store 玩家评价](https://apps.apple.com/us/app/defender-ii/id550081851?platform=watch&see-all=reviews)[Google Play 玩家评价](https://play.google.com/store/apps/details?id=com.droidhen.defender2)

本项目的可执行取舍：保留短局和简单上手，使用透明的资源收入和失败局金币减轻卡关；保留升级深度但用遥测监控单一最优流派；Battle 首版必须比原作更清楚地展示双方状态并采用装备归一化；所有商店/IAP、存档和返回键路径都纳入故障注入测试。评价中的“好玩/无聊/失衡”是体验信号，不得直接转化为硬数值。

## 3. 角色与用例

| 角色 | 主要用例 |
|---|---|
| 新玩家 | 启动、教学、开始 Local、射击、施法、升级、重新挑战 |
| 熟练玩家 | 选择武器/技能组合、冲击高波次、优化资源使用 |
| Battle 玩家 | 匹配/进入 Battle、在更长时间内存活、查看结果和排名 |
| 内容设计师 | 配置敌人、波次、技能、武器、难度和奖励 |
| QA/运维 | 重放问题、检查性能、回滚配置、审计异常结算 |

## 4. 功能需求

### 4.1 启动、档案与设置

**FR-001 首次启动**

系统 MUST 在首次启动创建本地 `PlayerProfile`、随机 `installId` 和默认设置。初始化失败时显示可重试错误，不得生成半成品存档。

**FR-002 存档**

系统 MUST 在升级购买、局结束、设置变更后保存；保存采用事务/原子替换。应用被系统杀死后，已完成局的奖励最多重复发放一次。

**FR-003 设置**

至少提供音乐、音效、震动、语言、画质、瞄准辅助和通知开关。设置立即生效并跨局保留。

**FR-004 版本迁移**

读取旧 schema 时按顺序执行迁移；迁移失败保留原档并显示“恢复备份”入口。

### 4.2 游戏模式

**FR-010 Local 模式入口**

玩家 MUST 看到线性 Stage 地图，只能开始当前已解锁 Stage 或重玩历史 Stage；入口显示目标、Boss 标记、最高结果和规则版本。经典规则集不得出现未经配置的任意选关。

**FR-011 Local 胜负**

Stage 的敌人目标数量/结束条件全部满足时显示胜利；城墙 HP 归零时显示失败。Stage 10、20 等 Boss 周期由配置决定，不能由 UI 猜测。结算 MUST 展示 XP、击杀、剩余生命百分比、金币和水晶；失败时仍提交并保存本局已获得的击杀金币。两者同 tick 时采用统一事件顺序并写入回放。

**FR-012 Battle 模式入口**

Battle 在玩家等级达到 2 前 MUST 显示锁定和解锁条件。解锁后开始实时并行匹配；未联网时 Battle 不可用，但 Local 仍可玩。匹配中显示取消、等待计时、超时和断线状态。

**FR-013 Battle 结果**

两名玩家 MUST 收到相同 `stageTemplateId + seed + rulesetVersion` 的生成事件，同时面对同一批敌人。结果页至少包含双方生存时间、最高波次、击杀数、城墙剩余百分比、胜负原因和奖励；先倒下者失败，同 tick 由服务端 tick/sequence 裁决。经典规则集默认启用装备/升级归一化，匹配评分仍记录真实战力用于诊断。

### 4.3 战斗场景与输入

**FR-020 场景**

战斗画面 MUST 显示城堡/城墙、敌人路径、熔岩沟（解锁后）、魔法塔（解锁后）、玩家瞄准点、敌人血条（可配置）、波次和资源 HUD。

**FR-021 瞄准**

触控拖拽/点击、鼠标和手柄右摇杆 MUST 转换为连续 2D 世界坐标；坐标经过安全区和缩放校正并夹紧到战场边界，不得映射为固定 lane。按住期间移动指针必须更新准星方向。

**FR-022 射击**

按下并保持射击命令时，系统 MUST 按武器射击间隔连续生成箭矢；抬起、暂停、死亡或离开战斗立即停止。多重箭一次射击生成配置数量的独立弹道。射击、命中和伤害均发布事件，事件带 `runId/tick/sequence`。

**FR-023 暂停/恢复**

Local 允许暂停，暂停时模拟、生成、冷却、音效时间均停止；Battle 是否允许暂停由模式配置决定，默认禁止。应用切后台必须按模式保存或结束。

### 4.4 玩家属性与武器

**FR-030 Strength**

升级 Strength 后，下一局及当前局新生成的箭矢伤害提高；已经飞行的箭矢是否使用旧快照必须固定为“使用生成时快照”。

**FR-031 Agility**

升级 Agility 后提高射击频率；必须设置最小射击间隔，防止浮点数或高等级导致零间隔。

**FR-032 武器装备**

玩家可在 Loadout 中查看、解锁、装备 Bow/Crossbow。每件武器至少展示伤害、射速、弹速、击退、穿透和特殊效果；装备变更在下一局生效，或由产品明确允许局中切换。

**FR-033 Power shot**

Power shot 命中后对合法目标施加击退；击退受 Boss 抗性、边界和冷却约束。无目标时不消耗充能（建议规则）。

**FR-034 Fatal Blow**

每次满足触发条件的箭矢按配置概率判定；触发时伤害为普通最终伤害的 2 倍（官方描述为 double damage），UI 必须给出可辨识反馈。

### 4.5 法术与 Mana

**FR-040 技能槽**

经典规则集 MUST 固定 3 个元素槽：火、冰、雷各 1 个；每槽装备该元素当前解锁的技能。HUD 显示图标、剩余 Mana、冷却/充能和不可用原因；其他规则集才允许配置槽位数。

**FR-041 施法**

拖拽技能图标到目标点或使用手柄确认目标后施法。Mana 不足、冷却中、目标非法时不得产生效果，并显示短暂反馈。

**FR-042 元素技能**

首版 MUST 实现三条可追踪技能链：Lightning Strike -> Thunder Storm -> Ragnarok、Glacial Spike -> Frost Nova -> Ice Age、Fire Ball -> Meteor -> Armageddon。火系为高 Mana 范围/持续伤害，冰系为伤害并减速或冻结，雷系为伤害并延迟动作/打断；具体倍率、半径、冷却和 Boss 抗性由配置定义。

**FR-043 Mana**

Mana 有最大值、当前值和再生来源。魔法塔按配置提供 Mana；施法扣除成本；所有变化不可超过 `[0, maxMana]`。

### 4.6 防御设施

**FR-050 城墙**

城墙显示当前/最大 HP，可通过局外升级提高最大 HP。敌人突破到城墙后按攻击间隔造成伤害；城墙归零触发失败并停止生成。

**FR-051 熔岩沟**

解锁并启用后，敌人进入/掉入熔岩区域时获得灼烧或一次性伤害；效果需有进入、持续、离开事件，避免重复触发漏洞。飞行/免疫标签敌人是否受影响由配置指定。

**FR-052 魔法塔**

魔法塔 MUST 自动攻击范围内敌人并按配置提供 Mana。历史观察的射程约为城墙至屏幕四分之三，落地实现以世界单位实测表为准，不得把未经证实的“自动回 Mana”写死。塔有等级、射速、范围、伤害、Mana 产出和目标策略；其攻击和 Mana 能力分别可配置启停。

### 4.7 敌人、波次与 Boss

**FR-060 敌人基类**

敌人至少包含 HP、速度、攻击伤害、攻击间隔、护甲、连续移动配置、攻击点、标签和状态效果抗性。内容设计师可添加近战、快速、远程、重甲、飞行、Boss 等原型；“路径”只能描述移动行为，不能把位置离散成固定 lane。

**FR-061 生成**

`SpawnDirector` 按配置生成总量、组成、间隔、纵向范围、队形和精英倍率；同一 Stage 的总量/组成保持模板一致，顺序使用 `seed` 洗牌以复现“每次顺序不同”。Battle 两端必须消费同一 `SpawnEvent` 流；数据结构不得使用 `lane` 作为位置约束。

**FR-062 增强曲线**

随 Stage/Battle 强度提高 HP、伤害、速度、数量或组合复杂度；每个倍率有上限。Local 采用线性 Stage，Battle 可无尽递增；TapTap 单一评论所称“3 分钟后提高难度”仅列为可选实验开关。系统不得只无限提高 HP，至少要通过敌人组合和 Boss 机制制造策略变化。

**FR-063 Boss**

Boss 具备独立血条、名称/警告、至少一个特殊行为和结算奖励。Boss 出现前提供可感知预警，Boss 死亡后发布 `BossDefeated`，不重复发奖。

**FR-064 敌人行为模板**

近战敌人向城墙推进并在攻击点按间隔伤害；远程敌人在 `preferredAttackX` 停下并执行蓄力攻击；重型敌人可配置击退抗性；飞行敌人可配置是否受熔岩沟影响。所有行为在固定 tick 中更新，并通过事件记录开始、取消和完成。

**FR-065 Boss 交互**

至少提供一个可被 Power Shot 击退的重型 Boss 和一个可被高打断等级元素技能打断蓄力攻击的 Boss 原型。Boss 的抗性、打断窗口、击退距离、阶段转换和奖励均配置化；同一技能在不同规则版本的控制结果必须可回放。

### 4.8 结算、成长与 Research center

**FR-070 结算**

显示胜负、Stage/Battle、波次、生存时间、击杀、剩余生命百分比、XP 进度、金币、水晶和新解锁内容。奖励先写入本地待确认结算，再以 `runId + rewardVersion` 幂等提交；关闭应用后可恢复未确认结算。失败局不得撤销已确认的击杀金币。

**FR-071 升级**

升级界面显示当前等级、下一等级效果、价格、前置条件和最大等级。购买必须原子扣费并写入新等级；余额不足不得扣除部分资源。

**FR-072 Research center**

Research center MUST 提供 Attack、Magic、Defense、Weapon 四页。Attack 至少包含 Strength、Agility、Power Shot、Poisoned Arrow、Fatal Blow、Multiple Arrows、Senior Hunter；Magic/Defense 使用本文件 2.2 的链；Weapon 至少提供 Power、Hurricane、Phantom 和 Final Fantasy。每个节点显示当前/下一等级、价格、前置条件、效果和规则版本；节点购买为单事务。

**FR-073 奖励幂等**

以 `runId + rewardVersion` 作为幂等键；重复提交只返回原结算，不再次增加资源。

**FR-080 经济与掉落**

系统 MUST 区分 `coins`、`crystals`、`xp` 三类资源。每次击杀产生可配置金币事件；Local 过关产生金币、水晶和 XP；Battle 胜者可获得额外水晶；失败局保留已产生的击杀金币。所有奖励事件带来源、数量、规则版本和幂等键，UI 显示余额变化明细。

**FR-081 Honors/成就**

系统 MUST 实现 8 个主题、每个 3 级的 24 项 Honors，并按累计事件实时更新进度：Big Spender（花费金币 50,000/250,000/1,000,000）、Great Mage（用水晶恢复 Mana 60/300/1,000）、Monster Hunter（击杀 5,000/30,000/200,000）、Defender（完成 Stage 50/150/350）、Tactician Master（Battle 胜利 30/100/300）、Fire/Ice/Lightning Master（对应施法 200/1,000/3,000）。达到阈值只触发一次，平台成就同步失败不得回滚游戏内进度；效果和奖励由配置定义。

**FR-082 商店与内购**

商店 MUST 提供金币包、水晶包和可选礼包三类商品，商品 ID、地区价格、货币数量和展示文案由平台配置返回。购买完成后以平台收据验证为准，服务端/本地幂等发放；取消、重复收据、退款和网络超时不得重复加币。未接入支付的平台显示不可购买原因，不影响 Local。

**FR-083 Battle 公平性与匹配**

匹配 MUST 记录玩家等级、升级评分、等待时长和规则版本；默认先按等级/评分匹配，超时逐步扩大范围。经典规则集启用相同装备/升级归一化，结果页明确显示该规则。服务端裁决同 tick 胜负、断线宽限和奖励，客户端不得提交最终生存时间。

**FR-084 生成种子与回放**

每局保存 `stageTemplateId`、`seed`、`rulesetVersion`、命令序列和配置哈希。相同输入日志 MUST 产生相同生成顺序、伤害、资源、结算和 Honors 事件；配置不兼容时回放明确拒绝并保留原日志。

**FR-085 生命周期与返回键**

Local 切后台/系统返回键时弹出确认，确认退出才结束本局；Battle 禁止暂停但必须保存最近权威快照，断线在宽限期内可恢复。Android 返回键不得直接杀掉未保存的结算或升级。

**FR-086 规则与证据版本**

所有玩法配置必须声明 `rulesetVersion`、`sourceGrade`、`sourceVersion`、`verifiedAt`。当官方、截图和社区数据冲突时，产品通过版本选择行为；客户端日志和客服导出必须包含这些版本字段。

**FR-087 第一代兼容规则集**

系统 MUST 支持加载 `defender-1` 规则集用于回归和迁移测试：只启用核心 Local、基础弩/法术、城墙和金币/水晶经济，不生成 Battle、Honors、Lava Moat、Magic Tower、XP 或第二代专属节点。`defender-1` 与 `classic-2012` 共用实体/事件 schema，但掉落、上限和解锁策略独立配置。

**FR-088 版本更新策略**

维护更新（Bug、性能、平台适配）不得隐式修改敌人、奖励、上限或胜负；内容/经济变更必须递增 `rulesetVersion` 或 `configVersion`，提供迁移脚本、回滚点和回放兼容声明。IAP 商品、广告开关、隐私字段通过平台配置，不进入 Domain。

**FR-089 媒体反馈质量门槛**

首版必须满足：战斗区域不被广告遮挡核心瞄准区；Boss 强度曲线不存在单关不可解释跳变；失败局仍能获得明确可见的金币进度；每个可购买升级显示效果、价格和资源来源；Battle 显示双方状态、同敌群规则和断线结果。

**FR-090 商店与生命周期容错**

购买成功但客户端中断时，重启后 MUST 通过未完成收据查询补发且只补发一次；购买失败/退款不增加余额。切后台、返回键、卸载重装（若启用云备份）均需有明确恢复或退出提示，不能静默丢失已确认进度。

**FR-091 技术栈与程序集门禁**

客户端 MUST 使用锁定版本的 Unity 6.3 LTS、C#、URP 2D、uGUI/TextMeshPro、Input System、Addressables 和 JSON 配置。`Domain` asmdef MUST 为纯 C#，不得引用 `UnityEngine`、UGS、IAP、SQLite 或平台程序集；CI 架构检查失败时不得合并。Battle 客户端使用 Netcode for GameObjects/Unity Transport，生产服务器使用 Unity Linux Dedicated Server。

**FR-092 平台能力**

首发 MUST 产出 Android 8/API 26+ ARM64 AAB 和 iOS/iPadOS 15+ Metal 横屏包；支持 16:9、19.5:9、4:3 平板安全区。Windows/WebGL/macOS/主机不属于首发验收范围，平台特性必须通过 Infrastructure 适配器。

**FR-093 服务端 API 与数据一致性**

Profile、Receipt、Support API MUST 使用 HTTPS、JWT/mTLS、OpenAPI 和请求幂等键；Profile 采用版本号乐观锁，Receipt/RewardLedger 使用同事务写入。PostgreSQL 为持久数据源，Redis 只用于短期匹配/限流状态；客户端不得直接访问数据库或提交最终 Battle 结果。

**FR-094 内容交付与构建归档**

Addressables catalog、Remote Config、规则 JSON、Unity/包/SDK 版本、AAB/IPA、符号文件和配置哈希 MUST 归档。内容发布先进入 staging，通过固定回放、真机冒烟、签名和灰度后才可切 production；客户端保留上一版本资源以支持回滚。

**FR-095 构建配置**

Android Release MUST 使用 Unity IL2CPP ARM64、AAB、Vulkan 优先并支持 OpenGL ES 3 回退、ETC2/ASTC 分档纹理；iOS Release MUST 使用 IL2CPP ARM64、Metal、ASTC 和 App Store Archive；Battle Dedicated Server MUST 使用 Unity Linux Server build、无渲染/音频、固定 30 tick/s。每种产物由 `BuildProfile` 生成，CI 必须归档符号文件、mapping、catalog、配置哈希和构建 SHA。

**FR-096 依赖升级**

升级 Unity、Package Manager、UGS、Netcode、IAP、SDK/NDK 或后端依赖前，工程 MUST 运行全量回放、Domain 架构检查、Battle 断线、支付沙盒、Android/iOS 真机和 Dedicated Server 冒烟。失败时不得推进 production 配置；lock 文件和变更说明必须随提交保存。

## 5. 初始内容规格（建议值）

这些是 `classic-2012` 兼容实现的开发和自动化测试基线；带“待实测”的数值不得视为原作精确数据。

| 内容 | MVP 建议 |
|---|---|
| 敌人 | 近战、快速、远程、重甲、飞行、巨人、龙骑士 Boss；原型字段可扩展 |
| 攻击研究 | Strength、Agility、Power Shot、Poisoned Arrow、Fatal Blow、Multiple Arrows、Senior Hunter |
| 魔法研究 | Mana Research + 火/冰/雷三条三级链；HUD 固定三个元素槽 |
| 武器 | Power、Hurricane、Phantom；Final Fantasy 购买/自动成长规则作为兼容开关 |
| 防御 | City Wall、Magic Tower、Lava Moat 及其强化节点 |
| Local | 线性 Stage；模板固定总量/组成，按 seed 随机顺序；每 10 Stage Boss（待实测可调） |
| Battle | 实时并行同敌群；等级 2 解锁；经典规则默认装备归一化 |
| 货币 | `coins` 击杀/结算，`crystals` 过关/Battle/Honors/商店，`xp` 升级；早期过关 2 水晶仅为版本样本 |
| Honors | 8 个主题 × 3 级 = 24 项，阈值见 FR-081 |

### 5.1 经典机制行为基线

下表是客户端、服务器、数值工具和 QA 共用的最小行为契约。倍率、上限和价格必须从 `classic-2012` 配置加载；表中“社区观察”只说明实现方向，不能当成未经验证的最终数值。

| 机制 | 可操作行为 | 初始配置/验收口径 | 证据 |
|---|---|---|---|
| Strength | 提高普通箭矢最终伤害 | 早期截图 Lv1 24 -> Lv2 28（+4），后续以等级表为准 | B |
| Agility | 缩短自动射击间隔 | 攻略常记每级 +2 射速，设置最小间隔 | B/C |
| Power Shot | 命中后施加击退，Boss 抗性可配置 | 每次命中产生 `KnockbackApplied`；不可穿越城墙边界 | A/C |
| Poisoned Arrow | 命中后附加中毒周期伤害 | 伤害、持续、叠层、Boss 抗性配置化 | C |
| Fatal Blow | 按概率使本次箭伤害 ×2 | UI 显示 `Fatal!`；不得实现一击必杀默认行为 | A/B |
| Multiple Arrows | 一次射击生成多条独立箭矢 | 社区常记最高 5 箭；箭数和分摊倍率配置化 | C |
| Senior Hunter | 提高经验获得 | 经验修正写入结算快照并计入等级进度 | C |
| Lightning | 伤害并延迟动作/打断蓄力 | 目标、链数、打断等级和冷却配置化 | C |
| Ice | 伤害并减速或冻结 | `Freeze` 时长、Boss 抗性、刷新规则配置化 | C/截图 |
| Fire | 高 Mana 消耗的范围/连续灼烧 | 周期伤害、半径、Mana 成本配置化 | C |
| City Wall | 提高最大城墙 HP | 城墙归零结束 Local/Battle；上限按版本表 | A/C |
| Lava Moat | 敌人进入/掉入时受灼烧或缠绕 | 进入、持续、离开各只触发一次；免疫标签配置化 | A/C |
| Magic Tower | 自动攻击射程内敌人并提供 Mana | 射程以世界单位表校准；攻击与 Mana 输出独立开关 | A/C |
| Weapons | Power/Hurricane/Phantom 改变伤害/射速/附加属性 | 装备在下一局快照生效；Final Fantasy 250 水晶和自动成长为兼容开关 | B/C |

## 6. 非功能需求

**NFR-001 性能**：30 tick/s；100 敌人和 200 投射物时逻辑 p95 < 10 ms，60 FPS 渲染 p95 < 16.7 ms。  
**NFR-002 启动**：中端设备冷启动 < 3 s；首次资源解压另行计时。  
**NFR-003 稳定性**：连续 30 分钟 Local 无崩溃、无可观测内存持续增长；关键异常可定位到 `runId/configVersion`。  
**NFR-004 离线**：Local 核心流程不要求网络；网络恢复后异步上报不影响玩法。  
**NFR-005 安全**：Battle 结果和奖励由服务端校验/签名；客户端输入、存档、远程配置均做 schema 校验。  
**NFR-006 可维护性**：敌人、技能、武器、波次不得以代码分支硬编码；配置有版本、哈希和回滚。  
**NFR-007 可访问性**：重要 HUD 文本支持放大、色盲友好状态区分、触控目标不小于 44 dp、震动和音效可关闭。  
**NFR-008 本地化**：所有可见文本使用 key；中文和英文覆盖主流程，数字、时间和复数规则按语言格式化。  
**NFR-009 确定性与公平**：固定 `seed + commandLog + configHash` 的回放事件必须一致；Battle 结果由服务端 tick/sequence 裁决，客户端时钟误差不影响胜负。  
**NFR-010 数据可靠性**：升级、结算、Honor 解锁和内购发放采用事务/幂等写入；崩溃或断电不得造成已扣资源无对应内容。  
**NFR-011 经济安全**：收据验证、退款撤销、异常频率和重复奖励均有审计日志；离线 Local 奖励可排队，但不得伪造 Battle 奖励。  
**NFR-012 规则可追溯**：任何平衡配置可追溯到 `rulesetVersion/sourceGrade/sourceVersion/verifiedAt`，支持灰度、回滚和回放兼容声明。  
**NFR-013 平台兼容**：Android API 26+ ARM64 与 iOS/iPadOS 15+ Metal 必须通过首发真机矩阵；16:9、19.5:9、4:3 平板均不得出现 HUD 截断、黑边遮挡核心战场或触控误判。  
**NFR-014 架构隔离**：Domain 程序集不得引用 `UnityEngine`、UGS、IAP、SQLite 或平台 API；编译检查和架构测试必须阻止反向依赖。  
**NFR-015 构建可复现**：Unity 编辑器、包版本、SDK/NDK/OpenJDK、配置哈希、Addressables catalog、符号文件和签名元数据必须归档；同一提交可重建同一资源清单。  
**NFR-016 Battle 网络质量**：在 80 ms RTT、1% 丢包、短暂断网 10 s 的测试条件下，Battle 不崩溃、不重复命令；超出宽限后给出确定性失败和幂等奖励结果。  
**NFR-017 商店容错**：支付成功、待处理、取消、退款、重复回调和客户端崩溃场景均可恢复；收据验证服务 p95 < 2 s，失败时展示重试而非扣款无内容。  
**NFR-018 隐私与数据**：只上传匿名 install/player 标识和玩法事件；原始收据、触控坐标和账号凭据不得进入普通遥测；提供隐私同意、数据删除和平台政策文案。  

## 7. UI 与交互验收

### 7.1 主菜单

必须提供 Local、Battle、Research center、Loadout、Settings、帮助/教学入口；锁定功能显示解锁条件，不显示不可解释的空白按钮。

主菜单 MUST 显示玩家等级/XP、Local 当前 Stage、金币、水晶和 Honors 入口；Battle 未达到等级 2 时显示锁定态。商店入口显示金币包、水晶包和礼包的商品状态，但不得遮挡 Local 入口。

### 7.2 战斗 HUD

左上显示城墙 HP，顶部显示 Stage/波次、金币、水晶和计时，右上显示暂停（Local）或对手存活摘要（Battle），底部显示 Mana 与火/冰/雷三个技能槽；屏幕中部保留连续瞄准与敌人可视区域。HUD 在 16:9、19.5:9 和平板比例下不得遮挡城墙或技能目标。

### 7.3 反馈

射击、命中、暴击、Power shot、技能生效、Mana 不足、Boss 预警、城墙受击和胜负均必须有视觉或音频反馈，且不能只依赖颜色。

### 7.4 社区反馈对应的设计验收

| 反馈/风险 | 需求响应 | 观测指标 |
|---|---|---|
| Agility、Strength、Multiple Arrows 常被优先 | 首版不强制单一加点；节点显示边际效果，记录选择率/失败率 | 节点购买率、Stage 失败波次 |
| 冰系常被认为最稳，火系耗 Mana，雷系适合打断 | 三元素必须各有可见反制场景；Boss 抗性、Mana 成本和控制时长可调 | 各元素施法率、控制造成的伤害占比 |
| Magic Tower、早期 Lava Moat/Poisoned Arrow 被认为回报低 | 塔和熔岩沟显示实际伤害/Mana 贡献；不得隐藏收益 | 设施伤害、Mana 产出、购买后留存 |
| 匹配等级差、装备差导致挫败 | Battle 采用等级/升级评分匹配并默认归一化；结果记录真实战力 | 等级差、等待时间、投降/断线率 |
| 卸载丢档、返回键误退 | 原子存档、云端可选备份、返回键确认和未确认结算恢复 | 存档恢复成功率、误退率 |

## 8. 验收测试矩阵

| ID | 前置 | 操作 | 期望 |
|---|---|---|---|
| AT-001 | 新档 | 开始教学并点击敌人 | 产生箭矢，命中后 HP 减少，教学进入下一步 |
| AT-002 | Strength 等级 1 | 升级到 2，开始同 seed 两局 | 新等级生成的箭矢伤害按配置提高 |
| AT-003 | Mana 不足 | 施放任一技能 | 不生成效果，不扣 Mana，显示原因 |
| AT-004 | 熔岩沟解锁 | 让敌人进入熔岩区 | 触发一次进入伤害/灼烧，离开后按配置结束 |
| AT-005 | 魔法塔启用 | 等待 10 秒 | 塔自动攻击且 Mana 按配置增加 |
| AT-006 | Boss 波 | 进入 Boss 波 | 预警出现，Boss 血条和特殊行为生效，死亡只结算一次 |
| AT-007 | 城墙低 HP | 放任敌人攻击 | HP 归零后停止生成，显示失败结算 |
| AT-008 | Local 离线 | 关闭网络并完成一局 | 可开始、战斗、结算和保存；网络恢复后可上报 |
| AT-009 | 重复提交 | 对同一 runId 提交两次结算 | 资源只增加一次，第二次返回同结果 |
| AT-010 | 固定 seed/replay | 运行并回放同一命令日志 | 事件序列、分数和胜负一致 |
| AT-011 | Battle 断线 | 中途断网并在宽限期内恢复 | 恢复到最近快照，不重复执行命令 |
| AT-012 | 低端设备 | 100 敌人、200 投射物运行 5 分钟 | 达到 NFR-001，无明显输入延迟和卡死 |
| AT-013 | 按住射击 | 按住并拖动准星 3 秒后抬起 | 以武器间隔持续发箭；抬起后不再生成；瞄准轨迹连续 |
| AT-014 | 新档等级 1 | 尝试进入 Battle，再升到等级 2 | 等级 1 被锁定；等级 2 解锁并能进入匹配 |
| AT-015 | 固定 Stage 模板 | 用两个不同 seed 开始同一 Local Stage | 敌人总量/组成相同，顺序可不同；同 seed 顺序完全一致 |
| AT-016 | Battle 房间 | 两名测试玩家进入同一 match | 收到相同 SpawnEvent；对手摘要实时刷新；同 tick 由服务端裁决 |
| AT-017 | Honors 计数 | 将击杀数从 4,999 提升到 5,000 | Monster Hunter Lv.1 只解锁一次并记录奖励/平台同步状态 |
| AT-018 | 内购收据 | 重放同一成功、取消、退款收据 | 成功收据只发放一次；取消/退款不增加余额并留下审计记录 |
| AT-019 | 结算恢复 | 结算写入后立即杀进程，再次启动 | 恢复未确认结算；确认两次资源只增加一次 |
| AT-020 | 返回键 | Local 战斗、Battle 断线、结算页分别按系统返回 | Local 弹确认；Battle 保留快照；结算页不丢失奖励 |
| AT-021 | 规则冲突 | 加载 Fatal Blow 9 级与 15 级配置 | 按 `rulesetVersion` 选择上限；日志显示来源，不混用数值 |
| AT-022 | Boss 交互 | 对重型 Boss 使用 Power Shot，对蓄力 Boss 在窗口内施放雷/冰技能 | 前者按抗性击退；后者取消蓄力；窗口外施法不产生打断 |
| AT-023 | 连续坐标 | 从不同纵向位置拖动准星并观察远程敌人 | 敌人位置不被 lane 吸附；远程敌人在配置攻击点停下并按间隔攻击 |
| AT-024 | 程序集依赖 | 执行架构检查/编译 Domain asmdef | Domain 不引用 UnityEngine、UGS、IAP、SQLite 或平台程序集；违规使 CI 失败 |
| AT-025 | Android 构建 | 在 CI 以锁定 Unity/SDK/NDK/OpenJDK 构建 AAB 并安装到 API 26 ARM64 真机 | 构建可安装、横屏锁定、Local 离线可完成；资源清单哈希与归档一致 |
| AT-026 | iOS 构建 | 在 macOS 构建机生成 Xcode 工程并安装到 iOS 15+/A12 真机 | Metal 渲染、横屏、安全区和触控正确；Local 不依赖登录 |
| AT-027 | Battle Dedicated Server | 启动 Linux Dedicated Server，两个客户端加入同一房间 | 服务端持有 RNG/胜负/奖励；两端 SpawnEvent 相同；客户端改时间无效 |
| AT-028 | UGS 登录/云档 | 匿名登录后绑定平台账号，在第二设备恢复 | Cloud Save 冲突按版本号提示选择；登录失败仍可 Local；不会覆盖较新档 |
| AT-029 | 支付沙盒 | Google Play/StoreKit 沙盒执行购买、待处理、重复、退款和补发 | 收据服务验签后只发放一次；重启可补发；退款撤销并记录审计 |
| AT-030 | 网络退化 | Battle 模拟 80 ms RTT、1% 丢包、断网 10 s/超时 | 快照可恢复且命令不重复；宽限内重连，超时确定性失败 |
| AT-031 | 资源热更新 | 下发签名 Remote Config 新版本，再执行回滚 | 签名/Schema 错误自动回退；回放记录 configHash 和 rulesetVersion |
| AT-032 | 可复现构建 | 在干净构建机重跑相同提交 | Unity/包/SDK/资源版本和 AAB 内容摘要符合归档清单 |
| AT-033 | Profile 并发 | 两设备同时提交同一 profileVersion 的升级 | 一个成功；另一个收到 409 和最新档；无资源丢失或覆盖 |
| AT-034 | Receipt API | 使用相同幂等键并发提交成功收据 | 只生成一个 grantId；两次响应一致；账本只有一条授予 |
| AT-035 | 服务端隔离 | 从客户端尝试访问数据库/内部服务地址 | 网络层拒绝；只有 API Gateway/ Battle 端口可达；日志记录告警 |
| AT-036 | Release 构建矩阵 | 分别生成 Android、iOS、Linux Server、EditMode 产物 | 编译后端、架构、图形 API、无渲染选项和符号归档符合 FR-095 |
| AT-037 | 依赖升级门禁 | 提交 Unity/UGS/Netcode/IAP/SDK 版本升级 | 全量回放、网络、支付、真机和服务器冒烟全通过后才允许合并 |

## 9. 内容与平衡工作流

1. 设计师在表格/JSON 中修改配置，工具执行 ID、引用、范围和曲线校验。
2. QA 使用固定 seed 的回放场景验证改动前后事件、难度和性能。
3. 发布系统生成带 `configVersion` 的签名包，支持灰度和一键回滚。
4. 通过波次失败率、技能使用率、武器选择率、平均局时长观察平衡，不直接依据单一胜率调数值。

## 10. 待确认问题与调查计划

| 问题 | 影响 | 确认方法 |
|---|---|---|
| 目标版本的完整数值表（属性、技能、价格、掉落） | 平衡和回放兼容 | 实机逐级截图/录屏，导入带来源字段的配置 |
| Battle 的实际同步协议和断线规则 | 服务端规模和协议 | 目标版本实机网络测试；当前需求按实时并行兼容实现 |
| 货币与奖励在不同版本的差异 | 经济与存档 | 记录至少 20 局各模式结算，按版本生成掉落表 |
| Research center 是否存在地区/版本分支 | 局外成长 UI | 实机逐节点截图，建立前置关系并比较规则版本 |
| Boss 周期、抗性和特殊行为 | 波次配置与战斗策略 | 长局录屏，标记 Boss 出现 Stage、技能打断和奖励 |
| 飞行/远程敌人原型及路径 | 碰撞、目标选择 | 实机观察并按连续坐标、攻击点和抗性标签归类 |

在这些问题得到证据前，工程实现应继续使用本文建议值，且不得把建议值写死进代码。

## 11. 发布前检查清单

* 领域层可在无图形环境运行，固定 seed 回放通过。
* Local 离线完整链路通过，存档迁移和损坏恢复通过。
* Strength、Agility、七项攻击节点、四页研究树、Power/Hurricane/Phantom 武器、Final Fantasy 规则开关、Power shot、Fatal Blow、三类技能、Mana、城墙、熔岩沟、魔法塔和 Boss 均有可操作验收用例。
* coins/crystals/xp、失败局击杀金币、Battle 胜者奖励、24 项三级 Honors 和商店收据均通过幂等测试。
* 16:9、19.5:9、平板、中文/英文、触控/手柄均完成冒烟测试。
* Battle 的同敌群同步、等级 2 解锁、装备归一化、结算、断线、重连、重复领奖和作弊检测通过；若服务端尚未上线，产品文案必须明确为测试/不可用。
* Android AAB、iOS Archive、Linux Dedicated Server 和 EditMode 测试产物均由锁定 BuildProfile 生成，符号文件、mapping、catalog、配置哈希和构建 SHA 已归档。
* CI 依赖门禁已运行 Unity/UGS/Netcode/IAP/SDK 升级套件；生产配置、云服务环境和商店商品 ID 与 staging 隔离。
* 公开资料链接、配置版本和已知偏差记录在发布说明中。

## 12. 参考资料

* [Google Play：Defender II（DroidHen）](https://play.google.com/store/apps/details?id=com.droidhen.defender2)
* [Neoseeker：Defender II](https://www.neoseeker.com/defender-ii/)
* [AppBrain：Defender II](https://www.appbrain.com/app/defender-ii/com.droidhen.defender2)
* [Skich：Defender II](https://skich.app/games/defender-ii)
* [Gamermenu：Defender 2 玩家攻略](https://gamermenu.blogspot.com/p/blog-page.html)
* [Galaxy of Geek：Defender II review](https://galaxyofgeek.com/2012/04/15/review-defender-ii-android-monsters-crossbows-and-fireballs-oh-my/)
* [Gamebase Taiwan 攻略](https://news.gamebase.com.tw/news/detail/96090041)
* [Unwire 截图与介绍](https://unwire.hk/2012/03/27/great-tower-defence-game-defender-ii/news/)
* [App Store：Defender II](https://apps.apple.com/us/app/defender-ii/id550081851?platform=watch)
* [Exophase 成就表](https://www.exophase.com/game/defender-2-android/achievements/) / [GameFAQs 成就表](https://gamefaqs.gamespot.com/android/839892-defender-ii/cheats)
* [JVC 玩家论坛：属性上限](https://www.jeuxvideo.com/forums/1-14935-3333-1-0-1-0-les-limites.htm)
* [Arqade：Final Fantasy bow](https://gaming.stackexchange.com/questions/82246/when-does-the-final-fantasy-bows-stats-surpass-those-of-phantom-lv-9) / [Magic Tower range](https://gaming.stackexchange.com/questions/64506/what-is-the-range-for-magic-tower)
* [Italian Defender II review](https://www.it-blog.ro/review-defender-ii) / [MobileWorld24 review](https://mobileworld24.pl/2012/03/30/bron-swego-zamku-defender-ii-juz-w-google-play/)
* [TapTap Defender II 讨论](https://www.taptap.cn/app/1591/topic)
* [Unity 6 releases](https://unity.com/releases/unity-6) / [Unity 6.3 system requirements](https://docs.unity3d.com/6000.3/Documentation/Manual/system-requirements.html)
* [Unity Multiplayer netcode](https://docs.unity.com/multiplayer/netcode/netcode) / [Multiplayer Services sessions](https://docs.unity.com/en-us/mps-sdk/sessions)
* [Unity Cloud Save getting started](https://docs.unity.com/en-us/cloud-save/get-started) / [Unity Authentication use cases](https://docs.unity.com/en-us/authentication/use-cases)
* [Google Play Billing integration](https://developer.android.com/google/play/billing/integrate.html) / [Billing release notes](https://developer.android.com/google/play/billing/release-notes)
