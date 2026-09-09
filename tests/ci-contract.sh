#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
WORKFLOW=$ROOT/.github/workflows/ci.yml

fail()
{
    printf 'not ok - %s\n' "$1" >&2
    exit 1
}

[ -r "$WORKFLOW" ] || fail 'CI workflow is missing'

grep -F 'workflow_dispatch:' "$WORKFLOW" >/dev/null || fail 'workflow_dispatch is missing'
grep -F 'fail-fast: false' "$WORKFLOW" >/dev/null || fail 'matrix fail-fast is not false'
grep -F 'arch: [x86_64, aarch64, riscv64, loongarch64, ppc64, ppc64le]' "$WORKFLOW" >/dev/null ||
    fail 'CI matrix is not the exact six-architecture list'
grep -F './scripts/build-matrix.sh "${{ matrix.arch }}"' "$WORKFLOW" >/dev/null ||
    fail 'matrix job does not build exactly its selected architecture'
grep -F './scripts/smoke-test.sh "${{ matrix.arch }}"' "$WORKFLOW" >/dev/null ||
    fail 'matrix job does not smoke-test its selected architecture'
grep -F 'image: docker.io/tonistiigi/binfmt@sha256:400a4873b838d1b89194d982c45e5fb3cda4593fbfd7e08a02e76b03b21166f0' "$WORKFLOW" >/dev/null ||
    fail 'QEMU binfmt image is not digest-pinned'
grep -F '          . ./lib/matrix.sh' "$WORKFLOW" >/dev/null ||
    fail 'validation step does not source the matrix helpers in POSIX shell'
grep -F '          expected=$(expected_artifacts "${{ matrix.arch }}")' "$WORKFLOW" >/dev/null ||
    fail 'validation step does not call expected_artifacts directly'
if grep -F 'expected_artifacts() {' "$WORKFLOW" >/dev/null; then
    fail 'validation step contains a nested expected_artifacts function hack'
fi
if grep -F -- '-printf' "$WORKFLOW" "$ROOT/scripts/publish-release.sh" >/dev/null; then
    fail 'manifest enumeration relies on non-portable GNU find -printf'
fi

for pinned in \
    'actions/checkout@11d5960a326750d5838078e36cf38b85af677262' \
    'docker/setup-qemu-action@c7c53464625b32c7a7e944ae62b3e17d2b600130' \
    'actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02' \
    'actions/download-artifact@d3f86a106a0bac45b974a628896c90dbdf5c8093'
do
    grep -F "uses: $pinned" "$WORKFLOW" >/dev/null || fail "missing pinned action $pinned"
done
if grep -E 'uses: [^[:space:]]+@(v[0-9]+|main|master)$' "$WORKFLOW" >/dev/null; then
    fail 'workflow contains a movable action reference'
fi

grep -F 'name: squashfs-tools-${{ matrix.arch }}' "$WORKFLOW" >/dev/null ||
    fail 'per-architecture upload name is missing'
grep -F 'release/mksquashfs-${{ matrix.arch }}' "$WORKFLOW" >/dev/null ||
    fail 'mksquashfs upload path is missing'
grep -F 'release/unsquashfs-${{ matrix.arch }}' "$WORKFLOW" >/dev/null ||
    fail 'unsquashfs upload path is missing'
grep -F 'if-no-files-found: error' "$WORKFLOW" >/dev/null || fail 'missing artifacts do not fail upload'

grep -F 'needs: build' "$WORKFLOW" >/dev/null || fail 'release does not wait for every matrix build'
grep -F "if: github.event_name == 'push' && startsWith(github.ref, 'refs/tags/')" "$WORKFLOW" >/dev/null ||
    fail 'release is not restricted to tag pushes'
grep -F 'merge-multiple: true' "$WORKFLOW" >/dev/null || fail 'release does not aggregate matrix artifacts'
grep -F 'expected_artifact_manifest' "$WORKFLOW" >/dev/null || fail 'release does not validate the exact manifest'
grep -F './scripts/publish-release.sh "$GITHUB_REF_NAME"' "$WORKFLOW" >/dev/null ||
    fail 'release does not use the safe publication helper'
grep -F 'GITHUB_TOKEN: ${{ github.token }}' "$WORKFLOW" >/dev/null ||
    fail 'release helper has no explicit GitHub token'

[ -r "$ROOT/scripts/publish-release.sh" ] || fail 'safe release publication helper is missing'
grep -F 'release create --draft --verify-tag' "$ROOT/scripts/publish-release.sh" >/dev/null ||
    fail 'missing release is not created as a verified draft'
grep -F 'release upload -- "$tag"' "$ROOT/scripts/publish-release.sh" >/dev/null ||
    fail 'release helper does not safely upload expected assets'
if grep -F -- '--clobber' "$ROOT/scripts/publish-release.sh" >/dev/null; then
    fail 'release helper contains destructive asset clobbering'
fi
if grep -F 'releases/assets/' "$ROOT/scripts/publish-release.sh" >/dev/null; then
    fail 'release helper can delete assets from an existing release'
fi
grep -F 'existing release asset manifest mismatch; refusing to mutate published release' "$ROOT/scripts/publish-release.sh" >/dev/null ||
    fail 'existing mismatched releases are not fail-closed'
grep -F 'draft=false' "$ROOT/scripts/publish-release.sh" >/dev/null ||
    fail 'verified draft is not explicitly published'
grep -F 'published release asset manifest verification failed' "$ROOT/scripts/publish-release.sh" >/dev/null ||
    fail 'release helper does not read back published assets'
[ "$(grep -c 'contents: write' "$WORKFLOW")" -eq 1 ] ||
    fail 'write permission is not isolated to the release job'

grep -F 'name: Contract tests' "$WORKFLOW" >/dev/null || fail 'dedicated contract test job is missing'
grep -F 'for test in tests/*.sh' "$WORKFLOW" >/dev/null || fail 'CI does not run every contract test'

printf '%s\n' 'ok - CI is a pinned six-architecture build matrix with tag-only aggregate release'
