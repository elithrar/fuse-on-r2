#!/bin/sh
set -eu

: "${AWS_ACCESS_KEY_ID:?AWS_ACCESS_KEY_ID is required}"
: "${AWS_SECRET_ACCESS_KEY:?AWS_SECRET_ACCESS_KEY is required}"
: "${BUCKET_NAME:?BUCKET_NAME is required}"
: "${R2_ACCOUNT_ID:?R2_ACCOUNT_ID is required}"

MOUNT_PATH="${MOUNT_PATH:-$HOME/mnt/r2/${BUCKET_NAME}}"
R2_ENDPOINT="https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com"
SOURCE="${BUCKET_NAME}${BUCKET_PREFIX:+:${BUCKET_PREFIX}}"

mkdir -p "${MOUNT_PATH}"
export MOUNT_PATH

printf 'Mounting %s at %s...\n' "${SOURCE}" "${MOUNT_PATH}"
/usr/local/bin/tigrisfs --endpoint "${R2_ENDPOINT}" -f "${SOURCE}" "${MOUNT_PATH}" &
tigrisfs_pid=$!

process_is_running() {
    kill -0 "$1" 2>/dev/null &&
        ! grep -q ") Z " "/proc/$1/stat" 2>/dev/null
}

# Invoked indirectly by trap.
# shellcheck disable=SC2317,SC2329
stop_processes() {
    trap - INT TERM
    if [ -n "${server_pid:-}" ]; then
        kill -TERM "${server_pid}" 2>/dev/null || true
    fi
    kill -TERM "${tigrisfs_pid}" 2>/dev/null || true
}

trap stop_processes INT TERM

attempt=0
while ! grep -Fqs " ${MOUNT_PATH} " /proc/mounts; do
    if ! process_is_running "${tigrisfs_pid}"; then
        exit_code=1
        wait "${tigrisfs_pid}" || exit_code=$?
        printf 'tigrisfs exited before the mount was ready (status %s)\n' "${exit_code}" >&2
        exit "${exit_code}"
    fi

    attempt=$((attempt + 1))
    if [ "${attempt}" -ge 30 ]; then
        printf 'Timed out waiting for %s to mount\n' "${MOUNT_PATH}" >&2
        kill "${tigrisfs_pid}" 2>/dev/null || true
        wait "${tigrisfs_pid}" 2>/dev/null || true
        exit 1
    fi

    sleep 1
done

printf 'Starting server on :8080\n'
/server &
server_pid=$!

while process_is_running "${server_pid}" && process_is_running "${tigrisfs_pid}"; do
    sleep 1
done

exit_code=0
if ! process_is_running "${server_pid}"; then
    wait "${server_pid}" || exit_code=$?
    printf 'Server exited (status %s); stopping tigrisfs\n' "${exit_code}" >&2
    kill -TERM "${tigrisfs_pid}" 2>/dev/null || true
    wait "${tigrisfs_pid}" 2>/dev/null || true
else
    wait "${tigrisfs_pid}" || exit_code=$?
    printf 'tigrisfs exited (status %s); stopping server\n' "${exit_code}" >&2
    kill -TERM "${server_pid}" 2>/dev/null || true
    wait "${server_pid}" 2>/dev/null || true
fi

exit "${exit_code}"
