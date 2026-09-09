#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VALIDATOR=$ROOT/scripts/validate-mimalloc-map.sh
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

fail()
{
    printf 'not ok - %s\n' "$1" >&2
    exit 1
}

cat >"$TMP/mksquashfs.map" <<'EOF'
Archive member included to satisfy reference by file (symbol)
/sysroot/lib/libmimalloc.a(static.c.o)
                              mksquashfs.o (malloc)
Cross Reference Table
Symbol                                            File
malloc                                            /sysroot/lib/libmimalloc.a(static.c.o)
EOF
cp "$TMP/mksquashfs.map" "$TMP/unsquashfs.map"
"$VALIDATOR" "$TMP/mksquashfs.map" "$TMP/unsquashfs.map"
printf '%s\n' 'ok - link maps prove mimalloc archive extraction and malloc resolution'

cat >"$TMP/missing.map" <<'EOF'
Cross Reference Table
Symbol                                            File
malloc                                            /usr/lib/libc.a(malloc.o)
EOF
if error=$("$VALIDATOR" "$TMP/missing.map" 2>&1); then
    fail 'map without mimalloc extraction should fail'
fi
case $error in
    *'did not extract mimalloc'*) ;;
    *) fail "missing mimalloc diagnostic: $error" ;;
esac
printf '%s\n' 'ok - map without mimalloc extraction rejected'

cat >"$TMP/wrong-allocator.map" <<'EOF'
Archive member included to satisfy reference by file (symbol)
/sysroot/lib/libmimalloc.a(options.c.o)
                              memory.o (mi_option_get)
Cross Reference Table
Symbol                                            File
malloc                                            /usr/lib/libc.a(malloc.o)
EOF
if error=$("$VALIDATOR" "$TMP/wrong-allocator.map" 2>&1); then
    fail 'map with libc malloc resolution should fail'
fi
case $error in
    *'does not resolve malloc to mimalloc'*) ;;
    *) fail "allocator resolution diagnostic: $error" ;;
esac
printf '%s\n' 'ok - map resolving malloc outside mimalloc rejected'
