local common = import './common.libsonnet';

local defaults = {
  name: 'must provide name',
  namespace: 'must provide namespace',
  jobLabel: '',
  targetLabels: [],
  podTargetLabels: [],
  endpoints: 'must provide endpoints',
  selector: 'must provide selector',
  namespaceSelector: {
    any: false,
    matchNames: [],
  },
};

local endpointDefaults = {
  port: '',
  profilingConfig: {},
  targetPort: '',
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
  // generateServiceProfilersConfig generates scrape configs for a list of serviceProfiler objects.
  generateServiceProfilersConfig(serviceProfilers): {
    scrape_configs+: [
      {
        local svc = defaults + s,
        local ep = endpointDefaults + svc.endpoints[i],
        local selector = selectorDefaults + svc.selector,

        assert std.isObject(selector),
        assert ep.port == '' || ep.targetPort == '',
        assert ep.port != '' || ep.targetPort != '',
        assert std.isObject(selector.matchLabels) && std.length(selector.matchLabels) > 0 ||
               std.isArray(selector.matchExpressions) && std.length(selector.matchExpressions) > 0,

        job_name: 'ServiceProfiler/%s/%s/%d' % [svc.namespace, svc.name, i],
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
              source_labels: ['__meta_kubernetes_service_label_' + common.sanitizeLabelName(labelKey)],
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
              source_labels: ['__meta_kubernetes_service_label_' + common.sanitizeLabelName(exp.Key), '__meta_kubernetes_service_labelpresent_' + common.sanitizeLabelName(exp.Key)],
              separator: ';',
              regex: '(%s);true' % std.join('|', exp.Values),
              replacement: '$1',
              action: 'keep',
            } else if exp.operator == 'NotIn' then {
              source_labels: ['__meta_kubernetes_service_label_' + common.sanitizeLabelName(exp.Key), '__meta_kubernetes_service_labelpresent_' + common.sanitizeLabelName(exp.Key)],
              separator: ';',
              regex: '(%s);true' % std.join('|', exp.Values),
              replacement: '$1',
              action: 'drop',
            } else if exp.operator == 'Exists' then {
              source_labels: ['__meta_kubernetes_service_labelpresent_' + common.sanitizeLabelName(exp.Key)],
              separator: ';',
              regex: 'true',
              replacement: '$1',
              action: 'keep',
            } else if exp.operator == 'NotExits' then {
              source_labels: ['__meta_kubernetes_service_labelpresent_' + common.sanitizeLabelName(exp.Key)],
              separator: ';',
              regex: 'true',
              replacement: '$1',
              action: 'drop',
            } else error 'unknown expression operator: ' + exp.operator
            for exp in selector.matchExpressions

            // Filter targets based on correct port for the endpoint.
          ] + (
            if ep.port != '' then [
              {
                source_labels: ['__meta_kubernetes_endpoint_port_name'],
                separator: ';',
                regex: ep.port,
                replacement: '$1',
                action: 'keep',
              },
            ] else if ep.targetPort != '' then
              if std.isString(ep.targetPort) then [
                {
                  source_labels: ['__meta_kubernetes_pod_container_port_name'],
                  separator: ';',
                  regex: ep.targetPort,
                  replacement: '$1',
                  action: 'keep',
                },
              ] else if std.isNumber(ep.targetPort) then [
                {
                  source_labels: ['__meta_kubernetes_pod_container_port_number'],
                  separator: ';',
                  regex: ep.targetPort,
                  replacement: '$1',
                  action: 'keep',
                },
              ] else error 'targetPort must be a string or integer'
            else error 'could not set endpoint port selector'
          ) + [

            {
              source_labels: ['__meta_kubernetes_endpoint_address_target_kind', '__meta_kubernetes_endpoint_address_target_name'],
              separator: ';',
              regex: 'Node;(.*)',
              target_label: 'node',
              replacement: '$1',
              action: 'replace',
            },
            {
              source_labels: ['__meta_kubernetes_endpoint_address_target_kind', '__meta_kubernetes_endpoint_address_target_name'],
              separator: ';',
              regex: 'Pod;(.*)',
              target_label: 'pod',
              replacement: '$1',
              action: 'replace',
            },
            {
              source_labels: ['__meta_kubernetes_namespace'],
              separator: ';',
              regex: '(.*)',
              target_label: 'namespace',
              replacement: '$1',
              action: 'replace',
            },
            {
              source_labels: ['__meta_kubernetes_service_name'],
              separator: ';',
              regex: '(.*)',
              target_label: 'service',
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
            {
              source_labels: ['__meta_kubernetes_pod_container_name'],
              separator: ';',
              regex: '(.*)',
              target_label: 'container',
              replacement: '$1',
              action: 'replace',
            },

            // Relabel targetLabels from Service onto target.
          ] + [
            {
              source_labels: ['__meta_kubernetes_service_label_' + common.sanitizeLabelName(l)],
              separator: ';',
              regex: '(.+)',
              target_label: l,
              replacement: '$1',
              action: 'replace',
            }
            for l in svc.targetLabels
          ] + [
            {
              source_labels: ['__meta_kubernetes_pod_label_' + common.sanitizeLabelName(l)],
              separator: ';',
              regex: '(.+)',
              target_label: l,
              replacement: '$1',
              action: 'replace',
            }
            for l in svc.podTargetLabels
          ] + [

            // Set job label
            {
              source_labels: ['__meta_kubernetes_service_name'],
              separator: ';',
              regex: '(.*)',
              target_label: 'job',
              replacement: '$1',
              action: 'replace',
            },

          ] + if svc.jobLabel != '' then [
            {
              source_labels: ['__meta_kubernetes_service_label_' + common.sanitizeLabelName(svc.jobLabel)],
              separator: ';',
              regex: '(.+)',
              target_label: 'job',
              replacement: '$1',
              action: 'replace',
            },

          ] else
            [] + (
              if ep.port != '' then [
                {
                  target_label: 'endpoint',
                  separator: ';',
                  regex: '(.*)',
                  replacement: ep.port,
                  action: 'replace',
                },
              ] else if ep.targetPort != '' then [
                {
                  target_label: 'endpoint',
                  separator: ';',
                  regex: '(.*)',
                  replacement: ep.targetPort,
                  action: 'replace',
                },
              ] else error 'could not set endpoint label'
            ) +

            ep.relabelings,

        kubernetes_sd_configs: [{
          role: 'endpoints',
          kubeconfig_file: '',
          follow_redirects: ep.followRedirects,
          namespaces: {
            own_namespace: false,
            names:
              if svc.namespaceSelector.any then
                []
              else if std.length(svc.namespaceSelector.matchNames) == 0 then
                [svc.namespace]
              else svc.namespaceSelector.matchNames,
          },
        }],
      }
      for s in serviceProfilers
      for i in std.range(0, std.length(s.endpoints) - 1)
    ],
  },
}
