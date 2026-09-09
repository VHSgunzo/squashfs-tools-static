#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
PROJECT=$TMP/project
mkdir -p "$PROJECT/scripts" "$PROJECT/lib" "$TMP/archive/powerpc64-linux-musl-cross/bin"
cp "$ROOT/lib/ppc64-toolchain.sh" "$PROJECT/lib/ppc64-toolchain.sh"
for tool in gcc g++ ar ranlib strip
do
    printf '%s\n' '#!/bin/sh' 'exit 0' >"$TMP/archive/powerpc64-linux-musl-cross/bin/powerpc64-linux-musl-$tool"
    chmod +x "$TMP/archive/powerpc64-linux-musl-cross/bin/powerpc64-linux-musl-$tool"
done
tar -C "$TMP/archive" -czf "$TMP/toolchain.tgz" powerpc64-linux-musl-cross
checksum=$(sha256sum "$TMP/toolchain.tgz")
checksum=${checksum%% *}

cat >"$PROJECT/build.sh" <<'EOF'
#!/bin/sh
set -eu
{
    printf 'TARGET_ARCH=%s\n' "$TARGET_ARCH"
    printf 'BUILD_MODE=%s\n' "$BUILD_MODE"
    printf 'CC=%s\n' "$CC"
    printf 'CXX=%s\n' "$CXX"
    printf 'AR=%s\n' "$AR"
    printf 'RANLIB=%s\n' "$RANLIB"
    printf 'STRIP=%s\n' "$STRIP"
} >"$BOOTSTRAP_CAPTURE"
EOF
chmod +x "$PROJECT/build.sh"
cp "$ROOT/scripts/build-ppc64.sh" "$PROJECT/scripts/build-ppc64.sh"
chmod +x "$PROJECT/scripts/build-ppc64.sh"

BOOTSTRAP_CAPTURE=$TMP/capture \
PPC64_MUSL_TOOLCHAIN_ARCHIVE=$TMP/toolchain.tgz \
PPC64_MUSL_TOOLCHAIN_SHA256=$checksum \
TOOLCHAIN_PARENT=$TMP/toolchains \
"$PROJECT/scripts/build-ppc64.sh"

grep -Fx 'TARGET_ARCH=ppc64' "$TMP/capture" >/dev/null
grep -Fx 'BUILD_MODE=cross-musl' "$TMP/capture" >/dev/null
grep -F '/powerpc64-linux-musl-cross/bin/powerpc64-linux-musl-gcc' "$TMP/capture" >/dev/null
printf '%s\n' 'ok - bootstrap verifies archive and exports real ppc64 cross tools'

rm -f "$TMP/capture"
if error=$(BOOTSTRAP_CAPTURE=$TMP/capture \
    PPC64_MUSL_TOOLCHAIN_ARCHIVE=$TMP/toolchain.tgz \
    PPC64_MUSL_TOOLCHAIN_SHA256=0000000000000000000000000000000000000000000000000000000000000000 \
    TOOLCHAIN_PARENT=$TMP/bad-toolchains \
    "$PROJECT/scripts/build-ppc64.sh" 2>&1); then
    printf '%s\n' 'not ok - invalid toolchain checksum should fail' >&2
    exit 1
fi
case $error in
    *'toolchain checksum mismatch'*) ;;
    *) printf 'not ok - checksum diagnostic: %s\n' "$error" >&2; exit 1 ;;
esac
[ ! -e "$TMP/capture" ] || {
    printf '%s\n' 'not ok - invalid archive reached build.sh' >&2
    exit 1
}
printf '%s\n' 'ok - invalid toolchain archive is rejected before build'
