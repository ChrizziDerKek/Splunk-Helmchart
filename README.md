# Splunk Helm chart v0.4.0

This revision is intentionally conservative for the existing production Splunk.

## Important: do not use v0.3.0 for the migration

v0.4.0 restores the two production requirements that must not change:

1. the exact Java-enabled custom image behavior;
2. Traefik BasicAuth explicitly attached to the Splunk Web Ingress.

## Known-good Enterprise image

Production uses:

```text
splunk-custom:10.0.1-java-v2
```

built from the included exact Dockerfile:

```dockerfile
FROM docker.io/splunk/splunk:10.0.1

USER root

RUN microdnf install -y java-17-openjdk-headless || \
    dnf install -y java-17-openjdk-headless || \
    yum install -y java-17-openjdk-headless
```

This is deliberately retained rather than substituting a different Java
injection mechanism.

Build/import on a fresh k3s node:

```bash
./build/build-and-import-enterprise.sh
```

For a truly one-command install on arbitrary nodes, publish this custom image to
a registry and override `enterprise.image.repository` / `pullPolicy`.

Helm itself does not build container images.

## BasicAuth

Enterprise mode defaults to BasicAuth enabled and attached to the Ingress.

Fresh installs create `Secret/splunk-basic-auth` themselves using Helm's
`htpasswd` function and a generated password.

The production migration profile instead references the existing
`splunk-basic-auth` Secret without modifying it.

## Why production should be adopted rather than rebuilt

The existing persistent data already lives at the desired final paths:

```text
/k3s/splunk/data/etc
/k3s/splunk/data/var
```

and is already bound through:

```text
splunk-etc-pv -> splunk-etc
splunk-var-pv -> splunk-var
```

Therefore the least-risk migration is:

1. make a complete offline backup;
2. leave the data/PVs/PVCs exactly where they are;
3. render and diff the migration profile;
4. let Helm take ownership of the existing Kubernetes objects.

There is no copy/restore step unless rollback or disaster recovery is needed.

## Complete backup first

Run only this initially:

```bash
./scripts/00-preflight-current.sh data-stack
./scripts/01-backup-everything-offline.sh data-stack
```

The backup includes:

- complete `/k3s/splunk/data/etc`;
- complete `/k3s/splunk/data/var`;
- PV/PVC definitions;
- StatefulSet/Pod definitions;
- Services;
- Ingress;
- BasicAuth Middleware;
- `splunk-secret`;
- `splunk-basic-auth`;
- TLS Secret when present;
- index list;
- KV Store status;
- app list;
- Splunk version;
- Java version;
- current image name;
- an export of the current custom image when containerd can resolve it.

The filesystem backup is taken with Splunk stopped.

## Dry-run before adoption

After verifying the backup:

```bash
./scripts/02-adoption-dry-run.sh data-stack
```

The migration profile must retain:

```text
image: splunk-custom:10.0.1-java-v2
startupMode: legacy
storageClassName: splunk-local
PV: splunk-etc-pv / splunk-var-pv
PVC: splunk-etc / splunk-var
paths: /k3s/splunk/data/etc /var
```

The intentional networking change is that the Ingress explicitly references:

```text
data-stack-splunk-basic-auth@kubernetescrd
```

## Adopt only after the diff is understood

The migration profile does NOT render the existing Secrets, so Helm cannot
change their data.

When ready:

```bash
helm upgrade --install splunk \
  /k3s/splunk/helm/splunk \
  -n data-stack \
  -f /k3s/splunk/helm/splunk/values-migration.yaml \
  --take-ownership \
  --wait \
  --timeout 20m
```

Then:

```bash
./scripts/03-verify-after-adoption.sh data-stack
```

## Fresh standalone Enterprise deployment

A new server has no old Secrets/PVs/PVCs.

First build/import the included Java-enabled image:

```bash
./build/build-and-import-enterprise.sh
```

Then install the chart using normal `values.yaml`:

```bash
helm install splunk ./ \
  -n data-stack \
  --create-namespace \
  --wait \
  --timeout 20m
```

Fresh mode creates:

- Splunk admin Secret;
- BasicAuth Secret;
- BasicAuth Middleware;
- StorageClass;
- both PVs/PVCs;
- StatefulSet;
- Services;
- TLS Ingress.

Adjust the local node hostname and host paths in values before deploying on a
different machine.

## Universal Forwarder mode

The same chart can deploy a Universal Forwarder without the Enterprise image,
Java, Web, HEC, Ingress, or BasicAuth.

Start from:

```text
values-forwarder.yaml
```

Example:

```bash
helm install splunk-forwarder ./ \
  -n splunk-forwarder \
  --create-namespace \
  -f values-forwarder.yaml
```

Forwarder mode uses the official:

```text
splunk/universalforwarder:10.0.1
```

and supports:

- `SPLUNK_STANDALONE_URL`;
- `SPLUNK_INDEXER_URL`;
- `SPLUNK_DEPLOYMENT_SERVER`;
- `SPLUNK_ADD`;
- `SPLUNK_CMD`;
- configurable hostPath log mounts;
- optional root mode for reading protected host logs.

Universal Forwarder has no Splunk Web, so BasicAuth/Ingress are intentionally
not created in that mode.
