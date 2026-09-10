# 場所別背景の生成記録

組み込み image_gen で生成。出力を `src/assets/backgrounds/` にコピーし、場所名で切り替えます。人物なし、16:9、水彩調の背景です。

### hallway.png

Use case: illustration-story. Asset type: 16:9 Japanese visual novel background, no UI. An empty Japanese high school corridor at 7 AM, large side windows with pale morning sunlight, stairs landing and a simple bench, polished floor with soft reflections, a quiet place where a student could practise ballet. Eye-level composition with open central space. Delicate anime background painting, fine pencil-like architectural linework, soft watercolor colors, subtle paper texture, grounded contemporary Japan. No people, no text, no logos, no watermark.

### classroom.png

Use case: illustration-story. Asset type: 16:9 Japanese visual novel background, no UI. An empty Japanese high school classroom after school, orderly wooden desks, tall windows glowing with warm late afternoon light, green chalkboard, curtains and leafy view. Eye-level perspective with open central space. Delicate anime background painting, fine pencil-like architectural linework, soft watercolor colors, subtle paper texture, grounded contemporary Japan. No people, no readable text, no logos, no watermark.

### living.png

Use case: illustration-story. Asset type: 16:9 Japanese visual novel background, no UI. A modest contemporary Japanese family's living room, soft beige sofa, low wooden coffee table, bookshelf, a houseplant, sliding balcony door, warm comfortable afternoon daylight. Eye-level perspective with open central space. Delicate anime background painting, fine pencil-like architectural linework, soft watercolor colors, subtle paper texture. No people, no text, no logos, no watermark.

### restaurant.png

Use case: illustration-story. Asset type: 16:9 Japanese visual novel background, no UI. Interior of an ordinary Japanese family restaurant after school, upholstered booth seats, wood laminate table with two clear glasses and drinking straws, drink bar in the distance, wide windows looking onto a suburban street in late afternoon. Eye-level from a table, uncluttered open composition. Delicate anime background painting, fine pencil-like architectural linework, soft watercolor colors, subtle paper texture, grounded contemporary Japan. No people, no text, no logos, no watermark.

### cafe.png

Use case: illustration-story. Asset type: 16:9 Japanese visual novel background, no UI. A quiet small Japanese kissaten coffee shop in the afternoon, dark wood tables, two porcelain coffee cups, upholstered chairs, a large window with warm diffused daylight, plants and a counter in the background. Eye-level from a seated visitor, open composition. Delicate anime background painting, fine pencil-like architectural linework, soft watercolor colors, subtle paper texture. No people, no text, no logos, no watermark.

### park.png

Use case: illustration-story. Asset type: 16:9 Japanese visual novel background, no UI. A small Japanese suburban nature park with a modest artificial pond, several ducks resting on a rock and swimming gently, low shrubs, a footpath, a wooden bench and leafy trees in calm afternoon light. Eye-level composition from the path overlooking the pond. Delicate anime background painting, fine pencil-like linework, soft watercolor colors, subtle paper texture. No people, no text, no logos, no watermark.

### street.png

Use case: illustration-story. Asset type: 16:9 Japanese visual novel background, no UI. Quiet residential street in a Tokyo suburb on an early school morning, small houses, utility poles, greenery, a pedestrian sidewalk leading toward a distant school gate, gentle blue sky. Eye-level perspective with an open central vanishing point. Delicate anime background painting, fine pencil-like architectural linework, soft watercolor colors, subtle paper texture. No people, no text, no logos, no watermark.

## りあの立ち絵

提供された `images/character/mother.png` はそのまま保持。背景透過版を `src/assets/mother_cutout.png` に保存。

Use case: background-removal. Edit the supplied character illustration only to remove the solid white background and make it fully transparent. Keep this exact woman, her face, hairstyle, clothing, pose, line art and colors unchanged. Retain white areas inside her clothes and skin highlights; only the exterior background must become transparent. No additions, no redesign, no cropping. Output transparent-background PNG.
