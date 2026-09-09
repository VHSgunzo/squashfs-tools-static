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
fakebin=$TMP/bin
mkdir "$fakebin"
for tool in gcc g++ ar ranlib strip
do
    cat >"$fakebin/powerpc64-linux-musl-$tool" <<EOF
#!/bin/sh
[ "\${1:-}" = -dumpmachine ] && printf '%s\\n' powerpc64-linux-musl
exit 0
EOF
    chmod +x "$fakebin/powerpc64-linux-musl-$tool"
done

TARGET_ARCH=ppc64
TARGET_TRIPLET=powerpc64-linux-musl
BUILD_MODE=cross-musl
CC=$fakebin/powerpc64-linux-musl-gcc
CXX=$fakebin/powerpc64-linux-musl-g++
AR=$fakebin/powerpc64-linux-musl-ar
RANLIB=$fakebin/powerpc64-linux-musl-ranlib
STRIP=$fakebin/powerpc64-linux-musl-strip
CFLAGS=-caller-cflag
LDFLAGS=-caller-ldflag
configure_build_environment "$TMP/project"

[ "$BUILD_PREFIX" = "$TMP/project/build/sysroot/ppc64" ] || fail 'target-specific build prefix'
expected_cflags="-caller-cflag -Os -g0 -ffunction-sections -fdata-sections -fvisibility=hidden -fmerge-all-constants -I$BUILD_PREFIX/include -static-pie"
[ "$CFLAGS" = "$expected_cflags" ] || fail "legacy/static-PIE CFLAGS: $CFLAGS"
expected_ldflags="-caller-ldflag -L$BUILD_PREFIX/lib -Wl,-static -static-pie -Wl,--gc-sections -Wl,--strip-all"
[ "$LDFLAGS" = "$expected_ldflags" ] || fail "legacy/static-PIE LDFLAGS: $LDFLAGS"
[ "$PKG_CONFIG_LIBDIR" = "$BUILD_PREFIX/lib/pkgconfig:$BUILD_PREFIX/share/pkgconfig" ] ||
    fail 'pkg-config is not isolated to target prefix'
case $PKG_CONFIG_LIBDIR in
    *'/usr/lib'*) fail 'host /usr/lib contaminated pkg-config path' ;;
esac
validate_compiler_target || fail 'real ppc64 compiler triple should validate'
printf '%s\n' 'ok - cross environment uses an isolated target prefix'

cat >"$fakebin/wrong-gcc" <<'EOF'
#!/bin/sh
[ "${1:-}" = -dumpmachine ] && printf '%s\n' x86_64-linux-musl
EOF
chmod +x "$fakebin/wrong-gcc"
CC=$fakebin/wrong-gcc
if error=$(validate_compiler_target 2>&1); then
    fail 'wrong compiler triple should fail'
fi
case $error in
    *"compiler target 'x86_64-linux-musl' does not match 'powerpc64-linux-musl'"*) ;;
    *) fail "compiler mismatch diagnostic: $error" ;;
esac
printf '%s\n' 'ok - cross environment rejects a relabeled host compiler'
