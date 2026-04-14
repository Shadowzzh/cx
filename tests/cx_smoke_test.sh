#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CX_BIN="$ROOT_DIR/bin/cx"
CX_VERSION="$(<"$ROOT_DIR/VERSION")"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains() {
  local file="$1"
  local expected="$2"

  if ! grep -F -- "$expected" "$file" >/dev/null 2>&1; then
    fail "expected '$expected' in $file"
  fi
}

assert_not_contains() {
  local file="$1"
  local unexpected="$2"

  if grep -F -- "$unexpected" "$file" >/dev/null 2>&1; then
    fail "did not expect '$unexpected' in $file"
  fi
}

make_fake_commands() {
  local dir="$1"

  mkdir -p "$dir"

  cat > "$dir/codex" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" > "${CX_TEST_OUTPUT:?}"
EOF
  chmod +x "$dir/codex"

  cat > "$dir/fzf" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${CX_TEST_FZF_ARGS:-}" ]]; then
  printf '%s\n' "$@" > "$CX_TEST_FZF_ARGS"
fi

prompt=""
for arg in "$@"; do
  case "$arg" in
    --prompt=*)
      prompt="${arg#--prompt=}"
      ;;
  esac
done

printf '%s\n' "$prompt" >> "${CX_TEST_PROMPTS:?}"
options=()
while IFS= read -r line; do
  options+=("$line")
done

case "$prompt" in
  "思考等级: ")
    printf '%s\n' "high"
    ;;
  "Yolo: ")
    printf '%s\n' "no"
    ;;
  "Model: ")
    printf '%s\n' "gpt-5.2-codex"
    ;;
  *)
    if ((${#options[@]} == 0)); then
      exit 1
    fi
    printf '%s\n' "${options[0]}"
    ;;
esac
EOF
  chmod +x "$dir/fzf"
}

assert_line_present() {
  local file="$1"
  local expected="$2"

  if ! grep -Fx -- "$expected" "$file" >/dev/null 2>&1; then
    fail "expected line '$expected' in $file"
  fi
}

run_test_direct_launch() {
  local temp_dir
  temp_dir="$(mktemp -d)"

  make_fake_commands "$temp_dir/bin"
  : > "$temp_dir/prompts.txt"

  PATH="$temp_dir/bin:$PATH" \
    CX_TEST_OUTPUT="$temp_dir/output.txt" \
    CX_TEST_PROMPTS="$temp_dir/prompts.txt" \
    bash "$CX_BIN" yolo xhigh gpt-5.4 hello

  assert_contains "$temp_dir/output.txt" '--model gpt-5.4'
  assert_contains "$temp_dir/output.txt" 'model_reasoning_effort="xhigh"'
  assert_contains "$temp_dir/output.txt" '--dangerously-bypass-approvals-and-sandbox'
  assert_contains "$temp_dir/output.txt" 'hello'

  if [[ -s "$temp_dir/prompts.txt" ]]; then
    fail "direct launch should not open any menu"
  fi

  rm -rf "$temp_dir"
}

run_test_direct_launch_without_passthrough() {
  local temp_dir
  temp_dir="$(mktemp -d)"

  make_fake_commands "$temp_dir/bin"
  : > "$temp_dir/prompts.txt"

  PATH="$temp_dir/bin:$PATH" \
    CX_TEST_OUTPUT="$temp_dir/output.txt" \
    CX_TEST_PROMPTS="$temp_dir/prompts.txt" \
    bash "$CX_BIN" no-yolo low gpt-5.4

  assert_contains "$temp_dir/output.txt" '--model gpt-5.4'
  assert_contains "$temp_dir/output.txt" 'model_reasoning_effort="low"'
  assert_not_contains "$temp_dir/output.txt" '--dangerously-bypass-approvals-and-sandbox'

  if [[ -s "$temp_dir/prompts.txt" ]]; then
    fail "direct launch without passthrough should not open any menu"
  fi

  rm -rf "$temp_dir"
}

run_test_model_only_prompt() {
  local temp_dir
  temp_dir="$(mktemp -d)"

  make_fake_commands "$temp_dir/bin"
  : > "$temp_dir/prompts.txt"

  PATH="$temp_dir/bin:$PATH" \
    CX_TEST_OUTPUT="$temp_dir/output.txt" \
    CX_TEST_PROMPTS="$temp_dir/prompts.txt" \
    bash "$CX_BIN" yolo xhigh hello

  assert_contains "$temp_dir/output.txt" '--model gpt-5.2-codex'
  assert_contains "$temp_dir/output.txt" 'model_reasoning_effort="xhigh"'
  assert_contains "$temp_dir/output.txt" '--dangerously-bypass-approvals-and-sandbox'
  assert_contains "$temp_dir/prompts.txt" 'Model: '
  assert_not_contains "$temp_dir/prompts.txt" '思考等级: '
  assert_not_contains "$temp_dir/prompts.txt" 'Yolo: '

  rm -rf "$temp_dir"
}

run_test_reasoning_and_yolo_prompt() {
  local temp_dir
  temp_dir="$(mktemp -d)"

  make_fake_commands "$temp_dir/bin"
  : > "$temp_dir/prompts.txt"

  PATH="$temp_dir/bin:$PATH" \
    CX_TEST_OUTPUT="$temp_dir/output.txt" \
    CX_TEST_PROMPTS="$temp_dir/prompts.txt" \
    bash "$CX_BIN" gpt-5.4 hello

  assert_contains "$temp_dir/output.txt" '--model gpt-5.4'
  assert_contains "$temp_dir/output.txt" 'model_reasoning_effort="high"'
  assert_not_contains "$temp_dir/output.txt" '--dangerously-bypass-approvals-and-sandbox'
  assert_contains "$temp_dir/prompts.txt" '思考等级: '
  assert_contains "$temp_dir/prompts.txt" 'Yolo: '
  assert_not_contains "$temp_dir/prompts.txt" 'Model: '

  rm -rf "$temp_dir"
}

run_test_reasoning_and_yolo_prompt_without_passthrough() {
  local temp_dir
  temp_dir="$(mktemp -d)"

  make_fake_commands "$temp_dir/bin"
  : > "$temp_dir/prompts.txt"

  PATH="$temp_dir/bin:$PATH" \
    CX_TEST_OUTPUT="$temp_dir/output.txt" \
    CX_TEST_PROMPTS="$temp_dir/prompts.txt" \
    bash "$CX_BIN" gpt-5.4

  assert_contains "$temp_dir/output.txt" '--model gpt-5.4'
  assert_contains "$temp_dir/output.txt" 'model_reasoning_effort="high"'
  assert_not_contains "$temp_dir/output.txt" '--dangerously-bypass-approvals-and-sandbox'
  assert_contains "$temp_dir/prompts.txt" '思考等级: '
  assert_contains "$temp_dir/prompts.txt" 'Yolo: '
  assert_not_contains "$temp_dir/prompts.txt" 'Model: '

  rm -rf "$temp_dir"
}

run_test_fzf_ignores_preview_and_enables_cycle() {
  local temp_dir
  temp_dir="$(mktemp -d)"

  make_fake_commands "$temp_dir/bin"
  : > "$temp_dir/prompts.txt"

  PATH="$temp_dir/bin:$PATH" \
    FZF_DEFAULT_OPTS='--height 60% --layout=reverse --border --preview "bat --color=always --line-range :100 {}"' \
    CX_TEST_OUTPUT="$temp_dir/output.txt" \
    CX_TEST_PROMPTS="$temp_dir/prompts.txt" \
    CX_TEST_FZF_ARGS="$temp_dir/fzf_args.txt" \
    bash "$CX_BIN" yolo xhigh hello

  assert_line_present "$temp_dir/fzf_args.txt" '--cycle'
  assert_not_contains "$temp_dir/fzf_args.txt" '--preview'
  assert_not_contains "$temp_dir/fzf_args.txt" 'bat --color=always --line-range :100 {}'

  rm -rf "$temp_dir"
}

run_test_fzf_can_inherit_all_opts() {
  local temp_dir
  temp_dir="$(mktemp -d)"

  make_fake_commands "$temp_dir/bin"
  : > "$temp_dir/prompts.txt"

  PATH="$temp_dir/bin:$PATH" \
    FZF_DEFAULT_OPTS='--height 60% --layout=reverse --border --preview "bat --color=always --line-range :100 {}"' \
    CX_TEST_OUTPUT="$temp_dir/output.txt" \
    CX_TEST_PROMPTS="$temp_dir/prompts.txt" \
    CX_TEST_FZF_ARGS="$temp_dir/fzf_args.txt" \
    CX_FZF_INHERIT_ALL="1" \
    bash "$CX_BIN" yolo xhigh hello

  assert_line_present "$temp_dir/fzf_args.txt" '--preview'
  assert_line_present "$temp_dir/fzf_args.txt" 'bat --color=always --line-range :100 {}'

  rm -rf "$temp_dir"
}

run_test_install_script() {
  local temp_dir
  temp_dir="$(mktemp -d)"

  mkdir -p "$temp_dir/home/.local/bin" "$temp_dir/fake-bin"
  cat > "$temp_dir/fake-bin/codex" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$temp_dir/fake-bin/codex"

  HOME="$temp_dir/home" PATH="$temp_dir/fake-bin:$PATH" \
    bash "$ROOT_DIR/scripts/install.sh" >"$temp_dir/stdout.txt"

  [[ -x "$temp_dir/home/.local/bin/cx" ]] || fail "install should place cx in ~/.local/bin"
  assert_contains "$temp_dir/stdout.txt" "安装 cx 版本: $CX_VERSION (build "

  rm -rf "$temp_dir"
}

run_test_install_script_from_stdin() {
  local temp_dir
  temp_dir="$(mktemp -d)"

  mkdir -p "$temp_dir/home/.local/bin" "$temp_dir/fake-bin"
  cat > "$temp_dir/fake-bin/codex" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$temp_dir/fake-bin/codex"

  HOME="$temp_dir/home" PATH="$temp_dir/fake-bin:$PATH" \
    bash < "$ROOT_DIR/scripts/install.sh" >"$temp_dir/stdout.txt" 2>"$temp_dir/stderr.txt"

  [[ -x "$temp_dir/home/.local/bin/cx" ]] || fail "stdin install should place cx in ~/.local/bin"
  assert_not_contains "$temp_dir/stderr.txt" 'BASH_SOURCE[0]: unbound variable'
  assert_contains "$temp_dir/stdout.txt" "安装 cx 版本: $CX_VERSION (build "

  rm -rf "$temp_dir"
}

run_test_uninstall_script() {
  local temp_dir
  temp_dir="$(mktemp -d)"

  mkdir -p "$temp_dir/home/.local/bin"
  touch "$temp_dir/home/.local/bin/cx"

  HOME="$temp_dir/home" bash "$ROOT_DIR/scripts/uninstall.sh" >/dev/null

  [[ ! -e "$temp_dir/home/.local/bin/cx" ]] || fail "uninstall should remove cx"

  rm -rf "$temp_dir"
}

main() {
  run_test_direct_launch
  run_test_direct_launch_without_passthrough
  run_test_model_only_prompt
  run_test_reasoning_and_yolo_prompt
  run_test_reasoning_and_yolo_prompt_without_passthrough
  run_test_fzf_ignores_preview_and_enables_cycle
  run_test_fzf_can_inherit_all_opts
  run_test_install_script
  run_test_install_script_from_stdin
  run_test_uninstall_script
  echo "PASS"
}

main "$@"
