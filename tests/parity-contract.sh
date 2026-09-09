#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BUILD=$ROOT/build.sh
PATCH=$ROOT/patches/squashfs-tools-mimalloc.patch

fail()
{
    printf 'not ok - %s\n' "$1" >&2
    exit 1
}

grep -F -- '-I$BUILD_PREFIX/include -static-pie' "$ROOT/lib/build-env.sh" >/dev/null ||
    fail 'compile flags do not make static PIE explicit'
grep -F -- '-Wl,-static -static-pie -Wl,--gc-sections -Wl,--strip-all' "$ROOT/lib/build-env.sh" >/dev/null ||
    fail 'link flags do not preserve static linkage with explicit static PIE'
if grep -F -- '-I$BUILD_PREFIX/include -static -static-pie' "$ROOT/lib/build-env.sh" >/dev/null ||
   grep -F -- '-L$BUILD_PREFIX/lib --static -static-pie' "$ROOT/lib/build-env.sh" >/dev/null; then
    fail 'conflicting GCC -static and -static-pie driver modes break LoongArch executables'
fi

if grep -R -- '--whole-archive' "$BUILD" "$ROOT/lib" "$ROOT/scripts" "$ROOT/patches" 2>/dev/null; then
    fail 'mimalloc still uses whole-archive linkage'
fi
[ -r "$PATCH" ] || fail 'tracked squashfs-tools mimalloc patch is missing'
grep -F '+LIBS += -lmimalloc' "$PATCH" >/dev/null ||
    fail 'upstream Makefile patch does not append normal mimalloc linkage'
grep -F '+	$(CC) $(LDFLAGS) $(EXTRA_LDFLAGS) -Wl,-Map,$@.map,--cref $(MKSQUASHFS_OBJS) $(LIBS) -o $@' "$PATCH" >/dev/null ||
    fail 'mksquashfs final link does not emit a per-binary map and end with objects/libraries'
grep -F '+	$(CC) $(LDFLAGS) $(EXTRA_LDFLAGS) -Wl,-Map,$@.map,--cref $(UNSQUASHFS_OBJS) $(LIBS) -o $@' "$PATCH" >/dev/null ||
    fail 'unsquashfs final link does not emit a per-binary map and end with objects/libraries'
grep -F 'patch -p1 <"$HERE/patches/squashfs-tools-mimalloc.patch"' "$BUILD" >/dev/null ||
    fail 'build does not apply the tracked upstream Makefile patch'
grep -F 'validate-mimalloc-map.sh' "$BUILD" >/dev/null ||
    fail 'build does not prove normal mimalloc archive extraction and malloc resolution'

grep -F 'SUPER_STRIP_COMMIT=9c57e288d8b2e0f90c9a15a4223331d1e7b43515' "$BUILD" >/dev/null ||
    fail 'super-strip is not pinned to the audited commit'
grep -F 'make CC="$BUILD_CC" AR=ar RANLIB=ranlib' "$BUILD" >/dev/null ||
    fail 'sstrip is not built with the build/host compiler'
grep -F "CFLAGS='-O2 -Ielfrw' CPPFLAGS= LDFLAGS=" "$BUILD" >/dev/null ||
    fail 'host sstrip build leaks target flags or omits its private include path'
grep -F '"$sstrip" "$staged_release/mksquashfs-$TARGET_ARCH"' "$BUILD" >/dev/null ||
    fail 'staged mksquashfs is not sstripped'
grep -F '"$sstrip" "$staged_release/unsquashfs-$TARGET_ARCH"' "$BUILD" >/dev/null ||
    fail 'staged unsquashfs is not sstripped'

if grep -Ei '(^|[^[:alnum:]_])(WITH_UPX|VENDOR_UPX|UPX_VERSION|upx[[:space:]]+--force-overwrite)([^[:alnum:]_]|$)' "$BUILD"; then
    fail 'UPX build/post-processing returned'
fi

printf '%s\n' 'ok - legacy static-PIE, normal mimalloc, required sstrip, and no-UPX contract is explicit'