# oauth2-proxy

See https://artifacthub.io/packages/helm/oauth2-proxy/oauth2-proxy

## Configure GitHub OAuth and Cookie Secret

1. [Create an OAuth App](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/creating-an-oauth-app) under the [`parca-dev` organization](https://github.com/organizations/parca-dev/settings/applications)
2. [Generate a cookie secret](https://oauth2-proxy.github.io/oauth2-proxy/docs/configuration/overview#generating-a-cookie-secret)
3. Edit the Kubernetes Secret `oauth2-proxy`: `kubectl edit secret --namespace=oauth2-proxy oauth2-proxy`
4. Add the `client-id`, `client-secret`, and `cookie-secret` keys. Their values must be be **base64 encoded**

## Usage with ingress-nginx

To require GitHub authentication, annotate the Ingress resource with:

```yaml
nginx.ingress.kubernetes.io/auth-signin: https://oauth2.parca.dev/oauth2/start
nginx.ingress.kubernetes.io/auth-url: http://oauth2-proxy.oauth2-proxy.svc.cluster.local/oauth2/auth
```
