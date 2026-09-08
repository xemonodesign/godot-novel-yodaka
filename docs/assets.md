# 素材と生成記録

## 提供素材

`bg.png`（街）、`bg_near.png`（会話背景）を使用。人物は `images/character/yodaka.png`（よだか）、`asika.png`（あしか）、`doctor.png`（ドクター）を使用。初版の `girl.png` は保持しています。`slide_01.png`〜`slide_06.png` は画面デザインの参照資料で、ゲーム本体には含めていません。元のXLSXは改変せず、本文からゲーム用JSONを生成しています。

## 診察室の背景

保存先：`src/assets/counseling.png`

生成方式：組み込み `image_gen` ツール（imagegenスキル）。生成結果を作業フォルダへコピーし、冒頭・最後のカウンセリングに使用。

最終プロンプト：

> Use case: illustration-story. Asset type: Japanese visual novel background, wide landscape 16:9. Primary request: a quiet welcoming Japanese doctor's counseling room, no people. Two simple comfortable chairs angled gently toward each other, low wooden table with a glass of water, a potted plant, bookshelf, tall window with sheer curtains and leafy suburban view. Hand-painted anime background, delicate architectural linework and soft watercolor-like light, late afternoon cream and muted sage palette, thoughtful calm atmosphere. Eye-level wide composition, clean uncluttered room, no medical equipment, no text, no logos, no watermark. Production background art, not UI mockup.

## 3Dの標本

`src/specimen.gd` で生成する実際のローポリメッシュです。八面体の岩、5枚の花びら、茎と葉。ラスター画像による回転表現ではありません。

## 日本語フォント

Noto Sans JP、SIL Open Font License 1.1。`src/assets/OFL-NotoSansJP.txt` にライセンス全文。Web配信物にもライセンスを同梱。

取得元：https://github.com/google/fonts/tree/main/ofl/notosansjp
