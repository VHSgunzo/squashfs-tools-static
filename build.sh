#!/bin/sh
set -eu

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$HERE"

# shellcheck source=lib/target.sh
. "$HERE/lib/target.sh"
# shellcheck source=lib/release.sh
. "$HERE/lib/release.sh"
# shellcheck source=lib/build-env.sh
. "$HERE/lib/build-env.sh"
# shellcheck source=lib/source-pins.sh
. "$HERE/lib/source-pins.sh"

resolve_target_contract
validate_build_mode

SQUASHFS_TOOLS_VERSION=4.7.5
MIMALLOC_VERSION=2.1.7
# These commits are the upstream HEADs used by the existing six-architecture
# release build; the comments retain their logical upstream versions.
SQUASHFS_TOOLS_COMMIT=708c59ae80853b0845017c33b42e56061cc546cd # 4.7.5
MIMALLOC_COMMIT=8c532c32c3c96e5ba1f2283e032f69ead8add00f # 2.1.7
XZ_COMMIT=9fc6f5cd8774ebef8d4e030f7081fb6984c0dc3f   # 5.8.2
LZO_COMMIT=0083878c235a89ef96a009d1ff0b500f3a364e4b  # no tags
ZLIB_COMMIT=e3dc0a85b7032e98380dec011bc8f2c2ee0d8fca # 1.3.2
LZ4_COMMIT=0774d05537f9762f838f7ab541b7765f1a729cb5  # 1.10.0
ZSTD_COMMIT=d9c0c7e2cf8a8bf9fb98d3bee546dcf8dc9ac59a # 1.5.7
NO_CLEANUP=${NO_CLEANUP:-0}

[ "$(uname -s)" = Linux ] || {
    printf '%s\n' '= this build requires Linux for static binaries' >&2
    exit 1
}

if command -v apk >/dev/null 2>&1; then
    apk add --no-cache musl-dev gcc g++ clang git gettext-dev automake po4a \
        autoconf libtool help2man patch make zstd-dev lz4-dev zlib-dev \
        lzo-dev xz-dev sed findutils cmake linux-headers
fi
configure_build_environment "$HERE"
if [ "$BUILD_MODE" = cross-musl ]; then
    validate_compiler_target
fi
MAKEFLAGS="${MAKEFLAGS:+$MAKEFLAGS }-j$(nproc)"
export MAKEFLAGS

echo "= target ${TARGET_ARCH} (${TARGET_TRIPLET}, ${BUILD_MODE})"

if [ "$BUILD_MODE" = native-emulated ]; then
    validate_compiler_target
fi

work=$BUILD_ROOT/work-$TARGET_ARCH
mkdir -p "$HERE/release"
target_lock=$HERE/release/.build-$TARGET_ARCH.lock
target_lock_owner=$$
lock_acquired=false
lock_attempted=false
cleanup_target_build()
{
    result=$?
    trap - EXIT HUP INT TERM
    if [ "$lock_acquired" = true ]; then
        release_target_lock "$target_lock" "$target_lock_owner"
    elif [ "$lock_attempted" = true ]; then
        # Covers a signal after atomic lock creation but before acquisition returns.
        release_target_lock "$target_lock" "$target_lock_owner"
    fi
    exit "$result"
}
trap cleanup_target_build EXIT
trap 'exit 1' HUP INT TERM
lock_attempted=true
acquire_target_lock "$target_lock" "$target_lock_owner"
lock_acquired=true

echo "= reset target build workspace $work"
rm -rf "$work" "$BUILD_PREFIX"
staged_release=$work/release
mkdir -p "$staged_release" "$BUILD_PREFIX/include" "$BUILD_PREFIX/lib"

cd "$work"

echo '= build mimalloc static library'
git clone https://github.com/microsoft/mimalloc.git
(
    cd mimalloc
    checkout_pinned_source . "$MIMALLOC_COMMIT"
    cmake -S . -B build \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_C_COMPILER="$CC" \
        -DCMAKE_AR="$(command -v "$AR")" \
        -DCMAKE_RANLIB="$(command -v "$RANLIB")" \
        -DCMAKE_INSTALL_PREFIX="$BUILD_PREFIX" \
        -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
        -DMI_BUILD_OBJECT=OFF \
        -DMI_BUILD_SHARED=OFF \
        -DMI_BUILD_TESTS=OFF \
        -DMI_LIBC_MUSL=ON \
        -DMI_SECURE=OFF \
        -DMI_SKIP_COLLECT_ON_EXIT=ON
    cmake --build build --target mimalloc-static
    cp build/libmimalloc.a "$BUILD_PREFIX/lib/"
    cp -R include/. "$BUILD_PREFIX/include/"
)

echo '= build liblzma static library'
git clone https://git.tukaani.org/xz.git
(
    cd xz
    checkout_pinned_source . "$XZ_COMMIT"
    ./autogen.sh
    ./configure --build="$BUILD_TRIPLET" --host="$TARGET_TRIPLET" \
        --prefix="$BUILD_PREFIX" \
        --enable-static --disable-shared --disable-doc
    make
    make install
)

echo '= build lzo2 static library'
git clone https://github.com/nemequ/lzo.git
(
    cd lzo
    checkout_pinned_source . "$LZO_COMMIT"
    autoreconf -fi
    ./configure --build="$BUILD_TRIPLET" --host="$TARGET_TRIPLET" \
        --prefix="$BUILD_PREFIX" \
        --enable-static --disable-shared
    make
    make install
)

echo '= build zlib static library'
git clone https://github.com/madler/zlib.git
(
    cd zlib
    checkout_pinned_source . "$ZLIB_COMMIT"
    CHOST="$TARGET_TRIPLET" ./configure --static --prefix="$BUILD_PREFIX"
    make libz.a
    make install
)

echo '= build lz4 static library'
git clone https://github.com/lz4/lz4.git
(
    cd lz4
    checkout_pinned_source . "$LZ4_COMMIT"
    make -C lib CC="$CC" AR="$AR" RANLIB="$RANLIB" liblz4.a
    cp lib/liblz4.a "$BUILD_PREFIX/lib/"
    cp lib/lz4.h lib/lz4frame.h lib/lz4frame_static.h lib/lz4hc.h \
        "$BUILD_PREFIX/include/"
)

echo '= build zstd static library'
git clone https://github.com/facebook/zstd.git
(
    cd zstd
    checkout_pinned_source . "$ZSTD_COMMIT"
    make -C lib CC="$CC" AR="$AR" RANLIB="$RANLIB" libzstd.a
    cp lib/libzstd.a "$BUILD_PREFIX/lib/"
    cp lib/zstd.h lib/zdict.h lib/zstd_errors.h "$BUILD_PREFIX/include/"
)

echo "= build squashfs-tools v${SQUASHFS_TOOLS_VERSION}"
git clone https://github.com/plougher/squashfs-tools.git
(
    cd squashfs-tools
    checkout_pinned_source . "$SQUASHFS_TOOLS_COMMIT"
    cd squashfs-tools
    mimalloc_link="-Wl,--whole-archive,$BUILD_PREFIX/lib/libmimalloc.a,--no-whole-archive"
    make XZ_SUPPORT=1 LZO_SUPPORT=1 LZ4_SUPPORT=1 ZSTD_SUPPORT=1 \
        CC="$CC" EXTRA_CFLAGS="-I$BUILD_PREFIX/include" \
        LDFLAGS="$LDFLAGS" EXTRA_LDFLAGS="$mimalloc_link" \
        mksquashfs unsquashfs
    install_release_binary mksquashfs "$staged_release" "$TARGET_ARCH"
    install_release_binary unsquashfs "$staged_release" "$TARGET_ARCH"
)

RELEASE_DIR=$staged_release "$HERE/scripts/validate-artifacts.sh" "$TARGET_ARCH"
publish_release_pair \
    "$staged_release/mksquashfs-$TARGET_ARCH" "mksquashfs-$TARGET_ARCH" \
    "$staged_release/unsquashfs-$TARGET_ARCH" "unsquashfs-$TARGET_ARCH" \
    "$HERE/release"
rm -f "$HERE/release/mksquashfs-$TARGET_ARCH-upx" \
    "$HERE/release/unsquashfs-$TARGET_ARCH-upx"
"$HERE/scripts/validate-artifacts.sh" "$TARGET_ARCH"

if [ "$NO_CLEANUP" != 1 ]; then
    echo "= cleanup target workspace $work"
    rm -rf "$work" "$BUILD_PREFIX"
fi

echo '= squashfs-tools done'
