local pa = import 'github.com/parca-dev/parca-agent/deploy/lib/parca-agent/parca-agent.libsonnet';
local versions = std.parseYaml(importstr './versions.yaml');

local defaults = {
  name: 'parca-agent-devel',
  namespace: 'parca-devel',
  version: versions.parcaAgent,
  image: 'ghcr.io/parca-dev/parca-agent:' + self.version,
  stores: ['parca-devel.%s.svc.cluster.local:7070' % self.namespace],
  insecure: true,
  insecureSkipVerify: true,
  logLevel: 'debug',
  resources: {
    limits: {
      cpu: '100m',
      memory: '1Gi',
    },
    requests: {
      cpu: '10m',
      memory: '1Gi',
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
              if c.name == 'parca' then c {
                // TODO: Make it easy to pass extra args upstream.
                args+: [
                  // One percent of events are profiled.
                  '--mutex-profile-fraction=100',
                  '--block-profile-rate=100',
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
            {
              namespaceSelector: {
                matchLabels: {
                  'kubernetes.io/metadata.name': 'parca-devel',
                },
              },
              podSelector: {
                matchLabels: {
                  'app.kubernetes.io/name': 'parca',
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
