# 構成

- `project.godot` / `src/main.tscn`: Godotの起動設定とルート画面。
- `src/main.gd`: 1280×800を基準にしたUI。会話、MAP、言葉の取得暗転（留める／手放す／忘れる）、カウンセリングのセッション画面、トラウマがほどけた／奥から出てきた暗転、カルテ、結果画面、話者の明暗。
- `src/story_state.gd`: 周回の進行、8枠の言葉欄、トラウマの固さと必要EXP、言葉のレベル、EXP、効果込みのパラメータ計算、JSON保存（v5）。
- `src/word_effect.gd`: 暗転時に標本の周囲へ描画する光の粒と波紋。
- `src/specimen.gd`: SubViewportごとの3D世界。言葉は花と石（育つと結晶）、トラウマは棘のある暗い石（固さで棘の数が変わる）。
- `src/data/word_marks.json`: 原稿に対する編集用マーキング。もらった時の `effects`、手放した時の `value`、3段階の `levels`（`cost` `insight` `passive` `counsel`）。
- `src/data/traumas.json`: トラウマの定義。`debuffs`、`base_cost`、`deeper`、話す会話 `talk`、向き合う会話 `soften`、奥のトラウマの `surface`。
- `src/data/source_rows.json`: ゲームで使うシートの本文キャッシュ（行番号・話者・セリフ・演出欄）。
- `src/data/scenario.json`: ビルドに含まれる289ノードの有向グラフ、`rules`、周回設定 `rounds`、行き先 `map_events`、10種類の言葉、10種類のトラウマ。
- `src/tools/import_scenario.py`: XLSX（または上記キャッシュ）のB/C/D列を読み込み、カウンセリング台本の3択、本編の分岐、寄り道、休息を接続。トラウマと言葉のデータを同梱。
- `tests/test_scenario.py`: カウンセリングの27通り、章ごとの全ルート、寄り道の到達語、言葉の3段階、トラウマの定義、キャッシュの存在。
- `tests/test_runtime.gd`: 実際のGodot状態・UIで3方針の通しプレイ、効果込みの数値、留める／手放す／忘れる、話す・向き合う・育てる、奥のトラウマ、勇気の分岐、保存復元、旧形式の拒否、本文の収まりを検証。
- `tests/screenshots.gd`: 仮想ディスプレイ上で各画面のスクリーンショットを `docs/screenshots/` に保存。
- `tests/browser_smoke.cjs`: Playwrightで公開ビルドを通しプレイし、IndexedDBの実データで各状態を検証。

## 進行

`current` は台本ノードのIDか、`map` / `counseling` / `result` のいずれか。

- ノードの `kind` は `counsel`（冒頭のカウンセリング）、`outing`（寄り道）、`main`（本編）。末尾の `next` はカウンセリングが `counseling`（第1回のセッション）、寄り道と本編が `sleep`。
- `rounds` は `[{outings, chapter, counseling}]`。寄り道を `outings` 回終えると `chapter` が始まり、章を終えた日の夜に `counseling` が真なら次のセッション、偽なら次の週の `map` へ。`round_index` と `outings_done` で管理します。セッション番号 `counsel_session` は 0（冒頭）から数え、最後の周回のあとは `final_session()` が真で、別れの言葉のあと `result` へ。
- `sleep` に着くと `_end_day()` が `SLEEP_EFFECTS`（-4）を適用し、章が始まるなら `CHAPTER_EFFECTS`（+6）も続けて適用。夜の画面はありません。
- `map_events` の `unlock` は行ける週、`repeatable` は「家で休む」。訪問済みは `visited`。表示ストレスが `STRESS_LIMIT`（80）以上なら休息以外を選べません。出かけると `OUTING_EFFECTS`（+5）。

## 言葉欄・トラウマ・EXP

- `slots` は `rules.slot_count`（8）個の文字列。`t:<id>` がトラウマ、`w:<id>` が言葉、空文字が空き枠。開始時は `deep` でないトラウマ8つで埋まります。
- `trauma_state[id]` は `{hardness, cost, loosened}`。デバフは `scaled_debuffs()` で固さに比例して縮みます（`offset` は値×固さ/100、`cap` は固さ 0 で 100 に戻る、倍率系は固さ 0 で ×1）。
- 表示値は `effective(i)` ＝ 素の `stats[i]` ＋ `stat_offset(i)`（トラウマの `offset` と言葉の `stat`）を 0〜`stat_cap(i)` に収めたもの。選択肢の `requires` とストレス制限は表示値で判定します。
- `preview()` / `apply()` は素の値に加算しますが、勇気・自認・キラキラの増加には `gain_multiplier()`、ストレスの減少には `recovery_multiplier()` を掛けます（最低 ±1）。予告と適用は同じ関数を通ります。
- `finish_line()` は新しい行を読むたびに `exp_per_tap()`（`rules.exp_per_tap` × トラウマと言葉の `exp` 倍率、最低 1）を `exp` と `exp_total` に加えます。カウンセリングの会話も `main.gd` 側で同じく加算します。
- 言葉の取得：`pending_word` と `pending_step`（`offer` → `kept` / `released`、空きがなければ `forget` を経由）。`keep_pending()` は空き枠へ、`release_pending()` は `release_value()`（`value` × レベル × `release` 倍率）を EXP に、`forget_for_pending(id)` は持っている言葉を EXP に変えて同じ枠に新しい言葉を置きます。`acknowledge_word()` で確定。
- セッション（`counsel_step == "session"`）：
  - `start_talk(id)` → `talk` ステップで `talk` の5行 → `_finish_talk()` が `loosened` を立て、`cost` を `rules.first_cost`（最初の1つ）か `base_cost / rules.talk_divisor` に。1セッション1回（`talked`）。
  - `confront_preview(id, cards)` が必要EXP（`cost` × 言葉の `cost` 倍率）、ほぐし量（`rules.soften_base` ＋ 言葉の `soften`）、`calm`、奥のものが出るか（`deeper` があり、`calm` なしで固さが `rules.surface_threshold` を跨ぐ）を返し、`confront()` が同じ計算で適用。固さ 0 で `resolved` に入り枠が空く。奥のものが出ると `deeper` が同じ枠に固さ 100・未ほぐしで入り `surfaced` に記録。
  - `grow(id)` はレベルの `cost` を払って `levels[id]` を上げる。`forget_in_session(id)` は言葉を EXP に。
  - `session_lines` に直近のみなと／よだかの2行を持ち、画面上部に表示。`end_session()` → `closing`（第2回以降はカルテ）→ `farewell` → `map` か `result`。

## 保存

保存先は `user://yodaka_v1.json`。WebではGodotのIndexedDBを使います。別端末への同期はありません。

形式v5は `current` `collected` `gains` `stats` `history` `read_count` `speed` `scene_key` `pending_word` `pending_step` `pending_gain` `pending_slot` `counsel_step` `counsel_session` `counsel_trauma` `talk_index` `talked` `session_lines` `round_index` `outings_done` `visited` `slots` `trauma_state` `levels` `exp` `exp_total` `released` `resolved` `surfaced` を保存し、読み込み時にすべて検証します（枠の中身と `trauma_state` / `levels` の整合、取得中の言葉の状態、話している最中のトラウマなど）。v4以前は読み込まず、タイトルで「はじめから」を案内します。

暗転中は本文描画のタイマー・AUTO・Space・Escapeを止めます。言葉の取得暗転は「留める／手放す」を選ぶまで閉じられず、結果表示のあとのクリックで `acknowledge_word()` を呼びます。カルテ（`karte: true` の行と第2回以降の `closing`）はクリックで開き、閉じてから次へ進みます。

Web exportはCompatibilityレンダラーと非スレッドのテンプレートを使用します。GitHub Pagesで追加のCOOP/COEPヘッダーを必要としない構成です。参考：[GodotのWeb export](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html)。
