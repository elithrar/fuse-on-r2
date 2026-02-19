#!/bin/sh
set -e

MOUNT_DIR="$HOME/mnt/r2/${BUCKET_NAME}"
mkdir -p "${MOUNT_DIR}"

R2_ENDPOINT="https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com"
echo "Mounting bucket ${BUCKET_NAME}..."
/usr/local/bin/tigrisfs --endpoint "${R2_ENDPOINT}" -f "${BUCKET_NAME}" \
  "${MOUNT_DIR}${BUCKET_PREFIX:+:${BUCKET_PREFIX}}" &
TIGRISFS_PID=$!

# Wait until the FUSE mount is ready (up to 30 seconds).
# Fail fast if the tigrisfs process itself exits before the mount appears.
i=0
until mountpoint -q "${MOUNT_DIR}" || [ "$i" -ge 30 ]; do
  if ! kill -0 "${TIGRISFS_PID}" 2>/dev/null; then
    echo "Error: tigrisfs exited unexpectedly before mount was ready" >&2
    exit 1
  fi
  sleep 1
  i=$((i + 1))
done

if ! mountpoint -q "${MOUNT_DIR}"; then
  echo "Error: FUSE mount did not become ready after 30 seconds" >&2
  exit 1
fi

echo "Starting server on :8080"
exec /server
