local g = import 'grafana.libsonnet';

local grafana = g({
  namespace: 'parca',
  datasources+: [
    {
      access: 'proxy',
      editable: false,
      name: 'Parca - PolarSignals',
      orgId: 1,
      type: 'parca-datasource',
      version: 1,
      jsonData: { APIEndpoint: 'https://demo.parca.dev' },
    },
    {
      name: 'Parca - Grafana',
      type: 'parca',
      url: 'https://demo.parca.dev',
      editable: false,
    },
  ],
  ingress+: {
    class: 'nginx',
    hosts: ['demo.parca.dev'],
  },
});

{
  apiVersion: 'v1',
  kind: 'List',
  items:
    // an APIResourceList can only have APIResource items
    [
      item
      for name in std.objectFields(grafana)
      if grafana[name].kind == 'ConfigMapList'
      for item in grafana[name].items
    ] +
    [
      grafana[name]
      for name in std.objectFields(grafana)
      if grafana[name].kind != 'ConfigMapList'
    ],
}
