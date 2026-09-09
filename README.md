# squashfs-tools-static

Statically linked [squashfs-tools](https://github.com/plougher/squashfs-tools) compiled with musl libc and [mimalloc](https://github.com/microsoft/mimalloc)

## To get started:
* **Download the latest revision**
```
git clone https://github.com/VHSgunzo/squashfs-tools-static.git
cd squashfs-tools-static
```

* **Compile the binaries**

Prerequisites:

- Linux with Docker Engine and support for `docker run --platform`.
- Internet access for pinned container images, source repositories, and the
  `ppc64` musl cross-toolchain archive.
- QEMU user-mode emulation with binfmt handlers registered for non-native
  container platforms. On Debian/Ubuntu, install `qemu-user-static` and
  `binfmt-support`; Docker Desktop already includes emulation support.
- Host `readelf` (normally from `binutils`) for artifact validation, and the
  matching QEMU user executable for a foreign-architecture smoke test.

Build one architecture at a time from the repository root:

```sh
./scripts/build-matrix.sh x86_64
./scripts/build-matrix.sh aarch64
./scripts/build-matrix.sh riscv64
./scripts/build-matrix.sh loongarch64
./scripts/build-matrix.sh ppc64
./scripts/build-matrix.sh ppc64le
```

Build the complete release matrix with `./scripts/build-matrix.sh all`.
Each selected target builds and validates both outputs under its target work directory before publishing them as a pair. Pair publication stages adjacent temporary files, backs up any previous pair, and rolls back the first rename if the second rename or a signal interrupts the transaction. A failed or interrupted musl target build leaves its previously published pair unchanged; obsolete `-upx` files are removed only after the normal pair is replaced successfully. Every other target's outputs are preserved:

```text
release/mksquashfs-ARCH
release/unsquashfs-ARCH
```

Same-target musl builds are serialized by a per-target lock in `release/`; different targets can proceed independently. Each canonical lock is atomically hard-linked from an adjacent private file that already contains its owner, so observers never see an empty lock. Normal exits and handled signals remove the canonical lock and private file. If the process is killed without running traps, remove a stale lock only after confirming that no build for that target is still running.

`ARCH` is one of `x86_64`, `aarch64`, `riscv64`, `loongarch64`, `ppc64`, or
`ppc64le`. The matrix driver uses pinned Alpine image digests. Most targets
build natively inside their selected architecture container under binfmt/QEMU.
`loongarch64` uses the LoongArch Alpine image and Docker platform
`linux/loong64`, so the host's Docker/QEMU installation must support that
platform. `ppc64` is the exception: it builds in the `linux/amd64` container
with a pinned big-endian PowerPC64 musl cross-toolchain. `ppc64le` is a
separate little-endian target and builds in a `linux/ppc64le` container.

Source revisions are immutable. `build.sh` checks out and verifies these exact
upstream commits without changing the user-facing dependency versions:

| Dependency | Version represented | Commit |
| --- | --- | --- |
| squashfs-tools | 4.7.5 | `708c59ae80853b0845017c33b42e56061cc546cd` |
| mimalloc | 2.1.7 | `8c532c32c3c96e5ba1f2283e032f69ead8add00f` |
| XZ | 5.8.2 | `9fc6f5cd8774ebef8d4e030f7081fb6984c0dc3f` |
| LZO | upstream (no tags) | `0083878c235a89ef96a009d1ff0b500f3a364e4b` |
| zlib | 1.3.2 | `e3dc0a85b7032e98380dec011bc8f2c2ee0d8fca` |
| LZ4 | 1.10.0 | `0774d05537f9762f838f7ab541b7765f1a729cb5` |
| Zstandard | 1.5.7 | `d9c0c7e2cf8a8bf9fb98d3bee546dcf8dc9ac59a` |

The source revisions, container base images, GitHub Actions, and external
`ppc64` toolchain archive are pinned.
Alpine package repository contents and toolchain package revisions are not frozen:
`apk add` resolves them live from the repositories configured in each pinned
image. The build therefore has
source-reproducible inputs, but is not guaranteed to produce byte-for-byte
identical artifacts across runs.

For direct `build.sh` use, `TARGET_ARCH` defaults to `uname -m` and must match
the build machine unless `BUILD_MODE=cross-musl` is configured with a matching
explicit cross-toolchain. Externally supplied compiler settings such as `CC`,
`CXX`, `AR`, `RANLIB`, and `STRIP` are preserved. UPX and host `sstrip`
post-processing are not required or run, and `-upx` artifacts are not
produced.

Validate an artifact pair and run a version plus SquashFS round trip with:

```sh
./scripts/validate-artifacts.sh ARCH
./scripts/smoke-test.sh ARCH
```

The smoke runner executes natively when `ARCH` matches the host and otherwise
selects the matching `qemu-*-static` executable, including `qemu-x86_64-static`
when testing x86-64 artifacts on a non-x86-64 host.

Run all shell contract tests with:

```sh
for test in tests/*.sh; do sh "$test"; done
```

These unit and contract tests are self-contained and pass in a clean checkout;
their generated fixtures do not claim a real SquashFS round trip. The commands
under `scripts/` above are the integration checks for actual build artifacts.

### Release safety

Published releases are treated as immutable. An existing published release is a no-op only if it has the exact expected 12-asset manifest; a mismatch fails without mutation. A missing release is created as a verified-tag draft, all 12 assets are uploaded without clobbering historical assets, and the draft is published only after exact manifest verification.

Every create attempt places a unique ownership marker in the draft notes as part of the creation request. Failures clean up only a freshly read draft whose ID, tag, draft state, and per-attempt ownership marker all match; a competing publisher draft is never deleted. Publishing atomically clears the internal marker while changing the draft state, and the public read-back requires empty notes. Malformed metadata, ambiguous publication responses, failed state reads, or changed/public state leave the release intact for manual inspection. Release jobs are serialized by repository and tag as defense in depth, publication is tag-push-only, and only the release job receives `contents: write` and a GitHub token.

Git tag components may begin with `-`, so release CLI calls use an option separator to keep such a tag from being parsed as a flag.

* Or take an already precompiled from the [releases](https://github.com/VHSgunzo/squashfs-tools-static/releases)
