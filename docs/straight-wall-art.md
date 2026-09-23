# 竖直贯通城墙：四项规则修正

2026-09-23，替代上一版蓝银整栋城墙的布局。依据本地原游戏截图（`参考/01_官方/google-play_03_火系技能.png`、`参考/03_玩家与评测/unwire_02_Stage1战斗HUD.jpg`）重新核对投影，参考图仅用于研究。

## 当前表现

| 用户指出的问题 | 实际处理 |
|---|---|
| 城墙整体倾斜 | 改为沿屏幕 Y 轴的连续墙体，走道、压顶、外墙面和垛口采用固定 X 坐标 |
| 与游戏、地面风格不一致 | 墙面采用新绘制的低饱和灰青石材；内院、圆塔和弩机同步压低鲜亮蓝银色，保留小面积水晶光 |
| 弩机上下墙段不共线 | 上下不是两张独立贴图，而是同一个缓存网格；弩机平台叠加于贯通墙体，不移动墙线 |
| 两塔外侧城墙缺失 | 墙体从 y=-96 延伸至 y=1176，覆盖 1080 高画布及震屏余量；完整圆塔覆盖在墙线上，塔后墙体持续贯通 |

墙体不再整张绘制旧城墙 PNG。圆塔仅采样 `Environment/citadel-v3.png` 的完整近端塔楼，排除斜向连接墙，两座塔均位于 x=199。受击特效沿外墙 x=264 分布。城内边界同步改为竖直，避免旧斜边从城墙旁露出。弩机保留固定底座与独立旋转/后坐，核心发射原点仍为 (245,555)。

`castle_view.gd` 一次性缓存墙体、平台和塔楼网格；新材质通过 Godot 导入资源加载，不在每帧生成图片或网格。游戏数值、核心碰撞、存档和外部战场地面不改动。

## 新材质

- 项目路径：`Gamematerials/Environment/masonry-slate-v1.png`。
- 内置 imagegen 生成，未使用 CLI/API 回退。
- 选用原始输出：`exec-552f4259-3d6b-406e-a134-146b82f253bd.png`，实际 1254×1254 RGB。
- 内容为 2×2 四种石块表面，真实不透明材质；由网格采样并控制墙体几何。
- 导入上限 512，启用 mipmap。最初的无倒角石面草稿未被选用。

最终提示词：

```text
Create an OPAQUE square 1024x1024 production game texture atlas with exactly FOUR large rectangular carved stone blocks in a precise 2 columns x 2 rows grid. Reference 1 supplies the muted blue-grey / grey-green battlefield palette; reference 2 supplies the hand-painted stone masonry style (ignore its architecture and banners). Each 512x512 cell contains one almost-square stone block from x/y 12 to 500 within the cell, on dark grey mortar, seen straight on. All blocks have broad softly chipped beveled edges, visible pale upper-left rims, shaded lower-right rims, subtle painterly mineral variation and sparse tiny shallow cracks. Main flat faces should be MID-LIGHT neutral blue-grey stone, roughly RGB(140,151,153), much lighter than the dark ground, with visible highlights around RGB(175,183,180), dark bevel around RGB(60,76,79). Four subtly varied faces from the SAME stone, no different colors. This is actual masonry material for a continuous straight vertical castle wall in a 2D game. Broad readable blocks, cohesive with painted fantasy ground, not plastic, no saturated blue, no ivory or gold trim, no shiny metal, no photorealistic grain, no deep cracks or rubble, no background scene. Exact regular grid, tiles isolated by thin mortar gutters, no perspective, no labels, no text, no transparency, no checkerboard, no vignette. Fill all four equal cells. The final geometry and wall alignment are controlled separately by the engine.
```

## 视觉验证

以实际 Godot 4.7.2 Compatibility 渲染器（GTX 1060）截图检查：

- 普通 / 熔岩地面 × 1920×1080 / 1280×720 × 水平 / 上瞄55° / 下瞄55° / 后坐，16 张全景与 16 张局部截图。
- 逐一检查墙轴、塔楼连接、屏幕上下延伸、低分辨率接缝、弩机安装及塔顶放电。
- 另检查 Boss 战场截图及城防受击/放电帧。
- 城墙图形验收增加同一 X 列在上下墙段、塔外和屏幕边缘的覆盖检查，并比较普通/熔岩切换时墙面像素，防止地面透出；旧的“整张斜城墙源图”断言已替换。

专项姿态布置和敌人位置是可复现验证状态，不是连续人工试玩录像。测试通过 `--script` 隔离玩家存档。

| 检查 | 结果 |
|---|---|
| 城墙图形验证 | 84 通过，0 失败 |
| 城防动画/暂停/特效图形验证 | 113 通过，0 失败 |
| 整机 UI 图形验证 | 1036 通过，0 失败 |
| 核心规则 | 162 通过，0 失败 |
| 素材与真实模拟，图形模式 | 93 通过，0 失败；100 怪 / 200 箭平均帧 16.55ms |
| 双语 × 四分辨率布局 | 720p / 768p / 1080p / 1440p，0 失败 |

复查命令（图形截图不要加 `--headless`）：

```powershell
& 'D:\Software\Godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe' --path . --script res://tools/capture_fortress_review.gd
& 'D:\Software\Godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe' --path . --script res://tests/castle_layout_acceptance.gd -- --capture
```

截图与本轮日志：`Builds/straight-wall-review/`。修改前后同布置对照为 `before-battle.png` / `after-battle.png`。整机截图：`Builds/production-ui-review/`。输出目录不纳入 Git。

2026-09-24 已重新生成 Windows Release：`Builds/Windows/DefenderGame.exe` 与 `Builds/Aegis-of-Ember-1.7.0-Windows-x64.zip`。构建使用当前修改的独立源码快照 `e546128755dfb72997fcf5b563ffda724f00d075`；正式构建检查、25 项包内资源检查及非管理员启动检查通过。使用 Godot 4.7.2 直接加载 EXE 内嵌资源完成 16 张战斗画面与 16 张局部截图，覆盖两种分辨率、普通/熔岩场景和四种弩机姿态；已人工核对画面。日志和截图位于 `Builds/RebuildLogs/fortress-20260924-003354/`。导出保留既有的图标缺少 128 像素尺寸警告。
