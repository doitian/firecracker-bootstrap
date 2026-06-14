#!/usr/bin/env bash
set -euo pipefail

IMAGE_REPO="iximiuz/labs/kernelfs"
IMAGE_TAG="6.18-fc-amd64"
REGISTRY="ghcr.io"
OUTDIR="./kernelfs/${IMAGE_TAG}"

rm -rf "${OUTDIR}"
mkdir -p "${OUTDIR}"

WORKDIR=$(mktemp -d)
trap 'rm -rf "${WORKDIR}"' EXIT

echo "Pulling image ${REGISTRY}/${IMAGE_REPO}:${IMAGE_TAG} ..."
skopeo copy --multi-arch linux/amd64 "docker://${REGISTRY}/${IMAGE_REPO}:${IMAGE_TAG}" "oci:${WORKDIR}"

TOP_DIGEST=$(jq -r '.manifests[0].digest' "${WORKDIR}/index.json")
TOP_MANIFEST="${WORKDIR}/blobs/sha256/${TOP_DIGEST#sha256:}"
TOP_TYPE=$(jq -r '.mediaType' "${TOP_MANIFEST}")

if echo "${TOP_TYPE}" | grep -q "index"; then
    DIGEST=$(jq -r '.manifests[] | select(.platform.architecture == "amd64" and .platform.os == "linux") | .digest' "${TOP_MANIFEST}")
    if [ -z "${DIGEST}" ] || [ "${DIGEST}" = "null" ]; then
        echo "ERROR: No amd64/linux manifest found in index" >&2
        exit 1
    fi
    IMG_MANIFEST="${WORKDIR}/blobs/sha256/${DIGEST#sha256:}"
else
    IMG_MANIFEST="${TOP_MANIFEST}"
fi

LAYER_DIGESTS=$(jq -r '.layers[].digest' "${IMG_MANIFEST}")
if [ -z "${LAYER_DIGESTS}" ] || [ "${LAYER_DIGESTS}" = "null" ]; then
    echo "ERROR: No layers found in manifest" >&2
    exit 1
fi

echo "Saving layers ..."
LAYER_NUM=0
while IFS= read -r LAYER_DIGEST; do
    LAYER_NUM=$((LAYER_NUM + 1))
    BLOB_FILE="${WORKDIR}/blobs/sha256/${LAYER_DIGEST#sha256:}"
    cp "${BLOB_FILE}" "${OUTDIR}/layer_${LAYER_NUM}.tar.gz"
done <<< "${LAYER_DIGESTS}"

echo "Done. Raw tarballs saved to ${OUTDIR}"

echo "Extracting vmlinux.bin ..."
for layer in "${OUTDIR}"/layer_*.tar.gz; do
    tar xzf "${layer}" --wildcards --anchored -C "${OUTDIR}" 'boot/vmlinux-*' 2>/dev/null || true
done
mv "${OUTDIR}"/boot/vmlinux-* "${OUTDIR}/vmlinux.bin"
rm -rf "${OUTDIR}/boot"
