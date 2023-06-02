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
