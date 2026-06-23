#!/usr/bin/env bash
# build-deps.sh — 交叉編譯 librime 的 6 依賴為 iOS（device arm64 + simulator arm64）。
# SPEC §22.4。產物：out/<slice>/{lib,include}。slice ∈ {ios, sim}。
set -euo pipefail
export PATH="/opt/homebrew/bin:$PATH"
ROOT="$(cd "$(dirname "$0")" && pwd)"
SRC="$ROOT/src"
DEPLOY=16.0
NCPU=$(sysctl -n hw.ncpu)
log(){ printf '\033[36m[deps]\033[0m %s\n' "$*"; }
die(){ printf '\033[31m[deps:FAIL]\033[0m %s\n' "$*" >&2; exit 1; }

slice_sysroot(){ [ "$1" = ios ] && echo iphoneos || echo iphonesimulator; }

cmake_ios(){ # dep_src build_dir slice  [extra cmake args...]
  local src="$1" bld="$2" slice="$3"; shift 3
  local sysroot; sysroot=$(slice_sysroot "$slice")
  local prefix="$ROOT/out/$slice"
  cmake -S "$src" -B "$bld" -G "Unix Makefiles" \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_SYSROOT="$sysroot" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOY" \
    -DCMAKE_INSTALL_PREFIX="$prefix" \
    -DCMAKE_PREFIX_PATH="$prefix" \
    -DBUILD_SHARED_LIBS=OFF \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    "$@" >/dev/null
  cmake --build "$bld" -j"$NCPU" --target install >/dev/null
}

build_slice(){
  local slice="$1"
  local sysroot; sysroot=$(slice_sysroot "$slice")
  local sdk; sdk=$(xcrun --sdk "$sysroot" --show-sdk-path)
  local prefix="$ROOT/out/$slice"
  mkdir -p "$prefix/lib" "$prefix/include"
  log "==== slice=$slice (sysroot=$sysroot) ===="

  # --- yaml-cpp ---
  if [ ! -f "$prefix/lib/libyaml-cpp.a" ]; then
    log "[$slice] yaml-cpp"; cmake_ios "$SRC/yaml-cpp" "$ROOT/b/$slice/yaml-cpp" "$slice" \
      -DYAML_CPP_BUILD_TESTS=OFF -DYAML_CPP_BUILD_TOOLS=OFF -DYAML_CPP_BUILD_CONTRIB=OFF -DYAML_CPP_FORMAT_SOURCE=OFF
  fi

  # --- glog ---
  if [ ! -f "$prefix/lib/libglog.a" ]; then
    log "[$slice] glog"; cmake_ios "$SRC/glog" "$ROOT/b/$slice/glog" "$slice" \
      -DWITH_GFLAGS=OFF -DWITH_GTEST=OFF -DWITH_UNWIND=OFF -DWITH_SYMBOLIZE=OFF -DBUILD_TESTING=OFF
  fi

  # --- leveldb ---
  if [ ! -f "$prefix/lib/libleveldb.a" ]; then
    log "[$slice] leveldb"; cmake_ios "$SRC/leveldb" "$ROOT/b/$slice/leveldb" "$slice" \
      -DLEVELDB_BUILD_TESTS=OFF -DLEVELDB_BUILD_BENCHMARKS=OFF -DHAVE_SNAPPY=OFF
  fi

  # --- marisa (opencc 內附 marisa-0.2.6；其 CMakeLists 無 min_required/project/install）---
  local msrc="$SRC/opencc/deps/marisa-0.2.6"
  grep -q cmake_minimum_required "$msrc/CMakeLists.txt" || {
    printf 'cmake_minimum_required(VERSION 3.5)\nproject(marisa CXX)\n' | \
      cat - "$msrc/CMakeLists.txt" > "$msrc/CMakeLists.txt.new" && mv "$msrc/CMakeLists.txt.new" "$msrc/CMakeLists.txt"
  }
  if [ ! -f "$prefix/lib/libmarisa.a" ]; then
    log "[$slice] marisa"
    local md="$ROOT/b/$slice/marisa"
    cmake -S "$msrc" -B "$md" -G "Unix Makefiles" \
      -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_ARCHITECTURES=arm64 \
      -DCMAKE_OSX_SYSROOT="$sysroot" -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOY" \
      -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_POLICY_VERSION_MINIMUM=3.5 >/dev/null
    cmake --build "$md" -j"$NCPU" --target marisa >/dev/null
    find "$md" -name "libmarisa.a" -exec cp {} "$prefix/lib/" \;
    cp "$msrc/include/marisa.h" "$prefix/include/"
    cp -R "$msrc/include/marisa" "$prefix/include/"
  fi

  # --- opencc (lib only; data 已在 RimeData，不需 cross 跑 dict 工具) ---
  # opencc tools 觸發 iOS MACOSX_BUNDLE install 錯誤；data 依賴 tools 的 opencc_dict。
  # 只要 libopencc（data 已在 RimeData）→ 拔掉 tools + data 子目錄
  sed -i.bak 's/^add_subdirectory(tools)/#&/' "$SRC/opencc/src/CMakeLists.txt"
  sed -i.bak 's/^add_subdirectory(data)/#&/' "$SRC/opencc/CMakeLists.txt"
  if [ ! -f "$prefix/lib/libopencc.a" ]; then
    log "[$slice] opencc (libopencc target only)"
    local ob="$ROOT/b/$slice/opencc"
    cmake -S "$SRC/opencc" -B "$ob" -G "Unix Makefiles" \
      -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_ARCHITECTURES=arm64 \
      -DCMAKE_OSX_SYSROOT="$sysroot" -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOY" \
      -DCMAKE_INSTALL_PREFIX="$prefix" -DCMAKE_PREFIX_PATH="$prefix" \
      -DBUILD_SHARED_LIBS=OFF -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DBUILD_TESTING=OFF -DENABLE_GTEST=OFF >/dev/null
    cmake --build "$ob" -j"$NCPU" --target libopencc >/dev/null
    # 手動 harvest（避免 install 觸發 cross 跑 dict 工具）
    find "$ob" -name "libopencc.a" -exec cp {} "$prefix/lib/" \;
    # opencc headers → include/opencc/（鏡像 vendored 佈局，librime include <opencc/Config.hpp>）
    mkdir -p "$prefix/include/opencc"
    cp "$SRC/opencc/src/"*.hpp "$prefix/include/opencc/"
    cp "$SRC/opencc/src/opencc.h" "$prefix/include/opencc/" 2>/dev/null || true
    cp "$ob/src/opencc_config.h" "$prefix/include/opencc/" 2>/dev/null || \
      cp "$SRC/opencc/src/opencc_config.h" "$prefix/include/opencc/" 2>/dev/null || true
  fi

  # --- boost: headers + 手動編 regex（避 b2 iOS 之苦）---
  if [ ! -f "$prefix/lib/libboost_regex.a" ]; then
    log "[$slice] boost headers + regex"
    [ -d "$prefix/include/boost" ] || cp -R "$SRC/boost/boost" "$prefix/include/boost"
    local bo="$ROOT/b/$slice/boost-regex"; mkdir -p "$bo"
    # 正確 platform tag：device=ios、simulator=ios...-simulator（-mios-version-min 會誤標成 IOS）
    local triple
    [ "$slice" = ios ] && triple="arm64-apple-ios$DEPLOY" || triple="arm64-apple-ios$DEPLOY-simulator"
    local srcs; srcs=$(find "$SRC/boost/libs/regex/src" -name "*.cpp")
    for f in $srcs; do
      xcrun --sdk "$sysroot" clang++ -c "$f" -I"$SRC/boost" -isysroot "$sdk" \
        -target "$triple" -std=c++17 -O2 -fvisibility=hidden \
        -o "$bo/$(basename "$f").o"
    done
    xcrun --sdk "$sysroot" ar rcs "$prefix/lib/libboost_regex.a" "$bo"/*.o
    # cmake 4.x 用 BoostConfig（FindBoost 已棄/移除）→ 手寫 config 套件
    local bcm="$prefix/lib/cmake/Boost"; mkdir -p "$bcm"
    cat > "$bcm/BoostConfig.cmake" <<'CMK'
set(Boost_VERSION 1.86.0)
set(Boost_FOUND TRUE)
get_filename_component(_bp "${CMAKE_CURRENT_LIST_DIR}/../../.." ABSOLUTE)
set(Boost_INCLUDE_DIRS "${_bp}/include")
set(Boost_INCLUDE_DIR "${_bp}/include")
foreach(t headers boost)
  if(NOT TARGET Boost::${t})
    add_library(Boost::${t} INTERFACE IMPORTED)
    set_target_properties(Boost::${t} PROPERTIES INTERFACE_INCLUDE_DIRECTORIES "${_bp}/include")
  endif()
endforeach()
if(NOT TARGET Boost::regex)
  add_library(Boost::regex STATIC IMPORTED)
  set_target_properties(Boost::regex PROPERTIES
    IMPORTED_LOCATION "${_bp}/lib/libboost_regex.a"
    INTERFACE_INCLUDE_DIRECTORIES "${_bp}/include")
endif()
set(Boost_LIBRARIES Boost::regex)
set(Boost_REGEX_FOUND TRUE)
CMK
    cat > "$bcm/BoostConfigVersion.cmake" <<'CMK'
set(PACKAGE_VERSION 1.86.0)
set(PACKAGE_VERSION_COMPATIBLE TRUE)
set(PACKAGE_VERSION_EXACT FALSE)
CMK
  fi

  log "[$slice] 依賴庫："; ls "$prefix/lib"/*.a
}

for slice in "${@:-ios sim}"; do build_slice "$slice"; done
log "ALL DONE"
