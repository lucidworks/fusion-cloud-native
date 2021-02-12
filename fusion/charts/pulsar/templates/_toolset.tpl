{{/*
Define the pulsar toolset service
*/}}
{{- define "pulsar.toolset.service" -}}
{{ template "pulsar.fullname" . }}-{{ .Values.toolset.component }}
{{- end }}

{{/*
Define the toolset hostname
*/}}
{{- define "pulsar.toolset.hostname" -}}
${HOSTNAME}.{{ template "pulsar.toolset.service" . }}.{{ template "pulsar.namespace" . }}.svc.cluster.local
{{- end -}}

{{/*
Define toolset zookeeper client tls settings
*/}}
{{- define "pulsar.toolset.zookeeper.tls.settings" -}}
{{- $tlsEnabled := false -}}
{{- if .Values.global -}}
{{- if .Values.global.tlsEnabled -}}
{{- $tlsEnabled = true -}}
{{- end -}}
{{- end -}}
{{- if $tlsEnabled -}}
/pulsar/keytool/keytool.sh toolset true;
{{- end -}}
{{- end }}

{{/*
Define toolset tls certs mounts
*/}}
{{- define "pulsar.toolset.certs.volumeMounts" -}}
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
Define toolset tls certs volumes
*/}}
{{- define "pulsar.toolset.certs.volumes" -}}
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
