#!/usr/bin/env bash
set -euo pipefail

IMAGE_REPO="iximiuz/labs/kernelfs"
IMAGE_TAG="6.18-fc-amd64"
REGISTRY="ghcr.io"
OUTDIR="./kernelfs/${IMAGE_TAG}"

AUTH_URL="https://${REGISTRY}/token?service=${REGISTRY}&scope=repository:${IMAGE_REPO}:pull"
BASE_URL="https://${REGISTRY}/v2/${IMAGE_REPO}"

echo "Authenticating with ${REGISTRY} ..."
TOKEN=$(curl -sSL "${AUTH_URL}" | jq -r '.token')
if [ -z "${TOKEN}" ] || [ "${TOKEN}" = "null" ]; then
    echo "ERROR: Failed to obtain auth token" >&2
    exit 1
fi
AUTH_HEADER="Authorization: Bearer ${TOKEN}"
ACCEPT_HEADER="Accept: application/vnd.oci.image.index.v1+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json, application/vnd.docker.distribution.manifest.list.v2+json"

echo "Fetching manifest for ${IMAGE_REPO}:${IMAGE_TAG} ..."
MANIFEST=$(curl -sSL -H "${AUTH_HEADER}" -H "${ACCEPT_HEADER}" "${BASE_URL}/manifests/${IMAGE_TAG}")
MEDIA_TYPE=$(echo "${MANIFEST}" | jq -r '.mediaType')

if echo "${MEDIA_TYPE}" | grep -q "index"; then
    echo "  -> OCI image index detected, resolving amd64 manifest ..."
    DIGEST=$(echo "${MANIFEST}" | jq -r '.manifests[] | select(.platform.architecture == "amd64" and .platform.os == "linux") | .digest')
    if [ -z "${DIGEST}" ] || [ "${DIGEST}" = "null" ]; then
        echo "ERROR: No amd64/linux manifest found in index" >&2
        exit 1
    fi
    MANIFEST=$(curl -sSL -H "${AUTH_HEADER}" -H "${ACCEPT_HEADER}" "${BASE_URL}/manifests/${DIGEST}")
fi

DIGESTS=$(echo "${MANIFEST}" | jq -r '.layers[].digest')
if [ -z "${DIGESTS}" ] || [ "${DIGESTS}" = "null" ]; then
    echo "ERROR: No layers found in manifest" >&2
    exit 1
fi

rm -rf "${OUTDIR}"
mkdir -p "${OUTDIR}"

echo "Pulling and saving layers ..."
LAYER_NUM=0
TOTAL=$(echo "${DIGESTS}" | wc -l)
while IFS= read -r DIGEST; do
    LAYER_NUM=$((LAYER_NUM + 1))
    echo "  [${LAYER_NUM}/${TOTAL}] ${DIGEST}"
    curl -sSL -H "${AUTH_HEADER}" "${BASE_URL}/blobs/${DIGEST}" -o "${OUTDIR}/layer_${LAYER_NUM}.tar.gz"
done <<< "${DIGESTS}"

echo "Done. Raw tarballs saved to ${OUTDIR}"
