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
