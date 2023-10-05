local pa = import 'github.com/parca-dev/parca-agent/deploy/lib/parca-agent/parca-agent.libsonnet';

local defaults = {
  namespace: 'parca',
  // renovate: datasource=docker depName=ghcr.io/parca-dev/parca-agent
  version: 'v0.26.0',
  image: 'ghcr.io/parca-dev/parca-agent:' + self.version,
  stores: ['parca.%s.svc.cluster.local:7070' % self.namespace],
  insecure: true,
  insecureSkipVerify: true,
  logLevel: 'debug',
  resources: {
    limits: {
      cpu: '100m',
      memory: '512Mi',
    },
    requests: {
      cpu: '10m',
      memory: '128Mi',
    },
  },
  podMonitor: true,
};

function(params={})
  local config = defaults + params;

  pa(config) {
    daemonSet+: {
      spec+: {
        template+: {
          spec+: {
            containers: [
              if c.name == 'parca-agent' then c {
                // TODO: Make it easy to pass extra args upstream.
                args+: [
                  '--bpf-verbose-logging',
                ],
              } else c
              for c in super.containers
            ],
            priorityClassName: 'system-node-critical',
          },
        },
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
                  'kubernetes.io/metadata.name': 'monitoring',
                },
              },
              podSelector: {
                matchLabels: {
                  'app.kubernetes.io/name': 'prometheus',
                },
              },
            },
          ],
          ports: [{
            port: 'http',
          }],
        }],
        podSelector: $.daemonSet.spec.selector,
        policyTypes: [
          'Egress',
          'Ingress',
        ],
      },
    },
  }
