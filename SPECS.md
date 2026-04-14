# zsh-complete — Specifications

A bash toolkit that aggregates zsh completions from heterogeneous sources, ranks
them by source priority, and exposes a single fpath directory of plain static
completion files (`~/.zinit/completions` by default) for fast shell startup.

## Conventions

- All scripts are bash. Use zsh only for syntax-checking emitted completions.
- All directories are created with `mkdir -p`.
- All scripts source `scripts/lib/utils.sh` for logging, config, and helpers.
- Detailed log goes to `files.history`. Terminal output is colored and aligned.
- Tests live in `tests/`, run via [bats-core](https://github.com/bats-core/bats-core).

## Source Taxonomy

Each entry in `config.sources[]` declares an explicit `type`:

| type        | required fields              | optional fields              | behavior                                                        |
|-------------|------------------------------|------------------------------|-----------------------------------------------------------------|
| `remote`    | `name`, `url`                | `paths`, `when`              | `git clone --depth 1`; copy matching globs into source dir      |
| `snippet`   | `name`, `url`                | `rename`, `when`             | `curl` a single file; auto-rewrite github `blob/` → `raw.*`     |
| `builtin`   | `name`, `paths`              | `when`                       | Copy `_*` files from local directories                          |
| `generated` | `name`, `commands`           | `when`                       | Run command, capture stdout as `_<key>` completion              |
| `generic`   | `name`, `commands`           | `when`                       | Parse `--help`/man via `generic.sh`; emit `_arguments` skeleton |

Common fields:

- `name` — unique source id, also the on-disk directory name
- `description` — human-readable
- `when` — only fetch if the named command exists on PATH
- `rename` — for `snippet`, override the destination basename

## Config Layout

```jsonc
{
  "files": {
    "history":   "...history.log",
    "commands":  "...commands.json",
    "available": "...comps-available.json",
    "existing":  "...comps-existing.json",
    "search":    "...comps-search.json",
    "generic":   "...comps-generic.json",
    "output":    "...comps-output.json"
  },
  "dirs": {
    "temp":      "/tmp/zsh-complete",
    "src":       ".../src",                    // tool-managed: src/<type>/<name>/_*
    "available": ".../available",              // priority-suffixed symlinks: _ls.0, _ls.3
    "active":    "$HOME/.zinit/completions"    // single _ls per command (fpath target)
  },
  "sources": [ /* see taxonomy */ ],
  "commands": { "<cmd>": "<source-name>" }      // optional per-command source override
}
```

## Scripts

All under `scripts/`. Each is invokable directly or via the dispatcher.

### `zsh-complete` (dispatcher)

```
zsh-complete fetch   [--source NAME] [--force]
zsh-complete compile [--limit N]
zsh-complete list    [--to-install|--to-uninstall|--missing|--existing|--all|--summary] [--pick] [--json]
zsh-complete sync    [--dry-run|--apply] [--prune]
zsh-complete generic <cmd>
zsh-complete check   [--all|<cmd>]
zsh-complete search  <query>          # deferred stub
zsh-complete doctor                   # deps + config sanity
```

### `fetch.sh`

Iterates `config.sources[]` and dispatches on `type`. Honors `when`. Writes into
`dirs.src/<type>/<name>/`. Flags: `--source NAME`, `--force`.

### `compile.sh`

- `compile_commands` — gather all PATH commands; record type, path, mime, lines
  for each definition; write `files.commands`
- `compile_existing` — scan standard zsh completion dirs; write `files.existing`
- `compile_available` — walk `dirs.src` per source priority; symlink each `_cmd`
  into `dirs.available/_cmd.<priority>`; write `files.available`

Source priority = source array index, lower is higher.

### `list.sh`

Filters: `--to-install`, `--to-uninstall`, `--missing`, `--existing`, `--all`,
`--summary`. `--pick` opens fzf (or `select`) to map a command to a source,
written into `config.commands`. `--json` switches output format.

### `sync.sh`

Builds an install/update/remove plan from `comps-available.json` against
`dirs.active`. Honors `config.commands` overrides above priority order. Default
is `--dry-run`; `--apply` executes. `--prune` removes orphaned symlinks.

### `generic.sh`

Generates a `_arguments`-based completion from `<cmd> --help` (falling back to
`man`). Minimal regex parser — recognizes `-s, --long[=VAL]  description`. Emits
to `dirs.src/generic/<cmd>/_<cmd>` and records metadata in `files.generic`.

### `output.sh`

Validates completion files: `zsh -n` syntax check + sourced smoke test in a
subshell. Records pass/fail to `files.output`. PTY-based simulation is out of
scope.

### `search.sh`

**Deferred.** Stub prints `search: deferred` and exits 0. Future: query GitHub
for completion files matching missing commands.

## Data Files

See `data/examples/` for representative shapes:

- `commands.json` — `{ cmd: [{type, path, lines, mime}, ...] }`
- `comps-available.json` — `{ cmd: [{path, lines, source, priority}, ...] }`
- `comps-existing.json` — `{ cmd: [{path, lines}, ...] }`
- `comps-generic.json` — `{ cmd: {generated, source, lines} }`
- `comps-output.json` — `{ cmd: {status, errors} }`

## Shared Utilities (`scripts/lib/utils.sh`)

- Logging: `log_error`, `log_warn`, `log_info`, `log_debug` (`LOG_LEVEL=debug` for verbose)
- Config: `load_config`, `get_dir`, `get_file`, `get_sources`, `get_source`,
  `get_source_count`, `get_source_by_name`, `get_source_dir`
- Helpers: `expand_path`, `ensure_dir`, `count_lines`, `get_mime_type`,
  `command_exists`, `has_command`, `fzf_or_select`, `print_aligned`,
  `print_header`, `print_success`, `print_error`

## Reference Material

`generic.sh` evolution targets:
- <https://github.com/BastiPaeltz/zsh-completion-generator>
- <https://github.com/RobSis/zsh-completion-generator>
- <https://github.com/clap-rs/clap/tree/master/clap_complete>
- <https://github.com/umlx5h/zsh-manpage-completion-generator>
- <https://github.com/adaszko/complgen>

`output.sh` evolution targets:
- <https://docs.rs/completest/0.0.12/completest/>

```zsh
# enumerating commands
results=("$(compgen -a)" "$(compgen -A function)" "$(compgen -b)" "$(compgen -c)")

# command hierarchy / typing
# type -a command
# mime detection
mime_type="$(file --mime-type "$path" | cut -f2 -d':')"

# enumerating loaded completions
for key val in "${(@kv)_comps[@]}"; do
  printf "%-50s %s\n" "${key}" "${val}"
done | sort
```
