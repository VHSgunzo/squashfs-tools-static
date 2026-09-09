#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck source=../lib/matrix.sh
. "$ROOT/lib/matrix.sh"

arch=${1:-}
validate_matrix_arch "$arch" || exit 2
RELEASE_DIR=${RELEASE_DIR:-$ROOT/release}
"$ROOT/scripts/validate-artifacts.sh" "$arch"

runner=$(qemu_command "$arch")
if [ "$runner" != native ]; then
    command -v "$runner" >/dev/null 2>&1 || {
        printf "required emulator '%s' is unavailable; smoke test did not run\n" "$runner" >&2
        exit 1
    }
    "$runner" --version | sed -n '1p'
fi

run_target()
{
    if [ "$runner" = native ]; then
        "$@"
    else
        "$runner" "$@"
    fi
}

mksquashfs=$RELEASE_DIR/mksquashfs-$arch
unsquashfs=$RELEASE_DIR/unsquashfs-$arch
run_target "$mksquashfs" -version >/dev/null
if unsquashfs_version=$(run_target "$unsquashfs" -version 2>&1); then
    :
else
    status=$?
    [ "$status" -eq 1 ] || {
        printf 'unsquashfs -version failed with status %s\n' "$status" >&2
        exit "$status"
    }
fi
printf '%s\n' "$unsquashfs_version" | grep -F 'unsquashfs version' >/dev/null || {
    printf '%s\n' 'unsquashfs -version did not identify the tool' >&2
    exit 1
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
mkdir -p "$tmp/input/nested"
printf '%s\n' 'multiarch squashfs round trip' >"$tmp/input/nested/message.txt"
printf '\000\001\002\376\377' >"$tmp/input/data.bin"
ln -s nested/message.txt "$tmp/input/message-link"
run_target "$mksquashfs" "$tmp/input" "$tmp/archive.squashfs" \
    -noappend -quiet -processors 1
run_target "$unsquashfs" -d "$tmp/output" -no-progress -processors 1 \
    "$tmp/archive.squashfs" >/dev/null
cmp "$tmp/input/nested/message.txt" "$tmp/output/nested/message.txt"
cmp "$tmp/input/data.bin" "$tmp/output/data.bin"
[ -L "$tmp/output/message-link" ] || {
    printf '%s\n' 'round trip did not preserve symlink type' >&2
    exit 1
}
[ "$(readlink "$tmp/output/message-link")" = nested/message.txt ] || {
    printf '%s\n' 'round trip did not preserve symlink target' >&2
    exit 1
}
printf '= version smoke and round trip passed for %s\n' "$arch"
