local pyrra = import 'github.com/pyrra-dev/pyrra/jsonnet/pyrra/kubernetes.libsonnet';

// This cluster runs Cilium with a cluster-wide default-deny (see cluster-config).
// Every workload therefore has to ship its own NetworkPolicy: egress is allowed
// everywhere by convention, ingress is restricted to known sources.
local ingressNginx = {
  namespaceSelector: { matchLabels: { 'kubernetes.io/metadata.name': 'ingress-nginx' } },
  podSelector: {
    matchLabels: {
      'app.kubernetes.io/name': 'ingress-nginx',
      'app.kubernetes.io/component': 'controller',
      'app.kubernetes.io/instance': 'ingress-nginx',
    },
  },
};

// Traefik runs alongside ingress-nginx during the migration and serves the
// same Ingresses, so it has to be an allowed source too.
local traefik = {
  namespaceSelector: { matchLabels: { 'kubernetes.io/metadata.name': 'traefik' } },
  podSelector: { matchLabels: { 'app.kubernetes.io/name': 'traefik' } },
};

{
  pyrra(params):: (
    pyrra {
      values+:: {
        common+: {
          namespace: params.namespace,
          versions+: { pyrra: params.version },
        },
        pyrra+: {
          prometheusURL: params.prometheusURL,
        },
      },
    }
  ).pyrra {
    local p = self,

    // The Prometheus instance Pyrra queries and that scrapes Pyrra back.
    local prometheus = {
      'app.kubernetes.io/name': 'prometheus',
      'app.kubernetes.io/instance': 'parca',
    },

    local resources = {
      requests: { cpu: '20m', memory: '64Mi' },
      limits: { memory: '128Mi' },
    },

    // The monitoring namespace enforces the restricted Pod Security Standard.
    // The image already runs as a non-root user (USER 65533).
    local podSecurityContext = {
      runAsNonRoot: true,
      seccompProfile: { type: 'RuntimeDefault' },
    },
    local hardened(container) = container {
      resources: resources,
      securityContext+: { capabilities: { drop: ['ALL'] } },
    },

    apiDeployment+: {
      spec+: { template+: { spec+: {
        securityContext+: podSecurityContext,
        containers: [hardened(c) for c in super.containers],
      } } },
    },

    kubernetesDeployment+: {
      spec+: { template+: { spec+: {
        securityContext+: podSecurityContext,
        containers: [hardened(c) for c in super.containers],
      } } },
    },

    // Make sure the CRD exists before the controller starts reconciling.
    crd+: {
      metadata+: { annotations+: { 'argocd.argoproj.io/sync-wave': '-1' } },
    },

    // Public UI ingress.
    apiIngress: {
      apiVersion: 'networking.k8s.io/v1',
      kind: 'Ingress',
      metadata: {
        name: 'pyrra',
        namespace: params.namespace,
        labels: p.apiService.metadata.labels,
        annotations: {
          'cert-manager.io/cluster-issuer': 'letsencrypt-prod',
        },
      },
      spec: {
        ingressClassName: 'nginx',
        rules: [
          {
            host: host,
            http: { paths: [{
              backend: { service: { name: p.apiService.metadata.name, port: { name: 'http' } } },
              path: '/',
              pathType: 'Prefix',
            }] },
          }
          for host in params.ingressHosts
        ],
        tls: [{ hosts: [host], secretName: host } for host in params.ingressHosts],
      },
    },

    apiNetworkPolicy: {
      apiVersion: 'networking.k8s.io/v1',
      kind: 'NetworkPolicy',
      metadata: { name: 'pyrra-api', namespace: params.namespace, labels: p.apiService.metadata.labels },
      spec: {
        podSelector: { matchLabels: p.apiSelectorLabels },
        policyTypes: ['Egress', 'Ingress'],
        egress: [{}],
        ingress: [
          // UI traffic via the ingress controllers and Prometheus scraping the API metrics.
          { from: [ingressNginx, traefik, { podSelector: { matchLabels: prometheus } }], ports: [{ port: 9099 }] },
        ],
      },
    },

    kubernetesNetworkPolicy: {
      apiVersion: 'networking.k8s.io/v1',
      kind: 'NetworkPolicy',
      metadata: { name: 'pyrra-kubernetes', namespace: params.namespace, labels: p.kubernetesService.metadata.labels },
      spec: {
        podSelector: { matchLabels: p.kubernetesSelectorLabels },
        policyTypes: ['Egress', 'Ingress'],
        egress: [{}],
        ingress: [
          // gRPC backend from the API.
          { from: [{ podSelector: { matchLabels: p.apiSelectorLabels } }], ports: [{ port: 9444 }] },
          // Prometheus scraping the controller metrics.
          { from: [{ podSelector: { matchLabels: prometheus } }], ports: [{ port: 8080 }] },
        ],
      },
    },

    // Additive policy allowing the Pyrra API to query Prometheus, whose own
    // policy only permits ingress-nginx.
    prometheusAccessNetworkPolicy: {
      apiVersion: 'networking.k8s.io/v1',
      kind: 'NetworkPolicy',
      metadata: { name: 'pyrra-api-to-prometheus', namespace: params.namespace, labels: p.apiService.metadata.labels },
      spec: {
        podSelector: { matchLabels: prometheus },
        policyTypes: ['Ingress'],
        ingress: [
          { from: [{ podSelector: { matchLabels: p.apiSelectorLabels } }], ports: [{ port: 'web' }] },
        ],
      },
    },
  },
}
