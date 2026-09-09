#!/bin/sh

supported_arches()
{
    printf '%s\n' 'x86_64 aarch64 riscv64 loongarch64 ppc64 ppc64le'
}

validate_matrix_arch()
{
    case $1 in
        x86_64|aarch64|riscv64|loongarch64|ppc64|ppc64le) ;;
        *)
            printf "unsupported architecture '%s' (supported: %s)\n" "$1" "$(supported_arches)" >&2
            return 1
            ;;
    esac
}

matrix_platform()
{
    validate_matrix_arch "$1" || return 1
    case $1 in
        x86_64|ppc64) printf '%s\n' linux/amd64 ;;
        aarch64) printf '%s\n' linux/arm64 ;;
        riscv64) printf '%s\n' linux/riscv64 ;;
        loongarch64) printf '%s\n' linux/loong64 ;;
        ppc64le) printf '%s\n' linux/ppc64le ;;
    esac
}

matrix_image()
{
    validate_matrix_arch "$1" || return 1
    case $1 in
        loongarch64)
            printf '%s\n' 'docker.io/loongarch64/alpine:3.21@sha256:ba4698dc340db5079eea01b7ea3488452a9a1c3cb8aad11033ea2cc978f49ffc'
            ;;
        *)
            printf '%s\n' 'docker.io/library/alpine:3.24@sha256:28bd5fe8b56d1bd048e5babf5b10710ebe0bae67db86916198a6eec434943f8b'
            ;;
    esac
}

matrix_build_mode()
{
    validate_matrix_arch "$1" || return 1
    case $1 in
        ppc64) printf '%s\n' cross-musl ;;
        *) printf '%s\n' native-emulated ;;
    esac
}

elf_machine()
{
    validate_matrix_arch "$1" || return 1
    case $1 in
        x86_64) printf '%s\n' 'Advanced Micro Devices X86-64' ;;
        aarch64) printf '%s\n' AArch64 ;;
        riscv64) printf '%s\n' RISC-V ;;
        loongarch64) printf '%s\n' LoongArch ;;
        ppc64|ppc64le) printf '%s\n' PowerPC64 ;;
    esac
}

elf_endian()
{
    validate_matrix_arch "$1" || return 1
    case $1 in
        ppc64) printf '%s\n' big ;;
        *) printf '%s\n' little ;;
    esac
}

qemu_command()
{
    validate_matrix_arch "$1" || return 1
    host_arch=${HOST_ARCH:-$(uname -m)}
    case $host_arch in
        amd64) host_arch=x86_64 ;;
        arm64) host_arch=aarch64 ;;
        loong64) host_arch=loongarch64 ;;
    esac
    if [ "$host_arch" = "$1" ]; then
        printf '%s\n' native
        return
    fi
    case $1 in
        x86_64) printf '%s\n' qemu-x86_64-static ;;
        aarch64) printf '%s\n' qemu-aarch64-static ;;
        riscv64) printf '%s\n' qemu-riscv64-static ;;
        loongarch64) printf '%s\n' qemu-loongarch64-static ;;
        ppc64) printf '%s\n' qemu-ppc64-static ;;
        ppc64le) printf '%s\n' qemu-ppc64le-static ;;
    esac
}

expected_artifacts()
{
    validate_matrix_arch "$1" || return 1
    printf 'mksquashfs-%s\nunsquashfs-%s\n' "$1" "$1"
}

expected_artifact_manifest()
{
    printf '%s\n' \
        mksquashfs-aarch64 \
        mksquashfs-loongarch64 \
        mksquashfs-ppc64 \
        mksquashfs-ppc64le \
        mksquashfs-riscv64 \
        mksquashfs-x86_64 \
        unsquashfs-aarch64 \
        unsquashfs-loongarch64 \
        unsquashfs-ppc64 \
        unsquashfs-ppc64le \
        unsquashfs-riscv64 \
        unsquashfs-x86_64
}
