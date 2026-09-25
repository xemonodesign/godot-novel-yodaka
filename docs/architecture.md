# 構成

- `project.godot` / `src/main.tscn`: Godotの起動設定とルート画面。
- `src/main.gd`: 1280×800を基準にしたUI。会話、MAP、夜（言葉を育てる）、カルテ、総括のカウンセリング、結果画面、クリック待ち暗転、話者の明暗。
- `src/story_state.gd`: 周回の進行、収集、即時効果、夜の成長、総括の回答、0〜100の4パラメータ、JSON保存（v4）。
- `src/word_effect.gd`: 言葉の取得時に標本の周囲へ描画する光の粒と波紋。
- `src/specimen.gd`: SubViewportごとの3D世界、カメラ・照明と実メッシュ。育てた言葉は明るく大きく描き、結晶を足す。
- `src/data/word_marks.json`: 原稿に対する編集用マーキング。もらった時の `effects` と3つの `interpretations`。
- `src/data/source_rows.json`: ゲームで使うシートの本文キャッシュ（行番号・話者・セリフ・演出欄）。元のXLSXが無い環境でのインポートとテストに使用。
- `src/data/scenario.json`: ビルドに含まれる289ノードの有向グラフ、周回設定 `rounds`、行き先 `map_events`、10種類の言葉。
- `src/tools/import_scenario.py`: XLSX（または上記キャッシュ）のB/C/D列を読み込み、カウンセリング台本の3択、本編の分岐、寄り道、休息を接続。Excelの読み仮名rPhは除外。
- `tests/test_scenario.py`: カウンセリングの27通り、章ごとの全ルート、寄り道の到達語、効果の範囲、キャッシュの存在。
- `tests/test_runtime.gd`: 実際のGodot状態・UIで3方針の通しプレイ、即時効果、夜の成長、週の解放・ストレス制限、勇気の分岐、保存復元、旧形式の拒否、モーダル、二重クリック、本文の収まりを検証。
- `tests/browser_smoke.cjs`: Playwrightで公開ビルドを通しプレイし、IndexedDBの実データで各状態を検証。

## 進行

`current` は台本ノードのIDか、`map` / `night` / `counseling` / `result` のいずれか。

- ノードの `kind` は `counsel`（冒頭のカウンセリング）、`outing`（寄り道）、`main`（本編）。末尾の `next` はカウンセリングが `map`、寄り道と本編が `night`。
- `rounds` は `[{outings, chapter}]`。寄り道を `outings` 回終えた夜のあと `chapter` が始まり、章を終えた夜のあと次の週の `map`（最終章なら `counseling`）へ進みます。`round_index` と `outings_done` で管理し、夜に入る時点で `after_night` を決めます。
- `map_events` の `unlock` は行ける週、`repeatable` は「家で休む」。訪問済みは `visited`。ストレスが `STRESS_LIMIT`（80）以上なら休息以外を選べません。
- 言葉は読み終えた行で収集し、`word.effects` をその場で適用して `gains[id]` に差分を記録します。同じ行を再開しても重複しません。ノードの `effects`（休息）と選択肢の `effects`（チュートリアル）も同様にその場で適用します。
- 出かけると `OUTING_EFFECTS`（ストレス+5）、章が始まると `CHAPTER_EFFECTS`（+6）。休息は `rest_2` の `effects`（-15）。
- 夜は `grow(id, index)` で未成長の言葉を1つだけ育て、`answers` に `stage: "night"` で記録。`sleep()` で `SLEEP_EFFECTS`（-4）のうえ次へ進みます。
- 総括のカウンセリングは `reviewed` 番目の言葉を順に扱い、育てた言葉は `grown_reply`、未成長の言葉は `question → choice → reply` を経て `response`。最後に `closing`（カルテ）→ `farewell` → `result`。
- `preview()` が0〜100の上限・下限を反映した差分を返し、予告と適用の両方で使用します。1回に動く項目は最大2つ。

初期値は `[60, 35, 35, 35]`（ストレス・勇気・自認・キラキラ）。CHAPTER 4の「お姫様じゃなくてもいい」は勇気60以上で選択可能で、`can_choose()` がUIの無効化に加えて状態遷移自体も防ぎます。

## 保存

保存先は `user://yodaka_v1.json`。WebではGodotのIndexedDBを使います。別端末への同期はありません。

形式v4は `current` `collected` `gains` `answers` `stats` `history` `read_count` `speed` `scene_key` `pending_word` `counsel_step` `reviewed` `round_index` `outings_done` `visited` `after_night` `night_step` `night_word` を保存し、読み込み時にすべて検証します。v1〜v3（以前の流れ）は読み込まず、タイトルで「はじめから」を案内します。

暗転中は本文描画のタイマー・AUTO・Space・Escapeを止め、クリックのフェードアウト完了で確認済みにします。カルテ（`karte: true` の行と総括の `closing`）はクリックで開き、閉じてから次へ進みます。

Web exportはCompatibilityレンダラーと非スレッドのテンプレートを使用します。GitHub Pagesで追加のCOOP/COEPヘッダーを必要としない構成です。参考：[GodotのWeb export](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html)。
