local g = import 'github.com/brancz/kubernetes-grafana/grafana/grafana.libsonnet';

local defaults = {
  local cfg = self,
  plugins: [
    'parca-datasource 0.0.36',
    'parca-panel 0.0.36',
  ],
  namespace: 'grafana',
  // renovate: datasource=docker depName=docker.io/grafana/grafana
  version: '9.5.18',
  replicas: 1,
  commonLabels+: {
    'app.kubernetes.io/component': 'observability',
  },
  config: {
    main: {
      app_mode: 'development',
    },
    sections: {
      analytics: {
        check_for_updates: false,
        reporting_enabled: false,
      },
      auth: {
        disable_login_form: true,
        disable_signout_menu: true,
      },
      'auth.anonymous': {
        enabled: true,
        org_role: 'Editor',
      },
      alerting: {
        enabled: false,
      },
      security: {
        disable_initial_admin_creation: true,
      },
      server: {
        domain: cfg.ingress.hosts[0],
        root_url: 'https://%s%s/' % [cfg.ingress.hosts[0], cfg.ingress.path],
        serve_from_sub_path: true,
      },
    },
  },
  dashboards+: {
    'parca.json': (import './dashboards/parca.json'),
  },
  resources: {
    limits: {
      memory: '256Mi',
    },
    requests: {
      cpu: '100m',
      memory: '256Mi',
    },
  },
  ingress: {
    class: error 'must provide ingress class',
    hosts: error 'must provide ingress hosts',
    path: '/grafana',
  },
};

function(params)
  local config = defaults + params;

  g(config) {
    ingress: {
      apiVersion: 'networking.k8s.io/v1',
      kind: 'Ingress',
      metadata: {
        name: 'grafana',
        namespace: $._config.namespace,
        labels: $._config.commonLabels,
      },
      spec: {
        ingressClassName: $._config.ingress.class,
        rules: [
          {
            host: host,
            http: {
              paths: [{
                backend: {
                  service: {
                    name: 'grafana',
                    port: {
                      name: 'http',
                    },
                  },
                },
                path: $._config.ingress.path,
                pathType: 'Prefix',
              }],
            },
          }
          for host in $._config.ingress.hosts
        ],
        tls: [
          {
            hosts: [host],
            secretName: std.strReplace(host, '.', '-') + '-tls',
          }
          for host in $._config.ingress.hosts
        ],
      },
    },

    networkPolicy: {
      apiVersion: 'networking.k8s.io/v1',
      kind: 'NetworkPolicy',
      metadata: {
        name: 'grafana',
        namespace: $._config.namespace,
        labels: $._config.commonLabels,
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
            port: 'http',
          }],
        }],
        podSelector: {
          matchLabels: $._config.selectorLabels,
        },
        policyTypes: [
          'Egress',
          'Ingress',
        ],
      },
    },
  }
