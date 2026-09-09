#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BUILD=$ROOT/build.sh

fail()
{
    printf 'not ok - %s\n' "$1" >&2
    exit 1
}

for dependency in SQUASHFS_TOOLS MIMALLOC XZ LZO ZLIB LZ4 ZSTD
do
    assignment=$(sed -n "s/^${dependency}_COMMIT=\([0-9a-f]*\).*/\1/p" "$BUILD")
    case $assignment in
        [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) ;;
        *) fail "$dependency source is not pinned to a 40-hex commit" ;;
    esac
done

for dependency in SQUASHFS_TOOLS MIMALLOC XZ LZO ZLIB LZ4 ZSTD
do
    grep -F 'checkout_pinned_source . "$'"${dependency}"'_COMMIT"' "$BUILD" >/dev/null ||
        fail "$dependency source does not use checkout plus HEAD verification"
done

if grep -E '^(SQUASHFS_TOOLS|MIMALLOC|XZ|LZO|ZLIB|LZ4|ZSTD)_(VERSION|COMMIT)=git([[:space:]]|$)' "$BUILD" >/dev/null; then
    fail 'moving git source marker remains'
fi

if grep -E 'git checkout "?v?\$(SQUASHFS_TOOLS|MIMALLOC)_VERSION' "$BUILD" >/dev/null; then
    fail 'mutable source tag checkout remains'
fi

if grep -Eiq '(fully|completely)[[:space:]-]+(bit-for-bit[[:space:]-]+)?reproducible|immutable build( environment)?' "$ROOT/README.md"; then
    fail 'README overclaims build reproducibility'
fi
grep -F 'Alpine package repository contents and toolchain package revisions are not frozen' "$ROOT/README.md" >/dev/null ||
    fail 'README does not disclose live Alpine package inputs'

[ -r "$ROOT/lib/source-pins.sh" ] || fail 'source pin helper is missing'
# shellcheck source=../lib/source-pins.sh
. "$ROOT/lib/source-pins.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
cat >"$tmp/git" <<'EOF'
#!/bin/sh
case "$*" in
    *'checkout --detach'*) exit 0 ;;
    *'rev-parse HEAD'*) printf '%s\n' "$FAKE_HEAD" ;;
    *) exit 2 ;;
esac
EOF
chmod +x "$tmp/git"

expected=0123456789abcdef0123456789abcdef01234567
PATH="$tmp:$PATH" FAKE_HEAD=$expected checkout_pinned_source source "$expected"
if error=$(PATH="$tmp:$PATH" FAKE_HEAD=ffffffffffffffffffffffffffffffffffffffff \
    checkout_pinned_source source "$expected" 2>&1); then
    fail 'checked-out source HEAD mismatch should fail'
fi
case $error in
    *"source HEAD mismatch"*) ;;
    *) fail "source HEAD mismatch diagnostic: $error" ;;
esac

printf '%s\n' 'ok - dependency sources use immutable commits with checked-out HEAD verification'
