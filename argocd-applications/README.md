# argocd-applications

See [User Guide - Argo CD](https://argo-cd.readthedocs.io/en/stable/user-guide/).

## Login with the `argocd` CLI

See [argocd/](../argocd#login-with-the-argocd-cli).

## Diff incoming changes

From a branch which has been pushed to the Git repository:

```shell
argocd app diff "${APPLICATION}" --revision="${BRANCH}"
```

See also [Argocd app diff | Argo CD](https://argo-cd.readthedocs.io/en/stable/user-guide/commands/argocd_app_diff/)

## Suspend and resume auto-sync

### Suspend

* With `kubectl`:

  ```shell
  kubectl patch Application \
    --namespace=argocd "${APPLICATION}" \
    --type=json --patch='[{ "op": "remove", "path": "/spec/syncPolicy/automated" }]'
  ```

* With `argocd`:

  ```shell
  argocd app patch "${APPLICATION}" \
    --type=json --patch='[{ "op": "remove", "path": "/spec/syncPolicy/automated" }]'
  ```

### Resume

Re-sync the desired configuration:

```shell
argocd app sync scaleway-parca-demo-argocd-applications \
  --resource="argoproj.io:Application:argocd/${APPLICATION}"
```
