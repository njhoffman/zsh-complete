#!/usr/bin/env bash
# Search GitHub for completion files matching missing commands.
# DEFERRED: this is a documented stub. See SPECS.md.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/utils.sh"

show_help() {
    cat << EOF
Usage: $(basename "$0") [QUERY]

Search remote sources (e.g. GitHub) for completions matching missing commands.

This implementation is currently a deferred stub. See SPECS.md for the
intended contract. Future versions will:
  - query GitHub for files matching _<cmd>
  - aggregate results into comps-search.json
  - offer an interactive picker to add results to config.sources

For now, exits 0 after printing a notice.
EOF
}

main() {
    case "${1:-}" in
        -h|--help) show_help; exit 0 ;;
    esac
    log_info "search: deferred (see SPECS.md)"
    echo "search: deferred"
    exit 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
