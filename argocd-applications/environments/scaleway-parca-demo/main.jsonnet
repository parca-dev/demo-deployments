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
    }),
    u.newJsonnetApp(common {
      name: 'parca',
      namespace: 'parca',
    }),
    u.newJsonnetApp(common {
      name: 'parca-devel',
      namespace: 'parca-devel',
    }),
    u.newHelmApp(common {
      name: 'traefik',
      namespace: 'traefik',
    }),
  ];

{
  apiVersion: 'v1',
  kind: 'List',
  items:
    projects +
    applications,
}
