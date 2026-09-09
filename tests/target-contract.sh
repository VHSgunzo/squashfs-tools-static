#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck source=../lib/target.sh
. "$ROOT/lib/target.sh"

fail()
{
    printf 'not ok - %s\n' "$1" >&2
    exit 1
}

for helper in lib/target.sh lib/release.sh
do
    if git -C "$ROOT" check-ignore --no-index -q -- "$helper"; then
        git_status=0
    else
        git_status=$?
    fi
    case $git_status in
        0) fail "$helper must be trackable" ;;
        1) ;;
        *) fail "git check-ignore failed for $helper (exit $git_status)" ;;
    esac
done
printf 'ok - required helpers are trackable\n'

assert_mapping()
{
    arch=$1
    expected=$2
    actual=$(target_triplet "$arch") || fail "$arch should be supported"
    [ "$actual" = "$expected" ] ||
        fail "$arch mapped to '$actual', expected '$expected'"
    printf 'ok - %s maps to %s\n' "$arch" "$expected"
}

assert_mapping x86_64 x86_64-linux-musl
assert_mapping aarch64 aarch64-linux-musl
assert_mapping riscv64 riscv64-linux-musl
assert_mapping loongarch64 loongarch64-linux-musl
assert_mapping ppc64 powerpc64-linux-musl
assert_mapping ppc64le powerpc64le-linux-musl

if error=$(target_triplet unknown-arch 2>&1); then
    fail "unknown architecture should fail"
fi
case $error in
    *"unsupported TARGET_ARCH 'unknown-arch'"*) ;;
    *) fail "unknown architecture error was not clear: $error" ;;
esac
printf 'ok - unknown architecture fails clearly\n'

TARGET_ARCH=aarch64
[ "$(resolve_target_arch)" = aarch64 ] || fail "explicit TARGET_ARCH was not preserved"
unset TARGET_ARCH

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT HUP INT TERM
fakebin=$test_tmp/default-bin
mkdir "$fakebin"
printf '%s\n' '#!/bin/sh' 'printf "%s\\n" riscv64' >"$fakebin/uname"
chmod +x "$fakebin/uname"
[ "$(PATH="$fakebin:$PATH" resolve_target_arch)" = riscv64 ] ||
    fail "TARGET_ARCH did not default from uname -m"
printf 'ok - TARGET_ARCH defaults from uname -m\n'

preflight_bin=$test_tmp/preflight-bin
side_effect=$test_tmp/side-effect
mkdir "$preflight_bin"
printf '%s\n' '#!/bin/sh' 'case ${1:-} in' '    -m) printf "%s\\n" x86_64 ;;' '    -s) printf "%s\\n" Linux ;;' 'esac' >"$preflight_bin/uname"
printf '%s\n' '#!/bin/sh' 'printf "%s\\n" called >"$SIDE_EFFECT"' 'exit 77' >"$preflight_bin/apk"
chmod +x "$preflight_bin/uname" "$preflight_bin/apk"
if mismatch_error=$(PATH="$preflight_bin:$PATH" SIDE_EFFECT="$side_effect" TARGET_ARCH=ppc64 \
    "$ROOT/build.sh" 2>&1); then
    fail "mismatched TARGET_ARCH should fail"
fi
case $mismatch_error in
    *"TARGET_ARCH 'ppc64' does not match build machine 'x86_64'"*) ;;
    *) fail "mismatched target error was not clear: $mismatch_error" ;;
esac
[ ! -e "$side_effect" ] || fail "mismatched target reached package/build side effects"
printf 'ok - mismatched TARGET_ARCH fails before side effects\n'

rm -f "$side_effect"
if unsupported_error=$(PATH="$preflight_bin:$PATH" SIDE_EFFECT="$side_effect" \
    TARGET_ARCH=unknown-arch "$ROOT/build.sh" 2>&1); then
    fail "unsupported TARGET_ARCH should fail"
fi
case $unsupported_error in
    *"unsupported TARGET_ARCH 'unknown-arch'"*) ;;
    *) fail "unsupported target error was not clear: $unsupported_error" ;;
esac
[ ! -e "$side_effect" ] || fail "unsupported target reached package/build side effects"
printf 'ok - unsupported TARGET_ARCH fails before side effects\n'

TARGET_ARCH=ppc64
TARGET_TRIPLET=stale-triplet
export TARGET_ARCH TARGET_TRIPLET
_target_arch=keep-arch-scratch
_target_triplet=keep-triplet-scratch
resolve_target_contract || fail "target contract could not be resolved"
[ "$TARGET_ARCH" = ppc64 ] || fail "resolved TARGET_ARCH changed unexpectedly"
[ "$TARGET_TRIPLET" = powerpc64-linux-musl ] || fail "resolved target triplet is wrong"
[ "${_target_arch-}" = keep-arch-scratch ] || fail "target helper clobbered caller's _target_arch"
[ "${_target_triplet-}" = keep-triplet-scratch ] || fail "target helper clobbered caller's _target_triplet"
if env | grep -E '^TARGET_(ARCH|TRIPLET)=' >/dev/null; then
    fail "target contract variables leaked into upstream build environments"
fi
printf 'ok - sourced helper preserves caller scratch variables\n'
printf 'ok - resolved target variables do not leak into child environments\n'

toolchain_root=$test_tmp/toolchain-root
toolchain_bin=$test_tmp/toolchain-bin
toolchain_capture=$test_tmp/toolchain-env
mkdir -p "$toolchain_root/lib" "$toolchain_bin"
cp "$ROOT/build.sh" "$toolchain_root/build.sh"
cp "$ROOT/lib/target.sh" "$toolchain_root/lib/target.sh"
cp "$ROOT/lib/release.sh" "$toolchain_root/lib/release.sh"
printf '%s\n' '#!/bin/sh' 'case ${1:-} in' '    -m) printf "%s\\n" x86_64 ;;' '    -s) printf "%s\\n" Linux ;;' 'esac' >"$toolchain_bin/uname"
printf '%s\n' '#!/bin/sh' 'printf "%s\\n" 1' >"$toolchain_bin/nproc"
printf '%s\n' '#!/bin/sh' 'exit 0' >"$toolchain_bin/apk"
printf '%s\n' '#!/bin/sh' 'env >"$TOOLCHAIN_CAPTURE"' 'exit 78' >"$toolchain_bin/git"
chmod +x "$toolchain_root/build.sh" "$toolchain_bin/uname" "$toolchain_bin/nproc" \
    "$toolchain_bin/apk" "$toolchain_bin/git"
if PATH="$toolchain_bin:$PATH" TOOLCHAIN_CAPTURE="$toolchain_capture" TARGET_ARCH=x86_64 \
    CC=custom-cc CXX=custom-cxx AR=custom-ar RANLIB=custom-ranlib STRIP=custom-strip \
    CROSS_COMPILE=custom- CMAKE_TOOLCHAIN_FILE=/toolchain.cmake \
    CFLAGS=-custom-cflag LDFLAGS=-custom-ldflag MAKEFLAGS=-custom-makeflag \
    "$toolchain_root/build.sh" >/dev/null 2>&1; then
    fail "toolchain probe unexpectedly completed the build"
fi
for expected in \
    'CC=custom-cc' 'CXX=custom-cxx' 'AR=custom-ar' 'RANLIB=custom-ranlib' \
    'STRIP=custom-strip' 'CROSS_COMPILE=custom-' \
    'CMAKE_TOOLCHAIN_FILE=/toolchain.cmake'
do
    grep -Fx "$expected" "$toolchain_capture" >/dev/null ||
        fail "externally supplied toolchain value was not preserved: $expected"
done
case $(grep '^CFLAGS=' "$toolchain_capture") in
    *-custom-cflag*) ;;
    *) fail "externally supplied CFLAGS were not preserved" ;;
esac
case $(grep '^LDFLAGS=' "$toolchain_capture") in
    *-custom-ldflag*) ;;
    *) fail "externally supplied LDFLAGS were not preserved" ;;
esac
case $(grep '^MAKEFLAGS=' "$toolchain_capture") in
    *-custom-makeflag*) ;;
    *) fail "externally supplied MAKEFLAGS were not preserved" ;;
esac
printf 'ok - externally supplied compiler and toolchain environment is preserved\n'

rm -rf "$toolchain_root/build" "$toolchain_root/release"
mkdir "$toolchain_root/release"
for asset in \
    mksquashfs-x86_64 unsquashfs-x86_64 \
    mksquashfs-x86_64-upx unsquashfs-x86_64-upx \
    mksquashfs-aarch64 unsquashfs-ppc64le-upx notes-x86_64.txt
do
    printf 'stale %s\n' "$asset" >"$toolchain_root/release/$asset"
done
PATH="$toolchain_bin:$PATH" TOOLCHAIN_CAPTURE="$toolchain_capture" TARGET_ARCH=x86_64 \
    "$toolchain_root/build.sh" >/dev/null 2>&1 || :
for stale in \
    mksquashfs-x86_64 unsquashfs-x86_64 \
    mksquashfs-x86_64-upx unsquashfs-x86_64-upx
do
    [ ! -e "$toolchain_root/release/$stale" ] ||
        fail "current-target stale release asset was not removed: $stale"
done
for preserved in mksquashfs-aarch64 unsquashfs-ppc64le-upx notes-x86_64.txt
do
    [ -e "$toolchain_root/release/$preserved" ] ||
        fail "cleanup removed unrelated release asset: $preserved"
done
printf 'ok - cleanup removes only current-target release and legacy UPX assets\n'

[ -r "$ROOT/lib/release.sh" ] || fail "release installation helper is missing"
# shellcheck source=../lib/release.sh
. "$ROOT/lib/release.sh"
release_test=$test_tmp/release-install
mkdir "$release_test"
release_source=$release_test/mksquashfs
printf 'new binary\n' >"$release_source"
chmod +x "$release_source"
printf 'old binary\n' >"$release_test/mksquashfs-x86_64"
install_release_binary "$release_source" "$release_test" x86_64 ||
    fail "atomic release installation failed"
cmp -s "$release_source" "$release_test/mksquashfs-x86_64" ||
    fail "installed release binary differs from source"
[ -x "$release_test/mksquashfs-x86_64" ] ||
    fail "installed release binary lost its executable mode"
if find "$release_test" -name '.mksquashfs-x86_64.tmp.*' | grep . >/dev/null; then
    fail "successful atomic install left a temporary file"
fi
printf 'ok - release binary installation succeeds through an adjacent temporary file\n'

printf 'old binary\n' >"$release_test/mksquashfs-x86_64"
failing_bin=$test_tmp/failing-copy-bin
mkdir "$failing_bin"
printf '%s\n' '#!/bin/sh' 'for destination do :; done' \
    'printf "%s\\n" partial >"$destination"' 'exit 79' >"$failing_bin/cp"
chmod +x "$failing_bin/cp"
if PATH="$failing_bin:$PATH" install_release_binary \
    "$release_source" "$release_test" x86_64; then
    fail "release installation should fail when its copy fails"
fi
[ "$(cat "$release_test/mksquashfs-x86_64")" = 'old binary' ] ||
    fail "failed install replaced the existing release binary"
if find "$release_test" -name '.mksquashfs-x86_64.tmp.*' | grep . >/dev/null; then
    fail "failed atomic install left a temporary file"
fi
printf 'ok - failed release installation keeps prior output and cleans its temporary file\n'

build_script=$ROOT/build.sh
if grep -E '(WITH_UPX|VENDOR_UPX|UPX_VERSION|super-strip|sstrip|upx --force-overwrite)' "$build_script" >/dev/null; then
    fail "build.sh still mandates UPX or host sstrip post-processing"
fi
printf 'ok - build.sh has no mandatory host post-processing\n'
