#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

fail()
{
    printf 'not ok - %s\n' "$1" >&2
    exit 1
}

mkdir "$TMP/good" "$TMP/with-sections" "$TMP/exec"
printf '%s\n' \
    '.global _start' \
    '.text' \
    '_start:' \
    '    mov $60, %rax' \
    '    xor %rdi, %rdi' \
    '    syscall' >"$TMP/static.s"
cc -nostdlib -static -static-pie "$TMP/static.s" -o "$TMP/with-sections/mksquashfs-x86_64"
cp "$TMP/with-sections/mksquashfs-x86_64" "$TMP/with-sections/unsquashfs-x86_64"
cp "$TMP/with-sections/mksquashfs-x86_64" "$TMP/good/mksquashfs-x86_64"
python3 - "$TMP/good/mksquashfs-x86_64" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
elf = bytearray(path.read_bytes())
elf[40:48] = b"\0" * 8
elf[58:64] = b"\0" * 6
path.write_bytes(elf)
PY
cp "$TMP/good/mksquashfs-x86_64" "$TMP/good/unsquashfs-x86_64"
RELEASE_DIR="$TMP/good" "$ROOT/scripts/validate-artifacts.sh" x86_64
printf 'ok - valid sstripped static-PIE x86_64 artifact pair accepted\n'

cc -nostdlib -static -no-pie "$TMP/static.s" -o "$TMP/exec/mksquashfs-x86_64"
cp "$TMP/exec/mksquashfs-x86_64" "$TMP/exec/unsquashfs-x86_64"
if error=$(RELEASE_DIR="$TMP/exec" "$ROOT/scripts/validate-artifacts.sh" x86_64 2>&1); then
    fail 'ET_EXEC artifacts should fail'
fi
case $error in
    *'ET_DYN static PIE'*) ;;
    *) fail "ET_EXEC diagnostic: $error" ;;
esac
printf 'ok - ET_EXEC static artifacts rejected\n'

if error=$(RELEASE_DIR="$TMP/with-sections" "$ROOT/scripts/validate-artifacts.sh" x86_64 2>&1); then
    fail 'release artifacts with a section header table should fail'
fi
case $error in
    *'section header table'*) ;;
    *) fail "section-header diagnostic: $error" ;;
esac
printf 'ok - non-sstripped static PIE artifacts rejected\n'

mkdir "$TMP/wrong"
cp "$TMP/good/mksquashfs-x86_64" "$TMP/wrong/mksquashfs-ppc64"
cp "$TMP/good/unsquashfs-x86_64" "$TMP/wrong/unsquashfs-ppc64"
if error=$(RELEASE_DIR="$TMP/wrong" "$ROOT/scripts/validate-artifacts.sh" ppc64 2>&1); then
    fail 'wrong-machine artifacts should fail'
fi
case $error in
    *"expected ELF64 PowerPC64 big endian"*) ;;
    *) fail "wrong-machine diagnostic: $error" ;;
esac
printf 'ok - wrong machine/endian pair rejected\n'

mkdir "$TMP/dynamic"
printf '%s\n' 'int main(void) { return 0; }' >"$TMP/main.c"
cc "$TMP/main.c" -o "$TMP/dynamic/mksquashfs-x86_64"
cp "$TMP/dynamic/mksquashfs-x86_64" "$TMP/dynamic/unsquashfs-x86_64"
if error=$(RELEASE_DIR="$TMP/dynamic" "$ROOT/scripts/validate-artifacts.sh" x86_64 2>&1); then
    fail 'PT_INTERP artifacts should fail'
fi
case $error in
    *'PT_INTERP'*) ;;
    *) fail "dynamic diagnostic: $error" ;;
esac
printf 'ok - dynamic artifact pair rejected\n'

mkdir "$TMP/needed"
printf '%s\n' '#include <stdio.h>' 'int main(void) { return puts("dynamic dependency"); }' >"$TMP/needed.c"
cc -shared -fPIC -Wl,--no-as-needed "$TMP/needed.c" -lc -o "$TMP/needed/mksquashfs-x86_64"
cp "$TMP/needed/mksquashfs-x86_64" "$TMP/needed/unsquashfs-x86_64"
if ! LC_ALL=C readelf -d "$TMP/needed/mksquashfs-x86_64" | grep -E '\(NEEDED\)|0x0*1[[:space:]]' >/dev/null; then
    fail 'DT_NEEDED regression fixture has no NEEDED entry'
fi
if LC_ALL=C readelf -l "$TMP/needed/mksquashfs-x86_64" | grep -E 'INTERP|Requesting program interpreter' >/dev/null; then
    fail 'DT_NEEDED regression fixture unexpectedly has PT_INTERP'
fi
if error=$(RELEASE_DIR="$TMP/needed" "$ROOT/scripts/validate-artifacts.sh" x86_64 2>&1); then
    fail 'DT_NEEDED artifacts without PT_INTERP should fail'
fi
case $error in
    *'DT_NEEDED'*) ;;
    *) fail "DT_NEEDED diagnostic: $error" ;;
esac
printf 'ok - DT_NEEDED artifact without PT_INTERP rejected\n'

: >"$TMP/good/mksquashfs-x86_64"
chmod +x "$TMP/good/mksquashfs-x86_64"
if error=$(RELEASE_DIR="$TMP/good" "$ROOT/scripts/validate-artifacts.sh" x86_64 2>&1); then
    fail 'zero-byte artifact should fail'
fi
case $error in
    *'nonzero executable'*) ;;
    *) fail "zero-byte diagnostic: $error" ;;
esac
printf 'ok - zero-byte artifact rejected\n'
