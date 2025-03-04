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
docker run --rm -it -v "$PWD:/root" --platform=linux/amd64 alpine:latest /root/build.sh

# for aarch64 (required qemu-user-static)
docker run --rm -it -v "$PWD:/root" --platform=linux/arm64 alpine:latest /root/build.sh
```

* Or take an already precompiled from the [releases](https://github.com/VHSgunzo/squashfs-tools-static/releases)
