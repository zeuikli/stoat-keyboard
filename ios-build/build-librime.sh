#!/usr/bin/env bash
# build-librime.sh — 用完整 librime 1.16.1 源 + iOS deps 交叉編譯 librime 靜態庫，
# 組裝 librime.xcframework（device arm64 + simulator arm64）。SPEC §22.3。
set -euo pipefail
export PATH="/opt/homebrew/bin:$PATH"
ROOT="$(cd "$(dirname "$0")" && pwd)"
LSRC="$ROOT/src/librime-full"
DEPLOY=16.0
NCPU=$(sysctl -n hw.ncpu)
log(){ printf '\033[35m[librime]\033[0m %s\n' "$*"; }
die(){ printf '\033[31m[librime:FAIL]\033[0m %s\n' "$*" >&2; exit 1; }
slice_sysroot(){ [ "$1" = ios ] && echo iphoneos || echo iphonesimulator; }

# lua loslib.c 用 system()（iOS unavailable）→ stub l_system（os.execute 在沙箱無意義）
patch_lua(){
  local los="$LSRC/plugins/librime-lua/thirdparty/lua5.4/loslib.c"
  [ -f "$los" ] || return 0
  grep -q "OnionKB l_system stub" "$los" || \
    sed -i '' '1i\
#define l_system(cmd) (-1) /* OnionKB l_system stub (iOS no system()) */
' "$los"
}

build_one(){
  patch_lua
  local slice="$1"; local sysroot; sysroot=$(slice_sysroot "$slice")
  local prefix="$ROOT/out/$slice"; local bld="$ROOT/b/$slice/librime"
  log "==== librime $slice ===="
  cmake -S "$LSRC" -B "$bld" -G "Unix Makefiles" \
    -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_SYSROOT="$sysroot" -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOY" \
    -DCMAKE_PREFIX_PATH="$prefix" -DCMAKE_MODULE_PATH="$LSRC/cmake" \
    -DCMAKE_FIND_ROOT_PATH="$prefix" \
    -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=BOTH \
    -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=BOTH \
    -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=BOTH \
    -DBUILD_SHARED_LIBS=OFF -DBUILD_STATIC=ON \
    -DBUILD_TEST=OFF -DBUILD_DATA=OFF -DBUILD_MERGED_PLUGINS=ON \
    -DENABLE_LOGGING=ON -DENABLE_THREADING=ON \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DCMAKE_POLICY_DEFAULT_CMP0167=NEW \
    -DCMAKE_BUILD_TYPE=Release >/dev/null || die "$slice configure 失敗"
  cmake --build "$bld" -j"$NCPU" --target rime-static >/dev/null || die "$slice build 失敗"
  local lib; lib=$(find "$bld" -name "librime.a" | head -1)
  [ -n "$lib" ] || die "$slice 找不到 librime.a"
  cp "$lib" "$prefix/lib/librime.a"
  log "$slice ✓ librime.a ($(du -h "$prefix/lib/librime.a" | cut -f1))"
}

# 合併所有靜態庫成單一 librime_full.a（含全部 deps），方便 xcframework
merge_slice(){
  local slice="$1"; local prefix="$ROOT/out/$slice"
  local libs=("$prefix/lib/librime.a" "$prefix/lib/libyaml-cpp.a" "$prefix/lib/libglog.a" \
              "$prefix/lib/libleveldb.a" "$prefix/lib/libmarisa.a" "$prefix/lib/libopencc.a" \
              "$prefix/lib/libboost_regex.a")
  for l in "${libs[@]}"; do [ -f "$l" ] || die "merge 缺 $l"; done
  libtool -static -o "$prefix/lib/librime_full.a" "${libs[@]}" 2>/dev/null
  log "$slice ✓ librime_full.a ($(du -h "$prefix/lib/librime_full.a" | cut -f1))"
}

for slice in "${@:-ios sim}"; do build_one "$slice"; merge_slice "$slice"; done

# xcframework（含公開標頭 rime_api.h）
HDR="$ROOT/out/headers"; mkdir -p "$HDR"
cp "$LSRC/src/rime_api.h" "$LSRC/src/rime_levers_api.h" "$HDR/" 2>/dev/null || \
  cp "$LSRC/src/"rime_api*.h "$HDR/"
XCF="$ROOT/out/librime.xcframework"; rm -rf "$XCF"
ARGS=()
for slice in ios sim; do
  [ -f "$ROOT/out/$slice/lib/librime_full.a" ] && \
    ARGS+=(-library "$ROOT/out/$slice/lib/librime_full.a" -headers "$HDR")
done
xcodebuild -create-xcframework "${ARGS[@]}" -output "$XCF" >/dev/null && \
  log "✓ $XCF" && find "$XCF" -name "*.a" -exec du -h {} \;
