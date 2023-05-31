local p = import 'github.com/parca-dev/parca/deploy/lib/parca/parca.libsonnet';

local defaults = {
  namespace: 'parca',
  // renovate: datasource=docker depName=ghcr.io/parca-dev/parca
  version: 'v0.17.0',
  image: 'ghcr.io/parca-dev/parca:' + self.version,
  replicas: 1,
  ingress: {
    class: 'nginx',
    hosts: error 'must provide ingress hosts',
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
};

function(params)
  local config = defaults + params;

  p(config) {
    deployment+: {
      spec+: {
        strategy: {
          // The demo cluster does not have enough memory
          // for running 2 Parca instances.
          type: 'Recreate',
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
          'kubernetes.io/ingress.class': $.config.ingress.class,
        },
      },
      spec: {
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
                path: '/',
                pathType: 'Prefix',
              }],
            },
          }
          for host in $.config.ingress.hosts
        ],
        tls: [
          {
            hosts: [host],
            secretName: std.strReplace(host, '.', '-') + '-tls',
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
                  'app.kubernetes.io/instance': 'parca-agent',
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
