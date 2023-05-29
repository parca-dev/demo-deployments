local common = import './common.libsonnet';

local defaults = {
  name: 'must provide name',
  namespace: 'must provide namespace',
  jobLabel: '',
  podTargetLabels: [],
  podProfileEndpoints: 'must provide endpoints',
  selector: 'must provide selector',
  namespaceSelector: {
    any: false,
    matchNames: [],
  },
};

local podProfileEndpointDefaults = {
  port: error 'must provide port',
  profilingConfig: {},
  scheme: 'http',
  interval: '10s',
  scrapeTimeout: '0s',
  relabelings: [],
  followRedirects: true,
};

local selectorDefaults = {
  matchLabels: {},
  matchExpressions: [],
};

{
  // generatePodProfilersConfig generates scrape configs for a list of podProfiler objects.
  generatePodProfilersConfig(podProfilers): {
    scrape_configs+: [
      {
        local pod = defaults + p,
        local ep = podProfileEndpointDefaults + pod.podProfileEndpoints[i],
        local selector = selectorDefaults + pod.selector,

        assert std.isObject(selector),
        assert std.isObject(selector.matchLabels) && std.length(selector.matchLabels) > 0 ||
               std.isArray(selector.matchExpressions) && std.length(selector.matchExpressions) > 0,

        job_name: 'PodProfiler/%s/%s/%d' % [pod.namespace, pod.name, i],
        scrape_interval: ep.interval,
        scrape_timeout: ep.scrapeTimeout,
        profiling_config: ep.profilingConfig,
        scheme: ep.scheme,
        relabel_configs:
          // Relabel prometheus job name into a meta label
          [
            {
              source_labels: ['job'],
              separator: ';',
              regex: '(.*)',
              target_label: '__tmp_prometheus_job_name',
              replacement: '$1',
              action: 'replace',
            },
          ] +

          // Exact label matches.
          [
            {
              source_labels: ['__meta_kubernetes_pod_label_' + common.sanitizeLabelName(labelKey)],
              separator: ';',
              regex: selector.matchLabels[labelKey],
              replacement: '$1',
              action: 'keep',
            }
            for labelKey in std.objectFields(selector.matchLabels)

          ] +

          // Set based label matching. We have to map the valid relations
          // `In`, `NotIn`, `Exists`, and `DoesNotExist`, into relabeling rules.
          [
            if exp.operator == 'In' then {
              source_labels: ['__meta_kubernetes_pod_label_' + common.sanitizeLabelName(exp.Key), '__meta_kubernetes_pod_labelpresent_' + common.sanitizeLabelName(exp.Key)],
              separator: ';',
              regex: '(%s);true' % std.join('|', exp.Values),
              replacement: '$1',
              action: 'keep',
            } else if exp.operator == 'NotIn' then {
              source_labels: ['__meta_kubernetes_pod_label_' + common.sanitizeLabelName(exp.Key), '__meta_kubernetes_pod_labelpresent_' + common.sanitizeLabelName(exp.Key)],
              separator: ';',
              regex: '(%s);true' % std.join('|', exp.Values),
              replacement: '$1',
              action: 'drop',
            } else if exp.operator == 'Exists' then {
              source_labels: ['__meta_kubernetes_pod_labelpresent_' + common.sanitizeLabelName(exp.Key)],
              separator: ';',
              regex: 'true',
              replacement: '$1',
              action: 'keep',
            } else if exp.operator == 'NotExits' then {
              source_labels: ['__meta_kubernetes_pod_labelpresent_' + common.sanitizeLabelName(exp.Key)],
              separator: ';',
              regex: 'true',
              replacement: '$1',
              action: 'drop',
            } else error 'unknown expression operator: ' + exp.operator
            for exp in selector.matchExpressions
          ] +

          [
            // Filter targets based on correct port for the endpoint.
            {
              source_labels: ['__meta_kubernetes_pod_container_port_name'],
              separator: ';',
              regex: ep.port,
              replacement: '$1',
              action: 'keep',
            },

            // Relabel namespace and pod and service labels into proper labels.
            {
              source_labels: ['__meta_kubernetes_namespace'],
              separator: ';',
              regex: '(.*)',
              target_label: 'namespace',
              replacement: '$1',
              action: 'replace',
            },
            {
              source_labels: ['__meta_kubernetes_pod_container_name'],
              separator: ';',
              regex: '(.*)',
              target_label: 'container',
              replacement: '$1',
              action: 'replace',
            },
            {
              source_labels: ['__meta_kubernetes_pod_name'],
              separator: ';',
              regex: '(.*)',
              target_label: 'pod',
              replacement: '$1',
              action: 'replace',
            },

            // Relabel targetLabels from Pod onto target.
          ] + [
            {
              source_labels: ['__meta_kubernetes_pod_label_' + common.sanitizeLabelName(l)],
              separator: ';',
              regex: '(.+)',
              target_label: l,
              replacement: '$1',
              action: 'replace',
            }
            for l in pod.podTargetLabels
          ] + [

            // Set job label
            {
              separator: ';',
              regex: '(.*)',
              target_label: 'job',
              replacement: '%s/%s' % [pod.namespace, pod.name],
              action: 'replace',
            },
          ] +

          if pod.jobLabel != '' then [
            {
              source_labels: ['__meta_kubernetes_pod_label_' + common.sanitizeLabelName(pod.jobLabel)],
              separator: ';',
              regex: '(.+)',
              target_label: 'job',
              replacement: '$1',
              action: 'replace',
            },
          ]

          else [] + [
            {
              target_label: 'endpoint',
              separator: ';',
              regex: '(.*)',
              replacement: ep.port,
              action: 'replace',
            },
          ] + ep.relabelings,

        kubernetes_sd_configs: [{
          role: 'pod',
          kubeconfig_file: '',
          follow_redirects: ep.followRedirects,
          namespaces: {
            own_namespace: false,
            names:
              if pod.namespaceSelector.any then
                []
              else if std.length(pod.namespaceSelector.matchNames) == 0 then
                [pod.namespace]
              else pod.namespaceSelector.matchNames,
          },
        }],
      }
      for p in podProfilers
      for i in std.range(0, std.length(p.podProfileEndpoints) - 1)
    ],
  },
}
