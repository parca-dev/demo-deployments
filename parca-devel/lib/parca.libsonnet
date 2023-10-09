local scrapeConfigs = import 'github.com/parca-dev/jsonnet-libs/scrape-configs/scrape-configs.libsonnet';
local p = import 'github.com/parca-dev/parca/deploy/lib/parca/parca.libsonnet';
local versions = std.parseYaml(importstr './versions.yaml');

local defaults = {
  name: 'parca-devel',
  namespace: 'parca-devel',
  version: versions.parca,
  image: 'ghcr.io/parca-dev/parca:' + self.version,
  replicas: 1,
  ingress: {
    class: 'nginx',
    hosts: error 'must provide ingress hosts',
    path: '/devel',
  },
  resources: {
    limits: {
      memory: '10Gi',
      'ephemeral-storage': '5Gi',
    },
    requests: {
      cpu: '2',
      memory: '10Gi',
      'ephemeral-storage': '5Gi',
    },
  },
  corsAllowedOrigins: '*',
  podProfilers: [
    {
      name: 'parca-agent-devel',
      namespace: $.namespace,
      podProfileEndpoints: [{
        port: 'http',
        relabelings: [
          {
            source_labels: ['__meta_kubernetes_pod_node_name'],
            target_label: 'instance',
          },
          {
            source_labels: ['__meta_kubernetes_service_label_app_kubernetes_io_version'],
            target_label: 'version',
          },
        ],
      }],
      selector: {
        matchLabels: {
          'app.kubernetes.io/name': 'parca-agent',
          'app.kubernetes.io/instance': 'parca-agent-devel',
          'app.kubernetes.io/component': 'observability',
        },
      },
    },
    {
      name: 'image-automation-controller',
      namespace: 'flux-system',
      podProfileEndpoints: [{
        port: 'http-prom',
        relabelings: [
          {
            source_labels: ['namespace', 'pod'],
            separator: '/',
            target_label: 'instance',
          },
        ],
      }],
      selector: {
        matchLabels: {
          'app.kubernetes.io/name': 'flux',
          'app.kubernetes.io/component': 'image-automation-controller',
        },
      },
    },
    {
      name: 'image-reflector-controller',
      namespace: 'flux-system',
      podProfileEndpoints: [{
        port: 'http-prom',
        relabelings: [
          {
            source_labels: ['namespace', 'pod'],
            separator: '/',
            target_label: 'instance',
          },
        ],
      }],
      selector: {
        matchLabels: {
          'app.kubernetes.io/name': 'flux',
          'app.kubernetes.io/component': 'image-reflector-controller',
        },
      },
    },
    {
      name: 'source-controller',
      namespace: 'flux-system',
      podProfileEndpoints: [{
        port: 'http-prom',
        relabelings: [
          {
            source_labels: ['namespace', 'pod'],
            separator: '/',
            target_label: 'instance',
          },
        ],
      }],
      selector: {
        matchLabels: {
          'app.kubernetes.io/name': 'flux',
          'app.kubernetes.io/component': 'source-controller',
        },
      },
    },
  ],
  serviceProfilers: [
    {
      name: $.name,
      namespace: $.namespace,
      endpoints: [{
        port: 'http',
        profilingConfig: {
          path_prefix: 'devel',
          pprof_config: {
            fgprof: {
              enabled: true,
              delta: true,
              path: '/debug/pprof/fgprof',
            },
          },
        },
        relabelings: [
          {
            source_labels: ['namespace', 'pod'],
            separator: '/',
            target_label: 'instance',
          },
          {
            source_labels: ['__meta_kubernetes_pod_label_app_kubernetes_io_version'],
            target_label: 'version',
          },
        ],
      }],
      selector: {
        matchLabels: $.podLabelSelector,
      },
    },
  ],
  config+:
    scrapeConfigs.generatePodProfilersConfig($.podProfilers) +
    scrapeConfigs.generateServiceProfilersConfig($.serviceProfilers),
};

function(params)
  local config = defaults + params;

  p(config) {
    clusterRole: {
      apiVersion: 'rbac.authorization.k8s.io/v1',
      kind: 'ClusterRole',
      metadata: {
        name: $.config.name,
        namespace: $.config.namespace,
        labels: $.config.commonLabels,
      },
      rules: [
        {
          apiGroups: [''],
          resources: ['services', 'endpoints', 'pods'],
          verbs: ['get', 'list', 'watch'],
        },
        {
          apiGroups: ['networking.k8s.io'],
          resources: ['ingresses'],
          verbs: ['get', 'list', 'watch'],
        },
      ],
    },

    clusterRoleBinding: {
      apiVersion: 'rbac.authorization.k8s.io/v1',
      kind: 'ClusterRoleBinding',
      metadata: {
        name: $.config.name,
        namespace: $.config.namespace,
        labels: $.config.commonLabels,
      },
      roleRef: {
        apiGroup: 'rbac.authorization.k8s.io',
        kind: 'ClusterRole',
        name: $.config.name,
      },
      subjects: [{
        kind: 'ServiceAccount',
        name: $.config.name,
        namespace: $.config.namespace,
      }],
    },

    deployment+: {
      spec+: {
        strategy: {
          // The demo cluster does not have enough memory
          // for running 2 Parca instances.
          type: 'Recreate',
        },
        template+: {
          spec+: {
            containers: [
              if c.name == 'parca' then c {
                // TODO: Make it easy to pass extra args upstream.
                args+: [
                  '--path-prefix=' + $.config.ingress.path,
                ],
              } else c
              for c in super.containers
            ],
            priorityClassName: 'system-cluster-critical',
          },
        },
      },
    },

    ingress: {
      apiVersion: 'networking.k8s.io/v1',
      kind: 'Ingress',
      metadata: {
        name: $.config.name,
        namespace: $.config.namespace,
        labels: $.config.commonLabels,
        annotations: {
          'nginx.ingress.kubernetes.io/backend-protocol': 'GRPC',
          // NGINX does not pass the CORS headers to the client when the backend
          // protocol is set to GRPC, even with `grpc_pass_header` in a
          // server-snippet annotation.
          // https://nginx.org/en/docs/http/ngx_http_grpc_module.html#grpc_pass_header
          'nginx.ingress.kubernetes.io/cors-allow-credentials': 'true',
          'nginx.ingress.kubernetes.io/cors-allow-headers': 'Content-Type, X-Grpc-Web',
          'nginx.ingress.kubernetes.io/cors-allow-methods': 'HEAD, GET, POST, PUT, PATCH, DELETE',
          'nginx.ingress.kubernetes.io/cors-allow-origin': 'https://demo.parca.dev, https://*.vercel.app, http://localhost:3000',
          'nginx.ingress.kubernetes.io/cors-expose-headers': 'Access-Control-Allow-Credentials, Access-Control-Allow-Origin, Grpc-Status, Grpc-Message, Content-Type, Date, Vary',
          'nginx.ingress.kubernetes.io/enable-cors': 'true',
        },
      },
      spec: {
        ingressClassName: $.config.ingress.class,
        rules: [
          {
            host: host,
            http: {
              paths: [{
                backend: {
                  service: {
                    name: $.config.name,
                    port: {
                      name: 'http',
                    },
                  },
                },
                path: $.config.ingress.path,
                pathType: 'Prefix',
              }],
            },
          }
          for host in $.config.ingress.hosts
        ],
      },
    },

    networkPolicy: {
      apiVersion: 'networking.k8s.io/v1',
      kind: 'NetworkPolicy',
      metadata: {
        name: $.config.name,
        namespace: $.config.namespace,
        labels: $.config.commonLabels,
      },
      spec: {
        egress: [{}],
        ingress: [{
          from: [
            {
              namespaceSelector: {
                matchLabels: {
                  'kubernetes.io/metadata.name': 'ingress-nginx',
                },
              },
              podSelector: {
                matchLabels: {
                  'app.kubernetes.io/name': 'ingress-nginx',
                  'app.kubernetes.io/component': 'controller',
                  'app.kubernetes.io/instance': 'ingress-nginx',
                },
              },
            },
            {
              podSelector: {
                matchLabels: {
                  'app.kubernetes.io/name': 'parca-agent',
                  'app.kubernetes.io/instance': 'parca-agent-devel',
                  'app.kubernetes.io/component': 'observability',
                },
              },
            },
          ],
          ports: [{
            port: 'http',
          }],
        }],
        podSelector: {
          matchLabels: $.config.podLabelSelector,
        },
        policyTypes: [
          'Egress',
          'Ingress',
        ],
      },
    },
  }
