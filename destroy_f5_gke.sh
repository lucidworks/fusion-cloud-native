#!/bin/bash

SCRIPT_CMD="$0"
GCLOUD_PROJECT=
GCLOUD_ZONE=us-west1
CLUSTER_NAME=
NAMESPACE=default
CLUSTER_TYPE=regional

function print_usage() {
  CMD="$1"
  ERROR_MSG="$2"

  if [ "$ERROR_MSG" != "" ]; then
    echo -e "\nERROR: $ERROR_MSG"
  fi

  echo -e "\nUse this script to destroy Fusion 5 along with GKE"
  echo -e "\nUsage: $CMD [OPTIONS] ... where OPTIONS include:\n"
  echo -e "  -c            Name of the GKE cluster (required)\n"
  echo -e "  -p            GCP Project ID (required)\n"
  echo -e "  -n            Kubernetes namespace to install Fusion 5 into, defaults to 'default'\n"
  echo -e "  -z            GCP Zone to launch the cluster in, defaults to 'us-west1'\n"
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
        -p)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the -p parameter!"
              exit 1
            fi
            GCLOUD_PROJECT="$2"
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
        -t)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the -t parameter!"
              exit 1
            fi
            CLUSTER_TYPE="$2"
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

# Uninstall and purge all Fusion objects from the specified namespace and cluster."
./setup_f5_gke.sh -c $CLUSTER_NAME -p $GCLOUD_PROJECT -n $NAMESPACE -z $GCLOUD_ZONE --purge

# Destroy underlying GKE cluster for Fusion 5
gcloud beta container clusters list --filter="${CLUSTER_NAME}" | grep "${CLUSTER_NAME}" > /dev/null 2>&1
cluster_status=$?
if [ "$cluster_status" == "0" ]; then
  if [ "$CLUSTER_TYPE" = "regional" ]; then
    gcloud container clusters delete $CLUSTER_NAME --region $GCLOUD_ZONE --project $GCLOUD_PROJECT
  else
    gcloud container clusters delete $CLUSTER_NAME --zone $GCLOUD_ZONE --project $GCLOUD_PROJECT
  fi
else
  echo -e "\nCluster '${CLUSTER_NAME}' doesn't exists."
fi

setup_result=$?
exit $setup_result