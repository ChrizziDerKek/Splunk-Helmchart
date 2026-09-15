#!/usr/bin/env bash
set -euo pipefail
NS="${1:-data-stack}"
CHART="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "Rendering migration profile..."
helm template splunk "$CHART" \
  -n "$NS" \
  -f "$CHART/values-migration.yaml" \
  > /tmp/splunk-migration-rendered.yaml

echo
echo "Checking critical storage identities..."
grep -nE 'kind: PersistentVolume|kind: PersistentVolumeClaim|storageClassName:|path: /k3s/splunk/data|volumeName: splunk-' \
  /tmp/splunk-migration-rendered.yaml || true

echo
echo "Checking image/startup..."
grep -nE 'splunk-custom:10.0.1-java-v2|Starting Splunk non-interactively' \
  /tmp/splunk-migration-rendered.yaml || true

echo
echo "Checking BasicAuth attachment..."
grep -n 'router.middlewares' /tmp/splunk-migration-rendered.yaml || true

echo
echo "Kubernetes diff follows. Metadata/Helm labels are expected."
kubectl diff -n "$NS" -f /tmp/splunk-migration-rendered.yaml || true
