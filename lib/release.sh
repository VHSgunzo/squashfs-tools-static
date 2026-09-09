#!/bin/sh

install_release_binary()
(
    source_path=$1
    destination=$2/$(basename "$source_path")-$3
    destination_dir=${destination%/*}
    destination_name=${destination##*/}
    temporary=$(mktemp "${destination_dir}/.${destination_name}.tmp.XXXXXX") || exit 1
    trap 'rm -f "$temporary"' EXIT HUP INT TERM

    cp -p "$source_path" "$temporary" && mv -f "$temporary" "$destination"
)
