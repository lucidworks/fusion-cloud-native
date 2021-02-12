{{/*
Define the pulsar autorecovery service
*/}}
{{- define "pulsar.autorecovery.service" -}}
{{ template "pulsar.fullname" . }}-{{ .Values.autorecovery.component }}
{{- end }}

{{/*
Define the autorecovery hostname
*/}}
{{- define "pulsar.autorecovery.hostname" -}}
${HOSTNAME}.{{ template "pulsar.autorecovery.service" . }}.{{ template "pulsar.namespace" . }}.svc.cluster.local
{{- end -}}

{{/*
Define autorecovery zookeeper client tls settings
*/}}
{{- define "pulsar.autorecovery.zookeeper.tls.settings" -}}
{{- $tlsEnabled := false -}}
{{- if .Values.global -}}
{{- if .Values.global.tlsEnabled -}}
{{- $tlsEnabled = true -}}
{{- end -}}
{{- end -}}
{{- if $tlsEnabled }}
/pulsar/keytool/keytool.sh autorecovery true;
{{- end }}
{{- end }}

{{/*
Define autorecovery tls certs mounts
*/}}
{{- define "pulsar.autorecovery.certs.volumeMounts" -}}
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
Define autorecovery tls certs volumes
*/}}
{{- define "pulsar.autorecovery.certs.volumes" -}}
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
Define autorecovery init container : verify cluster id
*/}}
{{- define "pulsar.autorecovery.init.verify_cluster_id" -}}
bin/apply-config-from-env.py conf/bookkeeper.conf;
{{- include "pulsar.autorecovery.zookeeper.tls.settings" . -}}
until bin/bookkeeper shell whatisinstanceid; do
  sleep 3;
done;
{{- end }}
