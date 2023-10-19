local t = import 'github.com/thanos-io/kube-thanos/jsonnet/kube-thanos/thanos.libsonnet';

local commonConfig = {
  config+:: {
    local cfg = self,
    namespace: 'monitoring',
    // renovate: datasource=docker depName=quay.io/thanos/thanos extractVersion=v(?<version>.*)$
    version: 'v0.32.5',
    image: 'quay.io/thanos/thanos:' + cfg.version,
    imagePullPolicy: 'IfNotPresent',
    objectStorageConfig: {
      name: 'thanos-objectstorage',
      key: 'thanos.yaml',
    },
  },
};

local s = t.store(commonConfig.config {
  replicas: 1,
  serviceMonitor: true,
});

local q = t.query(commonConfig.config {
  replicas: 1,
  replicaLabels: ['prometheus_replica', 'rule_replica'],
  serviceMonitor: true,
  stores: [s.storeEndpoint],
});

{ ['thanos-store-' + name]: s[name] for name in std.objectFields(s) } +
{ ['thanos-query-' + name]: q[name] for name in std.objectFields(q) }
