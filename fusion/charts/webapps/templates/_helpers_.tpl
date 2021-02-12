{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name of the chart.
*/}}
{{- define "fusion.webapps.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "fusion.webapps.fullname" -}}
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
Define the service url for pulsar broker
*/}}
{{- define "fusion.webapps.pulsarServiceUrl" -}}
{{- $tlsEnabled := ( eq ( include "fusion.tls.enabled" . ) "true" ) }}
{{- if .Values.global -}}
{{- if .Values.global.pulsarServiceUrl -}}
{{- printf "%s" .Values.global.pulsarServiceUrl -}}
{{- end -}}
{{- end -}}
{{- if .Values.pulsarServiceUrl -}}
{{- printf "%s" .Values.pulsarServiceUrl -}}
{{- else -}}
{{- printf "%s://%s-pulsar-broker:%s" ( ternary "pulsar+ssl" "pulsar" $tlsEnabled  )  .Release.Name ( (ternary .Values.pulsarServiceTLSPort .Values.pulsarServicePort $tlsEnabled ) ) -}}
{{- end -}}
{{- end -}}

{{/*
Define the kubernetes namespace variable
*/}}
{{- define "fusion.webapps.kubeNamespace" -}}
{{- if .Values.namespaceOverride -}}
{{- printf "%s" .Values.namespaceOverride -}}
{{- else -}}
{{- printf "%s" .Release.Namespace -}}
{{- end -}}
{{- end -}}


{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "fusion.webapps.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
  Define the labels that should be applied to all resources in the chart
*/}}
{{- define "fusion.webapps.labels" -}}
helm.sh/chart: "{{ include "fusion.webapps.chart" . }}"
app.kubernetes.io/name: "{{ template "fusion.webapps.name" . }}"
app.kubernetes.io/managed-by: "{{ .Release.Service }}"
app.kubernetes.io/instance: "{{ .Release.Name }}"
app.kubernetes.io/version: "{{ .Chart.AppVersion }}"
app.kubernetes.io/component: "webapps"
app.kubernetes.io/part-of: "fusion"
{{- end -}}
