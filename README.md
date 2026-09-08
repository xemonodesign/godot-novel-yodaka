# よだか — ことばの標本

Godot 4.6.2 製のノベルゲーム・プロトタイプ。

**遊ぶ:** https://xemonodesign.github.io/godot-novel-yodaka/

冒頭のカウンセリング → りあの断片 → メイン01・02 → すみかの断片 → メイン03・04 → 集めた言葉のカウンセリング → 結果、の順で進みます。原稿の4章と分岐を収録し、医師との会話をプロトタイプ用に追加しました。

## 操作

- 画面をクリック、または Space / Enter：全文表示、もう一度で次の文章。
- 選択肢：クリック / タップして選択。AUTO は選択肢で止まります。
- 下の標本：クリックすると、誰にもらった言葉かと元の会話を読み返せます。
- 「読み返す」で会話ログ、「文字速度」で表示速度を変更できます。
- 同じブラウザ・同じURLで自動保存。「つづきから」で再開します。
- PC / 横向きの画面向けです。小さい画面では全体を縮小して表示します。

## 実装

- 1文字ずつの表示、全文表示、AUTO、会話ログ、速度変更、自動保存。
- 8個の大事な言葉を下線と色でマーキング。読み終えた時に自動収集。
- 独立した3Dビューポート内でローポリの花・岩が回転。
- メインの原稿分岐12ルートすべてが最後のカウンセリングに合流。
- もらった言葉ごとに3択で振り返り、6パラメータが変化。
- 「自認」は自分の捉え方への納得度という暫定指標。男女を数値の両端にはしていません。
- メイン原稿の男女・無性自認UP指定は分岐の文章のみ維持し、数値変化は今回のカウンセリング方式に集約しています。

元の台本・デザイン案・全断片の抽出アーカイブはローカルに保持し、公開物にはゲーム本編に必要な素材とデータを含めています。断片集の残り15編は今回の進行には未接続です。立ち絵は提供素材のよだかを使用し、他の登場人物は話者名で表示します。場面ごとの背景差分・音声・BGM・街での行き先選択は未実装です。

## 開発

Godot 4.6.2 と同バージョンの Export Templates を使います。

```sh
make install
make run
make lint
make test
make web
make serve
```

`make serve` の後、http://localhost:8060 を開きます。Web出力は `build/web/`。HTMLをダブルクリックして開く方式では動きません。`make web` は生成済みの `src/data/scenario.json` を使用するので、公開リポジトリだけでもビルドできます。

### 台本・言葉を変更する

1. 元のXLSXをプロジェクト直下に置きます（最初の作業フォルダには配置済み）。
2. `src/data/word_marks.json` の `node`（シート別ID＋行番号）と `word`（原文内の文字列）を指定します。
3. `make import` でXLSXから `scenario.json` を再生成。
4. `make test` → `make web`。

`model` は `flower` / `rock`、`color` は16進色、`focus` はストレス・勇気・知性・忍耐・キラキラ・自認の6順です。原稿の行番号を変えたら `src/tools/import_scenario.py` の分岐接続も更新してください。インポーターとpytestの検証には元の3冊のXLSXが必要です。

### 公開の更新

`gh-pages` ブランチのルートをGitHub Pagesの配信元にしています。

```sh
make web
git worktree add /tmp/yodaka-pages gh-pages
cp build/web/* /tmp/yodaka-pages/
touch /tmp/yodaka-pages/.nojekyll
git -C /tmp/yodaka-pages add .
git -C /tmp/yodaka-pages commit -m 'feat(web): update playable prototype'
git -C /tmp/yodaka-pages push origin gh-pages
```

既に作業ツリーがあればそのパスを再利用してください。ソース変更は `main` に通常どおりコミットします。

詳細は [構成](docs/architecture.md) と [素材・生成記録](docs/assets.md) を参照。
