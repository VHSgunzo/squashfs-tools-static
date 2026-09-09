# squashfs-tools-static

Statically linked [squashfs-tools](https://github.com/plougher/squashfs-tools) compiled with musl libc and [mimalloc](https://github.com/microsoft/mimalloc)

## To get started:
* **Download the latest revision**
```
git clone https://github.com/VHSgunzo/squashfs-tools-static.git
cd squashfs-tools-static
```

* **Compile the binaries**
```
# for x86_64
docker run --rm -it -v "$PWD:/root" --platform=linux/amd64 \
  -e TARGET_ARCH=x86_64 alpine:latest /root/build.sh

# for aarch64 (required qemu-user-static)
docker run --rm -it -v "$PWD:/root" --platform=linux/arm64 \
  -e TARGET_ARCH=aarch64 alpine:latest /root/build.sh
```

`TARGET_ARCH` is the public architecture name used in release filenames. It must
be one of `x86_64`, `aarch64`, `riscv64`, `loongarch64`, `ppc64`, or `ppc64le`.
When it is not set, `build.sh` defaults to `uname -m` for convenient native
builds. This build path is native (including full-system or user-mode emulation):
the requested `TARGET_ARCH` must match the build machine's `uname -m`.
Unsupported or mismatched values fail before package installation and compilation;
true cross-compilation requires a future explicit cross-toolchain mode.
Externally supplied compiler and toolchain settings such as `CC`, `CXX`, `AR`,
`RANLIB`, and `STRIP` are preserved.

The default build produces the uncompressed static binaries
`release/mksquashfs-$TARGET_ARCH` and `release/unsquashfs-$TARGET_ARCH`. UPX and
host `sstrip` post-processing are not required or run, and `-upx` artifacts are
not produced.

Run the target contract tests with:

```
sh tests/target-contract.sh
```

* Or take an already precompiled from the [releases](https://github.com/VHSgunzo/squashfs-tools-static/releases)
