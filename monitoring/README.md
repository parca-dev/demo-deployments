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

## Sending parca-analytics data to Polar Signals Cloud

The parca-analytics Prometheus has a second `remoteWrite` target pointing at
Polar Signals Cloud, alongside the primary write into its own local storage.
This used to be done via a Traefik `Mirroring` TraefikService duplicating every
HTTP request, which buffered each request body in memory until the mirror
completed — at this cluster's request volume, that OOM-killed Traefik outright.
Using Prometheus's own `remoteWrite` instead avoids that: it has its own
write-ahead queue with proper batching, backpressure and retries, and requires
no changes on the agents writing into this Prometheus.

The token is not committed to git — the `polarsignals-cloud` Secret is
committed with no `data` at all, matching the `objectStorageSecret` pattern
above. Once you have a Polar Signals Cloud API token, patch it in:

```bash
kubectl --namespace=parca-analytics create secret generic polarsignals-cloud \
  --from-literal=token=<token> --dry-run=client -o yaml \
  | kubectl apply -f -
```
