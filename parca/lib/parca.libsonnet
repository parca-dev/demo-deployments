local p = import 'github.com/parca-dev/parca/deploy/lib/parca/parca.libsonnet';

local defaults = {
  namespace: 'parca',
  // renovate: datasource=docker depName=ghcr.io/parca-dev/parca
  version: 'v0.18.0@sha256:39fc8bd1432ca0cf424ead49bb22fb4d99b767960220de86a59237e4b3fca901',
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

    // Hide PSP: Removed in K8s 1.25
    // TODO: Clean up after next release
    podSecurityPolicy:: {},

    ingress: {
      apiVersion: 'networking.k8s.io/v1',
      kind: 'Ingress',
      metadata: {
        name: $.config.name,
        namespace: $.config.namespace,
        labels: $.config.commonLabels,
        annotations: {
          'cert-manager.io/cluster-issuer': 'letsencrypt-prod',
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
