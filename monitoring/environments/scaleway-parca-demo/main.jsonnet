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
      namespace: 'parca-analytics',
      namespaces: [],
      ingress: {
        class: 'nginx',
        hosts: ['analytics.parca.dev'],
      },
      thanos: {
        objectStorageConfig: {
          key: 'thanos.yaml',
          name: 'parca-analytics-objectstorage',
        },
      },
    },
  }) {
    local p = self,

    ingress: {
      apiVersion: 'networking.k8s.io/v1',
      kind: 'Ingress',
      metadata: {
        name: 'parca-analytics',
        namespace: 'parca-analytics',
        annotations: {
          'cert-manager.io/cluster-issuer': 'letsencrypt-prod',
          'nginx.ingress.kubernetes.io/auth-url': 'http://oauth2-proxy.oauth2-proxy.svc.cluster.local/oauth2/auth',
          'nginx.ingress.kubernetes.io/auth-signin': 'https://oauth2.parca.dev/oauth2/start',
        },
      },
      spec: {
        ingressClassName: p._config.ingress.class,
        rules: [
          {
            host: host,
            http: {
              paths: [{
                backend: {
                  service: {
                    name: p.service.metadata.name,
                    port: {
                      name: p.service.spec.ports[0].name,
                    },
                  },
                },
                path: '/',
                pathType: 'Prefix',
              }],
            },
          }
          for host in p._config.ingress.hosts
        ],
        tls: [
          {
            hosts: [host],
            secretName: host,
          }
          for host in p._config.ingress.hosts
        ],
      },
    },

    ingressRemoteWrite: {
      apiVersion: 'networking.k8s.io/v1',
      kind: 'Ingress',
      metadata: {
        name: 'parca-analytics-remote-write',
        namespace: 'parca-analytics',
        annotations: {
          'cert-manager.io/cluster-issuer': 'letsencrypt-prod',
        },
      },
      spec: {
        ingressClassName: p._config.ingress.class,
        rules: [
          {
            host: host,
            http: {
              paths: [{
                backend: {
                  service: {
                    name: p.service.metadata.name,
                    port: {
                      name: p.service.spec.ports[0].name,
                    },
                  },
                },
                path: '/api/v1/write',
                pathType: 'Prefix',
              }],
            },
          }
          for host in p._config.ingress.hosts
        ],
        tls: [
          {
            hosts: [host],
            secretName: host,
          }
          for host in p._config.ingress.hosts
        ],
      },
    },

    prometheus+: {
      spec+: {
        enableRemoteWriteReceiver: true,
        query+: {
          lookbackDelta: '15m',  // Analytics are only sent once every 10m
        },
        storage: {
          volumeClaimTemplate: {
            apiVersion: 'v1',
            kind: 'PersistentVolumeClaim',
            spec: {
              accessModes: ['ReadWriteOnce'],
              resources: { requests: { storage: '5Gi' } },
              storageClassName: 'scw-bssd-retain',
            },
          },
        },
      },
    },

    // We do not monitor k8s metrics with this instance.
    clusterRole:: {},
    clusterRoleBinding:: {},
  },
];

local prometheusOperator = m.prometheusOperator();

local kubeThanos = m.kubeThanos({
  namespace: 'parca-analytics',
});

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
    ] +
    [kubeThanos.query[name] for name in std.objectFields(kubeThanos.query)] +
    [kubeThanos.store[name] for name in std.objectFields(kubeThanos.store)],
}
