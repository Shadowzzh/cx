#!/usr/bin/env bash

set -euo pipefail

SCRIPT_SOURCE="${BASH_SOURCE[0]:-}"
SCRIPT_DIR=""
REPO_ROOT=""
LOCAL_SOURCE=""
EMBEDDED_VERSION="v0.1.7"

if [[ -n "$SCRIPT_SOURCE" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_SOURCE")" && pwd)"
  REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
  LOCAL_SOURCE="$REPO_ROOT/bin/cx"
fi
DEFAULT_DOWNLOAD_URL="${CX_DOWNLOAD_URL:-https://raw.githubusercontent.com/Shadowzzh/cx/main/bin/cx}"
INSTALL_BIN_DIR="${CX_INSTALL_BIN_DIR:-$HOME/.local/bin}"
WRITE_SHELL_CONFIG="0"

print_help() {
  cat <<'EOF'
用法:
  bash scripts/install.sh [--bin-dir <path>] [--write-shell-config]

说明:
  - 默认安装到 ~/.local/bin/cx
  - 默认不修改 shell 配置，只打印 PATH 提示
  - 如果本地存在仓库源码，优先使用本地 bin/cx
  - 如果通过远程脚本执行，会尝试从 CX_DOWNLOAD_URL 下载
EOF
}

detect_rc_file() {
  local shell_name=""
  shell_name="$(basename "${SHELL:-}")"

  case "$shell_name" in
    zsh)
      printf '%s\n' "$HOME/.zshrc"
      ;;
    bash)
      if [[ -f "$HOME/.bashrc" ]]; then
        printf '%s\n' "$HOME/.bashrc"
      else
        printf '%s\n' "$HOME/.bash_profile"
      fi
      ;;
    *)
      printf '%s\n' "$HOME/.profile"
      ;;
  esac
}

ensure_dependencies() {
  if ! command -v bash >/dev/null 2>&1; then
    echo "未找到 bash，无法安装" >&2
    exit 1
  fi

  if ! command -v codex >/dev/null 2>&1; then
    echo "未找到 codex，请先安装 Codex CLI" >&2
    exit 1
  fi
}

ensure_source() {
  if [[ -n "$LOCAL_SOURCE" && -f "$LOCAL_SOURCE" ]]; then
    printf '%s\n' "$LOCAL_SOURCE"
    return 0
  fi

  if ! command -v curl >/dev/null 2>&1; then
    echo "未找到本地源码，且系统没有 curl，无法下载 cx" >&2
    exit 1
  fi

  local temp_source=""
  temp_source="$(mktemp)"
  curl -fsSL "$DEFAULT_DOWNLOAD_URL" -o "$temp_source"
  printf '%s\n' "$temp_source"
}

resolve_version() {
  local version_file=""

  if [[ -n "$REPO_ROOT" ]]; then
    version_file="$REPO_ROOT/VERSION"
  fi

  if [[ -n "$version_file" && -f "$version_file" ]]; then
    head -n 1 "$version_file"
    return 0
  fi

  printf '%s\n' "$EMBEDDED_VERSION"
}

compute_build_id() {
  local file_path="$1"

  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file_path" | awk '{print substr($1, 1, 8)}'
    return 0
  fi

  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file_path" | awk '{print substr($1, 1, 8)}'
    return 0
  fi

  printf '%s\n' "unknown"
}

write_path_hint() {
  local rc_file="$1"
  local path_line="export PATH=\"$INSTALL_BIN_DIR:\$PATH\""

  if [[ ":$PATH:" == *":$INSTALL_BIN_DIR:"* ]]; then
    echo "PATH 已包含 $INSTALL_BIN_DIR"
    return 0
  fi

  if [[ "$WRITE_SHELL_CONFIG" == "1" ]]; then
    touch "$rc_file"

    if ! grep -F -- "$path_line" "$rc_file" >/dev/null 2>&1; then
      printf '\n%s\n' "$path_line" >> "$rc_file"
    fi

    echo "已将 PATH 写入 $rc_file"
    return 0
  fi

  echo "请将下面这行加入 $rc_file:"
  echo "$path_line"
}

main() {
  local source_file=""
  local target_file=""
  local rc_file=""
  local version=""
  local build_id=""

  while (($# > 0)); do
    case "$1" in
      --bin-dir)
        if (($# < 2)); then
          echo "--bin-dir 缺少值" >&2
          exit 1
        fi
        INSTALL_BIN_DIR="$2"
        shift 2
        ;;
      --write-shell-config)
        WRITE_SHELL_CONFIG="1"
        shift
        ;;
      -h|--help)
        print_help
        exit 0
        ;;
      *)
        echo "未知参数: $1" >&2
        exit 1
        ;;
    esac
  done

  ensure_dependencies

  mkdir -p "$INSTALL_BIN_DIR"
  source_file="$(ensure_source)"
  target_file="$INSTALL_BIN_DIR/cx"
  cp "$source_file" "$target_file"
  chmod +x "$target_file"
  version="$(resolve_version)"
  build_id="$(compute_build_id "$target_file")"

  rc_file="$(detect_rc_file)"
  write_path_hint "$rc_file"

  if [[ "$source_file" != "$LOCAL_SOURCE" ]]; then
    rm -f "$source_file"
  fi

  echo "安装 cx 版本: $version (build $build_id)"
  echo "安装完成: $target_file"
  echo "你现在可以运行: cx"
}

main "$@"
