{{/*
Define the pulsar broker service
*/}}
{{- define "pulsar.broker.service" -}}
{{ template "pulsar.fullname" . }}-{{ .Values.broker.component }}
{{- end }}

{{/*
Define the hostname
*/}}
{{- define "pulsar.broker.hostname" -}}
${HOSTNAME}.{{ template "pulsar.broker.service" . }}.{{ .Values.namespace }}.svc.cluster.local
{{- end -}}

{{/*
Define the broker znode
*/}}
{{- define "pulsar.broker.znode" -}}
{{ .Values.metadataPrefix }}/loadbalance/brokers/{{ template "pulsar.broker.hostname" . }}:{{ .Values.broker.ports.http }}
{{- end }}

{{/*
Define broker zookeeper client tls settings
*/}}
{{- define "pulsar.broker.zookeeper.tls.settings" -}}
{{- $tlsEnabled := false -}}
{{- if .Values.global -}}
{{- if .Values.global.tlsEnabled -}}
{{- $tlsEnabled = true -}}
{{- end -}}
{{- end -}}
{{- if $tlsEnabled }}
/pulsar/keytool/keytool.sh broker true;
{{- end }}
{{- end }}

{{/*
Define broker tls certs mounts
*/}}
{{- define "pulsar.broker.certs.volumeMounts" -}}
{{- $tlsEnabled := false -}}
{{- if .Values.global -}}
{{- if .Values.global.tlsEnabled -}}
{{- $tlsEnabled = true -}}
{{- end -}}
{{- end -}}
{{- if $tlsEnabled }}
- name: keytool
  mountPath: "/pulsar/keytool/keytool.sh"
  subPath: keytool.sh
{{- end }}
{{- end }}

{{/*
Define broker tls certs volumes
*/}}
{{- define "pulsar.broker.certs.volumes" -}}
{{- $tlsEnabled := false -}}
{{- if .Values.global -}}
{{- if .Values.global.tlsEnabled -}}
{{- $tlsEnabled = true -}}
{{- end -}}
{{- end -}}
{{- if $tlsEnabled }}
- name: keytool
  configMap:
    name: "{{ template "pulsar.fullname" . }}-keytool-configmap"
    defaultMode: 0755
{{- end }}
{{- end }}

{{/*
Define pulsar broker liveness probe URL
*/}}
{{- define "pulsar.broker.probe.liveness.url" -}}
{{- $brokerHttpPort := (int .Values.broker.ports.http) -}}
{{- $tenant := .Release.Namespace -}}
{{- if .Values.broker.probe.liveness.tenant -}}
{{- $tenant = .Values.broker.probe.liveness.tenant -}}
{{- end -}}
{{- if .Values.broker.probe.liveness.path -}}
{{- printf "127.0.0.1:%d%s" $brokerHttpPort .Values.broker.probe.liveness.path -}}
{{- else if .Values.broker.probe.liveness.topic -}}
{{- printf "http://127.0.0.1:%d/admin/v2/persistent/%s/%s/stats" $brokerHttpPort $tenant .Values.broker.probe.liveness.topic -}}
{{- end -}}
{{- end -}}
