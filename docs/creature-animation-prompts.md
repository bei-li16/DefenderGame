# 敌人逐帧动作素材生成记录

2026-09-27，内置 image_gen，透明背景输出。原角色 PNG 用作身份与画风参考，未覆盖原文件。每套包含 6 列 × 4 行；三个 Boss 为移动 / 普攻 / 专属施法 / 死亡，小怪为移动 / 攻击 / 受击 / 死亡。游戏通过实测 UV 区域和脚底锚点读取整张原始输出，不在运行时重绘或扭曲图像。

## dragon

保存：`Gamematerials/Creatures/dragon-actions-v1.png`。
原始输出：`exec-7365ad3a-b50c-4ca0-9458-dfd5c598ac98.png`。

```text
Use case: stylized-concept. Asset type: production 2D game animation sprite sheet, real transparent background. Reference image 1 defines the EXISTING character identity and hand-painted thick outline mobile fantasy art style. Create a NEW sprite animation atlas of this same red dragon; preserve red scales, black horns, cream belly and red bat wings. Remove the rock pedestal and permanently painted fire. Character faces LEFT in fixed side/three-quarter game view.
Layout MUST be exactly 6 equal columns x 4 equal rows, ideally 1536x1024 pixels, each cell 256x256. 24 separate complete full-body sprites. Each cell independent, no labels, no grid lines, no ground/shadow/background. Keep all artwork inside each cell with a 12px transparent gutter. Same character size and camera in every cell, feet baseline at cell y=228, body mass centered x=138. Tail and wings kept inside cell. Do not crop any limb.
Row 1, six consecutive WALK cycle frames: alternating front and rear leg steps, planted feet, head counter-motion, articulated folded wings and tail follow-through; last frame returns toward first.
Row 2, six consecutive CLAW ATTACK frames: crouch and pull claw back, lift front claw, forward lunge, long leftward claw swipe at frame 4, follow-through, recover. Legs support weight.
Row 3, six consecutive FIRE BREATH cast frames: brace feet, raise chest and fold neck backward, head draws back as throat glows, neck thrusts LEFT with jaws wide open, sustained open jaw exhale, head lowers into recovery. Only a SMALL orange glow inside mouth, NO flame extending from mouth (engine draws flame).
Row 4, six consecutive DEATH frames: stagger from hit, wings lose support, knees buckle, fall on side, lie dead with folded limbs, same corpse settling. Full visible corpse in last cell, do NOT fade transparency of character.
Strong readable changes of silhouette and independently posed joints between frames, never scale/stretch copies of one image. No new costume, no text, no numbers. Genuine transparent alpha around sprites.
```

## giant

保存：`Gamematerials/Creatures/giant-actions-v1.png`。
原始输出：`exec-bdbc9761-3251-4b02-b31e-380c2b681a6e.png`。

```text
Use case: stylized-concept. Production transparent 2D game animation atlas. Use attached reference ONLY for existing character identity and hand-painted bold outline fantasy-game art style. Draw the SAME character in genuinely different anatomical poses, never warped copies.
EXACT layout 6 equal columns x 4 equal rows = 24 full-body sprites on 1536x1024 canvas, 256x256 cells. No grid lines, numbers, text, pedestal, ground, shadows or scenery. Genuine alpha transparency. Fixed camera, LEFT-facing side/three-quarter view. Every cell has 12px empty gutters, same character scale, anchored hips x=142 and ground/feet baseline y=230 within each cell. Even the raised weapon and fallen body stay completely inside their own cell. Do not crop sprites. Death poses stay fully colored; engine fades them.
The reference rock giant is used as the FROST TITAN: preserve bulky jagged stone anatomy and huge fists; use cold slate-grey stones and icy cyan-blue energy in cracks and eyes instead of orange lava. No permanent fire.
ROW 1: six-frame WALK loop, heavy alternating footfalls, weight transferred between bent knees, opposite arm swing, torso counter-rotation.
ROW 2: six-frame NORMAL PUNCH, pull fist back, twist shoulder, extend fist LEFT, full contact punch in frame 4, follow-through, recover.
ROW 3: six-frame ICE NOVA SLAM, crouch, raise BOTH massive fists overhead, highest anticipation, drive both fists into ground in frame 4, braced impact pose with a few tiny ice fragments, push back upright. NO large effect or ground painted into frames.
ROW 4: six-frame DEATH: chest cracks, head drops, knees buckle, stone limbs collapse, body breaks into big recognizable stone chunks on ground, settled rubble with extinguished core. Progressive physical collapse, not shrink/fade.
```

## matron

保存：`Gamematerials/Creatures/matron-actions-v1.png`。
原始输出：`exec-4f14c6ad-7772-49bd-9263-00111f344124.png`。

```text
Use case: stylized-concept. Production transparent 2D game animation atlas. Use attached reference ONLY for existing character identity and hand-painted bold outline fantasy-game art style. Draw the SAME character in genuinely different anatomical poses, never warped copies.
EXACT layout 6 equal columns x 4 equal rows = 24 full-body sprites on 1536x1024 canvas, 256x256 cells. No grid lines, numbers, text, pedestal, ground, shadows or scenery. Genuine alpha transparency. Fixed camera, LEFT-facing side/three-quarter view. Every cell has 12px empty gutters, same character scale, anchored hips x=142 and ground/feet baseline y=230 within each cell. Even the raised weapon and fallen body stay completely inside their own cell. Do not crop sprites. Death poses stay fully colored; engine fades them.
Preserve the magenta tentacle monster lord with black curling horns, cream belly, dark spiked bracers and large wooden spiked club. FOUR prominent curling back tentacles, same weapon and anatomy throughout, strong muscular silhouette. Violet eye glow.
ROW 1 six-frame WALK/HOVER cycle: alternating steps and leg lifts, hips transfer weight, back tentacles curl with staggered timing, heavy club sways.
ROW 2 six-frame CLUB ATTACK: crouch, raise club behind head, high anticipation, forceful downward LEFTWARD club strike in frame 4, low follow-through, recovery.
ROW 3 six-frame STORM CHANNEL: plant feet, raise club vertically and spread four tentacles, tentacles arc overhead, thrust club toward LEFT as tentacles splay in frame 4, hold channel with TINY violet sparks at tentacle tips, lower club and recover. No broad lightning or ground effects painted into sheet.
ROW 4 six-frame DEATH: recoil, weapon slips, knees buckle and tentacles go limp, fall sideways, prone body and dropped club, settled corpse with curled limp tentacles. Progressive full-body collapse, not shrink/fade.
```

## snail

保存：`Gamematerials/Creatures/snail-actions-v1.png`。
原始输出：`exec-dd9a54cf-68e1-4a74-aab6-9a21dd03c6cf.png`。

```text
Use case: stylized-concept. Asset type: real transparent 2D game animation sprite sheet. Attached reference is the character identity and established bold outlined, smoothly painted mobile-fantasy game style. Preserve its species, palette, costume and face. Fixed LEFT-facing three-quarter side camera, no view changes.
Create EXACTLY 24 complete sprites in 6 equal columns by 4 equal rows, ideally 1536x1024, each 256x256 cell. Genuine transparent background, no labels, numbers, grid lines, scenery, shadows or ground. Keep 16px transparent gutters inside every cell; no limb may touch or cross a cell boundary. Same scale and body pivot x=135 in all cells, feet baseline y=224 except flying character. Motion must be redrawn articulated anatomy, not squash-stretch or rotated copies.
ROW 1 = 6 consecutive seamless locomotion cycle poses.
ROW 2 = 6 attack poses: anticipation, windup, maximal windup, impact/release (frame 4), follow-through, recovery.
ROW 3 = 6 HURT/recoil poses: small flinch, maximal backward recoil, braced pose, regain footing, recover, normal. No blood and no painted colored flashes.
ROW 4 = 6 DEATH poses: shock, lose balance, collapse, fall, settle, fully visible dead body. No fade or vanishing; do not shrink body; weapon if any falls with character.
Blue-grey squat turtle/snail with ORANGE RED spiral shell, two red-tipped antennae and short clawed legs. Walk: four little legs alternate visibly, head bobs independently, antennae follow with delayed sway, shell stays rigid. Attack: retract neck and brace behind shell, then thrust head and front shell LEFT into a strong bash at frame4, retract/recover. Hurt: antennae droop and head recoils behind shell. Death: head retreats, legs buckle, shell tips onto its side and rests with limp antennae.
```

## fist

保存：`Gamematerials/Creatures/fist-actions-v1.png`。
原始输出：`exec-1919c6e9-f12f-44b7-a0dc-87dce5b1fc39.png`。

```text
Use case: stylized-concept. Asset type: real transparent 2D game animation sprite sheet. Attached reference is the character identity and established bold outlined, smoothly painted mobile-fantasy game style. Preserve its species, palette, costume and face. Fixed LEFT-facing three-quarter side camera, no view changes.
Create EXACTLY 24 complete sprites in 6 equal columns by 4 equal rows, ideally 1536x1024, each 256x256 cell. Genuine transparent background, no labels, numbers, grid lines, scenery, shadows or ground. Keep 16px transparent gutters inside every cell; no limb may touch or cross a cell boundary. Same scale and body pivot x=135 in all cells, feet baseline y=224 except flying character. Motion must be redrawn articulated anatomy, not squash-stretch or rotated copies.
ROW 1 = 6 consecutive seamless locomotion cycle poses.
ROW 2 = 6 attack poses: anticipation, windup, maximal windup, impact/release (frame 4), follow-through, recovery.
ROW 3 = 6 HURT/recoil poses: small flinch, maximal backward recoil, braced pose, regain footing, recover, normal. No blood and no painted colored flashes.
ROW 4 = 6 DEATH poses: shock, lose balance, collapse, fall, settle, fully visible dead body. No fade or vanishing; do not shrink body; weapon if any falls with character.
Squat dark-grey rocky boxer with TWO enormous shiny RED boxing gloves, angry eyes, short grey legs. Walk: alternately plant feet, roll shoulders and alternate glove guard. Attack: wind back leading glove, shoulder twist, punch LEFT with extended arm at frame4, guard recovers. Hurt: gloves open apart, body reels backward and braces. Death: stagger, gloves drop, rocky knees buckle, fall on back/side, settled rock body with two limp gloves.
```

## tentacle

保存：`Gamematerials/Creatures/tentacle-actions-v1.png`。
原始输出：`exec-2631ca91-9b34-419c-949f-c018f80abb4d.png`。

```text
Use case: stylized-concept. Asset type: real transparent 2D game animation sprite sheet. Attached reference is the character identity and established bold outlined, smoothly painted mobile-fantasy game style. Preserve its species, palette, costume and face. Fixed LEFT-facing three-quarter side camera, no view changes.
Create EXACTLY 24 complete sprites in 6 equal columns by 4 equal rows, ideally 1536x1024, each 256x256 cell. Genuine transparent background, no labels, numbers, grid lines, scenery, shadows or ground. Keep 16px transparent gutters inside every cell; no limb may touch or cross a cell boundary. Same scale and body pivot x=135 in all cells, feet baseline y=224 except flying character. Motion must be redrawn articulated anatomy, not squash-stretch or rotated copies.
ROW 1 = 6 consecutive seamless locomotion cycle poses.
ROW 2 = 6 attack poses: anticipation, windup, maximal windup, impact/release (frame 4), follow-through, recovery.
ROW 3 = 6 HURT/recoil poses: small flinch, maximal backward recoil, braced pose, regain footing, recover, normal. No blood and no painted colored flashes.
ROW 4 = 6 DEATH poses: shock, lose balance, collapse, fall, settle, fully visible dead body. No fade or vanishing; do not shrink body; weapon if any falls with character.
Small pink/magenta horned imp with cream belly, two curved ivory horns, wooden spiked club, curled tentacle tail. Walk: quick alternating running strides, spring at knees, club carried over shoulder, tail counter-swings. Attack: lift club high, twist, swing hard LEFT and downward at frame4, follow-through/recover. Hurt: club wavers, head flinches backward, tail tightens. Death: knees buckle, club drops, fall on side, tail uncurls and settles beside prone body.
```

## spike

保存：`Gamematerials/Creatures/spike-actions-v1.png`。
原始输出：`exec-aef61a21-9b4f-4f46-bae8-4c3c308da777.png`。

```text
Use case: stylized-concept. Asset type: real transparent 2D game animation sprite sheet. Attached reference is the character identity and established bold outlined, smoothly painted mobile-fantasy game style. Preserve its species, palette, costume and face. Fixed LEFT-facing three-quarter side camera, no view changes.
Create EXACTLY 24 complete sprites in 6 equal columns by 4 equal rows, ideally 1536x1024, each 256x256 cell. Genuine transparent background, no labels, numbers, grid lines, scenery, shadows or ground. Keep 16px transparent gutters inside every cell; no limb may touch or cross a cell boundary. Same scale and body pivot x=135 in all cells, feet baseline y=224 except flying character. Motion must be redrawn articulated anatomy, not squash-stretch or rotated copies.
ROW 1 = 6 consecutive seamless locomotion cycle poses.
ROW 2 = 6 attack poses: anticipation, windup, maximal windup, impact/release (frame 4), follow-through, recovery.
ROW 3 = 6 HURT/recoil poses: small flinch, maximal backward recoil, braced pose, regain footing, recover, normal. No blood and no painted colored flashes.
ROW 4 = 6 DEATH poses: shock, lose balance, collapse, fall, settle, fully visible dead body. No fade or vanishing; do not shrink body; weapon if any falls with character.
Round ORANGE spiky hedgehog/puffer monster, cream lower face, short orange feet and large pale spikes. Walk: quick little alternating steps with body lean and changing foot silhouettes, not entire sprite rotation. Attack: brace feet, tuck head and expose forward spikes, lunging LEFT shell bash at frame4, recoil/recover. Hurt: eyes squint and spikes tilt with body recoil. Death: lose footing, roll onto side, limp feet upward, settled side-lying spiky body with eyes closed.
```

## mage

保存：`Gamematerials/Creatures/mage-actions-v1.png`。
原始输出：`exec-83e222e3-be23-45e8-a38a-24227852a56c.png`。

```text
Use case: stylized-concept. Asset type: real transparent 2D game animation sprite sheet. Attached reference is the character identity and established bold outlined, smoothly painted mobile-fantasy game style. Preserve its species, palette, costume and face. Fixed LEFT-facing three-quarter side camera, no view changes.
Create EXACTLY 24 complete sprites in 6 equal columns by 4 equal rows, ideally 1536x1024, each 256x256 cell. Genuine transparent background, no labels, numbers, grid lines, scenery, shadows or ground. Keep 16px transparent gutters inside every cell; no limb may touch or cross a cell boundary. Same scale and body pivot x=135 in all cells, feet baseline y=224 except flying character. Motion must be redrawn articulated anatomy, not squash-stretch or rotated copies.
ROW 1 = 6 consecutive seamless locomotion cycle poses.
ROW 2 = 6 attack poses: anticipation, windup, maximal windup, impact/release (frame 4), follow-through, recovery.
ROW 3 = 6 HURT/recoil poses: small flinch, maximal backward recoil, braced pose, regain footing, recover, normal. No blood and no painted colored flashes.
ROW 4 = 6 DEATH poses: shock, lose balance, collapse, fall, settle, fully visible dead body. No fade or vanishing; do not shrink body; weapon if any falls with character.
Small goblin mage with purple hooded robe with tan trim, dark face with glowing CYAN eyes, green hands/feet and tall wooden staff with cyan crystal. NO permanent floating fireball. Walk: alternating feet visible under robe, independent staff planting and robe hem follow-through. Attack: draw free hand back, raise staff and charge tiny cyan light in palm, thrust hand LEFT at frame4, follow-through/recover; no emitted projectile inside atlas. Hurt: hood tilts back, staff wobbles, hands guard chest. Death: stagger, staff falls, kneel, collapse sideways into crumpled robe, dim eye glow, settled robe and staff.
```

## bat

保存：`Gamematerials/Creatures/bat-actions-v1.png`。
原始输出：`exec-82ab87a4-2029-4c65-bfcc-acd38a44586b.png`。

```text
Use case: stylized-concept. Asset type: real transparent 2D game animation sprite sheet. Attached reference is the character identity and established bold outlined, smoothly painted mobile-fantasy game style. Preserve its species, palette, costume and face. Fixed LEFT-facing three-quarter side camera, no view changes.
Create EXACTLY 24 complete sprites in 6 equal columns by 4 equal rows, ideally 1536x1024, each 256x256 cell. Genuine transparent background, no labels, numbers, grid lines, scenery, shadows or ground. Keep 16px transparent gutters inside every cell; no limb may touch or cross a cell boundary. Same scale and body pivot x=135 in all cells, feet baseline y=224 except flying character. Motion must be redrawn articulated anatomy, not squash-stretch or rotated copies.
ROW 1 = 6 consecutive seamless locomotion cycle poses.
ROW 2 = 6 attack poses: anticipation, windup, maximal windup, impact/release (frame 4), follow-through, recovery.
ROW 3 = 6 HURT/recoil poses: small flinch, maximal backward recoil, braced pose, regain footing, recover, normal. No blood and no painted colored flashes.
ROW 4 = 6 DEATH poses: shock, lose balance, collapse, fall, settle, fully visible dead body. No fade or vanishing; do not shrink body; weapon if any falls with character.
Purple ONE-EYED bat monster with huge single orange eye, two small fangs, magenta membranes in two purple wings, tiny feet. Locomotion: six real articulated wingbeats through high upstroke, folded elbows, downstroke, low wings, recovery, raising wings. Body stays at cell x=128,y=130; wing silhouettes change dramatically. Attack: pull wings back, face leans forward, wings high, dive-bite toward LEFT at frame4 with mouth open, pull up, recover hover. Hurt: wingbeat stutters, eyelid closes, one wing folds then recovers. Death: eye closes, wings lose lift and fold, body falls toward baseline y=224, lands on side, wings fold limply, still corpse.
```
