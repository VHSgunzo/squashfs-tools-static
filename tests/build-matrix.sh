#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
FAKE_DOCKER=$TMP/docker
CAPTURE=$TMP/capture
FIXTURE_ROOT=$TMP/project
mkdir -p "$FIXTURE_ROOT/lib" "$FIXTURE_ROOT/scripts" "$FIXTURE_ROOT/release"
cp "$ROOT/lib/matrix.sh" "$FIXTURE_ROOT/lib/matrix.sh"
cp "$ROOT/scripts/build-matrix.sh" "$FIXTURE_ROOT/scripts/build-matrix.sh"
MATRIX_SCRIPT=$FIXTURE_ROOT/scripts/build-matrix.sh
cat >"$FAKE_DOCKER" <<'EOF'
#!/bin/sh
for arg do printf '<%s>\n' "$arg"; done >>"$DOCKER_CAPTURE"
EOF
chmod +x "$FAKE_DOCKER"

fail()
{
    printf 'not ok - %s\n' "$1" >&2
    exit 1
}

: >"$CAPTURE"
DOCKER="$FAKE_DOCKER" DOCKER_CAPTURE="$CAPTURE" "$MATRIX_SCRIPT" ppc64
for expected in \
    '<run>' '<--rm>' '<--platform>' '<linux/amd64>' '<-e>' '<TARGET_ARCH=ppc64>' \
    '<docker.io/library/alpine:3.22@sha256:14358309a308569c32bdc37e2e0e9694be33a9d99e68afb0f5ff33cc1f695dce>' \
    '<./scripts/build-ppc64.sh>'
do
    grep -Fx "$expected" "$CAPTURE" >/dev/null || fail "ppc64 invocation missing $expected"
done
printf 'ok - ppc64 uses explicit pinned cross path\n'

: >"$CAPTURE"
DOCKER="$FAKE_DOCKER" DOCKER_CAPTURE="$CAPTURE" "$MATRIX_SCRIPT" loongarch64
grep -Fx '<linux/loong64>' "$CAPTURE" >/dev/null || fail 'loongarch64 platform'
grep -Fx '<docker.io/loongarch64/alpine:3.21@sha256:ba4698dc340db5079eea01b7ea3488452a9a1c3cb8aad11033ea2cc978f49ffc>' "$CAPTURE" >/dev/null || fail 'loongarch64 pinned image'
grep -Fx '<./build.sh>' "$CAPTURE" >/dev/null || fail 'loongarch64 native/emulated entrypoint'
printf 'ok - loongarch64 uses digest-pinned image\n'

PRESERVED=$FIXTURE_ROOT/release/mksquashfs-x86_64
printf '%s\n' 'unrelated fixture' >"$PRESERVED"
cp "$PRESERVED" "$TMP/preserved-before"
: >"$CAPTURE"
DOCKER="$FAKE_DOCKER" DOCKER_CAPTURE="$CAPTURE" "$MATRIX_SCRIPT" all
[ "$(grep -c '^<run>$' "$CAPTURE")" -eq 6 ] || fail 'all did not invoke six builds'
cmp -s "$PRESERVED" "$TMP/preserved-before" || fail 'orchestrator changed an unrelated output'
printf 'ok - all invokes six builds without deleting unrelated outputs\n'

: >"$CAPTURE"
if error=$(DOCKER="$FAKE_DOCKER" DOCKER_CAPTURE="$CAPTURE" "$MATRIX_SCRIPT" invalid 2>&1); then
    fail 'invalid architecture should fail'
fi
case $error in
    *"unsupported architecture 'invalid'"*) ;;
    *) fail "invalid architecture diagnostic: $error" ;;
esac
[ ! -s "$CAPTURE" ] || fail 'invalid architecture invoked docker'
printf 'ok - invalid architecture fails before docker\n'
