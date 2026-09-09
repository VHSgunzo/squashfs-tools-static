#!/bin/sh
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

fail()
{
    printf 'not ok - %s\n' "$1" >&2
    exit 1
}

mkdir "$TMP/release"
# shellcheck source=../lib/matrix.sh
. "$ROOT/lib/matrix.sh"
for asset in $(expected_artifact_manifest)
do
    printf '%s\n' fixture >"$TMP/release/$asset"
done

grep -F 'Published releases are treated as immutable' "$ROOT/README.md" >/dev/null ||
    fail 'README does not document immutable release behavior'
grep -F 'Failures clean up only a freshly read draft whose ID, tag, draft state, and per-attempt ownership marker all match; a competing publisher draft is never deleted' "$ROOT/README.md" >/dev/null ||
    fail 'README does not document ownership-marked draft cleanup policy'
grep -F 'A failed or interrupted musl target build leaves its previously published pair unchanged' "$ROOT/README.md" >/dev/null ||
    fail 'README does not state rollback-safe pair publication semantics'
grep -F 'Same-target musl builds are serialized by a per-target lock' "$ROOT/README.md" >/dev/null ||
    fail 'README does not document same-target build locking'

cat >"$TMP/gh" <<'EOF'
#!/bin/sh
set -eu
printf '%s\n' "$*" >>"$GH_LOG"

emit_manifest()
{
    # shellcheck source=/dev/null
    . "$TEST_ROOT/lib/matrix.sh"
    expected_artifact_manifest
}

marker_base64=$(printf '%s' "$MARKER" | base64 | tr -d '\n')

case ${1:-} in
    api)
        shift
        case ${1:-} in
            --include)
                shift
                [ "${1:-}" = --silent ] || exit 90
                shift
                case $MODE in
                    existing-exact|existing-mismatch|invalid-metadata) status=200 ;;
                    # GitHub's get-by-tag endpoint does not expose drafts, even
                    # immediately after a successful draft creation.
                    *) status=404 ;;
                esac
                if [ "$status" = 200 ]; then
                    printf 'HTTP/2.0 200 OK\nContent-Type: application/json\n\n'
                    exit 0
                fi
                printf 'HTTP/2.0 404 Not Found\nContent-Type: application/json\n\n'
                exit 1
                ;;
            --paginate)
                shift
                if [ "${1:-}" = 'repos/example/project/releases?per_page=100' ]; then
                    endpoint=$1
                    shift
                    [ "$*" = '--jq .[] | select(.draft == true) | [.id, (.tag_name | @base64), ((.body // "") | @base64)] | @tsv' ] || exit 109
                    tag_base64=$(printf '%s' "$TAG" | base64 | tr -d '\n')
                    competitor_base64=$(printf '%s' 'different-prior-run-marker' | base64 | tr -d '\n')
                    if [ "$MODE" = prior-run-draft ]; then
                        printf '77\t%s\t%s\n' "$tag_base64" "$competitor_base64"
                    elif [ -e "$GH_STATE/created" ]; then
                        case $MODE in
                            competitor-create)
                                printf '77\t%s\t%s\n' "$tag_base64" "$competitor_base64"
                                ;;
                            multiple-owned)
                                printf '43\t%s\t%s\n44\t%s\t%s\n' \
                                    "$tag_base64" "$marker_base64" "$tag_base64" "$marker_base64"
                                ;;
                            malformed-owned)
                                printf 'not-a-number\t%s\t%s\n' "$tag_base64" "$marker_base64"
                                ;;
                            *)
                                printf '43\t%s\t%s\n' "$tag_base64" "$marker_base64"
                                ;;
                        esac
                    fi
                    exit 0
                fi
                case $1 in
                    */42/assets)
                        [ "$MODE" = existing-exact ] && emit_manifest || printf '%s\n' stale.bin
                        ;;
                    */43/assets)
                        [ -e "$GH_STATE/uploaded" ] && emit_manifest || :
                        ;;
                    *) exit 91 ;;
                esac
                ;;
            --method)
                method=$2
                endpoint=$3
                shift 3
                case "$method:$endpoint" in
                    PATCH:*/releases/43)
                        [ "$*" = '--input - --silent' ] || exit 92
                        [ "$(cat)" = '{"draft":false,"body":""}' ] || exit 105
                        [ -e "$GH_STATE/uploaded" ] || exit 93
                        : >"$GH_STATE/published"
                        : >"$GH_STATE/body-cleared"
                        [ "$MODE" != publish-response-lost ] || exit 45
                        ;;
                    DELETE:*/releases/43)
                        [ -e "$GH_STATE/created" ] || exit 94
                        if [ "$MODE" != publish-response-lost ]; then
                            [ ! -e "$GH_STATE/published" ] || exit 95
                        fi
                        : >"$GH_STATE/deleted"
                        rm -f "$GH_STATE/created"
                        ;;
                    DELETE:*/releases/77)
                        : >"$GH_STATE/deleted-competitor"
                        rm -f "$GH_STATE/created"
                        ;;
                    *) exit 96 ;;
                esac
                ;;
            *)
                endpoint=$1
                shift
                case "$endpoint:$*" in
                    */releases/tags/*:'--jq [.id, .draft] | @tsv')
                        case $MODE in
                            existing-exact|existing-mismatch) printf '42\tfalse\n' ;;
                            invalid-metadata) printf '\tfalse\n' ;;
                            *)
                                [ -e "$GH_STATE/created" ] || exit 97
                                if [ -e "$GH_STATE/published" ]; then
                                    printf '43\tfalse\n'
                                else
                                    printf '43\ttrue\n'
                                fi
                                ;;
                        esac
                        ;;
                    */releases/tags/*:'--jq [.id, .draft, .tag_name, (.body | @base64)] | @tsv')
                        # Contract assertion: drafts are never returned here.
                        [ -e "$GH_STATE/published" ] || exit 97
                        printf '43\tfalse\t%s\t\n' "$TAG"
                        ;;
                    */releases/43:'--jq [.id, .draft] | @tsv')
                        [ "$MODE" != state-read-fail ] || exit 46
                        [ -e "$GH_STATE/created" ] || exit 97
                        if [ -e "$GH_STATE/published" ]; then
                            printf '43\tfalse\n'
                        else
                            printf '43\ttrue\n'
                        fi
                        ;;
                    */releases/43:'--jq [.id, .draft, .tag_name, (.body | @base64)] | @tsv')
                        [ "$MODE" != state-read-fail ] || exit 46
                        [ -e "$GH_STATE/created" ] || exit 97
                        if [ -e "$GH_STATE/published" ]; then
                            printf '43\tfalse\t%s\t\n' "$TAG"
                        else
                            printf '43\ttrue\t%s\t%s\n' "$TAG" "$marker_base64"
                        fi
                        ;;
                    */releases/tags/*:'--jq [.id, .draft, (.body | @base64)] | @tsv')
                        [ -e "$GH_STATE/created" ] || exit 97
                        [ -e "$GH_STATE/published" ] || exit 106
                        [ -e "$GH_STATE/body-cleared" ] || exit 107
                        printf '43\tfalse\t\n'
                        ;;
                    *) exit 98 ;;
                esac
                ;;
        esac
        ;;
    release)
        shift
        case ${1:-} in
            create)
                shift
                [ "$*" = "--draft --verify-tag --title $TAG --notes $MARKER -- $TAG" ] || exit 99
                : >"$GH_STATE/created"
                if [ "$MODE" = competitor-create ]; then
                    : >"$GH_STATE/competitor"
                    exit 40
                fi
                : >"$GH_STATE/owned"
                if [ "$MODE" = create-response-signal ]; then
                    kill -TERM "$PPID"
                fi
                ;;
            upload)
                shift
                [ "${1:-}" = -- ] || exit 100
                shift
                [ "${1:-}" = "$TAG" ] || exit 101
                shift
                [ "$#" -eq 12 ] || exit 102
                case $MODE in
                    upload-fail|state-read-fail) exit 44 ;;
                esac
                : >"$GH_STATE/uploaded"
                ;;
            *) exit 103 ;;
        esac
        ;;
    *) exit 104 ;;
esac
EOF
chmod +x "$TMP/gh"

run_publish()
{
    mode=$1
    tag=$2
    state=$TMP/state-$mode
    log=$TMP/log-$mode
    mkdir "$state"
    : >"$log"
    marker=squashfs-tools-static-release-owner:test-marker-$mode
    set +e
    GH="$TMP/gh" GH_LOG="$log" GH_STATE="$state" MODE="$mode" TAG="$tag" MARKER="$marker" \
        RELEASE_OWNERSHIP_MARKER="$marker" \
        TEST_ROOT="$ROOT" GITHUB_REPOSITORY=example/project RELEASE_DIR="$TMP/release" \
        "$ROOT/scripts/publish-release.sh" "$tag" >"$TMP/out-$mode" 2>"$TMP/err-$mode"
    result=$?
    set -e
    RUN_STATE=$state
    RUN_LOG=$log
    RUN_RESULT=$result
    return "$result"
}

if run_publish existing-mismatch v1; then
    fail 'existing release with a stale manifest should fail'
fi
if grep -E 'release (create|upload)|api --method (DELETE|PATCH)' "$RUN_LOG" >/dev/null; then
    fail 'existing mismatched release was mutated'
fi
printf '%s\n' 'ok - existing mismatched release fails without mutation'

run_publish existing-exact v2 || fail 'existing exact release should succeed'
if grep -E 'release (create|upload)|api --method (DELETE|PATCH)' "$RUN_LOG" >/dev/null; then
    fail 'existing exact release was mutated instead of treated as a no-op'
fi
grep -F 'already published with the exact 12-asset manifest' "$TMP/out-existing-exact" >/dev/null ||
    fail 'existing exact release did not report a no-op'
printf '%s\n' 'ok - existing exact published release is a no-op'

if run_publish invalid-metadata v-invalid; then
    fail 'release metadata without a numeric id should fail'
fi
grep -F 'invalid release metadata' "$TMP/err-invalid-metadata" >/dev/null ||
    fail 'invalid release id did not produce a clear diagnostic'
if grep -E 'release (create|upload)|api --method (DELETE|PATCH)' "$RUN_LOG" >/dev/null; then
    fail 'invalid existing release metadata caused mutation'
fi
printf '%s\n' 'ok - malformed release metadata fails closed'

if run_publish prior-run-draft v-prior; then
    fail 'an existing exact-tag draft from another invocation should block creation'
fi
grep -F 'found 1 existing draft release(s) for tag v-prior' "$TMP/err-prior-run-draft" >/dev/null ||
    fail 'prior-run draft did not produce a clear manual-cleanup diagnostic'
if grep -E 'release (create|upload)|api --method (DELETE|PATCH)' "$RUN_LOG" >/dev/null; then
    fail 'prior-run draft was adopted or mutated'
fi
printf '%s\n' 'ok - prior-run exact-tag draft blocks creation without adoption or mutation'

run_publish missing-success -v3 || fail 'new release publication should succeed'
grep -F 'release create --draft --verify-tag --title -v3 --notes squashfs-tools-static-release-owner:test-marker-missing-success -- -v3' "$RUN_LOG" >/dev/null ||
    fail 'release was not created as a verified draft with a safe option separator'
grep -F 'release upload -- -v3 ' "$RUN_LOG" >/dev/null ||
    fail 'upload did not protect a dash-prefixed tag with an option separator'
if grep -F -- '--clobber' "$RUN_LOG" >/dev/null; then
    fail 'release upload used destructive clobbering'
fi
upload_line=$(grep -nF 'release upload -- -v3 ' "$RUN_LOG" | cut -d: -f1)
verify_line=$(grep -nF 'api --paginate repos/example/project/releases/43/assets --jq .[].name' "$RUN_LOG" | cut -d: -f1 | sed -n '1p')
publish_line=$(grep -nF 'api --method PATCH repos/example/project/releases/43 --input - --silent' "$RUN_LOG" | cut -d: -f1)
post_publish_line=$(grep -nF 'api repos/example/project/releases/tags/-v3 --jq [.id, .draft, (.body | @base64)] | @tsv' "$RUN_LOG" | cut -d: -f1)
grep -F 'api --paginate repos/example/project/releases?per_page=100 --jq .[] | select(.draft == true)' \
    "$RUN_LOG" >/dev/null || fail 'draft discovery did not list all paginated releases'
if grep -F 'api repos/example/project/releases/tags/-v3 --jq [.id, .draft, .tag_name' "$RUN_LOG" >/dev/null; then
    fail 'new draft was incorrectly read through the get-by-tag endpoint'
fi
[ "$upload_line" -lt "$verify_line" ] || fail 'draft was not verified after upload'
[ "$verify_line" -lt "$publish_line" ] || fail 'draft was published before exact manifest verification'
[ "$publish_line" -lt "$post_publish_line" ] || fail 'published release state was not read back'
[ -e "$RUN_STATE/published" ] || fail 'successful release remained a draft'
[ -e "$RUN_STATE/body-cleared" ] || fail 'successful release exposed its ownership marker'
[ ! -e "$RUN_STATE/deleted" ] || fail 'successful release draft was deleted'
printf '%s\n' 'ok - missing release stays draft until exact upload verification, then publishes'

if run_publish create-response-signal v-create-signal; then
    fail 'signal after server-side draft creation should interrupt publication'
fi
[ "$RUN_RESULT" -ne 0 ] || fail 'create-window signal did not preserve a failing status'
[ -e "$RUN_STATE/deleted" ] || fail 'create-window signal left a confirmed orphan draft'
grep -F 'api --paginate repos/example/project/releases?per_page=100 --jq .[] | select(.draft == true)' \
    "$RUN_LOG" >/dev/null || fail 'create-window signal cleanup did not rediscover the draft from the release list'
grep -F 'api repos/example/project/releases/43 --jq [.id, .draft, .tag_name, (.body | @base64)] | @tsv' \
    "$RUN_LOG" >/dev/null || fail 'create-window signal cleanup did not fresh-read the discovered numeric id'
grep -F 'api --method DELETE repos/example/project/releases/43' "$RUN_LOG" >/dev/null ||
    fail 'create-window signal cleanup did not delete the confirmed orphan by id'
set +e
rerun_marker=squashfs-tools-static-release-owner:test-marker-rerun
GH="$TMP/gh" GH_LOG="$RUN_LOG" GH_STATE="$RUN_STATE" MODE=missing-success TAG=v-create-signal MARKER="$rerun_marker" \
    RELEASE_OWNERSHIP_MARKER="$rerun_marker" \
    TEST_ROOT="$ROOT" GITHUB_REPOSITORY=example/project RELEASE_DIR="$TMP/release" \
    "$ROOT/scripts/publish-release.sh" v-create-signal \
    >"$TMP/out-create-signal-rerun" 2>"$TMP/err-create-signal-rerun"
rerun_result=$?
set -e
[ "$rerun_result" -eq 0 ] || fail 'rerun remained blocked after create-window signal cleanup'
printf '%s\n' 'ok - create-window signal fresh-reads and deletes only the confirmed orphan draft'

if run_publish competitor-create v-competitor; then
    fail 'a create lost to a competing publisher should fail'
fi
[ "$RUN_RESULT" -eq 40 ] || fail 'competing create did not preserve the create failure'
[ -e "$RUN_STATE/created" ] || fail 'competing draft was removed'
[ ! -e "$RUN_STATE/deleted-competitor" ] || fail 'cleanup deleted a competing publisher draft'
if grep -F 'api --method DELETE repos/example/project/releases/77' "$RUN_LOG" >/dev/null; then
    fail 'cleanup attempted to delete a competing publisher draft'
fi
printf '%s\n' 'ok - failed create never deletes a competing publisher draft'

if run_publish multiple-owned v-multiple; then
    fail 'multiple matching owned drafts should fail closed'
fi
[ ! -e "$RUN_STATE/deleted" ] || fail 'ambiguous matching drafts were deleted'
if grep -F 'api --method DELETE' "$RUN_LOG" >/dev/null; then
    fail 'cleanup attempted deletion after ambiguous draft discovery'
fi
grep -F 'did not find exactly one exact tag and ownership marker match' \
    "$TMP/err-multiple-owned" >/dev/null || fail 'multiple matching drafts lacked a clear diagnostic'
printf '%s\n' 'ok - multiple matching owned drafts fail closed without cleanup deletion'

if run_publish malformed-owned v-malformed-owned; then
    fail 'owned draft with malformed id should fail closed'
fi
if grep -F 'api --method DELETE' "$RUN_LOG" >/dev/null; then
    fail 'cleanup attempted deletion with a malformed draft id'
fi
grep -F 'malformed numeric release id' "$TMP/err-malformed-owned" >/dev/null ||
    fail 'malformed owned draft id lacked a clear diagnostic'
printf '%s\n' 'ok - malformed owned draft id fails closed without deletion'

if run_publish publish-response-lost v-lost; then
    fail 'publication with a lost PATCH response should report failure'
fi
[ "$RUN_RESULT" -eq 45 ] || fail 'cleanup did not preserve the failed PATCH exit status'
[ -e "$RUN_STATE/published" ] || fail 'lost PATCH response did not simulate server-side publication'
[ ! -e "$RUN_STATE/deleted" ] || fail 'cleanup deleted a release published by an ambiguously failed PATCH'
if grep -F 'api --method DELETE repos/example/project/releases/43' "$RUN_LOG" >/dev/null; then
    fail 'cleanup attempted to delete a release published by an ambiguously failed PATCH'
fi
printf '%s\n' 'ok - ambiguous PATCH failure leaves the server-published release intact'

if run_publish upload-fail v4; then
    fail 'upload failure should fail publication'
fi
[ -e "$RUN_STATE/deleted" ] || fail 'failed newly-created draft was not deleted'
[ ! -e "$RUN_STATE/published" ] || fail 'upload failure published a partial release'
if grep -F 'api --method PATCH' "$RUN_LOG" >/dev/null; then
    fail 'upload failure attempted to publish the draft'
fi
grep -F 'api --method DELETE repos/example/project/releases/43' "$RUN_LOG" >/dev/null ||
    fail 'cleanup did not delete the newly-created draft by release id'
printf '%s\n' 'ok - upload failure cannot publish and cleans up only the new draft'

if run_publish state-read-fail v5; then
    fail 'upload failure with failed cleanup state read should preserve the publication failure'
fi
[ "$RUN_RESULT" -eq 44 ] || fail 'cleanup state-read failure masked the upload exit status'
[ -e "$RUN_STATE/created" ] || fail 'state-read failure did not leave the new release intact'
[ ! -e "$RUN_STATE/deleted" ] || fail 'cleanup deleted a release whose state could not be read'
if grep -F 'api --method DELETE repos/example/project/releases/43' "$RUN_LOG" >/dev/null; then
    fail 'cleanup attempted deletion after its fresh release-state read failed'
fi
grep -F 'warning: failed to read release 43 state; leaving it for manual inspection' \
    "$TMP/err-state-read-fail" >/dev/null ||
    fail 'cleanup state-read failure did not emit a clear warning'
printf '%s\n' 'ok - cleanup state-read failure warns and leaves the release intact'
