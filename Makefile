all: get apply

.PHONY: get
get:
	curl -L https://github.com/cert-manager/cert-manager/releases/download/v1.8.2/cert-manager.crds.yaml > cert-manager.crds.yaml
	curl -L https://github.com/cert-manager/cert-manager/releases/download/v1.8.2/cert-manager.yaml > cert-manager.yaml
	curl -L https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.3.0/deploy/static/provider/scw/deploy.yaml > ingress-nginx.yaml
	curl -L https://github.com/parca-dev/parca/releases/download/v0.12.1/kubernetes-manifest.yaml > parca.yaml
	curl -L https://github.com/parca-dev/parca-agent/releases/download/v0.9.0/kubernetes-manifest.yaml > parca-agent.yaml

.PHONY: apply
apply:
	kubectl apply -f ./cert-manager.crds.yaml
	kubectl apply -f ./cert-manager.yaml
	kubectl apply -f ./ingress-nginx.yaml
	kubectl apply -f ./parca.yaml
	kubectl apply -f ./parca-agent.yaml
	# These are cluster specific files for our demo
	kubectl apply -f ./cert-manager-cluster-issuer.yaml
	kubectl apply -f ./ingress-nginx-loadbalancer.yaml
	kubectl apply -f ./parca-ingress.yaml
	kubectl set resources deployment -n parca parca --requests memory=4Gi


.PHONY: latest
latest:
	kubectl set image -n parca deployment/parca parca=ghcr.io/parca-dev/parca:main-7b9489cc
	kubectl set image -n parca daemonset/parca-agent parca-agent=ghcr.io/parca-dev/parca-agent:main-287dbf6f

.PHONY: monitoring
monitoring:
	kubectl apply --server-side -f https://raw.githubusercontent.com/prometheus-operator/kube-prometheus/main/manifests/setup/namespace.yaml
	kubectl apply --server-side -f https://raw.githubusercontent.com/prometheus-operator/kube-prometheus/main/manifests/setup/0alertmanagerConfigCustomResourceDefinition.yaml
	kubectl apply --server-side -f https://raw.githubusercontent.com/prometheus-operator/kube-prometheus/main/manifests/setup/0alertmanagerCustomResourceDefinition.yaml
	kubectl apply --server-side -f https://raw.githubusercontent.com/prometheus-operator/kube-prometheus/main/manifests/setup/0podmonitorCustomResourceDefinition.yaml
	kubectl apply --server-side -f https://raw.githubusercontent.com/prometheus-operator/kube-prometheus/main/manifests/setup/0probeCustomResourceDefinition.yaml
	kubectl apply --server-side -f https://raw.githubusercontent.com/prometheus-operator/kube-prometheus/main/manifests/setup/0prometheusCustomResourceDefinition.yaml
	kubectl apply --server-side -f https://raw.githubusercontent.com/prometheus-operator/kube-prometheus/main/manifests/setup/0prometheusruleCustomResourceDefinition.yaml
	kubectl apply --server-side -f https://raw.githubusercontent.com/prometheus-operator/kube-prometheus/main/manifests/setup/0servicemonitorCustomResourceDefinition.yaml
	kubectl apply --server-side -f https://raw.githubusercontent.com/prometheus-operator/kube-prometheus/main/manifests/setup/0thanosrulerCustomResourceDefinition.yaml
	kubectl apply --server-side -f https://raw.githubusercontent.com/prometheus-operator/kube-prometheus/main/manifests/prometheusOperator-serviceAccount.yaml
	kubectl apply --server-side -f https://raw.githubusercontent.com/prometheus-operator/kube-prometheus/main/manifests/prometheusOperator-clusterRole.yaml
	kubectl apply --server-side -f https://raw.githubusercontent.com/prometheus-operator/kube-prometheus/main/manifests/prometheusOperator-clusterRoleBinding.yaml
	kubectl apply --server-side -f https://raw.githubusercontent.com/prometheus-operator/kube-prometheus/main/manifests/prometheusOperator-deployment.yaml
	kubectl apply -f ./prometheus-serviceAccount.yaml
	kubectl apply -f ./prometheus-roleSpecificNamespaces.yaml
	kubectl apply -f ./prometheus-roleBindingSpecificNamespaces.yaml
	kubectl apply -f ./prometheus.yaml
	kubectl apply -f ./prometheus-podmonitor.yaml
	kubectl apply -f ./grafana.yaml
