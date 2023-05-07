PYTHON := python3

# renovate: datasoure=github-releases depName=yannh/kubeconform
KUBECONFORM_VERSION := v0.6.1

CRDS := \
	https://github.com/jetstack/cert-manager/releases/download/v1.8.2/cert-manager.crds.yaml \
	https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.57.0/jsonnet/prometheus-operator/podmonitors-crd.json \
	https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.57.0/jsonnet/prometheus-operator/prometheuses-crd.json \

all: schemas

openapi2jsonschema.py:
	@$(PYTHON) -m venv venv
	@venv/bin/pip install pyyaml
	@curl -sSfo $@ https://raw.githubusercontent.com/yannh/kubeconform/$(KUBECONFORM_VERSION)/scripts/openapi2jsonschema.py
	@chmod +x $@

.PHONY: schemas
schemas: openapi2jsonschema.py
	@rm -f *.json
	@for crd in $(CRDS); do \
	  FILENAME_FORMAT='{kind}-{group}-{version}' DENY_ROOT_ADDITIONAL_PROPERTIES=true venv/bin/python openapi2jsonschema.py "$${crd}"; \
	done
