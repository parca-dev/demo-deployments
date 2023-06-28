local m = import 'main.libsonnet';

local prometheuses = [
  m.prometheus({
    prometheus+:: {
      name: 'parca',
      namespaces: ['parca', 'parca-devel'],
    },
  }) {
    prometheus+: {
      spec+: {
        remoteWrite: [{
          url: 'https://demo.pyrra.dev/prometheus/api/v1/write',
          writeRelabelConfigs: [{
            action: 'keep',
            regex: 'parca(|-devel)/parca-agent(|-devel)',
            sourceLabels: ['job'],
          }],
        }],
      },
    },

    // We do not monitor k8s metrics with this instance.
    clusterRole:: {},
    clusterRoleBinding:: {},
  },
  m.prometheus({
    prometheus+:: {
      name: 'parca-analytics',
      namespaces: ['parca-analytics'],
    },
  }) {
    local p = self,

    namespace: {
      apiVersion: 'v1',
      kind: 'Namespace',
      metadata: {
        name: 'parca-analytics',
      },
    },

    ingressRemoteWrite: {
      apiVersion: 'networking.k8s.io/v1',
      kind: 'Ingress',
      metadata: {
        name: 'parca-analytics',
        namespace: 'parca-analytics',
      },
      spec: {
        tls: [{
          secretName: 'analytics.parca.dev',
          hosts: [
            'analytics.parca.dev',
          ],
        }],
        rules: [{
          host: 'analytics.parca.dev',
          http: {
            paths: [
              {
                path: '/api/v1/write',
                pathType: 'Prefix',
                backend: {
                  service: {
                    name: p.service.metadata.name,
                    port: {
                      number: p.service.spec.ports[0].port,
                    },
                  },
                },
              },
            ],
          },
        }],
      },
    },

    prometheus+: {
      spec+: {
        enableRemoteWriteReceiver: true,
        query+: {
          lookbackDelta: '15m',  // Analytics are only sent once every 10m
        },
      },
    },

    // We do not monitor k8s metrics with this instance.
    clusterRole:: {},
    clusterRoleBinding:: {},
  },
];

local prometheusOperator = m.prometheusOperator();

{
  apiVersion: 'v1',
  kind: 'List',
  items:
    [prometheusOperator[name] for name in std.objectFields(prometheusOperator)] +
    // an APIResourceList can only have APIResource items
    [
      item
      for prometheus in prometheuses
      for name in std.objectFields(prometheus)
      if std.setMember(prometheus[name].kind, ['RoleBindingList', 'RoleList'])
      for item in prometheus[name].items
    ] +
    [
      prometheus[name]
      for prometheus in prometheuses
      for name in std.objectFields(prometheus)
      if !std.setMember(prometheus[name].kind, ['RoleBindingList', 'RoleList'])
    ],
}
