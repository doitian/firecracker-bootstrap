#!/usr/bin/env bash
set -euo pipefail

KERNELFS_DIR="${1:?Usage: $0 <kernelfs-dir> <image-tag>}"
IMAGE_TAG="${2:?Usage: $0 <kernelfs-dir> <image-tag>}"
REGISTRY="ghcr.io"
mkdir -p "rootfs/${IMAGE_TAG}"
OUTPUT_FILE="rootfs/${IMAGE_TAG}/${IMAGE_TAG}.ext4"
SIZE_MB="${ROOTFS_SIZE_MB:-1024}"

WORK_DIR="$(mktemp -d)"
trap 'sudo umount "${WORK_DIR}/mnt" 2>/dev/null; rm -rf "${WORK_DIR}"' EXIT

truncate -s ${SIZE_MB}M "${OUTPUT_FILE}"
mkfs.ext4 -F "${OUTPUT_FILE}"

mkdir -p "${WORK_DIR}/mnt"
sudo mount -o loop "${OUTPUT_FILE}" "${WORK_DIR}/mnt"

IMAGE_REPO="doitian/firecracker-bootstrap"
AUTH_URL="https://${REGISTRY}/token?service=${REGISTRY}&scope=repository:${IMAGE_REPO}:pull"
BASE_URL="https://${REGISTRY}/v2/${IMAGE_REPO}"
ACCEPT_HEADER="Accept: application/vnd.oci.image.index.v1+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json, application/vnd.docker.distribution.manifest.list.v2+json"

TOKEN=$(curl -sSL "${AUTH_URL}" | jq -r '.token')
if [ -z "${TOKEN}" ] || [ "${TOKEN}" = "null" ]; then
    echo "ERROR: Failed to obtain auth token" >&2
    exit 1
fi
AUTH_HEADER="Authorization: Bearer ${TOKEN}"

MANIFEST=$(curl -sfSL -H "${AUTH_HEADER}" -H "${ACCEPT_HEADER}" "${BASE_URL}/manifests/${IMAGE_TAG}") || {
    echo "ERROR: Failed to fetch manifest for ${IMAGE_REPO}:${IMAGE_TAG}" >&2
    exit 1
}

MANIFEST_ERROR=$(echo "${MANIFEST}" | jq -r '.errors // empty')
if [ -n "${MANIFEST_ERROR}" ]; then
    echo "ERROR: ${MANIFEST_ERROR}" >&2
    exit 1
fi

MEDIA_TYPE=$(echo "${MANIFEST}" | jq -r '.mediaType')

if echo "${MEDIA_TYPE}" | grep -q "index"; then
    DIGEST=$(echo "${MANIFEST}" | jq -r '.manifests[] | select(.platform.architecture == "amd64" and .platform.os == "linux") | .digest')
    if [ -z "${DIGEST}" ] || [ "${DIGEST}" = "null" ]; then
        echo "ERROR: No amd64/linux manifest found in index" >&2
        exit 1
    fi
    MANIFEST=$(curl -sfSL -H "${AUTH_HEADER}" -H "${ACCEPT_HEADER}" "${BASE_URL}/manifests/${DIGEST}") || {
        echo "ERROR: Failed to fetch platform manifest" >&2
        exit 1
    }
fi

DIGESTS=$(echo "${MANIFEST}" | jq -r '.layers[]?.digest')
if [ -z "${DIGESTS}" ] || [ "${DIGESTS}" = "null" ]; then
    echo "ERROR: No layers found in manifest" >&2
    exit 1
fi

while IFS= read -r DIGEST; do
    curl -sSL -H "${AUTH_HEADER}" "${BASE_URL}/blobs/${DIGEST}" | gunzip | sudo tar -x \
        --xattrs --xattrs-include='*' \
        --numeric-owner \
        --same-permissions \
        --anchored \
        --exclude='dev/*' \
        --exclude='proc/*' \
        --exclude='sys/*' \
        --exclude='.dockerenv' \
        -C "${WORK_DIR}/mnt"
done <<< "${DIGESTS}"

echo "${IMAGE_TAG}" | sudo tee "${WORK_DIR}/mnt/etc/hostname" > /dev/null

sudo rm -rf "${WORK_DIR}/mnt/boot" "${WORK_DIR}/mnt/lib/modules"

for layer in "${KERNELFS_DIR}"/layer_*.tar.gz; do
    sudo tar xzf "${layer}" \
        --xattrs --xattrs-include='*' \
        --numeric-owner \
        --same-permissions \
        --anchored \
        -C "${WORK_DIR}/mnt"
done

sudo chown -R root:root "${WORK_DIR}/mnt/boot" "${WORK_DIR}/mnt/lib/modules"

if [ -n "${DEBUG:-}" ]; then
    trap - EXIT
    echo "DEBUG: Mounted at ${WORK_DIR}/mnt (temp dir preserved: ${WORK_DIR})"
    echo "Rootfs baked: ${OUTPUT_FILE}"
    exit 0
fi

sudo umount "${WORK_DIR}/mnt"
trap - EXIT
rm -rf "${WORK_DIR}"

echo "Rootfs baked: ${OUTPUT_FILE}"
