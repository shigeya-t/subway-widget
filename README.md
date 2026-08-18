# 都営地下鉄ウィジェット

都営地下鉄の次発時刻・残り時間と運行状況を表示する macOS ウィジェットです。
[都バス接近情報ウィジェット](https://github.com/shigeya-t/tobus-widget) と同じ構成
（WidgetKit ウィジェット + メニューバー常駐アプリ）で、[Yahoo!路線情報](https://transit.yahoo.co.jp/)
の公開 HTML を取得し、クライアント側で解析して表示します。

## できること

- 通知センター / デスクトップに置ける WidgetKit ウィジェット（小・中サイズ）
- 選んだ路線・駅・方面の **次発時刻と残り時間**、その後 2本（小） / 3本（中）
- 本日分が終わったら翌日の始発に切り替え（見出しで平日 / 土曜 / 日曜・祝日を明示）
- Yahoo!路線情報と同じ「平常運転 / 遅延」
- メニューバーに次発までの残り時間を常時表示
- APIキー等の登録は不要。Dock には出さない（メニューバーのみ）

次発の残り時間は在線位置ではなく **定刻 − 現在時刻** です。遅延時は運行状況で知らせ、
時刻そのものは定刻のまま出します。

デフォルトは大江戸線 **勝どき・大門／六本木方面** です。

## 必要なもの

- macOS 14 以降
- Xcode 15 以降
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)（`brew install xcodegen`）
- インターネット接続（初回ビルド時に SwiftSoup を取得します）

## ビルドと導入

```sh
brew install xcodegen
xcodegen generate
open SubwayWidget.xcodeproj
```

Xcode で以下を行ってください。

1. リポジトリ直下で `./scripts/sync-team.sh` を実行する（手元の証明書から Team ID を書く）
2. **Signing & Capabilities** で `SubwayWidget` と `SubwayWidgetExtension` の Team が入っていることを確認する
   （無料の Personal Team で動作します）
3. スキーム `SubwayWidget` を選んで実行（⌘R）する
   （メニューバーに路面電車のアイコンが出ます。Dock には出ません）
4. メニューバーから路線・駅・方面を選ぶ
5. 「ウィジェットを編集」を開き、左の一覧から **東京地下鉄運行情報** を選んでウィジェットを追加する

> 一覧に出るアプリ名は `.app` のファイル名です。濁点付きの日本語だとウィジェット拡張が起動しなくなるため、この名前（濁点なし）にしています。

常時使う場合は、システム設定 →「一般」→「ログイン項目」に登録しておくと便利です。

バンドル ID は `jp.shigeya.SubwayWidget` です。フォーク時は `project.yml` の
`bundleIdPrefix` / `PRODUCT_BUNDLE_IDENTIFIER` を書き換えてください。あわせて次は手で直します。

- `Shared/AppSettings.swift` の `Notification.Name(...)` 2つ
- `scripts/_common.sh` の `BUNDLE_ID`

App Group は `$(DEVELOPMENT_TEAM).jp.shigeya.SubwayWidget` です。Team を入れれば追従します。

> **署名について（重要）**
> アドホック署名では AppIntents が解決できず、ウィジェットが動きません。必ず Team 付きで署名してください。

```sh
./scripts/deploy-local.sh                 # ~/Applications へ配置
./scripts/deploy-local.sh /Applications   # 配置先を指定
./scripts/test.sh                         # 単体テスト
```

## 路線・駅・方面の選び方

メニューバーとウィジェット設定のどちらも、路線 → 駅 → 方面の順です。駅はカタログ（4路線）から選ぶので
検索のための通信はしません。大江戸線の方面名は駅ごとに異なり、時刻表の表見出しから取ります。

## 更新のしくみ

**このアプリはメニューバーに常駐します。** 常駐をやめるとウィジェットはほぼ更新されません。

取得はメニューバーアプリに一本化しており、**ウィジェット拡張は自分では通信しません。**
アプリが 60 秒ごとに運行状況を、駅×方面の時刻表は日をまたがない限り 1 日 1 回取り、
App Group 経由でウィジェットへ渡します。配置済みウィジェットが別の駅を出している場合もまとめて取ります。

使わない時間帯は「一時停止」でリクエストを止められます。「今すぐ更新」は一時停止中でも取得します。

## データソースについて

[Yahoo!路線情報](https://transit.yahoo.co.jp/) の公開ページを HTML として取得しています。
公式 API・オープンデータではありません。

| 用途 | URL |
| --- | --- |
| 駅時刻表 | `https://transit.yahoo.co.jp/timetable/{駅ID}/{方面ID}?kind={1\|2\|4}` |
| 運行情報 | `https://transit.yahoo.co.jp/diainfo/area/4` |
| 祝日 | `https://holidays-jp.github.io/api/v1/date.json` |

`kind` は 1=平日、2=土曜、4=日曜・祝日です。祝日判定に holidays-jp を使います。

**注意点**

- HTML 構造や駅・方面 ID は予告なく変わる可能性があります
- Yahoo! JAPAN の利用規約は自動取得を想定していません。このアプリは **個人の私的利用** を想定しています
- 運行情報・時刻は Yahoo!路線情報の掲載に合わせた目安で、実際の列車と異なることがあります
- 交通局・ODPT・LINEヤフーへこのアプリの不具合を問い合わせないでください

## 構成

```
project.yml               XcodeGen のプロジェクト定義
Shared/
  ToeiCatalog.swift         4路線・駅・方面の静的カタログ
  ToeiConfig.swift          タイムゾーン・ダイヤ区分
  TrainModels.swift         便・時刻表・運行状況
  ToeiAPI.swift             Yahoo!路線情報への HTTP GET
  ToeiPageParser.swift      SwiftSoup による HTML 解析
  TrainScheduleService.swift 時刻表の日次キャッシュ
  TrainStatusService.swift  運行状況の短時間キャッシュ
  HolidayChecker.swift      祝日判定
  SelectStationIntent.swift ウィジェット設定（路線→駅→方面）
  RefreshTrainIntent.swift  更新・一時停止ボタン
  AppSettings.swift         App Group 経由の共有
App/                       メニューバー常駐アプリ
WidgetExtension/           ウィジェット本体（通信しない）
Tests/                     単体テストと HTML フィクスチャ
scripts/
  deploy-local.sh
  test.sh
```

`Info.plist` と `*.entitlements` は `project.yml` から生成されるため、リポジトリには含めていません。

## ライセンス

[MIT License](LICENSE)

ライセンスが及ぶのはこのリポジトリのコードだけです。都営地下鉄の運行データ、および
Yahoo!路線情報・東京都交通局に対する権利は一切含みません。
