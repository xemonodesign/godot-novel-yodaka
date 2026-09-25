# 素材と生成記録

## 提供素材

`bg.png`（街）、`bg_near.png`（会話背景）を使用。人物は `images/character/yodaka.png`（よだか）、`asika.png`（あしか）、`doctor.png`（カウンセラーのみなと）を使用。初版の `girl.png` は保持しています。`slide_01.png`〜`slide_06.png` は画面デザインの参照資料で、ゲーム本体には含めていません。元のXLSXは改変せず、本文からゲーム用JSONを生成しています。

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

## 追加素材（2026-09-10）

りあ：提供された `images/character/mother.png` から組み込み image_gen で背景を除去し、`src/assets/mother_cutout.png` を使用。元画像は保持しています。すみか：専用素材がないため `images/character/girl.png` を仮使用。`sumika.png` を追加すると優先します。

場所別の7背景とりあの背景透過のプロンプトは [生成記録](background-prompts.md) を参照。

立ち絵は実行時に透明余白を除いた表示範囲を使い、縦長の全身素材は上半身まで表示します。元ファイル自体は変更しません。

## 追加台本（2026-09-25）

カウンセラー「みなと」と法月よだかの冒頭カウンセリング2シート（`カウンセリング.xlsx`：カウンセリング0・カウンセリング1）を取り込み。台本のB列を話者、C列を本文、D列の「選択肢」「〜を選択」「選択肢差分終了」「ステータス…表示」を分岐とカルテの指示として解釈しています。XLSX自体はローカルに保持し、本文は `src/data/source_rows.json` にキャッシュ。MAPの「家で休む」の3行と総括のカウンセリングの導入・結びは、プロトタイプ用に追加した文章です。

## 断片集の全編取り込み（2026-09-25）

`よだかプロト_断片集1.xlsx`（10編）と `よだかプロト_断片集2.xlsx`（7編）の全シートをMAPの行き先にしました。断片集1には題名が無いため、プロト用の仮題を `src/tools/import_scenario.py` の `EVENTS` に記載。背景は既存7種で代用（路上・歩道橋・街（夕方）・ゲームセンター→街、自室→自宅リビング）。先生・太鼓戦士・いのり・ずんだもんの立ち絵は無いため名前だけ表示します。新しい言葉3語の回想・返答はプロト用に追加した文章です。
