# pyrra

[Pyrra](https://github.com/pyrra-dev/pyrra) provides SLOs for Prometheus. It runs
two components, both from the same image:

* `pyrra-kubernetes` – the controller that reconciles `ServiceLevelObjective`
  custom resources into Prometheus recording and alerting rules
  (`PrometheusRule` objects).
* `pyrra-api` – the web UI and API that query Prometheus and the controller.

It is deployed via the upstream Jsonnet library, pinned in
[`jsonnetfile.json`](jsonnetfile.json) and wrapped in
[`lib/main.libsonnet`](lib/main.libsonnet).

## Integration with this cluster

* `pyrra-api` queries the existing `parca` Prometheus at
  `http://prometheus-parca.monitoring.svc.cluster.local:9090`.
* The `parca` Prometheus selects rules from all namespaces
  (`ruleSelector: {}` / `ruleNamespaceSelector: {}`), so the `PrometheusRule`
  objects Pyrra generates are picked up automatically.
* The cluster runs Cilium with a cluster-wide default-deny, so the wrapper ships
  `NetworkPolicy` objects for both components (egress allowed, ingress restricted)
  plus an additive policy allowing `pyrra-api` to reach the `parca` Prometheus.
* The UI is exposed at https://pyrra.parca.dev behind oauth2-proxy.

No `ServiceLevelObjective` resources are defined yet; the example SLOs shipped by
the upstream library are intentionally excluded.

## Notes

* Pyrra's own `ServiceMonitor` objects live in the `monitoring` namespace. The
  `parca` Prometheus currently only has target-discovery RBAC in the `parca` and
  `parca-devel` namespaces, so scraping Pyrra's own metrics additionally requires
  adding `monitoring` to that Prometheus' `namespaces` list (in
  [`../monitoring`](../monitoring)). This is only needed for monitoring Pyrra
  itself and is left for later.
