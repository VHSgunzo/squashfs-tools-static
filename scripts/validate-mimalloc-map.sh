#!/bin/sh
set -eu

[ "$#" -gt 0 ] || {
    printf '%s\n' 'usage: validate-mimalloc-map.sh MAP...' >&2
    exit 2
}

for map in "$@"
do
    [ -s "$map" ] || {
        printf '%s is missing or empty\n' "$map" >&2
        exit 1
    }
    if ! LC_ALL=C grep -E 'libmimalloc\.a\([^)]*\)' "$map" >/dev/null; then
        printf '%s did not extract mimalloc from the normal static archive\n' "$map" >&2
        exit 1
    fi
    if ! LC_ALL=C grep -E '^[[:space:]]*malloc[[:space:]]+.*libmimalloc\.a\([^)]*\)' "$map" >/dev/null; then
        printf '%s does not resolve malloc to mimalloc\n' "$map" >&2
        exit 1
    fi
    printf '= validated %s: normal mimalloc archive extracted and owns malloc\n' "$map"
done
