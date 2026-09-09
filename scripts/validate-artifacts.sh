#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck source=../lib/matrix.sh
. "$ROOT/lib/matrix.sh"

arch=${1:-}
validate_matrix_arch "$arch" || exit 2
RELEASE_DIR=${RELEASE_DIR:-$ROOT/release}
machine=$(elf_machine "$arch")
endian=$(elf_endian "$arch")

case $endian in
    little) data_description="2's complement, little endian" ;;
    big) data_description="2's complement, big endian" ;;
esac

for name in $(expected_artifacts "$arch")
do
    artifact=$RELEASE_DIR/$name
    if [ ! -s "$artifact" ] || [ ! -x "$artifact" ]; then
        printf '%s must be a nonzero executable\n' "$artifact" >&2
        exit 1
    fi

    header=$(LC_ALL=C readelf -h "$artifact" 2>&1) || {
        printf '%s is not a readable ELF file\n' "$artifact" >&2
        exit 1
    }
    if ! printf '%s\n' "$header" | grep -F 'Class:' | grep -F 'ELF64' >/dev/null ||
       ! printf '%s\n' "$header" | grep -F 'Machine:' | grep -F "$machine" >/dev/null ||
       ! printf '%s\n' "$header" | grep -F 'Data:' | grep -F "$data_description" >/dev/null; then
        printf '%s: expected ELF64 %s %s endian\n' "$artifact" "$machine" "$endian" >&2
        exit 1
    fi

    if LC_ALL=C readelf -l "$artifact" | grep -E 'INTERP|Requesting program interpreter' >/dev/null; then
        printf '%s contains PT_INTERP and is not static\n' "$artifact" >&2
        exit 1
    fi
    if LC_ALL=C readelf -d "$artifact" | grep -E '\(NEEDED\)|(^|[[:space:]])0x0*1[[:space:]]' >/dev/null; then
        printf '%s contains DT_NEEDED shared-library dependencies and is not static\n' "$artifact" >&2
        exit 1
    fi
    printf '= validated %s: ELF64 %s %s endian, static\n' "$name" "$machine" "$endian"
done
