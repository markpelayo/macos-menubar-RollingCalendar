#!/usr/bin/env bash
# Prints one version's section of CHANGELOG.md, for a release body:
#
#   ./release-notes.sh 1.6.0
#   gh release create v1.6.0 --title v1.6.0 --notes-file <(./release-notes.sh 1.6.0)
#
# No second copy of the notes to keep in step — the changelog is the source.
set -euo pipefail

version="${1:-}"
if [[ -z "$version" ]]; then
    echo "usage: $(basename "$0") <version>   e.g. $(basename "$0") 1.6.0" >&2
    exit 2
fi

changelog="$(dirname "$0")/CHANGELOG.md"

if ! grep -q "## \[$version\]" "$changelog"; then
    echo "no section for $version in CHANGELOG.md" >&2
    exit 1
fi

awk -v want="## [$version]" '
    index($0, want) == 1 { inside = 1; next }
    inside && /^## \[/    { exit }
    inside && /^\[[0-9]/  { exit }
    inside                { print }
' "$changelog" | awk 'NF || printed { print; printed = 1 }' | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}'

