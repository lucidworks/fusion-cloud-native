{{/*
Define the pulsar zookeeper
*/}}
{{- define "pulsar.zookeeper.service" -}}
{{ template "pulsar.fullname" . }}-{{ .Values.zookeeper.component }}
{{- end }}

{{/*
Define the pulsar zookeeper
*/}}
{{- define "pulsar.zookeeper.connect" -}}
{{- $tlsEnabled := (eq (include "fusion.tls.enabled" . ) "true" ) }}
{{- /*
# Determine the number of zookeeper replicas
# - If there is a global `zkReplicaCount` set, then we use that
# - If there isn't use the `zookeeper.replicaCount`, and if the
#   zookeeper subchart is disabled use the local `zkReplicaCount` variable
*/ -}}
{{- $zkReplicas:="" -}}
{{- if .Values.global -}}
{{- if .Values.global.zkReplicaCount -}}
{{- $zkReplicas = .Values.global.zkReplicaCount -}}
{{- else -}}
{{- $zkReplicas = ( .Values.zookeeper.replicaCount | default .Values.zkReplicaCount ) -}}
{{- end -}}
{{- else -}}
{{- $zkReplicas = ( .Values.zookeeper.replicaCount | default .Values.zkReplicaCount ) -}}
{{ end }}
{{- /*
# Determine the zookeeper port
# - If these is a global `zkPort` specified then use that,
# - If there isn't then use the local `zkPort` variable
*/ -}}
{{- $zkPort := "" -}}
{{- if .Values.global -}}
{{- if .Values.global.zkPort -}}
{{- $zkPort = ( .Values.global.zkPort | default .Values.zkPort ) -}}
{{- else -}}
{{- $zkPort = .Values.zkPort -}}
{{- end -}}
{{- else -}}
{{- $zkPort = .Values.zkPort -}}
{{- end -}}

{{- $zkTLSPort := "" -}}
{{- if .Values.global -}}
{{- if .Values.global.zkTLSPort -}}
{{- $zkTLSPort = ( .Values.global.zkTLSPort | default .Values.zkTLSPort ) -}}
{{- else -}}
{{- $zkTLSPort = .Values.zkTLSPort -}}
{{- end -}}
{{- else -}}
{{- $zkTLSPort = .Values.zkTLSPort -}}
{{- end -}}

{{- /*
# Determine the zookeeper connection string
# - If we have a global `zkConnectionString` defined then we use that
# - Else if we have a local `zkConnectionString` defined then use that
# - Else construct the zkConnection string using the zkReplicas and zkPort
#   variables that we determined before.
*/ -}}
{{- if .Values.global }}
{{- if .Values.global.zkConnectionString -}}
{{- .Values.global.zkConnectionString -}}
{{- else if .Values.zkConnectionString -}}
{{- .Values.zkConnectionString -}}
{{- else -}}
{{- range $i := until ( int ( $zkReplicas )) -}}
{{- if ne $i 0 }},{{ end }}{{- printf "%s-zookeeper-%d.%s-%s:%d" $.Release.Name $i $.Release.Name "zookeeper-headless" (ternary (int $zkTLSPort) (int $zkPort) $tlsEnabled ) -}}
{{- end -}}
{{- end -}}
{{- else if .Values.zkConnectionString -}}
{{- .Values.zkConnectionString -}}
{{- else -}}
{{- range $i := until ( int ( $zkReplicas )) -}}
{{- if ne $i 0 }},{{ end }}{{- printf "%s-zookeeper-%d.%s-%s:%d" $.Release.Name $i $.Release.Name "zookeeper-headless" (ternary (int $zkTLSPort) (int $zkPort) $tlsEnabled ) -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Define the zookeeper hostname
*/}}
{{- define "pulsar.zookeeper.hostname" -}}
${HOSTNAME}.{{ template "pulsar.zookeeper.service" . }}.{{ template "pulsar.namespace" . }}.svc.cluster.local
{{- end -}}

{{/*
Define zookeeper tls settings
*/}}
{{- define "pulsar.zookeeper.tls.settings" -}}
{{- $tlsEnabled := false -}}
{{- if .Values.global -}}
{{- if .Values.global.tlsEnabled -}}
{{- $tlsEnabled = true -}}
{{- end -}}
{{- end -}}
{{- if $tlsEnabled }}
/pulsar/keytool/keytool.sh zookeeper {{ template "pulsar.zookeeper.hostname" . }} false;
{{- end }}
{{- end }}
