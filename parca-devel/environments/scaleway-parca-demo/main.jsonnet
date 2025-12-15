local p = import 'main.libsonnet';

local parca = p.parca({
  ingress+: {
    hosts: ['demo.parca.dev'],
  },
});

local parcaAgent = p.parcaAgent({
  config+: {
    relabel_configs+: [
      {
        source_labels: ['__meta_thread_id'],
        target_label: 'thread_id',
      },
      {
        source_labels: ['__meta_cpu'],
        target_label: 'cpu',
      },
    ],
  },
});

{
  kind: 'List',
  apiVersion: 'v1',
  items:
    [parca[name] for name in std.objectFields(parca) if parca[name] != null] +
    [parcaAgent[name] for name in std.objectFields(parcaAgent) if parcaAgent[name] != null],
}
