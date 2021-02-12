{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name of the chart.
*/}}
{{- define "fusion.api-gateway.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "fusion.api-gateway.fullname" -}}
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
{{- define "fusion.api-gateway.pulsarServiceUrl" -}}
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
{{- define "fusion.api-gateway.kubeNamespace" -}}
{{- if .Values.namespaceOverride -}}
{{- printf "%s" .Values.namespaceOverride -}}
{{- else -}}
{{- printf "%s" .Release.Namespace -}}
{{- end -}}
{{- end -}}



{{/*
  Define the name of the service
*/}}
{{- define "fusion.api-gateway.serviceName" -}}
{{- printf "proxy" -}}
{{- end -}}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "fusion.api-gateway.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Define the repository that the keytools utils is pulled from,
by default it will pull from the same repository as api-gateway but
this can be overridden with the keytoolUtils.image.repository field
*/}}
{{- define "fusion.api-gateway.keytoolUtilsRepository" -}}
{{- if .Values.keytoolUtils.image.repository -}}
{{- printf "%s" .Values.keytoolUtils.image.repository -}}
{{- else -}}
{{- printf "%s" .Values.image.repository -}}
{{- end -}}
{{- end -}}


{{/*
  Define the labels that should be applied to all resources in the chart
*/}}
{{- define "fusion.api-gateway.labels" -}}
helm.sh/chart: "{{ include "fusion.api-gateway.chart" . }}"
app.kubernetes.io/name: "{{ template "fusion.api-gateway.name" . }}"
app.kubernetes.io/managed-by: "{{ .Release.Service }}"
app.kubernetes.io/instance: "{{ .Release.Name }}"
app.kubernetes.io/version: "{{ .Chart.AppVersion }}"
app.kubernetes.io/component: "api-gateway"
app.kubernetes.io/part-of: "fusion"
{{- end -}}

{{/*
Define the Spring Profile
*/}}
{{- define "fusion.api-gateway.springProfs" -}}
{{- if .Values.springProfilesOverride -}}
{{- printf "%s" .Values.springProfilesOverride -}}
{{- else -}}
{{- if .Values.datadog.enabled }}
{{- printf "%s,datadog" .Values.springProfiles -}}
{{- else -}}
{{- printf "%s" .Values.springProfiles -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Define the Datadog configuration
*/}}
{{- define "fusion.api-gateway.datadogHost" -}}
{{- if .Values.datadog.host -}}
{{- .Values.datadog.host -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name "datadog" -}}
{{- end -}}
{{- end -}}

{{/*
Define the Zipkin URL
*/}}
{{- define "fusion.api-gateway.zipkinUrl" -}}
{{- if .Values.zipkin.baseUrl -}}
{{- .Values.zipkin.baseUrl -}}
{{- else -}}
{{- printf "http://%s-%s:9411/" .Release.Name "zipkin" -}}
{{- end -}}
{{- end -}}


{{/*
Define the annotations for scraping prometheus metrics from this application
*/}}
{{- define "fusion.api-gateway.annotations" -}}
{{ if .Values.service.annotations }}
{{ toYaml .Values.service.annotations }}
{{ end }}
prometheus.io/scrape: "true"
prometheus.io/port: "{{ .Values.port }}"
{{- end -}}
