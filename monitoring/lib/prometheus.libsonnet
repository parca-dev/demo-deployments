local kp = import 'github.com/prometheus-operator/kube-prometheus/jsonnet/kube-prometheus/main.libsonnet';

local defaults = {
  common+: {
    versions+: {
      // renovate: datasource=docker depName=quay.io/prometheus/prometheus extractVersion=v(?<version>.*)$
      prometheus: '2.45.0',
    },
  },
  prometheus+: {
    namespace: 'monitoring',
    replicas: 1,
    commonLabels+: {
      'app.kubernetes.io/instance': $.prometheus.name,
    },
    alerting: {
      alertmanagers: [],
    },
    enableFeatures: ['native-histograms'],
    resources+: {
      limits+: {
        memory: '512Mi',
      },
      requests+: {
        cpu: '100m',
        memory: '512Mi',
      },
    },
  },
};

function(params={}) (
  kp {
    values+:: defaults + params,

    prometheus+: {
      local p = self,

      prometheus+: {
        spec+: {
          securityContext+: {
            // TODO: contribute seccompProfile to upstream
            seccompProfile+: { type: 'RuntimeDefault' },
          },
        },
      },

      // Hide
      prometheusRule:: {},

      networkPolicy: {
        apiVersion: 'networking.k8s.io/v1',
        kind: 'NetworkPolicy',
        metadata: {
          name: 'prometheus-' + p._config.name,
          namespace: p._config.namespace,
          labels: p._config.commonLabels,
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
            ],
            ports: [{
              port: 'web',
            }],
          }],
          podSelector: {
            matchLabels: p._config.selectorLabels,
          },
          policyTypes: [
            'Egress',
            'Ingress',
          ],
        },
      },

      serviceMonitor:: {},
    },
  }
).prometheus
