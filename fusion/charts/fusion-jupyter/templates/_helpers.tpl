{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name of the chart.
*/}}
{{- define "fusion-jupyter.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "fusion-jupyter.fullname" -}}
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
Create chart name and version as used by the chart label.
*/}}
{{- define "fusion-jupyter.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Common labels
*/}}
{{- define "fusion-jupyter.labels" -}}
app.kubernetes.io/name: {{ include "fusion-jupyter.name" . }}
helm.sh/chart: {{ include "fusion-jupyter.chart" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/*
Define the ZK connection string for Solr
*/}}
{{- define "jupyter.zkConnection" -}}
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
{{- $zkPort:="" -}}
{{- if .Values.global -}}
{{- if .Values.global.zkPort -}}
{{- $zkPort = ( .Values.global.zkPort | default .Values.zkPort ) 0}}
{{- else -}}
{{- $zkPort = .Values.zkPort -}}
{{- end -}}
{{- else -}}
{{- $zkPort = .Values.zkPort -}}
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
{{- if ne $i 0 }},{{ end }}{{- printf "%s-zookeeper-%d.%s-%s:%d" $.Release.Name $i $.Release.Name "zookeeper-headless" (int $zkPort) -}}
{{- end -}}
{{- end -}}
{{- else if .Values.zkConnectionString -}}
{{- .Values.zkConnectionString -}}
{{- else -}}
{{- range $i := until ( int ( $zkReplicas )) -}}
{{- if ne $i 0 }},{{ end }}{{- printf "%s-zookeeper-%d.%s-%s:%d" $.Release.Name $i $.Release.Name "zookeeper-headless" (int $zkPort) -}}
{{- end -}}
{{- end -}}
{{- end -}}
