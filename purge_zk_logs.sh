#!/bin/bash

function print_usage() {
  CMD="$1"
  ERROR_MSG="$2"

  if [ "$ERROR_MSG" != "" ]; then
    echo -e "\nERROR: $ERROR_MSG"
  fi

  echo -e "\nUse this script to purge Zookeeper logs/data"
  echo -e "\nUsage: $CMD [OPTIONS] ... where OPTIONS include:\n"
  echo -e "  -c          Name of the cluster (required)\n"
  echo -e "  -p          GCP Project ID (required)\n"
  echo -e "  -r          Helm release name for installing Fusion 5 (required)\n"
  echo -e "  -n          Kubernetes namespace to install Fusion 5 into (required)\n"
  echo -e "  -z          GCP Zone the cluster is running in, defaults to 'us-west1'\n"
}

SCRIPT_CMD="$0"
GCLOUD_PROJECT=
GCLOUD_ZONE=us-west1
CLUSTER_NAME=
RELEASE=
NAMESPACE=

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

if [ "$RELEASE" == "" ]; then
  print_usage "$SCRIPT_CMD" "Please provide the Helm release name using: -r <release>"
  exit 1
fi

if [ "$NAMESPACE" == "" ]; then
  print_usage "$SCRIPT_CMD" "Please provide the Kubernetes namespace using: -n <namespace>"
  exit 1
fi

gcloud config set compute/zone $GCLOUD_ZONE
gcloud config set project $GCLOUD_PROJECT
gcloud container clusters get-credentials $CLUSTER_NAME
kubectl config current-context

declare -a zk=("zookeeper-0" "zookeeper-1" "zookeeper-2")
for i in "${zk[@]}"
do
   next=${RELEASE}-$i
   echo "Purging logs/data for: $next"
   kubectl exec "$next" -n "${NAMESPACE}" -- java -cp /opt/zookeeper/zookeeper-3.4.10.jar:/opt/zookeeper/lib/* org.apache.zookeeper.server.PurgeTxnLog /var/lib/zookeeper/log /var/lib/zookeeper/data -n 10
   kubectl exec "$next" -n "${NAMESPACE}" -- df -h
done

