# Project Jump Plugin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Собрать Oh My Zsh plugin `project-jump`, совместимый по пользовательской модели с upstream `pj`, но с exact-path исключениями директорий, которые не должны считаться проектами.

**Architecture:** Плагин остается одним zsh-файлом с публичными командами `pj`, `pjo`, функцией completion `_pj` и двумя маленькими private-helper функциями для нормализации пути и проверки исключений. Поведение фиксируется pure-zsh regression harness, чтобы не добавлять зависимостей и не завязываться на полный runtime Oh My Zsh.

**Tech Stack:** zsh 5+, Oh My Zsh plugin conventions, pure zsh tests, markdown docs.

---

## Sources

- Upstream reference: [ohmyzsh/ohmyzsh plugins/pj](https://github.com/ohmyzsh/ohmyzsh/tree/master/plugins/pj)
- Локальная установленная копия, использованная для точного поведения: `/home/dev/.oh-my-zsh/plugins/pj/pj.plugin.zsh`
- Локальная README upstream `pj`: `/home/dev/.oh-my-zsh/plugins/pj/README.md`

## Requirements Summary

- Плагин должен предоставлять команду `pj <project-name>`, которая переходит в первую директорию `<basedir>/<project-name>` из массива `PROJECT_PATHS`.
- Плагин должен предоставлять `pjo <project-name>` и `pj open <project-name>`, которые открывают найденный проект в `$EDITOR`; если `$EDITOR` пустой, используется `vim`.
- Новая настройка: `PROJECT_JUMP_EXCLUDED_DIRS=(...)`.
- Исключения сравниваются как нормализованные exact paths, а не как basename. Это позволяет исключить `~/work/archive`, не исключая `~/src/archive`.
- Исключения применяются и к переходу `pj`, и к completion `_pj`.
- Если первая подходящая директория исключена, поиск продолжается по следующим директориям из `PROJECT_PATHS`.
- Если проект существует только в исключенных директориях, команда печатает `No such project '<name>'.`, не меняет `PWD` и возвращает status `1`.
- Пути с пробелами в `PROJECT_PATHS`, `PROJECT_JUMP_EXCLUDED_DIRS` и именах проектов должны работать.
- Плагин не добавляет runtime dependencies.

## File Structure

- Create: `project-jump.plugin.zsh`
  - Public API: `pj`, `pjo`, completion registration.
  - Private helpers: `_pj_expand_dir`, `_pj_is_excluded`, `_pj_resolve_project`.
  - Responsibility: runtime behavior only; no test fixtures and no docs prose.
- Create: `tests/project-jump.zsh`
  - Pure zsh regression harness.
  - Responsibility: verify jump resolution, exclusions, duplicate basename fallback, paths with spaces, editor open mode, and completion filtering.
- Modify: `README.md`
  - Responsibility: user-facing setup, configuration, commands, exclusion examples, and test command.
- Keep: `docs/superpowers/plans/2026-06-04-project-jump-plugin.md`
  - Responsibility: implementation handoff and verification checklist.

## RALPLAN-DR Summary

**Principles**

- Preserve the upstream `pj` mental model: `PROJECT_PATHS` is the only project root list and basename lookup remains first-match wins.
- Make exclusions conservative: exact path exclusion prevents accidental broad filtering.
- Keep the plugin dependency-free and shell-native.
- Test public behavior through zsh, not through implementation details.
- Keep changes small enough that a user can audit the plugin file directly.

**Decision Drivers**

- Predictability of exclusion behavior matters more than compact glob syntax.
- Compatibility with Oh My Zsh plugin loading matters more than standalone framework structure.
- The repo currently has only `README.md`, so the first implementation needs to establish tests and docs without adding project scaffolding noise.

**Viable Options**

- Option A: exact-path exclusion array `PROJECT_JUMP_EXCLUDED_DIRS`.
  - Pros: deterministic, supports duplicate basenames across roots, easy to test, easy to document.
  - Cons: users must write the full directory path for each excluded project.
  - Decision: chosen.
- Option B: basename exclusion array such as `PROJECT_JUMP_EXCLUDED_NAMES`.
  - Pros: shorter config for common names such as `tmp` or `archive`.
  - Cons: excludes the same basename across every `PROJECT_PATHS` entry, which is surprising when roots contain unrelated projects.
  - Decision: rejected.
- Option C: glob or pattern exclusion array.
  - Pros: powerful for advanced users.
  - Cons: harder escaping rules, ambiguous path-vs-name matching, larger test matrix.
  - Decision: rejected for the first version.

## Acceptance Criteria

- Running `zsh tests/project-jump.zsh` prints `ok - 8 assertions` and exits with status `0`.
- With `PROJECT_PATHS=("$root/work")`, `pj api` changes `PWD` to `$root/work/api`.
- With `PROJECT_JUMP_EXCLUDED_DIRS=("$root/work/not-a-project")`, `pj not-a-project` leaves `PWD` unchanged and exits with status `1`.
- With duplicate project basenames and the first candidate excluded, `pj shared` jumps to the non-excluded later candidate.
- With a project directory containing a space, `pj "with space"` jumps correctly.
- `pjo api` invokes `$EDITOR` with the resolved project directory and does not change `PWD`.
- `_pj` completion output excludes directories listed in `PROJECT_JUMP_EXCLUDED_DIRS`.
- `README.md` shows installation, `PROJECT_PATHS`, `PROJECT_JUMP_EXCLUDED_DIRS`, `pj`, `pjo`, and the test command.

## Task 1: Add Regression Test Harness

**Files:**

- Create: `tests/project-jump.zsh`

- [ ] **Step 1: Create the failing test file**

```zsh
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

main() {
  load_plugin

  test_jump_to_first_matching_project
  test_excluded_project_is_not_selected
  test_excluded_first_match_falls_back_to_later_root
  test_project_name_with_spaces
  test_open_mode_uses_editor_without_changing_directory
  test_completion_excludes_configured_directories

  if (( FAILURES > 0 )); then
    print -ru2 -- "${FAILURES} failure(s) in ${ASSERTIONS} assertion(s)"
    exit 1
  fi

  print -r -- "ok - ${ASSERTIONS} assertions"
}

main "$@"
```

- [ ] **Step 2: Run the tests and confirm they fail before implementation**

Run:

```bash
zsh tests/project-jump.zsh
```

Expected:

```text
FAIL: missing /home/dev/.oh-my-zsh/custom/plugins/project-jump/tests/../project-jump.plugin.zsh
```

The command exits with status `1`.

## Task 2: Implement `project-jump.plugin.zsh`

**Files:**

- Create: `project-jump.plugin.zsh`
- Test: `tests/project-jump.zsh`

- [ ] **Step 1: Create the plugin implementation**

```zsh
# project-jump
#
# Jump to project directories from PROJECT_PATHS, with exact-path exclusions.

typeset -ga PROJECT_PATHS
typeset -ga PROJECT_JUMP_EXCLUDED_DIRS

function _pj_expand_dir() {
  emulate -L zsh
  local dir="$1"

  if [[ "$dir" == "~" ]]; then
    dir="$HOME"
  elif [[ "$dir" == "~/"* ]]; then
    dir="$HOME/${dir#~/}"
  fi

  print -r -- "${dir:A}"
}

function _pj_is_excluded() {
  emulate -L zsh
  local candidate_abs excluded excluded_abs

  candidate_abs="$(_pj_expand_dir "$1")"

  for excluded in "${PROJECT_JUMP_EXCLUDED_DIRS[@]}"; do
    [[ -n "$excluded" ]] || continue
    excluded_abs="$(_pj_expand_dir "$excluded")"

    if [[ "$candidate_abs" == "$excluded_abs" ]]; then
      return 0
    fi
  done

  return 1
}

function _pj_resolve_project() {
  emulate -L zsh
  local project="$1"
  local basedir candidate

  for basedir in "${PROJECT_PATHS[@]}"; do
    [[ -d "$basedir" ]] || continue
    candidate="${basedir}/${project}"

    if [[ -d "$candidate" ]] && ! _pj_is_excluded "$candidate"; then
      print -r -- "$candidate"
      return 0
    fi
  done

  return 1
}

function pj() {
  emulate -L zsh
  local project="$1"
  local target open_project=0
  local -a editor_cmd

  if [[ "$project" == "open" ]]; then
    shift
    project="$*"
    open_project=1
    editor_cmd=(${=EDITOR})
    (( ${#editor_cmd[@]} > 0 )) || editor_cmd=(vim)
  else
    project="$*"
  fi

  if target="$(_pj_resolve_project "$project")"; then
    if (( open_project )); then
      "${editor_cmd[@]}" "$target"
    else
      cd "$target"
    fi
    return $?
  fi

  print -r -- "No such project '${project}'."
  return 1
}

function pjo() {
  pj open "$@"
}

function _pj() {
  emulate -L zsh
  local -a project_names
  local basedir project

  for basedir in "${PROJECT_PATHS[@]}"; do
    [[ -d "$basedir" ]] || continue

    for project in "${basedir}"/*(/N); do
      _pj_is_excluded "$project" && continue
      project_names+=("${project:t}")
    done
  done

  compadd -- "${(@u)project_names}"
}

(( $+functions[compdef] )) && compdef _pj pj pjo
```

- [ ] **Step 2: Run the regression tests**

Run:

```bash
zsh tests/project-jump.zsh
```

Expected:

```text
ok - 8 assertions
```

- [ ] **Step 3: Fix the acceptance count in this plan if the test count changes during implementation**

The planned test file above currently contains 8 assertions. If the worker adds assertions while preserving the same behavior, update the Acceptance Criteria line to the exact printed count before committing docs.

- [ ] **Step 4: Commit the test-backed implementation**

Run:

```bash
git add project-jump.plugin.zsh tests/project-jump.zsh
git commit -m "Make project jumps skip configured non-project directories" \
  -m "Constraint: Match upstream pj behavior while adding exact-path exclusions without dependencies.
Rejected: Basename exclusions | They would hide unrelated projects with the same directory name.
Confidence: high
Scope-risk: narrow
Directive: Keep PROJECT_JUMP_EXCLUDED_DIRS exact-path based unless a later requirement adds explicit pattern support.
Tested: zsh tests/project-jump.zsh
Not-tested: Interactive Oh My Zsh completion in a real terminal session"
```

## Task 3: Document Usage and Exclusion Semantics

**Files:**

- Modify: `README.md`

- [ ] **Step 1: Replace the README with user-facing documentation**

```markdown
# project-jump

`project-jump` is an Oh My Zsh plugin for jumping to project directories by
name. It follows the same core model as the built-in `pj` plugin: configure
one or more project roots in `PROJECT_PATHS`, then run `pj <name>` to jump to a
direct child directory.

This plugin adds `PROJECT_JUMP_EXCLUDED_DIRS`, an exact-path exclusion list for
directories that live under a project root but should not be treated as
projects.

## Install

Place this repository in your Oh My Zsh custom plugins directory:

```zsh
~/.oh-my-zsh/custom/plugins/project-jump
```

Enable it in `~/.zshrc`:

```zsh
plugins=(... project-jump)
```

Configure project roots before Oh My Zsh loads plugins:

```zsh
PROJECT_PATHS=(~/src ~/work ~/"dir with spaces")
```

## Excluding non-project directories

Use `PROJECT_JUMP_EXCLUDED_DIRS` for directories that are direct children of a
project root but should be ignored by `pj` and by completion:

```zsh
PROJECT_JUMP_EXCLUDED_DIRS=(
  ~/src/archive
  ~/src/tmp
  ~/"dir with spaces/not a project"
)
```

Exclusions are exact paths after normalization. Excluding `~/work/archive` does
not exclude `~/src/archive`.

## Commands

### `pj my-project`

Changes directory to `my-project` in the first matching root from
`PROJECT_PATHS`.

```zsh
PROJECT_PATHS=(~/code ~/work)
PROJECT_JUMP_EXCLUDED_DIRS=(~/code/archive)

pj blog      # cd ~/code/blog when it exists
pj archive   # skips ~/code/archive and uses ~/work/archive when it exists
```

If a project exists only in excluded directories, `pj` prints an error and
returns status `1`.

### `pjo my-project`

Opens the resolved project directory with `$EDITOR`. This is equivalent to:

```zsh
pj open my-project
```

If `$EDITOR` is empty, `vim` is used.

## Test

Run the regression harness from the plugin directory:

```zsh
zsh tests/project-jump.zsh
```
```

- [ ] **Step 2: Verify the README renders the exact config names**

Run:

```bash
rg -n "PROJECT_PATHS|PROJECT_JUMP_EXCLUDED_DIRS|pj open|pjo" README.md
```

Expected output includes all four terms:

```text
PROJECT_PATHS
PROJECT_JUMP_EXCLUDED_DIRS
pj open
pjo
```

- [ ] **Step 3: Commit documentation**

Run:

```bash
git add README.md
git commit -m "Explain exclusion-aware project jumping for users" \
  -m "Constraint: Documentation must show custom plugin setup and exact-path exclusion semantics.
Rejected: Pattern examples | Pattern matching is intentionally outside this version.
Confidence: high
Scope-risk: narrow
Directive: Keep README examples aligned with the tested variable names and command names.
Tested: rg -n \"PROJECT_PATHS|PROJECT_JUMP_EXCLUDED_DIRS|pj open|pjo\" README.md
Not-tested: Rendered markdown preview"
```

## Task 4: Run End-to-End Shell Smoke Checks

**Files:**

- Verify: `project-jump.plugin.zsh`
- Verify: `tests/project-jump.zsh`
- Verify: `README.md`

- [ ] **Step 1: Run the regression harness**

Run:

```bash
zsh tests/project-jump.zsh
```

Expected:

```text
ok - 8 assertions
```

- [ ] **Step 2: Run a no-Oh-My-Zsh source smoke check**

Run:

```bash
zsh -df -c '
  source ./project-jump.plugin.zsh
  root="$(mktemp -d "${TMPDIR:-/tmp}/project-jump-smoke.XXXXXX")" || exit 1
  trap "rm -rf -- \"$root\"" EXIT
  mkdir -p "$root/work/api" "$root/work/tmp"
  PROJECT_PATHS=("$root/work")
  PROJECT_JUMP_EXCLUDED_DIRS=("$root/work/tmp")
  pj api || exit 1
  [[ "$PWD" == "$root/work/api" ]] || exit 2
'
```

Expected: command exits with status `0` and prints no output.

- [ ] **Step 3: Run an exclusion smoke check**

Run:

```bash
zsh -df -c '
  source ./project-jump.plugin.zsh
  root="$(mktemp -d "${TMPDIR:-/tmp}/project-jump-smoke.XXXXXX")" || exit 1
  trap "rm -rf -- \"$root\"" EXIT
  mkdir -p "$root/work/tmp"
  PROJECT_PATHS=("$root/work")
  PROJECT_JUMP_EXCLUDED_DIRS=("$root/work/tmp")
  pj tmp >/dev/null
  [[ "$?" -eq 1 ]]
'
```

Expected: command exits with status `0`.

- [ ] **Step 4: Check the working tree**

Run:

```bash
git status --short
```

Expected after commits:

```text
```

If the worker is intentionally leaving the branch uncommitted, expected output contains only the changed files from this plan.

## Risks and Mitigations

- Risk: exact-path exclusion feels verbose for users with many common non-project names.
  - Mitigation: document exact-path behavior clearly and keep pattern support out of the first version.
- Risk: completion can show stale entries if a user changes arrays after compinit.
  - Mitigation: `_pj` reads `PROJECT_PATHS` and `PROJECT_JUMP_EXCLUDED_DIRS` at completion time, so normal zsh completion recalculation sees current values.
- Risk: `$EDITOR` may contain arguments such as `code -n`.
  - Mitigation: use zsh word splitting with `${=EDITOR}` and execute the resulting array.
- Risk: sourcing the plugin in a test shell without Oh My Zsh can fail if `compdef` is absent.
  - Mitigation: register completion only when `compdef` exists.

## ADR

**Decision:** Implement exact-path exclusions through `PROJECT_JUMP_EXCLUDED_DIRS` and filter both resolution and completion through `_pj_is_excluded`.

**Drivers:** predictable semantics, compatibility with duplicate basenames, no dependencies, easy shell tests.

**Alternatives considered:** basename exclusions, glob exclusions, maintaining an indexed project cache.

**Why chosen:** exact-path comparison is the smallest behavior that satisfies "this folder is not a project" without hiding unrelated folders elsewhere.

**Consequences:** users write full paths for exclusions; future pattern support can be added as a separate opt-in variable without breaking the exact-path contract.

**Follow-ups:** after the first implementation, collect real user config examples before adding basename or glob exclusion support.

## Verification Steps

Run these before claiming implementation complete:

```bash
zsh tests/project-jump.zsh
rg -n "PROJECT_PATHS|PROJECT_JUMP_EXCLUDED_DIRS|pj open|pjo" README.md
zsh -df -c '
  source ./project-jump.plugin.zsh
  root="$(mktemp -d "${TMPDIR:-/tmp}/project-jump-smoke.XXXXXX")" || exit 1
  trap "rm -rf -- \"$root\"" EXIT
  mkdir -p "$root/work/api" "$root/work/tmp"
  PROJECT_PATHS=("$root/work")
  PROJECT_JUMP_EXCLUDED_DIRS=("$root/work/tmp")
  pj api || exit 1
  [[ "$PWD" == "$root/work/api" ]] || exit 2
'
git status --short
```

Expected evidence:

- `zsh tests/project-jump.zsh` prints `ok - 8 assertions`.
- README grep output includes `PROJECT_PATHS`, `PROJECT_JUMP_EXCLUDED_DIRS`, `pj open`, and `pjo`.
- The smoke check exits with status `0`.
- `git status --short` shows either a clean tree after commits or only intentional uncommitted files.

## Available-Agent-Types Roster

- `explore`: quick read-only check of upstream `pj` and current repo files.
- `executor`: implement `project-jump.plugin.zsh` and README changes.
- `test-engineer`: validate and adjust the zsh regression harness.
- `verifier`: run final shell checks and inspect the working tree.
- `code-reviewer`: review the final diff for shell quoting, zsh compatibility, and behavior drift from upstream `pj`.

## Follow-up Staffing Guidance

- Solo execution is enough for this plan because the implementation surface is one plugin file, one test file, and one README.
- If using `$ultragoal`, use it as the durable ledger owner with this plan path: `docs/superpowers/plans/2026-06-04-project-jump-plugin.md`.
- If using `$team`, use two lanes:
  - `executor` lane: plugin implementation and README.
  - `test-engineer` lane: regression harness and shell smoke checks.
- Add `code-reviewer` after implementation if the plugin will be shared publicly.

## Launch Hints

From an attached OMX runtime surface:

```text
$ultragoal docs/superpowers/plans/2026-06-04-project-jump-plugin.md
```

For a parallel delivery path:

```text
$team docs/superpowers/plans/2026-06-04-project-jump-plugin.md
```

Team verification path:

- Team proves all acceptance criteria through `zsh tests/project-jump.zsh` and the smoke commands.
- Ultragoal records the final evidence and the diff summary before marking the goal complete.
- `$ralph` is only a fallback when a single persistent owner is explicitly preferred over Team + Ultragoal.

## Self-Review

- Spec coverage: upstream-like `pj`, `pjo`, `PROJECT_PATHS`, exact-path folder exclusions, completion filtering, tests, and README are each mapped to tasks.
- Placeholder scan: no unresolved placeholders are intentionally left in the plan.
- Type consistency: `PROJECT_JUMP_EXCLUDED_DIRS`, `_pj_is_excluded`, `_pj_resolve_project`, `pj`, `pjo`, and `_pj` use the same names across tests, implementation, docs, and verification.
