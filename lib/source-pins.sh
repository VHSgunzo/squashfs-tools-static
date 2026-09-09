#!/bin/sh

checkout_pinned_source()
{
    source_directory=$1
    expected_commit=$2

    git -C "$source_directory" checkout --detach "$expected_commit"
    actual_commit=$(git -C "$source_directory" rev-parse HEAD)
    if [ "$actual_commit" != "$expected_commit" ]; then
        printf '%s source HEAD mismatch: expected %s, got %s\n' \
            "$source_directory" "$expected_commit" "$actual_commit" >&2
        return 1
    fi
}
