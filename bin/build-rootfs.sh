#!/usr/bin/env bash
set -euo pipefail

REGISTRY="ghcr.io"
IMAGE_REPO="doitian/firecracker-bootstrap"
declare -A BUILT

resolve_deps() {
	local tag="$1"
	local dockerfile="rootfs/${tag}/Dockerfile"
	[ -f "$dockerfile" ] || return 0

	local prefix="${REGISTRY}/${IMAGE_REPO}:"
	while IFS= read -r line; do
		line="${line#"${line%%[![:space:]]*}"}"
		[[ "$line" == FROM\ * ]] || continue
		local ref="${line#FROM }"
		ref="${ref%% *}"
		[[ "$ref" == "$prefix"* ]] || continue
		local dep="${ref#$prefix}"
		[ -f "rootfs/${dep}/Dockerfile" ] || continue
		echo "$dep"
		resolve_deps "$dep"
	done < "$dockerfile"
}

build_image() {
	local tag="$1"
	[ -n "${BUILT[$tag]:-}" ] && return 0
	echo "Building ${REGISTRY}/${IMAGE_REPO}:${tag} ..."
	buildah bud \
		--tag "${REGISTRY}/${IMAGE_REPO}:${tag}" \
		"rootfs/${tag}"
	BUILT[$tag]=1
}

IMAGE_TAG="${1:-}"

if [ -n "${IMAGE_TAG}" ]; then
	deps=$(resolve_deps "${IMAGE_TAG}" | sort -u)
	for dep in $deps; do
		build_image "$dep"
	done
	build_image "${IMAGE_TAG}"
else
	for dir in rootfs/*/; do
		tag=$(basename "$dir")
		deps=$(resolve_deps "$tag" | sort -u)
		for dep in $deps; do
			build_image "$dep"
		done
		build_image "$tag"
	done
fi
