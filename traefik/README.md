# traefik

See https://artifacthub.io/packages/helm/traefik/traefik

Deployed in `kubernetesIngressNGINX` provider mode so Traefik serves the existing
`ingressClassName: nginx` Ingresses during the migration away from ingress-nginx.
