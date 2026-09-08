# 構成

- `project.godot` / `src/main.tscn`: Godotの起動設定とルート画面。
- `src/main.gd`: 1280×800を基準にしたUI、文字送り、会話・振り返り・結果画面。
- `src/story_state.gd`: 進行、収集、解釈、0〜100のパラメータ、JSON保存。
- `src/specimen.gd`: SubViewportごとの3D世界、カメラ・照明と実メッシュ。
- `src/data/word_marks.json`: 原稿に対する編集用マーキング。
- `src/data/scenario.json`: ビルドに含まれる224ノードの有向グラフと8つの言葉。
- `src/tools/import_scenario.py`: XLSXのB/C列、演出欄を読み込み、明示的な分岐接続を構築。Excelの読み仮名rPhは除外。
- `tests/test_scenario.py`: 全12ルート、相互排他の分岐、全言葉到達、原文の保持。
- `tests/test_runtime.gd`: 実際のGodot状態・UIで重複収集、保存復元、6指標の変化、範囲、モーダル、二重クリック、終了を検証。

読み終わった行の言葉だけを収集します。同じ行を再開しても重複しません。カウンセリングの回答は言葉ごとに1回。回答直後に離れた場合も保存済みの値から次の問いに再開します。バックログは閲覧のみで、進行を巻き戻しません。

初期値は `[65,40,45,40,35,35]`。解釈の基本変動に `focus × 4` を加算し、0〜100に制限します。表示する差分は上限・下限を適用した実際の差分です。花・岩に肯定／否定の意味は固定せず、どちらも好きな解釈を選べます。

保存先は `user://yodaka_v1.json`。WebではGodotのIndexedDBを使います。別端末への同期はありません。

Web exportはCompatibilityレンダラーと非スレッドのテンプレートを使用します。GitHub Pagesで追加のCOOP/COEPヘッダーを必要としない構成です。参考：[GodotのWeb export](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html)。
