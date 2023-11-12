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
