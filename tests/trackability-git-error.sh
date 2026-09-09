#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT HUP INT TERM
fakebin=$test_tmp/bin
output=$test_tmp/output
mkdir "$fakebin"
cat >"$fakebin/git" <<'EOF'
#!/bin/sh
printf '%s\n' 'simulated git operational error' >&2
exit 128
EOF
chmod +x "$fakebin/git"

if PATH="$fakebin:$PATH" sh "$ROOT/tests/target-contract.sh" >"$output" 2>&1; then
    printf '%s\n' 'not ok - git check-ignore exit 128 was accepted as trackable' >&2
    exit 1
fi
case $(cat "$output") in
    *"git check-ignore failed for lib/target.sh (exit 128)"*) ;;
    *)
        printf 'not ok - git operational error diagnostic was not clear:\n%s\n' \
            "$(cat "$output")" >&2
        exit 1
        ;;
esac
printf '%s\n' 'ok - git check-ignore operational errors reject the trackability check'
