# grafana

See https://github.com/brancz/kubernetes-grafana

## Add a new dashboard

1. Add the dashboard source by either:
    1. Adding a existing dashboard with `jsonnet-bundler`
       (e.g. `jb install github.com/someorg/somerepo/path/to/dashboards@v1.2.3`)
    2. Writing a dashboard in Jsonnet with [Grafonnet](https://grafana.github.io/grafonnet-lib/) under `lib/dashboards/`
    3. Building a dashboard in the Grafana UI,
       then [exporting it](https://grafana.com/docs/grafana/latest/dashboards/manage-dashboards/#export-and-import-dashboards),
       and placing the JSON file under `lib/dashboards`
2. Import it in the `dashboards` list in `lib/grafana.libsonnet`
