#!/bin/sh

resolve_target_arch()
{
    if [ -n "${TARGET_ARCH:-}" ]; then
        printf '%s\n' "$TARGET_ARCH"
    else
        uname -m
    fi
}

target_triplet()
{
    case $1 in
        x86_64)     printf '%s\n' x86_64-linux-musl ;;
        aarch64)    printf '%s\n' aarch64-linux-musl ;;
        riscv64)    printf '%s\n' riscv64-linux-musl ;;
        loongarch64) printf '%s\n' loongarch64-linux-musl ;;
        ppc64)      printf '%s\n' powerpc64-linux-musl ;;
        ppc64le)    printf '%s\n' powerpc64le-linux-musl ;;
        *)
            printf "unsupported TARGET_ARCH '%s' (supported: x86_64, aarch64, riscv64, loongarch64, ppc64, ppc64le)\n" "$1" >&2
            return 1
            ;;
    esac
}

resolve_target_contract()
{
    TARGET_ARCH=$(resolve_target_arch) || return 1
    TARGET_TRIPLET=$(target_triplet "$TARGET_ARCH") || return 1
    set -- "$TARGET_ARCH" "$TARGET_TRIPLET"

    # TARGET_ARCH commonly arrives exported by CI. Keep contract variables local
    # to this script so upstream Makefiles cannot reinterpret their names.
    unset TARGET_ARCH TARGET_TRIPLET
    TARGET_ARCH=$1
    TARGET_TRIPLET=$2
}

validate_native_target()
{
    set -- "$(uname -m)" "$TARGET_ARCH"
    if [ "$1" != "$2" ]; then
        printf "TARGET_ARCH '%s' does not match build machine '%s'; true cross builds require an explicit cross-toolchain mode (not yet supported)\n" \
            "$2" "$1" >&2
        return 1
    fi
}
