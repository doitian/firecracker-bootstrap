#!/usr/bin/env bash
set -euo pipefail

KERNELFS_DIR="${1:?Usage: $0 <kernelfs-dir> <image-tag>}"
IMAGE_TAG="${2:?Usage: $0 <kernelfs-dir> <image-tag>}"
REGISTRY="ghcr.io"
mkdir -p "rootfs/${IMAGE_TAG}"
OUTPUT_FILE="rootfs/${IMAGE_TAG}/${IMAGE_TAG}.ext4"
SIZE_MB="${ROOTFS_SIZE_MB:-1024}"

OCI_DIR=$(mktemp -d)
WORK_DIR=$(mktemp -d)
trap 'sudo umount "${WORK_DIR}/mnt" 2>/dev/null; rm -rf "${WORK_DIR}" "${OCI_DIR}"' EXIT

truncate -s ${SIZE_MB}M "${OUTPUT_FILE}"
mkfs.ext4 -F "${OUTPUT_FILE}"

mkdir -p "${WORK_DIR}/mnt"
sudo mount -o loop "${OUTPUT_FILE}" "${WORK_DIR}/mnt"

IMAGE_REPO="doitian/firecracker-bootstrap"

echo "Pulling image ${REGISTRY}/${IMAGE_REPO}:${IMAGE_TAG} ..."
skopeo copy --multi-arch linux/amd64 "docker://${REGISTRY}/${IMAGE_REPO}:${IMAGE_TAG}" "oci:${OCI_DIR}"

TOP_DIGEST=$(jq -r '.manifests[0].digest' "${OCI_DIR}/index.json")
TOP_MANIFEST="${OCI_DIR}/blobs/sha256/${TOP_DIGEST#sha256:}"
TOP_TYPE=$(jq -r '.mediaType' "${TOP_MANIFEST}")

if echo "${TOP_TYPE}" | grep -q "index"; then
    DIGEST=$(jq -r '.manifests[] | select(.platform.architecture == "amd64" and .platform.os == "linux") | .digest' "${TOP_MANIFEST}")
    if [ -z "${DIGEST}" ] || [ "${DIGEST}" = "null" ]; then
        echo "ERROR: No amd64/linux manifest found in index" >&2
        exit 1
    fi
    IMG_MANIFEST="${OCI_DIR}/blobs/sha256/${DIGEST#sha256:}"
else
    IMG_MANIFEST="${TOP_MANIFEST}"
fi

LAYER_DIGESTS=$(jq -r '.layers[].digest' "${IMG_MANIFEST}")
if [ -z "${LAYER_DIGESTS}" ] || [ "${LAYER_DIGESTS}" = "null" ]; then
    echo "ERROR: No layers found in manifest" >&2
    exit 1
fi

echo "Extracting rootfs layers ..."
while IFS= read -r LAYER_DIGEST; do
    BLOB_FILE="${OCI_DIR}/blobs/sha256/${LAYER_DIGEST#sha256:}"
    sudo tar xzf "${BLOB_FILE}" \
        --xattrs --xattrs-include='*' \
        --numeric-owner \
        --same-permissions \
        --anchored \
        --exclude='dev/*' \
        --exclude='proc/*' \
        --exclude='sys/*' \
        --exclude='.dockerenv' \
        -C "${WORK_DIR}/mnt"
done <<< "${LAYER_DIGESTS}"

echo "${IMAGE_TAG}" | sudo tee "${WORK_DIR}/mnt/etc/hostname" > /dev/null

sudo rm -rf "${WORK_DIR}/mnt/boot" "${WORK_DIR}/mnt/lib/modules"

echo "Extracting kernelfs layers ..."
for layer in "${KERNELFS_DIR}"/layer_*.tar.gz; do
    sudo tar xzf "${layer}" \
        --xattrs --xattrs-include='*' \
        --numeric-owner \
        --same-permissions \
        --anchored \
        --keep-directory-symlink \
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
rm -rf "${WORK_DIR}" "${OCI_DIR}"

echo "Rootfs baked: ${OUTPUT_FILE}"
