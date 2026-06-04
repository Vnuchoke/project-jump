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

if (( $+functions[compdef] )); then
  compdef _pj pj pjo
fi
