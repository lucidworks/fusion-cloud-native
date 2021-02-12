{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name of the chart.
*/}}
{{- define "solr.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "solr.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Define the name of the headless service for solr
*/}}
{{- define "solr.headless-service-name" -}}
{{- printf "%s-%s" (include "solr.fullname" .) "headless" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Define the name of the client service for solr
*/}}
{{- define "solr.service-name" -}}
{{- printf "%s-%s" (include "solr.fullname" .) "svc" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Define the name of the solr exporter
*/}}
{{- define "solr.exporter-name" -}}
{{- printf "%s-%s" (include "solr.fullname" .) "exporter" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Define the solr exporter configmap
*/}}
{{- define "solr.exporter-configmap-name" -}}
{{- printf "%s-%s" (include "solr.exporter-name" .) "config" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
The name of the zookeeper service
*/}}
{{- define "solr.zookeeper-connection-string" -}}
{{- /*
# Determine the number of zookeeper replicas
# - If there is a global `zkReplicaCount` set, then we use that
# - If there isn't use the `zookeeper.replicaCount`, and if the
#   zookeeper subchart is disabled use the local `zkReplicaCount` variable
*/ -}}
{{- $tlsEnabled := ( eq (include "fusion.tls.enabled" .) "true" ) -}}
{{- $zkReplicas := "" -}}
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
Create chart name and version as used by the chart label.
*/}}
{{- define "solr.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
  Define the name of the solr PVC
*/}}
{{- define "solr.pvc-name" -}}
{{ printf "%s-%s" (include "solr.fullname" .) "pvc" | trunc 63 | trimSuffix "-"  }}
{{- end -}}

{{/*
  Define the name of the solr.xml configmap
*/}}
{{- define "solr.configmap-name" -}}
{{- printf "%s-%s" (include "solr.fullname" .) "config-map" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
  Define the labels that should be applied to all resources in the chart
*/}}
{{- define "solr.common.labels" -}}
app.kubernetes.io/name: {{ include "solr.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ include "solr.chart" . }}
{{- end -}}
