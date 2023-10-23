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

function(params={}) {
  local cfg = commonConfig.config + params,

  local store = t.store(cfg {
    replicas: 1,
    serviceMonitor: true,
  }),
  store: store,

  query: t.query(cfg {
    replicas: 1,
    replicaLabels: ['prometheus_replica', 'rule_replica'],
    serviceMonitor: true,
    stores: [store.storeEndpoint, 'dnssrv+_grpc._tcp.prometheus-parca-analytics-thanos-sidecar.%s.svc.cluster.local' % cfg.namespace],
  }),
}
