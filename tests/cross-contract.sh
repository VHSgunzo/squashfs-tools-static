#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck source=../lib/target.sh
. "$ROOT/lib/target.sh"
# shellcheck source=../lib/ppc64-toolchain.sh
. "$ROOT/lib/ppc64-toolchain.sh"

fail()
{
    printf 'not ok - %s\n' "$1" >&2
    exit 1
}

[ "$PPC64_MUSL_TOOLCHAIN_URL" = 'https://github.com/musl-cc/musl.cc/releases/download/v0.0.1/powerpc64-linux-musl-cross.tgz' ] ||
    fail 'ppc64 toolchain URL is not release-pinned'
[ "$PPC64_MUSL_TOOLCHAIN_SHA256" = '4ae497aa188d336b25872d32d586cb2d7afb8a153001deac50149babb9886bc8' ] ||
    fail 'ppc64 toolchain checksum'
printf 'ok - ppc64 toolchain source and digest are pinned\n'

TARGET_ARCH=ppc64
BUILD_MODE=cross-musl
validate_build_mode || fail 'ppc64 cross-musl mode should validate'

TARGET_ARCH=aarch64
if error=$(validate_build_mode 2>&1); then
    fail 'cross-musl mode must be limited to ppc64'
fi
case $error in
    *'cross-musl mode is only supported for ppc64'*) ;;
    *) fail "cross-mode target diagnostic: $error" ;;
esac

TARGET_ARCH=ppc64
BUILD_MODE=native-emulated
fakebin=$(mktemp -d)
trap 'rm -rf "$fakebin"' EXIT HUP INT TERM
printf '%s\n' '#!/bin/sh' 'printf "%s\n" x86_64' >"$fakebin/uname"
chmod +x "$fakebin/uname"
if error=$(PATH="$fakebin:$PATH" validate_build_mode 2>&1); then
    fail 'native-emulated ppc64 must reject an x86_64 machine'
fi
case $error in
    *"TARGET_ARCH 'ppc64' does not match build machine 'x86_64'"*) ;;
    *) fail "native mismatch diagnostic: $error" ;;
esac
printf 'ok - cross mode is explicit and native mismatch remains rejected\n'

TARGET_ARCH=ppc64
BUILD_MODE=not-a-mode
if error=$(validate_build_mode 2>&1); then
    fail 'unknown build mode should fail'
fi
case $error in
    *"unsupported BUILD_MODE 'not-a-mode'"*) ;;
    *) fail "unknown build mode diagnostic: $error" ;;
esac
printf 'ok - unknown build mode fails clearly\n'
