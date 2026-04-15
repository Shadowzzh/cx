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

assert_count() {
  local file="$1"
  local expected_text="$2"
  local expected_count="$3"
  local actual_count

  actual_count="$(grep -Fxc -- "$expected_text" "$file" || true)"

  if [[ "$actual_count" != "$expected_count" ]]; then
    fail "expected '$expected_text' to appear $expected_count times in $file, got $actual_count"
  fi
}

assert_line_present() {
  local file="$1"
  local expected="$2"

  if ! grep -Fx -- "$expected" "$file" >/dev/null 2>&1; then
    fail "expected line '$expected' in $file"
  fi
}

assert_file_empty() {
  local file="$1"

  if [[ -s "$file" ]]; then
    fail "expected $file to be empty"
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
}

make_fake_fzf() {
  local dir="$1"

  cat > "$dir/fzf" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${CX_TEST_FZF_ARGS:-}" ]]; then
  printf '%s\n' "$@" > "$CX_TEST_FZF_ARGS"
fi

if [[ -n "${CX_TEST_FZF_ENV:-}" ]]; then
  {
    printf 'FZF_DEFAULT_OPTS=%s\n' "${FZF_DEFAULT_OPTS-<unset>}"
    printf 'FZF_DEFAULT_OPTS_FILE=%s\n' "${FZF_DEFAULT_OPTS_FILE-<unset>}"
  } > "$CX_TEST_FZF_ENV"
fi

prompt=""
for arg in "$@"; do
  case "$arg" in
    --prompt=*)
      prompt="${arg#--prompt=}"
      ;;
  esac
done

if [[ -n "${CX_TEST_PROMPTS:-}" ]]; then
  printf '%s\n' "$prompt" >> "$CX_TEST_PROMPTS"
fi

if [[ -n "${CX_TEST_FZF_OPTIONS:-}" ]]; then
  while IFS= read -r line; do
    printf '%s\n' "$line" >> "$CX_TEST_FZF_OPTIONS"
  done
else
  while IFS= read -r _line; do
    :
  done
fi

counter_file="${CX_TEST_FZF_COUNTER:?}"
call_index="1"

if [[ -f "$counter_file" ]]; then
  call_index="$(( $(cat "$counter_file") + 1 ))"
fi

printf '%s\n' "$call_index" > "$counter_file"

response_file="${CX_TEST_FZF_STATE_DIR:?}/${call_index}.out"
status_file="${CX_TEST_FZF_STATE_DIR:?}/${call_index}.status"
exit_code="0"

if [[ -f "$status_file" ]]; then
  exit_code="$(cat "$status_file")"
fi

if [[ -f "$response_file" ]]; then
  cat "$response_file"
fi

exit "$exit_code"
EOF
  chmod +x "$dir/fzf"
}

run_cx() {
  local temp_dir="$1"
  local input="$2"
  shift 2
  local test_path="$temp_dir/bin:/usr/bin:/bin"

  if [[ -n "$input" ]]; then
    PATH="$test_path" \
      CX_TEST_OUTPUT="$temp_dir/output.txt" \
      bash "$CX_BIN" "$@" >"$temp_dir/transcript.txt" 2>&1 <<<"$input"
    return 0
  fi

  PATH="$test_path" \
    CX_TEST_OUTPUT="$temp_dir/output.txt" \
    bash "$CX_BIN" "$@" >"$temp_dir/transcript.txt" 2>&1
}

run_test_direct_launch() {
  local temp_dir
  temp_dir="$(mktemp -d)"

  make_fake_commands "$temp_dir/bin"

  run_cx "$temp_dir" "" yolo xhigh gpt-5.4 hello

  assert_contains "$temp_dir/output.txt" '--model gpt-5.4'
  assert_contains "$temp_dir/output.txt" 'model_reasoning_effort="xhigh"'
  assert_contains "$temp_dir/output.txt" '--dangerously-bypass-approvals-and-sandbox'
  assert_contains "$temp_dir/output.txt" 'hello'
  assert_file_empty "$temp_dir/transcript.txt"

  rm -rf "$temp_dir"
}

run_test_direct_launch_without_passthrough() {
  local temp_dir
  temp_dir="$(mktemp -d)"

  make_fake_commands "$temp_dir/bin"

  run_cx "$temp_dir" "" no-yolo low gpt-5.4

  assert_contains "$temp_dir/output.txt" '--model gpt-5.4'
  assert_contains "$temp_dir/output.txt" 'model_reasoning_effort="low"'
  assert_not_contains "$temp_dir/output.txt" '--dangerously-bypass-approvals-and-sandbox'
  assert_file_empty "$temp_dir/transcript.txt"

  rm -rf "$temp_dir"
}

run_test_model_only_prompt() {
  local temp_dir
  temp_dir="$(mktemp -d)"

  make_fake_commands "$temp_dir/bin"

  run_cx "$temp_dir" $'2' yolo xhigh hello

  assert_contains "$temp_dir/output.txt" '--model gpt-5.3-codex'
  assert_contains "$temp_dir/output.txt" 'model_reasoning_effort="xhigh"'
  assert_contains "$temp_dir/output.txt" '--dangerously-bypass-approvals-and-sandbox'
  assert_contains "$temp_dir/transcript.txt" 'Model'
  assert_not_contains "$temp_dir/transcript.txt" '思考等级'
  assert_not_contains "$temp_dir/transcript.txt" 'Yolo'

  rm -rf "$temp_dir"
}

run_test_reasoning_and_yolo_prompt() {
  local temp_dir
  temp_dir="$(mktemp -d)"

  make_fake_commands "$temp_dir/bin"

  run_cx "$temp_dir" $'3\n2' gpt-5.4 hello

  assert_contains "$temp_dir/output.txt" '--model gpt-5.4'
  assert_contains "$temp_dir/output.txt" 'model_reasoning_effort="high"'
  assert_not_contains "$temp_dir/output.txt" '--dangerously-bypass-approvals-and-sandbox'
  assert_contains "$temp_dir/transcript.txt" '思考等级'
  assert_contains "$temp_dir/transcript.txt" 'Yolo'
  assert_not_contains "$temp_dir/transcript.txt" 'Model'

  rm -rf "$temp_dir"
}

run_test_reasoning_and_yolo_prompt_without_passthrough() {
  local temp_dir
  temp_dir="$(mktemp -d)"

  make_fake_commands "$temp_dir/bin"

  run_cx "$temp_dir" $'3\n2' gpt-5.4

  assert_contains "$temp_dir/output.txt" '--model gpt-5.4'
  assert_contains "$temp_dir/output.txt" 'model_reasoning_effort="high"'
  assert_not_contains "$temp_dir/output.txt" '--dangerously-bypass-approvals-and-sandbox'
  assert_contains "$temp_dir/transcript.txt" '思考等级'
  assert_contains "$temp_dir/transcript.txt" 'Yolo'
  assert_not_contains "$temp_dir/transcript.txt" 'Model'

  rm -rf "$temp_dir"
}

run_test_back_with_shortcut() {
  local temp_dir
  temp_dir="$(mktemp -d)"

  make_fake_commands "$temp_dir/bin"

  run_cx "$temp_dir" $'2\n2\nb\n1\n1'

  assert_contains "$temp_dir/output.txt" '--model gpt-5.4'
  assert_contains "$temp_dir/output.txt" 'model_reasoning_effort="low"'
  assert_contains "$temp_dir/output.txt" '--dangerously-bypass-approvals-and-sandbox'

  rm -rf "$temp_dir"
}

run_test_back_with_menu_item() {
  local temp_dir
  temp_dir="$(mktemp -d)"

  make_fake_commands "$temp_dir/bin"

  run_cx "$temp_dir" $'4\n2\n8\n1\n1'

  assert_contains "$temp_dir/output.txt" '--model gpt-5.4'
  assert_contains "$temp_dir/output.txt" 'model_reasoning_effort="xhigh"'
  assert_contains "$temp_dir/output.txt" '--dangerously-bypass-approvals-and-sandbox'
  assert_contains "$temp_dir/transcript.txt" '返回上一步'

  rm -rf "$temp_dir"
}

run_test_custom_model_back_returns_to_model_menu() {
  local temp_dir
  temp_dir="$(mktemp -d)"

  make_fake_commands "$temp_dir/bin"

  run_cx "$temp_dir" $'1\n1\n7\nb\n2'

  assert_contains "$temp_dir/output.txt" '--model gpt-5.3-codex'
  assert_not_contains "$temp_dir/output.txt" '--model b'
  assert_contains "$temp_dir/transcript.txt" '请输入自定义 model'

  rm -rf "$temp_dir"
}

run_test_back_skips_cli_fixed_values() {
  local temp_dir
  temp_dir="$(mktemp -d)"

  make_fake_commands "$temp_dir/bin"

  run_cx "$temp_dir" $'3\nb\n4\n1' yolo

  assert_contains "$temp_dir/output.txt" '--model gpt-5.4'
  assert_contains "$temp_dir/output.txt" 'model_reasoning_effort="xhigh"'
  assert_contains "$temp_dir/output.txt" '--dangerously-bypass-approvals-and-sandbox'
  assert_not_contains "$temp_dir/transcript.txt" 'Yolo'

  rm -rf "$temp_dir"
}

run_test_reasoning_menu_deduplicates_default_option() {
  local temp_dir
  temp_dir="$(mktemp -d)"

  make_fake_commands "$temp_dir/bin"

  PATH="$temp_dir/bin:/usr/bin:/bin" \
    CX_TEST_OUTPUT="$temp_dir/output.txt" \
    bash "$CX_BIN" gpt-5.4 >"$temp_dir/transcript.txt" 2>&1 <<'EOF'
1
1
EOF

  assert_count "$temp_dir/transcript.txt" '1) medium' 1
  assert_count "$temp_dir/transcript.txt" '2) low' 1
  assert_count "$temp_dir/transcript.txt" '3) high' 1
  assert_count "$temp_dir/transcript.txt" '4) xhigh' 1
  assert_not_contains "$temp_dir/transcript.txt" '3) medium'

  rm -rf "$temp_dir"
}

run_test_yolo_menu_deduplicates_default_option() {
  local temp_dir
  temp_dir="$(mktemp -d)"

  make_fake_commands "$temp_dir/bin"

  PATH="$temp_dir/bin:/usr/bin:/bin" \
    CX_TEST_OUTPUT="$temp_dir/output.txt" \
    CX_DEFAULT_YOLO=no \
    bash "$CX_BIN" medium gpt-5.4 >"$temp_dir/transcript.txt" 2>&1 <<'EOF'
1
EOF

  assert_count "$temp_dir/transcript.txt" '1) no' 1
  assert_count "$temp_dir/transcript.txt" '2) yes' 1
  assert_not_contains "$temp_dir/transcript.txt" '2) no'

  rm -rf "$temp_dir"
}

run_test_fzf_backend_selects_values() {
  local temp_dir
  temp_dir="$(mktemp -d)"

  make_fake_commands "$temp_dir/bin"
  make_fake_fzf "$temp_dir/bin"
  mkdir -p "$temp_dir/fzf-state"
  : > "$temp_dir/prompts.txt"

  cat > "$temp_dir/fzf-state/1.out" <<'EOF'
high
EOF
  cat > "$temp_dir/fzf-state/2.out" <<'EOF'

no
EOF

  env \
    CX_TEST_PROMPTS="$temp_dir/prompts.txt" \
    CX_TEST_FZF_COUNTER="$temp_dir/fzf-counter.txt" \
    CX_TEST_FZF_STATE_DIR="$temp_dir/fzf-state" \
    bash -c '
      PATH="$1/bin:/usr/bin:/bin" \
        CX_TEST_OUTPUT="$1/output.txt" \
        CX_TEST_PROMPTS="$2" \
        CX_TEST_FZF_COUNTER="$3" \
        CX_TEST_FZF_STATE_DIR="$4" \
        bash "$5" gpt-5.4 hello >"$1/transcript.txt" 2>&1
    ' _ "$temp_dir" "$temp_dir/prompts.txt" "$temp_dir/fzf-counter.txt" "$temp_dir/fzf-state" "$CX_BIN"

  assert_contains "$temp_dir/output.txt" '--model gpt-5.4'
  assert_contains "$temp_dir/output.txt" 'model_reasoning_effort="high"'
  assert_not_contains "$temp_dir/output.txt" '--dangerously-bypass-approvals-and-sandbox'
  assert_line_present "$temp_dir/prompts.txt" '思考等级: '
  assert_line_present "$temp_dir/prompts.txt" 'Yolo: '

  rm -rf "$temp_dir"
}

run_test_fzf_backend_supports_ctrl_b_back() {
  local temp_dir
  temp_dir="$(mktemp -d)"

  make_fake_commands "$temp_dir/bin"
  make_fake_fzf "$temp_dir/bin"
  mkdir -p "$temp_dir/fzf-state"
  : > "$temp_dir/prompts.txt"

  cat > "$temp_dir/fzf-state/1.out" <<'EOF'
xhigh
EOF
  cat > "$temp_dir/fzf-state/2.out" <<'EOF'
ctrl-b
EOF
  cat > "$temp_dir/fzf-state/3.out" <<'EOF'
low
EOF
  cat > "$temp_dir/fzf-state/4.out" <<'EOF'

yes
EOF

  env \
    CX_TEST_PROMPTS="$temp_dir/prompts.txt" \
    CX_TEST_FZF_COUNTER="$temp_dir/fzf-counter.txt" \
    CX_TEST_FZF_STATE_DIR="$temp_dir/fzf-state" \
    bash -c '
      PATH="$1/bin:/usr/bin:/bin" \
        CX_TEST_OUTPUT="$1/output.txt" \
        CX_TEST_PROMPTS="$2" \
        CX_TEST_FZF_COUNTER="$3" \
        CX_TEST_FZF_STATE_DIR="$4" \
        bash "$5" gpt-5.4 >"$1/transcript.txt" 2>&1
    ' _ "$temp_dir" "$temp_dir/prompts.txt" "$temp_dir/fzf-counter.txt" "$temp_dir/fzf-state" "$CX_BIN"

  assert_contains "$temp_dir/output.txt" '--model gpt-5.4'
  assert_contains "$temp_dir/output.txt" 'model_reasoning_effort="low"'
  assert_contains "$temp_dir/output.txt" '--dangerously-bypass-approvals-and-sandbox'
  assert_count "$temp_dir/prompts.txt" '思考等级: ' 2
  assert_count "$temp_dir/prompts.txt" 'Yolo: ' 2

  rm -rf "$temp_dir"
}

run_test_fzf_ignores_preview_and_enables_cycle() {
  local temp_dir
  temp_dir="$(mktemp -d)"

  make_fake_commands "$temp_dir/bin"
  make_fake_fzf "$temp_dir/bin"
  mkdir -p "$temp_dir/fzf-state"
  : > "$temp_dir/prompts.txt"
  : > "$temp_dir/fzfrc"

  cat > "$temp_dir/fzf-state/1.out" <<'EOF'
gpt-5.2-codex
EOF

  env \
    FZF_DEFAULT_OPTS='--height 60% --layout=reverse --border --preview "bat --color=always --line-range :100 {}"' \
    FZF_DEFAULT_OPTS_FILE="$temp_dir/fzfrc" \
    CX_TEST_PROMPTS="$temp_dir/prompts.txt" \
    CX_TEST_FZF_ARGS="$temp_dir/fzf_args.txt" \
    CX_TEST_FZF_ENV="$temp_dir/fzf_env.txt" \
    CX_TEST_FZF_COUNTER="$temp_dir/fzf-counter.txt" \
    CX_TEST_FZF_STATE_DIR="$temp_dir/fzf-state" \
    bash -c '
      PATH="$1/bin:/usr/bin:/bin" \
        CX_TEST_OUTPUT="$1/output.txt" \
        FZF_DEFAULT_OPTS="$2" \
        FZF_DEFAULT_OPTS_FILE="$3" \
        CX_TEST_PROMPTS="$4" \
        CX_TEST_FZF_ARGS="$5" \
        CX_TEST_FZF_ENV="$6" \
        CX_TEST_FZF_COUNTER="$7" \
        CX_TEST_FZF_STATE_DIR="$8" \
        bash "$9" yolo xhigh hello >"$1/transcript.txt" 2>&1
    ' _ "$temp_dir" '--height 60% --layout=reverse --border --preview "bat --color=always --line-range :100 {}"' "$temp_dir/fzfrc" "$temp_dir/prompts.txt" "$temp_dir/fzf_args.txt" "$temp_dir/fzf_env.txt" "$temp_dir/fzf-counter.txt" "$temp_dir/fzf-state" "$CX_BIN"

  assert_line_present "$temp_dir/fzf_args.txt" '--cycle'
  assert_not_contains "$temp_dir/fzf_args.txt" '--preview'
  assert_not_contains "$temp_dir/fzf_args.txt" 'bat --color=always --line-range :100 {}'
  assert_line_present "$temp_dir/fzf_env.txt" 'FZF_DEFAULT_OPTS='
  assert_line_present "$temp_dir/fzf_env.txt" 'FZF_DEFAULT_OPTS_FILE='

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

  HOME="$temp_dir/home" PATH="$temp_dir/fake-bin:/usr/bin:/bin" \
    bash "$ROOT_DIR/scripts/install.sh" >"$temp_dir/stdout.txt"

  [[ -x "$temp_dir/home/.local/bin/cx" ]] || fail "install should place cx in ~/.local/bin"
  assert_contains "$temp_dir/stdout.txt" "安装 cx 版本: $CX_VERSION (build "
  assert_not_contains "$temp_dir/stdout.txt" 'fzf'

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

  HOME="$temp_dir/home" PATH="$temp_dir/fake-bin:/usr/bin:/bin" \
    bash < "$ROOT_DIR/scripts/install.sh" >"$temp_dir/stdout.txt" 2>"$temp_dir/stderr.txt"

  [[ -x "$temp_dir/home/.local/bin/cx" ]] || fail "stdin install should place cx in ~/.local/bin"
  assert_not_contains "$temp_dir/stderr.txt" 'BASH_SOURCE[0]: unbound variable'
  assert_contains "$temp_dir/stdout.txt" "安装 cx 版本: $CX_VERSION (build "
  assert_not_contains "$temp_dir/stdout.txt" 'fzf'

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
  run_test_back_with_shortcut
  run_test_back_with_menu_item
  run_test_custom_model_back_returns_to_model_menu
  run_test_back_skips_cli_fixed_values
  run_test_reasoning_menu_deduplicates_default_option
  run_test_yolo_menu_deduplicates_default_option
  run_test_fzf_backend_selects_values
  run_test_fzf_backend_supports_ctrl_b_back
  run_test_fzf_ignores_preview_and_enables_cycle
  run_test_install_script
  run_test_install_script_from_stdin
  run_test_uninstall_script
  echo "PASS"
}

main "$@"
