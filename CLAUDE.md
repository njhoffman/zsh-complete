# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

zsh-complete is a toolset for managing zsh shell completions. It aggregates completions from multiple sources (builtin, vendor, remote repositories), catalogs available commands, and provides utilities for installing/syncing completions.

## Scripts

All scripts are bash (not zsh) unless zsh-specific features are required:

- **fetch.sh** - Downloads/refreshes completions from sources defined in config.json:
  - Remote URLs are cloned to `dirs.vendor/{source.name}`
  - Generated completions (via `source.cmd`) output to `dirs.generated/{source.name}`
  - Builtin paths are copied to `dirs.builtin/{source.name}`

- **compile.sh** - Aggregates sources into JSON data files:
  - Creates symbolic links in `dirs.available` with priority suffix (e.g., `comp_name.1`, `comp_name.3`)
  - Lower index = higher priority
  - Only includes completions for commands in commands.json

- **list.sh** - Lists completions with filtering options (to-install, to-uninstall, missing, existing)

- **sync.sh** - Installs/removes/syncs completions between available and active directories

- **generic.sh** - Generates completions from `--help` output for commands without existing completions

- **output.sh** - Simulates completion output for testing/error checking

## Configuration

`config.json` defines:

- **files**: Paths to data files (commands.json, comps-*.json, history.log)
- **dirs**: Working directories (src, vendor, builtin, generated, available, active)
- **sources**: Array of completion sources with name, optional url/cmd/paths

## Data Files (see data/examples/)

- **commands.json** - Map of command names to array of definitions (type: function/file/builtin/alias, path, lines, mime)
- **comps-available.json** - Available completions with path and line count
- **comps-existing.json** - Currently installed completions
- **comps-generic.json** - Generated completions from --help
- **comps-output.json** - Completion test output data

## Shared Utilities

`scripts/lib/utils.sh` provides common functions:

- **Logging**: `log_error`, `log_warn`, `log_info`, `log_debug` - colored terminal output + file logging
- **Config**: `load_config`, `get_dir`, `get_file`, `get_source` - parse config.json with jq
- **Helpers**: `ensure_dir`, `expand_path`, `count_lines`, `get_mime_type`

Set `LOG_LEVEL=debug` for verbose output.

## Testing

Uses [bats-core](https://github.com/bats-core/bats-core) for unit and integration tests:

```bash
bats tests/                        # Run all tests
bats tests/utils.bats              # Run single test file
bats tests/fetch.bats -f "builtin" # Run tests matching pattern
```

## Development Notes

- Terminal output should be aligned and colored for readability
- Detailed logging goes to the history log file
- Use `mkdir -p` to ensure directories exist
- All scripts source `scripts/lib/utils.sh` for shared functionality
- Use `declare -gA` for global associative arrays (required for bats compatibility)
