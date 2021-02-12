## Pulsar helm chart

We took the chart from https://github.com/apache/pulsar-helm-chart and copied it here to customize for Fusion. We are not 
using the official released charts but the aim is to make minimal changes to the original charts so that pulling in updates
in the future will be easier

Broker is configured with message retention, expiry, backlog quota and inactive topics configurations. See values.yaml 
in pulsar chart for broker default configuration

## Customization

1. Modified helpers in `_zookeeper.tpl` to read zookeeper connection string from global values
2. Defined `pulsar.namespace` in `_helpers.tpl` and replaced `{{ .Values.namespace }}` with `{{ template "pulsar.namespace" . }}` 
to make the default namespace to the release namespace
3. Liveness probe url is made configurable
4. Other changes to values yaml to fit our deployment needs
5. Job `bookkeeper-cluster-initialize.yaml` defined as init container for bookkeeper
6. Job `pulsar-cluster-initialize.yaml` defined as init container for broker
7. Namespace removed from broker and bookkeeper service names
8. Increase Journal size from 10Gi to 50Gi
