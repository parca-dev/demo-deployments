This is our [demo.parca.dev](https://demo.parca.dev) cluster configuration.

Ask in one of our channels to be invited to the Scaleway Organization.
Once you have access you can download the kubeconfig via the UI.

## Installation

Run `make` to both download the dependencies YAML files and afterwards apply all of them in one go.
Optionally, run `make get` to only download the dependencies or `make apply` to only apply the YAML files.

### Latest

There is also `make latest` which overrides the images in both parca and parca-agent Pods. 
Update the container tags before running this make target.

