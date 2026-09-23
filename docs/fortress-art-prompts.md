# 九技能图标与城防素材生成记录

2026-09-22 使用内置 imagegen，非 CLI/API 回退。2026-09-23 从本任务生成记录补录完整工具记录提示词。前三张为新生成，第四张在普通地面基础上编辑；文件均已进入项目，原素材不覆盖。实际输出尺寸不等于提示词请求尺寸，应用方式见 [城防视听说明](fortress-art.md)。

## 1. 九技能图标

输出：`Gamematerials/UI/spell-icons-v1.png`，1254×1254，真实透明通道。

```text
Use case: stylized-concept. Asset type: production game UI spell-icon ATLAS, one square image, a strictly regular 3 columns by 3 rows grid of NINE different icons, equal square cells. Each icon centered on its own cell with 10 percent transparent padding. Genuine transparent alpha everywhere outside the symbols; no black or colored background, no drawn grid, no frames, no text, no numbers, no watermark.
Hand painted fantasy mobile castle-defense art, crisp readable dark edges with luminous internal highlights, richly shaded tangible magical matter, not flat vector symbols. Consistent lighting, premium painterly detail and silhouette readable at 48 px. First ROW fire, second ROW ice, third ROW lightning. Columns show increasing tiers.
Row 1 column 1: ONE incandescent golden-orange fireball with rounded molten core and a long diagonal fiery comet tail; column 2: THREE separate flaming meteors sweeping diagonally together, clearly three streaks; column 3: a dramatic dense shower of SEVEN smaller flaming meteors surrounding one larger blazing central impact, compact composition.
Row 2 column 1: ONE tall angular translucent blue-white icicle with a tiny frosty base; column 2: a fan of THREE broad blue ice crystals erupting from a frosty impact; column 3: SEVEN sharp glacier shards in a circular blizzard crown with blue-white swirling snow and central bright frost.
Row 3 column 1: ONE branching violet-white lightning strike diagonally crossing the cell, organic electrical forks NOT a cartoon zigzag; column 2: THREE forked lightning bolts connected around a brilliant violet electrical contact; column 3: a dense violet thunderstorm nexus with FIVE branching white-hot lightning strikes and curled blue-violet ionized sparks.
Keep all nine silhouettes separated and wholly inside their respective cells; no merged effects between cells. Bright warm orange/gold fire, crystalline cyan/white ice, rich violet/white lightning. Strong material depth, avoid realistic photography, avoid emoji and simplistic geometric icons. Output one 1536x1536 atlas.
```

## 2. 普通地面

输出：`Gamematerials/Environment/battle-ground-v2.png`，1672×941，不透明。

```text
Use case: stylized-concept. Asset type: complete opaque landscape 2D castle-defense battlefield background, 16:9 canvas 2048x1152, no UI.
Elevated orthographic three-quarter TOP-DOWN view of cold slate-blue stone ground with hand-painted fantasy mobile game art, crisp dark crevices and soft cel shading, matching a silver-blue stone fortress and colorful stylized monsters. No horizon, no perspective vanishing point. Uniform scale across the whole plane.
The playable open field occupies x=28% through 100% of the image and has medium-small irregular worn flagstones with muted cool teal seams, subtle stone grain, moss sparsely in crevices and a few tiny pebbles. Calm medium-dark desaturated blue so monsters and magic read clearly. No enormous canyon cracks, no glowing entire ground, no large obstacles in the playable center.
On the far left x=0..14% show a quieter darker stone foundation apron, empty and flat for a SEPARATELY DRAWN vertical castle wall. Between x=14% and x=25%, show a narrow continuous irregular rocky drainage channel running vertically edge-to-edge from TOP to BOTTOM, currently DRY, dark blue stony bottom, low rocky banks; this region will later become a lava moat. Its center stays near x=20%, never wanders into the center of the battlefield. Channel is carved naturally into the SAME terrain, not a pasted straight strip. A very thin cluster of cool dark framing rocks at far right edge, with no cropping of important gameplay area.
Absolutely NO castle, tower, turret, ballista, building, bridge, stairs, character, projectile, fire, lava, text, watermark or HUD. Ground only, full bleed. Terrain stays visibly flat, scene is a playable landscape area NOT a portrait strip stretched wide. Upper-left soft cold illumination with readable painted texture and restrained value contrast.
```

## 3. 城防部件

输出：`Gamematerials/Environment/fortress-atlas-v1.png`，1254×1254，真实透明通道。

```text
Use case: stylized-concept. Asset type: one production game sprite atlas, square 1536x1536, strictly equal TWO columns by TWO rows, FOUR independent sprites, genuine transparent alpha between and around all sprites, with 12 percent margin within each cell.
Style: crisp dark outlines, hand-painted soft cel shading, blue-grey silver stone/metal, royal-blue inlays, small cyan crystal lights, coherent elevated orthographic three-quarter mobile castle-defense view. Upper-left lighting. Premium readable tangible materials, not UI glyphs. No text, frames, grid, watermark, terrain rectangle or background.
TOP LEFT CELL: ornate compact magic-tower crown, an upright large faceted cyan-blue crystal held by a SILVER AND DARK BLUE open metal basket of four short prongs and a small circular metal base. No tall tower shaft, no stone wall. Crystal fully visible. Polished silver bevels, deep blue base inlay and restrained blue aura fading to alpha. Fits a small existing castle bastion as a separate magical upgrade. Width about 60% and height about 75% of cell.
TOP RIGHT CELL: a complete mechanically convincing castle ballista UPPER ASSEMBLY viewed from above in the same three-quarter projection. The wooden rail points horizontally RIGHT, cyan-steel recurved limbs extend above and below the stock, clearly visible drawn taut silver bowstring, brass clamps, steel ratchet and winding spool. NO arrow, NO bolt, NO projectile, NO stone base, NO tower, NO giant decorative wings. Compact horizontal silhouette width80% height50% of cell, central swivel pivot at cell center. Silver/cyan steel and dark warm walnut wood. Ready for separately animated recoil.
BOTTOM LEFT CELL: a low irregular burst of molten orange lava bubbles and flying embers, from an oval molten core, orange red translucent plumes, bright yellow small highlights. Transparent outside, no black disk or rock pedestal; for a brief ground splash.
BOTTOM RIGHT CELL: a compact contact burst of irregular grey-blue STONE CHIPS and beige-grey dusty wisps thrown outward from a tiny center, several sharp silver sparks. Transparent outside, no ground disk. Center at cell center, chips remain wholly within cell. For masonry impact feedback.
```

## 4. 熔岩地面变体

输出：`Gamematerials/Environment/moat-ground-v2.png`，1672×941，不透明；以普通地面为编辑目标。

```text
Use case: precise-object-edit. Asset type: full opaque landscape battle terrain variant for a 2D castle-defense game.
Edit ONLY the dry drainage channel in the supplied ground background into an active molten lava moat. Preserve the original 16:9 framing, camera, stone ground, stone sizes, rock banks, every ground layout feature, all field pixels outside the channel, and calm blue field colors as closely as possible. The channel at approximately x=14%..25% goes vertically from top edge to bottom edge, center near20%; fill its recessed dark bed with flowing orange-red molten lava, yellow narrow liquid veins, scattered small black cooling crusts and a few tiny luminous bubbles. Both irregular rock banks retain their exact shape; softly warm-light ONLY the immediately bordering stones, do not tint the whole field. Lava should be rich and luminous but not washed-out yellow. No added towers, wall, castle, characters, UI, bridges, icons, flames covering the field, smoke obscuring the field or text. Keep the exact same complete landscape battlefield composition, not a composited strip, no transparency. Output 2048x1152 landscape.
```
