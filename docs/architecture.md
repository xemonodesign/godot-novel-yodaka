# 構成

- `project.godot` / `src/main.tscn`: Godotの起動設定とルート画面。
- `src/main.gd`: 1280×800を基準にしたUI、中央揃えの文字送り、会話・振り返り・結果画面、クリック待ち暗転、話者の明暗。
- `src/story_state.gd`: 進行、収集、解釈、0〜100のパラメータ、JSON保存。
- `src/word_effect.gd`: 言葉の取得時に標本の周囲へ描画する光の粒と波紋。
- `src/specimen.gd`: SubViewportごとの3D世界、カメラ・照明と実メッシュ。
- `src/data/word_marks.json`: 原稿に対する編集用マーキング。
- `src/data/scenario.json`: ビルドに含まれる250ノードの有向グラフと10種類の言葉。
- `src/tools/import_scenario.py`: XLSXのB/C列、演出欄を読み込み、明示的な分岐接続を構築。Excelの読み仮名rPhは除外。
- `tests/test_scenario.py`: 全36ルート、相互排他の分岐、全言葉到達、原文の保持。
- `tests/test_runtime.gd`: 実際のGodot状態・UIで重複収集、保存復元、6指標の変化、範囲、モーダル、二重クリック、終了を検証。

読み終わった行の言葉だけを収集します。同じ行を再開しても重複しません。カウンセリングの回答は言葉ごとに1回。回答直後に離れた場合は、保存済みの数値を保ち、選んだよだかの返答から再開します。バックログは閲覧のみで、進行を巻き戻しません。

初期値は `[65,40,45,40,35,35]`。解釈ごとの `effects` は最大2項目の疎な辞書。`preview_effects()` で0〜100の上限・下限を反映した差分を計算し、予告と適用の両方で使用します。予告時点で既に上限・下限なら変化0と表示します。花・岩に肯定／否定の意味は固定せず、どちらも好きな解釈を選べます。

保存先は `user://yodaka_v1.json`。WebではGodotのIndexedDBを使います。別端末への同期はありません。

Web exportはCompatibilityレンダラーと非スレッドのテンプレートを使用します。GitHub Pagesで追加のCOOP/COEPヘッダーを必要としない構成です。参考：[GodotのWeb export](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html)。

セーブ形式v2は `scene_key`（表示済みの章・場所）、`pending_word`（クリック待ちの取得演出）、`counsel_step`（ドクターの導入、よだかの報告、回想、問い、選択、返答、受け止め）を保存。v1も読み込めます。暗転中は本文描画のタイマー・AUTO・Space・Escapeを止め、クリックのフェードアウト完了で確認済みにします。

セーブ形式v3は `selected_event` と `counsel_return` を追加し、v1/v2も読み込みます。CHAPTER 5末尾は `map` へ進み、選択したイベント末尾の `counseling_mid` を状態側で中間カウンセリングに変換します。中間の帰り先は `main4_5`、本編終了後は `result`。回答済みの言葉は再回答しません。`can_choose()` が勇気条件を検証し、UIの無効化に加えて状態遷移自体も防ぎます。
