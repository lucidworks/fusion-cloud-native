#!/bin/bash

shopt -s expand_aliases

CHART_VERSION="5.0.3-3"
SOLR_REPLICAS=1
PROMETHEUS="none"
SCRIPT_CMD="$0"
CLUSTER_NAME="microk8s"
RELEASE=f5
NAMESPACE=default
UPGRADE=0
CREATE_MODE=
PURGE=0
FORCE=0
CUSTOM_MY_VALUES=()
MY_VALUES=()
ML_MODEL_STORE="fusion"
DRY_RUN=""
SOLR_DISK_GB=20
CURRENT_USER=`whoami`
PROVIDER="microk8s"

function print_usage() {
  CMD="$1"
  ERROR_MSG="$2"

  if [ "$ERROR_MSG" != "" ]; then
    echo -e "\nERROR: $ERROR_MSG"
  fi

  echo -e "\nUse this script to install Fusion 5 on microk8s, running locally\n"
  echo -e "\nUsage: $CMD [OPTIONS] ... where OPTIONS include:\n"
  echo -e "  -c          Cluster name, defaults to 'microk8s'\n"
  echo -e "  -r          Helm release name for installing Fusion 5, defaults to 'f5'\n"
  echo -e "  -n          Kubernetes namespace to install Fusion 5 into, defaults to 'default'\n"
  echo -e "  --prometheus  Enable Prometheus and Grafana for monitoring Fusion services, pass one of: install, provided, none; defaults to 'none' that skips that step"
  echo -e "                'install' installs Prometheus and Grafana from the stable Helm repo,\n"
  echo -e "                'provided' enables pod annotations on Fusion services to work with Prometheus but does NOT install anything\n"
  echo -e "  --version   Fusion Helm Chart version, defaults to ${CHART_VERSION}\n"
  echo -e "  --values    Custom values file containing config overrides; defaults to microk8s_<cluster>_<release>_fusion_values.yaml  (can be specified multiple times)\n"
  echo -e "  --num-solr    Number of Solr pods to deploy, defaults to ${SOLR_REPLICAS}\n"
  echo -e "  --upgrade   Perform a Helm upgrade on an existing Fusion installation\n"
  echo -e "  --dry-run     Perform a dry-run of the upgrade to see what would change\n"
  echo -e "  --purge     Uninstall and purge all Fusion objects from the specified namespace and cluster\n"
  echo -e "  --force       Force upgrade or purge a deployment if your account is not the value 'owner' label on the namespace\n"
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
        --prometheus)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the --prometheus parameter!"
              exit 1
            fi
            PROMETHEUS="$2"
            shift 2
        ;;
        --num-solr)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the --num-solr parameter!"
              exit 1
            fi
            SOLR_REPLICAS=$2
            shift 2
        ;;
        --version)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the --version parameter!"
              exit 1
            fi
            CHART_VERSION="$2"
            shift 2
        ;;
        --values)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the --values parameter!"
              exit 1
            fi
            CUSTOM_MY_VALUES+=("$2")
            shift 2
        ;;
        --upgrade)
            UPGRADE=1
            shift 1
        ;;
        --dry-run)
            DRY_RUN="--dry-run"
            shift 1
        ;;
        --purge)
            PURGE=1
            shift 1
        ;;
        --force)
            FORCE=1
            shift 1
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
  print_usage "$SCRIPT_CMD" "Please provide the microk8s cluster name using: -c <cluster>"
  exit 1
fi

DEFAULT_MY_VALUES="microk8s_${CLUSTER_NAME}_${RELEASE}_fusion_values.yaml"

alias kubectl="sudo microk8s.kubectl"
alias helm="sudo microk8s.helm"

# uncomment for debug
#echo "\nCLUSTER_NAME: ${CLUSTER_NAME}"
#echo "\nCHART_VERSION: ${CHART_VERSION}"
#echo "\nSOLR_REPLICAS: ${SOLR_REPLICAS}"
#echo "\nPROMETHEUS: ${PROMETHEUS}"
#echo "\nSCRIPT_CMD: ${SCRIPT_CMD}"
#echo "\nRELEASE: ${RELEASE}"
#echo "\nNAMESPACE: ${NAMESPACE}"
#echo "\nUPGRADE: ${UPGRADE}"
#echo "\nPURGE: ${PURGE}"
#echo "\nFORCE: ${FORCE}"
#echo "\nCUSTOM_MY_VALUES: ${CUSTOM_MY_VALUES}"
#echo "\nMY_VALUES: ${MY_VALUES}"
#echo "\nML_MODEL_STORE: ${ML_MODEL_STORE}"
#echo "\nDRY_RUN: ${DRY_RUN}"
#echo "\nSOLR_DISK_GB: ${SOLR_DISK_GB}"
#echo "\nCURRENT_USER: ${CURRENT_USER}"

if [ "$PURGE" == "1" ]; then
  FORCE_ARG=""
  if [ "${FORCE}" == "1" ]; then
    FORCE_ARG=" --force"
  fi
  source ./setup_f5_k8s.sh -c ${CLUSTER_NAME} -r ${RELEASE} -n ${NAMESPACE} --purge ${FORCE_ARG} --provider ${PROVIDER}
  exit 0
fi

echo -e "\nConfigured to use cluster: ${current_cluster}"

if [ "$UPGRADE" == "0" ]; then
  kubectl create clusterrolebinding cluster-admin-binding --clusterrole=cluster-admin --user=${CURRENT_USER}
fi

lw_helm_repo=lucidworks

echo -e "\nAdding the Lucidworks chart repo to helm repo list"
helm repo list | grep "https://charts.lucidworks.com"
if [ $? ]; then
  helm repo add "${lw_helm_repo}" https://charts.lucidworks.com
fi

helm repo update

echo -e "\nInstalling Fusion 5.0 Helm chart ${CHART_VERSION} into namespace ${NAMESPACE} with release tag: ${RELEASE} using custom values from ${MY_VALUES[*]}"

if [ ! -z "${CUSTOM_MY_VALUES[*]}" ]; then
  MY_VALUES=(${CUSTOM_MY_VALUES[@]})
fi

VALUES_STRING=""
if [ "${UPGRADE}" == "1" ] && [ -z "$MY_VALUES" ] && [ -f "${DEFAULT_MY_VALUES}" ]; then
  MY_VALUES=( ${DEFAULT_MY_VALUES} )
fi

for v in "${MY_VALUES[@]}"; do
  if [ ! -f "${v}" ]; then
    echo -e "\nWARNING: Custom values file ${v} not found!\nYou need to provide the same custom values you provided when creating the cluster in order to upgrade.\n"
    exit 1
  fi
  VALUES_STRING="${VALUES_STRING} --values ${v}"
done

if [ -z "${ADDITIONAL_VALUES}" ]; then
  VALUES_STRING="${VALUES_STRING} ${ADDITIONAL_VALUES}"
fi

# Invoke the generic K8s setup script to complete the install/upgrade
INGRESS_ARG=""
if [ ! -z "${INGRESS_HOSTNAME}" ]; then
  INGRESS_ARG=" --ingress ${INGRESS_HOSTNAME}"
fi

UPGRADE_ARGS=""
if [ "${UPGRADE}" == "1" ]; then
  UPGRADE_ARGS=" --upgrade"
  if [ "${FORCE}" == "1" ]; then
    UPGRADE_ARGS="$UPGRADE_ARGS --force"
  fi
  if [ "${DRY_RUN}" != "" ]; then
    UPGRADE_ARGS="$UPGRADE_ARGS --dry-run"
  fi
else
  if [ "${PURGE}" == "1" ]; then
    UPGRADE_ARGS=" --purge"
    if [ "${FORCE}" == "1" ]; then
      UPGRADE_ARGS="$UPGRADE_ARGS --force"
    fi
  fi
fi

if [ "${NODE_POOL}" == "" ]; then
  # the user did not specify a node pool label, but our templating needs one
  for node in $(kubectl get nodes --namespace="${NAMESPACE}" -o=name); do kubectl label "$node" fusion_node_type=system; done
  NODE_POOL="fusion_node_type: system"
fi

echo -e "Calling setup_f5_k8s.sh with: ${VALUES_STRING}${INGRESS_ARG}${UPGRADE_ARGS}"

source ./setup_f5_k8s.sh -c $CLUSTER_NAME -r "${RELEASE}" --provider ${PROVIDER} -n "${NAMESPACE}" --node-pool "${NODE_POOL}" \
  --version ${CHART_VERSION} --prometheus ${PROMETHEUS} ${VALUES_STRING}${INGRESS_ARG}${UPGRADE_ARGS}
setup_result=$?
exit $setup_result

