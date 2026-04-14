#!/usr/bin/env bash

set -euo pipefail

INSTALL_BIN_DIR="${CX_INSTALL_BIN_DIR:-$HOME/.local/bin}"

print_help() {
  cat <<'EOF'
用法:
  bash scripts/uninstall.sh [--bin-dir <path>]

说明:
  - 默认删除 ~/.local/bin/cx
  - 不会自动修改你的 shell 配置
EOF
}

main() {
  local target_file=""

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

  target_file="$INSTALL_BIN_DIR/cx"

  if [[ -e "$target_file" ]]; then
    rm -f "$target_file"
    echo "已删除: $target_file"
  else
    echo "未找到: $target_file"
  fi

  echo "如果你之前手动写入过 PATH，请按需清理 shell 配置"
}

main "$@"
