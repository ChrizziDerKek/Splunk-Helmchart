#!/usr/bin/env bash
set -euo pipefail
NS="${1:-data-stack}"

echo "=== Current Splunk resources ==="
kubectl get sts splunk -n "$NS"
kubectl get pod splunk-0 -n "$NS"
kubectl get svc splunk-web splunk-hec splunk-management -n "$NS"
kubectl get pvc splunk-etc splunk-var -n "$NS" -o wide
kubectl get pv splunk-etc-pv splunk-var-pv -o wide
kubectl get secret splunk-secret -n "$NS" >/dev/null
kubectl get secret splunk-basic-auth -n "$NS" >/dev/null
kubectl get middleware splunk-basic-auth -n "$NS" >/dev/null
kubectl get ingress splunk-web -n "$NS"

echo
echo "=== Current image ==="
kubectl get sts splunk -n "$NS" \
  -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'

echo
echo "=== Host data ==="
sudo du -sh /k3s/splunk/data/etc /k3s/splunk/data/var

echo
echo "=== Java in current Pod ==="
kubectl exec -n "$NS" splunk-0 -- sh -c \
  'command -v java; java -version'
