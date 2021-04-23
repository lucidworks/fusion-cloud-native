#!/bin/bash
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" > /dev/null && pwd )"

function print_usage() {
  CMD="$1"
  ERROR_MSG="$2"

  if [ "$ERROR_MSG" != "" ]; then
    echo -e "\nERROR: $ERROR_MSG"
  fi

  echo -e "\nUse this script to scale a Fusion cluster in the specified namespace down when not in use, or back up when needed"
  echo -e "\nUsage: $CMD up|down [OPTIONS] ... where OPTIONS include:\n"
  echo -e "  -c   Name of the cluster (required)\n"
  echo -e "  -p   GCP Project ID (required)\n"
  echo -e "  -n   Kubernetes namespace where Fusion 5 is running (required)\n"
  echo -e "  -r   Helm release name for installing Fusion 5; defaults to the namespace, see -n option\n"
  echo -e "  -z   GCP Zone the cluster is running in, defaults to 'us-west1'\n"
}

SCRIPT_CMD="$0"
GCLOUD_PROJECT=
GCLOUD_ZONE="us-west1"
CLUSTER_NAME=
ACTION="down"

if [ $# -gt 0 ]; then
  while true; do
    case "$1" in
        up)
            ACTION="up"
            shift 1
        ;;
        down)
            ACTION="down"
            shift 1
        ;;
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
        -p)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the -p parameter!"
              exit 1
            fi
            GCLOUD_PROJECT="$2"
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
        -z)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the -z parameter!"
              exit 1
            fi
            GCLOUD_ZONE="$2"
            shift 2
        ;;
        -help|-usage)
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
  print_usage "$SCRIPT_CMD" "Please provide the GKE cluster name using: -c <cluster>"
  exit 1
fi

if [ "$GCLOUD_PROJECT" == "" ]; then
  print_usage "$SCRIPT_CMD" "Please provide the GCP project name using: -p <project>"
  exit 1
fi

if [ "$NAMESPACE" == "" ]; then
  print_usage "$SCRIPT_CMD" "Please provide the Kubernetes namespace using: -n <namespace>"
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

has_gcloud=$(gcloud --version > /dev/null 2<&1)
has_prereq=$?
if [ $has_prereq == 1 ]; then
  echo -e "\nERROR: Must install GCloud command line tools! See https://cloud.google.com/sdk/docs/quickstarts"
  exit 1
fi

# verify the user is logged in ...
who_am_i=$(gcloud auth list --filter=status:ACTIVE --format="value(account)")
if [ "$who_am_i" == "" ]; then
  echo -e "\nERROR: GCloud user unknown, please use: 'gcloud auth login <account>' before proceeding with this script!"
  exit 1
fi

echo -e "\nLogged in as: $who_am_i\n"

hash kubectl
has_prereq=$?
if [ $has_prereq == 1 ]; then
  echo -e "\nERROR: Must install kubectl before proceeding with this script! For GKE, see: https://cloud.google.com/sdk/docs/"
  exit 1
fi

current_value=$(gcloud config get-value compute/zone)
if [ "${current_value}" != "${GCLOUD_ZONE}" ]; then
  gcloud config set compute/zone "${GCLOUD_ZONE}"
  echo -e "Set compute/zone to '${GCLOUD_ZONE}'"
fi

current_value=$(gcloud config get-value project)
if [ "${current_value}" != "${GCLOUD_PROJECT}" ]; then
  gcloud config set project "${GCLOUD_PROJECT}"
fi

gcloud container clusters get-credentials $CLUSTER_NAME
kubectl config current-context
kubectl config set-context --current --namespace=${NAMESPACE}

declare -a deployments=("admin-ui" "api-gateway" "argo-argo-ui" "argo-workflow-controller" "auth-ui" "connectors" "connectors-backend" "devops-ui" "fusion-admin" "fusion-indexing" "fusion-jupyter" "fusion-log-forwarder" "fusion-superset" "fusion-superset-proxy" "monitoring-grafana" "insights" "job-launcher" "job-rest-server" "ml-model-service" "ml-model-service-ambassador" "ml-model-service-mysql" "pm-ui" "monitoring-prometheus-kube-state-metrics" "monitoring-prometheus-pushgateway" "query-pipeline" "rules-ui" "sql-service-cm" "sql-service-cr" "templating" "tikaserver" "webapps")

if [ "$ACTION" == "down" ]; then

  # delete any spark driver pods
  kubectl delete po -l spark-role=driver -n ${NAMESPACE}

  # scale down the deployments first, then the statefulsets
  for i in "${deployments[@]}"
  do
     next="${RELEASE}-$i"
     kubectl scale deployments/${next} --replicas=0 -n ${NAMESPACE}
  done

  kubectl scale deployments/seldon-controller-manager --replicas=0 -n ${NAMESPACE}
  kubectl scale deployments/milvus-writable --replicas=0 -n ${NAMESPACE}

  # scale down the seldon deployments. When updating to Seldon Core beyond 1.1.0, instead of delete use:
  #  kubectl scale seldondeployments --replicas=0 --all -n ${NAMESPACE}

  kubectl delete seldondeployments -n ${NAMESPACE} --all 

  declare -a stateful=("classic-rest-service" "solr" "pulsar-bookkeeper" "pulsar-broker" "monitoring-prometheus-server")
  for i in "${stateful[@]}"
  do
     next="${RELEASE}-$i"
     kubectl scale statefulsets/${next} --replicas=0 -n ${NAMESPACE}
  done

  # do ZK last ... and wait
  kubectl scale statefulsets/${RELEASE}-zookeeper --replicas=0 -n ${NAMESPACE} --timeout=180s

  echo -e "\nAll done! To bring the cluster back, run your Fusion upgrade script.\n"
  exit 0
fi

UPGRADE_SCRIPT="${SCRIPT_DIR}/gke_${CLUSTER_NAME}_${RELEASE}_upgrade_fusion.sh"
if [ -f "${UPGRADE_SCRIPT}" ]; then
  if [ -f "${SCRIPT_DIR}/gke_${CLUSTER_NAME}_${RELEASE}_monitoring_values.yaml" ]; then
    echo -e "Restoring Prometheus / Grafana using ${SCRIPT_DIR}/gke_${CLUSTER_NAME}_${RELEASE}_monitoring_values.yaml"
    ( "${SCRIPT_DIR}/install_prom.sh" -c "${CLUSTER_NAME}" -n "${NAMESPACE}" -r "${RELEASE}" --provider "gke" )
  fi
  echo -e "Restoring Fusion using ${UPGRADE_SCRIPT}"
  ( ${UPGRADE_SCRIPT} )
else
  echo -e "\nERROR: Fusion upgrade script ${UPGRADE_SCRIPT} not found! This script is needed to restore your cluster."
fi



