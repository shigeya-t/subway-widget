#!/bin/bash
# 手元の Apple Development 証明書から Config/Team.xcconfig を書く。
# Xcode の Signing で Team を毎回入れ直さなくてよくするため。ファイルは gitignore。

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"
write_team_xcconfig
echo "DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM_RESOLVED"
