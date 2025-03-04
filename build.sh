#!/bin/sh
set -e
HERE="$(dirname "$(readlink -f "$0")")"
cd "$HERE"

WITH_UPX=1
VENDOR_UPX=1

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
            zlib-dev lzo-dev xz-dev sed findutils mimalloc-dev cmake g++
fi

if [ "$WITH_UPX" == 1 ]
    then
        if [[ "$VENDOR_UPX" == 1 || ! -x "$(which upx 2>/dev/null)" ]]
            then
                upx_ver=4.2.4
                case "$platform_arch" in
                   x86_64) upx_arch=amd64 ;;
                   aarch64) upx_arch=arm64 ;;
                esac
                wget https://github.com/upx/upx/releases/download/v${upx_ver}/upx-${upx_ver}-${upx_arch}_linux.tar.xz
                tar xvf upx-${upx_ver}-${upx_arch}_linux.tar.xz
                mv upx-${upx_ver}-${upx_arch}_linux/upx /usr/bin/
                rm -rf upx-${upx_ver}-${upx_arch}_linux*
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
mkdir build && cd build
cmake .. && make mimalloc-static
mv -fv libmimalloc.a /usr/lib/)

export CFLAGS="$CFLAGS -lmimalloc"

(echo "= build lzma lib"
(git clone https://git.tukaani.org/xz.git && cd xz
./autogen.sh
./configure --enable-static --disable-shared
make
mv -fv src/liblzma/.libs/liblzma.a /usr/lib/)

echo "= build lzo2 lib"
(git clone https://github.com/nemequ/lzo.git && cd lzo
./configure --enable-static --disable-shared
make
mv -fv src/.libs/liblzo2.a /usr/lib/)

echo "= build zlib lib"
(git clone https://github.com/madler/zlib.git  && cd zlib
./configure
make libz.a
mv -fv libz.a /usr/lib/)

echo "= build lz4 lib"
(git clone https://github.com/lz4/lz4.git && cd lz4
make liblz4.a
mv -fv lib/liblz4.a /usr/lib/)

echo "= build zstd lib"
(git clone https://github.com/facebook/zstd.git && cd zstd/lib
make libzstd.a
mv -fv libzstd.a /usr/lib/))

echo "= download squashfs-tools"
git clone https://github.com/plougher/squashfs-tools.git
squashfuse_version="$(cd squashfs-tools && git describe --long --tags|sed 's/^v//;s/\([^-]*-g\)/r\1/;s/-/./g')"
squashfs_tools_dir="${HERE}/build/squashfs-tools-${squashfs_tools_version}"
mv "squashfs-tools" "${squashfs_tools_dir}"
echo "= squashfs-tools v${squashfs_tools_version}"

echo "= build squashfs-tools"
(cd "${squashfs_tools_dir}"/squashfs-tools
git checkout 4.6.1
# patch -p2<"${HERE}/musl.patch"
env XZ_SUPPORT=1 LZO_SUPPORT=1 LZ4_SUPPORT=1 ZSTD_SUPPORT=1 \
make INSTALL_DIR="${squashfs_tools_dir}/install" LDFLAGS="$LDFLAGS" install)

echo "= extracting squashfs-tools binaries"
for bin in "${squashfs_tools_dir}"/install/*
    do [[ ! -L "$bin" && -f "$bin" ]] && \
        mv -fv "$bin" "${HERE}"/release/"$(basename "${bin}")-${platform_arch}"
done)

echo "= build super-strip"
(cd build && git clone https://github.com/aunali1/super-strip.git && cd super-strip
make
mv -fv sstrip /usr/bin/)

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
