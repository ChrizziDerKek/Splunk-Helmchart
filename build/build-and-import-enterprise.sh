#!/usr/bin/env bash
set -euo pipefail

IMAGE="${1:-splunk-custom:10.0.1-java-v2}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TAR="/tmp/$(echo "$IMAGE" | tr '/:' '__').tar"

echo "Building the exact Java-enabled Splunk image..."
docker build -t "$IMAGE" -f "$HERE/Dockerfile.enterprise" "$HERE"

echo "Exporting image..."
docker save "$IMAGE" -o "$TAR"

echo "Importing into k3s/containerd..."
sudo k3s ctr images import "$TAR"

echo
echo "Imported image candidates:"
sudo k3s ctr images list | grep -F 'splunk-custom' || true
