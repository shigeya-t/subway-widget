#!/bin/bash
#
# 署名付きでビルドし、配置済みのアプリを入れ替えて起動し直す。
#
#   ./scripts/deploy-local.sh                    # ~/Applications へ配置
#   ./scripts/deploy-local.sh /Applications      # 配置先を指定
#   DEVELOPMENT_TEAM=XXXXXXXXXX ./scripts/deploy-local.sh

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

DEST="${1:-$HOME/Applications}"
TARGET="$DEST/$APP_NAME"

echo "==> ビルド"
run_xcodebuild build >/dev/null || die "ビルドに失敗しました。詳細は xcodebuild を直接実行して確認してください。"

APP=$(built_app_path)
[[ -n "$APP" ]] || die "$APP_NAME が DerivedData に見つかりません。"
echo "    $APP"

echo "==> 実行中のプロセスを終了"
osascript -e "tell application id \"$BUNDLE_ID\" to quit" 2>/dev/null || true
osascript -e 'tell application id "jp.shigeya.ToeiWidget" to quit' 2>/dev/null || true
pkill -f "MacOS/SubwayWidget$" 2>/dev/null || true
pkill -f "MacOS/ToeiWidget$" 2>/dev/null || true
pkill -f "SubwayWidgetExtension" 2>/dev/null || true
pkill -f "ToeiWidgetExtension" 2>/dev/null || true
sleep 1

echo "==> 配置: $TARGET"
mkdir -p "$DEST"
rm -rf "$TARGET"
cp -R "$APP" "$DEST/"

"$LSREGISTER" -f -R -trusted "$TARGET"

echo "==> 署名の確認"
TEAM_LINE=$(codesign -dv "$TARGET/Contents/PlugIns/SubwayWidgetExtension.appex" 2>&1 \
  | grep TeamIdentifier || true)
echo "    ${TEAM_LINE:-TeamIdentifier が読めません}"
if [[ "$TEAM_LINE" == *"not set"* ]]; then
  die "無署名のビルドが配置されました。ウィジェットは動きません。"
fi

open "$TARGET"
echo "==> 完了。ウィジェット未配置なら「ウィジェットを編集」から追加してください。"
