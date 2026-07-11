# monitoring

See https://github.com/prometheus-operator/kube-prometheus

## Thanos

Create the object storage bucket `parca-analytics` gets created outside this repository, e.g. through terraform.

Once it exists create a new API Keys through the Scaleway UI: https://console.scaleway.com/iam/api-keys

This will create an `Access Key ID` and `Secret Key` for you.
Copy these into a file like the following (in the example stored as `/tmp/thanos.yaml`)

```yaml
type: s3
config:
  bucket: parca-analytics
  endpoint: s3.nl-ams.scw.cloud
  access_key: XXX
  secret_key: XXX
```

Use the following command to patch it into the cluster.

```bash
jq -Rs '{"data": {"thanos.yaml": .|@base64 }}' /tmp/thanos.yaml \
  | kubectl patch --namespace=parca-analytics secret parca-analytics-objectstorage --patch-file=/dev/stdin
```

This will unblock the parca-analytics Prometheus Pod and it will start uploading data to the object storage.

## Mirroring parca-analytics remote-write to Polar Signals Cloud

`analytics.parca.dev/api/v1/write` mirrors every remote-write request to Polar
Signals Cloud in addition to the primary write into the local Prometheus, via a
Traefik `Mirroring` TraefikService. The `Authorization`/project-ID headers added to
the mirrored (and, unavoidably, the primary) request are not committed to git —
the `psc-remote-write-headers` Middleware is committed with an empty
`customRequestHeaders`, and the ArgoCD `monitoring` Application has an
`ignoreDifferences` entry for that field so live patches survive future syncs.

Once you have a Polar Signals Cloud API token and project ID, patch them in:

```bash
kubectl --namespace=parca-analytics patch middleware psc-remote-write-headers \
  --type=merge -p '{"spec":{"headers":{"customRequestHeaders":{
    "Authorization":"Bearer <token>","<project-id-header>":"<project-id>"
  }}}}'
```

## Sending parca-analytics data to Polar Signals Cloud via remoteWrite

The parca-analytics Prometheus has a second `remoteWrite` target pointing
directly at Polar Signals Cloud. The token is not committed to git, and unlike
`objectStorageSecret`, the `polarsignals-cloud` Secret isn't declared in git
at all — it's created directly in the cluster and left untracked by ArgoCD,
so a sync can never prune or reset it. Once you have a Polar Signals Cloud API
token, create it:

```bash
kubectl --namespace=parca-analytics create secret generic polarsignals-cloud \
  --from-literal=token=<token>
```

If the Secret already exists with ArgoCD's `argocd.argoproj.io/tracking-id`
annotation on it (e.g. left over from before this Secret was untracked),
remove that annotation so `prune: true` syncs leave it alone:

```bash
kubectl --namespace=parca-analytics annotate secret polarsignals-cloud \
  argocd.argoproj.io/tracking-id-
```
