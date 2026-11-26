#!/usr/bin/env bash
# Check tracked shell sources without executing their contents.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

syntax_only=false
case "${1:-}" in
  '') ;;
  --syntax-only) syntax_only=true ;;
  *) echo 'Usage: check_shell_quality.sh [--syntax-only]' >&2; exit 2 ;;
esac
if (( $# > 1 )); then
  echo 'Usage: check_shell_quality.sh [--syntax-only]' >&2
  exit 2
fi

if [[ "$syntax_only" == false ]]; then
  command -v shellcheck >/dev/null || { echo 'ShellCheck is required' >&2; exit 1; }
  shellcheck --version
fi

git ls-files -z -- '*.sh' '*.bash' | while IFS= read -r -d '' path; do
  printf 'Checking %s\n' "$path"
  bash -n -- "$path"
  if [[ "$syntax_only" == false ]]; then
    # Initial correctness gate; warning/style debt is reviewed separately.
    shellcheck --severity=error -- "$path"
  fi
done
printf 'Shell quality checks passed (syntax-only=%s).\n' "$syntax_only"
