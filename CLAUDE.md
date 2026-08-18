# 新規クローン直後のセットアップ

`SubwayWidget.xcodeproj` / `Info.plist` / `*.entitlements` は `project.yml` から生成され、
`.gitignore` によりリポジトリに含まれていない。**クローン直後や `project.yml` を編集した後は
`xcodegen generate` が必要**（`brew install xcodegen`）。

初回ビルドは SwiftSoup を取りに行くのでネットワークが要る。

```sh
./scripts/test.sh
./scripts/deploy-local.sh
```

# ビルドについて（重要）

## 1. 必ず署名付きでビルドすること

AppIntents は Team ID 付き署名が必要。無署名や adhoc だとウィジェットがプレースホルダのまま止まる。
`.app` のファイル名は `東京地下鉄運行情報.app`（濁点なし）。実行ファイル名は ASCII の `SubwayWidget` のまま。濁点付き日本語の `.app` 名は拡張が起動しない。

## 2. `CONFIGURATION_BUILD_DIR` を独自パスに上書きしないこと

SwiftSoup のモジュール解決が壊れる。標準の DerivedData にビルドし、配置は
`scripts/deploy-local.sh` に任せる。

Team ID は手元の「Apple Development」証明書の OU から引く。複数あるときは
`DEVELOPMENT_TEAM=XXXXXXXXXX ./scripts/deploy-local.sh`。

# テスト

`SubwayWidgetTests` はホストアプリを立てない単体テスト。通信せず、原則 UserDefaults も触らない。

- `ToeiPageParserTests` — `Tests/Fixtures/` の時刻表・運行状況 HTML
- `CatalogAndURLTests` — 駅カタログと URL 組み立て
- `UpcomingTrainTests` — 次発選定、土休日、終電後の翌日始発

フィクスチャは Yahoo!路線情報の構造を模した固定 HTML。サイト側のマークアップが変わったら
実ページを保存し直して期待値も更新する。

# データソース

パースは `Shared/ToeiPageParser.swift` に集約する。データは Yahoo!路線情報
（`transit.yahoo.co.jp/timetable/{駅ID}/{方面ID}?kind=` と `/diainfo/area/4`）。
`URLSession` で取れるので WKWebView は使わない。時刻表 HTML は `table.tblDiaDetail` /
`li.timeNumb`。`kind` は 1=平日、2=土曜、4=日曜・祝日。終電の 24 時台は 0 時台
（24:00 以降）として持つ。

ホストは `LSUIElement` のメニューバー常駐。サンドボックスあり。App Group は Team ID 付き。

`xcodegen generate` のあと **必ず `./scripts/sync-team.sh`** する。証明書から
`Config/Team.xcconfig`（gitignore）を書き、`DEVELOPMENT_TEAM` をビルドに乗せる。
これを忘れると App Group が `.jp.shigeya.SubwayWidget` になり、App Intents の
`linkd.autoShortcut` エラーとウィジェット設定の不具合が同時に出る。

ウィジェット拡張の `Provider.buildEntry()` から通信してはいけない。時刻表・運行状況・祝日一覧は
App が App Group に書いたものを読むだけ。

`EntityQuery.entities(for:)` は名前を空文字で返さない。引けない ID は落とす。

`WidgetInfo.configuration as? SelectStationIntent` は常に nil。
`info.widgetConfigurationIntent(of: SelectStationIntent.self)` を使う。

# 開発中に踏まないこと（tobus-widget と同じ）

- `.app` 名に濁点付き日本語を入れない（拡張が起動せず空枠になる）
- アプリ終了は bundle ID（`tell application id "jp.shigeya.SubwayWidget"`）
- `??` は空文字を値ありと扱う
- `MenuBarExtra(.window)` は `NSApp.activate` しないと TextField が入力を受け取れない

# ログ

```sh
log stream --predicate 'subsystem beginswith "jp.shigeya.SubwayWidget"' --level debug
```
