#!/bin/sh
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck source=../lib/matrix.sh
. "$ROOT/lib/matrix.sh"

GH=${GH:-gh}
tag=${1:-}
RELEASE_DIR=${RELEASE_DIR:-$ROOT/release}
repository=${GITHUB_REPOSITORY:-}

if [ "$#" -ne 1 ] || [ -z "$tag" ]; then
    printf 'usage: %s TAG\n' "$0" >&2
    exit 2
fi
[ -n "$repository" ] || {
    printf '%s\n' 'GITHUB_REPOSITORY is required' >&2
    exit 2
}

expected=$(expected_artifact_manifest)
actual_local=$(
    for artifact in "$RELEASE_DIR"/*
    do
        [ -f "$artifact" ] || continue
        basename "$artifact"
    done | LC_ALL=C sort
)
if [ "$actual_local" != "$expected" ]; then
    printf '%s\n' 'local release artifact manifest mismatch' >&2
    printf 'expected:\n%s\nactual:\n%s\n' "$expected" "$actual_local" >&2
    exit 1
fi

headers_file=$(mktemp)
error_file=$(mktemp)
drafts_file=$(mktemp)
creation_attempted=false
publication_known=false
release_id=
ownership_marker=${RELEASE_OWNERSHIP_MARKER:-}
if [ -z "$ownership_marker" ]; then
    [ -r /proc/sys/kernel/random/uuid ] || {
        printf '%s\n' 'cannot generate a release ownership marker' >&2
        exit 1
    }
    IFS= read -r ownership_nonce </proc/sys/kernel/random/uuid
    ownership_marker=squashfs-tools-static-release-owner:$ownership_nonce
fi
ownership_marker_base64=$(printf '%s' "$ownership_marker" | base64 | tr -d '\n')
tag_base64=$(printf '%s' "$tag" | base64 | tr -d '\n')
tab=$(printf '\t')

# gh applies --jq separately to each response page in --paginate mode, so the
# query iterates one page array rather than a slurped outer array.
load_draft_releases()
{
    "$GH" api --paginate "repos/$repository/releases?per_page=100" \
        --jq '.[] | select(.draft == true) | [.id, (.tag_name | @base64), ((.body // "") | @base64)] | @tsv' \
        >"$drafts_file"
}

count_tag_drafts()
{
    draft_count=0
    while IFS="$tab" read -r candidate_id candidate_tag_base64 candidate_body_base64 candidate_extra
    do
        [ -n "$candidate_id$candidate_tag_base64$candidate_body_base64$candidate_extra" ] || continue
        if [ "$candidate_tag_base64" = "$tag_base64" ]; then
            draft_count=$((draft_count + 1))
        fi
    done <"$drafts_file"
    printf '%s\n' "$draft_count"
}

owned_draft_id()
{
    owned_count=0
    owned_id=
    owned_invalid=false
    while IFS="$tab" read -r candidate_id candidate_tag_base64 candidate_body_base64 candidate_extra
    do
        [ -n "$candidate_id$candidate_tag_base64$candidate_body_base64$candidate_extra" ] || continue
        if [ "$candidate_tag_base64" = "$tag_base64" ] && \
            [ "$candidate_body_base64" = "$ownership_marker_base64" ]; then
            owned_count=$((owned_count + 1))
            owned_id=$candidate_id
            case $candidate_id in
                ''|*[!0-9]*) owned_invalid=true ;;
            esac
            [ -z "$candidate_extra" ] || owned_invalid=true
        fi
    done <"$drafts_file"

    [ "$owned_count" -eq 1 ] || return 1
    [ "$owned_invalid" = false ] || return 2
    printf '%s\n' "$owned_id"
}

cleanup()
{
    result=$?
    trap - EXIT HUP INT TERM
    if [ "$result" -ne 0 ] && [ "$creation_attempted" = true ] && [ "$publication_known" != true ]; then
        cleanup_tab=$(printf '\t')
        cleanup_lookup_ok=true
        if [ -n "$release_id" ]; then
            cleanup_endpoint="repos/$repository/releases/$release_id"
            cleanup_subject="release $release_id"
        else
            cleanup_subject="requested tag release $tag"
            if load_draft_releases && cleanup_id=$(owned_draft_id); then
                cleanup_endpoint="repos/$repository/releases/$cleanup_id"
            else
                cleanup_lookup_ok=false
            fi
        fi
        if [ "$cleanup_lookup_ok" = true ] && cleanup_data=$("$GH" api "$cleanup_endpoint" \
            --jq '[.id, .draft, .tag_name, (.body | @base64)] | @tsv'); then
            cleanup_id=${cleanup_data%%"$cleanup_tab"*}
            cleanup_rest=${cleanup_data#*"$cleanup_tab"}
            cleanup_draft=${cleanup_rest%%"$cleanup_tab"*}
            cleanup_rest_after_draft=${cleanup_rest#*"$cleanup_tab"}
            cleanup_tag=${cleanup_rest_after_draft%%"$cleanup_tab"*}
            cleanup_body_base64=${cleanup_rest_after_draft#*"$cleanup_tab"}
            cleanup_confirmed=true
            case $cleanup_id in
                ''|*[!0-9]*) cleanup_confirmed=false ;;
            esac
            [ "$cleanup_rest" != "$cleanup_data" ] || cleanup_confirmed=false
            [ "$cleanup_rest_after_draft" != "$cleanup_rest" ] || cleanup_confirmed=false
            [ "$cleanup_body_base64" != "$cleanup_rest_after_draft" ] || cleanup_confirmed=false
            [ "$cleanup_draft" = true ] || cleanup_confirmed=false
            [ "$cleanup_tag" = "$tag" ] || cleanup_confirmed=false
            [ "$cleanup_body_base64" = "$ownership_marker_base64" ] || cleanup_confirmed=false
            if [ -n "$release_id" ] && [ "$cleanup_id" != "$release_id" ]; then
                cleanup_confirmed=false
            fi
            if [ "$cleanup_confirmed" = true ]; then
                if ! "$GH" api --method DELETE "repos/$repository/releases/$cleanup_id"; then
                    printf 'warning: failed to delete confirmed new draft release %s\n' \
                        "$cleanup_id" >&2
                fi
            else
                printf 'warning: %s is not a confirmed matching draft; leaving it for manual inspection\n' \
                    "$cleanup_subject" >&2
            fi
        else
            if [ "$cleanup_lookup_ok" = true ]; then
                printf 'warning: failed to read %s state; leaving it for manual inspection\n' \
                    "$cleanup_subject" >&2
            else
                printf 'warning: could not identify exactly one owned draft for %s; leaving drafts for manual inspection\n' \
                    "$tag" >&2
            fi
        fi
    fi
    rm -f "$headers_file" "$error_file" "$drafts_file"
    exit "$result"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

release_endpoint="repos/$repository/releases/tags/$tag"
: >"$headers_file"
: >"$error_file"
if "$GH" api --include --silent "$release_endpoint" >"$headers_file" 2>"$error_file"; then
    api_result=0
else
    api_result=$?
fi
http_status=
if IFS=' ' read -r _http_version http_status _reason <"$headers_file"; then
    http_status=$(printf '%s' "$http_status" | tr -d '\r')
fi

case $http_status in
    200)
        [ "$api_result" -eq 0 ] || {
            printf '%s\n' 'release lookup returned HTTP 200 with a failed gh command' >&2
            cat "$error_file" >&2
            exit 1
        }
        release_data=$("$GH" api "$release_endpoint" --jq '[.id, .draft] | @tsv')
        tab=$(printf '\t')
        release_id=${release_data%%"$tab"*}
        release_draft=${release_data#*"$tab"}
        case $release_id in
            ''|*[!0-9]*)
                printf 'invalid release metadata: %s\n' "$release_data" >&2
                exit 1
                ;;
        esac
        if [ "$release_draft" != false ]; then
            printf '%s\n' 'existing tag release is not a published immutable release' >&2
            exit 1
        fi
        remote=$("$GH" api --paginate "repos/$repository/releases/$release_id/assets" \
            --jq '.[].name' | LC_ALL=C sort)
        if [ "$remote" != "$expected" ]; then
            printf '%s\n' 'existing release asset manifest mismatch; refusing to mutate published release' >&2
            printf 'expected:\n%s\nactual:\n%s\n' "$expected" "$remote" >&2
            exit 1
        fi
        printf '= %s is already published with the exact 12-asset manifest; no changes made\n' "$tag"
        exit 0
        ;;
    404)
        [ "$api_result" -ne 0 ] || {
            printf '%s\n' 'release lookup returned HTTP 404 with a successful gh command' >&2
            exit 1
        }
        ;;
    *)
        printf 'release lookup did not return HTTP 200 or 404 (status: %s)\n' \
            "${http_status:-unknown}" >&2
        cat "$error_file" >&2
        exit 1
        ;;
esac

if ! load_draft_releases; then
    printf '%s\n' 'failed to list draft releases before creation; refusing to mutate releases' >&2
    exit 1
fi
tag_draft_count=$(count_tag_drafts)
if [ "$tag_draft_count" -ne 0 ]; then
    printf 'found %s existing draft release(s) for tag %s; refusing to create or adopt a draft; remove them manually after inspection\n' \
        "$tag_draft_count" "$tag" >&2
    exit 1
fi

# A missing tag release is assembled privately. Published releases are never
# modified: failures below delete only a freshly confirmed matching draft.
# Record intent before create because a signal can arrive after GitHub creates
# the draft but before the gh process returns its response.
creation_attempted=true
"$GH" release create --draft --verify-tag --title "$tag" --notes "$ownership_marker" -- "$tag"
if ! load_draft_releases; then
    printf '%s\n' 'failed to list draft releases after creation; refusing upload' >&2
    exit 1
fi
if release_id=$(owned_draft_id); then
    :
else
    owned_status=$?
    if [ "$owned_status" -eq 2 ]; then
        printf '%s\n' 'owned draft lookup returned a malformed numeric release id; refusing upload' >&2
    else
        printf '%s\n' 'owned draft lookup did not find exactly one exact tag and ownership marker match; refusing upload' >&2
    fi
    release_id=
    exit 1
fi

set --
for asset_name in $expected
do
    set -- "$@" "$RELEASE_DIR/$asset_name"
done
"$GH" release upload -- "$tag" "$@"

remote=$("$GH" api --paginate "repos/$repository/releases/$release_id/assets" \
    --jq '.[].name' | LC_ALL=C sort)
if [ "$remote" != "$expected" ]; then
    printf '%s\n' 'draft release asset manifest mismatch; refusing to publish' >&2
    printf 'expected:\n%s\nactual:\n%s\n' "$expected" "$remote" >&2
    exit 1
fi

printf '%s\n' '{"draft":false,"body":""}' | \
    "$GH" api --method PATCH "repos/$repository/releases/$release_id" \
        --input - --silent
publication_known=true

release_data=$("$GH" api "$release_endpoint" \
    --jq '[.id, .draft, (.body | @base64)] | @tsv')
verified_id=${release_data%%"$tab"*}
verified_rest=${release_data#*"$tab"}
verified_draft=${verified_rest%%"$tab"*}
verified_body_base64=${verified_rest#*"$tab"}
if [ "$verified_rest" = "$release_data" ] || \
    [ "$verified_body_base64" = "$verified_rest" ] || \
    [ "$verified_id" != "$release_id" ] || [ "$verified_draft" != false ] || \
    [ -n "$verified_body_base64" ]; then
    printf 'published release state verification failed: %s\n' "$release_data" >&2
    exit 1
fi
remote=$("$GH" api --paginate "repos/$repository/releases/$release_id/assets" \
    --jq '.[].name' | LC_ALL=C sort)
if [ "$remote" != "$expected" ]; then
    printf '%s\n' 'published release asset manifest verification failed' >&2
    printf 'expected:\n%s\nactual:\n%s\n' "$expected" "$remote" >&2
    exit 1
fi

printf '= published and verified %s with the exact 12-asset manifest\n' "$tag"
