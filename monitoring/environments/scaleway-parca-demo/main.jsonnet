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
    local p = self,

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

    // The base library hides self-monitoring for every instance (see
    // monitoring/lib/prometheus.libsonnet). This instance is the one that
    // should scrape itself, so re-add it explicitly.
    serviceMonitorSelf: {
      apiVersion: 'monitoring.coreos.com/v1',
      kind: 'ServiceMonitor',
      metadata: {
        name: 'prometheus-parca',
        namespace: p._config.namespace,
        labels: p._config.commonLabels,
      },
      spec: {
        selector: { matchLabels: p.service.spec.selector },
        endpoints: [
          { port: 'web', interval: '30s' },
          { port: 'reloader-web', interval: '30s' },
        ],
      },
    },

    // parca-analytics does not scrape itself (see below), so this instance
    // scrapes it instead. Lives here, in this namespace, rather than in
    // parca-analytics, so parca-analytics' own namespace-scoped
    // serviceMonitorNamespaceSelector never discovers it.
    serviceMonitorParcaAnalytics: {
      apiVersion: 'monitoring.coreos.com/v1',
      kind: 'ServiceMonitor',
      metadata: {
        name: 'prometheus-parca-analytics',
        namespace: p._config.namespace,
        labels: p._config.commonLabels,
      },
      spec: {
        namespaceSelector: { matchNames: ['parca-analytics'] },
        selector: {
          matchLabels: {
            'app.kubernetes.io/component': 'prometheus',
            'app.kubernetes.io/instance': 'parca-analytics',
            'app.kubernetes.io/name': 'prometheus',
            'app.kubernetes.io/part-of': 'kube-prometheus',
          },
        },
        endpoints: [
          { port: 'web', interval: '30s' },
          { port: 'reloader-web', interval: '30s' },
        ],
      },
    },
  },
  m.prometheus({
    prometheus+:: {
      name: 'parca-analytics',
      namespace: 'parca-analytics',
      namespaces: ['parca-analytics'],
      ingress: {
        class: 'nginx',
        hosts: ['analytics.parca.dev'],
      },
      thanos: {
        image: 'quay.io/thanos/thanos:%s' % self.version,
        // renovate: datasource=docker depName=quay.io/thanos/thanos
        version: 'v0.42.0',
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
        externalName: 'api.polarsignals.com',
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
        serverName: 'api.polarsignals.com',
        // Without these, Traefik's HTTP client waits indefinitely for a slow/dead
        // mirror target. Since mirrorBody buffers each request's full body in memory
        // until the mirror completes or fails, an unresponsive Polar Signals Cloud
        // endpoint queues up buffered bodies faster than they're freed at this
        // request volume (~1.8k req/s) and OOM-kills Traefik within seconds. Failing
        // fast bounds how long any single request can hold its buffer.
        forwardingTimeouts: {
          dialTimeout: '5s',
          responseHeaderTimeout: '5s',
          idleConnTimeout: '30s',
        },
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
            percent: 0,
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
        remoteWrite: [{
          url: 'https://api.polarsignals.com/api/v1/write',
          authorization: {
            credentials: { name: p.polarSignalsCloudSecret.metadata.name, key: 'token' },
          },
          headers: {
            projectID: '5a755043-1fb8-48fd-a2c8-2787498ec59d',
          },
        }],
        // This instance only ingests via remote-write; it does not scrape anything,
        // including its own Thanos sidecar/query/store (that's the parca instance's
        // job, see monitoring's serviceMonitorParcaAnalytics). The default {}
        // selectors match every PodMonitor/ServiceMonitor cluster-wide, so without
        // this it would also pick up unrelated apps (parca-agent, pyrra, ...) plus
        // its own Thanos components. `In: []` never matches, regardless of labels.
        podMonitorNamespaceSelector: { matchLabels: { 'kubernetes.io/metadata.name': p._config.namespace } },
        serviceMonitorNamespaceSelector: { matchLabels: { 'kubernetes.io/metadata.name': p._config.namespace } },
        podMonitorSelector: { matchExpressions: [{ key: 'prometheus', operator: 'In', values: [] }] },
        serviceMonitorSelector: { matchExpressions: [{ key: 'prometheus', operator: 'In', values: [] }] },
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

    polarSignalsCloudSecret: {
      apiVersion: 'v1',
      kind: 'Secret',
      metadata: {
        name: 'polarsignals-cloud',
        namespace: p._config.namespace,
        labels: p._config.commonLabels,
      },
    },

    polarSignalsCloudRemoteWriteSLO: {
      apiVersion: 'pyrra.dev/v1alpha1',
      kind: 'ServiceLevelObjective',
      metadata: {
        name: p._config.name + '-remote-write',
        namespace: p._config.namespace,
        labels: p._config.commonLabels { 'app.kubernetes.io/component': 'slo' },
      },
      spec: {
        target: '99',
        window: '4w',
        description: 'Samples remote-written to Polar Signals Cloud are not dropped.',
        indicator: {
          ratio: {
            errors: { metric: 'prometheus_remote_storage_samples_failed_total{url="https://api.polarsignals.com/api/v1/write"}' },
            total: { metric: 'prometheus_remote_storage_samples_total{url="https://api.polarsignals.com/api/v1/write"}' },
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
        }, {
          // Scraped by the parca Prometheus (parca-analytics does not scrape itself).
          from: [{
            namespaceSelector: { matchLabels: { 'kubernetes.io/metadata.name': 'monitoring' } },
            podSelector: {
              matchLabels: {
                'app.kubernetes.io/component': 'prometheus',
                'app.kubernetes.io/instance': 'parca',
                'app.kubernetes.io/name': 'prometheus',
                'app.kubernetes.io/part-of': 'kube-prometheus',
              },
            },
          }],
          ports: [{ port: 'web' }, { port: 'reloader-web' }],
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
