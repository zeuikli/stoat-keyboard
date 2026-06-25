#!/usr/bin/env bash
# select-variant.sh <full|lite> — 切換要打包的 RimeData 變體（SPEC §131）。
#   full：純注音 + 81 萬 phrases.chtp 擴充詞庫（table.bin ~27MB）
#   lite：純注音核心（不含擴充詞庫，table.bin ~7.5MB、bundle 約一半）
# 兩者皆為 B 方案（bgc grammar，候選出「為」）+ librime 1.17.0。
# RimeData/build/ 不入庫，由本腳本從 build-full/ 或 build-lite/ 生成；打包前先執行。
set -euo pipefail
V="${1:-full}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SRC="$ROOT/RimeData-variants/build-$V"
DST="$ROOT/RimeData/build"
[ -d "$SRC" ] || { echo "未知變體：'$V'（需 full 或 lite）" >&2; exit 1; }
rm -rf "$DST"; cp -R "$SRC" "$DST"
echo "✓ RimeData/build → $V 版（$(du -sh "$DST" | cut -f1)）"
echo "  接著：cd OnionKB && xcodegen generate && bash Scripts/package-ipa.sh"
echo "  （lite 版建議把 Info.plist 的 CFBundleShortVersionString 加 -lite 標識）"
