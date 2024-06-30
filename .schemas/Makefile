PYTHON := python3

# renovate: datasource=github-releases depName=yannh/kubeconform
KUBECONFORM_VERSION := v0.6.6

CRDS := \
	https://github.com/jetstack/cert-manager/releases/download/v1.15.1/cert-manager.crds.yaml \
	https://raw.githubusercontent.com/argoproj/argo-cd/v2.11.3/manifests/crds/application-crd.yaml \
	https://raw.githubusercontent.com/argoproj/argo-cd/v2.11.3/manifests/crds/applicationset-crd.yaml \
	https://raw.githubusercontent.com/argoproj/argo-cd/v2.11.3/manifests/crds/appproject-crd.yaml \
	https://raw.githubusercontent.com/cilium/cilium/v1.11.6/pkg/k8s/apis/cilium.io/client/crds/v2/ciliumclusterwidenetworkpolicies.yaml \
	https://raw.githubusercontent.com/fluxcd/image-automation-controller/v0.38.0/config/crd/bases/image.toolkit.fluxcd.io_imageupdateautomations.yaml \
	https://raw.githubusercontent.com/fluxcd/image-reflector-controller/v0.32.0/config/crd/bases/image.toolkit.fluxcd.io_imagepolicies.yaml \
	https://raw.githubusercontent.com/fluxcd/image-reflector-controller/v0.32.0/config/crd/bases/image.toolkit.fluxcd.io_imagerepositories.yaml \
	https://raw.githubusercontent.com/fluxcd/source-controller/v1.3.0/config/crd/bases/source.toolkit.fluxcd.io_gitrepositories.yaml \
	https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.67.1/jsonnet/prometheus-operator/podmonitors-crd.json \
	https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.67.1/jsonnet/prometheus-operator/prometheuses-crd.json \
	https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.67.1/jsonnet/prometheus-operator/prometheusrules-crd.json \
	https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.67.1/jsonnet/prometheus-operator/servicemonitors-crd.json \

all: schemas

venv:
	@$(PYTHON) -m venv venv
	@venv/bin/pip install pyyaml

openapi2jsonschema.py: venv
	@curl -sSfo $@ https://raw.githubusercontent.com/yannh/kubeconform/$(KUBECONFORM_VERSION)/scripts/openapi2jsonschema.py
	@chmod +x $@

.PHONY: schemas
schemas: openapi2jsonschema.py
	@rm -f *.json
	@for crd in $(CRDS); do \
	  FILENAME_FORMAT='{kind}-{group}-{version}' DENY_ROOT_ADDITIONAL_PROPERTIES=true venv/bin/python openapi2jsonschema.py "$${crd}"; \
	done
