#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
FIXTURE=$TMP/project
mkdir -p "$FIXTURE/lib" "$FIXTURE/scripts" "$FIXTURE/release" "$TMP/snapshot"
cp "$ROOT/lib/matrix.sh" "$FIXTURE/lib/matrix.sh"
cp "$ROOT/scripts/smoke-test.sh" "$FIXTURE/scripts/smoke-test.sh"

cat >"$FIXTURE/scripts/validate-artifacts.sh" <<'EOF'
#!/bin/sh
set -eu
[ "$1" = x86_64 ]
[ -x "$RELEASE_DIR/mksquashfs-x86_64" ]
[ -x "$RELEASE_DIR/unsquashfs-x86_64" ]
EOF

cat >"$FIXTURE/release/mksquashfs-x86_64" <<'EOF'
#!/bin/sh
set -eu
[ "${1:-}" = -version ] && exit 0
cp -a "$1/." "$FAKE_SOURCE_SNAPSHOT/"
: >"$2"
EOF

cat >"$FIXTURE/release/unsquashfs-x86_64" <<'EOF'
#!/bin/sh
set -eu
if [ "${1:-}" = -version ]; then
    printf '%s\n' 'unsquashfs version 4.7.5 (fixture)'
    exit 1
fi
while [ "$#" -gt 0 ]; do
    if [ "$1" = -d ]; then
        output=$2
        break
    fi
    shift
done
mkdir -p "$output"
cp -a "$FAKE_SOURCE_SNAPSHOT/." "$output/"
EOF
chmod +x "$FIXTURE/scripts/smoke-test.sh" "$FIXTURE/scripts/validate-artifacts.sh" \
    "$FIXTURE/release/mksquashfs-x86_64" "$FIXTURE/release/unsquashfs-x86_64"

output=$(HOST_ARCH=x86_64 FAKE_SOURCE_SNAPSHOT="$TMP/snapshot" \
    RELEASE_DIR="$FIXTURE/release" "$FIXTURE/scripts/smoke-test.sh" x86_64)
case $output in
    *'round trip passed for x86_64'*) ;;
    *)
        printf 'not ok - smoke-test orchestration did not report success:\n%s\n' "$output" >&2
        exit 1
        ;;
esac
printf '%s\n' 'ok - smoke-test orchestration contract passes with isolated fixture tools'
