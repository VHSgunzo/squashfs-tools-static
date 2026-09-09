#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
CLEAN=$TMP/clean
mkdir "$CLEAN"

# Reconstruct exactly what would be committed without touching the caller's
# real index: seed a temporary index from HEAD, overlay every current tracked
# change and non-ignored untracked file, then archive that prospective tree.
real_index_before=$(git -C "$ROOT" hash-object "$ROOT/.git/index")
GIT_INDEX_FILE=$TMP/index git -C "$ROOT" read-tree HEAD
GIT_INDEX_FILE=$TMP/index git -C "$ROOT" add -A -- .
tree=$(GIT_INDEX_FILE=$TMP/index git -C "$ROOT" write-tree)
git -C "$ROOT" archive "$tree" | tar -x -C "$CLEAN"
real_index_after=$(git -C "$ROOT" hash-object "$ROOT/.git/index")
[ "$real_index_before" = "$real_index_after" ] || {
    printf '%s\n' 'not ok - clean-checkout reconstruction modified the real git index' >&2
    exit 1
}

[ ! -e "$CLEAN/release" ] || {
    printf '%s\n' 'not ok - clean test fixture unexpectedly contains ignored release outputs' >&2
    exit 1
}

# Tests that inspect trackability need a real clean repository rather than a
# hand-copied directory that can silently omit a newly added helper.
git -C "$CLEAN" init -q
git -C "$CLEAN" add -A
git -C "$CLEAN" -c user.name='Clean Checkout Test' \
    -c user.email='clean-checkout@example.invalid' commit -q -m fixture

run_count=0
for test_path in "$CLEAN"/tests/*.sh
do
    test_name=$(basename "$test_path")
    [ "$test_name" = clean-checkout.sh ] && continue
    sh "$test_path"
    run_count=$((run_count + 1))
done

expected_count=0
for test_path in "$ROOT"/tests/*.sh
do
    [ "$(basename "$test_path")" = clean-checkout.sh ] && continue
    expected_count=$((expected_count + 1))
done
[ "$run_count" -eq "$expected_count" ] || {
    printf 'not ok - reconstructed tree ran %s of %s non-recursive tests\n' \
        "$run_count" "$expected_count" >&2
    exit 1
}
printf 'ok - all %s non-recursive tests pass in reconstructed prospective tree\n' \
    "$run_count"
