#!/bin/sh
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
# shellcheck source=../lib/release.sh
. "$ROOT/lib/release.sh"

fail()
{
    printf 'not ok - %s\n' "$1" >&2
    exit 1
}

assert_pair()
{
    expected_first=$1
    expected_second=$2
    directory=$3
    [ "$(cat "$directory/first")" = "$expected_first" ] || fail "first artifact is not $expected_first"
    [ "$(cat "$directory/second")" = "$expected_second" ] || fail "second artifact is not $expected_second"
}

assert_no_transaction_files()
{
    directory=$1
    leftovers=$(find "$directory" -maxdepth 1 -type f \( -name '.*.tmp.*' -o -name '.*.backup.*' \) -print)
    [ -z "$leftovers" ] || fail "transaction files remain: $leftovers"
}

mkdir "$TMP/release" "$TMP/built"
printf '%s\n' old-first >"$TMP/release/first"
printf '%s\n' old-second >"$TMP/release/second"
printf '%s\n' old-upx >"$TMP/release/first-upx"
printf '%s\n' old-upx >"$TMP/release/second-upx"
printf '%s\n' new-first >"$TMP/built/first"
if publish_release_pair "$TMP/built/first" first "$TMP/built/missing" second "$TMP/release"; then
    fail 'an incomplete built pair should not publish'
fi
assert_pair old-first old-second "$TMP/release"
if [ ! -e "$TMP/release/first-upx" ] || [ ! -e "$TMP/release/second-upx" ]; then
    fail 'failed build/publish removed stale UPX outputs'
fi
assert_no_transaction_files "$TMP/release"
printf '%s\n' 'ok - failure before publication preserves the old pair'

printf '%s\n' new-second >"$TMP/built/second"
cat >"$TMP/failing-mv" <<'EOF'
#!/bin/sh
set -eu
case ${3:-} in
    */second) exit 71 ;;
esac
exec mv "$@"
EOF
chmod +x "$TMP/failing-mv"
if (
    RELEASE_MV=$TMP/failing-mv
    export RELEASE_MV
    publish_release_pair "$TMP/built/first" first "$TMP/built/second" second "$TMP/release"
); then
    fail 'injected second rename failure should fail'
fi
assert_pair old-first old-second "$TMP/release"
assert_no_transaction_files "$TMP/release"
printf '%s\n' 'ok - second rename failure restores the complete old pair'

publish_release_pair "$TMP/built/first" first "$TMP/built/second" second "$TMP/release" ||
    fail 'valid pair publication failed'
assert_pair new-first new-second "$TMP/release"
assert_no_transaction_files "$TMP/release"
printf '%s\n' 'ok - successful publication replaces the complete pair'

printf '%s\n' old-first >"$TMP/release/first"
printf '%s\n' old-second >"$TMP/release/second"
cat >"$TMP/signal-hook" <<'EOF'
#!/bin/sh
set -eu
kill -TERM "$TRANSACTION_PID"
EOF
chmod +x "$TMP/signal-hook"
cat >"$TMP/run-signalled" <<'EOF'
#!/bin/sh
set -eu
. "$TEST_ROOT/lib/release.sh"
RELEASE_AFTER_FIRST_RENAME=$SIGNAL_HOOK \
    publish_release_pair "$BUILT/first" first "$BUILT/second" second "$RELEASE_DIR"
EOF
chmod +x "$TMP/run-signalled"
if TEST_ROOT="$ROOT" BUILT="$TMP/built" RELEASE_DIR="$TMP/release" SIGNAL_HOOK="$TMP/signal-hook" \
    "$TMP/run-signalled"; then
    fail 'injected signal should interrupt publication'
fi
assert_pair old-first old-second "$TMP/release"
assert_no_transaction_files "$TMP/release"
printf '%s\n' 'ok - signals roll back the pair and clean transaction files'

mkdir "$TMP/lock-project"
cp "$ROOT/build.sh" "$TMP/lock-project/build.sh"
cp -R "$ROOT/lib" "$ROOT/scripts" "$TMP/lock-project/"
mkdir "$TMP/lock-project/release" "$TMP/lock-bin"
cat >"$TMP/lock-bin/apk" <<'EOF'
#!/bin/sh
exit 0
EOF
cat >"$TMP/lock-bin/mkdir" <<'EOF'
#!/bin/sh
set -eu
case ${1:-} in
    *.lock)
        /usr/bin/mkdir "$@"
        kill "-$LOCK_SIGNAL" "$PPID"
        ;;
    *) exec /usr/bin/mkdir "$@" ;;
esac
EOF
cat >"$TMP/lock-signal-hook" <<'EOF'
#!/bin/sh
set -eu
kill "-$LOCK_SIGNAL" "$TARGET_LOCK_PID"
EOF
chmod +x "$TMP/lock-bin/apk" "$TMP/lock-bin/mkdir" "$TMP/lock-signal-hook"
for lock_signal in HUP INT TERM
do
    rm -rf "$TMP/lock-project/release/.build-x86_64.lock"
    set +e
    PATH="$TMP/lock-bin:$PATH" LOCK_SIGNAL=$lock_signal TARGET_ARCH=x86_64 \
        TARGET_LOCK_AFTER_ACQUIRE="$TMP/lock-signal-hook" \
        "$TMP/lock-project/build.sh" >"$TMP/lock-$lock_signal.out" 2>"$TMP/lock-$lock_signal.err"
    lock_result=$?
    set -e
    [ "$lock_result" -ne 0 ] || fail "$lock_signal during lock acquisition did not stop the build"
    [ ! -e "$TMP/lock-project/release/.build-x86_64.lock" ] ||
        fail "$lock_signal during lock acquisition left an orphan lock"
done
printf '%s\n' 'ok - handled HUP INT TERM during lock acquisition leave no orphan lock'

cat >"$TMP/run-lock-interval" <<'EOF'
#!/bin/sh
set -eu
. "$TEST_ROOT/lib/release.sh"
lock_owner=$$
cleanup_lock_interval()
{
    result=$?
    trap - EXIT HUP INT TERM
    release_target_lock "$LOCK_PATH" "$lock_owner"
    exit "$result"
}
trap cleanup_lock_interval EXIT
trap 'exit 1' HUP INT TERM
acquire_target_lock "$LOCK_PATH" "$lock_owner"
EOF
cat >"$TMP/lock-interval-hook" <<'EOF'
#!/bin/sh
set -eu
: >"$HOOK_CALLED"
kill "-$LOCK_SIGNAL" "$TARGET_LOCK_PID"
EOF
chmod +x "$TMP/run-lock-interval" "$TMP/lock-interval-hook"
for lock_interval in \
    TARGET_LOCK_AFTER_PRIVATE_CREATE \
    TARGET_LOCK_AFTER_PRIVATE_WRITE \
    TARGET_LOCK_AFTER_LINK \
    TARGET_LOCK_AFTER_ACQUIRE
do
    for lock_signal in HUP INT TERM
    do
        interval_lock=$TMP/release/.build-interval.lock
        hook_called=$TMP/hook-$lock_interval-$lock_signal
        rm -f "$interval_lock" "$hook_called" "$interval_lock".owner.*
        set +e
        env TEST_ROOT="$ROOT" LOCK_PATH="$interval_lock" LOCK_SIGNAL="$lock_signal" \
            HOOK_CALLED="$hook_called" TARGET_LOCK_AFTER_ACQUIRE= \
            "$lock_interval=$TMP/lock-interval-hook" "$TMP/run-lock-interval"
        interval_result=$?
        set -e
        [ "$interval_result" -ne 0 ] || fail "$lock_signal at $lock_interval did not interrupt acquisition"
        [ -e "$hook_called" ] || fail "$lock_interval was not exercised"
        [ ! -e "$interval_lock" ] || fail "$lock_signal at $lock_interval left a canonical lock"
        interval_private=$(find "$TMP/release" -maxdepth 1 -name '.build-interval.lock.owner.*' -print)
        [ -z "$interval_private" ] || fail "$lock_signal at $lock_interval left private lock file $interval_private"
    done
done
printf '%s\n' 'ok - every handled signal interval leaves no canonical or private lock file'

cat >"$TMP/install-competing-lock" <<'EOF'
#!/bin/sh
set -eu
printf '%s\n' 999999 >"$LOCK_PATH"
EOF
chmod +x "$TMP/install-competing-lock"
race_lock=$TMP/release/.build-race.lock
rm -f "$race_lock" "$race_lock".owner.*
if TARGET_LOCK_AFTER_PRIVATE_WRITE="$TMP/install-competing-lock" LOCK_PATH="$race_lock" \
    acquire_target_lock "$race_lock" 123456 2>"$TMP/lock-race-error"; then
    fail 'lock acquisition won after a competitor published the canonical lock first'
fi
[ "$(cat "$race_lock")" = 999999 ] || fail 'losing lock acquisition changed the competing owner lock'
race_private=$(find "$TMP/release" -maxdepth 1 -name '.build-race.lock.owner.*' -print)
[ -z "$race_private" ] || fail "losing lock acquisition left private lock file $race_private"
rm -f "$race_lock"
printf '%s\n' 'ok - atomic lock contention preserves the competing owner and removes private state'

lock_type_failures=
for lock_type in directory symlink-directory
do
    typed_lock=$TMP/release/.build-$lock_type.lock
    case $lock_type in
        directory)
            mkdir "$typed_lock"
            typed_lock_contents=$typed_lock
            typed_lock_target=
            ;;
        symlink-directory)
            typed_lock_contents=$TMP/$lock_type-contents
            mkdir "$typed_lock_contents"
            typed_lock_target=$typed_lock_contents
            ln -s "$typed_lock_target" "$typed_lock"
            ;;
    esac
    printf '%s\n' preserved >"$typed_lock_contents/marker"

    if acquire_target_lock "$typed_lock" 123456 2>"$TMP/lock-$lock_type-error"; then
        lock_type_failures="$lock_type_failures $lock_type acquisition unexpectedly succeeded;"
    fi
    [ "$(cat "$typed_lock_contents/marker")" = preserved ] ||
        lock_type_failures="$lock_type_failures $lock_type destination contents changed;"
    typed_nested=$(find "$typed_lock_contents" -mindepth 1 -maxdepth 1 ! -name marker -print)
    [ -z "$typed_nested" ] ||
        lock_type_failures="$lock_type_failures $lock_type destination gained nested entry $typed_nested;"
    typed_private=$(find "$TMP/release" -maxdepth 1 -name ".build-$lock_type.lock.owner.*" -print)
    [ -z "$typed_private" ] ||
        lock_type_failures="$lock_type_failures $lock_type acquisition left private lock file $typed_private;"
    case $lock_type in
        directory) [ -d "$typed_lock" ] && [ ! -L "$typed_lock" ] || lock_type_failures="$lock_type_failures directory destination changed type;" ;;
        symlink-directory) [ -L "$typed_lock" ] && [ "$(readlink "$typed_lock")" = "$typed_lock_target" ] || lock_type_failures="$lock_type_failures symlink-directory destination changed;" ;;
    esac
done
[ -z "$lock_type_failures" ] || fail "canonical lock path type rejection failed:$lock_type_failures"
printf '%s\n' 'ok - canonical directory lock paths are rejected without changing them or leaving private state'
printf '%s\n' 'ok - canonical symlink-directory lock paths are rejected without changing them or leaving private state'

printf '%s\n' 999999 >"$TMP/lock-project/release/.build-x86_64.lock"
set +e
PATH="$TMP/lock-bin:$PATH" TARGET_ARCH=x86_64 \
    "$TMP/lock-project/build.sh" >"$TMP/lock-contention.out" 2>"$TMP/lock-contention.err"
contention_result=$?
set -e
[ "$contention_result" -ne 0 ] || fail 'competing target lock did not stop the build'
[ "$(cat "$TMP/lock-project/release/.build-x86_64.lock")" = 999999 ] ||
    fail 'failed acquisition cleanup removed or changed another build owner lock'
rm -f "$TMP/lock-project/release/.build-x86_64.lock"
printf '%s\n' 'ok - failed lock contention leaves the competing owner lock unchanged'

lock=$TMP/release/.build-target.lock
acquire_target_lock "$lock" || fail 'first target lock acquisition failed'
if acquire_target_lock "$lock" 2>"$TMP/lock-error"; then
    fail 'second same-target lock acquisition should fail'
fi
grep -F 'target build is already locked' "$TMP/lock-error" >/dev/null ||
    fail 'same-target lock conflict lacks a clear diagnostic'
release_target_lock "$lock"
[ ! -e "$lock" ] || fail 'target lock was not released'
printf '%s\n' 'ok - same-target lock prevents concurrent publication work'
