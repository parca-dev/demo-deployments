# Flux

See [Automate image updates to Git | Flux](https://fluxcd.io/flux/guides/image-update/).

> **Note**: There is an [argocd-image-updater](https://github.com/argoproj-labs/argocd-image-updater),
> but it is very specific to Argo CD and supports Helm and Kustomize only.
> Flux supports any YAML file and is agnostic regarding the deployment solution.

## Suspend and resume an Image Repository

### Suspend

```bash
kubectl patch ImageRepository \
  --namespace=flux-system "${IMAGE_REPOSITORY}" \
  --type=json --patch='[{ "op": "add", "path": "/spec/suspend", "value": true }]'
```

### Resume

```bash
kubectl patch ImageRepository \
  --namespace=flux-system "${IMAGE_REPOSITORY}" \
  --type=json --patch='[{ "op": "remove", "path": "/spec/suspend" }]'
```

See also [Image Repositories | Flux - Suspending and resuming](https://fluxcd.io/flux/components/image/imagerepositories/#suspending-and-resuming)

## Suspend and resume Image Update Automation

### Suspend

```bash
kubectl patch ImageUpdateAutomation \
  --namespace=flux-system parca-dev-demo-deployments \
  --type=json --patch='[{ "op": "add", "path": "/spec/suspend", "value": true }]'
```

### Resume

```bash
kubectl patch ImageUpdateAutomation \
  --namespace=flux-system parca-dev-demo-deployments \
  --type=json --patch='[{ "op": "remove", "path": "/spec/suspend" }]'
```

See also [Image Update Automations | Flux](https://fluxcd.io/flux/components/image/imageupdateautomations/)

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
     --namespace=flux-system flux-ssh-credentials \
     --type=json --patch="${PATCH}"
   ```

3. Add the `fluxcdbot.pub` public key to the repository's [deploy keys](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/managing-deploy-keys#deploy-keys) with **write access**.

## Retrieve current SSH public key from the cluster

```bash
kubectl get secret --namespace=flux-system flux-ssh-credentials --output=json \
  | jq --raw-output '.data.identity|@base64d' \
  | ssh-keygen -y -f /dev/stdin
```
