#!/usr/bin/env bash
# fetch-sources.sh — 下載 librime iOS 交叉編譯所需依賴源（SPEC §22.4）。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
SRC="$ROOT/src"; mkdir -p "$SRC"; cd "$SRC"
log(){ printf '\033[36m[fetch]\033[0m %s\n' "$*"; }

dl(){ # url outfile
  [ -f "$2" ] && { log "已存在 $2"; return; }
  log "下載 $2"; curl -sSL --max-time 600 -o "$2.part" "$1" && mv "$2.part" "$2"
}

# CMake-friendly deps（tarball）
dl "https://codeload.github.com/jbeder/yaml-cpp/tar.gz/refs/tags/0.8.0" yaml-cpp-0.8.0.tgz
dl "https://codeload.github.com/google/glog/tar.gz/refs/tags/v0.7.1"    glog-0.7.1.tgz
dl "https://codeload.github.com/google/leveldb/tar.gz/refs/tags/1.23"   leveldb-1.23.tgz
# boost：headers + regex（b2）
dl "https://archives.boost.io/release/1.86.0/source/boost_1_86_0.tar.bz2" boost-1.86.0.tar.bz2

# 解壓 tarball
for t in yaml-cpp-0.8.0 glog-0.7.1 leveldb-1.23; do
  d="${t%-*}"; [ -d "$d" ] || { log "解壓 $t"; mkdir -p "$d"; tar xzf "$t.tgz" -C "$d" --strip-components=1; }
done
[ -d boost ] || { log "解壓 boost"; mkdir -p boost; tar xjf boost-1.86.0.tar.bz2 -C boost --strip-components=1; }

# opencc：含 submodule（marisa-trie / darts-clone），需 git clone --recursive
if [ ! -d opencc ]; then
  log "git clone opencc 1.1.9 (--recursive)"
  git clone --recursive --depth 1 --branch ver.1.1.9 https://github.com/BYVoid/OpenCC.git opencc
fi

log "完成。源清單："
ls -d "$SRC"/*/ 2>/dev/null
