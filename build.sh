#!/bin/sh
set -e
HERE="$(dirname "$(readlink -f "$0")")"
cd "$HERE"

# shellcheck source=lib/target.sh
. "$HERE/lib/target.sh"
# shellcheck source=lib/release.sh
. "$HERE/lib/release.sh"

resolve_target_contract || exit 1
validate_native_target || exit 1

SQUASHFS_TOOLS_VERSION=4.7.5

MIMALLOC_VERSION=2.1.7

XZ_VERSION=git              # 5.8.2
LZO_VERSION=git             # no tags
ZLIB_VERSION=git            # 1.3.2
LZ4_VERSION=git             # 1.10.0
ZSTD_VERSION=git            # 1.5.7
# NO_CLEANUP=1

HOST_PLATFORM=$(uname -s)
export MAKEFLAGS="${MAKEFLAGS:+$MAKEFLAGS }-j$(nproc)"

echo "= target ${TARGET_ARCH} (${TARGET_TRIPLET})"

if [ "$HOST_PLATFORM" = "Linux" ]
    then
        export CFLAGS="${CFLAGS:+$CFLAGS }-static"
        export LDFLAGS="${LDFLAGS:+$LDFLAGS }--static"
    else
        echo "= WARNING: your platform does not support static binaries."
        echo "= (This is mainly due to non-static libc availability.)"
        exit 1
fi

if command -v apk >/dev/null 2>&1
    then
        apk add musl-dev gcc clang git gettext-dev automake po4a \
            autoconf libtool help2man patch make zstd-dev lz4-dev \
            zlib-dev lzo-dev xz-dev sed findutils cmake g++
fi

if [ -d build ]
    then
        echo "= removing previous build directory"
        rm -rf build
fi

# if [ -d release ]
#     then
#         echo "= removing previous release directory"
#         rm -rf release
# fi

echo "= create build and release directories"
mkdir -p build release

echo "= removing previous ${TARGET_ARCH} release outputs"
rm -f "${HERE}"/release/*-"${TARGET_ARCH}" \
    "${HERE}"/release/*-"${TARGET_ARCH}"-upx

(cd build

export CFLAGS="$CFLAGS -Os -g0 -ffunction-sections -fdata-sections -fvisibility=hidden -fmerge-all-constants"
export LDFLAGS="$LDFLAGS -Wl,--gc-sections -Wl,--strip-all"
export CC="${CC:-gcc}"

echo "= build static deps"

echo "= build mimalloc lib"
(git clone https://github.com/microsoft/mimalloc.git && cd mimalloc
[ "$MIMALLOC_VERSION" = 'git' ] || git checkout "v$MIMALLOC_VERSION"
mkdir build && cd build
(export CFLAGS="$CFLAGS -D__USE_ISOC11"
cmake .. \
    -DCMAKE_BUILD_TYPE=Release \
    -DMI_BUILD_OBJECT=OFF \
    -DMI_BUILD_TESTS=OFF \
    -DMI_LIBC_MUSL=ON \
    -DMI_SECURE=OFF \
    -DMI_SKIP_COLLECT_ON_EXIT=ON && \
make mimalloc-static)
cp -fv libmimalloc.a /usr/lib/)

export CFLAGS="$CFLAGS -lmimalloc"

(echo "= build lzma lib"
(git clone https://git.tukaani.org/xz.git && cd xz
[ "$XZ_VERSION" = 'git' ] || git checkout "v$XZ_VERSION"
./autogen.sh
./configure --enable-static --disable-shared
make
cp -fv src/liblzma/.libs/liblzma.a /usr/lib/)

echo "= build lzo2 lib"
(git clone https://github.com/nemequ/lzo.git && cd lzo
[ "$LZO_VERSION" = 'git' ] || git checkout "$LZO_VERSION"
./configure --enable-static --disable-shared
make
cp -fv src/.libs/liblzo2.a /usr/lib/)

echo "= build zlib lib"
(git clone https://github.com/madler/zlib.git  && cd zlib
[ "$ZLIB_VERSION" = 'git' ] || git checkout "v$ZLIB_VERSION"
./configure
make libz.a
cp -fv libz.a /usr/lib/)

echo "= build lz4 lib"
(git clone https://github.com/lz4/lz4.git && cd lz4
[ "$LZ4_VERSION" = 'git' ] || git checkout "v$LZ4_VERSION"
make liblz4.a
cp -fv lib/liblz4.a /usr/lib/)

echo "= build zstd lib"
(git clone https://github.com/facebook/zstd.git && cd zstd/lib
[ "$ZSTD_VERSION" = 'git' ] || git checkout "v$ZSTD_VERSION"
make libzstd.a
cp -fv libzstd.a /usr/lib/))

echo "= download squashfs-tools"
squashfs_tools_dir="${HERE}/build/squashfs-tools-${SQUASHFS_TOOLS_VERSION}"
git clone https://github.com/plougher/squashfs-tools.git "$squashfs_tools_dir"
echo "= squashfs-tools v${SQUASHFS_TOOLS_VERSION}"

echo "= build squashfs-tools"
(cd "${squashfs_tools_dir}"/squashfs-tools
[ "$SQUASHFS_TOOLS_VERSION" = 'git' ] || git checkout "$SQUASHFS_TOOLS_VERSION"

# patch -p2<"${HERE}/musl.patch"
env XZ_SUPPORT=1 LZO_SUPPORT=1 LZ4_SUPPORT=1 ZSTD_SUPPORT=1 \
make INSTALL_DIR="${squashfs_tools_dir}/install" LDFLAGS="$LDFLAGS" install)

echo "= extracting squashfs-tools binaries"
for bin in "${squashfs_tools_dir}"/install/*
    do
        if [ ! -L "$bin" ] && [ -f "$bin" ]; then
            install_release_binary "$bin" "${HERE}/release" "$TARGET_ARCH"
        fi
done)

if [ "$NO_CLEANUP" != 1 ]
    then
        echo "= cleanup"
        rm -rfv build
fi

echo "= squashfs-tools done"
