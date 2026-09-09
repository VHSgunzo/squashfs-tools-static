#!/bin/sh

configure_build_environment()
{
    BUILD_ROOT=$1/build
    BUILD_PREFIX=$BUILD_ROOT/sysroot/$TARGET_ARCH

    CC=${CC:-gcc}
    CXX=${CXX:-g++}
    AR=${AR:-ar}
    RANLIB=${RANLIB:-ranlib}
    STRIP=${STRIP:-strip}
    BUILD_CC=${BUILD_CC:-cc}

    case ${BUILD_MODE:-native-emulated} in
        native-emulated)
            BUILD_TRIPLET=$TARGET_TRIPLET
            ;;
        cross-musl)
            command -v "$BUILD_CC" >/dev/null 2>&1 || {
                printf "required build compiler '%s' was not found\n" "$BUILD_CC" >&2
                return 1
            }
            BUILD_TRIPLET=$($BUILD_CC -dumpmachine) || {
                printf "could not query build compiler target from '%s'\n" "$BUILD_CC" >&2
                return 1
            }
            ;;
    esac

    CFLAGS="${CFLAGS:+$CFLAGS }-Os -g0 -ffunction-sections -fdata-sections -fvisibility=hidden -fmerge-all-constants -I$BUILD_PREFIX/include -static"
    CXXFLAGS="${CXXFLAGS:+$CXXFLAGS }$CFLAGS"
    CPPFLAGS="${CPPFLAGS:+$CPPFLAGS }-I$BUILD_PREFIX/include"
    LDFLAGS="${LDFLAGS:+$LDFLAGS }-L$BUILD_PREFIX/lib --static -Wl,--gc-sections -Wl,--strip-all"
    PKG_CONFIG_LIBDIR=$BUILD_PREFIX/lib/pkgconfig:$BUILD_PREFIX/share/pkgconfig
    PKG_CONFIG_PATH=

    export BUILD_ROOT BUILD_PREFIX CC CXX AR RANLIB STRIP BUILD_CC BUILD_TRIPLET
    export CFLAGS CXXFLAGS CPPFLAGS LDFLAGS PKG_CONFIG_LIBDIR PKG_CONFIG_PATH
}

validate_compiler_target()
{
    for compiler_tool in "$CC" "$CXX" "$AR" "$RANLIB"
    do
        command -v "$compiler_tool" >/dev/null 2>&1 || {
            printf "required target tool '%s' was not found\n" "$compiler_tool" >&2
            return 1
        }
    done

    if [ "${BUILD_MODE:-native-emulated}" = cross-musl ]; then
        compiler_target=$($CC -dumpmachine) || {
            printf "could not query compiler target from '%s'\n" "$CC" >&2
            return 1
        }
        if [ "$compiler_target" != "$TARGET_TRIPLET" ]; then
            printf "compiler target '%s' does not match '%s'\n" \
                "$compiler_target" "$TARGET_TRIPLET" >&2
            return 1
        fi
    fi
}
