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

function _pj_is_worktrees_root() {
  emulate -L zsh
  local basedir_abs

  basedir_abs="$(_pj_expand_dir "$1")"
  [[ "${basedir_abs:t}" == "worktrees" ]]
}

function _pj_emit_candidate() {
  emulate -L zsh
  local project_name="$1"
  local project_path="$2"
  local project_abs

  project_abs="$(_pj_expand_dir "$project_path")"
  _pj_is_excluded "$project_abs" && return 0

  print -r -- "${project_name}|${project_abs}"
}

function _pj_collect_root_candidates() {
  emulate -L zsh
  local basedir="$1"
  local basedir_abs tag_dir project_dir

  basedir_abs="$(_pj_expand_dir "$basedir")"
  [[ -d "$basedir_abs" ]] || return 0

  if _pj_is_worktrees_root "$basedir_abs"; then
    for tag_dir in "${basedir_abs}"/*(/N); do
      for project_dir in "${tag_dir}"/*(/N); do
        _pj_emit_candidate "${project_dir:t}" "$project_dir"
      done
    done
    return 0
  fi

  for project_dir in "${basedir_abs}"/*(/N); do
    _pj_emit_candidate "${project_dir:t}" "$project_dir"
  done
}

function _pj_collect_candidates() {
  emulate -L zsh
  local basedir

  for basedir in "${PROJECT_PATHS[@]}"; do
    _pj_collect_root_candidates "$basedir"
  done
}

function _pj_resolve_project() {
  emulate -L zsh
  local project="$1"
  local candidate_name candidate_path

  while IFS='|' read -r candidate_name candidate_path; do
    if [[ "$candidate_name" == "$project" ]]; then
      print -r -- "$candidate_path"
      return 0
    fi
  done < <(_pj_collect_candidates)

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
  local candidate_name candidate_path
  local -A seen_names

  while IFS='|' read -r candidate_name candidate_path; do
    [[ -n "$candidate_name" ]] || continue
    [[ -n "${seen_names[$candidate_name]:-}" ]] && continue
    seen_names[$candidate_name]=1
    project_names+=("$candidate_name")
  done < <(_pj_collect_candidates)

  compadd -- "${project_names[@]}"
}

if (( $+functions[compdef] )); then
  compdef _pj pj pjo
fi
