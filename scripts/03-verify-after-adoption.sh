#!/usr/bin/env bash
set -euo pipefail
NS="${1:-data-stack}"

PASS="$(kubectl get secret splunk-secret -n "$NS" \
  -o jsonpath='{.data.SPLUNK_PASSWORD}' | base64 -d)"

echo "=== Helm ==="
helm status splunk -n "$NS"

echo
echo "=== Kubernetes ==="
kubectl get sts,pod,svc,ingress,pvc -n "$NS" | grep -E 'NAME|splunk'

echo
echo "=== Storage ==="
kubectl get pv splunk-etc-pv splunk-var-pv \
  -o custom-columns='NAME:.metadata.name,STATUS:.status.phase,CLAIM:.spec.claimRef.namespace/.spec.claimRef.name,PATH:.spec.local.path,RECLAIM:.spec.persistentVolumeReclaimPolicy'

echo
echo "=== Java ==="
kubectl exec -n "$NS" splunk-0 -- sh -c 'command -v java; java -version'

echo
echo "=== Splunk ==="
kubectl exec -n "$NS" splunk-0 -- /opt/splunk/bin/splunk status

echo
echo "=== Indexes ==="
kubectl exec -n "$NS" splunk-0 -- \
  env SPLUNK_VERIFY_PASSWORD="$PASS" \
  sh -c '/opt/splunk/bin/splunk list index -auth "admin:$SPLUNK_VERIFY_PASSWORD"'

echo
echo "=== KV Store ==="
kubectl exec -n "$NS" splunk-0 -- \
  env SPLUNK_VERIFY_PASSWORD="$PASS" \
  sh -c '/opt/splunk/bin/splunk show kvstore-status -auth "admin:$SPLUNK_VERIFY_PASSWORD"' || true

echo
echo "=== BasicAuth middleware attached? ==="
kubectl get ingress splunk-web -n "$NS" \
  -o jsonpath='{.metadata.annotations.traefik\.ingress\.kubernetes\.io/router\.middlewares}{"\n"}'
