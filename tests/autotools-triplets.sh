#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck source=../lib/build-env.sh
. "$ROOT/lib/build-env.sh"

fail()
{
    printf 'not ok - %s\n' "$1" >&2
    exit 1
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
mkdir "$TMP/bin"
for row in \
    'target-cc loongarch64-linux-musl' \
    'cross-cc powerpc64-linux-musl' \
    'build-cc x86_64-alpine-linux-musl'
do
    set -- $row
    cat >"$TMP/bin/$1" <<EOF
#!/bin/sh
[ "\${1:-}" = -dumpmachine ] && printf '%s\\n' '$2'
EOF
    chmod +x "$TMP/bin/$1"
done
for tool in cxx ar ranlib strip
 do
    printf '%s\n' '#!/bin/sh' 'exit 0' >"$TMP/bin/$tool"
    chmod +x "$TMP/bin/$tool"
done

TARGET_ARCH=loongarch64
TARGET_TRIPLET=loongarch64-linux-musl
BUILD_MODE=native-emulated
CC=$TMP/bin/target-cc
CXX=$TMP/bin/cxx
AR=$TMP/bin/ar
RANLIB=$TMP/bin/ranlib
STRIP=$TMP/bin/strip
unset BUILD_CC BUILD_TRIPLET
configure_build_environment "$TMP/native"
[ "${BUILD_TRIPLET-}" = loongarch64-linux-musl ] ||
    fail "native build triplet should bypass stale config.guess: ${BUILD_TRIPLET-unset}"
printf '%s\n' 'ok - native-emulated autotools build and host triplets match the target'

TARGET_ARCH=ppc64
TARGET_TRIPLET=powerpc64-linux-musl
BUILD_MODE=cross-musl
CC=$TMP/bin/cross-cc
BUILD_CC=$TMP/bin/build-cc
unset BUILD_TRIPLET
configure_build_environment "$TMP/cross"
[ "$BUILD_TRIPLET" = x86_64-alpine-linux-musl ] ||
    fail "cross build triplet should come from the build compiler: $BUILD_TRIPLET"
[ "$BUILD_TRIPLET" != "$TARGET_TRIPLET" ] || fail 'cross build and host triplets were conflated'
printf '%s\n' 'ok - ppc64 cross autotools keeps build and host triplets distinct'

configure_count=$(grep -F -- '--build="$BUILD_TRIPLET" --host="$TARGET_TRIPLET"' "$ROOT/build.sh" | wc -l)
[ "$configure_count" -eq 2 ] ||
    fail "both autotools dependencies must receive explicit build/host triplets (found $configure_count)"
printf '%s\n' 'ok - every autotools dependency receives explicit build and host triplets'

grep -F 'autoreconf -fi' "$ROOT/build.sh" >/dev/null ||
    fail 'LZO must refresh stale config.guess/config.sub before configuring modern targets'
printf '%s\n' 'ok - LZO refreshes Autotools target metadata before configure'
