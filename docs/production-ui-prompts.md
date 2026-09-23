# Production UI and Fortress Asset Prompts

Generated 2026-09-23 with the built-in imagegen tool. All four selected outputs use generation mode (no referenced image input). Original castle/turret artwork and the repository's reference screenshots were inspected to establish the connected two-tower silhouette, central firing seat, right-facing firing axis and orthographic projection; they were not copied into the new bitmaps.

Source outputs remain in `C:/Users/18283/.codex/generated_images/01a05cc5-cb2a-77d2-b894-6449bc2d4891/`. Selected PNGs are copied unmodified into `Gamematerials/`; only Godot import size limits/mipmaps and runtime layout/tint are applied. Actual dimensions differ from requested dimensions. See `production-ui.md` for anchors and import budgets.

Rejected reference-edit/checkerboard drafts, including `exec-d777f63a-9080-4b3c-95ef-4299e4bc8473.png`, are not registered, copied to game resources or shipped. Transparency is verified on imported resources and by compositing actual gameplay screenshots, not inferred from a checkerboard preview.

## Castle

- Mode: generate
- Selected output: `exec-ad085891-75c4-40dd-b02a-f78cac8dcdb5.png`
- Project copy: `Gamematerials/Environment/citadel-v3.png`

```text
Create an isolated TRANSPARENT PNG game sprite with a genuinely transparent alpha background. One tall complete stone fortress defensive line for a 2D tower-defense game. No backdrop of any kind. The asset must be a CUTOUT with transparent empty pixels, do not draw checkerboard.
One upper stout circular bastion, one lower stout circular bastion, connected by a substantial continuous narrow curtain wall running vertically north-south. Exactly two tower buildings. Elevated orthographic three-quarter view looking down 55 degrees, upper-left lighting, all towers upright, top rampart surfaces visible. The defensive wall faces RIGHT into an open battlefield which is NOT painted. Upper tower center around 42% width/14% height; lower tower center around60% width/80% height. At center of the linking wall a broad square projecting EMPTY weapon platform with circular iron swivel bearing, center at 66% width/52% height. No ballista on the platform. Vertical composition with generous transparent left/right padding; all foundations and crenellations wholly within frame. Proportions: short sturdy fortress towers and thick wall, not thin fairytale spires. Towers have empty recessed round sockets on top for separately rendered magic crystals.
Premium hand-painted strategy-game art. Natural light grey limestone blocks, ash-grey shaded wall faces, iron reinforcement bands with small aged brass rivets, broad crenellations, exposed walkway, structural buttresses, arrow slits, restrained burgundy cloth pennants with a tiny gold geometric heraldic mark, subtle moss. Crisp sculpted beveled stone, convincing metal reflections, painterly detail concentrated at edges, readable when reduced to 280px wide. No heavy black cartoon outline, no oversaturated blue, no gold overload, no plastic toy rendering.
Portrait canvas. NO ground rectangle, terrain, background, shadow plane, chessboard pattern, UI, text, logos, third tower, roof spires, weapon, bolt, character, water or lava. Deliver real RGBA transparent isolated asset, not a mockup.
```

## Ballista

- Mode: generate
- Selected output: `exec-0bd53fa4-1501-4c4f-95b8-dbf74154ecf0.png`
- Project copy: `Gamematerials/Environment/ballista-v3.png`

```text
Generate a TRANSPARENT PNG cutout sprite with true alpha: one detailed upper ballista weapon assembly, pointing exactly RIGHT. No tower or pedestal. One isolated complete weapon on empty transparent pixels, no background or checkerboard. Premium hand-painted strategy-game asset, matching grey limestone fortress with dark iron and brass fittings.
Landscape composition, elevated orthographic three-quarter view looking down 55 degrees. Strong dark walnut rail runs horizontally left to right, two recurved heavy forged steel bow limbs extend above and below the rail at the right-hand front. Clearly visible taut silver bowstring, winch spool, bronze ratchet wheel, small winding crank, metal straps and rivets, stock groove for a SEPARATE bolt. No loaded arrow, bolt or projectile in this sprite. Circular swivel bearing below the central stock, small turquoise inset gem, no magical blue blade. Mechanical proportions, clear silhouette at 220px wide. Entire weapon within frame with 8 percent transparent padding, stock and firing axis horizontal. Swivel point around 44% width/60% height, stock firing line around 45% height.
Natural painterly wood grain, cool grey forged steel beveled highlights, aged pale brass accents, dark contact shadows, upper-left light. NOT a flat vector icon, NOT simplified cartoon, NOT photo, NO ground, NO stone base, NO banner, NO UI, NO letters, NO watermark, NO border. TRUE transparent alpha PNG, never paint a grey checkerboard.
```

## UI Chrome

- Mode: generate
- Selected output: `exec-176b4633-bd7d-4452-8e75-6ccd9d9357f1.png`
- Project copy: `Gamematerials/UI/chrome-v2.png`

```text
Use case: stylized-concept. Asset type: GAME UI SKIN ATLAS, a strictly aligned 2 by 2 equal-cell square atlas on a 1536x1536 canvas, designed for actual nine-slice rendering, NOT a UI screenshot. Four independent assets, each completely centered in its quadrant. True transparent alpha only outside the four assets. No text, letters, symbols, numbers, watermark, fake checkerboard or presentation backdrop.
Art direction: polished medieval fortress game interface matching sculpted neutral grey limestone, dark charcoal iron, restrained pale brass, deep burgundy enamel and muted verdigris. Premium hand-painted tactile edges, not flat vector rectangles, not blue SaaS panels, not orange/brown wood, not heavily ornamental fantasy filigree. Crisp small-scale edge highlights. Quiet flat dark interiors for readable white text. Rounded corners at most very slightly beveled, predominantly chamfered angular geometry.
TOP LEFT: one square large menu/modal PANEL. Occupies exactly x=4%..96%,y=4%..96% of its cell. Narrow forged iron double-beveled frame about 4% of cell width, small aged brass riveted corner caps, restrained chiselled stone outer lip. INNER CENTER is opaque near-black charcoal-green soft fine-grain slate, evenly lit, no illustration, no central ornament, no glow. Perfectly straight horizontal/vertical rails suitable for nine-slicing, corners contain all detail; frame not a bulky stone wall.
TOP RIGHT: one square neutral BUTTON tile, same inset 4% from cell edges, narrow 3% frame; dark steel bevel, subtle aged brass edge on top, charcoal-green enamel interior with fine wear, extremely restrained top-down light. Straight sides for nine slicing; nothing centered on face. This will stretch into horizontal buttons.
BOTTOM LEFT: one square PRIMARY BUTTON tile, precisely same geometry/insets as neutral button, richer pale brass rim and deep dark burgundy/red enamel center. The red is readable dark oxblood, not bright orange. No central decoration.
BOTTOM RIGHT: one circular SKILL SOCKET, outer diameter 90% of cell, thick carved black iron ring with silver bevel and four tiny brass clamps at compass points. Inner disk opaque near-black charcoal, very subtle radial metal sheen, no spell in it. Outside circle transparent; inner area dark and empty. Clearly separated light upper-left rim and shadow lower-right rim. Real crafted game UI ring, not a simple vector stroke.
Keep exact grid cells and strong transparent gutters, no assets touching, no drop shadows outside gutters. All four centers empty, texture detail concentrated in edges. Produce one transparent PNG atlas.
```

## UI Symbols

- Mode: generate
- Selected output: `exec-cde90b8b-66fc-41b5-bcc2-fb9c0a6b931a.png`
- Project copy: `Gamematerials/UI/symbols-v2.png`

```text
Create a genuine TRANSPARENT PNG game UI icon atlas. Strict 4 columns x 4 rows of SIXTEEN distinct isolated hand-painted inventory symbols, square canvas1536x1536. Equal square cells, icons centered with 16% transparent padding in each cell, no frames or plates, no words/numbers, no grid, no background or checkerboard. Cohesive premium medieval fortress game style: sculpted steel, pale aged brass, gems, burgundy cloth, clear dark edges with bright material highlights; not emoji, not flat vectors, no glow that touches other cells. Readable at32px.
ROW1 columns left to right: 1 one embossed round GOLD COIN with geometric crest; 2 cluster of three BLUE CRYSTALS; 3 small STEEL SHIELD with red center and stone castle crenellation emblem, for wall health; 4 luminous CYAN MANA ORB in a small silver cradle.
ROW2: 1 two crossed STEEL SWORDS, dark grips; 2 ivory ENEMY SKULL, compact and slightly stylized; 3 engraved BRASS GEAR wheel; 4 GOLD LAUREL MEDAL with red ribbon, for honors.
ROW3: 1 steel HAMMER and small anvil for research; 2 leather-bound JOURNAL with brass clasp and burgundy cover for save slots; 3 ivory SCROLL with leather tie for tutorial; 4 carved stone TOWER crown with turquoise crystal, for magic defense.
ROW4: 1 sturdy gold-edged ARROWHEAD pointing LEFT, simple broad shape for back; 2 same ARROWHEAD pointing RIGHT; 3 green-jeweled metal CHECKMARK; 4 red enamel metal X cross. Consistent visual weight, upper-left light, sharp silhouette, all objects fully inside their cell. Transparent alpha0 outside objects, no display sheet background. Painted production sprites, not an example of a UI.
```
