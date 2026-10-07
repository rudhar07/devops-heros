#!/usr/bin/env bash
# Load locally built images into a kind cluster.
#
# Why not just "kind load docker-image"? With Docker Desktop's containerd image
# store, locally built images are multi-platform indexes with attestation
# manifests; kind's "ctr import --all-platforms" then fails with
# "content digest ... not found". Saving only the node's platform avoids that.
set -euo pipefail
CLUSTER="${CLUSTER:-hw-f}"
PLATFORM="${PLATFORM:-linux/$(docker info -f '{{.Architecture}}' | sed 's/aarch64/arm64/;s/x86_64/amd64/')}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
for image in "$@"; do
  file="$TMP/$(echo "$image" | tr '/:' '__').tar"
  echo "saving $image ($PLATFORM)"
  docker save --platform "$PLATFORM" -o "$file" "$image"
  kind load image-archive "$file" --name "$CLUSTER"
done
