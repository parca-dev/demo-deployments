# Flux

See [Automate image updates to Git | Flux](https://fluxcd.io/flux/guides/image-update/).

> **Note**: There is an [argocd-image-updater](https://github.com/argoproj-labs/argocd-image-updater),
> but it is very specific to Argo CD and supports Helm and Kustomize only.
> Flux supports any YAML file and is agnostic regarding the deployment solution.

## Configure SSH key

Based on [Git Repositories - SSH authentication | Flux](https://fluxcd.io/flux/components/source/gitrepositories/#ssh-authentication).

1. Generate a new SSH key pair:

   ```bash
   ssh-keygen -b 4096 -N '' -C fluxcdbot -f fluxcdbot
   ```

2. Create a new secret in the cluster:

   ```bash
   PATCH="$(jq --null-input --arg identity "$(<fluxcdbot)" '[{
     "op": "replace",
     "path": "/data/identity",
     "value": "\($identity|@base64)"
   }]')"
   kubectl patch secret \
     --namespace=flux-system \
     flux-ssh-credentials \
     --type=json \
     --patch="${PATCH}"
   ```

3. Add the `fluxcdbot.pub` public key to the repository's [deploy keys](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/managing-deploy-keys#deploy-keys) with **write access**.

## Retrieve current SSH public key from the cluster

```bash
kubectl get secret --namespace=flux-system flux-ssh-credentials --output=json \
  | jq --raw-output '.data.identity|@base64d' \
  | ssh-keygen -y -f /dev/stdin
```
