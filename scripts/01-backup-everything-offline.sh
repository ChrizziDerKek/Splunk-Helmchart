#!/usr/bin/env bash
set -euo pipefail

NS="${1:-data-stack}"
DEST_ROOT="${2:-/k3s/splunk/backups}"
STAMP="$(date +%Y%m%d-%H%M%S)"
DEST="$DEST_ROOT/$STAMP"

ETC="/k3s/splunk/data/etc"
VAR="/k3s/splunk/data/var"

mkdir -p "$DEST"
chmod 0700 "$DEST"

PASS="$(kubectl get secret splunk-secret -n "$NS" \
  -o jsonpath='{.data.SPLUNK_PASSWORD}' | base64 -d)"

echo "Backup destination: $DEST"
echo
echo "=== Pre-backup data sizes ==="
sudo du -sh "$ETC" "$VAR" | tee "$DEST/data-sizes-before.txt"

echo
echo "=== Capturing live Splunk diagnostics ==="
kubectl exec -n "$NS" splunk-0 -- /opt/splunk/bin/splunk version \
  > "$DEST/splunk-version.txt" 2>&1 || true
kubectl exec -n "$NS" splunk-0 -- sh -c 'java -version' \
  > "$DEST/java-version.txt" 2>&1 || true
kubectl exec -n "$NS" splunk-0 -- \
  env SPLUNK_BK_PASS="$PASS" \
  sh -c '/opt/splunk/bin/splunk list index -auth "admin:$SPLUNK_BK_PASS"' \
  > "$DEST/index-list.txt" 2>&1 || true
kubectl exec -n "$NS" splunk-0 -- \
  env SPLUNK_BK_PASS="$PASS" \
  sh -c '/opt/splunk/bin/splunk show kvstore-status -auth "admin:$SPLUNK_BK_PASS"' \
  > "$DEST/kvstore-status.txt" 2>&1 || true
kubectl exec -n "$NS" splunk-0 -- sh -c 'ls -1 /opt/splunk/etc/apps' \
  > "$DEST/apps-list.txt" 2>&1 || true

echo
echo "=== Capturing Kubernetes objects ==="
kubectl get sts splunk -n "$NS" -o yaml > "$DEST/statefulset.yaml"
kubectl get pod splunk-0 -n "$NS" -o yaml > "$DEST/pod.yaml"
kubectl get svc splunk-web splunk-hec splunk-management -n "$NS" -o yaml > "$DEST/services.yaml"
kubectl get ingress splunk-web -n "$NS" -o yaml > "$DEST/ingress.yaml"
kubectl get middleware splunk-basic-auth -n "$NS" -o yaml > "$DEST/middleware.yaml"
kubectl get pvc splunk-etc splunk-var -n "$NS" -o yaml > "$DEST/pvcs.yaml"
kubectl get pv splunk-etc-pv splunk-var-pv -o yaml > "$DEST/pvs.yaml"

# Secrets are intentionally backed up for disaster recovery. Directory mode is 0700.
for SECRET in splunk-secret splunk-basic-auth splunk-web-tls; do
  if kubectl get secret "$SECRET" -n "$NS" >/dev/null 2>&1; then
    kubectl get secret "$SECRET" -n "$NS" -o yaml > "$DEST/secret-$SECRET.yaml"
    chmod 0600 "$DEST/secret-$SECRET.yaml"
  fi
done

IMAGE="$(kubectl get sts splunk -n "$NS" \
  -o jsonpath='{.spec.template.spec.containers[0].image}')"
printf '%s\n' "$IMAGE" > "$DEST/current-image.txt"

echo
echo "=== Attempting exact k3s/containerd image export ==="
MATCH="$(sudo k3s ctr images list -q 2>/dev/null | grep -E "(^|/)${IMAGE//./\\.}$" | head -1 || true)"
if [[ -z "$MATCH" ]]; then
  MATCH="$(sudo k3s ctr images list -q 2>/dev/null | grep -F 'splunk-custom' | head -1 || true)"
fi

if [[ -n "$MATCH" ]]; then
  echo "Exporting: $MATCH"
  sudo k3s ctr images export "$DEST/splunk-custom-image.tar" "$MATCH"
  sudo chown "$(id -u):$(id -g)" "$DEST/splunk-custom-image.tar"
  sha256sum "$DEST/splunk-custom-image.tar" > "$DEST/image-SHA256SUM"
else
  echo "WARNING: exact containerd image reference was not resolved." \
    | tee "$DEST/image-export-warning.txt"
fi

restart_splunk() {
  echo
  echo "Starting Splunk again..."
  kubectl scale statefulset splunk -n "$NS" --replicas=1 >/dev/null || true
  kubectl rollout status statefulset/splunk -n "$NS" --timeout=1200s || true
}
trap restart_splunk EXIT

echo
echo "=== Stopping Splunk for consistent filesystem backup ==="
kubectl exec -n "$NS" splunk-0 -- \
  /opt/splunk/bin/splunk stop >/dev/null 2>&1 || true
kubectl scale statefulset splunk -n "$NS" --replicas=0
kubectl wait --for=delete pod/splunk-0 -n "$NS" --timeout=300s 2>/dev/null || true

echo
echo "=== Archiving ALL persisted Splunk state ==="
sudo tar \
  --acls \
  --xattrs \
  --numeric-owner \
  --sparse \
  -czf "$DEST/splunk-persisted-data.tar.gz" \
  -C /k3s/splunk/data \
  etc var

sudo chown "$(id -u):$(id -g)" "$DEST/splunk-persisted-data.tar.gz"

gzip -t "$DEST/splunk-persisted-data.tar.gz"
sha256sum "$DEST/splunk-persisted-data.tar.gz" > "$DEST/data-SHA256SUM"

echo
echo "Archive top-level contents:"
tar -tzf "$DEST/splunk-persisted-data.tar.gz" | head -40 || true

trap - EXIT
restart_splunk

echo
echo "=== Post-backup health ==="
kubectl get pod splunk-0 -n "$NS" -o wide
sudo du -sh "$ETC" "$VAR" | tee "$DEST/data-sizes-after.txt"

echo
echo "BACKUP COMPLETE"
echo "Do not proceed unless the following checks pass:"
(cd "$DEST" && sha256sum -c data-SHA256SUM)
gzip -t "$DEST/splunk-persisted-data.tar.gz"
echo
ls -lh "$DEST"
