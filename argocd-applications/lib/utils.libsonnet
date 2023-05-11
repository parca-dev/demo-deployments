local clusterName = 'in-cluster';
local namespace = 'argocd';
local repoURL = 'https://github.com/parca-dev/demo-deployments.git';

{
  newProject(params)::
    local defaults = {
      name: error 'must provide name',
      description: error 'must provide description',
    };
    local config = defaults + params;

    {
      apiVersion: 'argoproj.io/v1alpha1',
      kind: 'AppProject',
      metadata: {
        name: config.name,
        namespace: namespace,
      },
      spec: {
        description: config.description,
        sourceRepos: [repoURL],
        destinations: [{
          name: clusterName,
          namespace: '*',
        }],
        clusterResourceWhitelist: [{
          group: '*',
          kind: '*',
        }],
      },
    },

  newApp(params)::
    local defaults = {
      project: error 'must provide project',
      name: error 'must provide name',
      namespace: error 'must provide namespace',
      path: error 'must provide path',
      // https://argo-cd.readthedocs.io/en/stable/operator-manual/high_availability/#webhook-and-manifest-paths-annotation
      generatePaths: ['/' + std.split(self.path, '/')[0], '/argocd-applications'],
    };
    local config = defaults + params;

    {
      apiVersion: 'argoproj.io/v1alpha1',
      kind: 'Application',
      metadata: {
        name: std.join('-', [config.project, config.name]),
        namespace: namespace,
        labels: {
          application: config.name,
        },
        annotations: {
          'argocd.argoproj.io/manifest-generate-paths': std.join(';', std.set(config.generatePaths)),
        },
        finalizers: ['resources-finalizer.argocd.argoproj.io/foreground'],
      },
      spec: {
        project: config.project,
        syncPolicy: {
          automated: {
            prune: true,
          },
          syncOptions: [
            'ServerSideApply=true',
          ],
        },
        destination: {
          name: clusterName,
          namespace: config.namespace,
        },
        source: {
          repoURL: repoURL,
          path: config.path,
          targetRevision: 'HEAD',
        },
      },
    },

  newKustomizeApp(params)::
    local defaults = {
      overlay: self.project,
      path: std.join('/', [self.name, 'overlays', self.overlay]),
    };
    local config = defaults + params;

    $.newApp(config),

  newJsonnetApp(params)::
    local defaults = {
      environment: self.project,
      path: std.join('/', [self.name, 'environments', self.environment]),
    };
    local config = defaults + params;

    $.newApp(config) {
      spec+: {
        source+: {
          directory+: {
            jsonnet+: {
              libs: [
                std.join('/', [config.name, path])
                for path in ['vendor', 'lib']
              ],
            },
          },
        },
      },
    },

  newHelmApp(params)::
    local defaults = {
      local cfg = self,
      path: cfg.name,
      helm: {
        releaseName: cfg.name,
        valueFiles: ['values/%s.yaml' % cfg.project],
      },
    };
    local config = defaults + params;

    $.newApp(config) {
      spec+: {
        source+: {
          helm: config.helm,
        },
      },
    },
}
