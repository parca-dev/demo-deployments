local u = import 'utils.libsonnet';

local projects = [
  u.newProject({
    name: 'scaleway-parca-demo',
    description: 'Scaleway Parca Demo cluster',
  }),
];

local applications =
  local common = {
    project: 'scaleway-parca-demo',
  };

  [
    u.newKustomizeApp(common {
      name: 'argocd',
      namespace: 'argocd',
    }),
    u.newJsonnetApp(common {
      name: 'argocd-applications',
      namespace: 'argocd',
    }) {
      spec+: {
        syncPolicy+: {
          // Disable auto-sync, so apps can be reconfigured ad-hoc
          automated:: {},
        },
      },
    },
    u.newKustomizeApp(common {
      name: 'cluster-config',
      namespace: 'default',
    }),
    u.newHelmApp(common {
      name: 'cert-manager',
      namespace: 'cert-manager',
    }),
    u.newKustomizeApp(common {
      name: 'flux',
      namespace: 'flux-system',
    }),
    u.newJsonnetApp(common {
      name: 'grafana',
      namespace: 'parca',
    }),
    u.newHelmApp(common {
      name: 'ingress-nginx',
      namespace: 'ingress-nginx',
    }),
    u.newJsonnetApp(common {
      name: 'monitoring',
      namespace: 'monitoring',
    }) {
      spec+: {
        ignoreDifferences: [{
          // The real Authorization/project-ID header values are patched live onto this
          // Middleware post-sync (see monitoring/README.md) and are never declared in
          // git, so ignore them here to avoid a permanent OutOfSync status.
          group: 'traefik.io',
          kind: 'Middleware',
          name: 'psc-remote-write-headers',
          namespace: 'parca-analytics',
          jsonPointers: ['/spec/headers/customRequestHeaders'],
        }],
      },
    },
    u.newHelmApp(common {
      name: 'oauth2-proxy',
      namespace: 'oauth2-proxy',
    }),
    u.newHelmApp(common {
      name: 'traefik',
      namespace: 'traefik',
    }),
    u.newJsonnetApp(common {
      name: 'parca',
      namespace: 'parca',
    }),
    u.newJsonnetApp(common {
      name: 'parca-devel',
      namespace: 'parca-devel',
    }),
    u.newJsonnetApp(common {
      name: 'pyrra',
      namespace: 'monitoring',
    }),
  ];

{
  apiVersion: 'v1',
  kind: 'List',
  items:
    projects +
    applications,
}
