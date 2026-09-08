# 検証結果

2026-09-08、Godot 4.6.2 / macOS / Chrome（Playwrightによる実ブラウザ操作）で確認。

- `make lint`: RuffとGodotの読み込みが成功。
- `make test`: pytest 2件成功。インポーターのカバレッジ98.85%。全12シナリオルートの到達性・分岐排他・8語の到達を確認。
- Godotランタイム検証: 1,583チェック成功。3種の解釈、上下限、保存復元、重複収集防止、二重回答防止、実UIの文字送り・モーダル・終了画面を確認。
- `make web`: 非スレッドのWebリリースビルド成功。
- GitHub Pages公開処理: [実行34229580900](https://github.com/xemonodesign/godot-novel-yodaka/actions/runs/34229580900) 成功。公開URL HTTP 200。
- 公開URLをChromeで読み込み、クリック操作で冒頭からエンディングまで通過。8語の収集と8回答を実際のIndexedDB保存データでも確認。JavaScript / Godotの実行時エラー0件。
- 公開URLを再読み込み →「つづきから」→ 結果画面の復元を確認。
- 標本をクリックして元の発言と解釈を閲覧し、Escapeで閉じられることを確認。
- 1280×800、および844×390の横長画面で画面全体の表示を確認。実機スマートフォン・Safariは未検証。

![振り返り](screenshots/reflection.png)

![結果](screenshots/result.png)
