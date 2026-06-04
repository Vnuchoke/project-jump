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
