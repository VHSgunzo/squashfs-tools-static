#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck source=../lib/matrix.sh
. "$ROOT/lib/matrix.sh"

validation_stage=release
if [ "${1:-}" = --before-sstrip ]; then
    validation_stage=before-sstrip
    shift
fi
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
    if ! printf '%s\n' "$header" | grep -F 'Type:' | grep -F 'DYN (Position-Independent Executable file)' >/dev/null; then
        printf '%s must be ET_DYN static PIE (not ET_EXEC)\n' "$artifact" >&2
        exit 1
    fi
    stage_description=
    if [ "$validation_stage" = release ]; then
        section_offset=$(printf '%s\n' "$header" | sed -n 's/^[[:space:]]*Start of section headers:[[:space:]]*\([0-9][0-9]*\).*/\1/p')
        section_count=$(printf '%s\n' "$header" | sed -n 's/^[[:space:]]*Number of section headers:[[:space:]]*\([0-9][0-9]*\).*/\1/p')
        if [ "$section_offset" != 0 ] || [ "$section_count" != 0 ]; then
            printf '%s retains a section header table; required sstrip was not applied\n' "$artifact" >&2
            exit 1
        fi
        stage_description=', no section headers'
    fi
    printf '= validated %s: ELF64 ET_DYN static PIE, %s %s endian%s\n' \
        "$name" "$machine" "$endian" "$stage_description"
done
