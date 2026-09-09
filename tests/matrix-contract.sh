#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
# This source is the RED gate for the matrix implementation.
# shellcheck source=../lib/matrix.sh
. "$ROOT/lib/matrix.sh"

fail()
{
    printf 'not ok - %s\n' "$1" >&2
    exit 1
}

assert_row()
{
    arch=$1
    expected_platform=$2
    expected_image=$3
    expected_mode=$4
    expected_machine=$5
    expected_endian=$6
    expected_qemu=$7

    [ "$(matrix_platform "$arch")" = "$expected_platform" ] || fail "$arch OCI platform"
    [ "$(matrix_image "$arch")" = "$expected_image" ] || fail "$arch image"
    [ "$(matrix_build_mode "$arch")" = "$expected_mode" ] || fail "$arch build mode"
    [ "$(elf_machine "$arch")" = "$expected_machine" ] || fail "$arch ELF machine"
    [ "$(elf_endian "$arch")" = "$expected_endian" ] || fail "$arch ELF endian"
    [ "$(qemu_command "$arch")" = "$expected_qemu" ] || fail "$arch QEMU command"
    printf 'ok - %s matrix row\n' "$arch"
}

ALPINE='docker.io/library/alpine:3.24@sha256:28bd5fe8b56d1bd048e5babf5b10710ebe0bae67db86916198a6eec434943f8b'
LOONG_ALPINE='docker.io/loongarch64/alpine:3.21@sha256:ba4698dc340db5079eea01b7ea3488452a9a1c3cb8aad11033ea2cc978f49ffc'
assert_row x86_64 linux/amd64 "$ALPINE" native-emulated 'Advanced Micro Devices X86-64' little native
assert_row aarch64 linux/arm64 "$ALPINE" native-emulated AArch64 little qemu-aarch64-static
assert_row riscv64 linux/riscv64 "$ALPINE" native-emulated RISC-V little qemu-riscv64-static
assert_row loongarch64 linux/loong64 "$LOONG_ALPINE" native-emulated LoongArch little qemu-loongarch64-static
assert_row ppc64 linux/amd64 "$ALPINE" cross-musl 'PowerPC64' big qemu-ppc64-static
assert_row ppc64le linux/ppc64le "$ALPINE" native-emulated 'PowerPC64' little qemu-ppc64le-static

[ "$(HOST_ARCH=aarch64 qemu_command aarch64)" = native ] || fail 'native aarch64 runner'
[ "$(HOST_ARCH=aarch64 qemu_command x86_64)" = qemu-x86_64-static ] ||
    fail 'x86_64 uses an emulator on an aarch64 host'
[ "$(HOST_ARCH=x86_64 qemu_command x86_64)" = native ] || fail 'native x86_64 runner'

expected_arches='x86_64 aarch64 riscv64 loongarch64 ppc64 ppc64le'
[ "$(supported_arches)" = "$expected_arches" ] || fail 'supported architecture order'
expected_manifest='mksquashfs-aarch64
mksquashfs-loongarch64
mksquashfs-ppc64
mksquashfs-ppc64le
mksquashfs-riscv64
mksquashfs-x86_64
unsquashfs-aarch64
unsquashfs-loongarch64
unsquashfs-ppc64
unsquashfs-ppc64le
unsquashfs-riscv64
unsquashfs-x86_64'
[ "$(expected_artifact_manifest)" = "$expected_manifest" ] || fail 'complete artifact manifest'
[ "$(expected_artifacts ppc64)" = 'mksquashfs-ppc64
unsquashfs-ppc64' ] || fail 'per-architecture artifact manifest'

for arch in $expected_arches
do
    validate_matrix_arch "$arch" || fail "$arch should validate"
done
if error=$(validate_matrix_arch not-real 2>&1); then
    fail 'unknown matrix architecture should fail'
fi
case $error in
    *"unsupported architecture 'not-real'"*) ;;
    *) fail "unclear unknown-architecture error: $error" ;;
esac

printf 'ok - six-architecture build and artifact contract\n'
