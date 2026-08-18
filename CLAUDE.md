# 新規クローン直後のセットアップ

`SubwayWidget.xcodeproj` / `Info.plist` / `*.entitlements` は `project.yml` から生成され、
`.gitignore` によりリポジトリに含まれていない。**クローン直後や `project.yml` を編集した後は
`xcodegen generate` が必要**（`brew install xcodegen`）。

初回ビルドは SwiftSoup を取りに行くのでネットワークが要る。

```sh
./scripts/sync-team.sh
./scripts/test.sh
./scripts/deploy-local.sh
```

`xcodegen generate` のあと **必ず `./scripts/sync-team.sh`** する。証明書から
`Config/Team.xcconfig`（gitignore）を書き、`DEVELOPMENT_TEAM` をビルドに乗せる。
これを忘れると App Group が `.jp.shigeya.SubwayWidget` になり、App Intents の
`linkd.autoShortcut` エラーとウィジェット設定の不具合が同時に出る。

# ビルドについて（重要）

## 1. 必ず署名付きでビルドすること

AppIntents は Team ID 付き署名が必要。無署名や adhoc だとウィジェットがプレースホルダのまま止まる。
`.app` のファイル名は `東京地下鉄運行情報.app`（濁点なし）。実行ファイル名は ASCII の `SubwayWidget` のまま。
濁点付き日本語の `.app` 名は拡張が起動しない。

## 2. `CONFIGURATION_BUILD_DIR` を独自パスに上書きしないこと

SwiftSoup のモジュール解決が壊れる。標準の DerivedData にビルドし、配置は
`scripts/deploy-local.sh` に任せる。同スクリプトは完成した `.app` を
`build/東京地下鉄運行情報.app` にもコピーする（`build/` は gitignore）。

Team ID は手元の「Apple Development」証明書の OU から引く。複数あるときは
`DEVELOPMENT_TEAM=XXXXXXXXXX ./scripts/deploy-local.sh`。

# テスト

`SubwayWidgetTests` はホストアプリを立てない単体テスト。通信せず、原則 UserDefaults も触らない。

- `ToeiPageParserTests` — `Tests/Fixtures/` の時刻表・運行状況 HTML
- `CatalogAndURLTests` — 駅カタログ（都営・東京メトロ）と URL 組み立て、ウィジェット設定のフォールバック
- `UpcomingTrainTests` — 次発選定、土休日、終電後の翌日始発

フィクスチャは Yahoo!路線情報の構造を模した固定 HTML。サイト側のマークアップが変わったら
実ページを保存し直して期待値も更新する。

# データソース

パースは `Shared/ToeiPageParser.swift` に集約する。データは Yahoo!路線情報
（`transit.yahoo.co.jp/timetable/{駅ID}/{方面ID}?kind=` と `/diainfo/area/4`）。
`URLSession` で取れるので WKWebView は使わない。

カタログは都営4路線 + 東京メトロ9路線。`ToeiCatalog` が路線定義と都営駅、`MetroCatalog` がメトロ駅。
時刻表 HTML は `table.tblDiaDetail` / `li.timeNumb`。`kind` は 1=平日、2=土曜、4=日曜・祝日。
終電の 24 時台は 0 時台（24:00 以降）として持つ。

ホストは `LSUIElement` のメニューバー常駐。サンドボックスあり。App Group は Team ID 付き。

ウィジェット拡張の `Provider.buildEntry()` から通信してはいけない。時刻表・運行状況・祝日一覧は
App が App Group に書いたものを読むだけ。

# ウィジェット設定（App Intents）

`EntityQuery.entities(for:)` は名前を空文字で返さない。親（事業者・路線・駅）と合わない ID は
落とさず、その親のデフォルトエンティティを返す。空配列を返すと設定画面が古い選択のまま残る。

従属パラメータは **1段ずつ** 依存させる。方面クエリで `(\.$line, \.$station)` のように両方必須にすると、
路線変更直後は駅が空で `defaultResult` が呼べず、方面が空欄のままになる。
路線の `defaultResult` は駅・方面クエリまで伝播しないので、駅クエリは `$railwayOperator` と `$line` を、
方面クエリは `$railwayOperator` と `$line` と `$station` を、それぞれ別の `@IntentParameterDependency` にする。
駅がまだ新しい路線と一致しないときは、その路線のデフォルト駅の先頭方面を返す。

デフォルト駅は丸ノ内線 東京（`SelectionKey.default`）。`WidgetEntityMatch.defaultStation(for:)` /
`defaultLine(for:)` をウィジェット設定とメニューバー（`ArrivalModel`）で共有すること。
先頭駅（荻窪）や `LineID.lines(of:).first`（銀座）に落とさない。

`WidgetInfo.configuration as? SelectStationIntent` は常に nil。
`info.widgetConfigurationIntent(of: SelectStationIntent.self)` を使う。

# アイコン

`scripts/generate-app-icon.swift` が App / ウィジェット拡張の AppIcon と、
ウィジェット一覧用の `AppIcon60x60*.png` を書き出す。背景は大江戸線のマゼンタ一色。
ウィジェット編集・設定は iOS 由来で `CFBundleIcons` / `AppIcon60x60` を探す。
`COMBINE_HIDPI_IMAGES` を YES にすると PNG が TIFF に潰れて格子プレースホルダになる。

一覧のアイコンが古い（4色レインボーなど）ときは、`MARKETING_VERSION` を上げて
`deploy-local.sh` で入れ直す。それでも残るならウィジェットを外して入れ直す。

# 開発中に踏まないこと（tobus-widget と同じ）

- `.app` 名に濁点付き日本語を入れない（拡張が起動せず空枠になる）
- アプリ終了は bundle ID（`tell application id "jp.shigeya.SubwayWidget"`）
- `??` は空文字を値ありと扱う
- `MenuBarExtra(.window)` は `NSApp.activate` しないと TextField が入力を受け取れない
- 型名の `Toei*`（`ToeiCatalog` / `ToeiAPI` / `ToeiPageParser` など）は都営専用だった名残。中身はメトロも含む

# ログ

```sh
log stream --predicate 'subsystem beginswith "jp.shigeya.SubwayWidget"' --level debug
```
