#!/usr/bin/env bash
# Lima CI 版本切换——可逆、不污染 brew 状态
# 用法:
#   lima-switch install <ci-解压目录>    接上 CI 构建版本
#   lima-switch revert                   切回 brew 原版
#   lima-switch status                   看当前用哪个

set -euo pipefail

BREW_PREFIX=${BREW_PREFIX:-$(brew --prefix 2>/dev/null || echo /opt/homebrew)}
CELLAR="$BREW_PREFIX/Cellar/lima"
ODK="2.1.1"  # brew 原版，回退时用这里的软链记录

# -- install: 把 CI 产物复制到新 keng 并切换软链 --
install_ci() (
  if [[ $# -lt 1 ]]; then
    echo "用法: lima-switch install <ci-解压目录>" >&2
    exit 1
  fi
  src="$1"
  if [[ ! -d "$src/bin" ]]; then
    echo "错误: $src/bin 不存在，请确认解压目录正确" >&2
    exit 1
  fi

  ver=${2:-$(cd "$src" && stat -f%m bin/limactl 2>/dev/null | cut -c1-8)}
  [[ -z "$ver" ]] && ver="ci-$(date +%Y%m%d-%H%M)"
  keng="$CELLAR/$ver"

  echo "→ 安装 CI 构建到 $keng"
  mkdir -p "$keng/bin" "$keng/libexec" "$keng/share"
  cp "$src"/bin/*      "$keng/bin/"
  cp -a "$src"/libexec/* "$keng/libexec/" 2>/dev/null || true
  cp -a "$src"/share/*   "$keng/share/"
  chmod 755 "$keng"/bin/*

  _link "$ver"
  echo "✓ 已切换 $(limactl --version)"
)

# -- revert: 切回 brew 原版 --
revert() (
  echo "→ 切回 $ODK"
  _link "$ODK"
  echo "✓ 已恢复 $(limactl --version)"
)

# -- status: 当前使用的版本 --
status() (
  cur=$(readlink "$BREW_PREFIX/opt/lima" | sed 's|.*/||')
  ver=$(limactl --version 2>/dev/null || echo "无法获取")
  echo "当前 keg: $cur | $ver"
)

# -- 切换软链 --
_link() {
  local ver="$1"
  keng="$CELLAR/$ver"
  ln -sfn "$keng" "$BREW_PREFIX/opt/lima"
  for name in limactl lima; do
    ln -sf "../Cellar/lima/$ver/bin/$name" "$BREW_PREFIX/bin/$name"
  done
  # share 按需
  if [[ -d "$keng/share/lima" ]]; then
    mkdir -p "$(dirname "$BREW_PREFIX/share/lima")"
    ln -sfn "../Cellar/lima/$ver/share/lima" "$BREW_PREFIX/share/lima"
  fi
}

# -- 入口 --
case "${1:-}" in
  install)
    shift; install_ci "$@" ;;
  revert)
    shift; revert "$@" ;;
  status)
    shift; status "$@" ;;
  *)
    echo "用法: lima-switch {install <dir>|revert|status}" >&2
    exit 1
    ;;
esac
