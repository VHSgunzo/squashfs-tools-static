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

publish_release_pair()
(
    source_first=$1
    name_first=$2
    source_second=$3
    name_second=$4
    destination_dir=$5
    destination_first=$destination_dir/$name_first
    destination_second=$destination_dir/$name_second
    release_mv=${RELEASE_MV:-mv}

    if [ ! -f "$source_first" ] || [ ! -f "$source_second" ]; then
        printf '%s\n' 'both built artifacts are required before publication' >&2
        exit 1
    fi

    temporary_first=
    temporary_second=
    backup_first=
    backup_second=
    had_first=false
    had_second=false
    installed_first=false
    installed_second=false
    committed=false
    # Called indirectly by the EXIT and signal traps below.
    # shellcheck disable=SC2317,SC2329
    cleanup_pair_publication()
    {
        result=$?
        trap - EXIT HUP INT TERM
        if [ "$committed" != true ]; then
            if [ "$installed_first" = true ]; then
                if [ "$had_first" = true ]; then
                    mv -f "$backup_first" "$destination_first" || result=1
                else
                    rm -f "$destination_first" || result=1
                fi
            fi
            if [ "$installed_second" = true ]; then
                if [ "$had_second" = true ]; then
                    mv -f "$backup_second" "$destination_second" || result=1
                else
                    rm -f "$destination_second" || result=1
                fi
            fi
        fi
        for transaction_file in "$temporary_first" "$temporary_second" "$backup_first" "$backup_second"
        do
            [ -z "$transaction_file" ] || rm -f "$transaction_file"
        done
        exit "$result"
    }
    trap cleanup_pair_publication EXIT
    trap 'exit 1' HUP INT TERM

    temporary_first=$(mktemp "$destination_dir/.${name_first}.tmp.XXXXXX") || exit 1
    temporary_second=$(mktemp "$destination_dir/.${name_second}.tmp.XXXXXX") || exit 1
    backup_first=$(mktemp "$destination_dir/.${name_first}.backup.XXXXXX") || exit 1
    backup_second=$(mktemp "$destination_dir/.${name_second}.backup.XXXXXX") || exit 1

    cp -p "$source_first" "$temporary_first" || exit 1
    cp -p "$source_second" "$temporary_second" || exit 1
    if [ -e "$destination_first" ]; then
        cp -p "$destination_first" "$backup_first" || exit 1
        had_first=true
    fi
    if [ -e "$destination_second" ]; then
        cp -p "$destination_second" "$backup_second" || exit 1
        had_second=true
    fi

    installed_first=true
    "$release_mv" -f "$temporary_first" "$destination_first" || exit 1
    if [ -n "${RELEASE_AFTER_FIRST_RENAME:-}" ]; then
        TRANSACTION_PID=$(sh -c 'printf %s "$PPID"')
        export TRANSACTION_PID
        "$RELEASE_AFTER_FIRST_RENAME" || exit 1
    fi
    installed_second=true
    "$release_mv" -f "$temporary_second" "$destination_second" || exit 1
    committed=true
)

cleanup_target_lock_private()
{
    if [ -n "${target_lock_private_prefix:-}" ]; then
        for lock_private_file in "$target_lock_private_prefix".*
        do
            [ -e "$lock_private_file" ] || continue
            rm -f "$lock_private_file"
        done
    fi
    target_lock_private=
    target_lock_private_prefix=
}

acquire_target_lock()
{
    lock_path=$1
    lock_owner=${2:-$$}
    target_lock_private=
    target_lock_private_prefix=$lock_path.owner.$lock_owner
    TARGET_LOCK_PID=$lock_owner
    export TARGET_LOCK_PID

    target_lock_private=$(mktemp "$target_lock_private_prefix.XXXXXX") || {
        cleanup_target_lock_private
        printf 'cannot create private target lock file beside: %s\n' "$lock_path" >&2
        return 1
    }
    if [ -n "${TARGET_LOCK_AFTER_PRIVATE_CREATE:-}" ]; then
        "$TARGET_LOCK_AFTER_PRIVATE_CREATE" || {
            cleanup_target_lock_private
            return 1
        }
    fi
    printf '%s\n' "$lock_owner" >"$target_lock_private" || {
        cleanup_target_lock_private
        return 1
    }
    if [ -n "${TARGET_LOCK_AFTER_PRIVATE_WRITE:-}" ]; then
        "$TARGET_LOCK_AFTER_PRIVATE_WRITE" || {
            cleanup_target_lock_private
            return 1
        }
    fi
    if ! ln -T "$target_lock_private" "$lock_path" 2>/dev/null; then
        cleanup_target_lock_private
        printf 'target build is already locked or its lock cannot be linked: %s\n' "$lock_path" >&2
        printf '%s\n' 'remove the lock only after confirming no build for this target is running' >&2
        return 1
    fi
    if [ -n "${TARGET_LOCK_AFTER_LINK:-}" ]; then
        "$TARGET_LOCK_AFTER_LINK" || {
            release_target_lock "$lock_path" "$lock_owner"
            return 1
        }
    fi
    cleanup_target_lock_private
    if [ -n "${TARGET_LOCK_AFTER_ACQUIRE:-}" ]; then
        "$TARGET_LOCK_AFTER_ACQUIRE" || {
            release_target_lock "$lock_path" "$lock_owner"
            return 1
        }
    fi
}

release_target_lock()
{
    lock_path=$1
    expected_owner=${2:-$$}
    cleanup_target_lock_private
    [ -f "$lock_path" ] || return 0
    IFS= read -r actual_owner <"$lock_path" || return 0
    [ "$actual_owner" = "$expected_owner" ] || return 0
    rm -f "$lock_path"
}
