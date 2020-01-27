#!/bin/bash

PROVIDER=gke
CLUSTER_NAME=
RELEASE=f5
NAMESPACE=default
NODE_POOL=""

function print_usage() {
  CMD="$1"
  ERROR_MSG="$2"

  if [ "$ERROR_MSG" != "" ]; then
    echo -e "\nERROR: $ERROR_MSG"
  fi

  echo -e "\nUse this script to install Prometheus and Grafana into an existing Fusion 5 cluster"
  echo -e "\nUsage: $CMD [OPTIONS] ... where OPTIONS include:\n"
  echo -e "  -c            Name of the K8s cluster (required)\n"
  echo -e "  -r            Helm release name for installing Fusion 5, defaults to 'f5'\n"
  echo -e "  -n            Kubernetes namespace to install Fusion 5 into, defaults to 'default'\n"
  echo -e "  --node-pool   Node pool label to assign pods to specific nodes, this option is only useful for existing clusters"
  echo -e "                where you defined a custom node pool, wrap the arg in double-quotes\n"
  echo -e "  --provider    Lowercase label for your K8s platform provider, e.g. eks, aks, gke; defaults to 'gke'\n"
}

if [ $# -gt 0 ]; then
  while true; do
    case "$1" in
        -c)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the -c parameter!"
              exit 1
            fi
            CLUSTER_NAME="$2"
            shift 2
        ;;
        -n)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the -n parameter!"
              exit 1
            fi
            NAMESPACE="$2"
            shift 2
        ;;
        -r)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the -r parameter!"
              exit 1
            fi
            RELEASE="$2"
            shift 2
        ;;
        --node-pool)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the --node-pool parameter!"
              exit 1
            fi
            NODE_POOL="$2"
            shift 2
        ;;
        --provider)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the --provider parameter!"
              exit 1
            fi
            PROVIDER="$2"
            shift 2
        ;;
        -help|-usage|--help|--usage)
            print_usage "$SCRIPT_CMD"
            exit 0
        ;;
        --)
            shift
            break
        ;;
        *)
            if [ "$1" != "" ]; then
              print_usage "$SCRIPT_CMD" "Unrecognized or misplaced argument: $1!"
              exit 1
            else
              break # out-of-args, stop looping
            fi
        ;;
    esac
  done
fi

if [ "$CLUSTER_NAME" == "" ]; then
  print_usage "$SCRIPT_CMD" "Please provide the K8s cluster name using: -c <cluster>"
  exit 1
fi

if [ "$RELEASE" == "" ]; then
  print_usage "$SCRIPT_CMD" "Please provide the Helm release name using: -r <release>"
  exit 1
fi

if kubectl get sts -n "${NAMESPACE}" -l "app=prometheus" -o "jsonpath={.items[0].metadata.labels['release']}" 2>&1 | grep -q "${RELEASE}-prom"; then
  echo -e "\nERROR: There is already a Prometheus StatefulSet in namespace: ${NAMESPACE} with release name: ${RELEASE}-prom\n"
  exit 1
fi

if [ "${NODE_POOL}" == "" ]; then
  if [ "${PROVIDER}" == "eks" ]; then
    NODE_POOL="alpha.eksctl.io/nodegroup-name: standard-workers"
  elif [ "${PROVIDER}" == "gke" ]; then
    NODE_POOL="cloud.google.com/gke-nodepool: default-pool"
  else
    NODE_POOL="{}"
  fi
fi

PROMETHEUS_VALUES="${PROVIDER}_${CLUSTER_NAME}_${RELEASE}_prom_values.yaml"
if [ ! -f "${PROMETHEUS_VALUES}" ]; then
  cp example-values/prometheus-values.yaml $PROMETHEUS_VALUES
  sed -i ''  -e "s|{NODE_POOL}|${NODE_POOL}|g" "$PROMETHEUS_VALUES"
  sed -i ''  -e "s|{NAMESPACE}|${NAMESPACE}|g" "$PROMETHEUS_VALUES"
  echo -e "\nCreated Prometheus custom values yaml: ${PROMETHEUS_VALUES}. Keep this file handy as you'll need it to customize your Prometheus installation.\n"
fi

GRAFANA_VALUES="${PROVIDER}_${CLUSTER_NAME}_${RELEASE}_graf_values.yaml"
if [ ! -f "${GRAFANA_VALUES}" ]; then
  cp example-values/grafana-values.yaml $GRAFANA_VALUES
  sed -i ''  -e "s|{NODE_POOL}|${NODE_POOL}|g" "$GRAFANA_VALUES"
  echo -e "\nCreated Grafana custom values yaml: ${GRAFANA_VALUES}. Keep this file handy as you'll need it to customize your Grafana installation.\n"
fi

echo -e "\nInstalling Prometheus and Grafana for monitoring Fusion metrics ... this can take a few minutes.\n"

helm upgrade ${RELEASE}-prom stable/prometheus --install --namespace "${NAMESPACE}" -f "$PROMETHEUS_VALUES" --version 9.0.0
kubectl rollout status statefulsets/${RELEASE}-prom-prometheus-server --timeout=180s --namespace "${NAMESPACE}"

helm upgrade ${RELEASE}-graf stable/grafana --install --namespace "${NAMESPACE}" -f "$GRAFANA_VALUES"
kubectl rollout status deployments/${RELEASE}-graf-grafana --timeout=60s --namespace "${NAMESPACE}"

echo -e "\n\nSuccessfully installed Prometheus (${RELEASE}-prom) and Grafana (${RELEASE}-graf) into the ${NAMESPACE} namespace.\n"
