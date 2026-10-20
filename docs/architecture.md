# 構成

- `project.godot` / `src/main.tscn`: Godotの起動設定とルート画面。
- `src/main.gd`: 1280×800を基準にしたUI。会話、MAP、心の棚とマウスオンのプレビュー、言葉の取得時の「留める／手放す」、カウンセリング（会話画面のまま棚をクリックして開く・向き合う・強化）、カルテ、結果画面、上枠だけの暗転、話者の明暗。
- `src/story_state.gd`: 周回の進行（夜なし）、EXP、心の棚（8枠）、トラウマの3状態とデバフ、言葉のLv、カウンセリングのセッション、0〜100の4パラメータと反映後の値、JSON保存（v6）。
- `src/goo.gd`: 謎のトラウマの描画。暗い赤紫のマダラがゆっくりうごめく。
- `src/word_effect.gd`: 言葉の取得時に標本の周囲へ描画する光の粒と波紋。
- `src/specimen.gd`: SubViewportごとの3D世界、カメラ・照明と実メッシュ。`flower` / `rock` は言葉（Lvで小さな結晶を足す）、`thorn` はトラウマ（残りの強さでトゲが増減）。
- `src/mind_map.gd`: カルテの「ことばの地図」。暗い面に、集めた言葉ごとの光（結晶で拡大）、中心とのつながり、忘れた言葉の燠火、未出会いの言葉の暗い点を描く。
- `src/data/word_marks.json`: 原稿に対する編集用マーキング。もらった時の `effects`、Lv2で選ぶ3つの `interpretations`、カードとしての `tag` `forget` `levels`（`hold` / `insight`）。
- `src/data/traumas.json`: 心の棚を最初に埋める6つのトラウマ。デバフ（謎のあいだの値と鑑定済みの値）、開くEXP、向き合うEXP、会話。
- `src/data/source_rows.json`: ゲームで使うシートの本文キャッシュ（行番号・話者・セリフ・演出欄）。元のXLSXが無い環境でのインポートとテストに使用。
- `src/data/scenario.json`: ビルドに含まれる361ノードの有向グラフ、周回設定 `rounds`（`counseling` で章のあとのセッションを指定）、行き先 `map_events`、6種類の言葉、6つのトラウマ、棚の枠数 `slots`。
- `src/tools/import_scenario.py`: XLSX（または上記キャッシュ）のB/C/D列を読み込み、カウンセリング台本の3択、本編の分岐、寄り道、休息を接続。Excelの読み仮名rPhは除外。
- `tests/test_scenario.py`: カウンセリングの27通りが最初のセッションに到達すること、章ごとの全ルート、寄り道の到達語、効果の範囲、カードとトラウマのデータ検証、キャッシュの存在。
- `tests/test_runtime.gd`: 実際のGodot状態・UIで3方針の通しプレイ（4回のセッションで開く・強化・向き合う）、EXP、棚の整合、3状態のデバフ、保存復元、旧形式の拒否、取得時の選択、棚のクリックとプレビュー、上枠だけの暗転、本文の収まりを検証。
- `tests/browser_smoke.cjs`: Playwrightで公開ビルドを通しプレイし、IndexedDBの実データで各状態を検証。

## 進行

`current` は台本ノードのIDか、`map` / `counseling` / `result` のいずれか。

- ノードの `kind` は `counsel`（冒頭のカウンセリング）、`outing`（寄り道）、`main`（本編）。末尾の `next` はチュートリアルが `counseling`（最初のセッション）、寄り道と本編が `night`。`night` は状態としては存在せず、`choose()` が `_end_day()` でその場で次の行き先（`map`、章の先頭、`counseling`）に置き換えます。夜の回復はありません。
- `rounds` は `[{outings, chapter, counseling}]`。寄り道を `outings` 回終えると `chapter` が始まり、章を終えると `counseling` が真なら（最終章なら必ず）セッションへ、そうでなければ次の週の `map` へ。`session` はセッションの通し番号（1〜4）。
- 言葉は読み終えた行で収集し、`word.effects`（`gain_half` のデバフ中は半分）をその場で適用して `gains[id]` に記録、`pending_word` に置きます。UIは「心に留める」`keep_pending()`（空き枠へ）、「手放す」`release_pending()`（`forget_value()` のEXP）、「入れ替える」`swap_pending(slot)` のどれかを選ぶまで進めません。
- 1タップ（初めて読む行、カウンセリングの動的な行も `read_dynamic()` で同様）ごとに `exp_per_tap()`（`EXP_PER_TAP` × 持っている言葉の `exp_mult` の積）が `exp` `exp_total` に入ります。
- 心の棚 `slots` は8要素で、`{kind: "trauma"|"word", id}` か空。`traumas[id]` は `{state: "mystery"|"appraised"|"accepted"}`。`effective_stats()` が素の `stats` に、持っている言葉の `hold`（ステータス加算）とトラウマのデバフ（`plus` は加算、`half` は割合の減算、`cap` は上限。謎のあいだは `debuff.mystery`、鑑定済みは `debuff.value` の量。`rest_half` / `forget_half` / `gain_half` は棚にある限り有効）を反映した値を返し、メーター表示・ストレス制限・選択肢の `requires` に使います。
- カウンセリングは `counsel_step` で進みます。`opening_doctor → opening_yodaka → board`。`board` は会話画面のまま棚を操作する状態で、`appraise(id)`（謎を開く：`appraise` のEXPを払い `appraised` に。1セッション1回 `talked`）→ `talk_recall → talk_doctor → board`、`face(id)`（鑑定済みに `face_cost()` ＝ `cost` × 持っている言葉の `cost_mult` の積（同じ `tag` なら `RESONANCE`=2 回）を払い `accepted`、枠を空ける）→ `face_line → face_response → board`、`grow(id)`（次の `levels[].cost` を払って Lv を上げる。Lv2 は `grow_question → grow_choice → interpret() → grow_reply → grow_response → board`、Lv3 は `grow_insight → grow_response → board`）。`finish_session()` → `closing`（総括ならカルテ）→ `farewell` → `map`（総括なら `result`）。開く・向き合う・強化はいずれも `board` でだけ可能です。
- 出かけることと章の開始にストレスはかからない。代わりに `STRESS_EVENTS`（`import_scenario.py`）で指定した嫌な瞬間の行に `effects: {"ストレス": n}` が付き、読み終えた時に上がる（最後の行には付けず、気づきの±1と分ける）。休息は `rest_2` の `effects`（-15、`rest_half` で半分）。
- `preview()` が0〜100の上限・下限を反映した差分を返し、予告と適用の両方で使用します。

初期値は `[60, 5, 5, 5]`（ストレス・勇気・自認・キラキラ）。表示上は最初から `[64, 5, 5, 4]`。CHAPTER 4の「お姫様じゃなくてもいい」は反映後の勇気15以上で選択可能で、`can_choose()` がUIの無効化に加えて状態遷移自体も防ぎます。

## 保存

保存先は `user://yodaka_v1.json`。WebではGodotのIndexedDBを使います。別端末への同期はありません。

形式v6は `current` `collected` `slots` `forgotten` `gains` `answers` `stats` `history` `read_count` `speed` `scene_key` `pending_word` `exp` `exp_total` `traumas` `levels` `session` `counsel_step` `talked` `focus` `grow_word` `round_index` `outings_done` `visited` を保存し、読み込み時にすべて検証します（棚と `traumas` の整合、Lvの範囲、ステップごとの前提など）。v1〜v5（以前の流れ）は読み込まず、タイトルで「はじめから」を案内します。

場所の切り替えの暗転は上の枠（`FRAME`）だけを覆い、その間は本文描画のタイマー・AUTO・Space・Escapeを止め、クリックのフェードアウト完了で確認済みにします。言葉の取得時の暗転は画面全体で、背景クリックでは閉じず、ボタンで留めるか手放すかを決めると閉じます。カルテ（`karte: true` の行と総括の `closing`）はクリックで開き、閉じてから次へ進みます。

Web exportはCompatibilityレンダラーと非スレッドのテンプレートを使用します。GitHub Pagesで追加のCOOP/COEPヘッダーを必要としない構成です。参考：[GodotのWeb export](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html)。
