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

Use the following command to create it in the cluster.

```bash
kubectl -n parca-analytics create secret generic parca-analytics-objectstorage --from-file=thanos.yaml=/tmp/thanos.yaml
```

This will unblock the parca-analytics Prometheus Pod and it will start uploading data to the object storage.
