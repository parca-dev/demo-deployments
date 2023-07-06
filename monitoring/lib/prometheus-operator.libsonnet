local kp = import 'github.com/prometheus-operator/kube-prometheus/jsonnet/kube-prometheus/main.libsonnet';

local defaults = {
  prometheusOperator+: {
    namespace: 'monitoring',
  },
};

function(params={}) (
  kp {
    values+:: defaults + params,

    prometheusOperator+: {
      local po = self,

      deployment+: {
        spec+: {
          template+: {
            spec+: {
              securityContext+: {
                seccompProfile+: {
                  // TODO: contribute seccompProfile to upstream
                  type: 'RuntimeDefault',
                },
              },
            },
          },
        },
      },

      // Hide
      prometheusRule:: {},

      networkPolicy: {
        apiVersion: 'networking.k8s.io/v1',
        kind: 'NetworkPolicy',
        metadata: {
          name: 'prometheus-operator',
          namespace: po._config.namespace,
          labels: po._config.commonLabels,
        },
        spec: {
          egress: [{}],
          podSelector: {
            matchLabels: po._config.selectorLabels,
          },
          policyTypes: ['Egress'],
        },
      },

      serviceMonitor:: {},
    },
  }
).prometheusOperator
