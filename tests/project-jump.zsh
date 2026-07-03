#!/usr/bin/env zsh
emulate -R zsh

typeset -i ASSERTIONS=0
typeset -i FAILURES=0
typeset -a TEMP_DIRS=()
typeset FIXTURE_ROOT=""

PLUGIN_FILE="${0:A:h}/../project-jump.plugin.zsh"

fail() {
  print -ru2 -- "FAIL: $*"
  FAILURES+=1
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="$3"

  ASSERTIONS+=1
  if [[ "$actual" != "$expected" ]]; then
    fail "${message}: expected [${expected}], got [${actual}]"
  fi
}

assert_status() {
  local expected="$1"
  local actual="$2"
  local message="$3"

  ASSERTIONS+=1
  if [[ "$actual" -ne "$expected" ]]; then
    fail "${message}: expected status ${expected}, got ${actual}"
  fi
}

make_fixture() {
  local root

  root="$(mktemp -d "${TMPDIR:-/tmp}/project-jump-test.XXXXXX")" || exit 1
  FIXTURE_ROOT="$root"
  TEMP_DIRS+=("$root")

  mkdir -p \
    "$root/work/api" \
    "$root/work/not-a-project" \
    "$root/work/scratch" \
    "$root/work/shared" \
    "$root/other/shared" \
    "$root/worktrees/TW-4650/telemed-api-TW-4650" \
    "$root/worktrees/TW-release-26-4/pipeline-admin-api-TW-release-26-4" \
    "$root/worktrees/archive/ignored-worktree" \
    "$root/space base/with space"

}

cleanup() {
  local dir

  for dir in "${TEMP_DIRS[@]}"; do
    rm -rf -- "$dir"
  done
}
trap cleanup EXIT

load_plugin() {
  if [[ ! -f "$PLUGIN_FILE" ]]; then
    print -ru2 -- "FAIL: missing ${PLUGIN_FILE}"
    exit 1
  fi

  source "$PLUGIN_FILE" || {
    print -ru2 -- "FAIL: cannot source ${PLUGIN_FILE}"
    exit 1
  }
}

test_jump_to_first_matching_project() {
  local root output

  make_fixture
  root="$FIXTURE_ROOT"
  output="$(
    PROJECT_PATHS=("$root/work" "$root/other")
    PROJECT_JUMP_EXCLUDED_DIRS=()
    pj api
    print -r -- "$?|$PWD"
  )"

  assert_eq "0|$root/work/api" "$output" "pj jumps to a direct project child"
}

test_excluded_project_is_not_selected() {
  local root output start

  make_fixture
  root="$FIXTURE_ROOT"
  start="$PWD"
  output="$(
    PROJECT_PATHS=("$root/work")
    PROJECT_JUMP_EXCLUDED_DIRS=("$root/work/not-a-project")
    pj not-a-project >/dev/null
    print -r -- "$?|$PWD"
  )"

  assert_eq "1|$start" "$output" "pj ignores an exact excluded project directory"
}

test_excluded_first_match_falls_back_to_later_root() {
  local root output

  make_fixture
  root="$FIXTURE_ROOT"
  output="$(
    PROJECT_PATHS=("$root/work" "$root/other")
    PROJECT_JUMP_EXCLUDED_DIRS=("$root/work/shared")
    pj shared
    print -r -- "$?|$PWD"
  )"

  assert_eq "0|$root/other/shared" "$output" "pj falls back when the first matching basename is excluded"
}

test_project_name_with_spaces() {
  local root output

  make_fixture
  root="$FIXTURE_ROOT"
  output="$(
    PROJECT_PATHS=("$root/space base")
    PROJECT_JUMP_EXCLUDED_DIRS=()
    pj "with space"
    print -r -- "$?|$PWD"
  )"

  assert_eq "0|$root/space base/with space" "$output" "pj supports project names and base paths with spaces"
}

test_open_mode_uses_editor_without_changing_directory() {
  local root log start command_status editor_target

  make_fixture
  root="$FIXTURE_ROOT"
  log="$root/editor.log"
  start="$PWD"

  project_jump_test_editor() {
    print -r -- "$1" >> "$log"
  }

  PROJECT_PATHS=("$root/work")
  PROJECT_JUMP_EXCLUDED_DIRS=()
  EDITOR=project_jump_test_editor

  pjo api
  command_status=$?
  editor_target="$(sed -n '1p' "$log")"

  assert_status 0 "$command_status" "pjo returns the editor command status"
  assert_eq "$start" "$PWD" "pjo does not cd in the caller shell"
  assert_eq "$root/work/api" "$editor_target" "pjo passes the project path to EDITOR"
}

test_completion_excludes_configured_directories() {
  local root output

  make_fixture
  root="$FIXTURE_ROOT"
  PROJECT_PATHS=("$root/work")
  PROJECT_JUMP_EXCLUDED_DIRS=("$root/work/scratch")

  compadd() {
    [[ "$1" == "--" ]] && shift
    print -rl -- "$@"
  }

  output="$(_pj | sort)"

  assert_eq $'api\nnot-a-project\nshared' "$output" "completion hides excluded project directories"
}

test_nested_worktree_root_resolves_projects() {
  local root output

  make_fixture
  root="$FIXTURE_ROOT"
  output="$({
    PROJECT_PATHS=("$root/worktrees")
    PROJECT_JUMP_EXCLUDED_DIRS=()
    pj telemed-api-TW-4650
    print -r -- "$?|$PWD"
  })"

  assert_eq "0|$root/worktrees/TW-4650/telemed-api-TW-4650" "$output" "pj resolves nested worktrees from a worktrees root"
}

test_nested_worktree_completion_uses_shared_backend() {
  local root output

  make_fixture
  root="$FIXTURE_ROOT"
  PROJECT_PATHS=("$root/worktrees")
  PROJECT_JUMP_EXCLUDED_DIRS=("$root/worktrees/archive/ignored-worktree")

  compadd() {
    [[ "$1" == "--" ]] && shift
    print -rl -- "$@"
  }

  output="$(_pj | sort)"

  assert_eq $'pipeline-admin-api-TW-release-26-4\ntelemed-api-TW-4650' "$output" "completion includes nested worktrees and excludes nested ignored paths"
}

main() {
  load_plugin

  test_jump_to_first_matching_project
  test_excluded_project_is_not_selected
  test_excluded_first_match_falls_back_to_later_root
  test_project_name_with_spaces
  test_open_mode_uses_editor_without_changing_directory
  test_completion_excludes_configured_directories
  test_nested_worktree_root_resolves_projects
  test_nested_worktree_completion_uses_shared_backend

  if (( FAILURES > 0 )); then
    print -ru2 -- "${FAILURES} failure(s) in ${ASSERTIONS} assertion(s)"
    exit 1
  fi

  print -r -- "ok - ${ASSERTIONS} assertions"
}

main "$@"
