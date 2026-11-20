#!/bin/bash
# 各スクリプトから source して使う共通処理。単体では実行しない。

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$REPO_ROOT/SubwayWidget.xcodeproj"
SCHEME="SubwayWidget"
APP_NAME="東京地下鉄運行情報.app"
BUNDLE_ID="jp.shigeya.SubwayWidget"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

die() { echo "error: $*" >&2; exit 1; }

# Team ID は環境ごとに異なる個人情報なのでリポジトリには書かない。
# DEVELOPMENT_TEAM が指定されていればそれを使い、無ければ手元の
# 「Apple Development」証明書の OU から引く。
resolve_team_id() {
  if [[ -n "${DEVELOPMENT_TEAM:-}" ]]; then
    echo "$DEVELOPMENT_TEAM"
    return
  fi

  local names
  names=$(security find-identity -v -p codesigning \
    | sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p')

  [[ -n "$names" ]] || die "Apple Development 証明書が見つかりません。Xcode でサインインしてください。"

  if [[ $(wc -l <<<"$names") -gt 1 ]]; then
    echo "複数の証明書が見つかりました。DEVELOPMENT_TEAM=<Team ID> を指定してください:" >&2
    # 名前の括弧内は証明書の ID で Team ID ではない。OU を並べて出す。
    local n
    while IFS= read -r n; do
      echo "  Team ID $(security find-certificate -c "$n" -p | openssl x509 -noout -subject \
        | sed -n 's/.*OU *= *\([A-Z0-9]*\).*/\1/p')  ← $n" >&2
    done <<<"$names"
    exit 1
  fi

  local team
  team=$(security find-certificate -c "$names" -p \
    | openssl x509 -noout -subject \
    | sed -n 's/.*OU *= *\([A-Z0-9]*\).*/\1/p')

  [[ -n "$team" ]] || die "証明書から Team ID を取得できませんでした: $names"
  echo "$team"
}

write_team_xcconfig() {
  local team
  # `run_xcodebuild ... || die` のように || の左辺から呼ばれると set -e が効かないので、
  # 明示的に止める（空の Team で Team.xcconfig を書くと App Group がずれる）。
  team=$(resolve_team_id) || exit 1
  [[ -n "$team" ]] || die "Team ID が空です。"
  DEVELOPMENT_TEAM_RESOLVED="$team"
  mkdir -p "$REPO_ROOT/Config"
  cat > "$REPO_ROOT/Config/Team.xcconfig" <<EOF
// 自動生成。手元の証明書から Team ID を書いた。リポジトリには含めない。
DEVELOPMENT_TEAM = $team
EOF
}

# 署名付きの xcodebuild。CONFIGURATION_BUILD_DIR は指定しない
# （SwiftPM 成果物のコピーとモジュール探索がずれて SwiftSoup の解決に失敗するため）。
run_xcodebuild() {
  write_team_xcconfig
  local team="$DEVELOPMENT_TEAM_RESOLVED"
  xcodebuild "$@" \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination 'platform=macOS' \
    -allowProvisioningUpdates \
    CODE_SIGN_STYLE=Automatic \
    CODE_SIGN_IDENTITY="Apple Development" \
    DEVELOPMENT_TEAM="$team"
}

built_app_path() {
  local dir
  dir=$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -showBuildSettings 2>/dev/null \
    | sed -n 's/^[[:space:]]*TARGET_BUILD_DIR = //p' | head -1)
  [[ -n "$dir" && -d "$dir/$APP_NAME" ]] && echo "$dir/$APP_NAME"
}

# 配置済みとみなす場所（deploy-local.sh の既定と DMG からの手動インストール先）。
installed_app_paths() {
  local d
  for d in "$HOME/Applications" /Applications; do
    [[ -d "$d/$APP_NAME" ]] && echo "$d/$APP_NAME"
  done
  return 0
}

# Launch Services に登録された同じ bundle ID のアプリを列挙する。
# DerivedData・build/・アーカイブ・DMG のマウント先など、もう存在しないパスも含む。
registered_app_paths() {
  "$LSREGISTER" -dump 2>/dev/null | awk -v id="$BUNDLE_ID" '
    /^-+$/ { path = "" }
    /^path:/ { sub(/^path:[[:space:]]*/, ""); sub(/ \(0x[0-9a-fA-F]+\)$/, ""); path = $0 }
    /^identifier:/ && $2 == id && path != "" { print path; path = "" }
  ' | sort -u
  mdfind "kMDItemCFBundleIdentifier == \"$BUNDLE_ID\"" 2>/dev/null || true
}

# 引数のアプリ以外の登録を外し、引数のアプリを登録し直す。
# 同じ bundle ID のコピー（Team ID 違いを含む）が複数登録されていると、再起動後に
# NotificationCenter が「Widget extension could not be looked up」で拡張を引けず、
# ウィジェットが黒い枠のまま止まる。
unregister_stray_copies() {
  local path keep skip
  while IFS= read -r path; do
    [[ -z "$path" ]] && continue
    skip=0
    for keep in "$@"; do
      [[ "$path" == "$keep" ]] && skip=1
    done
    (( skip )) && continue
    echo "    登録解除: $path"
    "$LSREGISTER" -u "$path" >/dev/null 2>&1 || true
  done < <(registered_app_paths | sort -u)
  for keep in "$@"; do
    "$LSREGISTER" -f -R -trusted "$keep"
  done
}

# DerivedData は触らず、完成した .app をリポジトリの build/ にも置く。
# CONFIGURATION_BUILD_DIR を上書きすると SwiftSoup の解決が壊れる。
copy_app_to_repo_build() {
  local src="$1"
  local dest="$REPO_ROOT/build/$APP_NAME"
  [[ -d "$src" ]] || die "コピー元がありません: $src"
  mkdir -p "$REPO_ROOT/build"
  rm -rf "$dest"
  ditto "$src" "$dest"
  echo "    $dest"
}
