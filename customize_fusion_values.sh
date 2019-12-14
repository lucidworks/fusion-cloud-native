#!/bin/bash

NODE_POOL="cloud.google.com/gke-nodepool: default-pool"
SOLR_REPLICAS=3
ML_MODEL_STORE=fusion
GCS_BUCKET=
RELEASE=f5
PROMETHEUS_ON=true
SOLR_DISK_GB=50

function print_usage() {
  CMD="$1"
  ERROR_MSG="$2"

  if [ "$ERROR_MSG" != "" ]; then
    echo -e "\nERROR: $ERROR_MSG"
  fi

  echo -e "\nUse this script to create a custom Fusion values yaml from a template"
  echo -e "\nUsage: $CMD <yaml-file-to-create> [OPTIONS] ... where OPTIONS include:\n"
  echo -e "  --release        Helm release name for installing Fusion 5, defaults to 'f5'\n"
  echo -e "  --prometheus     Enable Prometheus? true or false, defaults to true\n"
  echo -e "  --num-solr       Number of Solr pods to deploy, defaults to 3\n"
  echo -e "  --solr-disk-gb   Size (in gigabytes) of the Solr persistent volume claim, defaults to 50\n"
  echo -e "  --node-pool      Node pool label to assign pods to specific nodes, this option is only useful for existing clusters where you defined a custom node pool;\n                    defaults to '${NODE_POOL}', wrap the arg in double-quotes\n"
  echo -e "  --ml-gcs-bucket  GCS Bucket for storing ML models; if not provided, then the ML service uses the Fusion blob store\n"
}

SCRIPT_CMD="$0"

MY_VALUES="$1"
if [ "$MY_VALUES" == "" ]; then
  print_usage "$SCRIPT_CMD" "Please provide the name of the values yaml file to create as the first arg to this script!"
  exit 1
fi

if [ $# -gt 1 ]; then
  while true; do
    case "$1" in
        --ml-gcs-bucket)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the --ml-gcs-bucket parameter!"
              exit 1
            fi
            GCS_BUCKET="$2"
            shift 2
        ;;
        --release)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the --release parameter!"
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
            PROMETHEUS_ON="$2"
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
        --solr-disk-gb)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the --solr-disk-gb parameter!"
              exit 1
            fi
            SOLR_DISK_GB=$2
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

cp customize_fusion_values.yaml.example $MY_VALUES
sed -i ''  -e "s|{NODE_POOL}|${NODE_POOL}|g" "$MY_VALUES"
sed -i ''  -e "s|{SOLR_REPLICAS}|${SOLR_REPLICAS}|g" "$MY_VALUES"
sed -i ''  -e "s|{ML_MODEL_STORE}|${ML_MODEL_STORE}|g" "$MY_VALUES"
sed -i ''  -e "s|{GCS_BUCKET}|${GCS_BUCKET}|g" "$MY_VALUES"
sed -i ''  -e "s|{RELEASE}|${RELEASE}|g" "$MY_VALUES"
sed -i ''  -e "s|{PROMETHEUS}|${PROMETHEUS_ON}|g" "$MY_VALUES"
sed -i ''  -e "s|{SOLR_DISK_GB}|${SOLR_DISK_GB}|g" "$MY_VALUES"

echo -e "\nCreated ${MY_VALUES} from customize_fusion_values.yaml.example\n"

