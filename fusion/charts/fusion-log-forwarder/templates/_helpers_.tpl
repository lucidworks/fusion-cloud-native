
{{/*
Expand the name of the chart.
*/}}
{{- define "fusion.fusion-log-forwarder.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "fusion.fusion-log-forwarder.fullname" -}}
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

{{- define "fusion.fusion-log-forwarder.solrurl" -}}

{{- $tlsEnabled := ( eq ( include "fusion.tls.enabled" . ) "true" ) }}
{{- if .Values.solrSvc -}}
{{- printf "%s://%s:%s/%s"  ( ternary "https" "http" $tlsEnabled  ) .Values.solrSvc .Values.solrPort .Values.solrPath -}}
{{- else -}}
{{- printf "%s://%s-%s:%s/%s" ( ternary "https" "http" $tlsEnabled  ) .Release.Name "solr-svc" .Values.solrPort .Values.solrPath -}}
{{- end -}}
{{- end -}}

{{/*
Define the  url for pulsar broker
*/}}
{{- define "fusion.fusion-log-forwarder.pulsarServiceUrl" -}}
{{- $tlsEnabled := ( eq ( include "fusion.tls.enabled" . ) "true" ) }}
{{- if .Values.global -}}
{{- if .Values.global.pulsarServiceUrl -}}
{{- printf "%s" .Values.global.pulsarUrl -}}
{{- end -}}
{{- end -}}
{{- if .Values.pulsarServiceUrl -}}
{{- printf "%s" .Values.pulsarServiceUrl -}}
{{- else -}}
{{- printf "%s://%s-pulsar-broker:%s" ( ternary "pulsar+ssl" "pulsar" $tlsEnabled  )  .Release.Name ( (ternary .Values.pulsarServiceTLSPort .Values.pulsarServicePort $tlsEnabled ) ) -}}
{{- end -}}
{{- end -}}

{{/*
Define the admin url for pulsar broker
*/}}
{{- define "fusion.fusion-log-forwarder.pulsarAdminUrl" -}}
{{- $tlsEnabled := ( eq ( include "fusion.tls.enabled" . ) "true" ) }}
{{- if .Values.global -}}
{{- if .Values.global.pulsarAdminUrl -}}
{{- printf "%s" .Values.global.pulsarAdminUrl -}}
{{- end -}}
{{- end -}}
{{- if .Values.pulsarAdminUrl -}}
{{- printf "%s" .Values.pulsarAdminUrl -}}
{{- else -}}
{{- printf "%s://%s-pulsar-broker:%s" ( ternary "https" "http" $tlsEnabled  )  .Release.Name ( (ternary .Values.pulsarTLSPort .Values.pulsarPort $tlsEnabled ) ) -}}
{{- end -}}
{{- end -}}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "fusion.fusion-log-forwarder.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
  Define the labels that should be applied to all resources in the chart
*/}}
{{- define "fusion.fusion-log-forwarder.labels" -}}
helm.sh/chart: "{{ include "fusion.fusion-log-forwarder.chart" . }}"
app.kubernetes.io/name: "{{ template "fusion.fusion-log-forwarder.name" . }}"
app.kubernetes.io/managed-by: "{{ .Release.Service }}"
app.kubernetes.io/instance: "{{ .Release.Name }}"
app.kubernetes.io/version: "{{ .Chart.AppVersion }}"
app.kubernetes.io/component: "fusion-log-forwarder"
app.kubernetes.io/part-of: "fusion"
{{- end -}}
