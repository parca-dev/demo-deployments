local m = import 'main.libsonnet';

local kubeThanos = m.kubeThanos({
  namespace: 'parca-analytics',
  objectStorageConfig: {
    key: 'thanos.yaml',
    name: 'parca-analytics-objectstorage',
  },
  volumeClaimTemplate: {
    apiVersion: 'v1',
    kind: 'PersistentVolumeClaim',
    spec: {
      accessModes: ['ReadWriteOnce'],
      resources: { requests: { storage: '10Gi' } },
      storageClassName: 'scw-bssd-retain',
    },
  },
}) + {
  query+: {
    networkPolicy+: {
      spec+: {
        ingress: [
          {
            from: [{
              namespaceSelector: { matchLabels: { 'kubernetes.io/metadata.name': 'ingress-nginx' } },
              podSelector: {
                matchLabels: {
                  'app.kubernetes.io/component': 'controller',
                  'app.kubernetes.io/instance': 'ingress-nginx',
                  'app.kubernetes.io/name': 'ingress-nginx',
                },
              },
            }, {
              namespaceSelector: { matchLabels: { 'kubernetes.io/metadata.name': 'traefik' } },
              podSelector: { matchLabels: { 'app.kubernetes.io/name': 'traefik' } },
            }],
            ports: [{ port: 'http', protocol: 'TCP' }],
          },
        ],
      },
    },
  },
};

local prometheuses = [
  m.prometheus({
    prometheus+:: {
      name: 'parca',
      // RBAC (Role/RoleBinding) to list/watch pods,services,endpoints is only
      // generated for namespaces listed here, regardless of what the Prometheus
      // CR's podMonitorNamespaceSelector/serviceMonitorNamespaceSelector match.
      namespaces: ['parca', 'parca-devel', 'traefik', 'ingress-nginx', 'monitoring', 'parca-analytics'],
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
        image: 'quay.io/thanos/thanos:%s' % self.version,
        // renovate: datasource=docker depName=quay.io/thanos/thanos
        version: 'v0.40.1',
        objectStorageConfig: {
          key: 'thanos.yaml',
          name: 'parca-analytics-objectstorage',
        },
        resources+: {
          limits+: {
            memory: '64Mi',
          },
          requests+: {
            cpu: '50m',
            memory: '64Mi',
          },
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
        namespace: p._config.namespace,
        labels: p._config.commonLabels,
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
                    name: kubeThanos.query.service.metadata.name,
                    port: {
                      name: kubeThanos.query.service.spec.ports[1].name,
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

    // First route in this repo on Traefik-native CRDs (IngressRoute) rather than the
    // nginx-compat Ingress provider — a scoped start ahead of the broader
    // native-Traefik migration.
    //
    // Mirrors parca-analytics remote-write traffic to Polar Signals Cloud, in addition
    // to the primary write into this Prometheus.
    polarSignalsCloudService: {
      apiVersion: 'v1',
      kind: 'Service',
      metadata: {
        name: 'polarsignals-cloud',
        namespace: p._config.namespace,
        labels: p._config.commonLabels,
      },
      spec: {
        type: 'ExternalName',
        externalName: 'cloud.polarsignals.com',
        ports: [{ name: 'https', port: 443 }],
      },
    },

    polarSignalsCloudServersTransport: {
      apiVersion: 'traefik.io/v1alpha1',
      kind: 'ServersTransport',
      metadata: {
        name: 'polarsignals-cloud',
        namespace: p._config.namespace,
        labels: p._config.commonLabels,
      },
      spec: {
        serverName: 'cloud.polarsignals.com',
      },
    },

    // Real Authorization/project-ID header values are patched onto this live, see
    // monitoring/README.md; committed empty here, matching the empty-shell pattern
    // used by objectStorageSecret below. Traefik runs this Middleware once, before
    // the mirroring service fans the request out, so both the primary write and the
    // mirrored copy receive these headers — harmless, since the local Prometheus
    // remote-write receiver has no auth configured and ignores headers it doesn't
    // recognize.
    remoteWriteHeadersMiddleware: {
      apiVersion: 'traefik.io/v1alpha1',
      kind: 'Middleware',
      metadata: {
        name: 'psc-remote-write-headers',
        namespace: p._config.namespace,
        labels: p._config.commonLabels,
      },
      spec: {
        headers: {
          customRequestHeaders: {},
        },
      },
    },

    remoteWriteMirror: {
      apiVersion: 'traefik.io/v1alpha1',
      kind: 'TraefikService',
      metadata: {
        name: 'parca-analytics-mirror',
        namespace: p._config.namespace,
        labels: p._config.commonLabels,
      },
      spec: {
        mirroring: {
          name: p.service.metadata.name,
          port: 9090,
          mirrorBody: true,
          // Bound the mirror buffer (Traefik's memory has been unstable on this
          // cluster). Batches larger than this are simply not mirrored; the
          // primary write into the local Prometheus is unaffected either way.
          maxBodySize: 4194304,
          mirrors: [{
            name: p.polarSignalsCloudService.metadata.name,
            port: 443,
            scheme: 'https',
            serversTransport: p.polarSignalsCloudServersTransport.metadata.name,
            percent: 100,
          }],
        },
      },
    },

    remoteWriteIngressRoute: {
      apiVersion: 'traefik.io/v1alpha1',
      kind: 'IngressRoute',
      metadata: {
        name: p._config.name + '-remote-write',
        namespace: p._config.namespace,
        labels: p._config.commonLabels,
      },
      spec: {
        entryPoints: ['websecure'],
        routes: [
          {
            kind: 'Rule',
            match: 'Host(`%s`) && PathPrefix(`/api/v1/write`)' % host,
            middlewares: [{ name: p.remoteWriteHeadersMiddleware.metadata.name }],
            services: [{
              name: p.remoteWriteMirror.metadata.name,
              kind: 'TraefikService',
            }],
          }
          for host in p._config.ingress.hosts
        ],
        // spec.tls is a single object (unlike Ingress' tls list); ingress.hosts has
        // exactly one entry (analytics.parca.dev), which is also the cert secret name.
        tls: {
          secretName: p._config.ingress.hosts[0],
        },
      },
    },

    prometheus+: {
      spec+: {
        enableRemoteWriteReceiver: true,
        // This instance only ingests via remote-write and monitors its own Thanos
        // components. The default {} selectors match every PodMonitor/ServiceMonitor
        // cluster-wide, which would pull in unrelated apps (parca-agent, pyrra, ...).
        podMonitorNamespaceSelector: { matchLabels: { 'kubernetes.io/metadata.name': p._config.namespace } },
        serviceMonitorNamespaceSelector: { matchLabels: { 'kubernetes.io/metadata.name': p._config.namespace } },
        resources+: {
          requests+: { cpu: '500m' },
        },
        containers: [
          {
            name: 'prometheus',
            livenessProbe: { timeoutSeconds: 10, periodSeconds: 10, failureThreshold: 12 },
            readinessProbe: { timeoutSeconds: 10, periodSeconds: 10, failureThreshold: 12 },
          },
        ],
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

    objectStorageSecret: {
      apiVersion: 'v1',
      kind: 'Secret',
      metadata: {
        name: p._config.name + '-objectstorage',
        namespace: p._config.namespace,
        labels: p._config.commonLabels,
      },
    },

    networkPolicy+: {
      spec+: {
        ingress+: [{
          from: [{
            namespaceSelector: { matchLabels: { 'kubernetes.io/metadata.name': p._config.namespace } },
            podSelector: { matchLabels: { 'app.kubernetes.io/name': 'thanos-query' } },
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
    ] +
    [kubeThanos.query[name] for name in std.objectFields(kubeThanos.query)] +
    [kubeThanos.store[name] for name in std.objectFields(kubeThanos.store)],
}
