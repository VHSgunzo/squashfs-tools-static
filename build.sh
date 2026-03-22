#!/bin/sh
set -e
HERE="$(dirname "$(readlink -f "$0")")"
cd "$HERE"

SQUASHFS_TOOLS_VERSION=4.7.5

MIMALLOC_VERSION=2.1.7

XZ_VERSION=git              # 5.8.2
LZO_VERSION=git             # no tags
ZLIB_VERSION=git            # 1.3.2
LZ4_VERSION=git             # 1.10.0
ZSTD_VERSION=git            # 1.5.7
SUPER_STRIP_VERSION=git     # 3.0a

WITH_UPX=1
VENDOR_UPX=1
UPX_VERSION=4.2.4

# NO_CLEANUP=1

platform="$(uname -s)"
platform_arch="$(uname -m)"
export MAKEFLAGS="-j$(nproc)"

if [ "$platform" == "Linux" ]
    then
        export CFLAGS="-static"
        export LDFLAGS='--static'
    else
        echo "= WARNING: your platform does not support static binaries."
        echo "= (This is mainly due to non-static libc availability.)"
        exit 1
fi

if [ -x "$(which apk 2>/dev/null)" ]
    then
        apk add musl-dev gcc clang git gettext-dev automake po4a \
            autoconf libtool upx help2man patch make zstd-dev lz4-dev \
            zlib-dev lzo-dev xz-dev sed findutils cmake g++
fi

if [ "$WITH_UPX" == 1 ]
    then
        if [[ "$VENDOR_UPX" == 1 || ! -x "$(which upx 2>/dev/null)" ]]
            then
                case "$platform_arch" in
                   x86_64) upx_arch=amd64 ;;
                   aarch64) upx_arch=arm64 ;;
                esac
                wget https://github.com/upx/upx/releases/download/v${UPX_VERSION}/upx-${UPX_VERSION}-${upx_arch}_linux.tar.xz
                tar xvf upx-${UPX_VERSION}-${upx_arch}_linux.tar.xz
                mv upx-${UPX_VERSION}-${upx_arch}_linux/upx /usr/bin/
                rm -rf upx-${UPX_VERSION}-${upx_arch}_linux*
        fi
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

echo "=  create build and release directory"
mkdir -p build
mkdir -p release

(cd build

export CFLAGS="$CFLAGS -Os -g0 -ffunction-sections -fdata-sections -fvisibility=hidden -fmerge-all-constants"
export LDFLAGS="$LDFLAGS -Wl,--gc-sections -Wl,--strip-all"
export CC=gcc

echo "= build static deps"

echo "= build mimalloc lib"
(git clone https://github.com/microsoft/mimalloc.git && cd mimalloc
[ "$MIMALLOC_VERSION" == 'git' ] || git checkout "v$MIMALLOC_VERSION"
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
[ "$XZ_VERSION" == 'git' ] || git checkout "v$XZ_VERSION"
./autogen.sh
./configure --enable-static --disable-shared
make
cp -fv src/liblzma/.libs/liblzma.a /usr/lib/)

echo "= build lzo2 lib"
(git clone https://github.com/nemequ/lzo.git && cd lzo
[ "$LZO_VERSION" == 'git' ] || git checkout "$LZO_VERSION"
./configure --enable-static --disable-shared
make
cp -fv src/.libs/liblzo2.a /usr/lib/)

echo "= build zlib lib"
(git clone https://github.com/madler/zlib.git  && cd zlib
[ "$ZLIB_VERSION" == 'git' ] || git checkout "v$ZLIB_VERSION"
./configure
make libz.a
cp -fv libz.a /usr/lib/)

echo "= build lz4 lib"
(git clone https://github.com/lz4/lz4.git && cd lz4
[ "$LZ4_VERSION" == 'git' ] || git checkout "v$LZ4_VERSION"
make liblz4.a
cp -fv lib/liblz4.a /usr/lib/)

echo "= build zstd lib"
(git clone https://github.com/facebook/zstd.git && cd zstd/lib
[ "$ZSTD_VERSION" == 'git' ] || git checkout "v$ZSTD_VERSION"
make libzstd.a
cp -fv libzstd.a /usr/lib/))

echo "= download squashfs-tools"
squashfs_tools_dir="${HERE}/build/squashfs-tools-${SQUASHFS_TOOLS_VERSION}"
git clone https://github.com/plougher/squashfs-tools.git "$squashfs_tools_dir"
echo "= squashfs-tools v${SQUASHFS_TOOLS_VERSION}"

echo "= build squashfs-tools"
(cd "${squashfs_tools_dir}"/squashfs-tools
[ "$SQUASHFS_TOOLS_VERSION" == 'git' ] || git checkout "$SQUASHFS_TOOLS_VERSION"

# patch -p2<"${HERE}/musl.patch"
env XZ_SUPPORT=1 LZO_SUPPORT=1 LZ4_SUPPORT=1 ZSTD_SUPPORT=1 \
make INSTALL_DIR="${squashfs_tools_dir}/install" LDFLAGS="$LDFLAGS" install)

echo "= extracting squashfs-tools binaries"
for bin in "${squashfs_tools_dir}"/install/*
    do [[ ! -L "$bin" && -f "$bin" ]] && \
        cp -fv "$bin" "${HERE}"/release/"$(basename "${bin}")-${platform_arch}"
done)

echo "= build super-strip"
(cd build && git clone https://github.com/aunali1/super-strip.git && cd super-strip
[ "$SUPER_STRIP_VERSION" == 'git' ] || git checkout "$SUPER_STRIP_VERSION"
make
cp -fv sstrip /usr/bin/)

echo "= super-strip release binaries"
sstrip release/*-"${platform_arch}"

if [[ "$WITH_UPX" == 1 && -x "$(which upx 2>/dev/null)" ]]
    then
        echo "= upx compressing"
        find release -name "*-${platform_arch}"|\
        xargs -I {} upx --force-overwrite {} -o {}-upx
fi

if [ "$NO_CLEANUP" != 1 ]
    then
        echo "= cleanup"
        rm -rfv build
fi

echo "= squashfs-tools done"
