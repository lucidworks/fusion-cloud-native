#!/bin/bash

PROVIDER=gke
NODE_POOL=""
UPGRADE=0

function print_usage() {
  CMD="$1"
  ERROR_MSG="$2"

  if [ "$ERROR_MSG" != "" ]; then
    echo -e "\nERROR: $ERROR_MSG"
  fi

  echo -e "\nUse this script to install Prometheus and Grafana into an existing Fusion 5 cluster"
  echo -e "\nUsage: $CMD [OPTIONS] ... where OPTIONS include:\n"
  echo -e "  -c            Name of the K8s cluster (required)\n"
  echo -e "  -n            Kubernetes namespace to install Fusion 5 into (required)\n"
  echo -e "  -r            Helm release name for installing Fusion 5; defaults to the namespace, see -n option\n"
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

if [ "$NAMESPACE" == "" ]; then
  print_usage "$SCRIPT_CMD" "Please provide the K8s namespace using: -n <namespace>"
  exit 1
fi

valid="0-9a-zA-Z\-"
if [[ $NAMESPACE =~ [^$valid] ]]; then
  echo -e "\nERROR: Namespace $NAMESPACE must only contain 0-9, a-z, A-Z, or dash!\n"
  exit 1
fi

if [ -z ${RELEASE+x} ]; then
  # keep "f5" as the default for legacy purposes when using the default namespace
  if [ "${NAMESPACE}" == "default" ]; then
    RELEASE="f5"
  else
    RELEASE="$NAMESPACE"
  fi
fi

if [[ $RELEASE =~ [^$valid] ]]; then
  echo -e "\nERROR: Release $RELEASE must only contain 0-9, a-z, A-Z, or dash!\n"
  exit 1
fi

if ! helm repo list | grep -q "https://kubernetes-charts.storage.googleapis.com"; then
  echo -e "\nAdding the stable chart repo to helm repo list"
  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
  helm repo add grafana https://grafana.github.io/helm-charts
fi

if ! kubectl get namespace "${NAMESPACE}" > /dev/null 2>&1; then
  kubectl create namespace "${NAMESPACE}"
  if [ "$PROVIDER" == "gke" ]; then
    who_am_i=$(gcloud auth list --filter=status:ACTIVE --format="value(account)")
  else
    who_am_i=""
  fi
  OWNER_LABEL="${who_am_i//@/-}"
  if [ "${OWNER_LABEL}" != "" ]; then
    kubectl label namespace "${NAMESPACE}" "owner=${OWNER_LABEL}"
  fi
  echo -e "\nCreated namespace ${NAMESPACE} with owner label ${OWNER_LABEL}\n"
fi

if kubectl get sts -n "${NAMESPACE}" -l "app=prometheus" -o "jsonpath={.items[0].metadata.labels['release']}" 2>&1 | grep -q "${RELEASE}-monitoring"; then
  echo -e "\nThere is already a Prometheus StatefulSet in namespace: ${NAMESPACE} with release name: ${RELEASE}-monitoring, assuming this is an upgrade\n"
  UPGRADE=1
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

MONITORING_VALUES="${PROVIDER}_${CLUSTER_NAME}_${RELEASE}_monitoring_values.yaml"
if [ ! -f "${MONITORING_VALUES}" ]; then
  cp example-values/monitoring-values.yaml "${MONITORING_VALUES}"
  if [[ "$OSTYPE" == "linux-gnu" ]]; then
    sed -i -e "s|{NODE_POOL}|${NODE_POOL}|g" "${MONITORING_VALUES}"
    sed -i -e "s|{NAMESPACE}|${NAMESPACE}|g" "${MONITORING_VALUES}"
  else
    sed -i '' -e "s|{NODE_POOL}|${NODE_POOL}|g" "${MONITORING_VALUES}"
    sed -i '' -e "s|{NAMESPACE}|${NAMESPACE}|g" "${MONITORING_VALUES}"
  fi
  echo -e "\nCreated Monitoring custom values yaml: ${MONITORING_VALUES}. Keep this file handy as you'll need it to customize your Monitoring installation.\n"
fi


if [ "$UPGRADE" != "1" ]; then
  echo -e "\nInstalling Prometheus and Grafana for monitoring Fusion metrics ... this can take a few minutes.\n"
fi

helm dep up ./monitoring/helm/fusion-monitoring

helm upgrade --install "${RELEASE}-monitoring" ./monitoring/helm/fusion-monitoring --namespace "${NAMESPACE}" -f "${MONITORING_VALUES}" \
  --set-file grafana.dashboards.default.dashboard_gateway_metrics.json=monitoring/grafana/dashboard_gateway_metrics.json \
  --set-file grafana.dashboards.default.dashboard_indexing_metrics.json=monitoring/grafana/dashboard_indexing_metrics.json \
  --set-file grafana.dashboards.default.dashboard_jvm_metrics.json=monitoring/grafana/dashboard_jvm_metrics.json \
  --set-file grafana.dashboards.default.dashboard_query_pipeline.json=monitoring/grafana/dashboard_query_pipeline.json \
  --set-file grafana.dashboards.default.dashboard_solr_core.json=monitoring/grafana/dashboard_solr_core.json \
  --set-file grafana.dashboards.default.dashboard_solr_node.json=monitoring/grafana/dashboard_solr_node.json \
  --set-file grafana.dashboards.default.dashboard_solr_system.json=monitoring/grafana/dashboard_solr_system.json \
  --set-file grafana.dashboards.default.kube_metrics.json=monitoring/grafana/kube_metrics.json \
  --set-file grafana.dashboards.default.kube_metrics.json=monitoring/grafana/pulsar_grafana_dashboard.json \
  --render-subchart-notes --wait

ACTION=installed
if [ "$UPGRADE" == "1" ]; then
  ACTION="upgraded"
fi

echo -e "\n\nSuccessfully $ACTION Prometheus and Grafana into the ${NAMESPACE} namespace.\n"
helm ls -n "${NAMESPACE}"