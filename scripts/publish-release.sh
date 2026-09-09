#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck source=../lib/matrix.sh
. "$ROOT/lib/matrix.sh"

GH=${GH:-gh}
tag=${1:-}
RELEASE_DIR=${RELEASE_DIR:-$ROOT/release}
repository=${GITHUB_REPOSITORY:-}

[ "$#" -eq 1 ] && [ -n "$tag" ] || {
    printf 'usage: %s TAG\n' "$0" >&2
    exit 2
}
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
created=false
release_id=
cleanup()
{
    result=$?
    trap - EXIT HUP INT TERM
    if [ "$result" -ne 0 ] && [ "$created" = true ]; then
        if [ -n "$release_id" ]; then
            cleanup_tab=$(printf '\t')
            if cleanup_data=$("$GH" api "repos/$repository/releases/$release_id" \
                --jq '[.id, .draft] | @tsv'); then
                if [ "$cleanup_data" = "$release_id${cleanup_tab}true" ]; then
                    if ! "$GH" api --method DELETE "repos/$repository/releases/$release_id"; then
                        printf 'warning: failed to delete confirmed new draft release %s\n' \
                            "$release_id" >&2
                    fi
                else
                    printf 'warning: release %s is not a confirmed matching draft; leaving it for manual inspection\n' \
                        "$release_id" >&2
                fi
            else
                printf 'warning: failed to read release %s state; leaving it for manual inspection\n' \
                    "$release_id" >&2
            fi
        else
            printf '%s\n' 'warning: new release may remain; its id could not be read' >&2
        fi
    fi
    rm -f "$headers_file" "$error_file"
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

# A missing tag release is assembled privately. Published releases are never
# modified: failures below delete this newly-created release by id only after
# a fresh API read confirms that the same release is still a draft.
"$GH" release create --draft --verify-tag --title "$tag" -- "$tag"
created=true
release_data=$("$GH" api "$release_endpoint" --jq '[.id, .draft] | @tsv')
tab=$(printf '\t')
release_id=${release_data%%"$tab"*}
release_draft=${release_data#*"$tab"}
case $release_id in
    ''|*[!0-9]*)
        printf 'invalid new draft metadata: %s\n' "$release_data" >&2
        exit 1
        ;;
esac
if [ "$release_draft" != true ]; then
    printf '%s\n' 'new release was not created as a draft; refusing upload' >&2
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

"$GH" api --method PATCH "repos/$repository/releases/$release_id" \
    -f draft=false --silent

release_data=$("$GH" api "$release_endpoint" --jq '[.id, .draft] | @tsv')
verified_id=${release_data%%"$tab"*}
verified_draft=${release_data#*"$tab"}
if [ "$verified_id" != "$release_id" ] || [ "$verified_draft" != false ]; then
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
