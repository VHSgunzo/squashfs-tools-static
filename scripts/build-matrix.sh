#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck source=../lib/matrix.sh
. "$ROOT/lib/matrix.sh"

DOCKER=${DOCKER:-docker}
selection=${1:-all}
[ "$#" -le 1 ] || {
    printf 'usage: %s [all|%s]\n' "$0" "$(supported_arches)" >&2
    exit 2
}

if [ "$selection" = all ]; then
    arches=$(supported_arches)
else
    validate_matrix_arch "$selection" || exit 2
    arches=$selection
fi

command -v "$DOCKER" >/dev/null 2>&1 || {
    printf "required container command '%s' was not found\n" "$DOCKER" >&2
    exit 1
}

for arch in $arches
do
    platform=$(matrix_platform "$arch")
    image=$(matrix_image "$arch")
    mode=$(matrix_build_mode "$arch")
    printf '= build %s (%s, %s)\n' "$arch" "$platform" "$mode"
    if [ "$mode" = cross-musl ]; then
        entrypoint=./scripts/build-ppc64.sh
    else
        entrypoint=./build.sh
    fi
    "$DOCKER" run --rm \
        --platform "$platform" \
        -e "TARGET_ARCH=$arch" \
        -v "$ROOT:/src" \
        -w /src \
        "$image" "$entrypoint"
done
