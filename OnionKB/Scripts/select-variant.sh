#!/usr/bin/env bash
# select-variant.sh <full|plustrim|lite> — 切換要打包的 RimeData 變體（§131；§140 修：同時換 shared）。
#   full：純注音 + 81 萬 phrases.chtp 擴充（Plus）；plustrim：Plus 精選 35.6 萬詞（§175，0.1.183 穩定版）；lite：純注音核心。
# build 與 shared 必須成對一致，否則 librime 會在裝置端重編詞庫（lite 會 OOM 閃退）。
# RimeData/{build,shared} 不入庫，由本腳本從 RimeData-variants/{build,shared}-$V 生成；打包前先執行。
set -euo pipefail
V="${1:-full}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
for kind in build shared; do
  SRC="$ROOT/RimeData-variants/$kind-$V"
  DST="$ROOT/RimeData/$kind"
  [ -d "$SRC" ] || { echo "未知變體或缺檔：'$kind-$V'" >&2; exit 1; }
  rm -rf "$DST"; cp -R "$SRC" "$DST"
done
echo "✓ RimeData/{build,shared} → $V 版（build $(du -sh "$ROOT/RimeData/build"|cut -f1) / shared $(du -sh "$ROOT/RimeData/shared"|cut -f1)）"
echo "  接著：cd OnionKB && xcodegen generate && bash Scripts/package-ipa.sh"
