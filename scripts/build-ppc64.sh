#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck source=../lib/ppc64-toolchain.sh
. "$ROOT/lib/ppc64-toolchain.sh"

TOOLCHAIN_PARENT=${TOOLCHAIN_PARENT:-/opt}
toolchain=$TOOLCHAIN_PARENT/powerpc64-linux-musl-cross
archive=${PPC64_MUSL_TOOLCHAIN_ARCHIVE:-}

if [ ! -x "$toolchain/bin/powerpc64-linux-musl-gcc" ]; then
    mkdir -p "$TOOLCHAIN_PARENT"
    if [ -z "$archive" ]; then
        command -v apk >/dev/null 2>&1 && apk add --no-cache ca-certificates curl tar gzip
        archive=$(mktemp "$TOOLCHAIN_PARENT/.powerpc64-toolchain.tgz.XXXXXX")
        cleanup_archive=$archive
        curl --fail --location --retry 3 --output "$archive" "$PPC64_MUSL_TOOLCHAIN_URL"
    fi

    actual=$(sha256sum "$archive")
    actual=${actual%% *}
    if [ "$actual" != "$PPC64_MUSL_TOOLCHAIN_SHA256" ]; then
        printf 'toolchain checksum mismatch: expected %s, got %s\n' \
            "$PPC64_MUSL_TOOLCHAIN_SHA256" "$actual" >&2
        [ -z "${cleanup_archive:-}" ] || rm -f "$cleanup_archive"
        exit 1
    fi

    temporary=$TOOLCHAIN_PARENT/.powerpc64-toolchain.extract.$$
    trap 'rm -rf "$temporary"; [ -z "${cleanup_archive:-}" ] || rm -f "$cleanup_archive"' EXIT HUP INT TERM
    mkdir "$temporary"
    tar -xzf "$archive" -C "$temporary"
    [ -x "$temporary/powerpc64-linux-musl-cross/bin/powerpc64-linux-musl-gcc" ] || {
        printf '%s\n' 'toolchain archive did not contain powerpc64-linux-musl-gcc' >&2
        exit 1
    }
    rm -rf "$toolchain"
    mv "$temporary/powerpc64-linux-musl-cross" "$toolchain"
    rm -rf "$temporary"
    [ -z "${cleanup_archive:-}" ] || rm -f "$cleanup_archive"
    trap - EXIT HUP INT TERM
fi

PATH=$toolchain/bin:$PATH
CC=$toolchain/bin/powerpc64-linux-musl-gcc
CXX=$toolchain/bin/powerpc64-linux-musl-g++
AR=$toolchain/bin/powerpc64-linux-musl-ar
RANLIB=$toolchain/bin/powerpc64-linux-musl-ranlib
STRIP=$toolchain/bin/powerpc64-linux-musl-strip
CROSS_COMPILE=$toolchain/bin/powerpc64-linux-musl-
TARGET_ARCH=ppc64
BUILD_MODE=cross-musl
export PATH CC CXX AR RANLIB STRIP CROSS_COMPILE TARGET_ARCH BUILD_MODE
exec "$ROOT/build.sh"
