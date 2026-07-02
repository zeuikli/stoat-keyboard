#!/usr/bin/env bash
# package-ipa.sh — 產出 unsigned OnionKB.ipa（SPEC §10.2 / §10.3 側載重簽路徑）。
# 本環境僅 dev 簽章、無 Apple iOS 憑證 → 走 unsigned device build + 手動 Payload 封裝；
# AltStore/Sideloadly 安裝時重簽（§10.3）。M0 stub 引擎；M-B1 後換 librime.xcframework。
set -euo pipefail
PROJ_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJ_DIR"

DD="build/dd-dev"
OUT="build/ipa"
APP="$DD/Build/Products/Release-iphoneos/OnionKB.app"

log(){ printf '\033[36m[ipa]\033[0m %s\n' "$*"; }
die(){ printf '\033[31m[ipa:FAIL]\033[0m %s\n' "$*" >&2; exit 1; }

log "unsigned device build（iphoneos, Release）"
xcodebuild -project OnionKB.xcodeproj -scheme OnionKB -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath "$DD" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  build > build/ipa-build.log 2>&1 || { tail -30 build/ipa-build.log; die "device build 失敗"; }

[ -d "$APP" ] || die "缺 $APP"
grep -q "BUILD SUCCEEDED" build/ipa-build.log || die "未見 BUILD SUCCEEDED"

log "封裝 Payload → .ipa"
rm -rf "$OUT" "build/Payload"
mkdir -p "$OUT" "build/Payload"
cp -R "$APP" "build/Payload/"
# §222 App 層瘦身：predict_office.db(7.5M)+gram(4M) 僅鍵盤 appex 執行期讀（predictor/octagram），
# 容器 App 只跑 deploy（不開互動 session、不讀這兩檔）→ 從 App 層剝除、appex 內保留。未壓縮 −11.6MB。
rm -f "build/Payload/OnionKB.app/RimeData/shared/predict_office.db" \
      "build/Payload/OnionKB.app/RimeData/shared/zh-hant-t-essay-bgc.gram"
( cd build && /usr/bin/zip -qry "../$OUT/OnionKB.ipa" Payload )
rm -rf "build/Payload"

IPA="$OUT/OnionKB.ipa"
[ -f "$IPA" ] || die "未產出 .ipa"
log "✓ 產出 $IPA ($(du -h "$IPA" | cut -f1))"
log "內容驗證："
/usr/bin/unzip -l "$IPA" | grep -E "OnionKB.app/OnionKB|OnionKBKeyboard.appex|RimeData/build/.*\.bin" | head
