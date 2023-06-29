# Parca Demo Deployments

This is our [demo.parca.dev](https://demo.parca.dev) cluster configuration.

* argocd - [![App Status](https://demo.parca.dev/argo-cd/api/badge?name=scaleway-parca-demo-argocd)](https://demo.parca.dev/argo-cd/applications/scaleway-parca-demo-argocd)
* argocd-applications - [![App Status](https://demo.parca.dev/argo-cd/api/badge?name=scaleway-parca-demo-argocd-applications)](https://demo.parca.dev/argo-cd/applications/scaleway-parca-demo-argocd-applications)
* cert-manager - [![App Status](https://demo.parca.dev/argo-cd/api/badge?name=scaleway-parca-demo-cert-manager)](https://demo.parca.dev/argo-cd/applications/scaleway-parca-demo-cert-manager)
* cluster-config - [![App Status](https://demo.parca.dev/argo-cd/api/badge?name=scaleway-parca-demo-cluster-config)](https://demo.parca.dev/argo-cd/applications/scaleway-parca-demo-cluster-config)
* flux - [![App Status](https://demo.parca.dev/argo-cd/api/badge?name=scaleway-parca-demo-flux)](https://demo.parca.dev/argo-cd/applications/scaleway-parca-demo-flux)
* grafana - [![App Status](https://demo.parca.dev/argo-cd/api/badge?name=scaleway-parca-demo-grafana)](https://demo.parca.dev/argo-cd/applications/scaleway-parca-demo-grafana)
* ingress-nginx - [![App Status](https://demo.parca.dev/argo-cd/api/badge?name=scaleway-parca-demo-ingress-nginx)](https://demo.parca.dev/argo-cd/applications/scaleway-parca-demo-ingress-nginx)
* monitoring - [![App Status](https://demo.parca.dev/argo-cd/api/badge?name=scaleway-parca-demo-monitoring)](https://demo.parca.dev/argo-cd/applications/scaleway-parca-demo-monitoring)
* oauth2-proxy - [![App Status](https://demo.oauth2-proxy.dev/argo-cd/api/badge?name=scaleway-oauth2-proxy-demo-oauth2-proxy)](https://demo.oauth2-proxy.dev/argo-cd/applications/scaleway-oauth2-proxy-demo-oauth2-proxy)
* parca - [![App Status](https://demo.parca.dev/argo-cd/api/badge?name=scaleway-parca-demo-parca)](https://demo.parca.dev/argo-cd/applications/scaleway-parca-demo-parca)
* parca-devel - [![App Status](https://demo.parca.dev/argo-cd/api/badge?name=scaleway-parca-demo-parca-devel)](https://demo.parca.dev/argo-cd/applications/scaleway-parca-demo-parca-devel)

Ask in one of our channels to be invited to the Scaleway Organization.
Once you have access you can download the kubeconfig via the UI.

## File structure

```shell
.
├── README.md
└── <application>/  # Kubernetes resources configuration of an appliciation
```

## Deployment types

All the manifest outputs can be passed to `kubectl`, example:

```shell
${COMMAND} | kubectl diff --namespace "${NAMESPACE}" --filename -
```

Our **strongly opinionated** order of preference:

* preferred upstream method
  (must be 1st class, not derived from another. If more than 1, follow our order of preference)
* Kustomize
* Jsonnet
* Helm

Environment names are generally `<cluster_name>` or `<cluster_name>-<instance>`.

### Kustomize

```shell
${APPLICATION}/
├── base/                          # Common resources
│   ├── kustomization.yaml
│   ├── resource1.yaml
│   ...
│   └── resourceN.yaml
├── components/
│   └── ${FEATURE}/                # Optional feature resources and overrides
│       ├── kustomization.yaml
│       ├── resource1.yaml
│       ...
│       └── resourceN.yaml
└── overlays/
    └── ${ENVIRONMENT}/            # Environment-specific resources and overrides
        ├── kustomization.yaml
        ├── extra-resource1.yaml
        ...
        └── extra-resourceN.yaml
```

Build manifest locally:

```shell
cd "${APPLICATION}/overlays/${ENVIRONMENT}"
kustomize build
```

Requires [Kustomize](https://kustomize.io).

### Jsonnet

```shell
${APPLICATION}/
├── environements/
│  └── ${ENVIRONMENT}/       # Environment-specific resources and overrides
│      ├── main.jsonnet      # Jsonnet "entrypoint" file
│      └── spec.json         # Tanka environment configuration
├── lib/                     # Jsonnet libraries
├── vendor/                  # Third-party libraries
├── jsonnetfile.json         # Jsonnet-bundler dependency tracking
└── jsonnetfile.lock.json    # Jsonnet-bundler dependency lock file
```

Build manifest locally:

```shell
cd "${APPLICATION}"
jb install    # optional, 3rd-party libraries are checked in Git
jsonnet -J vendor -J lib "environments/${ENVIRONMENT}/main.jsonnet"
```

Requires [Jsonnet](https://github.com/google/go-jsonnet) and [jsonnet-bundler](https://github.com/jsonnet-bundler/jsonnet-bundler).

Or with Tanka:

```shell
tk show "environments/${ENVIRONMENT}"
```

Requires [Tanka](https://tanka.dev).

### Helm

```shell
${APPLICATION}/
├── Chart.lock
├── Chart.yaml
├── values.yaml               # Common values
└── values/
    └── ${ENVIRONMENT}.yaml   # Environment-specific values and overrides
```

Build manifest locally:

```shell
cd "${APPLICATION}/"
helm dependency build
helm template "${RELEASE_NAME}" --namespace "${NAMESPACE}" . \
  --values values/${ENVIRONMENT}.yaml
```

Requires [Helm](https://helm.sh).

## Manifests validation

Manifests validation is performed by [kubeconform](https://github.com/yannh/kubeconform).
JSON schemas are extracted from custom resource definitions under `.schemas/`.
Edit `.schemas/Makefile` to update them and use `make -C .schemas` to re-generate them.

Validation can be performed by passing the manifest output to `kubeconform`:

```shell
${COMMAND} | kubeconform \
  -schema-location '.schemas/{{ .ResourceKind }}{{ .KindSuffix }}.json' \
  -schema-location 'https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master' \
  -skip CustomResourceDefinition \
  -strict
```

## Continuous deployment

* Our [Argo CD](https://argoproj.github.io/cd/) instance is available at: https://demo.parca.dev/argo-cd (see also [argocd/](argocd))
* Argo CD Applications are configured under [argocd-applications/](argocd-applications)
* [Flux](https://fluxcd.io/) is used to automate the Parca server and agent image updates (see [flux/](flux))
* [Renovate](https://docs.renovatebot.com/) is used to update community dependencies (see [GitHub App](https://github.com/apps/renovate) and [renovate.json](renovate.json))
