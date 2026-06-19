local p = import 'main.libsonnet';

local pyrra = p.pyrra({
  namespace: 'monitoring',
  // renovate: datasource=docker depName=ghcr.io/pyrra-dev/pyrra extractVersion=^v(?<version>.*)$
  version: '0.10.0',
  prometheusURL: 'http://prometheus-parca.monitoring.svc.cluster.local:9090',
  ingressHosts: ['pyrra.parca.dev'],
});

{
  apiVersion: 'v1',
  kind: 'List',
  items: [
    pyrra[name]
    for name in std.objectFields(pyrra)
    // SLO definitions come later; only ship the Pyrra components for now.
    if !std.startsWith(name, 'slo-')
  ],
}
