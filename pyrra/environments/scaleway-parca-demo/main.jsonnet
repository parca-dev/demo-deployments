local p = import 'main.libsonnet';

local pyrra = p.pyrra({
  namespace: 'monitoring',
  // renovate: datasource=docker depName=ghcr.io/pyrra-dev/pyrra extractVersion=^v(?<version>.*)$
  version: '0.10.0',
  prometheusURL: 'http://prometheus-parca.monitoring.svc.cluster.local:9090',
  ingressHosts: ['pyrra.parca.dev'],
});

// SLO for the Parca Agent writing profiles to the Parca server. This is the
// core data path of the demo: agents continuously push profiles via the
// ProfileStore Write gRPC method, so a high error rate there means the
// user-facing pipeline is broken. The metric comes from the parca-agent
// PodMonitors, which are the only thing this Prometheus currently scrapes.
local writeAvailabilitySLO(name, job, description) = {
  local writeMetric = 'grpc_client_handled_total{job="%s",grpc_service="parca.profilestore.v1alpha1.ProfileStoreService",grpc_method="Write"%s}',
  apiVersion: 'pyrra.dev/v1alpha1',
  kind: 'ServiceLevelObjective',
  metadata: {
    name: name,
    namespace: 'monitoring',
    labels: {
      'app.kubernetes.io/name': 'pyrra',
      'app.kubernetes.io/component': 'slo',
    },
  },
  spec: {
    target: '99.9',
    window: '4w',
    description: description,
    indicator: {
      ratio: {
        errors: { metric: writeMetric % [job, ',grpc_code!="OK"'] },
        total: { metric: writeMetric % [job, ''] },
      },
    },
  },
};

local slos = [
  writeAvailabilitySLO(
    'parca-agent-write-availability',
    'parca/parca-agent',
    'Parca Agent writes profiles to the Parca server via ProfileStore Write.',
  ),
];

{
  apiVersion: 'v1',
  kind: 'List',
  items: [
    pyrra[name]
    for name in std.objectFields(pyrra)
    // The upstream example SLOs target cluster components we do not scrape.
    if !std.startsWith(name, 'slo-')
  ] + slos,
}
